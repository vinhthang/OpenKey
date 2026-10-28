# Specification: IME Intelligence, Secure Input, Ecosystem Compatibility & Adaptive Learning (`2026-10-27-ime-intelligence-and-ecosystem`)

- **Feature ID**: `2026-10-27-ime-intelligence-and-ecosystem`
- **Status**: `Completed`
- **Date**: `2026-10-27`
- **Platform**: `macOS 26.0+` (`arm64`, Pure Swift 6)

---

## 1. Problem Statement
Following internet research into macOS Vietnamese IME failure modes (OpenKey, EVKey, XKey, Chromium/Electron accessibility trees, `IsSecureEventInputEnabled()`, and launcher overlays) and a deep audit of `OpenKeySwiftCore` / `OpenKeySwiftApp`, seven concrete engineering improvements and defect resolutions were identified:
1. **Password & Secure Input Leaks**: When `IsSecureEventInputEnabled()` is active or an `AXSecureTextField` is focused, `EventTapCoordinator` must immediately bypass Vietnamese composition and hide the floating candidate bar.
2. **Launcher Overlay Conflicts (`Spotlight`, `Raycast`, `Alfred`)**: System launchers summon non-activating floating panels (`kCGWindowLayer > 0`) without triggering standard app switch notifications, causing English search queries to be altered by Vietnamese Telex/VNI rules.
3. **Electron/Chromium Caret Bounds (`AXManualAccessibility`) & Multi-Monitor Clamping**: Electron and Chromium applications disable their macOS Accessibility tree unless `"AXManualAccessibility"` is enabled on the target application `AXUIElement`, causing `CaretPositionResolver` to fall back to the mouse cursor instead of the text caret.
4. **English / Foreign Word Auto-Restore Gaps (`dd` / `đ` & Control-Key Word Breaks)**: `checkRestoreIfWrongSpelling` skipped consonants when checking `TONE_MASK`, failing to restore English words where `d...d` produced `đ` (e.g., `"dead"`, `"added"`), and `EventTapCoordinator` swallowed trailing control keys (`Return`/`Tab`) when `shouldSendControlKey` was set on a restored word.
5. **Static Candidate Ordering**: `AutoWordingEngine` ranked candidates with static priorities rather than adapting to the user's accepted words and compound phrases.
6. **Non-Extensible Shorthand Table**: Users could not add or remove custom shorthand expansions in `SettingsView`, and common work/chat shorthands (`k`, `j`, `bh`, `mn`, `cty`, `nv`, `gd`, `sdt`, `tks`) were missing from the default table.
7. **Multi-Delete & Subsequent Character Entry Word Breaking**: Pressing `Delete` (`KEY_DELETE`) repeatedly on toned words or across word boundaries and then entering new characters caused five interacting state bugs: (a) `insertMark(markMask:canModifyFlag: false)` inside `checkGrammar` dirtied `hookOutput.backspaceCount`/`newCharCount` while `hookOutput.code == 0`, causing `EventTapCoordinator` to swallow `Delete` and re-inject vowels (`"nhất"` + `Delete` → `"nhấấ"`); (b) `CHR(_ idx:)` read past `index` and returned `0` (`KEY_A`) instead of `KEY_EMPTY` (`256`); (c) `keyStates` and `stateIndex` desynchronized from `typingWord` and `index` after `KEY_DELETE` and `restoreLastTypingState()`; (d) `resetSession()` and shorthand expansion left stale words in `typingStates`; and (e) `checkGrammar` ran `repairPhonotacticClusterIfNeeded` during `KEY_DELETE` and overwrote `isCheckedGrammar = false`.

---

## 2. Normative Requirements

### `REQ-001` — Secure Input & Password Field Protection
- **Description**: `EventTapCoordinator` MUST detect secure text entry (`IsSecureEventInputEnabled()` from `Carbon` or a focused `AXSecureTextField` Accessibility element) and expose `isSecureInput: Bool` in `KeyEventContext`. When `isSecureInput == true`, `evaluateKeyEvent` MUST clear any active word candidates, reset the engine session, and return `.passThrough(resetSession: true)`.
- **Acceptance Criteria**:
  1. When `KeyEventContext.isSecureInput == true` in Vietnamese mode (`language == 1`), `evaluateKeyEvent` returns `.passThrough(resetSession: true)` and clears `AutoWordingEngine.shared.activeCandidates`.
  2. `EventTapCoordinator.isSecureEventInputActive()` queries `IsSecureEventInputEnabled()`.

