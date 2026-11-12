"""The Spoken voice addon's line corpus (github.com/rusty-key/spoken-wow, `pipelines/quests/corpus`): who
says each quest line it voices. Read only; nothing of Spoken is stored but the creature id."""

from __future__ import annotations

import gzip
import json
from collections import defaultdict
from pathlib import Path
from typing import Any

from wfj.io.forever_vo import SPEAKER_EVENTS as FIELD  # Spoken names the quest window's moments the same way


def load(path: Path) -> dict[str, Any]:
    """The corpus as Spoken commits it (`lines`, `npcs`, ...)."""
    with gzip.open(path, "rt", encoding="utf-8") as f:
        corpus: dict[str, Any] = json.load(f)
    return corpus


def source(commit: str) -> str:
    """The provenance source of a fact taken from the corpus at `commit`."""
    return f"spoken@{commit[:7]}"


def read_quest_speakers(path: Path) -> dict[tuple[int, str], int]:
    """{(quest id, field): creature id} for the quest lines the corpus gives to one creature. A line it
    gives to an object or an item, or to two creatures, has no entry: the other sources decide it."""
    corpus = load(path)
    seen: dict[tuple[int, str], set[int]] = defaultdict(set)
    other: set[tuple[int, str]] = set()
    for line in corpus.get("lines", ()):
        field = FIELD.get(line.get("source"))
        if field is None or not line.get("questId") or not line.get("npcId"):
            continue
        key = (int(line["questId"]), field)
        if line.get("npcType") == "creature":
            seen[key].add(int(line["npcId"]))
        else:
            other.add(key)
    return {key: next(iter(who)) for key, who in seen.items() if len(who) == 1 and key not in other}
