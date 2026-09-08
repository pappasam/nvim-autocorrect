# /// script
# requires-python = ">=3.11"
# dependencies = ["wordfreq==3.1.1", "cmudict==1.1.1", "codespell==2.4.1"]
# ///
"""Audit the JSON correction dictionary against independent spelling/name corpora.

uv run scripts/audit-dictionary.py --scowl /path/to/scowl-2020.12.07
This is an offline maintenance check once its dependencies and SCOWL are present;
none of these dictionaries or Python packages are loaded by Neovim.
"""

from __future__ import annotations

import argparse
import collections
import hashlib
import importlib.metadata
import json
import re
import string
import unicodedata
from pathlib import Path

import cmudict
import codespell_lib
import wordfreq

from dictionary_source import (
    load_documented_corrections, load_protected_words, load_reviewed_corrections, load_source,
)
from dictionary_policy import (
    MIN_CORRECTION_FREQUENCY,
    MIN_FREQUENCY_RATIO,
    MIN_SHORT_CORRECTION_FREQUENCY,
    MIN_FIVE_LETTER_FREQUENCY,
    MIN_JOINED_COMPONENT_FREQUENCY,
    documented_short_correction,
    frequency_short_correction,
    frequency_five_letter_correction,
    preferred_frequency,
    preferred_transposition,
    short_corpus_exception,
    valid_typo_length,
    joined_word_splits,
    valid_joined_correction,
)

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data/corrections.json"
PROTECTED_WORDS = ROOT / "data/protected-words.json"
REVIEWED_CORRECTIONS = ROOT / "data/reviewed-corrections.json"
# Existing, correctly spelled computing terms missing from SCOWL's <=80 words.
# This allowlist validates destinations only; it never permits a protected typo.
TECHNICAL_WORDS = {
    "booleans",
    "cacheable",
    "composability",
    "composable",
    "deallocate",
    "deallocated",
    "deallocates",
    "deallocating",
    "deallocation",
    "deallocations",
    "filesystem",
    "filesystems",
    "lifecycle",
    "lifecycles",
    "middleware",
    "namespace",
    "namespaces",
    "runtimes",
    "templated",
    "templating",
}


def normalized(word: str) -> str:
    ascii_word = unicodedata.normalize("NFKD", word).encode("ascii", "ignore").decode()
    return re.sub("[^a-z]", "", ascii_word.lower())


