# Architecture Decision Records: Native Android Vietnamese Keyboard for Large-Screen Phones (`2026-11-02-android-large-phone-keyboard`)

---

## `ADR-001` — Multi-Module Pure JVM `:openkey-core` + Android `:app` Split (`REQ-001`)
- **Context**: The Vietnamese composition engine (`VietnameseEngine`, `VietnameseEnginePhonotactics`, `BilingualAutoSwitchEngine`, `AutoWordingEngine`, `VietnameseDictionary`, `SmartSwitchStore`, `LargeScreenLayoutMetrics`, `KeyboardGestureController`) requires deterministic, sub-second TDD verification across hundreds of Telex/VNI, phonotactic, bilingual lookback, and gesture test cases (`REQ-001`, `REQ-002`, `REQ-003`, `REQ-004`). Coupling core engine classes to `android.inputmethodservice.InputMethodService` or `android.view.KeyEvent` would force tests onto slow Robolectric or Android emulator instances.
- **Decision**: Structure `Sources/OpenKey/android/` as a multi-module Gradle build with two modules:
  1. `:openkey-core` (`org.jetbrains.kotlin.jvm`): 100% pure Kotlin JVM module with zero Android SDK dependencies containing all composition, phonotactic, dictionary, bilingual auto-switch, auto-wording, layout metric calculation, and gesture state-machine logic.
  2. `:app` (`com.android.application`, `minSdk = 29`, `targetSdk = 35`): Thin Android platform shell containing `OpenKeyImeService`, `InputConnectionCommitter`, `InputContextEvaluator`, Jetpack Compose Material 3 views, and `SettingsActivity`, marked `android:directBootAware="true"` with zero `android.permission.INTERNET` permission.
- **Trade-offs & Risks**: Maintaining a clean boundary between `:openkey-core` and `:app` requires passing value-type abstractions (`EditorContext`, `EngineAction`, `LayoutConfig`) instead of raw Android `EditorInfo` or `InputConnection` objects into `:openkey-core`.
- **Rejected Alternatives**:
  - Single-module `:app` project with all Kotlin classes under `app/src/main/java` (rejected because Android unit test compilation and resource processing slow down TDD feedback loops and risk accidental `android.*` imports inside core engine logic).
  - Bridging the legacy C++ engine via Android NDK / JNI (rejected because `OpenKeySwiftCore` already eliminated C++ memory safety hazards and ported `BilingualAutoSwitchEngine` and `AutoWordingEngine` to high-level memory-safe code).
- **Consequences**: `:openkey-core:test` executes in `< 2s` on the local JVM with 100% deterministic reproducibility, while `:app` remains a thin, auditable Android lifecycle and Compose UI layer.

---

## `ADR-002` — 1:1 Pure Kotlin Port of `OpenKeySwiftCore` Bitmask & State Engine (`REQ-002`)
- **Context**: `OpenKeySwiftCore` solved numerous subtle Vietnamese composition defects over multiple iterations, including `"tiiếng"` diphthong vowel duplication (`handleModernMark` Rule 3.1 and `canModifyFlag == false` purity), `CHR(idx)` out-of-bounds reads after `KEY_DELETE`, `keyStates`/`stateIndex` desynchronization, and `gi-`/`qu-` backward vowel boundary scanning (`"giới"`, `"giường"`, `"gièo"`) (`REQ-002`).
- **Decision**: Port `VietnameseData.kt`, `VietnameseEngine.kt`, and `VietnameseEnginePhonotactics.kt` to `:openkey-core` preserving exact unsigned 32-bit syllable bitmask semantics (`UInt` extensions: `baseKey`, `isCaps`, `hasToneMark`, `toneMark`, `hasCircumflexOrStroke`, `hasHornOrBreve`, `hasAnyDiacritic`, `isAutoTone`, `isStandaloneW`), `CHR(idx)` bounds guards returning `KEY_EMPTY = 256u`, and `ReentrantLock.withLock` synchronization.
- **Trade-offs & Risks**: Using Kotlin `UInt` (`UIntArray` for `typingWord` and `keyStates`) requires explicit `.toUInt()` / `.toInt()` conversions at array index boundaries, which is mitigated by inline helper extensions.
- **Rejected Alternatives**: Rewriting a brand-new regex or string-based Telex parser for Android (rejected because string-based parsers fail on arbitrary keystroke orderings, double-key undo, `gi-`/`qu-` boundaries, and multi-word backspace history).
- **Consequences**: Complete behavioral and test-suite parity between macOS `OpenKeySwiftCore` and Android `:openkey-core`.

---

## `ADR-003` — Bilingual Vietnamese + English Code-Switching with `droppedKeys` & 2-Word Lookback (`REQ-003`)
- **Context**: Mobile users frequently type mixed Vietnamese and English sentences in chat apps (`Zalo`, `Messenger`, `Slack`, `Telegram`, `Discord`) without tapping the language switch button. Standard Telex corrupts English words containing `s/f/r/x/j/w` or doubled letters (`"test"` → `"tét"`, `"cheese"` → `"chees"`, `"is good"` → `"í good"`) (`REQ-003`).
- **Decision**: Port `BilingualAutoSwitchEngine.kt` and `VietnameseDictionary.kt` into `:openkey-core`, tracking mid-word Telex undo keystrokes in `droppedKeys` (`reconstructedRawKeys()`), repairing doubled-tone escapes (`"mixx "` → `"mix "`), checking standalone English priority collisions (`"test"`, `"list"`, `"more"`, `"view"`, `"docs"`), and executing 1–2 word look-back restoration (`previousWordHistory`) across spaces when a two-word English phrase (`"is good"`, `"in case"`, `"for sure"`, `"of course"`) is detected.
- **Trade-offs & Risks**: Look-back across spaces requires `InputConnectionCommitter` to delete back across the previous word (`prevCharCount + 1 + currentCharCount`) within a single `beginBatchEdit()`/`endBatchEdit()` transaction; works reliably because we use Batch Direct Replacement rather than locked composing spans.
- **Rejected Alternatives**: Requiring users to manually tap the `VI/EN` globe button before every English word (rejected because code-switching happens mid-sentence every few words).
- **Consequences**: Seamless bilingual Vietnamese + English typing on Android with zero manual language switching.

---

