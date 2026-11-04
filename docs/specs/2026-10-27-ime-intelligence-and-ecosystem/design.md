# Architecture & Design Blueprint: IME Intelligence, Secure Input, Ecosystem Compatibility & Adaptive Learning (`2026-10-27-ime-intelligence-and-ecosystem`)

---

## 1. Requirement-to-Component Traceability Matrix

| Requirement ID | ADR | Target Files | Component / Method |
| :--- | :--- | :--- | :--- |
| **`REQ-001`** | `ADR-001` | `EventTapCoordinator.swift` | `KeyEventContext.isSecureInput`, `EventTapCoordinator.isSecureEventInputActive()`, `evaluateKeyEvent(_:)` |
| **`REQ-002`** | `ADR-002` | `EventTapCoordinator.swift` | `EventTapCoordinator.isLauncherApp(bundleId:)`, `EventTapCoordinator.isSpotlightOverlayVisible(frontmostBundleId:)` |
| **`REQ-003`** | `ADR-003` | `CandidateBarController.swift` | `CaretPositionResolver.enableManualAccessibilityIfNeeded(for:pid:)`, `CaretPositionResolver.screenContaining(point:)` |
| **`REQ-004`** | `ADR-004` | `VietnameseEngine.swift`, `EventTapCoordinator.swift` | `checkRestoreIfWrongSpelling(handleCode:)`, `EventTapAction.replaceKeystroke(backspaces:chars:strategy:passThroughTrailingKey:)` |
| **`REQ-005`** | `ADR-005` | `AutoWordingEngine.swift`, `EventTapCoordinator.swift`, `CandidateBarController.swift`, `SettingsView.swift` | `AutoWordingEngine.recordCandidateAcceptance(text:)`, `resetLearnedFrequencies()`, candidate sorting |
| **`REQ-006`** | `ADR-005` | `AutoWordingEngine.swift`, `OpenKeySettingsStore.swift`, `SettingsView.swift` | Expanded `shorthandTable`, `customShorthands: [String: String]`, `setCustomShorthand(trigger:replacement:)`, `removeCustomShorthand(trigger:)` |
| **`REQ-007`** | `ADR-006` | `VietnameseEngine.swift`, `AutoWordingEngine.swift`, `EventTapCoordinator.swift` | `CHR(_:)`, `handleModernMark()`, `handleOldMark()`, `insertMark(markMask:canModifyFlag:)`, `checkGrammar(deltaBackSpace:)`, `startNewSessionInternal()`, `restoreLastTypingState()`, `resetSession()`, `handleKeyEvent(...)`, `updateCandidates(_:)`, `evaluateKeyEvent(_:)` |
| **`REQ-008`** | `ADR-007` | `VietnameseEngine.swift`, `AutoWordingEngine.swift`, `CaretPositionResolver.swift`, `CandidateBarController.swift`, `OpenKeySettingsStore.swift` | `OKWordContext`, `OKEngineGetWordContext`, `OKEngineCommitExternalExpansion`, `phonotacticRepairHook`, `CandidateKind.stemCompletion`, `CaretPositionResolver.resolveCaretScreenPoint()` |
| **`REQ-009`** | `ADR-008` | `Sources/OpenKey/macOS-Swift/Sources/**`, `Sources/OpenKey/macOS-Swift/Tests/**` | Cohesion-driven modular architecture (`VietnameseData.swift`, `VietnameseEngine.swift`, `VietnameseEngine+Phonotactics.swift`, `SmartSwitchStore.swift`, `AutoWordingEngine.swift`, `VietnameseDictionary.swift`, `EventTapCoordinator.swift`) |
| **`REQ-010`** | `ADR-009` | `VietnameseEngine+Phonotactics.swift`, `VietnameseEngine.swift`, `AutoWordingEngine.swift`, `VietnameseDictionary.swift` | `findAndCalculateVowel(forGrammar:)`, `canHasEndConsonant()`, `checkCorrectVowel(charset:i:markKey:)`, `handleCharacterKey(keyCode:isCaps:)`, `computeCurrentWordCandidates(currentSyllable:rawKeystrokes:isWrongSpelling:)` |
| **`REQ-011`** | `ADR-010` | `.github/workflows/macos-ci.yml`, `Sources/OpenKey/macOS-Swift/Package.swift`, `README.md` | GitHub Actions `macos-26` CI/CD workflow (`test`, `build-app.sh`, `.zip`/`.dmg` packaging, artifact upload, release publishing) & portable `Testing` macro plugin resolution |
| **`REQ-012`** | `ADR-011` | `OpenKeySettingsStore.swift`, `OpenKeyL10n.swift`, `SettingsView.swift`, `OpenKeySwiftApp.swift` | `uiLanguage` persistence (`VI | EN`), `OpenKeyL10n` concise single-language strings, `Esc`-to-close handler (`handleEscapeKey()`), and About section version + `Antigravity (Gemini 4 Argon High)` implementor attribution |
| **`REQ-013`** | `ADR-012` | `OpenKeyLogger.swift`, `OpenKeySettingsStore.swift`, `EventTapCoordinator.swift`, `VietnameseEngine.swift`, `AutoWordingEngine.swift`, `KeystrokeInjector.swift`, `CandidateBarController.swift`, `SmartSwitchStore.swift`, `SettingsView.swift`, `OpenKeySwiftApp.swift`, `OpenKeyL10n.swift`, `build-app.sh` | `OpenKeyLogger.shared`, `OpenKeyLogCategory`, `checkVersionRetention(currentStamp:)`, `debugModeEnabled`, `openLogFile()`, `revealLogInFinder()`, `clearLog()` |

---

## 2. Detailed Component Design

### 2.1 `EventTapCoordinator.swift` (`REQ-001`, `REQ-002`, `REQ-004`, `REQ-005`)
- **Secure Input Check (`REQ-001`, `ADR-001`)**:
  - Import `Carbon`.
  - Add `public var isSecureInput: Bool` (default `false`) to `KeyEventContext`.
  - Add `public static func isSecureEventInputActive() -> Bool` calling `IsSecureEventInputEnabled()`.
  - In `evaluateKeyEvent(_:)`: before candidate selection or Vietnamese key processing (right after HotKey checks), if `context.isSecureInput` is `true`, call `AutoWordingEngine.shared.clearCandidates()` and return `.passThrough(resetSession: true)`.
- **Launcher Overlay Detection (`REQ-002`, `ADR-002`)**:
  - Add `public static func isLauncherApp(bundleId: String?) -> Bool` matching:
    - `"com.apple.Spotlight"`
    - `"com.raycast.macos"`
    - `"com.runningwithcrayons.Alfred"`
    - `"com.runningwithcrayons.Alfred-Preferences"`
  - Update `isSpotlightOverlayVisible(frontmostBundleId:)` to return `true` if `isLauncherApp(bundleId: frontmostBundleId)` is `true` OR if an on-screen window with `kCGWindowLayer > 0` (`width >= 200`, `height >= 40`) is owned by `"Spotlight"`, `"Raycast"`, or `"Alfred"`.
  - In `evaluateKeyEvent(_:)`, check `if context.isSpotlightVisible || EventTapCoordinator.isLauncherApp(bundleId: context.activeAppBundleId)` -> return `.passThrough(resetSession: true)`.
- **Control-Key Word Break Preservation (`REQ-004`, `ADR-004`)**:
  - Update `EventTapAction.replaceKeystroke` to:
    `case replaceKeystroke(backspaces: Int, chars: [UInt16], strategy: ReplacementStrategy, passThroughTrailingKey: Bool = false)` (or explicit 4-argument case).
  - When `snapshot.shouldSendControlKey == true`, pass `passThroughTrailingKey: true` so `handleEvent` executes `injector.executeReplacement(...)` and returns `Unmanaged.passUnretained(event)` instead of `nil`.
