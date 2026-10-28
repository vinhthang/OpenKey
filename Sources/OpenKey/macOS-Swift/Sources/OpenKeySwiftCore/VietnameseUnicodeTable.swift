//
//  VietnameseUnicodeTable.swift
//  OpenKeySwiftCore
//
//  Converted to 100% Pure Swift 6 by Antigravity from the original C++ OpenKey engine:
//  Created by Mai Vũ Tuyên on 1/19/19.
//  Copyright © 2019 Mai Vũ Tuyên. All rights reserved.
//  Licensed under GNU General Public License v3.0.
//

import Foundation

// MARK: - Precomposed Unicode Code Table

public let _codeTable: [UInt32: [UInt16]] = [
    // KEY_A: Â, â, Ă, ă, Á, á, À, à, Ả, ả, Ã, ã, Ạ, ạ
    UInt32(KEY_A): [0x00C2, 0x00E2, 0x0102, 0x0103, 0x00C1, 0x00E1, 0x00C0, 0x00E0, 0x1EA2, 0x1EA3, 0x00C3, 0x00E3, 0x1EA0, 0x1EA1],
    // KEY_O: Ô, ô, Ơ, ơ, Ó, ó, O, o, Ỏ, ỏ, Õ, õ, Ọ, ọ
    UInt32(KEY_O): [0x00D4, 0x00F4, 0x01A0, 0x01A1, 0x00D3, 0x00F3, 0x00D2, 0x00F2, 0x1ECE, 0x1ECF, 0x00D5, 0x00F5, 0x1ECC, 0x1ECD],
    // KEY_U: -, -, Ư, ư, Ú, ú, Ù, ù, Ủ, ủ, Ũ, ũ, Ụ, ụ
    UInt32(KEY_U): [0x0000, 0x0000, 0x01AF, 0x01B0, 0x00DA, 0x00FA, 0x00D9, 0x00F9, 0x1EE6, 0x1EE7, 0x0168, 0x0169, 0x1EE4, 0x1EE5],
    // KEY_E: Ê, ê, -, -, É, é, È, è, Ẻ, ẻ, Ẽ, ẽ, Ẹ, ẹ
    UInt32(KEY_E): [0x00CA, 0x00EA, 0x0000, 0x0000, 0x00C9, 0x00E9, 0x00C8, 0x00E8, 0x1EBA, 0x1EBB, 0x1EBC, 0x1EBD, 0x1EB8, 0x1EB9],
    // KEY_D: Đ, đ
    UInt32(KEY_D): [0x0110, 0x0111],
    // KEY_A | TONE_MASK: Ấ, ấ, Ầ, ầ, Ẩ, ẩ, Ẫ, ẫ, Ậ, ậ
    UInt32(KEY_A) | TONE_MASK: [0x1EA4, 0x1EA5, 0x1EA6, 0x1EA7, 0x1EA8, 0x1EA9, 0x1EAA, 0x1EAB, 0x1EAC, 0x1EAD],
    // KEY_A | TONEW_MASK: Ắ, ắ, Ằ, ằ, Ẳ, ẳ, Ẵ, ẵ, Ặ, ặ
    UInt32(KEY_A) | TONEW_MASK: [0x1EAE, 0x1EAF, 0x1EB0, 0x1EB1, 0x1EB2, 0x1EB3, 0x1EB4, 0x1EB5, 0x1EB6, 0x1EB7],
    // KEY_O | TONE_MASK: Ố, ố, Ồ, ồ, Ổ, ổ, Ỗ, ỗ, Ộ, ộ
    UInt32(KEY_O) | TONE_MASK: [0x1ED0, 0x1ED1, 0x1ED2, 0x1ED3, 0x1ED4, 0x1ED5, 0x1ED6, 0x1ED7, 0x1ED8, 0x1ED9],
    // KEY_O | TONEW_MASK: Ớ, ớ, Ờ, ờ, Ở, ở, Ỡ, ỡ, Ợ, ợ
    UInt32(KEY_O) | TONEW_MASK: [0x1EDA, 0x1EDB, 0x1EDC, 0x1EDD, 0x1EDE, 0x1EDF, 0x1EE0, 0x1EE1, 0x1EE2, 0x1EE3],
    // KEY_U | TONEW_MASK: Ứ, ứng, Ừ, ừ, Ử, ử, Ữ, ữ, Ự, ự
    UInt32(KEY_U) | TONEW_MASK: [0x1EE8, 0x1EE9, 0x1EEA, 0x1EEB, 0x1EEC, 0x1EED, 0x1EEE, 0x1EEF, 0x1EF0, 0x1EF1],
    // KEY_E | TONE_MASK: Ế, ế, Ề, ề, Ể, ể, Ễ, ễ, Ệ, ệ
    UInt32(KEY_E) | TONE_MASK: [0x1EBE, 0x1EBF, 0x1EC0, 0x1EC1, 0x1EC2, 0x1EC3, 0x1EC4, 0x1EC5, 0x1EC6, 0x1EC7],
    // KEY_I: Í, í, Ì, ì, Ỉ, ỉ, Ĩ, ĩ, Ị, ị
    UInt32(KEY_I): [0x00CD, 0x00ED, 0x00CC, 0x00EC, 0x1EC8, 0x1EC9, 0x0128, 0x0129, 0x1ECA, 0x1ECB],
    // KEY_Y: Ý, ý, Ỳ, ỳ, Ỷ, ỷ, Ỹ, ỹ, Ỵ, ỵ
    UInt32(KEY_Y): [0x00DD, 0x00FD, 0x1EF2, 0x1EF3, 0x1EF6, 0x1EF7, 0x1EF8, 0x1EF9, 0x1EF4, 0x1EF5]
]

