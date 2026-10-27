# Specification: Native Swift/SwiftUI macOS Input Method (`2026-10-26-macos-swift-ime`)

- **Feature ID**: `2026-10-26-macos-swift-ime`
- **Status**: `Completed`
- **Date**: 2026-10-26

## 1. Overview & Problem Statement

The built-in macOS Vietnamese input method (`InputMethodKit`) relies on uncommitted marked text (`setMarkedText:`), which causes underline artifacts, duplicated characters in browser/IDE autocomplete fields, and swallowed `Enter`/`Tab` keystrokes. Meanwhile, Mac App Store wrappers such as `TomBoKey` are forced into `com.apple.security.app-sandbox = true`, which causes `sandboxd` to block `com.apple.universalaccessAuthWarn` Mach lookups during `AXIsProcessTrustedWithOptions` and interferes with global event injection. Furthermore, the legacy Objective-C++ `ModernKey` target and C++ engine in this repository contain `CFTypeRef` memory management bugs, unchecked buffer deserialization, and dead legacy features (`TCVN3`, `VNI Windows`, `Unicode Compound`, `CP1258`, `Simple Telex 1/2`, `ConvertTool`, `Macro`, `QuickTelex`, `QuickConsonant`).

This feature establishes and hardens a modern, unsandboxed 100% Pure Swift 6 / SwiftUI macOS input method under `Sources/OpenKey/macOS-Swift/` converted from the original C++ `OpenKey` engine by Mai Vũ Tuyên.

---

## 2. Normative Requirements

### `REQ-001`: Project Structure & Engine Module Architecture (`Sources/OpenKey/macOS-Swift/`)
- **Description**: The macOS Swift/SwiftUI application MUST reside under `Sources/OpenKey/macOS-Swift/` and expose the OpenKey Vietnamese composition engine and SmartSwitchKey API (`OKEngineInit`, `OKEngineSyncConfig`, `OKEngineHandleKeyEvent`, `OKEngineResetSession`, `OKEngineKeyCodeToChar`, `OKInitSmartSwitchKey`, `OKGetAppInputMethodStatus`, `OKSetAppInputMethodStatus`, `OKGetSmartSwitchKeySaveData`) to the app and unit tests (initially bridged via `OpenKeyEngineBridge` and subsequently converted to 100% Pure Swift 6 inside `OpenKeySwiftCore` per `REQ-014`).
- **Acceptance Criteria**:
  1. `Sources/OpenKey/macOS-Swift/` builds cleanly from the command line (`swift build`) and produces an executable macOS `.app` bundle.
  2. Engine calls (`OKEngineInit`, `OKEngineHandleKeyEvent`, `OKEngineResetSession`, `OKInitSmartSwitchKey`, `OKGetAppInputMethodStatus`, `OKSetAppInputMethodStatus`) are directly callable from Swift and unit tests.

### `REQ-002`: Unsandboxed `CGEventTap` Lifecycle, Wake Recovery & Accessibility Permission Management
- **Description**: The application MUST run unsandboxed (`com.apple.security.app-sandbox` omitted/false) and manage a session-level Quartz Event Tap (`CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault, ...)`).
- **Acceptance Criteria**:
  1. On launch, the app checks `AXIsProcessTrustedWithOptions` and displays a clear SwiftUI onboarding/permission status indicator if Accessibility permission is not yet granted.
  2. Once Accessibility permission is granted, the app automatically activates the `CGEventTap` without requiring a manual app restart.
  3. If macOS disables the event tap due to `kCGEventTapDisabledByTimeout` or `kCGEventTapDisabledByUserInput`, or when the system wakes from sleep (`NSWorkspace.didWakeNotification`), the tap is automatically re-enabled and the engine session is reset.
  4. Events synthesized by the input method itself are tagged with a private `CGEventSourceRef` state ID / user data (`0xBEEF`) so the callback never re-processes its own injected events.

