import Cocoa
import CoreGraphics
import ApplicationServices
#if canImport(Carbon)
import Carbon
#endif

public final class EventTapCoordinator: @unchecked Sendable {
    public static let shared = EventTapCoordinator()
    
    // Environment detection forwarding for backward compatibility (REQ-009, ADR-008)
    public static func isSecureEventInputActive() -> Bool { SystemEnvironmentDetector.isSecureEventInputActive() }
    public static func isLauncherApp(bundleId: String?) -> Bool { SystemEnvironmentDetector.isLauncherApp(bundleId: bundleId) }
    public static func isTerminalApp(bundleId: String?) -> Bool { SystemEnvironmentDetector.isTerminalApp(bundleId: bundleId) }
    public static func markSpotlightNeedsRecheck() { SystemEnvironmentDetector.markSpotlightNeedsRecheck() }
    public static func invalidateSpotlightCache() { SystemEnvironmentDetector.invalidateSpotlightCache() }
    public static func isSpotlightOverlayVisible(frontmostBundleId: String? = nil) -> Bool { SystemEnvironmentDetector.isSpotlightOverlayVisible(frontmostBundleId: frontmostBundleId) }
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var trustPollingTimer: Timer?
    private var notificationTokens: [NSObjectProtocol] = []
    private let settings = OpenKeySettingsStore.shared
    private let injector = KeystrokeInjector.shared
    
    // State tracking for hotkey handling
    private var swallowNextKeyUp: Bool = false
    private var pendingModifierTap: Bool = false
    private var modifierTapCancelled: Bool = false
    
    public private(set) var isRunning: Bool = false
    
    public init() {
        if let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           frontmost != "com.tuyenmai.openkey.swift" {
            settings.activeAppBundleId = frontmost
        }
        setupAppSwitchObserver()
        setupWakeObserver()
    }
    
    deinit {
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
    }
    
    public func start() {
        checkAccessibilityAndSetupTap()
    }
    
