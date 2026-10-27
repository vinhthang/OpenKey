# Specification: Experimental Auto Wording, Phonotactic Grammar Repair & Predictive Candidate Bar (`2026-10-26-auto-wording`)

- **Feature ID**: `2026-10-26-auto-wording`
- **Status**: `Completed`
- **Date**: 2026-10-26

## 1. Overview & Problem Statement

While typing Vietnamese quickly in Telex or VNI, users frequently encounter three friction points:
1. **Omitted vowel modifiers in phonotactically unambiguous contexts**: Typing `tiengs` (omitting the second `e` in `tieengs` → `tiếng`) or `uow` + final consonant (`truowngf` → `trường`) leaves the syllable uncomposed or rejected as invalid spelling even though `ie`/`ye` before a final consonant is unconditionally `iê`/`yê` in Vietnamese orthography.
2. **Repetitive typing of common Vietnamese abbreviations and compound words**: Frequently typed words (`ko` → `không`, `dc`/`đc` → `được`, `trc` → `trước`, `ng` → `người`, `vn` → `Việt Nam`) and multi-syllable compounds (`thành phố`, `nghiên cứu`, `phát triển`, `công nghệ`) require typing every character manually.
3. **Wrong-syntax / transposed syllables**: When a syllable has transposed Telex keys (`tineg`, `veit`, `ngheing`) or missing diacritics (`thanh`, `duoc`, `nguoi`), there is no non-intrusive way to see and accept the top valid Vietnamese word candidates.

This specification defines an experimental, sub-millisecond, 100% Pure Swift 6 **Auto Wording & Grammar Engine** (`AutoWordingEngine`) and a macOS 26 **Liquid Glass Floating Candidate Bar** (`CandidateBarController`) integrated into `OpenKeySwift`.

---

## 2. Normative Requirements

### `REQ-001`: Granular Experimental Auto Wording Configuration (`OpenKeySettingsStore`, Menu Bar & `SettingsView`)
- **Description**: `OpenKeySettingsStore` MUST persist a master `autoWordingEnabled` toggle and three independent sub-toggles (`grammarRepairEnabled`, `shorthandExpansionEnabled`, `candidateSuggestionsEnabled`), exposed via a master toggle in the status bar menu and a dedicated `"Auto Wording & Ngữ pháp (Thử nghiệm)"` section in `SettingsView`.
- **Acceptance Criteria**:
  1. `OpenKeySettingsStore` persists `autoWordingEnabled` (default `true`), `grammarRepairEnabled` (default `true`), `shorthandExpansionEnabled` (default `true`), and `candidateSuggestionsEnabled` (default `true`) in `UserDefaults` and syncs them to `VietnameseEngine` and `AutoWordingEngine`.
  2. `OpenKeySwiftApp` displays a checkable menu item `"Auto Wording & Gợi ý từ (Thử nghiệm)"` in the status bar dropdown that toggles `settings.autoWordingEnabled`.
  3. `SettingsView` includes a `"Auto Wording & Ngữ pháp (Thử nghiệm)"` section in its grouped `Form` with the master toggle and the three sub-toggles (disabled when `autoWordingEnabled == false`).

### `REQ-002`: Phonotactic Syllable Repair (`ie`/`ye` + Final Consonant → `iê`/`yê` and `uow`/`uwo` → `ươ`)
- **Description**: When `autoWordingEnabled && grammarRepairEnabled` is active, `VietnameseEngine` MUST automatically repair phonotactically unambiguous vowel clusters during syllable composition without requiring double vowel keystrokes.
- **Acceptance Criteria**:
  1. When a syllable contains the vowel pair `i + e` or `y + e` (including `qu + y + e` or `g + i + e`) followed by a valid final consonant (`c`, `p`, `t`, `m`, `n`, `ng`, `nh`, `ch`) and a tone mark or final consonant is typed (e.g., `tiengs`, `viets`, `bienf`, `hiens`, `yens`, `nghiengf`), `VietnameseEngine` automatically applies `TONE_MASK` (`e` → `ê`) and composes `tiếng`, `viết`, `biền`, `hiến`, `yến`, `nghiềng`.
  2. When a syllable contains `u + o` with a horn modifier (`w` typed as `uow` + final consonant or `uo` + final consonant + `w`, e.g., `truowngf`, `muowns`, `nuowcs`), `VietnameseEngine` normalizes both vowels to `ư + ơ` (`TONEW_MASK`) and composes `trường`, `mướn`, `nước`.
  3. When `autoWordingEnabled == false` or `grammarRepairEnabled == false`, strict Telex/VNI rules apply without automatic `ie` → `iê` promotion.

### `REQ-003`: Common Vietnamese Shorthand Auto-Expansion on `Space`
- **Description**: When `autoWordingEnabled && shorthandExpansionEnabled` is active, pressing `Space` after a recognized standalone Vietnamese shorthand token MUST atomically replace the shorthand token with its full Vietnamese word/phrase plus a trailing space.
- **Acceptance Criteria**:
  1. Pressing `Space` after typing `"ko"`, `"dc"`/`"đc"`, `"trc"`, `"ng"`, `"nhg"`, `"vs"`, `"ntn"`, `"bt"`, `"cx"`, `"mk"`, `"vn"`, `"hn"`, or `"tphcm"`/`"hcm"` replaces the shorthand characters and outputs `"không "`, `"được "`, `"trước "`, `"người "`, `"nhưng "`, `"với "`, `"như thế nào "`, `"bình thường "`, `"cũng "`, `"mình "`, `"Việt Nam "`, `"Hà Nội "`, or `"TP. Hồ Chí Minh "`.
  2. Capitalization of the shorthand token is preserved: Capitalized initial (`"Ko"`, `"Dc"`) expands to Title Case (`"Không "`, `"Được "`), and all-caps (`"KO"`, `"DC"`) expands to UPPERCASE (`"KHÔNG "`, `"ĐƯỢC "`).
  3. When `autoWordingEnabled == false` or `shorthandExpansionEnabled == false`, shorthand tokens are not expanded on `Space`.

