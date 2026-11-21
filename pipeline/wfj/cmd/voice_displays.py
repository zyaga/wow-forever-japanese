"""`wfj voice displays`: each speaking creature's display id → data/voice/displays.jsonl (ADR-089).

The voice panel draws a speaker who is not on screen (a quest replayed from the quest log) from a display id,
which addresses the client's own model data, instead of from the creature cache every client build empties.
This table gives it one for every creature data/voice/speakers.jsonl names: the first display of the newest
copied Forever creature cache that holds the creature (the client's own truth), else VMaNGOS's first display.
Rows are additive: a row no source holds any more is kept, a row a creature cache gave is never replaced by
VMaNGOS, and a row whose display and source are unchanged keeps its date. A copied cache whose build has no
pinned layout yet is left out with a message, so the rest of the table can still be rebuilt.
"""

from __future__ import annotations

import argparse
import datetime
import sys
from collections import Counter
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import Any

from wfj.io import creature_cache, vmangos
from wfj.io.jsonl_store import dumps, read_jsonl
from wfj.paths import data_root

DISPLAYS = Path("voice") / "displays.jsonl"


def cache_source(build: int) -> str:
    return f"creaturecache@{build}"


QUEST_NPCS = Path("voice") / "quest-npcs.jsonl"
SEXES = ("male", "female")
QUEST_NPC_FIELDS = ("description", "progress", "completion")
# a display the client itself named: its creature cache, or the NPC a player's quest window showed
_CLIENT_SOURCES = ("creaturecache@", "collector@")


def seen_displays(npcs: Sequence[Mapping[str, Any]]) -> dict[int, tuple[str, int]]:
    """creature → (source, display) from the quest NPC rows the players' sends gave: the display a player's
    client drew the NPC with. Where sends disagree the display most rows name wins, the lowest on a tie."""
    counts: dict[int, Counter[int]] = {}
    source: dict[tuple[int, int], str] = {}
    for r in npcs:
        if r.get("display"):
            c, d = int(r["creature"]), int(r["display"])
            counts.setdefault(c, Counter())[d] += 1
            source.setdefault((c, d), str(r["provenance"]["source"]))
    out = {}
    for c, by in counts.items():
        d = min(by, key=lambda k: (-by[k], k))
        out[c] = (source[(c, d)], d)
    return out


def seen_sexes(npcs: Sequence[Mapping[str, Any]]) -> dict[int, tuple[str, str]]:
    """creature → (sex, source) from the quest NPC rows, only where every send that names a sex for the
    creature names the same one: an NPC shown as both is a judgement, not a fact."""
    by: dict[int, dict[str, str]] = {}
    for r in npcs:
        if r.get("sex") in SEXES:
            by.setdefault(int(r["creature"]), {}).setdefault(str(r["sex"]), str(r["provenance"]["source"]))
    return {c: next(iter(sexes.items())) for c, sexes in by.items() if len(sexes) == 1}


def quest_npc_problems(npcs: Sequence[Mapping[str, Any]]) -> list[str]:
    """What is wrong with data/voice/quest-npcs.jsonl, one line each: a row is a quest line and the NPC a
    player's quest window showed for it, numbers only, from a collector send."""
    out, seen = [], set()
    for n, r in enumerate(npcs, 1):
        where = f"voice: quest-npcs.jsonl row {n}"
        ids = [r.get(k) for k in ("quest", "creature")]
        if not all(isinstance(v, int) and not isinstance(v, bool) and v > 0 for v in ids):
            out.append(f"{where}: quest and creature must be positive numbers")
            continue
        if r.get("field") not in QUEST_NPC_FIELDS:
            out.append(f"{where}: field {r.get('field')!r} is not one of {', '.join(QUEST_NPC_FIELDS)}")
        if "sex" in r and r["sex"] not in SEXES:
            out.append(f"{where}: sex {r['sex']!r} is not male or female")
        if "display" in r and not (isinstance(r["display"], int) and not isinstance(r["display"], bool)
                                   and r["display"] > 0):
            out.append(f"{where}: display must be a positive number")
        prov = r.get("provenance")
        if not (isinstance(prov, dict) and str(prov.get("source", "")).startswith("collector@")
                and prov.get("imported")):
            out.append(f"{where}: provenance must name a collector send and the day it was imported")
        if set(r) - {"quest", "field", "creature", "sex", "display", "provenance"}:
            out.append(f"{where}: holds more than numbers and provenance")
        key = (r["quest"], r.get("field"), r["creature"])
        if key in seen:
            out.append(f"{where}: quest {key[0]} {key[1]} names creature {key[2]} twice")
        seen.add(key)
    return out