### `REQ-003`: Telex & VNI Input with Precomposed Unicode Only, Orthography Validation & Auto-Restore
- **Description**: The input method MUST support strictly Telex (`0`) and VNI (`1`) input schemes and strictly precomposed Unicode, with configurable spelling validation (`vCheckSpelling`), modern orthography (`vUseModernOrthography`), and automatic restoration of raw English keystrokes when a word violates Vietnamese phonology (`vRestoreIfWrongSpelling`).
- **Acceptance Criteria**:
  1. Typing Vietnamese syllables in Telex (e.g., `tiengs` -> `tiếng`, `vietej` -> `việt`) and VNI (e.g., `tieng61` -> `tiếng`) produces the exact expected precomposed Unicode characters and backspace counts.
  2. `OpenKeySettingsStore` clamps `inputType` strictly to `0` (`Telex`) or `1` (`VNI`).
  3. When `vCheckSpelling = 1` and `vRestoreIfWrongSpelling = 1`, typing an invalid Vietnamese sequence (e.g., English words like `window`, `function`, `string`) followed by a word-break key restores the raw keystrokes.

### `REQ-004`: Bypass on Spotlight Overlay, Terminal Emulators, Remote Desktop/VMs & `Cmd + Tab`, and App-Aware Autocomplete Fix
- **Description**: The event tap MUST bypass Vietnamese composition on macOS Spotlight overlay, terminal emulators, remote desktop/VM consoles, and command/modifier shortcuts (`Cmd + Tab`, `Cmd + Space`, etc.), and use an app-aware empty-character breaker (`U+200C` in Sublime Text, `U+202F` elsewhere, skipped when `extCode == 4`).
- **Acceptance Criteria**:
  1. When the macOS Spotlight overlay search window is visible on screen or when the frontmost application is a terminal emulator (`com.apple.Terminal`, `com.googlecode.iterm2`, `dev.warp.Warp-Stable`, `dev.warp.Warp`, `com.mitchellh.ghostty`, `org.alacritty`, `io.alacritty`, `net.kovidgoyal.kitty`, `co.zeit.hyper`, `com.github.wez.wezterm`) or raw-keycode VM/remote-desktop client (`com.vmware.fusion`, `com.parallels.desktop.console`, `com.microsoft.rdc.macos`, `org.virtualbox.app.VirtualBoxVM`, `com.utmapp.UTM`), `EventTapCoordinator` resets the engine session (`OKEngineResetSession()`) and passes keystrokes through untouched.
  2. Pressing `Cmd + Tab` (any `.maskCommand`, `.maskControl`, or `.maskAlternate` key event) or switching active applications (`NSWorkspace.didActivateApplicationNotification`) immediately calls `OKEngineResetSession()` so uncommitted syllable state never leaks across application switches.
  3. Replacement characters are posted in batched UTF-16 `CGEventKeyboardSetUnicodeString` events, and when `vFixRecommendBrowser = 1`, `backspaceCount > 0`, and `extCode != 4`, `KeystrokeInjector` emits `U+200C` (`zeroWidthNonJoiner`) for Sublime Text (`com.sublimetext.*`) or `U+202F` (`narrowNoBreakSpace`) for all other apps and increments `backspaceCount` by `1` before sending Backspaces. When `extCode == 4` or `fixRecommendBrowser == false`, `.standardBackspace` is used.

### `REQ-005`: Configurable Per-App Smart Language Switching (Remember Per App vs Global Mode) & Safe Deserialization
- **Description**: The input method MUST provide an explicit user-configurable option to remember input language per application (`useSmartSwitchKey`, enabled by default) or use a single global language across all applications (`useSmartSwitchKey = false`), surfaced in both the status bar menu and the top Input & Language section of the Settings window.
- **Acceptance Criteria**:
  1. Per-app language memory (`useSmartSwitchKey`) defaults to `true` and can be toggled on or off from both the menu bar dropdown (`"Nhớ ngôn ngữ theo ứng dụng"`) and the Settings window (`"Nhớ ngôn ngữ theo từng ứng dụng (Remember language per app)"`).
  2. When `useSmartSwitchKey = true`, manually toggling or selecting the language updates `OKSetAppInputMethodStatus` for the active/last non-OpenKey application bundle ID (`activeAppBundleId`, ignoring `"com.tuyenmai.openkey.swift"`) and persists the binary map to `UserDefaults`, and switching focus between App A and App B (`NSWorkspace.didActivateApplicationNotification`) restores each app's saved language state and resets the engine word session (`startNewSession()`). When `useSmartSwitchKey` is toggled from `false` to `true`, the current `language` is immediately recorded for `activeAppBundleId`.
  3. When `useSmartSwitchKey = false`, switching focus between applications resets the engine word session (`OKEngineResetSession()`) without changing `settings.language` or consulting/mutating `SmartSwitchKey` per-app state (keeping the language global across all applications).
  4. `initSmartSwitchKey` in `Sources/OpenKey/engine/SmartSwitchKey.cpp` validates buffer boundaries (`cursor + len <= size`) before every `memcpy` or `std::string` construction, preventing out-of-bounds reads on truncated or corrupted inputs.

