"""Reader for a collector dump: the `WFJ_Collector` table in a player's SavedVariables file.

Shape (docs/systems/collector.md): `{version = 1, builds = {"1.15.9.69722", …},
entries = {["<kind>:<id>:<field>"] = {t, i, f, h, e, b[, n]}}, …}`; a gossip entry is keyed by its
gossip key (`i == h`, 16 hex) and may carry `n`, the creature ids that said it.
Nothing from the file is trusted: every entry is re-checked and its hash recomputed from the text with the
same normalize_v1 the addon uses, so a hand-edited or corrupted entry cannot land in `data/english/`.
"""

from __future__ import annotations

import re
from collections import Counter
from dataclasses import dataclass, field
from typing import Any

from wfj.core.hashing import key as hash_key
from wfj.core.language import KANA, KANJI
from wfj.core.normalize import normalize_v1
from wfj.io.lua_reader import Table, parse_assignments

VERSION = 1
# collector kind → (English store type, allowed fields)
KINDS: dict[str, tuple[str, tuple[str, ...]]] = {
    "quest": ("quest", ("title", "objectives", "description", "progress", "completion")),
    "item": ("item", ("description",)),
    "spell": ("spell", ("description", "aura")),  # aura: the buff / debuff tooltip line
    "npc": ("unit", ("name",)),
    "gossip": ("gossip", ("text",)),  # id = the gossip key
}
# The collector writes Blizzard's tokens, the pfQuest convention: $N / $C / $R for the player, $B$B between
# paragraphs. Any other `$x` or a `{…}` placeholder is not something the addon writes.
TOKENS = {"$N", "$C", "$R", "$B"}
REASONS = (
    "duplicate_key",
    "bad_key",
    "bad_kind",
    "bad_field",
    "bad_id",
    "not_english",
    "unknown_placeholder",
    "hash_mismatch",
    "no_build",
)
_HEX16 = re.compile(r"^[0-9a-f]{16}$")
# The addon refuses the whole U+3000..U+9FFF block (CJK punctuation, kana, kanji); the pipeline mirrors it,
# plus compatibility ideographs, so a hand-edited dump cannot slip Japanese in.
_CJK = re.compile(r"[\u3000-\u9fff\uf900-\ufaff]")
# A build lands in `src` (`collector@<build>`), which model.validate_line checks with this shape.
_BUILD = re.compile(r"^[0-9A-Za-z._-]{4,64}$")
_DOLLAR = re.compile(r"\$.?")
NPC_CAP = 32  # the addon's Collector.NPC_CAP: ids kept per gossip entry
MAX_ID = 2**31 - 1  # a creature id is a 32-bit GUID field
_BRACE = re.compile(r"\{[a-z]+\}")


@dataclass(frozen=True)
class Entry:
    type_: str  # English store type (npc → unit)
    id_: int | str  # a game id; for gossip the gossip key
    field: str
    en: str
    hash_: str
    build: str
    npcs: tuple[int, ...] = ()  # gossip: the creature ids that said the line
    player: tuple[str, str] | None = None  # (class, race) of the character that recorded a `$C` / `$R` line


@dataclass
class Dump:
    version: int
    entries: list[Entry]
    rejected: Counter = field(default_factory=Counter)


def _int(v: Any) -> int | None:
    if isinstance(v, bool):
        return None
    if isinstance(v, int):
        return v
    if isinstance(v, float) and v.is_integer():
        return int(v)
    return None


def _array(t: Any) -> list[Any]:
    """A Lua array written either positionally (`"x", -- [1]`) or with explicit `[1] = "x"` keys."""
    if not isinstance(t, Table):
        return []
    out = t.positional()
    keyed = {n: v for k, v in t.items if (n := _int(k)) is not None}
    while len(out) + 1 in keyed:
        out.append(keyed[len(out) + 1])
    return out


def _npcs(n: Any) -> tuple[int, ...] | None:
    """`n` → sorted unique creature ids; () when absent; None unless a list of 1..NPC_CAP creature ids."""
    if n is None:
        return ()
    if not isinstance(n, Table) or not n.items or len(n.items) > NPC_CAP:
        return None
    ids = [_int(v) for _, v in n.items]
    if len(_array(n)) != len(ids) or any(i is None or not 1 <= i <= MAX_ID for i in ids):
        return None
    return tuple(sorted({i for i in ids if i is not None}))


