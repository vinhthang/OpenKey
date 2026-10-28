//
//  AutoWordingEngine.swift
//  OpenKeySwiftCore
//
//  Created for OpenKey macOS Swift.
//  High-Performance, Sub-Millisecond Auto Wording, Shorthand & Predictive Candidate Engine.
//

import Foundation

public final class AutoWordingEngine: @unchecked Sendable {
    public static let shared = AutoWordingEngine()
    
    private let lock = NSLock()
    
    // Thread-safe configuration toggles with synchronized getters/setters
    public var isEnabled: Bool {
        get { lock.withLock { _isEnabled } }
        set {
            lock.withLock { _isEnabled = newValue }
            if !newValue { clearCandidates() }
        }
    }
    private var _isEnabled: Bool = false
    
    public var grammarRepairEnabled: Bool {
        get { lock.withLock { _grammarRepairEnabled } }
        set { lock.withLock { _grammarRepairEnabled = newValue } }
    }
    private var _grammarRepairEnabled: Bool = false
    
    public var shorthandExpansionEnabled: Bool {
        get { lock.withLock { _shorthandExpansionEnabled } }
        set { lock.withLock { _shorthandExpansionEnabled = newValue } }
    }
    private var _shorthandExpansionEnabled: Bool = false
    
    public var candidateSuggestionsEnabled: Bool {
        get { lock.withLock { _candidateSuggestionsEnabled } }
        set {
            lock.withLock { _candidateSuggestionsEnabled = newValue }
            if !newValue { clearCandidates() }
        }
    }
    private var _candidateSuggestionsEnabled: Bool = false
    
    public func syncConfig(
        isEnabled: Bool,
        grammarRepair: Bool,
        shorthandExpansion: Bool,
        candidateSuggestions: Bool
    ) {
        lock.withLock {
            self._isEnabled = isEnabled
            self._grammarRepairEnabled = grammarRepair
            self._shorthandExpansionEnabled = shorthandExpansion
            self._candidateSuggestionsEnabled = candidateSuggestions
        }
        if !isEnabled || !candidateSuggestions { clearCandidates() }
    }
    
    public func handleSessionReset() { clearCandidates() }
    
    // Active candidate state with synchronized lock
    public var activeCandidates: [WordCandidate] { lock.withLock { _activeCandidates } }
    private var _activeCandidates: [WordCandidate] = []
    
    // MainActor observer for floating candidate bar UI
    public var onCandidatesChanged: (@MainActor @Sendable ([WordCandidate]) -> Void)?
    
    // Custom Shorthands (REQ-006, ADR-005)
    public var customShorthands: [String: String] {
        get { lock.withLock { _customShorthands } }
        set { lock.withLock { _customShorthands = newValue } }
    }
    private var _customShorthands: [String: String] = [:]
    
    // Learned User Frequencies (REQ-005, ADR-005)
    public var userFrequencies: [String: Int] { lock.withLock { _userFrequencies } }
    private var _userFrequencies: [String: Int] = [:]
    
    // Curated shorthand dictionary mapping (REQ-003, REQ-006, REQ-009)
    private var shorthandTable: [String: String] { AutoWordingShorthandCatalog.builtInTable }
    private var properNounShorthands: Set<String> { AutoWordingShorthandCatalog.properNouns }
    
    private init() {
        let freqs = UserDefaults.standard.dictionary(forKey: "UserWordFrequencyData") as? [String: Int] ?? [:]
        self._userFrequencies = freqs
    }
    
    // MARK: - Learned Frequencies Management (REQ-005)
    
    public func recordCandidateAcceptance(text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty else { return }
        let snapshot = lock.withLock { () -> [String: Int] in
            _userFrequencies[clean] = (_userFrequencies[clean] ?? 0) + 1
            return _userFrequencies
        }
        UserDefaults.standard.set(snapshot, forKey: "UserWordFrequencyData")
    }
    