- **Candidate Acceptance Recording (`REQ-005`, `ADR-005`)**:
  - When `.acceptCandidate(let candidate)` is handled in `EventTapCoordinator.handleEvent` and `CandidateBarController.acceptCandidate`, call `AutoWordingEngine.shared.recordCandidateAcceptance(text: candidate.text)`.

### 2.2 `CandidateBarController.swift` (`REQ-003`, `ADR-003`)
- **`AXManualAccessibility` Activation**:
  - Maintain a thread-safe `private static var enabledAccessibilityPIDs = Set<pid_t>()` guarded by `NSLock`.
  - Add `public static func enableManualAccessibilityIfNeeded(for appElement: AXUIElement, pid: pid_t)`: if `!enabledAccessibilityPIDs.contains(pid)`, insert `pid` and call `AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)`.
- **Multi-Monitor Screen Resolution**:
  - Add `public static func screenContaining(point: NSPoint) -> NSScreen?` returning `NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens.first`.
  - Use `CaretPositionResolver.screenContaining(point: caretPoint)?.visibleFrame` when clamping `targetX` and `targetY` in `CandidateBarController.handleCandidatesUpdated(_:)`.

### 2.3 `VietnameseEngine.swift` (`REQ-004`, `REQ-007`, `ADR-004`, `ADR-006`)
- **`checkRestoreIfWrongSpelling(handleCode:)` (`REQ-004`)**:
  - Inspect all indices `0..<Int(index)` in `typingWord` without skipping consonants so `CHR(ii) == KEY_D` with `TONE_MASK` (`đ`) is detected alongside vowel marks/tones (`MARK_MASK | TONE_MASK | TONEW_MASK`).
  - Also check if any character was transformed from `KEY_W` to `KEY_U | TONEW_MASK` (`stateIndex == index` or `keyStates[ii] != typingWord[ii]`). Specifically, if any position `ii` has `(typingWord[ii] & (MARK_MASK | TONE_MASK | TONEW_MASK)) != 0`, restore all `stateIndex` raw keystrokes from `keyStates`.
- **Multi-Delete, Diphthong Tone Replacement & Subsequent Character Entry State Integrity (`REQ-007`, `ADR-006`)**:
  - `CHR(_ idx: Int)`: Check `guard idx >= 0 && idx < Int(index) && idx < maxBuff else { return KEY_EMPTY }` so out-of-bounds reads never return `0` (`KEY_A`) or read deleted characters at `idx >= Int(index)`.
  - `handleModernMark()` & `handleOldMark()`: Remove all `hookOutput.backspaceCount` and `hookOutput.newCharCount` assignments so they only compute `vowelWillSetMark` without mutating `hookOutput` during `checkGrammar(deltaBackSpace: 0)` -> `insertMark(canModifyFlag: false)`; fix Rule 3.1 in `handleModernMark()` to check `CHR(vsi + 1) == KEY_E && (w1 & TONE_MASK) != 0`.
  - `insertMark(markMask:canModifyFlag:)`: Guard `hookOutput` mutations (`code`, `backspaceCount = UInt8(Int(index) - vsi)`, `newCharCount = hookOutput.backspaceCount`, `charData`) and `tempDisableKey` behind `if canModifyFlag`.
  - `handleKeyEvent`: Reset `hookOutput` fields at entry; when `hookOutput.code == HookCodeState.doNothing`, return `backspaceCount: 0, newCharCount: 0, utf16Chars: []`.
  - `KEY_DELETE` & `restoreLastTypingState()`: Clear `typingWord[Int(index)] = UInt32(KEY_EMPTY)`, synchronize `stateIndex = index` and `keyStates[0..<Int(index)]` to the base keys of `typingWord`, and run `checkSpelling()` in `restoreLastTypingState()`.
  - `resetSession()`, `startNewSessionInternal()`, & `KEY_SPACE`: Clear `typingStates`, `typingStatesData`, `specialChar`, `spaceCount`, and `willTempOffEngine` inside `resetSession()` and on shorthand expansion; do not zero `hookOutput.backspaceCount` or `hookOutput.newCharCount` inside `startNewSessionInternal()` so calling it after `saveWord()` on `KEY_SPACE` preserves word-break restoration output.
  - `checkGrammar(deltaBackSpace:)` & `AutoWordingEngine.updateCandidates(_:)`: Only run `repairPhonotacticClusterIfNeeded` when `deltaBackSpace <= 0`, preserve `isCheckedGrammar = repaired`, only apply Rule 1 (`ie`/`ye` + consonant → `iê`/`yê`) when `isInsertingMark` is true or `MARK_MASK` is already present, and dispatch `onCandidatesChanged` asynchronously via `DispatchQueue.main.async`.

### 2.4 `AutoWordingEngine.swift`, `OpenKeySettingsStore.swift`, `SettingsView.swift` (`REQ-005`, `REQ-006`, `ADR-005`)
- **Expanded Built-in Shorthands (`REQ-006`)**:
  - Add `"k": "không"`, `"j": "gì"`, `"bh": "bây giờ"`, `"mn": "mọi người"`, `"cty": "công ty"`, `"nv": "nhân viên"`, `"gd": "gia đình"`, `"sdt": "số điện thoại"`, `"tks": "cảm ơn"` to `shorthandTable`.
- **Custom Shorthands (`REQ-006`)**:
  - Add `public var customShorthands: [String: String]` in `OpenKeySettingsStore` (persisted in `UserDefaults` under `Keys.customShorthands = "CustomShorthandsData"`) with helper methods `setCustomShorthand(trigger: String, replacement: String)` and `removeCustomShorthand(trigger: String)`.
  - Sync `customShorthands` to `AutoWordingEngine.shared.customShorthands`. `expandShorthand(rawWord:)` checks `customShorthands[lower]` first before `shorthandTable[lower]`.
- **User Frequency Learning (`REQ-005`)**:
  - Add `public private(set) var userFrequencies: [String: Int]` in `AutoWordingEngine` (persisted in `UserDefaults` under `"UserWordFrequencyData"`).
  - Add `public func recordCandidateAcceptance(text: String)` and `public func resetLearnedFrequencies()`.
  - In `computeCurrentWordCandidates` and `computeNextWordCandidates`, gather up to 8 candidate matches before sorting by `(userFrequencies[word.lowercased()] ?? 0)` descending (preserving dictionary order on ties) and taking `.prefix(3)`.
- **`SettingsView.swift` UI Controls (`REQ-005`, `REQ-006`)**:
  - Inside the `"Auto Wording & Ngữ pháp (Thử nghiệm)"` section, add:
    - Custom shorthand list & inline add/remove controls (`Trigger` + `Expansion` text fields and `+` button).
    - `"Xóa dữ liệu học từ (Reset learned words)"` button calling `AutoWordingEngine.shared.resetLearnedFrequencies()`.

---

## 5. Auto Wording Isolation & Live Candidate Lifecycle (`REQ-008`, `ADR-007`)
- **One-Way Decoupling & Atomic Engine Turn (`VietnameseEngine.swift`)**:
  - Define `public struct OKWordContext: Sendable, Equatable` (`composedWord: String`, `rawKeystrokes: String`, `charCount: Int`, `spaceCount: Int`, `isWrongSpelling: Bool`, `isBreakKey: Bool`).
  - Expose `OKEngineGetWordContext(_ keyCode: UInt16? = nil)` and `OKEngineCommitExternalExpansion()`.
  - Remove `vAutoWordingEnabled`, `vGrammarRepairEnabled`, `vShorthandExpansionEnabled`, and `vCandidateSuggestionsEnabled` from `VietnameseEngineState`, and replace the direct `AutoWordingEngine.shared.repairPhonotacticCluster` call with an injected `phonotacticRepairHook` closure so `VietnameseEngineState` has zero references to `AutoWordingEngine`.
  - In `OKEngineHandleKeyEvent`: if `!AutoWordingEngine.shared.isEnabled`, invoke `VietnameseEngineState.shared.handleKeyEvent(...)` directly (zero `getWordContext` calls). When enabled, execute `preContext`, `interceptBeforeKeyEvent` + `commitExternalExpansion()`, `handleKeyEvent`, and `postContext` atomically under `VietnameseEngineState.lock`.
