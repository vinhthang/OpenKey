# Execution Tasks (`2026-10-26-macos-swift-ime`)

- [x] **Task 1: Harden C++ Engine Deserialization & Fix Legacy `CFRelease` Bug** (`REQ-005`, `REQ-006`)
  - [x] Add bounds checks (`cursor + len <= size`) to `initSmartSwitchKey` in `Sources/OpenKey/engine/SmartSwitchKey.cpp` (`REQ-005`).
  - [x] Fix `TISCopyCurrentKeyboardInputSource` leak and `CFRelease(langRef)` over-release in `Sources/OpenKey/macOS/ModernKey/OpenKey.mm` (`REQ-006`).
- [x] **Task 2: Create `OpenKeyEngineBridge` C/C++ Target & Swift Package Scaffold** (`REQ-001`, `REQ-003`)
  - [x] Create `Sources/OpenKey/macOS-Swift/Package.swift` and `Sources/OpenKey/macOS-Swift/OpenKeySwift.entitlements` (unsandboxed `<dict/>`) (`REQ-001`, `REQ-002`).
  - [x] Implement `OpenKeyEngineBridge.h` and `OpenKeyEngineBridge.mm` wrapping `Sources/OpenKey/engine/` (`REQ-001`, `REQ-003`).
- [x] **Task 3: Implement `OpenKeySwiftCore` (Settings, HotKey, InputSourceGuard, Injector, EventTap)** (`REQ-002`, `REQ-003`, `REQ-004`, `REQ-005`, `REQ-006`, `REQ-007`)
  - [x] Implement `OpenKeySettingsStore.swift`, `HotKeyMatcher.swift`, `InputSourceGuard.swift`, `KeystrokeInjector.swift`, and `EventTapCoordinator.swift` (`REQ-002`..`REQ-007`).
- [x] **Task 4: Implement `OpenKeySwiftApp` (SwiftUI Menu Bar & Settings UI) and App Bundle Builder** (`REQ-002`, `REQ-007`, `REQ-008`)
  - [x] Implement `OpenKeySwiftApp.swift`, `SettingsView.swift`, and `build-app.sh` (`REQ-001`, `REQ-002`, `REQ-007`, `REQ-008`).
- [x] **Task 5: TDD Verification & `verification.md` Evidence Capture** (`REQ-001`..`REQ-008`)
  - [x] Write and run XCTest suite in `OpenKeySwiftTests.swift` and record evidence in `verification.md` (`REQ-001`..`REQ-008`).
- [x] **Task 6: Bypass Spotlight Overlay / Terminal Emulators / `Cmd + Tab`, Fix Smart Switch Language Revert & Remove Legacy Features** (`REQ-003`, `REQ-004`, `REQ-005`, `REQ-008`)
  - [x] Fix Smart Switch per-app persistence, add Spotlight/Terminal/`Cmd + Tab` bypass, remove `Simple Telex 1/2` and legacy code tables from Swift layer, and update menu bar icon to monochrome template (`REQ-003`, `REQ-004`, `REQ-005`, `REQ-008`).
