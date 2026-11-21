"""DonData's quest files (github.com/WoW-Forever-Addons/dondata): who gives and who takes each quest.

`Data/ATT_Quests.lua` is derived from AllTheThings' Forever database (MIT) and names quest givers.
`Data/Extra_Quests.lua` is DonData's own (GPL-3.0) and names the creature a quest is turned in to, with a few
more givers. Read only: nothing of either file is stored but quest ids and creature ids.

Both files are Lua tables written one row per line, `[quest id]={...},`, inside `ns.<NAME> = {` and `}`.
"""

from __future__ import annotations

import re
from collections.abc import Iterator
from dataclasses import dataclass
from pathlib import Path

ATT_FILE, EXTRA_FILE = "ATT_Quests.lua", "Extra_Quests.lua"  # as saved by `make voice-dondata-fetch`
GIVERS_FIELD = 6  # ATT_QUESTS / EXTRA_QUESTS: map, x, y, faction, level, prereqs, givers, flags, ...
FLAGS_FIELD = 7
ENDER_FIELD = 3  # QUEST_ENDS: uiMapID, x, y, npcID; a turn-in at an object has no fourth field

_ROW = re.compile(r"^\[(\d+)\]=\{(.*)\},?\s*$")


@dataclass(frozen=True)
class QuestNpcs:
    """Creature ids by quest id, and the quests the files say no creature starts or ends."""

    givers: dict[int, tuple[int, ...]]
    enders: dict[int, tuple[int, ...]]
    item_starts: frozenset[int]
    object_ends: frozenset[int]


def source(commit: str) -> str:
    """The provenance source of a fact taken from the files at `commit`."""
    return f"dondata@{commit[:7]}"


def _fields(body: str) -> list[str]:
    """A row's top-level fields: commas inside braces or a quoted string do not split."""
    out: list[str] = []
    depth, quoted, escaped, cur = 0, False, False, []
    for ch in body:
        if quoted:
            cur.append(ch)
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                quoted = False
        elif ch == "," and depth == 0:
            out.append("".join(cur))
            cur = []
        else:
            quoted = ch == '"'
            depth += (ch == "{") - (ch == "}")
            cur.append(ch)
    out.append("".join(cur))
    return out


def _rows(path: Path, table: str) -> Iterator[tuple[int, list[str]]]:
    """(quest id, fields) for each row of `ns.<table>`."""
    inside = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith(f"ns.{table} = {{"):
            inside = True
        elif inside and line.startswith("}"):
            return
        elif inside and (m := _ROW.match(line)):
            yield int(m.group(1)), _fields(m.group(2))


def _ids(field: str) -> tuple[int, ...]:
    """The ids of a `{1,2}` list field, in order; `nil` and anything quoted hold none."""
    if not field.startswith("{"):
        return ()
    return tuple(dict.fromkeys(int(n) for n in re.findall(r"\d+", field)))


def _inline_keys(path: Path, table: str) -> frozenset[int]:
    """The keys of a table written on one line, `ns.<table> = {[1]=true,[2]=true,}`."""
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith(f"ns.{table} = {{["):
            return frozenset(int(n) for n in re.findall(r"\[(\d+)\]=", line))
    return frozenset()


def read(att: Path, extra: Path) -> QuestNpcs:
    """Who gives and takes each quest, from the two files."""
    givers: dict[int, tuple[int, ...]] = {}
    item_starts = set(_inline_keys(extra, "EXTRA_ITEM_STARTS"))
    for path, table in ((att, "ATT_QUESTS"), (extra, "EXTRA_QUESTS")):
        for quest, f in _rows(path, table):
            flags = f[FLAGS_FIELD] if len(f) > FLAGS_FIELD else "nil"
            if flags.startswith('"') and "i" in flags:
                item_starts.add(quest)
            elif len(f) > GIVERS_FIELD and (who := _ids(f[GIVERS_FIELD])):
                givers[quest] = who
    for quest, f in _rows(extra, "EXTRA_GIVERS"):
        who = tuple(dict.fromkeys(int(n) for n in f if n.strip().isdigit()))
        if who and quest not in item_starts:
            givers[quest] = who
    enders: dict[int, tuple[int, ...]] = {}
    object_ends: set[int] = set()
    for quest, f in _rows(extra, "QUEST_ENDS"):
        if len(f) > ENDER_FIELD and f[ENDER_FIELD].strip().isdigit():
            enders[quest] = (int(f[ENDER_FIELD]),)
        else:
            object_ends.add(quest)
    return QuestNpcs(givers, enders, frozenset(item_starts), frozenset(object_ends))
