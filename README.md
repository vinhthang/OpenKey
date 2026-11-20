# [OpenKeySwift](https://github.com/vinhthang/OpenKey)

[![macOS CI/CD](https://github.com/vinhthang/OpenKey/actions/workflows/macos-ci.yml/badge.svg)](https://github.com/vinhthang/OpenKey/actions/workflows/macos-ci.yml)
[![Download v2.0.6 DMG](https://img.shields.io/badge/Download-OpenKeySwift%20v2.0.6%20(.dmg)-blue?logo=apple&logoColor=white)](https://github.com/vinhthang/OpenKey/releases/download/v2.0.6/OpenKeySwift.dmg)
[![Download Latest DMG](https://img.shields.io/badge/Rolling%20Master-OpenKeySwift.dmg-success?logo=apple&logoColor=white)](https://github.com/vinhthang/OpenKey/releases/download/latest/OpenKeySwift.dmg)
[![Agent Guide](https://img.shields.io/badge/Guide-AGENTS.md-informational)](AGENTS.md)

> [!NOTE]
> **OpenKeySwift `v2.0.6` — 100% Pure Swift 6 Vietnamese IME for macOS (`arm64`)**
> **OpenKeySwift** là bộ gõ tiếng Việt ngoại tuyến (**100% offline, zero telemetry**) viết hoàn toàn bằng **Swift 6 nguyên bản** cho **macOS 26 Tahoe** (Apple Silicon `arm64`), kế thừa và tái kiến trúc từ bộ gõ mã nguồn mở [**OpenKey**](https://github.com/tuyenvm/OpenKey) của tác giả **Mai Vũ Tuyên**.
>
> - **Phiên bản Android độc lập (Samsung One UI 6/7 Keyboard)**: Xem tại repository riêng [`1quachuoi9vang/openkey-thanghoang`](https://github.com/1quachuoi9vang/openkey-thanghoang).
> - Bản gốc Copyright © 2019–2026 **Mai Vũ Tuyên**. Phát hành theo giấy phép **GNU General Public License v3.0 (GPLv3)**.

---

## 1. Tải về & Cài đặt nhanh (Direct Download)

- **Bản phát hành ổn định (`v2.0.6`)**:
  - [**OpenKeySwift.dmg**](https://github.com/vinhthang/OpenKey/releases/download/v2.0.6/OpenKeySwift.dmg) (khuyên dùng — kéo thả `OpenKeySwift.app` vào `/Applications`)
  - [**OpenKeySwift-macOS-arm64.zip**](https://github.com/vinhthang/OpenKey/releases/download/v2.0.6/OpenKeySwift-macOS-arm64.zip)
- **Bản build tự động mới nhất từ nhánh `master` (`latest`)**:
  - [**OpenKeySwift.dmg (Rolling Latest)**](https://github.com/vinhthang/OpenKey/releases/download/latest/OpenKeySwift.dmg)

### Các bước cài đặt lần đầu
1. Mở tệp **`OpenKeySwift.dmg`** và kéo **`OpenKeySwift.app`** vào thư mục **`/Applications`**.
2. Nếu macOS Gatekeeper cảnh báo ứng dụng chưa qua Apple Developer ID notarization, chạy lệnh sau một lần trong Terminal để gỡ cờ cách ly tải về:
   ```bash
   xattr -cr /Applications/OpenKeySwift.app
   open /Applications/OpenKeySwift.app
   ```
3. Vào **System Settings → Privacy & Security → Accessibility** và bật quyền cho **OpenKeySwift**. Ứng dụng tự động nhận quyền ngay lập tức mà không cần khởi động lại (biểu tượng thanh menu chuyển từ `V!` sang `V`).

> [!IMPORTANT]
> Khi sử dụng `OpenKeySwift`, hãy để nguồn nhập mặc định của macOS ở **ABC / U.S.** và tắt các bộ gõ tiếng Việt khác để tránh xung đột sự kiện bàn phím.

---

## 2. Điểm nổi bật & Quy ước gõ (Key Highlights & IME Conventions)

- **100% Offline, Riêng tư tuyệt đối & Bảo vệ Mật khẩu (`REQ-001`, `REQ-017`)**:
  - Không có bất kỳ kết nối mạng hay thu thập dữ liệu nào (`Zero Network & Zero Telemetry`).
  - Tự động phát hiện `IsSecureEventInputEnabled()` và `AXSecureTextField` để bỏ qua bộ gõ tiếng Việt và che giấu tuyệt đối phím nhấn trong nhật ký gỡ lỗi khi nhập mật khẩu/PIN.
- **Ưu tiên Tiếng Việt nghiêm ngặt ở chế độ `V` (`Strict V Mode — MAC-11`)**:
  - Khi thanh menu đang ở **`V`**, mọi âm tiết tiếng Việt hợp lệ gõ bằng Telex (`"sẽ"`, `"thế"`, `"tô"`, `"thí"`, `"mã"`, `"sĩ"`, `"ơn"`, `"ít"`, `"cây bút"`, `"kiểu"`, `"xoá"`, kể cả chữ IN HOA `Caps Lock` như `"SẼ LÀM"`, `"TIẾNG VIỆT"`) **luôn giữ nguyên tiếng Việt** — không bao giờ tự đổi hay lùi xóa thành từ tiếng Anh (`"sex"`, `"max"`, `"too"`, `"this"`) ngay cả khi gõ câu pha trộn Anh–Việt (`"ok sẽ gửi"`, `"anh sẽ check"`, `"with sẽ"`).
  - Các từ tiếng Anh không phải âm tiết tiếng Việt hợp lệ (`"with"`, `"wrong"`, `"sometime"`, `"sentence"`, `"keyboard"`, `"coffee"`, `"process"`) vẫn tự động khôi phục nguyên vẹn về tiếng Anh khi ngắt từ (`Space`, `Return`, `Tab`), hỗ trợ nhấn `Backspace` một lần sau `Space` để hoàn tác nếu muốn giữ nguyên.
  - Hỗ trợ **gõ lặp phím dấu để thoát nhanh sang tiếng Anh** ngay trong chế độ `V` (`"sexx "` → `"sex "`, `"thiss "` → `"this "`, `"tooo "` → `"too "`, `"chaoss "` → `"chaos "`).
- **Trải nghiệm macOS Gọn nhẹ, Không làm phiền**:
  - Loại bỏ thanh gợi ý nổi / Auto Wording gây xao nhãng trên macOS; chỉ giữ lại cơ chế chuẩn hóa cụm nguyên âm âm vị học chạy ngầm (`tiengs` → `tiếng`, `truowngf` → `trường`, `quowi` → `quơi`).
  - Tùy chọn bật/tắt **Gõ tắt phụ âm đầu (`Quick Telex`)** trong Cài đặt (`cc → ch`, `gg → gi`, `kk → kh`, `nn → ng`, `pp → ph`, `qq → qu`, `tt → tr`; mặc định **Tắt**).
  - Bảng mã **Precomposed Unicode** dựng sẵn 100%, hỗ trợ tùy chọn đặt dấu kiểu mới (`oà, uý`) hoặc truyền thống (`òa, úy`), cùng cơ chế chèn ký tự ngắt thích ứng (`U+202F` / `U+200C`) chống nuốt chữ trên thanh địa chỉ Chrome, Safari, Arc, Firefox, VS Code, Sublime Text.
- **Thanh Menu Trực quan & Nhớ ngôn ngữ theo Ứng dụng (`SmartSwitchStore`)**:
  - Biểu tượng thanh trạng thái phân biệt rõ 3 trạng thái: đang bật (`V` / `E`), đang tạm ngắt cho ứng dụng hiện tại (`V·` / `E·`), và thiếu quyền Trợ năng (`V!` / `E!`) — tự cập nhật tức thì khi đổi quyền hoặc đổi ứng dụng.
  - Menu hỗ trợ **"Tắt tiếng Việt trong \<Ứng dụng\>"** (`excludedBundleIds`), **"Nhớ ngôn ngữ theo ứng dụng"**, **"Đặt lại nhớ ngôn ngữ"**, khởi động cùng macOS (`SMAppService`), và nút **"Đặt lại quyền Trợ năng"** (`tccutil reset` + kiểm tra trực tiếp `AXIsProcessTrusted()`).
  - Trình ghi phím tắt chuyển ngữ tương tác (mặc định `⌥Z`), hỗ trợ cả tổ hợp phím (`Space`, `Tab`, `Return`, `F1`–`F12`) lẫn nhấn nhả phím bổ trợ đơn (`⌃⇧`, `⌘⇧`, `⌥⇧`) và tự từ chối phím chữ đơn không có phím bổ trợ.
  - Tự động bỏ qua **Spotlight**, **Raycast**, **Alfred**, các trình **Terminal** (`Terminal.app`, `iTerm2`, `Warp`, `Ghostty`, `Alacritty`, `Kitty`, `WezTerm`, `Hyper`), **VM / Remote Desktop**, và các bố cục bàn phím khác (`Dvorak`, `Colemak`, `AZERTY`, CJK).
- **Từ điển Nguồn đơn Đồng bộ Đa nền tảng (`Sources/OpenKey/shared-data/`)**:
  - Kho âm tiết tiếng Việt đã chuẩn hóa âm vị học (`VietnameseDictionary+Phonotactics.swift`) được biên dịch tất định sang `VietnameseDictionaryCorpus.swift` qua `scripts/sync_shared_lexicon.py` và kiểm tra chống lệch tự động trên CI.

---

## 3. Cấu trúc dự án (Project Structure)

```text
OpenKey/
├── .github/workflows/
│   └── macos-ci.yml                                    # GitHub Actions CI/CD & tự động phát hành .dmg/.zip (latest & v*)
├── AGENTS.md                                           # Tài liệu kiến trúc & bất biến kỹ thuật
├── scripts/
│   └── sync_shared_lexicon.py                          # Trình sinh mã & kiểm tra đồng bộ từ điển nguồn đơn
├── Sources/OpenKey/
│   ├── shared-data/                                    # Dữ liệu từ vựng nguồn đơn (1 mục/dòng, đồng bộ với bản Android)
│   │   ├── vietnamese_syllables.txt
│   │   ├── vietnamese_priorities.tsv
│   │   ├── vietnamese_compound_bigrams.tsv
│   │   ├── english_words.tsv
│   │   ├── english_next_word_bigrams.tsv
│   │   └── typo_and_grammar_rules.tsv
│   └── macOS-Swift/
│       ├── Package.swift                               # Swift 6 Package (macOS 26.0+)
│       ├── Info.plist                                  # Metadata ứng dụng (v2.0.6)
│       ├── OpenKeySwift.entitlements                   # Quyền CGEventTap & Accessibility (unsandboxed)
│       ├── build-app.sh                                # Script build, ký mã, cài vào /Applications & khởi chạy lại
│       ├── Sources/
│       │   ├── OpenKeySwiftCore/                       # Thư viện lõi Pure Swift 6
│       │   │   ├── VietnameseEngine.swift              # State machine Telex/VNI & điều phối phím
│       │   │   ├── VietnameseEngine+Phonotactics.swift # Kiểm tra chính tả âm vị học, dấu thanh & phụ âm cuối
│       │   │   ├── BilingualAutoSwitchEngine.swift     # Ưu tiên Strict V-mode & tự khôi phục từ tiếng Anh sai âm vị
│       │   │   ├── AutoWordingEngine.swift             # Sửa cụm nguyên âm âm vị học & API gợi ý từ
│       │   │   ├── VietnameseDictionary.swift          # Tra cứu âm tiết & từ điển (< 550 dòng)
│       │   │   ├── VietnameseDictionary+Phonotactics.swift # Bộ lọc âm vị học âm tiết tiếng Việt hợp lệ
│       │   │   ├── VietnameseDictionaryCorpus.swift    # Dữ liệu từ điển sinh tự động từ shared-data/
│       │   │   ├── VietnameseData.swift                # Bảng mã phím, bitmask & bảng Unicode dựng sẵn
│       │   │   ├── EventTapCoordinator.swift           # Vòng đời CGEventTap, kiểm tra AXIsProcessTrusted & bypass app
│       │   │   ├── KeystrokeInjector.swift             # Chèn chuỗi UTF-16 & ký tự ngắt trình duyệt/IDE
│       │   │   ├── HotKeyMatcher.swift                 # Nhận diện tổ hợp phím tắt & nhấn nhả phím bổ trợ
│       │   │   ├── InputSourceGuard.swift              # Bộ gác bố cục bàn phím TIS có cache theo thông báo hệ thống
│       │   │   ├── CaretPositionResolver.swift         # Truy vấn tọa độ con trỏ Accessibility bất đồng bộ
│       │   │   ├── OpenKeySettingsStore.swift          # Lưu trữ cấu hình @Observable & đồng bộ trạng thái thanh menu
│       │   │   ├── SmartSwitchStore.swift              # Nhớ ngôn ngữ & danh sách loại trừ theo Bundle ID
│       │   │   └── OpenKeyLogger.swift                 # Nhật ký gỡ lỗi lazy @autoclosure có tự xóa khi đổi phiên bản
│       │   └── OpenKeySwiftApp/                        # Ứng dụng thanh menu macOS SwiftUI
│       │       ├── OpenKeySwiftApp.swift               # AppDelegate, biểu tượng trạng thái V/E/V·/V! & menu
│       │       ├── SettingsView.swift                  # Cửa sổ Cài đặt SwiftUI (.formStyle(.grouped), Esc đóng nhanh)
│       │       └── OpenKeyL10n.swift                   # Danh mục bản địa hóa giao diện đơn ngữ (VI | EN)
│       └── Tests/
│           └── OpenKeySwiftTests/                      # 83 bài kiểm thử đơn vị & chịu tải (Swift Testing)
│               ├── OpenKeyEngineTests.swift
│               ├── OpenKeyEventTapTests.swift
│               ├── OpenKeyAutoWordingTests.swift
│               ├── OpenKeyLoadTests.swift
│               └── OpenKeyTestHelpers.swift
└── docs/specs/                                         # Đặc tả kiến trúc 5 tài liệu
```

---

## 4. Hướng dẫn Build từ mã nguồn & Kiểm thử (Build from Source & Testing)

### Yêu cầu hệ thống (Prerequisites)
- **macOS 26.0 (Tahoe)** trở lên (`arm64`).
- **Swift 6.0+** (Xcode 26 hoặc Command Line Tools tương ứng).

### Bước 1: Tạo chứng chỉ ký mã nội bộ (Khuyên dùng — chạy 1 lần)
Để macOS (`tccd`) giữ nguyên quyền **Accessibility** sau mỗi lần tự build lại mà không hỏi lại quyền:

```bash
bash Sources/OpenKey/macOS-Swift/build-app.sh --setup-cert
```

### Bước 2: Build, Ký mã & Cài đặt vào `/Applications`
Script `build-app.sh` tự động biên dịch bản Release `arm64`, ký bằng chứng chỉ `OpenKey Local Signer` (hoặc ad-hoc `-` nếu chưa tạo chứng chỉ), chép vào `/Applications/OpenKeySwift.app` và khởi động lại ứng dụng:

```bash
bash Sources/OpenKey/macOS-Swift/build-app.sh
```

### Kiểm tra đồng bộ từ điển & Chạy kiểm thử (`83` tests)
```bash
# Kiểm tra hoặc cập nhật từ điển từ Sources/OpenKey/shared-data/
python3 scripts/sync_shared_lexicon.py --check
python3 scripts/sync_shared_lexicon.py --write

# Chạy toàn bộ 83 bài kiểm thử đơn vị & kiểm thử chịu tải
swift test --package-path Sources/OpenKey/macOS-Swift
```

### Tích hợp liên tục & Phát hành tự động (GitHub Actions CI/CD)
Workflow [`.github/workflows/macos-ci.yml`](.github/workflows/macos-ci.yml) tự động thực thi trên mỗi lần push/PR và khi đẩy tag `v*`:
- Kiểm tra đồng bộ từ điển nguồn đơn (`sync_shared_lexicon.py --check`) và chạy đầy đủ `83` bài kiểm thử Swift 6.
- Biên dịch chéo gói ứng dụng Apple Silicon (`BUILD_ARCH=arm64`), xác minh `lipo -archs` == `arm64` và chữ ký `codesign --verify --deep --strict`.
- Đóng gói `OpenKeySwift.dmg` + `OpenKeySwift-macOS-arm64.zip`, tải lên **Actions Artifacts**, đồng thời **tự động phát hành lên GitHub Releases** ở cả nhánh `master` ([`latest`](https://github.com/vinhthang/OpenKey/releases/tag/latest)) lẫn các tag phiên bản `v*` ([`v2.0.6`](https://github.com/vinhthang/OpenKey/releases/tag/v2.0.6)).

---

## 5. Nguồn gốc & Giấy phép (Attribution & License)

- **Tác giả bản gốc (`OpenKey` C++/Objective-C++)**: **Mai Vũ Tuyên** ([`tuyenvm/OpenKey`](https://github.com/tuyenvm/OpenKey)) — Email: `maivutuyen.91@gmail.com`.
- **Chuyển đổi Pure Swift 6 & Phát triển (`OpenKeySwift v2.0.6`)**: **Sam Hoang** ([`vinhthang/OpenKey`](https://github.com/vinhthang/OpenKey)) & **Antigravity**.
- **Giấy phép**: Phân phối dưới giấy phép [GNU General Public License v3.0 (GPLv3)](LICENSE).
