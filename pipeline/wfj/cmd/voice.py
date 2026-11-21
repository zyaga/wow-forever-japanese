"""wfj voice: Japanese voice over, made locally (ADR-061, ADR-062; docs/systems/voice.md, runbook
docs/operations/voice.md). This module builds who speaks each line; the casting verbs are in `voice_cast`,
the file verbs (cast, plan, generate, status) in `voice_make`, the shipping verbs (pack, release) in
`voice_ship`.

  speakers --vmangos FILE --commit SHA [--scope all] [--wdb questcache.wdb] [--spoken corpus.json.gz]
      Writes data/voice/speakers.jsonl (pack key → its main speaker, a creature id or narrator, and the
      `others` who say it too) for the scope, from the VMaNGOS world database, the creature ids the collector
      recorded with gossip English (data/english/gossip `npcs`, which win) and, with --wdb, the quest cache's
      conditional descriptions. Prints the lines read by the narrator, the conflicts and the scoped lines with
      no Japanese.
"""

from __future__ import annotations

import argparse
import datetime
import json
import sys
from collections.abc import Iterable, Sequence
from pathlib import Path
from typing import Any

from wfj.core import voice
from wfj.emit.lua_writer import shipped
from wfj.io import dondata, forever_vo, spoken, vmangos, wdb
from wfj.io.jsonl_store import Store, dumps
from wfj.paths import data_root

# The research doc's character counts: the quest and gossip text forever-vo voices, and everything
FULL_SCOPES = {"quest and gossip text": 3_880_000, "everything": 4_650_000}


def voice_dir(root: Path) -> Path:
    return root / "voice"


def read_rows(path: Path) -> list[dict[str, Any]]:
    if not path.is_file():
        return []
    with path.open(encoding="utf-8") as f:
        return [json.loads(raw) for raw in f if raw.strip()]


def write_rows(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(dumps(r) + "\n" for r in rows), encoding="utf-8")


def shipped_lines(root: Path, scope: str) -> dict[str, str]:
    """{pack key: shipped Japanese} for the scope: its quests' voiced fields and every shipped gossip line
    (the speakers table narrows gossip to the scope's creatures)."""
    store = Store(root)
    out = voice.shipped_quest(store.load("quest"), voice.SCOPES[scope]["quests"])
    out.update({voice.gossip_key(ln["id"]): ln["ja"] for ln in store.load("gossip") if shipped(ln)})
    return out


def _keep_date(rows: list[dict[str, Any]], old: list[dict[str, Any]], id_field: str) -> list[dict[str, Any]]:
    """A row unchanged but for its date keeps its old date: a re-run on another day writes the same bytes."""
    before = {r[id_field]: r for r in old}
    out = []
    for r in rows:
        prev = before.get(r[id_field])
        same = prev and {**prev, "provenance": {**prev["provenance"], "imported": ""}} == {
            **r, "provenance": {**r["provenance"], "imported": ""}
        }
        out.append(prev if same else r)
    return out


def _follow_captures(
    speakers: dict[str, int | str], sources: dict[str, str], keys: Iterable[str], folder: Path, commit: str
) -> None:
    """Gives each quest line of `keys` that no creature speaks yet the speaker the players' captures saw in
    its window: a creature, or the narrator for an object."""
    seen = forever_vo.read_quest_speakers(folder)
    for key in keys:
        q, f = key.split("-", 1)
        who = voice.captured_speaker(seen.get((int(q), f), []))
        if speakers.get(key, voice.NARRATOR) == voice.NARRATOR and who is not None:
            speakers[key] = who
            sources[key] = f"forever-vo@{commit}"


def _follow_spoken(
    speakers: dict[str, int | str], others: dict[str, list[int]], sources: dict[str, str],
    keys: Iterable[str], corpus: Path, commit: str,
) -> None:
    """Gives each quest line of `keys` the creature Spoken names for it, where that is another speaker than
    the one it has (or it has none), and records Spoken as the line's source."""
    named = spoken.read_quest_speakers(corpus)
    for key in keys:
        q, f = key.split("-", 1)
        who = named.get((int(q), f))
        if who is not None and speakers.get(key) != who:
            speakers[key] = who
            sources[key] = spoken.source(commit)
            if who in others.get(key, ()):
                others[key] = [c for c in others[key] if c != who]


