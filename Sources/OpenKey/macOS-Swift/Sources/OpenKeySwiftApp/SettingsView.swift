import SwiftUI
import Observation
import ServiceManagement
import OpenKeySwiftCore

@Observable final class SettingsUIModel: @unchecked Sendable {
    var isRecordingShortcut: Bool = false
    var localEventMonitor: Any? = nil
    var launchAtLoginError: String? = nil
    var newTrigger: String = ""
    var newExpansion: String = ""
}

public struct SettingsView: View {
    @Bindable var settings: OpenKeySettingsStore = OpenKeySettingsStore.shared
    private var ui = SettingsUIModel()
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header / Accessibility Status Banner with Liquid Glass
            accessibilityBanner
                .padding()
            
            Form {
                // 1. Input & Language Section (with per-app memory toggle placed prominently)
                Section(header: Label("Bộ gõ & Ngôn ngữ (Input & Language)", systemImage: "keyboard")) {
                    Picker("Ngôn ngữ (Language):", selection: $settings.language) {
                        Text("Tiếng Việt").tag(1)
                        Text("English").tag(0)
                    }
                    .pickerStyle(.segmented)
                    
                    Picker("Kiểu gõ (Input Type):", selection: $settings.inputType) {
                        Text("Telex").tag(0)
                        Text("VNI").tag(1)
                    }
                    
                    Toggle("Nhớ ngôn ngữ theo từng ứng dụng (Remember language per app)", isOn: $settings.useSmartSwitchKey)
                }
                
                // 2. Shortcut Section with Interactive Recorder
                Section(header: Label("Phím chuyển (Shortcut Switch)", systemImage: "command")) {
                    HStack {
                        Text("Phím tắt hiện tại:")
                        Spacer()
                        Text(HotKeyMatcher.describe(config: settings.switchKeyStatus))
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .glassEffect(.regular, in: .capsule)
                        
                        if ui.isRecordingShortcut {
                            Button("Hủy (Esc)") {
                                stopRecordingShortcut()
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button("Đổi phím tắt...") {
                                startRecordingShortcut()
                            }
                        }
                        
                        Button("Mặc định (⌥Z)") {
                            stopRecordingShortcut()
                            settings.switchKeyStatus = OpenKeySettingsStore.defaultSwitchKey
                        }
                    }
                    
                    if ui.isRecordingShortcut {
                        Text("Nhấn tổ hợp phím mong muốn (ví dụ ⌥Z, ⌃⇧Space, hoặc phím chức năng). Nhấn Esc để hủy.")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                    
                    Toggle("Phát âm thanh khi chuyển (Beep on switch)", isOn: $settings.beepOnSwitch)
                }
                
                // 3. Orthography & Spelling Options
                Section(header: Label("Chính tả & Tùy chọn gõ (Orthography)", systemImage: "checkmark.bubble")) {
                    Toggle("Kiểm tra chính tả (Check spelling)", isOn: $settings.checkSpelling)
                    Toggle("Tự động khôi phục từ sai (Auto-restore invalid words)", isOn: $settings.restoreIfWrongSpelling)
                    Toggle("Bỏ dấu kiểu mới (Modern orthography: oà, uý)", isOn: $settings.useModernOrthography)
                }
                
                // 3.5. Auto Wording & Grammar Section (REQ-001, REQ-005, REQ-006)
                Section(header: Label("Auto Wording & Ngữ pháp (Thử nghiệm)", systemImage: "sparkles")) {
                    Toggle("Bật Auto Wording & Gợi ý từ (Auto wording)", isOn: $settings.autoWordingEnabled)
                    
                    Toggle("Tự động sửa lỗi ngữ âm (ie/ye → iê/yê, uow → ươ)", isOn: $settings.grammarRepairEnabled)
                        .disabled(!settings.autoWordingEnabled)
                        
                    Toggle("Tự động viết tắt (ko → không, dc → được, vn → Việt Nam...)", isOn: $settings.shorthandExpansionEnabled)
                        .disabled(!settings.autoWordingEnabled)
                        
                    Toggle("Hiện thanh gợi ý từ Liquid Glass (Candidate bar)", isOn: $settings.candidateSuggestionsEnabled)
                        .disabled(!settings.autoWordingEnabled)
                        
                    if settings.autoWordingEnabled && settings.shorthandExpansionEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Gõ tắt tùy chỉnh (Custom Shorthands):")
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
                                TextField("Viết tắt (vd: cv)", text: Binding(
                                    get: { ui.newTrigger },
                                    set: { ui.newTrigger = $0 }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                                
                                TextField("Mở rộng (vd: công việc)", text: Binding(
                                    get: { ui.newExpansion },
                                    set: { ui.newExpansion = $0 }
                                ))
                                .textFieldStyle(.roundedBorder)
                                
                                Button("Thêm") {
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
                                Text("Dữ liệu tần suất học từ:")
                                    .font(.subheadline)
                                Text("Gợi ý từ tự động thích ứng với thói quen gõ của bạn.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Xóa dữ liệu học từ") {
                                AutoWordingEngine.shared.resetLearnedFrequencies()
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // 4. Workarounds & Browser Fixes
                Section(header: Label("Sửa lỗi ứng dụng & Trình duyệt (App Fixes)", systemImage: "wrench.and.screwdriver")) {
                    Toggle("Khắc phục gợi ý thanh địa chỉ trình duyệt (Browser fix)", isOn: $settings.fixRecommendBrowser)
                    Toggle("Tắt gõ tiếng Việt khi dùng layout không phải tiếng Anh", isOn: $settings.otherLanguage)
                }
                
                // 5. System Section with Error Recovery
                Section(header: Label("Hệ thống (System)", systemImage: "gearshape")) {
                    Toggle("Khởi động cùng máy tính (Launch at login)", isOn: $settings.launchAtLogin)
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
                
                // 6. About & Conversion Provenance
                Section(header: Label("Giới thiệu (About)", systemImage: "info.circle")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("OpenKeySwift — Bản chuyển đổi 100% Pure Swift 6 (macOS 26)")
                            .font(.headline)
                        Text("Được chuyển đổi hoàn toàn sang ngôn ngữ Swift 6 từ bộ gõ mã nguồn mở OpenKey (C++/Objective-C++) của tác giả Mai Vũ Tuyên.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("© Mai Vũ Tuyên • Giấy phép GNU GPLv3")
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
        }
        .onDisappear {
            stopRecordingShortcut()
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
                    Text("Quyền Trợ năng đã sẵn sàng")
                        .font(.headline)
                    Text("OpenKey có đầy đủ quyền can thiệp phím để gõ tiếng Việt.")
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
                    Text("Chưa cấp quyền Trợ năng (Accessibility)")
                        .font(.headline)
                    Text("Cần cấp quyền Trợ năng trong Cài đặt hệ thống để gõ được tiếng Việt.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Mở Cài đặt") {
                    openAccessibilitySettings()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(12)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
        }
    }
    
    private func openAccessibilitySettings() {
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
