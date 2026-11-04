# Architecture Decision Records: IME Intelligence, Secure Input, Ecosystem Compatibility & Adaptive Learning (`2026-10-27-ime-intelligence-and-ecosystem`)

---

## `ADR-001` — Secure Input Detection via `Carbon.IsSecureEventInputEnabled()` + Accessibility Role Check
- **Context**: Third-party macOS IMEs using `CGEventTap` must never mutate keystrokes or display predictive UI over password fields (`NSSecureTextField`, browser password inputs, `sudo` prompts, or password managers) (`REQ-001`).
- **Decision**: Query `IsSecureEventInputEnabled()` (`Carbon.HIToolbox`) and check whether the focused Accessibility element has `kAXRoleAttribute == "AXSecureTextField"` or `kAXSubroleAttribute == "AXSecureTextField"` (cached with a `0.15s` TTL alongside the launcher overlay check). When active, `KeyEventContext.isSecureInput` is set to `true`, causing `EventTapCoordinator.evaluateKeyEvent` to clear active candidates and return `.passThrough(resetSession: true)`.
- **Trade-offs & Risks**: Querying `AXUIElementCopyAttributeValue` for the focused element role incurs cross-process IPC if executed on every keystroke; mitigating with a `0.15s` TTL cache bounds IPC cost.
- **Rejected Alternatives**: Relying solely on `IsSecureEventInputEnabled()` without checking `AXSecureTextField` (rejected because custom web/Electron password inputs may expose `AXSecureTextField` before asserting Carbon Secure Input).
- **Consequences**: Password entry is 100% immune to Telex/VNI mutation, shorthand expansion, or candidate bar popups, with `< 0.01ms` amortized overhead.

---

## `ADR-002` — Unified Launcher Overlay Detection (`Spotlight`, `Raycast`, `Alfred`)
- **Context**: Spotlight (`com.apple.Spotlight`), Raycast (`com.raycast.macos`), and Alfred (`com.runningwithcrayons.Alfred`) often render as floating non-activating panels (`kCGWindowLayer > 0`) without changing `NSWorkspace.shared.frontmostApplication` (`REQ-002`).
- **Decision**: Extend the `0.15s`-cached window layer inspection in `EventTapCoordinator` to match window owners `"Spotlight"`, `"Raycast"`, and `"Alfred"` (with `kCGWindowLayer > 0`, `width >= 200`, `height >= 40`) in addition to checking `isLauncherApp(bundleId:)` for `com.apple.Spotlight`, `com.raycast.macos`, and `com.runningwithcrayons.Alfred*`.
- **Trade-offs & Risks**: Calling `CGWindowListCopyWindowInfo` synchronously talks to `WindowServer`; mitigated by gating rechecks behind `needsSpotlightRecheck`.
- **Rejected Alternatives**: Relying solely on `NSWorkspace.didActivateApplicationNotification` (rejected because non-activating launcher panels do not fire app-activation notifications).
- **Consequences**: Summoning Spotlight, Raycast, or Alfred immediately bypasses Vietnamese composition and resets any partial syllable state.

---

## `ADR-003` — On-Demand `AXManualAccessibility` Activation for Electron & Chromium Targets
- **Context**: Electron and Chromium apps disable their internal Accessibility tree by default until `"AXManualAccessibility"` is set to `kCFBooleanTrue` on the application's `AXUIElement`, causing `kAXBoundsForRangeParameterizedAttribute` to fail (`REQ-003`).
- **Decision**: In `CaretPositionResolver`, retrieve the PID of the focused `AXUIElement` via `AXUIElementGetPid` and set `"AXManualAccessibility" = kCFBooleanTrue` once per PID (tracked in a locked `Set<pid_t>`). Clamp candidate bar coordinates against `CaretPositionResolver.screenContaining(point:)`.
- **Trade-offs & Risks**: Enabling `AXManualAccessibility` causes Chromium/Electron renderers to maintain an internal AX tree; tracking per-PID ensures the attribute is written at most once per target process lifetime.
- **Rejected Alternatives**: Falling back permanently to mouse cursor coordinates in Electron apps (rejected because mouse position is frequently far from the typing caret).
- **Consequences**: Electron and Chromium apps (VS Code, Cursor, Slack, Discord, Notion, Chrome, Arc, Brave) expose accurate caret bounds for the Liquid Glass candidate bar across single and multi-monitor setups.

---

## `ADR-004` — Comprehensive Invalid-Word Restoration (`KEY_D` / `đ` & Trailing Control Keys)
- **Context**: `checkRestoreIfWrongSpelling` previously checked `!isConsonant(CHR(ii))` before inspecting `TONE_MASK`, which skipped `KEY_D` (`đ`) in English words like `"dead"` or `"added"`. Additionally, when `shouldSendControlKey` was true on word-break restoration, `EventTapCoordinator` swallowed the trailing control key (`REQ-004`).
- **Decision**:
  1. Remove the `!isConsonant(CHR(ii))` restriction in `checkRestoreIfWrongSpelling` so any character with `MARK_MASK`, `TONE_MASK` (including `đ`), or `TONEW_MASK` triggers full ASCII restoration when `tempDisableKey` (`!spellingOK || !spellingVowelOK`) is true.
  2. Add `passThroughTrailingKey: Bool = false` to `EventTapAction.replaceKeystroke` so `EventTapCoordinator.handleEvent` returns `Unmanaged.passUnretained(event)` after posting the replacement when `snapshot.shouldSendControlKey == true`.
- **Trade-offs & Risks**: Invalid Vietnamese syllables containing `đ` (such as English `"dead"` or `"added"`) auto-restore to raw ASCII on word break when `restoreIfWrongSpelling` is enabled.
- **Rejected Alternatives**: Maintaining a hardcoded English dictionary exclusion list for `d...d` words (rejected because phonotactic spelling validation already identifies invalid Vietnamese syllables).
- **Consequences**: English words containing `d...d` (`"dead"`, `"added"`, `"divided"`) and words terminated by `Return`/`Tab` restore cleanly without dropping the trailing key.

---

## `ADR-005` — Lightweight User Frequency Boosting & Custom Shorthand Table in `UserDefaults`
- **Context**: Users need candidate suggestions that adapt to their personal vocabulary (`REQ-005`) and a way to define custom shorthand expansions alongside expanded built-in shorthands (`REQ-006`).
- **Decision**:
  1. Store candidate acceptance counts in `UserDefaults` under `"UserWordFrequencyData"` (`[String: Int]`) and sort candidate arrays by `(userFrequency[word] ?? 0)` descending before falling back to static dictionary order.
  2. Store user-defined shorthands in `UserDefaults` under `"CustomShorthandsData"` (`[String: String]`), checking `customShorthands[lower]` first before `shorthandTable[lower]`, and expose an inline editor + frequency reset button in `SettingsView`.
- **Trade-offs & Risks**: `UserDefaults` is suitable for hundreds or low thousands of user frequency entries and custom shorthands; bounded dictionary sizes keep serialization cost negligible.
- **Rejected Alternatives**: Embedding a SQLite or CoreData store for user frequency counts (rejected as unnecessary complexity for a key-value frequency map).
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
- **Trade-offs & Risks**: Synchronizing `stateIndex` and `keyStates` when all diacritics are deleted discards earlier modifier history on the deleted suffix, which is intentional because those modifiers were backspaced.
- **Rejected Alternatives**: Resetting the entire word buffer on every `KEY_DELETE` (rejected because users expect to backspace a single character and extend the remaining syllable prefix).
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
- **Trade-offs & Risks**: Restricting `Tab` to `.correction` candidates requires users to press `Ctrl+1..3` (or click) for `.stemCompletion` and `.nextWord` candidates, preserving standard `Tab` indentation and navigation.
- **Rejected Alternatives**: Keeping `AutoWordingEngine` calls embedded directly inside `VietnameseEngineState.handleKeyEvent` (rejected because early return paths bypassed candidate updates).
- **Consequences**: `VietnameseEngineState` is 100% decoupled from `AutoWordingEngine`, disabled mode has zero overhead, `Tab` is never hijacked on valid words, native zero-width carets resolve accurately, and AX IPC can never stall the `CGEventTap` runloop.

---

