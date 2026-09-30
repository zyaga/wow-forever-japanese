"""Record the rulings on tooltip lines whose Japanese has a number baked into it.

    python -m wfj.dev.rule_baked_numbers --date YYYY-MM-DD [--field description] [--match REGEX]
                                         [--durations] [--by <who>] [--examples 3] [--apply]

`--durations`: select instead the lines whose Japanese names a `$d` duration's unit itself (`$N3秒間`,
`18秒`). That is wrong whenever the client renders minutes, and invisible to the gate, which checks the
number and never reads the unit. Duration units are never assumed.

An item or spell tooltip's English is a **template** the client fills: `Restores $o1 health over $d.` The
player is shown `Restores 58 health over 18 sec.`, and the values differ per item, rank, level and talent.
The predecessor corpus wrote the numbers it happened to see straight into the Japanese (`18秒間でhealthを61
回復。`), so the line is right for one item and wrong for the next.

`Align.check` catches it and shows the live English instead (ADR-007), which is why the food, drink and
hearthstone tooltips a player touches every few minutes stay English on an otherwise translated client.
It is not a failure of the gate: a baked number is simply unusable, and no
re-import can fix it, because the English never changed.

The fix is the placeholder the addon already fills: `$N<k>` for a value and `$D<k>` for a duration, whose
unit the client chooses (ADR-028). A redrafted line serves every item sharing that English at any value:
31 English texts cover the 173 hand-written food and drink lines.

Selection: a line of `--field` on an item or spell that has English, carries a hand-written (`human` /
`correction`) variant, and whose Japanese holds a **digit run the English template cannot produce**
(`align.check_numbers`, with the `$N<k>` / `$D<k>` placeholders removed first so a placeholder's index is
never read as a number). `--match` narrows it further by a regex on the English, which is how a ruling is
taken one set at a time rather than over the whole corpus at once.

The ruling is recorded the ADR-012 way, as a `ruling: {ruling: reject, by, date, note}` on each hand-written
variant, so the guard in `core/status` stops barring a machine draft there, and `decisions.carried` puts the
ruling back on every `make data`. Without `--apply` nothing is written.

Machine output never replaces a human translation without an explicit, logged decision. This tool IS that
log; it does not translate anything.
"""

from __future__ import annotations

import argparse
import re
import sys
from datetime import date
from pathlib import Path
from typing import Any

from wfj.core import align, decisions
from wfj.dev.translate_batch import has_prose, model_english
from wfj.io.jsonl_store import Store
from wfj.paths import data_root

TYPES = ("item", "spell")
NOTE = (
    "baked number: the Japanese holds a value the English template does not, so the runtime gate refuses it; "
    "the model redrafts the line with $N / $D placeholders "
    "(standing ruling: a baked number becomes a placeholder)"
)
NOTE_DURATION = (
    "named unit: the Japanese writes a `$d` duration's unit itself, which is wrong whenever the client "
    "renders "
    "another unit and the runtime gate cannot see it; the model redrafts the line with $D placeholders "
    "(standing ruling: duration units are never assumed, ADR-028)"
)


def baked(ja: str, english: str) -> list[str]:
    """The digit runs in `ja` the English template cannot vouch for, so the gate will refuse the line. The
    `$N<k>` / `$D<k>` placeholders are removed first: their index is not a number the player sees."""
    # `check_numbers` returns (checked, missing); the second is what the gate would refuse
    _, missing = align.check_numbers(align.FILL.sub("", re.sub(r"\$D\d+", "", ja or "")), english or "")
    return missing


_TITLE_WORD = re.compile(r"[A-Za-z][A-Za-z'’\-]{3,}")


def is_title(english: str) -> bool:
    """A book's title as an item description (`The Path of the Protector`): no sentence mark and every word of
    four letters or more capitalised. A title is a name, and names stay in English
    letters, so there is nothing to redraft and a ruling would only withdraw the hand-written line."""
    words = _TITLE_WORD.findall(english)
    return bool(words) and not re.search(r"[.!?…]", english) and all(w[0].isupper() for w in words)


def named_units(ja: str, english: str) -> list[str]:
    """The `$d` durations the Japanese does not carry as `$D<k>`: it wrote the number and a unit itself, or
    left the duration out. Either way the unit on screen is a guess (ADR-028)."""
    problems = align.slot_problems(model_english(english, player_tokens=False), ja) or []
    return [p for p in problems if p.startswith(("duration_missing", "duration_as_value"))]


def select(
    lines: list[dict[str, Any]], english: list[dict[str, Any]], field: str, match: re.Pattern[str] | None,
    *, durations: bool = False,
) -> tuple[list[tuple[dict[str, Any], str, list[str]]], list[dict[str, Any]]]:
    """([(line, its English, the unmatchable numbers)], lines skipped for already carrying a ruling).
    `durations`: select by a named duration unit (`named_units`) instead of a baked number."""
    # only a line a batch can redraft: Forever-sourced English (`db2@` / `wdb@`; batches translate only from
    # the Forever client) whose value slots can be counted. A ruling on any other line withdraws its
    # hand-written Japanese and puts nothing in its place.
    text = {
        ln["id"]: ln["en"]
        for ln in english
        if ln["field"] == field
        and str(ln.get("src", "")).startswith(("db2@", "wdb@"))
        and align.value_slots(model_english(ln["en"], player_tokens=False)) is not None
        and has_prose(model_english(ln["en"], player_tokens=False))  # `cut` drafts nothing without prose
        and not is_title(ln["en"])
    }
    rule: list[tuple[dict[str, Any], str, list[str]]] = []
    ruled: list[dict[str, Any]] = []
    for ln in lines:
        if ln["field"] != field or ln["id"] not in text:
            continue
        en = text[ln["id"]]
        if match and not match.search(en):
            continue
        hand = decisions.hand_written_variants(ln)
        if not hand:
            continue
        missing = named_units(ln["ja"], en) if durations else baked(ln["ja"], en)
        if not missing:
            continue
        if any(v.get("ruling") for v in hand):
            ruled.append(ln)
        else:
            rule.append((ln, en, missing))
    return rule, ruled