### `REQ-004`: Multi-Thousand-Word Vietnamese Reference Dictionary (`VietnameseDictionary`) & Sub-Millisecond Wrong-Syntax / Compound Prediction (`AutoWordingEngine`)
- **Description**: `OpenKeySwiftCore` MUST include a curated multi-thousand-word Vietnamese reference dictionary (`VietnameseDictionary.swift`, containing `>= 3,500` valid Vietnamese syllables and `>= 1,500` compound word pairs, totaling `>= 5,000` lexical entries) indexed in memory so `AutoWordingEngine` computes up to 3 ranked `WordCandidate` suggestions in under `1ms` for (a) current syllables with wrong Vietnamese syntax, transposed Telex keys, or missing diacritics, and (b) predictive next-word compound completions after pressing `Space`.
- **Acceptance Criteria**:
  1. `VietnameseDictionary` contains `>= 5,000` total Vietnamese lexical entries (`>= 3,500` single syllables with frequency ranks and `>= 1,500` two-syllable compound phrases) pre-indexed at startup by unaccented ASCII stem, sorted character anagram key (for O(1) transposition lookup), and first-syllable bigram head.
  2. While typing a syllable (`index >= 2`), if the syllable has wrong Vietnamese syntax/transposition (e.g., `"tineg"`, `"veit"`, `"ngheing"`, `"hcinh"`, `"taonf"`) or matches an unaccented/ambiguous stem in `VietnameseDictionary` (e.g., `"thanh"`, `"duoc"`, `"nguoi"`, `"chao"`, `"viet"`), `AutoWordingEngine` queries `VietnameseDictionary` and returns up to 3 valid Vietnamese `WordCandidate` items (`kind: .correction`, `replaceLength: currentComposedLength`) ranked by edit/transposition distance and lexical frequency.
  3. When `Space` is pressed after a valid Vietnamese syllable (or after accepting a candidate), `AutoWordingEngine` queries `VietnameseDictionary`'s compound bigram index and returns up to 3 `WordCandidate` items (`kind: .nextWord`, `replaceLength: 0`, e.g., `"thành"` → `["phố", "công", "viên"]`, `"nghiên"` → `["cứu", "ngẫm", "túc"]`, `"phát"` → `["triển", "hiện", "hành"]`, `"công"` → `["việc", "nghệ", "ty"]`).

### `REQ-005`: Keyboard Candidate Selection (`Tab`, `Ctrl+1..3`, `Esc`) in `EventTapCoordinator`
- **Description**: When `autoWordingEnabled && candidateSuggestionsEnabled` is active and `AutoWordingEngine` has non-empty active candidates, `EventTapCoordinator.evaluateKeyEvent` MUST handle `Tab` (accept `#1`), `Control + 1..3` (accept `#1..#3`), and `Esc` (dismiss candidates).
- **Acceptance Criteria**:
  1. Pressing `Tab` (`KEY_TAB = 48` with no Command/Option/Control modifiers) when active candidates exist returns `.acceptCandidate(candidates[0])`, injecting `replaceLength` backspaces followed by `candidate.text + " "`, resetting the engine session, and advancing `AutoWordingEngine` to next-word predictions for the accepted word.
  2. Pressing `Control + 1` (`KEY_1`), `Control + 2` (`KEY_2`), or `Control + 3` (`KEY_3`) when the corresponding candidate index (`0`, `1`, or `2`) exists returns `.acceptCandidate(candidates[i])`.
  3. Pressing `Esc` (`KEY_ESC = 53`) when active candidates exist clears the candidate list and swallows the `Esc` keystroke (`.dismissCandidates`); when no candidates are active, `Esc` passes through to the active application and resets the session.

### `REQ-006`: Floating Liquid Glass Candidate Bar (`CandidateBarController`) Following Active Text Caret
- **Description**: `OpenKeySwiftApp` MUST render active `WordCandidate` items in a non-activating floating `NSPanel` styled with macOS 26 Liquid Glass (`.glassEffect(.regular, in: .capsule)`) positioned near the focused Accessibility text caret.
- **Acceptance Criteria**:
  1. `CandidateBarController` manages a borderless, non-activating `NSPanel` (`styleMask: [.borderless, .nonactivatingPanel]`, `level: .popUpMenu`) that never steals keyboard focus from the active application.
  2. The candidate bar renders up to 3 candidates with their shortcut badges (`Tab` / `⌃1`, `⌃2`, `⌃3`) using `.glassEffect(.regular, in: .capsule)` and supports clicking any candidate pill with the mouse to trigger acceptance.
  3. `CaretPositionResolver` queries `AXUIElementCopyParameterizedAttributeValue` (`kAXBoundsForRangeParameterizedAttribute`) on the focused UI element to position the panel `6pt` below the text caret, clamping to the visible screen frame and falling back to the focused element's bounds or mouse cursor location when caret bounds are unavailable.
