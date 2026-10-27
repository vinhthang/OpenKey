//
//  VietnameseData.swift
//  OpenKeySwiftCore
//
//  Converted to 100% Pure Swift 6 by Antigravity from the original C++ OpenKey engine:
//  Created by Mai Vũ Tuyên on 1/19/19.
//  Copyright © 2019 Mai Vũ Tuyên. All rights reserved.
//  Licensed under GNU General Public License v3.0.
//

import Foundation

// MARK: - Key Codes (macOS Virtual Keycodes)

public let KEY_ESC: UInt16 = 53
public let KEY_DELETE: UInt16 = 51
public let KEY_TAB: UInt16 = 48
public let KEY_ENTER: UInt16 = 76
public let KEY_RETURN: UInt16 = 36
public let KEY_SPACE: UInt16 = 49
public let KEY_LEFT: UInt16 = 123
public let KEY_RIGHT: UInt16 = 124
public let KEY_DOWN: UInt16 = 125
public let KEY_UP: UInt16 = 126

public let KEY_EMPTY: UInt16 = 256
public let KEY_A: UInt16 = 0
public let KEY_B: UInt16 = 11
public let KEY_C: UInt16 = 8
public let KEY_D: UInt16 = 2
public let KEY_E: UInt16 = 14
public let KEY_F: UInt16 = 3
public let KEY_G: UInt16 = 5
public let KEY_H: UInt16 = 4
public let KEY_I: UInt16 = 34
public let KEY_J: UInt16 = 38
public let KEY_K: UInt16 = 40
public let KEY_L: UInt16 = 37
public let KEY_M: UInt16 = 46
public let KEY_N: UInt16 = 45
public let KEY_O: UInt16 = 31
public let KEY_P: UInt16 = 35
public let KEY_Q: UInt16 = 12
public let KEY_R: UInt16 = 15
public let KEY_S: UInt16 = 1
public let KEY_T: UInt16 = 17
public let KEY_U: UInt16 = 32
public let KEY_V: UInt16 = 9
public let KEY_W: UInt16 = 13
public let KEY_X: UInt16 = 7
public let KEY_Y: UInt16 = 16
public let KEY_Z: UInt16 = 6

public let KEY_1: UInt16 = 18
public let KEY_2: UInt16 = 19
public let KEY_3: UInt16 = 20
public let KEY_4: UInt16 = 21
public let KEY_5: UInt16 = 23
public let KEY_6: UInt16 = 22
public let KEY_7: UInt16 = 26
public let KEY_8: UInt16 = 28
public let KEY_9: UInt16 = 25
public let KEY_0: UInt16 = 29

public let KEY_LEFT_BRACKET: UInt16 = 33
public let KEY_RIGHT_BRACKET: UInt16 = 30

public let KEY_LEFT_SHIFT: UInt16 = 57
public let KEY_RIGHT_SHIFT: UInt16 = 60
public let KEY_DOT: UInt16 = 47

public let KEY_BACKQUOTE: UInt16 = 50
public let KEY_MINUS: UInt16 = 27
public let KEY_EQUALS: UInt16 = 24
public let KEY_BACK_SLASH: UInt16 = 42
public let KEY_SEMICOLON: UInt16 = 41
public let KEY_QUOTE: UInt16 = 39
public let KEY_COMMA: UInt16 = 43
public let KEY_SLASH: UInt16 = 44

// MARK: - Internal Engine Bitmasks

public let CAPS_MASK: UInt32 = 0x10000
public let TONE_MASK: UInt32 = 0x20000
public let TONEW_MASK: UInt32 = 0x40000

/*
 * MARK MASK
 * 1: Dấu Sắc - á
 * 2: Dấu Huyền - à
 * 3: Dấu Hỏi - ả
 * 4: Dấu Ngã - ã
 * 5: Dấu Nặng - ạ
 */
public let MARK1_MASK: UInt32 = 0x80000
public let MARK2_MASK: UInt32 = 0x100000
public let MARK3_MASK: UInt32 = 0x200000
public let MARK4_MASK: UInt32 = 0x400000
public let MARK5_MASK: UInt32 = 0x800000
public let MARK_MASK: UInt32 = 0xF80000

