"""Record the rulings on held-back quest lines: **completion** lines, and **description** / **objectives**
lines whose hand-written text is cut short (`truncated`).

    python -m wfj.dev.rule_held_back --date YYYY-MM-DD [--field completion|description|objectives] \
        [--by <who>] [--examples 3] [--apply]

A held-back line is a quest `completion` line that has English to translate, carries at least one
hand-written (`human` / `correction`) variant, and ships nothing: every hand-written variant on it is
rejected by the rules (`truncated`, `alignment_failed`, `numbers_changed`, `duplicate_conflict`, …), so the
addon shows the live English. For these lines the model translates the whole line and replaces that text.
The ruling is recorded the ADR-012 way, as a `ruling: {ruling: reject, by, date, note}` on each hand-written
variant of the line. That lifts the guard in `core/status` (machine text never replaces a human translation
without a recorded ruling) for this line, and `decisions.carried` puts the ruling back on every `make data`.

`--field description` / `--field objectives` narrow the set further: only a line rejected as `truncated` is
selected. The predecessor corpus stopped after the first paragraph, and the model translates the whole line
rather than splicing onto it. A description rejected for another reason only (a misspelled name, say) is a
hand correction's job (ADR-012), not a redraft's.

Nothing else is touched: a line whose hand-written text ships (`trusted` / `stale` / `unaligned`) never gets
a ruling, other fields (title / progress) are out of scope, and a hand-written variant that
already carries a ruling is left alone and reported. Without `--apply` nothing is written: it prints the
count and a few real examples. `--date` is required and has no default: it is the date of the ruling on
this set of lines, and a new set of lines is a new ruling with its own date.
"""

from __future__ import annotations

import argparse
import sys
from datetime import date
from pathlib import Path
from typing import Any

from wfj.core import decisions
from wfj.core.report import SHIPPED
from wfj.io.jsonl_store import Store
from wfj.paths import data_root

TYPE = "quest"
FIELD = "completion"
NOTE = (
    "held back: no hand-written variant ships; the model translates the whole line "
    "(standing ruling: no hand-written variant ships)"
)
NOTE_TRUNCATED = (
    "held back: the hand-written text is cut short (truncated) and ships nothing; "
    "the model translates the whole line (standing ruling: cut-short hand-written text ships nothing)"
)
# field → the ruling's note; a field other than completion also needs a `truncated` reason
NOTES = {FIELD: NOTE, "description": NOTE_TRUNCATED, "objectives": NOTE_TRUNCATED}
TRUNCATED = "truncated"


def held_back(
    store: list[dict[str, Any]], english: list[dict[str, Any]], field: str = FIELD
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """(lines to rule, lines skipped because a hand-written variant already carries a ruling)."""
    have_english = {ln["id"] for ln in english if ln["field"] == field}
    rule: list[dict[str, Any]] = []
    ruled: list[dict[str, Any]] = []
    for ln in store:
        if ln["field"] != field or ln["status"] in SHIPPED or ln["id"] not in have_english:
            continue
        if field != FIELD and not any(r.split(":")[0] == TRUNCATED for r in ln.get("reasons", [])):
            continue
        hand = decisions.hand_written_variants(ln)
        if not hand:
            continue
        (ruled if any(v.get("ruling") for v in hand) else rule).append(ln)
    return rule, ruled


def apply_rulings(lines: list[dict[str, Any]], by: str, date: str, field: str = FIELD) -> int:
    """Write the `reject` ruling onto every hand-written variant of each line. Returns variants ruled."""
    ruling = {"ruling": "reject", "by": by, "date": date, "note": NOTES[field]}
    n = 0
    for ln in lines:
        for v in decisions.hand_written_variants(ln):
            v["ruling"] = dict(ruling)
            n += 1
    return n


def _example(line: dict[str, Any], english: dict[int, str]) -> str:
    hand = decisions.hand_written_variants(line)[0]
    return (
        f"quest {line['id']} {line['field']} · rejected {', '.join(line['reasons'])}\n"
        f"  EN: {english[line['id']]}\n"
        f"  JA (hand-written, not shipping): {hand['ja']}"
    )


def run(data: Path, by: str, date: str, examples: int, apply: bool, field: str = FIELD) -> int:
    store = Store(data)
    lines = store.load(TYPE)
    english = Store(data, english=True).load(TYPE)
    rule, ruled = held_back(lines, english, field)
    print(f"held-back {field} lines: {len(rule)}" + (f" · already ruled: {len(ruled)}" if ruled else ""))
    en_text = {ln["id"]: ln["en"] for ln in english if ln["field"] == field}
    for ln in rule[:examples]:
        print(_example(ln, en_text))
    if apply:
        n = apply_rulings(rule, by, date, field)
        store.save(TYPE, lines)
        print(f"ruled {n} hand-written variants on {len(rule)} lines (by {by}, {date})")
    else:
        print("(dry run; pass --apply to write the rulings)")
    return 0


def _iso_date(value: str) -> str:
    try:
        return date.fromisoformat(value).isoformat()
    except ValueError:
        raise argparse.ArgumentTypeError(f"not a YYYY-MM-DD date: {value!r}") from None


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(prog="rule_held_back", description=__doc__.split("\n\n")[0])
    ap.add_argument("--field", default=FIELD, choices=sorted(NOTES),
                    help="completion (the default) or description / objectives "
                    "(truncated only)")
    ap.add_argument("--by", default="maintainer")
    ap.add_argument("--date", required=True, type=_iso_date, help="the date of the ruling")
    ap.add_argument("--examples", type=int, default=3)
    ap.add_argument("--apply", action="store_true", help="write the rulings into data/ (default: dry run)")
    args = ap.parse_args(argv)
    return run(data_root(), args.by, args.date, args.examples, args.apply, args.field)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
