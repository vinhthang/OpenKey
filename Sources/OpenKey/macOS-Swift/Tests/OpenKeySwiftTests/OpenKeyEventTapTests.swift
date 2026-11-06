//
//  OpenKeyEventTapTests.swift
//  OpenKeySwiftTests
//
//  Created for OpenKey macOS Swift.
//  Event tap routing, shortcuts, accessibility, secure input, and platform tests (REQ-009, ADR-008).
//

import Foundation
import CoreGraphics
import ApplicationServices
import Testing
@testable import OpenKeySwiftCore

extension OpenKeySwiftTests {

@Suite("OpenKeyEventTapTests", .serialized)
struct OpenKeyEventTapTests {
    
    init() {
        OKEngineInit()
        OKEngineResetSession()
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
        let safariBreaker = KeystrokeInjector.determineStrategy(backspaceCount: 2, fixRecommendBrowser: true, bundleId: "com.apple.Safari", extCode: 0)
        #expect(safariBreaker == .emptyCharBreaker(emptyChar: 0x202F))
        let excelBreaker = KeystrokeInjector.determineStrategy(backspaceCount: 2, fixRecommendBrowser: true, bundleId: "com.microsoft.Excel", extCode: 0)
        #expect(excelBreaker == .emptyCharBreaker(emptyChar: 0x202F))
        
        // Non-browser apps (Teams, Antigravity, Slack, Endo) use standardBackspace (REQ-021, ADR-022)
        let nonBrowserApps = [
            "com.microsoft.teams2",
            "com.microsoft.teams",
            "com.google.antigravity",
            "com.meta.endo",
            "com.tinyspeck.slackmacgap",
            "com.apple.Notes",
            "com.hnc.Discord"
        ]
        for app in nonBrowserApps {
            let strategy = KeystrokeInjector.determineStrategy(backspaceCount: 2, fixRecommendBrowser: true, bundleId: app, extCode: 0)
            #expect(strategy == .standardBackspace, "Expected standardBackspace for \(app)")
        }
        
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
    @Test("OpenKeySettingsStore synchronizes with OpenKeyEngineConfig and UserDefaults")
    @MainActor
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
    
    // REQ-012: UI Language persistence and clamping
    @Test("REQ-012: UI language setting persistence and clamping")
    func testUILanguagePersistence() {
        let store = OpenKeySettingsStore.shared
        let original = store.uiLanguage
        defer {
            store.uiLanguage = original
        }
        
        store.uiLanguage = 0
        #expect(store.uiLanguage == 0)
        #expect(UserDefaults.standard.integer(forKey: OpenKeySettingsStore.Keys.uiLanguage) == 0)
        
        store.uiLanguage = 99
        #expect(store.uiLanguage == 1, "Setting uiLanguage to 99 must clamp to 1 (Vietnamese)")
        #expect(UserDefaults.standard.integer(forKey: OpenKeySettingsStore.Keys.uiLanguage) == 1)
        
        store.uiLanguage = -1
        #expect(store.uiLanguage == 1, "Setting uiLanguage to -1 must clamp to 1 (Vietnamese)")
    }
    
    // REQ-013: Debug mode logging, secure-input redaction, and per-version log retention
    @Test("REQ-013: Debug mode logging, secure-input redaction, and per-version log retention")
    func testDebugModeLoggingAndRetention() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("OpenKeyTestLogs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let logger = OpenKeyLogger.shared
        let store = OpenKeySettingsStore.shared
        let origDebug = store.debugModeEnabled
        defer { store.debugModeEnabled = origDebug }
        
        // (a) Zero file writes & zero @autoclosure evaluation when debugModeEnabled == false
        store.debugModeEnabled = false
        logger.configureForTesting(logDirectoryURL: tempDir, appVersionStamp: "2.0.0-build1", maxFileSizeBytes: 1024 * 1024)
        var evaluated = false
        logger.log(.eventTap, { evaluated = true; return "disabled" }())
        logger.flushForTesting()
        #expect(!evaluated, "Autoclosure must not be evaluated when debug mode is disabled")
        let logFileURL = tempDir.appendingPathComponent("openkey-debug.log")
        #expect(!FileManager.default.fileExists(atPath: logFileURL.path), "Log file must not be created when debug mode is disabled")
        
        // (b) Multi-subsystem log emission when debugModeEnabled == true
        store.debugModeEnabled = true
        #expect(logger.isEnabled == true)
        logger.log(.lifecycle, "Lifecycle startup")
        logger.log(.settings, "Setting changed")
        logger.log(.eventTap, "Event tap key 14")
        logger.log(.engine, "Engine composed 'tiếng'")
        logger.log(.autoWording, "AutoWording candidate 'việt'")
        logger.flushForTesting()
        #expect(FileManager.default.fileExists(atPath: logFileURL.path))
        let contentB = try String(contentsOf: logFileURL, encoding: .utf8)
        #expect(contentB.contains("# OpenKeySwiftVersionStamp: 2.0.0-build1"))
        #expect(contentB.contains("[LIFECYCLE] Lifecycle startup"))
        #expect(contentB.contains("[SETTINGS] Setting changed"))
        #expect(contentB.contains("[EVENT_TAP] Event tap key 14"))
        #expect(contentB.contains("[ENGINE] Engine composed 'tiếng'"))
        #expect(contentB.contains("[AUTO_WORDING] AutoWording candidate 'việt'"))
        
        // (c) Strict keystroke redaction when KeyEventContext.isSecureInput == true
        let coordinator = EventTapCoordinator()
        let secureContext = KeyEventContext(
            eventType: .keyDown, keyCode: 6,
            activeAppBundleId: "com.apple.Terminal", isSecureInput: true
        )
        _ = coordinator.evaluateKeyEvent(secureContext)
        logger.flushForTesting()
        let contentC = try String(contentsOf: logFileURL, encoding: .utf8)
        #expect(contentC.contains("Secure input active — keystroke redacted, bypassing IME"))
        #expect(!contentC.contains("keyCode: 6") && !contentC.contains("secret") && !contentC.contains("code=6"))
        
        // (d) Automatic log truncation/purge when appVersionStamp changes
        logger.configureForTesting(logDirectoryURL: tempDir, appVersionStamp: "2.0.0-build2", maxFileSizeBytes: 1024 * 1024)
        logger.log(.lifecycle, "New version startup")
        logger.flushForTesting()
        let contentD = try String(contentsOf: logFileURL, encoding: .utf8)
        #expect(contentD.contains("# OpenKeySwiftVersionStamp: 2.0.0-build2"))
        #expect(!contentD.contains("2.0.0-build1"), "Old logs purged on version change")
        #expect(!contentD.contains("Lifecycle startup"))
        #expect(contentD.contains("[LIFECYCLE] New version startup"))
        
        // (e) Automatic size-cap truncation when maxFileSizeBytes is exceeded
        logger.configureForTesting(logDirectoryURL: tempDir, appVersionStamp: "2.0.0-build2", maxFileSizeBytes: 200)
        logger.log(.lifecycle, "Small line")
        logger.flushForTesting()
        logger.log(.engine, String(repeating: "DATA-CHUNK-TEST-", count: 20))
        logger.flushForTesting()
        let contentE = try String(contentsOf: logFileURL, encoding: .utf8)
        #expect(contentE.contains("# OpenKeySwiftVersionStamp: 2.0.0-build2"))
        let fileAttrs = try FileManager.default.attributesOfItem(atPath: logFileURL.path)
        let fileSize = (fileAttrs[.size] as? NSNumber)?.intValue ?? 0
        #expect(fileSize <= 800, "Log file size must be bounded after cap rotation, got \(fileSize) bytes")
    }

    // REQ-029, ADR-029: English Mode Pure Passthrough & Elimination of Autonomous Mode Switching
    @Test("REQ-029, ADR-029: English mode pure passthrough never switches to Vietnamese")
    func testEnglishModePurePassthroughNeverSwitchesToVietnamese() {
        let store = OpenKeySettingsStore.shared
        let origLang = store.language
        defer { store.language = origLang }
        store.language = 0

        let coordinator = EventTapCoordinator()

        // Type "did " (keyCodes 2, 34, 2, 49), "as " (keyCodes 0, 1, 49), "war " (keyCodes 13, 0, 15, 49), "code " (keyCodes 8, 31, 2, 14, 49)
        let sequences: [[Int64]] = [
            [2, 34, 2, 49],          // "did "
            [0, 1, 49],              // "as "
            [13, 0, 15, 49],         // "war "
            [8, 31, 2, 14, 49]       // "code "
        ]
        for seq in sequences {
            for keyCode in seq {
                let ctx = KeyEventContext(
                    eventType: .keyDown,
                    keyCode: keyCode,
                    language: store.language
                )
                let action = coordinator.evaluateKeyEvent(ctx)
                #expect(action == .passThrough(resetSession: false), "Keycode \(keyCode) in sequence \(seq) must pass through without resetting session")
            }
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        #expect(store.language == 0, "store.language must remain 0 (English mode)")
    }

    @Test("REQ-029, ADR-029: Zero autonomous language flipping on inline typing")
    func testZeroAutonomousLanguageFlippingOnInlineTyping() {
        let store = OpenKeySettingsStore.shared
        let origLang = store.language
        defer { store.language = origLang }
        store.language = 1

        let coordinator = EventTapCoordinator()

        // Simulate typing 3 English words in Vietnamese mode: "test list more "
        let words = [
            [17, 14, 1, 17, 49],     // "test "
            [37, 34, 1, 17, 49],     // "list "
            [46, 31, 15, 14, 49]     // "more "
        ]
        for word in words {
            for k in word {
                let ctx = KeyEventContext(eventType: .keyDown, keyCode: Int64(k), language: 1)
                _ = coordinator.evaluateKeyEvent(ctx)
            }
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        #expect(store.language == 1, "store.language must remain 1 after typing 3+ English words")
    }
}
}
