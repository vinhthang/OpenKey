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

---

## `ADR-007` — Isolating `AutoWordingEngine` from `VietnameseEngineState` & Fixing Live Candidate Lifecycle (`REQ-008`)
- **Context**: In manual testing and architectural code review, Auto Wording required full isolation and runtime hardening across six areas:
  1. Toggling `autoWordingEnabled = true` from the menu bar left `grammarRepairEnabled`, `shorthandExpansionEnabled`, and `candidateSuggestionsEnabled` all set to `false` (`0`) in `UserDefaults`, leaving all Auto Wording capabilities inactive.
  2. In `VietnameseEngine.handleKeyEvent`, `if hookOutput.code == HookCodeState.doNothing { return ... }` returned before reaching the candidate update block, so typing plain characters (`"thanh"`, `"ban"`, `"tineg"`) never generated candidates.
  3. In `CandidateBarController.swift`, `NSPanel` defaulted to `hidesOnDeactivate = true` and used `orderFront(nil)`, hiding the candidate panel in background `LSUIElement` mode; additionally, `CaretPositionResolver` rejected valid zero-width native insertion carets (`rect.width == 0`) and ran synchronous AX IPC on the main runloop without an AX messaging timeout.
  4. Treating plain unaccented stem completions (`"ban"`, `"thanh"`) and next-word predictions identically to typo corrections caused `Tab` (`keyCode == 48`) to be hijacked during normal Vietnamese typing.
  5. Unsynchronized reads of `activeCandidates`, `userFrequencies`, and feature flags in `AutoWordingEngine`, non-idempotent `clearCandidates()` main-thread dispatches, and calling `getWordContext` when Auto Wording was disabled introduced data races and unnecessary per-keystroke overhead.
- **Decision**:
  1. Remove all `AutoWordingEngine` references and duplicate flags from `VietnameseEngineState`, connecting phonotactic repair via an injected `phonotacticRepairHook` closure and fast-pathing `OKEngineHandleKeyEvent` when `!AutoWordingEngine.shared.isEnabled`. When enabled, execute `(preContext, snapshot, postContext)` atomically under `VietnameseEngineState.lock`.
  2. Synchronize all state in `AutoWordingEngine` under `lock` and make `updateCandidates(_:)` a no-op when `activeCandidates == candidates`.
  3. Distinguish `CandidateKind.correction` (`isWrongSpelling == true` / transposition) from `.stemCompletion` (`isWrongSpelling == false`) and `.nextWord`, restricting `Tab` acceptance to `.correction` while `Ctrl+1..3` accepts all candidate kinds.
  4. In `CaretPositionResolver`, accept `rect.width >= 0 && rect.height > 0`, set `AXUIElementSetMessagingTimeout(..., 0.04)`, and resolve caret coordinates on a background queue before updating `CandidateBarController`'s `NSPanel` (`level = .popUpMenu`, `hidesOnDeactivate = false`, `orderFrontRegardless()`).
- **Consequences**: `VietnameseEngineState` is 100% decoupled from `AutoWordingEngine`, disabled mode has zero overhead, `Tab` is never hijacked on valid words, native zero-width carets resolve accurately, and AX IPC can never stall the `CGEventTap` runloop.

---

