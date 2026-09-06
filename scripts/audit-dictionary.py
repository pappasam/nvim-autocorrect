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

from dictionary_source import load_protected_words, load_source
from dictionary_policy import (
    MIN_CORRECTION_FREQUENCY,
    MIN_FREQUENCY_RATIO,
    documented_short_correction,
    preferred_frequency,
    preferred_transposition,
    valid_typo_length,
)

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data/corrections.json"
PROTECTED_WORDS = ROOT / "data/protected-words.json"
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
    documented = {}
    codespell_path = Path(codespell_lib.__file__).parent / "data/dictionary.txt"
    for line in codespell_path.read_text().splitlines():
        typo, separator, correction = line.partition("->")
        if separator and re.fullmatch("[a-z]+", correction):
            documented[typo] = correction

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
    five_letter_transpositions = 0
    frequency_preferences = 0
    short_preferences = 0
    for typo, correction in sorted(entries.items()):
        pair = [typo, correction]
        neighbors = {word for word in one_edit_words(typo) if word in alternatives}
        short_preference = documented_short_correction(typo, correction, documented.get(typo))
        if not valid_typo_length(typo, correction, neighbors, documented.get(typo), frequencies):
            failures["short_ambiguous_token"].append(pair)
        elif len(typo) == 5 and documented.get(typo) != correction:
            five_letter_transpositions += 1
        if short_preference:
            short_preferences += 1
        if correction not in valid_destinations:
            failures["unverified_destination"].append(pair)
        if typo in protected:
            failures["protected_word_or_name"].append(pair)
        if typo in frequencies:
            if documented.get(typo) != correction:
                failures["undocumented_corpus_token"].append(pair)
            else:
                frequency_exceptions += 1
        other = neighbors - {correction}
        if other:
            swap = preferred_transposition(typo, neighbors)
            if short_preference:
                pass
            elif swap == correction:
                transposition_preferences += 1
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
        "documented_multi_edit_corrections": len(entries) - single_edits,
        "documented_frequency_exceptions": frequency_exceptions,
        "preferred_transposition_corrections": transposition_preferences,
        "preferred_frequency_corrections": frequency_preferences,
        "documented_short_corrections": short_preferences,
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
        "technical_destinations": sorted(set(entries.values()) - real_words),
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
