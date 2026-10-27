# Architecture Decision Records (`2026-10-26-macos-swift-ime`)

## `ADR-001`: Unsandboxed Distribution with `CGEventTap` Instead of `InputMethodKit` or App Sandbox
- **Status**: Proposed
- **Date**: 2026-10-26
- **Addresses**: `REQ-002`, `REQ-004`
- **Context**:
  - Apple's `InputMethodKit` (`IMKServer`) forces an uncommitted marked-text composition underline (`setMarkedText:`), which breaks inline autocomplete in browsers, Spotlight, and IDEs, and requires pressing `Enter`/`Tab` twice.
  - Mac App Store distribution requires `<key>com.apple.security.app-sandbox</key><true/>`. Forensic analysis of `TomBoKey` (`PID 95563`) on macOS 26.6.2 confirmed that `sandboxd` denies `mach-lookup com.apple.universalaccessAuthWarn` (`error = 159: Sandbox restriction`) during `AXIsProcessTrustedWithOptions` and blocks `job-creation`.
- **Decision**:
  - Build the application as an unsandboxed macOS menu-bar utility (`LSUIElement = true`) using `CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault, ...)` and `CGEventTapPostEvent`, with automatic re-enable on timeout, user input disable, and system wake (`NSWorkspace.didWakeNotification`).
- **Consequences**:
  - Zero marked-text underline bugs; full compatibility with browser address bars, Spotlight, and IDEs.
  - Requires user-granted Accessibility permission in **System Settings > Privacy & Security > Accessibility** and distribution outside the Mac App Store.

---

## `ADR-002`: Swift/SwiftUI App Layer Over Existing C++ `OpenKey` Engine via Objective-C++/C Bridge
- **Status**: Proposed
- **Date**: 2026-10-26
- **Addresses**: `REQ-001`, `REQ-003`, `REQ-008`
- **Context**:
  - The C++ engine in `Sources/OpenKey/engine/` (`Engine.cpp`, `Vietnamese.cpp`, `SmartSwitchKey.cpp`) implements Vietnamese phonological rules, vowel/tone tables, word history stacks (`_typingStates`), and smart-switch maps.
  - Rewriting the phonological state machine from scratch risks regressing edge-case syllables (`quởn`, `huỵch`, `gìn`, `tuýp`), whereas the legacy AppKit UI in `Sources/OpenKey/macOS/ModernKey/` is dated and couples UI directly to global C variables.
- **Decision**:
  - Create a Swift Package / Xcode target under `Sources/OpenKey/macOS-Swift/` containing:
    1. `OpenKeyEngineBridge` (C++/Objective-C++ target compiling `Sources/OpenKey/engine/*.cpp` and exposing a clean C API header `OpenKeyEngineBridge.h`).
    2. `OpenKeySwiftCore` (Swift library implementing the `CGEventTap` manager, keystroke injector, Spotlight/Browser workarounds, `TISInputSource` guard, and settings store).
    3. `OpenKeySwiftApp` (SwiftUI menu bar executable target).
    4. `OpenKeySwiftTests` (Unit test suite verifying the C++ engine bridge, bounds-checked deserialization, Telex/VNI typing, auto-restore, hotkey matching, and event-tap routing).
- **Consequences**:
  - Preserves 100% compatibility with `Sources/OpenKey/engine/` while enabling fast automated `swift test` verification and a modern SwiftUI interface.

---

## `ADR-003`: Bypass on Spotlight Overlay, Terminal Emulators & VMs + App-Aware Empty-Character Autocomplete Breaker
- **Status**: Proposed
- **Date**: 2026-10-26
- **Addresses**: `REQ-003`, `REQ-004`, `REQ-008`
- **Context**:
  - macOS Spotlight (`Cmd + Space`) renders as a floating overlay window (`kCGWindowOwnerName == "Spotlight"`) without changing `NSWorkspace.shared.frontmostApplication`, and users typing file/app queries, CLI commands in terminal emulators, or raw keycodes in VM/remote-desktop clients do not want Vietnamese composition or `U+202F` characters injected.
  - In Sublime Text (`com.sublimetext.*`), `U+202F` renders visibly before deletion whereas `U+200C` (Zero-Width Non-Joiner) is invisible, and when `extCode == 4` (word-break/restore boundary), no empty breaker character should be injected.
