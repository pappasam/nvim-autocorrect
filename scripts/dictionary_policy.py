"""Ambiguity policy for independently enumerated single-edit dictionary words."""

MIN_CORRECTION_FREQUENCY = 1e-5  # Ten occurrences per million words.
MIN_FREQUENCY_RATIO = 100
MIN_SHORT_CORRECTION_FREQUENCY = 1e-4  # One hundred occurrences per million words.
# Reviewed prose preference; codespell must confirm this exact mapping as well.
DOCUMENTED_SHORT_CORRECTIONS = {"hte": "the"}

QWERTY_NEIGHBORS = dict(zip(
    "qwertyuiopasdfghjklzxcvbnm",
    ("wa", "qeas", "wrsd", "etdf", "ryfg", "tugh", "yihj", "uojk", "ipkl", "ol",
     "qwsz", "awedxz", "serfcx", "drtgvc", "ftyhbv", "gyujnb", "huikmn", "jiolm", "kop",
     "asx", "zsdc", "xdfv", "cfgb", "vghn", "bhjm", "njk"),
))


def short_word_typos(word: str) -> set[str]:
    """Plausible single keystroke errors; never produce one/two-letter inputs."""
    if len(word) not in (3, 4) or not word.isascii() or not word.isalpha() or not word.islower():
        return set()
    typos = set()
    for index, char in enumerate(word):
        before, after = word[:index], word[index + 1:]
        typos.add(before + after)
        typos.add(before + char + char + after)
        if index + 1 < len(word):
            typos.add(before + word[index + 1] + char + word[index + 2:])
        for neighbor in QWERTY_NEIGHBORS[char]:
            typos.add(before + neighbor + after)
            typos.add(before + neighbor + char + after)
            typos.add(before + char + neighbor + after)
    return {typo for typo in typos if len(typo) >= 3 and typo != word}


def frequency_short_correction(
    typo: str, correction: str, candidates: set[str], frequencies: dict[str, float]
) -> bool:
    """Short destinations always require frequency dominance, even for swaps.

    Protected input and corpus membership must still be checked by the caller.
    """
    return (
        len(correction) in (3, 4)
        and frequencies.get(correction, 0) >= MIN_SHORT_CORRECTION_FREQUENCY
        and typo in short_word_typos(correction)
        and correction in candidates
        and preferred_frequency(candidates, frequencies) == correction
    )


def short_corpus_exception(typo: str, correction: str, documented: str | None) -> bool:
    """Corpus tokens need a documented swap/repeat, avoiding shorthand like wth."""
    return documented == correction and (
        adjacent_swap(typo, correction)
        or any(typo == correction[:i] + char + correction[i:] for i, char in enumerate(correction))
    )


def adjacent_swap(typo: str, correction: str) -> bool:
    if len(typo) != len(correction):
        return False
    differences = [i for i, char in enumerate(typo) if char != correction[i]]
    if len(differences) != 2:
        return False
    left, right = differences
    return (
        right == left + 1
        and typo[left] == correction[right]
        and typo[right] == correction[left]
    )


def preferred_transposition(
    typo: str, candidates: set[str], frequencies: dict[str, float] | None = None
) -> str | None:
    """Prefer a unique swap over deletions and sufficiently rare substitutions.

    Candidates must include all known single-edit words, including names and words
    outside the destination catalog. Longer candidates always block this rule.
    At five or more letters, same-length non-swap competitors may qualify for
    frequency screening. Shorter inputs retain their stricter existing rules.
    Protected-token, corpus, length, and destination checks still apply.
    """
    if any(len(word) not in (len(typo) - 1, len(typo)) for word in candidates):
        return None
    swaps = {word for word in candidates if adjacent_swap(typo, word)}
    if len(swaps) != 1:
        return None
    correction = next(iter(swaps))
    same_length = {word for word in candidates if len(word) == len(typo)}
    if same_length == {correction}:
        return correction
    if len(typo) >= 5 and preferred_frequency(same_length, frequencies or {}) == correction:
        return correction
    return None


def preferred_frequency(candidates: set[str], frequencies: dict[str, float]) -> str | None:
    """Resolve ambiguity only with a common, overwhelmingly more frequent word.

    Compare every known single-edit alternative, including names, supplemental
    words, and destinations outside the catalog. Missing corpus entries score zero.
    Corpus frequencies are a ranking signal, not probabilities of user intent.
    """
    if not candidates:
        return None
    ranked = sorted(candidates, key=lambda word: (-frequencies.get(word, 0), word))
    winner = ranked[0]
    first = frequencies.get(winner, 0)
    second = frequencies.get(ranked[1], 0) if len(ranked) > 1 else 0
    if first >= MIN_CORRECTION_FREQUENCY and first >= MIN_FREQUENCY_RATIO * second:
        return winner
    return None


def documented_short_correction(typo: str, correction: str, documented: str | None) -> bool:
    return DOCUMENTED_SHORT_CORRECTIONS.get(typo) == correction == documented


def valid_typo_length(
    typo: str,
    correction: str,
    candidates: set[str],
    documented_correction: str | None = None,
    frequencies: dict[str, float] | None = None,
) -> bool:
    """Allow common short destinations, selected five-letter swaps and exceptions.

    This is only the length gate. Protected tokens, corpus membership, verified
    destinations, and competing corrections must still be checked separately.
    """
    if len(typo) >= 6:
        return True
    if documented_short_correction(typo, correction, documented_correction):
        return True
    # Preserve the existing documented five-letter path, including non-keyboard
    # misspellings and less frequent destinations. New generated entries use the
    # stricter frequency rule below.
    if len(typo) == 5 and documented_correction == correction:
        return True
    if len(correction) in (3, 4):
        return frequency_short_correction(typo, correction, candidates, frequencies or {})
    return len(typo) == 5 and (
        documented_correction == correction
        or preferred_transposition(typo, candidates, frequencies) == correction
        or (
            adjacent_swap(typo, correction)
            and preferred_transposition(typo, candidates, frequencies) is None
            and preferred_frequency(candidates, frequencies or {}) == correction
        )
    )
