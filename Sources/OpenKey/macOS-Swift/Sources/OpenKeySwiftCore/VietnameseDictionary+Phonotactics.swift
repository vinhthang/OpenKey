//
//  VietnameseDictionary+Phonotactics.swift
//  OpenKeySwiftCore
//
//  Extracted phonotactic and onset validation rules for Vietnamese syllables.
//

import Foundation

extension VietnameseDictionary {
    private enum Phonotactics {
        static let FAKE_D_SHADOWS: Set<String> = ["dất", "dến", "diểm", "dồng", "dứng", "dể", "dữa"]
        static let NON_VN_CHARS_REGEX = try! NSRegularExpression(pattern: "[wfjz]")
        static let NON_QU_BARE_UE_REGEX = try! NSRegularExpression(pattern: "^(?!qu).*?[uúùủũụ][eéèẻẽẹ]$")
        static let GIOA_E_GIY_REGEX = try! NSRegularExpression(pattern: "^gi[oóòỏõọ][aáàảãạăắằẳẵặeéèẻẽẹ]|^gi[yýỳỷỹỵ]")
        static let GIU_INVALID_REGEX = try! NSRegularExpression(pattern: "^gi[uúùủũụ][ôốồổỗộâấầẩẫậêếềểễệyýỳỷỹỵoóòỏõọăắằẳẵặ]")
        static let HALF_HORN_UO_REGEX = try! NSRegularExpression(pattern: "(?:u[ơớờởỡợ]|[ưứừửữự][oóòỏõọ])(ng|nh|ch|[cmnptui])|[ưứừửữự][oóòỏõọ]$")
        static let UNHORNED_UO_REGEX = try! NSRegularExpression(pattern: "^(?!(?:q|th|h|kh)u[ơớờởỡợ]$).*?u[ơớờởỡợ]")
        static let GH_NGH_INVALID = try! NSRegularExpression(pattern: "^(gh|ngh)[aăâoôơuưyáắấóốớúứýàằầòồờùừỳảẳẩỏổởủửỷãẵẫõỗỡũữỹạặậọộợụựỵ]")
        static let G_NG_INVALID = try! NSRegularExpression(pattern: "^(g(?!h|[iíìỉĩị])|ng(?!h))[eéèẻẽẹêếềểễệiíìỉĩị]")
        static let K_INVALID = try! NSRegularExpression(pattern: "^k[aăâoôơuưáắấóốớúứàằầòồờùừảẳẩỏổởủửãẵẫõỗỡũữạặậọộợụự]|^k[yýỳỷỹỵ].+")
        static let C_INVALID = try! NSRegularExpression(pattern: "^c(?!h)[eéèẻẽẹêếềểễệiíìỉĩịyýỳỷỹỵ]|^ch[yýỳỷỹỵ].+")
        static let YE_INVALID = try! NSRegularExpression(pattern: "^(?:b|ch|d|đ|g|gh|gi|h|k|kh|l|m|n|ng|ngh|nh|p|ph|r|s|t|th|tr|v|x)y[êếềểễệ]")
        static let INVALID_RHYMES = try! NSRegularExpression(pattern: "(?<![ưứừửữự])[ơớờởỡợ]ng$|[ưứừửữự][nm]$|[iíìỉĩị]c$|[eéèẻẽẹ]c$|^(?:b|ch|c|d|đ|l|m|n|t|v)u[ểễềếệ]n$|ãu$|uổn$")
        static let LABIAL_MEDIALS = try! NSRegularExpression(pattern: "^(?:b|m|p|ph|v)(?:[oóòỏõọ][aáàảãạăắằẳẵặeéèẻẽẹ]|[uúùủũụ][êếềểễệyýỳỷỹỵâấầẩẫậ])")
        static let NHIA_CHECK = try! NSRegularExpression(pattern: "^nh[iíìỉĩị][aáàảãạ]$|^nhĩa$")
        static let validOeOnsets: Set<String> = ["", "ch", "h", "kh", "l", "ng", "nh", "t", "x", "gi", "qu"]

