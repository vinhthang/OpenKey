//
//  OpenKeyTestHelpers.swift
//  OpenKeySwiftTests
//
//  Created for OpenKey macOS Swift.
//  Test helpers, virtual screen simulator, and snapshot extensions (REQ-009, ADR-008).
//

import Foundation
import CoreGraphics
import ApplicationServices
import Testing
@testable import OpenKeySwiftCore

@Suite("OpenKeySwiftTests", .serialized)
struct OpenKeySwiftTests {}

extension OKHookSnapshot {
    var utf16Array: [UInt16] {
        utf16Chars
    }
    
    var decodedString: String {
        return String(utf16CodeUnits: utf16Chars, count: utf16Chars.count)
    }
}

@discardableResult
func typeKeys(_ keyCodes: [Int], caps: Int = 0, isKeypad: Bool = false) -> [OKHookSnapshot] {
    return keyCodes.map { OKEngineHandleKeyEvent(UInt16($0), UInt8(caps), isKeypad) }
}

struct VirtualScreen {
    var text: String = ""
    
    init(text: String = "") {
        self.text = text
        OKEngineResetSession()
    }
    
    mutating func typeKeys(_ keys: [Int]) {
        for k in keys { typeKey(k) }
    }
    
    @discardableResult
    mutating func typeKey(_ keyCode: Int, caps: Int = 0, isKeypad: Bool = false, char: Character? = nil) -> OKHookSnapshot {
        let snap = OKEngineHandleKeyEvent(UInt16(keyCode), UInt8(caps), isKeypad)
        if snap.code == HookCodeState.willProcess || snap.code == HookCodeState.restore || snap.code == HookCodeState.restoreAndStartNewSession {
            let bs = Int(snap.backspaceCount)
            if bs > 0 {
                let toRemove = min(bs, text.count)
                text.removeLast(toRemove)
            }
            text.append(snap.decodedString)
        } else {
            if keyCode == 51 { // KEY_DELETE
                if !text.isEmpty {
                    text.removeLast()
                }
            } else if let ch = char {
                text.append(ch)
            } else if let ch = Self.charForKeyCode(keyCode, caps: caps != 0) {
                text.append(ch)
            }
        }
        return snap
    }
    
    static func charForKeyCode(_ keyCode: Int, caps: Bool) -> Character? {
        switch keyCode {
        case 0: return caps ? "A" : "a"
        case 1: return caps ? "S" : "s"
        case 2: return caps ? "D" : "d"
        case 3: return caps ? "F" : "f"
        case 4: return caps ? "H" : "h"
        case 5: return caps ? "G" : "g"
        case 6: return caps ? "Z" : "z"
        case 7: return caps ? "X" : "x"
        case 8: return caps ? "C" : "c"
        case 9: return caps ? "V" : "v"
        case 11: return caps ? "B" : "b"
        case 12: return caps ? "Q" : "q"
        case 13: return caps ? "W" : "w"
        case 14: return caps ? "E" : "e"
        case 15: return caps ? "R" : "r"
        case 16: return caps ? "Y" : "y"
        case 17: return caps ? "T" : "t"
        case 30: return "]"
        case 31: return caps ? "O" : "o"
        case 32: return caps ? "U" : "u"
        case 33: return "["
        case 34: return caps ? "I" : "i"
        case 35: return caps ? "P" : "p"
        case 37: return caps ? "L" : "l"
        case 38: return caps ? "J" : "j"
        case 40: return caps ? "K" : "k"
        case 41: return ";"
        case 43: return ","
        case 45: return caps ? "N" : "n"
        case 46: return caps ? "M" : "m"
        case 18: return caps ? "!" : "1"
        case 19: return caps ? "@" : "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 25: return "9"
        case 26: return "7"
        case 27: return caps ? "_" : "-"
        case 28: return "8"
        case 29: return "0"
        case 39: return caps ? "\"" : "'"
        case 44: return caps ? "?" : "/"
        case 47: return "."
        case 49: return " "
        default: return nil
        }
    }
    
