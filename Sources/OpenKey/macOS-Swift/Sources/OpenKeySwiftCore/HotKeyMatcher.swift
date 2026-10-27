import Foundation
import CoreGraphics

public struct HotKeyMatcher {
    public static let defaultHotKey: Int = 0x7A000206 // Option + Z
    public static let modifierOnlyCode: UInt8 = 0xFE
    
    public static func isModifierOnlyTap(config: Int) -> Bool {
        return UInt8(config & 0xFF) == modifierOnlyCode
    }
    
    public static func matches(keyCode: UInt16, flags: CGEventFlags, config: Int) -> Bool {
        let expectedKeyCode = UInt16(config & 0xFF)
        if expectedKeyCode == UInt16(modifierOnlyCode) {
            // Modifier only tap matching
            let hasCtrl = (config & 0x100) != 0
            let hasOpt = (config & 0x200) != 0
            let hasCmd = (config & 0x400) != 0
            let hasShift = (config & 0x800) != 0
            
            let ctrlPressed = flags.contains(.maskControl)
            let optPressed = flags.contains(.maskAlternate)
            let cmdPressed = flags.contains(.maskCommand)
            let shiftPressed = flags.contains(.maskShift)
            
            return (hasCtrl == ctrlPressed) && (hasOpt == optPressed) && (hasCmd == cmdPressed) && (hasShift == shiftPressed)
        }
        
        if keyCode != expectedKeyCode {
            return false
        }
        
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
    
    public static func describe(config: Int) -> String {
        var parts: [String] = []
        if (config & 0x100) != 0 { parts.append("⌃") }
        if (config & 0x200) != 0 { parts.append("⌥") }
        if (config & 0x800) != 0 { parts.append("⇧") }
        if (config & 0x400) != 0 { parts.append("⌘") }
        
        let code = UInt8(config & 0xFF)
        if code == modifierOnlyCode {
            parts.append("Tap")
        } else {
            let asciiChar = UInt8((config >> 24) & 0xFF)
            if asciiChar != 0 {
                let scalar = UnicodeScalar(asciiChar)
                parts.append(String(scalar).uppercased())
            } else {
                parts.append(String(format: "0x%02X", code))
            }
        }
        return parts.joined()
    }
}