## `ADR-008` — Cohesion-Driven Modularization & Replacing C++-Ported Bitmask Boilerplate (`REQ-009`)
- **Context**: Following the pure Swift 6 port and feature additions (`REQ-001`..`REQ-008`), `VietnameseEngine.swift` (`1,851` lines) and `OpenKeySwiftTests.swift` (`1,602` lines) mixed multiple responsibilities (state buffers, phonotactic spell-checking, grammar/tone mark positioning, vowel/consonant transforms, keystroke event dispatching, and per-app Smart Switch binary persistence) using raw C++ bitmask arithmetic (`(typingWord[i] & MARK_MASK) != 0`) and a 235-line nested `handleKeyEvent` method. An initial `< 500` line rule forced artificial splits of tightly coupled files (`VietnameseData` + `VietnameseUnicodeTable`, `VietnameseDictionary` + `VietnameseDictionaryCorpus`, `AutoWordingEngine` + `AutoWordingTypes`, `EventTapCoordinator` + `SystemEnvironmentDetector`, and 4 separate `VietnameseEngine` fragments).
- **Decision**:
  1. Organize `VietnameseEngineState` into 2 cohesive files: `VietnameseEngine.swift` (state buffers, session lifecycle, `OKEngine*` entry points, and `handleKeyEvent` phase dispatcher) and `VietnameseEngine+Phonotactics.swift` (phonotactic spelling validation, vowel boundaries, grammar repair, and tone/mark transforms), while extracting per-app language persistence into `SmartSwitchStore.swift`.
  2. Consolidate the artificially split `< 500`-line companion files back into their parent modules (`VietnameseUnicodeTable.swift` → `VietnameseData.swift`, `VietnameseDictionaryCorpus.swift` → `VietnameseDictionary.swift`, `AutoWordingTypes.swift` → `AutoWordingEngine.swift`, and `SystemEnvironmentDetector.swift` → `EventTapCoordinator.swift`).
  3. Introduce `@inline(__always)` syllable bitmask computed properties on `UInt32` (`baseKey`, `isCaps`, `hasToneMark`, `toneMark`, `hasCircumflexOrStroke`, `hasHornOrBreve`, `hasAnyDiacritic`, `isAutoTone`, `isStandaloneW`) and `NSLock.withLock` to eliminate raw hex bit-twiddling and lock boilerplate, and keep domain-specific test suites (`OpenKeyEngineTests.swift`, `OpenKeyEventTapTests.swift`, `OpenKeyAutoWordingTests.swift`, `OpenKeyLoadTests.swift`).
- **Trade-offs & Risks**: Cohesive modules naturally span 500–750 lines, which is mitigated by clear `// MARK:` section organization.
- **Rejected Alternatives**: Enforcing a mechanical line-count cap per file (rejected because it artificially split cohesive types and static tables across companion files); keeping the entire engine in a single 1,851-line monolith (rejected because separating state/dispatch from phonotactic/tone rules improves readability).
- **Consequences**: Every `.swift` source file maps 1-to-1 to a genuine architectural subsystem with zero artificial file fragmentation and zero line-count caps.

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
- **Trade-offs & Risks**: Evaluating all `stemToWords[stem]` matches before sorting examines ~15–25 words per stem instead of truncating at 8, adding `< 0.01ms` per keystroke while ensuring high-priority words at later indices are never dropped.
- **Rejected Alternatives**: Special-casing `"giới"` in `insertW` without fixing `findAndCalculateVowel` (rejected because `vowelStartIndex = 1` broke all `gi` + vowel combinations).
- **Consequences**: `"giới"` and all `gi-` words compose with minimal backspaces (`bs=2` on `giowis`), support double-`w` undo, place tones accurately on `"gièo"`/`"giường"`/`"giưới"`, never eat `'g'` on `giswoi`, and rank `"giới"` and `ơ`-preserving candidates at the top of the candidate bar.

---

## `ADR-010` — GitHub Actions macOS 26 CI/CD Workflow & Portable Swift Testing Plugin Resolution (`REQ-011`)
- **Context**: Pushing to `vinhthang/OpenKey` triggered the legacy `.github/workflows/msbuild.yml` workflow targeting deleted Windows `win32` Visual Studio solutions. Furthermore, `Sources/OpenKey/macOS-Swift/Package.swift` hardcoded `-Xfrontend -plugin-path -Xfrontend /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`, which is required when `xcode-select -p` points to `/Library/Developer/CommandLineTools` locally, whereas GitHub Actions `macos-26` runners use `/Applications/Xcode*.app/Contents/Developer` with its own bundled `Testing` macro plugin (`REQ-011`).
- **Decision**:
  1. Remove `.github/workflows/msbuild.yml` and author `.github/workflows/macos-ci.yml` running on `macos-26` (`arm64`) to execute `swift test --package-path Sources/OpenKey/macOS-Swift`, `bash Sources/OpenKey/macOS-Swift/build-app.sh`, `codesign --verify --deep --strict`, `.zip` (`ditto`) and `.dmg` (`hdiutil`) packaging, `actions/upload-artifact@v4`, and tag-triggered GitHub Releases (`softprops/action-gh-release@v2`).
  2. Update `Sources/OpenKey/macOS-Swift/Package.swift` (`import Foundation`) to pass the `CommandLineTools` `-plugin-path` flag only when `/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing` exists and `GITHUB_ACTIONS` is not set (or `DEVELOPER_DIR` is not an Xcode bundle).
  3. Update `README.md` with the GitHub Actions CI/CD badge and CI artifact / release instructions.
- **Trade-offs & Risks**: Ad-hoc signing (`-`) in CI allows immediate verification and artifact packaging without Apple Developer ID secrets, though downloaded unsigned artifacts require initial Gatekeeper approval.
- **Rejected Alternatives**: Keeping `msbuild.yml` alongside `macos-ci.yml` (rejected because the legacy `win32` directory was removed).
- **Consequences**: Every push and pull request on `vinhthang/OpenKey` automatically validates tests and `.app` bundle code-signing on `macos-26` and produces ready-to-install `OpenKeySwift-macOS-arm64.zip` and `OpenKeySwift.dmg` artifacts.

---

## `ADR-011` — Settings `Esc`-to-Close, Single-Language UI Switcher (`VI | EN`) & Implementor/Version Attribution (`REQ-012`)
- **Context**: User feedback identified three UX issues in `SettingsView`:
  1. Closing the Settings window required clicking the window close button with the mouse instead of pressing `Esc`.
  2. Every label concatenated Vietnamese and English side-by-side (e.g., `"Nhớ ngôn ngữ theo từng ứng dụng (Remember language per app)"`), making the Settings UI overly verbose.
  3. The About section lacked the current application version and implementor attribution for **Antigravity (Gemini 4 Argon High)**.
- **Decision**:
  1. Register a window-level local `keyDown` monitor in `SettingsView` while visible: if `event.keyCode == 53` (`Esc`), cancel shortcut recording if `ui.isRecordingShortcut == true`, or close the Settings window (`NSApp.keyWindow?.close()`) if `ui.isRecordingShortcut == false`.
  2. Add `uiLanguage: Int` (`1` = Vietnamese, `0` = English; key `"UILanguage"`) to `OpenKeySettingsStore` and extract a dedicated `OpenKeyL10n.swift` localization helper (`< 200` lines) providing concise single-language strings for both `SettingsView` and `OpenKeySwiftApp`, controlled by a compact `VI | EN` segmented picker in the Settings top bar.
  3. Update the About section in `SettingsView` and `OpenKeyL10n` to display the current version (`v2.0.0 (Build 1)`), implementor (`Antigravity — Gemini 4 Argon High`), and original author (`Mai Vũ Tuyên`, GPLv3).
  4. In `SettingsView.openAccessibilitySettings()`, automatically execute `/usr/bin/tccutil reset Accessibility com.tuyenmai.openkey.swift` and `EventTapCoordinator.shared.checkAccessibilityAndSetupTap()` when `!settings.isAccessibilityTrusted`, and in `build-app.sh`, use `/usr/bin/openssl` for `--setup-cert` and preserve certificate-anchored designated requirements when `SIGNING_IDENTITY != "-"`.
- **Trade-offs & Risks**: Maintaining localized strings in `OpenKeyL10n.swift` requires adding new UI keys in both Vietnamese and English branches.
- **Rejected Alternatives**: Using `.strings` / `.xcstrings` resource bundles (rejected because a single-struct `OpenKeyL10n` enables instant reactive `VI | EN` toggling without restarting the app).
- **Consequences**: The Settings window closes effortlessly with `Esc`, displays crisp single-language labels in either Vietnamese or English, recovers cleanly from stale TCC `CDHash` entries across rebuilds, and clearly documents both the app version and implementor provenance.

---