## `ADR-004` — Lock-Isolated `AutoWordingEngine` with Diacritic-Preserving Stem Ranking (`REQ-004`)
- **Context**: On touch keyboards, a top candidate strip significantly accelerates typing and fixes fat-finger transpositions (`tineg` → `"tiếng"`), provided candidate computation never blocks touch input and respects vowel modifiers (`"giơi"` → `"giới"`) (`REQ-004`).
- **Decision**: Isolate `AutoWordingEngine.kt` from `VietnameseEngine.kt` using `OKWordContext` snapshots and an optional `phonotacticRepairHook` lambda. Synchronize all mutable candidate and frequency maps under `ReentrantLock`, persist `userFrequencies` (`Map<String, Int>`) and `customShorthands` (`Map<String, String>`) via `OpenKeySettingsStore`, and emit candidate list updates via Kotlin `StateFlow<List<Candidate>>` to the Compose UI.
- **Trade-offs & Risks**: Keeping the dictionary corpus in memory (`VietnameseDictionary.kt`) consumes ~1.5 MB of heap, which is < 1% of an Android IME process budget on modern devices.
- **Rejected Alternatives**: Querying Android's system `UserDictionary` ContentProvider on every keystroke (rejected due to binder IPC latency and inconsistent OEM implementations).
- **Consequences**: Sub-millisecond candidate updates after every keystroke, adaptive user frequency ranking, and custom shorthand expansion on `Space`.

---

## `ADR-005` — Atomic Batch Direct Replacement (`beginBatchEdit` / `deleteSurroundingText` / `commitText`) over `setComposingText` (`REQ-005`)
- **Context**: Android's `InputConnection.setComposingText` underlines the active word and delegates composition state to the target `EditText` or `WebView`. In Chrome omnibox, Google Docs, Notion, Slack, Discord, and React Native inputs, `setComposingText` frequently triggers premature autocomplete suggestions, duplicates syllables on space, or drops characters when backspacing (`REQ-005`).
- **Decision**: Implement `InputConnectionCommitter.kt` using **Batch Direct Replacement**:
  1. Wrap every keystroke replacement in `ic.beginBatchEdit()` ... `ic.endBatchEdit()`.
  2. Call `ic.deleteSurroundingText(backspaceCount, 0)` followed by `ic.commitText(newText, 1)`.
  3. Never maintain an underlined composing span via `setComposingText`.
  4. In `InputContextEvaluator.kt`, inspect `EditorInfo.inputType` and `EditorInfo.packageName` on `onStartInputView` to automatically bypass Vietnamese composition on password fields, URIs, email fields, numeric pads, `TYPE_TEXT_FLAG_NO_SUGGESTIONS`, and terminal/remote-desktop apps (`com.termux`, etc.).
- **Trade-offs & Risks**: Because the target editor sees committed characters rather than an active composing span, cursor movement outside the keyboard (e.g., user tapping in the middle of a paragraph) must reset the engine session via `InputMethodService.onUpdateSelection(...)` when the selection moves outside the expected cursor delta.
- **Rejected Alternatives**: Using `setComposingText` by default (rejected due to underline visual noise, WebView duplication bugs, and inability to perform 2-word bilingual look-back after space).
- **Consequences**: Zero underline artifacts, rock-solid compatibility with WebViews and cross-platform apps, and clean `onUpdateSelection` session reset when the user taps elsewhere in the text field.

---

## `ADR-006` — Per-Package Language Persistence in `SmartSwitchStore` (`REQ-006`)
- **Context**: Users consistently type Vietnamese in messaging apps (`com.zing.zalo`, `com.facebook.orca`) and English in code/terminal/search apps (`com.termux`, `com.github.android`). Toggling `VI/EN` manually on every app switch wastes thumb taps (`REQ-006`).
- **Decision**: Port `SmartSwitchStore.kt` into `:openkey-core` and invoke it in `OpenKeyImeService.onStartInputView(editorInfo, restarting)` using `editorInfo.packageName`. Persist the package-to-language map in device-protected `SharedPreferences`.
- **Trade-offs & Risks**: Bounded map size (~100 installed apps) takes `< 4 KB` on disk.
- **Rejected Alternatives**: Relying on `AccessibilityService` to detect foreground app changes (rejected because `EditorInfo.packageName` is already provided directly to `InputMethodService.onStartInputView` with zero extra permissions).
- **Consequences**: Automatic per-app language memory with zero Accessibility permission requirement.

---

## `ADR-007` — Samsung Galaxy A37 One UI Stock Keyboard Layout Parity & Ergonomics (`REQ-007`, `REQ-020`)
- **Context**: The user's daily driver is a **Samsung Galaxy A37** (`6.7"` Super AMOLED, `1080 × 2340` FHD+, `19.5:9` aspect ratio, `360dp × 780dp` or `411dp × 891dp` logical viewport) running Samsung One UI, and the user explicitly requires **minimum change from the current stock Samsung Keyboard** so existing thumb muscle memory transfers with zero friction (`REQ-007`, `REQ-020`).
- **Decision**: Implement `PhoneLayoutMetrics.kt` and `KeyboardLayoutDefinition.kt` in `:openkey-core` to mirror the exact stock Samsung One UI 6/7 Keyboard geometry and visual theme:
  1. **Samsung One UI 5-Row Proportions**: `44dp` Top Suggestion/Toolbar Strip, `42dp` Number Row (`1–0`), `52dp` Letter Rows (`×3`, with an exact `5%` left and `5%` right horizontal inset on the `A–L` home row), and `50dp` Bottom Row (`!#1` [`14%`], `🌐` [`10%`], `,` [`9%`], `Spacebar` [`42%`, labeled `"Tiếng Việt"` / `"English (US)"`], `.` [`9%`], `Enter` [`16%`]) with `4dp` horizontal gap, `5dp` vertical gap, and `7dp` keycap corner radius.
  2. **Samsung One UI Symbol Pages (`!#1`, `1/2`, `2/2`, `ABC`) & Top-Right Sub-Labels**: Replicate Samsung Keyboard's exact secondary symbol sub-labels on letter keys and its 2-page `!#1` symbol layout (`1/2` and `2/2`).
  3. **Samsung One UI Light & Dark Color Palette**: Match Samsung Keyboard's `#E8EAED` light background / `#FFFFFF` `7dp`-radius keycaps (`#DCE0E8` pressed) / `#D6D9E0` modifier keys (`#C4C9D4` pressed) / `#0072DE` accented `Enter` key and `#1B1B1F` dark background / `#2C2C32` keycaps (`#3E3E47` pressed) / `#222227` modifier keys (`#34343D` pressed) / `#387AFF` accented `Enter` key.
  4. **Galaxy A37 Bottom Chin & One-Handed Mode**: Default `14dp` portrait bottom chin margin above the One UI gesture bar (`0..48dp` configurable), `heightScalePercent` (`85..125%`), One-Handed `82%` docked mode (`LEFT | RIGHT | OFF` with `18%` Swap/Expand gutter), and `38dp` landscape auto-compact mode.