        static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
            let range = NSRange(text.startIndex..., in: text)
            return regex.firstMatch(in: text, options: [], range: range) != nil
        }
    }

    public static let VALID_VIETNAMESE_ONSETS: Set<String> = [
        "", "b", "c", "ch", "d", "dd", "g", "gh", "gi", "h", "k", "kh", "l", "m", "n",
        "ng", "ngh", "nh", "p", "ph", "qu", "r", "s", "t", "th", "tr", "v", "x"
    ]
    public static let ORTHO_ONSET_PAIRS: [String: String] = [
        "ng": "ngh", "g": "gh", "gh": "g", "ngh": "ng", "c": "k", "k": "c"
    ]

    /// Validates whether a syllable obeys Vietnamese orthography and phonotactics.
    public static func isPhonotacticallyValidVietnameseSyllable(_ word: String) -> Bool {
        let lower = word.lowercased()
        if lower.isEmpty || Phonotactics.FAKE_D_SHADOWS.contains(lower) { return false }
        if Phonotactics.matches(Phonotactics.NON_VN_CHARS_REGEX, lower) || Phonotactics.matches(Phonotactics.NON_QU_BARE_UE_REGEX, lower) { return false }
        if Phonotactics.matches(Phonotactics.GIOA_E_GIY_REGEX, lower) || Phonotactics.matches(Phonotactics.GIU_INVALID_REGEX, lower) { return false }
        if Phonotactics.matches(Phonotactics.HALF_HORN_UO_REGEX, lower) || Phonotactics.matches(Phonotactics.UNHORNED_UO_REGEX, lower) { return false }
        if Phonotactics.matches(Phonotactics.GH_NGH_INVALID, lower) || Phonotactics.matches(Phonotactics.G_NG_INVALID, lower) { return false }
        if Phonotactics.matches(Phonotactics.K_INVALID, lower) || Phonotactics.matches(Phonotactics.C_INVALID, lower) { return false }
        if Phonotactics.matches(Phonotactics.YE_INVALID, lower) || Phonotactics.matches(Phonotactics.INVALID_RHYMES, lower) || Phonotactics.matches(Phonotactics.LABIAL_MEDIALS, lower) { return false }
        if Phonotactics.matches(Phonotactics.NHIA_CHECK, lower) { return false }
        if let lastCoda = lower.last, lastCoda == "c" || lastCoda == "p" || lastCoda == "t" || lower.hasSuffix("ch") {
            if !lower.contains(where: { "áắấéếíóốớúứýạặậẹệịọộợụựỵ".contains($0) }) { return false }
        }
        return true
    }

    /// Validates whether the ASCII or Unicode syllable begins with a legal Vietnamese onset for the following vowel.
    public static func hasValidVietnameseOnset(_ rawLower: String) -> Bool {
        let stripped = stripVietnameseDiacritics(rawLower)
        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
        let onset = stripped.hasPrefix("qu") ? "qu" : String(stripped.prefix(while: { !vowels.contains($0) }))
        let rest = String(stripped.dropFirst(onset.count))
        if onset == "ng" && (rest.hasPrefix("i") || rest.hasPrefix("e")) { return false }
        if onset == "g" && rest.hasPrefix("e") { return false }
        if (onset == "gh" || onset == "ngh") && (rest.hasPrefix("a") || rest.hasPrefix("o") || rest.hasPrefix("u")) { return false }
        if onset == "c" && (rest.hasPrefix("i") || rest.hasPrefix("e") || rest.hasPrefix("y")) { return false }
        if onset == "k" && (rest.hasPrefix("a") || rest.hasPrefix("o") || rest.hasPrefix("u")) { return false }
        return VALID_VIETNAMESE_ONSETS.contains(onset)
    }

    static func isValidOeSyllable(_ word: String) -> Bool {
        let stem = stripVietnameseDiacritics(word)
        guard stem.contains("oe") else { return true }
        let onset = String(stem.prefix(while: { !"aeiouy".contains($0) }))
        return Phonotactics.validOeOnsets.contains(onset)
    }
}
