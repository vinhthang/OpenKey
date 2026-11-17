import Foundation
import CoreGraphics

public struct HotKeyMatcher {
    public static let defaultHotKey: Int = 0x7A000206 // Option + Z
    public static let modifierOnlyCode: UInt8 = 0xFE
    
    public static func isModifierOnlyTap(config: Int) -> Bool {
        return UInt8(config & 0xFF) == modifierOnlyCode
    }
    
    public static func modifiersMatch(flags: CGEventFlags, config: Int) -> Bool {
        let needCtrl = (config & 0x100) != 0
        let needOpt = (config & 0x200) != 0
        let needCmd = (config & 0x400) != 0
        let needShift = (config & 0x800) != 0
        
        let hasCtrl = flags.contains(.maskControl)
        let hasOpt = flags.contains(.maskAlternate)
        let hasCmd = flags.contains(.maskCommand)
        let hasShift = flags.contains(.maskShift)
        
        return (needCtrl == hasCtrl) && (needOpt == hasOpt) && (needCmd == hasCmd) && (needShift == hasShift)
    }
    
    public static func matches(keyCode: UInt16, flags: CGEventFlags, config: Int) -> Bool {
        let expectedKeyCode = UInt16(config & 0xFF)
        if expectedKeyCode == UInt16(modifierOnlyCode) {
            return modifiersMatch(flags: flags, config: config)
        }
        
        if keyCode != expectedKeyCode {
            return false
        }
        
        return modifiersMatch(flags: flags, config: config)
    }
    
    public static func encode(
        keyCode: UInt16,
        control: Bool,
        option: Bool,
        command: Bool,
        shift: Bool,
        beep: Bool = false,
        displayChar: UInt8 = 0
    ) -> Int {
        var result = Int(keyCode & 0xFF)
        if control { result |= 0x100 }
        if option { result |= 0x200 }
        if command { result |= 0x400 }
        if shift { result |= 0x800 }
        if beep { result |= 0x8000 }
        result |= (Int(displayChar) << 24)
        return result
    }
    
    private static let specialKeyNames: [UInt8: String] = [
        49: "Space",
        48: "⇥",
        36: "↩",
        76: "↩",
        51: "⌫",
        53: "⎋",
        115: "↖",
        119: "↘",
        116: "⇞",
        121: "⇟",
        117: "⌦",
        123: "←",
        124: "→",
        125: "↓",
        126: "↑",
        122: "F1",
        120: "F2",
        99: "F3",
        118: "F4",
        96: "F5",
        97: "F6",
        98: "F7",
        100: "F8",
        101: "F9",
        109: "F10",
        103: "F11",
        111: "F12",
        105: "F13",
        107: "F14",
        113: "F15",
        106: "F16",
        64: "F17",
        79: "F18",
        80: "F19",
        90: "F20"
    ]
    
    public static func describe(config: Int) -> String {
        var parts: [String] = []
        if (config & 0x100) != 0 { parts.append("⌃") }
        if (config & 0x200) != 0 { parts.append("⌥") }
        if (config & 0x800) != 0 { parts.append("⇧") }
        if (config & 0x400) != 0 { parts.append("⌘") }
        
        let code = UInt8(config & 0xFF)
        if code == modifierOnlyCode {
            parts.append("Tap")
        } else if let special = specialKeyNames[code] {
            parts.append(special)
        } else {
            let asciiChar = UInt8((config >> 24) & 0xFF)
            if asciiChar >= 0x21 && asciiChar <= 0x7E {
                let scalar = UnicodeScalar(asciiChar)
                parts.append(String(scalar).uppercased())
            } else {
                let mapped = keyCodeToCharacter(UInt32(code))
                if mapped >= 0x21 && mapped <= 0x7E, let scalar = UnicodeScalar(mapped) {
                    parts.append(String(scalar).uppercased())
                } else {
                    parts.append(String(format: "0x%02X", code))
                }
            }
        }
        return parts.joined()
    }
}
