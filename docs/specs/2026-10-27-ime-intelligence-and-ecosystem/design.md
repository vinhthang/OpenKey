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
