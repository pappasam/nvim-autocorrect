"""Exercise the audit loader with the same fixtures as the Neovim build loader."""

import hashlib
import json
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from dictionary_source import load_protected_words, load_source
from dictionary_policy import MIN_CORRECTION_FREQUENCY, MIN_FREQUENCY_RATIO

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
assert len(entries) == audit["entries"]
assert hashlib.sha256(canonical).hexdigest() == audit["mapping_sha256"], "Audit snapshot is stale"
protected = load_protected_words(ROOT / "data/protected-words.json")
protected_canonical = json.dumps(protected, sort_keys=True, separators=(",", ":")).encode()
assert len(protected) == audit["supplemental_protected_tokens"]
assert (
    hashlib.sha256(protected_canonical).hexdigest()
    == audit["supplemental_protected_sha256"]
), "Protected-word audit snapshot is stale"
assert not entries.keys() & protected.keys(), "Supplemental protected word is corrected"
print(f"PASS: {len(cases)} Python source validation cases and both audit source hashes")