### `REQ-002` — Universal System Launcher Overlay Detection (`Spotlight`, `Raycast`, `Alfred`)
- **Description**: `EventTapCoordinator` MUST detect active launcher overlays and bundle identifiers for **Spotlight** (`com.apple.Spotlight`), **Raycast** (`com.raycast.macos`), and **Alfred** (`com.runningwithcrayons.Alfred`, `com.runningwithcrayons.Alfred-Preferences`), bypassing Vietnamese composition and resetting the session when a launcher overlay is active.
- **Acceptance Criteria**:
  1. `EventTapCoordinator.isLauncherApp(bundleId:)` returns `true` for Spotlight, Raycast, and Alfred bundle IDs.
  2. When `activeAppBundleId` matches a launcher app or `isSpotlightVisible` is `true`, `evaluateKeyEvent` returns `.passThrough(resetSession: true)`.

### `REQ-003` — Electron/Chromium Caret Positioning (`AXManualAccessibility`) & Multi-Display Clamping
- **Description**: `CaretPositionResolver` MUST enable `"AXManualAccessibility"` (`kCFBooleanTrue`) once per focused application PID so Electron and Chromium applications expose `kAXSelectedTextRangeAttribute` and `kAXBoundsForRangeParameterizedAttribute`. `CandidateBarController` MUST clamp the floating candidate bar frame to the `visibleFrame` of the `NSScreen` containing the resolved caret point.
- **Acceptance Criteria**:
  1. `CaretPositionResolver.enableManualAccessibilityIfNeeded(for:pid:)` sets `"AXManualAccessibility"` once per PID and caches enabled PIDs in a thread-safe set.
  2. `CaretPositionResolver.screenContaining(point:)` selects the screen whose frame contains the point (falling back to `NSScreen.main` or `NSScreen.screens.first`).

### `REQ-004` — Enhanced English Word Auto-Restore (`dd`/`đ` Restoration & Control-Key Word Breaks)
- **Description**: When `vRestoreIfWrongSpelling != 0`, `VietnameseEngine.checkRestoreIfWrongSpelling` MUST restore raw keystrokes whenever any character in the syllable has `MARK_MASK`, `TONE_MASK` (including `KEY_D` / `đ`), or `TONEW_MASK` and the word fails Vietnamese spelling validation (`!spellingOK || !spellingVowelOK`). Additionally, when `OKHookSnapshot.shouldSendControlKey == true`, `EventTapCoordinator` MUST preserve/pass through the trailing control key after injecting the restored characters.
- **Acceptance Criteria**:
  1. Typing English words with `d...d` (such as `"dead "` or `"added "`) in Telex with `restoreIfWrongSpelling = true` restores the raw ASCII word (`"dead"`, `"added"`) on `Space` instead of leaving `"đea"` or `"ađed"`.
  2. Typing English words with invalid Vietnamese vowel/consonant combinations (`"sweet "`, `"window "`, `"project "`) restores the raw ASCII characters on word break.
  3. `EventTapAction.replaceKeystroke` includes `passThroughTrailingKey: Bool` (populated from `snapshot.shouldSendControlKey`) so trailing control keys (`Return`/`Tab`) are not swallowed after word restoration.

