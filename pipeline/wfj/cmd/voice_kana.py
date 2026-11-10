"""wfj voice kana [--export FILE] [--date YYYY-MM-DD] | wfj voice kana-import BATCH --model M --batch NAME

The kana line of every voiced line (core/kana.py, ADR-077) in `data/voice/kana.jsonl`:
`{"key", "ja_hash", "kana", "provenance"}`, `ja_hash` being what the line's words were made from (the shipped
Japanese and the numbers filled into it, `voice.text_hash`). A line the builder can read is rebuilt every run;
one it cannot (a kanji with no reading, a name with no Japanese) keeps a model-written kana line written for
the
same `ja_hash`, else it is listed (and, with --export, written to FILE as {"key", "ja", "problems"} for a
drafting round). `kana-import` takes rows {"key", "ja_hash", "kana"} for those lines.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
from collections.abc import Sequence
from pathlib import Path
from typing import Any

from wfj.cmd.names import draft_provenance
from wfj.cmd.readings import read_batch
from wfj.cmd.voice import read_rows, write_rows
from wfj.cmd.voice_make import line_values, scoped_rows, shipped_lines
from wfj.core import kana, names, readings, voice
from wfj.io.jsonl_store import Store
from wfj.io.names_store import load_lines
from wfj.paths import data_root

KEYS = ("key", "ja_hash", "kana", "provenance")


BUILT = "kana-build@"  # the source of a line the builder made (not a model)


def kana_path(root: Path) -> Path:
    return root / "voice" / "kana.jsonl"


def voiced_lines(root: Path) -> dict[str, str]:
    """{voice key: shipped Japanese} for exactly the lines the voice reads: the speakers table's lines that
    ship (a voice file is made for each) and the character's error lines (`e-`, in `shipped_lines`)."""
    lines = shipped_lines(root)
    keys = {r["key"] for r in scoped_rows(root, "all")} | {k for k in lines if k.startswith("e-")}
    return {k: lines[k] for k in sorted(keys) if k in lines}


def reading_words(root: Path) -> dict[str, list[list[str]]]:
    """{voice key: the words of its current reading record}."""
    store, rstore = Store(root), Store(root / "reading")
    out: dict[str, list[list[str]]] = {}
    for type_ in ("quest", "gossip", "ui", "book"):
        lines = store.load(type_)
        result = readings.check(type_, rstore.load(type_), readings.shipped_japanese(lines))
        for rec in readings.addon_keyed(type_, result["current"], lines):
            if type_ == "quest":
                out[voice.quest_key(rec["id"], rec["field"])] = rec["words"]
            elif type_ == "gossip":
                out[voice.gossip_key(rec["id"])] = rec["words"]
            elif type_ == "book":
                out[voice.book_key(str(rec["id"]))] = rec["words"]
            else:
                out[f"e-{rec['id']}"] = rec["words"]
    return out


def name_lookup(root: Path):
    by_id = {ln["id"]: ln for ln in load_lines(root) if ln["status"] == "trusted"}

    def lookup(run: str) -> str | None:
        ln = by_id.get(names.name_id(run))
        return kana.name_kana(ln) if ln else None

    return lookup


def build_all(root: Path, today: str) -> tuple[list[dict[str, Any]], dict[str, tuple[str, str, list[str]]]]:
    """(kana rows, {key: (ja_hash, speech text or Japanese, problems)} for the lines left unfinished). A row
    the builder makes again unchanged keeps its old date, so a rerun is a byte no-op."""
    lines = voiced_lines(root)
    values = line_values(root, lines)
    words = reading_words(root)
    lookup = name_lookup(root)
    old = {r["key"]: r for r in read_rows(kana_path(root))}
    prov = {"class": "machine", "source": f"{BUILT}{today}", "imported": today}
    rows, left = [], {}
    for key in sorted(lines):
        ja, vals = lines[key], values.get(key, [])
        h = voice.text_hash(ja, vals)
        text, problems = kana.build(ja, key, vals, words.get(key), lookup)
        prev = old.get(key)
        fresh = bool(prev) and prev["ja_hash"] == h
        built = fresh and prev["provenance"]["source"].startswith(BUILT)
        if text is not None:
            same = built and prev["kana"] == text
            rows.append(prev if same else {"key": key, "ja_hash": h, "kana": text, "provenance": dict(prov)})
            continue
        if fresh and not built:  # a model-written line for this same Japanese
            rows.append(prev)
            continue
        try:
            shown = voice.speech_text(ja, key, vals)
        except voice.VoiceError:
            shown = ja
        left[key] = (h, shown, problems)
    return rows, left


