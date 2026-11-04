# OpenKey — Agent & Contributor Engineering Guide (`AGENTS.md`)

OpenKey is a 100% offline, privacy-first Vietnamese Input Method Editor (IME) with two active modern native implementations that share identical Vietnamese linguistic, phonotactic, bilingual auto-switch, and candidate-ranking algorithms:

1. **OpenKey Android (`Sources/OpenKey/android/`)** — Pure Kotlin 2.x + Jetpack Compose IME engineered for the **Samsung Galaxy A37** (`6.7"` FHD+ `1080 × 2340`, `19.5:9`, `120Hz` Super AMOLED) with 1:1 Stock Samsung One UI Keyboard layout parity.
2. **OpenKey macOS Swift (`Sources/OpenKey/macOS-Swift/`)** — Pure Swift 6 (`OpenKeySwiftCore` + `OpenKeySwiftApp`) event-tap IME for macOS (`arm64`).

---

## 1. Repository Layout & Module Architecture

| Path | Target / Module | Description |
| :--- | :--- | :--- |
| `Sources/OpenKey/android/openkey-core/` | `:openkey-core` (Pure JVM Kotlin) | Zero-Android-dependency Vietnamese engine (`VietnameseEngine.kt`, `VietnameseEnginePhonotactics.kt`), bilingual auto-switch (`BilingualAutoSwitchEngine.kt`), live candidate ranking (`AutoWordingEngine.kt`), corpus (`VietnameseDictionary.kt`), Samsung Galaxy A37 layout geometry (`PhoneLayoutMetrics.kt`, `KeyboardLayoutDefinition.kt`), gesture controller (`KeyboardGestureController.kt`), session controller (`KeyboardSessionController.kt`), settings (`OpenKeySettingsStore.kt`), localization (`OpenKeyL10n.kt`), and logger (`OpenKeyLogger.kt`). |
| `Sources/OpenKey/android/app/` | `:app` (Android IME + Compose UI) | Direct-Boot-aware `OpenKeyImeService.kt`, `InputConnectionCommitter.kt`, `ImeComposeLifecycleOwner.kt`, 120Hz Jetpack Compose keyboard UI (`KeyboardScreen.kt`, `CandidateStripView.kt`, `KeyButton.kt`), and `SettingsActivity.kt`. |
| `Sources/OpenKey/macOS-Swift/Sources/OpenKeySwiftCore/` | `OpenKeySwiftCore` (macOS Swift) | Core Vietnamese engine (`VietnameseEngine.swift`, `VietnameseEngine+Phonotactics.swift`), `BilingualAutoSwitchEngine.swift`, `AutoWordingEngine.swift`, `VietnameseDictionary.swift`, `EventTapCoordinator.swift`, `KeystrokeInjector.swift`, `OpenKeySettingsStore.swift`, `SmartSwitchStore.swift`, and `OpenKeyLogger.swift`. |
| `Sources/OpenKey/macOS-Swift/Sources/OpenKeySwiftApp/` | `OpenKeySwiftApp` (macOS App) | Menu-bar app, `CandidateBarController.swift`, `SettingsView.swift`, and `OpenKeyL10n.swift`. |
| `docs/specs/` | 5-Document Specifications | Feature specifications (`spec.md`, `decisions.md`, `design.md`, `tasks.md`, `verification.md`, `traceability_audit.json`) indexed in `docs/specs/INDEX.md`. |
| `.github/workflows/` | CI/CD Pipelines | `android-ci.yml` (`ubuntu-latest`, JDK 21) and `macos-ci.yml` (`macos-26`, Swift 6). |

---

## 2. Build & Test Commands

### Android (`Sources/OpenKey/android/`)
- **Fast Pure-JVM Core Unit Tests (`< 2s`, requires only JDK 17/21 — no Android SDK or emulator needed)**:
  ```bash
  cd Sources/OpenKey/android && ./gradlew :openkey-core:test
  ```
- **Full Android Unit Test Suite + Samsung Galaxy A37 Debug APK Assembly (requires JDK 21 + Android SDK `platforms;android-35`)**:
  ```bash
  cd Sources/OpenKey/android && ./gradlew :openkey-core:test :app:testDebugUnitTest :app:assembleDebug
  ```
  - Output APK: `Sources/OpenKey/android/app/build/outputs/apk/debug/app-debug.apk`

### macOS Swift (`Sources/OpenKey/macOS-Swift/`)
- **Swift Package Unit Tests (requires macOS host or GitHub Actions `macos-26` runner)**:
  ```bash
  swift test --package-path Sources/OpenKey/macOS-Swift
  ```
