"""Voice casting rules (ADR-062): who each speaking creature is (its profile), and which roster voice it gets.
Pure: the readers and writers live in `cmd/voice.py`.

A profile row: `{"creature", "race", "gender", "age", "archetype", "role"?, "provenance": {field: {...}}}`.
Each field's provenance names where it came from, in this order of trust:

1. a ruling, with its date: never replaced by anything else.
2. `client@<build>`: the client's own display tables (race and gender).
3. `vmangos@<commit>`: the open database (gender of a display the client tables lack, the creature type's
   kind of being, a racial leader's role).
4. `machine` (`{"source": "machine", "model", "batch", "reason", "imported"}`): the casting pass, for
   what only judgement can say (age, and the rest where the tables are silent). It fills gaps and replaces
   earlier machine values; it never replaces a value from 1 to 3.
"""

from __future__ import annotations

import re
import zlib
from collections.abc import Iterable, Mapping, Sequence
from typing import Any

GENDERS = ("male", "female", "none", "mixed")
AGES = ("child", "young", "adult", "elder")
ARCHETYPES = ("none", "undead", "ghost", "demon", "dragon", "elemental", "mechanical", "beast-kin", "giant")
ROLES = (
    "leader",
    "guard",
    "soldier",
    "priest",
    "mage",
    "scholar",
    "merchant",
    "innkeeper",
    "trainer",
    "noble",
    "commoner",
    "villain",
)
PLAYABLE = ("human", "orc", "dwarf", "nightelf", "scourge", "tauren", "gnome", "troll", "goblin", "bloodelf",
            "draenei")
# A speaker that is not a playable-race character model: its kind, from the creature type or the casting pass.
FAMILIES = (
    "beast",
    "dragonkin",
    "demon",
    "elemental",
    "giant",
    "undead",
    "critter",
    "mechanical",
    "ogre",
    "kobold",
    "gnoll",
    "murloc",
    "centaur",
    "harpy",
    "naga",
    "satyr",
    "furbolg",
    "trogg",
    "quilboar",
    "tauren-kin",
    "troll-kin",
    "dryad",
    "spirit",
    "other",
)
FIELDS = ("race", "gender", "age", "archetype", "role")
MAINTAINER, MACHINE = "maintainer", "machine"

# VMaNGOS creature_template.type → (race family for a speaker with no character model, archetype)
_TYPE = {
    1: ("beast", "beast-kin"),
    2: ("dragonkin", "dragon"),
    3: ("demon", "demon"),
    4: ("elemental", "elemental"),
    5: ("giant", "giant"),
    6: ("undead", "undead"),
    8: ("critter", "beast-kin"),
    9: ("mechanical", "mechanical"),
}
_UNDEAD_RACES = ("scourge", "skeleton", "northrendskeleton")
_RACE = re.compile(r"[a-z][a-z0-9_-]*")
_SOURCE = re.compile(r"(client|vmangos)@\S+")
_DATE = re.compile(r"\d{4}-\d{2}-\d{2}")


def _rank(prov: Mapping[str, Any] | None) -> int:
    """Trust of a field's provenance: higher wins."""
    src = (prov or {}).get("source", "")
    if src == MAINTAINER:
        return 3
    if isinstance(src, str) and _SOURCE.fullmatch(src):
        return 2
    if src == MACHINE:
        return 1
    return 0


def _gender(genders: Iterable[str]) -> str | None:
    """One creature's gender from its displays' genders: both kinds → mixed; a sexless display beside a
    gendered one does not count."""
    g = set(genders)
    if {"male", "female"} <= g:
        return "mixed"
    for one in ("male", "female", "none"):
        if one in g:
            return one
    return None