- **Decision**:
  - Bypass Vietnamese composition completely (and reset the engine session via `OKEngineResetSession()`) when the Spotlight overlay search window (`width >= 200 && height >= 40`) is visible on screen, when the frontmost application is a terminal emulator or VM/remote-desktop client, or when `Cmd`/`Ctrl`/`Option` shortcuts (`Cmd + Tab`) are pressed.
  - Restrict input methods strictly to `Telex` (`0`) and `VNI` (`1`) and Precomposed Unicode.
  - In `KeystrokeInjector.determineStrategy`, use `.emptyCharBreaker(emptyChar: 0x200C)` for Sublime Text (`com.sublimetext.*`) and `.emptyCharBreaker(emptyChar: 0x202F)` for other apps when `fixRecommendBrowser == true && backspaceCount > 0 && extCode != 4`, and `.standardBackspace` otherwise.
- **Consequences**:
  - Clean, predictable behavior in Spotlight, terminals, VMs, Sublime Text, and browsers.

---

## `ADR-004`: Bounds-Checked Binary Deserialization in `SmartSwitchKey.cpp`
- **Status**: Proposed
- **Date**: 2026-10-26
- **Addresses**: `REQ-005`
- **Context**:
  - `initSmartSwitchKey` (`Sources/OpenKey/engine/SmartSwitchKey.cpp`) reads raw `Byte*` buffers from `NSUserDefaults` without verifying that `cursor + bundleIdSize + 1 <= size`.
- **Decision**:
  - Add explicit bounds checks before every read in `initSmartSwitchKey`, aborting deserialization cleanly if a truncated or malformed buffer is encountered. Also fix `CFRelease` memory management in `Sources/OpenKey/macOS/ModernKey/OpenKey.mm` and the new Swift core (`REQ-006`).
- **Consequences**:
  - Eliminates out-of-bounds heap reads and CoreFoundation memory leaks/crashes.

---

## `ADR-005`: Default Language Toggle Shortcut `Option + Z` (`0x7A000206`) with Auto-Repeat Suppression, Key-Up Swallowing & Clean Modifier-Only Release
- **Status**: Proposed
- **Date**: 2026-10-26
- **Addresses**: `REQ-007`
- **Context**:
  - Holding `Option + Z` generates key-repeat `.keyDown` events (`keyboardEventAutorepeat == 1`) that would rapidly toggle the language back and forth, and swallowing only `.keyDown` leaks an orphaned `.keyUp` to the active app. Additionally, modifier-only shortcuts (`0xFE`) must not trigger when used as part of a multi-key chord (e.g. `Ctrl + Option + Left`).
- **Decision**:
  - Use `Option + Z` (`0x7A000206`) as the default switch shortcut, provide an interactive shortcut recorder in `SettingsView`, ignore auto-repeated `.keyDown` events when matching the shortcut while still swallowing them, swallow the matching `.keyUp` event, and trigger modifier-only shortcuts strictly on modifier release when no intervening key or mouse event occurred.
- **Consequences**:
  - Reliable shortcut toggling with zero bounce on key-hold, zero leaked `keyUp` events, and zero conflict with modifier chords.

---

## `ADR-006`: Stable Code-Signing Identity & Designated Requirement in `build-app.sh`
- **Status**: Proposed
- **Date**: 2026-10-26
- **Addresses**: `REQ-009`
- **Context**:
  - Bare ad-hoc signing (`codesign --sign -`) binds macOS TCC Accessibility grants to the binary's `cdhash`, which changes on every recompile.
- **Decision**:
  - Update `build-app.sh` to auto-detect a valid code-signing certificate in the user's Keychain (`CODESIGN_IDENTITY` or `security find-identity -v -p codesigning`, plus a `--setup-cert` flag to create a local `OpenKey Local Signer` certificate), and pass `--identifier com.tuyenmai.openkey.swift -r='designated => identifier "com.tuyenmai.openkey.swift"'` to `codesign`.
- **Consequences**:
  - Preserves TCC identity across rebuilds when signed with a local or developer certificate and anchors the designated requirement to `com.tuyenmai.openkey.swift`.

---

## `ADR-007`: Zero-IPC Hot-Path Ordering & Notification-Driven Caching in `EventTapCoordinator` and `InputSourceGuard`
- **Status**: Proposed
- **Date**: 2026-10-26
- **Addresses**: `REQ-006`, `REQ-010`
- **Context**:
  - Querying `NSWorkspace.shared.frontmostApplication`, `CGWindowListCopyWindowInfo`, and `TISCopyCurrentKeyboardInputSource()` on every key event (including modifier events and English mode) adds synchronous IPC latency to the main thread event tap.
