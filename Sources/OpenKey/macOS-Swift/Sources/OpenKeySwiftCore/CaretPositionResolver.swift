//
//  CaretPositionResolver.swift
//  OpenKeySwiftCore
//
//  Created for OpenKey macOS Swift.
//  AXUIElement Caret Tracking, Electron/Chromium AXManualAccessibility & Multi-Monitor Clamping.
//

#if canImport(AppKit)
import AppKit
#endif
import ApplicationServices
import Foundation

public enum CaretPositionResolver {
    private static let pidLock = NSLock()
    nonisolated(unsafe) private static var enabledAccessibilityPIDs = Set<pid_t>()
    
    public static func enableManualAccessibilityIfNeeded(for appElement: AXUIElement, pid: pid_t) {
        pidLock.lock()
        let alreadyEnabled = enabledAccessibilityPIDs.contains(pid)
        if !alreadyEnabled {
            enabledAccessibilityPIDs.insert(pid)
        }
        pidLock.unlock()
        
        if !alreadyEnabled {
            AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }
    }
    
    public static func isAccessibilityEnabled(for pid: pid_t) -> Bool {
        pidLock.lock()
        defer { pidLock.unlock() }
        return enabledAccessibilityPIDs.contains(pid)
    }
    
    public static func resetAccessibilityPIDs() {
        pidLock.lock()
        enabledAccessibilityPIDs.removeAll()
        pidLock.unlock()
    }
    
    #if canImport(AppKit)
    public static func screenContaining(point: NSPoint) -> NSScreen? {
        return NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens.first
    }
    #endif

    public static func resolveCaretScreenPoint() -> CGPoint {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedAppVal: AnyObject?
        
        if AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedAppVal) == .success,
           let focusedApp = focusedAppVal {
            let appElement = focusedApp as! AXUIElement
            var pid: pid_t = 0
            if AXUIElementGetPid(appElement, &pid) == .success {
                enableManualAccessibilityIfNeeded(for: appElement, pid: pid)
            }
            
            var focusedElementVal: AnyObject?
            if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElementVal) == .success,
               let focusedElement = focusedElementVal {
                let uiElement = focusedElement as! AXUIElement
                
                // 1. Try kAXSelectedTextRangeParameterizedAttribute bounds
                var selectedRangeVal: AnyObject?
                if AXUIElementCopyAttributeValue(uiElement, kAXSelectedTextRangeAttribute as CFString, &selectedRangeVal) == .success,
                   let rangeVal = selectedRangeVal {
                    var range = CFRange()
                    if AXValueGetValue(rangeVal as! AXValue, .cfRange, &range) {
                        var boundsVal: AnyObject?
                        let cfRangeValue = AXValueCreate(.cfRange, &range)
                        if let cfRangeValue = cfRangeValue,
                           AXUIElementCopyParameterizedAttributeValue(
                            uiElement,
                            kAXBoundsForRangeParameterizedAttribute as CFString,
                            cfRangeValue,
                            &boundsVal
                           ) == .success,
                           let bVal = boundsVal {
                            var rect = CGRect.zero
                            if AXValueGetValue(bVal as! AXValue, .cgRect, &rect) && rect.width > 0 && rect.height > 0 {
                                #if canImport(AppKit)
                                let mainScreenHeight = NSScreen.screens.first?.frame.height ?? 1080
                                #else
                                let mainScreenHeight: CGFloat = 1080
                                #endif
                                let cocoaY = mainScreenHeight - rect.origin.y - rect.size.height - 6
                                return CGPoint(x: rect.origin.x, y: cocoaY)
                            }
                        }
                    }
                }
                
                // 2. Try element position fallback
                var posVal: AnyObject?
                var sizeVal: AnyObject?
                if AXUIElementCopyAttributeValue(uiElement, kAXPositionAttribute as CFString, &posVal) == .success,
                   AXUIElementCopyAttributeValue(uiElement, kAXSizeAttribute as CFString, &sizeVal) == .success,
                   let pVal = posVal, let sVal = sizeVal {
                    var pt = CGPoint.zero
                    var sz = CGSize.zero
                    if AXValueGetValue(pVal as! AXValue, .cgPoint, &pt) && AXValueGetValue(sVal as! AXValue, .cgSize, &sz) {
                        #if canImport(AppKit)
                        let mainScreenHeight = NSScreen.screens.first?.frame.height ?? 1080
                        #else
                        let mainScreenHeight: CGFloat = 1080
                        #endif
                        let cocoaY = mainScreenHeight - pt.y - sz.height - 6
                        return CGPoint(x: pt.x, y: cocoaY)
                    }
                }
            }
        }
        
        // 3. Fallback: Mouse cursor location
        #if canImport(AppKit)
        let mouse = NSEvent.mouseLocation
        return CGPoint(x: mouse.x + 10, y: mouse.y - 30)
        #else
        return CGPoint(x: 100, y: 100)
        #endif
    }
}
