import Foundation
import CoreGraphics
import ApplicationServices
import Testing
@testable import OpenKeySwiftCore

extension OKHookSnapshot {
    var utf16Array: [UInt16] {
        utf16Chars
    }
    
    var decodedString: String {
        return String(utf16CodeUnits: utf16Chars, count: utf16Chars.count)
    }
}

struct VirtualScreen {
    var text: String = ""
    
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

@Suite("OpenKeySwiftTests", .serialized)
struct OpenKeySwiftTests {
    
    init() {
        OKEngineInit()
        OKEngineResetSession()
    }
    
    // REQ-001, REQ-003: Telex syllable composition
    @Test("Telex syllable composition")
    func telexComposition() {
        OKEngineInit()
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1)
        defer {
            OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0)
        }
        
        // Test "tiengs" -> "tiếng"
        // Key codes: t=17, i=34, e=14, n=45, g=5, s=1
        _ = OKEngineHandleKeyEvent(17, 0, false) // t
        _ = OKEngineHandleKeyEvent(34, 0, false) // i
        _ = OKEngineHandleKeyEvent(14, 0, false) // e
        _ = OKEngineHandleKeyEvent(45, 0, false) // n
        _ = OKEngineHandleKeyEvent(5, 0, false)  // g
        let snapS = OKEngineHandleKeyEvent(1, 0, false)  // s (acute mark)
        
        #expect(snapS.code != 0, "Typing 's' in 'tieng' must trigger engine processing")
        #expect(snapS.backspaceCount >= 3, "Must send backspaces to replace syllable")
        #expect(snapS.decodedString.contains("ế") || snapS.decodedString.contains("é"), "Must output accented vowel: \(snapS.decodedString)")
        
        // Test "vieetj" -> "việt"
        OKEngineResetSession()
        // v=9, i=34, e=14, e=14, t=17, j=38
        _ = OKEngineHandleKeyEvent(9, 0, false)  // v
        _ = OKEngineHandleKeyEvent(34, 0, false) // i
        _ = OKEngineHandleKeyEvent(14, 0, false) // e
        _ = OKEngineHandleKeyEvent(14, 0, false) // e -> ê
        _ = OKEngineHandleKeyEvent(17, 0, false) // t
        let snapJ = OKEngineHandleKeyEvent(38, 0, false) // j -> dot below
        