// MARK: - Character Map & KeyCode to Character Conversion

public let _characterMap: [UInt32: UInt32] = [
    UInt32(Character("a").asciiValue!): UInt32(KEY_A),
    UInt32(Character("A").asciiValue!): UInt32(KEY_A) | CAPS_MASK,
    UInt32(Character("b").asciiValue!): UInt32(KEY_B),
    UInt32(Character("B").asciiValue!): UInt32(KEY_B) | CAPS_MASK,
    UInt32(Character("c").asciiValue!): UInt32(KEY_C),
    UInt32(Character("C").asciiValue!): UInt32(KEY_C) | CAPS_MASK,
    UInt32(Character("d").asciiValue!): UInt32(KEY_D),
    UInt32(Character("D").asciiValue!): UInt32(KEY_D) | CAPS_MASK,
    UInt32(Character("e").asciiValue!): UInt32(KEY_E),
    UInt32(Character("E").asciiValue!): UInt32(KEY_E) | CAPS_MASK,
    UInt32(Character("f").asciiValue!): UInt32(KEY_F),
    UInt32(Character("F").asciiValue!): UInt32(KEY_F) | CAPS_MASK,
    UInt32(Character("g").asciiValue!): UInt32(KEY_G),
    UInt32(Character("G").asciiValue!): UInt32(KEY_G) | CAPS_MASK,
    UInt32(Character("h").asciiValue!): UInt32(KEY_H),
    UInt32(Character("H").asciiValue!): UInt32(KEY_H) | CAPS_MASK,
    UInt32(Character("i").asciiValue!): UInt32(KEY_I),
    UInt32(Character("I").asciiValue!): UInt32(KEY_I) | CAPS_MASK,
    UInt32(Character("j").asciiValue!): UInt32(KEY_J),
    UInt32(Character("J").asciiValue!): UInt32(KEY_J) | CAPS_MASK,
    UInt32(Character("k").asciiValue!): UInt32(KEY_K),
    UInt32(Character("K").asciiValue!): UInt32(KEY_K) | CAPS_MASK,
    UInt32(Character("l").asciiValue!): UInt32(KEY_L),
    UInt32(Character("L").asciiValue!): UInt32(KEY_L) | CAPS_MASK,
    UInt32(Character("m").asciiValue!): UInt32(KEY_M),
    UInt32(Character("M").asciiValue!): UInt32(KEY_M) | CAPS_MASK,
    UInt32(Character("n").asciiValue!): UInt32(KEY_N),
    UInt32(Character("N").asciiValue!): UInt32(KEY_N) | CAPS_MASK,
    UInt32(Character("o").asciiValue!): UInt32(KEY_O),
    UInt32(Character("O").asciiValue!): UInt32(KEY_O) | CAPS_MASK,
    UInt32(Character("p").asciiValue!): UInt32(KEY_P),
    UInt32(Character("P").asciiValue!): UInt32(KEY_P) | CAPS_MASK,
    UInt32(Character("q").asciiValue!): UInt32(KEY_Q),
    UInt32(Character("Q").asciiValue!): UInt32(KEY_Q) | CAPS_MASK,
    UInt32(Character("r").asciiValue!): UInt32(KEY_R),
    UInt32(Character("R").asciiValue!): UInt32(KEY_R) | CAPS_MASK,
    UInt32(Character("s").asciiValue!): UInt32(KEY_S),
    UInt32(Character("S").asciiValue!): UInt32(KEY_S) | CAPS_MASK,
    UInt32(Character("t").asciiValue!): UInt32(KEY_T),
    UInt32(Character("T").asciiValue!): UInt32(KEY_T) | CAPS_MASK,
    UInt32(Character("u").asciiValue!): UInt32(KEY_U),
    UInt32(Character("U").asciiValue!): UInt32(KEY_U) | CAPS_MASK,
    UInt32(Character("v").asciiValue!): UInt32(KEY_V),
    UInt32(Character("V").asciiValue!): UInt32(KEY_V) | CAPS_MASK,
    UInt32(Character("w").asciiValue!): UInt32(KEY_W),
    UInt32(Character("W").asciiValue!): UInt32(KEY_W) | CAPS_MASK,
    UInt32(Character("x").asciiValue!): UInt32(KEY_X),
    UInt32(Character("X").asciiValue!): UInt32(KEY_X) | CAPS_MASK,
    UInt32(Character("y").asciiValue!): UInt32(KEY_Y),
    UInt32(Character("Y").asciiValue!): UInt32(KEY_Y) | CAPS_MASK,
    UInt32(Character("z").asciiValue!): UInt32(KEY_Z),
    UInt32(Character("Z").asciiValue!): UInt32(KEY_Z) | CAPS_MASK,
    UInt32(Character("1").asciiValue!): UInt32(KEY_1),
    UInt32(Character("!").asciiValue!): UInt32(KEY_1) | CAPS_MASK,
    UInt32(Character("2").asciiValue!): UInt32(KEY_2),
    UInt32(Character("@").asciiValue!): UInt32(KEY_2) | CAPS_MASK,
    UInt32(Character("3").asciiValue!): UInt32(KEY_3),
    UInt32(Character("#").asciiValue!): UInt32(KEY_3) | CAPS_MASK,
    UInt32(Character("4").asciiValue!): UInt32(KEY_4),
    UInt32(Character("$").asciiValue!): UInt32(KEY_4) | CAPS_MASK,
    UInt32(Character("5").asciiValue!): UInt32(KEY_5),
    UInt32(Character("%").asciiValue!): UInt32(KEY_5) | CAPS_MASK,
    UInt32(Character("6").asciiValue!): UInt32(KEY_6),
    UInt32(Character("^").asciiValue!): UInt32(KEY_6) | CAPS_MASK,
    UInt32(Character("7").asciiValue!): UInt32(KEY_7),
    UInt32(Character("&").asciiValue!): UInt32(KEY_7) | CAPS_MASK,
    UInt32(Character("8").asciiValue!): UInt32(KEY_8),
    UInt32(Character("*").asciiValue!): UInt32(KEY_8) | CAPS_MASK,
    UInt32(Character("9").asciiValue!): UInt32(KEY_9),
    UInt32(Character("(").asciiValue!): UInt32(KEY_9) | CAPS_MASK,
    UInt32(Character("0").asciiValue!): UInt32(KEY_0),
    UInt32(Character(")").asciiValue!): UInt32(KEY_0) | CAPS_MASK,
    UInt32(Character("`").asciiValue!): UInt32(KEY_BACKQUOTE),
    UInt32(Character("~").asciiValue!): UInt32(KEY_BACKQUOTE) | CAPS_MASK,
    UInt32(Character("-").asciiValue!): UInt32(KEY_MINUS),
    UInt32(Character("_").asciiValue!): UInt32(KEY_MINUS) | CAPS_MASK,
    UInt32(Character("=").asciiValue!): UInt32(KEY_EQUALS),
    UInt32(Character("+").asciiValue!): UInt32(KEY_EQUALS) | CAPS_MASK,
    UInt32(Character("[").asciiValue!): UInt32(KEY_LEFT_BRACKET),
    UInt32(Character("{").asciiValue!): UInt32(KEY_LEFT_BRACKET) | CAPS_MASK,
    UInt32(Character("]").asciiValue!): UInt32(KEY_RIGHT_BRACKET),
    UInt32(Character("}").asciiValue!): UInt32(KEY_RIGHT_BRACKET) | CAPS_MASK,
    UInt32(Character("\\").asciiValue!): UInt32(KEY_BACK_SLASH),
    UInt32(Character("|").asciiValue!): UInt32(KEY_BACK_SLASH) | CAPS_MASK,
    UInt32(Character(";").asciiValue!): UInt32(KEY_SEMICOLON),
    UInt32(Character(":").asciiValue!): UInt32(KEY_SEMICOLON) | CAPS_MASK,
    UInt32(Character("'").asciiValue!): UInt32(KEY_QUOTE),
    UInt32(Character("\"").asciiValue!): UInt32(KEY_QUOTE) | CAPS_MASK,
    UInt32(Character(",").asciiValue!): UInt32(KEY_COMMA),
    UInt32(Character("<").asciiValue!): UInt32(KEY_COMMA) | CAPS_MASK,
    UInt32(Character(".").asciiValue!): UInt32(KEY_DOT),
    UInt32(Character(">").asciiValue!): UInt32(KEY_DOT) | CAPS_MASK,
    UInt32(Character("/").asciiValue!): UInt32(KEY_SLASH),
    UInt32(Character("?").asciiValue!): UInt32(KEY_SLASH) | CAPS_MASK,
    UInt32(Character(" ").asciiValue!): UInt32(KEY_SPACE)
]

private let _keyCodeToCharMap: [UInt32: UInt16] = {
    var map: [UInt32: UInt16] = [:]
    for (charVal, keyVal) in _characterMap {
        map[keyVal] = UInt16(charVal)
    }
    return map
}()

@inline(__always)
public func keyCodeToCharacter(_ keyCode: UInt32) -> UInt16 {
    _keyCodeToCharMap[keyCode & (CHAR_MASK | CAPS_MASK)] ?? 0
}
