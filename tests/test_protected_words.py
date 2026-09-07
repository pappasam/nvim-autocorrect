"""Validate supplemental evidence and audit enforcement using small local corpora."""

import contextlib
import importlib.metadata
import io
import json
import runpy
import sys
import tempfile
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from dictionary_source import load_protected_words

evidence = {"reason": "Documented intentional spelling.", "source": "https://example.org/term"}

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    path = root / "protected.json"
    for words in ({}, {"buidl": evidence}):
        path.write_text(json.dumps(words))
        assert load_protected_words(path) == words
    invalid = [
        "[]", "null", '"buidl"', "{",
        json.dumps({"BUIDL": evidence}),
        json.dumps({"bu-idl": evidence}),
        json.dumps({"buídl": evidence}),
        json.dumps({"": evidence}),
        json.dumps({"buidl": None}),
        json.dumps({"buidl": "slang"}),
        json.dumps({"buidl": {"reason": "slang"}}),
        json.dumps({"buidl": {**evidence, "extra": "ignored?"}}),
        json.dumps({"buidl": {**evidence, "reason": " "}}),
        json.dumps({"buidl": {**evidence, "reason": 123}}),
        json.dumps({"buidl": {**evidence, "source": ""}}),
        json.dumps({"buidl": {**evidence, "source": "file:///tmp/source"}}),
        json.dumps({"buidl": {**evidence, "source": "https:///missing-host"}}),
        json.dumps({"buidl": {**evidence, "source": "https://@"}}),
        json.dumps({"buidl": {**evidence, "source": "https://example.org/a b"}}),
        '{"buidl":' + json.dumps(evidence) + ',"bu\\u0069dl":' + json.dumps(evidence) + '}',
        '{"buidl":{"reason":"first","reason":"second","source":"https://example.org"}}',
    ]
    for text in invalid:
        path.write_text(text)
        try:
            load_protected_words(path)
        except ValueError:
            pass
        else:
            raise AssertionError("Accepted invalid protected words: " + text)
    path.unlink()
    try:
        load_protected_words(path)
    except FileNotFoundError:
        pass
    else:
        raise AssertionError("Silently accepted a missing protected-word list")

    # Supply tiny reference corpora to the real audit entrypoint, keeping normal
    # make check independent of Python packages and external dictionary downloads.
    (root / "final").mkdir()
    (root / "final/english-words.10").write_text("build\nmight\nrequire\nrequires\nabout\nabote\nthe\nhe\nwith\nwhit\nwight\nfrom\nform\n")
    (root / "data").mkdir()
    (root / "data/dictionary.txt").write_text("buidl->build\nhte->the\nabotu->about\nwiht->with\nwth->with\n")
    frequencies = {
        "buidl": 1e-6, "build": 0.001, "about": 0.002, "the": 0.05,
        "he": 0.005, "hte": 1e-7, "might": 1e-4, "mgint": 1e-4,
        "require": 0.001, "requires": 1e-7,
        "with": 0.007, "whit": 1e-6, "wight": 1e-6, "wiht": 1e-7, "wth": 1e-6,
        "from": 0.004, "form": 0.0005,
    }
    modules = {
        "cmudict": SimpleNamespace(words=lambda: []),
        "codespell_lib": SimpleNamespace(__file__=str(root / "codespell_lib.py")),
        "wordfreq": SimpleNamespace(get_frequency_dict=lambda language: frequencies),
    }
    with (
        patch.dict(sys.modules, modules),
        patch.object(importlib.metadata, "version", return_value="fixture"),
    ):
        audit = runpy.run_path(str(ROOT / "scripts/audit-dictionary.py"))
        source = root / "corrections.json"
        cases = [
            # Control: codespell can permit this corpus token before protection.
            ({"build": ["buidl"]}, {}, None),
            # Supplemental protection overrides codespell, corpus and swap exceptions.
            ({"build": ["buidl"]}, {"buidl": evidence}, "protected_word_or_name"),
            # Supplemental words also compete outside the destination catalog.
            ({"might": ["mgiht"]}, {"mgint": evidence}, "competing_correction"),
            # Adding an exclusion does not authorize it as a destination.
            ({"buidl": ["buiidl"]}, {"buidl": evidence}, "unverified_destination"),
            ({"might": ["mgiht"], "requires": ["requirse"]}, {"buidl": evidence}, None),
            ({"about": ["abotu"]}, {}, None),
            ({"abote": ["abotu"]}, {}, "competing_correction"),
            ({"about": ["abotu"]}, {"abotu": evidence}, "protected_word_or_name"),
            ({"the": ["hte"]}, {}, None),
            ({"the": ["hte"]}, {"hte": evidence}, "protected_word_or_name"),
            # A short typo may pass frequency, but real dictionary names still win.
            ({"the": ["teh"]}, {"teh": evidence}, "protected_word_or_name"),
            ({"with": ["wiht", "witth"]}, {}, None),
            ({"with": ["wiht"]}, {"wiht": evidence}, "protected_word_or_name"),
            ({"with": ["wth"]}, {}, "unsafe_short_corpus_token"),
            ({"with": ["iwth"]}, {"iwth": evidence}, "protected_word_or_name"),
            ({"with": ["witx"]}, {}, "short_ambiguous_token"),
            ({"from": ["fomr"]}, {}, "competing_correction"),
            ({"require": ["requirse"]}, {}, "competing_correction"),
        ]
        for groups, protected, failure in cases:
            source.write_text(json.dumps(groups))
            path.write_text(json.dumps(protected))
            argv = [
                "audit-dictionary.py", "--scowl", str(root),
                "--source", str(source), "--protected-words", str(path),
            ]
            output = io.StringIO()
            with patch.object(sys, "argv", argv), contextlib.redirect_stdout(output):
                result = audit["main"]()
            report = json.loads(output.getvalue())
            assert report["passed"] == (failure is None), report
            assert result == int(failure is not None), report
            assert report["supplemental_protected_tokens"] == len(protected), report
            if failure:
                assert report["failure_counts"].get(failure), report

print(
    "PASS: protected-word schema, missing-file rejection, "
    f"and {len(cases)} audit integration cases"
)
