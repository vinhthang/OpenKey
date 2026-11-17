# Independent Code Review & Mutation Audit (`review.md`) — Pass 4

- **Verdict**: **APPROVED** (`0` P0, `0` P1, `1` minor P2 advisory `P2-A`; `P2-B` resolved)
- **Scope**: `/Users/thanghoang/github/OpenKey` (macOS Swift 6) & `/Users/thanghoang/github/openkey-thanghoang` (Android Kotlin `:openkey-core` + `:app` integrated on top of `origin/main` `b66d86a`)
- **Review Role**: Independent Code Reviewer & Mutation Auditor (Pass 4 Focused `:app` Fix Verification)
- **Git Topology & Backup Check (`openkey-thanghoang`)**:
  - `git merge-base --is-ancestor origin/main HEAD`: PASS (`origin/main` and `HEAD` at `b66d86abd6e5f779a7da0844fd010cb2feea8486`, cleanly fast-forwardable).
  - `backup-0316f3f` branch intact at `0316f3f32f241cf798c9660235e485b3fca26028`.
- **Shared Lexicon Sync (`diff -rq` & `sync_shared_lexicon.py --check`)**: PASS (`0` diffs between `OpenKey/Sources/OpenKey/shared-data` and `openkey-thanghoang/shared-data`; both `sync_shared_lexicon.py --check` commands exited `0` with `100%` synchronization).
- **Final Clean Post-Mutation Suite Verification**:
  - macOS Swift (`rtk proxy swift test --package-path /Users/thanghoang/github/OpenKey/Sources/OpenKey/macOS-Swift`): **`81 / 81` tests passed** across 5 suites (`2.821s`, exit `0`).
  - Android `:openkey-core:test` (`./gradlew --offline :openkey-core:test --rerun-tasks --console=plain`): **`94 / 94` tests passed** in Pass 4 (`AutoWordingEngineTest`: 11, `BilingualAutoSwitchTest`: 28, `ImePipelineAndContextTest`: 18, `PhoneErgonomicsAndGestureTest`: 16, `SmoothArchitectureTest`: 11, `VietnameseEngineTest`: 10; `0` failures, `0` errors, `0` skipped; exit `0`).
  - Android `:app:testDebugUnitTest`: Not executable locally (no Android SDK installed at `/Users/thanghoang/Library/Android/sdk`); Pass 4 focused static audit of `InputConnectionCommitter.kt`, `OpenKeyImeService.kt`, and `OpenKeyAndroidAppTest.kt` passed.

---

## Executive Summary

Integration onto `origin/main` (`b66d86a`) preserves all `3f3a2f2..b66d86a` Android regressions fixes, achieves 100% cross-repo phonotactic & lexicon parity, satisfies all modularity bounds, passes `81/81` Swift tests and `94/94` Kotlin `:openkey-core` tests after all mutation checks were restored cleanly, and achieves `>= 80%` non-equivalent mutation kill rate on both platforms (`90.0%` Swift non-equivalent; `100.0%` on Pass 3 Kotlin spot-check mutants / `94.7%` cumulative Kotlin).

