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
    
    // Input & Language Section
    public var sectionInput: String { isVietnamese ? "Bộ gõ & Ngôn ngữ" : "Input & Language" }
    public var inputLanguage: String { isVietnamese ? "Chế độ gõ:" : "Input Mode:" }
    public var inputType: String { isVietnamese ? "Kiểu gõ:" : "Input Method:" }
    public var smartSwitch: String { isVietnamese ? "Nhớ ngôn ngữ theo từng ứng dụng" : "Remember input mode per application" }
    
    // Shortcut Section
    public var sectionShortcut: String { isVietnamese ? "Phím tắt chuyển chế độ" : "Toggle Shortcut" }
    public var currentShortcut: String { isVietnamese ? "Phím tắt hiện tại:" : "Current shortcut:" }
    public var cancelShortcut: String { isVietnamese ? "Hủy (Esc)" : "Cancel (Esc)" }
    public var changeShortcut: String { isVietnamese ? "Đổi phím tắt..." : "Change..." }
    public var defaultShortcut: String { isVietnamese ? "Mặc định (⌥Z)" : "Default (⌥Z)" }
    public var recordingHint: String { isVietnamese ? "Nhấn tổ hợp phím mới (ví dụ ⌥Z, ⌃Space). Nhấn Esc để hủy." : "Press desired shortcut (e.g. ⌥Z, ⌃Space). Press Esc to cancel." }
    public var beepOnSwitch: String { isVietnamese ? "Phát âm báo khi chuyển chế độ" : "Play sound when switching mode" }
    
    // Orthography Section
    public var sectionOrthography: String { isVietnamese ? "Chính tả & Quy tắc dấu" : "Spelling & Orthography" }
    public var checkSpelling: String { isVietnamese ? "Kiểm tra chính tả tiếng Việt" : "Enable Vietnamese spell checking" }
    public var autoRestore: String { isVietnamese ? "Tự khôi phục phím khi từ sai chính tả" : "Auto-restore raw keys on invalid words" }
    public var modernOrthography: String { isVietnamese ? "Đặt dấu kiểu mới (oà, uý thay vì òa, úy)" : "Use modern tone placement (oà, uý)" }
    
    // Auto Wording & Suggestions Section
    public var sectionAutoWording: String { isVietnamese ? "Auto Wording & Gợi ý từ" : "Auto Wording & Suggestions" }
    public var enableAutoWording: String { isVietnamese ? "Bật Auto Wording & Gợi ý từ" : "Enable Auto Wording & suggestions" }
    public var grammarRepair: String { isVietnamese ? "Tự sửa cụm nguyên âm (ie/ye → iê/yê, uow → ươ)" : "Auto-repair vowel clusters (ie/ye → iê/yê, uow → ươ)" }
    public var shorthandExpansion: String { isVietnamese ? "Tự bung từ viết tắt khi nhấn Space" : "Expand shorthands on Space (ko → không, dc → được...)" }
    public var candidateBar: String { isVietnamese ? "Hiện thanh gợi ý từ nổi Liquid Glass" : "Show floating Liquid Glass candidate bar" }
    public var customShorthandsTitle: String { isVietnamese ? "Từ viết tắt tùy chỉnh:" : "Custom Shorthands:" }
    public var triggerPlaceholder: String { isVietnamese ? "Viết tắt (vd: cv)" : "Trigger (e.g. cv)" }
    public var expansionPlaceholder: String { isVietnamese ? "Mở rộng (vd: công việc)" : "Expansion (e.g. công việc)" }
    public var addButton: String { isVietnamese ? "Thêm" : "Add" }
    public var learnedFreqTitle: String { isVietnamese ? "Tần suất từ đã học:" : "Learned word frequencies:" }
    public var learnedFreqSubtitle: String { isVietnamese ? "Thứ tự gợi ý tự thích ứng theo từ bạn chọn." : "Candidate ranking adapts to your accepted words." }
    public var resetLearnedButton: String { isVietnamese ? "Xóa dữ liệu học" : "Reset Learned Words" }
    
    // App Compatibility Section
    public var sectionAppFixes: String { isVietnamese ? "Tương thích ứng dụng" : "App Compatibility" }
    public var fixBrowser: String { isVietnamese ? "Sửa lỗi gợi ý tự động trên trình duyệt & IDE" : "Fix autocomplete issues in browsers & IDEs" }
    public var otherLanguage: String { isVietnamese ? "Tự tắt khi dùng bố cục bàn phím khác (Dvorak/Colemak)" : "Bypass on non-QWERTY / non-English layouts" }
    
    // System Section
    public var sectionSystem: String { isVietnamese ? "Hệ thống" : "System" }
    public var launchAtLogin: String { isVietnamese ? "Khởi động cùng macOS" : "Launch at login" }
    
    // About Section
    public var sectionAbout: String { isVietnamese ? "Giới thiệu" : "About" }
    public var versionLabel: String { isVietnamese ? "Phiên bản:" : "Version:" }
    public var versionValue: String { "v2.0.0 (Build 1) • Pure Swift 6 (macOS 26)" }
    public var implementorLabel: String { isVietnamese ? "Thực hiện chuyển đổi & phát triển:" : "Implementor:" }
    public var implementorValue: String { "Antigravity — Gemini 4 Argon (High)" }
    public var originalAuthorLabel: String { isVietnamese ? "Tác giả bản gốc (OpenKey):" : "Original Author (OpenKey):" }
    public var originalAuthorValue: String { "Mai Vũ Tuyên" }
    public var licenseFooter: String { isVietnamese ? "Phát hành theo giấy phép mã nguồn mở GNU GPLv3 • Nhấn Esc để đóng cửa sổ" : "Licensed under GNU GPLv3 • Press Esc to close window" }
    
    // Menu items
    public var menuVietnamese: String { isVietnamese ? "Tiếng Việt (⌥Z)" : "Vietnamese Input (⌥Z)" }
    public var menuSmartSwitch: String { isVietnamese ? "Nhớ ngôn ngữ theo ứng dụng" : "Remember Language Per App" }
    public var menuAutoWording: String { isVietnamese ? "Auto Wording & Gợi ý từ" : "Auto Wording & Suggestions" }
    public var menuSettings: String { isVietnamese ? "Cài đặt..." : "Settings..." }
    public var menuAbout: String { "OpenKeySwift v2.0.0 • Antigravity (Gemini 4 Argon High) & Mai Vũ Tuyên" }
    public var menuQuit: String { isVietnamese ? "Thoát OpenKeySwift" : "Quit OpenKeySwift" }
}
