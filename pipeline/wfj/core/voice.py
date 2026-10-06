"""Voice over rules (ADR-061): the scope, who speaks each line, which voice a creature has, the text the
engine reads, and the fingerprint that says whether a made file still matches its line. Pure.

A line's pack key is the file name without `.mp3`: `<quest id>-<field>` for a quest field, `g-<gossip key>`
for a gossip line. Audio is matched to its Japanese by `ja_hash`, the hash of the Japanese exactly as the
addon ships it (tokens unfilled), so the addon can refuse audio made from older Japanese.
"""

from __future__ import annotations

import re
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass
from typing import Any

from wfj.core.hashing import key as hash_key
from wfj.core.normalize import normalize_v1
from wfj.emit.lua_writer import shipped

# A scope is the quests whose offer, progress and turn-in are voiced, and the creatures whose NPC talk is
# voiced besides their givers and enders. `all` is every quest and every creature that talks (None).
_SHADOWGLEN = {
    "quests": (456, 457, 458, 459, 916, 917, 920, 921, 928, 2159, 3120, 3519, 3521, 3522, 4495, 5842),
    "creatures": (3597,),  # the druid trainer, who gives no quest there
}
_NARACHE = {
    # 95805: a quest Forever added (Grace of An'she and Mu'sha, Seer Graytongue)
    "quests": (747, 750, 752, 753, 755, 757, 763, 780, 781, 1656, 3376, 3091, 3092, 3093, 3094, 95805),
    "creatures": (3059, 3060, 3061, 3062),  # the warrior, druid, hunter and shaman trainers
}
SCOPES: dict[str, dict[str, Any]] = {
    "shadowglen": _SHADOWGLEN,
    "narache": _NARACHE,
    # the second in-game test: the night elf and the tauren starts
    "test2": {k: _SHADOWGLEN[k] + _NARACHE[k] for k in ("quests", "creatures")},
    "all": {"quests": None, "creatures": None},
}
# description is the offer the quest giver reads, progress and completion the turn-in NPC's lines
FIELDS = ("description", "progress", "completion")
NARRATOR = "narrator"
PLAYER_WORD = "冒険者"  # the pack is made before anyone plays: it cannot know the name, class or race

_TOKEN = re.compile(r"\{(name|class|race)\}")
# angle brackets around Japanese are a stage direction ("<Iverronが解毒剤を飲む>"), read by nobody
_STAGE = re.compile(r"<[^<>]*[^\x00-\x7f][^<>]*>")
_MARKUP = re.compile(r"[{}<>$|]")
_KEY = re.compile(r"\d+-(description|progress|completion)|[gb]-[0-9a-f]{16}")
_VOICE = re.compile(r"[a-z0-9]+")


class VoiceError(ValueError):
    """A line the engine must not read as it stands."""


def quest_key(quest: int, field: str) -> str:
    return f"{quest}-{field}"


def gossip_key(key: str) -> str:
    return f"g-{key}"


def ja_hash(ja: str) -> str:
    return hash_key(ja)


_VALUE = re.compile(r"\$N(\d+)(個|体|頭|匹|羽|本|枚|つ|人|名|回|分|秒|時間|日|年|冊|粒|束|杯|箱|袋|着)?")
_WORLD_STATE = re.compile(r"\$\d+w")  # a number the server fills in ("$2113w日以内"): read as 数
_BREAK = re.compile(r"\$[bB]")
_LIVE_NUMBER = re.compile(r"[\d.,]+")


def live_values(en: str) -> list[str]:
    """The numbers the addon fills a line's `$N<k>` with, from its English: every run of digits, dots and
    commas not touching a Latin letter, commas dropped, and "A to B" joined as "A～B". A port of
    Core/Align.lua `Align.values`, so the audio says the number the window shows."""
    en = _BREAK.sub("\n", en)  # the client shows $B as a line break, which ends the letter before a number
    out: list[str] = []
    last_end = None
    for m in _LIVE_NUMBER.finditer(en):
        s, e = m.start(), m.end()
        if (s > 0 and en[s - 1].isascii() and en[s - 1].isalpha()) or (e < len(en) and en[e].isascii()
                                                                        and en[e].isalpha()):
            continue
        v = m.group(0).replace(",", "").strip(".")
        if not v:
            continue
        if last_end is not None and en[last_end:s] == " to ":
            out[-1] = f"{out[-1]}～{v}"
        else:
            out.append(v)
        last_end = e
    return out


