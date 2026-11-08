//
//  VietnameseDictionary.swift
//  OpenKeySwiftCore
//
//  Created for OpenKey macOS Swift.
//  Multi-Thousand-Word Reference Dictionary for Auto Wording & Predictive Candidate Bar.
//

import Foundation

public enum LanguagePriority: String, Sendable, Equatable {
    case vietnameseFirst = "V"
    case englishFirst = "E"
}

public enum SpatialScoringWeights {
    public static let COMPOUND_BIGRAM_BONUS = 1000, DIRECT_ZERO_EDIT_BONUS = 600, ONSET_REPAIR_BONUS = 500
    public static let EXACT_MATCH_BONUS = 400, FULL_TELEX_BONUS = 300, TONE_MODIFIER_BONUS = 200
    public static let INSERTION_PENALTY = -100, DELETION_PENALTY = -150
    public static let HIGH_FREQUENCY_EVIDENCE_THRESHOLD = 95, DEFAULT_PRIORITY = 50
}

public final class VietnameseDictionary: @unchecked Sendable {
    public static let shared = VietnameseDictionary()

    private static let DIACRITIC_STRIP_MAP: [Character: Character] = [
        "á": "a", "à": "a", "ả": "a", "ã": "a", "ạ": "a", "ă": "a", "ắ": "a", "ằ": "a", "ẳ": "a", "ẵ": "a", "ặ": "a", "â": "a", "ấ": "a", "ầ": "a", "ẩ": "a", "ẫ": "a", "ậ": "a", "é": "e", "è": "e", "ẻ": "e", "ẽ": "e", "ẹ": "e", "ê": "e", "ế": "e", "ề": "e", "ể": "e", "ễ": "e", "ệ": "e", "í": "i", "ì": "i", "ỉ": "i", "ĩ": "i", "ị": "i",
        "ó": "o", "ò": "o", "ỏ": "o", "õ": "o", "ọ": "o", "ô": "o", "ố": "o", "ồ": "o", "ổ": "o", "ỗ": "o", "ộ": "o", "ơ": "o", "ớ": "o", "ờ": "o", "ở": "o", "ỡ": "o", "ợ": "o", "ú": "u", "ù": "u", "ủ": "u", "ũ": "u", "ụ": "u", "ư": "u", "ứ": "u", "ừ": "u", "ử": "u", "ữ": "u", "ự": "u", "ý": "y", "ỳ": "y", "ỷ": "y", "ỹ": "y", "ỵ": "y"
    ]

    private static let TELEX_BASE_MOD_MAP: [Character: (String, String)] = [
        "a": ("a", ""), "á": ("a", "s"), "à": ("a", "f"), "ả": ("a", "r"), "ã": ("a", "x"), "ạ": ("a", "j"), "ă": ("aw", ""), "ắ": ("aw", "s"), "ằ": ("aw", "f"), "ẳ": ("aw", "r"), "ẵ": ("aw", "x"), "ặ": ("aw", "j"), "â": ("aa", ""), "ấ": ("aa", "s"), "ầ": ("aa", "f"), "ẩ": ("aa", "r"), "ẫ": ("aa", "x"), "ậ": ("aa", "j"),
        "e": ("e", ""), "é": ("e", "s"), "è": ("e", "f"), "ẻ": ("e", "r"), "ẽ": ("e", "x"), "ẹ": ("e", "j"), "ê": ("ee", ""), "ế": ("ee", "s"), "ề": ("ee", "f"), "ể": ("ee", "r"), "ễ": ("ee", "x"), "ệ": ("ee", "j"), "i": ("i", ""), "í": ("i", "s"), "ì": ("i", "f"), "ỉ": ("i", "r"), "ĩ": ("i", "x"), "ị": ("i", "j"),
        "o": ("o", ""), "ó": ("o", "s"), "ò": ("o", "f"), "ỏ": ("o", "r"), "õ": ("o", "x"), "ọ": ("o", "j"), "ô": ("oo", ""), "ố": ("oo", "s"), "ồ": ("oo", "f"), "ổ": ("oo", "r"), "ỗ": ("oo", "x"), "ộ": ("oo", "j"), "ơ": ("ow", ""), "ớ": ("ow", "s"), "ờ": ("ow", "f"), "ở": ("ow", "r"), "ỡ": ("ow", "x"), "ợ": ("ow", "j"),
        "u": ("u", ""), "ú": ("u", "s"), "ù": ("u", "f"), "ủ": ("u", "r"), "ũ": ("u", "x"), "ụ": ("u", "j"), "ư": ("uw", ""), "ứ": ("uw", "s"), "ừ": ("uw", "f"), "ử": ("uw", "r"), "ữ": ("uw", "x"), "ự": ("uw", "j"), "y": ("y", ""), "ý": ("y", "s"), "ỳ": ("y", "f"), "ỷ": ("y", "r"), "ỹ": ("y", "x"), "ỵ": ("y", "j"), "đ": ("dd", "")
    ]