- **Build & Ad-Hoc Sign `OpenKeySwift.app`**:
  ```bash
  bash Sources/OpenKey/macOS-Swift/build-app.sh
  ```
  > **Note for Linux Remote Agents**: `Sources/OpenKey/macOS-Swift/` imports macOS frameworks (`AppKit`, `Carbon`, `CoreGraphics`, `ServiceManagement`) and cannot be compiled on a Linux container. When running on a Linux container, verify core logic via `./gradlew :openkey-core:test`, mirror corresponding changes to `.swift` files, and rely on `.github/workflows/macos-ci.yml` (`macos-26`) to compile and run the 63 macOS unit tests on push.

---

## 3. Core Architectural Invariants (Non-Negotiable)

1. **Zero Network & Zero Telemetry (`REQ-001`, `ADR-001`)**:
   - `Sources/OpenKey/android/app/src/main/AndroidManifest.xml` must **never** declare `android.permission.INTERNET` or `android.permission.ACCESS_NETWORK_STATE`.
   - `OpenKeyImeService` must remain `android:directBootAware="true"` using device-protected storage (`createDeviceProtectedStorageContext()`).
2. **Zero-Underline Atomic Direct Replacement (`REQ-005`, `ADR-005`)**:
   - Never use `InputConnection.setComposingText` by default on Android. Commit keystroke mutations atomically via `beginBatchEdit()` -> `deleteSurroundingText(backspaceCount, 0)` -> `commitText(committedText, 1)` -> `endBatchEdit()` (`BatchReplacementCoordinator.kt` / `InputConnectionCommitter.kt`).
3. **120Hz Hot-Path Latency & Commit-First Execution (`REQ-011`–`REQ-015`, `ADR-011`–`ADR-014`)**:
   - On key press, `KeyboardSessionController.onKeyPress` must return `CommitDelta` immediately so `InputConnectionCommitter.applyDelta` runs **before** asynchronous `AutoWordingEngine.computeCandidates` evaluation.
   - Spacebar trackpad cursor scrubbing must use `BatchReplacementCoordinator.moveCursorByOffset(delta)` (`setSelection`) with **zero** synchronous `getExtractedText` IPC calls during drag events.
   - Phone-only touch scope: do not re-introduce physical/Bluetooth `HardwareKeyMapper` interception into the phone keyboard (`ADR-015`).
4. **Cross-Platform Linguistic & Bilingual Engine Parity (`REQ-002`–`REQ-004`, `REQ-018`, `ADR-019`)**:
   - Keep `VietnameseEngine`, `VietnameseDictionary`, `BilingualAutoSwitchEngine`, and `AutoWordingEngine` behavior synchronized between Kotlin (`:openkey-core`) and Swift (`OpenKeySwiftCore`).
   - **Context-Ordered `V` / `E` Homograph Disambiguation (`REQ-018`, `ADR-019`)**:
     - English words whose Telex keystrokes form valid everyday Vietnamese syllables (`sex`/`"sẽ"`, `vex`/`"vẽ"`, `max`/`"mã"`, `six`/`"sĩ"`, `tax`/`"tã"`, `lax`/`"lã"`, `hex`/`"hẽ"`, `moon`/`"môn"`, `noon`/`"nôn"`, `soon`/`"sôn"`, `seen`/`"sên"`, `seem`/`"sêm"`, `beef`/`"bề"`, `reef`/`"rề"`, `room`/`"rôm"`, `boom`/`"bôm"`, `doom`/`"dôm"`, `loom`/`"lôm"`, `boots`/`"bốt"`, `roots`/`"rốt"`, `loops`/`"lốp"`, `meets`/`"mết"`, `keeps`/`"kếp"`, `moor`/`"mổ"`, `door`/`"dổ"`) must reside in `englishLookbackStems` (`lookbackRaw`) and **never** in unconditional `englishPriorityWords` (`prioRaw`).
     - Under `LanguagePriority.VIETNAMESE_FIRST` (`V`), those homographs stay Vietnamese (`"sẽ "`, `"anh sẽ làm "`, `"bác sĩ "`, `"mã nguồn "`, `"bản vẽ "`) and rank Vietnamese first in the candidate bar (`["sẽ", "sẻ", "sex"]`).
     - Under `LanguagePriority.ENGLISH_FIRST` (`E`, after an English word like `"have sex "`, `"at max "`, `"number six "`) or via 1–2 word look-back before an English word (`"sex is "`, `"max value "`), they restore to English and rank English first in the candidate bar (`["sex", "sẽ", "sẻ"]`).
5. **Secure Input Redaction in Debug Mode (`REQ-017`, `ADR-017`)**:
   - `OpenKeyLogger` (`OpenKeyLogger.kt` / `OpenKeyLogger.swift`) must use lazy closure evaluation (`() -> String`) so `debugModeEnabled == false` incurs zero allocation or I/O overhead.
   - When `isSecureField == true` (password/PIN fields), keystroke values must **never** be logged—only `"Secure input active — keystroke redacted, bypassing IME"`.