### `REQ-005` — User-Adaptive Candidate Frequency Learning
- **Description**: `AutoWordingEngine` MUST record user candidate acceptances (`recordCandidateAcceptance(text:previousWord:)`) and persist frequency counts in `UserDefaults` (`"UserWordFrequencyData"`). Both `computeCurrentWordCandidates` and `computeNextWordCandidates` MUST boost candidates with higher user acceptance frequency so frequently accepted words rank `#1` (`Tab`). `SettingsView` MUST provide a control to reset learned word frequencies.
- **Acceptance Criteria**:
  1. Calling `AutoWordingEngine.shared.recordCandidateAcceptance(text:)` increments the persisted frequency for that candidate in `UserDefaults`.
  2. A candidate with higher user acceptance frequency ranks ahead of default-ordered candidates for the same stem or preceding word.
  3. Calling `AutoWordingEngine.shared.resetLearnedFrequencies()` clears all learned counts.

### `REQ-006` — Expanded & User-Customizable Shorthand Dictionary
- **Description**: `AutoWordingEngine` MUST expand additional high-frequency Vietnamese shorthands (`k` → `không`, `j` → `gì`, `bh` → `bây giờ`, `mn` → `mọi người`, `cty` → `công ty`, `nv` → `nhân viên`, `gd` → `gia đình`, `sdt` → `số điện thoại`, `tks` → `cảm ơn`) and support user-defined custom shorthands (`customShorthands: [String: String]`) persisted in `OpenKeySettingsStore` (`"CustomShorthandsData"`) and editable in `SettingsView`.
- **Acceptance Criteria**:
  1. Typing `"cty "`, `"mn "`, `"sdt "`, `"bh "`, `"k "`, `"j "` in Telex expands to `"công ty "`, `"mọi người "`, `"số điện thoại "`, `"bây giờ "`, `"không "`, `"gì "` when shorthand expansion is enabled.
  2. Adding a custom shorthand in `OpenKeySettingsStore.shared.setCustomShorthand(trigger:replacement:)` persists across sessions and overrides or extends the built-in shorthand table on `Space`.

### `REQ-007` — Multi-Delete, Diphthong Tone Replacement & Subsequent Character Entry State Integrity
- **Description**: `VietnameseEngine`, `AutoWordingEngine`, and `EventTapCoordinator` MUST maintain strict buffer, screen-replacement (`backspaceCount` vs `newCharCount`), and hook-state invariance across diphthong tone placement (`"tiếng"`, `"kiểm"`, `"trường"`), single and multiple `KEY_DELETE` (`51`) operations, and subsequent character entry:
  1. `insertMark(markMask:canModifyFlag: false)`, `handleModernMark()`, and `handleOldMark()` MUST NOT mutate `hookOutput.backspaceCount` or `hookOutput.newCharCount` when `canModifyFlag == false`, so `checkGrammar(deltaBackSpace: 0)` never overwrites `hookOutput.backspaceCount` (e.g., from `4` to `3` on `"tiếng"`, which previously left `"ti"` on screen before injecting `"iếng"` to produce `"tiiếng"`). `handleModernMark()` Rule 3.1 MUST check `CHR(vsi + 1) == KEY_E && (w1 & TONE_MASK) != 0` rather than bitwise `(w1 & (UInt32(KEY_E) | TONE_MASK)) != 0`. `handleKeyEvent` MUST return `backspaceCount == 0`, `newCharCount == 0`, and `utf16Chars == []` whenever `hookOutput.code == HookCodeState.doNothing` (`0`), and `EventTapCoordinator.evaluateKeyEvent` MUST treat `snapshot.code == HookCodeState.doNothing` as a clean pass-through.
  2. `CHR(_ idx:)` MUST return `KEY_EMPTY` (`256`) whenever `idx < 0 || idx >= Int(index) || idx >= maxBuff`, and `typingWord` slots at or above `index` MUST be cleared on `KEY_DELETE` and session reset.
  3. On `KEY_DELETE` and inside `restoreLastTypingState()`, `keyStates` and `stateIndex` MUST be synchronized to `typingWord[0..<Int(index)]` (`stateIndex = index`) and `checkSpelling()` re-evaluated so subsequent characters never resurrect deleted Telex modifier keys.
  4. `resetSession()` and shorthand expansion MUST clear `typingStates`, `typingStatesData`, `specialChar`, `spaceCount`, and `willTempOffEngine`. `startNewSessionInternal()` MUST reset `index = 0` and `stateIndex = 0` without clobbering `hookOutput.backspaceCount` or `hookOutput.newCharCount` when called after `checkRestoreIfWrongSpelling` on `KEY_SPACE`.
  5. `checkGrammar(deltaBackSpace:)` MUST NOT invoke `repairPhonotacticClusterIfNeeded` during `KEY_DELETE` (`deltaBackSpace > 0`), MUST preserve `isCheckedGrammar` when phonotactic repair fires on forward keystrokes, and `repairPhonotacticClusterIfNeeded` Rule 1 (`ie`/`ye` + consonant → `iê`/`yê`) MUST only fire when a tone mark is being inserted or already present. `AutoWordingEngine.updateCandidates(_:)` MUST dispatch UI callbacks asynchronously so Accessibility queries never block `CGEventTap` keystroke replacement.