        #expect(snapJ.code != 0, "Typing 'j' in 'vieet' must trigger tone processing")
        #expect(snapJ.decodedString.contains("ệ"), "Must output 'ệ': \(snapJ.decodedString)")
    }
    
    // REQ-003: VNI syllable composition
    @Test("VNI syllable composition")
    func vniComposition() {
        OKEngineInit()
        OKEngineResetSession()
        OKEngineSyncConfig(1, 1, 1, 1, 1, 1, 1)
        
        // Test "vie6t5" -> "việt" in VNI
        // v=9, i=34, e=14, 6=22, t=17, 5=23
        _ = OKEngineHandleKeyEvent(9, 0, false)  // v
        _ = OKEngineHandleKeyEvent(34, 0, false) // i
        _ = OKEngineHandleKeyEvent(14, 0, false) // e
        let snap6 = OKEngineHandleKeyEvent(22, 0, false) // 6 -> circumflex
        #expect(snap6.code != 0, "Typing '6' after 'e' in VNI must add circumflex")
        _ = OKEngineHandleKeyEvent(17, 0, false) // t
        let snap5 = OKEngineHandleKeyEvent(23, 0, false) // 5 -> nặng
        #expect(snap5.code != 0, "Typing '5' in VNI on 'viet' must add dot below")
        #expect(snap5.backspaceCount >= 2, "Must send backspaces to replace vowel with tone")
        #expect(snap5.decodedString.contains("ệ"), "Must output 'ệ': \(snap5.decodedString)")
    }
    
    // REQ-003: Spelling check & auto-restore on invalid English words
    @Test("Spelling check and auto-restore")
    func spellingCheckAndAutoRestore() {
        OKEngineInit()
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1)
        defer {
            OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0)
        }
        
        // Type English word "window"
        // w=13, i=34, n=45, d=2, o=31, w=13
        _ = OKEngineHandleKeyEvent(13, 0, false) // w
        _ = OKEngineHandleKeyEvent(34, 0, false) // i
        _ = OKEngineHandleKeyEvent(45, 0, false) // n
        _ = OKEngineHandleKeyEvent(2, 0, false)  // d
        _ = OKEngineHandleKeyEvent(31, 0, false) // o
        _ = OKEngineHandleKeyEvent(13, 0, false) // w
        
        // Space keycode: 49
        let spaceSnap = OKEngineHandleKeyEvent(49, 0, false)
        #expect(spaceSnap.code == 0 || spaceSnap.code == 2 || spaceSnap.code == 3 || spaceSnap.code == 5,
                "Word break or restore should execute cleanly on invalid Vietnamese word")
        for cu in spaceSnap.utf16Array {
            #expect(cu <= 0x7F, "Auto-restored ASCII characters must be valid ASCII code units (< 128)")
        }
    }
    
    // REQ-005: Bounds-checked deserialization in OKInitSmartSwitchKey
    @Test("Bounds-checked deserialization on truncated buffers")
    func boundsCheckedDeserialization() {
        // Corrupted SmartSwitchKey buffer: declared count = 5, but buffer truncated
        let corruptedSmartData: [UInt8] = [0x05, 0x00, 0x0A, 0x63, 0x6F]
        corruptedSmartData.withUnsafeBufferPointer { ptr in
            OKInitSmartSwitchKey(ptr.baseAddress, Int32(ptr.count))
        }
        
        // Null / zero size
        OKInitSmartSwitchKey(nil, 0)
        OKInitSmartSwitchKey(nil, 1)
        
        OKEngineResetSession()
    }
    
    // REQ-005: Per-app smart switch state persistence and lookup
    @Test("SmartSwitchKey persistence and lookup")
    func smartSwitchKeyPersistenceAndLookup() {
        let bundleTerminal = "com.apple.Terminal"
        let bundleNotes = "com.apple.Notes"
        
        OKSetAppInputMethodStatus(bundleTerminal, 0) // English
        OKSetAppInputMethodStatus(bundleNotes, 1)    // Vietnamese
        
        #expect(OKGetAppInputMethodStatus(bundleTerminal, 1) == 0, "Terminal should be English (0)")
        #expect(OKGetAppInputMethodStatus(bundleNotes, 0) == 1, "Notes should be Vietnamese (1)")
        #expect(OKGetAppInputMethodStatus("com.unknown.app", 1) == -1, "Unknown app should return -1")
    }
    
    // REQ-007: Default Option + Z (0x7A000206) and custom modifier-tap (0xFE) hotkey matching
    @Test("HotKeyMatcher default and custom patterns")
    func hotKeyMatcher() {
        let defaultShortcut = HotKeyMatcher.defaultHotKey // 0x7A000206 (Option + Z)
        
        // ANSI Z keycode = 6
        #expect(HotKeyMatcher.matches(keyCode: 6, flags: .maskAlternate, config: defaultShortcut))
        #expect(!HotKeyMatcher.matches(keyCode: 6, flags: [.maskAlternate, .maskShift], config: defaultShortcut))
        #expect(!HotKeyMatcher.matches(keyCode: 7, flags: .maskAlternate, config: defaultShortcut))
        #expect(!HotKeyMatcher.matches(keyCode: 6, flags: .maskCommand, config: defaultShortcut))
        
        // Custom modifier-tap (0xFE)
        let modifierTapConfig = HotKeyMatcher.encode(keyCode: 0xFE, control: true, option: false, command: false, shift: false)
        #expect(HotKeyMatcher.isModifierOnlyTap(config: modifierTapConfig))
        #expect(HotKeyMatcher.matches(keyCode: 0, flags: .maskControl, config: modifierTapConfig))
        #expect(!HotKeyMatcher.matches(keyCode: 0, flags: .maskAlternate, config: modifierTapConfig))
        
        // Description
        let desc = HotKeyMatcher.describe(config: defaultShortcut)
        #expect(desc.contains("⌥") && desc.contains("Z"))
    }
    
    // Task 6: Terminal App Detection (expanded with VM & Remote Desktop clients)
    @Test("Terminal app detection")
    func terminalAppDetection() {
        let terminals = [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "dev.warp.Warp-Stable",
            "dev.warp.Warp",
            "com.mitchellh.ghostty",
            "org.alacritty",
            "io.alacritty",
            "net.kovidgoyal.kitty",
            "co.zeit.hyper",
            "com.github.wez.wezterm",
            // VMs / Remote Desktop
            "com.vmware.fusion",
            "com.parallels.desktop.console",
            "com.microsoft.rdc.macos",
            "org.virtualbox.app.VirtualBoxVM",
            "com.utmapp.UTM"
        ]
        for term in terminals {
            #expect(EventTapCoordinator.isTerminalApp(bundleId: term), "Expected \(term) to be recognized as terminal app")
        }
        #expect(!EventTapCoordinator.isTerminalApp(bundleId: "com.apple.Notes"))
        #expect(!EventTapCoordinator.isTerminalApp(bundleId: "com.google.Chrome"))
        #expect(!EventTapCoordinator.isTerminalApp(bundleId: nil))
    }
    
    // REQ-004: KeystrokeInjector replacement strategy selection (including Sublime Text U+200C and extCode=4)
    @Test("KeystrokeInjector replacement strategies")
    func keystrokeInjectorReplacementStrategies() {
        // Standard browser fix with U+202F
        let breaker = KeystrokeInjector.determineStrategy(backspaceCount: 2, fixRecommendBrowser: true, bundleId: "com.google.Chrome", extCode: 0)
        #expect(breaker == .emptyCharBreaker(emptyChar: 0x202F))
        
        // Sublime Text fix with U+200C
        let sublimeBreaker = KeystrokeInjector.determineStrategy(backspaceCount: 2, fixRecommendBrowser: true, bundleId: "com.sublimetext.4", extCode: 0)
        #expect(sublimeBreaker == .emptyCharBreaker(emptyChar: 0x200C))
        
        // extCode == 4 forces standard backspace
        let extCodeBreaker = KeystrokeInjector.determineStrategy(backspaceCount: 2, fixRecommendBrowser: true, bundleId: "com.google.Chrome", extCode: 4)
        #expect(extCodeBreaker == .standardBackspace)
        
        // Zero backspace
        let zeroBreaker = KeystrokeInjector.determineStrategy(backspaceCount: 0, fixRecommendBrowser: true)
        #expect(zeroBreaker == .standardBackspace)
        
        // fixRecommendBrowser disabled
        let standard = KeystrokeInjector.determineStrategy(backspaceCount: 2, fixRecommendBrowser: false)
        #expect(standard == .standardBackspace)
    }
    
    // REQ-006: InputSourceGuard compatibility check and repeated invocation safety
    @Test("InputSourceGuard repeated invocation safety")
    func inputSourceGuardSafety() {
        for _ in 0..<100 {
            _ = InputSourceGuard.isEnglishCurrentInputSource()
            _ = InputSourceGuard.isVietnameseProcessingAllowed(otherLanguageEnabled: true)
            _ = InputSourceGuard.isVietnameseProcessingAllowed(otherLanguageEnabled: false)
        }
        
        // Pure compatibility checks
        #expect(InputSourceGuard.isCompatibleInputSource(language: "en", inputSourceID: "com.apple.keylayout.US"))
        #expect(InputSourceGuard.isCompatibleInputSource(language: "en-US", inputSourceID: "com.apple.keylayout.ABC"))
        #expect(!InputSourceGuard.isCompatibleInputSource(language: "en", inputSourceID: "com.apple.keylayout.Dvorak"))
        #expect(!InputSourceGuard.isCompatibleInputSource(language: "en", inputSourceID: "com.apple.keylayout.Colemak"))
        #expect(!InputSourceGuard.isCompatibleInputSource(language: "fr", inputSourceID: "com.apple.keylayout.French-AZERTY"))
        #expect(!InputSourceGuard.isCompatibleInputSource(language: "de", inputSourceID: "com.apple.keylayout.German"))
    }
    
    // REQ-008, Task 6: OpenKeySettingsStore persistence, clamping, and smart switch
    @Test("OpenKeySettingsStore persistence and sync")
    func openKeySettingsStoreSync() {
        let store = OpenKeySettingsStore.shared
        
        store.language = 1
        #expect(store.language == 1)
        
        store.inputType = 1 // VNI
        #expect(store.inputType == 1)
        
        // Clamps inputType strictly to 0 (Telex) or 1 (VNI); setting 2 or 3 clamps to 0
        store.inputType = 2
        #expect(store.inputType == 0, "Setting inputType 2 should clamp to 0 (Telex)")
        store.inputType = 3
        #expect(store.inputType == 0, "Setting inputType 3 should clamp to 0 (Telex)")
        store.inputType = 1
        #expect(store.inputType == 1)
        
        // Defaults useSmartSwitchKey to true
        #expect(store.useSmartSwitchKey == true, "useSmartSwitchKey must default to true")
        
        let testBundle = "com.apple.TextEdit"
        store.activeAppBundleId = testBundle
        
        final class CallbackTracker: @unchecked Sendable {
            var invoked = false
        }
        let tracker = CallbackTracker()
        store.onLanguageChanged = { [tracker] _ in
            tracker.invoked = true
        }
        
        store.language = 0 // Manually set to English
        #expect(tracker.invoked, "onLanguageChanged callback must fire")
        #expect(OKGetAppInputMethodStatus(testBundle, 1) == 0, "Manual switch to English must save status 0 for active app")
        
        // Toggle language
        store.toggleLanguage()
        #expect(store.language == 1, "Toggling from English (0) should yield Vietnamese (1)")
        #expect(OKGetAppInputMethodStatus(testBundle, 0) == 1, "Toggling to Vietnamese must save status 1 for active app")
        
        store.toggleLanguage()
        #expect(store.language == 0, "Toggling from Vietnamese (1) should yield English (0)")
        #expect(OKGetAppInputMethodStatus(testBundle, 1) == 0, "Toggling back to English must save status 0 for active app")
        
        // Toggle smart switch
        store.useSmartSwitchKey = false
        #expect(!store.useSmartSwitchKey)
        store.useSmartSwitchKey = true
        #expect(store.useSmartSwitchKey)
        
        store.switchKeyStatus = OpenKeySettingsStore.defaultSwitchKey
        #expect(store.switchKeyStatus == 0x7A000206)
    }
    
    // REQ-001, REQ-002: Bundle Info.plist and executable contract
    @Test("Bundle Info.plist and executable contract")
    func bundleInfoPlistAndExecutableContract() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let packageDir = testFileURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let infoPlistURL = packageDir.appendingPathComponent("Info.plist")
        
        let data = try Data(contentsOf: infoPlistURL)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        
        #expect(plist != nil, "Info.plist must be valid property list")
        let executableName = plist?["CFBundleExecutable"] as? String
        #expect(executableName == "OpenKeySwift", "CFBundleExecutable must be 'OpenKeySwift'")
        let minSysVersion = plist?["LSMinimumSystemVersion"] as? String
        #expect(minSysVersion == "26.0", "LSMinimumSystemVersion must be '26.0'")
    }
    
    // REQ-004: KeystrokeInjector self-event tagging and private CGEventSource
    @Test("KeystrokeInjector self-event tagging and source state")
    func keystrokeInjectorSelfEventTagging() {
        #expect(KeystrokeInjector.eventSourceUserData == 0xBEEF)
        #expect(KeystrokeInjector.shared.sourceStateID == .privateState)
    }
    
    // REQ-011: Pure testable event routing pipeline (evaluateKeyEvent)
    @Test("Pure Event Routing Pipeline evaluateKeyEvent")
    func evaluateKeyEventPipeline() {
        let coordinator = EventTapCoordinator.shared
        
        // 1. Self event passes through without resetting session
        var ctx = KeyEventContext(eventType: .keyDown, keyCode: 6, isSelfEvent: true)
        #expect(coordinator.evaluateKeyEvent(ctx) == .passThrough(resetSession: false))
        
        // 2. Mouse events pass through and reset session
        ctx = KeyEventContext(eventType: .leftMouseDown, keyCode: 0)
        #expect(coordinator.evaluateKeyEvent(ctx) == .passThrough(resetSession: true))
        
        // 3. Regular hotkey keyDown toggles language
        ctx = KeyEventContext(eventType: .keyDown, keyCode: 6, flags: .maskAlternate, language: 1)
        #expect(coordinator.evaluateKeyEvent(ctx) == .toggleLanguage(newLanguage: 0))
        
        // 4. Hotkey auto-repeat swallows without toggling
        ctx = KeyEventContext(eventType: .keyDown, keyCode: 6, flags: .maskAlternate, isAutoRepeat: true, language: 1)
        #expect(coordinator.evaluateKeyEvent(ctx) == .swallow)
        
        // 5. Hotkey keyUp swallows
        ctx = KeyEventContext(eventType: .keyUp, keyCode: 6, flags: .maskAlternate)
        #expect(coordinator.evaluateKeyEvent(ctx) == .swallow)
        
        // 6. Command/Control/Option shortcuts bypass and reset session
        ctx = KeyEventContext(eventType: .keyDown, keyCode: 48, flags: .maskCommand) // Cmd + Tab
        #expect(coordinator.evaluateKeyEvent(ctx) == .passThrough(resetSession: true))
        
        // 7. English mode fast path returns immediately without resetting session
        ctx = KeyEventContext(eventType: .keyDown, keyCode: 1, language: 0)
        #expect(coordinator.evaluateKeyEvent(ctx) == .passThrough(resetSession: false))
        
        // 8. Terminal app bypass
        ctx = KeyEventContext(eventType: .keyDown, keyCode: 1, language: 1, activeAppBundleId: "com.apple.Terminal")
        #expect(coordinator.evaluateKeyEvent(ctx) == .passThrough(resetSession: true))
        
        // 9. Spotlight overlay bypass
        ctx = KeyEventContext(eventType: .keyDown, keyCode: 1, language: 1, isSpotlightVisible: true)
        #expect(coordinator.evaluateKeyEvent(ctx) == .passThrough(resetSession: true))
        
        // 10. Incompatible layout bypass (Dvorak/AZERTY/etc.)
        ctx = KeyEventContext(eventType: .keyDown, keyCode: 1, language: 1, otherLanguage: true, isCompatibleInputSource: false)
        #expect(coordinator.evaluateKeyEvent(ctx) == .passThrough(resetSession: true))
        
        // 11. Engine composition in Vietnamese mode
        OKEngineInit()
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1)
        defer {
            OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0)
        }
        // Type 'a' (keyCode 0) then 'a' (keyCode 0) -> â
        _ = coordinator.evaluateKeyEvent(KeyEventContext(eventType: .keyDown, keyCode: 0, language: 1))
        let replaceAction = coordinator.evaluateKeyEvent(KeyEventContext(eventType: .keyDown, keyCode: 0, language: 1))
        switch replaceAction {
        case .replaceKeystroke(let backspaces, let chars, _, _):
            #expect(backspaces >= 1)
            #expect(!chars.isEmpty)
        default:
            Issue.record("Expected .replaceKeystroke for 'aa' -> 'â', got \(replaceAction)")
        }
    }
    
    @Test("Pure Swift Engine Phonotactic Parity and Complex Syllables")
    func pureSwiftEnginePhonotacticParity() {
        OKEngineInit()
        
        // 1. "truong" Telex composition: t r u o w n g f -> trường
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1)
        _ = OKEngineHandleKeyEvent(17, 0, false) // t
        _ = OKEngineHandleKeyEvent(15, 0, false) // r
        _ = OKEngineHandleKeyEvent(32, 0, false) // u
        _ = OKEngineHandleKeyEvent(31, 0, false) // o
        let snapW = OKEngineHandleKeyEvent(13, 0, false) // w -> ươ
        #expect(snapW.code == HookCodeState.willProcess)
        #expect(snapW.backspaceCount >= 1)
        _ = OKEngineHandleKeyEvent(45, 0, false) // n
        _ = OKEngineHandleKeyEvent(5, 0, false)  // g
        let snapTruong = OKEngineHandleKeyEvent(3, 0, false) // f -> grave mark
        #expect(snapTruong.code == HookCodeState.willProcess)
        #expect(snapTruong.decodedString.contains("ườ"))
        
        // 2. "nghieng" Telex: n g h i e e n g -> nghiêng
        OKEngineResetSession()
        _ = OKEngineHandleKeyEvent(45, 0, false) // n
        _ = OKEngineHandleKeyEvent(5, 0, false)  // g
        _ = OKEngineHandleKeyEvent(4, 0, false)  // h
        _ = OKEngineHandleKeyEvent(34, 0, false) // i
        _ = OKEngineHandleKeyEvent(14, 0, false) // e
        let snapEE = OKEngineHandleKeyEvent(14, 0, false) // e -> ê
        #expect(snapEE.code == HookCodeState.willProcess)
        #expect(snapEE.decodedString.contains("ê"))
        
        // 3. "quoc" Telex: q u o c s -> quốc
        OKEngineResetSession()
        _ = OKEngineHandleKeyEvent(12, 0, false) // q
        _ = OKEngineHandleKeyEvent(32, 0, false) // u
        _ = OKEngineHandleKeyEvent(31, 0, false) // o
        _ = OKEngineHandleKeyEvent(8, 0, false)  // c
        let snapQuoc = OKEngineHandleKeyEvent(1, 0, false) // s -> sắc
        #expect(snapQuoc.code == HookCodeState.willProcess)
        #expect(snapQuoc.decodedString.contains("ố") || snapQuoc.decodedString.contains("ó"))
        
        // 4. "giu" Telex: g i u x -> giữ
        OKEngineResetSession()
        _ = OKEngineHandleKeyEvent(5, 0, false)  // g
        _ = OKEngineHandleKeyEvent(34, 0, false) // i
        _ = OKEngineHandleKeyEvent(32, 0, false) // u
        let snapGiu = OKEngineHandleKeyEvent(7, 0, false) // x -> ngã
        #expect(snapGiu.code == HookCodeState.willProcess)
        #expect(snapGiu.decodedString.contains("ữ") || snapGiu.decodedString.contains("ũ"))
        
        // 5. Modern vs Old Orthography ("oa" + f)
        // Modern: vUseModernOrthography = 1 -> oà
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1)
        _ = OKEngineHandleKeyEvent(31, 0, false) // o
        _ = OKEngineHandleKeyEvent(0, 0, false)  // a
        let snapModernOa = OKEngineHandleKeyEvent(3, 0, false) // f
        #expect(snapModernOa.code == HookCodeState.willProcess)
        #expect(snapModernOa.decodedString.contains("à"))
        
        // Old: vUseModernOrthography = 0 -> òa
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 0, 1, 1, 1)
        _ = OKEngineHandleKeyEvent(31, 0, false) // o
        _ = OKEngineHandleKeyEvent(0, 0, false)  // a
        let snapOldOa = OKEngineHandleKeyEvent(3, 0, false) // f
        #expect(snapOldOa.code == HookCodeState.willProcess)
        #expect(snapOldOa.decodedString.contains("ò"))
        
        // 6. d/D -> đ/Đ
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1)
        _ = OKEngineHandleKeyEvent(2, 0, false) // d
        let snapLowerD = OKEngineHandleKeyEvent(2, 0, false) // d -> đ
        #expect(snapLowerD.code == HookCodeState.willProcess)
        #expect(snapLowerD.decodedString.contains("đ"))
        
        OKEngineResetSession()
        _ = OKEngineHandleKeyEvent(2, 1, false) // D (caps=1)
        let snapUpperD = OKEngineHandleKeyEvent(2, 1, false) // D -> Đ
        #expect(snapUpperD.code == HookCodeState.willProcess)
        #expect(snapUpperD.decodedString.contains("Đ"))
        
        // 7. Standalone w -> ư, ww -> w
        OKEngineResetSession()
        let snapW1 = OKEngineHandleKeyEvent(13, 0, false) // w alone
        #expect(snapW1.code == HookCodeState.willProcess)
        #expect(snapW1.decodedString.contains("ư"))
        let snapW2 = OKEngineHandleKeyEvent(13, 0, false) // second w -> restore to w
        #expect(snapW2.code == HookCodeState.willProcess || snapW2.code == HookCodeState.restore)
        #expect(snapW2.decodedString.contains("w"))
        
        // 8. Standalone [[ -> [
        OKEngineResetSession()
        let snapBracket1 = OKEngineHandleKeyEvent(33, 0, false) // [ alone -> ơ
        #expect(snapBracket1.code == HookCodeState.willProcess)
        #expect(snapBracket1.decodedString.contains("ơ"))
        let snapBracket2 = OKEngineHandleKeyEvent(33, 0, false) // second [ -> restore [
        #expect(snapBracket2.code == HookCodeState.willProcess || snapBracket2.code == HookCodeState.restore)
        #expect(snapBracket2.decodedString.contains("["))
        
        // 9. Backspace Grammar Re-evaluation
        OKEngineResetSession()
        _ = OKEngineHandleKeyEvent(17, 0, false) // t
        _ = OKEngineHandleKeyEvent(14, 0, false) // e
        _ = OKEngineHandleKeyEvent(14, 0, false) // e -> ê
        _ = OKEngineHandleKeyEvent(17, 0, false) // t
        let snapDel = OKEngineHandleKeyEvent(51, 0, false) // delete key (backspace)
        #expect(snapDel.extCode == 2)
        
        // 10. Space Word Restore on Backspace
        OKEngineResetSession()
        _ = OKEngineHandleKeyEvent(17, 0, false) // t
        _ = OKEngineHandleKeyEvent(34, 0, false) // i
        _ = OKEngineHandleKeyEvent(49, 0, false) // space
        let snapSpaceDel = OKEngineHandleKeyEvent(51, 0, false) // backspace over space
        #expect(snapSpaceDel.extCode == 2)
        
        // 11. Invalid Spelling Auto-Restore (window -> restore on wrong letter)
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1)
        _ = OKEngineHandleKeyEvent(13, 0, false) // w -> ư
        _ = OKEngineHandleKeyEvent(34, 0, false) // i
        _ = OKEngineHandleKeyEvent(45, 0, false) // n
        _ = OKEngineHandleKeyEvent(2, 0, false)  // d
        _ = OKEngineHandleKeyEvent(31, 0, false) // o
        let snapRestore = OKEngineHandleKeyEvent(49, 0, false) // space terminates word
        #expect(snapRestore.code == HookCodeState.doNothing || snapRestore.code == HookCodeState.restore)
        
        // 12. Conversion Provenance Attribution Metadata (REQ-015)
        #if canImport(AppKit)
        let plistPath = Bundle.main.bundleURL.appendingPathComponent("Contents/Info.plist").path
        if FileManager.default.fileExists(atPath: plistPath),
           let dict = NSDictionary(contentsOfFile: plistPath) as? [String: Any],
           let copyright = dict["NSHumanReadableCopyright"] as? String {
            #expect(copyright.contains("Pure Swift 6"))
            #expect(copyright.contains("Mai Vũ Tuyên"))
        }
        #endif
    }
    
    // REQ-002: Phonotactic syllable repair (ie/ye + consonant -> iê/yê, uow -> ươ)
    @Test("REQ-002: Phonotactic syllable repair")
    func phonotacticSyllableRepair() {
        OKEngineInit()
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1) // Enable AutoWording & GrammarRepair
        
        // 1. "tiengs" -> "tiếng"
        // t=17, i=34, e=14, n=45, g=5, s=1
        var screen = VirtualScreen()
        screen.typeKey(17) // t
        screen.typeKey(34) // i
        screen.typeKey(14) // e
        screen.typeKey(45) // n
        screen.typeKey(5)  // g
        let snapS = screen.typeKey(1) // s
        #expect(snapS.code == HookCodeState.willProcess, "Must process tone mark with repaired iê")
        #expect(snapS.backspaceCount == 4, "snapS.backspaceCount must be 4, got \(snapS.backspaceCount)")
        #expect(snapS.newCharCount == 4, "snapS.newCharCount must be 4, got \(snapS.newCharCount)")
        #expect(screen.text == "tiếng", "Screen buffer must be 'tiếng', got '\(screen.text)'")
        #expect(snapS.decodedString.contains("ế") || snapS.decodedString.contains("tiếng"), "Output must contain 'ế': \(snapS.decodedString)")
        
        // 2. "viets" -> "viết"
        // v=9, i=34, e=14, t=17, s=1
        OKEngineResetSession()
        _ = OKEngineHandleKeyEvent(9, 0, false)
        _ = OKEngineHandleKeyEvent(34, 0, false)
        _ = OKEngineHandleKeyEvent(14, 0, false)
        _ = OKEngineHandleKeyEvent(17, 0, false)
        let snapViet = OKEngineHandleKeyEvent(1, 0, false)
        #expect(snapViet.code == HookCodeState.willProcess)
        #expect(snapViet.decodedString.contains("ế") || snapViet.decodedString.contains("viết"), "Output must contain 'ế': \(snapViet.decodedString)")
        
        // 3. "nghiengf" -> "nghiềng"
        // n=45, g=5, h=4, i=34, e=14, n=45, g=5, f=3
        OKEngineResetSession()
        _ = OKEngineHandleKeyEvent(45, 0, false)
        _ = OKEngineHandleKeyEvent(5, 0, false)
        _ = OKEngineHandleKeyEvent(4, 0, false)
        _ = OKEngineHandleKeyEvent(34, 0, false)
        _ = OKEngineHandleKeyEvent(14, 0, false)
        _ = OKEngineHandleKeyEvent(45, 0, false)
        _ = OKEngineHandleKeyEvent(5, 0, false)
        let snapNghieng = OKEngineHandleKeyEvent(3, 0, false)
        #expect(snapNghieng.code == HookCodeState.willProcess)
        #expect(snapNghieng.decodedString.contains("ề") || snapNghieng.decodedString.contains("nghiềng"))
        
        // 4. "truowngf" -> "trường"
        // t=17, r=15, u=32, o=31, w=13, n=45, g=5, f=3
        OKEngineResetSession()
        _ = OKEngineHandleKeyEvent(17, 0, false)
        _ = OKEngineHandleKeyEvent(15, 0, false)
        _ = OKEngineHandleKeyEvent(32, 0, false)
        _ = OKEngineHandleKeyEvent(31, 0, false)
        _ = OKEngineHandleKeyEvent(13, 0, false)
        _ = OKEngineHandleKeyEvent(45, 0, false)
        _ = OKEngineHandleKeyEvent(5, 0, false)
        let snapTruong = OKEngineHandleKeyEvent(3, 0, false)
        #expect(snapTruong.code == HookCodeState.willProcess)
        #expect(snapTruong.decodedString.contains("ườ") || snapTruong.decodedString.contains("trường"))
        
        // 5. When grammarRepairEnabled == 0: repair must not trigger
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 1, 0, 1, 1) // grammarRepairEnabled = 0
        _ = OKEngineHandleKeyEvent(17, 0, false)
        _ = OKEngineHandleKeyEvent(34, 0, false)
        _ = OKEngineHandleKeyEvent(14, 0, false)
        _ = OKEngineHandleKeyEvent(45, 0, false)
        _ = OKEngineHandleKeyEvent(5, 0, false)
        let snapDisabled = OKEngineHandleKeyEvent(1, 0, false)
        #expect(!snapDisabled.decodedString.contains("ế"), "Must not promote ie to iê when grammarRepairEnabled is false")
        
        // Restore default opt-in config (disabled by default)
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0)
    }
    
    // REQ-003: Vietnamese shorthand auto-expansion on Space
    @Test("REQ-003: Shorthand auto-expansion on Space")
    func shorthandAutoExpansionOnSpace() {
        OKEngineInit()
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1)
        
        // 1. "ko " -> "không "
        // k=40, o=31, space=49
        _ = OKEngineHandleKeyEvent(40, 0, false)
        _ = OKEngineHandleKeyEvent(31, 0, false)
        let snapKo = OKEngineHandleKeyEvent(49, 0, false)
        #expect(snapKo.code == HookCodeState.willProcess)
        #expect(snapKo.backspaceCount == 2)
        #expect(snapKo.decodedString == "không ")
        
        // 2. "dc " -> "được "
        // d=2, c=8, space=49
        OKEngineResetSession()
        _ = OKEngineHandleKeyEvent(2, 0, false)
        _ = OKEngineHandleKeyEvent(8, 0, false)
        let snapDc = OKEngineHandleKeyEvent(49, 0, false)
        #expect(snapDc.code == HookCodeState.willProcess)
        #expect(snapDc.backspaceCount == 2)
        #expect(snapDc.decodedString == "được ")
        
        // 3. Capitalization preservation: "Ko " -> "Không "
        OKEngineResetSession()
        _ = OKEngineHandleKeyEvent(40, 1, false) // K (caps=1)
        _ = OKEngineHandleKeyEvent(31, 0, false) // o
        let snapTitleKo = OKEngineHandleKeyEvent(49, 0, false)
        #expect(snapTitleKo.code == HookCodeState.willProcess)
        #expect(snapTitleKo.decodedString == "Không ")
        
        // 4. All-caps preservation: "KO " -> "KHÔNG "
        OKEngineResetSession()
        _ = OKEngineHandleKeyEvent(40, 1, false) // K
        _ = OKEngineHandleKeyEvent(31, 1, false) // O
        let snapAllKo = OKEngineHandleKeyEvent(49, 0, false)
        #expect(snapAllKo.code == HookCodeState.willProcess)
        #expect(snapAllKo.decodedString == "KHÔNG ")
        
        // 5. Proper noun: "vn " -> "Việt Nam "
        // v=9, n=45, space=49
        OKEngineResetSession()
        _ = OKEngineHandleKeyEvent(9, 0, false)
        _ = OKEngineHandleKeyEvent(45, 0, false)
        let snapVn = OKEngineHandleKeyEvent(49, 0, false)
        #expect(snapVn.code == HookCodeState.willProcess)
        #expect(snapVn.decodedString == "Việt Nam ")
        
        // 6. When shorthandExpansionEnabled == 0: no expansion on Space
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 1, 1, 0, 1) // shorthandExpansionEnabled = 0
        _ = OKEngineHandleKeyEvent(40, 0, false) // k
        _ = OKEngineHandleKeyEvent(31, 0, false) // o
        let snapNoExpand = OKEngineHandleKeyEvent(49, 0, false)
        #expect(snapNoExpand.decodedString != "không ", "Shorthand expansion must not trigger when disabled")
        
        // Restore default opt-in config (disabled by default)
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0)
    }
    
    // REQ-004: Multi-thousand-word dictionary & candidate generation
    @Test("REQ-004: Multi-thousand-word dictionary and candidate generation")
    func dictionaryAndCandidateGeneration() {
        let dict = VietnameseDictionary.shared
        
        // 1. Vocabulary scale guarantees
        #expect(dict.syllableCount >= 3500, "Dictionary must contain >= 3,500 valid syllables: \(dict.syllableCount)")
        #expect(dict.compoundCount >= 1500, "Dictionary must contain >= 1,500 compound pairs: \(dict.compoundCount)")
        #expect(dict.totalEntries >= 5000, "Total entries must be >= 5,000: \(dict.totalEntries)")
        
        // 2. Transposed keystroke corrections (O(1) signature index)
        let engine = AutoWordingEngine.shared
        engine.isEnabled = true
        engine.candidateSuggestionsEnabled = true
        defer {
            engine.isEnabled = false
            engine.candidateSuggestionsEnabled = false
        }
        let cTineg = engine.computeCurrentWordCandidates(rawStem: "tineg", currentSyllable: "")
        #expect(cTineg.map(\.text).contains("tiếng"), "Transposed 'tineg' must suggest 'tiếng'")
        
        let cVeit = engine.computeCurrentWordCandidates(rawStem: "veit", currentSyllable: "")
        #expect(cVeit.map(\.text).contains("việt"), "Transposed 'veit' must suggest 'việt'")
        
        let cNgheing = engine.computeCurrentWordCandidates(rawStem: "ngheing", currentSyllable: "")
        #expect(cNgheing.map(\.text).contains("nghiêng"), "Transposed 'ngheing' must suggest 'nghiêng'")
        
        let cThanh = engine.computeCurrentWordCandidates(rawStem: "thanh", currentSyllable: "")
        #expect(cThanh.map(\.text).contains("thành"), "Stem 'thanh' must suggest 'thành'")
        
        let cDuoc = engine.computeCurrentWordCandidates(rawStem: "duoc", currentSyllable: "")
        #expect(cDuoc.map(\.text).contains("được"), "Stem 'duoc' must suggest 'được'")
        
        // 3. Compound next-word predictions after Space
        let nThanh = engine.computeNextWordCandidates(previousWord: "thành")
        #expect(nThanh.map(\.text).contains("phố"), "'thành' must predict 'phố'")
        
        let nNghien = engine.computeNextWordCandidates(previousWord: "nghiên")
        #expect(nNghien.map(\.text).contains("cứu"), "'nghiên' must predict 'cứu'")
        
        let nPhat = engine.computeNextWordCandidates(previousWord: "phát")
        #expect(nPhat.map(\.text).contains("triển"), "'phát' must predict 'triển'")
        
        let nCong = engine.computeNextWordCandidates(previousWord: "công")
        #expect(nCong.map(\.text).contains("nghệ") || nCong.map(\.text).contains("việc"), "'công' must predict 'nghệ' or 'việc'")
    }
    
    // REQ-005: Keyboard candidate selection (Tab, Ctrl+1..3, Esc)
    @Test("REQ-005: Candidate selection keyboard routing Tab, Ctrl+1..3, Esc")
    func candidateKeyboardRouting() {
        let coordinator = EventTapCoordinator.shared
        let candidates = [
            WordCandidate(id: 0, text: "tiếng", kind: .correction, replaceLength: 5),
            WordCandidate(id: 1, text: "tiêng", kind: .correction, replaceLength: 5),
            WordCandidate(id: 2, text: "tiện", kind: .correction, replaceLength: 5)
        ]
        
        // 1. Tab (keyCode: 48) accepts candidate #1
        let ctxTab = KeyEventContext(
            eventType: .keyDown,
            keyCode: 48,
            flags: [],
            language: 1,
            autoWordingEnabled: true,
            candidateSuggestionsEnabled: true,
            activeCandidates: candidates
        )
        let actionTab = coordinator.evaluateKeyEvent(ctxTab)
        #expect(actionTab == .acceptCandidate(candidates[0]), "Tab must accept candidate #1")
        
        // 2. Control + 2 (keyCode: 19) accepts candidate #2
        let ctxCtrl2 = KeyEventContext(
            eventType: .keyDown,
            keyCode: 19,
            flags: [.maskControl],
            language: 1,
            autoWordingEnabled: true,
            candidateSuggestionsEnabled: true,
            activeCandidates: candidates
        )
        let actionCtrl2 = coordinator.evaluateKeyEvent(ctxCtrl2)
        #expect(actionCtrl2 == .acceptCandidate(candidates[1]), "Control+2 must accept candidate #2")
        
        // 3. Control + 3 (keyCode: 20) accepts candidate #3
        let ctxCtrl3 = KeyEventContext(
            eventType: .keyDown,
            keyCode: 20,
            flags: [.maskControl],
            language: 1,
            autoWordingEnabled: true,
            candidateSuggestionsEnabled: true,
            activeCandidates: candidates
        )
        let actionCtrl3 = coordinator.evaluateKeyEvent(ctxCtrl3)
        #expect(actionCtrl3 == .acceptCandidate(candidates[2]), "Control+3 must accept candidate #3")
        
        // 4. Esc (keyCode: 53) dismisses active candidates
        let ctxEsc = KeyEventContext(
            eventType: .keyDown,
            keyCode: 53,
            flags: [],
            language: 1,
            autoWordingEnabled: true,
            candidateSuggestionsEnabled: true,
            activeCandidates: candidates
        )
        let actionEsc = coordinator.evaluateKeyEvent(ctxEsc)
        #expect(actionEsc == .dismissCandidates, "Esc must return .dismissCandidates when active candidates exist")
        
        // 5. Esc when candidates list is empty passes through to application
        let ctxEscEmpty = KeyEventContext(
            eventType: .keyDown,
            keyCode: 53,
            flags: [],
            language: 1,
            autoWordingEnabled: true,
            candidateSuggestionsEnabled: true,
            activeCandidates: []
        )
        let actionEscEmpty = coordinator.evaluateKeyEvent(ctxEscEmpty)
        #expect(actionEscEmpty != .dismissCandidates, "Esc must not be swallowed when candidates are empty")
    }
    
    // REQ-001: Settings store persistence & sync
    @Test("REQ-001: Auto wording settings store persistence and sync")
    func settingsStoreAutoWordingPersistence() {
        let store = OpenKeySettingsStore.shared
        
        // Check opt-in default states (default false)
        #expect(store.autoWordingEnabled == false)
        #expect(store.grammarRepairEnabled == false)
        #expect(store.shorthandExpansionEnabled == false)
        #expect(store.candidateSuggestionsEnabled == false)
        
        // Toggle to true and check engine sync
        store.autoWordingEnabled = true
        #expect(AutoWordingEngine.shared.isEnabled == true)
        
        store.grammarRepairEnabled = true
        #expect(AutoWordingEngine.shared.grammarRepairEnabled == true)
        
        store.shorthandExpansionEnabled = true
        #expect(AutoWordingEngine.shared.shorthandExpansionEnabled == true)
        
        store.candidateSuggestionsEnabled = true
        #expect(AutoWordingEngine.shared.candidateSuggestionsEnabled == true)
        
        // Restore opt-in defaults (false)
        store.autoWordingEnabled = false
        store.grammarRepairEnabled = false
        store.shorthandExpansionEnabled = false
        store.candidateSuggestionsEnabled = false
        #expect(AutoWordingEngine.shared.isEnabled == false)
    }
    
    // MARK: - REQ-001..REQ-006 Feature Tests (2026-10-27-ime-intelligence-and-ecosystem)
    
    // REQ-001: Secure Input Protection & Candidate Bar Suppression
    @Test("REQ-001: Secure Input bypasses Vietnamese composition and clears candidate bar")
    func secureInputBypassAndCandidateClear() {
        let coordinator = EventTapCoordinator.shared
        
        // Populate candidate list
        let testCandidates = [
            WordCandidate(id: 0, text: "bảo mật", kind: .correction, replaceLength: 7)
        ]
        AutoWordingEngine.shared.updateCandidates(testCandidates)
        #expect(!AutoWordingEngine.shared.activeCandidates.isEmpty)
        
        // Dispatch key in secure input context
        let secureCtx = KeyEventContext(
            eventType: .keyDown,
            keyCode: 0, // 'a'
            language: 1,
            autoWordingEnabled: true,
            candidateSuggestionsEnabled: true,
            activeCandidates: testCandidates,
            isSecureInput: true
        )
        let action = coordinator.evaluateKeyEvent(secureCtx)
        #expect(action == .passThrough(resetSession: true), "Secure input must pass through and reset session")
        #expect(AutoWordingEngine.shared.activeCandidates.isEmpty, "Active candidates must be cleared on secure input")
    }
    
    // REQ-002: Universal Launcher Overlay Detection
    @Test("REQ-002: Universal Launcher overlay detection (Spotlight, Raycast, Alfred)")
    func launcherOverlayDetection() {
        #expect(EventTapCoordinator.isLauncherApp(bundleId: "com.apple.Spotlight"))
        #expect(EventTapCoordinator.isLauncherApp(bundleId: "com.raycast.macos"))
        #expect(EventTapCoordinator.isLauncherApp(bundleId: "com.runningwithcrayons.Alfred"))
        #expect(EventTapCoordinator.isLauncherApp(bundleId: "com.runningwithcrayons.Alfred-Preferences"))
        #expect(!EventTapCoordinator.isLauncherApp(bundleId: "com.apple.Safari"))
        #expect(!EventTapCoordinator.isLauncherApp(bundleId: nil))
        
        let coordinator = EventTapCoordinator.shared
        
        // Raycast launcher context
        let raycastCtx = KeyEventContext(
            eventType: .keyDown,
            keyCode: 0,
            language: 1,
            activeAppBundleId: "com.raycast.macos"
        )
        #expect(coordinator.evaluateKeyEvent(raycastCtx) == .passThrough(resetSession: true))
        
        // Spotlight overlay visible context
        let spotlightCtx = KeyEventContext(
            eventType: .keyDown,
            keyCode: 0,
            language: 1,
            isSpotlightVisible: true
        )
        #expect(coordinator.evaluateKeyEvent(spotlightCtx) == .passThrough(resetSession: true))
    }
    
    // REQ-003: Caret Accessibility & Multi-Monitor Screen Resolution
    @Test("REQ-003: Caret accessibility activation and screen resolution")
    func caretAccessibilityAndScreenResolution() {
        CaretPositionResolver.resetAccessibilityPIDs()
        #expect(!CaretPositionResolver.isAccessibilityEnabled(for: 99999))
        
        let dummy = AXUIElementCreateSystemWide()
        CaretPositionResolver.enableManualAccessibilityIfNeeded(for: dummy, pid: 99999)
        #expect(CaretPositionResolver.isAccessibilityEnabled(for: 99999))
        
        // Idempotent check
        CaretPositionResolver.enableManualAccessibilityIfNeeded(for: dummy, pid: 99999)
        #expect(CaretPositionResolver.isAccessibilityEnabled(for: 99999))
        
        #if canImport(AppKit)
        let screen = CaretPositionResolver.screenContaining(point: NSPoint(x: 100, y: 100))
        #expect(screen != nil, "screenContaining must resolve a display for valid coordinates")
        #endif
    }
    
    // REQ-004: English Word Auto-Restore without Skipping KEY_D / đ & Trailing Key Preservation
    @Test("REQ-004: English word auto-restore without skipping KEY_D and trailing key pass-through")
    func englishWordAutoRestoreWithD() {
        OKEngineInit()
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1)
        defer {
            OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0)
        }
        
        // 1. Type English word "dead": d d e a d -> đead in Telex, space restores dead
        var screenDead = VirtualScreen()
        screenDead.typeKey(2) // d
        let snapD1 = screenDead.typeKey(2) // d -> đ (Telex dd)
        #expect(snapD1.code != 0, "Typing 'dd' should compose 'đ'")
        screenDead.typeKey(14) // e -> đe
        screenDead.typeKey(0)  // a -> đea
        screenDead.typeKey(2)  // d -> đead
        
        // Hit Space (keyCode 49) to trigger word break restoration of "dead"
        let snapDeadSpace = screenDead.typeKey(49)
        #expect(snapDeadSpace.code == 0 || snapDeadSpace.code == 2 || snapDeadSpace.code == 3 || snapDeadSpace.code == 5,
                "Restoring 'dead' must execute clean word-break restore")
        #expect(snapDeadSpace.backspaceCount == 4, "snapDeadSpace.backspaceCount must be 4, got \(snapDeadSpace.backspaceCount)")
        #expect(screenDead.text == "ddead ", "Virtual screen must restore raw keystrokes 'ddead ', got '\(screenDead.text)'")
        for cu in snapDeadSpace.utf16Array {
            #expect(cu <= 0x7F, "Restored characters for 'dead' must be ASCII code units")
        }
        
        // 2. Type English word "added": a=0, d=2, d=2, e=14, d=2
        OKEngineResetSession()
        var screenAdded = VirtualScreen()
        screenAdded.typeKey(0)  // a
        screenAdded.typeKey(2)  // d -> tempDisableKey=true (d not valid end consonant after a)
        screenAdded.typeKey(2)  // second d stays d
        screenAdded.typeKey(14) // e
        screenAdded.typeKey(2)  // d
        let snapAddedSpace = screenAdded.typeKey(49)
        #expect(snapAddedSpace.code == 0 || snapAddedSpace.code == 2 || snapAddedSpace.code == 3 || snapAddedSpace.code == 5,
                "Restoring 'added' must execute clean word-break restore")
        #expect(snapAddedSpace.backspaceCount == 0, "snapAddedSpace.backspaceCount must be 0 for purely ASCII sequence")
        #expect(screenAdded.text == "added ", "Virtual screen must preserve 'added ', got '\(screenAdded.text)'")
        
        // 3. Trailing key preservation in replaceKeystroke action
        let actionWithTrailing = EventTapAction.replaceKeystroke(
            backspaces: 4,
            chars: [0x64, 0x65, 0x61, 0x64],
            strategy: .standardBackspace,
            passThroughTrailingKey: true
        )
        if case .replaceKeystroke(_, _, _, let passThrough) = actionWithTrailing {
            #expect(passThrough == true, "passThroughTrailingKey must be preserved")
        } else {
            Issue.record("Expected .replaceKeystroke")
        }
    }
    
    // REQ-005: Adaptive Candidate Frequency Learning
    @Test("REQ-005: Adaptive candidate frequency learning and ranking boost")
    func adaptiveCandidateFrequencyLearning() {
        let engine = AutoWordingEngine.shared
        engine.isEnabled = true
        engine.candidateSuggestionsEnabled = true
        defer {
            engine.isEnabled = false
            engine.candidateSuggestionsEnabled = false
        }
        engine.resetLearnedFrequencies()
        #expect(engine.userFrequencies.isEmpty)
        
        // Acceptance recording for continuation word "trai" of compound "con"
        engine.recordCandidateAcceptance(text: "trai")
        #expect(engine.userFrequencies["trai"] == 1)
        engine.recordCandidateAcceptance(text: "trai")
        #expect(engine.userFrequencies["trai"] == 2)
        
        // Verify ranking boost in next-word predictions for "con"
        let candidates = engine.computeNextWordCandidates(previousWord: "con")
        #expect(!candidates.isEmpty)
        #expect(candidates.first?.text == "trai", "Learned high-frequency word 'trai' must rank #1")
        
        // Reset frequencies
        engine.resetLearnedFrequencies()
        #expect(engine.userFrequencies.isEmpty)
    }
    
    // REQ-006: Expanded Built-in & Custom Shorthand Table Persistence
    @Test("REQ-006: Expanded built-in and custom shorthand table persistence")
    func expandedBuiltInAndCustomShorthands() {
        let store = OpenKeySettingsStore.shared
        store.autoWordingEnabled = true
        store.shorthandExpansionEnabled = true
        defer {
            store.autoWordingEnabled = false
            store.shorthandExpansionEnabled = false
        }
        let engine = AutoWordingEngine.shared
        
        // 1. Built-in expanded shorthands
        #expect(engine.expandShorthand(rawWord: "k") == "không")
        #expect(engine.expandShorthand(rawWord: "K") == "Không")
        #expect(engine.expandShorthand(rawWord: "j") == "gì")
        #expect(engine.expandShorthand(rawWord: "bh") == "bây giờ")
        #expect(engine.expandShorthand(rawWord: "Bh") == "Bây giờ")
        #expect(engine.expandShorthand(rawWord: "mn") == "mọi người")
        #expect(engine.expandShorthand(rawWord: "cty") == "công ty")
        #expect(engine.expandShorthand(rawWord: "nv") == "nhân viên")
        #expect(engine.expandShorthand(rawWord: "gd") == "gia đình")
        #expect(engine.expandShorthand(rawWord: "sdt") == "số điện thoại")
        #expect(engine.expandShorthand(rawWord: "tks") == "cảm ơn")
        
        // 2. Custom shorthands persistence via OpenKeySettingsStore
        store.setCustomShorthand(trigger: "cv", replacement: "công việc")
        #expect(store.customShorthands["cv"] == "công việc")
        #expect(engine.expandShorthand(rawWord: "cv") == "công việc")
        #expect(engine.expandShorthand(rawWord: "Cv") == "Công việc")
        #expect(engine.expandShorthand(rawWord: "CV") == "CÔNG VIỆC")
        
        // Cleanup custom shorthand
        store.removeCustomShorthand(trigger: "cv")
        #expect(store.customShorthands["cv"] == nil)
        #expect(engine.expandShorthand(rawWord: "cv") == nil)
    }
    
    // MARK: - REQ-007: Multi-Delete & Subsequent Character Entry State Integrity
    @Test("REQ-007: Multi-Delete and Subsequent Character Entry State Integrity")
    func multiDeleteAndSubsequentEntryStateIntegrity() {
        let coordinator = EventTapCoordinator.shared
        OKEngineInit()
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1)
        defer {
            OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0)
        }
        
        // (a) Typing toned words and pressing KEY_DELETE (51) 1..6 times
        // 1. "nhất": n=45, h=4, a=0, a=0 -> â, s=1 -> ấ, t=17 -> nhất
        OKEngineResetSession()
        _ = OKEngineHandleKeyEvent(45, 0, false)
        _ = OKEngineHandleKeyEvent(4, 0, false)
        _ = OKEngineHandleKeyEvent(0, 0, false)
        _ = OKEngineHandleKeyEvent(0, 0, false)
        _ = OKEngineHandleKeyEvent(1, 0, false)
        _ = OKEngineHandleKeyEvent(17, 0, false)
        for _ in 1...5 {
            let snapDel = OKEngineHandleKeyEvent(51, 0, false)
            #expect(snapDel.code == HookCodeState.doNothing, "KEY_DELETE must not trigger unexpected replacement")
            #expect(snapDel.backspaceCount == 0, "KEY_DELETE backspace count must be 0")
            #expect(snapDel.newCharCount == 0, "KEY_DELETE newCharCount must be 0")
            let action = coordinator.evaluateKeyEvent(KeyEventContext(eventType: .keyDown, keyCode: 51, language: 1))
            #expect(action == .passThrough(resetSession: false), "KEY_DELETE must pass through to application")
        }
        
        // 2. "tiếng": t=17, i=34, e=14, e=14 -> ê, n=45, g=5, s=1 -> tiếng
        OKEngineResetSession()
        _ = OKEngineHandleKeyEvent(17, 0, false)
        _ = OKEngineHandleKeyEvent(34, 0, false)
        _ = OKEngineHandleKeyEvent(14, 0, false)
        _ = OKEngineHandleKeyEvent(14, 0, false)
        _ = OKEngineHandleKeyEvent(45, 0, false)
        _ = OKEngineHandleKeyEvent(5, 0, false)
        _ = OKEngineHandleKeyEvent(1, 0, false)
        for _ in 1...6 {
            let snapDel = OKEngineHandleKeyEvent(51, 0, false)
            #expect(snapDel.code == HookCodeState.doNothing)
            #expect(snapDel.backspaceCount == 0)
            #expect(snapDel.newCharCount == 0)
        }
        
        // 3. "trường": t=17, r=15, u=32, o=31, w=13 -> ươ, n=45, g=5, f=3 -> trường
        OKEngineResetSession()
        _ = OKEngineHandleKeyEvent(17, 0, false)
        _ = OKEngineHandleKeyEvent(15, 0, false)
        _ = OKEngineHandleKeyEvent(32, 0, false)
        _ = OKEngineHandleKeyEvent(31, 0, false)
        _ = OKEngineHandleKeyEvent(13, 0, false)
        _ = OKEngineHandleKeyEvent(45, 0, false)
        _ = OKEngineHandleKeyEvent(5, 0, false)
        _ = OKEngineHandleKeyEvent(3, 0, false)
        for _ in 1...6 {
            let snapDel = OKEngineHandleKeyEvent(51, 0, false)
            #expect(snapDel.code == HookCodeState.doNothing)
            #expect(snapDel.backspaceCount == 0)
            #expect(snapDel.newCharCount == 0)
        }
        
        // 4. "hoàn": h=4, o=31, a=0, n=45, f=3 -> hoàn
        OKEngineResetSession()
        _ = OKEngineHandleKeyEvent(4, 0, false)
        _ = OKEngineHandleKeyEvent(31, 0, false)
        _ = OKEngineHandleKeyEvent(0, 0, false)
        _ = OKEngineHandleKeyEvent(45, 0, false)
        _ = OKEngineHandleKeyEvent(3, 0, false)
        for _ in 1...5 {
            let snapDel = OKEngineHandleKeyEvent(51, 0, false)
            #expect(snapDel.code == HookCodeState.doNothing)
            #expect(snapDel.backspaceCount == 0)
            #expect(snapDel.newCharCount == 0)
        }
        
        // (b) Typing "tiếng" -> Delete 3 times (leaving "ti") -> type "me " -> "time " and "ếp" -> "tiếp"
        OKEngineResetSession()
        _ = OKEngineHandleKeyEvent(17, 0, false) // t
        _ = OKEngineHandleKeyEvent(34, 0, false) // i
        _ = OKEngineHandleKeyEvent(14, 0, false) // e
        _ = OKEngineHandleKeyEvent(14, 0, false) // e -> ê
        _ = OKEngineHandleKeyEvent(45, 0, false) // n
        _ = OKEngineHandleKeyEvent(5, 0, false)  // g
        _ = OKEngineHandleKeyEvent(1, 0, false)  // s -> tiếng
        
        // Delete 3 times: g, n, ê -> leaves "ti"
        _ = OKEngineHandleKeyEvent(51, 0, false)
        _ = OKEngineHandleKeyEvent(51, 0, false)
        _ = OKEngineHandleKeyEvent(51, 0, false)
        
        // Now type m (46), e (14) -> "time"
        _ = OKEngineHandleKeyEvent(46, 0, false) // m
        _ = OKEngineHandleKeyEvent(14, 0, false) // e
        let snapSpaceTime = OKEngineHandleKeyEvent(49, 0, false) // Space
        #expect(snapSpaceTime.code == HookCodeState.doNothing || snapSpaceTime.code == 2,
                "Typing 'time ' after deleting back to 'ti' must not resurrect 'e' from previous syllable")
        
        // Sub-test: type "ti" then "ếp" -> "tiếp"
        OKEngineResetSession()
        _ = OKEngineHandleKeyEvent(17, 0, false) // t
        _ = OKEngineHandleKeyEvent(34, 0, false) // i
        _ = OKEngineHandleKeyEvent(14, 0, false) // e
        _ = OKEngineHandleKeyEvent(14, 0, false) // e -> ê
        _ = OKEngineHandleKeyEvent(45, 0, false) // n
        _ = OKEngineHandleKeyEvent(5, 0, false)  // g
        _ = OKEngineHandleKeyEvent(1, 0, false)  // s -> tiếng
        _ = OKEngineHandleKeyEvent(51, 0, false) // delete g
        _ = OKEngineHandleKeyEvent(51, 0, false) // delete n
        _ = OKEngineHandleKeyEvent(51, 0, false) // delete ê -> leaves "ti"
        _ = OKEngineHandleKeyEvent(14, 0, false) // e
        let snapTie = OKEngineHandleKeyEvent(14, 0, false) // e -> ê
        #expect(snapTie.code != 0, "Typing 'ee' after 'ti' must compose 'ê'")
        _ = OKEngineHandleKeyEvent(35, 0, false) // p
        let snapTiep = OKEngineHandleKeyEvent(1, 0, false)  // s -> tiếp
        #expect(snapTiep.code != 0, "Typing 's' on 'tiep' must add acute accent")
        #expect(snapTiep.decodedString.contains("ế"), "Must produce 'tiếp': \(snapTiep.decodedString)")
        
        // (c) Typing multi-word "xin chào em", pressing Delete 7 times across spaces and typing new characters
        OKEngineResetSession()
        // "xin": x=7, i=34, n=45, Space=49
        _ = OKEngineHandleKeyEvent(7, 0, false)
        _ = OKEngineHandleKeyEvent(34, 0, false)
        _ = OKEngineHandleKeyEvent(45, 0, false)
        _ = OKEngineHandleKeyEvent(49, 0, false)
        // "chào": c=8, h=4, a=0, f=3 -> à, o=31, Space=49
        _ = OKEngineHandleKeyEvent(8, 0, false)
        _ = OKEngineHandleKeyEvent(4, 0, false)
        _ = OKEngineHandleKeyEvent(0, 0, false)
        _ = OKEngineHandleKeyEvent(3, 0, false)
        _ = OKEngineHandleKeyEvent(31, 0, false)
        _ = OKEngineHandleKeyEvent(49, 0, false)
        // "em": e=14, m=46
        _ = OKEngineHandleKeyEvent(14, 0, false)
        _ = OKEngineHandleKeyEvent(46, 0, false)
        
        // Delete 7 times across "em" and "chào"
        for _ in 1...7 {
            let snapD = OKEngineHandleKeyEvent(51, 0, false)
            #expect(snapD.code == HookCodeState.doNothing)
            #expect(snapD.backspaceCount == 0)
        }
        // Now type "bạn": b=11, a=0, n=45, j=38
        _ = OKEngineHandleKeyEvent(11, 0, false)
        _ = OKEngineHandleKeyEvent(0, 0, false)
        _ = OKEngineHandleKeyEvent(45, 0, false)
        let snapBan = OKEngineHandleKeyEvent(38, 0, false) // j -> nặng
        #expect(snapBan.code != 0, "Must process tone mark for 'bạn' cleanly across deleted words")
        #expect(snapBan.decodedString.contains("ạ"), "Must produce 'bạn': \(snapBan.decodedString)")
        
        // (d) Typing shorthand "ko " -> "không ", pressing Delete 6 times and typing new characters
        OKEngineResetSession()
        _ = OKEngineHandleKeyEvent(40, 0, false) // k
        _ = OKEngineHandleKeyEvent(31, 0, false) // o
        let snapKoSpace = OKEngineHandleKeyEvent(49, 0, false) // Space -> expands "không "
        #expect(snapKoSpace.code != 0, "Shorthand 'ko ' must expand to 'không '")
        #expect(snapKoSpace.decodedString.contains("không"), "Must contain 'không'")
        
        // Delete 6 times
        for _ in 1...6 {
            let snapD = OKEngineHandleKeyEvent(51, 0, false)
            #expect(snapD.code == HookCodeState.doNothing)
            #expect(snapD.backspaceCount == 0)
        }
        // Type "chào": c=8, h=4, a=0, f=3, o=31
        _ = OKEngineHandleKeyEvent(8, 0, false)
        _ = OKEngineHandleKeyEvent(4, 0, false)
        _ = OKEngineHandleKeyEvent(0, 0, false)
        let snapChaoA = OKEngineHandleKeyEvent(3, 0, false) // f -> à
        #expect(snapChaoA.code != 0, "Must add grave accent cleanly after shorthand delete")
        _ = OKEngineHandleKeyEvent(31, 0, false) // o
        
        // (e) VirtualScreen simulation: typing 'kiểm tra tiếng v, '
        // Case 1: with t-i-e-n-g-s (phonotactic promotion ie -> iê)
        OKEngineResetSession()
        var screen1 = VirtualScreen()
        // 'kiểm ': k=40, i=34, e=14, e=14, m=46, r=15, space=49
        screen1.typeKey(40)
        screen1.typeKey(34)
        screen1.typeKey(14)
        screen1.typeKey(14)
        screen1.typeKey(46)
        screen1.typeKey(15)
        screen1.typeKey(49)
        #expect(screen1.text == "kiểm ")
        
        // 'tra ': t=17, r=15, a=0, space=49
        screen1.typeKey(17)
        screen1.typeKey(15)
        screen1.typeKey(0)
        screen1.typeKey(49)
        #expect(screen1.text == "kiểm tra ")
        
        // 'tiếng ': t=17, i=34, e=14, n=45, g=5, s=1, space=49
        screen1.typeKey(17)
        screen1.typeKey(34)
        screen1.typeKey(14)
        screen1.typeKey(45)
        screen1.typeKey(5)
        let snapS1 = screen1.typeKey(1)
        #expect(snapS1.backspaceCount == 4, "snapS.backspaceCount must be 4, never 3")
        #expect(snapS1.newCharCount == 4, "snapS.newCharCount must be 4")
        screen1.typeKey(49) // space
        #expect(screen1.text == "kiểm tra tiếng ")
        
        // 'v, ': v=9, comma=43, space=49
        screen1.typeKey(9)
        screen1.typeKey(43)
        screen1.typeKey(49)
        #expect(screen1.text == "kiểm tra tiếng v, ", "Screen must display 'kiểm tra tiếng v, ', got '\(screen1.text)'")
        
        // Case 2: with t-i-e-e-n-g-s (explicit double e)
        OKEngineResetSession()
        var screen2 = VirtualScreen()
        // 'kiểm '
        screen2.typeKey(40)
        screen2.typeKey(34)
        screen2.typeKey(14)
        screen2.typeKey(14)
        screen2.typeKey(46)
        screen2.typeKey(15)
        screen2.typeKey(49)
        // 'tra '
        screen2.typeKey(17)
        screen2.typeKey(15)
        screen2.typeKey(0)
        screen2.typeKey(49)
        // 'tiếng ': t=17, i=34, e=14, e=14, n=45, g=5, s=1, space=49
        screen2.typeKey(17)
        screen2.typeKey(34)
        screen2.typeKey(14)
        screen2.typeKey(14)
        screen2.typeKey(45)
        screen2.typeKey(5)
        let snapS2 = screen2.typeKey(1)
        #expect(snapS2.backspaceCount == 4, "snapS.backspaceCount must be 4")
        #expect(snapS2.newCharCount == 4, "snapS.newCharCount must be 4")
        screen2.typeKey(49) // space
        // 'v, '
        screen2.typeKey(9)
        screen2.typeKey(43)
        screen2.typeKey(49)
        #expect(screen2.text == "kiểm tra tiếng v, ", "Screen must display 'kiểm tra tiếng v, ', got '\(screen2.text)'")
    }
    
    // MARK: - REQ-008: Code Review Invariants & Edge Case Hardening
    @Test("REQ-008: Code review regression tests (delete-restore, caps lock punctuation, bracket word break)")
    func codeReviewRegressionTests() {
        OKEngineInit()
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1)
        defer {
            OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0)
        }
        
        // (a) Deleting 'tiếng' down to 'ti' and typing invalid syllable 'fg ' ('tìg ') restores to 'tifg ' (not 'tieefg ')
        var screenA = VirtualScreen()
        screenA.typeKey(17) // t
        screenA.typeKey(34) // i
        screenA.typeKey(14) // e
        screenA.typeKey(14) // e
        screenA.typeKey(45) // n
        screenA.typeKey(5)  // g
        screenA.typeKey(1)  // s -> tiếng
        #expect(screenA.text == "tiếng")
        
        // Delete 3 times ('g', 'n', 'ế') -> leaves 'ti'
        screenA.typeKey(51)
        screenA.typeKey(51)
        screenA.typeKey(51)
        #expect(screenA.text == "ti")
        
        // Type 'f' (3), 'g' (5), Space (49) -> invalid syllable 'tìg ' restores to 'tifg '
        screenA.typeKey(3)  // f
        screenA.typeKey(5)  // g
        screenA.typeKey(49) // Space -> triggers restore
        #expect(screenA.text == "tifg ", "Must restore to 'tifg ' without orphaned 'ee', got '\(screenA.text)'")
        
        // (b) Typing 'WINDOWS.' with Caps Lock (capsStatus = 2 on letters and '.') restores to 'WINDOWS.' (not 'WINDOWS>')
        OKEngineResetSession()
        var screenB = VirtualScreen()
        screenB.typeKey(13, caps: 2) // W
        screenB.typeKey(34, caps: 2) // I
        screenB.typeKey(45, caps: 2) // N
        screenB.typeKey(2, caps: 2)  // D
        screenB.typeKey(31, caps: 2) // O
        screenB.typeKey(13, caps: 2) // W
        screenB.typeKey(1, caps: 2)  // S
        screenB.typeKey(47, caps: 2) // . with Caps Lock
        #expect(screenB.text == "WINDOWS.", "Caps Lock must not turn '.' into '>' upon spell-restore, got '\(screenB.text)'")
        
        // (c) Typing 'ca[bạn]' in Telex composes 'ca[bạn]' cleanly
        OKEngineResetSession()
        var screenC = VirtualScreen()
        screenC.typeKey(8)  // c
        screenC.typeKey(0)  // a -> ca
        screenC.typeKey(33) // [
        #expect(screenC.text == "ca[")
        screenC.typeKey(11) // b
        screenC.typeKey(0)  // a
        screenC.typeKey(38) // j -> ạ
        screenC.typeKey(45) // n -> bạn
        screenC.typeKey(30) // ]
        #expect(screenC.text == "ca[bạn]", "Typing 'ca[bạn]' must compose 'ca[bạn]' cleanly, got '\(screenC.text)'")
    }
}
