"""Re-stamp the English hashes after a change to normalize_v1, keeping every translation and reading.

    python -m wfj.dev.rehash_english [--dry-run]

Every English line's `hash` is recomputed from its `en` with the current normalize_v1. Where it changed:

- a line keyed by its hash (gossip: the id is the hash) moves to the new key, with every translation variant
  and its readings, so a translation follows its English instead of being orphaned;
- every translation variant whose recorded English hash was the old one is re-stamped to the new one: the text
  did not change, only how it is hashed, so the line stays fresh.

A new key that is already taken by another English line is a collision: the two are the same text from two
sources. The line already at the new key stays (it is the text as the client shows it), and the moving line is
dropped with its translation variants and readings; each drop is printed. A moving line with a hand-written
variant stops the run with nothing written: a hand-written translation is never dropped without a ruling.
Text, provenance and statuses are otherwise not touched; `make check` and `make generate` run after."""

from __future__ import annotations

import argparse
from typing import Any

from wfj.core import decisions
from wfj.core.hashing import key as hash_key
from wfj.core.normalize import normalize_for
from wfj.io.jsonl_store import Store
from wfj.paths import data_root

# English types whose id is the hash of the English (the key the addon computes from the live text).
HASH_KEYED = ("gossip",)


def plan(root) -> tuple[dict[str, dict[tuple[Any, str], tuple[str, str]]], dict[str, set[Any]], list[str]]:
    """{type: {(id, field): (old hash, new hash)}} for every English line whose hash changes, the moving lines to
    drop because their new key is taken ({type: {old id}}), and the collisions that stop the run."""
    store_en, store = Store(root, english=True), Store(root)
    changes: dict[str, dict[tuple[Any, str], tuple[str, str]]] = {}
    drop: dict[str, set[Any]] = {}
    problems: list[str] = []
    for d in sorted(p for p in store_en.root.iterdir() if p.is_dir()):
        type_ = d.name
        lines = store_en.load(type_)
        taken = {line["id"] for line in lines}
        hand = {line["id"] for line in store.load(type_) if decisions.is_hand_written(line.get("provenance", {}))}
        for line in lines:
            new = hash_key(normalize_for(type_, line["en"]))
            if new == line.get("hash"):
                continue
            if type_ in HASH_KEYED and new != line["id"] and new in taken:
                if line["id"] in hand:
                    problems.append(f"{type_} {line['id']}: its new key {new} is taken, and it has a hand-written"
                                    " translation")
                drop.setdefault(type_, set()).add(line["id"])
                continue
            changes.setdefault(type_, {})[(line["id"], line["field"])] = (line["hash"], new)
    return changes, drop, problems


def apply(root, changes: dict[str, dict[tuple[Any, str], tuple[str, str]]], drop: dict[str, set[Any]], *,
          dry_run: bool) -> dict[str, int]:
    """Rewrite the English, translation and reading stores. → counts of what changed"""
    counts = {"english": 0, "rekeyed": 0, "restamped": 0, "readings": 0, "dropped": 0}
    store_en, store, readings = Store(root, english=True), Store(root), Store(root / "reading")
    for type_ in sorted(set(changes) | set(drop)):
        by_line = changes.get(type_, {})
        gone = drop.get(type_, set())
        rekey = {k[0]: v[1] for k, v in by_line.items() if type_ in HASH_KEYED and k[0] == v[0]}
        old_hash = {k: v[0] for k, v in by_line.items()}
        new_hash = {k: v[1] for k, v in by_line.items()}

        english = store_en.load(type_)
        counts["dropped"] += sum(1 for line in english if line["id"] in gone)
        english = [line for line in english if line["id"] not in gone]
        for line in english:
            k = (line["id"], line["field"])
            if k in new_hash:
                line["hash"] = new_hash[k]
                if line["id"] in rekey:
                    line["id"] = rekey[line["id"]]
                counts["english"] += 1

        lines = [line for line in store.load(type_) if line["id"] not in gone]
        for line in lines:
            k = (line["id"], line["field"])
            eng = line.get("english")
            if k in old_hash and isinstance(eng, dict) and eng.get("hash") == old_hash[k]:
                eng["hash"] = new_hash[k]
                counts["restamped"] += 1
            if line["id"] in rekey:
                line["id"] = rekey[line["id"]]
                counts["rekeyed"] += 1

        read = [line for line in (readings.load(type_) if readings.dir(type_).is_dir() else []) if line["id"] not in gone]
        for line in read:
            if line["id"] in rekey:
                line["id"] = rekey[line["id"]]
                counts["readings"] += 1

        if not dry_run:
            emptied = bool(gone)  # dropping a duplicate may empty a type in a small store
            store_en.save(type_, english, allow_empty=emptied)
            store.save(type_, lines, allow_empty=emptied)
            if read or (emptied and readings.dir(type_).is_dir()):
                readings.save(type_, read, allow_empty=emptied)
    return counts


def run(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="wfj.dev.rehash_english", description=__doc__.split("\n\n")[0])
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args(argv)
    root = data_root()
    changes, drop, problems = plan(root)
    for type_, by_line in sorted(changes.items()):
        print(f"rehash: {type_}: {len(by_line)} English lines change hash")
    for type_, ids in sorted(drop.items()):
        for id_ in sorted(ids):
            print(f"rehash: {type_} {id_}: dropped, the same text is already a line at its new key")
    if problems:
        for p in problems:
            print(f"rehash: collision: {p}")
        print("rehash: nothing written")
        return 1
    counts = apply(root, changes, drop, dry_run=args.dry_run)
    print(("rehash (dry run): " if args.dry_run else "rehash: ") + " · ".join(f"{k} {v}" for k, v in counts.items()))
    return 0


if __name__ == "__main__":
    raise SystemExit(run())
