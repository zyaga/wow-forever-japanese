"""Conflict ruling for lines that carry duplicate variants (imported as `conflicts`).

A variant is the line's own `ja` (index 0) or one of `conflicts[i]` (index i+1). A human `ruling`
(`{"ruling": "accept", ...}`) on exactly one variant wins outright. Otherwise the rules decide: exactly
one variant passing `evaluate` wins; zero or several → no winner (the line is `rejected/duplicate_conflict`).
"""

from __future__ import annotations

import json
from collections.abc import Callable
from dataclasses import dataclass
from typing import Any


@dataclass
class Candidate:
    index: int
    ja: str
    provenance: dict[str, Any]
    extra: dict[str, Any] | None
    ruling: dict[str, Any] | None


def variants(line: dict[str, Any]) -> list[Candidate]:
    out = [Candidate(0, line["ja"], line["provenance"], line.get("extra"), line.get("ruling"))]
    for i, c in enumerate(line.get("conflicts") or [], 1):
        out.append(Candidate(i, c["ja"], c["provenance"], c.get("extra"), c.get("ruling")))
    return out


# Source priority for the tie-break (ADR-011): when several variants pass the rules, the one from the
# newest source wins: the kept named-WoWJapanizer rows (2012–2022) over CraftJapanizer_Quest-2012 over
# QuestJapanizer-2009 over the wiki. Matched on the `provenance.source` prefix (`cqjt@…`).
SOURCE_PRIORITY: tuple[str, ...] = ("cqjt", "cjq", "qjp", "qjwiki")
# Attribution to a community rather than a person (an uncredited wiki row); ranks below any named translator
# from the same source.
ANONYMOUS_TRANSLATORS: frozenset[str] = frozenset({"questjapanizer-wiki", "unknown"})


def source_rank(provenance: dict[str, Any]) -> tuple[int, int]:
    """Lower is better: (source priority, 1 if the translator is a community label else 0)."""
    src = str(provenance.get("source", "")).split("@", 1)[0]
    rank = SOURCE_PRIORITY.index(src) if src in SOURCE_PRIORITY else len(SOURCE_PRIORITY)
    anonymous = 1 if str(provenance.get("translator", "")) in ANONYMOUS_TRANSLATORS else 0
    return (rank, anonymous)


def _rule(c: Candidate) -> str | None:
    return c.ruling.get("ruling") if isinstance(c.ruling, dict) else None


def resolve(
    cands: list[Candidate],
    evaluate: Callable[[Candidate], bool],
    *,
    priority: bool = False,
    rank: Callable[[Candidate], tuple] | None = None,
) -> int | None:
    """Index of the winning candidate, or None when the rules cannot decide. With `priority`, several
    passing variants are settled by `rank` (default `source_rank`; lower wins) when exactly one has the best
    rank (`tiebreak`). `check` ranks completeness before source (ADR-011)."""
    if len(cands) == 1:
        return cands[0].index
    rule = _rule
    key = rank or (lambda c: source_rank(c.provenance))
    accepted = [c.index for c in cands if rule(c) == "accept"]
    if len(accepted) == 1:
        return accepted[0]
    if len(accepted) > 1:
        return None
    passing = [c for c in cands if rule(c) != "reject" and evaluate(c)]
    if len(passing) == 1:
        return passing[0].index
    if len(passing) > 1 and priority:
        best = min(key(c) for c in passing)
        top = [c for c in passing if key(c) == best]
        if len(top) == 1:
            return top[0].index
    return None


def tiebroken(cands: list[Candidate], evaluate: Callable[[Candidate], bool], winner: int) -> bool:
    """True when `winner` was chosen by rank rather than as the sole passing variant or by a ruling."""
    if any(_rule(c) == "accept" for c in cands):
        return False
    passing = [c for c in cands if _rule(c) != "reject" and evaluate(c)]
    return len(passing) > 1 and any(c.index == winner for c in passing)


# The stored order of `conflicts`: hand-written before machine, then source, translator, text. Total
# and independent of history, so a line reaches the same bytes whether a fresh rebuild or a promotion after a
# draft import produced it. Winner selection never reads this order (it is by rule, ruling and rank).
CLASS_ORDER: tuple[str, ...] = ("human", "correction", "machine")


def conflict_order(c: dict[str, Any]) -> tuple:
    prov = c["provenance"]
    cls = str(prov.get("class", ""))
    rank = CLASS_ORDER.index(cls) if cls in CLASS_ORDER else len(CLASS_ORDER)
    # the whole variant last: two variants alike in all of the above but a ruling or an `extra` still sort one
    # way
    whole = json.dumps(c, sort_keys=True, ensure_ascii=False)
    return (rank, cls, str(prov.get("source", "")), str(prov.get("translator", "")), c["ja"], whole)


def canonical_conflicts(conflicts: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """`conflicts` in the stored order (a new list; the variants themselves are not copied)."""
    return sorted(conflicts, key=conflict_order)


def promote(line: dict[str, Any], winner: int) -> dict[str, Any]:
    """Return a copy of the line with `winner` as the line's own variant; the displaced one joins
    `conflicts`. Nothing is dropped: a human translation is never lost."""
    if winner == 0:
        return line
    cands = variants(line)
    new_line = dict(line)
    w = cands[winner]
    displaced = {"ja": line["ja"], "provenance": line["provenance"]}
    if line.get("extra"):
        displaced["extra"] = line["extra"]
    if line.get("ruling"):
        displaced["ruling"] = line["ruling"]
    others = [c for i, c in enumerate(line.get("conflicts") or [], 1) if i != winner]
    new_line["ja"] = w.ja
    new_line["provenance"] = w.provenance
    if w.extra:
        new_line["extra"] = w.extra
    else:
        new_line.pop("extra", None)
    if w.ruling:
        new_line["ruling"] = w.ruling
    else:
        new_line.pop("ruling", None)
    new_line["conflicts"] = [displaced] + others
    # keep the canonical key order (extra/ruling after conflicts) so a promotion never reorders keys
    order = [
        "id",
        "field",
        "ja",
        "status",
        "checks",
        "provenance",
        "english",
        "reasons",
        "conflicts",
        "extra",
        "ruling",
    ]
    return {k: new_line[k] for k in order if k in new_line}
