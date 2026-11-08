# OpenKey macOS — Agent & Contributor Engineering Guide (`AGENTS.md`)

OpenKey is a 100% offline, privacy-first Vietnamese Input Method Editor (IME) for macOS (`arm64`) written in **Pure Swift 6** (`OpenKeySwiftCore` + `OpenKeySwiftApp`).

> **Standalone Android Repository**: The Android implementation for the Samsung Galaxy A37 (`:openkey-core` + `:app`) now resides in its own standalone repository: [`https://github.com/1quachuoi9vang/openkey-thanghoang`](https://github.com/1quachuoi9vang/openkey-thanghoang) (local clone: `/Users/thanghoang/github/openkey-thanghoang`).

---

## 1. Repository Layout & Module Architecture

| Path | Target / Module | Description |
| :--- | :--- | :--- |
| `Sources/OpenKey/macOS-Swift/Sources/OpenKeySwiftCore/` | `OpenKeySwiftCore` (macOS Swift) | Core Vietnamese engine (`VietnameseEngine.swift`, `VietnameseEngine+Phonotactics.swift`), `BilingualAutoSwitchEngine.swift`, `AutoWordingEngine.swift`, `VietnameseDictionary.swift`, generated corpus (`VietnameseDictionaryCorpus.swift`), `EventTapCoordinator.swift`, `KeystrokeInjector.swift`, `OpenKeySettingsStore.swift`, `SmartSwitchStore.swift`, and `OpenKeyLogger.swift`. |
| `Sources/OpenKey/macOS-Swift/Sources/OpenKeySwiftApp/` | `OpenKeySwiftApp` (macOS App) | Menu-bar app, `CandidateBarController.swift`, `SettingsView.swift`, and `OpenKeyL10n.swift`. |
| `Sources/OpenKey/shared-data/` | Single-Source Lexicon (`1` entry/line) | Canonical lexical data (`vietnamese_syllables.txt`, `vietnamese_priorities.tsv`, `vietnamese_compound_bigrams.tsv`, `english_words.tsv`, `english_next_word_bigrams.tsv`, `typo_and_grammar_rules.tsv`). |
| `scripts/sync_shared_lexicon.py` | Lexicon Code Generator | Deterministic generator (`--write`) and CI drift verifier (`--check`) that compiles `Sources/OpenKey/shared-data/*` into `VietnameseDictionaryCorpus.swift`. |
| `docs/specs/` | 5-Document Specifications | Feature specifications (`spec.md`, `decisions.md`, `design.md`, `tasks.md`, `verification.md`, `traceability_audit.json`) indexed in `docs/specs/INDEX.md`. |
| `.github/workflows/macos-ci.yml` | CI/CD Pipeline | `macos-ci.yml` (`macos-26`, Swift 6). |

---

## 2. Build, Lexicon Sync & Test Commands

- **Sync / Verify Shared Lexicon (`1`-Line Edit Workflow)**:
  ```bash
  python3 scripts/sync_shared_lexicon.py --write
  python3 scripts/sync_shared_lexicon.py --check
  ```
- **Swift Package Unit Tests (`69` tests — requires macOS host or GitHub Actions `macos-26` runner)**:
  ```bash
  swift test --package-path Sources/OpenKey/macOS-Swift
  ```
- **Build & Ad-Hoc Sign `OpenKeySwift.app`**:
  ```bash
  bash Sources/OpenKey/macOS-Swift/build-app.sh
  ```

---

## 3. Core Architectural Invariants (Non-Negotiable)

1. **Zero Network & Zero Telemetry (`REQ-001`, `ADR-001`)**:
   - OpenKey operates 100% offline with zero network calls or telemetry.
2. **Linguistic & Bilingual Engine Invariants (`REQ-002`–`REQ-004`, `REQ-018`, `REQ-026`, `REQ-027`, `ADR-019`, `ADR-027`, `ADR-028`)**:
   - **Pure Bucket Invariant (`AC-027.1`)**: Every word in `stemToWords[stem]` must satisfy `stripVietnameseDiacritics(word) == stem`, and every word in `telexSignatureToWords[sig]` must satisfy `sorted(strip(word)) == sig`. Never add hardcoded non-homophone bucket overrides.
   - **Phonotactic Corpus Sanitization (`AC-027.2`)**: `isPhonotacticallyValidVietnameseSyllable` rejects half-horned `*uơ`+coda strings (`"luờng"`, `"huờng"`, `"vuờn"`, `"suờn"`), orthographic non-words (`"ghuy"`, `"kuy"`, `"byên"`, `"bơng"`, `"bưn"`, `"tưn"`, `"nhĩa"`), and fake `d-` shadow words (`"dất"`, `"dến"`, `"diểm"`, `"dồng"`).
   - **Single-`d` `đ-` Indexing & Class 5 Insertion (`AC-027.3`)**: `stemToneToSyllable` indexes single-`d` + vowel-modifier + tone keys for `đ-` syllables (`"daats "` → `"đất "`, `"deens "` → `"đến "`), and `findVietnameseSpatialCandidates` supports all 6 typo classes including Class 5 (`1`-missing-key insertion + `ORTHO_ONSET_PAIRS` for `"ngiax "` → `"nghĩa "`, `"ngiengs "` → `"nghiếng "`).
   - **Context-Ordered `V` / `E` Homograph Disambiguation (`REQ-018`, `ADR-019`)**:
     - English words whose Telex keystrokes form valid everyday Vietnamese syllables (`sex`/`"sẽ"`, `vex`/`"vẽ"`, `max`/`"mã"`, `six`/`"sĩ"`, `tax`/`"tã"`, `lax`/`"lã"`, `hex`/`"hẽ"`, `moon`/`"môn"`, `noon`/`"nôn"`, `soon`/`"sôn"`, `seen`/`"sên"`, `seem`/`"sêm"`, `beef`/`"bề"`, `reef`/`"rề"`, `room`/`"rôm"`, `boom`/`"bôm"`, `doom`/`"dôm"`, `loom`/`"lôm"`, `boots`/`"bốt"`, `roots`/`"rốt"`, `loops`/`"lốp"`, `meets`/`"mết"`, `keeps`/`"kếp"`, `moor`/`"mổ"`, `door`/`"dổ"`) must reside in `englishLookbackStems` (`lookback` in `shared-data/english_words.tsv`) and **never** in unconditional `englishPriorityWords` (`priority`).
     - Under `LanguagePriority.vietnameseFirst` (`V`), those homographs stay Vietnamese (`"sẽ "`, `"anh sẽ làm "`, `"bác sĩ "`, `"mã nguồn "`, `"bản vẽ "`) and rank Vietnamese first in the candidate bar (`["sẽ", "sẻ", "sex"]`).
     - Under `LanguagePriority.englishFirst` (`E`, after an English word like `"have sex "`, `"at max "`, `"number six "`) or via 1–2 word look-back before an English word (`"sex is "`, `"max value "`), they restore to English and rank English first in the candidate bar (`["sex", "sẽ", "sẻ"]`).
3. **File & Function Modularity Bounds (`REQ-028`, `AC-028.3`, `AC-028.4`)**:
   - `VietnameseDictionary.swift` must remain `< 550` lines.
   - `BilingualAutoSwitchEngine.evaluateWordBreakRestore` must remain `< 120` lines, delegating to single-responsibility helpers (`<= 65` lines each) and `emitHookReplacement`.
4. **Secure Input Redaction in Debug Mode (`REQ-017`, `ADR-017`)**:
   - `OpenKeyLogger.swift` must use lazy closure evaluation (`@autoclosure () -> String`) so `debugModeEnabled == false` incurs zero allocation or I/O overhead.
   - When `isSecureField == true` (password/PIN fields), keystroke values must **never** be logged—only `"Secure input active — keystroke redacted, bypassing IME"`.