- **Thread-Safe Lock-Isolated `AutoWordingEngine` & `CandidateKind` Disambiguation (`AutoWordingEngine.swift`, `EventTapCoordinator.swift`)**:
  - Synchronize all reads and writes of `isEnabled`, `grammarRepairEnabled`, `shorthandExpansionEnabled`, `candidateSuggestionsEnabled`, `activeCandidates`, and `userFrequencies` with `AutoWordingEngine.lock`.
  - Make `updateCandidates(_:)` a no-op under lock when `_activeCandidates == candidates`.
  - Extend `CandidateKind` to `.correction`, `.stemCompletion`, and `.nextWord`. `computeCurrentWordCandidates` assigns `.correction` when `isWrongSpelling == true` (or when matched only via transposition signature) and `.stemCompletion` when `isWrongSpelling == false`.
  - In `EventTapCoordinator.evaluateKeyEvent`, `Tab` (`keyCode == 48`) accepts candidate `#0` only when `activeCandidates[0].kind == .correction` (passing through `Tab` and clearing candidates for `.stemCompletion` and `.nextWord`), while `Ctrl+1..3` accepts candidates `#0..#2` for all kinds.
- **Zero-Width Caret Resolution, `40ms` AX Timeout & Non-Deactivating Panel (`CaretPositionResolver.swift`, `CandidateBarController.swift`)**:
  - In `CaretPositionResolver.resolveCaretScreenPoint()`, set `AXUIElementSetMessagingTimeout(..., 0.04)` (`40ms`), accept `rect.width >= 0 && rect.height > 0 && (rect.origin.x != 0 || rect.origin.y != 0)` for zero-width native insertion carets, and restrict Fallback #2 (`kAXPositionAttribute` + `kAXSizeAttribute`) to single-line inputs (`sz.height <= 48`).
  - In `CandidateBarController.swift`, resolve caret coordinates on a background queue (`com.openkey.caret-resolver`) before updating the `NSPanel` (`level = .popUpMenu`, `hidesOnDeactivate = false`, `orderFrontRegardless()`) on `@MainActor`, and ignore `leftMouseDown` session resets in `EventTapCoordinator` when clicking inside the candidate bar panel.

---

## 6. Codebase Modularization & Complexity Reduction Architecture (`REQ-009`, `ADR-008`)

### 6.1 Module Decomposition Map (Cohesion-Driven Single Responsibility)
- **`OpenKeySwiftCore` Target (11 Cohesive Files)**:
  1. `VietnameseData.swift` (~540 lines): Virtual keycode constants, bitmask constants, `@inline(__always)` `UInt32` syllable bitmask helpers (`baseKey`, `isCaps`, `hasToneMark`, `toneMark`, `hasCircumflexOrStroke`, `hasHornOrBreve`, `hasAnyDiacritic`, `isAutoTone`, `isStandaloneW`), `NSLock.withLock`, `OKHookSnapshot`, `HookCodeState`, phonotactic tables, precomposed Unicode `_codeTable`, `_characterMap`, and `keyCodeToCharacter(_:)`.
  2. `VietnameseEngine.swift` (~650 lines): `OKWordContext`, `VietnameseEngineState` core state buffers, configuration, session lifecycle (`initEngine`, `resetSession`, `commitExternalExpansion`, `getWordContext`, `getComposedWord`), buffer helpers (`insertKey`, `insertState`, `saveWord`, `restoreLastTypingState`), `handleKeyEvent(keyCode:capsStatus:otherControlKey:)` phase dispatcher (`handleWordBreakOrControlKey`, `handleSpaceKey`, `handleDeleteKey`, `handleCharacterKey`, `buildOutputSnapshot`), and public `OKEngine*` functions.
  3. `VietnameseEngine+Phonotactics.swift` (~735 lines): Phonotactic spelling validation, vowel boundaries, grammar repair, and tone/mark transforms (`checkSpelling`, `checkCorrectVowel`, `canHasEndConsonant`, `findAndCalculateVowel`, `repairPhonotacticClusterIfNeeded`, `checkGrammar`, `checkRestoreIfWrongSpelling`, `getCharacterCode`, `removeMark`, `handleModernMark`, `handleOldMark`, `insertMark`, `insertD`, `insertAOE`, `insertW`, `reverseLastStandaloneChar`, `checkForStandaloneChar`, `handleMainKey`).
  4. `SmartSwitchStore.swift` (~117 lines): Per-app language memory (`SmartSwitchStore.shared`) with `Data`-based persistence (`loadData(_:)`, `exportData()`) plus `OKInitSmartSwitchKey`, `OKGetSmartSwitchKeySaveData`, `OKGetAppInputMethodStatus`, and `OKSetAppInputMethodStatus`.
  5. `AutoWordingEngine.swift` (~500 lines): `CandidateKind`, `WordCandidate`, `AutoWordingShorthandCatalog`, and lock-isolated `AutoWordingEngine` (configuration, candidate ranking, frequency learning, shorthand expansion, phonotactic cluster repair, and pre/post key event hooks).
  6. `VietnameseDictionary.swift` (~555 lines): `VietnameseDictionary` index construction, `stripVietnameseDiacritics(_:)`, and embedded `VietnameseDictionaryCorpus` static syllable array, compound bigram table, and priority weights.
  7. `EventTapCoordinator.swift` (~615 lines): `EventTapEventType`, `KeyEventContext`, `EventTapAction`, `SystemEnvironmentDetector` (secure input, launcher overlay, terminal app detection), `CGEventTap` setup/teardown, app-switch/wake observers, `evaluateKeyEvent(_:)`, and `handleEvent(proxy:type:event:)`.
  8. `CaretPositionResolver.swift`, `HotKeyMatcher.swift`, `InputSourceGuard.swift`, `KeystrokeInjector.swift`, `OpenKeyLogger.swift`, `OpenKeySettingsStore.swift`.
- **`OpenKeySwiftTests` Target**:
  - Domain-focused suites (`OpenKeyEngineTests.swift`, `OpenKeyEventTapTests.swift`, `OpenKeyAutoWordingTests.swift`, `OpenKeyLoadTests.swift`, `OpenKeyTestHelpers.swift`).

---

## 7. `"giới"` & `gi-` Initial Consonant Vowel Boundary, Phonotactic Validation & Candidate Ranking (`REQ-010`, `ADR-009`)
- **`VietnameseEngine+SpellingAndGrammar.swift`**:
  - `findAndCalculateVowel(forGrammar: Bool = false)`: Scan backward from `Int(index) - 1` down to `0`. When encountering a vowel, set `vowelEndIndex` on the first vowel seen, break before `i` in `gi` (`iii - 1 >= 0 && CHR(iii) == KEY_I && CHR(iii - 1) == KEY_G`) or `u` in `qu` (`CHR(iii) == KEY_U && CHR(iii - 1) == KEY_Q`) when `!forGrammar`, and otherwise update `vowelStartIndex = UInt8(iii)` and `vowelCount += 1`. After the loop, if `vowelStartIndex >= 1 && CHR(Int(vowelStartIndex)) == KEY_U && CHR(Int(vowelStartIndex) - 1) == KEY_Q`, increment `vowelStartIndex += 1` and decrement `vowelCount -= 1`.
  - `canHasEndConsonant() -> Bool`: Look up `_vowelCombine[CHR(Int(vowelStartIndex))]` and verify a combination matching `CHR(Int(vowelStartIndex)...Int(vowelEndIndex))` has `vo[0] == 1`.
  - `checkCorrectVowel(charset:i:markKey:)`: Reject entries containing `END_CONSONANT_MASK` (since quick end consonants are not enabled), reject `isKeyF(markKey) || isKeyR(markKey) || isKeyX(markKey)` when the ending consonant is `-c`, `-t`, or `-ch`, and reject partial suffix matches when `k >= 0 && CHR(k) == CHR(k + 1)`.