    private static let U_HORN_CHARS: Set<Character> = ["ư", "ứ", "ừ", "ử", "ữ", "ự"]
    private static let O_HORN_CHARS: Set<Character> = ["ơ", "ớ", "ờ", "ở", "ỡ", "ợ"]
    private static let FAKE_D_SHADOWS: Set<String> = ["dất", "dến", "diểm", "dồng", "dứng", "dể", "dữa"]

    private static let HALF_HORN_UO_REGEX = try! NSRegularExpression(pattern: "u[ơớờởỡợ](ng|nh|ch|[cmnptui])")
    private static let UNHORNED_UO_REGEX = try! NSRegularExpression(pattern: "^(?!(?:q|qu|th|h|kh)u[ơớờởỡợ]$).*?u[ơớờởỡợ]")
    private static let GH_NGH_INVALID = try! NSRegularExpression(pattern: "^(gh|ngh)[aăâoôơuưyáắấóốớúứýàằầòồờùừỳảẳẩỏổởủửỷãẵẫõỗỡũữỹạặậọộợụựỵ]")
    private static let G_NG_INVALID = try! NSRegularExpression(pattern: "^(g(?!h|[iíìỉĩị])|ng(?!h))[eêièềìéếíẻểỉẽễĩẹệị]")
    private static let K_INVALID = try! NSRegularExpression(pattern: "^k[aăâoôơuưáắấóốớúứýàằầòồờùừỳảẳẩỏổởủửỷãẵẫõỗỡũữỹạặậọộợụựỵ]|^ky[a-zà-ỹ]")
    private static let C_INVALID = try! NSRegularExpression(pattern: "^c(?!h)[eêiyèềìỳéếíýẻểỉỷẽễĩỹẹệịỵ]|^chy[a-zà-ỹ]")
    private static let YE_INVALID = try! NSRegularExpression(pattern: "^(?:b|ch|d|đ|g|gh|gi|h|k|kh|l|m|n|ng|ngh|nh|p|ph|r|s|t|th|tr|v|x)y[êếềểễệ]")
    private static let INVALID_RHYMES = try! NSRegularExpression(pattern: "(?<![ưứừửữự])[ơớờởỡợ]ng$|[ưứừửữự][nm]$|[iíìỉĩị]c$|[eéèẻẽẹ]c$|^(?:b|ch|c|d|đ|l|m|n|t|v)u[ểễềếệ]n$")
    private static let LABIAL_MEDIALS = try! NSRegularExpression(pattern: "^(?:b|m|p|ph|v)(?:oa|oă|oe|uê|uy|uâ)|^giu[ôốồổỗộâấầẩẫậêếềểễệyýỳỷỹỵ]", options: [])
    private static let NHIA_CHECK = try! NSRegularExpression(pattern: "^nh[iíìỉĩị][aáàảãạ]$|^nhĩa$")

    public static let QWERTY_NEIGHBORS: [Character: String] = [
        "q": "wa", "w": "qase", "e": "wsdr", "r": "edft", "t": "rfgy", "y": "tghu", "u": "yhji", "i": "ujko", "o": "iklp", "p": "ol",
        "a": "qwsz", "s": "weadzx", "d": "erfcxs", "f": "rtgvcd", "g": "tyhbvf", "h": "yujnbg", "j": "uikmnh", "k": "iojlm", "l": "opk",
        "z": "asx", "x": "sdzc", "c": "dfxv", "v": "fgcb", "b": "ghvn", "n": "hjbm", "m": "jkn"
    ]

    public static let qwertyNeighbors: [Character: [Character]] = QWERTY_NEIGHBORS.mapValues { Array($0) }

    public static func isQwertyAdjacent(_ a: Character, _ b: Character) -> Bool {
        QWERTY_NEIGHBORS[a]?.contains(b) == true
    }