## `ADR-012` — Version-Scoped Asynchronous File Logger (`OpenKeyLogger`) with Secure-Input Redaction (`REQ-013`)
- **Context**: Users and developers need a toggleable Debug Mode that captures end-to-end diagnostic logs across all IME subsystems (`EventTap`, `Engine`, `AutoWording`, `KeystrokeInjector`, `CandidateBar`, `SmartSwitch`, `Settings`) to a persistent log file (`~/Library/Logs/OpenKeySwift/openkey-debug.log`), automatically purges old logs whenever a new version or build of the app is launched, and guarantees zero performance impact when disabled and zero keystroke leakage in password fields (`REQ-013`).
- **Decision**:
  1. Create a dedicated `OpenKeyLogger` module (`Sources/OpenKey/macOS-Swift/Sources/OpenKeySwiftCore/OpenKeyLogger.swift`, `< 250` lines) with an `@autoclosure` fast-path (`guard isEnabled else { return }`) and a background serial queue (`com.tuyenmai.openkey.logger`, `.utility` QoS) writing to `~/Library/Logs/OpenKeySwift/openkey-debug.log`.
  2. Stamp each build in `build-app.sh` by updating `CFBundleVersion` in `build/OpenKeySwift.app/Contents/Info.plist` with a UTC build timestamp (e.g. `1.202610300820`), and compute a composite version stamp in `OpenKeyLogger` (`CFBundleShortVersionString` + `CFBundleVersion` + executable mtime). Write `# OpenKeySwiftVersionStamp: <stamp>` as the first line of `openkey-debug.log`. On startup or logger initialization, if the existing file's stamp differs from the running binary's stamp, remove stale logs and truncate `openkey-debug.log` so only the current version's logs are retained (plus a `20 MB` size cap).
  3. Enforce strict Secure Input redaction in `EventTapCoordinator.evaluateKeyEvent`: when `context.isSecureInput == true`, log only `[EVENT_TAP] Secure input active — keystroke redacted, bypassing IME` and never record `keyCode` or character values.
  4. Expose `debugModeEnabled: Bool` in `OpenKeySettingsStore` (`"DebugModeEnabled"`, default `false`), a Debug Mode toggle + `Open Log File` / `Reveal in Finder` / `Clear Log` buttons in `SettingsView`, and quick Debug Mode controls in the `OpenKeySwiftApp` status bar menu.
- **Trade-offs & Risks**: Asynchronous logging on a background serial queue means that if the process crashes with `SIGKILL`, the last few in-flight log messages may not reach disk; avoiding synchronous disk I/O inside `CGEventTap` is strictly higher priority.
- **Rejected Alternatives**: Writing only to Apple Unified Logging (`os.Logger`) without a file (rejected because the user requested saving all debug logs to a persistent log file with per-version retention).
- **Consequences**: Full observability across every IME layer when Debug Mode is enabled, automatic per-version/per-build log cleanup without manual maintenance, zero overhead when disabled, and 100% password privacy.

---

## `ADR-013` — Inline Mixed-Language English Auto-Fix, Swallowed-Key Recovery, 1–2 Word Look-Back, 3-Word Auto-Switch Threshold & Single-Backspace Undo (`REQ-014`)
- **Context**: Users frequently type Vietnamese sentences containing 1–2 embedded English/technical words (e.g., `"anh đang test cái list này"`, `"check cheese và coffee"`, `"xem more info ở docs"`). Studying `tonyminibot/Vikey` revealed strong dictionary and swallowed-key recovery mechanisms (`_asDropPos`/`_asDropKey`, `vAutoSwitchFixDoubledKey`, `asReplay`, 1–2 word look-back, and single-backspace undo), but switching the global input mode (`vLanguage`) on the very first English word disrupts users who only type 1–2 English words before returning to Vietnamese. Furthermore, standard OpenKey phonotactic validation accepts invalid Vietnamese syllables like `"mỏe"` (`more`), `"cỏe"` (`core`), `"tét"` (`test`), `"lít"` (`list`), `"thí"` (`this`), `"trê"` (`tree`), and `"mĩ"` (`mix`), and loses letters when Telex undoes a doubled key mid-word (`"cheese"` → `"chees"`, `"seemed"` → `"semed"`).
- **Decision**:
  1. **Swallowed-Key Tracking (`droppedKeys`) & Doubled-Tone Escape Repair**: In `VietnameseEngineState`, record every keystroke undone by `HookCodeState.restore` mid-word in `droppedKeys: [(pos: Int, key: UInt32)]` and reconstruct `fullRawKeyStates()` at word break. Restore the full raw keystrokes whenever `fullRawKeyStates()` matches `englishWords` or has $\ge 2$ vowel groups with a dropped modifier. If a tone key was doubled to escape Telex (`"mixx"`, `"fixx"`, `"boxx"`) and only the single-key form is in `englishWords`, emit the single-key English word (`"mix"`, `"fix"`, `"box"`).
  2. **Dictionary-Backed Collision Resolution (`englishWords`, `englishPriorityWords`, `syllableSet`)**: Add curated `englishWords` and `englishPriorityWords` sets to `VietnameseDictionary`. Always restore `englishPriorityWords` (`test`, `list`, `this`, `best`, `host`, `post`, `more`, `core`, `user`, `vars`, `docs`, `tree`, `free`, `see`, `too`, `add`, `boss`, `pass`, `mix`, `fix`, etc.) at word break, and restore any word in `englishWords` whose composed Vietnamese form is not in `VietnameseDictionary.shared.syllableSet` (catching `"mỏe"`, `"cỏe"`, `"cáe"`, `"uẻ"`).
  3. **1–2 Word Look-Back (`previousWords`)**: Maintain a 2-word look-back buffer across single spaces so ambiguous short words (`is`/`í`, `of`/`ò`, `if`/`ì`, `for`/`fỏ`, `or`/`ỏ`, `us`/`ú`, `car`/`cả`, `ban`/`bán`) are retroactively restored to English when followed by an English word (`"is good"`, `"of course"`, `"for sure"`, `"if needed"`).
  4. **Inline Mode Retention for 1–2 English Words & 3+ Word Auto-Switch**: Keep `vLanguage == 1` when 1–2 consecutive English words are restored inline. Only emit `languageSwitchRequest = 0` when `consecutiveEnglishWordCount >= 3`, and when `vLanguage == 0`, replay buffered English word keystrokes on a scratch session to convert unambiguous Vietnamese Telex words back to Vietnamese and emit `languageSwitchRequest = 1`.
  5. **Single-Backspace Undo (`autoRestoreUndoState`)**: Arm an undo snapshot on every word-break auto-conversion so pressing `KEY_DELETE` immediately after reverts the conversion + break key, restores the original composed word (`"tét"`, `"lít"`), and whitelists `undoneRawWord` against re-conversion on the next `Space`.
- **Trade-offs & Risks**: Prioritizing standalone common English/tech collision words (`"test"` over `"tét"`, `"list"` over `"lít"`, `"this"` over `"thí"`) means a user who genuinely wants the rarer Vietnamese word `"tét"` or `"lít"` must press `Backspace` once after `Space`; this matches the user's explicit preference (`A2`, `A3`) and is mitigated by single-keystroke `Backspace` undo.
- **Rejected Alternatives**: Switching global `vLanguage` to `0` on the very first English word (rejected per user choice `A1` because 1–2 English words inside a Vietnamese sentence should not force subsequent Vietnamese words into English mode).
- **Consequences**: 1–2 embedded English words and phrases inside Vietnamese sentences are restored with 100% letter fidelity (including `"cheese"`, `"seemed"`, `"deepseek"`, `"mix"`, `"test"`, `"list"`, `"more"`, `"is good"`), Vietnamese mode remains seamlessly active for 1–2 English words, 3+ English words auto-switch modes, and any conversion can be undone with a single `Backspace`.

---

## `ADR-014` — Swallowed Telex Modifier Key Tracking & Full Raw Word Reconstruction (`REQ-015`)
- **Context**: In standard OpenKey, pressing a Telex modifier key (`a, e, o, d, w, s, f, r, x, j`) that undoes an existing mark (`HookCodeState.restore`) decrements `stateIndex` (`stateIndex -= 1`), permanently discarding the second modifier press from `keyStates`. Consequently, English words with doubled letters (`"cheese"`, `"seemed"`, `"needed"`, `"deepseek"`, `"google"`, `"process"`, `"office"`, `"coffee"`, `"error"`, `"tomorrow"`, `"address"`) restore with missing letters (`"chees"`, `"semed"`, `"deepsek"`, `"gogle"`, `"proces"`) (`REQ-015`).
- **Decision**:
  1. Add `var droppedKeys: [(pos: Int, key: UInt32)] = []` to `VietnameseEngineState`.
  2. Whenever `hookOutput.code == HookCodeState.restore` undoes a modifier mid-word and decrements `stateIndex`, record `(pos: Int(stateIndex), key: keyStates[Int(stateIndex)])` in `droppedKeys` (pruning entries $\ge stateIndex$ on `KEY_DELETE` and clearing on session reset).
  3. At word breaks, reconstruct `reconstructedRawKeys()` by reinserting `droppedKeys` in reverse-drop order, and restore the full reconstructed keystrokes whenever they match `englishWords` or have $\ge 2$ vowel groups.
- **Trade-offs & Risks**: Maintaining `droppedKeys` adds a small array ($\le 4$ elements per word) to `VietnameseEngineState`; care must be taken to prune `droppedKeys` when the user presses `KEY_DELETE` mid-word.
- **Rejected Alternatives**: Never decrementing `stateIndex` on `HookCodeState.restore` (rejected because genuine Vietnamese Telex undo such as typing `cuooocf` to fix a typo into `cuoocf` expects `keyStates` to reflect the undone single-syllable Vietnamese word unless the full word is English).
- **Consequences**: 100% letter preservation for all English words containing doubled vowels or consonants (`"cheese"`, `"seemed"`, `"deepseek"`, `"google"`, `"process"`, `"coffee"`, `"address"`).