def build_tables(  # noqa: PLR0913 - the data, the database, and one optional outside source per parameter
    root: Path, db: Path, commit: str, scope: str, today: str, wdb_path: Path | None = None,
    captures: tuple[Path, str] | None = None, spoken_corpus: tuple[Path, str] | None = None,
    dondata_files: tuple[Path, Path, str] | None = None,
) -> tuple[list[dict[str, Any]], dict[str, list[str]]]:
    """(speakers rows, report) for the scope. A speakers row names the line's main speaker and,
    when several creatures say it, the `others` (each may be cast to a voice of its own). With `wdb_path`
    (the pinned quest cache) a quest's conditional descriptions, keyed by their English (ADR-054), are read
    by the giver the cache names, else by the quest's starter. With `spoken_corpus` (Spoken's line corpus and
    its commit) a quest line Spoken gives to one creature is spoken by that creature, whatever the other
    sources say: the two voices of a line a player hears with both addons are then the same NPC's. With
    `dondata_files` (DonData's two quest files and their commit) a quest line no other source names is spoken
    by the creature those files name. The NPC a player's own quest window showed (the Collector's quest NPCs)
    wins over all of them. A quest line nobody names has no row: it is not voiced."""
    cfg = voice.SCOPES[scope]
    whole = cfg["quests"] is None
    src = f"vmangos@{commit}"
    store, english_store = Store(root), Store(root, english=True)
    quest_lines = store.load("quest")
    if whole:
        starters, objects, enders = vmangos.read_all_quest_speakers(db)
        object_ends = vmangos.read_object_ends(db)
        quest_keys = voice.shipped_quest(quest_lines, None)
        quests = {int(k.split("-", 1)[0]) for k in quest_keys}
    else:
        quests = set(cfg["quests"])
        starters, objects, enders = vmangos.read_quest_speakers(db, quests)
        object_ends = vmangos.read_object_ends(db, quests)
        quest_keys = voice.shipped_quest(quest_lines, quests)
    others: dict[str, list[int]] = {}
    q_speakers, q_problems = voice.quest_speakers(quest_keys, starters, objects, enders, others, object_ends)
    # a quest the open database lacks (one Forever added): who the players' captures saw in the window
    captured_src: dict[str, str] = {}
    if captures is not None:
        _follow_captures(q_speakers, captured_src, sorted(quest_keys), *captures)
    if spoken_corpus is not None:
        _follow_spoken(q_speakers, others, captured_src, sorted(quest_keys), *spoken_corpus)
    if dondata_files is not None:
        _follow_dondata(q_speakers, others, captured_src, sorted(quest_keys), *dondata_files)
    _follow_collector(q_speakers, others, captured_src, sorted(quest_keys), root)
    q_problems = [p for p in q_problems if p.split(":", 1)[0] not in captured_src]
    creatures = {c for q in quests for c in (*starters.get(q, ()), *enders.get(q, ()))}
    creatures |= {s for s in q_speakers.values() if isinstance(s, int)}
    creatures |= vmangos.read_gossip_creatures(db) if whole else set(cfg["creatures"])
    gossip_shipped = {
        ln["id"] for ln in store.load("gossip") if shipped(ln) and not voice.kept_in_english(ln["ja"])
    }
    english_gossip = english_store.load("gossip")
    collector = {ln["id"]: ln["npcs"] for ln in english_gossip if ln.get("npcs")}
    collector_src = {ln["id"]: ln["src"] for ln in english_gossip if ln.get("npcs")}
    said = vmangos.read_creature_lines(db, creatures)
    if whole:  # a line the client served with the creatures who said it, the database's or not
        said += [(n, ln["en"]) for ln in english_gossip for n in ln.get("npcs") or ()]
    g_speakers, report = voice.gossip_speakers(said, collector, gossip_shipped, others)
    report["quest"] = q_problems
    report["missing"] += sorted(
        f"{voice.quest_key(q, f)}"
        for q in (quests if not whole else ())
        for f in voice.FIELDS
        if voice.quest_key(q, f) not in quest_keys and _has_english(root, q, f)
    )

    def prov(source: str) -> dict[str, str]:
        return {"source": source, "imported": today}

    def row(key: str, speaker: int | str, source: str) -> dict[str, Any]:
        r: dict[str, Any] = {"key": key, "speaker": speaker}
        if others.get(key):
            r["others"] = others[key]
        r["provenance"] = prov(source)
        return r

    speakers = [row(k, s, captured_src.get(k, src)) for k, s in sorted(q_speakers.items())]
    speakers += [
        row(k, s, collector_src[k[2:]] if s in collector.get(k[2:], []) else src)
        for k, s in sorted(g_speakers.items())
    ]
    if wdb_path is not None:
        have = {r["key"] for r in speakers}
        conditional = _conditional_speakers(
            wdb_path, quests, starters, objects, q_speakers, gossip_shipped, have)
        speakers += [row(k, s, f"wdb@{b}") for k, (s, b) in sorted(conditional.items())]
        report["conditional"] = [f"{k}: {s}" for k, (s, _) in sorted(conditional.items())]
    if whole:  # each plain-text book page: its signer if one cast creature has that name, else the narrator
        have = {r["key"] for r in speakers}
        for k, who in book_readers(root, db, have).items():
            source = "book@narrator" if who == voice.NARRATOR else f"book-signature@{commit}"
            speakers.append(row(k, who, source))
    speakers.sort(key=lambda r: r["key"])
    return speakers, report


