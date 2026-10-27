import Carbon
import Foundation

public enum InputSourceGuard {
    nonisolated(unsafe) private static var cachedIsCompatible: Bool?
    nonisolated(unsafe) private static var observerInstalled: Bool = false
    private static let lock = NSLock()
    
    public static func isCompatibleInputSource(language: String, inputSourceID: String) -> Bool {
        let lowerID = inputSourceID.lowercased()
        if lowerID.contains("dvorak") || lowerID.contains("colemak") || lowerID.contains("azerty") {
            return false
        }
        let lowerLang = language.lowercased()
        if !lowerLang.hasPrefix("en") && lowerLang != "en" {
            return false
        }
        return true
    }
    
    public static func invalidateCache() {
        lock.lock()
        cachedIsCompatible = nil
        lock.unlock()
    }
    
    public static func setupNotificationObserverIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !observerInstalled else { return }
        observerInstalled = true
        
        let notificationName = NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
        DistributedNotificationCenter.default().addObserver(
            forName: notificationName,
            object: nil,
            queue: nil
        ) { _ in
            InputSourceGuard.invalidateCache()
        }
    }
    
    public static func isEnglishCurrentInputSource() -> Bool {
        setupNotificationObserverIfNeeded()
        
        lock.lock()
        if let cached = cachedIsCompatible {
            lock.unlock()
            return cached
        }
        lock.unlock()
        
        guard let isource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return true
        }
        
        var sourceID = ""
        if let idPtr = TISGetInputSourceProperty(isource, kTISPropertyInputSourceID) {
            sourceID = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
        }
        
        var lang = "en"
        if let ptr = TISGetInputSourceProperty(isource, kTISPropertyInputSourceLanguages) {
            let languages = Unmanaged<CFArray>.fromOpaque(ptr).takeUnretainedValue() as [AnyObject]
            if let first = languages.first as? String {
                lang = first
            }
        }
        
        let result = isCompatibleInputSource(language: lang, inputSourceID: sourceID)
        lock.lock()
        cachedIsCompatible = result
        lock.unlock()
        return result
    }
    
    public static func isVietnameseProcessingAllowed(otherLanguageEnabled: Bool) -> Bool {
        if !otherLanguageEnabled {
            return true
        }
        return isEnglishCurrentInputSource()
    }
}