- **Acceptance Criteria**:
  1. Typing `"kiểm tra tiếng v, "` (via both `t-i-e-e-n-g-s` and `t-i-e-n-g-s`) into a simulated screen buffer applying `backspaceCount` and `utf16Chars` on every keystroke produces `"kiểm tra tiếng v, "` with `backspaceCount == 4` and `newCharCount == 4` on the `'s'` keystroke of `"tiếng"`, never duplicating `'i'` (`"tiiếng"`).
  2. Typing toned words (`"nhất"`, `"tiếng"`, `"trường"`, `"hoàn"`) and pressing `KEY_DELETE` 1 to 6 times passes through `Delete` cleanly (`snapshot.code == 0`, `backspaceCount == 0`, `newCharCount == 0`, `.passThrough(resetSession: false)`) whenever the tone mark position does not shift, never duplicating vowels (`"nhấấ"`).
  3. Typing `"tiếng"` (`t-i-e-e-n-g-s`), pressing `Delete` 3 times (leaving `"ti"`), and typing `"me "` or `"ếp"` produces `"time "` or `"tiếp"` on the simulated screen buffer without resurrecting deleted `'e'` from `keyStates`.
  4. Typing multi-word sequences (`"xin chào em"`) or shorthand expansions (`"ko "` → `"không "`), pressing `Delete` repeatedly across word boundaries, and typing new characters produces exact Vietnamese composition on the simulated screen buffer with zero ghost characters from `typingStates`.

### `REQ-008` — Auto Wording Module Isolation, Master Toggle Sub-Feature Activation & Live `.doNothing` Candidate Generation
- **Statement**: All Auto Wording logic (phonotactic cluster repair, shorthand expansion on Space, live current-word candidate generation, and compound next-word prediction) MUST be isolated in `AutoWordingEngine.swift` with zero direct symbol references from `VietnameseEngineState` (`VietnameseEngine.swift` exposes `OKWordContext` read-only word snapshots, `commitExternalExpansion()`, and an optional `phonotacticRepairHook` closure, and fast-paths directly to `VietnameseEngineState.handleKeyEvent` with zero overhead when `AutoWordingEngine.shared.isEnabled == false`). All mutable state in `AutoWordingEngine` MUST be lock-isolated for thread safety and `updateCandidates(_:)` MUST be idempotent. Enabling `autoWordingEnabled` MUST ensure at least one sub-feature is active (auto-enabling `grammarRepairEnabled`, `shorthandExpansionEnabled`, and `candidateSuggestionsEnabled` in a single batch sync if all three are `false`). Live candidate updates MUST execute after every keystroke including `HookCodeState.doNothing` (`0`) and `KEY_DELETE`, distinguishing `.correction` (`isWrongSpelling == true` / transposition, accepted via `Tab` or `Ctrl+1..3`) from `.stemCompletion` and `.nextWord` (accepted via `Ctrl+1..3` without hijacking `Tab`). Finally, `CaretPositionResolver` MUST accept zero-width insertion carets (`rect.width >= 0 && rect.height > 0`), enforce a `40ms` `AXUIElementSetMessagingTimeout`, and resolve off the main thread while `CandidateBarController` configures its `NSPanel` with `level = .popUpMenu`, `hidesOnDeactivate = false`, and `orderFrontRegardless()`.
- **Acceptance Criteria**:
  1. `VietnameseEngineState` contains zero direct references to `AutoWordingEngine`, and when `AutoWordingEngine.shared.isEnabled == false`, `OKEngineHandleKeyEvent` executes without calling `getWordContext` or dispatching `onCandidatesChanged`.
  2. Toggling `OpenKeySettingsStore.shared.autoWordingEnabled = true` when `grammarRepairEnabled`, `shorthandExpansionEnabled`, and `candidateSuggestionsEnabled` are all `false` automatically activates all three sub-toggles (`true`) and syncs them to `AutoWordingEngine.shared` without redundant cascade syncs.
  3. Typing plain unaccented letters (`"thanh"`) populates `.stemCompletion` candidates (`"thành"`, `"thánh"`) where `Tab` passes through without hijacking indentation/navigation while `Ctrl+1..3` accepts the candidate; typing a misspelled/transposed syllable (`"tineg"`) populates `.correction` candidates (`"tiếng"`) where `Tab` accepts candidate `#1`.
  4. `CaretPositionResolver` accepts zero-width insertion carets (`rect.width == 0 && rect.height > 0`), applies a `40ms` AX messaging timeout, and `CandidateBarController` resolves caret coordinates on a background queue and displays its `NSPanel` (`level = .popUpMenu`, `hidesOnDeactivate = false`, `orderFrontRegardless()`) without blocking the `CGEventTap` runloop.