- **Trade-offs & Risks**: Matching Samsung One UI's exact key weights (`5%` home-row inset, `15%` modifier width, `🌐` bottom-row language key, `!#1` / `1/2` symbol pages) rather than generic Material 3 pill buttons requires custom key geometry definitions in `KeyboardLayoutDefinition.kt`, which is straightforward in Jetpack Compose `Row`/`Box` layouts.
- **Rejected Alternatives**: Designing a custom Material Expressive pill keyboard or prototype toolbar with scattered pill buttons (rejected because the user explicitly requested authentic Samsung Galaxy A37 One UI keyboard ergonomics and legibility).
- **Consequences**: Switching from Samsung Keyboard to OpenKey on the Galaxy A37 feels 100% native and familiar to the user's thumbs while delivering OpenKey's Vietnamese and bilingual engine under the hood.

---

## `ADR-008` — Pure State-Machine Gesture Controller for Spacebar Trackpad & Backspace Swipe-Delete (`REQ-008`)
- **Context**: Repositioning the text cursor by tapping inside text on a high-DPI 6.8" screen is imprecise, and tapping Backspace repeatedly to delete a mistyped long word is slow (`REQ-008`).
- **Decision**: Implement a pure, unit-testable `KeyboardGestureController.kt` in `:openkey-core` consumed by Compose pointer input modifiers:
  1. **Spacebar Horizontal Drag**: Accumulates `deltaX`; once `abs(totalDragDp) >= 10f`, transitions to `TRACKPAD_ACTIVE` and emits `CursorMove(steps = (deltaDp / 12f).toInt())` while suppressing the space key commit on pointer up.
  2. **Backspace Left Swipe**: Accumulates negative `deltaX` on the `⌫` key; every `-24dp` threshold emits `DeletePreviousWord` (deleting back to the preceding whitespace boundary via `InputConnection.getTextBeforeCursor`), while holding stationary (`>= 400ms`) triggers `50ms` character repeat deletion.
  3. **Long-Press Popup (`220ms`)**: Triggers secondary symbol or precomposed Vietnamese vowel selection (`ă, â, đ, ê, ô, ơ, ư`).
- **Trade-offs & Risks**: Horizontal swipe on the spacebar must not conflict with Android system edge-back gestures; because the spacebar sits in the central `50%` of the keyboard width (well away from the `24dp` left/right screen edges), zero conflict occurs.
- **Rejected Alternatives**: Full-keyboard glide/swipe typing (rejected for initial scope because Vietnamese Telex tone keys appear at the end of syllables after vowel clusters, creating severe ambiguity in spatial path decoding).
- **Consequences**: Fast, accurate cursor positioning and whole-word deletion with full JVM unit test coverage.

---

## `ADR-009` — Hardware Keyboard Interception via `onKeyDown` / `onKeyUp` (`REQ-009`)
- **Context**: Flagship large phones (e.g., Galaxy S Ultra with Samsung DeX, Pixel Pro with USB-C/Bluetooth keyboards) are frequently paired with physical keyboards where Android's stock hardware layout lacks OpenKey Telex/VNI and bilingual auto-restore (`REQ-009`).
- **Decision**: Implement `HardwareKeyMapper.kt` in `:openkey-core` mapping Android `KeyEvent.KEYCODE_*` constants to OpenKey `KEY_*` codes, and override `onKeyDown` / `onKeyUp` in `OpenKeyImeService` to handle `Alt + Z` and `Ctrl + Space` language toggling (with repeat suppression and key-up swallowing) and route printable keys through `VietnameseEngine` + `InputConnectionCommitter`.
- **Trade-offs & Risks**: Modifier combinations (`Ctrl+C`, `Ctrl+V`, `Alt+Tab`, `Meta+*`) must pass through untouched (`super.onKeyDown`) after resetting the engine session.
- **Rejected Alternatives**: Ignoring hardware key events in `OpenKeyImeService` (rejected because external keyboard users on flagship phones would lose Vietnamese typing whenever OpenKey is active).
- **Consequences**: Seamless desktop-class OpenKey typing on external keyboards and Samsung DeX.

---

## `ADR-010` — Jetpack Compose Lifecycle Host in `InputMethodService` & Direct-Boot Settings (`REQ-010`)
- **Context**: `android.inputmethodservice.InputMethodService` does not subclass `ComponentActivity`, so hosting a `ComposeView` inside `onCreateInputView()` requires providing a `LifecycleOwner`, `ViewModelStoreOwner`, and `SavedStateRegistryOwner` attached to the IME window decor view (`REQ-007`, `REQ-010`). Additionally, an IME with `android:directBootAware="true"` is instantiated before the user unlocks the phone after reboot, when credential-encrypted storage is unavailable (`REQ-001`, `REQ-010`).
- **Decision**:
  1. Implement `ImeComposeLifecycleOwner` implementing `LifecycleOwner`, `ViewModelStoreOwner`, and `SavedStateRegistryOwner`, binding it via `setViewTreeLifecycleOwner`, `setViewTreeViewModelStoreOwner`, and `setViewTreeSavedStateRegistryOwner` on the IME window's root view.
  2. Back `OpenKeySettingsStore` with an interface `KeyValueStorage` implemented by `SharedPreferencesStorage(context.createDeviceProtectedStorageContext())` on Android and `InMemoryKeyValueStorage` in `:openkey-core` JVM unit tests.
- **Trade-offs & Risks**: Storing settings and custom shorthands in device-protected storage means they are accessible while the device is locked; since settings contain only keyboard preferences and user shorthands (and never passwords or keystroke logs), this is safe and required for lock-screen typing.
- **Rejected Alternatives**: Using XML `KeyboardView` (deprecated in Android API 29) or credential-encrypted `SharedPreferences` (crashes with `IllegalStateException` when typing on the lock screen after reboot).
- **Consequences**: Crash-free Jetpack Compose Material 3 rendering inside `InputMethodService` and full Direct Boot lock-screen compatibility.

---

