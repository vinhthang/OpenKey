//
//  SystemEnvironmentDetector.swift
//  OpenKeySwiftCore
//
//  Created for OpenKey macOS Swift.
//  System environment detection, secure input queries, launcher and terminal classification, and event tap context structures (REQ-009, ADR-008).
//

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

public enum SystemEnvironmentDetector {
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
    
    nonisolated(unsafe) private static var lastSpotlightCheckTime: TimeInterval = 0
    nonisolated(unsafe) private static var cachedSpotlightResult: Bool = false
    nonisolated(unsafe) private static var needsSpotlightRecheck: Bool = true
    private static let spotlightLock = NSLock()
    
    public static func markSpotlightNeedsRecheck() {
        spotlightLock.lock()
        needsSpotlightRecheck = true
        spotlightLock.unlock()
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
}