def text_hash(ja: str, values: Sequence[str] = ()) -> str:
    """What a file's words were made from: the shipped Japanese, and the numbers filled into it."""
    return ja_hash(ja) if not values else ja_hash(ja + "\x00" + ",".join(values))


def speech_text(ja: str, key: str, values: Sequence[str] = ()) -> str:
    """The text the engine reads: player tokens become 冒険者, `$N<k>` the k-th number of the line's English
    (`values`); a number only the game knows (none in the English, or a server count such as `$2113w`) is
    read as 何個か / 数, stage directions are dropped (a line that is nothing but one is read without its
    brackets), and any other markup is refused with the line's key (it would be read aloud as symbols)."""

    def number(m: re.Match[str]) -> str:
        k, counter = int(m.group(1)), m.group(2) or ""
        if 1 <= k <= len(values):
            return values[k - 1] + counter
        return f"何{counter}か" if counter else "いくつか"

    filled = _WORLD_STATE.sub("数", _VALUE.sub(number, _BREAK.sub("\n", ja)))
    spoken = _STAGE.sub("", filled)
    if not _MARKUP.sub("", _TOKEN.sub("", spoken)).strip():
        spoken = re.sub(r"[<>]", "", filled)
    text = _TOKEN.sub(PLAYER_WORD, spoken)
    bad = _MARKUP.search(text)
    if bad:
        raise VoiceError(f"{key}: markup {bad.group(0)!r} the voice cannot read")
    text = re.sub(r"[ \t]+\n", "\n", text).strip()
    if not text:
        raise VoiceError(f"{key}: nothing left to read")
    return text


def shipped_quest(quest_lines: Iterable[dict[str, Any]], quests: Iterable[int] | None) -> dict[str, str]:
    """{pack key: Japanese} for the scoped quests' voiced fields that ship (the Japanese generate writes
    verbatim for a quest field). `quests` None: every quest."""
    want = None if quests is None else set(quests)
    return {
        quest_key(ln["id"], ln["field"]): ln["ja"]
        for ln in quest_lines
        if (want is None or ln["id"] in want) and ln["field"] in FIELDS and shipped(ln)
    }


def gossip_id(en: str) -> str:
    """The gossip key of an English text, as the importer keys it (ADR-005)."""
    return hash_key(normalize_v1(en))


def quest_speakers(
    keys: Iterable[str],
    starters: dict[int, list[int]],
    objects: set[int],
    enders: dict[int, list[int]],
    others: dict[str, list[int]] | None = None,
) -> tuple[dict[str, int | str], list[str]]:
    """{pack key: creature id or "narrator"} for quest keys, and the conflicts reported. The offer is read by
    the creature that starts the quest; an object or item start (no creature) is the narrator. Progress and
    turn-in are read by the creature that ends it. Two creatures for one line: the lowest id is its main
    speaker, reported; the rest go into `others` when it is given (each may have a voice of its own)."""
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
            if others is not None:
                others[key] = sorted(set(who) - {min(who)})
        out[key] = min(who)
    return out, problems


def captured_speaker(names: list[int | None]) -> int | str | None:
    """The speaker most submissions name for a window: a creature id, the narrator for an object (a shrine, a
    sign), or None when there are none. A tie goes to a creature, then the lowest id."""
    if not names:
        return None
    counts: dict[int | None, int] = {}
    for n in names:
        counts[n] = counts.get(n, 0) + 1
    best = max(counts.items(), key=lambda kv: (kv[1], kv[0] is not None, -(kv[0] or 0)))[0]
    return NARRATOR if best is None else best


