"""Apply a review of stale hand-written lines: each line whose English a client build changed was
read against its new English, and the Japanese is either kept (it still says what the new English
says) or corrected, the person's Japanese edited as little as the new English needs, never redrafted.

    python -m wfj.dev.apply_review <decisions.jsonl> --date <YYYY-MM-DD> --by <who> --model <id>
        [--dry-run]

A decisions row is `{"type", "id", "field", "decision": "keep" | "correct", "ja"?, "note"}` (`ja`
on `correct` only).

- **keep**: the line's English baseline is re-stamped to the English `check` judges it against now
  (`check.current_baseline`), so the line is judged fresh; its Japanese and variants are untouched.
- **correct**: a `correction` variant in the ADR-012 shape: `translator` = the
  corrected variant's translator, `source: correction@<date>`, `corrects` = the imported layer it
  corrects, `note` = the row's note and who drafted and ruled it. A correction the line already
  shipped is ruled `reject` (superseded), and the new one names the layer that correction corrected.
  Then the baseline is re-stamped as for `keep`.

Only a `stale` line whose winner is hand-written (`human` / `correction`) is taken; anything else
stops the run with nothing written, as does a row with no English to judge it against. `make check`
then assigns the statuses.

`--scope audit` (the audit of every shipped hand-written line): a row may name any **shipped**
line (`trusted` / `stale` / `unaligned`) whose winner is hand-written, and the decisions are `correct`
(as above) and `redraft`: every hand-written variant of the line is ruled `reject` in the ADR-012 shape
(the `rule_held_back` one), so the line ships nothing until a machine redraft is imported
(`translate_batch cut --held-back`). A line the audit found right is simply not listed. Only a list that was
ruled on is applied: machine text never replaces a human translation without a recorded ruling.

`--scope templates`: as `audit`, for the hand-written lines on included / branching templates that kept the
translator's numbers; the ruling rewrites them with `$N` / `$D` placeholders."""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any

from wfj.cmd.check import Included, current_baseline, scopes_for
from wfj.core import decisions, public_text
from wfj.core.report import SHIPPED
from wfj.io import private_rules
from wfj.io.jsonl_store import Store
from wfj.paths import data_root

DECISIONS = ("keep", "correct")
AUDIT_DECISIONS = ("correct", "redraft")
SCOPES = ("stale", "audit", "templates")
# the scopes that take any shipped hand-written line (not only a stale one)
ANY_SHIPPED = frozenset({"audit", "templates"})
SUPERSEDED_BY = {"stale": "for the new English", "audit": "from the audit", "templates": "with placeholders"}


def _capital(note: str) -> str:
    """A reviewer's note as the start of a provenance note."""
    return note[:1].upper() + note[1:] if note[:1].islower() else note

WHY = {"stale": "to update stale lines", "audit": "on the audit of the hand-written lines",
       "templates": "to write the baked numbers of included / branching templates as placeholders"}


def read_decisions(path: Path, scope: str = "stale") -> list[dict[str, Any]]:
    rows = []
    seen: set[tuple[Any, Any, Any]] = set()
    for n, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not raw.strip():
            continue
        row = json.loads(raw)
        if not all(row.get(k) not in (None, "") for k in ("type", "id", "field")):
            raise ValueError(f"{path.name}:{n}: a row names its type, id and field")
        key = (row["type"], row["id"], row["field"])
        if key in seen:  # a duplicate is never resolved silently (last-wins)
            raise ValueError(f"{path.name}:{n}: {key[0]} {key[1]}/{key[2]} is decided twice")
        seen.add(key)
        allowed = AUDIT_DECISIONS if scope in ANY_SHIPPED else DECISIONS
        if row.get("decision") not in allowed:
            raise ValueError(f"{path.name}:{n}: decision must be one of {allowed}")
        if (row["decision"] == "correct") != bool(str(row.get("ja", "")).strip()):
            raise ValueError(f"{path.name}:{n}: `ja` is required on correct and only there")
        if not str(row.get("note", "")).strip():
            raise ValueError(f"{path.name}:{n}: every decision carries a note")
        rows.append(row)
    return rows


def _baseline(scope: Any, field: str, included: Included | None) -> dict[str, Any] | None:
    """`check.current_baseline`, with the spells the line splices in when `included` is given: the
    baseline `check` itself records, so a re-run finds the row applied and an included spell's change between
    this run and the next `check` is not missed."""
    if not scope or scope.empty:
        return None
    return current_baseline(scope, field, included.of(scope, field) if included is not None else None)


def applied(
    line: dict[str, Any],
    row: dict[str, Any],
    scopes: dict[Any, Any],
    ruled: dict[str, str],
    included: Included | None = None,
) -> bool:
    """The row's effect is already in `line`: its baseline is the current English and, for a correction, the
    winner is this run's correction with the row's Japanese; for a redraft, every hand-written
    variant carries a reject ruling."""
    if row["decision"] == "redraft":
        hand = decisions.hand_written_variants(line)
        return bool(hand) and all(decisions.is_rejected(v) for v in hand)
    base = _baseline(scopes.get(row["id"]), row["field"], included)
    if base is None or line.get("english") != base:
        return False
    if row["decision"] == "keep":
        return decisions.is_hand_written(line["provenance"])
    return line["provenance"].get("source") == f"correction@{ruled['date']}" and line["ja"] == row["ja"]


