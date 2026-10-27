import Foundation
import CoreGraphics

public enum ReplacementStrategy: Sendable, Equatable {
    case emptyCharBreaker(emptyChar: UInt16)
    case standardBackspace
}

public final class KeystrokeInjector: @unchecked Sendable {
    public static let shared = KeystrokeInjector()
    public static let eventSourceUserData: Int64 = 0xBEEF
    
    // Key codes
    public static let keyCodeDelete: CGKeyCode = 51
    
    // Special empty breaker characters
    public static let narrowNoBreakSpace: UInt16 = 0x202F // Standard browsers / recommendation (U+202F)
    public static let zeroWidthNonJoiner: UInt16 = 0x200C // Sublime Text breaker (U+200C)
    
    public init() {}
    
    public static func determineStrategy(
        backspaceCount: Int,
        fixRecommendBrowser: Bool,
        bundleId: String? = nil,
        extCode: Int32 = 0
    ) -> ReplacementStrategy {
        guard backspaceCount > 0, fixRecommendBrowser, extCode != 4 else {
            return .standardBackspace
        }
        if let bundleId = bundleId, bundleId.hasPrefix("com.sublimetext") {
            return .emptyCharBreaker(emptyChar: zeroWidthNonJoiner)
        }
        return .emptyCharBreaker(emptyChar: narrowNoBreakSpace)
    }
    
    public var sourceStateID: CGEventSourceStateID {
        return .privateState
    }
    
    private let eventSource: CGEventSource? = {
        let source = CGEventSource(stateID: .privateState)
        source?.userData = KeystrokeInjector.eventSourceUserData
        return source
    }()
    
    public func postBackspaces(count: Int, proxy: CGEventTapProxy) {
        guard count > 0, let source = eventSource else { return }
        for _ in 0..<count {
            if let down = CGEvent(keyboardEventSource: source, virtualKey: Self.keyCodeDelete, keyDown: true) {
                down.setIntegerValueField(.eventSourceUserData, value: Self.eventSourceUserData)
                down.tapPostEvent(proxy)
            }
            if let up = CGEvent(keyboardEventSource: source, virtualKey: Self.keyCodeDelete, keyDown: false) {
                up.setIntegerValueField(.eventSourceUserData, value: Self.eventSourceUserData)
                up.tapPostEvent(proxy)
            }
        }
    }
    
    public func postUnicodeString(_ utf16CodeUnits: [UInt16], proxy: CGEventTapProxy) {
        guard !utf16CodeUnits.isEmpty, let source = eventSource else { return }
        let chunkSize = 16
        var startIndex = 0
        while startIndex < utf16CodeUnits.count {
            let endIndex = min(startIndex + chunkSize, utf16CodeUnits.count)
            var chunk = Array(utf16CodeUnits[startIndex..<endIndex])
            
            if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                down.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                down.setIntegerValueField(.eventSourceUserData, value: Self.eventSourceUserData)
                down.tapPostEvent(proxy)
            }
            if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                up.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                up.setIntegerValueField(.eventSourceUserData, value: Self.eventSourceUserData)
                up.tapPostEvent(proxy)
            }
            startIndex = endIndex
        }
    }
    
    public func executeReplacement(
        strategy: ReplacementStrategy,
        backspaceCount: Int,
        newChars: [UInt16],
        proxy: CGEventTapProxy
    ) {
        switch strategy {
        case .emptyCharBreaker(let emptyChar):
            // Post empty breaker character, increment backspace count by 1
            postUnicodeString([emptyChar], proxy: proxy)
            postBackspaces(count: backspaceCount + 1, proxy: proxy)
            postUnicodeString(newChars, proxy: proxy)
            
        case .standardBackspace:
            postBackspaces(count: backspaceCount, proxy: proxy)
            postUnicodeString(newChars, proxy: proxy)
        }
    }
    
    public func injectReplacementWithoutProxy(backspaceCount: Int, chars: [UInt16]) {
        guard let source = eventSource else { return }
        for _ in 0..<backspaceCount {
            if let down = CGEvent(keyboardEventSource: source, virtualKey: Self.keyCodeDelete, keyDown: true) {
                down.setIntegerValueField(.eventSourceUserData, value: Self.eventSourceUserData)
                down.post(tap: .cghidEventTap)
            }
            if let up = CGEvent(keyboardEventSource: source, virtualKey: Self.keyCodeDelete, keyDown: false) {
                up.setIntegerValueField(.eventSourceUserData, value: Self.eventSourceUserData)
                up.post(tap: .cghidEventTap)
            }
        }
        guard !chars.isEmpty else { return }
        var copy = chars
        if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
            down.keyboardSetUnicodeString(stringLength: copy.count, unicodeString: &copy)
            down.setIntegerValueField(.eventSourceUserData, value: Self.eventSourceUserData)
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
            up.keyboardSetUnicodeString(stringLength: copy.count, unicodeString: &copy)
            up.setIntegerValueField(.eventSourceUserData, value: Self.eventSourceUserData)
            up.post(tap: .cghidEventTap)
        }
    }
    
    public func postKeyCode(_ keyCode: UInt16, flags: CGEventFlags = [], proxy: CGEventTapProxy? = nil) {
        guard let source = eventSource else { return }
        if let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: true) {
            down.flags = flags
            down.setIntegerValueField(.eventSourceUserData, value: Self.eventSourceUserData)
            if let proxy = proxy {
                down.tapPostEvent(proxy)
            } else {
                down.post(tap: .cghidEventTap)
            }
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: false) {
            up.flags = flags
            up.setIntegerValueField(.eventSourceUserData, value: Self.eventSourceUserData)
            if let proxy = proxy {
                up.tapPostEvent(proxy)
            } else {
                up.post(tap: .cghidEventTap)
            }
        }
    }
}
