# Architecture Decision Records (`2026-10-26-auto-wording`)

## `ADR-001`: Deterministic In-Memory Vietnamese Lexicon & Bigram Engine Over `FoundationModels` LLM
- **Status**: Proposed
- **Date**: 2026-10-26
- **Addresses**: `REQ-003`, `REQ-004`
- **Context**:
  - Real-time input method keystroke callbacks (`CGEventTap`) must complete in `< 1ms` to avoid `WindowServer` tap timeouts and typing lag.
  - On macOS 26, `FoundationModels.SystemLanguageModel.default` requires Apple Intelligence to be enabled (`unavailable(appleIntelligenceNotEnabled)` on machines where Apple Intelligence is off) and incurs `50–200ms` token generation latency.
- **Decision**:
  - Implement `VietnameseDictionary.swift` and `AutoWordingEngine.swift` in 100% Pure Swift 6 inside `OpenKeySwiftCore` using deterministic, zero-IPC in-memory data structures over a `>= 5,000`-entry Vietnamese reference dictionary:
    1. A curated shorthand dictionary for atomic `Space` expansion.
    2. `VietnameseDictionary`: `>= 3,500` valid Vietnamese syllables (generated and frequency-ranked across standard Vietnamese onset + rime + tone combinations) and `>= 1,500` two-syllable Vietnamese compound words, indexed in memory by:
       - `stemIndex: [String: [String]]` (unaccented ASCII stem → frequency-ordered accented syllables, e.g., `"tieng"` → `["tiếng", "tiêng", "tiềng", ...]`, `"duoc"` → `["được", "dược", "duộc"]`).
       - `anagramIndex: [String: [String]]` (sorted ASCII character signature → valid stems, enabling O(1) lookup of any transposed-keystroke typo such as `"tineg"` → `"tieng"` → `["tiếng", ...]`, `"ngheing"` → `"nghieng"` → `["nghiêng", ...]`).
       - `bigramIndex: [String: [String]]` (first syllable → top compound continuations from `>= 1,500` compound words).
- **Consequences**:
  - Works 100% offline on every Mac without Apple Intelligence dependencies, covers thousands of real Vietnamese syllables and compound words, and resolves transpositions, missing diacritics, and compound predictions in `< 0.1ms`.

---

## `ADR-002`: Phonotactic `ie`/`ye` + Final Consonant Auto-Promotion Inside `VietnameseEngine`
- **Status**: Proposed
- **Date**: 2026-10-26
- **Addresses**: `REQ-002`
- **Context**:
  - In standard Vietnamese orthography, the vowel combinations `ie` and `ye` never appear as un-circumflexed `ie`/`ye` when followed by a final consonant (`c`, `p`, `t`, `m`, `n`, `ng`, `nh`, `ch`) — they are always `iê`/`yê` (`tiếng`, `việt`, `biển`, `nghiêng`, `yến`). Users typing fast frequently omit the second `e` (`tiengs` instead of `tieengs`).
- **Decision**:
  - When `autoWordingEnabled && grammarRepairEnabled` is enabled in `VietnameseEngine`, detect `[KEY_I, KEY_E]` or `[KEY_Y, KEY_E]` (including after `q`/`u` or `g`) followed by a valid final consonant in `checkGrammar` / `checkSpelling` and automatically apply `TONE_MASK` to `KEY_E`, re-running vowel and mark placement.
- **Consequences**:
  - Eliminates the most common fast-typing Telex error (`tiengs` → `tiếng`, `viets` → `viết`) while preserving strict Telex behavior when `grammarRepairEnabled` is toggled off.

---

## `ADR-003`: Non-Intrusive Candidate Acceptance Keys (`Tab`, `Ctrl+1..3`, `Esc`)
- **Status**: Proposed
- **Date**: 2026-10-26
- **Addresses**: `REQ-005`
- **Context**:
  - Binding plain number keys `1`, `2`, `3` to candidate selection would collide with VNI tone keys (`1`..`9`) and prevent users from typing numbers after words in Telex mode.
- **Decision**:
  - Use `Tab` (unmodified) to accept the primary candidate (`#1`), `Control + 1`, `Control + 2`, `Control + 3` to accept specific candidates `#1..#3`, and `Esc` to dismiss the candidate bar when visible.
- **Consequences**:
  - Zero collision with VNI tone input or numeric typing, while giving single-keystroke (`Tab`) access to the top suggestion.

---

## `ADR-004`: Non-Activating `NSPanel` with macOS 26 Liquid Glass & `AXUIElement` Caret Tracking
- **Status**: Proposed
- **Date**: 2026-10-26
- **Addresses**: `REQ-006`
- **Context**:
  - Because `OpenKeySwift` operates via a global `CGEventTap` rather than `InputMethodKit`, it must display its own floating candidate bar without stealing focus from the frontmost app.
- **Decision**:
  - Use an `NSPanel` configured with `[.borderless, .nonactivatingPanel]`, `level = .popUpMenu`, and `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, hosting a SwiftUI view styled with `.glassEffect(.regular, in: .capsule)`.
  - Resolve the text caret screen rect via Accessibility `AXUIElementCopyParameterizedAttributeValue(..., kAXBoundsForRangeParameterizedAttribute, ...)` on the focused UI element, with graceful fallback to mouse location when an app does not expose Accessibility text range bounds.
- **Consequences**:
  - Native macOS 26 Tahoe appearance that tracks the text cursor across standard macOS apps without interrupting typing focus.