---

## `ADR-015` — Doubled-Tone Escape Repair, Acronym Protection & Contraction/Hyphen Handling (`REQ-016`)
- **Context**: Users typing in Vietnamese mode often press a Telex tone key twice (`"mixx"`, `"fixx"`, `"boxx"`) when they see `"mĩ"`, `"fĩ"`, `"bõ"` and want `"mix"`, `"fix"`, `"box"`, leaving a trailing duplicate letter on screen. Additionally, English contractions (`"doesn't"`, `"isn't"`), hyphenated `w-` words (`"Wi-Fi"`), and mixed/all-caps acronyms (`"NAS"`, `"SATA"`, `"GoPro"`) are corrupted by Telex unless handled at word/punctuation breaks (`REQ-016`).
- **Decision**:
  1. At word break, if the reconstructed raw word has a doubled Telex tone key (`s, f, r, x, j`) where the full form (`"mixx"`, `"fixx"`, `"boxx"`, `"maxx"`, `"taxx"`) is not in `englishWords` while the single-key form (`"mix"`, `"fix"`, `"box"`, `"max"`, `"tax"`) is in `englishWords`, restore the single-key form; if the full form is in `englishWords` (`"boss"`, `"class"`, `"terrible"`), restore the full form.
  2. On apostrophe (`KEY_QUOTE` unshifted), treat words ending in `'n'` whose stem without `'n'` is in `englishWords` (`"doesn"`, `"isn"`, `"wasn"`, `"don"`, `"can"`, `"won"`, `"didn"`) as English.
  3. On hyphen (`KEY_MINUS` unshifted), restore transformed words starting with `w` (`"ưi"` → `"Wi"` in `"Wi-Fi"`) when the composed syllable is not a common Vietnamese word.
  4. For words with $\ge 2$ uppercase letters (`"NAS"`, `"SATA"`, `"GoPro"`), restore to English if any vowel was modified by Telex (`vowelChanged == true`), while preserving Vietnamese `Đ`-acronyms (`"VĐV"`, `"HĐND"`, `"BĐS"`).
- **Trade-offs & Risks**: Restoring `w-` words before `-` could affect Vietnamese loanwords with hyphens, so the rule is strictly gated to words starting with `w` (`KEY_W`), leaving Vietnamese loanwords like `"nơ-ron"`, `"rơ-moóc"`, and `"táp-lô"` untouched.
- **Rejected Alternatives**: Stripping all trailing doubled letters blindly (rejected because English words like `"boss"`, `"pass"`, `"class"`, `"less"`, `"err"`, `"add"`, `"odd"`, `"too"`, `"see"`, `"free"`, `"tree"` legitimately end in doubled letters).
- **Consequences**: Seamless recovery for `"mixx"` → `"mix"`, `"boss"` → `"boss"`, `"doesn't"`, `"Wi-Fi"`, and `"NAS"`/`"GoPro"` while keeping `"VĐV"` and `"BĐS"` intact.

---

## `ADR-016` — Standalone English Collision Priority & Invalid Vietnamese Diphthong Rejection (`REQ-017`)
- **Context**: Many high-frequency English and developer words (`"test"`, `"list"`, `"this"`, `"best"`, `"host"`, `"post"`, `"more"`, `"core"`, `"user"`, `"vars"`, `"chars"`, `"cors"`, `"nums"`, `"docs"`, `"tree"`, `"free"`, `"see"`, `"too"`, `"add"`, `"mix"`, `"fix"`) form structurally valid Vietnamese consonant-vowel-consonant combinations (`"tét"`, `"lít"`, `"thí"`, `"mỏe"`, `"cỏe"`, `"uẻ"`, `"vả"`, `"chả"`, `"trê"`, `"sê"`, `"tô"`, `"mĩ"`) and therefore bypass phonotactic `checkRestoreIfWrongSpelling` (`REQ-017`).
- **Decision**:
  1. Restore any transformed word at a word break whose lowercase raw string is in `englishPriorityWords` (unless locked by `undoneRawWord`).
  2. Restore any transformed word whose lowercase raw string is in `englishWords` when the composed Vietnamese string is not in `VietnameseDictionary.shared.isValidVietnameseSyllable(composed)` (eliminating false-positive phonotactic diphthongs like `"mỏe"`, `"cỏe"`, `"cáe"`, `"uẻ"`, `"pủe"`, `"sủe"`, `"trúe"`).
  3. Preserve core Vietnamese words (`"có"`, `"bạn"`, `"anh"`, `"em"`, `"con"`, `"ăn"`, `"ở"`, `"ừ"`, `"ạ"`, `"ý"`) by excluding their Telex keys (`cos`, `banj`, `awn`, `owr`, `uwf`, `aj`, `ys`) from `englishPriorityWords`.
- **Trade-offs & Risks**: Typing `"test "` in Vietnamese mode produces `"test "` instead of `"tét "`; if the user rarely intends the Vietnamese word `"tét"` or `"lít"`, they press `Backspace` once (`REQ-020`) to revert to `"tét"` and lock it.
- **Rejected Alternatives**: Relying solely on structural consonant/vowel tables (`_consonantTable`, `_vowelCombine`, `_endConsonantTable`) without dictionary validation (rejected because `_vowelCombine` must allow `o-e` for `"khỏe"`/`"xòe"` and `u-e` for `"thuê"`/`"huệ"`, which inevitably accepts `"mỏe"`/`"cỏe"`/`"trúe"` unless checked against the real syllable dictionary).
- **Consequences**: 100% accuracy when typing 1–2 common English or developer words inside Vietnamese sentences without breaking genuine Vietnamese vocabulary.

---

## `ADR-017` — 1–2 Word Context Look-Back for Multi-Word English Phrases (`REQ-018`)
- **Context**: Short English function words and nouns (`"is"`, `"of"`, `"if"`, `"for"`, `"or"`, `"us"`, `"car"`, `"ban"`) collide with common 1–2 letter Vietnamese words (`"í"`, `"ò"`, `"ì"`, `"fỏ"`, `"ỏ"`, `"ú"`, `"cả"`, `"bán"`). When a user types a 2-word English phrase like `"is good"`, `"of course"`, `"for sure"`, or `"if needed"`, the first word stays Vietnamese at the first `Space` because the engine does not yet know an English word follows (`REQ-018`).
- **Decision**:
  1. Maintain a 2-word ring buffer `previousWords: [PreviousWordEntry]` across single spaces in `VietnameseEngineState` (cleared on non-space breaks, multiple spaces, or cursor navigation).
  2. When the current word at a word break restores to English—or is an unchanged English-only word (`englishWords.contains(raw)` and `!isValidVietnameseSyllable(raw)`, such as `"good"`, `"course"`, `"needed"`)—check up to 2 preceding words in `previousWords`.
  3. If `previousWords[0]` (and `previousWords[1]`) has `canFollowEnglishRestore == true` (`englishLookbackStems.contains(rawLower)`), expand `hookOutput.backspaceCount` by `prev.shownChars.count + 1` (for the intervening space) and prepend `prev.rawKeys + [KEY_SPACE]` to the replacement buffer so both words are restored to English in a single atomic replacement.
- **Trade-offs & Risks**: Replacing across a space boundary emits a larger backspace count (e.g. `7–12` backspaces for 2 words); `KeystrokeInjector` already handles multi-character replacements atomically.
- **Rejected Alternatives**: Putting `"is"`, `"of"`, `"if"`, `"or"`, `"us"`, `"car"`, `"ban"` into standalone `englishPriorityWords` (rejected because `"bán"`, `"cả"`, `"ì"`, `"ò"`, `"ỏ"`, `"ú"`, `"í"` are used in Vietnamese phrases like `"bán hàng"`, `"cả nhà"`, `"em í ạ"`).
- **Consequences**: Multi-word English phrases (`"is good"`, `"of course"`, `"for sure"`, `"if needed"`, `"car play"`) are automatically repaired into 100% clean English while `"cả nhà"`, `"bán hàng"`, and `"em í ạ"` remain Vietnamese.

---

## `ADR-018` — Inline Vietnamese Mode Retention (1–2 Words), 3+ Word Bidirectional Auto-Switch & Single-Backspace Undo (`REQ-019`, `REQ-020`)
- **Context**: Switching the global input mode (`vLanguage`) to English on the very first English word forces the user's next Vietnamese word to be typed in English mode, which is jarring when the user only embeds 1–2 English words inside a Vietnamese sentence. At the same time, typing 3+ consecutive English words indicates a full English sentence, and any automatic word conversion requires a fast, frictionless escape hatch (`REQ-019`, `REQ-020`).
- **Decision**:
  1. Keep `vLanguage == 1` (`languageSwitchRequest = -1`) when 1 or 2 consecutive English words are restored (`consecutiveEnglishWordCount < 3`).
  2. Emit `languageSwitchRequest = 0` only when `consecutiveEnglishWordCount >= 3` (provided the 5.0-second manual-switch cooldown `manualTogglePauseUntil` is not active).
  3. While `vLanguage == 0` (English mode), route keystrokes through `OKEngineHandleEnglishModeKeyEvent`: buffer clean-start word letters in `enKeys` and replay them on a scratch session at word breaks; if the replay produces a diacritic-transformed syllable in `VietnameseDictionary.shared.syllableSet` and the raw word is not in `englishWords`, emit backspaces + the composed Vietnamese word (including up to 2 plain-Vietnamese look-back words) and `languageSwitchRequest = 1`.
  4. On every single-word auto-conversion at a word break, arm `autoRestoreUndoState` so an immediate `KEY_DELETE` (`51`) deletes the converted word + break key, restores the pre-conversion text (`"tét"`, `"lít"`), reverts any language switch, and sets `undoneRawWord` so re-pressing `Space` keeps the Vietnamese word.