## `ADR-011` — Unified `KeyboardSessionController` & Live `EditorUiState` Reactivity (`REQ-011`)
- **Context**: Previously, `OpenKeyImeService` and `KeyboardScreen` duplicated keystroke handling logic (`getWordContext`, `handleKeyEvent`, `didProcessKeyEvent`, `commitBatch`), passed `enterActionLabel` only once when `ComposeView` was first created, bypassed Vietnamese only on hardware keys (leaving touch keys processing Vietnamese inside password/URI/email fields!), and always passed `performEditorAction(0)` on `Enter` (`REQ-011`).
- **Decision**: Introduce `KeyboardSessionController.kt` in `:openkey-core` as the single source of truth for active editor context (`EditorUiState`), touch key actions (`onKeyAction`), hardware key events (`onHardwareKeyDown`/`onHardwareKeyUp`), candidate selection (`onCandidateSelected`), and cursor selection tracking (`onStartInput`, `onUpdateSelection`). Extend `InputEvaluation` with `imeActionId: Int` and `shouldSendNewlineOnEnter: Boolean`, and notify `KeyboardScreen` via a live listener whenever `EditorUiState` changes on `onStartInputView`.
- **Trade-offs & Risks**: Centralizing session orchestration in `:openkey-core` requires `KeyboardSessionController` to communicate with Android's `InputConnectionCommitter` strictly through `TextCommitterTarget`, which also makes the entire touch + hardware + `EditorInfo` pipeline 100% unit-testable on the JVM.
- **Rejected Alternatives**: Duplicating `bypassVietnamese` and `imeActionId` checks separately in `KeyboardScreen.kt` and `OpenKeyImeService.kt` (rejected due to state drift between touch and hardware paths).
- **Consequences**: Identical, bug-free behavior across touch and physical keyboards, instant `Enter` key label/action reactivity on field switches, and strict Vietnamese bypass in password/URI/email/terminal fields.

---

## `ADR-012` — Commit-First Keystroke Pipeline, Static Dictionary Lookup Tables & Generation-Tagged Async Candidates (`REQ-012`, `REQ-015`)
- **Context**: On a 120Hz Samsung Galaxy A37 (`8.33ms` frame budget), profiling the keystroke path revealed three latency hazards (`REQ-012`, `REQ-015`):
  1. Both `VietnameseEngine.handleKeyEvent` and `KeyboardScreen` were calling `getWordContext` and `AutoWordingEngine.didProcessKeyEvent` synchronously **before** `batchCoordinator.commitBatch` committed the character to `InputConnection`.
  2. `VietnameseDictionary.stripVietnameseDiacritics` and `canonicalTelexKey` allocated new 66-entry `Map` and `Set` instances on every call.
  3. `VietnameseDictionary.shared` was lazily initialized on the first keystroke on the UI thread.
- **Decision**:
  1. Refactor `VietnameseEngine` and `KeyboardSessionController` into a **Commit-First Pipeline**: `VietnameseEngine.handleKeyEvent` processes only the syllable transformation (and pre-keystroke shorthand intercept when enabled), `KeyboardSessionController` commits the resulting `HookSnapshot` to `TextCommitterTarget` **immediately** (`< 0.1ms`), and only then triggers post-keystroke candidate updates.
  2. Hoist `DIACRITIC_STRIP_MAP`, `TELEX_BASE_MOD_MAP`, `U_HORN_CHARS`, and `O_HORN_CHARS` to static constants in `VietnameseDictionary` and add `VietnameseDictionary.prewarmAsync()` called from `OpenKeyImeService.onCreate()`.
  3. Add generation-tagged asynchronous candidate execution (`asyncCandidateExecutionEnabled`, `AtomicLong` generation counter, single-threaded daemon worker) to `AutoWordingEngine` so rapid keystrokes never block the UI thread and stale candidate computations are dropped.
- **Trade-offs & Risks**: Asynchronous candidate emission means candidates arrive ~0.5–2ms after the character is already on screen; keeping a synchronous default (`asyncCandidateExecutionEnabled = false`) for unit tests and enabling async mode in `OpenKeyImeService` preserves both deterministic JVM tests and 120Hz UI smoothness.
- **Rejected Alternatives**: Running dictionary candidate sorting on the main thread before `commitText` (rejected because it adds unnecessary jitter to every keystroke).
- **Consequences**: Sub-`0.2ms` hot-path keystroke commit latency (`> 40×` faster than the `8.33ms` 120Hz frame budget) and zero cold-start freeze on first keystroke.

---

## `ADR-013` — Zero-IPC-Read Spacebar Trackpad Cursor Control (`REQ-013`)
- **Context**: During Spacebar horizontal trackpad dragging at 120Hz, `InputConnectionCommitter.moveCursorBy(deltaChars)` previously called `ic.getExtractedText(ExtractedTextRequest(), 0)` on every `12dp` step. `getExtractedText` copies the entire text buffer across Binder IPC from the target app, causing frame drops in long documents (`REQ-013`).
- **Decision**: Track live selection offsets (`currentSelStart`, `currentSelEnd`, `hasKnownSelection`) inside `BatchReplacementCoordinator` via `onStartInputView(info.initialSelStart, info.initialSelEnd)` and `onUpdateSelection(...)`, and dispatch cursor movement in `InputConnectionCommitter.moveCursorBy(deltaChars)` using `KEYCODE_DPAD_LEFT` / `KEYCODE_DPAD_RIGHT` key events (or tracked selection offset via `SelectionTracker`) without ever invoking `getExtractedText`.
- **Trade-offs & Risks**: Using DPAD key events or tracked selection offsets avoids reading the full document length across Binder IPC; Android `EditText` and `WebView` clamp cursor bounds natively when handling DPAD or `setSelection`.
- **Rejected Alternatives**: Calling `getExtractedText` or `getTextBeforeCursor(10000, 0)` on every pointer move event (rejected due to synchronous Binder IPC stalls at 120Hz).
- **Consequences**: Zero Binder read stalls during Spacebar trackpad cursor dragging.

---

## `ADR-014` — Zero-Recomposition Key Grid Isolation, Cached Layer Layouts & Single-Pass `drawBehind` Keycap Rendering (`REQ-014`)
- **Context**: In `KeyboardScreen.kt`, holding `candidates` state at the root composable caused all 45 `KeyButton` composables across 5 rows to re-evaluate on every keystroke whenever candidates changed. Simultaneously, `KeyboardLayoutDefinition.getLayer(...)` allocated fresh `KeyRow` and `KeyModel` lists on every recomposition, and `KeyButton.kt` chained `.shadow().clip().background().border()` modifiers (creating multiple outline/RenderNode layers per key) (`REQ-014`).
- **Decision**:
  1. Cache `KeyboardLayerDef` instances in `KeyboardLayoutDefinition` keyed by `LayerCacheKey(layer, isShifted, language, imeActionLabel)` in a `ConcurrentHashMap`.
  2. Extract a dedicated `LiveCandidateStripHost` composable that subscribes to `autoWordingEngine.onCandidatesChanged` locally, isolating candidate recompositions strictly to the `42dp` top strip.
  3. Replace `.shadow().clip().background().border()` in `KeyButton.kt` with a single `Modifier.drawBehind` pass that draws the `6dp` rounded keycap rect, subtle bottom shadow bevel when unpressed, and `1dp` border directly on the Canvas.