- **`VietnameseEngine+KeyEventDispatcher.swift`**:
  - In `handleCharacterKey`: compute `let grammarDelta = (hookOutput.extCode == 4 && hookOutput.backspaceCount == 0 && hookOutput.newCharCount == 1) ? -1 : 0` and call `checkGrammar(deltaBackSpace: grammarDelta)`.
- **`AutoWordingEngine.swift` & `VietnameseDictionaryCorpus.swift`**:
  - Add priority weights in `VietnameseDictionaryCorpus.priorityMap` for `"giới": 100`, `"giỏi": 95`, `"giời": 90`, `"giờ": 100`, `"giữ": 100`, `"giữa": 98`, `"giúp": 100`, `"giải": 98`, `"giảm": 96`, `"giá": 100`, `"gia": 95`, `"giao": 95`, `"giàu": 92`, `"giấy": 95`.
  - In `AutoWordingEngine.computeCurrentWordCandidates`: collect all unseen candidates from `dict.stemToWords[stem]` before sorting, and compute a tone-stripped base string (preserving vowel modifiers `ă, â, ê, ô, ơ, ư, đ` while stripping only tone marks) so candidates matching the user's explicit vowel modifiers rank ahead of candidates that strip `ơ` back to `o`.

---

## 8. GitHub Actions macOS 26 CI/CD Pipeline & Portable Swift Testing Plugin Resolution (`REQ-011`, `ADR-010`)
- **`Sources/OpenKey/macOS-Swift/Package.swift`**:
  - Import `Foundation`.
  - Detect whether the local `CommandLineTools` testing plugin path (`/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`) should be passed via `.unsafeFlags(["-Xfrontend", "-plugin-path", ...])` only when `ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == nil` and `/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing` exists on disk.
- **`.github/workflows/macos-ci.yml` (replacing `.github/workflows/msbuild.yml`)**:
  - Triggers: `push` (`branches: ["master", "main"]`, `tags: ["v*"]`), `pull_request` (`branches: ["master", "main"]`), and `workflow_dispatch`.
  - Runner: `macos-26` (Apple Silicon `arm64`, macOS 26 Tahoe + Xcode 26).
  - Steps:
    1. Checkout repository (`actions/checkout@v4`).
    2. Verify Swift & Xcode toolchain (`swift --version`, `xcodebuild -version`).
    3. Run automated unit and load test suite (`swift test --package-path Sources/OpenKey/macOS-Swift`).
    4. Build and code-sign `OpenKeySwift.app` (`bash Sources/OpenKey/macOS-Swift/build-app.sh`) and verify signature (`codesign --verify --deep --strict Sources/OpenKey/macOS-Swift/build/OpenKeySwift.app`).
    5. Package distributable `OpenKeySwift-macOS-arm64.zip` (`ditto -c -k --sequesterRsrc --keepParent`) and `OpenKeySwift.dmg` (`hdiutil create`).
    6. Upload `OpenKeySwift-macOS-arm64.zip` and `OpenKeySwift.dmg` via `actions/upload-artifact@v4`.
    7. Publish release assets via `softprops/action-gh-release@v2` when `startsWith(github.ref, 'refs/tags/v')`.
- **`README.md`**:
  - Add the GitHub Actions `macOS CI/CD` workflow status badge under the header and document CI/CD automated builds and artifact downloads in Section 4.

---

## 9. Settings `Esc`-to-Close, Single-Language UI Switcher (`VI | EN`) & Implementor/Version Attribution (`REQ-012`, `ADR-011`)
- **`OpenKeySettingsStore.swift`**:
  - Add `public static let uiLanguage = "UILanguage"` to `Keys`.
  - Add `public var uiLanguage: Int` (`1` = Vietnamese default, `0` = English; clamped to `0` or `1` and persisted to `UserDefaults`).
- **`OpenKeyL10n.swift` (`Sources/OpenKey/macOS-Swift/Sources/OpenKeySwiftApp/OpenKeyL10n.swift`)**:
  - Provide a value-type `public struct OpenKeyL10n: Sendable` initialized with `isVietnamese: Bool` (`settings.uiLanguage == 1`), exposing concise single-language strings for all Settings sections, toggles, buttons, accessibility banner messages, status bar menu items, and the About section (`versionString`, `implementorLine`, `authorLine`).
- **`SettingsView.swift`**:
  - Top bar: HStack containing the Accessibility status banner and a compact segmented `VI | EN` picker bound to `$settings.uiLanguage`.
  - Replace all dual-language strings with `l10n.<property>`.
  - About section: Display `OpenKeySwift` version badge (`v2.0.0 (Build 1)`), implementor row (`Antigravity (Gemini 4 Argon High)`), and original author row (`Mai Vũ Tuyên • GNU GPLv3`).
  - `Esc` key handling: Install a window key monitor on `onAppear` (removed on `onDisappear`) that intercepts `keyCode == 53` (`Esc`): if `ui.isRecordingShortcut` is `true`, calls `stopRecordingShortcut()`; otherwise calls `NSApp.keyWindow?.close()`.
- **`OpenKeySwiftApp.swift`**:
  - Use `OpenKeyL10n(isVietnamese: settings.uiLanguage == 1)` when building status bar menu items and setting the Settings window title.