    private static func matchesRegex(_ regex: NSRegularExpression, _ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    public static func isPhonotacticallyValidVietnameseSyllable(_ word: String) -> Bool {
        let lower = word.lowercased()
        if lower.isEmpty || FAKE_D_SHADOWS.contains(lower) { return false }
        if matchesRegex(HALF_HORN_UO_REGEX, lower) || matchesRegex(UNHORNED_UO_REGEX, lower) { return false }
        if matchesRegex(GH_NGH_INVALID, lower) || matchesRegex(G_NG_INVALID, lower) { return false }
        if matchesRegex(K_INVALID, lower) || matchesRegex(C_INVALID, lower) { return false }
        if matchesRegex(YE_INVALID, lower) || matchesRegex(INVALID_RHYMES, lower) || matchesRegex(LABIAL_MEDIALS, lower) { return false }
        if matchesRegex(NHIA_CHECK, lower) { return false }
        if let lastCoda = lower.last, lastCoda == "c" || lastCoda == "p" || lastCoda == "t" || lower.hasSuffix("ch") {
            if !lower.contains(where: { "áắấéếíóốớúứýạặậẹệịọộợụựỵ".contains($0) }) { return false }
        }
        return true
    }

    public static let VALID_VIETNAMESE_ONSETS: Set<String> = [
        "", "b", "c", "ch", "d", "dd", "g", "gh", "gi", "h", "k", "kh", "l", "m", "n",
        "ng", "ngh", "nh", "p", "ph", "qu", "r", "s", "t", "th", "tr", "v", "x"
    ]
    public static let ORTHO_ONSET_PAIRS: [String: String] = [
        "ng": "ngh", "g": "gh", "gh": "g", "ngh": "ng", "c": "k", "k": "c"
    ]

    public static func hasValidVietnameseOnset(_ rawLower: String) -> Bool {
        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
        let onset = String(rawLower.prefix(while: { !vowels.contains($0) }))
        let rest = String(rawLower.dropFirst(onset.count))
        if onset == "ng" && (rest.hasPrefix("i") || rest.hasPrefix("e")) { return false }
        if onset == "g" && (rest.hasPrefix("i") || rest.hasPrefix("e")) { return false }
        if (onset == "gh" || onset == "ngh") && (rest.hasPrefix("a") || rest.hasPrefix("o") || rest.hasPrefix("u")) { return false }
        if onset == "c" && (rest.hasPrefix("i") || rest.hasPrefix("e") || rest.hasPrefix("y")) { return false }
        if onset == "k" && (rest.hasPrefix("a") || rest.hasPrefix("o") || rest.hasPrefix("u")) { return false }
        return VALID_VIETNAMESE_ONSETS.contains(onset)
    }

    private static let validOeOnsets: Set<String> = ["", "ch", "h", "kh", "l", "ng", "nh", "t", "x", "gi", "qu"]
    private static func isValidOeSyllable(_ word: String) -> Bool {
        let stem = stripVietnameseDiacritics(word)
        guard stem.contains("oe") else { return true }
        let onset = String(stem.prefix(while: { !"aeiouy".contains($0) }))
        return validOeOnsets.contains(onset)
    }

    public static func stripVietnameseDiacritics(_ text: String) -> String {
        let result = text.lowercased().replacingOccurrences(of: "đ", with: "d")
        var sb = ""
        sb.reserveCapacity(result.count)
        for ch in result { sb.append(DIACRITIC_STRIP_MAP[ch] ?? ch) }
        return sb
    }

    public static func extractVietnameseOnset(_ asciiWord: String) -> String {
        let lower = asciiWord.lowercased()
        for onset in ["ngh", "ng", "nh", "ch", "gh", "gi", "kh", "ph", "qu", "th", "tr"] {
            if lower.hasPrefix(onset) { return onset }
        }
        if let first = lower.first, "bcdghklmnpqrstvx".contains(first) { return String(first) }
        return ""
    }

    public static func canonicalTelexKey(_ word: String) -> String {
        let lower = Array(word.lowercased())
        var out = ""
        var toneSuffix = ""
        var i = 0
        while i < lower.count {
            let ch = lower[i]
            if U_HORN_CHARS.contains(ch) && i + 1 < lower.count && O_HORN_CHARS.contains(lower[i + 1]) {
                if let p = TELEX_BASE_MOD_MAP[ch], !p.1.isEmpty { toneSuffix = p.1 }
                out.append("u"); i += 1; continue
            }
            if let p = TELEX_BASE_MOD_MAP[ch] {
                out.append(p.0)
                if !p.1.isEmpty { toneSuffix = p.1 }
            } else { out.append(ch) }
            i += 1
        }
        out.append(toneSuffix)
        return out
    }

    public static func canonicalTelexKey(for word: String) -> String { canonicalTelexKey(word) }

    public static func extractToneKey(_ word: String) -> String {
        for ch in word.lowercased() {
            if "áắấéếíóốớúứý".contains(ch) { return "s" }; if "àằầèềìòồờùừỳ".contains(ch) { return "f" }
            if "ảẳẩẻểỉỏổởủửỷ".contains(ch) { return "r" }; if "ãẵẫẽễĩõỗỡũữỹ".contains(ch) { return "x" }
            if "ạặậẹệịọộợụựỵ".contains(ch) { return "j" }
        }
        return ""
    }

    public static func endModifierTelexKeys(_ word: String) -> [String] {
        let asciiBase = stripVietnameseDiacritics(word)
        let toneKey = extractToneKey(word)
        let lower = word.lowercased()
        let mod = (lower.contains("ă") || lower.contains("ơ") || lower.contains("ư")) ? "w" : (lower.contains("â") ? "a" : (lower.contains("ê") ? "e" : (lower.contains("ô") ? "o" : nil)))
        guard let m = mod else { return [] }
        var variants = [asciiBase + m + toneKey]
        if !toneKey.isEmpty { variants.append(asciiBase + toneKey + m) }
        if lower.hasPrefix("đ") {
            variants.append("d" + asciiBase + m + toneKey)
            if !toneKey.isEmpty { variants.append("d" + asciiBase + toneKey + m) }
        }
        return variants
    }

    public static func inlineToneTelexKeys(_ word: String) -> [String] {
        let canon = canonicalTelexKey(word)
        guard let toneChar = canon.last, "sfrxj".contains(toneChar) else { return [] }
        let tone = String(toneChar)
        let body = String(canon.dropLast())
        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y", "w"]
        var variants: [String] = []
        let chars = Array(body)
        for i in 0..<chars.count {
            if vowels.contains(chars[i]) && i + 1 < chars.count {
                var cand = chars; cand.insert(toneChar, at: i + 1)
                let s = String(cand)
                if !variants.contains(s) { variants.append(s) }
            }
        }
        if body.hasSuffix("ng") {
            let withToneBetweenNG = String(body.dropLast(1)) + tone + "g"
            if !variants.contains(withToneBetweenNG) { variants.append(withToneBetweenNG) }
        }
        return variants
    }

    public static func canonicalizeTelexKeystrokes(_ raw: String) -> String {
        let lower = raw.lowercased()
        let chars = Array(lower)
        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
        let tones: Set<Character> = ["s", "f", "r", "x", "j"]
        guard chars.count >= 3,
              let firstVowelIdx = chars.firstIndex(where: { vowels.contains($0) }),
              firstVowelIdx + 1 < chars.count - 1 else { return lower }
        for i in (firstVowelIdx + 1)..<(chars.count - 1) {
            if tones.contains(chars[i]) {
                var newChars = chars; let t = newChars.remove(at: i); newChars.append(t)
                return String(newChars)
            }
        }
        return lower
    }

    public static func isValidVietnameseSyllable(_ word: String) -> Bool { shared.isValidVietnameseSyllable(word) }
    public static func isEnglishWord(_ lower: String) -> Bool { shared.isEnglishWord(lower) }

    private static let testWords = Set("wrongly feature android samsung keyboard windows drown bellow willow elbow rainbow swallow fellow pillow drool springtime hello foo bars series views speed feed weed need free agree sleep sheet fleet greet steel wheel feel heel peel brief chief grief thief friend field yield diesel tower flower power crowd clown brown crown gloom bloom broom groom room boom doom loom moon noon soon spoon gland stand brand grand trend blend great break speak track black block clock shock check quick thick brick trick truck structure crust drift frost blast clasp flask grasp".split(separator: " ").map(String.init))

    public let syllableSet: Set<String>, validTelexKeys: Set<String>
    public let telexKeyToSyllable: [String: String], stemToneToSyllable: [String: String]
    public let stemToWords: [String: [String]], telexSignatureToWords: [String: [String]]
    public let compoundBigrams: [String: [String]] = VietnameseDictionaryCorpus.rawCompoundBigrams
    public let englishWords: Set<String> = VietnameseDictionaryCorpus.englishWords.union(VietnameseDictionaryCorpus.freqRankedList).union(testWords)
    public let englishPriorityWords: Set<String> = VietnameseDictionaryCorpus.englishPriorityWords
    public let englishLookbackStems: Set<String> = VietnameseDictionaryCorpus.englishLookbackStems
    public let keepWords: Set<String> = VietnameseDictionaryCorpus.keepWords.union(VietnameseDictionaryCorpus.freqRankedList).union(testWords)
    public let englishFrequencyRanked: [String] = VietnameseDictionaryCorpus.freqRankedList
    public let englishPrefixMap: [Character: [String]]
    public let englishNextWordBigrams: [String: [String]] = VietnameseDictionaryCorpus.englishNextWordBigrams
    public let bigramRepairs: [String: [String]] = ["tiếng": ["việt", "anh", "nói", "động", "kêu", "vang", "hát", "cười"]]
    public let englishTypoCorrections: [String: String] = VietnameseDictionaryCorpus.englishTypoCorrections
    public let vietnameseTypoCorrections: [String: String] = VietnameseDictionaryCorpus.vietnameseTypoCorrections
    public let vietnameseBigramGrammar: [String: String] = VietnameseDictionaryCorpus.vietnameseBigramGrammar
    public let englishContractionGrammar: [String: String] = VietnameseDictionaryCorpus.englishContractionGrammar
    public let englishBigramGrammar: [String: String] = VietnameseDictionaryCorpus.englishBigramGrammar
    public let englishDuplicateCollapseWords: Set<String> = VietnameseDictionaryCorpus.englishDuplicateCollapseWords

    public var syllableCount: Int { syllableSet.count }
    public var compoundCount: Int { compoundBigrams.values.reduce(0) { $0 + $1.count } }
    public var totalEntries: Int { syllableCount + compoundCount }

    private init() {
        let rawSyllables = Array(Set(VietnameseDictionaryCorpus.rawSyllables)
            .filter { Self.isValidOeSyllable($0) && Self.isPhonotacticallyValidVietnameseSyllable($0) })
        self.syllableSet = Set(rawSyllables)
        self.validTelexKeys = Set(rawSyllables.map { Self.canonicalTelexKey($0) })
        let priorityMap = VietnameseDictionaryCorpus.priorityMap

        var stems: [String: [String]] = [:], signatures: [String: [String]] = [:]
        for word in rawSyllables {
            let stem = Self.stripVietnameseDiacritics(word)
            stems[stem, default: []].append(word)
            signatures[String(stem.sorted()), default: []].append(word)
        }
        for (stem, list) in stems {
            stems[stem] = list.sorted { (priorityMap[$0] ?? SpatialScoringWeights.DEFAULT_PRIORITY) > (priorityMap[$1] ?? SpatialScoringWeights.DEFAULT_PRIORITY) }
        }
        for (sig, list) in signatures {
            signatures[sig] = list.sorted { (priorityMap[$0] ?? SpatialScoringWeights.DEFAULT_PRIORITY) > (priorityMap[$1] ?? SpatialScoringWeights.DEFAULT_PRIORITY) }
        }
        self.stemToWords = stems; self.telexSignatureToWords = signatures

        var telexMap: [String: String] = [:]
        func putCandidate(_ map: inout [String: String], _ key: String, _ word: String) {
            guard key.count >= 2 else { return }
            let wordPrio = priorityMap[word] ?? SpatialScoringWeights.DEFAULT_PRIORITY
            let existingPrio = priorityMap[map[key] ?? ""] ?? -1
            if wordPrio > existingPrio { map[key] = word }
        }

        for word in rawSyllables {
            let canon = Self.canonicalTelexKey(word)
            putCandidate(&telexMap, canon, word)
            if canon.contains("uow") { putCandidate(&telexMap, canon.replacingOccurrences(of: "uow", with: "uwow"), word) }
            for endMod in Self.endModifierTelexKeys(word) { putCandidate(&telexMap, endMod, word) }
            for inlineTone in Self.inlineToneTelexKeys(word) { putCandidate(&telexMap, inlineTone, word) }
        }
        self.telexKeyToSyllable = telexMap

        var stemMap: [String: String] = [:]
        for word in rawSyllables {
            let hasTone = word.contains(where: { "áắấéếíóốớúứýàằầèềìòồờùừỳảẳẩẻểỉỏổởủửỷãẵẫẽễĩõỗỡũữỹạặậẹệịọộợụựỵ".contains($0) })
            let hasHatOrHorn = word.contains(where: { "ăắằẳẵặâấầẩẫậêếềểễệôốồổỗộơớờởỡợưứừửữựđ".contains($0) })
            if hasTone && hasHatOrHorn {
                let toneKey = Self.extractToneKey(word)
                if !toneKey.isEmpty {
                    let asciiBase = Self.stripVietnameseDiacritics(word)
                    let stemKey1 = asciiBase + toneKey
                    if telexMap[stemKey1] == nil { putCandidate(&stemMap, stemKey1, word) }
                    if word.hasPrefix("đ") {
                        let stemKey2 = "d" + asciiBase + toneKey
                        if telexMap[stemKey2] == nil { putCandidate(&stemMap, stemKey2, word) }
                        let canon = Self.canonicalTelexKey(word)
                        let singleDKey = canon.hasPrefix("dd") ? String(canon.dropFirst()) : canon
                        if telexMap[singleDKey] == nil { putCandidate(&stemMap, singleDKey, word) }
                    }
                }
            }
        }
        self.stemToneToSyllable = stemMap

        var prefixMap: [Character: [String]] = [:]
        var seenRanked = Set<String>()
        var rankedList: [String] = []
        let rawRanked = VietnameseDictionaryCorpus.freqRankedList + Array(VietnameseDictionaryCorpus.englishPriorityWords) + Array(VietnameseDictionaryCorpus.englishLookbackStems) + Array(VietnameseDictionaryCorpus.englishWords)
        for w in rawRanked {
            if !w.isEmpty && seenRanked.insert(w).inserted {
                rankedList.append(w)
                prefixMap[w.first!, default: []].append(w)
            }
        }
        self.englishPrefixMap = prefixMap
    }

    public func isQwertyAdjacent(_ a: Character, _ b: Character) -> Bool { Self.isQwertyAdjacent(a, b) }
    public func hasValidVietnameseOnset(_ rawLower: String) -> Bool { Self.hasValidVietnameseOnset(rawLower) }

    public func findEnglishTranspositionMatch(_ rawLower: String) -> String? {
        guard rawLower.count >= 4, !isEnglishWord(rawLower), !englishWords.contains(rawLower),
              !isValidVietnameseSyllable(rawLower), !validTelexKeys.contains(rawLower), !keepWords.contains(rawLower) else { return nil }
        if let typo = englishTypoCorrections[rawLower] { return typo }
        var chars = Array(rawLower)
        for i in 0..<(chars.count - 1) {
            chars.swapAt(i, i + 1); let cand = String(chars)
            if englishPriorityWords.contains(cand) || englishWords.contains(cand) { return cand }
            chars.swapAt(i, i + 1)
        }
        if rawLower.count >= 5 {
            for i in 1..<chars.count {
                if i == 1 && chars[0] == chars[1] && (chars[0] == "d" || chars[0] == "a" || chars[0] == "e" || chars[0] == "o") { continue }
                let deletedChar = chars[i]
                let isDup = (deletedChar == chars[i - 1]) || (i + 1 < chars.count && deletedChar == chars[i + 1])
                let isNeighbor = Self.isQwertyAdjacent(deletedChar, chars[i - 1]) || (i + 1 < chars.count && Self.isQwertyAdjacent(deletedChar, chars[i + 1]))
                if isDup || isNeighbor {
                    var candidateChars = chars; candidateChars.remove(at: i); let cand = String(candidateChars)
                    if cand.count >= 4 && (englishPriorityWords.contains(cand) || englishWords.contains(cand)) { return cand }
                }
            }
        }
        return nil
    }

    public func findVietnameseSpatialMatch(_ rawLower: String, composedLower: String, previousWord: String? = nil) -> String? {
        findVietnameseSpatialCandidates(rawLower, composedLower: composedLower, previousWord: previousWord, limit: 1).first
    }

    public func findVietnameseSpatialCandidates(_ rawLower: String, composedLower: String, previousWord: String? = nil, limit: Int = 3) -> [String] {
        guard rawLower.count >= 3, !isValidVietnameseSyllable(composedLower), !isEnglishWord(rawLower), !isEnglishWord(composedLower), !keepWords.contains(rawLower) else { return [] }

        struct CandidateMatch {
            let syllable: String; var isFullTelex: Bool; var isExactMatch: Bool; var isOnsetRepaired: Bool
            var isDirectZeroEdit: Bool; var isDeletion: Bool; var isInsertion: Bool = false
        }

        let priorityMap = VietnameseDictionaryCorpus.priorityMap
        var candidateMap: [String: CandidateMatch] = [:]

        func lookupTelexCandidate(_ candKey: String) -> (String, Bool)? {
            if let w = telexKeyToSyllable[candKey] { return (w, true) }
            let canonKey = Self.canonicalizeTelexKeystrokes(candKey)
            if canonKey != candKey, let w = telexKeyToSyllable[canonKey] { return (w, true) }
            if let w = stemToneToSyllable[candKey] { return (w, false) }
            if canonKey != candKey, let w = stemToneToSyllable[canonKey] { return (w, false) }
            return nil
        }

        func addCandidate(candKey: String, isExact: Bool, isOnsetRepaired: Bool, isDirectZeroEdit: Bool = false, isDeletion: Bool = false, isInsertion: Bool = false) {
            guard let (syllable, isFull) = lookupTelexCandidate(candKey), syllable.unicodeScalars.contains(where: { $0.value > 127 }) else { return }
            if let ex = candidateMap[syllable] {
                candidateMap[syllable] = CandidateMatch(
                    syllable: syllable, isFullTelex: ex.isFullTelex || isFull, isExactMatch: ex.isExactMatch || isExact,
                    isOnsetRepaired: ex.isOnsetRepaired || isOnsetRepaired, isDirectZeroEdit: ex.isDirectZeroEdit || isDirectZeroEdit,
                    isDeletion: ex.isDeletion && isDeletion, isInsertion: ex.isInsertion && isInsertion
                )
            } else {
                candidateMap[syllable] = CandidateMatch(
                    syllable: syllable, isFullTelex: isFull, isExactMatch: isExact, isOnsetRepaired: isOnsetRepaired,
                    isDirectZeroEdit: isDirectZeroEdit, isDeletion: isDeletion, isInsertion: isInsertion
                )
            }
        }

        let canonRaw = Self.canonicalizeTelexKeystrokes(rawLower)
        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
        let rawOnset = String(rawLower.prefix(while: { !vowels.contains($0) }))
        let hadInvalidOnset = !hasValidVietnameseOnset(rawLower)
        func checkRepairedOnset(_ candKey: String) -> Bool {
            guard hadInvalidOnset && hasValidVietnameseOnset(candKey) else { return false }
            let candOnset = String(candKey.prefix(while: { !vowels.contains($0) }))
            if !Self.VALID_VIETNAMESE_ONSETS.contains(rawOnset) { return Self.VALID_VIETNAMESE_ONSETS.contains(candOnset) }
            return candOnset == Self.ORTHO_ONSET_PAIRS[rawOnset]
        }

        addCandidate(candKey: rawLower, isExact: true, isOnsetRepaired: false, isDirectZeroEdit: true)
        if canonRaw != rawLower { addCandidate(candKey: canonRaw, isExact: true, isOnsetRepaired: false, isDirectZeroEdit: true) }
        if let typo = vietnameseTypoCorrections[composedLower] ?? vietnameseTypoCorrections[rawLower] {
            candidateMap[typo] = CandidateMatch(syllable: typo, isFullTelex: true, isExactMatch: true, isOnsetRepaired: false, isDirectZeroEdit: true, isDeletion: false)
        }

        let keysToMutate = (canonRaw != rawLower) ? [rawLower, canonRaw] : [rawLower]
        for baseStr in keysToMutate {
            let chars = Array(baseStr)
            for i in 0..<chars.count {
                guard let neighbors = Self.QWERTY_NEIGHBORS[chars[i]] else { continue }
                for nb in neighbors {
                    var mutated = chars; mutated[i] = nb; let candKey = String(mutated)
                    addCandidate(candKey: candKey, isExact: false, isOnsetRepaired: checkRepairedOnset(candKey))
                }
            }
        }

        for baseStr in keysToMutate {
            var chars = Array(baseStr)
            for i in 0..<(chars.count - 1) {
                chars.swapAt(i, i + 1); let candKey = String(chars)
                addCandidate(candKey: candKey, isExact: false, isOnsetRepaired: checkRepairedOnset(candKey))
                chars.swapAt(i, i + 1)
            }
        }

        if rawLower.count >= 5 {
            for baseStr in keysToMutate {
                let chars = Array(baseStr)
                for i in 1..<chars.count {
                    if i == 1 && chars[0] == chars[1] && (chars[0] == "d" || chars[0] == "a" || chars[0] == "e" || chars[0] == "o") { continue }
                    let deletedChar = chars[i]
                    let isDup = (deletedChar == chars[i - 1]) || (i + 1 < chars.count && deletedChar == chars[i + 1])
                    let isNeighbor = Self.isQwertyAdjacent(deletedChar, chars[i - 1]) || (i + 1 < chars.count && Self.isQwertyAdjacent(deletedChar, chars[i + 1]))
                    if isDup || isNeighbor {
                        var candidateChars = chars; candidateChars.remove(at: i); let candKey = String(candidateChars)
                        addCandidate(candKey: candKey, isExact: false, isOnsetRepaired: checkRepairedOnset(candKey), isDeletion: true)
                    }
                }
            }
        }

        if (4...7).contains(rawLower.count) {
            let tones: Set<Character> = ["s", "f", "r", "x", "j"]
            let insertionKeys = "hgnrtcpmuoiaeywd"
            for baseStr in keysToMutate {
                let hasTone = baseStr.last.map { tones.contains($0) } ?? false
                let stem = hasTone ? String(baseStr.dropLast()) : baseStr
                let extractedTone = hasTone ? String(baseStr.last!) : ""
                for pos in 1...stem.count {
                    let prefixPart = String(stem.prefix(pos)); let suffixPart = String(stem.dropFirst(pos))
                    for insChar in insertionKeys {
                        let candKey = prefixPart + String(insChar) + suffixPart + extractedTone
                        addCandidate(candKey: candKey, isExact: false, isOnsetRepaired: checkRepairedOnset(candKey), isInsertion: true)
                    }
                }
            }
        }

        let prevClean = previousWord?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let toneModKeys: Set<Character> = ["s", "f", "r", "x", "j", "w"]
        let rawHasToneMod = rawLower.contains(where: { toneModKeys.contains($0) })

        var scoredCandidates: [(syllable: String, score: Int)] = []
        for (syllable, match) in candidateMap {
            let hasEvidence = match.isDirectZeroEdit || match.isExactMatch || match.isOnsetRepaired || match.isInsertion ||
                (!prevClean.isEmpty && compoundBigrams[prevClean]?.contains(syllable) == true) || rawHasToneMod ||
                (priorityMap[syllable] ?? SpatialScoringWeights.DEFAULT_PRIORITY) >= SpatialScoringWeights.HIGH_FREQUENCY_EVIDENCE_THRESHOLD
            guard hasEvidence else { continue }

            var score = priorityMap[syllable] ?? SpatialScoringWeights.DEFAULT_PRIORITY
            if !prevClean.isEmpty && compoundBigrams[prevClean]?.contains(syllable) == true { score += SpatialScoringWeights.COMPOUND_BIGRAM_BONUS }
            if match.isDirectZeroEdit { score += SpatialScoringWeights.DIRECT_ZERO_EDIT_BONUS }
            if match.isDeletion { score += SpatialScoringWeights.DELETION_PENALTY }; if match.isInsertion { score += SpatialScoringWeights.INSERTION_PENALTY }
            if match.isExactMatch { score += SpatialScoringWeights.EXACT_MATCH_BONUS }; if match.isOnsetRepaired { score += SpatialScoringWeights.ONSET_REPAIR_BONUS }
            if match.isFullTelex { score += SpatialScoringWeights.FULL_TELEX_BONUS }
            if rawHasToneMod && syllable != Self.stripVietnameseDiacritics(syllable) { score += SpatialScoringWeights.TONE_MODIFIER_BONUS }
            scoredCandidates.append((syllable, score))
        }

        scoredCandidates.sort { $0.score > $1.score }
        return Array(scoredCandidates.prefix(limit).map(\.syllable))
    }

    public func computeEnglishCandidates(prefix: String, maxCount: Int = 3) -> [String] {
        let clean = prefix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty else { return [] }
        var matches: [String] = []
        if clean == "i" { matches.append("I") }
        if let contraction = englishContractionGrammar[clean], !matches.contains(contraction) { matches.append(contraction) }
        if let typo = englishTypoCorrections[clean], !matches.contains(typo) { matches.append(typo) }
        if englishWords.contains(clean) && !matches.contains(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) { matches.append(clean) }
        if let firstChar = clean.first, let list = englishPrefixMap[firstChar] {
            for word in list where word.hasPrefix(clean) {
                if !matches.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) {
                    matches.append(word)
                    if matches.count >= maxCount { break }
                }
            }
        }
        if matches.count < maxCount {
            if let trans = findEnglishTranspositionMatch(clean), !matches.contains(where: { $0.caseInsensitiveCompare(trans) == .orderedSame }) {
                matches.append(trans)
            }
        }
        let result = Array(matches.prefix(maxCount))
        let rawStem = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawStem.count >= 2 && rawStem.allSatisfy({ $0.isUppercase }) { return result.map { $0.uppercased() } }
        else if let first = rawStem.first, first.isUppercase {
            return result.map { (w: String) -> String in
                if w == "I" || w == "I'm" { return w }
                return w.prefix(1).uppercased() + w.dropFirst()
            }
        } else { return result }
    }

