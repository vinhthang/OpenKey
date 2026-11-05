# Specification: Native Android Vietnamese Keyboard for Samsung Galaxy A37 (`2026-11-02-android-large-phone-keyboard`)

- **Feature ID**: `2026-11-02-android-large-phone-keyboard`
- **Status**: `Completed`
- **Date**: `2026-11-02`
- **Platform**: `Android 10+ (minSdk 29, targetSdk 35, Pure Kotlin 2.x & Jetpack Compose)`
- **Primary Hardware Target**: `Samsung Galaxy A37 (6.7" Super AMOLED, 1080 × 2340 FHD+ 19.5:9, 120Hz One UI Stock Keyboard Layout Parity)`

---

## 1. Overview & Problem Statement

On the **Samsung Galaxy A37** (`6.7"`, `1080 × 2340` FHD+, `19.5:9`), the stock **Samsung Keyboard (One UI)** has well-established key geometry, 5-row proportions (`1–0` number row, 3 letter rows with `5%` side insets on `A–L`, and `!#1` / `,` / `Space` / `.` / `Enter` bottom row), and light/dark One UI colors that match the user's existing muscle memory. However, Samsung Keyboard's built-in Vietnamese input engine relies on underlined `setComposingText` spans, corrupts mixed Vietnamese + English sentences (`"test"` → `"tét"`, `"list"` → `"lít"`, `"cheese"` → `"chees"`, `"is good"` → `"í good"`), and misfires on complex `gi-`/`qu-` vowel clusters (`"giới"`) and multi-backspace editing.

The goal of **OpenKey Android** (`Sources/OpenKey/android/`) is to keep the **visual layout, key proportions, symbol layers (`!#1`, `1/2`, `2/2`), and muscle memory virtually identical to the stock Samsung Galaxy A37 One UI Keyboard** (minimum visual/interaction change from the current keyboard), while swapping in the 100% Pure Kotlin **OpenKey Vietnamese Engine** (`VietnameseEngine`, `BilingualAutoSwitchEngine`, `AutoWordingEngine`) under the hood.

---

## 2. Normative Requirements

### `REQ-001` — Multi-Module Gradle Architecture, Direct-Boot Readiness & Zero-Network Privacy (`Sources/OpenKey/android/`)
- **Description**: The Android implementation MUST reside under `Sources/OpenKey/android/` as a multi-module Gradle Kotlin project comprising `:openkey-core` (a 100% pure JVM Kotlin library with zero Android SDK dependencies) and `:app` (the Android `InputMethodService`, Jetpack Compose One UI keyboard view, and `SettingsActivity` targeting `minSdk = 29`, `targetSdk = 35`, `compileSdk = 35`). The application MUST declare `android:directBootAware="true"` on the IME service and MUST NOT request `android.permission.INTERNET` or any network/telemetry permissions.
- **Acceptance Criteria**:
  1. `./gradlew :openkey-core:test` executes all engine, phonotactic, bilingual, auto-wording, Samsung A37 layout metric, and gesture unit tests directly on the host JVM without requiring an Android emulator or device.
  2. `./gradlew :app:testDebugUnitTest` and `./gradlew :app:assembleDebug` succeed cleanly from the command line.
  3. `Sources/OpenKey/android/app/src/main/AndroidManifest.xml` contains zero `android.permission.INTERNET` declarations and marks `OpenKeyImeService` with `android:directBootAware="true"` and `android:permission="android.permission.BIND_INPUT_METHOD"`.

### `REQ-002` — Pure Kotlin Vietnamese Engine & Phonotactic Parity (`VietnameseEngine`, `VietnameseData`)
- **Description**: `:openkey-core` MUST port the complete `OpenKeySwiftCore` composition engine (`VietnameseData.kt`, `VietnameseEngine.kt`, `VietnameseEnginePhonotactics.kt`) supporting Telex (`0`) and VNI (`1`), precomposed Unicode (`NFC`), modern (`oà`, `uý`) and traditional (`òa`, `úy`) tone placement (`vUseModernOrthography`), `gi-` and `qu-` initial consonant backward vowel boundary calculation (`vowelStartIndex == 2` for `"giới"`, `"giường"`, `"gièo"`), standalone-`w` grammar backspace delta (`deltaBackSpace = -1`), multi-delete state synchronization (`CHR(idx)` bounds check returning `KEY_EMPTY = 256`, `keyStates`/`stateIndex` synchronization), and invalid-word ASCII restoration (`vRestoreIfWrongSpelling`, including `KEY_D` / `đ` restoration on `"dead"`, `"added"`).
- **Acceptance Criteria**:
  1. Typing Vietnamese syllables in Telex (`tiengs` → `"tiếng"`, `giowis` → `"giới"`, `truowngf` → `"trường"`) and VNI (`tieng61` → `"tiếng"`, `gio71i` → `"giới"`) produces exact precomposed Unicode characters and screen backspace counts (`backspaceCount == 2, newCharCount == 2, "ới"` on the final `s` of `giowis`).
  2. Typing toned words (`"nhất"`, `"tiếng"`, `"trường"`) and pressing `KEY_DELETE` 1 to 6 times followed by new characters (`"tiếng"` + `3×Delete` + `"ếp"` → `"tiếp"`) maintains strict buffer synchronization with zero duplicated vowels (`"tiiếng"`, `"nhấấ"`).
  3. When `checkSpelling == true` and `restoreIfWrongSpelling == true`, invalid Vietnamese syllables containing vowel/tone marks or `đ` (`"dead "`, `"added "`, `"window "`) restore raw ASCII keystrokes on word break.

