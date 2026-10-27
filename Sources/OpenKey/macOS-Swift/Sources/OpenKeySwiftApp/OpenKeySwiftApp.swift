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
    private let settings = OpenKeySettingsStore.shared
    private let coordinator = EventTapCoordinator.shared
    
    // Pre-cached monochrome icons (15.5 x 15.5pt filled keycap with knockout character, 18x18 canvas)
    private let vietnameseIcon: NSImage = AppDelegate.makeStatusIcon(isVietnamese: true)
    private let englishIcon: NSImage = AppDelegate.makeStatusIcon(isVietnamese: false)
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("OpenKey Menu Bar Input Method")
        setupStatusItem()
        coordinator.start()
        CandidateBarController.shared.start()
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
        buildMenuItems(in: menu)
    }
    
    public static func makeStatusIcon(isVietnamese: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            // Solid keycap badge for both V and E
            let badgeRect = NSRect(x: 1.25, y: 1.25, width: 15.5, height: 15.5)
            let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 3.6, yRadius: 3.6)
            NSColor.black.setFill()
            badgePath.fill()
            
            let context = NSGraphicsContext.current?.cgContext
            context?.setBlendMode(.clear)
            NSColor.black.setStroke()
            
            if isVietnamese {
                // Knockout "V"
                let vPath = NSBezierPath()
                vPath.move(to: NSPoint(x: 5.0, y: 13.5))
                vPath.line(to: NSPoint(x: 9.0, y: 4.3))
                vPath.line(to: NSPoint(x: 13.0, y: 13.5))
                vPath.lineWidth = 2.25
                vPath.lineCapStyle = .round
                vPath.lineJoinStyle = .round
                vPath.stroke()
            } else {
                // Knockout "E"
                let ePath = NSBezierPath()
                // Spine + top/bottom bars
                ePath.move(to: NSPoint(x: 12.4, y: 13.4))
                ePath.line(to: NSPoint(x: 5.8, y: 13.4))
                ePath.line(to: NSPoint(x: 5.8, y: 4.6))
                ePath.line(to: NSPoint(x: 12.4, y: 4.6))
                
                // Middle bar
                ePath.move(to: NSPoint(x: 5.8, y: 9.0))
                ePath.line(to: NSPoint(x: 11.4, y: 9.0))
                
                ePath.lineWidth = 2.15
                ePath.lineCapStyle = .round
                ePath.lineJoinStyle = .round
                ePath.stroke()
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
        button.image = (settings.language == 1) ? vietnameseIcon : englishIcon
    }
    
    private func buildMenuItems(in menu: NSMenu) {
        menu.removeAllItems()
        
        let toggleItem = NSMenuItem(title: "Tiếng Việt (Option+Z)", action: #selector(toggleLanguage), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.state = (settings.language == 1) ? .on : .off
        menu.addItem(toggleItem)
        
        let smartSwitchItem = NSMenuItem(title: "Nhớ ngôn ngữ theo ứng dụng", action: #selector(toggleSmartSwitch), keyEquivalent: "")
        smartSwitchItem.target = self
        smartSwitchItem.state = settings.useSmartSwitchKey ? .on : .off
        menu.addItem(smartSwitchItem)
        
        let autoWordingItem = NSMenuItem(title: "Auto Wording & Gợi ý từ (Thử nghiệm)", action: #selector(toggleAutoWording), keyEquivalent: "")
        autoWordingItem.target = self
        autoWordingItem.state = settings.autoWordingEnabled ? .on : .off
        menu.addItem(autoWordingItem)
        
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
        
        let settingsItem = NSMenuItem(title: "Bảng điều khiển (Settings)...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let aboutItem = NSMenuItem(title: "Chuyển đổi Pure Swift 6 từ OpenKey (Mai Vũ Tuyên)", action: nil, keyEquivalent: "")
        aboutItem.isEnabled = false
        menu.addItem(aboutItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Thoát (Quit)", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    @objc private func toggleLanguage() {
        settings.toggleLanguage()
        updateStatusItemTitle()
    }
    
    @objc private func toggleSmartSwitch() {
        settings.useSmartSwitchKey.toggle()
    }
    
    @objc private func toggleAutoWording() {
        settings.autoWordingEnabled.toggle()
    }
    
    @objc private func selectTelex() {
        settings.inputType = 0
    }
    
    @objc private func selectVNI() {
        settings.inputType = 1
    }
    
    @objc private func openSettings() {
        if settingsWindowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "OpenKey - Cài đặt"
            window.center()
            window.contentView = NSHostingView(rootView: SettingsView())
            settingsWindowController = NSWindowController(window: window)
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
