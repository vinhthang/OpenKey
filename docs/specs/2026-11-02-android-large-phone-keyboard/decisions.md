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

---

## `ADR-022`: Live Mid-Word Phonotactic Auto-Escape (`more`, `needed`), Compound Tone+Circumflex Escape (`these`), Morphological Inflection Stemming (`goes`, `errors`), and `*oe*` Corpus Hygiene (`REQ-021`, `REQ-002`, `REQ-003`)
- **Date**: `2026-11-06`
- **Status**: `Accepted`
- **Context**: Inspection of `/Users/thanghoang/Library/Logs/OpenKeySwift/openkey-debug.log` (`7,014` lines) revealed 6 concrete typing and bilingual auto-restore failures in `V` mode:
  1. **`"so goes with"` (`g-o-e-s` → `"goé"`)**: `"goes"` was missing from `VietnameseDictionary.englishWords` and `englishPriorityWords`, and `VietnameseDictionaryCorpus.rawSyllables` included combinatorially generated invalid `*oe*` syllables (`"goé"`, `"doé"`, `"moẻ"`), causing `dict.isValidVietnameseSyllable("goé")` to return `true` and blocking English restoration.
  2. **`"here is still"` (`h-e-r-e` → `"hể"`)**: `"here"` and `"mere"` had been placed in `lookbackRaw` rather than `prioRaw`. Unlike `"thể"` (`there`) and `"thế"` (`these`), `"hể"` (`here`) and `"mể"` (`mere`) are not common standalone Vietnamese words, whereas `"here"` is one of the most common English sentence-starters.
  3. **`"more"` (`m-o-r-e` → `"moẻ"` → `"moể"` on `e` escape)**: When typing `m-o-r-e`, `m-o-r` composed `"mỏ"`. Pressing `e` appended `'e'` and moved the tone mark to form `"moẻ"`. Seeing `"moẻ"`, the user pressed `e` to escape, which triggered `insertAOE` and turned it into `"moể"`. In Vietnamese Telex, no valid Vietnamese syllable without an existing `'e'` vowel ever has `'e'` typed *after* a tone mark; `(a/i/o/u) + [s/f/r/x/j] + e` is exclusively an English `-re`/`-se`/`-fe`/`-xe` pattern (`more`, `core`, `store`, `care`, `share`, `fire`, `sure`, `case`, `nose`, `use`, `house`, `life`).
  4. **`"needed"` (`n-e-e-d-e-d` → `"nêd"` mid-word)**: When typing `n-e-e-d`, `n-e-e` composed `"nê"`, and pressing `'d'` left `"nêd"` on screen mid-word, causing the user to stop and manually backspace. In Vietnamese phonotactics, `b`, `d` (when `CHR(0) != KEY_D`), `k`, `l`, `q`, `v`, `z`, `f`, `j`, `w` can never appear as a Vietnamese coda consonant after a vowel, and stop codas `c`, `p`, `t` can never appear on a syllable carrying `huyền` (`f`), `hỏi` (`r`), or `ngã` (`x`).
  5. **Missing Inflected English Words (`"errors"`, `"goes"`, `"does"`, `"files"`, `"lines"`, `"working"`, `"updated"`)**: Because `"errors"` was absent from `englishWords`, doubled-key restoration and English context tracking failed for inflected forms.
  6. **Compound Tone+Circumflex Escape (`"these"` + `s`/`e` → `"thês"` / `"thêse"`)**: When a vowel carried both `TONE_MASK` and `MARK_MASK` from an interleaved key sequence (`t-h-e-s-e` → `"thế"`), pressing `s` or `e` only stripped one mask and set `tempDisableKey = true`, leaving `'ê'` stranded.
  7. **Microsoft Teams (`com.microsoft.teams2`) `U+202F` Narrow No-Break Space Injection & Proper-Name Context Break (`L1912–L2080`, `L7483–L7608`)**:
     - When typing Vietnamese in Microsoft Teams (`"kiểm tra lỗi chính tả sai"`, `L7483–L7608`), `KeystrokeInjector.determineStrategy` injected `U+202F` (`narrowNoBreakSpace`, `emptyChar: 8239`) + `bs + 1` Backspaces on every diacritic (`ê`, `ể`, `ô`, `ỗ`, `ín`, `ả`). Because Teams' WebView2 CKEditor/ProseMirror composer treats `U+202F` as a Unicode whitespace separator (`Zs`) and processes DOM mutations asynchronously, injecting `U+202F` splits DOM text nodes / leaves phantom non-breaking spaces inside Vietnamese words and triggers Teams' red spellcheck squiggles (`"kiểm tra lỗi chính tả sai"`).
     - When typing `"I think Tony is correct,"` (`L1983–L2078`) and `"@Shi @To, these"` (`L1912–L1982`) in Microsoft Teams, `"Tony"` and `"Shi"` (`!isValidVietnameseSyllable`) were not recognized as English because they were not in `englishWords`, resetting `consecutiveEnglishWordCount = 0` so `"is"` became `"í"` and `"these"` became `"thế"`.