### `REQ-009` — Codebase Modularization, Complexity Reduction & Readability (`ADR-008`)
- **Statement**: The system MUST decompose monolithic source and test files so that every `.swift` file in `Sources/OpenKey/macOS-Swift/Sources/` and `Sources/OpenKey/macOS-Swift/Tests/` is under 500 lines and follows a single, well-defined responsibility, while replacing cryptic C++-ported bitmask expressions and repetitive lock/dispatch boilerplate with self-documenting Swift helpers (`UInt32` syllable bitmask extensions, `NSLock.withLock`, named phase handlers in `VietnameseEngineState`, extracted `SmartSwitchStore`, `SystemEnvironmentDetector`, `AutoWordingTypes`, `VietnameseUnicodeTable`, and `VietnameseDictionaryCorpus`) with zero behavioral regression.
- **Acceptance Criteria**:
  1. Every `.swift` file under `Sources/OpenKey/macOS-Swift/Sources/` and `Sources/OpenKey/macOS-Swift/Tests/` has `< 500` lines (`wc -l`).
  2. `VietnameseEngine.swift` (formerly `1,851` lines) is decomposed into focused, single-purpose files (`VietnameseEngine.swift`, `VietnameseEngine+SpellingAndGrammar.swift`, `VietnameseEngine+MarkAndTone.swift`, `VietnameseEngine+KeyEventDispatcher.swift`, and `SmartSwitchStore.swift`) using expressive `UInt32` syllable bitmask properties (`baseKey`, `isCaps`, `hasToneMark`, `hasCircumflexOrStroke`, `hasHornOrBreve`, `hasAnyDiacritic`, `isAutoTone`, `isStandaloneW`) and named event phase handlers (`handleWordBreakOrControlKey`, `handleSpaceKey`, `handleDeleteKey`, `handleCharacterKey`, `buildOutputSnapshot`).
  3. `EventTapCoordinator.swift`, `AutoWordingEngine.swift`, `VietnameseDictionary.swift`, `VietnameseData.swift`, and `OpenKeySwiftTests.swift` are modularized into cohesive sub-500-line files (`SystemEnvironmentDetector.swift`, `AutoWordingTypes.swift`, `VietnameseDictionaryCorpus.swift`, `VietnameseUnicodeTable.swift`, `OpenKeyEngineTests.swift`, `OpenKeyEventTapTests.swift`, `OpenKeyAutoWordingTests.swift`, `OpenKeyLoadTests.swift`).
  4. All unit/load tests (`32+` tests via `swift test`) and all `10/10` real-system E2E load tests (`scripts/real-system-load-test.swift`) pass with 100% public API and behavioral parity.
