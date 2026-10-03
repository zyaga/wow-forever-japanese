"""Reader for forever-vo's capture files (github.com/quinn-dougherty/forever-vo, MIT): quest progress and
turn-in text and NPC greetings that players of the Forever client recorded with that project's addon and sent
in. The server sends this text only at the NPC, so no client file holds it (ADR-055).

Each `captures/*.json` is one player's submission: `origin` (the issue it came from) and `quests`, a map of
entries `{questID, event, title, text, build, …}`. Only `progress` and `complete` events are read.

A text is taken only when it can be trusted as Forever's English:
- the entry's quest title equals the English title we hold for that quest id (`titles`). The files carry no
  client language, and a German client's entry has a German title, so this keeps only English clients;
- at least `MIN_ORIGINS` separate submissions sent the same text (compared normalized), so one tampered or
  garbled submission never decides a line.
When submissions disagree (another build's wording, one player's race or gender written out), the text sent by
the most submissions wins; a tie goes to the text that keeps a player token, then to the newest build."""

from __future__ import annotations

import json
from collections.abc import Mapping
from dataclasses import dataclass, field
from pathlib import Path

from wfj.core.normalize import normalize_v1

FIELDS = {"progress": "progress", "complete": "completion"}
MIN_ORIGINS = 2
TOKENS = ("{name}", "{class}", "{race}")
ENGLISH_SHARE = 0.9  # of a submission's known quest titles that must be our English ones


@dataclass
class Candidate:
    text: str  # as the newest submission sent it
    build: int
    origins: set[str] = field(default_factory=set)


@dataclass
class Capture:
    id_: int
    field: str
    en: str
    origins: int  # how many submissions sent this text


@dataclass
class Result:
    captures: list[Capture]
    skipped: dict[str, int]


def _build(value: object) -> int:
    try:
        return int(str(value))
    except ValueError:
        return 0


def _qid(entry: object) -> int | None:
    """A capture entry's quest id, or None for an entry that is not a well-formed quest record."""
    if not isinstance(entry, dict):
        return None
    try:
        return int(entry["questID"])
    except (KeyError, TypeError, ValueError):
        return None


def read_captures(folder: Path, titles: Mapping[int, str]) -> Result:
    """Every (quest id, field) the captures under `folder/captures` agree on. → Result (sorted by key)"""
    files = sorted((folder / "captures").glob("*.json"))
    if not files:
        raise ValueError(f"forever-vo: no captures/*.json under {folder}")
    by: dict[tuple[int, str], dict[str, Candidate]] = {}
    skipped = {"other_language": 0, "no_title": 0, "malformed": 0}
    for path in files:
        doc = json.loads(path.read_text(encoding="utf-8"))
        origin = str(doc.get("origin") or path.stem)
        for entry in (doc.get("quests") or {}).values():
            qid = _qid(entry)
            if qid is None:
                skipped["malformed"] += 1
                continue
            field_ = FIELDS.get(entry.get("event"))
            text = entry.get("text")
            if field_ is None or not isinstance(text, str) or not text.strip():
                continue
            title = titles.get(qid)
            if title is None:
                skipped["no_title"] += 1
                continue
            if entry.get("title") != title:
                skipped["other_language"] += 1
                continue
            norm = normalize_v1(text)
            build = _build(entry.get("build"))
            cand = by.setdefault((qid, field_), {}).get(norm)
            if cand is None:
                cand = by[(qid, field_)][norm] = Candidate(text, build)
            elif build >= cand.build:
                cand.text, cand.build = text, build
            cand.origins.add(origin)
    captures = []
    disagreed = few = 0
    for (qid, field_), cands in sorted(by.items()):
        if len(cands) > 1:
            disagreed += 1
        norm, best = max(
            cands.items(),
            key=lambda kv: (len(kv[1].origins), any(t in kv[0] for t in TOKENS), kv[1].build, kv[0]),
        )
        if len(best.origins) < MIN_ORIGINS:
            few += 1
            continue
        captures.append(Capture(qid, field_, best.text, len(best.origins)))
    skipped["one_submission"] = few
    skipped["disagreed_resolved"] = disagreed
    return Result(captures, skipped)


@dataclass
class Greeting:
    en: str
    origins: int
    npcs: list[int]


def english_origins(folder: Path, titles: Mapping[int, str]) -> set[str]:
    """The submissions from an English client: at least ENGLISH_SHARE of the quest entries whose id we know
    carry the English title we hold. A submission is one player's client, so its greetings share its
    language; one with no quest entry to tell by is left out. Not every title must match: Forever renames a
    quest now and then, and a capture from before the rename holds the old title (at the pin, English clients
    match 94.7% or more, the German ones none)."""
    good: set[str] = set()
    for path in sorted((folder / "captures").glob("*.json")):
        doc = json.loads(path.read_text(encoding="utf-8"))
        origin = str(doc.get("origin") or path.stem)
        seen = [(titles.get(q), e.get("title")) for e in (doc.get("quests") or {}).values()
                if (q := _qid(e)) is not None]
        known = [(ours, theirs) for ours, theirs in seen if ours is not None]
        if known and sum(ours == theirs for ours, theirs in known) >= ENGLISH_SHARE * len(known):
            good.add(origin)
    return good


def read_greetings(folder: Path, titles: Mapping[int, str]) -> list[Greeting]:
    """The NPC greetings (`gossip` entries) at least MIN_ORIGINS English submissions sent, compared
    normalized, each with the creature ids that said it. → sorted by text"""
    english = english_origins(folder, titles)
    by: dict[str, tuple[str, set[str], set[int]]] = {}
    for path in sorted((folder / "captures").glob("*.json")):
        doc = json.loads(path.read_text(encoding="utf-8"))
        origin = str(doc.get("origin") or path.stem)
        if origin not in english:
            continue
        for entry in (doc.get("gossip") or {}).values():
            text = entry.get("text")
            if entry.get("event") != "gossip" or not isinstance(text, str) or not text.strip():
                continue
            norm = normalize_v1(text)
            if not norm:
                continue
            _, origins, npcs = by.setdefault(norm, (text, set(), set()))
            origins.add(origin)
            npc = str(entry.get("npc") or "")
            if npc.isdigit() and 0 < int(npc) < 2**31 and not entry.get("isObject"):
                npcs.add(int(npc))
    return [
        Greeting(text, len(origins), sorted(npcs))
        for _, (text, origins, npcs) in sorted(by.items())
        if len(origins) >= MIN_ORIGINS
    ]