### `REQ-006`: CoreFoundation Memory Safety, Non-QWERTY Exclusion & Notification-Cached Keyboard Layout Guard (`vOtherLanguage`)
- **Description**: When `vOtherLanguage = 1`, the input method MUST bypass Vietnamese processing whenever the active macOS system keyboard layout primary language is not `"en"` OR when the layout is a non-QWERTY English layout (`Dvorak`, `Colemak`, `AZERTY`), without leaking CoreFoundation objects or querying `TISCopyCurrentKeyboardInputSource()` on every keystroke.
- **Acceptance Criteria**:
  1. `TISCopyCurrentKeyboardInputSource()` (`isource`) is released properly on every code path, and unowned `CFStringRef` values obtained from `CFArrayGetValueAtIndex` are never passed to `CFRelease`.
  2. `InputSourceGuard` returns `false` when the input source ID (`kTISPropertyInputSourceID`) contains `"Dvorak"`, `"Colemak"`, or `"AZERTY"` (case-insensitive) or when the primary language does not start with `"en"`.
  3. `InputSourceGuard` caches the layout check result in memory and invalidates the cache upon receiving `kTISNotifySelectedKeyboardInputSourceChanged` from `DistributedNotificationCenter`, avoiding per-keystroke `TISCopyCurrentKeyboardInputSource()` IPC overhead.

### `REQ-007`: Customizable Toggle Shortcut Defaulting to `Option + Z` with Auto-Repeat Suppression, Key-Up Swallowing & Safe Modifier-Only Tap
- **Description**: The language toggle shortcut MUST default to `Option + Z` (`vSwitchKeyStatus = 0x7A000206`), support interactive user recording in the Settings UI, suppress key auto-repeat when held, swallow the matching `keyUp` event, and trigger modifier-only shortcuts (`0xFE`) strictly on clean release when no other key was pressed.
- **Acceptance Criteria**:
  1. Pressing `Option + Z` (or the user-configured shortcut) on initial `.keyDown` (`keyboardEventAutorepeat == 0`) toggles `language` between Vietnamese (`1`) and English (`0`), updates the menu bar icon immediately, persists per-app state when `useSmartSwitchKey = true`, and resets the engine session.
  2. Holding the shortcut (`keyboardEventAutorepeat != 0`) swallows the repeated `.keyDown` without re-toggling `language`, and releasing the shortcut key swallows the corresponding `.keyUp` so the active application never receives an orphaned `keyUp`.
  3. When configured as a modifier-only shortcut (`keyCode == 0xFE`), pressing the modifier arms a pending tap, pressing any regular key or mouse button while held cancels the pending tap, and releasing the modifier triggers `toggleLanguage()` only if no other key was pressed during the hold.

