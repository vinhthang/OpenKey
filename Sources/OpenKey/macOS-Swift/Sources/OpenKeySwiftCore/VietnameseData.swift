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
        [KEY_A, KEY_N], [KEY_A, KEY_M], [KEY_A, KEY_U], [KEY_A, KEY_Y],
        [KEY_A, KEY_T], [KEY_A, KEY_P], [KEY_A], [KEY_A, KEY_C]
    ],
    KEY_O: [
        [KEY_O, KEY_N, KEY_G], [KEY_O, KEY_G | END_CONSONANT_MASK],
        [KEY_O, KEY_N], [KEY_O, KEY_M], [KEY_O, KEY_I],
        [KEY_O, KEY_C], [KEY_O, KEY_T], [KEY_O, KEY_P], [KEY_O]
    ],
    KEY_E: [
        [KEY_E, KEY_N, KEY_H], [KEY_E, KEY_H | END_CONSONANT_MASK],
        [KEY_E, KEY_N, KEY_G], [KEY_E, KEY_G | END_CONSONANT_MASK],
        [KEY_E, KEY_C, KEY_H], [KEY_E, KEY_K | END_CONSONANT_MASK],
        [KEY_E, KEY_C], [KEY_E, KEY_T], [KEY_E, KEY_Y], [KEY_E, KEY_U],
        [KEY_E, KEY_P], [KEY_E, KEY_C], [KEY_E, KEY_N], [KEY_E, KEY_M], [KEY_E]
    ],
    KEY_W: [
        [KEY_O, KEY_N],
        [KEY_U, KEY_O, KEY_N, KEY_G], [KEY_U, KEY_O, KEY_G | END_CONSONANT_MASK],
        [KEY_U, KEY_O, KEY_N], [KEY_U, KEY_O, KEY_I], [KEY_U, KEY_O, KEY_C],
        [KEY_O, KEY_I], [KEY_O, KEY_P], [KEY_O, KEY_M], [KEY_O, KEY_A], [KEY_O, KEY_T],
        [KEY_U, KEY_N, KEY_G], [KEY_U, KEY_G | END_CONSONANT_MASK],
        [KEY_A, KEY_N, KEY_G], [KEY_A, KEY_G | END_CONSONANT_MASK],
        [KEY_U, KEY_N], [KEY_U, KEY_M], [KEY_U, KEY_C], [KEY_U, KEY_A],
        [KEY_U, KEY_I], [KEY_U, KEY_T], [KEY_U], [KEY_A, KEY_P],
        [KEY_A, KEY_T], [KEY_A, KEY_M], [KEY_A, KEY_N], [KEY_A], [KEY_A, KEY_C],
        [KEY_A, KEY_C, KEY_H], [KEY_A, KEY_K | END_CONSONANT_MASK],
        [KEY_O], [KEY_U, KEY_U]
    ]
]

