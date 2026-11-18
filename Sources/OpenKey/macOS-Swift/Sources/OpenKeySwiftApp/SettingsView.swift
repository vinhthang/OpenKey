import SwiftUI
import Observation
import ServiceManagement
import OpenKeySwiftCore

@Observable final class SettingsUIModel: @unchecked Sendable {
    var isRecordingShortcut: Bool = false
    var localEventMonitor: Any? = nil
    var escapeEventMonitor: Any? = nil
    var launchAtLoginError: String? = nil
    var shortcutError: String? = nil
    var recordedModifierFlags: NSEvent.ModifierFlags = []
    var isSyncingLaunchAtLogin: Bool = false
}

public struct SettingsView: View {
    @Bindable var settings: OpenKeySettingsStore = OpenKeySettingsStore.shared
    private var _ui = State(initialValue: SettingsUIModel())
    private var ui: SettingsUIModel { _ui.wrappedValue }
    
    private static let functionKeyCodes: Set<UInt16> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90
    ]
    
    private var l10n: OpenKeyL10n {
        OpenKeyL10n(isVietnamese: settings.uiLanguage == 1)
    }
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                accessibilityBanner
                VStack(alignment: .trailing, spacing: 4) {
                    Text(l10n.uiLanguageLabel)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Picker("", selection: $settings.uiLanguage) {
                        Text("VI").tag(1)
                        Text("EN").tag(0)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 84)
                }
                .padding(10)
                .glassEffect(.regular, in: .rect(cornerRadius: 12))
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 4)
            
            Form {
                // 1. Input & Language Section
                Section(header: Label(l10n.sectionInput, systemImage: "keyboard")) {
                    Picker(l10n.inputLanguage, selection: $settings.language) {
                        Text("Tiếng Việt").tag(1)
                        Text("English").tag(0)
                    }
                    .pickerStyle(.segmented)
                    
                    Picker(l10n.inputType, selection: $settings.inputType) {
                        Text("Telex").tag(0)
                        Text("VNI").tag(1)
                    }
                    
                    if settings.inputType == 0 {
                        Toggle(l10n.quickTelex, isOn: $settings.quickTelexEnabled)
                    }
                    
                    HStack {
                        Toggle(l10n.smartSwitch, isOn: $settings.useSmartSwitchKey)
                        Spacer()
                        Button(l10n.resetSmartSwitch) {
                            settings.resetSmartSwitchData()
                        }
                        .controlSize(.small)
                    }
                }
                
                // 2. Shortcut Section with Interactive Recorder
                Section(header: Label(l10n.sectionShortcut, systemImage: "command")) {
                    HStack {
                        Text(l10n.currentShortcut)
                        Spacer()
                        Text(HotKeyMatcher.describe(config: settings.switchKeyStatus))
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .glassEffect(.regular, in: .capsule)
                        
                        if ui.isRecordingShortcut {
                            Button(l10n.cancelShortcut) {
                                stopRecordingShortcut()
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button(l10n.changeShortcut) {
                                startRecordingShortcut()
                            }
                        }
                        
                        Button(l10n.defaultShortcut) {
                            stopRecordingShortcut()
                            ui.shortcutError = nil
                            settings.switchKeyStatus = OpenKeySettingsStore.defaultSwitchKey
                        }
                    }
                    
                    if ui.isRecordingShortcut {
                        Text(l10n.recordingHint)
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                    if let shortcutErr = ui.shortcutError {
                        Text(shortcutErr)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    
                    Toggle(l10n.beepOnSwitch, isOn: $settings.beepOnSwitch)
                }
                
                // 3. Orthography & Spelling Options
                Section(header: Label(l10n.sectionOrthography, systemImage: "checkmark.bubble")) {
                    Toggle(l10n.checkSpelling, isOn: $settings.checkSpelling)
                    Toggle(l10n.autoRestore, isOn: $settings.restoreIfWrongSpelling)
                    Toggle(l10n.modernOrthography, isOn: $settings.useModernOrthography)
                }
                
                // 4. Workarounds & App Compatibility
                Section(header: Label(l10n.sectionAppFixes, systemImage: "wrench.and.screwdriver")) {
                    Toggle(l10n.fixBrowser, isOn: $settings.fixRecommendBrowser)
                    Toggle(l10n.otherLanguage, isOn: $settings.otherLanguage)
                }
                
                // 5. System Section
                Section(header: Label(l10n.sectionSystem, systemImage: "gearshape")) {
                    Toggle(l10n.launchAtLogin, isOn: $settings.launchAtLogin)
                        .onChange(of: settings.launchAtLogin) { _, newValue in
                            guard !ui.isSyncingLaunchAtLogin else { return }
                            handleLaunchAtLoginChange(newValue)
                        }
                    
                    if let errorText = ui.launchAtLoginError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.red)
                            Text(errorText)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(l10n.debugModeTitle, isOn: $settings.debugModeEnabled)
                        Text(l10n.debugModeSubtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if settings.debugModeEnabled {
                            HStack(spacing: 8) {
                                Button(l10n.openLogFile) {
                                    OpenKeyLogger.shared.openLogFile()
                                }
                                Button(l10n.revealLogInFinder) {
                                    OpenKeyLogger.shared.revealLogInFinder()
                                }
                                Button(role: .destructive, action: {
                                    OpenKeyLogger.shared.clearLog()
                                }) {
                                    Text(l10n.clearLog)
                                }
                            }
                            .controlSize(.small)
                            .padding(.top, 2)
                        }
                    }
                }
                
                // 6. About & Conversion Provenance
                Section(header: Label(l10n.sectionAbout, systemImage: "info.circle")) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(l10n.versionLabel)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(width: 140, alignment: .leading)
                            Text(l10n.versionValue)
                                .font(.subheadline)
                                .bold()
                        }
                        HStack(alignment: .firstTextBaseline) {
                            Text(l10n.implementorLabel)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 140, alignment: .leading)
                            Text(l10n.implementorValue)
                                .font(.caption)
                        }
                        HStack(alignment: .firstTextBaseline) {
                            Text(l10n.originalAuthorLabel)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 140, alignment: .leading)
                            Text(l10n.originalAuthorValue)
                                .font(.caption)
                        }
                        Divider()
                            .padding(.vertical, 2)
                        Text(l10n.licenseFooter)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 500, height: 640)
        .onAppear {
            checkLaunchAtLoginStatus()
            setupEscapeMonitor()
        }
        .onDisappear {
            stopRecordingShortcut()
            removeEscapeMonitor()
        }
        .onChange(of: settings.uiLanguage) { _, _ in
            NSApp.keyWindow?.title = l10n.windowTitle
        }
    }
    
    @ViewBuilder
    private var accessibilityBanner: some View {
        if settings.isAccessibilityTrusted {
            HStack {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundColor(.green)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.accessReadyTitle)
                        .font(.headline)
                    Text(l10n.accessReadySubtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
        } else {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.accessMissingTitle)
                        .font(.headline)
                    Text(l10n.accessMissingSubtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Button(l10n.openSystemSettings) {
                        openAccessibilitySettings()
                    }
                    .buttonStyle(.borderedProminent)
                    Button(l10n.resetAccessibility) {
                        resetAccessibilityPermission()
                    }
                    .controlSize(.small)
                }
            }
            .padding(12)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
        }
    }
    
    private func setupEscapeMonitor() {
        removeEscapeMonitor()
        ui.escapeEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 {
                if self.ui.isRecordingShortcut {
                    self.stopRecordingShortcut()
                } else {
                    NSApp.keyWindow?.close()
                }
                return nil
            }
            return event
        }
    }
    
    private func removeEscapeMonitor() {
        if let monitor = ui.escapeEventMonitor {
            NSEvent.removeMonitor(monitor)
            ui.escapeEventMonitor = nil
        }
    }
    
    private func openAccessibilitySettings() {
        EventTapCoordinator.shared.checkAccessibilityAndSetupTap()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func resetAccessibilityPermission() {
        DispatchQueue.global(qos: .userInitiated).async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            proc.arguments = ["reset", "Accessibility", "com.tuyenmai.openkey.swift"]
            try? proc.run()
            proc.waitUntilExit()
            DispatchQueue.main.async {
                EventTapCoordinator.shared.resetAndCheckAccessibility()
            }
        }
    }
    
    private func checkLaunchAtLoginStatus() {
        ui.isSyncingLaunchAtLogin = true
        let status = SMAppService.mainApp.status
        settings.launchAtLogin = (status == .enabled)
        if status == .requiresApproval {
            ui.launchAtLoginError = l10n.launchAtLoginRequiresApproval
        } else {
            ui.launchAtLoginError = nil
        }
        ui.isSyncingLaunchAtLogin = false
    }
    
    private func handleLaunchAtLoginChange(_ enabled: Bool) {
        ui.launchAtLoginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    ui.launchAtLoginError = l10n.launchAtLoginRequiresApproval
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            ui.launchAtLoginError = l10n.launchAtLoginError(error.localizedDescription)
            ui.isSyncingLaunchAtLogin = true
            settings.launchAtLogin = (SMAppService.mainApp.status == .enabled)
            ui.isSyncingLaunchAtLogin = false
        }
    }
    
    private func startRecordingShortcut() {
        stopRecordingShortcut()
        ui.isRecordingShortcut = true
        ui.shortcutError = nil
        ui.recordedModifierFlags = []
        
        ui.localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .keyDown && event.keyCode == 53 {
                self.stopRecordingShortcut()
                return nil
            }
            
            let mask: NSEvent.ModifierFlags = [.control, .option, .command, .shift]
            let flags = event.modifierFlags.intersection(mask)
            
            if event.type == .flagsChanged {
                if !flags.isEmpty {
                    self.ui.recordedModifierFlags.formUnion(flags)
                } else if !self.ui.recordedModifierFlags.isEmpty {
                    let mod = self.ui.recordedModifierFlags
                    let encoded = HotKeyMatcher.encode(
                        keyCode: UInt16(HotKeyMatcher.modifierOnlyCode),
                        control: mod.contains(.control),
                        option: mod.contains(.option),
                        command: mod.contains(.command),
                        shift: mod.contains(.shift)
                    )
                    self.ui.shortcutError = nil
                    self.settings.switchKeyStatus = encoded
                    self.stopRecordingShortcut()
                }
                return event
            }
            
            if event.type == .keyDown {
                self.ui.recordedModifierFlags = []
                let hasModifier = !flags.isEmpty
                let isFunctionKey = Self.functionKeyCodes.contains(event.keyCode)
                guard hasModifier || isFunctionKey else {
                    self.ui.shortcutError = self.l10n.shortcutInvalidHint
                    return nil
                }
                let asciiVal = event.charactersIgnoringModifiers?.uppercased().first?.asciiValue ?? 0
                let encoded = HotKeyMatcher.encode(
                    keyCode: event.keyCode,
                    control: flags.contains(.control),
                    option: flags.contains(.option),
                    command: flags.contains(.command),
                    shift: flags.contains(.shift),
                    displayChar: asciiVal
                )
                self.ui.shortcutError = nil
                self.settings.switchKeyStatus = encoded
                self.stopRecordingShortcut()
                return nil
            }
            return event
        }
    }
    
    private func stopRecordingShortcut() {
        if let monitor = ui.localEventMonitor {
            NSEvent.removeMonitor(monitor)
            ui.localEventMonitor = nil
        }
        ui.recordedModifierFlags = []
        ui.isRecordingShortcut = false
    }
}
