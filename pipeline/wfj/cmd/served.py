"""wfj import english served: drop the English for ids the target client does not serve (ADR-034).

    wfj import english served <QuestV2.csv> <questcache.wdb> <ItemSparse.csv> <SpellName.csv>
        --keys <ui_keys.txt> [--map-cache <other client's questcache.wdb>]... [--dry-run]

The addon targets one client, Forever. Classic Era stays an input: its quest cache and tables fill English
under the union merge (ADR-020), so `data/english` also holds lines for ids Forever does not have, and
`generate` would ship their Japanese. `make import` / `make import-english` run this step last, after every
client, with Forever's folder. It removes from `data/english`:

- quest: a line whose quest id is in neither QuestV2 nor the Forever quest cache (every id the cache holds,
  placeholders included, was answered by the server). QuestV2 is kept as well as the cache: Forever lists
  quests its server has not answered yet, and their English (from Classic Era) keeps their Japanese shipping.
- area: keyed by the quest id, so kept exactly when its quest is.
- objective: keyed by QuestObjective id, not quest id, so each objective is mapped to its quest through the
  quest caches (Forever's first, then each `--map-cache`, Classic Era's) and kept when that quest is kept.
  An objective no cache maps is kept and counted: nothing proves Forever does not serve it.
- item: a line whose id is not in ItemSparse. spell: a line whose id is not in SpellName. Every field (the
  name, tooltip and aura text) is keyed by the item / spell id, so one rule covers them all.
- ui: a line whose English `src` is not the Forever tables' stamp (`<src>@<build>` from the folder's
  `tables-source.txt`). Under the union merge Forever's line wins wherever Forever has the key, so a line
  still stamped by another client is a key no Forever table provides. A line whose key has left
  `ui_keys.txt` goes too: the curated list is what the dictionary is, and the union merge would otherwise
  keep the English of a key nothing imports any more.

Every other kind (book, gossip, unit) and every `data/<kind>` Japanese line is untouched; a Japanese line
whose English is gone is `no_english_id` at the next `wfj check` and not generated, and ships again when a
later harvest lists its id. The three CSVs must carry one stamp, and the cache's build must be that stamp's
build. A missing or unreadable input, or a kind that would lose every line, stops the step before anything is
written. Idempotent.
"""

from __future__ import annotations

import argparse
from collections.abc import Callable
from pathlib import Path
from typing import Any

from wfj.io import tables_stamp, wago, wdb
from wfj.io.jsonl_store import Store
from wfj.paths import data_root

KINDS = ("quest", "area", "objective", "item", "spell", "ui")


def add_parser(esub: Any) -> None:
    sv = esub.add_parser("served", help="drop English for ids the target client (Forever) does not serve")
    sv.add_argument("questv2_csv", help="the target client's QuestV2.csv")
    sv.add_argument("questcache", help="the target client's questcache.wdb")
    sv.add_argument("item_csv", help="the target client's ItemSparse.csv")
    sv.add_argument("spell_csv", help="the target client's SpellName.csv")
    sv.add_argument("--keys", required=True, metavar="TXT", help="pipeline/ui_keys.txt: the curated ui keys")
    sv.add_argument(
        "--map-cache",
        action="append",
        default=[],
        metavar="WDB",
        help="another client's questcache.wdb, read only to map an objective id to its quest",
    )
    sv.add_argument("--dry-run", action="store_true", help="print the counts, write nothing")
    sv.set_defaults(fn=run_served)


# The client tables ui English is read from (wago-ui: strings, item subclasses, enchantments, spell subtexts
# and the text-family tables).
UI_TABLES = ("GlobalStrings", "ItemSubClass", "SpellItemEnchantment", "Spell", *wago.FAMILY_TABLES)


def _stamp(csvs: list[Path]) -> str:
    """The one `<src>@<build>` the CSVs carry; ValueError when one is unstamped or they differ."""
    stamps = {}
    for csv in csvs:
        got = tables_stamp.read(csv.parent).get(tables_stamp.table_of(csv))
        if got is None:
            raise ValueError(f"served: {csv}: no source stamp in {csv.parent / tables_stamp.FILE}")
        stamps[csv.name] = got
    if len(set(stamps.values())) != 1:
        raise ValueError(f"served: the target tables carry different stamps: {stamps}")
    label = next(iter(stamps.values()))
    # the ui rule keeps lines stamped `label`: the tables ui English comes from must carry the same stamp,
    # or a re-extract of one of them at another build would drop its keys here
    folder = tables_stamp.read(csvs[0].parent)
    other = {t: folder.get(t) for t in UI_TABLES if folder.get(t) != label}
    if other:
        raise ValueError(f"served: the ui source tables do not carry {label}: {other}")
    return label