    public func resetLearnedFrequencies() {
        lock.withLock { _userFrequencies.removeAll() }
        UserDefaults.standard.removeObject(forKey: "UserWordFrequencyData")
    }
    
    // MARK: - Shorthand Expansion (REQ-003, REQ-006)
    
    /// Evaluates a standalone token and returns the expanded Vietnamese word/phrase with case preservation.
    public func expandShorthand(rawWord: String) -> String? {
        guard isEnabled && shorthandExpansionEnabled else { return nil }
        guard !rawWord.isEmpty else { return nil }
        
        let lower = rawWord.lowercased()
        
        let baseExpansion: String
        lock.lock()
        if let custom = _customShorthands[lower] {
            baseExpansion = custom
            lock.unlock()
        } else if let builtin = shorthandTable[lower] {
            baseExpansion = builtin
            lock.unlock()
        } else {
            lock.unlock()
            return nil
        }
        
        // Proper nouns
        if properNounShorthands.contains(lower) {
            return baseExpansion
        }
        
        // Check ALL-CAPS
        let isAllCaps = rawWord.count > 1 && rawWord.allSatisfy { $0.isUppercase }
        if isAllCaps {
            return baseExpansion.uppercased()
        }
        
        // Check Title-Case (first character uppercase)
        if let first = rawWord.first, first.isUppercase {
            return baseExpansion.prefix(1).uppercased() + baseExpansion.dropFirst()
        }
        
        // Lowercase
        return baseExpansion
    }
    
    // MARK: - Current Syllable Correction & Stem Candidates (REQ-004, REQ-008)
    