def display_rows(who: set[int], caches: Sequence[tuple[int, dict[int, list[int]]]], vm: dict[int, list[int]],
                 vm_source: str, old: list[dict[str, Any]], today: str,
                 seen: Mapping[int, tuple[str, int]] | None = None) -> list[dict[str, Any]]:
    """{"creature", "display", provenance} per creature of `who` with a display id, sorted by creature. The
    newest creature cache that holds the creature wins, then the display a player's quest window showed
    (`seen`, from `seen_displays`), then VMaNGOS; a display the client named is never replaced by VMaNGOS."""
    newest_first = sorted(caches, key=lambda c: c[0], reverse=True)
    prev = {int(r["creature"]): r for r in old}
    rows = []
    for c in sorted(who | set(prev)):
        found = next(((cache_source(b), d[c][0]) for b, d in newest_first if d.get(c)), None)
        if found is None and seen and c in seen:
            found = seen[c]
        p = prev.get(c)
        from_cache = p and str(p["provenance"].get("source", "")).startswith(_CLIENT_SOURCES)
        if found is None and vm.get(c) and not from_cache:
            found = (vm_source, vm[c][0])
        if found is None:
            if p:
                rows.append(p)
            continue
        source, display = found
        same = p and p["display"] == display and p["provenance"].get("source") == source
        rows.append({"creature": c, "display": display,
                     "provenance": p["provenance"] if same else {"source": source, "imported": today}})
    return rows


def run(argv: Sequence[str]) -> int:
    from wfj.cmd import voice_cast

    p = argparse.ArgumentParser(prog="wfj voice displays")
    p.add_argument("--creatures", required=True, help="the folder of copied creature caches (<build>.wdb)")
    p.add_argument("--vmangos", required=True)
    p.add_argument("--commit", required=True)
    a = p.parse_args(list(argv))
    root = data_root()
    folder = Path(a.creatures)
    if not folder.is_dir():
        print(f"voice displays: no creature cache folder {folder} (make creature-copy fills it)",
              file=sys.stderr)
        return 1
    try:
        caches = []
        for f in sorted(folder.glob("*.wdb")):
            build = creature_cache.read_build(f)
            try:
                creature_cache.layout_for(build)
            except creature_cache.CreatureCacheError:
                print(f"voice displays: {f.name} left out: build {build} has no pinned creature layout yet "
                      "(check it and pin it in io/creature_cache.LAYOUTS)", file=sys.stderr)
                continue
            caches.append(creature_cache.read_displays(f))
        who = voice_cast.speaking(root)
        vm = {c: info["displays"] for c, info in vmangos.read_creatures(Path(a.vmangos), who).items()}
        rows = display_rows(who, caches, vm, f"vmangos@{a.commit}", read_jsonl(root / DISPLAYS),
                            datetime.date.today().isoformat(), seen_displays(read_jsonl(root / QUEST_NPCS)))
    except (creature_cache.CreatureCacheError, vmangos.VmangosError) as e:
        print(f"voice displays: {e}", file=sys.stderr)
        return 1
    (root / DISPLAYS).write_text("".join(dumps(r) + "\n" for r in rows), encoding="utf-8")
    from_cache = sum(1 for r in rows if r["provenance"]["source"].startswith("creaturecache@"))
    print(f"voice displays: {len(rows)} of {len(who)} speakers have a display id ({from_cache} from "
          f"{len(caches)} creature cache(s), the rest from VMaNGOS) → data/{DISPLAYS}")
    return 0