def book_readers(root: Path, db: Path, have: set[str]) -> dict[str, int | str]:
    """{book key: reader} for every shipped plain-text page not already given a speaker: the creature its
    signature names (VMaNGOS creature names, read here only, never written), else the narrator."""
    from wfj.cmd.voice_make import shipped_lines as all_lines

    english = {voice.book_key(str(ln["hash"])): ln["en"]
               for ln in Store(root, english=True).load("book") if ln.get("hash")}
    pages = {k: english.get(k, "") for k in sorted(all_lines(root)) if k.startswith("b-") and k not in have}
    names: dict[str, list[int]] = {}
    for c, info in vmangos.read_creatures(db).items():
        names.setdefault(str(info["name"]), []).append(c)
    cast = {int(r["creature"]) for r in read_rows(voice_dir(root) / "voices.jsonl")}
    return voice.book_speakers(pages, names, cast)


def _follow_dondata(
    speakers: dict[str, int | str], others: dict[str, list[int]], sources: dict[str, str],
    keys: Iterable[str], att: Path, extra: Path, commit: str,
) -> None:
    """Names the quest lines of `keys` that no other source named, from DonData's quest files: the creature
    that gives the quest (the offer) or takes it (progress, turn-in), or the narrator where the files say an
    item starts it or it is turned in at an object."""
    found = dondata.read(att, extra)
    for key in keys:
        if key in speakers:
            continue
        q, f = key.split("-", 1)
        offer = f == "description"
        who = (found.givers if offer else found.enders).get(int(q), ())
        if who:
            speakers[key] = min(who)
            if len(who) > 1:
                others[key] = sorted(set(who) - {min(who)})
        elif int(q) in (found.item_starts if offer else found.object_ends):
            speakers[key] = voice.NARRATOR
        else:
            continue
        sources[key] = dondata.source(commit)


def _follow_collector(
    speakers: dict[str, int | str], others: dict[str, list[int]], sources: dict[str, str],
    keys: Iterable[str], root: Path,
) -> None:
    """Gives each quest line of `keys` the NPCs players' own quest windows showed for it (the Collector's
    quest NPCs, data/voice/quest-npcs.jsonl). It is what the game itself said, so it is applied last and wins
    over every other source. A line's main speaker stays when it is one of the NPCs seen, else the lowest id
    seen leads; the other NPCs seen, and a creature another source named, are kept as its other speakers, so
    a quest several NPCs give plays each one's own voice. A row that names no creature is left out."""
    seen: dict[str, dict[int, str]] = {}
    for r in read_rows(voice_dir(root) / "quest-npcs.jsonl"):
        who, quest, field = r.get("creature"), r.get("quest"), r.get("field")
        if isinstance(who, int) and isinstance(quest, int) and isinstance(field, str):
            source = (r.get("provenance") or {}).get("source", "collector")
            seen.setdefault(voice.quest_key(quest, field), {})[who] = source
    for key in keys:
        found = seen.get(key)
        if not found:
            continue
        before = speakers.get(key)
        main = before if before in found else min(found)
        rest = {*others.get(key, ()), *found, *([before] if isinstance(before, int) else [])} - {main}
        speakers[key], sources[key] = main, found[main]
        if rest:
            others[key] = sorted(rest)
        else:
            others.pop(key, None)


def _conditional_speakers(  # noqa: PLR0913 - the cache, the scope, and what is known of each quest's offer
    path: Path, quests: set[int], starters: dict[int, list[int]], objects: set[int],
    offers: dict[str, int | str], shipped_keys: set[str], have: set[str],
) -> dict[str, tuple[int | str, int]]:
    """{pack key: (speaker, cache build)} for the scoped quests' conditional descriptions that ship: the giver
    the cache names, else whoever says the quest's own offer after every source (`offers`, by quest key), else
    the quest's lowest starter, else the narrator when an object or item starts the quest. Another wording of
    an offer nobody names has no entry: it is not voiced."""
    cache = wdb.read_quests(path)
    out: dict[str, tuple[int | str, int]] = {}
    for q in cache.quests:
        if q.id not in quests:
            continue
        for _, giver, en in q.conditional:
            k = voice.gossip_id(en or "")
            key = voice.gossip_key(k)
            if not en or k not in shipped_keys or key in have or key in out:
                continue
            who = (giver or offers.get(voice.quest_key(q.id, "description"))
                   or min(starters.get(q.id, []), default=None)
                   or (voice.NARRATOR if q.id in objects else None))
            if who:
                out[key] = (who, cache.build)
    return out


def _has_english(root: Path, quest: int, field: str) -> bool:
    return any(
        ln["id"] == quest and ln["field"] == field for ln in Store(root, english=True).load("quest")
    )


