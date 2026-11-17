# Independent Code Review & Mutation Audit (`review.md`) — Pass 2

- **Verdict**: **APPROVED** (`0` P0, `0` P1, `0` unresolved P2)
- **Scope**: `/Users/thanghoang/github/OpenKey` (macOS Swift 6) & `/Users/thanghoang/github/openkey-thanghoang` (Android Kotlin `:openkey-core` + `:app`)
- **Review Role**: Independent Code Reviewer & Mutation Auditor (Pass 2 Re-Review)
- **Shared Lexicon Sync (`diff -rq` & `sync_shared_lexicon.py --check`)**: PASS (`0` diffs between `OpenKey/Sources/OpenKey/shared-data` and `openkey-thanghoang/shared-data`; both `sync_shared_lexicon.py --check` scripts exited `0` with `100%` synchronization)
- **Final Clean Post-Mutation Suite Verification**:
  - macOS Swift (`rtk proxy swift test --package-path /Users/thanghoang/github/OpenKey/Sources/OpenKey/macOS-Swift`): **`81 / 81` tests passed** across 5 suites (`3.501s`, exit `0`).
  - Android `:openkey-core:test` (`./gradlew --offline :openkey-core:test --rerun-tasks --console=plain`): **`82 / 82` tests passed** (`0` failures, `0` errors, `0` skipped; exit `0`).
  - Android `:app:testDebugUnitTest`: Not executable locally (no Android SDK installed at `/Users/thanghoang/Library/Android/sdk`); audited statically in full below.

---

## Executive Summary

All P0, P1, and P2 items raised in Pass 1 have been remediated and independently verified in Pass 2:
- **P0-1 Resolved**: `OpenKeyAndroidAppTest.kt` lines `643`, `652`, and `666` were converted to JUnit 4 `org.junit.Assert.*` message-first argument order, and a full AST/regex scan confirmed `0` JUnit 5 trailing-message assertions remain anywhere in `OpenKeyAndroidAppTest.kt`.
- **P1-1 Resolved (`100.0%` non-equivalent kill rate on macOS Swift)**: Re-testing all previously survived Swift mutants (`S2`, `S6`, `S7`) confirmed every one is now **KILLED** by the strengthened `OpenKeyEngineTests.swift` assertions (`9 / 9` non-equivalent mutants killed = **`100.0%`**, or `9 / 10 = 90.0%` including equivalent `S1`).
- **P1-2 Resolved (`93.3%` kill rate on Android `:openkey-core`)**: Re-testing previously survived Kotlin mutants confirmed `K2`, `K3`, `K4`, `K7`, `K9`, and `K11` are now **KILLED** (`14 / 15` killed = **`93.3%`**, exceeding the `>= 80%` `mutation-guard` threshold; `K10` `isIeuYeu` remains handled via `insertMark`/`stemToneToSyllable` on Space).
- **P2-1..P2-3 Resolved**: `isIeuYeu` and `repairPhonotacticClusterCore` are consolidated in `VietnameseEnginePhonotactics.kt` and reused by `AutoWordingEngine.kt`; `KeyButton.kt` wraps its gesture loop in `try/finally` with `.pointerInput(key)` before `.padding(horizontal = gapH, vertical = gapV)`; unused `Divider` import was removed from `SettingsActivity.kt`.