def one_edit_words(word: str):
    """Independently enumerate Levenshtein edits plus adjacent transpositions."""
    for index, char in enumerate(word):
        before, after = word[:index], word[index + 1 :]
        yield before + after
        if index + 1 < len(word) and char != word[index + 1]:
            yield before + word[index + 1] + char + word[index + 2 :]
        for letter in string.ascii_lowercase:
            if letter != char:
                yield before + letter + after
    for index in range(len(word) + 1):
        before, after = word[:index], word[index:]
        for letter in string.ascii_lowercase:
            yield before + letter + after


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scowl", required=True, type=Path)
    parser.add_argument("--source", type=Path, default=SOURCE)
    parser.add_argument("--protected-words", type=Path, default=PROTECTED_WORDS)
    parser.add_argument("--reviewed-corrections", type=Path, default=REVIEWED_CORRECTIONS)
    parser.add_argument("--expect", type=int)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()

    final = args.scowl / "final"
    if not final.is_dir():
        parser.error("--scowl must contain the SCOWL final/ directory")
    protected, real_words = set(), set()
    corpus_hash = hashlib.sha256()
    for path in sorted(final.iterdir()):
        level = int(path.suffix[1:])
        data = path.read_bytes()
        corpus_hash.update(path.name.encode() + b"\0" + data)
        for word in data.decode("latin1").splitlines():
            protected.add(normalized(word))
            if re.fullmatch("[A-Za-z]+", word):
                if "-words." in path.name and level <= 80:
                    real_words.add(word.lower())

    pronunciation_words = {normalized(word) for word in cmudict.words()}
    protected.update(pronunciation_words)
    supplemental = load_protected_words(args.protected_words)
    protected.update(supplemental)
    frequencies = wordfreq.get_frequency_dict("en")
    codespell_path = Path(codespell_lib.__file__).parent / "data/dictionary.txt"
    reviewed = load_reviewed_corrections(args.reviewed_corrections)
    documented = load_documented_corrections(codespell_path, reviewed)

    entries = load_source(args.source)
    valid_destinations = real_words | TECHNICAL_WORDS
    # Every protected spelling is also a possible competing correction, including
    # size-95 words and normalized accented, hyphenated, or possessive forms.
    alternatives = protected | valid_destinations | set(entries.values())
    failures: dict[str, list] = collections.defaultdict(list)
    if args.expect is not None and len(entries) != args.expect:
        failures["entry_count"] = [len(entries), args.expect]
    frequency_exceptions = 0
    single_edits = 0
    transposition_preferences = 0
    rare_alternative_transpositions = 0
    documented_transpositions = 0
    five_letter_transpositions = 0
    frequency_preferences = 0
    short_preferences = 0
    frequency_short_preferences = 0
    frequency_five_letter_corrections = 0
    reviewed_corrections = 0
    reviewed_corpus_exceptions = 0
    joined_corrections = 0
    for typo, correction in sorted(entries.items()):
        pair = [typo, correction]
        neighbors = {word for word in one_edit_words(typo) if word in alternatives}
        short_preference = documented_short_correction(typo, correction, documented.get(typo))
        frequency_short = frequency_short_correction(typo, correction, neighbors, frequencies)
        frequency_five = frequency_five_letter_correction(typo, correction, neighbors, frequencies)
        if frequency_five:
            frequency_five_letter_corrections += 1
        if typo in reviewed and reviewed[typo]["correction"] == correction:
            reviewed_corrections += 1
            reviewed_corpus_exceptions += int(typo in frequencies)
        if typo in protected:
            failures["protected_word_or_name"].append(pair)
        if " " in correction:
            if not valid_joined_correction(
                typo, correction, documented.get(typo), neighbors,
                joined_word_splits(typo, alternatives), real_words, frequencies,
            ):
                failures["unsafe_joined_word_correction"].append(pair)
            joined_corrections += 1
            if typo in frequencies and documented.get(typo) == correction:
                frequency_exceptions += 1
            continue
        if not valid_typo_length(typo, correction, neighbors, documented.get(typo), frequencies):
            failures["short_ambiguous_token"].append(pair)
        elif len(typo) == 5 and len(correction) == 5 and documented.get(typo) != correction and not frequency_five:
            five_letter_transpositions += 1
        if frequency_short and not short_preference:
            frequency_short_preferences += 1
        if short_preference:
            short_preferences += 1
        if correction not in valid_destinations:
            failures["unverified_destination"].append(pair)
        if typo in frequencies:
            if documented.get(typo) != correction:
                failures["undocumented_corpus_token"].append(pair)
            elif len(typo) < 5 and len(correction) in (3, 4) and not short_preference and not short_corpus_exception(typo, correction, documented.get(typo)):
                failures["unsafe_short_corpus_token"].append(pair)
            else:
                frequency_exceptions += 1
        other = neighbors - {correction}
        if other:
            swap = preferred_transposition(typo, neighbors, frequencies, documented.get(typo))
            if short_preference:
                pass
            elif frequency_short:
                frequency_preferences += 1
            elif any(frequency_short_correction(typo, word, neighbors, frequencies) for word in other):
                failures["competing_correction"].append(pair + [sorted(other)])
            elif swap == correction:
                transposition_preferences += 1
                if preferred_transposition(typo, neighbors, frequencies) is None:
                    documented_transpositions += 1
                elif preferred_transposition(typo, neighbors) is None:
                    rare_alternative_transpositions += 1
            elif swap is None and preferred_frequency(neighbors, frequencies) == correction:
                frequency_preferences += 1
            else:
                failures["competing_correction"].append(pair + [sorted(other)])
        if correction in neighbors:
            single_edits += 1
        elif documented.get(typo) != correction:
            failures["undocumented_multi_edit"].append(pair)
    canonical = json.dumps(entries, sort_keys=True, separators=(",", ":")).encode()
    supplemental_canonical = json.dumps(
        supplemental, sort_keys=True, separators=(",", ":")
    ).encode()
    report = {
        "passed": not failures,
        "entries": len(entries),
        "destinations": len(set(entries.values())),
        "single_edit_corrections": single_edits,
        "documented_multi_edit_corrections": len(entries) - single_edits - joined_corrections,
        "joined_word_corrections": joined_corrections,
        "joined_word_policy": {
            "minimum_input_length": 6,
            "minimum_component_frequency": MIN_JOINED_COMPONENT_FREQUENCY,
            "destination_words": 2,
            "documentation_required": True,
            "single_word_alternatives": "block",
            "alternative_splits": "block",
        },
        "documented_frequency_exceptions": frequency_exceptions,
        "preferred_transposition_corrections": transposition_preferences,
        "rare_alternative_transposition_corrections": rare_alternative_transpositions,
        "documented_transposition_corrections": documented_transpositions,
        "transposition_preference": {
            "rare_alternative_minimum_length": 5,
            "minimum_frequency": MIN_CORRECTION_FREQUENCY,
            "minimum_ratio": MIN_FREQUENCY_RATIO,
            "frequency_competitors": "same-length non-swap alternatives",
            "longer_alternatives": "block",
            "documented_swap_competitors": "strictly less frequent same-length alternatives",
        },
        "preferred_frequency_corrections": frequency_preferences,
        "documented_short_corrections": short_preferences,
        "frequency_short_corrections": frequency_short_preferences,
        "frequency_five_letter_corrections": frequency_five_letter_corrections,
        "five_letter_preference": {
            "minimum_frequency": MIN_FIVE_LETTER_FREQUENCY,
            "minimum_ratio": MIN_FREQUENCY_RATIO,
            "destination_lengths": [5],
            "typo_lengths": [4, 5],
        },
        "reviewed_corrections": reviewed_corrections,
        "reviewed_corpus_exceptions": reviewed_corpus_exceptions,
        "reviewed_records": len(reviewed),
        "reviewed_sha256": hashlib.sha256(
            json.dumps(reviewed, sort_keys=True, separators=(",", ":")).encode()
        ).hexdigest(),
        "short_word_preference": {
            "minimum_frequency": MIN_SHORT_CORRECTION_FREQUENCY,
            "minimum_ratio": MIN_FREQUENCY_RATIO,
            "destination_lengths": [3, 4],
            "typo_lengths": [3, 4, 5],
            "three_four_letter_corpus_exceptions": "documented adjacent swap or repeated letter",
        },
        "short_word_destinations": len({word for word in entries.values() if len(word) in (3, 4)}),
        "frequency_preference": {
            "minimum_frequency": MIN_CORRECTION_FREQUENCY,
            "minimum_ratio": MIN_FREQUENCY_RATIO,
        },
        "five_letter_transposition_exceptions": five_letter_transpositions,
        "protected_dictionary_tokens": len(protected),
        "supplemental_protected_tokens": len(supplemental),
        "supplemental_protected_sha256": hashlib.sha256(supplemental_canonical).hexdigest(),
        "alternative_dictionary_tokens": len(alternatives),
        "protected_frequency_tokens": len(frequencies),
        "technical_destinations": sorted(word for word in set(entries.values()) - real_words if " " not in word),
        "mapping_sha256": hashlib.sha256(canonical).hexdigest(),
        "scowl_lists_sha256": corpus_hash.hexdigest(),
        "packages": {
            name: importlib.metadata.version(name)
            for name in ("wordfreq", "cmudict", "codespell")
        },
        "failure_counts": {name: len(values) for name, values in failures.items()},
        "failure_examples": {name: values[:20] for name, values in failures.items()},
        "rejected_typos": sorted(
            {
                item[0]
                for values in failures.values()
                for item in values
                if isinstance(item, list) and item and isinstance(item[0], str)
            }
        ),
    }
    text = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.report:
        args.report.write_text(text)
    print(text, end="")
    return int(bool(failures))


if __name__ == "__main__":
    raise SystemExit(main())