- [x] **Task 7: Purge Dead C++ Engine Code, Adopt macOS 26 (`@Observable` & Liquid Glass) & Harden Hot-Path Performance, Shortcut State Machine, Layout/App Guards, Signing & Routing Unit Tests** (`REQ-002`, `REQ-003`, `REQ-004`, `REQ-005`, `REQ-006`, `REQ-007`, `REQ-008`, `REQ-009`, `REQ-010`, `REQ-011`, `REQ-012`, `REQ-013`)
  - [x] Write failing unit tests in `OpenKeySwiftTests.swift` (TDD RED) covering:
    1. Pure `EventTapCoordinator.evaluateKeyEvent` routing (self-event `0xBEEF`, mouse session reset, modifier bypass `Cmd + Tab`, English-mode O(1) fast exit without invoking Spotlight/layout closures, Terminal & VM bypass, Spotlight bypass, and Telex composition dispatch) (`REQ-010`, `REQ-011`).
    2. Shortcut auto-repeat suppression (`isAutoRepeat == true` swallows without toggling), matching `.keyUp` swallowing, and modifier-only tap (`0xFE`) release vs chord cancellation (`REQ-007`, `REQ-011`).
    3. `InputSourceGuard.isCompatibleInputSource` rejecting `Dvorak`, `Colemak`, `AZERTY`, and non-English languages while accepting US/ABC/Australian/British QWERTY (`REQ-006`).
    4. `KeystrokeInjector.determineStrategy` selecting `U+200C` for `com.sublimetext.*`, `U+202F` for standard apps, and `.standardBackspace` when `extCode == 4` (`REQ-004`).
    5. Per-app vs global language switching (`useSmartSwitchKey == true` vs `false`) (`REQ-005`).
  - [x] Purge dead legacy files and branches from `Sources/OpenKey/engine/` and `OpenKeyEngineBridge.mm` (`REQ-012`):
    - Delete `ConvertTool.h`, `ConvertTool.cpp`, `Macro.h`, and `Macro.cpp`.
    - Flatten `_codeTable` in `Vietnamese.h/.cpp` to a single Precomposed Unicode map and remove `_codeTable[1..4]`, `_unicodeCompoundMark`, `_quickTelex`, `_quickStartConsonant`, and `_quickEndConsonant`.
    - Remove dead globals and dead branches (`vSimpleTelex1/2`, `vReplaceMaro`, `handleQuickTelex`, `checkQuickConsonant`, `upperCaseFirstCharacter`, `isMacroBreakCode`) from `DataType.h`, `Engine.h`, `Engine.cpp`, and `OpenKeyEngineBridge.mm`.
  - [x] Upgrade `Package.swift` (`swift-tools-version: 6.0`, `.macOS("26.0")`, `.cxx17`) and `Info.plist` (`LSMinimumSystemVersion = 26.0`), and migrate `OpenKeySettingsStore.swift` from `Combine` (`ObservableObject`) to `@Observable` (`Observation`) (`REQ-013`).
  - [x] Implement `InputSourceGuard` notification-driven caching (`kTISNotifySelectedKeyboardInputSourceChanged`) and non-QWERTY (`Dvorak`/`Colemak`/`AZERTY`) filtering in `InputSourceGuard.swift` (`REQ-006`).
  - [x] Implement app-aware `U+200C` (`com.sublimetext.*`) vs `U+202F` and `extCode != 4` check in `KeystrokeInjector.swift` (`REQ-004`).
  - [x] Implement `evaluateKeyEvent`, zero-IPC fast-path ordering, `0.15s` TTL + dimension-filtered (`width >= 200 && height >= 40`) Spotlight detection, VM/remote-desktop bundle IDs, `NSWorkspace.didWakeNotification` observer, and hotkey auto-repeat / `keyUp` / modifier-only release state machine in `EventTapCoordinator.swift` (`REQ-002`, `REQ-004`, `REQ-007`, `REQ-010`, `REQ-011`).
  - [x] Cache pre-rendered monochrome `V` and `E` `NSImage` instances, wire `settings.onLanguageChanged`, remove `Combine` and `UserDefaults.didChangeNotification`, and add `"Nhớ ngôn ngữ theo ứng dụng"` checkable menu item in `OpenKeySwiftApp.swift` (`REQ-005`, `REQ-008`, `REQ-013`).
  - [x] Refactor `SettingsView.swift` to use `@Bindable`, `Form` with `.formStyle(.grouped)`, macOS 26 Liquid Glass (`.glassEffect(.regular, in: .rect(cornerRadius: 12))` and `.glassEffect(.regular, in: .capsule)`), 2-parameter `.onChange`, top-section `"Nhớ ngôn ngữ theo từng ứng dụng (Remember language per app)"` toggle, interactive shortcut recorder (`"Đổi phím tắt..."`), and Launch-at-Login error rollback/display (`REQ-005`, `REQ-007`, `REQ-008`, `REQ-013`).
  - [x] Update `build-app.sh` with Keychain signing identity auto-detection, `--setup-cert` local certificate generator, and explicit `--identifier com.tuyenmai.openkey.swift -r='designated => identifier "com.tuyenmai.openkey.swift"'` (`REQ-009`).
  - [x] Run `swift test`, rebuild `/Applications/OpenKeySwift.app`, update `verification.md`, and verify spec compliance via `spec_checker.py` (`REQ-001`..`REQ-013`).
- [x] **Task 8: Convert C++ Vietnamese Engine to 100% Pure Swift 6, Remove `OpenKeyEngineBridge` & Add Conversion Provenance Attribution** (`REQ-001`, `REQ-003`, `REQ-005`, `REQ-014`, `REQ-015`)
  - [x] Write unit tests in `OpenKeySwiftTests.swift` (TDD RED/characterization) verifying Pure Swift engine parity across complex Telex/VNI syllables (`tiếng`, `việt`, `trường`, `nghiêng`, `quốc`, `giữ`, `oà`/`òa` modern vs old orthography, `đ`/`Đ`, standalone `w` -> `ư`, `[[` -> `[`, backspace grammar re-evaluation, space word restore on backspace, and invalid spelling auto-restore) plus attribution metadata (`REQ-003`, `REQ-014`, `REQ-015`).
  - [x] Implement `Sources/OpenKey/macOS-Swift/Sources/OpenKeySwiftCore/VietnameseData.swift` porting `DataType.h`, `mac.h`, and `Vietnamese.h/.cpp` in 100% Pure Swift 6 with provenance header (`REQ-014`, `REQ-015`).
  - [x] Implement `Sources/OpenKey/macOS-Swift/Sources/OpenKeySwiftCore/VietnameseEngine.swift` porting `Engine.h/.cpp` and `SmartSwitchKey.h/.cpp` in 100% Pure Swift 6 with provenance header (`REQ-014`, `REQ-015`).
  - [x] Delete `Sources/OpenKey/macOS-Swift/Sources/OpenKeyEngineBridge/` and update `Package.swift`, `EventTapCoordinator.swift`, `OpenKeySettingsStore.swift`, and `OpenKeySwiftTests.swift` to remove `import OpenKeyEngineBridge` (`REQ-001`, `REQ-014`).
  - [x] Add explicit Pure Swift 6 conversion attribution to `SettingsView.swift` (`"Giới thiệu"` section), `OpenKeySwiftApp.swift` (status bar menu item), `Info.plist` (`NSHumanReadableCopyright`), and `README.md` (`REQ-015`).
  - [x] Run `swift test`, rebuild and deploy `/Applications/OpenKeySwift.app`, verify zero C++/Obj-C++ objects and update `verification.md` (`REQ-001`..`REQ-015`).
