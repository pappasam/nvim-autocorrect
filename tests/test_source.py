"""Exercise the audit loader with the same fixtures as the Neovim build loader."""

import hashlib
import json
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from dictionary_source import load_protected_words, load_reviewed_corrections, load_source
from dictionary_policy import MIN_CORRECTION_FREQUENCY, MIN_FREQUENCY_RATIO, MIN_SHORT_CORRECTION_FREQUENCY, MIN_FIVE_LETTER_FREQUENCY, MIN_JOINED_COMPONENT_FREQUENCY

cases = json.loads((ROOT / "tests/source_cases.json").read_text())
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / "corrections.json"
    for case in cases:
        path.write_text(case["source"])
        try:
            entries = load_source(path)
        except ValueError:
            assert "expected" not in case, case["name"]
        else:
            assert "expected" in case, case["name"]
            assert entries == case["expected"], case["name"]

entries = load_source(ROOT / "data/corrections.json")
canonical = json.dumps(entries, sort_keys=True, separators=(",", ":")).encode()
audit = json.loads((ROOT / "data/audit.json").read_text())
assert audit["passed"] and not audit["failure_counts"], "Dictionary audit failed"
assert audit["frequency_preference"] == {
    "minimum_frequency": MIN_CORRECTION_FREQUENCY,
    "minimum_ratio": MIN_FREQUENCY_RATIO,
}, "Frequency policy audit snapshot is stale"
assert audit["transposition_preference"] == {
    "rare_alternative_minimum_length": 5,
    "minimum_frequency": MIN_CORRECTION_FREQUENCY,
    "minimum_ratio": MIN_FREQUENCY_RATIO,
    "frequency_competitors": "same-length non-swap alternatives",
    "longer_alternatives": "block",
}, "Transposition policy audit snapshot is stale"
assert audit["short_word_preference"] == {
    "minimum_frequency": MIN_SHORT_CORRECTION_FREQUENCY,
    "minimum_ratio": MIN_FREQUENCY_RATIO,
    "destination_lengths": [3, 4],
    "typo_lengths": [3, 4, 5],
    "three_four_letter_corpus_exceptions": "documented adjacent swap or repeated letter",
}, "Short-word policy audit snapshot is stale"
assert len(entries) == audit["entries"]
assert audit["joined_word_policy"] == {
    "minimum_input_length": 6,
    "minimum_component_frequency": MIN_JOINED_COMPONENT_FREQUENCY,
    "destination_words": 2,
    "documentation_required": True,
    "single_word_alternatives": "block",
    "alternative_splits": "block",
}, "Joined-word policy audit snapshot is stale"
assert audit["joined_word_corrections"] == sum(" " in word for word in entries.values())
assert audit["entries"] == sum(audit[key] for key in (
    "single_edit_corrections", "documented_multi_edit_corrections", "joined_word_corrections",
))
assert audit["five_letter_preference"] == {
    "minimum_frequency": MIN_FIVE_LETTER_FREQUENCY,
    "minimum_ratio": MIN_FREQUENCY_RATIO,
    "destination_lengths": [5],
    "typo_lengths": [4, 5],
}, "Five-letter policy audit snapshot is stale"
assert hashlib.sha256(canonical).hexdigest() == audit["mapping_sha256"], "Audit snapshot is stale"
protected = load_protected_words(ROOT / "data/protected-words.json")
protected_canonical = json.dumps(protected, sort_keys=True, separators=(",", ":")).encode()
assert len(protected) == audit["supplemental_protected_tokens"]
assert (
    hashlib.sha256(protected_canonical).hexdigest()
    == audit["supplemental_protected_sha256"]
), "Protected-word audit snapshot is stale"
assert not entries.keys() & protected.keys(), "Supplemental protected word is corrected"
reviewed = load_reviewed_corrections(ROOT / "data/reviewed-corrections.json")
assert audit["reviewed_records"] == len(reviewed)
assert hashlib.sha256(
    json.dumps(reviewed, sort_keys=True, separators=(",", ":")).encode()
).hexdigest() == audit["reviewed_sha256"], "Reviewed-correction audit snapshot is stale"
print(f"PASS: {len(cases)} Python source validation cases and all audit source hashes")
