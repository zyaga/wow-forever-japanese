"""The game's own NPC voice sets and the cast that clones them (ADR-074; docs/systems/voice.md).

Each playable race and gender has two or three sets of NPC barks, recorded by different actors and named like
`sound/creature/nightelfmalewarriornpc/`. Which set each NPC speaks with is taken as the Spoken voice addon
assigns it (`wfj voice sets creatures`, data/voice/creature-sets.jsonl).
"""

from __future__ import annotations

import re
from collections.abc import Iterable, Mapping
from typing import Any

SET = re.compile(r"(human|dwarf|gnome|nightelf|orc|troll|tauren|undead|goblin|skybourneelf)(male|female)"
                 r"([a-z]+?|\d+)npc")
# the set folders spell the Forsaken "undead" and the profiles call Forever's elves "skyborne"; a set
# Forever adds has no folder name and is named after its NPCSounds row instead ("skybourneelfmale3776npc")
_RACE = {"undead": "scourge", "skybourneelf": "skyborne"}
GENDERS = ("male", "female")


def parse(name: str) -> tuple[str, str, str] | None:
    """(race as the display tables name it, gender, flavour) of a set folder name; None for anything else."""
    m = SET.fullmatch(name)
    if not m:
        return None
    return _RACE.get(m.group(1), m.group(1)), m.group(2), m.group(3)


def voice_id(set_name: str) -> str:
    """The roster id of a set's cloned voice: `q` and the set name without its `npc`."""
    return "q" + set_name.removesuffix("npc")


def rule_sets(profile: Mapping[str, Any], rules: Iterable[Mapping[str, Any]]) -> dict[str, str]:
    """{gender: set} for a creature Spoken gives no set: the first `[[set_cast]]` rule of voice.toml whose
    `when` matches its profile, per gender (a creature shown as both genders, or as none, is matched as male
    and as female)."""
    g = profile.get("gender")
    out: dict[str, str] = {}
    for gender in (("male", "female") if g in ("mixed", "none", None) else (g,)):
        p = {**profile, "gender": gender}
        for rule in rules:
            when = rule["when"].items()
            if all((p.get(k) in v) if isinstance(v, list) else p.get(k) == v for k, v in when):
                out[gender] = rule["set"]
                break
    if g in ("none", None):
        out.pop("female", None)  # a sexless creature speaks with the male set
    return out


def clone_cast(cast: Mapping[int, Mapping[str, str]], sets: Mapping[int, Mapping[str, str]],
               homes: Mapping[int, str], cloned_packs: Iterable[str], roster: Mapping[str, Any],
               pinned: Iterable[int] = ()) -> dict[int, dict[str, str]]:
    """The cast with each creature of a cloned pack moved to its game voice set: a creature whose home pack is
    cloned and whose set has a cloned voice in the roster (picked as a voice-only or full copy) speaks with
    it, a creature shown as both genders with each gender's set. Everyone else, and a creature pinned by a
    ruling, keeps its cast."""
    packs, keep = set(cloned_packs), set(pinned)
    out: dict[int, dict[str, str]] = {}
    for c, row in cast.items():
        new = dict(row)
        got = sets.get(c, {})
        if c not in keep and homes.get(c) in packs and got:
            male, female = got.get("male"), got.get("female")
            mv = voice_id(male) if male and voice_id(male) in roster else None
            fv = voice_id(female) if female and voice_id(female) in roster else None
            if male and female:
                if mv:
                    new.update(voice=mv, row=f"set {male}")
                if fv:
                    new.update(female=fv, female_row=f"set {female}")
            elif male and mv:
                new.update(voice=mv, row=f"set {male}")
            elif female and fv:
                new.update(voice=fv, row=f"set {female}")
        out[c] = new
    return out


def voice_genders(roster: Mapping[str, Mapping[str, Any]],
                  model_genders: Mapping[str, str]) -> dict[str, str]:
    """voice id → male or female, where it is known: a cloned voice by its set, an AivisSpeech voice by its
    model's gender in the voice catalogue (a neutral or mechanical voice has none)."""
    out: dict[str, str] = {}
    for vid, v in roster.items():
        if v.get("engine") == "qwen":
            p = parse(str(v.get("set", "")))
            g = p[1] if p else None
        else:
            g = model_genders.get(str(v.get("model", "")))
        if g in GENDERS:
            out[vid] = g
    return out


def gender_problems(cast: Mapping[int, Mapping[str, str]], profiles: Mapping[int, Mapping[str, Any]],
                    genders: Mapping[str, str]) -> list[str]:
    """Creatures of one gender cast to a voice of the other: a man must never be heard in a woman's voice. A
    creature cast to a game voice set is left out: its set, and so its gender, is Spoken's assignment, which
    wins over a gender this project judged from text."""
    out = []
    for c, row in sorted(cast.items()):
        if str(row.get("row", "")).startswith("set "):
            continue
        g = (profiles.get(c) or {}).get("gender")
        if g in GENDERS and genders.get(row.get("voice", "")) not in (None, g):
            v = row["voice"]
            out.append(f"voice voices {c}: a {g} speaker cast to {v}, a {genders[v]} voice")
    return out