public let _vowelCombine: [UInt16: [[UInt32]]] = [
    KEY_A: [
        [0, UInt32(KEY_A), UInt32(KEY_I)], [0, UInt32(KEY_A), UInt32(KEY_O)],
        [0, UInt32(KEY_A), UInt32(KEY_U)], [0, UInt32(KEY_A) | TONE_MASK, UInt32(KEY_U)],
        [0, UInt32(KEY_A), UInt32(KEY_Y)], [0, UInt32(KEY_A) | TONE_MASK, UInt32(KEY_Y)]
    ],
    KEY_E: [
        [0, UInt32(KEY_E), UInt32(KEY_O)], [0, UInt32(KEY_E) | TONE_MASK, UInt32(KEY_U)]
    ],
    KEY_I: [
        [1, UInt32(KEY_I), UInt32(KEY_E) | TONE_MASK, UInt32(KEY_U)], [0, UInt32(KEY_I), UInt32(KEY_A)],
        [1, UInt32(KEY_I), UInt32(KEY_E) | TONE_MASK], [0, UInt32(KEY_I), UInt32(KEY_U)]
    ],
    KEY_O: [
        [0, UInt32(KEY_O), UInt32(KEY_A), UInt32(KEY_I)], [0, UInt32(KEY_O), UInt32(KEY_A), UInt32(KEY_O)],
        [0, UInt32(KEY_O), UInt32(KEY_A), UInt32(KEY_Y)], [0, UInt32(KEY_O), UInt32(KEY_E), UInt32(KEY_O)],
        [1, UInt32(KEY_O), UInt32(KEY_A)], [1, UInt32(KEY_O), UInt32(KEY_A) | TONEW_MASK],
        [1, UInt32(KEY_O), UInt32(KEY_E)], [0, UInt32(KEY_O), UInt32(KEY_I)],
        [0, UInt32(KEY_O) | TONE_MASK, UInt32(KEY_I)], [0, UInt32(KEY_O) | TONEW_MASK, UInt32(KEY_I)],
        [1, UInt32(KEY_O), UInt32(KEY_O)], [1, UInt32(KEY_O) | TONE_MASK, UInt32(KEY_O) | TONE_MASK]
    ],
    KEY_U: [
        [0, UInt32(KEY_U), UInt32(KEY_Y), UInt32(KEY_U)], [1, UInt32(KEY_U), UInt32(KEY_Y), UInt32(KEY_E) | TONE_MASK],
        [0, UInt32(KEY_U), UInt32(KEY_Y), UInt32(KEY_A)], [0, UInt32(KEY_U) | TONEW_MASK, UInt32(KEY_O) | TONEW_MASK, UInt32(KEY_U)],
        [0, UInt32(KEY_U) | TONEW_MASK, UInt32(KEY_O) | TONEW_MASK, UInt32(KEY_I)], [0, UInt32(KEY_U), UInt32(KEY_O) | TONE_MASK, UInt32(KEY_I)],
        [0, UInt32(KEY_U), UInt32(KEY_A) | TONE_MASK, UInt32(KEY_Y)], [1, UInt32(KEY_U), UInt32(KEY_A), UInt32(KEY_O)],
        [1, UInt32(KEY_U), UInt32(KEY_A)], [1, UInt32(KEY_U), UInt32(KEY_A) | TONEW_MASK],
        [1, UInt32(KEY_U), UInt32(KEY_A) | TONE_MASK], [0, UInt32(KEY_U) | TONEW_MASK, UInt32(KEY_A)],
        [1, UInt32(KEY_U), UInt32(KEY_E) | TONE_MASK], [0, UInt32(KEY_U), UInt32(KEY_I)],
        [0, UInt32(KEY_U) | TONEW_MASK, UInt32(KEY_I)], [1, UInt32(KEY_U), UInt32(KEY_O)],
        [1, UInt32(KEY_U), UInt32(KEY_O) | TONE_MASK], [0, UInt32(KEY_U), UInt32(KEY_O) | TONEW_MASK],
        [1, UInt32(KEY_U) | TONEW_MASK, UInt32(KEY_O) | TONEW_MASK], [0, UInt32(KEY_U) | TONEW_MASK, UInt32(KEY_U)],
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
    [KEY_D, KEY_E, KEY_N], [KEY_D, KEY_E, KEY_C], [KEY_D, KEY_E, KEY_M], [KEY_D, KEY_E],
    [KEY_D, KEY_E, KEY_T], [KEY_D, KEY_E, KEY_U], [KEY_D, KEY_E, KEY_O], [KEY_D, KEY_E, KEY_P],
    
    [KEY_D, KEY_U, KEY_N, KEY_G], [KEY_D, KEY_U, KEY_G | END_CONSONANT_MASK],
    [KEY_D, KEY_U, KEY_N], [KEY_D, KEY_U, KEY_M], [KEY_D, KEY_U, KEY_C], [KEY_D, KEY_U, KEY_O], [KEY_D, KEY_U, KEY_A],
    [KEY_D, KEY_U, KEY_O, KEY_I], [KEY_D, KEY_U, KEY_O, KEY_C], [KEY_D, KEY_U, KEY_O, KEY_N],
    [KEY_D, KEY_U, KEY_O, KEY_N, KEY_G], [KEY_D, KEY_U, KEY_O, KEY_G | END_CONSONANT_MASK],
    [KEY_D, KEY_U], [KEY_D, KEY_U, KEY_P], [KEY_D, KEY_U, KEY_T], [KEY_D, KEY_U, KEY_I],
    
    [KEY_D, KEY_I, KEY_C, KEY_H], [KEY_D, KEY_I, KEY_K | END_CONSONANT_MASK],
    [KEY_D, KEY_I, KEY_C], [KEY_D, KEY_I, KEY_N, KEY_H], [KEY_D, KEY_I, KEY_H | END_CONSONANT_MASK],
    [KEY_D, KEY_I, KEY_N], [KEY_D, KEY_I], [KEY_D, KEY_I, KEY_A], [KEY_D, KEY_I, KEY_E],
    [KEY_D, KEY_I, KEY_E, KEY_C], [KEY_D, KEY_I, KEY_E, KEY_U], [KEY_D, KEY_I, KEY_E, KEY_N],
    [KEY_D, KEY_I, KEY_E, KEY_M], [KEY_D, KEY_I, KEY_E, KEY_P], [KEY_D, KEY_I, KEY_T],
    
    [KEY_D, KEY_O], [KEY_D, KEY_O, KEY_A], [KEY_D, KEY_O, KEY_A, KEY_N],
    [KEY_D, KEY_O, KEY_A, KEY_N, KEY_G], [KEY_D, KEY_O, KEY_A, KEY_G | END_CONSONANT_MASK],
    [KEY_D, KEY_O, KEY_A, KEY_N, KEY_H], [KEY_D, KEY_O, KEY_A, KEY_H | END_CONSONANT_MASK],
    [KEY_D, KEY_O, KEY_A, KEY_M], [KEY_D, KEY_O, KEY_E], [KEY_D, KEY_O, KEY_I], [KEY_D, KEY_O, KEY_P],
    [KEY_D, KEY_O, KEY_C], [KEY_D, KEY_O, KEY_N], [KEY_D, KEY_O, KEY_N, KEY_G], [KEY_D, KEY_O, KEY_G | END_CONSONANT_MASK],
    [KEY_D, KEY_O, KEY_M], [KEY_D, KEY_O, KEY_T],
    
    [KEY_D, KEY_A], [KEY_D, KEY_A, KEY_T], [KEY_D, KEY_A, KEY_Y], [KEY_D, KEY_A, KEY_U], [KEY_D, KEY_A, KEY_I],
    [KEY_D, KEY_A, KEY_O], [KEY_D, KEY_A, KEY_P], [KEY_D, KEY_A, KEY_C],
    [KEY_D, KEY_A, KEY_C, KEY_H], [KEY_D, KEY_A, KEY_K | END_CONSONANT_MASK],
    [KEY_D, KEY_A, KEY_N], [KEY_D, KEY_A, KEY_N, KEY_H], [KEY_D, KEY_A, KEY_H | END_CONSONANT_MASK],
    [KEY_D, KEY_A, KEY_N, KEY_G], [KEY_D, KEY_A, KEY_G | END_CONSONANT_MASK],
    [KEY_D, KEY_A, KEY_M], [KEY_D]
]

public let _vowelForMark: [UInt16: [[UInt16]]] = [
    KEY_A: [
        [KEY_A, KEY_N, KEY_G], [KEY_A, KEY_G | END_CONSONANT_MASK],
        [KEY_A, KEY_N], [KEY_A, KEY_N, KEY_H], [KEY_A, KEY_H | END_CONSONANT_MASK],
        [KEY_A, KEY_M], [KEY_A, KEY_U], [KEY_A, KEY_Y], [KEY_A, KEY_T],
        [KEY_A, KEY_P], [KEY_A], [KEY_A, KEY_C], [KEY_A, KEY_I], [KEY_A, KEY_O],
        [KEY_A, KEY_C, KEY_H], [KEY_A, KEY_K | END_CONSONANT_MASK]
    ],
    KEY_O: [
        [KEY_O, KEY_O, KEY_N, KEY_G], [KEY_O, KEY_O, KEY_G | END_CONSONANT_MASK],
        [KEY_O, KEY_N, KEY_G], [KEY_O, KEY_G | END_CONSONANT_MASK],
        [KEY_O, KEY_O, KEY_N], [KEY_O, KEY_O, KEY_C], [KEY_O, KEY_O],
        [KEY_O, KEY_N], [KEY_O, KEY_M], [KEY_O, KEY_I], [KEY_O, KEY_C],
        [KEY_O, KEY_T], [KEY_O, KEY_P], [KEY_O]
    ],
    KEY_E: [
        [KEY_E, KEY_N, KEY_H], [KEY_E, KEY_H | END_CONSONANT_MASK],
        [KEY_E, KEY_N, KEY_G], [KEY_E, KEY_G | END_CONSONANT_MASK],
        [KEY_E, KEY_C, KEY_H], [KEY_E, KEY_K | END_CONSONANT_MASK],
        [KEY_E, KEY_C], [KEY_E, KEY_T], [KEY_E, KEY_Y], [KEY_E, KEY_U],
        [KEY_E, KEY_P], [KEY_E, KEY_C], [KEY_E, KEY_N], [KEY_E, KEY_M], [KEY_E]
    ],
    KEY_I: [
        [KEY_I, KEY_N, KEY_H], [KEY_I, KEY_H | END_CONSONANT_MASK],
        [KEY_I, KEY_C, KEY_H], [KEY_I, KEY_K | END_CONSONANT_MASK],
        [KEY_I, KEY_N], [KEY_I, KEY_T], [KEY_I, KEY_U], [KEY_I, KEY_U, KEY_P],
        [KEY_I, KEY_N], [KEY_I, KEY_M], [KEY_I, KEY_P], [KEY_I, KEY_A],
        [KEY_I, KEY_C], [KEY_I]
    ],
    KEY_U: [
        [KEY_U, KEY_N, KEY_G], [KEY_U, KEY_G | END_CONSONANT_MASK],
        [KEY_U, KEY_I], [KEY_U, KEY_O], [KEY_U, KEY_Y], [KEY_U, KEY_Y, KEY_N],
        [KEY_U, KEY_Y, KEY_T], [KEY_U, KEY_Y, KEY_P],
        [KEY_U, KEY_Y, KEY_C, KEY_H], [KEY_U, KEY_Y, KEY_K | END_CONSONANT_MASK],
        [KEY_U, KEY_Y, KEY_N, KEY_H], [KEY_U, KEY_Y, KEY_H | END_CONSONANT_MASK],
        [KEY_U, KEY_T], [KEY_U, KEY_U], [KEY_U, KEY_A], [KEY_U, KEY_I],
        [KEY_U, KEY_C], [KEY_U, KEY_N], [KEY_U, KEY_M], [KEY_U, KEY_P], [KEY_U]
    ],
    KEY_Y: [
        [KEY_Y]
    ]
]

public let _consonantTable: [[UInt16]] = [
    [KEY_N, KEY_G, KEY_H], [KEY_P, KEY_H], [KEY_T, KEY_H], [KEY_T, KEY_R],
    [KEY_G, KEY_I], [KEY_C, KEY_H], [KEY_N, KEY_H], [KEY_N, KEY_G],
    [KEY_K, KEY_H], [KEY_G, KEY_H], [KEY_G], [KEY_C], [KEY_Q], [KEY_K],
    [KEY_T], [KEY_R], [KEY_H], [KEY_B], [KEY_M], [KEY_V], [KEY_N],
    [KEY_L], [KEY_X], [KEY_P], [KEY_S], [KEY_D]
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

// MARK: - Syllable Bitmask Properties Extension

extension UInt32 {
    @inline(__always)
    public var baseKey: UInt16 {
        UInt16(self & CHAR_MASK)
    }
    
    @inline(__always)
    public var isCaps: Bool {
        (self & CAPS_MASK) != 0
    }
    
    @inline(__always)
    public var hasToneMark: Bool {
        (self & (TONE_MASK | TONEW_MASK)) != 0
    }
    
    @inline(__always)
    public var toneMark: UInt32 {
        self & (TONE_MASK | TONEW_MASK)
    }
    
    @inline(__always)
    public var hasCircumflexOrStroke: Bool {
        (self & TONE_MASK) != 0
    }
    
    @inline(__always)
    public var hasHornOrBreve: Bool {
        (self & TONEW_MASK) != 0
    }
    
    @inline(__always)
    public var hasAnyDiacritic: Bool {
        (self & (TONE_MASK | TONEW_MASK | MARK_MASK)) != 0
    }
    
    @inline(__always)
    public var isAutoTone: Bool {
        (self & AUTO_TONE_MASK) != 0
    }
    
    @inline(__always)
    public var isStandaloneW: Bool {
        (self & STANDALONE_MASK) != 0
    }
}