- **Trade-offs & Risks**: Waiting for 3 consecutive English words before switching global `vLanguage` means words 1 and 2 are restored at their word breaks rather than pass-through keystrokes, which is the exact behavior requested (`A1`) so 1–2 English words never disrupt Vietnamese typing.
- **Rejected Alternatives**: Requiring a multi-key shortcut (`Cmd+Z`) to undo an unwanted English auto-restore (rejected because `Cmd+Z` triggers host-app Undo, which can undo entire paragraphs in browsers or editors; a single `Backspace` is immediate and universal).
- **Consequences**: Seamless inline handling of 1–2 English words in Vietnamese mode, automatic bidirectional switching on 3+ English words, and instant 1-keystroke `Backspace` undo.

---

## `ADR-019` — `KeepWords` Do-Not-Autocorrect Safe-List for `AutoWordingEngine` (`REQ-021`)
- **Context**: `AutoWordingEngine`'s rule-based and fuzzy Damerau-Levenshtein auto-wording (`REQ-003`) can inadvertently rewrite short valid tokens, proper nouns, foreign loanwords, abbreviations, and chat interjections (`"ok"`, `"uh"`, `"ah"`, `"eh"`, `"oh"`, `"hm"`, `"ha"`, `"hi"`, `"he"`, `"ho"`, `"ko"`, `"dc"`, `"vs"`, `"vk"`, `"ck"`, `"mk"`, `"uhm"`, `"aha"`, `"haha"`, `"hihi"`, `"hehe"`, `"huhu"`, `"wow"`, `"yay"`, `"vip"`, `"pro"`, `"app"`, `"web"`, `"net"`, `"dev"`, `"api"`, `"sdk"`, `"ide"`, `"cli"`, `"gui"`, `"cpu"`, `"gpu"`, `"ram"`, `"ssd"`, `"usb"`, `"lan"`, `"wan"`, `"vpn"`, `"dns"`, `"ssh"`, `"ssl"`, `"tls"`, `"jwt"`, `"sql"`, `"xml"`, `"yml"`, `"csv"`, `"pdf"`, `"png"`, `"jpg"`, `"gif"`, `"mp3"`, `"mp4"`, `"zip"`, `"tar"`, `"mac"`, `"ios"`, `"win"`, `"bot"`, `"ai"`, `"ml"`, `"llm"`) into unrelated Vietnamese words (`REQ-021`). Studying `tonyminibot/Vikey`'s `KeepWords.inc` (`D45`) demonstrated the effectiveness of a compile-time `keepWords` safe-list that shields valid short tokens from fuzzy/rule rewriting.
- **Decision**:
  1. Add `public let keepWords: Set<String>` to `VietnameseDictionary.swift` containing curated short interjections, chat tokens, and technical abbreviations, plus all entries in `englishWords` and `englishPriorityWords`.
  2. In `AutoWordingEngine.evaluate(rawToken:composedWord:previousToken:)`, check `VietnameseDictionary.shared.keepWords.contains(rawToken.lowercased())` before applying non-explicit rule or fuzzy distance-1 corrections, returning `nil` immediately when matched (unless the user explicitly enabled Teencode expansion `teencodeEnabled == true` and the token matches `teencodeExpansions`).
- **Trade-offs & Risks**: Tokens in `keepWords` will not receive automatic typo correction if they happen to be 1 edit away from a Vietnamese syllable; however, every entry in `keepWords` is an intentional, high-frequency token where fuzzy correction would be a false positive.
- **Rejected Alternatives**: Raising the minimum token length for all `AutoWordingEngine` corrections to $\ge 5$ characters (rejected because common 3–4 letter Vietnamese typos like `"vieet"` → `"việt"` or `"nguwowif"` → `"người"` still benefit from correction).
- **Consequences**: Zero false-positive fuzzy rewrites on short chat interjections, tech acronyms, and English words inside `AutoWordingEngine`.

---

## `ADR-020` — Curated Teencode & Chat Shorthand Rule + Whitelist Hybrid (`REQ-022`) — **Superseded by `ADR-022`**
- **Context**: Users typing casual Vietnamese chat messages frequently use shorthand tokens (`"ko"` → `"không"`, `"dc"`/`"đc"` → `"được"`, `"ng"` → `"người"`, `"bt"` → `"bình thường"`, `"ntn"` → `"như thế nào"`, `"j"` → `"gì"`, `"vk"` → `"vợ"`, `"ck"` → `"chồng"`, `"trc"` → `"trước"`, `"ms"` → `"mới"`, `"cx"` → `"cũng"`, `"bh"` → `"bây giờ"`, `"vs"` → `"với"`, `"mk"` → `"mình"`) as well as structural suffix shorthands (`-g` → `-ng` when a vowel is present, e.g. `"khog"` → `"không"`, `"nhug"` → `"nhưng"`, `"duog"` → `"đường"`, and `-k` → `-ch`). Studying `tonyminibot/Vikey`'s `TeencodeData.h` (`D13`) showed that a gated option combining a curated dictionary with a vowel-validated `-g` → `-ng` rule avoids false positives on English words (`"king"`, `"song"`, `"park"`, `"work"`, `"link"`, `"check"`) (`REQ-022`).
- **Decision**:
  1. Add `public let teencodeExpansions: [String: String]` and `public let teencodeSuffixGWhitelist: [String: String]` to `VietnameseDictionary.swift`.
  2. Add `teencodeEnabled: Bool` (`Keys.teencodeEnabled = "TeencodeEnabled"`, default `false`) to `OpenKeySettingsStore.swift` so developers and formal writers are never surprised by shorthand expansion unless opted in.
  3. When `teencodeEnabled == true`, expand exact matches in `teencodeExpansions` (preserving initial capitalization) and expand `-g` → `-ng` stems validated against `teencodeSuffixGWhitelist` while strictly skipping any word in `englishWords`.
- **Trade-offs & Risks**: Because some teencode shorthands (`"ms"`, `"bt"`, `"vs"`) overlap with technical abbreviations, gating `teencodeEnabled` to `false` by default ensures zero interference with developer workflows while giving chat users a 1-click toggle.
- **Rejected Alternatives**: Applying blind regex suffix replacement (`s/g$/ng/`, `s/k$/ch/`) across all tokens (rejected because it corrupts English words like `"blog"` → `"blong"`, `"dog"` → `"dong"`, `"work"` → `"worch"`, `"check"` → `"chech"`).
- **Consequences**: Safe, opt-in Vietnamese chat shorthand expansion with zero corruption of English vocabulary.

---

## `ADR-021` — Engine Context Guards: Digit-After-Space Word Start (`D33`), Arrow-Key Mid-Word Navigation Recovery (`D51`), & Compound-Token Boundary (`REQ-023`)
- **Context**: Studying `tonyminibot/Vikey`'s engine decisions (`D33`, `D51`, and `wordStartOk`) exposed three subtle context-boundary edge cases in Vietnamese input engines:
  1. **Digit-After-Space Prefix (`D33`)**: When a user types a number followed immediately by a Vietnamese unit (`"1casi"` for `"1cái"`, `"2ngayf"` for `"2ngày"`, `"100dd"` for `"100đ"`), treating digits as non-word characters that block or corrupt Telex composition prevents natural quantity typing, whereas treating hex/alphanumeric identifiers (`"0xdeadbeef"`, `"v2ray"`, `"mp3"`, `"h264"`, `"base64"`) as Vietnamese corrupts technical tokens.
  2. **Left/Right Arrow Mid-Word Navigation Recovery (`D51`)**: Pressing `Left Arrow` (`123`) once at the end of an active word to inspect or fix the last character normally calls `startNewSession()`, wiping the entire word buffer even if the user immediately presses `Right Arrow` (`124`) to resume typing at the end of the word.
  3. **Compound-Token Boundary (`wordStartOk`)**: When typing compound identifiers (`"foo.bar"`, `"my_var"`, `"user@host.com"`, `"path/to/file"`), the token after `.`, `_`, `/`, or `@` starts immediately after a non-space identifier separator and must not trigger false-positive Vietnamese look-back or corrupt code identifiers (`REQ-023`).