### `REQ-003` — Mixed Vietnamese + English Code-Switching (`BilingualAutoSwitchEngine`, `VietnameseDictionary`)
- **Description**: `:openkey-core` MUST implement `BilingualAutoSwitchEngine.kt` and `VietnameseDictionary.kt` to prevent corruption when typing mixed Vietnamese sentences containing 1–2 English words without manual language switching:
  1. Reconstruct full raw keystrokes via `droppedKeys` tracking when English words contain doubled Telex modifier keys (`"cheese"`, `"seemed"`, `"needed"`, `"deepseek"`, `"google"`, `"choose"`, `"process"`, `"success"`, `"message"`, `"issue"`, `"office"`, `"coffee"`, `"error"`, `"array"`, `"current"`, `"correct"`, `"tomorrow"`, `"sorry"`, `"address"`, `"middle"`, `"reddit"`).
  2. Repair doubled-tone escape sequences (`"mixx "` → `"mix "`, `"fixx "` → `"fix "`, `"boxx "` → `"box "`) while preserving true double-letter English words (`"boss"`, `"class"`, `"pass"`).
  3. Restore standalone English/developer collision words (`"test"`, `"list"`, `"this"`, `"best"`, `"host"`, `"post"`, `"last"`, `"fast"`, `"rest"`, `"next"`, `"text"`, `"view"`, `"show"`, `"flow"`, `"more"`, `"core"`, `"store"`, `"score"`, `"user"`, `"vars"`, `"chars"`, `"cors"`, `"nums"`, `"hist"`, `"defs"`, `"docs"`, `"sort"`, `"port"`, `"start"`, `"part"`, `"turn"`, `"term"`, `"form"`, `"work"`, `"word"`, `"tree"`, `"free"`, `"see"`, `"too"`, `"add"`, `"mix"`, `"fix"`, `"box"`, `"max"`, `"tax"`) while preserving genuine Vietnamese words (`"có"`, `"bạn"`, `"anh"`, `"ăn"`, `"ở"`, `"ạ"`).
  4. Perform 1–2 word look-back restoration for English phrases where the first word is a short Vietnamese homograph (`"is good "` → `"is good "`, `"in case "` → `"in case "`, `"for sure "` → `"for sure "`, `"of course "` → `"of course "`).
  5. Restore contractions (`"doesn't"`, `"isn't"`), hyphenated `w-` words (`"Wi-Fi"`), and multi-capital acronyms (`"NAS"`, `"GoPro"` vs Vietnamese `"VĐV"`, `"BĐS"`).
- **Acceptance Criteria**:
  1. Simulated screen buffer tests typing mixed sentences (`"anh đang test cái list này "`, `"mình dùng deepseek và google ở office "`, `"it is good for sure "`) produce 100% uncorrupted Vietnamese and English output.

### `REQ-004` — Predictive Candidate Strip, Adaptive Frequency Learning & Custom Shorthands (`AutoWordingEngine`)
- **Description**: `:openkey-core` MUST implement thread-safe `AutoWordingEngine.kt` isolated from `VietnameseEngine` via `OKWordContext` and `phonotacticRepairHook`:
  1. Generate up to 3 live candidates (`CandidateKind.CORRECTION`, `STEM_COMPLETION`, `NEXT_WORD`) after every keystroke including `HookCodeState.DO_NOTHING` (`0`) and `KEY_DELETE`, preserving active vowel modifiers (`ă`, `â`, `ê`, `ô`, `ơ`, `ư`, `đ`) during stem completion (`"giơi"` prioritizes `"giới"`).
  2. Boost candidate ranking by user acceptance frequency (`recordCandidateAcceptance(text)`, `resetLearnedFrequencies()`).
  3. Repair transposed phonotactic clusters (`repairPhonotacticCluster`, e.g., `tineg` → `"tiếng"`) when `grammarRepairEnabled == true`.
  4. Expand user-defined custom shorthands (`customShorthands: Map<String, String>`) on `Space` when `shorthandExpansionEnabled == true`, without shipping unexpected built-in chat/teencode tables.
- **Acceptance Criteria**:
  1. Typing `"thanh"` populates `STEM_COMPLETION` candidates (`"thành"`, `"thánh"`); typing `"giơi"` ranks `"giới"` #1; accepting a candidate increments its persisted user frequency and promotes it to #1 on subsequent typing.
  2. Defining a custom shorthand (`"cty"` → `"công ty"`) expands on `Space` and clears session buffers cleanly.

### `REQ-005` — Batch Direct-Replacement `InputConnection` Pipeline & Smart `EditorInfo` Context Guard (`OpenKeyImeService`, `InputContextEvaluator`)
- **Description**: `OpenKeyImeService` MUST apply engine replacements using atomic batch direct replacement (`beginBatchEdit()`, `deleteSurroundingText(backspaceCount, 0)`, `commitText(replacement, 1)`, `endBatchEdit()`) without calling `setComposingText`, eliminating composing-underline artifacts and WebView autocomplete duplication. `InputContextEvaluator` MUST inspect `EditorInfo` on `onStartInput` / `onStartInputView` and automatically bypass Vietnamese composition (resetting the engine session and clearing candidates) when:
  - The input field is a password field (`TYPE_TEXT_VARIATION_PASSWORD`, `TYPE_TEXT_VARIATION_VISIBLE_PASSWORD`, `TYPE_TEXT_VARIATION_WEB_PASSWORD`, `TYPE_NUMBER_VARIATION_PASSWORD`).
  - The input field is a URI (`TYPE_TEXT_VARIATION_URI`, `TYPE_TEXT_VARIATION_WEB_EDIT_TEXT` URL bar), email (`TYPE_TEXT_VARIATION_EMAIL_ADDRESS`, `TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS`), filter/no-suggestions field (`TYPE_TEXT_FLAG_NO_SUGGESTIONS`), or non-text class (`TYPE_CLASS_NUMBER`, `TYPE_CLASS_PHONE`, `TYPE_CLASS_DATETIME`).
  - The target package (`EditorInfo.packageName`) is a terminal or remote-desktop client (`com.termux`, `com.sonelli.juicessh`, `com.server.auditor.ssh.client`, `com.microsoft.rdc.androidx`, `com.realvnc.viewer.android`).
- **Acceptance Criteria**:
  1. `InputContextEvaluator.evaluate(editorInfo)` deterministically classifies password, URI, email, numeric, and terminal package inputs as `bypassVietnamese = true` and `isSecureField = true/false`.
  2. When `EngineAction` emits `backspaceCount > 0` and `newChars`, `InputConnectionCommitter` invokes `beginBatchEdit()`, `deleteSurroundingText(backspaceCount, 0)`, `commitText(newChars, 1)`, and `endBatchEdit()` in exact sequence with zero `setComposingText` calls.

### `REQ-006` — Per-App Smart Language Memory (`SmartSwitchStore`)
- **Description**: `SmartSwitchStore` MUST persist per-package input language state (`packageName: String` → `language: Int`, `1 = VI`, `0 = EN`) when `useSmartSwitchKey == true` (enabled by default). When focus switches to a target app (`onStartInputView(editorInfo, restarting)`), if `useSmartSwitchKey == true` and `editorInfo.packageName` is non-empty (excluding `"com.tuyenmai.openkey.android"`), `SmartSwitchStore` restores the saved language for that package (or records the current language on first sight) and resets the engine word session.
- **Acceptance Criteria**:
  1. Switching between App A (`com.slack`, set to `EN`) and App B (`com.zing.zalo`, set to `VI`) automatically restores `EN` in App A and `VI` in App B when `useSmartSwitchKey == true`.
  2. When `useSmartSwitchKey == false`, switching apps preserves the global `language` setting while still resetting the uncommitted syllable session.

