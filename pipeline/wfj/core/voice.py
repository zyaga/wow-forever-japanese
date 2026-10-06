"""Voice over rules (ADR-061): the scope, who speaks each line, which voice a creature has, the text the
engine reads, and the fingerprint that says whether a made file still matches its line. Pure.

A line's pack key is the file name without `.mp3`: `<quest id>-<field>` for a quest field, `g-<gossip key>`
for a gossip line. Audio is matched to its Japanese by `ja_hash`, the hash of the Japanese exactly as the
addon ships it (tokens unfilled), so the addon can refuse audio made from older Japanese.
"""

from __future__ import annotations

import re
from collections.abc import Iterable
from typing import Any

from wfj.core.hashing import key as hash_key
from wfj.core.normalize import normalize_v1
from wfj.emit.lua_writer import shipped

# The quests a new night elf does in Shadowglen, and its druid trainer, who gives no quest there.
SCOPES: dict[str, dict[str, Any]] = {
    "shadowglen": {
        "quests": (456, 457, 458, 459, 916, 917, 920, 921, 928, 2159, 3120, 3519, 3521, 3522, 4495, 5842),
        "creatures": (3597,),
    },
}
# description is the offer the quest giver reads, progress and completion the turn-in NPC's lines
FIELDS = ("description", "progress", "completion")
VOICES = ("male", "female", "narrator")
NARRATOR = "narrator"
PLAYER_WORD = "冒険者"  # the pack is made before anyone plays: it cannot know the name, class or race

_TOKEN = re.compile(r"\{(name|class|race)\}")
# angle brackets around Japanese are a stage direction ("<Iverronが解毒剤を飲む>"), read by nobody
_STAGE = re.compile(r"<[^<>]*[^\x00-\x7f][^<>]*>")
_MARKUP = re.compile(r"[{}<>$|]")
_KEY = re.compile(r"\d+-(description|progress|completion)|g-[0-9a-f]{16}")


class VoiceError(ValueError):
    """A line the engine must not read as it stands."""


def quest_key(quest: int, field: str) -> str:
    return f"{quest}-{field}"


def gossip_key(key: str) -> str:
    return f"g-{key}"


def ja_hash(ja: str) -> str:
    return hash_key(ja)


def speech_text(ja: str, key: str) -> str:
    """The text the engine reads: player tokens become 冒険者, stage directions are dropped, and any other
    markup is refused with the line's key (it would be read aloud as symbols)."""
    text = _TOKEN.sub(PLAYER_WORD, _STAGE.sub("", ja))
    bad = _MARKUP.search(text)
    if bad:
        raise VoiceError(f"{key}: markup {bad.group(0)!r} the voice cannot read")
    text = re.sub(r"[ \t]+\n", "\n", text).strip()
    if not text:
        raise VoiceError(f"{key}: nothing left to read")
    return text


def shipped_quest(quest_lines: Iterable[dict[str, Any]], quests: Iterable[int]) -> dict[str, str]:
    """{pack key: Japanese} for the scoped quests' voiced fields that ship (the Japanese generate writes
    verbatim for a quest field)."""
    want = set(quests)
    return {
        quest_key(ln["id"], ln["field"]): ln["ja"]
        for ln in quest_lines
        if ln["id"] in want and ln["field"] in FIELDS and shipped(ln)
    }


def gossip_id(en: str) -> str:
    """The gossip key of an English text, as the importer keys it (ADR-005)."""
    return hash_key(normalize_v1(en))


def quest_speakers(
    keys: Iterable[str],
    starters: dict[int, list[int]],
    objects: set[int],
    enders: dict[int, list[int]],
) -> tuple[dict[str, int | str], list[str]]:
    """{pack key: creature id or "narrator"} for quest keys, and the conflicts reported. The offer is read by
    the creature that starts the quest; an object or item start (no creature) is the narrator. Progress and
    turn-in are read by the creature that ends it. Two creatures for one line: the lowest id, reported."""
    out: dict[str, int | str] = {}
    problems: list[str] = []
    for key in sorted(keys):
        quest_s, field = key.split("-", 1)
        quest = int(quest_s)
        who = starters.get(quest, []) if field == "description" else enders.get(quest, [])
        if not who:
            out[key] = NARRATOR
            if field != "description" or quest not in objects:
                problems.append(f"{key}: no creature in the database, narrator")
            continue
        if len(who) > 1:
            problems.append(f"{key}: creatures {who}, took {min(who)}")
        out[key] = min(who)
    return out, problems


