import Cocoa
import CoreGraphics
import ApplicationServices
#if canImport(Carbon)
import Carbon
#endif

public enum EventTapEventType: Sendable, Equatable {
    case keyDown
    case keyUp
    case flagsChanged
    case leftMouseDown
    case rightMouseDown
    case otherMouseDown
}

public struct KeyEventContext: Sendable {
    public var eventType: EventTapEventType
    public var keyCode: Int64
    public var flags: CGEventFlags
    public var isAutoRepeat: Bool
    public var isSelfEvent: Bool
    public var language: Int
    public var useSmartSwitchKey: Bool
    public var otherLanguage: Bool
    public var switchKeyStatus: Int
    public var fixRecommendBrowser: Bool
    public var activeAppBundleId: String?
    public var isSpotlightVisible: Bool
    public var isCompatibleInputSource: Bool
    public var autoWordingEnabled: Bool
    public var candidateSuggestionsEnabled: Bool
    public var activeCandidates: [WordCandidate]
    public var isSecureInput: Bool
    
    public init(
        eventType: EventTapEventType,
        keyCode: Int64,
        flags: CGEventFlags = [],
        isAutoRepeat: Bool = false,
        isSelfEvent: Bool = false,
        language: Int = 1,
        useSmartSwitchKey: Bool = true,
        otherLanguage: Bool = true,
        switchKeyStatus: Int = OpenKeySettingsStore.defaultSwitchKey,
        fixRecommendBrowser: Bool = true,
        activeAppBundleId: String? = nil,
        isSpotlightVisible: Bool = false,
        isCompatibleInputSource: Bool = true,
        autoWordingEnabled: Bool = false,
        candidateSuggestionsEnabled: Bool = false,
        activeCandidates: [WordCandidate] = [],
        isSecureInput: Bool = false
    ) {
        self.eventType = eventType
        self.keyCode = keyCode
        self.flags = flags
        self.isAutoRepeat = isAutoRepeat
        self.isSelfEvent = isSelfEvent
        self.language = language
        self.useSmartSwitchKey = useSmartSwitchKey
        self.otherLanguage = otherLanguage
        self.switchKeyStatus = switchKeyStatus
        self.fixRecommendBrowser = fixRecommendBrowser
        self.activeAppBundleId = activeAppBundleId
        self.isSpotlightVisible = isSpotlightVisible
        self.isCompatibleInputSource = isCompatibleInputSource
        self.autoWordingEnabled = autoWordingEnabled
        self.candidateSuggestionsEnabled = candidateSuggestionsEnabled
        self.activeCandidates = activeCandidates
        self.isSecureInput = isSecureInput
    }
}

public enum EventTapAction: Sendable, Equatable {
    case swallow
    case passThrough(resetSession: Bool)
    case toggleLanguage(newLanguage: Int)
    case replaceKeystroke(backspaces: Int, chars: [UInt16], strategy: ReplacementStrategy, passThroughTrailingKey: Bool = false)
    case acceptCandidate(WordCandidate)
    case dismissCandidates
}

public final class EventTapCoordinator: @unchecked Sendable {
    public static let shared = EventTapCoordinator()
    
    /// Queries Carbon HIToolbox to detect if Secure Event Input is active
    public static func isSecureEventInputActive() -> Bool {
        #if canImport(Carbon)
        return IsSecureEventInputEnabled()
        #else
        return false
        #endif
    }
    
    /// Detects universal system launcher overlays (Spotlight, Raycast, Alfred)
    public static func isLauncherApp(bundleId: String?) -> Bool {
        guard let bundleId = bundleId else { return false }
        return bundleId == "com.apple.Spotlight" ||
               bundleId == "com.raycast.macos" ||
               bundleId.hasPrefix("com.runningwithcrayons.Alfred")
    }
    
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
    
    // Spotlight cache
    nonisolated(unsafe) private static var lastSpotlightCheckTime: TimeInterval = 0
    nonisolated(unsafe) private static var cachedSpotlightResult: Bool = false
    nonisolated(unsafe) private static var needsSpotlightRecheck: Bool = true
    private static let spotlightLock = NSLock()
    
