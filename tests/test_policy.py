"""Exercise adjacent-swap preference, ambiguity, and its precise limits."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from dictionary_policy import (
    documented_short_correction,
    frequency_short_correction,
    preferred_frequency,
    preferred_transposition,
    short_corpus_exception,
    short_word_typos,
    valid_typo_length,
)

# Candidate sets model all single-edit dictionary words, not just destinations.
cases = [
    ("requirse", {"require", "requires"}, "requires"),
    ("requirse", {"requires"}, "requires"),
    ("requirse", {"require"}, None),
    ("requirse", set(), None),
    # Several deletions are fine; multiple swaps or another substitution are not.
    ("acbd", {"abcd", "acd", "abd"}, "abcd"),
    ("acbd", {"abcd", "cabd", "acd"}, None),
    ("acbd", {"abcd", "acbe", "acd"}, None),
    # An insertion candidate blocks preference; this is not a general longest rule.
    ("acbd", {"abcd", "acbed", "acd"}, None),
    ("acbd", {"acbed", "acd"}, None),
    # A substitution, nonadjacent swap, two swaps, or identity cannot win.
    ("acbd", {"acbe", "acd"}, None),
    ("abdc", {"acdb", "abc"}, None),
    ("badc", {"abcd", "bad"}, None),
    ("abcd", {"abcd", "abc"}, None),
    # Swapping distinct adjacent letters works at either boundary and with repeats.
    ("bacd", {"abcd", "bcd"}, "abcd"),
    ("abdc", {"abcd", "abc"}, "abcd"),
    ("aba", {"aab", "ab"}, "aab"),
]
for typo, candidates, expected in cases:
    assert preferred_transposition(typo, candidates) == expected, (typo, candidates)
print(f"PASS: {len(cases)} transposition preference cases")

# The length gate does not grant exceptions for arbitrary five-letter edits.
length_cases = [
    ("mgiht", "might", {"might"}, None, True),
    ("mgiht", "might", {"might"}, "other", True),
    ("mgiht", "might", {"might", "mgit"}, None, True),
    ("mgiht", "might", {"might", "mgith"}, None, False),
    ("mgiht", "might", {"might", "mgint"}, None, False),
    ("mgiht", "might", {"might", "mgihta"}, None, False),
    ("mgiht", "mgit", {"might", "mgit"}, None, False),
    ("mgiht", "might", set(), None, False),
    ("mighx", "might", {"might"}, None, False),
    ("migtx", "might", {"might"}, None, False),
    ("mihgt", "might", {"might"}, None, True),
    ("mtghi", "might", {"might"}, None, False),
    ("might", "might", {"might"}, None, False),
    # Existing documented five-letter corrections remain eligible for screening.
    ("woudl", "would", {"would"}, "would", True),
    ("mighx", "might", {"might"}, "might", True),
    # Short words cannot qualify without frequency evidence, even documented swaps.
    ("abdc", "abcd", {"abcd"}, None, False),
    ("abdc", "abcd", {"abcd"}, "abcd", False),
    ("teh", "the", {"the"}, "the", False),
    ("", "word", set(), None, False),
    # Six-letter typos retain the existing gate; other checks decide eligibility.
    ("mighht", "might", {"might"}, None, True),
]
for typo, correction, candidates, documented, expected in length_cases:
    assert valid_typo_length(typo, correction, candidates, documented) == expected, (
        typo, correction, candidates, documented
    )
print(f"PASS: {len(length_cases)} typo length policy cases")

frequency_cases = [
    ({"about", "abote", "abott"}, {"about": 0.002, "abott": 2e-8}, "about"),
    ({"common", "rival"}, {"common": 0.01, "rival": 0.0001}, "common"),
    ({"common", "rival"}, {"common": 0.009, "rival": 0.0001}, None),
    ({"common", "rival"}, {"common": 0.01, "rival": 0.01}, None),
    ({"rare", "rarer"}, {"rare": 1e-7, "rarer": 0}, None),
    ({"known", "unknown"}, {"known": 1e-5}, "known"),
    ({"known", "unknown"}, {}, None),
    (set(), {"outside": 1}, None),
    # A common word outside the catalog must still prevent guessing.
    ({"about", "outside"}, {"about": 0.002, "outside": 0.001}, None),
]
for candidates, frequencies, expected in frequency_cases:
    assert preferred_frequency(candidates, frequencies) == expected, candidates
assert valid_typo_length("abotu", "about", {"about", "abote"}, frequencies={"about": 0.002})
assert not valid_typo_length("abotu", "abote", {"about", "abote"}, frequencies={"about": 0.002})
assert valid_typo_length("hte", "the", {"the", "he"}, "the")
assert not valid_typo_length("hte", "the", {"the", "he"})
assert not valid_typo_length("teh", "the", {"the"}, "the")
assert documented_short_correction("hte", "the", "the")
assert not documented_short_correction("hte", "he", "he")
print(f"PASS: {len(frequency_cases)} frequency cases and exact short-correction limits")

short_cases = [
    ("wiht", "with", {"with", "whit", "wight"}, {"with": 0.007, "whit": 1e-6, "wight": 1e-6}, True),
    ("fomr", "from", {"form", "from"}, {"from": 0.004, "form": 0.0005}, False),
    # Every short destination needs the higher frequency floor, even if unique.
    ("wiht", "with", {"with"}, {"with": 0.0001}, True),
    ("wiht", "with", {"with"}, {"with": 0.000099}, False),
    ("wiht", "with", {"with", "whit"}, {"with": 0.001, "whit": 0.00001}, True),
    ("wiht", "with", {"with", "whit"}, {"with": 0.00099, "whit": 0.00001}, False),
    # A swap cannot override a common shorter competitor for short words.
    ("hte", "the", {"the", "he"}, {"the": 0.05, "he": 0.005}, False),
    ("tthe", "the", {"the"}, {"the": 0.05}, True),
    ("witth", "with", {"with"}, {"with": 0.007}, True),
    ("wiht", "with", {"whit"}, {"with": 0.007}, False),
    ("wiht", "with", {"with"}, {}, False),
    # Keep the two-letter exclusion and the limits on physical typing errors.
    ("th", "the", {"the"}, {"the": 0.05}, False),
    ("witx", "with", {"with"}, {"with": 0.007}, False),
    ("whitt", "with", {"with"}, {"with": 0.007}, False),
]
for typo, correction, candidates, frequencies, expected in short_cases:
    assert frequency_short_correction(typo, correction, candidates, frequencies) == expected
    assert valid_typo_length(typo, correction, candidates, frequencies=frequencies) == expected
assert valid_typo_length("ofrom", "from", {"from"}, "from")  # Existing documented path.
assert short_corpus_exception("wiht", "with", "with")
assert short_corpus_exception("tthe", "the", "the")
assert not short_corpus_exception("wiht", "with", None)
assert not short_corpus_exception("wth", "with", "with")
assert not short_corpus_exception("mayu", "may", "may")
assert {"wiht", "wtih", "witth", "wuth", "wijth"} <= short_word_typos("with")
assert not {"with", "With", "witx", "whitt"} & short_word_typos("with")
assert not short_word_typos("longer")
assert not short_word_typos("The")
print(f"PASS: {len(short_cases)} short-word frequency cases, edit patterns and corpus limits")