def apply_rulings(lines: list[dict[str, Any]], by: str, date_: str, note: str = NOTE) -> int:
    """Write the `reject` ruling onto every hand-written variant of each line. Returns variants ruled."""
    ruling = {"ruling": "reject", "by": by, "date": date_, "note": note}
    n = 0
    for ln in lines:
        for v in decisions.hand_written_variants(ln):
            v["ruling"] = dict(ruling)
            n += 1
    return n


NOTE_ACCEPT = (
    "redraft of a ruled line: this machine line replaces hand-written text the maintainer ruled `reject` "
    "(baked numbers / named duration units): the explicit, recorded decision that lets machine text replace "
    "a hand-written line"
)


def accept_redrafts(lines: list[dict[str, Any]], by: str, date_: str) -> int:
    """The second half of a ruling: once a machine redraft wins a line whose hand-written variants
    are all ruled `reject` by this tool (their note names the baked-number ruling), it carries
    `ruling: accept` itself. `validate --base` asks for exactly this when the hand-written line shipped
    before: the reject ruling alone only lets a draft replace text that shipped nothing.
    Returns lines accepted."""
    n = 0
    for ln in lines:
        if not decisions.is_machine(ln["provenance"]) or ln.get("ruling"):
            continue
        hand = decisions.hand_written_variants(ln)
        if hand and all(str((v.get("ruling") or {}).get("note", "")) in (NOTE, NOTE_DURATION) for v in hand) \
                and decisions.hand_written_all_rejected(ln):
            ln["ruling"] = {"ruling": "accept", "by": by, "date": date_, "note": NOTE_ACCEPT}
            n += 1
    return n


def run(data: Path, field: str, match: re.Pattern[str] | None, by: str, date_: str,
        examples: int, apply: bool, durations: bool = False) -> int:
    store = Store(data)
    english_store = Store(data, english=True)
    total = 0
    for type_ in TYPES:
        lines = store.load(type_)
        rule, ruled = select(lines, english_store.load(type_), field, match, durations=durations)
        if not rule and not ruled:
            continue
        what = "a named duration unit" if durations else "a baked number"
        print(f"{type_} {field}: {len(rule)} line(s) with {what}"
              + (f" · already ruled: {len(ruled)}" if ruled else ""))
        for ln, en, missing in rule[:examples]:
            print(f"  {type_} {ln['id']}: EN {en!r}")
            print(f"      JA {ln['ja']!r}")
            why = "unit guessed" if durations else "the English cannot produce"
            print(f"      {why}: {', '.join(missing)}")
        if apply and rule:
            n = apply_rulings([ln for ln, _, _ in rule], by, date_, NOTE_DURATION if durations else NOTE)
            store.save(type_, lines)
            print(f"  ruled {n} hand-written variant(s) on {len(rule)} line(s) (by {by}, {date_})")
        total += len(rule)
    if not total:
        print("nothing to rule")
    elif not apply:
        print("(dry run; pass --apply to write the rulings)")
    return 0


def _iso_date(value: str) -> str:
    try:
        return date.fromisoformat(value).isoformat()
    except ValueError:
        raise argparse.ArgumentTypeError(f"not a YYYY-MM-DD date: {value!r}") from None


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="python -m wfj.dev.rule_baked_numbers")
    p.add_argument("--date", required=True, type=_iso_date, help="the date of the ruling on this set")
    p.add_argument("--field", default="description", choices=("description", "aura"))
    p.add_argument("--match", help="regex on the English: rule one set at a time, not the whole corpus")
    p.add_argument("--by", default="maintainer")
    p.add_argument("--examples", type=int, default=3)
    p.add_argument("--durations", action="store_true",
                   help="select lines that name a `$d` duration's unit themselves instead of a baked number")
    p.add_argument("--accept", action="store_true",
                   help="record `accept` on each machine redraft that won a line this tool ruled "
                        "(after `make check`)")
    p.add_argument("--apply", action="store_true", help="write the rulings (otherwise a dry run)")
    a = p.parse_args(list(argv) if argv is not None else None)
    if a.accept:
        store = Store(data_root())
        total = 0
        for type_ in TYPES:
            lines = store.load(type_)
            n = accept_redrafts(lines, a.by, a.date)
            if n and a.apply:
                store.save(type_, lines)
            print(f"{type_}: {n} redraft(s) to accept" + ("" if a.apply else " (dry run)"))
            total += n
        return 0
    try:
        return run(data_root(), a.field, re.compile(a.match) if a.match else None,
                   a.by, a.date, a.examples, a.apply, a.durations)
    except (ValueError, OSError, re.error) as e:
        print(f"rule-baked-numbers: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
