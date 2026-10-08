"""wfj voice: Japanese voice over, made locally (ADR-061, ADR-062; docs/systems/voice.md, runbook
docs/operations/voice.md). This module builds who speaks each line; the casting verbs are in `voice_cast`,
the file verbs (cast, plan, generate, status) in `voice_make`, the shipping verbs (pack, release) in
`voice_ship`.

  speakers --vmangos FILE --commit SHA [--scope all] [--wdb questcache.wdb]
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
from collections.abc import Sequence
from pathlib import Path
from typing import Any

from wfj.core import voice
from wfj.emit.lua_writer import shipped
from wfj.io import forever_vo, vmangos, wdb
from wfj.io.jsonl_store import Store, dumps
from wfj.paths import data_root

# The research doc's character counts: the quest and gossip text forever-vo voices, and everything
FULL_SCOPES = {"quest and gossip text": 3_880_000, "everything": 4_650_000}
LAME = ("lame", "-m", "m", "--resample", "22.05", "-b", "32", "--cbr", "-t", "--quiet")


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


def build_tables(
    root: Path, db: Path, commit: str, scope: str, today: str, wdb_path: Path | None = None,
    captures: tuple[Path, str] | None = None,
) -> tuple[list[dict[str, Any]], dict[str, list[str]]]:
    """(speakers rows, report) for the scope. A speakers row names the line's main speaker and,
    when several creatures say it, the `others` (each may be cast to a voice of its own). With `wdb_path`
    (the pinned quest cache) a quest's conditional descriptions, keyed by their English (ADR-054), are read
    by the giver the cache names, else by the quest's starter."""
    cfg = voice.SCOPES[scope]
    whole = cfg["quests"] is None
    src = f"vmangos@{commit}"
    store, english_store = Store(root), Store(root, english=True)
    quest_lines = store.load("quest")
    if whole:
        starters, objects, enders = vmangos.read_all_quest_speakers(db)
        quest_keys = voice.shipped_quest(quest_lines, None)
        quests = {int(k.split("-", 1)[0]) for k in quest_keys}
    else:
        quests = set(cfg["quests"])
        starters, objects, enders = vmangos.read_quest_speakers(db, quests)
        quest_keys = voice.shipped_quest(quest_lines, quests)
    others: dict[str, list[int]] = {}
    q_speakers, q_problems = voice.quest_speakers(quest_keys, starters, objects, enders, others)
    # a quest the open database lacks (one Forever added): who the players' captures saw in the window
    captured_src: dict[str, str] = {}
    if captures is not None:
        seen = forever_vo.read_quest_speakers(captures[0])
        for key, sp in q_speakers.items():
            q, f = key.split("-", 1)
            who = voice.captured_speaker(seen.get((int(q), f), []))
            if sp == voice.NARRATOR and who is not None:
                q_speakers[key] = who
                captured_src[key] = f"forever-vo@{captures[1]}"
        q_problems = [p for p in q_problems if p.split(":", 1)[0] not in captured_src]
    creatures = {c for q in quests for c in (*starters.get(q, ()), *enders.get(q, ()))}
    creatures |= {s for s in q_speakers.values() if isinstance(s, int)}
    creatures |= vmangos.read_gossip_creatures(db) if whole else set(cfg["creatures"])
    gossip_shipped = {ln["id"] for ln in store.load("gossip") if shipped(ln)}
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
        conditional = _conditional_speakers(wdb_path, quests, starters, gossip_shipped, have)
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


def _conditional_speakers(
    path: Path, quests: set[int], starters: dict[int, list[int]], shipped_keys: set[str], have: set[str]
) -> dict[str, tuple[int | str, int]]:
    """{pack key: (speaker, cache build)} for the scoped quests' conditional descriptions that ship: the giver
    the cache names, else the quest's lowest starter, else the narrator."""
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
            who = giver or min(starters.get(q.id, []), default=None)
            out[key] = (who if who else voice.NARRATOR, cache.build)
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
    if verb == ["profiles"]:
        from wfj.cmd import voice_cast  # the casting verbs and the file verbs live in their own modules

        return voice_cast.run_profiles(argv[1:])
    if verb == ["audition"]:
        from wfj.cmd import voice_audition

        return voice_audition.run(argv[1:])
    if verb and verb[0] in ("cast", "plan", "generate", "status"):
        from wfj.cmd import voice_make

        return voice_make.run(argv)
    if verb and verb[0] in ("levels", "store-sync"):
        from wfj.cmd import voice_store

        return voice_store.run(argv)
    if verb and verb[0] in ("pack", "release", "inputs"):
        from wfj.cmd import voice_ship

        return voice_ship.run(argv)
    p = argparse.ArgumentParser(prog="wfj voice")
    sub = p.add_subparsers(dest="cmd", required=True)
    sp = sub.add_parser("speakers")
    sp.add_argument("--vmangos", required=True)
    sp.add_argument("--commit", required=True)
    sp.add_argument("--scope", default="all", choices=sorted(voice.SCOPES))
    sp.add_argument("--wdb", help="the pinned quest cache, for conditional descriptions")
    sp.add_argument("--forever-vo", help="forever-vo, pinned: who speaks quests the database lacks")
    sp.add_argument("--forever-vo-commit", default="")
    a = p.parse_args(list(argv))
    try:
        return run_speakers(a)
    except (ValueError, vmangos.VmangosError, wdb.WdbError) as e:
        print(f"voice {a.cmd}: {e}", file=sys.stderr)
        return 1
