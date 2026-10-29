import SwiftUI
import Observation
import ServiceManagement
import OpenKeySwiftCore

@Observable final class SettingsUIModel: @unchecked Sendable {
    var isRecordingShortcut: Bool = false
    var localEventMonitor: Any? = nil
    var escapeEventMonitor: Any? = nil
    var launchAtLoginError: String? = nil
    var newTrigger: String = ""
    var newExpansion: String = ""
}

public struct SettingsView: View {
    @Bindable var settings: OpenKeySettingsStore = OpenKeySettingsStore.shared
    private var ui = SettingsUIModel()
    
    private var l10n: OpenKeyL10n {
        OpenKeyL10n(isVietnamese: settings.uiLanguage == 1)
    }
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header / Accessibility Status Banner with Segmented VI | EN Language Picker
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
                    
                    Toggle(l10n.smartSwitch, isOn: $settings.useSmartSwitchKey)
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
                            settings.switchKeyStatus = OpenKeySettingsStore.defaultSwitchKey
                        }
                    }
                    
                    if ui.isRecordingShortcut {
                        Text(l10n.recordingHint)
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                    
                    Toggle(l10n.beepOnSwitch, isOn: $settings.beepOnSwitch)
                }
                
                // 3. Orthography & Spelling Options
                Section(header: Label(l10n.sectionOrthography, systemImage: "checkmark.bubble")) {
                    Toggle(l10n.checkSpelling, isOn: $settings.checkSpelling)
                    Toggle(l10n.autoRestore, isOn: $settings.restoreIfWrongSpelling)
                    Toggle(l10n.modernOrthography, isOn: $settings.useModernOrthography)
                }
                
                // 4. Auto Wording & Grammar Section
                Section(header: Label(l10n.sectionAutoWording, systemImage: "sparkles")) {
                    Toggle(l10n.enableAutoWording, isOn: $settings.autoWordingEnabled)
                    
                    Toggle(l10n.grammarRepair, isOn: $settings.grammarRepairEnabled)
                        .disabled(!settings.autoWordingEnabled)
                        
                    Toggle(l10n.shorthandExpansion, isOn: $settings.shorthandExpansionEnabled)
                        .disabled(!settings.autoWordingEnabled)
                        
                    Toggle(l10n.candidateBar, isOn: $settings.candidateSuggestionsEnabled)
                        .disabled(!settings.autoWordingEnabled)
                        
                    if settings.autoWordingEnabled && settings.shorthandExpansionEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(l10n.customShorthandsTitle)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            ForEach(Array(settings.customShorthands.keys.sorted()), id: \.self) { trigger in
                                HStack {
                                    Text(trigger)
                                        .font(.system(.body, design: .monospaced))
                                        .bold()
                                        .frame(width: 80, alignment: .leading)
                                    Image(systemName: "arrow.right")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(settings.customShorthands[trigger] ?? "")
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Button(action: {
                                        settings.removeCustomShorthand(trigger: trigger)
                                    }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 2)
                            }
                            
                            HStack(spacing: 8) {
                                TextField(l10n.triggerPlaceholder, text: Binding(
                                    get: { ui.newTrigger },
                                    set: { ui.newTrigger = $0 }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                                
                                TextField(l10n.expansionPlaceholder, text: Binding(
                                    get: { ui.newExpansion },
                                    set: { ui.newExpansion = $0 }
                                ))
                                .textFieldStyle(.roundedBorder)
                                
                                Button(l10n.addButton) {
                                    settings.setCustomShorthand(trigger: ui.newTrigger, replacement: ui.newExpansion)
                                    ui.newTrigger = ""
                                    ui.newExpansion = ""
                                }
                                .disabled(ui.newTrigger.trimmingCharacters(in: .whitespaces).isEmpty || ui.newExpansion.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    if settings.autoWordingEnabled && settings.candidateSuggestionsEnabled {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(l10n.learnedFreqTitle)
                                    .font(.subheadline)
                                Text(l10n.learnedFreqSubtitle)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(l10n.resetLearnedButton) {
                                AutoWordingEngine.shared.resetLearnedFrequencies()
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // 5. Workarounds & App Compatibility
                Section(header: Label(l10n.sectionAppFixes, systemImage: "wrench.and.screwdriver")) {
                    Toggle(l10n.fixBrowser, isOn: $settings.fixRecommendBrowser)
                    Toggle(l10n.otherLanguage, isOn: $settings.otherLanguage)
                }
                
                // 6. System Section
                Section(header: Label(l10n.sectionSystem, systemImage: "gearshape")) {
                    Toggle(l10n.launchAtLogin, isOn: $settings.launchAtLogin)
                        .onChange(of: settings.launchAtLogin) { oldValue, newValue in
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
                }
                
                // 7. About & Conversion Provenance
                Section(header: Label(l10n.sectionAbout, systemImage: "info.circle")) {
                    VStack(alignment: .leading, spacing: 8) {
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
                    .padding(.vertical, 4)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 500, height: 760)
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
                Button(l10n.openSystemSettings) {
                    openAccessibilitySettings()
                }
                .buttonStyle(.borderedProminent)
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
        if !settings.isAccessibilityTrusted {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            proc.arguments = ["reset", "Accessibility", "com.tuyenmai.openkey.swift"]
            try? proc.run()
            proc.waitUntilExit()
            EventTapCoordinator.shared.checkAccessibilityAndSetupTap()
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func checkLaunchAtLoginStatus() {
        settings.launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }
    
    private func handleLaunchAtLoginChange(_ enabled: Bool) {
        ui.launchAtLoginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            ui.launchAtLoginError = "Lỗi khi cấu hình tự khởi động: \(error.localizedDescription)"
            settings.launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }
    
    private func startRecordingShortcut() {
        stopRecordingShortcut()
        ui.isRecordingShortcut = true
        
        ui.localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            // Esc cancels recording
            if event.type == .keyDown && event.keyCode == 53 {
                self.stopRecordingShortcut()
                return nil
            }
            
            let flags = event.modifierFlags
            let needCtrl = flags.contains(.control)
            let needOpt = flags.contains(.option)
            let needCmd = flags.contains(.command)
            let needShift = flags.contains(.shift)
            
            if event.type == .keyDown {
                // Captured regular key + modifiers
                let asciiVal = event.charactersIgnoringModifiers?.uppercased().first?.asciiValue ?? 0
                let encoded = HotKeyMatcher.encode(
                    keyCode: event.keyCode,
                    control: needCtrl,
                    option: needOpt,
                    command: needCmd,
                    shift: needShift,
                    displayChar: asciiVal
                )
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
        ui.isRecordingShortcut = false
    }
}