| Audit Area | Result | Observed Evidence |
| :--- | :--- | :--- |
| Fast-Forward Topology & Backup | PASS | `origin/main` == `HEAD` (`b66d86abd6e5f779a7da0844fd010cb2feea8486`); `backup-0316f3f` intact (`0316f3f32f241cf798c9660235e485b3fca26028`) |
| Shared Lexicon Parity (`diff -rq` & `sync_shared_lexicon.py --check`) | PASS | `0` diffs across `shared-data`; both `--check` runs exited `0` (`100%` synced) |
| Phonotactics Parity (`VietnamesePhonotacticsValidator.kt` vs `VietnameseDictionary+Phonotactics.swift`) | PASS | Identical rules: permits `buýt`, `ưm`, `ừm` and `quoe` (`isValidOeSyllable` `"qu"` onset); rejects `bưn`, `tưn`, `bue`, `cue`, `due`, `gioa*`, `*ãu`, `*uổn`, `kểu` |
| Modularity Line Bounds (`VietnameseDictionary` `< 550`, `evaluateWordBreakRestore` `< 120`, helpers `<= 65`) | PASS | `VietnameseDictionary.swift`: `487`, `.kt`: `480`; `evaluateWordBreakRestore`: `82` (Swift) / `78` (Kotlin); all extracted helpers `<= 64` lines |
| `origin/main` (`3f3a2f2..b66d86a`) Regression Guards | PASS | Never auto-capitalizes `'i'` (`testNeverAutoCapitalizeLowercaseI` & `testEnglishModeNeverAutoCapitalizesIAndProtectsCompoundTokens`), `vBilingualAutoRestore`, `isCursorAnchorKnown`/`pendingExpectedCursors`/`recordSelfDelete`, `sharedSettingsStore`, `deleteSurroundingText >= 5` clamp, `allowBackup="false"`, `android-ci.yml` (`OpenKey-Android.apk`) all verified intact |
| Static `:app` Audit | PASS | All `:openkey-core`, Compose, and Android API signatures match `minSdk=29`/`compileSdk=35`; `.pointerInput(key)` before `.padding(horizontal = gapH, vertical = gapV)` in `KeyButton.kt`; clutter-free `CandidateStripView.kt`; `Divider` unused import absent in `SettingsActivity.kt`; `0` JUnit 5 trailing-message assertions in `OpenKeyAndroidAppTest.kt` |
| Spot-Check Mutation Testing (`mutation-guard >= 80%`) | PASS | Swift: `9 / 10` non-equivalent (`90.0%`); Kotlin `:openkey-core`: `9 / 9` Pass 3 spot-checks (`100.0%`), `18 / 19` cumulative (`94.7%`) |

---

## P0 Issues (Critical)

- **None (`0` open)**.

---

## P1 Issues (Blocking)

- **None (`0` open)**.

---

## P2 Issues (Advisory)

1. **P2-A (Swift Test Parity for `buýt`/`ưm`/`ừm`/`quoe`)**: `OpenKeyEngineTests.swift:1574` (`testStage1CorpusAndPhonotacticsInvariants`) does not yet explicitly list `"buýt"`, `"ưm"`, `"ừm"`, `"quoe"`, `"quòe"` as in Kotlin `BilingualAutoSwitchTest.kt:856` (so `MS1` removing `if lower == "buýt" || lower == "ưm" || lower == "ừm"` survived in Swift, though non-equivalent Swift kill rate remains `90.0%`). Adding those 5 syllables to `OpenKeyEngineTests.swift` would bring Swift phonotactic test parity to 100%.
2. **P2-B (Resolved in Pass 4 — Unused Imports in `OpenKeyImeService.kt`)**: Unused imports `BilingualAutoSwitchEngine`, `HookCodeState`, and `VietnameseEngineState` were removed cleanly from `OpenKeyImeService.kt` with zero missing imports.

---

## Static `:app` Signature & Compatibility Audit

All modified `:app` files in `/Users/thanghoang/github/openkey-thanghoang/app/` were audited statically against the merged `:openkey-core` and Android SDK (`minSdk = 29`, `compileSdk = 35`):