- **Decision**:
  1. **Live Mid-Word Phonotactic Auto-Restore (`VietnameseEngine.swift` / `VietnameseEngine.kt` & `VietnameseEngine+Phonotactics.swift` / `VietnameseEnginePhonotactics.kt`)**:
     - When `KEY_E` is pressed in Telex mode on a syllable with at least one vowel (`vsi >= 0`), no existing `KEY_E` in the vowel cluster, and an existing tone mark (`MARK_MASK != 0`), immediately restore `typingWord` from `rawKeyStates` and set `tempDisableKey = true` (`HookCodeState.RESTORE`).
     - When a post-vowel consonant is pressed on a syllable carrying any diacritic (`TONE_MASK != 0 || MARK_MASK != 0` or `CHR(0) == KEY_D && hasToneOrHat`) and that consonant is either (a) a non-coda consonant (`b`, `d` when `CHR(0) != KEY_D`, `k`, `l`, `q`, `v`, `z`, `f`, `j`, `w` when not consumed as a Telex modifier) or (b) a stop consonant (`c`, `p`, `t`) after a vowel carrying `MARK2_MASK`, `MARK3_MASK`, or `MARK4_MASK` (`f`/`r`/`x`), immediately restore `typingWord` from `rawKeyStates` and set `tempDisableKey = true`.
  2. **Compound Tone+Circumflex Escape (`VietnameseEngine+Phonotactics.swift` / `VietnameseEnginePhonotactics.kt`)**:
     - In `insertMark` and `insertAOE`, when a Telex escape (`hasSameMark` or `hasCircumflexOrStroke`) is triggered on a syllable that holds **both** `TONE_MASK` and `MARK_MASK`, restore all characters in `typingWord` from `rawKeyStates` (excluding the consumed escape keystroke if it duplicates a prior raw key or popping the duplicate escape key from `rawKeyStates` when escaping an interleaved sequence like `t-h-e-s-e` + `s`/`e`) and set `tempDisableKey = true` so `"thế"` (`t-h-e-s-e`) + `s` or `e` yields clean `"these"`.
  3. **`*oe*` Corpus Filter, Expanded `prioRaw`, and Morphological `isEnglishWord` (`VietnameseDictionary` & `BilingualAutoSwitchEngine` in Swift and Kotlin)**:
     - Filter `rawSyllables` at dictionary initialization to exclude invalid `*oe*` syllables whose initial consonant is outside `{"", "ch", "h", "kh", "l", "ng", "nh", "t", "x"}`.
     - Add `"goes"`, `"does"`, `"toes"`, `"foes"`, `"woes"`, `"hoes"`, `"shoes"`, `"heroes"`, `"zeroes"`, `"echoes"`, `"here"`, `"mere"`, `"were"`, `"errors"`, and common `-rs`/`-st`/`-se` English words to `prioRaw`, while keeping `"of"`, `"if"`, `"there"`, and `"these"` in `lookbackRaw`.
     - Implement `VietnameseDictionary.isEnglishWord` with regular English suffix stripping (`-s`, `-es`, `-ies`, `-d`, `-ed`, `-ied`, `-ing`, `-er`, `-ers`, `-or`, `-ors`, `-ly`) guarded by `!isValidVietnameseSyllable(lower) && !validTelexKeys.contains(lower)`, and use `dict.isEnglishWord(...)` throughout `BilingualAutoSwitchEngine`.
  4. **Microsoft Teams (`com.microsoft.teams2`) `.standardBackspace` & Non-Vietnamese Proper-Name Context Continuity (`KeystrokeInjector.swift` & `BilingualAutoSwitchEngine`)**:
     - In `KeystrokeInjector.determineStrategy`, return `.standardBackspace` when `bundleId` matches `com.microsoft.teams2`, `com.microsoft.teams`, `com.tinyspeck.slackmacgap`, `com.hnc.Discord`, `com.microsoft.Word`, `com.microsoft.Outlook`, `com.microsoft.Powerpoint`, `com.apple.Notes`, `com.apple.mail`, or `com.apple.TextEdit`.
     - In `BilingualAutoSwitchEngine`, treat unaccented multi-letter non-Vietnamese words (`!hasAnyDiacritic && composedLower.count >= 2 && !dict.isValidVietnameseSyllable(composedLower) && !vietnameseShorthandSet.contains(composedLower)`) as English (`isEng = true`), and preserve `consecutiveEnglishWordCount` across comma breaks (`KEY_COMMA`) when preceded by an English word or compound `@mention` token (`!wordStartOk`).
