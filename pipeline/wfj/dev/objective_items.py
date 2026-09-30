"""Item names a quest asks for, found in its English objectives: a batch row lists them so the
drafter can tell a lower-case item name (kept in English letters) from an everyday word (translated).
"""

from __future__ import annotations

import re
from typing import Any

_WORD = re.compile(r"[A-Za-z0-9][A-Za-z0-9'’\-]*")
MAX_ITEM_WORDS = 8


def objective_items(objectives: str, item_names: set[str]) -> list[str]:
    """Item names in a quest's English objectives, longest match first, in text order. A plural last word
    (`Gnoll Paws`, `Boxes`) is matched in the singular and reported as the item's name. A match is refused
    when a capitalised word is joined to it by a space (`Dire Maul` is not the item `Maul`), except the word
    that starts a sentence (`Bring Holy Spring Water`)."""
    words = list(_WORD.finditer(objectives))

    def capital_neighbour(j: int, before: bool) -> bool:
        if not 0 <= j < len(words):
            return False
        left, right = (words[j], words[j + 1]) if before else (words[j - 1], words[j])
        gap = objectives[left.end() : right.start()]
        if gap != " " or not words[j].group(0)[:1].isupper():
            return False
        return not (before and (j == 0 or objectives[: words[j].start()].rstrip()[-1:] in ".!?:;"))

    found: list[str] = []
    i = 0
    while i < len(words):
        for n in range(min(MAX_ITEM_WORDS, len(words) - i), 0, -1):
            span = [w.group(0) for w in words[i : i + n]]
            last = span[-1].removesuffix("'s").removesuffix("’s")
            heads = " ".join(span[:-1] + [""])
            singulars = (last, last.removesuffix("s"), last.removesuffix("es"))
            name = next((heads + w for w in singulars if heads + w in item_names), None)
            if name and not capital_neighbour(i - 1, True) and not capital_neighbour(i + n, False):
                if name not in found:
                    found.append(name)
                i += n
                break
        else:
            i += 1
    return found


def quest_items(
    english_quest: list[dict[str, Any]], english_item: list[dict[str, Any]]
) -> dict[int, list[str]]:
    """Quest id → the item names in its English `objectives` (only quests that name at least one)."""
    names = {ln["en"] for ln in english_item if ln["field"] == "name"}
    out: dict[int, list[str]] = {}
    for ln in english_quest:
        if ln["field"] == "objectives" and (found := objective_items(ln["en"], names)):
            out.setdefault(ln["id"], [])
            out[ln["id"]] += [f for f in found if f not in out[ln["id"]]]
    return out