    public static func markSpotlightNeedsRecheck() {
        spotlightLock.lock()
        needsSpotlightRecheck = true
        spotlightLock.unlock()
    }
    
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
        trustPollingTimer?.invalidate()
        trustPollingTimer = nil
        
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
            trustPollingTimer?.invalidate()
            trustPollingTimer = nil
            return
        }
        
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        settings.isAccessibilityTrusted = false
        
        // Poll every 1.0s until granted
        if trustPollingTimer == nil {
            trustPollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                if self.setupEventTap() {
                    self.settings.isAccessibilityTrusted = true
                    self.trustPollingTimer?.invalidate()
                    self.trustPollingTimer = nil
                }
            }
        }
    }
    
    @discardableResult
    private func setupEventTap() -> Bool {
        guard eventTap == nil else { return true }
        
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) |
                                     (1 << CGEventType.keyUp.rawValue) |
                                     (1 << CGEventType.flagsChanged.rawValue) |
                                     (1 << CGEventType.leftMouseDown.rawValue) |
                                     (1 << CGEventType.rightMouseDown.rawValue) |
                                     (1 << CGEventType.otherMouseDown.rawValue)
        
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
    
    public static func isTerminalApp(bundleId: String?) -> Bool {
        guard let bundleId = bundleId else { return false }
        let terminalBundleIds: Set<String> = [
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
            // Remote desktop & virtual machine clients
            "com.vmware.fusion",
            "com.parallels.desktop.console",
            "com.microsoft.rdc.macos",
            "org.virtualbox.app.VirtualBoxVM",
            "com.utmapp.UTM"
        ]
        return terminalBundleIds.contains(bundleId)
    }
    
    public static func invalidateSpotlightCache() {
        spotlightLock.lock()
        lastSpotlightCheckTime = 0
        cachedSpotlightResult = false
        needsSpotlightRecheck = true
        spotlightLock.unlock()
    }
    
    public static func isSpotlightOverlayVisible(frontmostBundleId: String? = nil) -> Bool {
        if isLauncherApp(bundleId: frontmostBundleId) {
            return true
        }
        
        spotlightLock.lock()
        if !needsSpotlightRecheck && !cachedSpotlightResult {
            spotlightLock.unlock()
            return false
        }
        
        let now = ProcessInfo.processInfo.systemUptime
        if cachedSpotlightResult && (now - lastSpotlightCheckTime) < 0.5 {
            spotlightLock.unlock()
            return true
        }
        needsSpotlightRecheck = false
        spotlightLock.unlock()
        
        var isVisible = false
        if let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for window in windowList {
                if let owner = window[kCGWindowOwnerName as String] as? String,
                   (owner == "Spotlight" || owner == "Raycast" || owner == "Alfred"),
                   let layer = window[kCGWindowLayer as String] as? Int, layer > 0,
                   let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                   let width = boundsDict["Width"] as? CGFloat,
                   let height = boundsDict["Height"] as? CGFloat,
                   width >= 200 && height >= 40 {
                    isVisible = true
                    break
                }
            }
        }
        
        spotlightLock.lock()
        lastSpotlightCheckTime = now
        cachedSpotlightResult = isVisible
        spotlightLock.unlock()
        return isVisible
    }
    
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
        if bundleId == "com.tuyenmai.openkey.swift" {
            return
        }
        settings.activeAppBundleId = bundleId
        guard settings.useSmartSwitchKey else { return }
        if EventTapCoordinator.isTerminalApp(bundleId: bundleId) {
            return
        }
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
        
        if context.eventType == .keyUp {
            return .passThrough(resetSession: false)
        }
        if context.eventType == .flagsChanged {
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
            
            // Tab (KEY_TAB = 48) accepts candidate #1
            if context.keyCode == 48 &&
               !context.flags.contains(.maskCommand) &&
               !context.flags.contains(.maskAlternate) &&
               !context.flags.contains(.maskControl) {
                return .acceptCandidate(context.activeCandidates[0])
            }
            
            // Control + 1..3 accepts candidate #1..#3
            if context.flags.contains(.maskControl) &&
               !context.flags.contains(.maskCommand) &&
               !context.flags.contains(.maskAlternate) {
                var targetIdx: Int? = nil
                if context.keyCode == 18 { targetIdx = 0 }      // 1
                else if context.keyCode == 19 { targetIdx = 1 } // 2
                else if context.keyCode == 20 { targetIdx = 2 } // 3
                
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
        if context.flags.contains(.maskCommand) ||
           context.flags.contains(.maskControl) ||
           context.flags.contains(.maskAlternate) {
            return .passThrough(resetSession: true)
        }
        
        // 6. Fast O(1) English mode bypass
        if context.language == 0 {
            return .passThrough(resetSession: false)
        }
        
        // 7. Bypass on Terminal emulators / VM clients
        if EventTapCoordinator.isTerminalApp(bundleId: context.activeAppBundleId) {
            return .passThrough(resetSession: true)
        }
        
        // 8. Bypass on System Launchers (Spotlight, Raycast, Alfred) (REQ-002, ADR-002)
        if context.isSpotlightVisible || EventTapCoordinator.isLauncherApp(bundleId: context.activeAppBundleId) {
            return .passThrough(resetSession: true)
        }
        
        // 9. Check input source guard (Dvorak/Colemak/AZERTY/non-English layouts)
        if context.otherLanguage && !context.isCompatibleInputSource {
            return .passThrough(resetSession: true)
        }
        
        // 10. Engine Evaluation
        let otherControlKey = context.flags.contains(.maskSecondaryFn) ||
                              context.flags.contains(.maskNumericPad) ||
                              context.flags.contains(.maskHelp)
        
        let capsStatus: UInt8 = context.flags.contains(.maskShift) ? 1 : (context.flags.contains(.maskAlphaShift) ? 2 : 0)
        
        let snapshot = OKEngineHandleKeyEvent(UInt16(context.keyCode), capsStatus, otherControlKey)
        
        if snapshot.code == HookCodeState.doNothing {
            return .passThrough(resetSession: false)
        }
        
        let utf16Chars = snapshot.utf16Chars
        
        let strategy = KeystrokeInjector.determineStrategy(
            backspaceCount: Int(snapshot.backspaceCount),
            fixRecommendBrowser: context.fixRecommendBrowser,
            bundleId: context.activeAppBundleId,
            extCode: Int32(snapshot.extCode)
        )
        
        return .replaceKeystroke(
            backspaces: Int(snapshot.backspaceCount),
            chars: utf16Chars,
            strategy: strategy,
            passThroughTrailingKey: snapshot.shouldSendControlKey
        )
    }
    
    // MARK: - Live Event Tap Callback Handler
    fileprivate func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // 1. Timeout / Disabled Recovery
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
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
        
        let isSelf = event.getIntegerValueField(.eventSourceUserData) == KeystrokeInjector.eventSourceUserData
        if isSelf {
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
            isSelfEvent: isSelf,
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
                OKEngineResetSession()
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
