"""The Spoken voice addon's line corpus (github.com/rusty-key/spoken-wow, `pipelines/quests/corpus`): who
says each quest line it voices. Read only; nothing of Spoken is stored but the creature id."""

from __future__ import annotations

import gzip
import json
from collections import defaultdict
from pathlib import Path

# Spoken's name for the moment a quest line is said, and the quest field that holds the line here
FIELD = {"accept": "description", "progress": "progress", "complete": "completion"}


def read_quest_speakers(path: Path) -> dict[tuple[int, str], int]:
    """{(quest id, field): creature id} for the quest lines the corpus gives to one creature. A line it
    gives to an object or an item, or to two creatures, has no entry: the other sources decide it."""
    with gzip.open(path, "rt", encoding="utf-8") as f:
        corpus = json.load(f)
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