    public func stop() {
        trustPollingTimer?.invalidate(); trustPollingTimer = nil
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }
        isRunning = false
    }
    
    public func checkAccessibilityAndSetupTap() {
        if setupEventTap() {
            settings.isAccessibilityTrusted = true
            trustPollingTimer?.invalidate(); trustPollingTimer = nil
            return
        }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        settings.isAccessibilityTrusted = false
        if trustPollingTimer == nil {
            trustPollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                if self.setupEventTap() {
                    self.settings.isAccessibilityTrusted = true
                    self.trustPollingTimer?.invalidate(); self.trustPollingTimer = nil
                }
            }
        }
    }
    
    @discardableResult
    private func setupEventTap() -> Bool {
        guard eventTap == nil else { return true }
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) |
                                     (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.leftMouseDown.rawValue) |
                                     (1 << CGEventType.rightMouseDown.rawValue) | (1 << CGEventType.otherMouseDown.rawValue)
        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: observer
        ) else {
            return false
        }
        
        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        return true
    }
    
    public nonisolated(unsafe) static var candidatePanelFrame: NSRect = .zero
    
    private func setupAppSwitchObserver() {
        let token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleId = app.bundleIdentifier else { return }
            Self.invalidateSpotlightCache()
            self.handleAppSwitch(bundleId: bundleId)
        }
        notificationTokens.append(token)
    }
    
    private func setupWakeObserver() {
        let token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            OKEngineResetSession()
            if let tap = self.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            } else {
                self.setupEventTap()
            }
        }
        notificationTokens.append(token)
    }
    
    public func handleAppSwitch(bundleId: String) {
        OKEngineResetSession()
        if bundleId == "com.tuyenmai.openkey.swift" { return }
        settings.activeAppBundleId = bundleId
        guard settings.useSmartSwitchKey && !EventTapCoordinator.isTerminalApp(bundleId: bundleId) else { return }
        let currentLang = settings.language
        let appLang = OKGetAppInputMethodStatus(bundleId, Int32(currentLang))
        if appLang >= 0 && appLang != currentLang {
            settings.applySmartSwitchLanguage(Int(appLang))
        } else if appLang == -1 {
            settings.saveSmartSwitchData()
        }
    }
    
    public func saveLanguageForApp(bundleId: String, language: Int) {
        OKSetAppInputMethodStatus(bundleId, Int32(language))
        settings.saveSmartSwitchData()
    }
    
    // MARK: - Pure Testable Event Evaluation Pipeline
    public func evaluateKeyEvent(_ context: KeyEventContext) -> EventTapAction {
        // 1. Ignore self-generated synthetic events
        if context.isSelfEvent {
            return .passThrough(resetSession: false)
        }
        
        // 2. Mouse events reset session and cancel pending modifier tap
        if context.eventType == .leftMouseDown ||
           context.eventType == .rightMouseDown ||
           context.eventType == .otherMouseDown {
            pendingModifierTap = false
            modifierTapCancelled = false
            return .passThrough(resetSession: true)
        }
        
        let isModifierOnly = HotKeyMatcher.isModifierOnlyTap(config: context.switchKeyStatus)
        
        // 3. Modifier-Only HotKey (0xFE)
        if isModifierOnly {
            if context.eventType == .flagsChanged {
                let matchesModifier = HotKeyMatcher.matches(keyCode: 0xFE, flags: context.flags, config: context.switchKeyStatus)
                if matchesModifier {
                    // Modifier pressed down: arm pending tap
                    pendingModifierTap = true
                    modifierTapCancelled = false
                } else if pendingModifierTap {
                    // Modifier released
                    pendingModifierTap = false
                    if !modifierTapCancelled {
                        let newLang = (context.language == 1) ? 0 : 1
                        return .toggleLanguage(newLanguage: newLang)
                    }
                }
                return .passThrough(resetSession: false)
            } else if context.eventType == .keyDown {
                // If any regular key is pressed while modifier is held, cancel modifier tap
                if pendingModifierTap {
                    modifierTapCancelled = true
                }
            }
        }
        
        // 4. Regular HotKey (e.g. Option + Z)
        let matchesHotKey = HotKeyMatcher.matches(keyCode: UInt16(context.keyCode), flags: context.flags, config: context.switchKeyStatus)
        if !isModifierOnly && matchesHotKey {
            if context.eventType == .keyDown {
                if context.isAutoRepeat {
                    return .swallow // Swallow repeated keyDown without re-toggling
                }
                swallowNextKeyUp = true
                let newLang = (context.language == 1) ? 0 : 1
                return .toggleLanguage(newLanguage: newLang)
            } else if context.eventType == .keyUp {
                if swallowNextKeyUp {
                    swallowNextKeyUp = false
                    return .swallow // Swallow corresponding keyUp
                }
            }
        }
        
        if context.eventType == .keyUp || context.eventType == .flagsChanged {
            return .passThrough(resetSession: false)
        }
        
        // 4.1. Secure Input Protection (REQ-001, ADR-001)
        if context.isSecureInput {
            AutoWordingEngine.shared.clearCandidates()
            return .passThrough(resetSession: true)
        }
        
        // 4.5. Candidate Selection / Dismissal (REQ-005)
        if context.language == 1 &&
           context.autoWordingEnabled &&
           context.candidateSuggestionsEnabled &&
           !context.activeCandidates.isEmpty &&
           context.eventType == .keyDown {
            
            // Tab (KEY_TAB = 48) accepts candidate #1 ONLY when it is a correction (REQ-008)
            if context.keyCode == 48 &&
               !context.flags.contains(.maskCommand) &&
               !context.flags.contains(.maskAlternate) &&
               !context.flags.contains(.maskControl) {
                if context.activeCandidates[0].kind == .correction {
                    return .acceptCandidate(context.activeCandidates[0])
                } else {
                    AutoWordingEngine.shared.clearCandidates()
                }
            }
            
            // Control + 1..3 accepts candidate #1..#3
            if context.flags.contains(.maskControl) &&
               !context.flags.contains(.maskCommand) &&
               !context.flags.contains(.maskAlternate) {
                let targetIdx = (context.keyCode == 18) ? 0 : ((context.keyCode == 19) ? 1 : ((context.keyCode == 20) ? 2 : nil))
                if let idx = targetIdx, idx < context.activeCandidates.count {
                    return .acceptCandidate(context.activeCandidates[idx])
                }
            }
            
            // Esc (KEY_ESC = 53) dismisses candidates
            if context.keyCode == 53 &&
               !context.flags.contains(.maskCommand) &&
               !context.flags.contains(.maskAlternate) &&
               !context.flags.contains(.maskControl) {
                return .dismissCandidates
            }
        }
        
        // 5. Bypass on Command/Control/Option shortcuts
        if context.flags.contains(.maskCommand) || context.flags.contains(.maskControl) || context.flags.contains(.maskAlternate) {
            return .passThrough(resetSession: true)
        }
        
        // 6-9. Fast bypass checks
        if context.language == 0 { return .passThrough(resetSession: false) }
        if EventTapCoordinator.isTerminalApp(bundleId: context.activeAppBundleId) { return .passThrough(resetSession: true) }
        if context.isSpotlightVisible || EventTapCoordinator.isLauncherApp(bundleId: context.activeAppBundleId) { return .passThrough(resetSession: true) }
        if context.otherLanguage && !context.isCompatibleInputSource { return .passThrough(resetSession: true) }
        
        // 10. Engine Evaluation
        let otherControlKey = context.flags.contains(.maskSecondaryFn) ||
                              context.flags.contains(.maskNumericPad) ||
                              context.flags.contains(.maskHelp)
        let capsStatus: UInt8 = context.flags.contains(.maskShift) ? 1 : (context.flags.contains(.maskAlphaShift) ? 2 : 0)
        let snapshot = OKEngineHandleKeyEvent(UInt16(context.keyCode), capsStatus, otherControlKey)
        if snapshot.code == HookCodeState.doNothing {
            return .passThrough(resetSession: false)
        }
        let strategy = KeystrokeInjector.determineStrategy(
            backspaceCount: Int(snapshot.backspaceCount),
            fixRecommendBrowser: context.fixRecommendBrowser,
            bundleId: context.activeAppBundleId,
            extCode: Int32(snapshot.extCode)
        )
        return .replaceKeystroke(
            backspaces: Int(snapshot.backspaceCount),
            chars: snapshot.utf16Chars,
            strategy: strategy,
            passThroughTrailingKey: snapshot.shouldSendControlKey
        )
    }
    
    // MARK: - Live Event Tap Callback Handler
    fileprivate func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // 1. Timeout / Disabled Recovery
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            OKEngineResetSession()
            return Unmanaged.passUnretained(event)
        }
        
        let eventType: EventTapEventType
        switch type {
        case .keyDown: eventType = .keyDown
        case .keyUp: eventType = .keyUp
        case .flagsChanged: eventType = .flagsChanged
        case .leftMouseDown: eventType = .leftMouseDown
        case .rightMouseDown: eventType = .rightMouseDown
        case .otherMouseDown: eventType = .otherMouseDown
        default: return Unmanaged.passUnretained(event)
        }
        
        if event.getIntegerValueField(.eventSourceUserData) == KeystrokeInjector.eventSourceUserData {
            return Unmanaged.passUnretained(event)
        }
        
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isAutoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        
        if eventType == .flagsChanged || eventType == .leftMouseDown || eventType == .rightMouseDown || eventType == .otherMouseDown ||
           event.flags.contains(.maskCommand) || event.flags.contains(.maskControl) || event.flags.contains(.maskAlternate) ||
           keyCode == 53 || keyCode == 36 || keyCode == 76 {
            EventTapCoordinator.markSpotlightNeedsRecheck()
        }
        
        let frontBundle = settings.activeAppBundleId ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let isCmdOrCtrlOrAlt = event.flags.contains(.maskCommand) || event.flags.contains(.maskControl) || event.flags.contains(.maskAlternate)
        let isSpotlight = (eventType == .keyDown) && !isCmdOrCtrlOrAlt && EventTapCoordinator.isSpotlightOverlayVisible(frontmostBundleId: frontBundle)
        let isCompatible = InputSourceGuard.isVietnameseProcessingAllowed(otherLanguageEnabled: settings.otherLanguage)
        let isSecure = EventTapCoordinator.isSecureEventInputActive()
        
        let context = KeyEventContext(
            eventType: eventType,
            keyCode: keyCode,
            flags: event.flags,
            isAutoRepeat: isAutoRepeat,
            isSelfEvent: false,
            language: settings.language,
            useSmartSwitchKey: settings.useSmartSwitchKey,
            otherLanguage: settings.otherLanguage,
            switchKeyStatus: settings.switchKeyStatus,
            fixRecommendBrowser: settings.fixRecommendBrowser,
            activeAppBundleId: frontBundle,
            isSpotlightVisible: isSpotlight,
            isCompatibleInputSource: isCompatible,
            autoWordingEnabled: settings.autoWordingEnabled,
            candidateSuggestionsEnabled: settings.candidateSuggestionsEnabled,
            activeCandidates: AutoWordingEngine.shared.activeCandidates,
            isSecureInput: isSecure
        )
        
        let action = evaluateKeyEvent(context)
        
        switch action {
        case .swallow:
            return nil
            
        case .passThrough(let resetSession):
            if resetSession {
                #if canImport(AppKit)
                let mouseInPanel = (eventType == .leftMouseDown) &&
                    !EventTapCoordinator.candidatePanelFrame.isEmpty &&
                    EventTapCoordinator.candidatePanelFrame.contains(NSEvent.mouseLocation) &&
                    !AutoWordingEngine.shared.activeCandidates.isEmpty
                if !mouseInPanel {
                    OKEngineResetSession()
                }
                #else
                OKEngineResetSession()
                #endif
            }
            return Unmanaged.passUnretained(event)
            
        case .toggleLanguage(let newLang):
            OKEngineResetSession()
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.settings.language = newLang
                if self.settings.beepOnSwitch {
                    NSSound.beep()
                }
            }
            return nil // Swallow hotkey
            
        case .replaceKeystroke(let backspaces, let chars, let strategy, let passThroughTrailingKey):
            injector.executeReplacement(
                strategy: strategy,
                backspaceCount: backspaces,
                newChars: chars,
                proxy: proxy
            )
            if passThroughTrailingKey {
                injector.postKeyCode(UInt16(context.keyCode), flags: context.flags, proxy: proxy)
            }
            return nil // Swallow original keystroke
            
        case .acceptCandidate(let candidate):
            AutoWordingEngine.shared.recordCandidateAcceptance(text: candidate.text)
            let fullText = candidate.text + " "
            let chars = Array(fullText.utf16)
            injector.executeReplacement(
                strategy: .standardBackspace,
                backspaceCount: candidate.replaceLength,
                newChars: chars,
                proxy: proxy
            )
            OKEngineResetSession()
            let nextCands = AutoWordingEngine.shared.computeNextWordCandidates(previousWord: candidate.text)
            AutoWordingEngine.shared.updateCandidates(nextCands)
            return nil
            
        case .dismissCandidates:
            AutoWordingEngine.shared.clearCandidates()
            return nil
        }
    }
}

// C-convention callback for CGEventTap
private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let coordinator = Unmanaged<EventTapCoordinator>.fromOpaque(userInfo).takeUnretainedValue()
    return coordinator.handleEvent(proxy: proxy, type: type, event: event)
}