## `ADR-008` — Modularizing Monolithic Swift Files (<500 Lines) & Replacing C++-Ported Bitmask Boilerplate (`REQ-009`)
- **Context**: Following the pure Swift 6 port and feature additions (`REQ-001`..`REQ-008`), six files grew beyond 500 lines (`VietnameseEngine.swift` at `1,851` lines, `OpenKeySwiftTests.swift` at `1,602` lines, `EventTapCoordinator.swift` at `669` lines, `VietnameseDictionary.swift` at `665` lines, `VietnameseData.swift` at `646` lines, and `AutoWordingEngine.swift` at `580` lines). In particular, `VietnameseEngine.swift` mixed six distinct responsibilities (state buffers, phonotactic spell-checking, grammar/tone mark positioning, vowel/consonant transforms, keystroke event dispatching, and per-app Smart Switch binary persistence) using raw C++ bitmask arithmetic (`(typingWord[i] & MARK_MASK) != 0`) and a 235-line nested `handleKeyEvent` method, making the codebase harder to read and modify.
- **Decision**:
  1. Decompose `VietnameseEngineState` (changing `private` to `internal` across extension files) into 4 cohesive files under 450 lines (`VietnameseEngine.swift`, `VietnameseEngine+SpellingAndGrammar.swift`, `VietnameseEngine+MarkAndTone.swift`, `VietnameseEngine+KeyEventDispatcher.swift`) and extract per-app language persistence into `SmartSwitchStore.swift`.
  2. Introduce `@inline(__always)` syllable bitmask computed properties on `UInt32` (`baseKey`, `isCaps`, `hasToneMark`, `toneMark`, `hasCircumflexOrStroke`, `hasHornOrBreve`, `hasAnyDiacritic`, `isAutoTone`, `isStandaloneW`) and `NSLock.withLock` to eliminate raw hex bit-twiddling and lock boilerplate.
  3. Split static data tables and environment detectors into dedicated files (`VietnameseUnicodeTable.swift`, `VietnameseDictionaryCorpus.swift`, `SystemEnvironmentDetector.swift`, `AutoWordingTypes.swift`) and split `OpenKeySwiftTests.swift` into domain-specific test suites (`OpenKeyEngineTests.swift`, `OpenKeyEventTapTests.swift`, `OpenKeyAutoWordingTests.swift`, `OpenKeyLoadTests.swift`), enforcing `< 500` lines per file across the entire Swift package while preserving all public APIs (`OKEngine*`, `EventTapCoordinator`, `AutoWordingEngine`, `VietnameseDictionary`).
- **Consequences**: Every `.swift` source and test file is under 500 lines, has a single clear responsibility, and uses readable Swift abstractions while maintaining 100% backward compatibility and sub-millisecond performance.

---

## `ADR-009` — C++ Parity for `gi-`/`qu-` Vowel Boundaries, Phonotactic Validation, Standalone-`W` Grammar Delta & Diacritic-Aware Candidate Ranking (`REQ-010`)
- **Context**: Root-cause investigation of errors around the word `"giới"` and `gi-` initial words isolated four defects across `VietnameseEngine+SpellingAndGrammar.swift`, `VietnameseEngine+KeyEventDispatcher.swift`, and `AutoWordingEngine.swift`:
  1. `findAndCalculateVowel(forGrammar: false)` scanned forward and assigned `vowelStartIndex = 1` instead of `2` (or scanning backward and breaking on `gi`/`qu` as in C++ `Engine.cpp` lines 560–585). Because `CHR(0) == KEY_G` is already a consonant, `vowelStartIndex` was already `1`, so setting `vowelStartIndex = 1` while decrementing `vowelCount -= 1` left `vowelStartIndex = 1` (`'i'` of consonant `'gi'`). This caused `giowis` (`"giới"`) to backspace 3 characters (`"iới"`) instead of 2 (`"ới"`), prevented double-`w` undo on `"giơi"`/`"giới"` (`gioiww`, `giowiw`, `giowisw`), placed tones on `'o'` instead of `'e'` in `"gièo"`/`"giéo"` (`gieof` → `"gieò"`), and caused `"giường"`/`"giướng"`/`"giười"`/`"giưới"` (`giuowngf`) to fail `insertW` (`ch0 == KEY_I, ch1 == KEY_U`).
  2. When `checkForStandaloneChar` appended a standalone `'ư'` (`extCode == 4, backspaceCount == 0, newCharCount == 1`) on `w` after `gis`, `handleCharacterKey` called `checkGrammar(deltaBackSpace: 0)` instead of `checkGrammar(deltaBackSpace: -1)`, causing `checkGrammar` to send 1 extra backspace and eat `'g'` (`giswoi` → `"iưới"`, `giswi` → `"iứi"`).
  3. `canHasEndConsonant()` ignored `_vowelCombine`, and `checkCorrectVowel()` had an impossible `isKeyS(markKey) && isKeyJ(markKey)` check, stripped `END_CONSONANT_MASK` unconditionally, and omitted the C++ `-c`/`-t` tone check and duplicate-character prefix check (`CHR(k) == CHR(k + 1)`), allowing `gisiow` to match `[KEY_O]` on `[G, I, I, O]` and output `"giiów"`.
  4. `AutoWordingEngine.computeCurrentWordCandidates` truncated `stemMatches` at 8 before sorting (excluding `"giới"` at index 13 of `"gioi"`) and stripped vowel modifiers (`ơ` → `o`), suggesting plain-`o` `["gioi", "giòi", "giói"]` when the user typed `"giơi"` or `"giới"`.