def import_rows(root: Path, path: Path, model_id: str, batch: str, today: str) -> tuple[int, list[str]]:
    prov = draft_provenance(model_id, "kana", batch, today)
    lines = voiced_lines(root)
    values = line_values(root, lines)
    current = {k: voice.text_hash(ja, values.get(k, [])) for k, ja in lines.items()}
    rows = {r["key"]: r for r in read_rows(kana_path(root))}
    rejected, written = [], 0
    for r in read_batch(path):
        key = r.get("key")
        bad = kana.kana_problems(r.get("kana"))
        if current.get(key) is None:
            rejected.append(f"{key}: not a voiced line")
        elif r.get("ja_hash") != current[key]:
            rejected.append(f"{key}: written for other Japanese")
        elif bad:
            rejected.append(f"{key}: {'; '.join(bad)}")
        else:
            rows[key] = {"key": key, "ja_hash": current[key], "kana": r["kana"].strip(), "provenance": prov}
            written += 1
    write_rows(kana_path(root), [rows[k] for k in sorted(rows)])
    return written, rejected


def problems(root: Path) -> list[str]:
    """The stored kana lines against a fresh build: every voiced line has one, made from its current Japanese,
    readings and names (a reading or name that changed makes a built line out of date even when the Japanese
    did not), and a model-written one is kana."""
    stored = {r["key"]: r for r in read_rows(kana_path(root))}
    rebuilt, left = build_all(root, "0000-00-00")
    out = [
        f"kana {k}: no kana line, and the builder cannot make one: {'; '.join(p)}"
        for k, (_, _, p) in left.items()
    ]
    for r in rebuilt:
        have = stored.pop(r["key"], None)
        if have is None:
            out.append(f"kana {r['key']}: no kana line (wfj voice kana)")
        elif (have["ja_hash"], have["kana"]) != (r["ja_hash"], r["kana"]):
            out.append(f"kana {r['key']}: out of date (wfj voice kana)")
        elif tuple(have) != KEYS:
            out.append(f"kana {r['key']}: keys must be {KEYS}")
    out += [f"kana {k}: not a voiced line any more (wfj voice kana)" for k in sorted(stored)]
    return out


def run(argv: Sequence[str]) -> int:
    today = dt.date.today().isoformat()
    if argv and argv[0] == "kana-import":
        p = argparse.ArgumentParser(prog="wfj voice kana-import")
        p.add_argument("batch_file")
        p.add_argument("--model", required=True)
        p.add_argument("--batch", required=True)
        p.add_argument("--date", default=today)
        a = p.parse_args(list(argv[1:]))
        n, rejected = import_rows(data_root(), Path(a.batch_file), a.model, a.batch, a.date)
        for r in rejected:
            print(f"voice kana-import: rejected {r}", file=sys.stderr)
        print(f"voice kana-import: {n} kana lines written, {len(rejected)} rejected")
        return 1 if rejected else 0
    p = argparse.ArgumentParser(prog="wfj voice kana")
    p.add_argument("--export", help="write the unfinished lines here for a drafting round")
    p.add_argument("--date", default=today)
    a = p.parse_args(list(argv[1:]))
    root = data_root()
    rows, left = build_all(root, a.date)
    write_rows(kana_path(root), rows)
    print(f"voice kana: {len(rows)} kana lines, {len(left)} left unfinished")
    for key, (_, _, probs) in list(left.items())[:20]:
        print(f"  {key}: {'; '.join(probs)}")
    if a.export:
        out = Path(a.export)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(
            "".join(
                json.dumps({"key": k, "ja_hash": h, "ja": t, "problems": p}, ensure_ascii=False) + "\n"
                for k, (h, t, p) in left.items()
            ),
            encoding="utf-8",
        )
    return 0