| Audit Area | Result | Evidence |
| :--- | :--- | :--- |
| Shared Lexicon Parity (`diff -rq` & `sync_shared_lexicon.py --check`) | PASS | `0` diffs across `shared-data`; both `--check` runs exited `0` (`100%` synced) |
| Modularity Line Bounds (`VietnameseDictionary` `< 550`, `evaluateWordBreakRestore` `< 120`, helpers `<= 65`) | PASS | `VietnameseDictionary.swift`: `487`, `.kt`: `512`; `evaluateWordBreakRestore`: `82` (Swift) / `78` (Kotlin); all extracted helpers `<= 64` lines |
| P0-1 JUnit 4 Fix (`OpenKeyAndroidAppTest.kt`) | PASS | Lines `643`, `652`, `666` use message-first JUnit 4 order; full-file scan found `0` remaining JUnit 5 order calls |
| Static `:app` Audit (`OpenKeyImeService`, `InputConnectionCommitter`, `SystemSpellCheckerBridge`, `KeyButton`, `KeyboardScreen`, `SettingsActivity`) | PASS | All `:openkey-core`, Compose, and Android SDK (`minSdk=29`, `compileSdk=35`) APIs verified statically; `:app:testDebugUnitTest` not run locally (no Android SDK) |
| P2 Advisory Remediations (`P2-1`, `P2-2`, `P2-3`) | PASS | `repairPhonotacticClusterCore` consolidated; `KeyButton.kt` `try/finally` added; `SettingsActivity.kt` unused `Divider` removed |
| Mutation Testing (`mutation-guard >= 80%`) | PASS | Swift: `9 / 9` non-equivalent (`100.0%`); Kotlin `:openkey-core`: `14 / 15` (`93.3%`) |

---

## P0 Issues (Critical)

- **None (`0` open)**.
- *Verified Remediation (P0-1)*: In `/Users/thanghoang/github/openkey-thanghoang/app/src/test/java/com/tuyenmai/openkey/android/OpenKeyAndroidAppTest.kt`:
  - Line `643`: `assertTrue("deleteSelectionIfAny must delete non-empty selection", committer.deleteSelectionIfAny())`
  - Line `652`: `assertEquals("Surrogate pair emoji must delete 2 UTF-16 code units", 2, deletedSurrogate)`
  - Line `666`: `assertEquals("deletePreviousWord must update expectedCursorPosition", 6, coordinator.expectedCursorPosition)`
  - Full-file scan confirmed `0` remaining `assert*(..., "...")` trailing-message calls in `OpenKeyAndroidAppTest.kt`.

---

## P1 Issues (Blocking)

- **None (`0` open)**.
- *Verified Remediation (P1-1 — Swift)*: `OpenKeyEngineTests.swift` added VNI tone-before-coda `-p` checks (`ba3p`, `ba2p`, `ba5p` at lines `1757-1775`) killing `S2`, direct `VietnameseDictionary.isPhonotacticallyValidVietnameseSyllable(...)` assertions (`bue`, `cue`, `due`, `sue`, `true` at lines `1592-1595`) killing `S6`, and unaccented vowel + `ii` checks (`uii `, `muii `, `aii ` at lines `1884-1889`) killing `S7`.
- *Verified Remediation (P1-2 — Kotlin `:openkey-core`)*:
  - `BilingualAutoSwitchTest.kt` added direct `VietnameseDictionary.isPhonotacticallyValidVietnameseSyllable(...)` checks (`K2`), mid-word `quowi`/`quowis` `getComposedWord()` assertions (`K3`), mid-word `huwou` `getComposedWord()` assertions (`K9`), and `"and and "` duplicate collapse suppression with `grammarRepair = false` (`K4`).
  - `PhoneErgonomicsAndGestureTest.kt:543` added `resolvePopupSlideIndex(dragOffsetX = 70f, itemWidthPx = 40f, itemCount = 6) == 2` (`1.75f` midpoint rounding, killing `K7`).
  - `ImePipelineAndContextTest.kt:395-397` added `controller.onUpdateSelection(11, 11, -1, -1)` asserting `hasKnownSelection == false` (`K11`).

---

## P2 Issues (Advisory)

- **None (`0` open)**.
- *Verified Remediations*:
  - **P2-1**: `AutoWordingEngine.kt:473-479` now delegates directly to `repairPhonotacticClusterCore` defined in `VietnameseEnginePhonotactics.kt:133-201`; duplicated `isIeuYeu` code removed.
  - **P2-2**: `KeyButton.kt:474-532` wraps `while (pointer.pressed)` inside `try { ... } finally { isPressed = false; longPressJob?.cancel(); repeatDeleteJob?.cancel() }`, preserving `.pointerInput(key)` (line `415`) before `.padding(horizontal = gapH, vertical = gapV)` (line `563`).
  - **P2-3**: Unused `import androidx.compose.material3.Divider` removed from `SettingsActivity.kt` (retaining `HorizontalDivider`).