- **Decision**:
  - Order the event tap fast path so modifier shortcuts, non-`keyDown` events, and English mode (`language == 0`) return in O(1) before any app, Spotlight, or layout check.
  - Use notification-updated `settings.activeAppBundleId` instead of querying `NSWorkspace` per key, cache `InputSourceGuard` results with invalidation on `kTISNotifySelectedKeyboardInputSourceChanged` (while also rejecting `Dvorak`/`Colemak`/`AZERTY` non-QWERTY layouts), and cache `isSpotlightOverlayVisible` with a `0.15s` TTL invalidated on `Cmd + Space` or app switch.
- **Consequences**:
  - Eliminates per-keystroke IPC overhead in the `CGEventTap` callback and prevents event-tap timeouts.

---

## `ADR-008`: Pure Value-Type Event-Routing Function (`evaluateKeyEvent`) for Deterministic Unit Testing
- **Status**: Proposed
- **Date**: 2026-10-26
- **Addresses**: `REQ-011`
- **Context**:
  - Coupling `CGEvent` extraction and system queries directly inside `handleEvent` previously prevented unit tests from exercising the event-tap routing pipeline.
- **Decision**:
  - Extract `evaluateKeyEvent(_ context: KeyEventContext) -> EventTapAction` in `EventTapCoordinator` so the entire routing state machine (self-events, mouse resets, hotkey keyDown/auto-repeat/keyUp, modifier-only tap state machine, modifier bypass, English mode, Terminal/VM/Spotlight bypass, layout guard, and C++ engine replacement) is deterministically testable in `OpenKeySwiftTests`.
- **Consequences**:
  - 100% unit-testable core event-tap routing logic without requiring synthetic `WindowServer` sessions during `swift test`.

---

## `ADR-009`: Purge Dead Legacy Files, Code Tables & Branches from `Sources/OpenKey/engine/`
- **Status**: Proposed
- **Date**: 2026-10-26
- **Addresses**: `REQ-003`, `REQ-012`
- **Context**:
  - After removing Simple Telex, legacy code tables (`TCVN3`, `VNI Windows`, `Unicode Compound`, `CP 1258`), `ConvertTool`, `Macro`, and legacy typing flags from the Swift UI/store in Task 6, dead files (`ConvertTool.h/.cpp`, `Macro.h/.cpp`), 60 lines of non-Unicode tables in `Vietnamese.cpp`, 12 unused `extern int` globals, and dead branches in `Engine.cpp` remained in `Sources/OpenKey/engine/` and `OpenKeyEngineBridge.mm`.
- **Decision**:
  - Delete `ConvertTool.h`, `ConvertTool.cpp`, `Macro.h`, and `Macro.cpp` from `Sources/OpenKey/engine/`.
  - Flatten `_codeTable` in `Vietnamese.h/.cpp` to a single Precomposed Unicode `map<Uint32, vector<Uint16>> _codeTable` and remove `_unicodeCompoundMark`, `_quickTelex`, `_quickStartConsonant`, and `_quickEndConsonant`.
  - Strip all dead `extern int` globals and dead branches (`vSimpleTelex1/2`, `vReplaceMaro`, `handleQuickTelex`, `checkQuickConsonant`, `upperCaseFirstCharacter`, `isMacroBreakCode`) from `DataType.h`, `Engine.h`, `Engine.cpp`, and `OpenKeyEngineBridge.mm`.
- **Consequences**:
  - Reduces `Sources/OpenKey/engine/` by ~800 lines of dead legacy code and leaves only active, tested Telex/VNI Precomposed Unicode logic.

---

## `ADR-010`: macOS 26 (Tahoe) Deployment Target, Swift `@Observable` & Liquid Glass UI (`SettingsView`)
- **Status**: Proposed
- **Date**: 2026-10-26
- **Addresses**: `REQ-008`, `REQ-013`
- **Context**:
  - The host environment runs macOS 26.6.2 (Tahoe) with Swift 6.4 (`arm64-apple-macosx26.0`), while `Package.swift` was targeting `.macOS(.v13)` (`swift-tools-version: 5.7`), causing linker version-mismatch warnings with `Testing.framework` and relying on legacy `Combine` (`ObservableObject`/`@Published`), manual `ScrollView` + `GroupBox` layouts, and deprecated `.onChange(of:)` / `.cornerRadius(_:)` modifiers.
  - Note on `MenuBarExtra` vs `NSStatusItem` on macOS 26: We intentionally retain `NSStatusItem` in `AppDelegate` rather than SwiftUI `MenuBarExtra` because `NSStatusItem` allows pre-rendered `NSImage` caching and avoids macOS 26 accessory-app termination quirks when menu bar items are toggled in Control Center.
