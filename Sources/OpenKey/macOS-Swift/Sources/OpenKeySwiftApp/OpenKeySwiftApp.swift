import Cocoa
import SwiftUI
import OpenKeySwiftCore

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static var sharedDelegate: AppDelegate?
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var settingsWindowController: NSWindowController?
    private var workspaceObserver: NSObjectProtocol?
    private let settings = OpenKeySettingsStore.shared
    private let coordinator = EventTapCoordinator.shared
    
    // Pre-cached monochrome icons (15.5 x 15.5pt filled keycap with knockout character, 18x18 canvas)
    private let vietnameseIcon: NSImage = AppDelegate.makeStatusIcon(isVietnamese: true)
    private let englishIcon: NSImage = AppDelegate.makeStatusIcon(isVietnamese: false)
    private let vietnameseBypassedIcon: NSImage = AppDelegate.makeStatusIcon(isVietnamese: true, isBypassed: true)
    private let englishBypassedIcon: NSImage = AppDelegate.makeStatusIcon(isVietnamese: false, isBypassed: true)
    private let vietnameseUntrustedIcon: NSImage = AppDelegate.makeStatusIcon(isVietnamese: true, isAccessibilityMissing: true)
    private let englishUntrustedIcon: NSImage = AppDelegate.makeStatusIcon(isVietnamese: false, isAccessibilityMissing: true)
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("OpenKey Menu Bar Input Method")
        OpenKeyLogger.shared.checkVersionRetention()
        setupStatusItem()
        coordinator.start()
        updateStatusItemTitle()
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateStatusItemTitle()
            }
        }
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItemTitle()
        
        let menu = NSMenu()
        menu.delegate = self
        self.statusMenu = menu
        statusItem?.menu = menu
        buildMenuItems(in: menu)
        
        settings.onLanguageChanged = { [weak self] _ in
            self?.updateStatusItemTitle()
        }
    }
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        updateStatusItemTitle()
        buildMenuItems(in: menu)
    }
    
    public static func makeStatusIcon(
        isVietnamese: Bool,
        isBypassed: Bool = false,
        isAccessibilityMissing: Bool = false
    ) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let badgeRect = NSRect(x: 1.25, y: 1.25, width: 15.5, height: 15.5)
            let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 3.6, yRadius: 3.6)
            NSColor.black.setFill()
            badgePath.fill()
            
            let context = NSGraphicsContext.current?.cgContext
            context?.setBlendMode(.clear)
            NSColor.black.setStroke()
            
            let offsetX: CGFloat = (isBypassed || isAccessibilityMissing) ? -1.4 : 0.0
            if isVietnamese {
                let vPath = NSBezierPath()
                vPath.move(to: NSPoint(x: 5.0 + offsetX, y: 13.5))
                vPath.line(to: NSPoint(x: 9.0 + offsetX, y: 4.3))
                vPath.line(to: NSPoint(x: 13.0 + offsetX, y: 13.5))
                vPath.lineWidth = 2.15
                vPath.lineCapStyle = .round
                vPath.lineJoinStyle = .round
                vPath.stroke()
            } else {
                let ePath = NSBezierPath()
                ePath.move(to: NSPoint(x: 12.2 + offsetX, y: 13.4))
                ePath.line(to: NSPoint(x: 5.8 + offsetX, y: 13.4))
                ePath.line(to: NSPoint(x: 5.8 + offsetX, y: 4.6))
                ePath.line(to: NSPoint(x: 12.2 + offsetX, y: 4.6))
                ePath.move(to: NSPoint(x: 5.8 + offsetX, y: 9.0))
                ePath.line(to: NSPoint(x: 11.2 + offsetX, y: 9.0))
                ePath.lineWidth = 2.05
                ePath.lineCapStyle = .round
                ePath.lineJoinStyle = .round
                ePath.stroke()
            }
            
            if isAccessibilityMissing {
                let bang = NSBezierPath()
                bang.move(to: NSPoint(x: 14.3, y: 13.2))
                bang.line(to: NSPoint(x: 14.3, y: 7.4))
                bang.lineWidth = 1.8
                bang.lineCapStyle = .round
                bang.stroke()
                let dot = NSBezierPath(ovalIn: NSRect(x: 13.4, y: 4.3, width: 1.8, height: 1.8))
                dot.fill()
            } else if isBypassed {
                let dot = NSBezierPath(ovalIn: NSRect(x: 13.1, y: 4.3, width: 2.3, height: 2.3))
                dot.fill()
            }
            
            context?.setBlendMode(.normal)
            return true
        }
        image.isTemplate = true
        return image
    }
    
    private func updateStatusItemTitle() {
        guard let button = statusItem?.button else { return }
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        let isVi = settings.language == 1
        if !settings.isAccessibilityTrusted {
            button.image = isVi ? vietnameseUntrustedIcon : englishUntrustedIcon
        } else if EventTapCoordinator.isBypassedApp(bundleId: settings.resolveTargetAppBundleId()) {
            button.image = isVi ? vietnameseBypassedIcon : englishBypassedIcon
        } else {
            button.image = isVi ? vietnameseIcon : englishIcon
        }
    }
    
    private func buildMenuItems(in menu: NSMenu) {
        menu.removeAllItems()
        let l10n = OpenKeyL10n(isVietnamese: settings.uiLanguage == 1)
        
        if !settings.isAccessibilityTrusted {
            let axItem = NSMenuItem(title: l10n.menuAccessibilityMissing, action: #selector(openSettings), keyEquivalent: "")
            axItem.target = self
            menu.addItem(axItem)
            menu.addItem(NSMenuItem.separator())
        }
        
        let shortcutLabel = HotKeyMatcher.describe(config: settings.switchKeyStatus)
        let toggleItem = NSMenuItem(title: l10n.menuVietnamese(shortcut: shortcutLabel), action: #selector(toggleLanguage), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.state = (settings.language == 1) ? .on : .off
        menu.addItem(toggleItem)
        
        if let targetBundle = settings.resolveTargetAppBundleId(),
           !EventTapCoordinator.isTerminalApp(bundleId: targetBundle),
           !EventTapCoordinator.isLauncherApp(bundleId: targetBundle) {
            let appName = NSRunningApplication.runningApplications(withBundleIdentifier: targetBundle).first?.localizedName ?? targetBundle
            let bypassItem = NSMenuItem(title: l10n.menuBypassApp(appName), action: #selector(toggleBypassCurrentApp), keyEquivalent: "")
            bypassItem.target = self
            bypassItem.representedObject = targetBundle
            bypassItem.state = settings.isAppExcluded(targetBundle) ? .on : .off
            menu.addItem(bypassItem)
        }
        
        let smartSwitchItem = NSMenuItem(title: l10n.menuSmartSwitch, action: #selector(toggleSmartSwitch), keyEquivalent: "")
        smartSwitchItem.target = self
        smartSwitchItem.state = settings.useSmartSwitchKey ? .on : .off
        menu.addItem(smartSwitchItem)
        
        let resetSmartSwitchItem = NSMenuItem(title: l10n.menuResetSmartSwitch, action: #selector(resetSmartSwitch), keyEquivalent: "")
        resetSmartSwitchItem.target = self
        menu.addItem(resetSmartSwitchItem)
        
        let debugModeItem = NSMenuItem(title: l10n.menuDebugMode, action: #selector(toggleDebugMode), keyEquivalent: "")
        debugModeItem.target = self
        debugModeItem.state = settings.debugModeEnabled ? .on : .off
        menu.addItem(debugModeItem)
        
        if settings.debugModeEnabled {
            let openLogItem = NSMenuItem(title: l10n.menuOpenLogFile, action: #selector(openDebugLog), keyEquivalent: "")
            openLogItem.target = self
            menu.addItem(openLogItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        let telexItem = NSMenuItem(title: "Telex", action: #selector(selectTelex), keyEquivalent: "")
        telexItem.target = self
        telexItem.state = (settings.inputType == 0) ? .on : .off
        menu.addItem(telexItem)
        
        let vniItem = NSMenuItem(title: "VNI", action: #selector(selectVNI), keyEquivalent: "")
        vniItem.target = self
        vniItem.state = (settings.inputType == 1) ? .on : .off
        menu.addItem(vniItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(title: l10n.menuSettings, action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let aboutItem = NSMenuItem(title: l10n.menuAbout, action: nil, keyEquivalent: "")
        aboutItem.isEnabled = false
        menu.addItem(aboutItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: l10n.menuQuit, action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    @objc private func toggleLanguage() {
        settings.toggleLanguage()
        updateStatusItemTitle()
    }
    
    @objc private func toggleBypassCurrentApp(_ sender: NSMenuItem) {
        guard let bundleId = sender.representedObject as? String else { return }
        settings.toggleAppExclusion(bundleId)
        updateStatusItemTitle()
    }
    
    @objc private func toggleSmartSwitch() {
        settings.useSmartSwitchKey.toggle()
    }
    
    @objc private func resetSmartSwitch() {
        settings.resetSmartSwitchData()
    }
    
    @objc private func toggleDebugMode() {
        settings.debugModeEnabled.toggle()
    }
    
    @objc private func openDebugLog() {
        OpenKeyLogger.shared.openLogFile()
    }
    
    @objc private func selectTelex() {
        settings.inputType = 0
    }
    
    @objc private func selectVNI() {
        settings.inputType = 1
    }
    
    @objc private func openSettings() {
        let l10n = OpenKeyL10n(isVietnamese: settings.uiLanguage == 1)
        if settingsWindowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 640),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = l10n.windowTitle
            window.center()
            window.contentView = NSHostingView(rootView: SettingsView())
            settingsWindowController = NSWindowController(window: window)
        } else {
            settingsWindowController?.window?.title = l10n.windowTitle
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        sharedDelegate = delegate
        app.delegate = delegate
        app.run()
    }
}
