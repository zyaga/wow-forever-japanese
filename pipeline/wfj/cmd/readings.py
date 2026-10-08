"""wfj readings export|import: the batch path for whole-word readings
(ADR-036; docs/systems/readings.md).

  export --type quest|gossip|ui --ids FILE [--all] [--class machine|human|correction] --out BATCH.jsonl
      One row per shipped Japanese line of those ids that has no current reading (--all: every line):
      {"type", "id", "field", "ja", "ja_hash", "en"}. The model writes `words` onto each row. `en` is the
      line's current English (a batch input for the meanings: the game's word where a Japanese word
      translates it; never imported, never shipped), left out when the line has none; a line with no kanji and
      no kana (an English-only title) is not exported: there is nothing to annotate. --class keeps only the
      lines whose shipped variant has that provenance class (one quest id mixes human and machine fields,
      and their readings are written in separate batches).
  import BATCH.jsonl --model MODEL --batch NAME [--date YYYY-MM-DD] [--dry-run]
      Rows {"type", "id", "field", "ja_hash", "words"} (a row may keep "ja"; it is ignored). Each row is
      checked against the shipped Japanese (core/readings.word_problems); a row with a problem, or written
      for Japanese that has since changed, is rejected with its reason and nothing of it is written. Machine
      output replaces machine output; it never replaces a `correction` reading (kept and reported).
  import BATCH.jsonl --correction --by NAME --date YYYY-MM-DD [--note TEXT] [--dry-run]
      The rows fix readings already in the store. Each is written as a `correction` record
      (translator NAME, source correction@DATE, `corrects` = the source of the record it replaces); a row
      for a line that has no reading yet is rejected: there is nothing to correct.
  fill-repeats [--dry-run]
      Gives every word a line uses again its card at each place (core/readings.fill_repeats): the copy has
      the same reading and meaning. Only current readings change; their provenance stays. `import` does this
      for every row it writes, and `validate` fails on a reading that still misses one.
Follows `cmd/import_draft.py`'s batch pattern: a batch is a file, the store is the only thing written.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
from collections.abc import Sequence
from pathlib import Path
from typing import Any

from wfj.core import model, readings
from wfj.io.jsonl_store import Store, dumps
from wfj.paths import data_root

_BATCH_RE = re.compile(r"^[0-9A-Za-z._-]{4,64}$")


def reading_store(root: Path) -> Store:
    """`data/reading/<type>/<type>-NNNN.jsonl`: the same sharding and order as the translation store."""
    return Store(root / "reading")


def read_ids(path: Path, type_: str) -> list[int | str]:
    """One id per line (# comments and blank lines skipped): ints for quest, 16-hex keys for gossip, UI
    string keys as written for ui."""
    out: list[int | str] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        tok = raw.split("#", 1)[0].strip()
        if tok:
            if type_ == "ui":
                out.append(tok)
            else:
                out.append(tok.lower() if type_ in model.HASH_KEYED else int(tok))
    return out


def export_rows(
    root: Path, type_: str, ids: list[int | str], *, every: bool = False, klass: str | None = None
) -> list[dict[str, Any]]:
    lines = Store(root).load(type_)
    japanese = readings.shipped_japanese(lines)
    if klass is not None:
        japanese = {
            (ln["id"], ln["field"]): ln["ja"]
            for ln in lines
            if readings.shipped(ln) and ln["provenance"]["class"] == klass
        }
    have = {
        (r["id"], r["field"])
        for r in readings.check(type_, reading_store(root).load(type_), japanese)["current"]
    }
    english = {(ln["id"], ln["field"]): ln["en"] for ln in Store(root, english=True).load(type_)}
    rows = []
    for id_ in ids:
        for field in readings.TYPES[type_]:
            ja = japanese.get((id_, field))
            if (
                ja is not None
                and readings.annotatable(ja)
                and not readings.html_page(type_, ja)
                and not readings.holds_escape(ja)
                and (every or (id_, field) not in have)
            ):
                h = readings.ja_hash(ja)
                row: dict[str, Any] = {"type": type_, "id": id_, "field": field, "ja": ja, "ja_hash": h}
                en = english.get((id_, field))
                if isinstance(en, str):
                    row["en"] = en
                rows.append(row)
    return rows


def _well_formed(
    rows: list[dict[str, Any]], shape_prov: dict[str, Any], rejected: list[str]
) -> dict[str, dict[tuple[int | str, str], dict[str, Any]]]:
    """The batch rows whose shape is valid, as records by type and (id, field); every other row's problem
    goes in `rejected`."""
    incoming: dict[str, dict[tuple[int | str, str], dict[str, Any]]] = {}
    for n, row in enumerate(rows, 1):
        type_ = row.get("type") if isinstance(row, dict) else None
        if type_ not in readings.TYPES:
            rejected.append(f"row {n}: type must be one of {sorted(readings.TYPES)}")
            continue
        rec = {k: row.get(k) for k in ("id", "field", "ja_hash", "words")} | {"provenance": shape_prov}
        where = f"row {n} {type_} {rec['id']}/{rec['field']}"
        shape = readings.record_problems(type_, rec)
        if shape:
            rejected += [f"{where}: {x}" for x in shape]
            continue
        k = (rec["id"], rec["field"])
        if k in incoming.setdefault(type_, {}):
            rejected.append(f"{where}: the batch has this line twice")
            continue
        incoming[type_][k] = rec
    return incoming


def import_rows(
    root: Path, rows: list[dict[str, Any]], prov: dict[str, Any], *, dry_run: bool = False
) -> dict[str, Any]:
    """→ {"written": n, "rejected": [str], "kept": [str], "by_type": {type: n}}.
    Nothing is written on dry_run."""
    store = reading_store(root)
    rejected: list[str] = []
    kept: list[str] = []
    correcting = prov["class"] == "correction"
    # a correction's `corrects` is the replaced record's source, known only per row (below)
    shape_prov = prov | {"corrects": "readings@pending"} if correcting else prov
    incoming = _well_formed(rows, shape_prov, rejected)
    written = 0
    by_type: dict[str, int] = {}
    for type_, recs in sorted(incoming.items()):
        lines = Store(root).load(type_)
        japanese = readings.shipped_japanese(lines)
        by_key = {(ln["id"], ln["field"]): ln for ln in lines}
        existing = {(r["id"], r["field"]): r for r in store.load(type_)}
        merged = dict(existing)
        for k, rec in recs.items():
            where = f"{type_} {k[0]}/{k[1]}"
            ja = japanese.get(k)
            if ja is None:
                rejected.append(f"{where}: no shipped Japanese for this id and field")
                continue
            if rec["ja_hash"] != readings.ja_hash(ja):
                # words written for a stored variant that does not ship (a draft merged as a
                # conflict, e.g. behind a hand-written line) get their own reason
                ln = by_key.get(k) or {}
                variants = [ln, *ln.get("conflicts", [])] if ln else []
                if rec["ja_hash"] in {readings.ja_hash(v["ja"]) for v in variants}:
                    rejected.append(f"{where}: written for a variant that does not ship; the shipped line "
                                    "is another text; export it to write its readings")
                else:
                    rejected.append(f"{where}: written for Japanese that has since changed; export it again")
                continue
            bad = readings.word_problems(ja, rec["words"])
            if bad:
                rejected += [f"{where}: {x}" for x in bad]
                continue
            # a word the line uses twice gets its card both times, whatever the batch listed
            rec["words"] = readings.fill_repeats(ja, rec["words"])
            old = existing.get(k)
            if correcting:
                if old is None:
                    rejected.append(f"{where}: no reading to correct")
                    continue
                # a second correction the same day would name itself (`correction@D`); keep what the first
                # one corrected instead
                replaced = old["provenance"]
                same_day = replaced["source"] == prov["source"]
                corrects = replaced.get("corrects", replaced["source"]) if same_day else replaced["source"]
                rec["provenance"] = prov | {"corrects": corrects}
            # a correction protects only the Japanese it was written for: once that line is retranslated the
            # correction is stale and a new reading may replace it
            corrected = (
                old is not None
                and old.get("provenance", {}).get("class") == "correction"
                and old.get("ja_hash") == rec["ja_hash"]
            )
            if corrected and prov["class"] != "correction":
                kept.append(f"{where}: kept the correction reading")
                continue
            merged[k] = {key: rec[key] for key in readings.KEYS}
            written += 1
            by_type[type_] = by_type.get(type_, 0) + 1
        if not dry_run and by_type.get(type_):
            store.save(type_, merged.values())
    return {"written": written, "rejected": rejected, "kept": kept, "by_type": by_type}


def read_batch(path: Path) -> list[dict[str, Any]]:
    rows = []
    for n, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if raw.strip():
            row = json.loads(raw)
            if not isinstance(row, dict):
                raise ValueError(f"{path.name}:{n}: a batch row is a JSON object")
            rows.append(row)
    return rows


def fill_store(root: Path, *, dry_run: bool = False) -> dict[str, Any]:
    """Every current reading with a repeated word lacking a card, filled. → {"lines": n, "places": n,
    "by_type": {type: n}, "left": [str]} (left: a line the fill could not complete; reported, not written)."""
    store = reading_store(root)
    lines = places = 0
    by_type: dict[str, int] = {}
    left: list[str] = []
    for type_ in sorted(readings.TYPES):
        japanese = readings.shipped_japanese(Store(root).load(type_))
        recs = store.load(type_)
        changed = False
        for rec in recs:
            ja = japanese.get((rec["id"], rec["field"]))
            if ja is None or rec["ja_hash"] != readings.ja_hash(ja):
                continue
            missing = readings.uncovered_repeats(ja, rec["words"])
            if not missing:
                continue
            filled = readings.fill_repeats(ja, rec["words"])
            if readings.uncovered_repeats(ja, filled) or readings.word_problems(ja, filled):
                left.append(f"{type_} {rec['id']}/{rec['field']}")
                continue
            rec["words"] = filled
            changed = True
            lines += 1
            places += len(missing)
            by_type[type_] = by_type.get(type_, 0) + 1
        if changed and not dry_run:
            store.save(type_, recs)
    return {"lines": lines, "places": places, "by_type": by_type, "left": left}


def run(argv: Sequence[str]) -> int:
    p = argparse.ArgumentParser(prog="wfj readings")
    sub = p.add_subparsers(dest="cmd", required=True)
    e = sub.add_parser("export", help="lines that need readings → a batch file")
    e.add_argument("--type", required=True, choices=sorted(readings.TYPES))
    e.add_argument("--ids", required=True, type=Path, help="file: one id per line")
    e.add_argument("--all", action="store_true", help="every line, not only those without a current reading")
    e.add_argument(
        "--class",
        dest="klass",
        choices=model.PROVENANCE_CLASSES,
        help="only lines whose shipped variant has this provenance class",
    )
    e.add_argument("--out", required=True, type=Path)
    i = sub.add_parser("import", help="a batch file with words → data/reading/")
    i.add_argument("batch", type=Path)
    i.add_argument("--model", help="the model id that wrote the readings")
    i.add_argument("--batch", dest="name", help="batch name (provenance source readings@NAME)")
    i.add_argument("--correction", action="store_true", help="the rows fix existing readings")
    i.add_argument("--by", help="with --correction: who made the fix (provenance translator)")
    i.add_argument("--note", help="with --correction: what was fixed")
    i.add_argument("--date", default=dt.date.today().isoformat())
    i.add_argument("--dry-run", action="store_true")
    f = sub.add_parser("fill-repeats", help="give every repeated word its card at each place")
    f.add_argument("--dry-run", action="store_true")
    a = p.parse_args(list(argv))
    root = data_root()
    if a.cmd == "fill-repeats":
        res = fill_store(root, dry_run=a.dry_run)
        for line in res["left"]:
            print(f"  left {line}: the fill could not complete it")
        verb = "would fill" if a.dry_run else "filled"
        print(f"readings fill-repeats: {verb} {res['places']} place(s) in {res['lines']} line(s) · by type "
              f"{res['by_type']} · left {len(res['left'])}")
        return 1 if res["left"] else 0
    if a.cmd == "export":
        ids = read_ids(a.ids, a.type)
        rows = export_rows(root, a.type, ids, every=a.all, klass=a.klass)
        shipped_ids = {i for (i, _f) in readings.shipped_japanese(Store(root).load(a.type))}
        for id_ in ids:
            if id_ not in shipped_ids:
                print(f"  warning: {a.type} {id_} has no shipped Japanese")
        a.out.write_text("".join(dumps(r) + "\n" for r in rows), encoding="utf-8")
        print(f"readings export: {len(rows)} line(s) → {a.out}")
        return 0
    if a.correction:
        if not a.by:
            raise SystemExit("readings import: --correction needs --by")
        prov = {"class": "correction", "translator": a.by, "source": f"correction@{a.date}"}
        prov["imported"] = a.date
        if a.note:
            prov["note"] = a.note
    else:
        if not a.model or not a.name:
            raise SystemExit("readings import: needs --model and --batch (or --correction --by)")
        if not _BATCH_RE.match(a.name):
            raise SystemExit("readings import: --batch must be 4–64 of [0-9A-Za-z._-]")
        prov = {"class": "machine", "model": a.model, "source": f"readings@{a.name}", "imported": a.date}
    result = import_rows(root, read_batch(a.batch), prov, dry_run=a.dry_run)
    for line in result["rejected"]:
        print(f"  rejected {line}")
    for line in result["kept"]:
        print(f"  {line}")
    verb = "would write" if a.dry_run else "wrote"
    print(
        f"readings import: {verb} {result['written']} · rejected {len(result['rejected'])} · "
        f"kept {len(result['kept'])} · by type {result['by_type']}"
    )
    return 1 if result["rejected"] else 0
