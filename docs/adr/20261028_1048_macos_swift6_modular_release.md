# ADR: Pure Swift 6 Modularization, Auto Wording Isolation & Pre-Push Verification

- **Date**: 2026-10-28 10:48
- **Status**: Accepted & Verified
- **References**:
  - [`review.md`](../../review.md)
  - [`README.md`](../../README.md)
  - [`docs/specs/2026-10-26-macos-swift-ime/spec.md`](../specs/2026-10-26-macos-swift-ime/spec.md)
  - [`docs/specs/2026-10-26-auto-wording/spec.md`](../specs/2026-10-26-auto-wording/spec.md)
  - [`docs/specs/2026-10-27-ime-intelligence-and-ecosystem/spec.md`](../specs/2026-10-27-ime-intelligence-and-ecosystem/spec.md)

## Context & Problem Statement

Before publishing the 100% Pure Swift 6 conversion (`OpenKeySwift`) of the macOS `OpenKey` input method to GitHub (`vinhthang/OpenKey`), the codebase required:
1. Strict module isolation between `VietnameseEngineState` and `AutoWordingEngine` (`REQ-008`, `ADR-007`) so disabling Auto Wording incurs zero hot-path overhead and `Tab` only accepts `.correction` candidates while `Ctrl+1..3` accepts `.correction`, `.stemCompletion`, and `.nextWord`.
2. Full decomposition of monolithic Swift source and test files so every `.swift` file in `Sources/OpenKey/macOS-Swift/Sources/` and `Sources/OpenKey/macOS-Swift/Tests/` is strictly under 500 lines (`REQ-009`, `ADR-008`).
3. Up-to-date repository documentation in `README.md` and a verified pre-push audit (`review.md`).

## Decision

1. **Engine & Auto Wording Decoupling**:
   - `VietnameseEngineState` communicates with `AutoWordingEngine` strictly via value-type `OKWordContext` snapshots, `commitExternalExpansion()`, and an optional `phonotacticRepairHook` closure.
   - `CaretPositionResolver` runs off the main thread with a `40ms` `AXUIElementSetMessagingTimeout` and accepts zero-width insertion carets (`rect.width >= 0 && rect.height > 0`).
2. **Sub-500-Line Modularization**:
   - Decomposed `VietnameseEngine.swift` into `VietnameseEngine.swift`, `VietnameseEngine+SpellingAndGrammar.swift`, `VietnameseEngine+MarkAndTone.swift`, `VietnameseEngine+KeyEventDispatcher.swift`, and `SmartSwitchStore.swift`.
   - Extracted `VietnameseUnicodeTable.swift`, `VietnameseDictionaryCorpus.swift`, `AutoWordingTypes.swift`, and `SystemEnvironmentDetector.swift`.
   - Split the test suite into `OpenKeyEngineTests.swift`, `OpenKeyEventTapTests.swift`, `OpenKeyAutoWordingTests.swift`, `OpenKeyLoadTests.swift`, and `OpenKeyTestHelpers.swift`.
3. **Documentation & Release Publication**:
   - Updated `README.md` with the 26-file project layout, feature matrix, build/code-signing instructions, and GPLv3 attribution to Mai Vũ Tuyên.

## Verification Evidence

- **Unit & Load Tests**: `33/33` tests across 5 suites passed in `0.807s` (`rtk swift test --package-path Sources/OpenKey/macOS-Swift`).
- **Release Bundle & Signing**: `Sources/OpenKey/macOS-Swift/build/OpenKeySwift.app` compiled and passed `codesign --verify --deep --strict` (`exit 0`).
- **Line Count Audit**: All 26 `.swift` files under `Sources/` and `Tests/` verified `< 500` lines (`review.md`).