def facts(
    creature: Mapping[str, Any] | None,
    displays: Mapping[int, Any],
    client_src: str,
    vmangos_src: str,
    vm_gender: int | None,
) -> dict[str, tuple[str, str]]:
    """What the tables say about one creature: {field: (value, source)}. `creature` is its VMaNGOS row
    (`io/vmangos.read_creatures`) or None for a creature the database lacks; `displays` the client's display
    map (`io/creature_tables.read`); `vm_gender` VMaNGOS' gender of its first display (0 / 1 / 2) when the
    client has none of its displays."""
    out: dict[str, tuple[str, str]] = {}
    if not creature:
        return out
    shown = [displays[d] for d in creature.get("displays", []) if d in displays]
    g = _gender(d.gender for d in shown)
    if g:
        out["gender"] = (g, client_src)
    elif vm_gender in (0, 1, 2):
        out["gender"] = ({0: "male", 1: "female", 2: "none"}[vm_gender], vmangos_src)
    race = next((d.race for d in shown if d.race), None)
    kind = _TYPE.get(int(creature.get("type") or 0))
    if race:
        out["race"] = (race, client_src)
    elif kind:
        out["race"] = (kind[0], vmangos_src)
    if kind:
        out["archetype"] = (kind[1], vmangos_src)
    elif race in _UNDEAD_RACES:  # a Forsaken character model: undead, though the database calls it humanoid
        out["archetype"] = ("undead", client_src)
    if creature.get("leader"):
        out["role"] = ("leader", vmangos_src)
    return out


def build(
    speakers: Iterable[int],
    table_facts: Mapping[int, dict[str, tuple[str, str]]],
    existing: Iterable[Mapping[str, Any]],
    today: str,
) -> list[dict[str, Any]]:
    """One profile row per speaker, sorted. A field from the tables is written with its source; a field the
    file already holds from a ruling is kept over everything, and one from the casting pass is kept
    where the tables are silent. A row whose values and sources are unchanged keeps its old dates."""
    old = {int(r["creature"]): r for r in existing}
    rows = []
    for c in sorted(set(speakers)):
        prev = old.get(c, {})
        row: dict[str, Any] = {"creature": c}
        prov: dict[str, Any] = {}
        for f in FIELDS:
            mine = table_facts.get(c, {}).get(f)
            theirs = prev.get(f)
            their_prov = prev.get("provenance", {}).get(f)
            keep_theirs = theirs is not None and (
                _rank(their_prov) == 3
                or (_rank(their_prov) == 1 and mine is None)
                or (
                    mine is not None
                    and their_prov
                    and their_prov.get("source") == mine[1]
                    and theirs == mine[0]
                )
            )
            if keep_theirs:
                row[f] = theirs
                prov[f] = their_prov
            elif mine is not None:
                row[f] = mine[0]
                prov[f] = {"source": mine[1], "imported": today}
        row["provenance"] = prov
        rows.append(row)
    return rows


def needs_judgement(row: Mapping[str, Any]) -> list[str]:
    """The fields the casting pass must fill or may revisit: anything missing, or held by the pass already."""
    prov = row.get("provenance", {})
    return [f for f in FIELDS if f != "role" and (row.get(f) is None or _rank(prov.get(f)) == 1)]


def merge_machine(
    rows: list[dict[str, Any]], drafts: Iterable[Mapping[str, Any]], model: str, batch: str, today: str
) -> tuple[list[dict[str, Any]], list[str]]:
    """Casting-pass drafts into the profile rows. A draft `{"creature", "age", "archetype", "race"?,
    "gender"?, "role"?, "reason"}` fills a field that is empty or machine-made; a ruled or table value is
    never replaced (the draft's value is reported when it differs). → (rows, problems)"""
    by_id = {int(r["creature"]): r for r in rows}
    problems: list[str] = []
    for d in drafts:
        c = d.get("creature")
        if not isinstance(c, int) or c not in by_id:
            problems.append(f"draft for unknown creature {c!r}")
            continue
        reason = d.get("reason")
        if not isinstance(reason, str) or not reason.strip():
            problems.append(f"creature {c}: no reason")
            continue
        row = by_id[c]
        for f in FIELDS:
            if f not in d or d[f] is None:
                continue
            bad = _field_problem(f, d[f])
            if bad:
                problems.append(f"creature {c}: {bad}")
                continue
            if _rank(row.get("provenance", {}).get(f)) >= 2:
                if row.get(f) != d[f]:
                    problems.append(f"creature {c}: {f} kept {row.get(f)!r} (draft says {d[f]!r})")
                continue
            row[f] = d[f]
            row.setdefault("provenance", {})[f] = {
                "source": MACHINE,
                "model": model,
                "batch": batch,
                "reason": reason.strip(),
                "imported": today,
            }
    return rows, problems