public let CHAR_MASK: UInt32 = 0xFFFF
public let STANDALONE_MASK: UInt32 = 0x1000000
public let CHAR_CODE_MASK: UInt32 = 0x2000000
public let AUTO_TONE_MASK: UInt32 = 0x4000000
public let PURE_CHARACTER_MASK: UInt32 = 0x80000000

public let END_CONSONANT_MASK: UInt16 = 0x4000
public let CONSONANT_ALLOW_MASK: UInt16 = 0x8000

// MARK: - Hook Snapshot Structure

public struct OKHookSnapshot: Sendable, Equatable {
    public var code: UInt8
    public var backspaceCount: UInt8
    public var newCharCount: UInt8
    public var extCode: UInt8
    public var shouldSendControlKey: Bool
    public var utf16Chars: [UInt16]
    
    public init(
        code: UInt8 = 0,
        backspaceCount: UInt8 = 0,
        newCharCount: UInt8 = 0,
        extCode: UInt8 = 0,
        shouldSendControlKey: Bool = false,
        utf16Chars: [UInt16] = []
    ) {
        self.code = code
        self.backspaceCount = backspaceCount
        self.newCharCount = newCharCount
        self.extCode = extCode
        self.shouldSendControlKey = shouldSendControlKey
        self.utf16Chars = utf16Chars
    }
}

// MARK: - Hook Code Constants

public enum HookCodeState {
    public static let doNothing: UInt8 = 0
    public static let willProcess: UInt8 = 1
    public static let breakWord: UInt8 = 2
    public static let restore: UInt8 = 3
    public static let restoreAndStartNewSession: UInt8 = 4
}

// MARK: - Phonotactic Helper Utilities

@inline(__always)
public func isConsonant(_ keyCode: UInt16) -> Bool {
    !(keyCode == KEY_A || keyCode == KEY_E || keyCode == KEY_U || keyCode == KEY_Y || keyCode == KEY_I || keyCode == KEY_O)
}

@inline(__always)
public func isNumberKey(_ code: UInt16) -> Bool {
    code == KEY_1 || code == KEY_2 || code == KEY_3 || code == KEY_4 || code == KEY_5 ||
    code == KEY_6 || code == KEY_7 || code == KEY_8 || code == KEY_9 || code == KEY_0
}

// MARK: - Phonotactic Tables

public let douKey: [[UInt16]] = [
    [KEY_A, 0x00E2], // a -> â
    [KEY_E, 0x00EA]  // e -> ê
]

public let _vowel: [UInt16: [[UInt16]]] = [
    KEY_A: [
        [KEY_A, KEY_N, KEY_G], [KEY_A, KEY_G | END_CONSONANT_MASK],
        [KEY_A, KEY_N],
        [KEY_A, KEY_M],
        [KEY_A, KEY_U],
        [KEY_A, KEY_Y],
        [KEY_A, KEY_T],
        [KEY_A, KEY_P],
        [KEY_A],
        [KEY_A, KEY_C]
    ],
    KEY_O: [
        [KEY_O, KEY_N, KEY_G], [KEY_O, KEY_G | END_CONSONANT_MASK],
        [KEY_O, KEY_N],
        [KEY_O, KEY_M],
        [KEY_O, KEY_I],
        [KEY_O, KEY_C],
        [KEY_O, KEY_T],
        [KEY_O, KEY_P],
        [KEY_O]
    ],
    KEY_E: [
        [KEY_E, KEY_N, KEY_H], [KEY_E, KEY_H | END_CONSONANT_MASK],
        [KEY_E, KEY_N, KEY_G], [KEY_E, KEY_G | END_CONSONANT_MASK],
        [KEY_E, KEY_C, KEY_H], [KEY_E, KEY_K | END_CONSONANT_MASK],
        [KEY_E, KEY_C],
        [KEY_E, KEY_T],
        [KEY_E, KEY_Y],
        [KEY_E, KEY_U],
        [KEY_E, KEY_P],
        [KEY_E, KEY_C],
        [KEY_E, KEY_N],
        [KEY_E, KEY_M],
        [KEY_E]
    ],
    KEY_W: [
        [KEY_O, KEY_N],
        [KEY_U, KEY_O, KEY_N, KEY_G], [KEY_U, KEY_O, KEY_G | END_CONSONANT_MASK],
        [KEY_U, KEY_O, KEY_N],
        [KEY_U, KEY_O, KEY_I],
        [KEY_U, KEY_O, KEY_C],
        [KEY_O, KEY_I],
        [KEY_O, KEY_P],
        [KEY_O, KEY_M],
        [KEY_O, KEY_A],
        [KEY_O, KEY_T],
        [KEY_U, KEY_N, KEY_G], [KEY_U, KEY_G | END_CONSONANT_MASK],
        [KEY_A, KEY_N, KEY_G], [KEY_A, KEY_G | END_CONSONANT_MASK],
        [KEY_U, KEY_N],
        [KEY_U, KEY_M],
        [KEY_U, KEY_C],
        [KEY_U, KEY_A],
        [KEY_U, KEY_I],
        [KEY_U, KEY_T],
        [KEY_U],
        [KEY_A, KEY_P],
        [KEY_A, KEY_T],
        [KEY_A, KEY_M],
        [KEY_A, KEY_N],
        [KEY_A],
        [KEY_A, KEY_C],
        [KEY_A, KEY_C, KEY_H], [KEY_A, KEY_K | END_CONSONANT_MASK],
        [KEY_O],
        [KEY_U, KEY_U]
    ]
]

