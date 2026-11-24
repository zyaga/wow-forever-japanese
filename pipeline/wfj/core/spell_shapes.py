"""The spell an item's tooltip line prints, found by the line's shape (ADR-107).

An item's "Use:", "Equip:" and "Chance on hit:" lines are its spells' descriptions with the numbers filled in.
The item ships one description, joined from the spells its client tables listed when the English was taken.
A line that description does not cover (the item's English came from another client, or the client prints
more lines than the tables named) has no Japanese of its own, but the spell it prints usually has. Nothing in
the client names that spell per line, so the addon finds it by the line's SHAPE: the line with every value
masked, keyed the way a keyed branch line is (`align.variant_key`, ADR-064; the addon's `Align.variantKey` on
the live line, parity-tested by the align vectors).

The table maps a shape key to one spell id, kept only when every spell description with that shape ships the
same Japanese with the same status: then whichever of them the line printed, that Japanese is its Japanese,
and the addon's gate fills and checks it against the live line. A shape two spells word differently in
Japanese, or one with a spell that ships nothing, is left out, and its line stays English.

Only the shapes an item can print are kept: a spell whose English is one or more whole lines of some item's
description English. A key, never the English, is what ships.
"""

from __future__ import annotations

from collections.abc import Iterable
from typing import Any

from wfj.core import align
from wfj.core.english_text import model_english
from wfj.emit.lua_writer import shipped as ships


def item_windows(item_english: Iterable[str]) -> set[str]:
    """Every run of whole consecutive lines of each item description English: the texts a spell's English
    must equal to be one an item prints (an item's English joins its spells with a line break, and a spell's
    own English may hold breaks of its own)."""
    out: set[str] = set()
    for en in item_english:
        parts = en.split("\n")
        for i in range(len(parts)):
            for j in range(i + 1, len(parts) + 1):
                text = "\n".join(parts[i:j]).strip()
                if text:
                    out.add(text)
    return out


def shape_key(en: str) -> str | None:
    """The shape key of a spell description's English, or None when the client prints something the template
    does not say: another spell's text spliced in, or a branch chosen at run time."""
    if align.UNCOUNTABLE.search(en):
        return None
    return align.variant_key(model_english(en, player_tokens=False))


def table(
    spell_english: dict[int, str],
    shipped: dict[int, tuple[str, str]],
    item_english: Iterable[str],
) -> dict[str, int]:
    """{shape key: spell id}. `spell_english`: every spell's description English by id; `shipped`: id →
    (the Japanese as it ships, its status) for every shipped description; `item_english`: every item's
    description English. A key maps to the lowest id of its spells, only when every spell of that shape
    ships the same Japanese with the same status."""
    windows = item_windows(item_english)
    groups: dict[str, list[int]] = {}
    printed: set[str] = set()
    for sid in sorted(spell_english):
        en = spell_english[sid]
        key = shape_key(en)
        if key is None:
            continue
        groups.setdefault(key, []).append(sid)
        if en.strip() in windows:
            printed.add(key)
    out: dict[str, int] = {}
    for key in sorted(printed):
        ids = groups[key]
        texts = {shipped.get(sid) for sid in ids}
        if len(texts) == 1 and None not in texts:
            out[key] = ids[0]
    return out


def spell_inputs(
    spell_lines: list[dict[str, Any]], spell_english: list[dict[str, Any]]
) -> tuple[dict[int, str], dict[int, tuple[str, str]]]:
    """The two spell maps `table` takes, from the shipped spell lines (their Japanese already as it ships)
    and the spell English store."""
    english = {int(ln["id"]): str(ln["en"]) for ln in spell_english if ln["field"] == "description"}
    shipped = {
        int(ln["id"]): (str(ln["ja"]), str(ln["status"]))
        for ln in spell_lines
        if ln["field"] == "description" and ships(ln)
    }
    return english, shipped
