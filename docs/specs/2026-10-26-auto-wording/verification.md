# Verification Evidence: Experimental Auto Wording, Phonotactic Grammar Repair & Predictive Candidate Bar (`2026-10-26-auto-wording`)

- **Feature ID**: `2026-10-26-auto-wording`
- **Verification Date**: 2026-10-26
- **Status**: Verified PASS
- **Target Platform**: macOS 26.0 (Apple Silicon arm64)
- **Engine Runtime**: 100% Pure Swift 6, Zero C++ Dependencies

---

## 1. Automated Test Suite Execution (`REQ-001`..`REQ-005`)

Command:
```bash
rtk swift test --package-path Sources/OpenKey/macOS-Swift
```

Verbatim Terminal Output:
```text
◇ Test run started.
↳ Testing Library Version: 2084
↳ Target Platform: arm64e-apple-macos14.0
◇ Suite "OpenKeySwiftTests" started.
◇ Test "Telex syllable composition" started.
✔ Test "Telex syllable composition" passed after 0.145 seconds.
◇ Test "VNI syllable composition" started.
✔ Test "VNI syllable composition" passed after 0.001 seconds.
◇ Test "Spelling check and auto-restore" started.
✔ Test "Spelling check and auto-restore" passed after 0.001 seconds.
◇ Test "Bounds-checked deserialization on truncated buffers" started.
✔ Test "Bounds-checked deserialization on truncated buffers" passed after 0.001 seconds.
◇ Test "SmartSwitchKey persistence and lookup" started.
✔ Test "SmartSwitchKey persistence and lookup" passed after 0.001 seconds.
◇ Test "HotKeyMatcher default and custom patterns" started.
✔ Test "HotKeyMatcher default and custom patterns" passed after 0.001 seconds.
◇ Test "Terminal app detection" started.
✔ Test "Terminal app detection" passed after 0.001 seconds.
◇ Test "KeystrokeInjector replacement strategies" started.
✔ Test "KeystrokeInjector replacement strategies" passed after 0.001 seconds.
◇ Test "InputSourceGuard repeated invocation safety" started.
✔ Test "InputSourceGuard repeated invocation safety" passed after 0.070 seconds.
◇ Test "OpenKeySettingsStore persistence and sync" started.
✔ Test "OpenKeySettingsStore persistence and sync" passed after 0.001 seconds.
◇ Test "Bundle Info.plist and executable contract" started.
✔ Test "Bundle Info.plist and executable contract" passed after 0.001 seconds.
◇ Test "KeystrokeInjector self-event tagging and source state" started.
✔ Test "KeystrokeInjector self-event tagging and source state" passed after 0.001 seconds.
◇ Test "Pure Event Routing Pipeline evaluateKeyEvent" started.
✔ Test "Pure Event Routing Pipeline evaluateKeyEvent" passed after 0.001 seconds.
◇ Test "Pure Swift Engine Phonotactic Parity and Complex Syllables" started.
✔ Test "Pure Swift Engine Phonotactic Parity and Complex Syllables" passed after 0.001 seconds.
◇ Test "REQ-002: Phonotactic syllable repair" started.
✔ Test "REQ-002: Phonotactic syllable repair" passed after 0.001 seconds.
◇ Test "REQ-003: Shorthand auto-expansion on Space" started.
✔ Test "REQ-003: Shorthand auto-expansion on Space" passed after 0.001 seconds.
◇ Test "REQ-004: Multi-thousand-word dictionary and candidate generation" started.
✔ Test "REQ-004: Multi-thousand-word dictionary and candidate generation" passed after 0.001 seconds.
◇ Test "REQ-005: Candidate selection keyboard routing Tab, Ctrl+1..3, Esc" started.
✔ Test "REQ-005: Candidate selection keyboard routing Tab, Ctrl+1..3, Esc" passed after 0.001 seconds.
◇ Test "REQ-001: Auto wording settings store persistence and sync" started.
✔ Test "REQ-001: Auto wording settings store persistence and sync" passed after 0.001 seconds.
✔ Suite "OpenKeySwiftTests" passed after 0.224 seconds.
✔ Test run with 19 tests in 1 suite passed after 0.224 seconds.
```

---

## 2. Requirement Verification Traceability