- **Decision**:
  - Upgrade `Package.swift` to `swift-tools-version: 6.0` targeting `.macOS("26.0")` (`cxxLanguageStandard: .cxx17`) and set `LSMinimumSystemVersion = 26.0` in `Info.plist`.
  - Migrate `OpenKeySettingsStore` to `@Observable` (`import Observation`) with a lightweight `onLanguageChanged` callback for `NSStatusItem` icon updates, eliminating `Combine` from the store, coordinator, and views.
  - Refactor `SettingsView` to use `Form` with `.formStyle(.grouped)` and macOS 26 Liquid Glass modifiers (`.glassEffect(.regular, in: .rect(cornerRadius: 12))` on the Accessibility banner and `.glassEffect(.regular, in: .capsule)` on the shortcut pill).
- **Consequences**:
  - Zero linker target-version warnings, zero `Combine` overhead, fine-grained SwiftUI property observation, and native macOS 26 Tahoe Liquid Glass visual integration.

---

## `ADR-011`: 100% Pure Swift 6 Vietnamese Engine Conversion & Explicit OpenKey Provenance Attribution
- **Status**: Proposed
- **Date**: 2026-10-26
- **Addresses**: `REQ-001`, `REQ-014`, `REQ-015`
- **Context**:
  - After Task 7 purged all dead legacy C++ code, the remaining C++ engine (`DataType.h`, `mac.h`, `Vietnamese.h/.cpp`, `SmartSwitchKey.h/.cpp`, `Engine.h/.cpp`) and Objective-C++ bridge (`OpenKeyEngineBridge.h/.mm`) totaled ~2,500 lines. Maintaining a mixed C++17 / Objective-C++ / Swift 6 build graph required C pointer marshalling, `std::map` / `std::vector` heap allocations, and `libc++.1.dylib` linkage.
  - At the same time, because the core Vietnamese syllable composition state machine and phonotactic tables originate from Mai Vũ Tuyên's `OpenKey` project, the converted application must prominently credit its provenance as a 100% Pure Swift 6 conversion of `OpenKey`.
- **Decision**:
  - Convert the entire C++ Vietnamese typing engine and `SmartSwitchKey` store into two pure Swift 6 files inside `OpenKeySwiftCore`:
    1. `VietnameseData.swift`: Key constants (`KEY_A`..`KEY_SLASH`), bitmasks (`CAPS_MASK`, `TONE_MASK`, `TONEW_MASK`, `MARK1_MASK`..`MARK5_MASK`, `CHAR_MASK`, `STANDALONE_MASK`, `CHAR_CODE_MASK`, `PURE_CHARACTER_MASK`, `END_CONSONANT_MASK`, `CONSONANT_ALLOW_MASK`), `OKHookSnapshot` struct, phonotactic tables (`_vowel`, `_vowelCombine`, `_vowelForMark`, `_consonantD`, `_consonantTable`, `_endConsonantTable`, `_standaloneWbad`, `_doubleWAllowed`, `_codeTable`, `_characterMap`), and `keyCodeToCharacter(_:)`.
    2. `VietnameseEngine.swift`: Full syllable buffer (`TypingWord`, `KeyStates`, `_typingStates`, `_longWordHelper`, `_specialChar`), Telex/VNI composition (`insertKey`, `insertAOE`, `insertW`, `insertD`, `insertMark`, `handleModernMark`, `handleOldMark`, `findAndCalculateVowel`, `removeMark`, `checkSpelling`, `checkGrammar`, `checkRestoreIfWrongSpelling`, `checkForStandaloneChar`, `vKeyHandleEvent`), `SmartSwitchKey` binary serialization/lookup, and the `OKEngine*` / `OK*SmartSwitchKey*` Swift entry points.
  - Delete `Sources/OpenKey/macOS-Swift/Sources/OpenKeyEngineBridge/` and remove `OpenKeyEngineBridge` and `cxxLanguageStandard` from `Package.swift`.
  - Add explicit conversion attribution in `SettingsView.swift` (About / Provenance section), `OpenKeySwiftApp.swift` (status bar menu item `"Giới thiệu: Chuyển đổi Pure Swift 6 từ OpenKey"`), `Info.plist` (`NSHumanReadableCopyright`), `VietnameseData.swift` / `VietnameseEngine.swift` file headers, and `README.md`.
- **Consequences**:
  - `OpenKeySwift` becomes a 100% Pure Swift 6 codebase with zero C++ or Objective-C++ files, zero C pointer bridging overhead, and clear user-facing and code-level attribution to the original `OpenKey` project.