public let _vowelCombine: [UInt16: [[UInt32]]] = [
    KEY_A: [
        [0, UInt32(KEY_A), UInt32(KEY_I)],
        [0, UInt32(KEY_A), UInt32(KEY_O)],
        [0, UInt32(KEY_A), UInt32(KEY_U)],
        [0, UInt32(KEY_A) | TONE_MASK, UInt32(KEY_U)],
        [0, UInt32(KEY_A), UInt32(KEY_Y)],
        [0, UInt32(KEY_A) | TONE_MASK, UInt32(KEY_Y)]
    ],
    KEY_E: [
        [0, UInt32(KEY_E), UInt32(KEY_O)],
        [0, UInt32(KEY_E) | TONE_MASK, UInt32(KEY_U)]
    ],
    KEY_I: [
        [1, UInt32(KEY_I), UInt32(KEY_E) | TONE_MASK, UInt32(KEY_U)],
        [0, UInt32(KEY_I), UInt32(KEY_A)],
        [1, UInt32(KEY_I), UInt32(KEY_E) | TONE_MASK],
        [0, UInt32(KEY_I), UInt32(KEY_U)]
    ],
    KEY_O: [
        [0, UInt32(KEY_O), UInt32(KEY_A), UInt32(KEY_I)],
        [0, UInt32(KEY_O), UInt32(KEY_A), UInt32(KEY_O)],
        [0, UInt32(KEY_O), UInt32(KEY_A), UInt32(KEY_Y)],
        [0, UInt32(KEY_O), UInt32(KEY_E), UInt32(KEY_O)],
        [1, UInt32(KEY_O), UInt32(KEY_A)],
        [1, UInt32(KEY_O), UInt32(KEY_A) | TONEW_MASK],
        [1, UInt32(KEY_O), UInt32(KEY_E)],
        [0, UInt32(KEY_O), UInt32(KEY_I)],
        [0, UInt32(KEY_O) | TONE_MASK, UInt32(KEY_I)],
        [0, UInt32(KEY_O) | TONEW_MASK, UInt32(KEY_I)],
        [1, UInt32(KEY_O), UInt32(KEY_O)],
        [1, UInt32(KEY_O) | TONE_MASK, UInt32(KEY_O) | TONE_MASK]
    ],
    KEY_U: [
        [0, UInt32(KEY_U), UInt32(KEY_Y), UInt32(KEY_U)],
        [1, UInt32(KEY_U), UInt32(KEY_Y), UInt32(KEY_E) | TONE_MASK],
        [0, UInt32(KEY_U), UInt32(KEY_Y), UInt32(KEY_A)],
        [0, UInt32(KEY_U) | TONEW_MASK, UInt32(KEY_O) | TONEW_MASK, UInt32(KEY_U)],
        [0, UInt32(KEY_U) | TONEW_MASK, UInt32(KEY_O) | TONEW_MASK, UInt32(KEY_I)],
        [0, UInt32(KEY_U), UInt32(KEY_O) | TONE_MASK, UInt32(KEY_I)],
        [0, UInt32(KEY_U), UInt32(KEY_A) | TONE_MASK, UInt32(KEY_Y)],
        [1, UInt32(KEY_U), UInt32(KEY_A), UInt32(KEY_O)],
        [1, UInt32(KEY_U), UInt32(KEY_A)],
        [1, UInt32(KEY_U), UInt32(KEY_A) | TONEW_MASK],
        [1, UInt32(KEY_U), UInt32(KEY_A) | TONE_MASK],
        [0, UInt32(KEY_U) | TONEW_MASK, UInt32(KEY_A)],
        [1, UInt32(KEY_U), UInt32(KEY_E) | TONE_MASK],
        [0, UInt32(KEY_U), UInt32(KEY_I)],
        [0, UInt32(KEY_U) | TONEW_MASK, UInt32(KEY_I)],
        [1, UInt32(KEY_U), UInt32(KEY_O)],
        [1, UInt32(KEY_U), UInt32(KEY_O) | TONE_MASK],
        [0, UInt32(KEY_U), UInt32(KEY_O) | TONEW_MASK],
        [1, UInt32(KEY_U) | TONEW_MASK, UInt32(KEY_O) | TONEW_MASK],
        [0, UInt32(KEY_U) | TONEW_MASK, UInt32(KEY_U)],
        [1, UInt32(KEY_U), UInt32(KEY_Y)]
    ],
    KEY_Y: [
        [0, UInt32(KEY_Y), UInt32(KEY_E) | TONE_MASK, UInt32(KEY_U)],
        [1, UInt32(KEY_Y), UInt32(KEY_E) | TONE_MASK]
    ]
]

