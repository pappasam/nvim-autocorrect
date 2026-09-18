# /// script
# requires-python = ">=3.11"
# dependencies = ["codespell==2.4.1"]
# ///
"""Materialize initial-capital eligibility without adding a Neovim dependency."""

import argparse
import collections
import json
from pathlib import Path

import codespell_lib

from dictionary_policy import capitalized_corrections
from dictionary_source import load_documented_corrections, load_reviewed_corrections, load_source

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    documented = load_documented_corrections(
        Path(codespell_lib.__file__).parent / "data/dictionary.txt",
        load_reviewed_corrections(ROOT / "data/reviewed-corrections.json"),
    )
    entries = capitalized_corrections(load_source(ROOT / "data/corrections.json"), documented)
    groups = collections.defaultdict(list)
    for typo, correction in sorted(entries.items()):
        groups[correction].append(typo)
    text = json.dumps(groups, indent=2, sort_keys=True) + "\n"
    output = ROOT / "data/capitalized-corrections.json"
    if args.check:
        if output.read_text() != text:
            parser.error("Capitalized corrections are stale; run scripts/build-capitalized.py")
    else:
        output.write_text(text)
    print(f"{len(entries)} initial-capital corrections")


if __name__ == "__main__":
    main()