---

## Static `:app` Signature & Compatibility Audit

All modified `:app` files in `/Users/thanghoang/github/openkey-thanghoang/app/` were re-verified:
- `OpenKeyImeService.kt`, `InputConnectionCommitter.kt`, `SystemSpellCheckerBridge.kt`, `KeyButton.kt`, `KeyboardScreen.kt`, `SettingsActivity.kt`, `CandidateStripView.kt`: all `:openkey-core`, Compose BOM `2024.10.01`, and Android API signatures match `minSdk = 29` / `compileSdk = 35`; `CandidateStripView.kt` remains clutter-free; `.pointerInput(key)` precedes `.padding(horizontal = gapH, vertical = gapV)` in `KeyButton.kt`.
- `OpenKeyAndroidAppTest.kt`: JUnit 4 argument order fixed on lines `643`, `652`, `666` (verified statically; Gradle `:app:testDebugUnitTest` could not be executed locally due to missing Android SDK).

---

## Mutation Testing Scorecard (Pass 2)

Every mutant was injected one line at a time, verified with its targeted test run, and immediately restored cleanly.

### 1. macOS Swift (`OpenKeySwiftCore`) — `9 / 9` non-equivalent killed (`100.0%`; `9 / 10 = 90.0%` raw)

| # | Target (`file:line`) | Mutation | Targeted Test | Pass 2 Outcome |
| :--- | :--- | :--- | :--- | :--- |
| S1 | `VietnameseEngine.swift:517` | Remove `&& keyCode != KEY_SPACE` from `isAlphaKey` | `testMac01SpaceWithShiftOrCapsLock` | **EQUIVALENT** *(Pass 1: `keyCodeToCharacter` & `baseBreakChar` fallback already emit `0x20`)* |
| S2 | `VietnameseEngine+Phonotactics.swift:126` | Remove `\|\| CHR(Int(index) - 1) == KEY_P` in `checkSpelling` | `testPar02StopCodaTonesAndQuoi` | **KILLED** *(3 failures on VNI `ba3p` / `ba2p`)* |
| S3 | `VietnameseEngine+Phonotactics.swift:216` | `if hookOutput.backspaceCount == 0` → `if true` | `testMac04CheckGrammarPreservesBrowserBreakerStrategy` | **KILLED** *(Pass 1)* |
| S4 | `BilingualAutoSwitchEngine.swift:668` | `if trailingCount == 1` → `if trailingCount >= 0` | `testMac05ReturnOrTabDoesNotArmAutoRestoreUndo` | **KILLED** *(Pass 1)* |
| S5 | `SmartSwitchStore.swift:110` | `utf8Bytes.count <= 255` → `<= 2550` | `testMac03SmartSwitchLongBundleAndReadMissPurity` | **KILLED** *(Pass 1)* |
| S6 | `VietnameseDictionary+Phonotactics.swift:14` | Disable `NON_QU_BARE_UE_REGEX` | `testStage1CorpusAndPhonotacticsInvariants` | **KILLED** *(5 failures on `bue`/`cue`/`due`/`sue`/`true`)* |
| S7 | `VietnameseEngine.swift:963` | Remove `hasDiacritic &&` in trailing-`i` consumption | `testMac06DeleteKeySyncAndTrailingIConsumption` | **KILLED** *(3 failures on `uii `/`muii `/`aii `)* |
| S8 | `EventTapCoordinator.swift:285` | `if isExcluded` → `if false` | `OpenKeyEventTapTests` | **KILLED** *(Pass 1)* |
| S9 | `VietnameseEngine.swift:975` | `vQuickTelex != 0` → `false && vQuickTelex != 0` | `testMac07EngineEdgeCasesAndConsonantD` | **KILLED** *(Pass 1)* |
| S10 | `VietnameseEngine.swift:53` | Remove `KEY_HOME` from `breakCode` | `testMac02NonPrintableNavigationAndFunctionKeys` | **KILLED** *(Pass 1)* |

