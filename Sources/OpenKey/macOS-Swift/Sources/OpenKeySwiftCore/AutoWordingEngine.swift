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

public final class AutoWordingEngine: @unchecked Sendable {
    public static let shared = AutoWordingEngine()
    
    private let lock = NSLock()
    
    // Configuration toggles
    public var isEnabled: Bool = false
    public var grammarRepairEnabled: Bool = false
    public var shorthandExpansionEnabled: Bool = false
    public var candidateSuggestionsEnabled: Bool = false
    
    // Active candidate state
    public private(set) var activeCandidates: [WordCandidate] = []
    
    // MainActor observer for floating candidate bar UI
    public var onCandidatesChanged: (@MainActor @Sendable ([WordCandidate]) -> Void)?
    
    // Custom Shorthands (REQ-006, ADR-005)
    public var customShorthands: [String: String] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _customShorthands
        }
        set {
            lock.lock()
            _customShorthands = newValue
            lock.unlock()
        }
    }
    private var _customShorthands: [String: String] = [:]
    
    // Learned User Frequencies (REQ-005, ADR-005)
    public private(set) var userFrequencies: [String: Int] = [:]
    private var _userFrequencies: [String: Int] = [:]
    
    // Curated shorthand dictionary mapping
    private let shorthandTable: [String: String] = [
        "ko": "không",
        "k": "không",
        "dc": "được",
        "đc": "được",
        "trc": "trước",
        "ng": "người",
        "nhg": "nhưng",
        "vs": "với",
        "ntn": "như thế nào",
        "bt": "bình thường",
        "cx": "cũng",
        "mk": "mình",
        "j": "gì",
        "bh": "bây giờ",
        "mn": "mọi người",
        "cty": "công ty",
        "nv": "nhân viên",
        "gd": "gia đình",
        "sdt": "số điện thoại",
        "tks": "cảm ơn",
        "vn": "Việt Nam",
        "hn": "Hà Nội",
        "tphcm": "TP. Hồ Chí Minh",
        "hcm": "TP. Hồ Chí Minh"
    ]
    
    // Proper nouns that always retain Title Case even if typed lowercase
    private let properNounShorthands: Set<String> = [
        "vn", "hn", "tphcm", "hcm"
    ]
    
    private init() {
        let freqs = UserDefaults.standard.dictionary(forKey: "UserWordFrequencyData") as? [String: Int] ?? [:]
        self._userFrequencies = freqs
        self.userFrequencies = freqs
    }
    
    // MARK: - Learned Frequencies Management (REQ-005)
    
    public func recordCandidateAcceptance(text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty else { return }
        
        lock.lock()
        let count = (_userFrequencies[clean] ?? 0) + 1
        _userFrequencies[clean] = count
        let snapshot = _userFrequencies
        self.userFrequencies = snapshot
        lock.unlock()
        
        UserDefaults.standard.set(snapshot, forKey: "UserWordFrequencyData")
    }
    
    public func resetLearnedFrequencies() {
        lock.lock()
        _userFrequencies.removeAll()
        self.userFrequencies = [:]
        lock.unlock()
        
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
    
    // MARK: - Current Syllable Correction & Stem Candidates (REQ-004)
    
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
        
        // 1. Check sorted signature (O(1) transposition lookup)
        let cleanRaw = rawStem.lowercased()
        let rawSig = String(cleanRaw.sorted())
        if let matches = dict.telexSignatureToWords[rawSig] {
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
        
        // 2. Check unaccented stem lookup
        if results.count < 8 {
            let stemSource = currentSyllable.isEmpty ? rawStem : currentSyllable
            let cleanStem = VietnameseDictionary.stripVietnameseDiacritics(stemSource)
            if let matches = dict.stemToWords[cleanStem] {
                for m in matches where !results.contains(m) {
                    results.append(m)
                    if results.count >= 8 { break }
                }
            }
        }
        
        guard !results.isEmpty else { return [] }
        
        // Boost ranking with learned user frequencies (REQ-005)
        lock.lock()
        let freqs = _userFrequencies
        lock.unlock()
        
        let sortedResults: [String]
        if !freqs.isEmpty {
            sortedResults = results.sorted { a, b in
                let fa = freqs[a.lowercased()] ?? 0
                let fb = freqs[b.lowercased()] ?? 0
                if fa != fb {
                    return fa > fb
                }
                return false
            }
        } else {
            sortedResults = results
        }
        
        let replaceLen = currentSyllable.isEmpty ? rawStem.count : currentSyllable.count
        return sortedResults.prefix(3).enumerated().map { index, text in
            WordCandidate(id: index, text: text, kind: .correction, replaceLength: replaceLen)
        }
    }
    
    // MARK: - Compound Next-Word Candidates (REQ-004, REQ-005)
    
    /// Returns up to 3 predictive continuation syllables after Space based on Vietnamese compound bigrams.
    public func computeNextWordCandidates(previousWord: String) -> [WordCandidate] {
        guard isEnabled && candidateSuggestionsEnabled else { return [] }
        let cleanPrev = previousWord.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanPrev.isEmpty else { return [] }
        
        let dict = VietnameseDictionary.shared
        guard let continuations = dict.compoundBigrams[cleanPrev], !continuations.isEmpty else {
            return []
        }
        
        let pool = Array(continuations.prefix(8))
        
        lock.lock()
        let freqs = _userFrequencies
        lock.unlock()
        
        let sortedPool: [String]
        if !freqs.isEmpty {
            sortedPool = pool.sorted { a, b in
                let fa = freqs[a.lowercased()] ?? 0
                let fb = freqs[b.lowercased()] ?? 0
                if fa != fb {
                    return fa > fb
                }
                return false
            }
        } else {
            sortedPool = pool
        }
        
        return sortedPool.prefix(3).enumerated().map { index, continuation in
            WordCandidate(id: index, text: continuation, kind: .nextWord, replaceLength: 0)
        }
    }
    
    // MARK: - State Management & MainActor Dispatch
    
    public func updateCandidates(_ candidates: [WordCandidate]) {
        lock.lock()
        self.activeCandidates = candidates
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
}