### `REQ-008`: Native SwiftUI Menu Bar (Cached Monochrome Icons) & Settings Interface (Per-App Memory Toggle, Interactive Shortcut Recorder & Launch-at-Login Error Recovery)
- **Description**: The app MUST provide a lightweight native macOS status bar item with cached monochrome `V` / `E` template icons, a one-click per-app language memory toggle in the status bar menu and Settings window, an interactive shortcut recorder, and an error-checked Launch-at-Login toggle.
- **Acceptance Criteria**:
  1. `OpenKeySwiftApp` pre-renders and caches the monochrome `V` and `E` `NSImage` instances (`isTemplate = true`, `15.5 × 15.5pt` filled keycap with knockout character), updates `statusItem.button.image` strictly on `settings.$language.removeDuplicates()` without subscribing to `UserDefaults.didChangeNotification`, and includes a checkable `"Nhớ ngôn ngữ theo ứng dụng"` menu item bound to `settings.useSmartSwitchKey`.
  2. `SettingsView` places the `"Nhớ ngôn ngữ theo từng ứng dụng (Remember language per app)"` toggle prominently in the top `"Bộ gõ & Ngôn ngữ (Input & Language)"` group box, and includes an interactive shortcut recorder button (`"Đổi phím tắt..."`) that captures modifier+key or modifier-only shortcuts (with `Esc` to cancel) alongside the `"Mặc định (⌥Z)"` reset button.
  3. If `SMAppService.mainApp.register()` or `unregister()` throws an error, `SettingsView` reverts `settings.launchAtLogin` to match `SMAppService.mainApp.status == .enabled` and displays the error text in the System section instead of failing silently.

### `REQ-009`: Stable Code-Signing Identity & Designated Requirement in `build-app.sh`
- **Description**: `build-app.sh` MUST sign `OpenKeySwift.app` using a stable code-signing identity when available in the user's Keychain (or `CODESIGN_IDENTITY`), and embed an explicit bundle-identifier designated requirement so macOS TCC (`tccd`) can anchor Accessibility permissions to `com.tuyenmai.openkey.swift`.
- **Acceptance Criteria**:
  1. `build-app.sh` checks `CODESIGN_IDENTITY` or queries `security find-identity -v -p codesigning` for an available signing identity, falling back to ad-hoc (`-`) only when no certificate exists in Keychain, and includes `--identifier com.tuyenmai.openkey.swift` and `-r='designated => identifier "com.tuyenmai.openkey.swift"'`.
  2. `build-app.sh` provides a `--setup-cert` helper mode that generates a local self-signed code-signing certificate (`OpenKey Local Signer`) in the user's login keychain when requested.

### `REQ-010`: Zero-IPC Hot-Path Ordering & Accurate Spotlight Overlay Detection
- **Description**: `EventTapCoordinator` MUST order its event-handling fast path so non-`keyDown` events, modifier shortcuts, and English mode (`language == 0`) exit in O(1) before any app, Spotlight, or keyboard layout checks, and Spotlight overlay detection MUST avoid per-keystroke `NSWorkspace`/`NSRunningApplication` polling and ignore small status-bar windows.
- **Acceptance Criteria**:
  1. In `EventTapCoordinator`, after self-event filtering, mouse session reset, and hotkey handling:
     - Modifier shortcuts (`.maskCommand`, `.maskControl`, `.maskAlternate`) reset the session and return immediately.
     - Non-`.keyDown` events return immediately.
     - English mode (`settings.language == 0`) returns immediately in O(1) without calling `isSpotlightOverlayVisible` or `InputSourceGuard`.
  2. `EventTapCoordinator` uses its notification-maintained `settings.activeAppBundleId` instead of querying `NSWorkspace.shared.frontmostApplication` on every keystroke, and caches `isSpotlightOverlayVisible` with a short TTL (`0.15s`, invalidated immediately when `Cmd + Space` is pressed or active app changes) while requiring any `"Spotlight"` window in `CGWindowListCopyWindowInfo` to have `kCGWindowLayer > 0` and bounds `width >= 200 && height >= 40`.