def gossip_speakers(
    lines: Iterable[tuple[int, str]], collector: dict[str, list[int]], shipped_keys: set[str]
) -> tuple[dict[str, int], dict[str, list[str]]]:
    """{pack key: creature id} for gossip lines of the scoped creatures that ship in Japanese. A creature id
    the collector recorded in game for that line wins over the database (what the client served). Report:
    `conflict` (several creatures, lowest taken) and `missing` (scoped English with no shipped Japanese)."""
    by_key: dict[str, set[int]] = {}
    report: dict[str, list[str]] = {"conflict": [], "missing": []}
    for creature, en in lines:
        k = gossip_id(en)
        if k not in shipped_keys:
            report["missing"].append(f"g-{k} (creature {creature})")
            continue
        by_key.setdefault(k, set()).add(creature)
    out: dict[str, int] = {}
    for k, creatures in sorted(by_key.items()):
        recorded = collector.get(k, [])
        seen = sorted(set(recorded) & creatures) or sorted(recorded) or sorted(creatures)
        if len(seen) > 1:
            report["conflict"].append(f"g-{k}: creatures {seen}, took {seen[0]}")
        out[gossip_key(k)] = seen[0]
    report["missing"] = sorted(set(report["missing"]))
    return out, report


def voice_of(gender: int | None) -> str:
    """0 male, 1 female; a display with no gender, or none known, is the narrator."""
    return {0: "male", 1: "female"}.get(gender if gender is not None else -1, NARRATOR)


def fingerprint(ja_h: str, voice: str, style: int, speed: float, engine: str) -> str:
    return f"{ja_h}|{voice}|{style}|{speed:g}|{engine}"


def speaker_problems(speakers: list[dict[str, Any]], voices: list[dict[str, Any]]) -> list[str]:
    """`wfj validate` over data/voice/: shape, provenance, duplicates, and a voice for every speaker."""
    problems: list[str] = []
    seen: set[str] = set()
    for row in speakers:
        key = row.get("key")
        if not isinstance(key, str) or not _KEY.fullmatch(key):
            problems.append(f"voice speakers: bad key {key!r}")
        elif key in seen:
            problems.append(f"voice speakers {key}: duplicate")
        seen.add(str(key))
        sp = row.get("speaker")
        if not (sp == NARRATOR or (isinstance(sp, int) and not isinstance(sp, bool) and sp > 0)):
            problems.append(f"voice speakers {key}: speaker must be a creature id or {NARRATOR!r}")
        problems += _provenance(row, f"voice speakers {key}")
    has_voice: set[int] = set()
    for row in voices:
        c = row.get("creature")
        if not isinstance(c, int) or isinstance(c, bool) or c <= 0:
            problems.append(f"voice voices: bad creature {c!r}")
            continue
        if c in has_voice:
            problems.append(f"voice voices {c}: duplicate")
        has_voice.add(c)
        if row.get("voice") not in VOICES:
            problems.append(f"voice voices {c}: voice must be one of {', '.join(VOICES)}")
        problems += _provenance(row, f"voice voices {c}")
    for row in speakers:
        sp = row.get("speaker")
        if isinstance(sp, int) and sp not in has_voice:
            problems.append(f"voice speakers {row.get('key')}: creature {sp} has no voice row")
    return problems


def _provenance(row: dict[str, Any], label: str) -> list[str]:
    prov = row.get("provenance")
    if not isinstance(prov, dict):
        return [f"{label}: provenance must be an object"]
    p = []
    if not isinstance(prov.get("source"), str) or not re.fullmatch(r"[a-z0-9_-]+@\S+", prov["source"]):
        p.append(f"{label}: provenance source must be name@version")
    if not isinstance(prov.get("imported"), str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", prov["imported"]):
        p.append(f"{label}: provenance imported must be a date")
    return p
