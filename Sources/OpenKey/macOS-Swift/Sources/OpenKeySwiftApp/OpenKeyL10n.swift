import Foundation

public struct OpenKeyL10n: Sendable {
    public let isVietnamese: Bool
    
    public init(isVietnamese: Bool) {
        self.isVietnamese = isVietnamese
    }
    
    // Window & General
    public var windowTitle: String { isVietnamese ? "OpenKeySwift — Cài đặt" : "OpenKeySwift — Settings" }
    public var uiLanguageLabel: String { isVietnamese ? "Giao diện" : "UI Language" }
    
    // Accessibility Banner
    public var accessReadyTitle: String { isVietnamese ? "Quyền Trợ năng đã sẵn sàng" : "Accessibility Permission Active" }
    public var accessReadySubtitle: String { isVietnamese ? "OpenKeySwift đã sẵn sàng xử lý gõ tiếng Việt." : "OpenKeySwift is ready to process Vietnamese input." }
    public var accessMissingTitle: String { isVietnamese ? "Chưa cấp quyền Trợ năng" : "Accessibility Permission Required" }
    public var accessMissingSubtitle: String { isVietnamese ? "Hãy bật quyền cho OpenKeySwift trong Cài đặt Hệ thống." : "Grant permission in System Settings to enable Vietnamese typing." }
    public var openSystemSettings: String { isVietnamese ? "Mở Cài đặt" : "Open Settings" }
    public var resetAccessibility: String { isVietnamese ? "Đặt lại quyền" : "Reset Permission" }
    
    // Input & Language Section
    public var sectionInput: String { isVietnamese ? "Bộ gõ & Ngôn ngữ" : "Input & Language" }
    public var inputLanguage: String { isVietnamese ? "Chế độ gõ:" : "Input Mode:" }
    public var inputType: String { isVietnamese ? "Kiểu gõ:" : "Input Method:" }
    public var quickTelex: String { isVietnamese ? "Gõ tắt phụ âm đầu (Quick Telex: cc→ch, tt→tr...)" : "Quick Telex (cc→ch, gg→gi, tt→tr...)" }
    public var smartSwitch: String { isVietnamese ? "Nhớ ngôn ngữ theo từng ứng dụng" : "Remember input mode per application" }
    public var resetSmartSwitch: String { isVietnamese ? "Đặt lại nhớ ngôn ngữ" : "Reset Smart Switch" }
    
    // Shortcut Section
    public var sectionShortcut: String { isVietnamese ? "Phím tắt chuyển chế độ" : "Toggle Shortcut" }
    public var currentShortcut: String { isVietnamese ? "Phím tắt hiện tại:" : "Current shortcut:" }
    public var cancelShortcut: String { isVietnamese ? "Hủy (Esc)" : "Cancel (Esc)" }
    public var changeShortcut: String { isVietnamese ? "Đổi phím tắt..." : "Change..." }
    public var defaultShortcut: String { isVietnamese ? "Mặc định (⌥Z)" : "Default (⌥Z)" }
    public var recordingHint: String { isVietnamese ? "Nhấn tổ hợp phím mới (vd ⌥Z, ⌃Space) hoặc nhấn rồi thả phím bổ trợ. Nhấn Esc để hủy." : "Press shortcut (e.g. ⌥Z, ⌃Space) or tap a modifier key. Press Esc to cancel." }
    public var shortcutInvalidHint: String { isVietnamese ? "Phím tắt cần có phím bổ trợ (⌃, ⌥, ⇧, ⌘) hoặc phím F1–F20." : "Shortcut requires a modifier (⌃, ⌥, ⇧, ⌘) or a function key (F1–F20)." }
    public var beepOnSwitch: String { isVietnamese ? "Phát âm báo khi chuyển chế độ" : "Play sound when switching mode" }
    
    // Orthography Section
    public var sectionOrthography: String { isVietnamese ? "Chính tả & Quy tắc dấu" : "Spelling & Orthography" }
    public var checkSpelling: String { isVietnamese ? "Kiểm tra chính tả tiếng Việt" : "Enable Vietnamese spell checking" }
    public var autoRestore: String { isVietnamese ? "Tự khôi phục phím khi từ sai chính tả" : "Auto-restore raw keys on invalid words" }
    public var modernOrthography: String { isVietnamese ? "Đặt dấu kiểu mới (oà, uý thay vì òa, úy)" : "Use modern tone placement (oà, uý)" }
    