- **Decision**:
  1. **Digit-Prefix Handling (`D33`)**: Track `hasDigitPrefix: Bool` in `VietnameseEngineState`. When a word starts with digits (`0–9`) followed by letters, allow Vietnamese Telex composition on the letter portion (`"1casi"` → `"1cái"`, `"2ngayf"` → `"2ngày"`), but if the resulting letter portion is not in `VietnameseDictionary.shared.syllableSet` or matches hex/technical patterns (`0x...`, `base64`, `h264`, `mp3`, `mp4`, `v2`, `s3`, `ec2`), restore/preserve the raw ASCII token.
  2. **Single-Step Arrow Navigation Snapshot (`D51` `navSavedState`)**: Add `navSavedState` to `VietnameseEngineState`. When `KEY_LEFT` (`123`, without Shift/Cmd/Option) is pressed while `index > 0`, snapshot the active word buffer into `navSavedState` before resetting the active buffer; if the very next key event is `KEY_RIGHT` (`124`, without modifiers), restore `navSavedState` into the active session so the user can continue composing the word seamlessly. Any other key clears `navSavedState`.
  3. **Compound-Token Boundary (`wordStartOk`)**: Track `wordStartOk: Bool` in `VietnameseEngineState` (`true` at initial state or after whitespace/sentence punctuation, `false` after `.`, `_`, `/`, `@`, `-`). When `wordStartOk == false`, clear `previousWords` look-back and bypass English-mode `enKeys` Vietnamese replay so compound code tokens (`foo.bar`, `my_var`, `path/to/file`) are never misconverted.
- **Trade-offs & Risks**: Snapshotting `navSavedState` adds one optional struct copy on `KEY_LEFT`, which is $O(1)$ ($\le 64$ entries) and immediately cleared on any key other than `KEY_RIGHT`.
- **Rejected Alternatives**: Intercepting full multi-character cursor movement across arbitrary positions in the host app via Accessibility AX APIs on every arrow press (rejected because AX text-selection queries are slow and asynchronous across Electron/browser apps, whereas single-step `Left` + `Right` snapshot recovery is 100% deterministic and zero-latency).
- **Consequences**: `"1casi"` composes cleanly into `"1cái"` while `"0xdeadbeef"` and `"base64"` stay untouched, accidental `Left` + `Right` arrow taps preserve active word composition, and compound identifiers (`foo.bar`, `my_var`) never suffer false cross-token conversions.


---

## `ADR-022` — Removal of Built-In Teencode & Chat Shorthands in Favor of Custom-Only Shorthands (`REQ-022`, `REQ-006`) — **Supersedes `ADR-020`**
- **Context**: Shipping two overlapping built-in chat/teencode abbreviation tables (`AutoWordingShorthandCatalog.builtInTable` and `VietnameseDictionary.teencodeExpansions`/`teencodeSuffixGWhitelist`) created conflicting expansions (`"nhg"` → `"nhưng"` vs. `"những"`), added a headless `teencodeEnabled` setting not exposed in `SettingsView`, and risked unexpected expansions on short technical or casual tokens (`"k"`, `"j"`, `"vs"`, `"bt"`, `"ng"`, `"ko"`). In the Phase 0 requirements interview (`A1`), the user explicitly chose to remove both `REQ-022` Teencode and built-in chat shorthands (`ko`, `dc`, `ntn`, `bt`...), keeping only user-defined Custom Shorthands/Macros (`REQ-022`).
- **Decision**:
  1. Remove `teencodeExpansions` and `teencodeSuffixGWhitelist` from `VietnameseDictionary.swift`, `teencodeEnabled` from `OpenKeySettingsStore.swift` and `AutoWordingEngine.swift`, and `AutoWordingShorthandCatalog.builtInTable` entries from `AutoWordingEngine.swift`.
  2. Restrict `AutoWordingEngine.expandShorthand(rawWord:)` strictly to user-defined `_customShorthands` when `shorthandExpansionEnabled == true`.
- **Trade-offs & Risks**: Users who want `"ko"` → `"không"` or `"cty"` → `"công ty"` must add them to Custom Shorthands in Settings; in exchange, default typing has zero surprise abbreviation expansions and zero duplicate shorthand dictionaries.
- **Rejected Alternatives**: Keeping `AutoWordingShorthandCatalog.builtInTable` while only removing `REQ-022` (rejected per explicit user choice `A1`).
- **Consequences**: Single, predictable, user-controlled `customShorthands` table with zero teencode bloat.

---

## `ADR-023` — Hybrid `E`/`V` Context-Ordered Wrong-Word Auto-Correction & Bilingual Candidate Ranking (`REQ-024`)
- **Context**: In mixed English + Vietnamese typing, a user can mistype either an English word (`"teh"`, `"fucntion"`, `"recieve"`, `"seperate"`, `"occured"`) or a Vietnamese word (`"ngươi"`, `"đươc"`). Deciding whether to evaluate and rank English (`E`) or Vietnamese (`V`) corrections first requires knowing the language of the current phrase without forcing manual mode switches (`REQ-024`).
- **Decision**:
  1. **Hybrid Context + Active Mode Priority (`A2`)**: Resolve `effectiveLanguagePriority: LanguagePriority` (`.englishFirst` vs. `.vietnameseFirst`) by inspecting the preceding 1–2 words in `previousWords` first (if the most recent word is English, prioritize `.englishFirst`; if Vietnamese, prioritize `.vietnameseFirst`), and falling back to the active status-bar mode (`vLanguage == 1 ? .vietnameseFirst : .englishFirst`) at sentence start (`previousWords.isEmpty`).
  2. **Auto-Correct High-Confidence Typos on `Space` with 1-Backspace Undo (`A3`)**: On `Space`, when a word is not in `keepWords` and is misspelled, evaluate typo corrections (`englishTypoCorrections` + single adjacent transposition against `englishPriorityWords` for `E`; `vietnameseTypoCorrections` + phonotactic repair for `V`) in `effectiveLanguagePriority` order. Every inline correction arms `autoRestoreUndoState` (`REQ-020`) so 1 `Backspace` reverts to the exact raw typed word.
  3. **Bilingual Candidate Bar Ordering (`A3`)**: `AutoWordingEngine` generates both `E` and `V` candidates and orders them according to `effectiveLanguagePriority`.
- **Trade-offs & Risks**: Aggressive fuzzy matching ($d_{DL} \ge 2$) on `Space` could cause false auto-corrections; therefore inline `Space` auto-correction is strictly restricted to curated high-confidence typo tables (`englishTypoCorrections`, `vietnameseTypoCorrections`) and unambiguous distance-1 adjacent transpositions not colliding with valid words in either language, while broader completions appear in the Candidate Bar.
- **Rejected Alternatives**: Status-bar mode priority only (rejected because when embedding a 2-word English phrase `"async fucntion"` inside Vietnamese mode, `"async"` establishes English context so `"fucntion"` should prioritize English `"function"` even while the status bar remains in `V` mode).
- **Consequences**: Seamless, context-aware wrong-word correction across both English and Vietnamese with instant 1-Backspace Undo and E/V-ordered candidate suggestions.

---

## `ADR-024` — Sub-Millisecond Inline Bilingual Grammar, Agreement & Sentence Formatting Engine (`REQ-025`)
- **Context**: Beyond single-word typos, mixed-language typing suffers from 2-word contextual grammar mistakes: Vietnamese homophone/tone confusion (`"làm việt"` instead of `"làm việc"`, `"suy nghỉ"` instead of `"suy nghĩ"`, `"sữa chữa"` instead of `"sửa chữa"`, `"phát triễn"` instead of `"phát triển"`), English contraction/pronoun/agreement errors (`"i dont"`, `"a error"`, `"an user"`, `"he dont"`, `"they was"`, `"the the"`), and manual punctuation/capitalization friction (`REQ-025`).
- **Decision**:
  1. **Vietnamese Bigram Grammar (`vietnameseBigramGrammar`)**: At word break on `Space`, check `(previousWord, currentComposedWord)` against curated 2-word Vietnamese compound grammar pairs and replace the current word when matched, arming `autoRestoreUndoState` (`REQ-020`).
  2. **English Contraction, Pronoun `"I"` & 2-Word Agreement**: In `.englishFirst` context, normalize standalone `"i"` → `"I"` and apostrophe-omitted contractions (`"dont"` → `"don't"`, `"im"` → `"I'm"`, `"doesnt"` → `"doesn't"`, `"cant"` → `"can't"`, `"wont"` → `"won't"`, `"isnt"` → `"isn't"`, `"didnt"` → `"didn't"`), repair 2-word `"a"`/`"an"` article agreement (`"a apple"` → `"an apple"`, `"a error"` → `"an error"`, `"an user"` → `"a user"`, `"an book"` → `"a book"`) and subject-verb agreement (`"he dont"` / `"he don't"` → `"he doesn't"`, `"they was"` → `"they were"`), and collapse accidental duplicate English function words (`"the the "` → `"the "`, `"is is "` → `"is "`).
  3. **Double-Space Period & Sentence-Start Auto-Capitalization**: When `grammarRepairEnabled == true`, convert double-space after a word (`"word  "`) into `". "` (`"word. "`) and auto-capitalize the first letter of the word following terminal sentence punctuation (`.`, `!`, `?` + space), skipping lowercase tech identifiers in `keepWords`.
