"""Reader for forever-vo's capture files (github.com/quinn-dougherty/forever-vo, MIT): quest progress and
turn-in text that players of the Forever client recorded with that project's addon and sent in. The server
sends this text only at the NPC, so no client file holds it (ADR-055).

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


def read_captures(folder: Path, titles: Mapping[int, str]) -> Result:
    """Every (quest id, field) the captures under `folder/captures` agree on. → Result (sorted by key)"""
    files = sorted((folder / "captures").glob("*.json"))
    if not files:
        raise ValueError(f"forever-vo: no captures/*.json under {folder}")
    by: dict[tuple[int, str], dict[str, Candidate]] = {}
    skipped = {"other_language": 0, "no_title": 0}
    for path in files:
        doc = json.loads(path.read_text(encoding="utf-8"))
        origin = str(doc.get("origin") or path.stem)
        for entry in (doc.get("quests") or {}).values():
            field_ = FIELDS.get(entry.get("event"))
            text = entry.get("text")
            if field_ is None or not isinstance(text, str) or not text.strip():
                continue
            qid = int(entry["questID"])
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