def _field_problem(field: str, value: Any) -> str | None:
    allowed = {"gender": GENDERS, "age": AGES, "archetype": ARCHETYPES, "role": ROLES}.get(field)
    if allowed is not None and value not in allowed:
        return f"{field} {value!r} is not one of {', '.join(allowed)}"
    if field == "race" and not (isinstance(value, str) and _RACE.fullmatch(value)):
        return f"race {value!r} must be a lowercase race or family name"
    return None


def problems(rows: Iterable[Mapping[str, Any]]) -> list[str]:
    """`wfj validate` over data/voice/profiles.jsonl: shape, allowed values, provenance on every field, one
    row per creature. A race the client's tables gave is taken as read; any other race is a playable race
    or a family."""
    known = set(PLAYABLE) | set(FAMILIES)
    out: list[str] = []
    seen: set[int] = set()
    for row in rows:
        c = row.get("creature")
        if not isinstance(c, int) or isinstance(c, bool) or c <= 0:
            out.append(f"voice profiles: bad creature {c!r}")
            continue
        if c in seen:
            out.append(f"voice profiles {c}: duplicate")
        seen.add(c)
        prov = row.get("provenance")
        if not isinstance(prov, dict):
            out.append(f"voice profiles {c}: provenance must be an object")
            continue
        for f in FIELDS:
            v = row.get(f)
            if v is None:
                if f in prov:
                    out.append(f"voice profiles {c}: provenance for {f}, which is empty")
                continue
            bad = _field_problem(f, v)
            from_client = str((prov.get(f) or {}).get("source", "")).startswith("client@")
            if bad:
                out.append(f"voice profiles {c}: {bad}")
            elif f == "race" and v not in known and not from_client:
                out.append(f"voice profiles {c}: race {v!r} is neither a playable race nor a family")
            out += _field_provenance(prov.get(f), f"voice profiles {c} {f}")
        extra = set(row) - {"creature", "provenance", *FIELDS}
        if extra:
            out.append(f"voice profiles {c}: unknown field(s) {', '.join(sorted(extra))}")
    return out


def _field_provenance(p: Any, label: str) -> list[str]:
    if not isinstance(p, dict):
        return [f"{label}: no provenance"]
    if not isinstance(p.get("imported"), str) or not _DATE.fullmatch(p["imported"]):
        return [f"{label}: provenance imported must be a date"]
    src = p.get("source")
    if src == MACHINE:
        missing = [k for k in ("model", "batch", "reason") if not isinstance(p.get(k), str) or not p[k]]
        return [f"{label}: machine provenance lacks {', '.join(missing)}"] if missing else []
    if src == MAINTAINER or (isinstance(src, str) and _SOURCE.fullmatch(src)):
        return []
    return [f"{label}: provenance source {src!r} is not client@…, vmangos@…, machine or maintainer"]


def missing_age(rows: Iterable[Mapping[str, Any]]) -> list[int]:
    """Speakers the casting pass still owes an age."""
    return [int(r["creature"]) for r in rows if not r.get("age")]


# ---- casting: profile → roster voice ---------------------------------------------------------------------

NARRATOR_ROW = "narrator"
_VOICE_ID = re.compile(r"[a-z0-9]+")


def stable_pick(creature: int, voices: Sequence[str]) -> str:
    """The voice a creature gets from a row's list: the same creature always gets the same voice, and
    creatures standing together spread over the list."""
    return voices[zlib.crc32(str(creature).encode()) % len(voices)]


