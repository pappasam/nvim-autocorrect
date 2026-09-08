"""Load the grouped correction catalog without silently overwriting entries."""

import json
import re
from pathlib import Path
from urllib.parse import urlsplit

from dictionary_policy import DOCUMENTED_SHORT_CORRECTIONS

CORRECTION_PATTERN = r"[a-z]+(?: [a-z]+)?"


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
        if not re.fullmatch(CORRECTION_PATTERN, correction):
            raise ValueError("Corrections must be one or two lowercase ASCII words")
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


def load_reviewed_corrections(path: Path) -> dict[str, dict[str, str]]:
    """Exact externally documented pairs; evidence is reviewed during maintenance."""
    records = json.loads(path.read_text(), object_pairs_hook=unique_object)
    if not isinstance(records, dict):
        raise ValueError("Reviewed corrections must be a JSON object")
    for typo, record in records.items():
        if not re.fullmatch("[a-z]+", typo):
            raise ValueError("Reviewed typos must be lowercase ASCII words")
        if not isinstance(record, dict) or set(record) != {"correction", "reason", "source"}:
            raise ValueError(f"Reviewed correction requires correction, reason and source: {typo}")
        if any(not isinstance(v, str) or not v.strip() for v in record.values()):
            raise ValueError(f"Reviewed evidence must be nonempty strings: {typo}")
        if not re.fullmatch(CORRECTION_PATTERN, record["correction"]) or record["correction"] == typo:
            raise ValueError(f"Invalid reviewed destination: {typo}")
        url = urlsplit(record["source"])
        if url.scheme not in {"http", "https"} or not url.hostname or any(
            char.isspace() for char in record["source"]
        ):
            raise ValueError(f"Reviewed source must be an HTTP(S) URL: {typo}")
    return records


def load_documented_corrections(
    codespell_path: Path, reviewed: dict[str, dict[str, str]]
) -> dict[str, str]:
    """Combine unambiguous codespell pairs and reviewed evidence; reject conflicts."""
    documented = {}
    for line in codespell_path.read_text().splitlines():
        typo, separator, correction = line.partition("->")
        if not separator:
            continue
        if typo in reviewed and correction != reviewed[typo]["correction"]:
            raise ValueError(f"Reviewed correction conflicts with codespell: {typo}")
        if re.fullmatch(CORRECTION_PATTERN, correction):
            documented[typo] = correction
    for typo, record in reviewed.items():
        # External evidence cannot independently activate an exact short override.
        if typo in DOCUMENTED_SHORT_CORRECTIONS and documented.get(typo) != record["correction"]:
            raise ValueError(f"Exact short correction requires codespell confirmation: {typo}")
        documented[typo] = record["correction"]
    return documented