### 2. Android Kotlin (`:openkey-core`) — `14 / 15` killed (`93.3%`)

| # | Target (`file:line`) | Mutation | Targeted Test | Pass 2 Outcome |
| :--- | :--- | :--- | :--- | :--- |
| K1 | `VietnameseDictionary.kt:132` | `canon.dropLast(1)` → `canon.dropLast(2)` | `BilingualAutoSwitchTest` + `AutoWordingEngineTest` | **KILLED** *(Pass 1)* |
| K2 | `VietnamesePhonotacticsValidator.kt:9` | Disable `NON_QU_BARE_UE_REGEX` | `BilingualAutoSwitchTest` (`line 620`) | **KILLED** |
| K3 | `VietnameseEnginePhonotactics.kt:244` | Remove `Q` guard `&& !(i - 3 >= 0 && CHR(i - 3) == KEY_Q)` | `BilingualAutoSwitchTest` (`line 714`) | **KILLED** |
| K4 | `BilingualAutoSwitchEngine.kt:163` | `tryCollapseDuplicateEnglishWord` guard → `if (false)` | `BilingualAutoSwitchTest` (`line 916`) | **KILLED** |
| K5 | `BilingualAutoSwitchEngine.kt:248` | `isImpossibleOrInvalidVnInput` → `return true` | `BilingualAutoSwitchTest` | **KILLED** *(Pass 1)* |
| K6 | `BatchReplacementCoordinator.kt:61` | Short-circuit `if (!deleted) return false` | `ImePipelineAndContextTest` | **KILLED** *(Pass 1)* |
| K7 | `KeyboardGestureController.kt:170` | `roundToInt()` → `toInt()` in `resolvePopupSlideIndex` | `PhoneErgonomicsAndGestureTest` (`line 543`) | **KILLED** |
| K8 | `KeyboardGestureController.kt:26` | `DOUBLE_TAP_CAPS_LOCK_WINDOW_MS = 350L` → `200L` | `PhoneErgonomicsAndGestureTest` | **KILLED** *(Pass 1)* |
| K9 | `VietnameseEnginePhonotactics.kt:243` | Remove `\|\| ch == KEY_U` in `checkGrammar` | `BilingualAutoSwitchTest` (`line 727`) | **KILLED** |
| K10 | `VietnameseEnginePhonotactics.kt:151` | `if (isIeuYeu)` → `if (false)` in `repairPhonotacticClusterCore` | `BilingualAutoSwitchTest` + `AutoWordingEngineTest` | **SURVIVED** *(Resolved on Space via `insertMark`/`stemToneToSyllable`)* |
| K11 | `BatchReplacementCoordinator.kt:102` | `if (newSelStart < 0)` → `if (false)` | `ImePipelineAndContextTest` (`line 396`) | **KILLED** |
| K12 | `InputContextEvaluator.kt:120` | `suppressSuggestions = false` | `ImePipelineAndContextTest` | **KILLED** *(Pass 1)* |
| K13 | `VietnameseEngine.kt:779` | `handleSingleBackspaceUndo` → `if (false)` | `BilingualAutoSwitchTest` | **KILLED** *(Pass 1)* |
| K14 | `BilingualAutoSwitchEngine.kt:574` | `doubleSpacePeriodEnabled` guard → `if (true)` | `BilingualAutoSwitchTest` | **KILLED** *(Pass 1)* |
| K15 | `KeyboardSessionController.kt:187` | Smart punctuation `commitBatch(target, 1, ...)` → `0` | `ImePipelineAndContextTest` | **KILLED** *(Pass 1)* |