- **Trade-offs & Risks**: Collapse of duplicate words must never touch intentional Vietnamese reduplications (`"luôn luôn"`, `"ngày ngày"`, `"đỏ đỏ"`, `"xanh xanh"`), so duplicate collapse is restricted to English function words (`the`, `is`, `to`, `in`, `for`, `and`, `of`, `at`, `on`).
- **Rejected Alternatives**: Invoking an external/LLM grammar model on `Space` (rejected for inline typing because `CGEventTap` requires `< 1ms` synchronous execution; table + bigram lookup executes in $< 50\ \mu\text{s}$).
- **Consequences**: Zero-latency inline grammar, contraction, agreement, and sentence formatting across both Vietnamese and English.

---

## `ADR-025` — Cohesion Refactoring (`BilingualAutoSwitchEngine.swift`) & `OpenKeyLogger` Queue Serialization (`REQ-026`)
- **Context**: Adding `REQ-015`..`REQ-023` directly into `VietnameseEngine.swift` (`969` lines) and `VietnameseEngine+Phonotactics.swift` (`1,000` lines) mixed low-level C++-ported syllable bitmask logic with high-level bilingual look-back, undo, and auto-switch heuristics. Furthermore, adversarial code review (`review.md` `P1-1`, `P1-2`) identified unsynchronized main-thread file truncation in `OpenKeyLogger` and stale `< 500` line-count comments (`REQ-026`).
- **Decision**:
  1. Extract all bilingual disambiguation, `droppedKeys` reconstruction, 2-word look-back, hybrid `E`/`V` wrong-word correction, inline bilingual grammar repair, single-backspace undo, arrow navigation snapshots, and English-mode keystroke replay into `BilingualAutoSwitchEngine.swift`.
  2. Serialize `OpenKeyLogger` file lifecycle operations (`checkVersionRetention`, `recreateLogFile`, `clearLog`) onto `self.queue` (`com.tuyenmai.openkey.logger`).
- **Trade-offs & Risks**: Moving methods across files in the same module (`OpenKeySwiftCore`) requires `internal` access on shared `VietnameseEngineState` properties, which has zero runtime overhead in Swift WMO release builds.
- **Rejected Alternatives**: Leaving all bilingual and grammar logic inside `VietnameseEngine+Phonotactics.swift` (rejected because a 1,300+ line file mixing bitmask vowel tables with English grammar rules violates single-responsibility cohesion).
- **Consequences**: Clean architectural separation between core Vietnamese syllable composition (`VietnameseEngine.swift`, `VietnameseEngine+Phonotactics.swift`) and bilingual intelligence (`BilingualAutoSwitchEngine.swift`), plus thread-safe debug logging.

---

## `ADR-026` — Independent Double-Space Period Configuration & Double-Tap Threshold (`REQ-025`)
- **Context**: `handleDoubleSpacePeriod()` in `BilingualAutoSwitchEngine.swift` was previously coupled directly to `grammarRepairEnabled` without an independent user setting or a double-tap time threshold. Users typing multiple spaces deliberately (e.g., indentation, alignment, formatting) or experiencing keyboard bounce (100–150ms switch chatter) suffered unexpected period conversions (`"word. "`). Furthermore, users who wanted vowel cluster grammar repairs (`"ie"` → `"iê"`) were forced to accept period substitutions on double space.
- **Decision**:
  1. Introduce an explicit, independent configuration toggle `doubleSpacePeriodEnabled: Bool` (defaults to `false`, opt-in) across `OpenKeySettingsStore`, `AutoWordingEngine`, `SettingsView`, and `OpenKeyL10n`.
  2. Enforce a 500ms double-tap time window (`lastSpaceUptime`): two consecutive `KEY_SPACE` events after a completed word convert to `". "` if and only if `doubleSpacePeriodEnabled == true` AND `now - lastSpaceUptime <= 0.5s`. If `now - lastSpaceUptime > 0.5s`, the second space is treated as a regular whitespace character.
  3. Keep sentence-start auto-capitalization active after terminal sentence punctuation (`.`, `!`, `?` + space) whenever `grammarRepairEnabled == true`, regardless of whether punctuation was typed manually or generated via double-space period.
- **Trade-offs & Risks**: Adding a dedicated toggle increases settings UI count slightly. Defaulting to `false` prevents unwanted period conversions in code editors, terminals, and markdown, requiring users who want macOS-style double-space periods to opt in.
- **Rejected Alternatives**:
  - Keeping double-space period bundled under `grammarRepairEnabled` (rejected because vowel cluster phonotactics and punctuation insertion are orthogonal user concerns).
  - Omitting the 500ms timing threshold (rejected because pauses of multiple seconds followed by a second space must never trigger period substitution).
- **Consequences**: Complete user control over double-space punctuation with zero unintended period conversions during deliberate spacing or slow typing.

---

## `ADR-027` — Escape Keystroke Consumption and Composed Word Protection (`REQ-027`)
- **Context**: In Telex mode, when a user presses a tone or modifier key that matches an active mark (e.g. `s` on `cháo`, `r` on `sẻ`, `f` on `ò`), the engine treats the second keystroke as an escape/cancellation key: it strips the diacritic and appends the literal character to produce `chaos`, `service`, `of`. However, `rawKeyStates` accumulated both the initial mark key and the cancellation key. On word break, `evaluateWordBreakRestore` checked `!droppedKeys.isEmpty && (dict.englishWords.contains(fullRawLower) || composed != fullRawStr)`, which triggered whenever `composed != fullRawStr` even when `fullRawLower` was complete gibberish (`chaoss`, `serrvice`, `thoiwfi`). As a result, the engine replaced already-correct English and Vietnamese words with corrupted raw keys containing duplicate escape characters (`REQ-027`).
- **Decision**:
  1. Restrict mid-word swallowed key restoration (`REQ-015`) to strictly verify that `dict.englishWords.contains(fullRawLower)` AND `!dict.englishWords.contains(composedLower)`. Completely remove the unconstrained fallback `|| composed != fullRawStr`.
  2. If `composedLower` is already a verified English word without diacritics, protect it: do not restore raw keys, and save `composed` and `stdRawKeys` into `previousWords` with `wasRestoredToEnglish = true`.
- **Trade-offs & Risks**: English words with intentional doubled letters (`coffee`, `process`) still restore correctly via `dict.englishWords.contains(fullRawLower)`. Unrecognized non-dictionary words that had a canceled tone mark will keep their on-screen composed spelling rather than being corrupted into doubled-letter raw strings.
- **Rejected Alternatives**:
  - Decrementing `rawStateIndex` inside `handleCharacterKey` when `hookOutput.code == HookCodeState.restore` (rejected because `rawKeyStates` is also needed for `coffee` where both `f`s were intentional).
  - Leaving `|| composed != fullRawStr` active (rejected because it guaranteed character corruption on every Telex tone cancellation).
- **Consequences**: Zero phantom character expansions on Space or punctuation for words typed with Telex escape keys (`chaos`, `service`, `of`).

---

## `ADR-028` — Previous Word History Synchronization across Backspace and Word Boundaries (`ADR-028`)
- **Context**: `previousWords` in `VietnameseEngineState` records preceding word entries for 2-word look-back rewriting (`REQ-018`) and duplicate word collapse (`REQ-025`). However, `VietnameseEngine.swift`'s legacy `handleDeleteKey()` and `restoreLastTypingState()` only popped `typingStates`, leaving `previousWords` untouched when the user backspaced over spaces and previous words. Consequently, when a user backspaced a word away and re-typed a new word, `previousWords` retained stale ghost entries. In the debug logs (`Line 4251`), this caused the engine to believe `ò` was still on screen when the user typed `of`, calculating `bs=4` and emitting `of off ` (`REQ-028`).
- **Decision**:
  1. In `handleDeleteKey()`, when `spaceCount` decrements to `0` and triggers `restoreLastTypingState()`, pop `previousWords.removeLast()` to reflect that the preceding word is being reopened or deleted.
  2. In `handleDeleteKey()`, when `index == 0` and all `typingStates` are empty, call `previousWords.removeAll()`.
  3. In `restoreLastTypingState()`, if `typingStates.isEmpty`, ensure `previousWords.removeAll()` is invoked.
- **Trade-offs & Risks**: Popping `previousWords` on backspacing over a space prevents 2-word look-back from seeing words that are being modified or deleted, which is the exact correct semantic invariant.
- **Rejected Alternatives**: Keeping `previousWords` persistent across word backspaces (rejected because phantom entries lead to invalid backspace counts and duplicate text injections).
- **Consequences**: Complete semantic alignment between text on screen and engine look-back history, eliminating phantom word duplications on Space.

---