- **Decision**:
  1. Implement `findAndCalculateVowel(forGrammar:)`, `canHasEndConsonant()`, and `checkCorrectVowel(charset:i:markKey:)` with exact C++ `Engine.cpp` semantics so `gi` + vowel words set `vowelStartIndex = 2`.
  2. Pass `deltaBackSpace: -1` to `checkGrammar` in `handleCharacterKey` when `hookOutput.extCode == 4 && hookOutput.backspaceCount == 0 && hookOutput.newCharCount == 1`.
  3. Add high-frequency `gi-` words (`"giới"`, `"giỏi"`, `"giời"`, `"giờ"`, `"giữ"`, `"giữa"`, `"giúp"`, `"giải"`, `"giảm"`, `"giá"`, `"gia"`, `"giao"`, `"giàu"`, `"giấy"`) to `VietnameseDictionaryCorpus.priorityMap`, evaluate all `stemToWords[stem]` matches before sorting in `computeCurrentWordCandidates`, and prioritize candidates preserving any vowel modifiers (`ă`, `â`, `ê`, `ô`, `ơ`, `ư`, `đ`) present in `currentSyllable`.
- **Consequences**: `"giới"` and all `gi-` words compose with minimal backspaces (`bs=2` on `giowis`), support double-`w` undo, place tones accurately on `"gièo"`/`"giường"`/`"giưới"`, never eat `'g'` on `giswoi`, and rank `"giới"` and `ơ`-preserving candidates at the top of the candidate bar.

---

## `ADR-010` — GitHub Actions macOS 26 CI/CD Workflow & Portable Swift Testing Plugin Resolution (`REQ-011`)
- **Context**: Pushing to `vinhthang/OpenKey` triggered the legacy `.github/workflows/msbuild.yml` workflow targeting deleted Windows `win32` Visual Studio solutions. Furthermore, `Sources/OpenKey/macOS-Swift/Package.swift` hardcoded `-Xfrontend -plugin-path -Xfrontend /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`, which is required when `xcode-select -p` points to `/Library/Developer/CommandLineTools` locally, whereas GitHub Actions `macos-26` runners use `/Applications/Xcode*.app/Contents/Developer` with its own bundled `Testing` macro plugin (`REQ-011`).
- **Decision**:
  1. Remove `.github/workflows/msbuild.yml` and author `.github/workflows/macos-ci.yml` running on `macos-26` (`arm64`) to execute line-count verification (`< 500` lines per `.swift` file), `swift test --package-path Sources/OpenKey/macOS-Swift`, `bash Sources/OpenKey/macOS-Swift/build-app.sh`, `codesign --verify --deep --strict`, `.zip` (`ditto`) and `.dmg` (`hdiutil`) packaging, `actions/upload-artifact@v4`, and tag-triggered GitHub Releases (`softprops/action-gh-release@v2`).
  2. Update `Sources/OpenKey/macOS-Swift/Package.swift` (`import Foundation`) to pass the `CommandLineTools` `-plugin-path` flag only when `/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing` exists and `GITHUB_ACTIONS` is not set (or `DEVELOPER_DIR` is not an Xcode bundle).
  3. Update `README.md` with the GitHub Actions CI/CD badge and CI artifact / release instructions.
- **Consequences**: Every push and pull request on `vinhthang/OpenKey` automatically validates tests, line-count invariants, and `.app` bundle code-signing on `macos-26` and produces ready-to-install `OpenKeySwift-macOS-arm64.zip` and `OpenKeySwift.dmg` artifacts.