def _objective_quests(target: wdb.WdbCache, others: list[wdb.WdbCache]) -> tuple[dict[int, int], int]:
    """objective id → quest id, the target cache first; (map, objectives another cache puts under another
    quest: the target's mapping wins, the stated rule, and they are counted)."""
    out: dict[int, int] = {}
    for cache in (target, *others):
        for q in cache.quests:
            for oid, _ in q.objective_texts:
                out.setdefault(oid, q.id)
    disagree = 0
    for cache in others:
        for q in cache.quests:
            for oid, _ in q.objective_texts:
                disagree += out[oid] != q.id
    return out, disagree


def run_served(a: argparse.Namespace) -> int:
    csvs = [Path(a.questv2_csv), Path(a.item_csv), Path(a.spell_csv)]
    cache_path = Path(a.questcache)
    for p in [*csvs, cache_path, *map(Path, a.map_cache)]:
        if not p.is_file():
            raise ValueError(f"served: {p} is missing; nothing written")
    label = _stamp(csvs)
    cache = wdb.read_quests(cache_path)
    build = label.split("@", 1)[1]
    if build.rsplit(".", 1)[-1] != str(cache.build):
        raise ValueError(f"served: {cache_path.name} is build {cache.build}, the tables are {label}")
    others = [wdb.read_quests(Path(p)) for p in a.map_cache]
    questv2 = wago.read_ids(csvs[0])
    quests = questv2 | {q.id for q in cache.quests} | set(cache.placeholders)
    items, spells = wago.read_ids(csvs[1]), wago.read_ids(csvs[2])
    objective_quest, disagree = _objective_quests(cache, others)
    unmapped: set[int] = set()

    def objective_kept(ln: dict[str, Any]) -> bool:
        quest = objective_quest.get(ln["id"])
        if quest is None:
            unmapped.add(ln["id"])
            return True
        return quest in quests

    keep: dict[str, Callable[[dict[str, Any]], bool]] = {
        "quest": lambda ln: ln["id"] in quests,
        "area": lambda ln: ln["id"] in quests,  # keyed by the quest id, kept with its quest
        "objective": objective_kept,
        "item": lambda ln: ln["id"] in items,
        "spell": lambda ln: ln["id"] in spells,
        "ui": lambda ln: ln["src"] == label and ln["id"] in ui_keys,
    }
    store = Store(data_root(), english=True)
    ui_english = {ln["id"]: ln["en"] for ln in store.load("ui")}
    ui_keys = set(wago.expand_keys(wago.read_keys(Path(a.keys)), ui_english))
    result: dict[str, list[dict[str, Any]]] = {}
    removed: dict[str, int] = {}
    report = []
    for kind in KINDS:  # everything is read and decided before anything is written
        lines = store.load(kind)
        # A collector dump is not replayed by `make import`: its English is never dropped here (it could not
        # be rebuilt), and `check` does not consult it (ADR-013)
        kept = [ln for ln in lines if str(ln["src"]).startswith("collector@") or keep[kind](ln)]
        if lines and not kept:  # the wrong folder, a truncated table: never empty a kind
            raise ValueError(f"served: every {kind} line would be removed; check the target tables")
        result[kind], removed[kind] = kept, len(lines) - len(kept)
        gone = len({ln["id"] for ln in lines}) - len({ln["id"] for ln in kept})
        report.append(f"served {kind}: kept {len(kept)} lines, removed {len(lines) - len(kept)} ({gone} ids)")
    if not a.dry_run:
        for kind in KINDS:
            if removed[kind]:
                store.save(kind, result[kind])
    tag = " [dry run: nothing written]" if a.dry_run else ""
    print(
        f"served{tag}: target {label} · {len(questv2)} QuestV2 ids + {len(quests) - len(questv2)} cached "
        f"only · {len(items)} items · {len(spells)} spells"
    )
    print("\n".join(report))
    if unmapped:
        print(f"served objective: {len(unmapped)} ids no quest cache maps to a quest, kept")
    if disagree:
        print(f"served objective: {disagree} filed under another quest by another cache; the target wins")
    return 0
