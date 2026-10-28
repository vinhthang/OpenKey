//
//  AutoWordingTypes.swift
//  OpenKeySwiftCore
//
//  Created for OpenKey macOS Swift.
//  Auto Wording types, candidate structures, and shorthand catalog (REQ-009, ADR-008).
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
    public static let builtInTable: [String: String] = [
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
    
    public static let properNouns: Set<String> = [
        "vn", "hn", "tphcm", "hcm"
    ]
}