def _matches(when: Mapping[str, Any], profile: Mapping[str, Any]) -> bool:
    for field, want in when.items():
        have = profile.get(field)
        if isinstance(want, list):
            if have not in want:
                return False
        elif have != want:
            return False
    return True


def cast_one(profile: Mapping[str, Any], rows: Sequence[Mapping[str, Any]]) -> tuple[str, str] | None:
    """(voice id, row name) from the first casting row with voices whose `when` matches the profile, or None.
    A row with no voices yet is skipped."""
    for row in rows:
        if row.get("voices") and _matches(row.get("when", {}), profile):
            return stable_pick(int(profile["creature"]), row["voices"]), row["name"]
    return None


def cast(
    profiles: Iterable[Mapping[str, Any]],
    rows: Sequence[Mapping[str, Any]],
    narrator: str,
    overrides: Mapping[int, str],
) -> dict[int, dict[str, str]]:
    """creature → {"voice", "row"[, "female", "female_row"]}. An override (a ruling) wins; then the first
    matching row; then the narrator (row `narrator`). A creature the game shows as both genders (`mixed`) is
    cast twice, as male and as female, so the addon can pick by the NPC on screen."""
    out: dict[int, dict[str, str]] = {}
    for p in profiles:
        c = int(p["creature"])
        if c in overrides:
            out[c] = {"voice": overrides[c], "row": "override"}
            continue
        if p.get("gender") == "mixed":
            m = cast_one({**p, "gender": "male"}, rows) or (narrator, NARRATOR_ROW)
            f = cast_one({**p, "gender": "female"}, rows) or (narrator, NARRATOR_ROW)
            out[c] = {"voice": m[0], "row": m[1]}
            if f[0] != m[0]:
                out[c].update({"female": f[0], "female_row": f[1]})
            continue
        v, r = cast_one(p, rows) or (narrator, NARRATOR_ROW)
        out[c] = {"voice": v, "row": r}
    return out


def roster_problems(
    roster: Mapping[str, Mapping[str, Any]],
    rows: Sequence[Mapping[str, Any]],
    narrator: str,
    book_narrator: str,
) -> list[str]:
    """voice.toml's roster and casting rows: ids well formed, every voice a row names is in the roster, every
    `when` field and value one the profiles can hold, names unique."""
    out: list[str] = []
    for vid, v in roster.items():
        if not _VOICE_ID.fullmatch(vid):
            out.append(f"roster {vid!r}: an id is lowercase letters and digits")
        if not isinstance(v.get("style"), int):
            out.append(f"roster {vid}: style must be an engine style id")
        if v.get("licence") not in ("ACML 1.0", "CC0"):
            out.append(f"roster {vid}: licence must be ACML 1.0 or CC0")
    for vid in (narrator, book_narrator):
        if vid not in roster:
            out.append(f"narrator voice {vid!r} is not in the roster")
    names: set[str] = set()
    for row in rows:
        name = row.get("name")
        if not isinstance(name, str) or not name or name in names or name in (NARRATOR_ROW, "override"):
            out.append(f"cast row {name!r}: needs a unique name")
        names.add(str(name))
        out += _row_problems(row, str(name), roster)
    return out


def _row_problems(row: Mapping[str, Any], name: str, roster: Mapping[str, Any]) -> list[str]:
    out: list[str] = []
    voices = row.get("voices")
    if not isinstance(voices, list):
        out.append(f"cast row {name}: voices must be a list (empty while not cast yet)")
        voices = []
    out += [f"cast row {name}: voice {vid!r} is not in the roster" for vid in voices if vid not in roster]
    allowed = {"gender": GENDERS, "age": AGES, "archetype": ARCHETYPES, "role": ROLES}
    for field, want in row.get("when", {}).items():
        if field not in FIELDS:
            out.append(f"cast row {name}: unknown field {field!r}")
            continue
        for w in want if isinstance(want, list) else [want]:
            if field in allowed and w not in allowed[field]:
                out.append(f"cast row {name}: {field} {w!r} is not one of {', '.join(allowed[field])}")
    return out