    /// Computes up to 3 valid Vietnamese candidates for transposed keystrokes or unaccented stems in < 0.1ms.
    public func computeCurrentWordCandidates(
        rawStem: String,
        currentSyllable: String,
        isWrongSpelling: Bool = false
    ) -> [WordCandidate] {
        guard isEnabled && candidateSuggestionsEnabled else { return [] }
        guard !rawStem.isEmpty || !currentSyllable.isEmpty else { return [] }
        
        let dict = VietnameseDictionary.shared
        var results: [String] = []
        
        // 1. Check unaccented stem lookup FIRST (REQ-008)
        let stemSource = currentSyllable.isEmpty ? rawStem : currentSyllable
        let cleanStem = VietnameseDictionary.stripVietnameseDiacritics(stemSource).lowercased()
        let stemMatches = dict.stemToWords[cleanStem] ?? []
        for m in stemMatches where !results.contains(m) {
            results.append(m)
            if results.count >= 8 { break }
        }
        
        // 2. Check sorted signature (O(1) transposition lookup) SECOND (REQ-008)
        let cleanRaw = rawStem.lowercased()
        let rawSig = String(cleanRaw.sorted())
        if results.count < 8, let matches = dict.telexSignatureToWords[rawSig] {
            for m in matches where !results.contains(m) {
                results.append(m)
                if results.count >= 8 { break }
            }
        }
        
        // Also strip trailing tone key if transposed (e.g. "taonf" -> "taon" -> "toan")
        if results.count < 8 && cleanRaw.count > 2 {
            let tones: Set<Character> = ["s", "f", "r", "x", "j", "w", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
            if let last = cleanRaw.last, tones.contains(last) {
                let trimmed = String(cleanRaw.dropLast())
                let trimmedSig = String(trimmed.sorted())
                if let matches = dict.telexSignatureToWords[trimmedSig] {
                    for m in matches where !results.contains(m) {
                        results.append(m)
                        if results.count >= 8 { break }
                    }
                }
            }
        }
        
        guard !results.isEmpty else { return [] }
        
        // Boost ranking with learned user frequencies (REQ-005)
        let freqs = lock.withLock { _userFrequencies }
        let sortedByFreq = freqs.isEmpty ? results : results.sorted { (freqs[$0.lowercased()] ?? 0) > (freqs[$1.lowercased()] ?? 0) }
        
        // Place candidates strictly equal to currentSyllable.lowercased() after distinct accented candidates (REQ-008)
        let currentLower = currentSyllable.lowercased()
        var distinctAccented: [String] = []
        var exactMatches: [String] = []
        for word in sortedByFreq {
            if !currentLower.isEmpty && word.lowercased() == currentLower {
                exactMatches.append(word)
            } else {
                distinctAccented.append(word)
            }
        }
        let sortedResults = distinctAccented + exactMatches
        
        let replaceLen = currentSyllable.isEmpty ? rawStem.count : currentSyllable.count
        return sortedResults.prefix(3).enumerated().map { index, text in
            let kind: CandidateKind = isWrongSpelling ? .correction : (stemMatches.contains(text) ? .stemCompletion : .correction)
            return WordCandidate(id: index, text: text, kind: kind, replaceLength: replaceLen)
        }
    }
    
    // MARK: - Compound Next-Word Candidates (REQ-004, REQ-005)
    
    /// Returns up to 3 predictive continuation syllables after Space based on Vietnamese compound bigrams.
    public func computeNextWordCandidates(previousWord: String) -> [WordCandidate] {
        guard isEnabled && candidateSuggestionsEnabled else { return [] }
        let cleanPrev = previousWord.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanPrev.isEmpty else { return [] }
        
        let dict = VietnameseDictionary.shared
        guard let continuations = dict.compoundBigrams[cleanPrev], !continuations.isEmpty else { return [] }
        let pool = Array(continuations.prefix(8))
        let freqs = lock.withLock { _userFrequencies }
        let sortedPool = freqs.isEmpty ? pool : pool.sorted { (freqs[$0.lowercased()] ?? 0) > (freqs[$1.lowercased()] ?? 0) }
        
        return sortedPool.prefix(3).enumerated().map { index, continuation in
            WordCandidate(id: index, text: continuation, kind: .nextWord, replaceLength: 0)
        }
    }
    
    // MARK: - State Management & MainActor Dispatch
    
    public func updateCandidates(_ candidates: [WordCandidate]) {
        lock.lock()
        if _activeCandidates == candidates {
            lock.unlock()
            return
        }
        self._activeCandidates = candidates
        let copy = candidates
        lock.unlock()
        
        if let callback = onCandidatesChanged {
            DispatchQueue.main.async {
                callback(copy)
            }
        }
    }
    
    public func clearCandidates() {
        updateCandidates([])
    }
    
    // MARK: - Phonotactic Syllable Repair (REQ-002, ADR-002, REQ-008, ADR-007)
    
    public func repairPhonotacticCluster(
        typingWord: inout [UInt32],
        index: UInt8,
        vowelStartIndex: UInt8,
        vowelEndIndex: UInt8,
        vowelCount: UInt8,
        isInsertingMark: Bool
    ) -> Bool {
        guard isEnabled && grammarRepairEnabled else { return false }
        var repaired = false
        let vsi = Int(vowelStartIndex)
        let vei = Int(vowelEndIndex)
        
        func charAt(_ idx: Int) -> UInt16 {
            UInt16(typingWord[idx] & 0xFFFF)
        }
        
        // Final consonant present after vowel span
        let hasFinalConsonant = (Int(index) - 1 > vei) && isConsonant(charAt(vei + 1))
        guard hasFinalConsonant else { return false }
        
        // Rule 1: ie/ye + final consonant -> iê/yê
        let prev = charAt(vei - 1)
        let curr = charAt(vei)
        if (prev == KEY_I || prev == KEY_Y) && curr == KEY_E {
            let prevIdx = vei - 1
            let currIdx = vei
            let hasToneOrInserting = isInsertingMark ||
                (typingWord[prevIdx] & MARK_MASK) != 0 ||
                (typingWord[currIdx] & MARK_MASK) != 0
            if hasToneOrInserting && (typingWord[vei] & TONE_MASK) == 0 {
                typingWord[vei] |= (TONE_MASK | AUTO_TONE_MASK)
                repaired = true
            }
        }
        
        // Rule 2: uow -> ươ (only c1 == KEY_U && c2 == KEY_O, skip if preceded by Q)
        if vei >= vsi + 1 {
            for i in vsi..<vei {
                let c1 = charAt(i)
                let c2 = charAt(i + 1)
                if c1 == KEY_U && c2 == KEY_O {
                    if i > 0 && charAt(i - 1) == KEY_Q { continue }
                    let m1 = typingWord[i] & TONEW_MASK
                    let m2 = typingWord[i + 1] & TONEW_MASK
                    if (m1 != 0 || m2 != 0) && (m1 == 0 || m2 == 0) {
                        if m1 == 0 { typingWord[i] |= (TONEW_MASK | AUTO_TONE_MASK) }
                        if m2 == 0 { typingWord[i + 1] |= (TONEW_MASK | AUTO_TONE_MASK) }
                        repaired = true
                    }
                }
            }
        }
        
        return repaired
    }
    
    // MARK: - Key Event Interception & Post-Processing (REQ-008, ADR-007)
    
    public func interceptBeforeKeyEvent(
        keyCode: UInt16,
        preContext: OKWordContext
    ) -> OKHookSnapshot? {
        guard isEnabled && shorthandExpansionEnabled else { return nil }
        guard keyCode == KEY_SPACE else { return nil }
        guard preContext.spaceCount == 0 && preContext.charCount > 0 && !preContext.composedWord.isEmpty else {
            return nil
        }
        
        guard let expanded = expandShorthand(rawWord: preContext.composedWord) else {
            return nil
        }
        
        let fullText = expanded + " "
        let utf16 = Array(fullText.utf16)
        let bs = UInt8(min(preContext.charCount, 32))
        
        if candidateSuggestionsEnabled {
            let nextCands = computeNextWordCandidates(previousWord: expanded)
            updateCandidates(nextCands)
        }
        
        return OKHookSnapshot(
            code: HookCodeState.willProcess,
            backspaceCount: bs,
            newCharCount: UInt8(utf16.count),
            extCode: 4,
            shouldSendControlKey: false,
            utf16Chars: utf16
        )
    }
    
    public func didProcessKeyEvent(
        keyCode: UInt16,
        snapshot: OKHookSnapshot,
        preContext: OKWordContext,
        postContext: OKWordContext
    ) {
        guard isEnabled && candidateSuggestionsEnabled else {
            clearCandidates()
            return
        }
        
        // If restored or spell-check canceled out the syllable
        if snapshot.code == HookCodeState.restore || snapshot.code == HookCodeState.restoreAndStartNewSession {
            clearCandidates()
            return
        }
        
        if keyCode == KEY_SPACE {
            // Space pressed without shorthand interception
            if !preContext.composedWord.isEmpty {
                let nextCands = computeNextWordCandidates(previousWord: preContext.composedWord)
                updateCandidates(nextCands)
            } else {
                clearCandidates()
            }
            return
        }
        
        func updateLiveCandidates() {
            if postContext.spaceCount == 0 && postContext.charCount > 0 &&
                (postContext.rawKeystrokes.count >= 2 || postContext.composedWord.count >= 2) {
                let candidates = computeCurrentWordCandidates(
                    rawStem: postContext.rawKeystrokes,
                    currentSyllable: postContext.composedWord,
                    isWrongSpelling: postContext.isWrongSpelling
                )
                if !candidates.isEmpty { updateCandidates(candidates) } else { clearCandidates() }
            } else {
                clearCandidates()
            }
        }
        
        if keyCode == KEY_DELETE {
            updateLiveCandidates()
            return
        }
        
        // Break keys or empty state reset candidates
        if postContext.isBreakKey || postContext.charCount == 0 {
            clearCandidates()
            return
        }
        
        // Live syllable candidates during active typing (handles both willProcess and doNothing)
        updateLiveCandidates()
    }
}