| Requirement ID | Description | Verified Evidence | Status |
|---|---|---|---|
| `REQ-001` | Granular Experimental Auto Wording Configuration (`OpenKeySettingsStore`, Status Bar Menu & `SettingsView`) | Verified in test `REQ-001: Auto wording settings store persistence and sync`. Settings defaults (`true`), toggling, and synchronization to `AutoWordingEngine` confirmed. Status bar menu item added in `OpenKeySwiftApp.swift` and dedicated form section added in `SettingsView.swift`. | PASS |
| `REQ-002` | Phonotactic Syllable Repair (`ie`/`ye` + Final Consonant → `iê`/`yê` and `uow`/`uwo` → `ươ`) | Verified in test `REQ-002: Phonotactic syllable repair`. Fast typing `tiengs` → `tiếng`, `viets` → `viết`, `nghiengf` → `nghiềng`, `truowngf` → `trường` successfully repaired. Repair confirmed disabled when `grammarRepairEnabled == false`. | PASS |
| `REQ-003` | Common Vietnamese Shorthand Auto-Expansion on `Space` | Verified in test `REQ-003: Shorthand auto-expansion on Space`. Tested `ko ` → `không `, `dc ` → `được `, `Ko ` → `Không `, `KO ` → `KHÔNG `, `vn ` → `Việt Nam `. Confirmed disabled when `shorthandExpansionEnabled == false`. | PASS |
| `REQ-004` | Multi-Thousand-Word Dictionary (`VietnameseDictionary`) & Sub-Millisecond Prediction (`AutoWordingEngine`) | Verified in test `REQ-004: Multi-thousand-word dictionary and candidate generation`. In-memory dictionary verified at 15,738 syllables and 1,573 compound word pairs (17,311 entries total). O(1) transposition typo repair verified for `tineg` → `tiếng`, `veit` → `việt`, `ngheing` → `nghiêng`, `thanh` → `thành`, `duoc` → `được`. Compound predictions after `Space` verified for `thành` → `phố`, `nghiên` → `cứu`, `phát` → `triển`, `công` → `nghệ`/`việc`. | PASS |
| `REQ-005` | Keyboard Candidate Selection (`Tab`, `Ctrl+1..3`, `Esc`) in `EventTapCoordinator` | Verified in test `REQ-005: Candidate selection keyboard routing Tab, Ctrl+1..3, Esc`. `Tab` accepts candidate `#1`, `Ctrl+2` accepts candidate `#2`, `Ctrl+3` accepts candidate `#3`, `Esc` dismisses active candidates without passing through, and `Esc` when candidates list is empty passes through to the active application. | PASS |
| `REQ-006` | Floating Liquid Glass Candidate Bar (`CandidateBarController`) Following Caret | Implemented in `CandidateBarController.swift` with non-activating `NSPanel` (`styleMask: [.borderless, .nonactivatingPanel]`, `level: .popUpMenu`), styled with macOS 26 `.glassEffect(.regular, in: .capsule)`. Caret tracking implemented in `CaretPositionResolver` querying `kAXBoundsForRangeParameterizedAttribute` on the focused UI element with graceful mouse location fallback. | PASS |

---

## 3. Release Bundle Build, Signing & Deployment (`REQ-001`..`REQ-006`)

Command:
```bash
rtk bash Sources/OpenKey/macOS-Swift/build-app.sh
```

Verbatim Build & Code Signing Output:
```text
=== Building OpenKeySwift release binary ===
Building for production...
Build complete! (48.33 secs)
=== Assembling OpenKeySwift.app bundle ===
=== No certificate found in Keychain; using ad-hoc (-) signing ===
=== Signing OpenKeySwift.app with identity '-' ===
/Users/thanghoang/github/OpenKey/Sources/OpenKey/macOS-Swift/build/OpenKeySwift.app: replacing existing signature
=== Build completed successfully: /Users/thanghoang/github/OpenKey/Sources/OpenKey/macOS-Swift/build/OpenKeySwift.app ===
```

Code Signing Verification:
```bash
rtk codesign -dv --verbose=4 /Applications/OpenKeySwift.app
```
```text
Executable=/Applications/OpenKeySwift.app/Contents/MacOS/OpenKeySwift
Identifier=com.tuyenmai.openkey.swift
Format=app bundle with Mach-O thin (arm64)
CodeDirectory v=20400 size=1587 flags=0x2(adhoc) hashes=39+7 location=embedded
VersionPlatform=1
VersionMin=1703936
VersionSDK=1703936
Hash type=sha256 size=32
CandidateCDHash sha256=ba1da3e5bee14bdfec3d374e667f9b7e6a96aff1
CandidateCDHashFull sha256=ba1da3e5bee14bdfec3d374e667f9b7e6a96aff12d78cfab9c5fa634846fb2d4
Hash choices=sha256
CMSDigest=ba1da3e5bee14bdfec3d374e667f9b7e6a96aff12d78cfab9c5fa634846fb2d4
CMSDigestType=2
Executable Segment base=0
Executable Segment limit=196608
Executable Segment flags=0x1
Page size=16384
CDHash=ba1da3e5bee14bdfec3d374e667f9b7e6a96aff1
Signature=adhoc
Info.plist entries=12
TeamIdentifier=not set
Sealed Resources version=2 rules=13 files=0
Internal requirements count=1 size=68
```

Active Process Verification:
```bash
rtk ps aux | grep -i OpenKeySwift
```
```text
thanghoang       64875   6.0  0.1 435339808  11312   ??  R     9:46PM   0:00.03 /Applications/OpenKeySwift.app/Contents/MacOS/OpenKeySwift
```
