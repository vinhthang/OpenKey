# Architecture Decision Records: IME Intelligence, Secure Input, Ecosystem Compatibility & Adaptive Learning (`2026-10-27-ime-intelligence-and-ecosystem`)

---

## `ADR-001` — Secure Input Detection via `Carbon.IsSecureEventInputEnabled()` + Accessibility Role Check
- **Context**: Third-party macOS IMEs using `CGEventTap` must never mutate keystrokes or display predictive UI over password fields (`NSSecureTextField`, browser password inputs, `sudo` prompts, or password managers) (`REQ-001`).
- **Decision**: Query `IsSecureEventInputEnabled()` (`Carbon.HIToolbox`) and check whether the focused Accessibility element has `kAXRoleAttribute == "AXSecureTextField"` or `kAXSubroleAttribute == "AXSecureTextField"` (cached with a `0.15s` TTL alongside the launcher overlay check). When active, `KeyEventContext.isSecureInput` is set to `true`, causing `EventTapCoordinator.evaluateKeyEvent` to clear active candidates and return `.passThrough(resetSession: true)`.
- **Consequences**: Password entry is 100% immune to Telex/VNI mutation, shorthand expansion, or candidate bar popups, with `< 0.01ms` amortized overhead.

---

## `ADR-002` — Unified Launcher Overlay Detection (`Spotlight`, `Raycast`, `Alfred`)
- **Context**: Spotlight (`com.apple.Spotlight`), Raycast (`com.raycast.macos`), and Alfred (`com.runningwithcrayons.Alfred`) often render as floating non-activating panels (`kCGWindowLayer > 0`) without changing `NSWorkspace.shared.frontmostApplication` (`REQ-002`).
- **Decision**: Extend the `0.15s`-cached window layer inspection in `EventTapCoordinator` to match window owners `"Spotlight"`, `"Raycast"`, and `"Alfred"` (with `kCGWindowLayer > 0`, `width >= 200`, `height >= 40`) in addition to checking `isLauncherApp(bundleId:)` for `com.apple.Spotlight`, `com.raycast.macos`, and `com.runningwithcrayons.Alfred*`.
- **Consequences**: Summoning Spotlight, Raycast, or Alfred immediately bypasses Vietnamese composition and resets any partial syllable state.

---

## `ADR-003` — On-Demand `AXManualAccessibility` Activation for Electron & Chromium Targets
- **Context**: Electron and Chromium apps disable their internal Accessibility tree by default until `"AXManualAccessibility"` is set to `kCFBooleanTrue` on the application's `AXUIElement`, causing `kAXBoundsForRangeParameterizedAttribute` to fail (`REQ-003`).
- **Decision**: In `CaretPositionResolver`, retrieve the PID of the focused `AXUIElement` via `AXUIElementGetPid` and set `"AXManualAccessibility" = kCFBooleanTrue` once per PID (tracked in a locked `Set<pid_t>`). Clamp candidate bar coordinates against `CaretPositionResolver.screenContaining(point:)`.
- **Consequences**: Electron and Chromium apps (VS Code, Cursor, Slack, Discord, Notion, Chrome, Arc, Brave) expose accurate caret bounds for the Liquid Glass candidate bar across single and multi-monitor setups.

---

## `ADR-004` — Comprehensive Invalid-Word Restoration (`KEY_D` / `đ` & Trailing Control Keys)
- **Context**: `checkRestoreIfWrongSpelling` previously checked `!isConsonant(CHR(ii))` before inspecting `TONE_MASK`, which skipped `KEY_D` (`đ`) in English words like `"dead"` or `"added"`. Additionally, when `shouldSendControlKey` was true on word-break restoration, `EventTapCoordinator` swallowed the trailing control key (`REQ-004`).
- **Decision**:
  1. Remove the `!isConsonant(CHR(ii))` restriction in `checkRestoreIfWrongSpelling` so any character with `MARK_MASK`, `TONE_MASK` (including `đ`), or `TONEW_MASK` triggers full ASCII restoration when `tempDisableKey` (`!spellingOK || !spellingVowelOK`) is true.
  2. Add `passThroughTrailingKey: Bool = false` to `EventTapAction.replaceKeystroke` so `EventTapCoordinator.handleEvent` returns `Unmanaged.passUnretained(event)` after posting the replacement when `snapshot.shouldSendControlKey == true`.
- **Consequences**: English words containing `d...d` (`"dead"`, `"added"`, `"divided"`) and words terminated by `Return`/`Tab` restore cleanly without dropping the trailing key.

---

## `ADR-005` — Lightweight User Frequency Boosting & Custom Shorthand Table in `UserDefaults`
- **Context**: Users need candidate suggestions that adapt to their personal vocabulary (`REQ-005`) and a way to define custom shorthand expansions alongside expanded built-in shorthands (`REQ-006`).
- **Decision**:
  1. Store candidate acceptance counts in `UserDefaults` under `"UserWordFrequencyData"` (`[String: Int]`) and sort candidate arrays by `(userFrequency[word] ?? 0)` descending before falling back to static dictionary order.
  2. Store user-defined shorthands in `UserDefaults` under `"CustomShorthandsData"` (`[String: String]`), checking `customShorthands[lower]` first before `shorthandTable[lower]`, and expose an inline editor + frequency reset button in `SettingsView`.
