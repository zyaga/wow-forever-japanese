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

from wfj.cmd.voice import read_rows, write_rows
from wfj.cmd.voice_make import error_lines, line_values, read_cast, scoped_rows, shipped_lines
from wfj.core import kana, names, readings, voice
from wfj.io.jsonl_store import Store
from wfj.io.names_store import load_lines
from wfj.paths import data_root

KEYS = ("key", "ja_hash", "kana", "provenance")


def kana_path(root: Path) -> Path:
    return root / "voice" / "kana.jsonl"


def voiced_lines(root: Path) -> dict[str, str]:
    """{voice key: shipped Japanese} for exactly the lines the voice reads: every line a voice file is made
    for
    (the speakers table's lines that ship, read by whoever the cast gives them) and the character's error
    lines."""
    lines = shipped_lines(root)
    keys = {
        j.key for j in voice.jobs(scoped_rows(root, "all"), read_cast(root), "narrator", "narrator", lines)
    }
    keys |= set(error_lines(root))
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


def build_all(root: Path, today: str) -> tuple[list[dict[str, Any]], dict[str, tuple[str, list[str]]]]:
    """(kana rows, {key: (speech text or Japanese, problems)} for the lines left unfinished)."""
    lines = voiced_lines(root)
    values = line_values(root, lines)
    words = reading_words(root)
    lookup = name_lookup(root)
    old = {r["key"]: r for r in read_rows(kana_path(root))}
    prov = {"class": "machine", "source": f"kana-build@{today}", "imported": today}
    rows, left = [], {}
    for key in sorted(lines):
        ja, vals = lines[key], values.get(key, [])
        h = voice.text_hash(ja, vals)
        text, problems = kana.build(ja, key, vals, words.get(key), lookup)
        if text is not None:
            keep = old.get(key)
            same = (
                keep
                and keep["ja_hash"] == h
                and keep["kana"] == text
                and keep["provenance"]["source"].startswith("kana-build@")
            )
            rows.append(keep if same else {"key": key, "ja_hash": h, "kana": text, "provenance": dict(prov)})
            continue
        drafted = old.get(key)
        if (
            drafted
            and drafted["ja_hash"] == h
            and not drafted["provenance"]["source"].startswith("kana-build@")
        ):
            rows.append(drafted)
            continue
        try:
            shown = voice.speech_text(ja, key, vals)
        except voice.VoiceError:
            shown = ja
        left[key] = (shown, problems)
    return rows, left


def import_rows(root: Path, path: Path, model_id: str, batch: str, today: str) -> tuple[int, list[str]]:
    lines = voiced_lines(root)
    values = line_values(root, lines)
    current = {k: voice.text_hash(ja, values.get(k, [])) for k, ja in lines.items()}
    rows = {r["key"]: r for r in read_rows(kana_path(root))}
    prov = {"class": "machine", "model": model_id, "source": f"draft-kana-{batch}@{today}", "imported": today}
    rejected, written = [], 0
    with path.open(encoding="utf-8") as f:
        for raw in f:
            if not raw.strip():
                continue
            r = json.loads(raw)
            key = r.get("key")
            if current.get(key) is None:
                rejected.append(f"{key}: not a voiced line")
            elif r.get("ja_hash") != current[key]:
                rejected.append(f"{key}: written for other Japanese")
            elif kana.kana_problems(r.get("kana")):
                rejected.append(f"{key}: {'; '.join(kana.kana_problems(r.get('kana')))}")
            else:
                rows[key] = {
                    "key": key,
                    "ja_hash": current[key],
                    "kana": r["kana"].strip(),
                    "provenance": prov,
                }
                written += 1
    write_rows(kana_path(root), [rows[k] for k in sorted(rows)])
    return written, rejected


def problems(root: Path) -> list[str]:
    """Every voiced line needs a kana line made from its current Japanese, and every kana line is kana."""
    lines = voiced_lines(root)
    values = line_values(root, lines)
    rows = {r["key"]: r for r in read_rows(kana_path(root))}
    out = []
    for key, ja in sorted(lines.items()):
        r = rows.get(key)
        if r is None:
            out.append(f"kana {key}: no kana line")
        elif tuple(r) != KEYS:
            out.append(f"kana {key}: keys must be {KEYS}")
        elif r["ja_hash"] != voice.text_hash(ja, values.get(key, [])):
            out.append(f"kana {key}: made from other Japanese (wfj voice kana)")
        else:
            out += [f"kana {key}: {p}" for p in kana.kana_problems(r["kana"])]
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
    for key, (_, probs) in list(left.items())[:20]:
        print(f"  {key}: {'; '.join(probs)}")
    if a.export:
        out = Path(a.export)
        out.parent.mkdir(parents=True, exist_ok=True)
        lines = voiced_lines(root)
        values = line_values(root, lines)
        out.write_text(
            "".join(
                json.dumps(
                    {
                        "key": k,
                        "ja_hash": voice.text_hash(lines[k], values.get(k, [])),
                        "ja": t,
                        "problems": p,
                    },
                    ensure_ascii=False,
                )
                + "\n"
                for k, (t, p) in left.items()
            ),
            encoding="utf-8",
        )
    return 0