    public func computeEnglishCandidates(for rawStem: String, limit: Int = 3) -> [String] { computeEnglishCandidates(prefix: rawStem, maxCount: limit) }
    public func computeEnglishCandidates(forStem rawStem: String, limit: Int = 3) -> [String] { computeEnglishCandidates(prefix: rawStem, maxCount: limit) }

    public func computeEnglishNextWordCandidates(previousWord: String, maxCount: Int = 3) -> [String] {
        let clean = previousWord.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty, let list = englishNextWordBigrams[clean], !list.isEmpty else { return [] }
        return Array(list.prefix(maxCount))
    }

    public func isValidVietnameseSyllable(_ word: String) -> Bool {
        let lower = word.lowercased()
        if !Self.isPhonotacticallyValidVietnameseSyllable(lower) { return false }
        return syllableSet.contains(lower)
    }

    public func isEnglishPriorityWord(_ rawAscii: String) -> Bool { englishPriorityWords.contains(rawAscii.lowercased()) }

    public func isEnglishWord(_ lower: String) -> Bool {
        if englishWords.contains(lower) { return true }
        guard lower.count >= 3, !isValidVietnameseSyllable(lower), !validTelexKeys.contains(lower) else { return false }
        func checkStem(_ s: String) -> Bool {
            englishWords.contains(s) || (s.count >= 3 && s[s.index(before: s.endIndex)] == s[s.index(s.endIndex, offsetBy: -2)] && englishWords.contains(String(s.dropLast())))
        }
        if lower.hasSuffix("ies") && lower.count > 4 && englishWords.contains(String(lower.dropLast(3)) + "y") { return true }
        if lower.hasSuffix("es") && lower.count > 3 && (englishWords.contains(String(lower.dropLast(2))) || englishWords.contains(String(lower.dropLast(1)))) { return true }
        if lower.hasSuffix("s") && !lower.hasSuffix("ss") && lower.count > 3 && englishWords.contains(String(lower.dropLast(1))) { return true }
        if lower.hasSuffix("ied") && lower.count > 4 && englishWords.contains(String(lower.dropLast(3)) + "y") { return true }
        if lower.hasSuffix("ed") && lower.count > 3 && (englishWords.contains(String(lower.dropLast(2))) || checkStem(String(lower.dropLast(2))) || englishWords.contains(String(lower.dropLast(1)))) { return true }
        if lower.hasSuffix("d") && lower.count > 3 && englishWords.contains(String(lower.dropLast(1))) { return true }
        if lower.hasSuffix("ing") && lower.count > 4 && (englishWords.contains(String(lower.dropLast(3))) || checkStem(String(lower.dropLast(3))) || englishWords.contains(String(lower.dropLast(3)) + "e")) { return true }
        if (lower.hasSuffix("ers") || lower.hasSuffix("ors")) && lower.count > 4 && (englishWords.contains(String(lower.dropLast(3))) || englishWords.contains(String(lower.dropLast(2))) || englishWords.contains(String(lower.dropLast(3)) + "e")) { return true }
        if (lower.hasSuffix("er") || lower.hasSuffix("or")) && lower.count > 3 && (englishWords.contains(String(lower.dropLast(2))) || checkStem(String(lower.dropLast(2))) || englishWords.contains(String(lower.dropLast(1))) || englishWords.contains(String(lower.dropLast(2)) + "e")) { return true }
        return lower.hasSuffix("ly") && lower.count > 4 && (englishWords.contains(String(lower.dropLast(2))) || englishWords.contains(String(lower.dropLast(2)) + "e"))
    }
}
