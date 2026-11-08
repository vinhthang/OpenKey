#!/usr/bin/env python3
"""
Single-Source Shared Lexicon Synchronizer (scripts/sync_shared_lexicon.py)

Synchronizes macOS Swift corpus dataset from:
- Canonical human-readable shared data: Sources/OpenKey/shared-data/*
- macOS Swift corpus: Sources/OpenKey/macOS-Swift/Sources/OpenKeySwiftCore/VietnameseDictionaryCorpus.swift

Usage:
    python3 scripts/sync_shared_lexicon.py --check
    python3 scripts/sync_shared_lexicon.py --write
"""

import os
import sys
import argparse

CHUNK_SIZE = 450


def find_repo_root():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    root = os.path.dirname(script_dir)
    shared_data = os.path.join(root, "Sources", "OpenKey", "shared-data")
    if os.path.isdir(shared_data):
        return root
    cwd = os.getcwd()
    if os.path.isdir(os.path.join(cwd, "Sources", "OpenKey", "shared-data")):
        return cwd
    raise RuntimeError(f"Could not locate repository root with Sources/OpenKey/shared-data from {script_dir}")


def read_tsv_rows(filepath):
    rows = []
    with open(filepath, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            rows.append(parts)
    return rows


def load_shared_data(repo_root):
    shared_dir = os.path.join(repo_root, "Sources", "OpenKey", "shared-data")

    # 1. Syllables
    syllables_file = os.path.join(shared_dir, "vietnamese_syllables.txt")
    with open(syllables_file, "r", encoding="utf-8") as f:
        syllables = [line.strip() for line in f if line.strip() and not line.startswith("#")]

    # 2. Priorities
    priorities_file = os.path.join(shared_dir, "vietnamese_priorities.tsv")
    priorities = {}
    for parts in read_tsv_rows(priorities_file):
        if len(parts) >= 2:
            priorities[parts[0]] = int(parts[1])

    # 3. Compound bigrams
    compound_file = os.path.join(shared_dir, "vietnamese_compound_bigrams.tsv")
    compound_bigrams = {}
    for parts in read_tsv_rows(compound_file):
        if len(parts) >= 2:
            prev = parts[0]
            nexts = [x.strip() for x in parts[1].split(",") if x.strip()]
            compound_bigrams[prev] = nexts

    # 4. English words
    english_words_file = os.path.join(shared_dir, "english_words.tsv")
    en_priority = []
    en_lookback = []
    en_extra = []
    en_keep = []
    en_ranked = []
    for parts in read_tsv_rows(english_words_file):
        if len(parts) >= 2:
            cat = parts[0]
            word = parts[1]
            if cat == "priority":
                en_priority.append(word)
            elif cat == "lookback":
                en_lookback.append(word)
            elif cat == "extra":
                en_extra.append(word)
            elif cat == "keep":
                en_keep.append(word)
            elif cat == "ranked":
                en_ranked.append(word)

    # 5. English next word bigrams
    en_bigrams_file = os.path.join(shared_dir, "english_next_word_bigrams.tsv")
    en_bigrams = {}
    for parts in read_tsv_rows(en_bigrams_file):
        if len(parts) >= 2:
            prev = parts[0]
            nexts = [x.strip() for x in parts[1].split(",") if x.strip()]
            en_bigrams[prev] = nexts

    # 6. Typo and grammar rules
    rules_file = os.path.join(shared_dir, "typo_and_grammar_rules.tsv")
    vi_typo = {}
    vi_grammar = {}
    en_contraction = {}
    en_grammar = {}
    en_typo = {}
    en_dup_collapse = []
    for parts in read_tsv_rows(rules_file):
        if not parts:
            continue
        cat = parts[0]
        if cat == "vi_typo" and len(parts) >= 3:
            vi_typo[parts[1]] = parts[2]
        elif cat == "vi_grammar" and len(parts) >= 3:
            vi_grammar[parts[1]] = parts[2]
        elif cat == "en_contraction" and len(parts) >= 3:
            en_contraction[parts[1]] = parts[2]
        elif cat == "en_grammar" and len(parts) >= 3:
            en_grammar[parts[1]] = parts[2]
        elif cat == "en_typo" and len(parts) >= 3:
            en_typo[parts[1]] = parts[2]
        elif cat == "en_dup_collapse" and len(parts) >= 2:
            en_dup_collapse.append(parts[1])

    return {
        "syllables": syllables,
        "priorities": priorities,
        "compound_bigrams": compound_bigrams,
        "en_priority": en_priority,
        "en_lookback": en_lookback,
        "en_extra": en_extra,
        "en_keep": en_keep,
        "en_ranked": en_ranked,
        "en_bigrams": en_bigrams,
        "vi_typo": vi_typo,
        "vi_grammar": vi_grammar,
        "en_contraction": en_contraction,
        "en_grammar": en_grammar,
        "en_typo": en_typo,
        "en_dup_collapse": en_dup_collapse,
    }


def chunk_list(items, chunk_size):
    return [items[i:i + chunk_size] for i in range(0, len(items), chunk_size)]


def generate_swift_code(data):
    lines = [
        "import Foundation",
        "",
        "/**",
        " * Auto-generated by scripts/sync_shared_lexicon.py from Sources/OpenKey/shared-data.",
        " * Do not edit manually.",
        " */",
        "public enum VietnameseDictionaryCorpus {",
        "    public static let priorityMap: [String: Int] = ["
    ]

    for k in sorted(data["priorities"].keys()):
        lines.append(f'        "{k}": {data["priorities"][k]},')
    lines.append("    ]")
    lines.append("")

    lines.append("    public static let rawCompoundBigrams: [String: [String]] = [")
    for k in sorted(data["compound_bigrams"].keys()):
        next_items = ", ".join(f'"{x}"' for x in data["compound_bigrams"][k])
        lines.append(f'        "{k}": [{next_items}],')
    lines.append("    ]")
    lines.append("")

    lines.append("    public static let englishPriorityWords: Set<String> = [")
    for chunk in chunk_list(data["en_priority"], 15):
        items_str = ", ".join(f'"{w}"' for w in chunk)
        lines.append(f"        {items_str},")
    lines.append("    ]")
    lines.append("")

    lines.append("    public static let englishLookbackStems: Set<String> = [")
    for chunk in chunk_list(data["en_lookback"], 15):
        items_str = ", ".join(f'"{w}"' for w in chunk)
        lines.append(f"        {items_str},")
    lines.append("    ]")
    lines.append("")

    lines.append("    public static let englishExtraWords: Set<String> = [")
    for chunk in chunk_list(data["en_extra"], 15):
        items_str = ", ".join(f'"{w}"' for w in chunk)
        lines.append(f"        {items_str},")
    lines.append("    ]")
    lines.append("")

    lines.append("    public static let baseKeepWords: Set<String> = [")
    for chunk in chunk_list(data["en_keep"], 15):
        items_str = ", ".join(f'"{w}"' for w in chunk)
        lines.append(f"        {items_str},")
    lines.append("    ]")
    lines.append("")

    lines.append("    public static let englishWords: Set<String> = englishPriorityWords.union(englishLookbackStems).union(englishExtraWords)")
    lines.append("    public static let keepWords: Set<String> = baseKeepWords.union(englishWords)")
    lines.append("")

    lines.append("    public static let freqRankedList: [String] = [")
    for chunk in chunk_list(data["en_ranked"], 15):
        items_str = ", ".join(f'"{w}"' for w in chunk)
        lines.append(f"        {items_str},")
    lines.append("    ]")
    lines.append("")

    lines.append("    public static let englishNextWordBigrams: [String: [String]] = [")
    for k in sorted(data["en_bigrams"].keys()):
        next_items = ", ".join(f'"{x}"' for x in data["en_bigrams"][k])
        lines.append(f'        "{k}": [{next_items}],')
    lines.append("    ]")
    lines.append("")

    lines.append("    public static let englishTypoCorrections: [String: String] = [")
    for k in sorted(data["en_typo"].keys()):
        lines.append(f'        "{k}": "{data["en_typo"][k]}",')
    lines.append("    ]")
    lines.append("")

    lines.append("    public static let vietnameseTypoCorrections: [String: String] = [")
    for k in sorted(data["vi_typo"].keys()):
        lines.append(f'        "{k}": "{data["vi_typo"][k]}",')
    lines.append("    ]")
    lines.append("")

    lines.append("    public static let vietnameseBigramGrammar: [String: String] = [")
    for k in sorted(data["vi_grammar"].keys()):
        lines.append(f'        "{k}": "{data["vi_grammar"][k]}",')
    lines.append("    ]")
    lines.append("")

    lines.append("    public static let englishContractionGrammar: [String: String] = [")
    for k in sorted(data["en_contraction"].keys()):
        lines.append(f'        "{k}": "{data["en_contraction"][k]}",')
    lines.append("    ]")
    lines.append("")

    lines.append("    public static let englishBigramGrammar: [String: String] = [")
    for k in sorted(data["en_grammar"].keys()):
        lines.append(f'        "{k}": "{data["en_grammar"][k]}",')
    lines.append("    ]")
    lines.append("")

    lines.append("    public static let englishDuplicateCollapseWords: Set<String> = [")
    for w in sorted(data["en_dup_collapse"]):
        lines.append(f'        "{w}",')
    lines.append("    ]")
    lines.append("")

    # Syllables chunks
    syllable_chunks = chunk_list(data["syllables"], CHUNK_SIZE)
    for idx, chunk in enumerate(syllable_chunks):
        chunk_str = " ".join(chunk)
        lines.append(f'    private static let syllablesChunk{idx}: String = "{chunk_str}"')

    lines.append("")
    lines.append("    public static let rawSyllables: [String] = {")
    lines.append("        let chunks = [")
    for idx in range(len(syllable_chunks)):
        lines.append(f"            syllablesChunk{idx},")
    lines.append('        ]')
    lines.append('        return chunks.flatMap { $0.split(separator: " ").map(String.init) }')
    lines.append("    }()")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Synchronize shared lexicon files for macOS Swift")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--write", action="store_true", help="Generate Swift corpus file from shared-data")
    group.add_argument("--check", action="store_true", help="Check parity between shared-data and generated Swift corpus file")

    args = parser.parse_args()

    repo_root = find_repo_root()
    data = load_shared_data(repo_root)

    swift_target = os.path.join(
        repo_root,
        "Sources", "OpenKey", "macOS-Swift", "Sources", "OpenKeySwiftCore",
        "VietnameseDictionaryCorpus.swift"
    )

    swift_content = generate_swift_code(data)

    if args.write:
        os.makedirs(os.path.dirname(swift_target), exist_ok=True)
        with open(swift_target, "w", encoding="utf-8") as f:
            f.write(swift_content)
        print(f"[OK] Wrote Swift corpus: {swift_target}")
        sys.exit(0)

    if args.check:
        if not os.path.isfile(swift_target):
            print(f"[FAIL] Missing Swift corpus file: {swift_target}", file=sys.stderr)
            sys.exit(1)
        with open(swift_target, "r", encoding="utf-8") as f:
            existing_swift = f.read()

        if existing_swift != swift_content:
            print(f"[FAIL] Swift corpus {swift_target} differs from shared-data source!", file=sys.stderr)
            sys.exit(1)

        print("[OK] Shared lexicon parity check passed: 100% synchronized for macOS Swift corpus.")
        sys.exit(0)


if __name__ == "__main__":
    main()
