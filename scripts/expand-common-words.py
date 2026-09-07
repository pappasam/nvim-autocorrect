# /// script
# requires-python = ">=3.11"
# dependencies = ["wordfreq==3.1.1", "cmudict==1.1.1", "codespell==2.4.1"]
# ///
"""Add common five-letter keyboard corrections and exact reviewed spellings.

Writes a separate proposal; run the full independent audit before adopting it.
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
    MIN_FIVE_LETTER_FREQUENCY,
    frequency_five_letter_correction,
    frequency_short_correction,
    keyboard_typos,
    preferred_frequency,
    preferred_transposition,
    short_corpus_exception,
    valid_typo_length,
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
    parser.add_argument("--output", type=Path, default=Path("/tmp/common-word-corrections.json"))
    args = parser.parse_args()
    if not (args.scowl / "final").is_dir():
        parser.error("--scowl must contain the SCOWL final/ directory")
    audit = runpy.run_path(str(ROOT / "scripts/audit-dictionary.py"))
    normalized, one_edit_words = audit["normalized"], audit["one_edit_words"]
    protected, destinations, valid_destinations = set(), set(), set(audit["TECHNICAL_WORDS"])
    for path in sorted((args.scowl / "final").iterdir()):
        level = int(path.suffix[1:])
        for word in path.read_text(encoding="latin1").splitlines():
            protected.add(normalized(word))
            if "-words." in path.name and level <= 80 and re.fullmatch("[A-Za-z]+", word):
                valid_destinations.add(word.lower())
            if "-words." in path.name and level <= 60 and re.fullmatch("[a-z]{5}", word):
                destinations.add(word)
    protected.update(normalized(word) for word in cmudict.words())
    protected.update(load_protected_words(args.protected_words))
    frequencies = wordfreq.get_frequency_dict("en")
    reviewed = load_reviewed_corrections(args.reviewed_corrections)
    documented = load_documented_corrections(
        Path(codespell_lib.__file__).parent / "data/dictionary.txt", reviewed,
    )
    entries = load_source(args.source)
    alternatives = protected | valid_destinations | set(entries.values())
    proposed = {(typo, record["correction"]) for typo, record in reviewed.items()}
    for correction in destinations:
        if frequencies.get(correction, 0) >= MIN_FIVE_LETTER_FREQUENCY:
            proposed.update((typo, correction) for typo in keyboard_typos(correction) if len(typo) in (4, 5))
    additions, conflicts = {}, {}
    rejected, categories = collections.Counter(), collections.Counter()
    for typo, correction in sorted(proposed):
        if entries.get(typo) == correction:
            continue
        if correction not in valid_destinations:
            rejected["unverified_destination"] += 1
            continue
        if typo in protected:
            rejected["protected_word_or_name"] += 1
            continue
        if typo in frequencies and documented.get(typo) != correction:
            rejected["undocumented_corpus_token"] += 1
            continue
        if typo in frequencies and len(typo) < 5 and len(correction) in (3, 4) and not short_corpus_exception(typo, correction, documented.get(typo)):
            rejected["unsafe_short_corpus_token"] += 1
            continue
        candidates = {word for word in one_edit_words(typo) if word in alternatives}
        if not valid_typo_length(typo, correction, candidates, documented.get(typo), frequencies):
            rejected["length"] += 1
            continue
        if typo not in reviewed and not frequency_five_letter_correction(typo, correction, candidates, frequencies):
            rejected["frequency_or_ambiguity"] += 1
            continue
        # Preserve the audit's candidate-selection order, including short words.
        short = {word for word in candidates if frequency_short_correction(typo, word, candidates, frequencies)}
        winner = next(iter(short)) if short else (
            preferred_transposition(typo, candidates, frequencies)
            or preferred_frequency(candidates, frequencies)
        )
        if winner != correction:
            rejected["frequency_or_ambiguity"] += 1
            continue
        if typo in entries or (typo in additions and additions[typo] != correction):
            conflicts[typo] = [entries.get(typo, additions.get(typo)), correction]
            continue
        additions[typo] = correction
        categories["reviewed" if typo in reviewed else "five_letter_keyboard"] += 1
    if conflicts:
        raise ValueError(f"Existing or proposed mappings need review: {conflicts}")
    entries.update(additions)
    groups = collections.defaultdict(list)
    for typo, correction in sorted(entries.items()):
        groups[correction].append(typo)
    args.output.write_text(json.dumps(groups, indent=2, sort_keys=True) + "\n")
    print(json.dumps({
        "added": len(additions),
        "categories": dict(categories),
        "destinations_added_to": len(set(additions.values())),
        "additions_by_typo_length": dict(sorted(collections.Counter(map(len, additions)).items())),
        "entries": len(entries),
        "rejected_candidate_pairs": dict(rejected),
        "output": str(args.output),
    }, indent=2))


if __name__ == "__main__":
    main()