| File | Verified Details | Status |
| :--- | :--- | :--- |
| `OpenKeyImeService.kt` | Uses `SharedPreferencesKeyValueStorage.sharedSettingsStore(this)`, wires single-fire `keyCodeSender = { sendDownUpKeyEvents(it) }` (preventing double-Enter and double-DPAD firing), passes `bilingualAutoRestore` to `VietnameseEngine.syncConfig(...)`, `syncSettingsToEngine(changedKey)` preserves per-app SmartSwitch language except on `KEY_LANGUAGE`, `SystemSpellCheckerBridge`, `getCursorCapsMode`, `onStartInput`/`onFinishInput`; unused imports (`BilingualAutoSwitchEngine`, `HookCodeState`, `VietnameseEngineState`) removed with zero missing imports. | PASS |
| `InputConnectionCommitter.kt` | Backward-compatible 1-arg (`line 25`) and 2-arg (`lines 27-31`) constructors intact plus optional trailing `keyCodeSender: ((Int) -> Unit)? = null` (`line 22`); single shared helper `dispatchHardwareKeyCode(keyCode, ic)` (`lines 87-100`) used by both `moveCursorBy` (`line 81`) and `sendEnterKey` (`line 166`) with `ic.commitText("\n", 1)` fallback preserved (`line 169`); `deleteSurroundingText >= 5` clamp, `hasKnownSelection \|\| isCursorAnchorKnown` trackpad guard, `recordSelfDelete`, `sharedSettingsStore(context)` `@Synchronized` singleton, `deleteSelectionIfAny`, `deleteSingleBackward` surrogate pair handling. | PASS |
| `SystemSpellCheckerBridge.kt` | `AtomicLong` generation guard (`requestCounter`) prevents stale `SpellCheckerSession` callbacks from polluting `cache`. | PASS |
| `KeyButton.kt` | `.pointerInput(key)` (line `415`) precedes `.padding(horizontal = gapH, vertical = gapV)` (line `564`); `try { while (pointer.pressed) ... } finally { isPressed = false; longPressJob?.cancel(); repeatDeleteJob?.cancel(); spacebarTrackpadLabel = null }` (lines `474-533`). | PASS |
| `KeyboardScreen.kt` & `CandidateStripView.kt` | `onLanguageToggled` dispatches `controller.onKeyAction(KeyAction.SwitchLanguage)` (line `238`); `LiveCandidateStripHost` isolates `AutoWordingEngine` candidate updates; `CandidateStripView.kt` remains clutter-free (`0` settings/gear/one-handed buttons or text). | PASS |
| `SettingsActivity.kt` | Uses `SharedPreferencesKeyValueStorage.sharedSettingsStore(this)` (line `76`), `doubleSpacePeriodEnabled`, `OpenKeyL10n.Debug.*`, `OpenKeyLogger.shared`; unused `Divider` import removed. | PASS |
| `OpenKeyAndroidAppTest.kt` | Zero `.keyCode` inspections on unmocked `KeyEvent` stubs (only static `KeyEvent.KEYCODE_ENTER` and `KeyEvent.KEYCODE_DPAD_LEFT` constants used — safe under `unitTests.isReturnDefaultValues = true`); full-file regex scan confirmed `0` JUnit 5 trailing-message assertions; lines `689-720` and `756` verify `sendEnterKey` fallback (`commitText("\n", 1)`), single-fire `keyCodeSender` dispatch, and `OpenKeyImeService` wiring cleanly against `InputConnectionCommitter` and `MockInputConnection`. *Note: `:app:testDebugUnitTest` was not executed locally (no Android SDK installed).* | PASS (static) |
| `AndroidManifest.xml` & `.github/workflows/android-ci.yml` | `android:allowBackup="false"`, `android:directBootAware="true"`, zero `INTERNET`/`ACCESS_NETWORK_STATE`; `android-ci.yml` executes `sync_shared_lexicon.py --check`, `:openkey-core:test :app:testDebugUnitTest :app:assembleDebug`, and packages `OpenKey-Android.apk`. | PASS |

---

## Pass 3 Spot-Check Mutation Testing Scorecard

All spot-check mutants were injected one at a time on the merged repositories, verified against tests, and immediately restored cleanly via reverse edit.

### 1. macOS Swift (`OpenKeySwiftCore`) — `9 / 10` non-equivalent killed (`90.0%`)