### `REQ-011`: Pure Testable Event-Routing Pipeline (`evaluateKeyEvent`)
- **Description**: `EventTapCoordinator` MUST expose a pure, deterministic routing function (`evaluateKeyEvent`) accepting a value-type `KeyEventContext` and returning an explicit `EventTapAction` enum so all event-tap bypass, hotkey, and replacement decisions can be unit-tested without live `CGEventTap` or `WindowServer` dependencies.
- **Acceptance Criteria**:
  1. `EventTapCoordinator.evaluateKeyEvent(_ context: KeyEventContext) -> EventTapAction` deterministically handles self-events (`0xBEEF`), mouse resets, hotkey `keyDown` / auto-repeat / `keyUp` swallowing, modifier-only tap state transitions, modifier bypasses (`Cmd + Tab`), English-mode fast return, Terminal/VM/Spotlight bypasses, non-English/Dvorak layout bypasses, and C++ engine replacement dispatch.
  2. `OpenKeySwiftTests` verifies every branch of `evaluateKeyEvent` with automated unit tests.

### `REQ-012`: Dead Legacy Code Removal Across `Sources/OpenKey/engine/` and `OpenKeyEngineBridge`
- **Description**: All dead legacy code, unused global variables, and obsolete source files (`ConvertTool.h/.cpp`, `Macro.h/.cpp`, legacy code tables `TCVN3`/`VNI Windows`/`Unicode Compound`/`CP 1258`, `vSimpleTelex1/2`, `vQuickTelex`, `vQuickStartConsonant`, `vQuickEndConsonant`, `vAllowConsonantZFWJ`, `vUpperCaseFirstChar`, `vFreeMark`, `vTempOffSpelling`, `vTempOffOpenKey`, `vRememberCode`) MUST be completely removed from `Sources/OpenKey/engine/` and `OpenKeyEngineBridge.mm`.
- **Acceptance Criteria**:
  1. `Sources/OpenKey/engine/ConvertTool.h`, `Sources/OpenKey/engine/ConvertTool.cpp`, `Sources/OpenKey/engine/Macro.h`, and `Sources/OpenKey/engine/Macro.cpp` are deleted, and `#include "Macro.h"` / `#include "../../../engine/Macro.cpp"` are removed from `OpenKeyEngineBridge.mm`.
  2. `Vietnamese.h` and `Vietnamese.cpp` contain strictly the single Precomposed Unicode table (`map<Uint32, vector<Uint16>> _codeTable`), with `_codeTable[1..4]`, `_unicodeCompoundMark`, `_quickTelex`, `_quickStartConsonant`, and `_quickEndConsonant` removed.
  3. `DataType.h`, `Engine.h`, `Engine.cpp`, and `OpenKeyEngineBridge.mm` define and reference strictly the 7 active configuration globals (`vLanguage`, `vInputType`, `vCheckSpelling`, `vUseModernOrthography`, `vRestoreIfWrongSpelling`, `vFixRecommendBrowser`, `vUseSmartSwitchKey`), with all `vSimpleTelex1/2`, `vReplaceMaro`, `handleQuickTelex`, `checkQuickConsonant`, and `upperCaseFirstCharacter` branches deleted.

### `REQ-013`: macOS 26 (Tahoe) Native SDK Target, `@Observable` State Management & Liquid Glass UI (`SettingsView`)
- **Description**: The Swift package and app bundle MUST target macOS 26.0 (`Tahoe`), migrate `OpenKeySettingsStore` from legacy `Combine` (`ObservableObject` / `@Published`) to the Swift `Observation` framework (`@Observable`), and adopt macOS 26 Liquid Glass (`.glassEffect`) and grouped `Form` styling (`.formStyle(.grouped)`) with zero deprecated SwiftUI modifiers.
- **Acceptance Criteria**:
  1. `Package.swift` targets `.macOS("26.0")` (`swift-tools-version: 6.0`, `cxxLanguageStandard: .cxx17`) and `Info.plist` sets `LSMinimumSystemVersion` to `26.0`, eliminating legacy macOS 13 deployment-target linker warnings against `Testing.framework`.
  2. `OpenKeySettingsStore` uses `@Observable` (`import Observation`) instead of `ObservableObject` / `@Published`, and `SettingsView` binds via `@Bindable var settings = OpenKeySettingsStore.shared` with zero `import Combine` dependencies.
  3. `SettingsView` uses native `Form` with `.formStyle(.grouped)`, applies macOS 26 Liquid Glass `.glassEffect(.regular, in: .rect(cornerRadius: 12))` to the Accessibility status banner and `.glassEffect(.regular, in: .capsule)` to the shortcut badge, and replaces deprecated 1-parameter `.onChange(of:)` and `.cornerRadius(_:)` modifiers with modern 2-parameter `.onChange(of:) { _, newValue in }` and shape modifiers.