public let _consonantD: [[UInt16]] = [
    [KEY_D, KEY_E, KEY_N, KEY_H], [KEY_D, KEY_E, KEY_H | END_CONSONANT_MASK],
    [KEY_D, KEY_E, KEY_N, KEY_G], [KEY_D, KEY_E, KEY_G | END_CONSONANT_MASK],
    [KEY_D, KEY_E, KEY_C, KEY_H], [KEY_D, KEY_E, KEY_K | END_CONSONANT_MASK],
    [KEY_D, KEY_E, KEY_N],
    [KEY_D, KEY_E, KEY_C],
    [KEY_D, KEY_E, KEY_M],
    [KEY_D, KEY_E],
    [KEY_D, KEY_E, KEY_T],
    [KEY_D, KEY_E, KEY_U],
    [KEY_D, KEY_E, KEY_O],
    [KEY_D, KEY_E, KEY_P],
    
    [KEY_D, KEY_U, KEY_N, KEY_G], [KEY_D, KEY_U, KEY_G | END_CONSONANT_MASK],
    [KEY_D, KEY_U, KEY_N],
    [KEY_D, KEY_U, KEY_M],
    [KEY_D, KEY_U, KEY_C],
    [KEY_D, KEY_U, KEY_O],
    [KEY_D, KEY_U, KEY_A],
    [KEY_D, KEY_U, KEY_O, KEY_I],
    [KEY_D, KEY_U, KEY_O, KEY_C],
    [KEY_D, KEY_U, KEY_O, KEY_N],
    [KEY_D, KEY_U, KEY_O, KEY_N, KEY_G], [KEY_D, KEY_U, KEY_O, KEY_G | END_CONSONANT_MASK],
    [KEY_D, KEY_U],
    [KEY_D, KEY_U, KEY_P],
    [KEY_D, KEY_U, KEY_T],
    [KEY_D, KEY_U, KEY_I],
    
    [KEY_D, KEY_I, KEY_C, KEY_H], [KEY_D, KEY_I, KEY_K | END_CONSONANT_MASK],
    [KEY_D, KEY_I, KEY_C],
    [KEY_D, KEY_I, KEY_N, KEY_H], [KEY_D, KEY_I, KEY_H | END_CONSONANT_MASK],
    [KEY_D, KEY_I, KEY_N],
    [KEY_D, KEY_I],
    [KEY_D, KEY_I, KEY_A],
    [KEY_D, KEY_I, KEY_E],
    [KEY_D, KEY_I, KEY_E, KEY_C],
    [KEY_D, KEY_I, KEY_E, KEY_U],
    [KEY_D, KEY_I, KEY_E, KEY_N],
    [KEY_D, KEY_I, KEY_E, KEY_M],
    [KEY_D, KEY_I, KEY_E, KEY_P],
    [KEY_D, KEY_I, KEY_T],
    
    [KEY_D, KEY_O],
    [KEY_D, KEY_O, KEY_A],
    [KEY_D, KEY_O, KEY_A, KEY_N],
    [KEY_D, KEY_O, KEY_A, KEY_N, KEY_G], [KEY_D, KEY_O, KEY_A, KEY_G | END_CONSONANT_MASK],
    [KEY_D, KEY_O, KEY_A, KEY_N, KEY_H], [KEY_D, KEY_O, KEY_A, KEY_H | END_CONSONANT_MASK],
    [KEY_D, KEY_O, KEY_A, KEY_M],
    [KEY_D, KEY_O, KEY_E],
    [KEY_D, KEY_O, KEY_I],
    [KEY_D, KEY_O, KEY_P],
    [KEY_D, KEY_O, KEY_C],
    [KEY_D, KEY_O, KEY_N],
    [KEY_D, KEY_O, KEY_N, KEY_G], [KEY_D, KEY_O, KEY_G | END_CONSONANT_MASK],
    [KEY_D, KEY_O, KEY_M],
    [KEY_D, KEY_O, KEY_T],
    
    [KEY_D, KEY_A],
    [KEY_D, KEY_A, KEY_T],
    [KEY_D, KEY_A, KEY_Y],
    [KEY_D, KEY_A, KEY_U],
    [KEY_D, KEY_A, KEY_I],
    [KEY_D, KEY_A, KEY_O],
    [KEY_D, KEY_A, KEY_P],
    [KEY_D, KEY_A, KEY_C],
    [KEY_D, KEY_A, KEY_C, KEY_H], [KEY_D, KEY_A, KEY_K | END_CONSONANT_MASK],
    [KEY_D, KEY_A, KEY_N],
    [KEY_D, KEY_A, KEY_N, KEY_H], [KEY_D, KEY_A, KEY_H | END_CONSONANT_MASK],
    [KEY_D, KEY_A, KEY_N, KEY_G], [KEY_D, KEY_A, KEY_G | END_CONSONANT_MASK],
    [KEY_D, KEY_A, KEY_M],
    
    [KEY_D]
]