| # | Target (`file:line`) | Mutation | Targeted Test | Outcome |
| :--- | :--- | :--- | :--- | :--- |
| S2 | `VietnameseEngine+Phonotactics.swift:126` | Remove `\|\| CHR(Int(index) - 1) == KEY_P` in `checkSpelling` | `testPar02StopCodaTonesAndQuoi` | **KILLED** *(Pass 3)* |
| S6 | `VietnameseDictionary+Phonotactics.swift:14` | Disable `NON_QU_BARE_UE_REGEX` | `testStage1CorpusAndPhonotacticsInvariants` | **KILLED** *(Pass 3)* |
| S7 | `VietnameseEngine.swift:963` | Remove `hasDiacritic &&` in trailing-`i` consumption | `testMac06DeleteKeySyncAndTrailingIConsumption` | **KILLED** *(Pass 3)* |
| MS1 | `VietnameseDictionary+Phonotactics.swift:48` | `if lower == "buýt" \|\| lower == "ưm" \|\| lower == "ừm"` → `if false` | `testStage1CorpusAndPhonotacticsInvariants` | **SURVIVED** *(P2-A)* |
| S3–S5, S8–S10 | (`checkGrammar`, `trailingCount`, `>255B`, `isExcluded`, `QuickTelex`, `KEY_HOME`) | Verified in Pass 1/2 (`6/6` killed) | `OpenKeyEngineTests`, `OpenKeyEventTapTests` | **KILLED** *(Pass 1/2)* |

### 2. Android Kotlin (`:openkey-core`) — `9 / 9` Pass 3 spot-checks killed (`100.0%`; `18 / 19 = 94.7%` cumulative)

| # | Target (`file:line`) | Mutation | Targeted Test | Outcome |
| :--- | :--- | :--- | :--- | :--- |
| MK1 | `VietnamesePhonotacticsValidator.kt:43` | Disable `buýt`/`ưm`/`ừm` allowlist (`if (false)`) | `BilingualAutoSwitchTest` (`line 859`) | **KILLED** *(Pass 3)* |
| MK2 | `VietnamesePhonotacticsValidator.kt:35` | Remove `qu` onset branch in `isValidOeSyllable` | `BilingualAutoSwitchTest` (`line 859`) | **KILLED** *(Pass 3)* |
| MK3 | `BilingualAutoSwitchEngine.kt:329` | Remove `composedLower != "i" && fullRawLower != "i"` | `BilingualAutoSwitchTest` (`line 670`) | **KILLED** *(Pass 3)* |
| MK4 | `BatchReplacementCoordinator.kt:192` | Disable `if (!isCursorAnchorKnown)` branch (`if (false)`) | `ImePipelineAndContextTest` (`lines 422, 474`) | **KILLED** *(Pass 3)* |
| K3 | `VietnameseEnginePhonotactics.kt:249` | Remove `Q` guard in `checkGrammar` | `BilingualAutoSwitchTest` (`line 964`) | **KILLED** *(Pass 3)* |
| K4 | `BilingualAutoSwitchEngine.kt:164` | Remove `grammarRepairEnabled` guard in `tryCollapseDuplicateEnglishWord` | `BilingualAutoSwitchTest` (`line 1166`) | **KILLED** *(Pass 3)* |
| K7 | `KeyboardGestureController.kt:170` | `roundToInt()` → `toInt()` in `resolvePopupSlideIndex` | `PhoneErgonomicsAndGestureTest` (`line 543`) | **KILLED** *(Pass 3)* |
| K9 | `VietnameseEnginePhonotactics.kt:248` | Remove `\|\| ch == KEY_U` in `checkGrammar` | `BilingualAutoSwitchTest` (`line 977`) | **KILLED** *(Pass 3)* |
| K11 | `BatchReplacementCoordinator.kt:185` | `if (newSelStart < 0)` → `if (false)` | `ImePipelineAndContextTest` (`line 490`) | **KILLED** *(Pass 3)* |
| K1, K2, K5, K6, K8, K12–K15 | (`inlineTone`, `NON_QU_BARE_UE_REGEX`, `isImpossibleOrInvalidVnInput`, `commitBatch`, `DOUBLE_TAP`, `suppressSuggestions`, `undo`, `doubleSpace`, `smartPunct`) | Verified in Pass 1/2 (`9/9` killed; `K10` `isIeuYeu` survived) | `:openkey-core:test` | **KILLED** *(Pass 1/2)* |
