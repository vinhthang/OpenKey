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

### 6.1 Module Decomposition Map (All Files `< 500` Lines)
- **`OpenKeySwiftCore` Target**:
  1. `VietnameseData.swift` (`< 400` lines): Virtual keycode constants, bitmask constants, `@inline(__always)` `UInt32` syllable bitmask helpers (`baseKey`, `isCaps`, `hasToneMark`, `toneMark`, `hasCircumflexOrStroke`, `hasHornOrBreve`, `hasAnyDiacritic`, `isAutoTone`, `isStandaloneW`), `NSLock.withLock`, `OKHookSnapshot`, `HookCodeState`, and phonotactic tables.
  2. `VietnameseUnicodeTable.swift` (`< 200` lines): Precomposed Unicode `_codeTable`, `_characterMap`, and `keyCodeToCharacter(_:)`.
  3. `VietnameseEngine.swift` (`< 400` lines): `OKWordContext`, `VietnameseEngineState` core state buffers, configuration, session lifecycle (`initEngine`, `resetSession`, `commitExternalExpansion`, `getWordContext`, `getComposedWord`), buffer helpers (`insertKey`, `insertState`, `saveWord`, `restoreLastTypingState`), and public `OKEngine*` functions.
  4. `VietnameseEngine+SpellingAndGrammar.swift` (`< 350` lines): `checkSpelling`, `checkCorrectVowel`, `canHasEndConsonant`, `findAndCalculateVowel`, `repairPhonotacticClusterIfNeeded`, `checkGrammar`, and `checkRestoreIfWrongSpelling`.
  5. `VietnameseEngine+MarkAndTone.swift` (`< 420` lines): `getCharacterCode`, `removeMark`, `handleModernMark`, `handleOldMark`, `insertMark`, `insertD`, `insertAOE`, `insertW`, `reverseLastStandaloneChar`, `checkForStandaloneChar`, and `handleMainKey`.
  6. `VietnameseEngine+KeyEventDispatcher.swift` (`< 300` lines): `handleKeyEvent(keyCode:capsStatus:otherControlKey:)` decomposed into `handleWordBreakOrControlKey`, `handleSpaceKey`, `handleDeleteKey`, `handleCharacterKey`, and `buildOutputSnapshot`.
  7. `SmartSwitchStore.swift` (`< 150` lines): Per-app language memory (`SmartSwitchStore.shared`) with `Data`-based persistence (`loadData(_:)`, `exportData()`) plus `OKInitSmartSwitchKey`, `OKGetSmartSwitchKeySaveData`, `OKGetAppInputMethodStatus`, and `OKSetAppInputMethodStatus`.
  8. `AutoWordingTypes.swift` (`< 150` lines): `CandidateKind`, `WordCandidate`, `AutoWordingShorthandCatalog` (`builtInShorthands`, `properNounShorthands`).
  9. `AutoWordingEngine.swift` (`< 450` lines): Lock-isolated configuration and candidate state using `lock.withLock`, frequency learning, shorthand expansion, candidate ranking, phonotactic cluster repair, and pre/post key event hooks.
  10. `VietnameseDictionary.swift` (`< 160` lines): `VietnameseDictionary` index construction and `stripVietnameseDiacritics(_:)`.
  11. `VietnameseDictionaryCorpus.swift` (`< 480` lines): Compact static syllable array, compound bigram table, and priority weights.
  12. `SystemEnvironmentDetector.swift` (`< 200` lines): `EventTapEventType`, `KeyEventContext`, `EventTapAction`, and system environment detectors (`isSecureEventInputActive`, `isLauncherApp`, `isTerminalApp`, `isSpotlightOverlayVisible`, `markSpotlightNeedsRecheck`, `invalidateSpotlightCache`).
  13. `EventTapCoordinator.swift` (`< 450` lines): `CGEventTap` setup/teardown, app-switch/wake observers, `evaluateKeyEvent(_:)`, and `handleEvent(proxy:type:event:)`.
- **`OpenKeySwiftTests` Target**:
  - Split `OpenKeySwiftTests.swift` (`1,602` lines) into `OpenKeyEngineTests.swift` (`< 480` lines), `OpenKeyEventTapTests.swift` (`< 480` lines), and `OpenKeyAutoWordingTests.swift` (`< 480` lines) alongside `OpenKeyLoadTests.swift` (`< 480` lines).