def gossip_speakers(
    lines: Iterable[tuple[int, str]],
    collector: dict[str, list[int]],
    shipped_keys: set[str],
    others: dict[str, list[int]] | None = None,
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
        rest = sorted((set(recorded) | creatures) - {seen[0]})
        if rest and others is not None:
            others[gossip_key(k)] = rest
        out[gossip_key(k)] = seen[0]
    report["missing"] = sorted(set(report["missing"]))
    return out, report


def fingerprint(ja_h: str, voice: str, settings: Mapping[str, Any]) -> str:
    """What a file was made from: the Japanese hash, the roster voice and that voice's engine settings. A
    file is made again when any of them changes, so recasting one kind of speaker remakes only its lines.
    The engine version is recorded beside it, not in it: an engine upgrade does not remake the game."""
    return (
        f"{ja_h}|{voice}|{int(settings['style'])}|{float(settings['speed']):g}"
        f"|{float(settings.get('pitch', 0.0)):g}|{float(settings.get('intonation', 1.0)):g}"
    )


@dataclass(frozen=True)
class Job:
    """One audio file: `stem` is the file name without `.mp3`: the pack key for a line's main voice,
    `<key>_<voice>` for a variant (`_` appears in no key and no voice id)."""

    stem: str
    key: str
    voice: str


def book_key(key: str) -> str:
    return f"b-{key}"


def voices_of(row: Mapping[str, Any], cast: Mapping[int, Mapping[str, str]], narrator: str,
              book_narrator: str) -> tuple[str, list[str]]:
    """(the line's main voice, its other voices). The main voice is its main speaker's (a mixed-gender
    creature's male casting), the narrator's for a line no creature says; the others are every other voice
    a speaker of the line is cast to, sorted."""
    sp = row["speaker"]
    if sp == NARRATOR:
        main = book_narrator if row["key"].startswith("b-") else narrator
    else:
        main = cast[sp]["voice"]
    other: set[str] = set()
    for c in (sp, *row.get("others", ())):
        if isinstance(c, int):
            other.add(cast[c]["voice"])
            if cast[c].get("female"):
                other.add(cast[c]["female"])
    other.discard(main)
    return main, sorted(other)


def jobs(rows: Iterable[Mapping[str, Any]], cast: Mapping[int, Mapping[str, str]], narrator: str,
         book_narrator: str, lines: Mapping[str, str]) -> list[Job]:
    """Every file the rows need, for the keys that ship Japanese."""
    out: list[Job] = []
    for row in rows:
        key = row["key"]
        if key not in lines:
            continue
        main, other = voices_of(row, cast, narrator, book_narrator)
        out.append(Job(key, key, main))
        out += [Job(f"{key}_{v}", key, v) for v in other]
    return out


def in_step(
    file_jobs: Iterable[Job], lines: Mapping[str, str], roster: Mapping[str, Mapping[str, Any]],
    audio: Mapping[str, Mapping[str, Any]], values: Mapping[str, Sequence[str]] | None = None,
) -> dict[str, list[str]]:
    """The audio record against what the files must be now: `missing` (no record), `stale` (made from other
    Japanese, another voice or other settings). Empty lists: voice is in step with the translation."""
    out: dict[str, list[str]] = {"missing": [], "stale": []}
    for j in file_jobs:
        rec = audio.get(j.stem)
        if rec is None:
            out["missing"].append(j.stem)
        elif rec.get("fingerprint") != fingerprint(
            text_hash(lines[j.key], (values or {}).get(j.key, ())), j.voice, roster[j.voice]
        ):
            out["stale"].append(j.stem)
    return out


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
        if not (sp == NARRATOR or _creature_id(sp)):
            problems.append(f"voice speakers {key}: speaker must be a creature id or {NARRATOR!r}")
        others = row.get("others", [])
        if not isinstance(others, list) or not all(_creature_id(o) for o in others) or sp in others:
            problems.append(f"voice speakers {key}: others must be creature ids other than the speaker")
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
        for f in ("voice", "female"):
            v = row.get(f)
            if (f == "voice" or v is not None) and not (isinstance(v, str) and _VOICE.fullmatch(v)):
                problems.append(f"voice voices {c}: {f} must be a roster voice id")
        if not isinstance(row.get("row"), str) or not row["row"]:
            problems.append(f"voice voices {c}: row must name the cast row that chose the voice")
        problems += _provenance(row, f"voice voices {c}")
    for row in speakers:
        for sp in (row.get("speaker"), *row.get("others", [])):
            if isinstance(sp, int) and sp not in has_voice:
                problems.append(f"voice speakers {row.get('key')}: creature {sp} has no voice row")
    return problems


def _creature_id(v: Any) -> bool:
    return isinstance(v, int) and not isinstance(v, bool) and v > 0


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