- **Trade-offs & Risks**: Custom `drawBehind` rendering draws a deterministic 1dp bottom bevel instead of a blurred elevation shadow, which actually matches Samsung One UI's flat keycap bevel more closely while eliminating 45 hardware elevation layers.
- **Rejected Alternatives**: Keeping `candidates` state at the top of `KeyboardScreen` and relying on `.shadow()` per key (rejected due to unnecessary 45-key recompositions and RenderNode overhead on every keystroke).
- **Consequences**: Zero key-grid recompositions when candidates update, zero `KeyboardLayerDef` allocations during typing, and minimal GPU overdraw at 120Hz.


---

## `ADR-015` — Phone-Dedicated Layout Naming (`PhoneLayoutMetrics`) & Removal of Physical Keyboard Interception (`REQ-007`, `REQ-009`, `REQ-011`)
- **Context**: Modern smartphones—including the user's daily-driver **Samsung Galaxy A37** (`6.7"` FHD+ `1080 × 2340`)—have standardized around `6.5"`–`6.8"` screens, whereas Android SDK terminology reserves `"LargeScreen"` for tablets and foldables (`sw >= 600dp`). Using `LargeScreenLayoutMetrics` and `LargeScreenLayoutConfig` for phone geometry creates ambiguity between phone and tablet code (`REQ-007`). Furthermore, the Galaxy A37 is used strictly as a handheld touch-typing phone, so keeping physical USB/Bluetooth keyboard mapping (`HardwareKeyMapper.kt`, `onHardwareKeyDown`, `onHardwareKeyUp`, `processHardwareKey` from `ADR-009`) adds unnecessary non-phone code paths (`REQ-009`, `REQ-011`).
- **Decision**: Supersede the class naming in `ADR-007` and the hardware-key interception in `ADR-009`:
  1. Rename `LargeScreenLayoutMetrics.kt` → `PhoneLayoutMetrics.kt` (`PhoneLayoutConfig`, `PhoneLayoutMetrics`) and `LargeScreenErgonomicsAndGestureTest.kt` → `PhoneErgonomicsAndGestureTest.kt` across `:openkey-core` and `:app`.
  2. Delete `HardwareKeyMapper.kt` from `:openkey-core` and remove `onHardwareKeyDown`, `onHardwareKeyUp`, `processHardwareKey`, and `onKeyDown`/`onKeyUp` hardware key interception from `KeyboardSessionController.kt` and `OpenKeyImeService.kt`.
- **Trade-offs & Risks**: Physical USB/Bluetooth keyboards connected to the phone will use Android's default system key handling instead of OpenKey's IME interception, which matches the user's explicit phone-only requirement and keeps future tablet/desktop support cleanly separated.
- **Rejected Alternatives**: Keeping `LargeScreenLayoutMetrics` naming and `HardwareKeyMapper.kt` inside the phone codebase (rejected because the user requested renaming layout classes to be explicitly phone-specific and removing physical keyboard handling).
- **Consequences**: `:openkey-core` and `:app` are 100% dedicated to on-screen phone touch typing on the Samsung Galaxy A37 with zero tablet/desktop ambiguity.


---

## `ADR-016` — GitHub Actions Android CI/CD Pipeline & Portable Gradle Properties (`REQ-016`)
- **Context**: Publishing `Sources/OpenKey/android/` to GitHub (`origin`: `git@github.com:vinhthang/OpenKey.git`) requires an automated GitHub Actions build that compiles `:openkey-core` and `:app`, runs all unit tests, and uploads the installable APK artifact (`REQ-016`). Hardcoding a local macOS JDK path (`org.gradle.java.home=/Users/thanghoang/...`) in `gradle.properties` or committing `local.properties` (`sdk.dir=/Users/thanghoang/...`) breaks Linux CI runners (`ubuntu-latest`).
- **Decision**:
  1. Remove `org.gradle.java.home` from `Sources/OpenKey/android/gradle.properties` and configure `Sources/OpenKey/android/gradlew` to resolve JDK 21 automatically when `JAVA_HOME` is unset on local macOS while honoring `JAVA_HOME` set by `actions/setup-java@v4` on GitHub Actions.
  2. Add `Sources/OpenKey/android/.gitignore` ignoring `.gradle/`, `build/`, `*/build/`, and `local.properties`.
  3. Create `.github/workflows/android-ci.yml` running on `ubuntu-latest` with JDK 21 (`temurin`), executing `./gradlew :openkey-core:test :app:testDebugUnitTest :app:assembleDebug`, uploading `OpenKey-Android-A37-debug.apk` via `actions/upload-artifact@v4`, and attaching the APK to GitHub Releases on `v*` tags.
- **Trade-offs & Risks**: Running Android builds on `ubuntu-latest` is `3×` faster and consumes `10×` fewer GitHub Actions minutes than `macos` runners while using the standard pre-installed Android SDK (`$ANDROID_HOME`) on GitHub-hosted Ubuntu images.
- **Rejected Alternatives**: Combining the Android Gradle build into `macos-ci.yml` on `macos-26` (rejected because macOS runners do not pre-install the Android SDK platform-tools/build-tools 35 and decouples Android CI status from macOS Swift CI).
- **Consequences**: Every push to GitHub automatically verifies `:openkey-core` and `:app` unit tests and produces a downloadable Samsung Galaxy A37 APK artifact on GitHub Actions.


---

## `ADR-017`: Android Debug Mode, Version-Scoped Persistent File Logger (`OpenKeyLogger.kt`) & In-App Log Viewer (`REQ-017`, `REQ-010`, `REQ-011`)
- **Date**: `2026-11-02`
- **Status**: `Accepted`
- **Context**: On macOS (`REQ-013`, `OpenKeyLogger.swift`), OpenKey provides an opt-in Debug Mode (`debugModeEnabled`) that logs subsystem events (`LIFECYCLE`, `SETTINGS`, `ENGINE`, `AUTO_WORDING`, `SMART_SWITCH`) to `openkey-debug.log` with automatic keystroke redaction in secure fields, version-stamp retention, and size-cap rotation. On the Samsung Galaxy A37, inspecting `adb logcat` requires connecting to a computer, so users need both persistent file logging (`openkey-debug.log`) and an in-app **Debug & Diagnostics** viewer/clipboard exporter directly inside `SettingsActivity`.
- **Decision**:
  1. Implement `OpenKeyLogger.kt` in `:openkey-core` (`com.tuyenmai.openkey.core`) with `OpenKeyLogCategory` (`LIFECYCLE`, `SETTINGS`, `SESSION`, `ENGINE`, `AUTO_WORDING`, `SMART_SWITCH`), a single-thread background daemon writer (`"openkey-debug-logger"`), lazy lambda evaluation (`log(category) { ... }` returning immediately when `!isEnabled`), version-stamp retention (`# OpenKeyAndroidVersionStamp: <stamp>`), size-cap rotation (`maxFileSizeBytes`, default `5 MB`), and `readRecentLogs(maxLines: Int = 200)` / `clearLog()`.
  2. Add `debugModeEnabled: Boolean` (`KEY_DEBUG_MODE_ENABLED = "DebugModeEnabled"`, default `false`) to `OpenKeySettingsStore`, automatically syncing `OpenKeyLogger.shared.isEnabled = debugModeEnabled`.
  3. Wire `OpenKeyLogger.shared.log(...)` across `OpenKeySettingsStore`, `KeyboardSessionController` (redacting keystrokes when `editorUiState.isSecureField == true`), `VietnameseEngine`, `AutoWordingEngine`, and `OpenKeyImeService` (configuring the log directory at `context.createDeviceProtectedStorageContext().filesDir/logs`).
  4. Add a localized (`VI | EN`) **Debug & Diagnostics** card in `SettingsActivity.kt` (`OpenKeyL10n.Debug`) with a `Debug Mode` switch, live scrollable log output (`readRecentLogs`), a **Copy Logs** button (`ClipboardManager`), and a **Clear Log** button.