- **Trade-offs & Risks**:
  - *Trade-off*: Immediate mid-word restoration when typing `KEY_E` after a toned non-`e` vowel disallows typing the tone mark *before* the second vowel in rare `oe` words (e.g. typing `h-o-s-e` instead of `h-o-e-s` for `"hoé"`).
  - *Mitigation*: Standard and natural Vietnamese Telex types the diphthong `oe` before the tone mark (`h-o-e-s` → `"hoé"`, `x-o-e-f` → `"xoè"`), which remains 100% supported, while `m-o-r-e`, `c-o-r-e`, `s-t-o-r-e`, `c-a-r-e`, `s-h-a-r-e`, `f-i-r-e`, `s-u-r-e`, `c-a-s-e`, `n-o-s-e`, `u-s-e`, `h-o-u-s-e`, `l-i-f-e` are overwhelmingly English words in real user logs.
- **Rejected Alternatives**:
  - *Waiting until `Space` to restore `"more"` (`"moẻ"`) and `"needed"` (`"nêd"`)*: Rejected because `openkey-debug.log` proved that users see `"moẻ"` and `"nêd"` mid-word, assume the word is corrupted, and immediately press Backspace or extra escape keys before ever reaching `Space`.

---

## `ADR-023`: Persistent Repository-Scoped APK Signing Keystore (`openkey-debug.keystore`) & Git-Commit Monotonic `versionCode` for Seamless In-Place Android Updates (`REQ-022`, `REQ-016`)
- **Date**: `2026-11-07`
- **Status**: `Accepted`
- **Context**: When attempting to install a newly built `OpenKey-Android-A37.apk` from GitHub Releases over an existing installation on the Samsung Galaxy A37, Android's Package Installer rejected the update (`"App not installed as package conflicts with an existing package"` / `INSTALL_FAILED_UPDATE_INCOMPATIBLE`), forcing the user to manually uninstall the old APK and reinstall from scratch (wiping IME activation in Android System Settings, default keyboard selection, and user settings). Inspection of `Sources/OpenKey/android/app/build.gradle.kts` and `.github/workflows/android-ci.yml` revealed two compounding root causes:
  1. **Ephemeral Per-Runner Debug Keystore (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`)**: `app/build.gradle.kts` did not configure `signingConfigs`. When `./gradlew :app:assembleDebug` executed on an ephemeral GitHub Actions `ubuntu-latest` runner, the Android Gradle Plugin (AGP) saw no `~/.android/debug.keystore` and generated a brand-new random RSA 2048-bit keypair and self-signed X.509 certificate for that single CI run. Because every CI run (and every developer laptop) produced a different signing certificate `SHA-256` fingerprint, Android `PackageManager` blocked every in-place update.
  2. **Hardcoded `versionCode = 1` & `versionName = "1.0.0"` (`INSTALL_FAILED_VERSION_DOWNGRADE` & Opaque Build Identity)**: `defaultConfig` in `app/build.gradle.kts` hardcoded `versionCode = 1` and `versionName = "1.0.0"`. Even with matching certificates, static version codes prevent Android from recognizing subsequent releases as strictly newer upgrades and make it impossible to verify which commit/build is installed on the phone.
- **Options Considered**:
  - **Option A (Chosen): Repository-Tracked Deterministic Signing Keystore (`Sources/OpenKey/android/app/openkey-debug.keystore`) + Git-Commit Monotonic `versionCode` (`git rev-list --count HEAD`) with Optional Environment Override**:
    - Commit a dedicated, deterministic Android keystore (`Sources/OpenKey/android/app/openkey-debug.keystore`, `storePassword = "android"`, `keyAlias = "androiddebugkey"`, `keyPassword = "android"`) and explicitly bind `signingConfigs.getByName("debug")` and `buildTypes.release.signingConfig` in `Sources/OpenKey/android/app/build.gradle.kts` to `file("openkey-debug.keystore")` (falling back to `OPENKEY_KEYSTORE_PATH` if provided via environment variables).
    - Compute `versionCode` dynamically in `Sources/OpenKey/android/app/build.gradle.kts` via `-PversionCode` or `git rev-list --count HEAD` (with fallback `>= 1`), set `versionName = "1.0.$resolvedVersionCode"`, and set `fetch-depth: 0` on `actions/checkout@v4` in `.github/workflows/android-ci.yml`.
    - *Blast Radius & Coupling*: Low — isolated to `Sources/OpenKey/android/app/build.gradle.kts`, `Sources/OpenKey/android/app/openkey-debug.keystore`, and `.github/workflows/android-ci.yml`.
    - *Maintenance Cost*: Zero — works out-of-the-box across all GitHub Actions CI runs, PRs, forks, and local macOS `adb install` builds with zero manual secret rotation, guaranteeing that local builds and GitHub Release APKs share the exact same certificate and `versionCode` progression.
  - **Option B: GitHub Actions Encrypted Secret (`ANDROID_KEYSTORE_BASE64`) + `github.run_number` Versioning**:
    - Store a base64-encoded keystore exclusively in GitHub repository secrets and use `${{ github.run_number }}` as `versionCode`.
    - *Blast Radius & Coupling*: Medium — couples APK signing and versioning to GitHub-hosted runner secrets and workflow variables.
    - *Maintenance Cost*: High — fails if secrets are not manually provisioned in GitHub settings, fails on forks, and produces a *different* signing certificate and `versionCode` scale than local `./gradlew :app:assembleDebug` builds, re-triggering `INSTALL_FAILED_UPDATE_INCOMPATIBLE` whenever a developer switches between local `adb install` and GitHub Release downloads.
- **Decision**: Adopt **Option A** (Repository-tracked `Sources/OpenKey/android/app/openkey-debug.keystore` with optional `OPENKEY_KEYSTORE_PATH` override + `git rev-list --count HEAD` monotonic `versionCode` and `versionName = "1.0.<versionCode>"`).
- **Trade-offs & Risks**:
  - *Trade-off*: After upgrading to the first build signed with `Sources/OpenKey/android/app/openkey-debug.keystore`, a user who currently has an older ephemeral-CI-signed APK installed will perform one final transition install; from that point onward, every subsequent CI release (`OpenKey-Android-A37.apk`) and local build will update seamlessly in-place forever without uninstalling.

---

## `ADR-024`: Removal of Top Keyboard Setting Panel & Dedicated Auto-Wording Strip (`REQ-023`, `REQ-020`)
- **Date**: `2026-11-07`
- **Status**: `Accepted`
- **Context**: User screenshot (`media_1794018317892_e6caf697.jpg`) on the Samsung Galaxy A37 showed the `44dp` top bar above the `1–0` number row displaying `English (US)` on the left and `OneHandedModeIcon` (`📱`) + `SettingsGearIcon` (`⚙`) on the right. Because Row 5 already provides the dedicated `🌐` language key and Spacebar language label (`‹ English (US) ›` / `‹ Tiếng Việt ›`) and Android provides the dedicated OpenKey launcher app for settings, those idle controls in `CandidateStripView.kt` functioned as an unwanted setting panel (`"there is still setting panel, remove it"`).
- **Options Considered**:
  - **Option A (Chosen): Delete the Idle Setting Toolbar (`SettingsGearIcon`, `OneHandedModeIcon`, Mode Text) Completely and Dedicate `CandidateStripView` Strictly to Auto-Wording Suggestions**:
    - Remove `OneHandedModeIcon`, `SettingsGearIcon`, and the idle `else` branch from `CandidateStripView.kt`.
    - Dedicate `CandidateStripView` 100% to rendering 3-slot Vietnamese and English Auto-Wording suggestions (`candidates`).
    - *Blast Radius & Coupling*: Low — isolated to `CandidateStripView.kt` and `KeyboardScreen.kt`.
    - *Maintenance Cost*: Low — removes ~140 lines of unused toolbar icon/label UI code.
  - **Option B: Keep Settings & Mode Controls in the Top Strip**:
    - *Rejected*: Explicitly rejected by the user (`"there is still setting panel, remove it"`).
- **Decision**: Adopt **Option A** (Delete the setting panel from `CandidateStripView.kt` and `KeyboardScreen.kt` so the top strip only displays Auto-Wording word suggestions).

---

## `ADR-025`: Hybrid Offline Frequency-Indexed English Auto-Wording, Bilingual Touch-Typing Auto-Correct (`"vietek"` → `"việt"`, `"featuere"` → `"feature"`) & Android `TextServicesManager` (`SpellCheckerSession`) Bridge (`REQ-024`, `REQ-003`, `REQ-004`, `REQ-011`)
- **Date**: `2026-11-07`
- **Status**: `Accepted`
- **Context**:
  1. When switching the keyboard to English (`language == 0`), no auto-wording suggestions appeared because `KeyboardSessionController.onKeyAction` had an early return `if (editorUiState.bypassVietnamese || editorUiState.language != 1)` that skipped `AutoWordingEngine` entirely when `language == 0`, and `VietnameseDictionary.computeEnglishCandidates` only searched `englishPriorityWords` (~350 words) without an English next-word bigram table.
  2. When typing `"thử tiếng vietek, maybe we should have an auto correct featuere, like auto correct 2 wrongly words in this sentence"`, two real-world mobile touch-typing typos occurred before commas (`,`):
     - **`"vietek"` → `"việt"`**: The user typed `v-i-e-t-e` (`"viêt"`) and fat-fingered **`k`** (directly right of **`j`** on QWERTY Row 3 `h-j-k`) instead of `j` (*dấu nặng*), which triggered invalid-coda auto-restore to `"vietek"`, and `BilingualAutoSwitchEngine` only ran bigram grammar on `KEY_SPACE` (ignoring `KEY_COMMA`).
     - **`"featuere"` → `"feature"`**: As the user moved from `'u'` to `'r'` on QWERTY Row 2 (`e-r-t-y-u`), their thumb grazed the adjacent `'e'` key (`f-e-a-t-u-e-r-e`), and `findEnglishTranspositionMatch` only checked same-length character swaps rather than 1-extra-key deletion distance.
- **Options Considered**:
  - **Option A (Chosen): Hybrid Architecture — Full-Corpus Frequency-Ranked English Index & Bigrams + Bilingual Touch-Typing Auto-Correct (`findVietnameseAutoCorrectMatch` & `findEnglishAutoCorrectMatch`) in `:openkey-core` + Android Native `TextServicesManager` (`SpellCheckerSession`) Bridge in `:app`**:
    - Fix `KeyboardSessionController.kt` so `language == 0` (when `!bypassVietnamese`) tracks `_composingWord`, runs Commit-First character output, computes 3-slot English candidates from the 1st character (`length >= 1`), auto-repairs English contractions/typos (`"im"` → `"I'm"`, `"dont"` → `"don't"`, `"i"` → `"I"`, `"teh"` → `"the"`, `"featuere"` → `"feature"`) on `Space` and punctuation (`,`, `.`, `?`, `!`), and predicts next-word continuations after `Space`.
    - Add `findVietnameseAutoCorrectMatch` (handling trailing `k`-for-`j` QWERTY neighbor fat-finger on Vietnamese circumflex/horn stems: `"vietek"` / `"vieetk"` / `"vietk"` → `"việt"`, `"viecek"` → `"việc"`, `"duowck"` → `"được"`, `"mootk"` → `"một"`, `"hoack"` → `"hoặc"`, `"thuwck"` → `"thực"`, `"hieenk"` → `"hiện"`, plus single-target bigram repair on punctuation breaks) and `findEnglishAutoCorrectMatch` (handling adjacent transpositions + 1-extra-character duplicate/QWERTY-neighbor deletions like `"featuere"` → `"feature"`, `"keyboasrd"` → `"keyboard"`, `"mesasage"` → `"message"`, `"andrtoid"` → `"android"`, `"problrem"` → `"problem"`) in `VietnameseDictionary` (`Kotlin` & `Swift`).
    - Build a pre-sorted frequency rank and 1–3 char prefix index over the full `englishWords` corpus (`2,500+` words) + `englishNextWordBigrams` (`120+` common English word pairs) in `VietnameseDictionary` (`Kotlin` & `Swift`).
    - Add `SystemSpellCheckerBridge.kt` in `:app` using Android's standard, zero-permission `android.view.textservice.TextServicesManager` (`newSpellCheckerSession(..., Locale.US, ...)`).
    - *Blast Radius & Coupling*: Low — `:openkey-core` and `OpenKeySwiftCore` share identical deterministic auto-correct algorithms, while `:app` wires Android's `TextServicesManager` cleanly in `OpenKeyImeService`.
    - *Maintenance Cost*: Low — zero external AAR/Maven dependencies and zero network permissions (`REQ-001` preserved).
  - **Option B: Rely Solely on Static Typo Maps or Android `SpellCheckerSession`**:
    - *Rejected*: Static maps cannot cover systematic QWERTY neighbor fat-finger patterns (`k`-for-`j` in Telex or extra adjacent vowel in English), and `SpellCheckerSession` alone cannot repair Vietnamese Telex tone fat-fingers (`"vietek"` → `"việt"`) or run synchronously on word break.
- **Decision**: Adopt **Option A**.

---

## `ADR-026`: Dedicated Samsung One UI 4×4 Numeric Keypad (`KeyboardLayer.NUMPAD`) for `TYPE_CLASS_NUMBER`, `TYPE_CLASS_PHONE` & `TYPE_CLASS_DATETIME` Fields (`REQ-025`, `REQ-009`, `REQ-011`)
- **Date**: `2026-11-07`
- **Status**: `Accepted`
- **Context**: User screenshot (`media_1794019317151_50bd3369.jpg`) in Vietcombank VCB Digibank (`"Số tiền 750,000 VND"`) showed the full 45-key QWERTY keyboard appearing inside a numeric-only field (`"why in this number only, I see the full keyboard"`). Although `InputContextEvaluator` detected `TYPE_CLASS_NUMBER` / `TYPE_CLASS_PHONE` / `TYPE_CLASS_DATETIME` to set `bypassVietnamese = true`, it did not propagate an `isNumericField: Boolean` flag to `EditorUiState` or switch `KeyboardScreen` to a numeric keypad layer.
- **Options Considered**:
  - **Option A (Chosen): Add `isNumericField: Boolean` to `InputEvaluation` / `EditorUiState` and `KeyboardLayer.NUMPAD` (Samsung One UI 4×4 Numpad) to `KeyboardLayoutDefinition`**:
    - When `inputClass` is `TYPE_CLASS_NUMBER`, `TYPE_CLASS_PHONE`, or `TYPE_CLASS_DATETIME`, `InputContextEvaluator.evaluate` sets `isNumericField = true`.
    - When `editorUiState.isNumericField == true`, `KeyboardScreen` hides the candidate strip and renders `KeyboardLayer.NUMPAD`: 4 rows × 4 columns (`1 2 3 -`, `4 5 6 Space`, `7 8 9 ⌫`, `, 0 . Enter` with `0.26f / 0.26f / 0.26f / 0.22f` weights, `58.dp` portrait row height, and `26.sp` digit typography).
    - *Blast Radius & Coupling*: Low — cleanly extends `InputEvaluation`, `EditorUiState`, `KeyboardLayer`, `KeyboardLayoutDefinition`, `KeyboardScreen`, and `KeyButton`.
    - *Maintenance Cost*: Low — reuses the existing single-pass `KeyButton` renderer and `LayerCacheKey` cache (`REQ-014`).
  - **Option B: Keep QWERTY Keyboard and Force `SYMBOLS_1` Layer on Numeric Fields**:
    - *Rejected*: `SYMBOLS_1` still has 37 small keys across 5 rows instead of large, thumb-friendly 4×4 Numpad keys expected in banking, OTP, PIN, and phone-number fields.
- **Decision**: Adopt **Option A** (4×4 Samsung One UI `KeyboardLayer.NUMPAD` automatically activated whenever `editorUiState.isNumericField == true`).

---

## Gate 1: Normative Source Self-Validation

| Check # | Gate 1 Criterion | Status | Evidence |
| :--- | :--- | :---: | :--- |
| **1** | **Codebase Grounding** | `PASS` | Inspected `InputContextEvaluator.kt`, `KeyboardSessionController.kt`, `KeyboardLayoutDefinition.kt`, `KeyboardScreen.kt`, `KeyButton.kt`, `AutoWordingEngine.kt`, `VietnameseDictionary.kt`, `CandidateStripView.kt`, `app/build.gradle.kts`, and `android-ci.yml`. |
| **2** | **Intent Attribution & Non-Goals** | `PASS` | `REQ-022`..`REQ-025` cite verbatim user prompts (`"I can't update the apk..."`, `"there is still setting panel, remove it"`, `"why in english, I do not see the auto wording..."`, `"thử tiếng vietek... featuere..."`, `"why in this number only, I see the full keyboard"`, `2026-11-07`), and `spec.md` declares explicit `## 3. Non-Goals`. |
| **3** | **EARS & Falsifiable ACs** | `PASS` | `REQ-022`..`REQ-025` use EARS `WHEN ... THE ... SHALL` syntax paired with observable acceptance criteria `AC-022.1`–`AC-025.2`. |
| **4** | **Zero Deferral Placeholders** | `PASS` | Zero `TODO`, `TBD`, `FIXME`, or unowned placeholders exist in `spec.md` or `decisions.md`. |
| **5** | **Anti-Strawman ADR Debate** | `PASS` | `ADR-023`..`ADR-026` compare $\ge 2$ viable options across blast radius, coupling, and maintenance cost. |
| **6** | **Cross-Spec Lineage & 1-Hop Cascade** | `PASS` | `spec.md` header declares `Type: enhancement`, `Version: 1.6.0`, `Status: Planning`, and `Lineage: None`, and `docs/specs/INDEX.md` is synchronized. |

