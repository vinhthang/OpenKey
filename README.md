# [OpenKeySwift](https://github.com/vinhthang/OpenKey)

[![macOS CI/CD](https://github.com/vinhthang/OpenKey/actions/workflows/macos-ci.yml/badge.svg)](https://github.com/vinhthang/OpenKey/actions/workflows/macos-ci.yml)

> [!NOTE]
> **OpenKeySwift — 100% Pure Swift 6 Conversion (macOS 26 Tahoe)**
> **OpenKeySwift** là bản chuyển đổi **100% bằng ngôn ngữ Swift 6 nguyên bản** (nhắm tới **macOS 26 Tahoe**) từ bộ gõ tiếng Việt mã nguồn mở [**OpenKey**](https://github.com/tuyenvm/OpenKey) (C++/Objective-C++) của tác giả **Mai Vũ Tuyên**. Toàn bộ state machine xử lý Telex/VNI, bảng luật âm vị học tiếng Việt, cơ chế ghi nhớ ngôn ngữ theo ứng dụng (`SmartSwitchKey`), cùng hệ thống **Auto Wording & Ngữ pháp thông minh** và giao diện **SwiftUI Liquid Glass** đã được thiết kế và viết lại hoàn toàn bằng Swift 6 hiện đại, không còn phụ thuộc vào bất kỳ thành phần C++ hay Objective-C++ nào.
>
> Bản gốc Copyright © 2019–2026 **Mai Vũ Tuyên**. Phát hành theo giấy phép **GNU General Public License v3.0 (GPLv3)**.

---

## 1. Điểm nổi bật (Key Highlights)

- **100% Pure Swift 6 & Kiến trúc Module hóa (`OpenKeySwiftCore` & `OpenKeySwiftApp`)**:
  - Loại bỏ hoàn toàn cầu nối C++/Objective-C++ (`OpenKeyEngineBridge`) và các mã nguồn cũ không còn sử dụng.
  - Toàn bộ bộ máy ghép vần tiếng Việt (`VietnameseEngine`, `VietnameseEngine+SpellingAndGrammar`, `VietnameseEngine+MarkAndTone`, `VietnameseEngine+KeyEventDispatcher`, `VietnameseData`, `VietnameseUnicodeTable`, `SmartSwitchStore`) hoạt động trực tiếp trên kiểu dữ liệu Swift 6 an toàn bộ nhớ, sử dụng hệ thống thuộc tính bitmask rõ nghĩa (`baseKey`, `isCaps`, `hasToneMark`, `hasCircumflexOrStroke`, `hasHornOrBreve`, `hasAnyDiacritic`) với mỗi file nguồn dưới 500 dòng.
  - Tương thích 100% ngữ nghĩa C++ cho ranh giới nguyên âm `gi-` / `qu-` (`"giới"`, `"gièo"`, `"giường"`, `"giười"`), hoàn tác hai lần phím `w` (`gioiww`, `giowisw`), và tính toán chính xác độ lùi `Backspace` khi chèn nguyên âm đơn `ư`/`ơ`.
- **Unsandboxed Quartz Event Tap (`CGEventTap`)**:
  - Sử dụng kỹ thuật `Backspace` qua `kCGSessionEventTap` để loại bỏ triệt để lỗi gạch chân (underline) của bộ gõ mặc định macOS.
  - Tối ưu đường nóng **Zero-IPC O(1)**, tự động khôi phục khi máy thức dậy (`didWakeNotification`) hoặc khi `CGEventTap` bị timeout, và gắn thẻ sự kiện nội bộ (`0xBEEF`) để tránh lặp vô hạn.
  - Đảm bảo tính toàn vẹn trạng thái bộ đệm (`typingWord`, `keyStates`, `typingStates`) khi nhấn `Delete` nhiều lần liên tiếp trên từ có dấu hoặc xóa qua ranh giới từ rồi nhập ký tự mới.
- **Giao diện macOS 26 Tahoe & Liquid Glass**:
  - Quản lý trạng thái bằng `@Observable` (`Observation` framework), biểu tượng thanh menu `V` / `E` monochrome sắc nét được tạo sẵn trong bộ nhớ đệm.
  - Cửa sổ cài đặt SwiftUI `.formStyle(.grouped)` và thanh gợi ý từ nổi (**Floating Candidate Bar**) sử dụng hiệu ứng **Liquid Glass** (`.glassEffect`) không chiếm quyền điều khiển bàn phím (`nonactivatingPanel`, `level: .popUpMenu`).
- **Auto Wording, Tự sửa âm vị & Gợi ý từ thông minh (`AutoWordingEngine`)**:
  - **Độc lập & Zero-Overhead khi tắt**: Module `AutoWordingEngine` tách biệt hoàn toàn khỏi `VietnameseEngineState` thông qua `OKWordContext` và hook âm vị học; khi tắt Auto Wording, đường nóng gõ phím không chịu bất kỳ chi phí xử lý phụ nào.
  - **Tự sửa cụm nguyên âm (`Phonotactic Syllable Repair`)**: Tự động chuyển `ie`/`ye` + phụ âm cuối khi có dấu thanh thành `iê`/`yê` (ví dụ: `tiengs` → `tiếng`, `viets` → `viết`) và chuẩn hóa `uow`/`uwo` thành `ươ` (`truowngf` → `trường`) mà không cần gõ đúp phím nguyên âm.
  - **Từ điển tiếng Việt > 5.000 mục từ (`VietnameseDictionary` & `VietnameseDictionaryCorpus`)**: Tra cứu dưới `1ms` với hơn 3.500 âm tiết đơn và 1.500 từ ghép hai âm tiết, tự động phân biệt:
    - **Sửa lỗi gõ sai / đảo phím (`.correction`)**: Gợi ý sửa các từ sai quy tắc âm vị hoặc đảo thứ tự phím Telex (`tineg` → `tiếng`, `veit` → `việt`), chọn nhanh bằng `Tab` hoặc `Ctrl + 1..3`.
    - **Hoàn thiện dấu & Gợi ý từ ghép tiếp theo (`.stemCompletion` / `.nextWord`)**: Gợi ý từ có dấu khi gõ không dấu (`thanh` → `thành`, `thánh`, `thanh`) và từ ghép sau khi nhấn `Space` (`thành` → `phố`, `công`, `viên`), chọn bằng `Ctrl + 1..3` mà không chiếm phím `Tab` dùng để thụt lề/di chuyển ô.
  - **Học tần suất từ theo thói quen người dùng (`Adaptive Learning`)**: Tự động ưu tiên xếp hạng `#1` cho các từ/cụm từ bạn thường xuyên chọn.
  - **Gõ tắt thông minh & Tùy biến (`Shorthand Expansion`)**: Tự động bung từ viết tắt thông dụng khi nhấn `Space` (`ko`/`k` → `không`, `dc`/`đc` → `được`, `trc` → `trước`, `ng` → `người`, `j` → `gì`, `cty` → `công ty`, `mn` → `mọi người`, `nv` → `nhân viên`, `gd` → `gia đình`, `sdt` → `số điện thoại`, `bh` → `bây giờ`, `tks` → `cảm ơn`, `vn` → `Việt Nam`, `hn` → `Hà Nội`, `tphcm` → `TP. Hồ Chí Minh`, v.v.) có giữ nguyên kiểu chữ hoa/thường và hỗ trợ người dùng tự thêm/xóa từ viết tắt riêng.
- **Tương thích hệ sinh thái & Bảo mật (`SystemEnvironmentDetector` & `CaretPositionResolver`)**:
  - **Bảo vệ ô nhập mật khẩu (`Secure Input Protection`)**: Tự động phát hiện `IsSecureEventInputEnabled()` và `AXSecureTextField` để tạm ngắt bộ gõ tiếng Việt và ẩn thanh gợi ý từ khi nhập mật khẩu.
  - **Tự động bỏ qua Launcher, Terminal & Máy ảo**: Không can thiệp phím khi mở **Spotlight**, **Raycast**, **Alfred**, các trình **Terminal** (`Terminal.app`, `iTerm2`, `Warp`, `Ghostty`, `Alacritty`, `Kitty`, `WezTerm`, `Hyper`) và **VM / Remote Desktop** (`VMware Fusion`, `Parallels`, `UTM`, `VirtualBox`, `Microsoft Remote Desktop`).
  - **Định vị con trỏ văn bản chính xác trên Electron/Chromium & Đa màn hình**: Tự động kích hoạt `AXManualAccessibility` cho ứng dụng Chromium/Electron, hỗ trợ con trỏ độ rộng bằng `0` (`width == 0 && height > 0`), giới hạn thời gian truy vấn Accessibility ở `40ms` trên luồng nền và tự động kẹp khung hiển thị theo màn hình đang hoạt động.

---

## 2. Tính năng chi tiết (Features)

### Kiểu gõ & Bảng mã
- **Kiểu gõ hỗ trợ**: **Telex** và **VNI**.
- **Bảng mã**: Chuẩn hóa 100% trên **Unicode dựng sẵn (Precomposed Unicode)** để đảm bảo tương thích tuyệt đối với các ứng dụng hiện đại.

### Kiểm tra chính tả & Tự khôi phục từ tiếng Anh
- **Đặt dấu kiểu mới (`Modern Orthography`)**: Tùy chọn đặt dấu `oà, uý` hoặc kiểu truyền thống `òa, úy`.
- **Kiểm tra chính tả & Tự khôi phục phím (`Auto-Restore`)**: Khi gõ các từ tiếng Anh không hợp lệ với âm vị tiếng Việt (bao gồm cả từ chứa `d...d` tạo thành `đ` như `"dead"`, `"added"` hoặc các từ như `"window"`, `"function"`, `"project"`), OpenKeySwift tự động khôi phục nguyên vẹn chuỗi ký tự ASCII gốc khi nhấn phím ngắt từ (`Space`, `Return`, `Tab`) mà không làm nuốt phím điều khiển cuối.
- **Sửa lỗi Autocomplete trên trình duyệt & IDE**: Sử dụng ký tự ngắt thích ứng theo ứng dụng (`U+200C` cho Sublime Text, `U+202F` cho Chrome, Safari, Arc, Firefox, VS Code, Xcode,...) trước khi gửi chuỗi `Backspace`.

### Chuyển ngữ thông minh & Phím tắt
- **Nhớ ngôn ngữ theo từng ứng dụng (`SmartSwitchKey`)**: Bật/tắt nhanh ngay trên thanh menu hoặc trong Cài đặt. Tự động chuyển đổi giữa Tiếng Việt (`V`) và Tiếng Anh (`E`) khi chuyển đổi qua lại giữa các ứng dụng, hoặc dùng chung một ngôn ngữ toàn cục.
- **Phím tắt chuyển chế độ tùy chỉnh**: Mặc định là `Option + Z` (`⌥Z`). Hỗ trợ trình ghi phím tắt tương tác (`Đổi phím tắt...`) cho cả tổ hợp phím và phím bổ trợ đơn (`Modifier-only tap`), chống lặp phím khi nhấn giữ và tự nuốt sự kiện `keyUp` tương ứng.
- **Tự động bỏ qua bố cục bàn phím khác (`vOtherLanguage`)**: Tự động tạm ngưng xử lý tiếng Việt khi chuyển sang bàn phím không phải tiếng Anh hoặc bố cục `Dvorak`, `Colemak`, `AZERTY` (có bộ nhớ đệm theo thông báo hệ thống `kTISNotifySelectedKeyboardInputSourceChanged`).

### Phím tắt thanh gợi ý từ (Candidate Bar Shortcuts)
Khi thanh gợi ý từ Liquid Glass đang hiển thị dưới con trỏ văn bản:
- `Tab`: Chọn nhanh gợi ý số `#1` khi từ đang gõ bị sai chính tả / đảo phím (`.correction`).
- `Ctrl + 1` / `Ctrl + 2` / `Ctrl + 3`: Chọn từ gợi ý số `#1` / `#2` / `#3` cho mọi loại gợi ý (`.correction`, `.stemCompletion`, `.nextWord`).
- `Esc`: Đóng thanh gợi ý từ hiện tại.
- Nhấp chuột trực tiếp vào từng viên nang (pill) gợi ý trên thanh nổi.

---

## 3. Cấu trúc dự án (Project Structure)

```text
OpenKey/
├── .github/workflows/
│   └── macos-ci.yml                   # GitHub Actions macOS 26 CI/CD (test, build, sign, .zip & .dmg)
├── Sources/OpenKey/macOS-Swift/
│   ├── Package.swift                  # Swift 6 Package (macOS 26.0+)
│   ├── Info.plist                     # Bundle metadata & copyright attribution
│   ├── OpenKeySwift.entitlements      # Unsandboxed CGEventTap & Accessibility entitlements
│   ├── build-app.sh                   # Build, bundle & code-signing script (--setup-cert)
│   ├── Scripts/
│   │   └── real-system-load-test.swift # End-to-end real-system load & stress test suite
│   ├── Sources/
│   │   ├── OpenKeySwiftCore/          # Pure Swift 6 IME Core Library (< 500 lines per file)
│   │   │   ├── VietnameseData.swift                     # Keycodes, bitmasks, syllable helpers & vowel/consonant rules
│   │   │   ├── VietnameseUnicodeTable.swift             # Precomposed Unicode code table
│   │   │   ├── VietnameseEngine.swift                   # Core state buffer, session management & public C-style API
│   │   │   ├── VietnameseEngine+SpellingAndGrammar.swift# Phonotactic validation, grammar repair & auto-restore
│   │   │   ├── VietnameseEngine+MarkAndTone.swift       # Modern/old tone placement, circumflex, horn & breve
│   │   │   ├── VietnameseEngine+KeyEventDispatcher.swift# Key event phase handlers (Space, Delete, Character, Break)
│   │   │   ├── SmartSwitchStore.swift                   # Per-app language memory & safe binary serialization
│   │   │   ├── VietnameseDictionary.swift               # Sub-millisecond stem, anagram & bigram lookup engine
│   │   │   ├── VietnameseDictionaryCorpus.swift         # 5,000+ syllable & compound word corpus data
│   │   │   ├── AutoWordingEngine.swift                  # Phonotactic repair, shorthands, candidate ranking & learning
│   │   │   ├── AutoWordingTypes.swift                   # WordCandidate, CandidateKind & default shorthand tables
│   │   │   ├── EventTapCoordinator.swift                # Quartz CGEventTap lifecycle & deterministic evaluateKeyEvent
│   │   │   ├── SystemEnvironmentDetector.swift          # Secure input, Spotlight/Raycast/Alfred, Terminal & VM detection
│   │   │   ├── KeystrokeInjector.swift                  # Batched UTF-16 injection & browser autocomplete breaker
│   │   │   ├── CaretPositionResolver.swift              # Async 40ms Accessibility caret bounds & Electron support
│   │   │   ├── InputSourceGuard.swift                   # Notification-cached TIS keyboard layout guard
│   │   │   ├── HotKeyMatcher.swift                      # Shortcut matching & modifier-only tap state machine
│   │   │   └── OpenKeySettingsStore.swift               # @Observable UserDefaults persistence & batch sync
│   │   └── OpenKeySwiftApp/           # macOS 26 SwiftUI Application Target
│   │       ├── OpenKeySwiftApp.swift      # Status bar item, menu & wake/app-switch observers
│   │       ├── SettingsView.swift         # Grouped Form UI, Liquid Glass banner & custom shorthands
│   │       └── CandidateBarController.swift # Non-activating Liquid Glass floating NSPanel
│   └── Tests/
│       └── OpenKeySwiftTests/         # Modular Swift Testing suite
│           ├── OpenKeyEngineTests.swift     # Telex/VNI syllable composition, Delete & auto-restore tests
│           ├── OpenKeyEventTapTests.swift   # Pure event routing, Secure Input, Launcher & HotKey tests
│           ├── OpenKeyAutoWordingTests.swift# Phonotactic repair, shorthand, dictionary & learning tests
│           ├── OpenKeyLoadTests.swift       # High-volume multi-session stress & latency tests
│           └── OpenKeyTestHelpers.swift     # Shared simulated screen buffer & keystroke helpers
└── docs/specs/                        # 5-Document Architecture specifications & verification reports
    ├── INDEX.md
    ├── 2026-10-26-macos-swift-ime/
    ├── 2026-10-26-auto-wording/
    └── 2026-10-27-ime-intelligence-and-ecosystem/
```

---

## 4. Hướng dẫn Build & Cài đặt (Build & Installation)

### Yêu cầu hệ thống (Prerequisites)
- **macOS 26.0 (Tahoe)** trở lên.
- **Swift 6.0+** (Xcode 26 hoặc Command Line Tools tương ứng).

### Bước 1: Tạo chứng chỉ ký mã nội bộ (Khuyên dùng)
Để macOS (`tccd`) ghi nhớ quyền **Accessibility** qua các lần build lại mà không cần cấp quyền lại từ đầu, hãy tạo chứng chỉ tự ký `OpenKey Local Signer` vào Keychain cá nhân (chỉ cần chạy 1 lần):

```bash
cd Sources/OpenKey/macOS-Swift
./build-app.sh --setup-cert
```

### Bước 2: Build ứng dụng `OpenKeySwift.app`
Chạy script đóng gói và ký mã tự động:

```bash
cd Sources/OpenKey/macOS-Swift
./build-app.sh
```

Sau khi hoàn tất, gói ứng dụng sẽ nằm tại `Sources/OpenKey/macOS-Swift/build/OpenKeySwift.app`. Bạn có thể copy trực tiếp vào `/Applications`:

```bash
cp -R Sources/OpenKey/macOS-Swift/build/OpenKeySwift.app /Applications/
open /Applications/OpenKeySwift.app
```

### Bước 3: Cấp quyền Accessibility
Khi mở `OpenKeySwift.app` lần đầu, vào **System Settings → Privacy & Security → Accessibility** và bật quyền cho **OpenKeySwift**. Ứng dụng sẽ tự động kích hoạt bộ gõ ngay lập tức mà không cần khởi động lại.

> [!IMPORTANT]
> Khi sử dụng `OpenKeySwift`, hãy chuyển bộ gõ mặc định của macOS về **ABC / U.S.** và tắt các bộ gõ tiếng Việt thứ ba khác để tránh xung đột sự kiện bàn phím.

### Chạy bộ kiểm thử tự động (Running Tests)
```bash
cd Sources/OpenKey/macOS-Swift
swift test
```

### Tích hợp liên tục & Đóng gói tự động (GitHub Actions CI/CD)
Dự án đi kèm workflow [`.github/workflows/macos-ci.yml`](.github/workflows/macos-ci.yml) chạy trên runner **`macos-26` (`arm64`, Xcode 26)**:
- **Kiểm tra cấu trúc & Chất lượng mã (`REQ-009`)**: Tự động xác minh mọi file `.swift` trong `Sources/` và `Tests/` đều dưới `500` dòng.
- **Kiểm thử tự động (`swift test`)**: Chạy toàn bộ bộ kiểm thử đơn vị và kiểm thử chịu tải (`OpenKeySwiftTests`).
- **Đóng gói & Ký mã (`build-app.sh`)**: Biên dịch bản Release `OpenKeySwift.app`, kiểm tra chữ ký số nghiêm ngặt (`codesign --verify --deep --strict`), và đóng gói thành `OpenKeySwift-macOS-arm64.zip` cùng ảnh đĩa `OpenKeySwift.dmg`.
- **Phát hành tự động (Artifacts & Releases)**: Tự động tải lên gói cài đặt trong mục **Actions → Artifacts** ở mỗi lần push/PR và tự động tạo **GitHub Release** khi đẩy tag phiên bản `v*` (ví dụ: `git tag v2.0.0 && git push origin v2.0.0`).

---

## 5. Nguồn gốc & Giấy phép (Attribution & License)

- **Tác giả bản gốc (`OpenKey` C++/Objective-C++)**: **Mai Vũ Tuyên** ([`tuyenvm/OpenKey`](https://github.com/tuyenvm/OpenKey)) — Email: `maivutuyen.91@gmail.com`.
- **Chuyển đổi Pure Swift 6 & Phát triển tính năng mới (`OpenKeySwift`)**: **Sam Hoang** ([`vinhthang/OpenKey`](https://github.com/vinhthang/OpenKey)).
- **Giấy phép**: Dự án được phân phối dưới giấy phép [GNU General Public License v3.0 (GPLv3)](LICENSE).