- **Trade-offs & Risks**:
  - *Trade-off*: Writing debug logs to internal storage adds background I/O when `debugModeEnabled == true`.
  - *Mitigation*: `OpenKeyLogger.log` uses a lazy `() -> String` lambda that exits in `< 2 ns` when `isEnabled == false` (default), dispatches file writes asynchronously to a daemon thread when enabled, caps log file size at `5 MB`, and strictly redacts keystrokes in secure/password fields.
- **Rejected Alternatives**:
  - *Relying only on `android.util.Log` (`logcat`)*: Rejected because reading `logcat` on a physical Samsung Galaxy A37 requires USB debugging and a PC, whereas an in-app log viewer + clipboard copy works standalone on the phone.

---

## `ADR-018`: Cross-Platform GitHub Actions Path Filtering & `@MainActor` Test Synchronization (`REQ-016`)
- **Date**: `2026-11-02`
- **Status**: `Accepted`
- **Context**: In GitHub Actions run `41440523284`, pushing Android specification updates triggered `.github/workflows/macos-ci.yml` (which lacked path filters), and `OpenKeyEventTapTests.openKeySettingsStoreSync()` failed intermittently on `macos-26` because `openKeySettingsStoreSync()` ran on a background Swift Testing cooperative thread (`Thread.isMainThread == false`), causing `OpenKeySettingsStore.language.didSet` to dispatch `onLanguageChanged` asynchronously via `DispatchQueue.main.async` after `#expect(tracker.invoked)` had already evaluated.
- **Decision**:
  1. Annotate `openKeySettingsStoreSync()` (and any `OpenKeyEventTapTests` mutating `@MainActor`-dispatched `OpenKeySettingsStore` callbacks) with `@MainActor` in `Sources/OpenKey/macOS-Swift/Tests/OpenKeySwiftTests/OpenKeyEventTapTests.swift` so `Thread.isMainThread` is guaranteed `true` and `onLanguageChanged` executes synchronously.
  2. Add `paths:` filters (`Sources/OpenKey/macOS-Swift/**`, `.github/workflows/macos-ci.yml`) to `.github/workflows/macos-ci.yml` so macOS and Android CI pipelines run when their respective platform files or workflows change (plus `workflow_dispatch` and `v*` tags).
- **Trade-offs & Risks**:
  - *Trade-off*: Running `openKeySettingsStoreSync()` on `@MainActor` serializes that test onto the main thread.
  - *Mitigation*: `openKeySettingsStoreSync()` takes `0.001s` and tests UI/settings state callbacks (`@MainActor @Sendable (Int) -> Void`), making `@MainActor` the exact contract boundary.
- **Rejected Alternatives**:
  - *Adding `Thread.sleep` in `openKeySettingsStoreSync()`*: Rejected because sleeping on the main or background thread is brittle and non-deterministic compared to `@MainActor` isolation.


---

## `ADR-019`: Context-Ordered `V` / `E` Homograph Disambiguation (`"sẽ"` vs. `"sex"`) & Tone-Preserving Candidate Ranking (`REQ-018`, `REQ-003`, `REQ-004`)
- **Date**: `2026-11-04`
- **Status**: `Accepted`
- **Context**: Typing `"sẽ"` (`s-e-x` in Telex) in Vietnamese mode was erroneously converted to `"sex"` on `Space` because `"sex"` (along with other English words whose Telex sequences form common Vietnamese words such as `vex` → `"vẽ"`, `max` → `"mã"`, `six` → `"sĩ"`, `tax` → `"tã"`, `lax` → `"lã"`, `moon` → `"môn"`, `noon` → `"nôn"`, `soon` → `"sôn"`, `seen` → `"sên"`, `beef` → `"bề"`, `reef` → `"rề"`, `room` → `"rôm"`, `boots` → `"bốt"`, `roots` → `"rốt"`, `loops` → `"lốp"`) was placed in `englishPriorityWords`, which unconditionally forced English restoration regardless of whether the user was in a Vietnamese (`V`) or English (`E`) context. Additionally, `AutoWordingEngine.computeCurrentWordCandidates` demoted exact matches of `currentSyllable` even when `currentSyllable` already carried an explicit tone mark (`"sẽ"`), causing unaccented `"se"` and `"sex"` to appear ahead of `"sẽ"`.
- **Decision**:
  1. Remove Vietnamese-homograph collision words (`sex`, `vex`, `max`, `six`, `tax`, `lax`, `hex`, `moon`, `noon`, `soon`, `seen`, `seem`, `beef`, `reef`, `room`, `boom`, `doom`, `loom`, `boots`, `roots`, `loops`, `meets`, `keeps`, `moor`, `door`) from unconditional `englishPriorityWords` and place them in `englishLookbackStems` + `englishWords` in both `VietnameseDictionary.kt` and `VietnameseDictionary.swift`.
  2. In `BilingualAutoSwitchEngine.evaluateWordBreakRestore` (both Kotlin and Swift), when `priority == LanguagePriority.ENGLISH_FIRST` (`E`, i.e., after an English word) and `dict.englishWords.contains(fullRawLower)` (and `dict.englishLookbackStems.contains(fullRawLower)`), restore `fullKeys` to English (`"have sex "`, `"at max "`, `"number six "`, `"income tax "`, `"full moon "`). When `priority == LanguagePriority.VIETNAMESE_FIRST` (`V`, default in Vietnamese mode or after a Vietnamese word), keep the composed Vietnamese word (`"sẽ "`, `"anh sẽ "`, `"vẽ "`, `"mã "`, `"sĩ "`, `"tã "`, `"môn "`). When followed by an English word (`"sex is "`, `"sex education "`, `"max value "`), the 2-word look-back (`englishLookbackStems`) restores both words to English.
  3. In `AutoWordingEngine.computeCurrentWordCandidates` (both Kotlin and Swift), only demote `w == currentLower` behind `distinctAccented` when `currentSyllable` has no tone mark (`!hasExplicitToneMark(currentSyllable)`), and ensure `VietnameseDictionary.computeEnglishCandidates` includes exact `englishWords`/`englishLookbackStems` matches (`"sex"`) so `VIETNAMESE_FIRST` (`V`) orders `["sẽ", ..., "sex"]` and `ENGLISH_FIRST` (`E`) orders `["sex", "sẽ", ...]`.
