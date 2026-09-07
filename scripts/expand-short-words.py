# /// script
# requires-python = ">=3.11"
# dependencies = ["wordfreq==3.1.1", "cmudict==1.1.1", "codespell==2.4.1"]
# ///
"""Add frequency-screened typos of common three/four-letter modern English words.

Writes a separate proposed catalog by default. Run the full independent audit
before adopting it. No runtime dependencies are added to the Neovim plugin.
"""

import argparse
import collections
import json
import re
import runpy
from pathlib import Path

import cmudict
import codespell_lib
import wordfreq

from dictionary_policy import (
    MIN_SHORT_CORRECTION_FREQUENCY,
    frequency_short_correction,
    short_corpus_exception,
    short_word_typos,
)
from dictionary_source import (
    load_documented_corrections, load_protected_words, load_reviewed_corrections, load_source,
)

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scowl", required=True, type=Path)
    parser.add_argument("--source", type=Path, default=ROOT / "data/corrections.json")
    parser.add_argument("--protected-words", type=Path, default=ROOT / "data/protected-words.json")
    parser.add_argument("--reviewed-corrections", type=Path, default=ROOT / "data/reviewed-corrections.json")
    parser.add_argument("--output", type=Path, default=Path("/tmp/short-word-corrections.json"))
    args = parser.parse_args()
    if not (args.scowl / "final").is_dir():
        parser.error("--scowl must contain the SCOWL final/ directory")

    audit = runpy.run_path(str(ROOT / "scripts/audit-dictionary.py"))
    normalized, one_edit_words = audit["normalized"], audit["one_edit_words"]
    protected, destinations = set(), set()
    for path in sorted((args.scowl / "final").iterdir()):
        for word in path.read_text(encoding="latin1").splitlines():
            protected.add(normalized(word))
            if "-words." in path.name and int(path.suffix[1:]) <= 60 and re.fullmatch("[a-z]{3,4}", word):
                destinations.add(word)
    protected.update(normalized(word) for word in cmudict.words())
    protected.update(load_protected_words(args.protected_words))
    frequencies = wordfreq.get_frequency_dict("en")
    documented = load_documented_corrections(
        Path(codespell_lib.__file__).parent / "data/dictionary.txt",
        load_reviewed_corrections(args.reviewed_corrections),
    )

    entries = load_source(args.source)
    alternatives = protected | set(entries.values()) | audit["TECHNICAL_WORDS"]
    additions = {}
    rejected = collections.Counter()
    for correction in sorted(destinations, key=lambda word: (-frequencies.get(word, 0), word)):
        if frequencies.get(correction, 0) < MIN_SHORT_CORRECTION_FREQUENCY:
            continue
        for typo in sorted(short_word_typos(correction)):
            if typo in entries:
                continue
            if typo in protected:
                rejected["protected_word_or_name"] += 1
                continue
            if typo in frequencies and not short_corpus_exception(typo, correction, documented.get(typo)):
                rejected["unsafe_or_undocumented_corpus_token"] += 1
                continue
            candidates = {word for word in one_edit_words(typo) if word in alternatives}
            if not frequency_short_correction(typo, correction, candidates, frequencies):
                rejected["frequency_or_ambiguity"] += 1
                continue
            if typo in additions and additions[typo] != correction:
                raise ValueError(f"Conflicting additions for {typo}")
            additions[typo] = correction
    entries.update(additions)
    groups = collections.defaultdict(list)
    for typo, correction in sorted(entries.items()):
        groups[correction].append(typo)
    args.output.write_text(json.dumps(groups, indent=2, sort_keys=True) + "\n")
    print(json.dumps({
        "added": len(additions),
        "destinations_added_to": len(set(additions.values())),
        "additions_by_destination_length": dict(sorted(collections.Counter(map(len, additions.values())).items())),
        "additions_by_typo_length": dict(sorted(collections.Counter(map(len, additions)).items())),
        "entries": len(entries),
        "rejected_candidate_pairs": dict(rejected),
        "output": str(args.output),
    }, indent=2))


if __name__ == "__main__":
    main()