def run_speakers(a: argparse.Namespace) -> int:
    root = data_root()
    today = datetime.date.today().isoformat()
    speakers, report = build_tables(
        root, Path(a.vmangos), a.commit, a.scope, today, Path(a.wdb) if a.wdb else None,
        (Path(a.forever_vo), a.forever_vo_commit) if a.forever_vo else None,
        (Path(a.spoken), a.spoken_commit) if a.spoken else None,
        (Path(a.dondata) / dondata.ATT_FILE, Path(a.dondata) / dondata.EXTRA_FILE, a.dondata_commit)
        if a.dondata else None,
    )
    d = voice_dir(root)
    speakers = _keep_date(speakers, read_rows(d / "speakers.jsonl"), "key")
    write_rows(d / "speakers.jsonl", speakers)
    narrator = [r["key"] for r in speakers if r["speaker"] == voice.NARRATOR]
    creatures = {c for r in speakers for c in (r["speaker"], *r.get("others", ())) if isinstance(c, int)}
    several = sum("others" in r for r in speakers)
    print(f"voice speakers: {len(speakers)} lines, {len(creatures)} creatures,")
    print(f"voice speakers: {len(narrator)} narrator lines")
    print(f"voice speakers: {several} lines with several speakers")
    for name in ("quest", "conflict", "missing", "conditional"):
        for item in report.get(name, []):
            print(f"voice speakers: {name}: {item}")
    return 0


def in_scope(rows: list[dict[str, Any]], scope: str) -> list[dict[str, Any]]:
    """The speakers rows a scope voices: its quests' fields, and the NPC talk of its quests' givers and enders
    and of its own creatures. `all` keeps every row."""
    cfg = voice.SCOPES[scope]
    if cfg["quests"] is None:
        return rows
    quests = set(cfg["quests"])
    quest_rows = [r for r in rows if r["key"][0].isdigit() and int(r["key"].split("-", 1)[0]) in quests]
    # creatures only: the narrator reads lines all over the game, none of them this scope's NPC talk
    who = set(cfg["creatures"]) | {
        c for r in quest_rows for c in (r["speaker"], *r.get("others", ())) if isinstance(c, int)
    }
    talk = [
        r for r in rows
        if not r["key"][0].isdigit() and any(c in who for c in (r["speaker"], *r.get("others", ())))
    ]
    return sorted(quest_rows + talk, key=lambda r: r["key"])


def run(argv: Sequence[str]) -> int:
    verb = list(argv[:1])
    # the other verbs live in their own modules, each with its own `run`; some take the verb, some not
    own = {"profiles": ("voice_cast", "run_profiles", 1), "sets-page": ("voice_sets_page", "run", 1),
           "sets": ("voice_sets", "run", 1), "displays": ("voice_displays", "run", 1),
           "audition": ("voice_audition", "run", 1),
           **{v: ("voice_make", "run", 0)
              for v in ("cast", "plan", "generate", "status", "record-hashes", "export", "relevel", "owed")},
           "speed": ("voice_make", "run_speed", 1),
           "time": ("voice_time", "run", 1),
           "reencode": ("voice_reencode", "run", 1),
           **{v: ("voice_kana", "run", 0) for v in ("kana", "kana-import")},
           **{v: ("voice_store", "run", 0) for v in ("levels", "store-sync")},
           **{v: ("voice_ship", "run", 0) for v in ("pack", "release", "inputs")}}
    if verb and verb[0] in own:
        import importlib

        module, fn, skip = own[verb[0]]
        return getattr(importlib.import_module(f"wfj.cmd.{module}"), fn)(argv[skip:])
    p = argparse.ArgumentParser(prog="wfj voice")
    sub = p.add_subparsers(dest="cmd", required=True)
    sp = sub.add_parser("speakers")
    sp.add_argument("--vmangos", required=True)
    sp.add_argument("--commit", required=True)
    sp.add_argument("--scope", default="all", choices=sorted(voice.SCOPES))
    sp.add_argument("--wdb", help="the pinned quest cache, for conditional descriptions")
    sp.add_argument("--forever-vo", help="forever-vo, pinned: who speaks quests the database lacks")
    sp.add_argument("--forever-vo-commit", default="")
    sp.add_argument("--spoken", help="Spoken's corpus.json.gz: the creature it gives a quest line speaks it")
    sp.add_argument("--spoken-commit", default="")
    sp.add_argument("--dondata", help="the folder of DonData's two quest files: who gives and takes a quest "
                    "no other source names")
    sp.add_argument("--dondata-commit", default="")
    a = p.parse_args(list(argv))
    try:
        return run_speakers(a)
    except (ValueError, vmangos.VmangosError, wdb.WdbError) as e:
        print(f"voice {a.cmd}: {e}", file=sys.stderr)
        return 1