### `REQ-014`: 100% Pure Swift 6 Vietnamese Engine & Removal of C++/Objective-C++ Bridge (`OpenKeySwiftCore`)
- **Description**: All remaining C++ and Objective-C++ code (`Engine.cpp/.h`, `Vietnamese.cpp/.h`, `DataType.h`, `SmartSwitchKey.cpp/.h`, and `OpenKeyEngineBridge.mm/.h`) MUST be converted to 100% native Swift 6 inside `OpenKeySwiftCore` (`VietnameseData.swift` and `VietnameseEngine.swift`), eliminating the `OpenKeyEngineBridge` target and all C++/Objective-C++ compilation from `OpenKeySwift`.
- **Acceptance Criteria**:
  1. `Sources/OpenKey/macOS-Swift/Sources/OpenKeyEngineBridge/` is deleted, `Package.swift` contains strictly pure Swift targets (`OpenKeySwiftCore`, `OpenKeySwiftApp`, `OpenKeySwiftTests`) with no `cxxLanguageStandard` or C++ header search paths, and the compiled `/Applications/OpenKeySwift.app/Contents/MacOS/OpenKeySwift` binary contains zero C++ or Objective-C++ translation units.
  2. `VietnameseData.swift` and `VietnameseEngine.swift` in `OpenKeySwiftCore` faithfully port the entire Vietnamese Telex/VNI syllable composition engine (`vKeyInit`, `vKeyHandleEvent`, `startNewSession`, `checkSpelling`, `findAndCalculateVowel`, `checkGrammar`, `handleModernMark`, `handleOldMark`, `insertMark`, `insertD`, `insertAOE`, `insertW`, `checkForStandaloneChar`, `removeMark`, `checkRestoreIfWrongSpelling`, `saveWord`, `restoreLastTypingState`, and `SmartSwitchKey` binary serialization/lookup) in pure Swift 6 with 100% behavioral parity across all unit tests.
  3. Existing public engine entry points (`OKEngineInit`, `OKEngineSyncConfig`, `OKEngineHandleKeyEvent`, `OKEngineResetSession`, `OKEngineKeyCodeToChar`, `OKInitSmartSwitchKey`, `OKGetAppInputMethodStatus`, `OKSetAppInputMethodStatus`, `OKGetSmartSwitchKeySaveData`) are implemented in pure Swift inside `OpenKeySwiftCore` so `EventTapCoordinator`, `OpenKeySettingsStore`, and `OpenKeySwiftTests` operate without C interop.

### `REQ-015`: Explicit Conversion Provenance & Attribution Across UI, Bundle Metadata & Documentation
- **Description**: The application UI (`SettingsView` and status bar menu), bundle metadata (`Info.plist`), source headers (`VietnameseData.swift`, `VietnameseEngine.swift`), and repository `README.md` MUST clearly state that `OpenKeySwift` is a **100% Pure Swift 6 conversion** of the original C++/Objective-C++ `OpenKey` project by Mai Vũ Tuyên.
- **Acceptance Criteria**:
  1. `SettingsView` displays a dedicated attribution section/footer clearly stating that `OpenKeySwift` is converted to 100% Pure Swift 6 (macOS 26) from the original C++ `OpenKey` engine by Mai Vũ Tuyên, and `OpenKeySwiftApp` includes a conversion attribution line in the status bar menu.
  2. `Sources/OpenKey/macOS-Swift/Info.plist` sets `NSHumanReadableCopyright` to credit both the Pure Swift 6 conversion and the original `OpenKey` work (`© Mai Vũ Tuyên, GPLv3`).
  3. `VietnameseData.swift`, `VietnameseEngine.swift`, and `README.md` document the Pure Swift 6 conversion provenance and credit the original C++ `OpenKey` architecture by Mai Vũ Tuyên.
