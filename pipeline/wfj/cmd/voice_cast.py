"""wfj voice profiles build|export|import: who each speaking creature is, for voice casting (ADR-062;
docs/systems/voice.md, runbook docs/operations/voice.md).

  profiles build --vmangos FILE --commit SHA --client DIR
      Writes data/voice/profiles.jsonl: one row per creature that speaks a line in data/voice/speakers.jsonl,
      with what the client's display tables (DIR, `make tables-extract`) and VMaNGOS say (race, gender, the
      kind of being, a racial leader's role). Values from the casting pass and the rulings
      already in the file are kept (core/casting.build).
  profiles export --vmangos FILE --out DIR [--per N]
      Writes the casting pass's input: part-NN.jsonl files of the speakers that still need judgement, each
      with its name, title, creature type, what the tables say and up to three of its Japanese lines.
  profiles import --drafts FILE… --model ID --batch NAME
      Merges the pass's drafts into data/voice/profiles.jsonl (never over a table value or a ruling) and
      prints the speakers still owed an age.
"""

from __future__ import annotations

import argparse
import datetime
import json
import sys
from collections.abc import Sequence
from pathlib import Path
from typing import Any

from wfj.core import casting, voice
from wfj.emit.lua_writer import shipped
from wfj.io import creature_tables, vmangos
from wfj.io.jsonl_store import Store, dumps
from wfj.paths import data_root

PROFILES = "profiles.jsonl"
TYPE_NAMES = {
    1: "beast",
    2: "dragonkin",
    3: "demon",
    4: "elemental",
    5: "giant",
    6: "undead",
    7: "humanoid",
    8: "critter",
    9: "mechanical",
    10: "not specified",
}


def _rows(path: Path) -> list[dict[str, Any]]:
    if not path.is_file():
        return []
    with path.open(encoding="utf-8") as f:
        return [json.loads(raw) for raw in f if raw.strip()]


def _write(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(dumps(r) + "\n" for r in rows), encoding="utf-8")


def speaking(root: Path) -> set[int]:
    """Every creature data/voice/speakers.jsonl names, main speaker or other."""
    return {
        c
        for r in _rows(root / "voice" / "speakers.jsonl")
        for c in (r["speaker"], *r.get("others", ()))
        if isinstance(c, int)
    }


def build(root: Path, db: Path, commit: str, client: Path, today: str) -> tuple[list[dict[str, Any]], dict]:
    who = speaking(root)
    creatures = vmangos.read_creatures(db, who)
    displays, client_src = creature_tables.read(client)
    vm_genders = vmangos.read_creature_genders(db, who)
    vm_src = f"vmangos@{commit}"
    table_facts = {
        c: casting.facts(creatures.get(c), displays, client_src, vm_src, vm_genders.get(c)) for c in who
    }
    rows = casting.build(who, table_facts, _rows(root / "voice" / PROFILES), today)
    stats = {
        "speakers": len(who),
        "not in the database": sum(c not in creatures for c in who),
        **{f"{f} from the tables": sum(f in table_facts[c] for c in who) for f in casting.FIELDS},
        "still need judgement": sum(bool(casting.needs_judgement(r)) for r in rows),
    }
    return rows, stats


def _lines_by_speaker(root: Path) -> dict[int, list[str]]:
    """creature → the shipped Japanese of the lines it speaks, longest first (the pass reads up to three)."""
    store = Store(root)
    ja = {voice.quest_key(ln["id"], ln["field"]): ln["ja"] for ln in store.load("quest") if shipped(ln)}
    ja.update({voice.gossip_key(ln["id"]): ln["ja"] for ln in store.load("gossip") if shipped(ln)})
    out: dict[int, list[str]] = {}
    for r in _rows(root / "voice" / "speakers.jsonl"):
        for c in (r["speaker"], *r.get("others", ())):
            if isinstance(c, int) and r["key"] in ja:
                out.setdefault(c, []).append(ja[r["key"]])
    return {c: sorted(set(v), key=lambda t: (-len(t), t)) for c, v in out.items()}


def export(root: Path, db: Path, out: Path, per: int) -> int:
    """The casting pass's input files. → how many speakers were exported."""
    rows = _rows(root / "voice" / PROFILES)
    want = [r for r in rows if casting.needs_judgement(r)]
    creatures = vmangos.read_creatures(db, {r["creature"] for r in want})
    names = {r["id"]: r["en"] for r in Store(root, english=True).load("unit") if r.get("field") == "name"}
    lines = _lines_by_speaker(root)
    items = []
    for r in want:
        c = r["creature"]
        cr = creatures.get(c) or {}
        items.append(
            {
                "creature": c,
                "name": cr.get("name") or names.get(c, ""),
                "title": cr.get("subname", ""),
                "type": TYPE_NAMES.get(cr.get("type", 0), "unknown"),
                "known": {
                    f: r[f]
                    for f in casting.FIELDS
                    if r.get(f) is not None and f not in casting.needs_judgement(r)
                },
                "lines": [t[:400] for t in lines.get(c, [])[:3]],
            }
        )
    out.mkdir(parents=True, exist_ok=True)
    for n in range(0, len(items), per):
        _write(out / f"part-{n // per + 1:02d}.jsonl", items[n : n + per])
    return len(items)


def import_drafts(root: Path, files: Sequence[Path], model: str, batch: str, today: str) -> list[str]:
    path = root / "voice" / PROFILES
    drafts = [d for f in files for d in _rows(f)]
    rows, problems = casting.merge_machine(_rows(path), drafts, model, batch, today)
    _write(path, rows)
    return problems


def run_profiles(argv: Sequence[str]) -> int:
    p = argparse.ArgumentParser(prog="wfj voice profiles")
    sub = p.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build")
    b.add_argument("--vmangos", required=True)
    b.add_argument("--commit", required=True)
    b.add_argument("--client", required=True, help="the client folder holding the display tables")
    e = sub.add_parser("export")
    e.add_argument("--vmangos", required=True)
    e.add_argument("--out", required=True)
    e.add_argument("--per", type=int, default=800)
    i = sub.add_parser("import")
    i.add_argument("--drafts", nargs="+", required=True)
    i.add_argument("--model", required=True)
    i.add_argument("--batch", required=True)
    a = p.parse_args(list(argv))
    root = data_root()
    today = datetime.date.today().isoformat()
    try:
        if a.cmd == "build":
            rows, stats = build(root, Path(a.vmangos), a.commit, Path(a.client), today)
            _write(root / "voice" / PROFILES, rows)
            print(f"voice profiles: {len(rows)} speakers → data/voice/{PROFILES}")
            for k, v in stats.items():
                print(f"voice profiles: {k}: {v}")
        elif a.cmd == "export":
            n = export(root, Path(a.vmangos), Path(a.out), a.per)
            print(f"voice profiles: {n} speakers to judge → {a.out}")
        else:
            problems = import_drafts(root, [Path(f) for f in a.drafts], a.model, a.batch, today)
            for pr in problems:
                print(f"voice profiles: {pr}")
            owed = casting.missing_age(_rows(root / "voice" / PROFILES))
            print(f"voice profiles: {len(problems)} problem(s); {len(owed)} speaker(s) still owed an age")
            return 1 if owed else 0
    except (ValueError, FileNotFoundError, vmangos.VmangosError) as e:
        print(f"voice profiles: {e}", file=sys.stderr)
        return 1
    return 0