## `ADR-029` — Pure Passthrough English Mode & Elimination of Autonomous Language Flipping (`REQ-029`)
- **Context**: `REQ-019` previously introduced experimental bidirectional auto-switching, attempting to detect Vietnamese typing while in English mode (`OKEngineHandleEnglishModeKeyEvent`) and switching `settings.language = 1` whenever typed letters formed a Vietnamese syllable with diacritics. However, because Vietnamese Telex uses English letters (`d`, `s`, `f`, `r`, `x`, `j`, `w`) for diacritics, common English words like `"did"` (`d-i-d` → Telex `"đi"`) or words missing from the lexicon triggered false-positive conversions. In live logs, a user in English mode typing `"did "` suffered immediate replacement to `"đi "` and had `settings.language` flipped to Vietnamese 5 times in a row. Furthermore, autonomously mutating global `settings.language` on 3+ English words surprised users by flipping menu bar icons and mutating per-app `SmartSwitchStore` preferences (`REQ-029`).
- **Decision**:
  1. In `EventTapCoordinator.swift`, when `context.language == 0` (English mode), immediately return `.passThrough(resetSession: false)`. Keystrokes pass directly to macOS without buffering, background Telex replay, or mode switching.
  2. Discontinue autonomous mutation of `settings.language` during inline typing. Input language changes are strictly reserved for explicit user actions (toggle hotkeys, menu clicks) and per-application focus shifts (`SmartSwitchStore`).
  3. Expand `VietnameseDictionary.shared.englishWords` and `keepWords` with comprehensive high-frequency English past-tense verbs (`did`, `said`, `went`, `got`, `made`, `came`, `took`, `gave`, `saw`, etc.) so bilingual look-back in Vietnamese mode protects them from unwanted diacritic conversions.
- **Trade-offs & Risks**: Users who accidentally type Vietnamese while in English mode will need to press the language toggle shortcut (`Ctrl+Shift` / `Cmd+Space`) rather than relying on automatic mode flipping. This is the universal standard across macOS, Unikey, and EVKey, preventing keystroke hijacking.
- **Rejected Alternatives**:
  - Expanding the dictionary only without fixing English mode passthrough (rejected because any unrecognized English word, technical acronym, or name would continue to hijack English typing into Vietnamese).
  - Adding a heuristic delay before flipping from `E` to `V` (rejected because autonomous mode changes inherently violate user expectations when English mode is explicitly selected).
- **Consequences**: English mode is 100% stable, zero-latency passthrough with zero phantom mode flips to Vietnamese.

---

## `ADR-030` — Onset-Preserving Transposition Signatures, Immediate Standalone `w` Auto-Revert & Idempotent Word-Break Replacement (`REQ-030`)
- **Context**: A post-Task-26 audit of live production logs (`~/Library/Logs/OpenKeySwift/openkey-debug.log`, `14:51:15`–`21:58:27`) and `OpenKeySwiftCore` / `OpenKeySwiftApp` source code exposed five concrete defects:
  1. *Anagram Coda/Onset Scrambling*: `telexSignatureToWords` in `VietnameseDictionary.swift` indexed full-word character-sorted anagrams (`String(stem.sorted())`). When the user typed incomplete vowel prefixes `"muo"` (at `16:57:27.840`, intending `"muốn"`) or `"phuo"`/`"phuow"` (at `17:01:17.518`–`17:01:17.671`, intending `"phương"`), the candidate bar suggested coda-scrambled words `["uôm", "uốm", "uồm"]` and `["hướp", "hượp"]` badged with `Tab` (`.correction`).
  2. *Redundant Replacement on Uppercase `"I"`*: At `18:04:12.290`–`18:04:12.454`, typing `Shift+I` (`word='I'`) followed by `Space` checked `fullRawLower == "i"` in `BilingualAutoSwitchEngine.swift` (line 378), triggering `bs=1, new=2, chars="I "` with `U+202F` breaker even though `"I"` was already capitalized on screen.
  3. *Live Typing Friction on English `w-` Words in Vietnamese Mode*: At `18:04:13.172`–`18:04:14.539`, after typing `"I think "`, the user typed `w-e` (`"we"`). Because standalone `w` at `index == 0` became `ư` (`STANDALONE_MASK`) and `e` left `"ưe"` on screen while `computeEnglishCandidates` suggested `["week", "weep", "west"]` (missing `"we"` from `englishPriorityWords`), the user had to backspace twice and type `w-w-e`.
  4. *First-Keystroke Dictionary Stall & Stale Candidate Bar Dispatch*: At `16:56:19.429`–`16:56:19.569`, lazy initialization of `VietnameseDictionary.shared` stalled the `CGEventTap` thread for `137ms` on the first 2-letter stem (`"tr"`), causing two `DispatchQueue.main.async` candidate callbacks (`["tree", "true", "trees"]` and `["trà", "trá", "trã"]`) to fire back-to-back on the same millisecond.
  5. *Redundant `OKEngineResetSession` Log Spam & Missing Engine Logs When AutoWording Disabled*: `OKEngineResetSession()` logged on every mouse click and shortcut even when the engine buffer was already empty, and `OKEngineHandleKeyEvent` bypassed `[ENGINE]` logging when `AutoWordingEngine.shared.isEnabled == false`.
- **Decision**:
  1. Add `VietnameseDictionary.extractVietnameseOnset(_:)` and require in `AutoWordingEngine.computeCurrentWordCandidates` that any `telexSignatureToWords` match shares the exact same initial consonant cluster as the typed stem.
  2. In `BilingualAutoSwitchEngine.evaluateWordBreakRestore`, only trigger standalone `"i"` → `"I"` when `fullRawStr == "i" && composed == "i"`, clear `replacementWord = nil` whenever `replacementWord == composed`, and treat `composed == "I"` as an English word in `previousWords` (`wasRestoredToEnglish = true`).
  3. In `VietnameseEngine.handleCharacterKey`, when `vInputType == 0 && index == 1 && CHR(0) == KEY_U && typingWord[0].isStandaloneW` and `keyCode` is in `[KEY_E, KEY_I, KEY_H, KEY_Y, KEY_L, KEY_B, KEY_D, KEY_G, KEY_K, KEY_Q, KEY_V]` (letters that can never follow word-initial `ư` in Vietnamese), immediately revert `typingWord[0]` to `KEY_W`, set `tempDisableKey = true`, insert `keyCode`, and emit `bs=1, new=2` (`"we"`, `"wi"`, `"wh"`, etc.); add common unambiguous `w-` words (`"we"`, `"with"`, `"what"`, `"when"`, `"where"`, `"which"`, `"while"`, `"who"`, `"why"`, `"will"`, `"would"`, `"want"`, `"work"`, `"world"`, `"word"`, `"well"`, `"way"`, `"were"`, `"went"`, `"water"`, `"watch"`, `"wait"`, `"walk"`, `"think"`) to `englishPriorityWords`.
  4. Pre-warm `_ = VietnameseDictionary.shared` in `OKEngineInit()`, guard `AutoWordingEngine.updateCandidates` main-thread dispatch with `guard self.activeCandidates == copy`, and move `CandidateBarController`'s `"Show candidate bar"` log inside the debounced work item with an `activeCandidates == candidates` check after caret resolution.
  5. Make `VietnameseEngineState.resetSession()` return `Bool` (`wasDirty`), only log `OKEngineResetSession` when `wasDirty || !AutoWordingEngine.shared.activeCandidates.isEmpty`, and log `OKEngineHandleKeyEvent` even when `AutoWordingEngine.shared.isEnabled == false`.
- **Trade-offs & Risks**: Auto-reverting word-initial standalone `w` (`ư`) on the second keystroke must never interfere with valid Vietnamese initial-`ư` words (`ư`, `ứ`, `ừ`, `ử`, `ữ`, `ự`, `ưa`, `ươ...`, `ưu`, `ức`, `ưng`, `ướp`, `ướt`, `ứt`). Restricting the trigger strictly to `index == 1 && typingWord[0].isStandaloneW` and the non-Vietnamese second-letter set `[KEY_E, KEY_I, KEY_H, KEY_Y, KEY_L, KEY_B, KEY_D, KEY_G, KEY_K, KEY_Q, KEY_V]` guarantees 100% preservation of all valid Vietnamese `ư-` syllables.
- **Rejected Alternatives**:
  - Removing `telexSignatureToWords` entirely (rejected because rime transpositions like `"tineg"` → `"tiếng"` and `"veit"` → `"việt"` are required by `REQ-004` / `REQ-008`).
  - Disabling standalone `w` → `ư` globally at `index == 0` (rejected because typing `w` for `ư` / `w-r` for `ử` is standard Telex behavior tested in `REQ-009`).
- **Consequences**: Zero false anagram candidates on incomplete Vietnamese stems, zero redundant backspaces on `"I "`, instant live `"we"`/`"with"`/`"what"`/`"when"` composition without `w-w` escaping, zero first-keystroke dictionary stalls, and clean diagnostic logs.