    mutating func typeASCII(_ str: String) {
        let map: [Character: (Int, Int)] = [
            "a": (0, 0), "A": (0, 1), "s": (1, 0), "S": (1, 1), "d": (2, 0), "D": (2, 1),
            "f": (3, 0), "F": (3, 1), "h": (4, 0), "H": (4, 1), "g": (5, 0), "G": (5, 1),
            "z": (6, 0), "Z": (6, 1), "x": (7, 0), "X": (7, 1), "c": (8, 0), "C": (8, 1),
            "v": (9, 0), "V": (9, 1), "b": (11, 0), "B": (11, 1), "q": (12, 0), "Q": (12, 1),
            "w": (13, 0), "W": (13, 1), "e": (14, 0), "E": (14, 1), "r": (15, 0), "R": (15, 1),
            "y": (16, 0), "Y": (16, 1), "t": (17, 0), "T": (17, 1), "!": (18, 1), "1": (18, 0), "2": (19, 0),
            "@": (19, 1), "3": (20, 0), "4": (21, 0), "6": (22, 0), "5": (23, 0), "9": (25, 0),
            "7": (26, 0), "-": (27, 0), "_": (27, 1), "8": (28, 0), "0": (29, 0), "]": (30, 0),
            "o": (31, 0), "O": (31, 1), "u": (32, 0), "U": (32, 1), "[": (33, 0), "i": (34, 0),
            "I": (34, 1), "p": (35, 0), "P": (35, 1), "l": (37, 0), "L": (37, 1), "j": (38, 0),
            "J": (38, 1), "'": (39, 0), "\"": (39, 1), "k": (40, 0), "K": (40, 1), ";": (41, 0),
            ":": (41, 1), ",": (43, 0), "/": (44, 0), "?": (44, 1), "n": (45, 0), "N": (45, 1), "m": (46, 0),
            "M": (46, 1), ".": (47, 0), " ": (49, 0)
        ]
        let telexVnMap: [Character: String] = [
            "à": "af", "á": "as", "ả": "ar", "ã": "ax", "ạ": "aj",
            "ă": "aw", "ằ": "awf", "ắ": "aws", "ẳ": "awr", "ẵ": "awx", "ặ": "awj",
            "â": "aa", "ầ": "aaf", "ấ": "aas", "ẩ": "aar", "ẫ": "aax", "ậ": "aaj",
            "è": "ef", "é": "es", "ẻ": "er", "ẽ": "ex", "ẹ": "ej",
            "ê": "ee", "ề": "eef", "ế": "ees", "ể": "eer", "ễ": "eex", "ệ": "eej",
            "ì": "if", "í": "is", "ỉ": "ir", "ĩ": "ix", "ị": "ij",
            "ò": "of", "ó": "os", "ỏ": "or", "õ": "ox", "ọ": "oj",
            "ô": "oo", "ồ": "oof", "ố": "oos", "ổ": "oor", "ỗ": "oox", "ộ": "ooj",
            "ơ": "ow", "ờ": "owf", "ớ": "ows", "ở": "owr", "ỡ": "owx", "ợ": "owj",
            "ù": "uf", "ú": "us", "ủ": "ur", "ũ": "ux", "ụ": "uj",
            "ư": "uw", "ừ": "uwf", "ứ": "uws", "ử": "uwr", "ữ": "uwx", "ự": "uwj",
            "ỳ": "yf", "ý": "ys", "ỷ": "yr", "ỹ": "yx", "ỵ": "yj",
            "đ": "dd", "Đ": "Dd"
        ]
        for ch in str {
            if let telexSeq = telexVnMap[ch] {
                for tCh in telexSeq {
                    if let (code, caps) = map[tCh] {
                        typeKey(code, caps: caps)
                    }
                }
            } else if let (code, caps) = map[ch] {
                typeKey(code, caps: caps)
            }
        }
    }
}
