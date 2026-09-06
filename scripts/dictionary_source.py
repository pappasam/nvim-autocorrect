"""Load the grouped correction catalog without silently overwriting entries."""

import json
import re
from pathlib import Path
from urllib.parse import urlsplit


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate JSON key: {key}")
        result[key] = value
    return result


def load_source(path: Path) -> dict[str, str]:
    groups = json.loads(path.read_text(), object_pairs_hook=unique_object)
    if not isinstance(groups, dict):
        raise ValueError("Corrections must be a JSON object")
    entries = {}
    for correction, typos in groups.items():
        if not re.fullmatch("[a-z]+", correction):
            raise ValueError("Corrections must be lowercase ASCII words")
        if not isinstance(typos, list):
            raise ValueError("Typos must be a JSON array")
        if not typos:
            raise ValueError(f"Typo lists must not be empty: {correction}")
        for typo in typos:
            if not isinstance(typo, str) or not re.fullmatch("[a-z]+", typo):
                raise ValueError("Typos must be lowercase ASCII words")
            if typo == correction:
                raise ValueError(f"Correction maps to itself: {typo}")
            if typo in entries:
                raise ValueError(f"Duplicate or conflicting typo: {typo}")
            entries[typo] = correction
    return entries


def load_protected_words(path: Path) -> dict[str, dict[str, str]]:
    """Load explicit lowercase exclusions with reviewable reasons and sources."""
    words = json.loads(path.read_text(), object_pairs_hook=unique_object)
    if not isinstance(words, dict):
        raise ValueError("Protected words must be a JSON object")
    for word, evidence in words.items():
        if not re.fullmatch("[a-z]+", word):
            raise ValueError("Protected words must be lowercase ASCII words")
        if not isinstance(evidence, dict) or set(evidence) != {"reason", "source"}:
            raise ValueError(f"Protected word requires reason and source: {word}")
        if any(
            not isinstance(value, str) or not value.strip()
            for value in evidence.values()
        ):
            raise ValueError(f"Protected word evidence must be nonempty strings: {word}")
        source = evidence["source"]
        url = urlsplit(source)
        if (
            url.scheme not in {"http", "https"}
            or not url.hostname
            or any(char.isspace() for char in source)
        ):
            raise ValueError(f"Protected word source must be an HTTP(S) URL: {word}")
    return words
