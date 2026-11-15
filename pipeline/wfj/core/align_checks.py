"""Checks on the two aligners' answers as a run on rented cards brings them back (ADR-090): the run stops
at the first batch that fails one, before it costs more. Pure.

A batch fails when the two models disagree on where words start more than the 1,000-line trial ever did,
when a line whose answer the Mac already made comes back different, when more than a few lines' times run
backwards or past their recording, or when more than a couple of lines come back with no answer. A line or
two of the third kind is a take to listen to (often one cut short), listed, not a failed batch."""

from __future__ import annotations

import statistics
from collections.abc import Mapping, Sequence

AGREE = 0.20  # seconds: the two models place a word's start this close ...
AGREE_SHARE = 0.90  # ... for at least this share of a batch's words (the trial measured 97.8%)
SAME = 0.02  # seconds: median gap to the Mac's answer for the same line and model ...
SAME_P95 = 0.09  # ... and its 95th percentile (Qwen times in steps of 80 ms: one step apart passes)
EMPTY = 2  # lines a batch may bring back with no answer
SLACK = 0.10  # seconds a time may sit past the end of its recording (the models' frames)
SUSPECT = 5  # lines a batch may bring back with times out of order or past their recording (a take cut short)

Chars = Mapping[str, float]  # ReazonSpeech: character index (as text) → seconds
Words = Sequence[Sequence[float]]  # Qwen: [first, end, start, end]
Row = tuple[str, "Chars | None", "Words | None", str]


def agreement(chars: Chars, words: Words) -> tuple[int, int]:
    """(words whose starts the two models place within AGREE, words both models timed)."""
    near = both = 0
    for first, _end, start, _stop in words:
        rz = chars.get(str(int(first)))
        if rz is None:
            continue
        both += 1
        near += abs(rz - start) <= AGREE
    return near, both


def gaps(mine: Chars | Words, theirs: Chars | Words) -> list[float]:
    """How far apart two answers for the same line put each character (ReazonSpeech) or word (Qwen); an item
    only one of them has counts as a gap of one second."""
    if isinstance(mine, Mapping) and isinstance(theirs, Mapping):
        keys = set(mine) | set(theirs)
        return [abs(mine[k] - theirs[k]) if k in mine and k in theirs else 1.0 for k in keys]
    a = {(int(w[0]), int(w[1])): w[2] for w in mine}
    b = {(int(w[0]), int(w[1])): w[2] for w in theirs}
    return [abs(a[k] - b[k]) if k in a and k in b else 1.0 for k in set(a) | set(b)]


def in_order(chars: Chars, words: Words, seconds: float) -> bool:
    """Every time inside the recording, ReazonSpeech's characters and Qwen's word starts never going back."""
    rz = [chars[k] for k in sorted(chars, key=int)]
    qw = [w[2] for w in words]
    times = rz + qw + [w[3] for w in words]
    return (all(0 <= t <= seconds + SLACK for t in times)
            and all(a <= b for a, b in zip(rz, rz[1:], strict=False))
            and all(a <= b for a, b in zip(qw, qw[1:], strict=False)))


def suspects(rows: Sequence[Row], seconds: Mapping[str, float]) -> list[str]:
    """The lines whose times run backwards or past their recording: a take to listen to (often cut short),
    not a sign the cards are wrong. Their answers are kept."""
    return [s for s, c, w, _ in rows if c and w and not in_order(c, w, seconds[s])]


def check(rows: Sequence[Row], seconds: Mapping[str, float], mac_rz: Mapping[str, Chars],
          mac_qw: Mapping[str, Words]) -> str:
    """Why a batch fails, or "" when it passes. `seconds`: each line's recording length; `mac_rz`,
    `mac_qw`: answers the Mac made for some of the lines. A few suspect lines (suspects) pass; more than
    SUSPECT fail."""
    empty = [s for s, c, w, _ in rows if not c or not w]
    if len(empty) > EMPTY:
        return f"{len(empty)} lines with no answer, e.g. {empty[:3]}"
    odd = suspects(rows, seconds)
    if len(odd) > SUSPECT:
        return f"{len(odd)} lines with times out of order or past their recording, e.g. {odd[:3]}"
    near = both = 0
    same: dict[str, list[float]] = {"ReazonSpeech": [], "Qwen": []}
    for stem, chars, words, _ in rows:
        if not chars or not words:
            continue
        n, b = agreement(chars, words)
        near, both = near + n, both + b
        if stem in mac_rz:
            same["ReazonSpeech"] += gaps(chars, mac_rz[stem])
        if stem in mac_qw:
            same["Qwen"] += gaps(words, mac_qw[stem])
    if both and near / both < AGREE_SHARE:
        return f"the models agree on {near / both:.1%} of word starts (at least {AGREE_SHARE:.0%} expected)"
    for model, g in same.items():
        if not g:
            continue
        mid, p95 = statistics.median(g), sorted(g)[int(0.95 * (len(g) - 1))]
        if mid > SAME or p95 > SAME_P95:
            return (f"{model} differs from the Mac's answers: median {mid * 1000:.0f} ms, "
                    f"95th percentile {p95 * 1000:.0f} ms")
    return ""