def check_entry(key: Any, raw: Any, builds: list[Any]) -> tuple[Entry | None, str | None]:
    """→ (entry, None) or (None, reason). Reasons in the order they are checked (REASONS)."""
    if not isinstance(key, str) or not isinstance(raw, Table):
        return None, "bad_key"
    e = raw.named()
    kind, fld, raw_id = e.get("t"), e.get("f"), e.get("i")
    id_: int | str | None
    if kind == "gossip":  # the key is the text's hash: `i` must be it
        id_ = raw_id if isinstance(raw_id, str) and _HEX16.match(raw_id) and raw_id == e.get("h") else None
    else:
        id_ = _int(raw_id)
    reason = _address_problem(key, kind, fld, id_)
    if reason:
        return None, reason
    npcs = _npcs(e.get("n"))
    if npcs is None or (npcs and kind != "gossip"):
        return None, "bad_id"
    reason = _text_problem(e.get("e"), e.get("h"))
    if reason:
        return None, reason
    b = _int(e.get("b"))
    if b is None or not 1 <= b <= len(builds) or not isinstance(builds[b - 1], str):
        return None, "no_build"
    if not _BUILD.match(builds[b - 1]):
        return None, "no_build"
    return Entry(KINDS[kind][0], id_, fld, e["e"], e["h"], builds[b - 1], npcs, _player(e.get("p"))), None


def _player(raw: Any) -> tuple[str, str] | None:
    """`p`, "Class|Race" of the recording character, written only on a line holding `$C` / `$R`; anything else
    (absent, an older dump, malformed) is no player, and no literal is put back for that line."""
    if not isinstance(raw, str):
        return None
    parts = raw.split("|")
    if len(parts) != 2 or not all(part.strip() for part in parts):
        return None
    return parts[0].strip(), parts[1].strip()


def _address_problem(key: str, kind: Any, fld: Any, id_: int | str | None) -> str | None:
    """Why an entry's kind, field and id do not make a valid address matching its key, or None."""
    if not isinstance(kind, str) or not isinstance(fld, str) or id_ is None or key != f"{kind}:{id_}:{fld}":
        return "bad_key"
    if kind not in KINDS:
        return "bad_kind"
    if fld not in KINDS[kind][1]:
        return "bad_field"
    if isinstance(id_, int) and not 1 <= id_ <= MAX_ID:  # a game id is a 32-bit field
        return "bad_id"
    return None


def _text_problem(text: Any, h: Any) -> str | None:
    """Why an entry's English and its hash cannot be imported, or None."""
    if (
        not isinstance(text, str)
        or not normalize_v1(text)
        or KANA.search(text)
        or KANJI.search(text)
        or _CJK.search(text)
    ):
        return "not_english"
    if _BRACE.search(text) or any(tok not in TOKENS for tok in _DOLLAR.findall(text)):
        return "unknown_placeholder"
    if not isinstance(h, str) or not _HEX16.match(h) or h != hash_key(normalize_v1(text)):
        return "hash_mismatch"
    return None


def read_dump(text: str) -> Dump:
    """Parse a SavedVariables file and validate its `WFJ_Collector`.

    Raises ValueError when there is no dump or its version is not one this pipeline reads."""
    tables = parse_assignments(text)
    dump = tables.get("WFJ_Collector")
    if not isinstance(dump, Table):
        raise ValueError("no WFJ_Collector table in the file")
    version = _int(dump.get("version"))
    if version != VERSION:
        raise ValueError(f"collector dump version {dump.get('version')!r} is not {VERSION}")
    builds = _array(dump.get("builds"))
    entries_t = dump.get("entries")
    out = Dump(version, [])
    if not isinstance(entries_t, Table):
        return out
    seen = Counter(key for key, _ in entries_t.items)
    for key, raw in entries_t.items:
        if seen[key] > 1:  # a real client cannot write one key twice: every copy is dropped, and reported
            out.rejected["duplicate_key"] += 1
            continue
        entry, reason = check_entry(key, raw, builds)
        if entry is None:
            out.rejected[reason] += 1
        else:
            out.entries.append(entry)
    out.entries.sort(key=lambda en: (en.type_, en.id_, en.field))
    return out