    // App Compatibility Section
    public var sectionAppFixes: String { isVietnamese ? "Tương thích ứng dụng" : "App Compatibility" }
    public var fixBrowser: String { isVietnamese ? "Sửa lỗi gợi ý tự động trên trình duyệt & IDE" : "Fix autocomplete issues in browsers & IDEs" }
    public var otherLanguage: String { isVietnamese ? "Tự tắt khi dùng bố cục bàn phím khác (Dvorak/Colemak)" : "Bypass on non-QWERTY / non-English layouts" }
    
    // System Section
    public var sectionSystem: String { isVietnamese ? "Hệ thống" : "System" }
    public var launchAtLogin: String { isVietnamese ? "Khởi động cùng macOS" : "Launch at login" }
    public var launchAtLoginRequiresApproval: String { isVietnamese ? "Cần phê duyệt OpenKeySwift trong Cài đặt Hệ thống → Mục đăng nhập." : "Requires approval in System Settings → Login Items." }
    public func launchAtLoginError(_ detail: String) -> String {
        isVietnamese ? "Lỗi khi cấu hình tự khởi động: \(detail)" : "Failed to configure launch at login: \(detail)"
    }
    public var debugModeTitle: String { isVietnamese ? "Chế độ Gỡ lỗi (Debug Mode)" : "Debug Mode & Logging" }
    public var debugModeSubtitle: String { isVietnamese ? "Ghi nhật ký chẩn đoán chi tiết ra ~/Library/Logs/OpenKeySwift/openkey-debug.log (Tự dọn dẹp theo bản build, che giấu mật khẩu)" : "Write verbose diagnostics to ~/Library/Logs/OpenKeySwift/openkey-debug.log (Auto-purged per version, keystrokes redacted in password fields)" }
    public var openLogFile: String { isVietnamese ? "Mở tệp nhật ký" : "Open Log File" }
    public var revealLogInFinder: String { isVietnamese ? "Hiện trong Finder" : "Reveal in Finder" }
    public var clearLog: String { isVietnamese ? "Xóa nhật ký" : "Clear Log" }
    
    private var bundleShortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.6"
    }

    // About Section
    public var sectionAbout: String { isVietnamese ? "Giới thiệu" : "About" }
    public var versionLabel: String { isVietnamese ? "Phiên bản:" : "Version:" }
    public var versionValue: String { "v\(bundleShortVersion) • Pure Swift 6 (macOS 26)" }
    public var implementorLabel: String { isVietnamese ? "Thực hiện chuyển đổi & phát triển:" : "Implementor:" }
    public var implementorValue: String { "Antigravity — Gemini 4 Argon (High)" }
    public var originalAuthorLabel: String { isVietnamese ? "Tác giả bản gốc (OpenKey):" : "Original Author (OpenKey):" }
    public var originalAuthorValue: String { "Mai Vũ Tuyên" }
    public var licenseFooter: String { isVietnamese ? "Phát hành theo giấy phép mã nguồn mở GNU GPLv3 • Nhấn Esc để đóng cửa sổ" : "Licensed under GNU GPLv3 • Press Esc to close window" }
    
    // Menu items
    public func menuVietnamese(shortcut: String) -> String {
        isVietnamese ? "Tiếng Việt (\(shortcut))" : "Vietnamese Input (\(shortcut))"
    }
    public func menuBypassApp(_ appName: String) -> String {
        isVietnamese ? "Tắt tiếng Việt trong \(appName)" : "Bypass Vietnamese in \(appName)"
    }
    public var menuSmartSwitch: String { isVietnamese ? "Nhớ ngôn ngữ theo ứng dụng" : "Remember Language Per App" }
    public var menuResetSmartSwitch: String { isVietnamese ? "Đặt lại nhớ ngôn ngữ" : "Reset Smart Switch" }
    public var menuAccessibilityMissing: String { isVietnamese ? "Chưa cấp quyền Trợ năng — Mở Cài đặt..." : "Accessibility Required — Open Settings..." }
    public var menuDebugMode: String { isVietnamese ? "Chế độ Gỡ lỗi (Debug Mode)" : "Debug Mode" }
    public var menuOpenLogFile: String { isVietnamese ? "Mở tệp nhật ký gỡ lỗi..." : "Open Debug Log..." }
    public var menuSettings: String { isVietnamese ? "Cài đặt..." : "Settings..." }
    public var menuAbout: String { "OpenKeySwift v\(bundleShortVersion) • Antigravity (Gemini 4 Argon High) & Mai Vũ Tuyên" }
    public var menuQuit: String { isVietnamese ? "Thoát OpenKeySwift" : "Quit OpenKeySwift" }
}