public let _vowelForMark: [UInt16: [[UInt16]]] = [
    KEY_A: [
        [KEY_A, KEY_N, KEY_G], [KEY_A, KEY_G | END_CONSONANT_MASK],
        [KEY_A, KEY_N],
        [KEY_A, KEY_N, KEY_H], [KEY_A, KEY_H | END_CONSONANT_MASK],
        [KEY_A, KEY_M],
        [KEY_A, KEY_U],
        [KEY_A, KEY_Y],
        [KEY_A, KEY_T],
        [KEY_A, KEY_P],
        [KEY_A],
        [KEY_A, KEY_C],
        [KEY_A, KEY_I],
        [KEY_A, KEY_O],
        [KEY_A, KEY_C, KEY_H], [KEY_A, KEY_K | END_CONSONANT_MASK]
    ],
    KEY_O: [
        [KEY_O, KEY_O, KEY_N, KEY_G], [KEY_O, KEY_O, KEY_G | END_CONSONANT_MASK],
        [KEY_O, KEY_N, KEY_G], [KEY_O, KEY_G | END_CONSONANT_MASK],
        [KEY_O, KEY_O, KEY_N],
        [KEY_O, KEY_O, KEY_C],
        [KEY_O, KEY_O],
        [KEY_O, KEY_N],
        [KEY_O, KEY_M],
        [KEY_O, KEY_I],
        [KEY_O, KEY_C],
        [KEY_O, KEY_T],
        [KEY_O, KEY_P],
        [KEY_O]
    ],
    KEY_E: [
        [KEY_E, KEY_N, KEY_H], [KEY_E, KEY_H | END_CONSONANT_MASK],
        [KEY_E, KEY_N, KEY_G], [KEY_E, KEY_G | END_CONSONANT_MASK],
        [KEY_E, KEY_C, KEY_H], [KEY_E, KEY_K | END_CONSONANT_MASK],
        [KEY_E, KEY_C],
        [KEY_E, KEY_T],
        [KEY_E, KEY_Y],
        [KEY_E, KEY_U],
        [KEY_E, KEY_P],
        [KEY_E, KEY_C],
        [KEY_E, KEY_N],
        [KEY_E, KEY_M],
        [KEY_E]
    ],
    KEY_I: [
        [KEY_I, KEY_N, KEY_H], [KEY_I, KEY_H | END_CONSONANT_MASK],
        [KEY_I, KEY_C, KEY_H], [KEY_I, KEY_K | END_CONSONANT_MASK],
        [KEY_I, KEY_N],
        [KEY_I, KEY_T],
        [KEY_I, KEY_U],
        [KEY_I, KEY_U, KEY_P],
        [KEY_I, KEY_N],
        [KEY_I, KEY_M],
        [KEY_I, KEY_P],
        [KEY_I, KEY_A],
        [KEY_I, KEY_C],
        [KEY_I]
    ],
    KEY_U: [
        [KEY_U, KEY_N, KEY_G], [KEY_U, KEY_G | END_CONSONANT_MASK],
        [KEY_U, KEY_I],
        [KEY_U, KEY_O],
        [KEY_U, KEY_Y],
        [KEY_U, KEY_Y, KEY_N],
        [KEY_U, KEY_Y, KEY_T],
        [KEY_U, KEY_Y, KEY_P],
        [KEY_U, KEY_Y, KEY_C, KEY_H], [KEY_U, KEY_Y, KEY_K | END_CONSONANT_MASK],
        [KEY_U, KEY_Y, KEY_N, KEY_H], [KEY_U, KEY_Y, KEY_H | END_CONSONANT_MASK],
        [KEY_U, KEY_T],
        [KEY_U, KEY_U],
        [KEY_U, KEY_A],
        [KEY_U, KEY_I],
        [KEY_U, KEY_C],
        [KEY_U, KEY_N],
        [KEY_U, KEY_M],
        [KEY_U, KEY_P],
        [KEY_U]
    ],
    KEY_Y: [
        [KEY_Y]
    ]
]