### `REQ-007` — Samsung Galaxy A37 One UI Stock Phone Keyboard Layout Parity (`PhoneLayoutMetrics`, `6.7"` FHD+ `1080 × 2340`)
- **Description**: The keyboard UI (`KeyboardScreen.kt`, `PhoneLayoutMetrics.kt`, `KeyboardLayoutDefinition.kt`) MUST replicate the exact stock **Samsung One UI 6/7 Keyboard** phone geometry, key weights, symbol layers, and visual theme on the **Samsung Galaxy A37 (`6.7"`, `1080 × 2340` FHD+, `19.5:9`)** using explicit phone-dedicated layout types (`PhoneLayoutConfig`, `PhoneLayoutMetrics`) rather than tablet/foldable `"LargeScreen"` naming:
  1. **Samsung One UI Top Toolbar / Suggestion Bar (`44dp` base portrait height)**:
     - When `activeCandidates` is non-empty: renders 3 full-height One UI suggestion slots separated by thin vertical dividers (`1dp`), with `candidates[0]` highlighted in the center primary slot (`17.sp` `FontWeight.SemiBold`).
     - When `activeCandidates` is empty: renders a clean, minimalist One UI toolbar with a subtle left mode indicator (`"Tiếng Việt • Telex"` / `"Tiếng Việt • VNI"` / `"English (US)"`) and borderless right-side Canvas vector icons (`One-Handed` mode icon and `Settings` gear icon) — with zero bulky text pill buttons.
  2. **Samsung One UI 5-Row Key Grid (`44dp` strip, `42dp` number row, `52dp` letter rows, `50dp` bottom row, `4dp` horizontal gap, `5dp` vertical gap, `7dp` corner radius)**:
     - **Row 1 — Dedicated Number Row (`42dp` base height)**: `1 2 3 4 5 6 7 8 9 0` (`10` equal keys, `10%` width each), enabled by default like Samsung Keyboard and automatically kept visible in VNI mode.
     - **Row 2 — Top Letter Row (`52dp` base height)**: `q w e r t y u i o p` (`10` equal keys, `10%` width each) with top-right secondary symbol sub-labels (`+ × ÷ = / _ < > [ ]` or `! @ # $ % ^ & * ( )`).
     - **Row 3 — Home Letter Row (`52dp` base height)**: `a s d f g h j k l` (`9` keys, `10%` width each) with exact **`5%` left and `5%` right horizontal row inset** matching Samsung Keyboard's staggered home row (`! @ # $ % ^ & * (` secondary sub-labels).
     - **Row 4 — Bottom Letter Row (`52dp` base height)**: `⇧` (`15%` width, One UI Shift/Caps-Lock vector icon) + `z x c v b n m` (`7` keys × `10%` width each, with `- ' " : ; , ?` sub-labels) + `⌫` (`15%` width, One UI Backspace vector icon).
     - **Row 5 — Bottom Function Row (`50dp` base height)**:
       - On `QWERTY` (`6` keys): `!#1` (`14%` width — symbol-layer switch) + `🌐` (`10%` width — dedicated Language Switch key with Globe vector icon and `VI`/`EN` badge) + `,` (`9%` width — left comma key) + `Spacebar` (`42%` width — displaying `"Tiếng Việt"` in Vietnamese mode or `"English (US)"` in English mode) + `.` (`9%` width — right period key) + `Enter / Action` (`16%` width — accented One UI Blue keycap with context-aware vector icon for `Search`, `Go`, `Send`, `Done`, `Next`, or `↵`).
       - On `SYMBOLS_1` & `SYMBOLS_2` (`5` keys): `ABC` (`15%` width) + `,` (`10%` width) + `Spacebar` (`50%` width) + `.` (`10%` width) + `Enter / Action` (`15%` width).
  3. **Samsung One UI Symbol Layers (`!#1` Page `1/2` & `2/2`)**:
     - Tapping `!#1` opens Page `1/2` (`1–0` top row, `+ × ÷ = / _ < > [ ]`, `! @ # $ % ^ & * ( )`, `1/2` page button + `- ' " : ; , ?` + `⌫`, and `ABC` + `,` + `Space` + `.` + `Enter`).
     - Tapping `1/2` switches to Page `2/2` (`~ ` | • √ π ÷ × § Δ`, `£ ¢ € ¥ ^ ° = { } \`, `2/2` + `% © ® ™ ✓ [ ]` + `⌫`).
  4. **Samsung One UI Visual Theme & Galaxy A37 Phone Ergonomics**:
     - **One UI Light Theme**: `#E8EAED` keyboard background, `#FFFFFF` letter/number keycaps (`7dp` corner radius, `#DCE0E8` pressed fill, `1dp` `#C4C7CC` bottom elevation border), `#D6D9E0` functional keycaps (`#C4C9D4` pressed fill), `#0072DE` accented `Enter` keycap, `#252528` primary label, `#7A7E87` top-right sub-label.
     - **One UI Dark Theme**: `#1B1B1F` keyboard background, `#2C2C32` letter/number keycaps (`7dp` corner radius, `#3E3E47` pressed fill), `#222227` functional keycaps (`#34343D` pressed fill), `#387AFF` accented `Enter` keycap, `#F2F2F7` primary label, `#9494A0` top-right sub-label.
     - **Configurable Size & Ergonomics**:
       - `heightScalePercent` (`85..125`, default `100`).
       - `bottomChinPaddingDp` (`0..48`, default `14dp` in portrait matching One UI's bottom keyboard margin above the gesture handle).
       - `OneHandedMode` (`OFF | LEFT | RIGHT`, `82%` active keyboard width + `18%` One UI side dock gutter with vector swap and expand buttons).
       - Landscape auto-compact (`38dp` alpha rows, `32dp` number row, `<= 42%` screen height).
- **Acceptance Criteria**:
  1. `PhoneLayoutMetrics.compute(PhoneLayoutConfig(...))` and `KeyboardLayoutDefinition` produce the exact 5-row Samsung One UI 6/7 phone layout (`44dp` strip, `42dp` number row, `52dp` alpha rows, `50dp` bottom row, `!#1`, `🌐`, `1/2`, `2/2`, `ABC`, `5%` Row 3 side inset, `14% / 10% / 9% / 42% / 9% / 16%` QWERTY Row 5 weights) across Galaxy A37 portrait (`360dp × 780dp` and `411dp × 891dp`) and landscape configurations, with zero `"LargeScreen"` tablet class names remaining in `:openkey-core` or `:app`.

### `REQ-008` — Samsung One UI Touch Gestures, Long-Press Popups & Haptics (`KeyboardGestureController`)
- **Description**: The keyboard UI MUST implement deterministic gesture recognition (`KeyboardGestureController.kt`) matching Samsung One UI Keyboard behavior:
  1. **Spacebar Trackpad Cursor Control**: Horizontal drag on the Spacebar exceeding `10dp` enters cursor-trackpad mode, emitting `1` cursor step left or right per `12dp` of horizontal displacement without inserting a space on release.
  2. **Backspace Swipe-Delete & Hold Repeat**: Leftward drag starting on the Backspace key (`⌫`) exceeding `24dp` deletes whole words (`1` word per `24dp` step), while stationary hold (`> 400ms`) repeats character deletion every `50ms`.
  3. **Long-Press Secondary Symbols & Vietnamese Vowels (`220ms`)**: Long-pressing any letter key commits or pops up its One UI top-right secondary symbol (`! @ # $ % ^ & * ( ) - ' " : ; ?`) alongside Vietnamese precomposed vowel variants (`a` → `ă, â`, `d` → `đ`, `e` → `ê`, `o` → `ô, ơ`, `u` → `ư`).
  4. **One UI Haptics & Key Popup Preview**: Key-down triggers configurable haptic feedback (`HapticFeedbackConstants.KEYBOARD_TAP`) and floating keycap preview bubble.
- **Acceptance Criteria**:
  1. Unit tests on `KeyboardGestureController` verify exact cursor step counts per `12dp` Spacebar drag (with zero space committed on release), word-delete counts per `24dp` Backspace left-swipe, and One UI secondary symbol + Vietnamese vowel long-press mappings.

### `REQ-009` — Phone Touch-Only Scope & Zero Hardware-Keyboard Interception Overhead
- **Description**: Because the target device (**Samsung Galaxy A37**) is a touch-first smartphone and not a tablet/desktop hybrid, `:openkey-core` and `:app` MUST NOT include external physical/Bluetooth keyboard mapping (`HardwareKeyMapper.kt`) or override `onKeyDown` / `onKeyUp` in `OpenKeyImeService` to intercept hardware key events:
  1. `HardwareKeyMapper.kt` and hardware key interception methods (`onHardwareKeyDown`, `onHardwareKeyUp`, `processHardwareKey`) MUST be absent from `:openkey-core` and `:app`.
  2. `OpenKeyImeService` and `KeyboardSessionController` MUST route exclusively on-screen touch actions (`KeyAction.CommitChar`, `KeyAction.Backspace`, `KeyAction.Space`, `KeyAction.Enter`, `KeyAction.Shift`, `KeyAction.SwitchLayer`, `KeyAction.SwitchLanguage`), candidate selections (`onCandidateSelected`), and touch gesture callbacks (`onMoveCursor`, `onDeletePreviousWord`).
- **Acceptance Criteria**:
  1. `HardwareKeyMapper.kt` does not exist in `:openkey-core`, and neither `OpenKeyImeService` nor `KeyboardSessionController` contains `onHardwareKeyDown`, `onHardwareKeyUp`, or `processHardwareKey`.

### `REQ-010` — Clean One UI-Styled Settings & Onboarding App (`SettingsActivity`, `OpenKeySettingsStore`)
- **Description**: The app MUST provide a clean Jetpack Compose `SettingsActivity` (`VI | EN` UI localization via `OpenKeyL10n.kt`) backed by Direct-Boot-safe `OpenKeySettingsStore`:
  1. **Interactive 2-Step Onboarding Banner**: Detects whether OpenKey is enabled in `InputMethodManager.enabledInputMethodList` and whether it is the currently selected default IME on the Galaxy A37, providing one-tap buttons to launch `Settings.ACTION_INPUT_METHOD_SETTINGS` and `InputMethodManager.showInputMethodPicker()`.
  2. **Live Sandbox Typing Field & Galaxy A37 Layout Preview**: Includes an embedded test box and sliders/toggles for `heightScalePercent` (`85%–125%`), `bottomChinPaddingDp` (`0–48dp`, default `14dp`), `OneHandedMode` (`OFF | LEFT | RIGHT`), `showNumberRow`, `hapticFeedbackEnabled`, and `keyPopupPreviewEnabled`.
  3. **Input & Intelligence Settings**: Controls for Input Method (`Telex` / `VNI`), `Language` (`VI` / `EN`), `Modern Orthography`, `Check Spelling`, `Auto-Restore Wrong Spelling`, `Bilingual English Auto-Restore`, `Per-App Smart Switch`, `Auto Wording Master Toggle`, inline **Custom Shorthand Editor**, and **Reset Learned Word Frequencies**.
  4. **Direct-Boot Persistence**: `OpenKeySettingsStore` uses `context.createDeviceProtectedStorageContext()` when running on Android so settings and `SmartSwitchStore` load cleanly before first user unlock.
- **Acceptance Criteria**:
  1. `OpenKeySettingsStore` unit tests verify value clamping (`inputType` in `0..1`, `heightScalePercent` in `85..125`, `bottomChinPaddingDp` in `0..48`), master `autoWordingEnabled` cascade activation, custom shorthand CRUD, and listener notification.
  2. `OpenKeyL10n` provides complete Vietnamese (`VI`) and English (`EN`) strings across all Onboarding, Galaxy A37 Layout, Engine, Auto Wording, and About sections.

### `REQ-011` — Unified Fast-Path `KeyboardSessionController` & Live `EditorInfo` Reactivity
- **Description**: `:openkey-core` MUST provide a unified `KeyboardSessionController` that centralizes touch keystroke routing (`onKeyAction`), `EditorInfo` evaluation (`InputEvaluation` including `imeActionId: Int` and `shouldSendNewlineOnEnter: Boolean`), `SmartSwitchStore` per-app language switching, `BatchReplacementCoordinator` commit execution, and candidate selection (`onCandidateSelected`):
  1. When `currentEvaluation.bypassVietnamese == true` (e.g., password, URI, email, numeric, `TYPE_TEXT_FLAG_NO_SUGGESTIONS`, or terminal package), touch keystrokes MUST bypass `VietnameseEngine` and `AutoWordingEngine`, committing raw characters directly with zero composition overhead.
  2. When `onStartInputView(editorInfo)` is invoked, `KeyboardSessionController` MUST publish a live `EditorUiState` (`enterActionLabel`, `imeActionId`, `shouldSendNewlineOnEnter`, `bypassVietnamese`, `isSecureField`, `language`) to `KeyboardScreen` so the `Enter` key label (`Search`, `Send`, `Go`, `Next`, `Done`, `↵`) and bypass behavior update reactively without recreating `ComposeView`.
  3. Pressing `KeyAction.Enter` MUST commit `"\n"` when `shouldSendNewlineOnEnter == true` (multiline text fields without explicit action or with `IME_FLAG_NO_ENTER_ACTION`) and invoke `committer.performEditorAction(imeActionId)` otherwise.
- **Acceptance Criteria**:
  1. Unit tests on `KeyboardSessionController` verify that setting an email/password/URI `EditorContext` bypasses Vietnamese Telex transformation on touch `KeyAction.CommitChar` and updates `editorUiState.enterActionLabel` and `imeActionId` reactively.
  2. Pressing `KeyAction.Enter` dispatches `performEditorAction(IME_ACTION_SEARCH)` on a search field and commits `"\n"` on a multiline field.

### `REQ-012` — Commit-First Keystroke Pipeline, Static Dictionary Lookup Tables & Generation-Tagged Async Candidates
- **Description**: To guarantee `< 8.33ms` 120Hz frame budgets on the Samsung Galaxy A37, keystroke commit MUST be decoupled from candidate computation and dictionary initialization:
  1. `KeyboardSessionController` MUST commit the `HookSnapshot` character replacement to `TextCommitterTarget` (`batchCoordinator.commitBatch`) **before** computing post-keystroke `AutoWordingEngine` candidates, eliminating redundant duplicate calls to `getWordContext` and `didProcessKeyEvent`.
  2. `VietnameseDictionary` MUST use static pre-allocated lookup tables (`DIACRITIC_STRIP_MAP`, `TELEX_BASE_MOD_MAP`, `U_HORN_CHARS`, `O_HORN_CHARS`) in `stripVietnameseDiacritics` and `canonicalTelexKey` (zero per-call `Map`/`Set` allocation) and expose `VietnameseDictionary.prewarmAsync()` invoked on `OpenKeyImeService.onCreate()`.
  3. `AutoWordingEngine` MUST support generation-tagged asynchronous candidate computation (`asyncCandidateExecutionEnabled`, `scheduleCandidateComputation` with monotonic `AtomicLong` generation counter) so stale candidate computations during rapid 120Hz typing are discarded before invoking `onCandidatesChanged`.
- **Acceptance Criteria**:
  1. `KeyboardSessionController` commits text to `TextCommitterTarget` strictly prior to candidate emission on every keystroke.
  2. `AutoWordingEngine` with `asyncCandidateExecutionEnabled = true` computes candidates on its background worker thread and discards stale generation IDs when rapid consecutive keystrokes arrive.
  3. `VietnameseDictionary.prewarmAsync()` initializes `VietnameseDictionary.shared` safely and idempotently.

### `REQ-013` — Zero-IPC-Read Spacebar Trackpad Cursor Control & Selection Tracking
- **Description**: During 120Hz Spacebar horizontal trackpad dragging (`onMoveCursor`), `InputConnectionCommitter.moveCursorBy(deltaChars)` MUST NOT call `InputConnection.getExtractedText(...)` (which copies the entire document text across Binder IPC on every `12dp` drag step). Instead, `BatchReplacementCoordinator` MUST track the live cursor offset (`currentSelStart`, `currentSelEnd`, `hasKnownSelection`) from `onStartInputView(info.initialSelStart, info.initialSelEnd)` and `onUpdateSelection(...)`, and `InputConnectionCommitter.moveCursorBy` MUST use tracked selection coordinates or lightweight `KEYCODE_DPAD_LEFT` / `KEYCODE_DPAD_RIGHT` key events wrapped in batch edits.
- **Acceptance Criteria**:
  1. Unit tests verify that `InputConnectionCommitter.moveCursorBy(deltaChars)` repositions the cursor across 50 consecutive drag steps with **zero** calls to `InputConnection.getExtractedText(...)`.

### `REQ-014` — Zero-Recomposition Key Grid Isolation, Cached Layer Layouts & Single-Pass `drawBehind` Keycaps
- **Description**: The Jetpack Compose UI (`KeyboardScreen.kt`, `CandidateStripView.kt`, `KeyButton.kt`, `KeyboardLayoutDefinition.kt`) MUST eliminate whole-keyboard recomposition storms and multi-node keycap rendering overhead at 120Hz:
  1. `KeyboardLayoutDefinition.getLayer(layer, isShifted, language, imeActionLabel)` MUST cache and reuse immutable `KeyboardLayerDef` instances in a thread-safe cache (`ConcurrentHashMap`) instead of allocating new `KeyRow` and `KeyModel` lists on every recomposition.
  2. Candidate list state subscription (`autoWordingEngine.onCandidatesChanged`) MUST be isolated inside a dedicated `CandidateStripHost` / `CandidateStripView` scope so updating `activeCandidates` after each keystroke triggers **zero** recompositions of the 45 `KeyButton` composables in the 5-row key grid.
  3. `KeyButton.kt` MUST render the Samsung One UI keycap (`6dp` corner radius, `1dp` bottom shadow bevel, keycap fill, and `1dp` border) in a single lightweight `Modifier.drawBehind` canvas pass rather than chaining `.shadow().clip().background().border()` modifiers across 45 keys.
- **Acceptance Criteria**:
  1. Calling `KeyboardLayoutDefinition.getLayer(...)` repeatedly with identical arguments returns the exact same cached object reference (`===`).
  2. `KeyboardScreen` isolates candidate state updates inside `CandidateStripView` and renders `KeyButton` surfaces via `Modifier.drawBehind`.

### `REQ-015` — 120Hz Frame-Budget & Throughput Benchmark Verification (`< 0.2ms` Average Keystroke Hot Path)
- **Description**: `:openkey-core` MUST include a deterministic throughput and latency verification suite (`SmoothArchitectureTest.kt`) benchmarking 1,000 continuous mixed Vietnamese Telex + English keystrokes through `KeyboardSessionController`, verifying that average hot-path keystroke processing and commit time is `< 0.2ms` per keystroke (`> 40×` faster than the `8.33ms` 120Hz frame budget on Samsung Galaxy A37).
- **Acceptance Criteria**:
  1. `SmoothArchitectureTest` executes 1,000 continuous keystrokes through `KeyboardSessionController` with average per-keystroke latency `< 0.2ms` (`200,000 ns`) and 100% output accuracy.


### `REQ-016` — GitHub Actions CI/CD Workflows, Pipeline Isolation & Portable Build (`android-ci.yml` & `macos-ci.yml`)
- **Description**: The repository MUST include automated, path-isolated GitHub Actions CI/CD workflows (`.github/workflows/android-ci.yml` and `.github/workflows/macos-ci.yml`) and portable Gradle configuration (`Sources/OpenKey/android/gradle.properties`, `Sources/OpenKey/android/.gitignore`) so pushing to GitHub automatically runs unit tests, builds the Samsung Galaxy A37 APK, and keeps both Android and macOS CI pipelines green:
  1. `Sources/OpenKey/android/gradle.properties` MUST NOT hardcode a machine-local `org.gradle.java.home` path so the build runs portably across macOS developer machines and Linux (`ubuntu-latest`) GitHub Actions runners.
  2. `Sources/OpenKey/android/.gitignore` MUST exclude `.gradle/`, `build/`, `*/build/`, and `local.properties` from version control.
  3. `.github/workflows/android-ci.yml` MUST trigger on `push` (`master`/`main`, tags `v*`), `pull_request`, and `workflow_dispatch`, set up JDK 21 (`actions/setup-java@v4`), execute `./gradlew :openkey-core:test :app:testDebugUnitTest :app:assembleDebug` under `Sources/OpenKey/android`, upload the compiled APK (`app-debug.apk`) via `actions/upload-artifact@v4`, and publish it to GitHub Releases on `v*` tags.
  4. `.github/workflows/macos-ci.yml` MUST scope `push` and `pull_request` triggers to `Sources/OpenKey/macOS-Swift/**` and `.github/workflows/macos-ci.yml`, and `OpenKeyEventTapTests.openKeySettingsStoreSync()` MUST be annotated with `@MainActor` so `onLanguageChanged` fires deterministically without background-thread race conditions on `macos-26` runners.
- **Acceptance Criteria**:
  1. `Sources/OpenKey/android/gradle.properties` contains zero hardcoded `/Users/` paths, and both `.github/workflows/android-ci.yml` and `.github/workflows/macos-ci.yml` pass all jobs on GitHub (`rtk gh run list`) after pushing to `origin`.

### `REQ-017` — Android Debug Mode, Version-Scoped Diagnostic Logger (`OpenKeyLogger`), Secure-Field Redaction & In-App Log Viewer
- **Description**: `:openkey-core` and `:app` MUST provide an opt-in Debug Mode (`OpenKeySettingsStore.debugModeEnabled`, `OpenKeyLogger.kt`) and an in-app Debug & Diagnostics UI card in `SettingsActivity.kt` with full parity to macOS `REQ-013`:
  1. **Zero Overhead When Disabled**: `OpenKeyLogger.log(category: OpenKeyLogCategory, message: () -> String)` MUST accept a lazy lambda (`() -> String`) and return immediately when `!isEnabled`, guaranteeing zero lambda evaluation and zero disk/memory writes on the 120Hz keystroke hot path when `debugModeEnabled == false`.
  2. **Multi-Subsystem Diagnostic Logging**: When `debugModeEnabled == true`, `OpenKeyLogger` MUST record timestamped entries (`[yyyy-MM-dd HH:mm:ss.SSS] [CATEGORY] message`) across `LIFECYCLE`, `SETTINGS`, `SESSION`, `ENGINE`, `AUTO_WORDING`, and `SMART_SWITCH` to `openkey-debug.log` in the configured log directory (e.g., `context.filesDir/logs/openkey-debug.log`) and expose `readRecentLogs(maxLines: Int)` for in-app viewing.
  3. **Strict Secure-Field Keystroke Redaction**: When `editorUiState.isSecureField == true`, `KeyboardSessionController` MUST log `"Secure input active — keystroke redacted, bypassing IME"` and MUST NEVER record raw characters or keystrokes.
  4. **Version-Scoped Retention & Size-Cap Rotation**: `OpenKeyLogger` MUST write `# OpenKeyAndroidVersionStamp: <versionStamp>` on initialization, automatically purge/recreate `openkey-debug.log` when `versionStamp` changes (`"2.0.0-build1"` → `"2.0.0-build2"`), and rotate/truncate when `maxFileSizeBytes` is exceeded.
  5. **In-App Debug & Diagnostics Card (`SettingsActivity.kt` & `OpenKeyL10n.kt`)**: `SettingsScreen` MUST include a localized (`VI | EN`) **Debug & Diagnostics** card with a `Debug Mode` toggle (`debugModeEnabled`), live log entry view (`readRecentLogs`), a **Copy Logs** button (copying to Android `ClipboardManager`), and a **Clear Log** button (`OpenKeyLogger.shared.clearLog()`).
- **Acceptance Criteria**:
  1. Unit tests in `:openkey-core` and `:app` verify: (a) zero lambda evaluation and zero file creation when `debugModeEnabled == false`; (b) multi-subsystem log emission (`LIFECYCLE`, `SETTINGS`, `SESSION`, `ENGINE`, `AUTO_WORDING`) when `debugModeEnabled == true`; (c) strict keystroke redaction when `isSecureField == true`; (d) automatic log purge on version stamp change; and (e) automatic truncation when `maxFileSizeBytes` is exceeded.
  2. `OpenKeyL10n.Debug` provides non-empty `VI` and `EN` strings for all debug controls in `SettingsActivity`.

### `REQ-018` — Context-Ordered `V` / `E` Homograph Disambiguation (`"sẽ"` vs. `"sex"`) & Tone-Preserving Candidate Ranking
- **Description**: Both `:openkey-core` (`BilingualAutoSwitchEngine.kt`, `VietnameseDictionary.kt`, `AutoWordingEngine.kt`) and `OpenKeySwiftCore` (`BilingualAutoSwitchEngine.swift`, `VietnameseDictionary.swift`, `AutoWordingEngine.swift`) MUST order homograph disambiguation and candidate ranking by active `LanguagePriority` (`VIETNAMESE_FIRST` [`V`] vs. `ENGLISH_FIRST` [`E`]):
  1. **Vietnamese-Priority Homograph Protection in `V` Context**: Common Vietnamese words whose Telex keystrokes also spell an English word (`"sẽ"` [`sex`], `"vẽ"` [`vex`], `"mã"` [`max`], `"sĩ"` [`six`], `"tã"` [`tax`], `"lã"` [`lax`], `"hẽ"` [`hex`], `"môn"` [`moon`], `"nôn"` [`noon`], `"sôn"` [`soon`], `"sên"` [`seen`], `"sêm"` [`seem`], `"bề"` [`beef`], `"rề"` [`reef`], `"rôm"` [`room`], `"bôm"` [`boom`], `"dôm"` [`doom`], `"lôm"` [`loom`], `"bốt"` [`boots`], `"rốt"` [`roots`], `"lốp"` [`loops`], `"mết"` [`meets`], `"kếp"` [`keeps`], `"mổ"` [`moor`], `"dổ"` [`door`]) MUST NOT be unconditionally restored in `englishPriorityWords` when `effectiveLanguagePriority == VIETNAMESE_FIRST` (`V`). In `V` context (e.g., standalone `"sẽ "`, `"anh sẽ làm "`, `"bác sĩ "`, `"mã nguồn "`, `"bản vẽ "`), the engine MUST keep the composed Vietnamese word (`"sẽ"`, `"vẽ"`, `"mã"`, `"sĩ"`, etc.).
  2. **English-Priority Restoration in `E` Context & 2-Word Look-Back**: When `effectiveLanguagePriority == ENGLISH_FIRST` (`E`, i.e., immediately following an English word such as `"have sex "`, `"safe sex "`, `"at max "`, `"number six "`, `"income tax "`, `"full moon "`, `"at noon "`, `"coming soon "`) OR when followed by an English word in a 2-word phrase (`"sex education "`, `"sex is "`, `"max value "`, `"tax rate "` via `englishLookbackStems`), the engine MUST restore the raw English word (`"sex"`, `"max"`, `"six"`, `"tax"`, `"moon"`, `"noon"`, `"soon"`).
  3. **Tone-Preserving `V` / `E` Candidate Bar Ordering (`AutoWordingEngine`)**: When `currentSyllable` already carries an explicit tone mark (`á, à, ả, ã, ạ`, e.g., `"sẽ"`), `AutoWordingEngine.computeCurrentWordCandidates` MUST keep `currentSyllable` at the front of the Vietnamese candidate list (rather than demoting it behind unaccented `"se"`), placing `"sẽ"` at slot 1 and `"sex"` after Vietnamese candidates when `languagePriority == VIETNAMESE_FIRST` (`V`), and placing `"sex"` at slot 1 and `"sẽ"` at slot 2 when `languagePriority == ENGLISH_FIRST` (`E`).
- **Acceptance Criteria**:
  1. Typing `"sẽ "`, `"anh sẽ làm "`, `"chia sẽ "` (→ `"chia sẻ "`), `"bác sĩ "`, `"mã nguồn "`, `"bản vẽ "`, and `"bộ môn "` in Vietnamese mode produces the exact Vietnamese output without converting `"sẽ"` to `"sex"`.
  2. Typing `"have sex "`, `"safe sex "`, `"sex education "`, `"at max "`, `"max value "`, `"number six "`, `"income tax "`, and `"full moon "` produces the restored English phrases.
  3. `AutoWordingEngine.computeCurrentWordCandidates(rawStem = "sex", currentSyllable = "sẽ", languagePriority = VIETNAMESE_FIRST)` ranks `"sẽ"` before `"sex"`, and with `languagePriority = ENGLISH_FIRST` ranks `"sex"` before `"sẽ"`.

### `REQ-019` — Vietnamese Syllable Protection Against Transposition/Homograph Overwrite (`"thể"` vs. `"there"`) & Standalone-`W` Escape Buffer Normalization (`"Why"` vs. `"Wwhy"`)
- **Description**: Both `:openkey-core` (`VietnameseEnginePhonotactics.kt`, `VietnameseDictionary.kt`, `BilingualAutoSwitchEngine.kt`) and `OpenKeySwiftCore` (`VietnameseEngine+Phonotactics.swift`, `VietnameseDictionary.swift`, `BilingualAutoSwitchEngine.swift`) MUST prevent false English restoration on valid Vietnamese syllables and eliminate duplicate `w` keystrokes when escaping standalone `Ư`/`ư`:
  1. **Protection of Valid Vietnamese Syllables Against Free-Order Telex & Transposition Overwrite (`"thể"` vs. `"there"`, `"thế"` vs. `"these"`, `"hể"` vs. `"here"`, `"mể"` vs. `"mere"`)**:
     - When `dict.isValidVietnameseSyllable(composedLower)` is `true`, `BilingualAutoSwitchEngine.evaluateWordBreakRestore` in `VIETNAMESE_FIRST` (`V`) mode MUST NOT overwrite `composed` with `fullRawLower` based on `countVowelGroups(fullKeys) >= 2` (which miscounts interleaved Telex tone keys in free-order sequences like `t-h-e-r-e` → `"thể"` or `t-h-e-s-e` → `"thế"` as two vowel groups).
     - `VietnameseDictionary` MUST precompute `validTelexKeys: Set<String>` for all valid Vietnamese syllables (`canonicalTelexKey(syllable)`), and `findEnglishTranspositionMatch(rawLower)` MUST return `null` whenever `validTelexKeys.contains(rawLower)` (so `"theer"` [Telex for `"thể"`] and `"thees"` [Telex for `"thế"`] are never matched as adjacent-character transpositions of `"there"` or `"these"`). Furthermore, Step 5 (`Typo & Transposition Corrections`) in `BilingualAutoSwitchEngine` MUST guard both `englishTypoCorrections` and `findEnglishTranspositionMatch` with `!dict.isValidVietnameseSyllable(composedLower)` in both `VIETNAMESE_FIRST` and `ENGLISH_FIRST` branches.
     - Unaccented valid Vietnamese words that also appear in `englishWords` (e.g., `"con"`, `"hay"`, `"may"`, `"ban"`, `"can"`, `"tan"`, `"man"`, `"son"`, `"ton"`, `"non"`, `"don"`, `"do"`, `"to"`, `"so"`, `"no"`, `"an"`, `"in"`, `"on"`, `"me"`, `"he"`, `"be"`, `"em"`) MUST NOT set `wasRestoredToEnglish = true` when `shouldRestore == false` in `VIETNAMESE_FIRST` (`V`) mode, so typing `"con thể "`, `"hay thể "`, or `"ban thể "` keeps `effectiveLanguagePriority == VIETNAMESE_FIRST` for the subsequent word `"thể"`.
     - `"there"`, `"these"`, `"here"`, `"mere"`, and `"were"` MUST be included in `englishLookbackStems` so English phrases (`"there is "`, `"there are "`, `"these are "`, `"here is "`) still restore via 2-word look-back or `ENGLISH_FIRST` context (`"in there "`, `"over there "`).
  2. **Standalone-`W` Telex Escape Buffer Normalization (`"Why"` vs. `"Wwhy"`)**:
     - In `VietnameseEnginePhonotactics.insertW` (`VietnameseEngine+Phonotactics.insertW`), when `typingWord[ii].isStandaloneW && ch == KEY_U` reverts standalone `'Ư'`/`'ư'` to a single literal `'W'`/`'w'` in `typingWord`, the engine MUST pop the consumed escape `w` keystroke from `keyStates` (`stateIndex--`) and `rawKeyStates` (`rawStateIndex--`) so `getRawKeyStatesString` (`stdRawStr`) and `getFullRawKeyString` (`fullRawStr`) contain `"Why"` / `"why"` instead of `"Wwhy"` / `"wwhy"`.
     - In `BilingualAutoSwitchEngine.evaluateWordBreakRestore` Step 6 (`Sentence Capitalization`), when `dict.englishWords.contains(composedLower) && !hasAnyDiacritic`, `wordToCap` MUST use `composed` (rather than `fullRawStr`), ensuring `. wwhy ` or `. Why ` after sentence punctuation emits `". Why "` and never `". Wwhy "`.
- **Acceptance Criteria**:
  1. Typing `"thể "` (both standard Telex `theer ` and free-order `there `), `"có thể "`, `"con thể "`, `"hay thể "`, `"như thế "`, and `"thế "` in `V` mode produces exact Vietnamese output (`"thể "`, `"có thể "`, `"con thể "`, `"hay thể "`, `"như thế "`, `"thế "`), while English contexts (`"there is "`, `"in there "`, `"these are "`) produce `"there is "`, `"in there "`, `"these are "`.
  2. Typing `"Why "` (`W-w-h-y ` or `W-h-y `), `"why "` (`w-w-h-y ` or `w-h-y `), and sentence-initial `". wwhy "` or `". Why "` in `V` mode produces `"Why "`, `"why "`, and `". Why "` with zero `"Wwhy"` duplication on both Android (`:openkey-core`) and macOS (`OpenKeySwiftCore`).

### `REQ-020` — Authentic Samsung Galaxy A37 One UI 6/7 Visual Polish, High-Legibility Typography, Dedicated Bottom-Row Globe Key & Custom Vector Icons (`PhoneLayoutMetrics.kt`, `KeyboardLayoutDefinition.kt`, `KeyButton.kt`, `CandidateStripView.kt`, `KeyboardScreen.kt`)
- **Description**: `:openkey-core` and `:app` MUST eliminate prototype-style small characters, arbitrary top-bar text pills, and raw Unicode glyph buttons by implementing authentic **Samsung One UI 6/7 Keyboard / Gboard** typography, row geometry, bottom-row language switching, and Canvas vector icons:
  1. **Taller Samsung Galaxy A37 Portrait Row Proportions & Tighter Keycap Spacing (`PhoneLayoutMetrics.kt`)**:
     - Portrait base heights (`heightScalePercent = 100`): `candidateStripHeightDp = 44dp`, `numberRowHeightDp = 42dp`, `alphaRowHeightDp = 52dp` (yielding a `47dp` vertical keycap face), `bottomRowHeightDp = 50dp`, `keyCornerRadiusDp = 7dp`, `keyHorizontalGapDp = 4dp`, and `keyVerticalGapDp = 5dp` (`totalHeightDp = 306dp` with default `14dp` bottom chin).
  2. **High-Legibility Keycap Typography (`KeyButton.kt`)**:
     - Lowercase letter keys (`a–z`): **`23.sp`** (`FontWeight.Normal`) with a `1.dp` downward vertical offset when a top-right secondary symbol (`10.5.sp` `FontWeight.Medium`) is present, ensuring the primary character is large, centered in the lower-middle keycap zone, and never crowded by the secondary sub-label.
     - Uppercase letter keys (`A–Z`): **`21.sp`** (`FontWeight.Medium`).
     - Number row keys (`1–0`): **`20.sp`** (`FontWeight.Normal`).
     - Punctuation keys (`,` and `.`): **`22.sp`** (`FontWeight.Medium`).
     - Spacebar label (`"‹ Tiếng Việt ›"` / `"‹ English (US) ›"`): **`13.5.sp`** (`FontWeight.Medium`).
     - Functional text keys (`!#1`, `ABC`, `1/2`, `2/2`): **`14.sp`** (`FontWeight.SemiBold`).
  3. **Dedicated Bottom-Row Language Switch Key (`🌐`) & Clutter-Free Top Suggestion/Toolbar Strip (`KeyboardLayoutDefinition.kt` & `CandidateStripView.kt`)**:
     - **Row 5 (`QWERTY` layer)**: MUST include a dedicated **Language Switch key (`🌐`, `KeyAction.SwitchLanguage`)** between `!#1` and `,` with exact weights: `!#1` (`0.14f`), `🌐` (`0.10f`, `primaryLabel = "🌐"`, `secondaryLabel = "VI"` when `language == 1` else `"EN"`), `,` (`0.09f`), `Spacebar` (`0.42f`), `.` (`0.09f`), and `Enter` (`0.16f`).
     - **`CandidateStripView.kt`**: MUST remove the 4 boxy text pill buttons (`[VI]`, `[Telex]`, `[Full / Left 82%]`, `[⚙]`). When `candidates` is non-empty, it renders 3 full-height suggestion slots ordered as `[candidates.getOrNull(1), candidates[0] (center primary bold 17.sp with subtle accent pill), candidates.getOrNull(2)]`. When `candidates` is empty, it renders a clean left mode label (`"Tiếng Việt • Telex"` / `"Tiếng Việt • VNI"` / `"English (US)"`, tappable to toggle `Telex`/`VNI`) and borderless right-side Canvas vector icon buttons (`One-Handed` icon and `Settings` gear icon).
  4. **Custom Canvas Vector Icons, Pressed Keycap Fill & Accented Enter Key (`KeyButton.kt` & `ThemePalette`)**:
     - `ThemePalette` MUST define `pressedKeycapColor` (`0xFFDCE0E8` Light / `0xFF3E3E47` Dark) and `pressedFunctionalKeycapColor` (`0xFFC4C9D4` Light / `0xFF34343D` Dark).
     - `KeyButton.kt` MUST render custom Canvas vector icons (`KeyboardVectorIcons`) instead of raw Unicode text glyphs for `KeyAction.Shift` (outline arrow when unshifted, solid filled `accentColor` arrow when shifted, solid filled arrow + underline bar when Caps Locked), `KeyAction.Backspace` (pentagonal backspace outline with `×` cross), `KeyAction.SwitchLanguage` (meridian globe vector icon + compact `VI`/`EN` badge), and `KeyAction.Enter` (white vector icon for `Search` magnifier, `Send` paper plane, `Go`/`Next` right arrow, `Done` checkmark, or `↵` return arrow on an accented `theme.accentColor` keycap).
- **Acceptance Criteria**:
  1. `PhoneLayoutMetrics.compute(PhoneLayoutConfig(screenWidthDp = 360, screenHeightDp = 780, isLandscape = false))` returns `candidateStripHeightDp = 44f`, `numberRowHeightDp = 42f`, `alphaRowHeightDp = 52f`, `bottomRowHeightDp = 50f`, `keyCornerRadiusDp = 7f`, `keyHorizontalGapDp = 4f`, `keyVerticalGapDp = 5f`, and `totalHeightDp = 306f`.
  2. `KeyboardLayoutDefinition.getLayer(KeyboardLayer.QWERTY, ...)` Row 5 contains 6 keys (`!#1` [`0.14f`], `🌐` [`0.10f`, `KeyAction.SwitchLanguage`], `,` [`0.09f`], `Spacebar` [`0.42f`], `.` [`0.09f`], `Enter` [`0.16f`]) whose weights sum to `1.00f`, and `ThemePalette` exposes `pressedKeycapColor` and `pressedFunctionalKeycapColor` for both Light and Dark themes.
  3. `KeyButton.kt` and `CandidateStripView.kt` render `23.sp` lowercase / `21.sp` uppercase / `20.sp` number typography, Canvas vector icons (`Shift`, `Backspace`, `Globe`, `Enter`, `Settings`, `One-Handed`), center-highlighted primary candidate slot, and accented `Enter` keycap, and `./gradlew :openkey-core:test :app:testDebugUnitTest :app:assembleDebug` passes 100%.