def apply(
    lines: list[dict[str, Any]],
    rows: list[dict[str, Any]],
    scopes: dict[Any, Any],
    ruled: dict[str, str],
    scope_name: str = "stale",
    included: Included | None = None,
) -> dict[str, int]:
    """Edit `lines` in place per `rows`. `ruled`: {by, date, model}. → counts"""
    by = {(ln["id"], ln["field"]): ln for ln in lines}
    c = {"keep": 0, "correct": 0, "redraft": 0, "superseded": 0, "already": 0}
    taken = SHIPPED if scope_name in ANY_SHIPPED else ("stale",)
    for row in rows:  # a note goes into public data as written, so it must pass the public check first
        rules = private_rules.load(Path(__file__).resolve().parents[3])
        note = str(row.get("note", ""))
        blocked = sorted({h.rule for h in public_text.content_hits(note, in_data=True, rules=rules)})
        if blocked:
            where = f"{row['id']}/{row['field']}"
            raise ValueError(f"review: {where}: the note cannot be published ({', '.join(blocked)})")
    for row in rows:
        k = (row["id"], row["field"])
        line = by.get(k)
        if line is not None and applied(line, row, scopes, ruled, included):
            c["already"] += 1  # a re-run (before or after `make check`) leaves an applied row as it is
            continue
        if line is None or line["status"] not in taken or not decisions.is_hand_written(line["provenance"]):
            what = "shipped" if scope_name in ANY_SHIPPED else "stale"
            raise ValueError(f"review: {k[0]}/{k[1]}: not a {what} line with a hand-written winner")
        base = _baseline(scopes.get(row["id"]), row["field"], included)
        if base is None:
            raise ValueError(f"review: {k[0]}/{k[1]}: no English to judge it against")
        if row["decision"] == "redraft":
            ruling = {"ruling": "reject", "by": ruled["by"], "date": ruled["date"],
                      "note": f"{_capital(row['note'])}; the model redrafts the whole line (drafted by "
                      f"{ruled['model']}, on the {ruled['by']}'s ruling {WHY[scope_name]})"}
            for v in decisions.hand_written_variants(line):
                v["ruling"] = dict(ruling)
            c["redraft"] += 1
            continue
        if row["decision"] == "correct":
            keys = ("ja", "provenance", "extra", "ruling")
            old = {key: line[key] for key in keys if line.get(key) is not None}
            ruling = {"ruling": "reject", "by": ruled["by"], "date": ruled["date"],
                      "note": "Superseded by the correction "
                      + SUPERSEDED_BY[scope_name]
                      + f" ({row['note']})"}
            corrects = old["provenance"]["source"]
            if old["provenance"]["class"] == decisions.CORRECTION:
                old["ruling"] = ruling
                corrects = old["provenance"]["corrects"]
                c["superseded"] += 1
            prov = {
                "class": decisions.CORRECTION,
                "translator": old["provenance"].get("translator", ""),
                "source": f"correction@{ruled['date']}",
                "imported": ruled["date"],
                "corrects": corrects,
                "note": f"{_capital(row['note'])} (edited from the translator's Japanese by "
                f"{ruled['model']}, "
                f"on the {ruled['by']}'s ruling {WHY[scope_name]})",
            }
            line["conflicts"] = [old, *line["conflicts"]]
            line["ja"], line["provenance"] = row["ja"], prov
            line.pop("extra", None)
            line.pop("ruling", None)
        line["english"] = base
        c[row["decision"]] += 1
    return c


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="wfj.dev.apply_review", description=__doc__.split("\n\n")[0])
    ap.add_argument("decisions", type=Path)
    ap.add_argument("--date", required=True)
    ap.add_argument("--by", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--scope", choices=SCOPES, default="stale",
                    help="stale (the default), audit (any shipped hand-written line) or "
                         "templates (the same, baked numbers on included / branching templates)")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args(argv)
    rows = read_decisions(a.decisions, a.scope)
    root = data_root()
    store, english = Store(root), Store(root, english=True)
    by_type: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        by_type[row["type"]].append(row)
    out, total = {}, {"keep": 0, "correct": 0, "redraft": 0, "superseded": 0, "already": 0}
    try:
        for type_, trows in by_type.items():
            lines = store.load(type_)
            ruled = {"by": a.by, "date": a.date, "model": a.model}
            c = apply(lines, trows, scopes_for(english, store, type_), ruled, a.scope, Included(english))
            out[type_] = lines
            total = {k: total[k] + c[k] for k in total}
    except ValueError as e:
        print(e, file=sys.stderr)
        return 1
    if not a.dry_run:
        for type_, lines in out.items():
            store.save(type_, lines)
    print(f"review{' (dry run)' if a.dry_run else ''}: kept {total['keep']} · corrected {total['correct']} · "
          + (f"ruled for redraft {total['redraft']} · " if a.scope in ANY_SHIPPED else "")
          + f"earlier corrections superseded {total['superseded']} · "
          f"already applied {total['already']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