- **Consequences**: Zero external database dependencies, `< 0.05ms` lookup overhead, and full persistence across app restarts.

---

## `ADR-006` — Multi-Delete, Diphthong Tone Replacement & Subsequent Character Entry State Integrity (`hookOutput`, `CHR`, `keyStates`, `typingStates`)
- **Context**: User testing revealed word corruption when pressing `Delete` (`KEY_DELETE`) repeatedly and then entering new characters, as well as `"tiiếng"` (`ii` vowel duplication) when typing `"kiểm tra tiếng v, "` (`REQ-007`). Comparative analysis isolated six interacting defects:
  1. `insertMark(markMask:canModifyFlag: false)` inside `checkGrammar` called `handleModernMark()` and `handleOldMark()`, which unconditionally mutated `hookOutput.backspaceCount = Int(index) - Int(vowelWillSetMark)` (`5 - 2 = 3`) even when `canModifyFlag == false`. During `t-i-e-e-n-g-s` (`"tiếng"`), `insertMark(canModifyFlag: true)` set `backspaceCount = 4` and `newCharCount = 4` (`"iếng"`), and then `checkGrammar(deltaBackSpace: 0)` called `insertMark(canModifyFlag: false)` which called `handleModernMark()` and overwrote `backspaceCount = 3`, leaving `"ti"` on screen before injecting `"iếng"` (`"tiiếng"`). Additionally, `handleModernMark()` Rule 3.1 used `(w1 & (UInt32(KEY_E) | TONE_MASK)) != 0` instead of `CHR(vsi + 1) == KEY_E && (w1 & TONE_MASK) != 0`.
  2. `CHR(_ idx:)` did not check `idx < Int(index)` and returned `0` (`KEY_A`!) instead of `KEY_EMPTY` (`256`), so `checkSpelling()`, `handleModernMark()`, and `insertW()` read deleted characters still sitting at `typingWord[Int(index)]`.
  3. `keyStates` and `stateIndex` were not synchronized with `typingWord` and `index` after `KEY_DELETE` or `restoreLastTypingState()`, resurrecting deleted Telex modifier keys on subsequent typing.
  4. `resetSession()` and shorthand expansion did not clear `typingStates`, `typingStatesData`, `specialChar`, and `spaceCount`; `KEY_SPACE` left the previous word in `typingWord` while `spaceCount > 0`, and `startNewSessionInternal()` clobbered `hookOutput.backspaceCount` and `hookOutput.newCharCount` when called after `checkRestoreIfWrongSpelling`.
  5. `checkGrammar(deltaBackSpace:)` ran `repairPhonotacticClusterIfNeeded` during `KEY_DELETE` (`deltaBackSpace == 1`) and immediately overwrote `isCheckedGrammar = false`.
  6. `AutoWordingEngine.updateCandidates(_:)` ran `MainActor.assumeIsolated` synchronously inside the `CGEventTap` callback (`Thread.isMainThread == true`), triggering synchronous cross-process `AXUIElement` IPC before `KeystrokeInjector` posted synthetic keystrokes.
- **Decision**:
  1. Remove all `hookOutput.backspaceCount` and `hookOutput.newCharCount` writes from `handleModernMark()` and `handleOldMark()` so they only compute `vowelWillSetMark`; fix Rule 3.1 in `handleModernMark()` to check `CHR(vsi + 1) == KEY_E && (w1 & TONE_MASK) != 0`; guard all `hookOutput` mutations in `insertMark` behind `if canModifyFlag` with `hookOutput.backspaceCount = UInt8(Int(index) - vsi)` and `hookOutput.newCharCount = hookOutput.backspaceCount`; emit zeroed `backspaceCount`/`newCharCount`/`utf16Chars` whenever `hookOutput.code == HookCodeState.doNothing`.
  2. Enforce `guard idx >= 0 && idx < Int(index) && idx < maxBuff else { return KEY_EMPTY }` in `CHR(_ idx:)` and clear `typingWord` slots on `KEY_DELETE` and session reset.
  3. Synchronize `stateIndex = index` and `keyStates[0..<Int(index)]` from base keys of `typingWord` on `KEY_DELETE` and `restoreLastTypingState()`, and call `checkSpelling()` in `restoreLastTypingState()`.
  4. Clear `typingStates`, `typingStatesData`, `specialChar`, `spaceCount`, and `willTempOffEngine` in `resetSession()` and on shorthand expansion, and remove `hookOutput.backspaceCount = 0` / `hookOutput.newCharCount = 0` from `startNewSessionInternal()` so calling it after `saveWord()` on `KEY_SPACE` preserves word-break restoration output.
  5. Only call `repairPhonotacticClusterIfNeeded` when `deltaBackSpace <= 0`, preserve `isCheckedGrammar = repaired`, restrict Rule 1 (`ie`/`ye` + consonant → `iê`/`yê`) to when a tone mark is being inserted or already present, and dispatch `AutoWordingEngine.updateCandidates(_:)` asynchronously via `DispatchQueue.main.async`.
- **Consequences**: Diphthong tone placement (`"tiếng"`, `"kiểm"`, `"trường"`), repeated `Delete` presses, and subsequent character entry across single words, multi-word sentences, and shorthand expansions behave deterministically with zero `"tiiếng"` vowel duplication or buffer desynchronization.