public let _consonantTable: [[UInt16]] = [
    [KEY_N, KEY_G, KEY_H],
    [KEY_P, KEY_H],
    [KEY_T, KEY_H],
    [KEY_T, KEY_R],
    [KEY_G, KEY_I],
    [KEY_C, KEY_H],
    [KEY_N, KEY_H],
    [KEY_N, KEY_G],
    [KEY_K, KEY_H],
    [KEY_G, KEY_H],
    [KEY_G],
    [KEY_C],
    [KEY_Q],
    [KEY_K],
    [KEY_T],
    [KEY_R],
    [KEY_H],
    [KEY_B],
    [KEY_M],
    [KEY_V],
    [KEY_N],
    [KEY_L],
    [KEY_X],
    [KEY_P],
    [KEY_S],
    [KEY_D]
]

public let _endConsonantTable: [[UInt16]] = [
    [KEY_T], [KEY_P], [KEY_C], [KEY_N], [KEY_M],
    [KEY_C, KEY_H], [KEY_N, KEY_H], [KEY_N, KEY_G]
]

public let _standaloneWbad: [UInt16] = [
    KEY_W, KEY_E, KEY_Y, KEY_F, KEY_J, KEY_K, KEY_Z
]

public let _doubleWAllowed: [[UInt16]] = [
    [KEY_T, KEY_R],
    [KEY_T, KEY_H],
    [KEY_C, KEY_H],
    [KEY_N, KEY_H],
    [KEY_N, KEY_G],
    [KEY_K, KEY_H],
    [KEY_G, KEY_I],
    [KEY_P, KEY_H],
    [KEY_G, KEY_H]
]

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

public func keyCodeToCharacter(_ keyCode: UInt32) -> UInt16 {
    _keyCodeToCharMap[keyCode & (CHAR_MASK | CAPS_MASK)] ?? 0
}