- **Trade-offs & Risks**:
  - *Trade-off*: Typing standalone `"sex "` or `"max "` as the very first word of a Vietnamese-mode session produces `"sẽ "` or `"mã "` unless preceded or followed by an English word (or undone via `xx` escape `sexx ` / `maxx ` or selecting `"sex"` from the candidate bar).
  - *Mitigation*: In Vietnamese mode (`V`), `"sẽ"` (*will/shall*) and `"mã"` (*code*) are orders of magnitude more frequent than standalone single-word `"sex"` or `"max"`, while multi-word English phrases (`"have sex "`, `"sex education "`, `"at max "`, `"max value "`), `sexx ` doubled-tone escape, and the 3-slot candidate bar (`["sẽ", "sẻ", "sex"]`) handle English seamlessly.
- **Rejected Alternatives**:
  - *Keeping `"sex"` in unconditional `englishPriorityWords`*: Rejected because it corrupts `"sẽ"`—one of the most common words in the Vietnamese language—every time a user types Vietnamese.

---

## `ADR-020`: Vietnamese Syllable Protection Against Transposition/Homograph Overwrite (`"thể"` vs. `"there"`) & Standalone-`W` Escape Normalization (`"Why"` vs. `"Wwhy"`) (`REQ-019`, `REQ-002`, `REQ-003`)
- **Date**: `2026-11-05`
- **Status**: `Accepted`
- **Context**: Two high-impact regressions in `V` mode (`LanguagePriority.VIETNAMESE_FIRST`) were identified:
  1. **`"thể"` → `"there"` in `V` Mode**:
     - When `"thể"` is typed in free-order Telex (`t-h-e-r-e`), `fullRawLower` is `"there"` (`dict.englishWords.contains("there") == true`) and `countVowelGroups(fullKeys)` counts `e`...`r`...`e` as `2` vowel groups (`>= 2`), triggering `(!dict.isValidVietnameseSyllable(composedLower) || countVowelGroups(fullKeys) >= 2)` in `BilingualAutoSwitchEngine.evaluateWordBreakRestore` and overwriting the valid single-syllable Vietnamese word `"thể"` with `"there"`.
     - When `"thể"` is typed in standard Telex (`t-h-e-e-r`, `fullRawLower = "theer"`), `VietnameseDictionary.findEnglishTranspositionMatch("theer")` swaps adjacent indices 3 and 4 (`'e'` and `'r'`) to match `"there"`, and Step 5 (`Typo & Transposition Corrections`) in `BilingualAutoSwitchEngine` ran without checking `!dict.isValidVietnameseSyllable(composedLower)` whenever `priority == LanguagePriority.ENGLISH_FIRST`. Compounding this, typing a valid unaccented Vietnamese syllable that happens to be in `englishWords` (e.g., `"con"`, `"hay"`, `"may"`, `"ban"`, `"can"`) falsely set `wasRestoredToEnglish = true` in `V` mode, flipping the next word's `priority` to `ENGLISH_FIRST` and converting `"thể"` (`theer`) into `"there"`.
  2. **`"Why"` (`W-w-h-y` / `w-w-h-y`) → `"Wwhy"` in `V` Mode**:
     - Typing `W` (or `w`) at word start in `V` mode produces standalone `"Ư"` (or `"ư"`). Pressing `w` a second time escapes `"Ư"`/`"ư"` to literal `"W"`/`"w"` inside `VietnameseEnginePhonotactics.insertW` (`typingWord[ii].isStandaloneW && ch == KEY_U`). However, `handleCharacterKey` had already pushed the second `w` into `keyStates` and `rawKeyStates` via `insertState`, and `insertW` returned `WILL_PROCESS` without popping that consumed escape `w`. As a result, `typingWord` held `"Why"` (`3` chars) while `keyStates` and `rawKeyStates` held `"Wwhy"` (`4` chars). Any subsequent sentence capitalization (`. wwhy ` / `. Why `) or raw-key restoration read `fullRawStr` (`"Wwhy"`) and replaced `"Why"` on screen with `"Wwhy"`.
- **Decision**:
  1. **Protect Valid Vietnamese Syllables (`VietnameseDictionary` & `BilingualAutoSwitchEngine` in Kotlin and Swift)**:
     - Precompute `validTelexKeys: Set<String>` from `rawSyllables.map { canonicalTelexKey(it) }` in `VietnameseDictionary` and reject `validTelexKeys.contains(rawLower)` inside `findEnglishTranspositionMatch(rawLower)`.
     - In `BilingualAutoSwitchEngine.evaluateWordBreakRestore` Step 5, require `!dict.isValidVietnameseSyllable(composedLower)` before applying `englishTypoCorrections` or `findEnglishTranspositionMatch` in both `ENGLISH_FIRST` and `VIETNAMESE_FIRST` branches.
     - In `BilingualAutoSwitchEngine.evaluateWordBreakRestore` Step 7 (`VIETNAMESE_FIRST` branch), remove `|| countVowelGroups(fullKeys) >= 2` so `dict.englishWords.contains(fullRawLower)` only restores when `!dict.isValidVietnameseSyllable(composedLower)`. Add `"there"`, `"these"`, `"here"`, `"mere"`, `"were"` to `englishLookbackStems` so English phrases (`"there is "`, `"these are "`, `"in there "`) still restore in English context.
     - When `shouldRestore == false` in `VIETNAMESE_FIRST` (`V`) mode, only mark `isEng = true` (`wasRestoredToEnglish = true`) if `!dict.isValidVietnameseSyllable(composedLower)` (or `composed == "I"`), preventing valid unaccented Vietnamese words (`"con"`, `"hay"`, `"may"`, `"ban"`, `"can"`) from flipping session priority to `ENGLISH_FIRST`.
  2. **Normalize Standalone-`W` Escape Key Buffers (`VietnameseEnginePhonotactics` & `BilingualAutoSwitchEngine` in Kotlin and Swift)**:
     - In `insertW`, when `typingWord[ii].isStandaloneW && ch == KEY_U` reverts standalone `'Ư'`/`'ư'` to `'W'`/`'w'`, pop the consumed escape `w` from `keyStates` (`stateIndex--`) and `rawKeyStates` (`rawStateIndex--`).
     - In `BilingualAutoSwitchEngine` Step 6 (`Sentence Capitalization`), prefer `composed` over `fullRawStr` whenever `dict.englishWords.contains(composedLower) && !hasAnyDiacritic`.
