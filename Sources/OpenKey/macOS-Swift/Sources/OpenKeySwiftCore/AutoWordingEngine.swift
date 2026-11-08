//
//  AutoWordingEngine.swift
//  OpenKeySwiftCore
//
//  Created for OpenKey macOS Swift.
//  High-Performance, Sub-Millisecond Auto Wording, Shorthand & Predictive Candidate Engine.
//

import Foundation

public enum CandidateKind: String, Sendable, Equatable {
    case correction
    case stemCompletion
    case nextWord
}

public struct WordCandidate: Sendable, Equatable, Identifiable {
    public let id: Int
    public let text: String
    public let kind: CandidateKind
    public let replaceLength: Int
    
    public init(id: Int, text: String, kind: CandidateKind, replaceLength: Int) {
        self.id = id
        self.text = text
        self.kind = kind
        self.replaceLength = replaceLength
    }
}

public enum AutoWordingShorthandCatalog {
    public static let builtInTable: [String: String] = [:]
    
    public static let properNouns: Set<String> = []
}

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
    
    public var doubleSpacePeriodEnabled: Bool {
        get { lock.withLock { _doubleSpacePeriodEnabled } }
        set { lock.withLock { _doubleSpacePeriodEnabled = newValue } }
    }
    private var _doubleSpacePeriodEnabled: Bool = false
    
    public func syncConfig(
        isEnabled: Bool,
        grammarRepair: Bool,
        shorthandExpansion: Bool,
        candidateSuggestions: Bool,
        doubleSpacePeriod: Bool = false
    ) {
        lock.withLock {
            self._isEnabled = isEnabled
            self._grammarRepairEnabled = grammarRepair
            self._shorthandExpansionEnabled = shorthandExpansion
            self._candidateSuggestionsEnabled = candidateSuggestions
            self._doubleSpacePeriodEnabled = doubleSpacePeriod
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
        OpenKeyLogger.shared.log(.autoWording, "Accepted candidate: '\(clean)', count=\(snapshot[clean] ?? 0)")
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
        
        var resolved: String? = nil
        lock.lock()
        if let custom = _customShorthands[lower] {
            resolved = custom
        }
        lock.unlock()
        guard let baseExpansion = resolved else { return nil }
        
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
    
    // MARK: - Current Syllable Correction & Stem Candidates (REQ-004, REQ-008, REQ-024)
    
    private static let tonedCharacters: Set<Character> = Set(
        "áàảãạắằẳẵặấầẩẫậéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵ" +
        "ÁÀẢÃẠẮẰẲẴẶẤẦẨẪẬÉÈẺẼẸẾỀỂỄỆÍÌỈĨỊÓÒỎÕỌỐỒỔỖỘỚỜỞỠỢÚÙỦŨỤỨỪỬỮỰÝỲỶỸỴ"
    )
    
    public static func hasToneMark(_ text: String) -> Bool {
        text.contains { tonedCharacters.contains($0) }
    }
    
    public func hasToneMark(_ text: String) -> Bool {
        Self.hasToneMark(text)
    }
    
    public static func computeCandidates(
        currentSyllable: String,
        rawStem: String,
        previousWord: String? = nil,
        languagePriority: LanguagePriority = .vietnameseFirst
    ) -> [WordCandidate] {
        shared.computeCurrentWordCandidates(
            rawStem: rawStem,
            currentSyllable: currentSyllable,
            previousWord: previousWord,
            isWrongSpelling: false,
            languagePriority: languagePriority,
            bypassEnabledCheck: true
        )
    }
    
    /// Computes up to 3 valid Vietnamese candidates for transposed keystrokes or unaccented stems in < 0.1ms.
    public func computeCurrentWordCandidates(
        rawStem: String,
        currentSyllable: String,
        previousWord: String? = nil,
        isWrongSpelling: Bool = false,
        languagePriority: LanguagePriority = .vietnameseFirst,
        bypassEnabledCheck: Bool = false
    ) -> [WordCandidate] {
        guard bypassEnabledCheck || (isEnabled && candidateSuggestionsEnabled) else { return [] }
        guard !rawStem.isEmpty || !currentSyllable.isEmpty else { return [] }
        
        let dict = VietnameseDictionary.shared
        if isWrongSpelling && dict.keepWords.contains(rawStem.lowercased()) {
            return []
        }
        var results: [String] = []
        
        let currentLower = currentSyllable.lowercased()
        let cleanRaw = rawStem.lowercased()
        
        // Spatial auto-correct candidates (REQ-026, ADR-027)
        var spatialMatches: [String] = []
        let composedToCheck = currentLower.isEmpty ? cleanRaw : currentLower
        if !dict.isValidVietnameseSyllable(composedToCheck) && !dict.isValidVietnameseSyllable(cleanRaw) && cleanRaw.count >= 3 {
            spatialMatches = dict.findVietnameseSpatialCandidates(cleanRaw, composedLower: currentLower, previousWord: previousWord, limit: 3)
        }
        
        // 1. Check unaccented stem lookup FIRST (REQ-008, REQ-010)
        let stemSource = currentSyllable.isEmpty ? rawStem : currentSyllable
        let cleanStem = VietnameseDictionary.stripVietnameseDiacritics(stemSource).lowercased()
        let stemMatches = dict.stemToWords[cleanStem] ?? []
        for m in stemMatches where !results.contains(m) {
            results.append(m)
        }
        
        // 2. Check sorted signature (O(1) transposition lookup) SECOND (REQ-008, REQ-030)
        let stemOnset = VietnameseDictionary.extractVietnameseOnset(cleanStem)
        let rawSig = String(cleanRaw.sorted())
        if results.count < 8, let matches = dict.telexSignatureToWords[rawSig] {
            for m in matches where !results.contains(m) && VietnameseDictionary.extractVietnameseOnset(VietnameseDictionary.stripVietnameseDiacritics(m)) == stemOnset {
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
                    for m in matches where !results.contains(m) && VietnameseDictionary.extractVietnameseOnset(VietnameseDictionary.stripVietnameseDiacritics(m)) == stemOnset {
                        results.append(m)
                        if results.count >= 8 { break }
                    }
                }
            }
        }
        
        // Boost ranking with learned user frequencies (REQ-005)
        let freqs = lock.withLock { _userFrequencies }
        let sortedByFreq = freqs.isEmpty ? results : results.sorted { (freqs[$0.lowercased()] ?? 0) > (freqs[$1.lowercased()] ?? 0) }
        
        // Prioritize candidates preserving vowel modifiers present in currentSyllable (REQ-010, ADR-009)
        let requiredModifiers = Self.extractVowelModifiers(from: currentSyllable)
        let modifierRanked: [String]
        if requiredModifiers.isEmpty {
            modifierRanked = sortedByFreq
        } else {
            let matching = sortedByFreq.filter { requiredModifiers.isSubset(of: Self.extractVowelModifiers(from: $0)) }
            let nonMatching = sortedByFreq.filter { !requiredModifiers.isSubset(of: Self.extractVowelModifiers(from: $0)) }
            modifierRanked = matching + nonMatching
        }
        
        // Place candidates strictly equal to currentSyllable.lowercased() after distinct accented candidates (REQ-008)
        var distinctAccented: [String] = []
        var exactMatches: [String] = []
        for word in modifierRanked {
            if !currentLower.isEmpty && word.lowercased() == currentLower {
                exactMatches.append(word)
            } else {
                distinctAccented.append(word)
            }
        }
        let vietnameseSorted: [String]
        if !spatialMatches.isEmpty {
            var frontList: [String] = []
            for sm in spatialMatches {
                if !frontList.contains(sm) { frontList.append(sm) }
            }
            for w in (distinctAccented + exactMatches) {
                if !frontList.contains(w) { frontList.append(w) }
            }
            vietnameseSorted = frontList
        } else if currentSyllable.count < rawStem.count && !distinctAccented.isEmpty && !hasToneMark(currentSyllable) {
            vietnameseSorted = distinctAccented + exactMatches
        } else if !distinctAccented.isEmpty && !hasToneMark(currentSyllable) {
            vietnameseSorted = distinctAccented + exactMatches
        } else {
            vietnameseSorted = exactMatches + distinctAccented
        }
        
        let engCandidates = dict.computeEnglishCandidates(for: rawStem)
        
        var combinedTexts: [String] = []
        if languagePriority == .englishFirst {
            if let firstEng = engCandidates.first {
                combinedTexts.append(firstEng)
            }
            for vn in vietnameseSorted where !combinedTexts.contains(vn) {
                combinedTexts.append(vn)
            }
            for eng in engCandidates.dropFirst() where !combinedTexts.contains(eng) {
                combinedTexts.append(eng)
            }
        } else {
            for vn in vietnameseSorted.prefix(2) where !combinedTexts.contains(vn) {
                combinedTexts.append(vn)
            }
            for eng in engCandidates where !combinedTexts.contains(eng) {
                combinedTexts.append(eng)
            }
            for vn in vietnameseSorted.dropFirst(2) where !combinedTexts.contains(vn) {
                combinedTexts.append(vn)
            }
        }
        
        guard !combinedTexts.isEmpty else { return [] }
        
        let replaceLen = currentSyllable.isEmpty ? rawStem.count : currentSyllable.count
        let isCap = rawStem.first?.isUppercase == true || currentSyllable.first?.isUppercase == true
        let candidates = Array(combinedTexts.prefix(3).enumerated().map { index, text in
            let isEng = engCandidates.contains(text)
            let isSpatial = spatialMatches.contains(text)
            let kind: CandidateKind = (isEng || isSpatial || isWrongSpelling) ? .correction : (stemMatches.contains(text) ? .stemCompletion : .correction)
            let formattedText = isCap ? (text.prefix(1).uppercased() + text.dropFirst()) : text
            return WordCandidate(id: index, text: formattedText, kind: kind, replaceLength: replaceLen)
        })
        if !candidates.isEmpty {
            OpenKeyLogger.shared.log(.autoWording, "Stem '\(rawStem)' candidates: \(candidates.map(\.text))")
        }
        return candidates
    }
    
    // MARK: - Compound Next-Word Candidates (REQ-004, REQ-005)
    
    /// Returns up to 3 predictive continuation syllables after Space based on Vietnamese compound bigrams.
    public func computeNextWordCandidates(previousWord: String) -> [WordCandidate] {
        guard isEnabled && candidateSuggestionsEnabled else { return [] }
        let cleanPrev = previousWord.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanPrev.isEmpty else { return [] }
        
        let dict = VietnameseDictionary.shared
        guard let continuations = dict.compoundBigrams[cleanPrev] ?? dict.englishNextWordBigrams[cleanPrev], !continuations.isEmpty else { return [] }
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
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.activeCandidates == copy else { return }
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
        
        // Final consonant present after vowel span or ieu/yeu cluster
        let hasFinalConsonant = (Int(index) - 1 > vei) && isConsonant(charAt(vei + 1))
        let isIeuYeu = vei >= vsi + 2 && (charAt(vsi) == KEY_I || charAt(vsi) == KEY_Y) && charAt(vsi + 1) == KEY_E && charAt(vsi + 2) == KEY_U
        guard hasFinalConsonant || isIeuYeu else { return false }
        
        if isIeuYeu {
            let hasToneOrInserting = isInsertingMark ||
                (typingWord[vsi] & MARK_MASK) != 0 ||
                (typingWord[vsi + 1] & MARK_MASK) != 0 ||
                (typingWord[vsi + 2] & MARK_MASK) != 0
            if hasToneOrInserting && (typingWord[vsi + 1] & TONE_MASK) == 0 {
                typingWord[vsi + 1] |= (TONE_MASK | AUTO_TONE_MASK)
                repaired = true
            }
        }
        
        // Rule 1: ie/ye + final consonant -> iê/yê
        if hasFinalConsonant {
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
        OpenKeyLogger.shared.log(.autoWording, "Expanded shorthand '\(preContext.composedWord)' -> '\(expanded)'")
        
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
            let capturedPriority = OKEngineGetEffectiveLanguagePriority()
            let capturedPrevWord = VietnameseEngine.lastPreviousWord()
            if postContext.spaceCount == 0 && postContext.charCount > 0 &&
                (postContext.rawKeystrokes.count >= 1 || postContext.composedWord.count >= 1) {
                let candidates = computeCurrentWordCandidates(
                    rawStem: postContext.rawKeystrokes,
                    currentSyllable: postContext.composedWord,
                    previousWord: capturedPrevWord,
                    isWrongSpelling: postContext.isWrongSpelling,
                    languagePriority: capturedPriority
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
    
    static func extractVowelModifiers(from text: String) -> Set<Character> {
        var mods = Set<Character>()
        for ch in text.lowercased() {
            switch ch {
            case "ă", "ắ", "ằ", "ẳ", "ẵ", "ặ": mods.insert("ă")
            case "â", "ấ", "ầ", "ẩ", "ẫ", "ậ": mods.insert("â")
            case "ê", "ế", "ề", "ể", "ễ", "ệ": mods.insert("ê")
            case "ô", "ố", "ồ", "ổ", "ỗ", "ộ": mods.insert("ô")
            case "ơ", "ớ", "ờ", "ở", "ỡ", "ợ": mods.insert("ơ")
            case "ư", "ứ", "ừ", "ử", "ữ", "ự": mods.insert("ư")
            case "đ": mods.insert("đ")
            default: break
            }
        }
        return mods
    }
}
