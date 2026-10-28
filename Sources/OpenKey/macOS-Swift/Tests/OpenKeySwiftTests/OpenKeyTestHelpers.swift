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
        case 27: return "-"
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
        case 47: return "."
        case 49: return " "
        default: return nil
        }
    }
}