- **`SettingsView.openAccessibilitySettings()` & `build-app.sh` TCC Resilience**:
  - When `!settings.isAccessibilityTrusted`, `openAccessibilitySettings()` runs `/usr/bin/tccutil reset Accessibility com.tuyenmai.openkey.swift` via `Process` and calls `EventTapCoordinator.shared.checkAccessibilityAndSetupTap()` before opening `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`.
  - `build-app.sh` uses `/usr/bin/openssl` (LibreSSL PKCS#12 compatibility with macOS `security import`) in `--setup-cert` and only passes `-r='designated => identifier "com.tuyenmai.openkey.swift"'` when `SIGNING_IDENTITY == "-"`.

---

## 10. Debug Mode & Version-Scoped Persistent File Logging (`REQ-013`, `ADR-012`)
- **`OpenKeyLogger.swift` (`Sources/OpenKey/macOS-Swift/Sources/OpenKeySwiftCore/OpenKeyLogger.swift`, `< 250` lines)**:
  - `public enum OpenKeyLogCategory: String, Sendable`: `lifecycle = "LIFECYCLE"`, `settings = "SETTINGS"`, `eventTap = "EVENT_TAP"`, `engine = "ENGINE"`, `autoWording = "AUTO_WORDING"`, `injector = "INJECTOR"`, `candidateBar = "CANDIDATE_BAR"`, `smartSwitch = "SMART_SWITCH"`.
  - `public final class OpenKeyLogger: @unchecked Sendable`:
    - `public static let shared = OpenKeyLogger()`
    - Default log directory: `~/Library/Logs/OpenKeySwift/`, active log file: `~/Library/Logs/OpenKeySwift/openkey-debug.log`, default `maxFileSizeBytes = 20 * 1024 * 1024` (20 MB).
    - `public var isEnabled: Bool`: lock-protected boolean synced with `OpenKeySettingsStore.shared.debugModeEnabled` (default `false`). When transitioned to `true`, ensures the log directory and version-stamped `openkey-debug.log` are initialized and logs a `[LIFECYCLE]` activation banner.
    - `public func checkVersionRetention(currentStamp: String? = nil)`: resolves `currentStamp` from `Bundle.main.infoDictionary` (`CFBundleShortVersionString` + `CFBundleVersion` + executable modification date epoch). Removes any legacy/rotated `.log` files in `logDirectoryURL` other than `openkey-debug.log`. Reads the first line of `openkey-debug.log` (`# OpenKeySwiftVersionStamp: <stamp>`). If the file does not exist or its stamp != `currentStamp`, recreates `openkey-debug.log` with `# OpenKeySwiftVersionStamp: <currentStamp>\n# Initialized: <ISO8601>\n`.
    - `@inline(__always) public func log(_ category: OpenKeyLogCategory, _ message: @autoclosure () -> String)`: returns immediately if `!isEnabled`; otherwise evaluates `message()`, formats `[<ISO8601-ms>] [<category.rawValue>] <msg>\n`, and dispatches asynchronously to `queue` (`DispatchQueue(label: "com.tuyenmai.openkey.logger", qos: .utility)`). If file size + entry size > `maxFileSizeBytes`, truncates and writes the version header + `[LOG_ROTATED_SIZE_CAP]` notice before appending.
    - `public func clearLog()`, `public func flushForTesting()`, and `public func configureForTesting(logDirectoryURL: URL, appVersionStamp: String, maxFileSizeBytes: Int = 20 * 1024 * 1024)`.
- **Subsystem Instrumentation & Secure Input Redaction**:
  - `EventTapCoordinator.swift`: In `evaluateKeyEvent(_:)`, if `context.isSecureInput == true`, log `.eventTap` `"Secure input active — keystroke redacted, bypassing IME"` and return `.passThrough(resetSession: true)` without logging `keyCode` or flags. For non-secure events, log incoming key context and resulting `EventTapAction`.
  - `VietnameseEngine.swift`: In `OKEngineHandleKeyEvent` and `OKEngineResetSession`, log input `keyCode`/`capsStatus` and output `OKHookSnapshot` (`code`, `backspaceCount`, `newCharCount`, composed word).
  - `AutoWordingEngine.swift`: Log phonotactic cluster repairs, shorthand expansions, candidate list computations, and frequency learning updates.
  - `KeystrokeInjector.swift`, `CandidateBarController.swift`, `SmartSwitchStore.swift`, `OpenKeySettingsStore.swift`: Log replacement injection parameters, candidate panel coordinate updates, per-app language switches, and setting changes.
- **UI, Menu Bar & Build Script Integration**:
  - `OpenKeySettingsStore.swift`: Add `Keys.debugModeEnabled = "DebugModeEnabled"` (default `false`) and `public var debugModeEnabled: Bool` syncing to `OpenKeyLogger.shared.isEnabled`.
  - `SettingsView.swift` & `OpenKeyL10n.swift`: Under `Hệ thống / System`, add a Debug Mode toggle, log file path + per-version retention subtitle, and `Open Log File`, `Reveal in Finder`, and `Clear Log` buttons.
  - `OpenKeySwiftApp.swift`: Add a `Debug Mode` toggle item (and `Open Debug Log...` when enabled) in the status bar menu, and call `OpenKeyLogger.shared.checkVersionRetention()` on launch.
  - `build-app.sh`: Stamp `CFBundleVersion` in `${APP_BUNDLE}/Contents/Info.plist` with `1.$(date -u +%Y%m%d%H%M%S)` via `/usr/libexec/PlistBuddy` so every new `.app` build automatically rotates/purges the previous build's debug log.

---

## 11. Mixed-Language Inline English Auto-Fix, Swallowed-Key Recovery, 1–2 Word Look-Back, 3-Word Auto-Switch & Single-Backspace Undo (`REQ-014`..`REQ-020`, `ADR-013`..`ADR-018`)
- **11.1 Canonical Telex Key & Bilingual Dictionary (`REQ-014`, `ADR-013`, `VietnameseDictionary.swift`)**:
  - Store `englishWords`, `englishPriorityWords`, `englishLookbackStems`, `keepWords`, and `rawSyllables` using space-delimited `String.split(separator: " ")` literals to eliminate $O(N^2)$ `swift-frontend` array-literal type-checking latency during compilation.
  - `public static func canonicalTelexKey(for word: String) -> String`: normalizes `â/ê/ô/đ` → `aa/ee/oo/dd`, `ă/ơ/ư` → `aw/ow/uw`, and appends the tone mark (`s/f/r/x/j`) at the end.
  - `public let englishWords: Set<String>`: common English + developer/CLI/chat vocabulary (`en_extra` + `en_code`).
  - `public let englishPriorityWords: Set<String>`: high-frequency English/tech words that collide with valid Vietnamese phonotactics (`test`, `list`, `this`, `best`, `host`, `post`, `cost`, `most`, `last`, `fast`, `rest`, `next`, `text`, `view`, `new`, `show`, `flow`, `slow`, `raw`, `more`, `core`, `store`, `score`, `share`, `care`, `pure`, `sure`, `user`, `vars`, `chars`, `cors`, `nums`, `hist`, `defs`, `docs`, `logs`, `bugs`, `tags`, `jobs`, `apps`, `tabs`, `keys`, `days`, `ways`, `sort`, `port`, `short`, `sport`, `start`, `part`, `chart`, `smart`, `card`, `hard`, `board`, `word`, `work`, `fork`, `form`, `norm`, `term`, `turn`, `burn`, `learn`, `warn`, `tree`, `free`, `see`, `too`, `zoo`, `add`, `odd`, `boss`, `pass`, `less`, `mess`, `off`, `mix`, `fix`, `six`, `box`, `max`, `tax`, etc.).
  - `public let englishLookbackStems: Set<String>`: (`is`, `of`, `if`, `for`, `or`, `us`, `in`, `on`, `at`, `up`, `as`, `to`, `by`, `car`, `ban`, `can`, `man`, `has`, `was`, `his`, `her`, `our`, `out`, `all`, `any`, `may`, `way`, `day`, `say`, `pay`, `set`, `get`, `let`, `met`, `net`, `put`, `cut`, `but`, `run`, `sun`, `fun`).
  - `public func isValidVietnameseSyllable(_ word: String) -> Bool`: checks `syllableSet` and `teencodeWhitelist` (`zui`, `dzô`, `gòy`, `thík`, `ừk`, `đc`, `đt`, `đk`).
- **11.2 Swallowed Telex Modifier Key Tracking (`REQ-015`, `ADR-014`, `VietnameseEngine.swift`)**:
  - Maintain `var droppedKeys: [(pos: Int, key: UInt32)] = []` on `VietnameseEngineState` (cleared on `clearBuffersInternal()`, pruned on `KEY_DELETE`).
  - In `handleCharacterKey(keyCode:)`, when `hookOutput.code == HookCodeState.restore` undoes a modifier and decrements `stateIndex`, append `(pos: Int(stateIndex), key: keyStates[Int(stateIndex)])` to `droppedKeys`.
  - `func reconstructedRawKeys() -> [UInt32]` reinserts `droppedKeys` in reverse-drop order so `"cheese"`, `"seemed"`, `"needed"`, `"deepseek"`, `"google"`, `"process"`, `"office"`, `"coffee"`, `"error"`, `"tomorrow"`, `"address"` retain all characters.
- **11.3 Doubled-Tone Escape Repair, Acronyms & Contractions (`REQ-016`, `ADR-015`, `VietnameseEngine+Phonotactics.swift`)**:
  - When a tone key (`s, f, r, x, j`) was doubled (`"mixx"`, `"fixx"`, `"boxx"`, `"maxx"`, `"taxx"`) and the doubled string is not in `englishWords` while the single-key string (`"mix"`, `"fix"`, `"box"`, `"max"`, `"tax"`) is in `englishWords`, restore the single-key array.
  - Handle contraction stems before `KEY_QUOTE` (`"doesn't"`, `"isn't"`, `"wasn't"`), `w-` words before `KEY_MINUS` (`"Wi-Fi"`), and $\ge 2$-capital acronyms with vowel modifications (`"NAS"`, `"SATA"`, `"GoPro"` vs. Vietnamese `"VĐV"`, `"BĐS"`).
- **11.4 Standalone English Collision Priority & Diphthong Validation (`REQ-017`, `ADR-016`, `VietnameseEngine+Phonotactics.swift`)**:
  - In `shouldRestoreToEnglishAtBreak`, restore when `englishPriorityWords.contains(rawLower)` (unless `rawLower == undoneRawWord`) or when `englishWords.contains(rawLower)` and `!VietnameseDictionary.shared.isValidVietnameseSyllable(composed)` (catching `"mỏe"` → `"more"`, `"cỏe"` → `"core"`, `"cáe"` → `"case"`, `"uẻ"` → `"user"`).
- **11.5 1–2 Word Context Look-Back (`REQ-018`, `ADR-017`, `VietnameseEngine.swift`)**:
  - Maintain `var previousWords: [PreviousWordEntry] = []` (up to 2 single-space-separated words).
  - When the current word at a break restores to English (or is an unchanged English-only word like `"good"`, `"course"`, `"needed"`), include up to 2 preceding `previousWords` entries where `canFollowEnglishRestore == true` (`englishLookbackStems.contains(rawLower)`), increasing `hookOutput.backspaceCount` by `entry.shownChars.count + 1` and prepending `entry.rawKeys + [KEY_SPACE]`.
- **11.6 Inline Mode Retention, 3+ Word Auto-Switch & Single-Backspace Undo (`REQ-019`, `REQ-020`, `ADR-018`, `VietnameseData.swift`, `VietnameseEngine.swift`, `EventTapCoordinator.swift`)**:
  - Add `public let languageSwitchRequest: Int` (`-1` = no change, `0` = switch to EN, `1` = switch to VI) to `OKHookSnapshot`.
  - Keep `vLanguage == 1` when `consecutiveEnglishWordCount < 3`; emit `languageSwitchRequest = 0` when `consecutiveEnglishWordCount >= 3`.
  - Implement `OKEngineHandleEnglishModeKeyEvent` for `vLanguage == 0` scratch-session replay (`replayAsVietnamese`) and `languageSwitchRequest = 1`.
  - Implement `autoRestoreUndoState` on `KEY_DELETE` (`51`) to revert the last auto-conversion + break key in 1 keystroke and lock `undoneRawWord`.

### 11.7 `KeepWords` Do-Not-Autocorrect Safe-List (`REQ-021`, `ADR-019`)
- **`VietnameseDictionary.swift`**:
  - Add `public let keepWords: Set<String>` containing curated short interjections, chat tokens, and technical abbreviations (`"ok"`, `"uh"`, `"ah"`, `"eh"`, `"oh"`, `"hm"`, `"ha"`, `"hi"`, `"he"`, `"ho"`, `"ko"`, `"dc"`, `"vs"`, `"vk"`, `"ck"`, `"mk"`, `"uhm"`, `"aha"`, `"haha"`, `"hihi"`, `"hehe"`, `"huhu"`, `"wow"`, `"yay"`, `"vip"`, `"pro"`, `"app"`, `"web"`, `"net"`, `"dev"`, `"api"`, `"sdk"`, `"ide"`, `"cli"`, `"gui"`, `"cpu"`, `"gpu"`, `"ram"`, `"ssd"`, `"usb"`, `"lan"`, `"wan"`, `"vpn"`, `"dns"`, `"ssh"`, `"ssl"`, `"tls"`, `"jwt"`, `"sql"`, `"xml"`, `"yml"`, `"csv"`, `"pdf"`, `"png"`, `"jpg"`, `"gif"`, `"mp3"`, `"mp4"`, `"zip"`, `"tar"`, `"mac"`, `"ios"`, `"win"`, `"bot"`, `"ai"`, `"ml"`, `"llm"`, etc.) unioned with `englishWords` and `englishPriorityWords`.
- **`AutoWordingEngine.swift`**:
  - In `evaluate(rawToken:composedWord:previousToken:)`, if `VietnameseDictionary.shared.keepWords.contains(rawToken.lowercased())` is `true` (and the token is not being expanded by an active `teencodeEnabled` rule), return `nil` immediately before running consonant/vowel rule normalization or Damerau-Levenshtein distance-1 fuzzy matching.

### 11.8 Removal of Built-In Teencode & Chat Shorthands (`REQ-022`, `REQ-006`, `ADR-020`, `ADR-022`)
- **`VietnameseDictionary.swift`**:
  - Remove `teencodeExpansions` and `teencodeSuffixGWhitelist` properties and initializers.
- **`OpenKeySettingsStore.swift`**:
  - Remove `Keys.teencodeEnabled` and `public var teencodeEnabled: Bool`.
- **`AutoWordingEngine.swift`**:
  - Remove `teencodeEnabled` and empty `AutoWordingShorthandCatalog.builtInTable` so `expandShorthand(rawWord:)` evaluates exclusively `_customShorthands` when `shorthandExpansionEnabled == true`.

### 11.9 Engine Context Guards: Digit-After-Space (`D33`), Arrow Navigation Snapshot (`D51`), & Compound-Token Boundary (`REQ-023`, `ADR-021`)
- **`VietnameseEngine.swift` & `BilingualAutoSwitchEngine.swift`**:
  - **Digit-After-Space Word Start (`D33`)**:
    - Track `hasDigitPrefix: Bool = false` in `VietnameseEngineState`. When a number key (`KEY_0`..`KEY_9` unshifted) is typed at the start of a token (`index == 0`), set `hasDigitPrefix = true` instead of permanently locking out Vietnamese composition for that token.
    - When letters follow the digit prefix (`"1casi"`, `"2ngayf"`), compose the letter suffix normally; at word break, if `hasDigitPrefix == true` and the composed suffix is not a valid Vietnamese syllable in `VietnameseDictionary.shared.syllableSet` (or the raw suffix matches technical/hex tokens like `"xdeadbeef"`, `"ray"`, `"mp"`, `"h"`, `"base"`), restore the letter suffix to raw ASCII.
  - **Single-Step Arrow Navigation Snapshot (`D51` `navSavedState`)**:
    - Define `struct NavSavedSnapshot` storing `index`, `stateIndex`, `keyStates`, `typingWord`, `rawKeyStates`, `rawStateIndex`, `droppedKeys`, `tempDisableKey`, and `hasDigitPrefix`.
    - When `KEY_LEFT` (`123`) is pressed with no modifiers while `index > 0`, save `navSavedState = captureNavSnapshot()` before resetting the active buffer.
    - When the immediately following key event is `KEY_RIGHT` (`124`) with no modifiers and `navSavedState != nil`, restore `navSavedState` into `state` and clear `navSavedState`. Clear `navSavedState` on any other key event.
  - **Compound-Token Boundary (`wordStartOk`)**:
    - Track `wordStartOk: Bool = true` in `VietnameseEngineState`. Set `wordStartOk = true` on whitespace (`Space`, `Tab`, `Return`) or sentence punctuation, and set `wordStartOk = false` when a token is broken by an identifier separator (`.`, `_`, `/`, `@`, `:`).
    - When a separator sets `wordStartOk = false`, clear `previousWords` and skip English-mode `enKeys` Vietnamese replay for the sub-token immediately following the separator.

### 11.10 Hybrid `E`/`V` Context-Ordered Wrong-Word Auto-Correction & Bilingual Candidate Ranking (`REQ-024`, `ADR-023`)
- **`VietnameseDictionary.swift`**:
  - `public enum LanguagePriority: String, Sendable, Equatable { case vietnameseFirst = "V"; case englishFirst = "E" }`
  - `public let englishTypoCorrections: [String: String]`: deterministic common English typos (`"teh": "the"`, `"adn": "and"`, `"taht": "that"`, `"wiht": "with"`, `"thsi": "this"`, `"recieve": "receive"`, `"beleive": "believe"`, `"seperate": "separate"`, `"definately": "definitely"`, `"occured": "occurred"`, `"becuase": "because"`, `"untill": "until"`, `"wich": "which"`, `"woudl": "would"`, `"shoudl": "should"`, `"coudl": "could"`, `"fucntion": "function"`, `"retrun": "return"`, `"strign": "string"`, `"lenth": "length"`, `"widht": "width"`, `"heigth": "height"`, `"enviroment": "environment"`, `"goverment": "government"`, `"immediatly": "immediately"`, `"asyncronous": "asynchronous"`, `"publik": "public"`, `"calender": "calendar"`, `"tommorow": "tomorrow"`, `"accomodate": "accommodate"`, `"neccessary": "necessary"`).
  - `public let vietnameseTypoCorrections: [String: String]`: deterministic Vietnamese wrong-word repairs (`"ngươi": "người"`, `"đươc": "được"`, `"dươc": "được"`, `"vơi": "với"`, `"nưa": "nữa"`).
  - `public func findEnglishTranspositionMatch(_ rawLower: String) -> String?`: checks single adjacent character swaps ($d_{DL} = 1$) against `englishPriorityWords` when `rawLower.count >= 4`, `!englishWords.contains(rawLower)`, and `!isValidVietnameseSyllable(rawLower)`.
- **`BilingualAutoSwitchEngine.swift` & `AutoWordingEngine.swift`**:
  - `effectiveLanguagePriority()` inspects `previousWords.last` (if `wasRestoredToEnglish` or English-only word → `.englishFirst`; if valid Vietnamese word → `.vietnameseFirst`) and falls back to `vLanguage == 1 ? .vietnameseFirst : .englishFirst` when `previousWords.isEmpty`.
  - At `Space` word break, if the word is not in `keepWords` and not locked by `undoneRawWord`, evaluate wrong-word typo repair in `effectiveLanguagePriority` order (`E` then `V` for `.englishFirst`; `V` then `E` for `.vietnameseFirst`) and arm `autoRestoreUndoState` (`REQ-020`).
  - In `AutoWordingEngine.computeCurrentWordCandidates`, generate both Vietnamese (`V`) and English (`E`) candidates and sort them by `effectiveLanguagePriority` (`E` first when `.englishFirst`, `V` first when `.vietnameseFirst`).

### 11.11 Sub-Millisecond Inline Bilingual Grammar, Agreement & Sentence Formatting Engine (`REQ-025`, `ADR-024`)
- **`VietnameseDictionary.swift`**:
  - `public let vietnameseBigramGrammar: [String: String]`: maps `"<word1> <word2>"` lowercase pairs to the corrected second word (`"làm việt": "việc"`, `"công việt": "việc"`, `"nghỉ ngợi": "nghĩ ngợi"` [full 2-word replacement], `"suy nghỉ": "nghĩ"`, `"sữa chữa": "sửa chữa"`, `"chỉnh sữa": "sửa"`, `"chia sẽ": "sẻ"`, `"vui vẽ": "vẻ"`, `"mạnh mẻ": "mẽ"`, `"chặt chẻ": "chẽ"`, `"dể dàng": "dễ dàng"`, `"cẫn thận": "cẩn thận"`, `"phát triễn": "triển"`, `"tiêu chuẫn": "chuẩn"`, `"ãnh hưởng": "ảnh hưởng"`, `"kỉ thuật": "kỹ thuật"`, `"bổ xung": "sung"`, `"xữ lý": "xử lý"`, `"giãi quyết": "giải quyết"`).
  - `public let englishContractionGrammar: [String: String]`: (`"im": "I'm"`, `"dont": "don't"`, `"doesnt": "doesn't"`, `"didnt": "didn't"`, `"cant": "can't"`, `"wont": "won't"`, `"isnt": "isn't"`, `"arent": "aren't"`, `"wasnt": "wasn't"`, `"werent": "weren't"`, `"havent": "haven't"`, `"hasnt": "hasn't"`, `"hadnt": "hadn't"`, `"wouldnt": "wouldn't"`, `"couldnt": "couldn't"`, `"shouldnt": "shouldn't"`).
  - `public let englishBigramGrammar: [String: String]`: full 2-word replacements (`"he dont": "he doesn't"`, `"he don't": "he doesn't"`, `"she dont": "she doesn't"`, `"she don't": "she doesn't"`, `"it dont": "it doesn't"`, `"it don't": "it doesn't"`, `"they was": "they were"`, `"we was": "we were"`, `"you was": "you were"`, `"i is": "I am"`, `"a apple": "an apple"`, `"a error": "an error"`, `"a hour": "an hour"`, `"a object": "an object"`, `"a issue": "an issue"`, `"an book": "a book"`, `"an user": "a user"`, `"an test": "a test"`).
  - `public let englishDuplicateCollapseWords: Set<String>`: (`"the"`, `"is"`, `"to"`, `"in"`, `"for"`, `"and"`, `"of"`, `"at"`, `"on"`).
- **`BilingualAutoSwitchEngine.swift`**:
  - On `Space`, after single-word/look-back resolution, run `applyInlineBilingualGrammarIfNeeded(isSpaceBreak: true)`:
    1. Check 2-word `vietnameseBigramGrammar` and `englishBigramGrammar` against `(previousWords.last, currentWord)`.
    2. Check standalone `"i"` → `"I"` and `englishContractionGrammar` in `.englishFirst` context.
    3. Check duplicate English function word collapse (`prev.lower == current.lower && englishDuplicateCollapseWords.contains(current.lower)`).
    4. When `AutoWordingEngine.shared.isEnabled && AutoWordingEngine.shared.doubleSpacePeriodEnabled`: convert double-space after a word (`spaceCount == 1 && index == 0`) to `". "` (`backspaceCount = 1`, `utf16Chars = [".", " "]`, `sentenceEndedWithPunctuation = true`) if and only if `ProcessInfo.processInfo.systemUptime - lastSpaceUptime <= 0.5`. Record `lastSpaceUptime` on each `KEY_SPACE` event. When `sentenceEndedWithPunctuation == true` and `grammarRepairEnabled == true`, auto-capitalize the first character of a lowercase word typed after terminal sentence punctuation (unless in lowercase tech `keepWords`).
    5. Arm `autoRestoreUndoState` (`REQ-020`) on every grammar/capitalization replacement so 1 `Backspace` reverts to the exact raw typed text.

### 11.12 Cohesion Refactoring (`BilingualAutoSwitchEngine.swift`) & `OpenKeyLogger` Queue Serialization (`REQ-026`, `ADR-025`)
- **`BilingualAutoSwitchEngine.swift` (`Sources/OpenKey/macOS-Swift/Sources/OpenKeySwiftCore/BilingualAutoSwitchEngine.swift`)**:
  - Houses `PreviousWordEntry`, `AutoRestoreUndoSnapshot`, `NavSavedSnapshot`, `reconstructedRawKeys()`, `isTrailingDoubledToneEscape()`, `shouldRestoreToEnglishAtBreak()`, `handleTwoWordEnglishLookbackIfNeeded()`, `applyWrongWordAndGrammarAtBreak()`, `handleSingleBackspaceUndoIfNeeded()`, `handleEnglishModeKeyEvent()`, and `replayAsVietnamese()`.
- **`OpenKeyLogger.swift`**:
  - Dispatch file mutations in `checkVersionRetention`, `recreateLogFile`, and `clearLog` through `self.queue` so they never race with `appendLogEntry`.

### 11.13 Escape Keystroke Consumption & Composed Word Protection (`REQ-027`, `ADR-027`)
- **`BilingualAutoSwitchEngine.swift`**:
  - In `evaluateWordBreakRestore`:
    - Replace `!droppedKeys.isEmpty && (dict.englishWords.contains(fullRawLower) || composed != fullRawStr)` with `!droppedKeys.isEmpty && dict.englishWords.contains(fullRawLower) && !dict.englishWords.contains(composedLower)`.
    - If `composedLower` is already in `dict.englishWords` without diacritics, do not restore `fullKeys`.
    - In `previousWords.append` on `KEY_SPACE`: if `dict.englishWords.contains(composedLower)` without diacritics, save `rawString = composed`, `rawKeys = stdRawKeys`, and `wasRestoredToEnglish = true`.

### 11.14 Previous Word History Synchronization across Backspace and Word Boundaries (`REQ-028`, `ADR-028`)
- **`VietnameseEngine.swift`**:
  - In `handleDeleteKey()`:
    - When `spaceCount > 0` decrements to `0` and invokes `restoreLastTypingState()`: call `if !previousWords.isEmpty { previousWords.removeLast() }`.
    - When `index == 0` and `typingStates.isEmpty`: call `previousWords.removeAll()`.
  - In `restoreLastTypingState()`: if `typingStates.isEmpty`, invoke `previousWords.removeAll()`.

### 11.15 English Mode Pure Passthrough & Elimination of Autonomous Mode Switching (`REQ-029`, `ADR-029`)
- **`EventTapCoordinator.swift`**:
  - When `context.language == 0`: immediately return `.passThrough(resetSession: false)`. Keystrokes pass through directly to macOS without buffering or conversion.
  - Remove autonomous `settings.language` mutation upon inline typing (discontinue setting `self?.settings.language = newLang` on `snapshot.languageSwitchRequest`).
- **`VietnameseDictionary.swift`**:
  - Append missing common English past tenses and vocabulary (`did`, `said`, `went`, `got`, `made`, `came`, `took`, `gave`, `saw`, `told`, `felt`, `kept`, `began`, `held`, `wrote`, `sat`, `stood`, `paid`, `spent`, `grew`, `won`, `bought`, `fell`, `cut`, `sold`, `ate`, `drew`, `chose`, `fought`, `threw`, `hid`, `done`, `seen`, `gone`) to `extraEngRaw`, automatically populating `englishWords` and `keepWords`.

### 11.16 Onset-Preserving Transposition Matching, Word-Initial Standalone `w` Auto-Revert, Idempotent `"I"` Replacement & Candidate Bar Race Elimination (`REQ-030`, `ADR-030`)
- **`VietnameseDictionary.swift` & `AutoWordingEngine.swift`**:
  - Add `public static func extractVietnameseOnset(_ asciiWord: String) -> String` extracting the leading Vietnamese consonant cluster (`"ngh"`, `"ng"`, `"nh"`, `"ch"`, `"gh"`, `"gi"`, `"kh"`, `"ph"`, `"qu"`, `"th"`, `"tr"`, or single initial consonant `"b"`, `"c"`, `"d"`, `"g"`, `"h"`, `"k"`, `"l"`, `"m"`, `"n"`, `"p"`, `"r"`, `"s"`, `"t"`, `"v"`, `"x"`).
  - In `AutoWordingEngine.computeCurrentWordCandidates`, compute `let stemOnset = VietnameseDictionary.extractVietnameseOnset(cleanStem)` and require `VietnameseDictionary.extractVietnameseOnset(VietnameseDictionary.stripVietnameseDiacritics(m)) == stemOnset` for all candidates `m` retrieved from `dict.telexSignatureToWords`.
  - Expand `prioRaw` (`englishPriorityWords`) in `VietnameseDictionary.swift` with unambiguous `w-` and common words: `"we"`, `"with"`, `"what"`, `"when"`, `"where"`, `"which"`, `"while"`, `"who"`, `"why"`, `"will"`, `"would"`, `"want"`, `"work"`, `"world"`, `"word"`, `"well"`, `"way"`, `"were"`, `"went"`, `"water"`, `"watch"`, `"wait"`, `"walk"`, `"think"`.
- **`BilingualAutoSwitchEngine.swift`**:
  - In `evaluateWordBreakRestore`:
    - Change standalone `"i"` check from `if fullRawLower == "i"` to `if fullRawStr == "i" && composed == "i"`.
    - Before checking `if let rw = replacementWord`, guard `if replacementWord == composed { replacementWord = nil }`.
    - In the `shouldRestore == false` branch on `KEY_SPACE`, update `let isComposedEng = (dict.englishWords.contains(composedLower) && !hasAnyDiacritic) || composed == "I"` so uppercase `"I "` sets `wasRestoredToEnglish = true`.
- **`VietnameseEngine.swift`**:
  - In `OKEngineInit()`, pre-warm `_ = VietnameseDictionary.shared`.
  - In `handleCharacterKey(keyCode:)`, when `vInputType == 0 && index == 1 && CHR(0) == KEY_U && typingWord[0].isStandaloneW` and `keyCode` is in `[KEY_E, KEY_I, KEY_H, KEY_Y, KEY_L, KEY_B, KEY_D, KEY_G, KEY_K, KEY_Q, KEY_V]`:
    - Revert `typingWord[0] = UInt32(KEY_W) | (typingWord[0].isCaps ? CAPS_MASK : 0)`, set `keyStates[0] = typingWord[0]`, `rawKeyStates[0] = typingWord[0]`, `tempDisableKey = true`.
    - Insert `keyCode` (`insertKey(keyCode: keyCode, caps: isCaps)`), set `hookOutput.code = HookCodeState.willProcess`, `hookOutput.backspaceCount = 1`, `hookOutput.newCharCount = 2`, `hookOutput.charData[1] = GET(typingWord[0])`, `hookOutput.charData[0] = GET(typingWord[1])`, and return.
  - Make `resetSession()` return `Bool` (`wasDirty`), and in `OKEngineResetSession()`, only log `"OKEngineResetSession"` when `wasDirty || !AutoWordingEngine.shared.activeCandidates.isEmpty`.
  - In `OKEngineHandleKeyEvent`, log `"OKEngineHandleKeyEvent: ..."` when `OpenKeyLogger.shared.isEnabled` even when `AutoWordingEngine.shared.isEnabled == false`.
- **`AutoWordingEngine.swift` & `CandidateBarController.swift`**:
  - In `AutoWordingEngine.updateCandidates(_:)`, inside `DispatchQueue.main.async`, verify `guard self.activeCandidates == copy else { return }` before invoking `callback(copy)`.
  - In `CandidateBarController.handleCandidatesUpdated(_:)`, move the `"Show candidate bar"` log inside the debounced `workItem` and check `guard AutoWordingEngine.shared.activeCandidates == candidates else { return }` on `@MainActor` after `CaretPositionResolver.resolveCaretScreenPoint()`.