- **Trade-offs & Risks**:
  - *Trade-off*: Precomputing `validTelexKeys` adds ~7,200 strings to `VietnameseDictionary` initialization.
  - *Mitigation*: `VietnameseDictionary.shared` is a lazy singleton prewarmed asynchronously on a background daemon thread via `VietnameseDictionary.prewarmAsync()` (`REQ-012`), adding `< 2ms` one-time startup work and `O(1)` lookup on the hot path.
- **Rejected Alternatives**:
  - *Removing `"there"` from `englishWords`*: Rejected because `"there"` is a core English word needed for English phrases (`"there is "`, `"in there "`, `"over there "`) and candidate completion.

---

## `ADR-021`: Authentic Samsung Galaxy A37 One UI 6/7 Visual Polish, High-Legibility Typography, Dedicated Bottom-Row Globe Key & Custom Canvas Vector Icons (`REQ-020`, `REQ-007`)
- **Date**: `2026-11-05`
- **Status**: `Accepted`
- **Context**: Real-device testing of `OpenKey-Android-A37.apk` on a `6.7"` FHD+ (`1080 × 2340`) phone revealed three critical UI/UX deficiencies compared to the stock **Samsung Galaxy A37 One UI 6/7 Keyboard** and **Gboard**:
  1. **Key Characters & Row Proportions Too Small**: `KeyButton.kt` rendered letter labels at `19.sp` (`FontWeight.Normal`) inside `48dp` portrait rows with `6dp` vertical gap (`42dp` actual keycap height), making letters appear cramped and hard to read at normal holding distance.
  2. **Cluttered Top-Bar Pill Buttons & Missing Bottom-Row Language Key**: `CandidateStripView.kt` placed 4 boxy text pill buttons (`[VI]`, `[Telex]`, `[Full / Left 82%]`, `[⚙]`) across the top strip when idle—which vanished whenever word candidates appeared—and `Row 5` (`KeyboardLayoutDefinition.kt`) lacked a dedicated **Language Switch (`🌐`)** key.
  3. **Prototype-Like Raw Text Glyphs & Flat Unresponsive Keycaps**: `KeyButton.kt` rendered raw Unicode characters (`"⇧"`, `"⇪"`, `"⌫"`, `"↵"`) instead of crisp vector icons, provided no pressed-state keycap fill (`pressedKeycapColor`), and styled `Enter` with the same flat gray (`functionalKeycapColor`) as modifier keys instead of an accented action keycap.
- **Decision**:
  1. **Upgrade Portrait Row Geometry & Keycap Typography (`PhoneLayoutMetrics.kt` & `KeyButton.kt`)**:
     - Increase portrait base heights to `candidateStripHeightDp = 44dp`, `numberRowHeightDp = 42dp`, `alphaRowHeightDp = 52dp`, `bottomRowHeightDp = 50dp`, `keyCornerRadiusDp = 7dp`, `keyHorizontalGapDp = 4dp`, and `keyVerticalGapDp = 5dp` (`totalHeightDp = 306dp`).
     - Increase primary letter typography to **`23.sp`** (`FontWeight.Normal`, with `1.dp` downward offset when a `10.5.sp` top-right secondary symbol is present), uppercase letters to **`21.sp`** (`FontWeight.Medium`), number row keys (`1–0`) to **`20.sp`**, punctuation (`,` / `.`) to **`22.sp`**, and candidate strip primary suggestions to **`17.sp`** (`FontWeight.SemiBold`).
  2. **Dedicated Bottom-Row Language Switch Key (`🌐`) & Clutter-Free Top Strip (`KeyboardLayoutDefinition.kt` & `CandidateStripView.kt`)**:
     - Add a dedicated **Language Switch key (`🌐`, `KeyAction.SwitchLanguage`, `0.10f` weight, `secondaryLabel = "VI"` / `"EN"`)** in `Row 5` (`QWERTY`) between `!#1` (`0.14f`) and `,` (`0.09f`), alongside `Spacebar` (`0.42f`), `.` (`0.09f`), and `Enter` (`0.16f`).
     - Remove the 4 boxy text pill buttons from `CandidateStripView.kt`. Render a clean 3-slot suggestion bar (`[secondary1, primary0 (center highlighted), secondary2]`) when typing, and a minimalist One UI idle toolbar (subtle left mode label + borderless right-side Canvas vector icons for `One-Handed` and `Settings`) when idle.
  3. **Custom Canvas Vector Icons, Pressed Keycap Fill & Accented Enter Key (`KeyButton.kt` & `ThemePalette`)**:
     - Add `pressedKeycapColor` (`0xFFDCE0E8` Light / `0xFF3E3E47` Dark) and `pressedFunctionalKeycapColor` (`0xFFC4C9D4` Light / `0xFF34343D` Dark) to `ThemePalette`.
     - Render custom Canvas vector paths (`KeyboardVectorIcons`) for `Shift` (outline / filled accent / Caps-Lock underlined), `Backspace` (pentagonal key with `×`), `Globe` (`🌐`), `Enter` (`Search` magnifier, `Send` plane, `Go`/`Next` arrow, `Done` check, or `↵` return arrow on an accented `theme.accentColor` keycap), `Settings` gear, and `One-Handed` dock icons.
- **Trade-offs & Risks**:
  - *Trade-off*: Increasing portrait `alphaRowHeightDp` from `48dp` to `52dp` increases total default portrait height from `288dp` to `306dp` (`+18dp`, ~`34.3%` of the Galaxy A37's `891dp` viewport height).
  - *Mitigation*: `306dp` matches the exact vertical footprint of the stock Samsung One UI 6/7 Keyboard with number row enabled on a `6.7"` `19.5:9` display, and users can still scale height between `85%` and `125%` in `SettingsActivity`.
- **Rejected Alternatives**:
  - *Keeping `VI/EN` toggle only in the top toolbar*: Rejected because the top toolbar is replaced by word candidates during typing, hiding the language switch button right when users need it.
  - *Bundling external PNG/VectorDrawable XML resources for keyboard icons*: Rejected in favor of pure Compose `Canvas` / `Path` vector drawing (`KeyboardVectorIcons`) which scales losslessly at any DPI/scale factor, requires zero XML asset lookups on the 120Hz render path, and dynamically adapts stroke/fill to `ThemePalette`.
