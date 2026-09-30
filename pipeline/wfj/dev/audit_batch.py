"""The audit of the shipped hand-written lines: cut them into parts beside their English, then check
the verdicts the model wrote and turn them into a report, a decisions list and word lists.

    python -m wfj.dev.audit_batch cut --type quest|item|spell|ui --size 250 --out-dir DIR \
        [--prefix q] [--words FILE ...]
    python -m wfj.dev.audit_batch check PART.jsonl
    python -m wfj.dev.audit_batch report DIR [--out REPORT.md]

`cut` takes every **shipped** line (`trusted` / `stale` / `unaligned`) whose winner is hand-written (`human` /
`correction`) and that has English to judge it against, in id / field order, and writes `<prefix>NN.jsonl`
parts of `--size` rows: `{"type", "id", "field", "class", "ja", "ja_hash", "en", "included"?}`. A tooltip
English that includes another spell's description (`$@spelldesc434`) carries that text in `included`
(`{"434": "..."}`), so the line can be judged whole. `--words` names readings
batches already written for these lines (`*.words.jsonl`); a row whose type, id, field and Japanese
hash match one of them carries its `words`, so the audit keeps them instead of writing them again. Lines with
no English are counted and left out: there is nothing to judge them against.

The model writes `<part>.verdicts.jsonl` beside each part, one row per part row, in order:
`{"type", "id", "field", "ja_hash", "verdict", "kind"?, "problem"?, "ja"?, "words"?}`.

- `match`: the Japanese says what the English says. A quest row carries `words` for that Japanese.
- `correct`: a small defect, fixed by the smallest edit: `ja` is the corrected Japanese; a quest row carries
  `words` for it.
- `redraft`: the meaning is wrong, garbled, another quest's text, or cut off; the whole line is redrafted
  later (with its own words); no `ja`, no `words`.

`correct` and `redraft` name a `kind` (`KINDS`) and a short `problem`. Item and spell rows never carry `words`
(tooltip text has no readings).

`check` runs the same checks as `report` on one part's verdicts and writes nothing (the audit agent's check).

`report` checks every part against its verdicts (a missing, extra, duplicate or re-ordered row, a changed
`ja_hash`, an unknown verdict or kind, a `correct` whose `ja` is missing or unchanged, words missing where
they are owed or present where they are not, and words the readings import would refuse
(`readings.word_problems`, every entry the 5-item form))
and prints each problem. With none, it writes into DIR:

- `audit.decisions.jsonl`: the `correct` / `redraft` rows as `wfj.dev.apply_review --scope audit` reads them;
  applied only once the list is ruled on (machine text never replaces a human translation without a ruling);
- `audit.words.jsonl`: the `match` rows' words (for `wfj readings import` now: their Japanese is unchanged);
- `audit.correct-words.jsonl`: the `correct` rows' words, hashed for the corrected Japanese (imported after
  the corrections are applied);

and the report (`--out`): verdicts per type × field and examples of each kind. Nothing in `data/` is written.

`--type ui` audits the shipped UI strings, which are machine-written, as (English, Japanese) pairs with the
screens they appear on; its rows, verdicts (`split` is UI only) and outputs (`audit.ui-draft.jsonl`,
`audit.ui-base.jsonl`, `audit.ui-redraft.ids`, `audit.ui-split.jsonl`) are described in `wfj.dev.audit_ui`.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

from wfj.core import decisions, readings
from wfj.core.report import SHIPPED
from wfj.dev import audit_ui
from wfj.io.jsonl_store import Store
from wfj.paths import data_root

TYPES = ("quest", "item", "spell", "ui")
VERDICTS = ("match", "correct", "redraft", "split")
KINDS = (
    "meaning",  # says something else than the English (a mismatch, a reversed sense, a missing sentence)
    "other_text",  # another quest's / item's text
    "cut_off",  # stops before the English does
    "garbled",  # unreadable Japanese
    "typo",  # a doubled or dropped character (軍をを)
    "particle",  # a wrong or garbled particle (だがの問題)
    "kanji",  # the wrong kanji (大儀 for 大義)
    "name",  # a name mangled or translated (names stay English)
    "number",  # a number or placeholder wrong or missing
    "other",
    *audit_ui.UI_KINDS,
)
ROW_KEYS = ("type", "id", "field", "ja_hash")
_INCLUDED = re.compile(r"\$@spell(?:desc|tooltip)(\d+)")


def _key(row: dict[str, Any]) -> tuple[Any, ...]:
    return tuple(row.get(k) for k in ROW_KEYS[:3])


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    rows = []
    for n, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if raw.strip():
            row = json.loads(raw)
            if not isinstance(row, dict):
                raise ValueError(f"{path.name}:{n}: a row is a JSON object")
            rows.append(row)
    return rows


def write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    path.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")


# ---- cut ------------------------------------------------------------------------------------------


def audit_rows(root: Path, type_: str, words: dict[tuple[Any, ...], list[Any]] | None = None
               ) -> tuple[list[dict[str, Any]], int]:
    """(rows to audit, shipped hand-written lines left out for having no English)."""
    if type_ == "ui":
        return audit_ui.ui_rows(root)
    english = {(ln["id"], ln["field"]): ln["en"] for ln in Store(root, english=True).load(type_)}
    if type_ == "spell":
        spells = english
    elif type_ == "item":
        spells = {(ln["id"], ln["field"]): ln["en"] for ln in Store(root, english=True).load("spell")}
    else:
        spells = {}
    words = words or {}
    rows: list[dict[str, Any]] = []
    no_english = 0
    for ln in Store(root).load(type_):
        if ln["status"] not in SHIPPED or not decisions.is_hand_written(ln["provenance"]):
            continue
        en = english.get((ln["id"], ln["field"]))
        if not isinstance(en, str) or not en.strip():
            no_english += 1
            continue
        h = readings.ja_hash(ln["ja"])
        row = {"type": type_, "id": ln["id"], "field": ln["field"], "class": ln["provenance"]["class"],
               "ja": ln["ja"], "ja_hash": h, "en": en}
        included = {
            m: spells[(int(m), "description")]
            for m in _INCLUDED.findall(en)
            if (int(m), "description") in spells
        }
        if included:
            row["included"] = included
        w = words.get((type_, ln["id"], ln["field"], h))
        if w:
            row["words"] = w
        rows.append(row)
    return rows, no_english


def known_words(paths: list[Path]) -> dict[tuple[Any, ...], list[Any]]:
    """(type, id, field, ja_hash) → words, from readings batches already written."""
    out: dict[tuple[Any, ...], list[Any]] = {}
    for p in paths:
        for r in load_jsonl(p):
            if r.get("words"):
                out[(r.get("type"), r.get("id"), r.get("field"), r.get("ja_hash"))] = r["words"]
    return out


def cut(root: Path, type_: str, size: int, out_dir: Path, prefix: str, words: list[Path]) -> int:
    rows, no_english = audit_rows(root, type_, known_words(words))
    out_dir.mkdir(parents=True, exist_ok=True)
    parts = [rows[i:i + size] for i in range(0, len(rows), size)]
    for n, part in enumerate(parts, 1):
        write_jsonl(out_dir / f"{prefix}{n:02d}.jsonl", part)
    reused = sum(1 for r in rows if "words" in r)
    by_field = Counter(r["field"] for r in rows)
    print(f"{type_}: {len(rows)} lines to audit in {len(parts)} parts of ≤{size} "
          f"({', '.join(f'{f} {n}' for f, n in sorted(by_field.items()))}) · "
          f"words reused {reused} · left out, no English {no_english}")
    return 0


# ---- report ---------------------------------------------------------------------------------------


def verdict_problems(part: dict[str, Any], v: dict[str, Any]) -> list[str]:
    """Problems with one verdict row against its part row (empty = fine)."""
    p: list[str] = []
    if tuple(v.get(k) for k in ROW_KEYS) != tuple(part.get(k) for k in ROW_KEYS):
        return [f"does not match the part row ({'/'.join(str(part.get(k)) for k in ROW_KEYS[:3])})"]
    verdict = v.get("verdict")
    if verdict not in VERDICTS:
        return [f"verdict must be one of {VERDICTS}"]
    if part["type"] == "ui":
        return audit_ui.problems(part, v, KINDS)
    if verdict == "split":
        return ["a split is for UI rows only"]
    if v.get("kind") in audit_ui.UI_KINDS:
        return [f"kind {v['kind']} is for UI rows only"]
    quest = part["type"] == "quest"
    if verdict == "match":
        if v.get("ja") not in (None, part["ja"]):
            p.append("a match carries no new `ja`")
    else:
        if v.get("kind") not in KINDS:
            p.append(f"kind must be one of {KINDS}")
        if not str(v.get("problem", "")).strip():
            p.append(f"a {verdict} names its problem")
    if verdict == "correct":
        ja = v.get("ja")
        if not isinstance(ja, str) or not ja.strip():
            p.append("a correct carries the corrected `ja`")
        elif ja == part["ja"]:
            p.append("a correct's `ja` is unchanged")
    if verdict == "redraft" and v.get("ja") not in (None, part["ja"]):
        p.append("a redraft carries no `ja` (the redraft batch writes it)")
    shipped = v.get("ja") if verdict == "correct" else part["ja"]
    owed = quest and verdict != "redraft" and isinstance(shipped, str) and readings.annotatable(shipped)
    return p + _words_problems(v, shipped, owed)


def _words_problems(v: dict[str, Any], shipped: Any, owed: bool) -> list[str]:
    """The problems with a verdict's `words`, which a quest line that keeps annotatable Japanese owes."""
    if "words" in v and not owed:
        return ["words where none are owed (item / spell text, a redraft, or nothing to annotate)"]
    if not owed:
        return []
    if not v.get("words"):
        return ["words missing"]
    p: list[str] = []
    if any(not (isinstance(w, list) and len(w) == 5) for w in v["words"]):
        p.append("every word entry is the 5-item form (word, reading, dict. form, reading, meaning)")
    return p + readings.word_problems(shipped, v["words"])


def check_dir(d: Path) -> tuple[list[tuple[dict[str, Any], dict[str, Any]]], list[str], list[str]]:
    """(part row, verdict row) pairs, problems, parts with no verdicts yet."""
    pairs: list[tuple[dict[str, Any], dict[str, Any]]] = []
    problems: list[str] = []
    missing: list[str] = []
    seen: set[tuple[Any, ...]] = set()
    for part_path in sorted(d.glob("*.jsonl")):
        if part_path.name.count(".") != 1 or part_path.name.startswith("audit"):
            continue  # verdicts, words and outputs have a second dot or the audit prefix
        vpath = part_path.with_suffix(".verdicts.jsonl")
        if not vpath.exists():
            missing.append(part_path.name)
            continue
        part, verdicts = load_jsonl(part_path), load_jsonl(vpath)
        if len(verdicts) != len(part):
            problems.append(f"{vpath.name}: {len(verdicts)} verdicts for {len(part)} rows")
        for n, (row, v) in enumerate(zip(part, verdicts, strict=False), 1):
            k = _key(row)
            if k in seen:
                problems.append(f"{vpath.name}:{n}: {k} is audited twice")
                continue
            seen.add(k)
            bad = verdict_problems(row, v)
            if bad:
                problems += [f"{vpath.name}:{n} {'/'.join(map(str, k))}: {x}" for x in bad]
            else:
                pairs.append((row, v))
    return pairs, problems, missing


def check_part(part_path: Path) -> int:
    vpath = part_path.with_suffix(".verdicts.jsonl")
    if not vpath.exists():
        print(f"{vpath.name}: no verdicts file yet (write it beside {part_path.name})")
        return 1
    part, verdicts = load_jsonl(part_path), load_jsonl(vpath)
    problems = [] if len(verdicts) == len(part) else [f"{len(verdicts)} verdicts for {len(part)} rows"]
    for n, (row, v) in enumerate(zip(part, verdicts, strict=False), 1):
        problems += [f"row {n} {'/'.join(map(str, _key(row)))}: {x}" for x in verdict_problems(row, v)]
    for x in problems:
        print(x)
    c = Counter(v.get("verdict") for v in verdicts)
    print(f"{vpath.name}: {len(verdicts)} verdicts · match {c['match']} · correct {c['correct']} · "
          f"redraft {c['redraft']} · split {c['split']} · {len(problems)} failed")
    return 1 if problems else 0


def outputs(pairs: list[tuple[dict[str, Any], dict[str, Any]]]) -> dict[str, list[dict[str, Any]]]:
    dec: list[dict[str, Any]] = []
    match_words: list[dict[str, Any]] = []
    correct_words: list[dict[str, Any]] = []
    for row, v in pairs:
        if row["type"] == "ui":
            continue  # a UI row becomes a draft line (audit_ui.outputs), not a decision
        base = {"type": row["type"], "id": row["id"], "field": row["field"]}
        if v["verdict"] == "match":
            if v.get("words"):
                match_words.append(base | {"ja_hash": row["ja_hash"], "words": v["words"]})
            continue
        note = f"{v['kind']}: {v['problem']}"
        if v["verdict"] == "correct":
            dec.append(base | {"decision": "correct", "ja": v["ja"], "note": note})
            if v.get("words"):
                correct_words.append(base | {"ja_hash": readings.ja_hash(v["ja"]), "words": v["words"]})
        else:
            dec.append(base | {"decision": "redraft", "note": note})
    return {"audit.decisions.jsonl": dec, "audit.words.jsonl": match_words,
            "audit.correct-words.jsonl": correct_words}


def render(pairs: list[tuple[dict[str, Any], dict[str, Any]]], examples: int = 3) -> str:
    table: dict[tuple[str, str], Counter] = defaultdict(Counter)
    kinds: dict[str, list[tuple[dict[str, Any], dict[str, Any]]]] = defaultdict(list)
    for row, v in pairs:
        table[(row["type"], row["field"])][v["verdict"]] += 1
        if v["verdict"] != "match":
            kinds[v["kind"]].append((row, v))
    out = ["| Type | Field | Lines | Match | Correct | Redraft | Split |", "|---|---|---|---|---|---|---|"]
    total: Counter = Counter()
    for (t, f), c in sorted(table.items()):
        n = sum(c.values())
        total.update(c)
        counts = " | ".join(f"{c[v]:,}" for v in VERDICTS)
        out.append(f"| {t} | {f} | {n:,} | {counts} |")
    out.append(f"| **all** | | **{sum(total.values()):,}** | **{total['match']:,}** | "
               f"**{total['correct']:,}** | **{total['redraft']:,}** | **{total['split']:,}** |")
    out += ["", "| Kind | Correct | Redraft | Split |", "|---|---|---|---|"]
    for k in KINDS:
        c = Counter(v["verdict"] for _, v in kinds.get(k, []))
        if c:
            out.append(f"| {k} | {c['correct']:,} | {c['redraft']:,} | {c['split']:,} |")
    for k in KINDS:
        for row, v in kinds.get(k, [])[:examples]:
            head = f"**{k}** · {row['type']} {row['id']} {row['field']} · {v['verdict']}: {v['problem']}"
            out += ["", head, f"- EN: {row['en']}", f"- JA: {row['ja']}"]
            if v["verdict"] == "correct":
                out.append(f"- fix: {v['ja']}")
    return "\n".join(out) + "\n"


def report(d: Path, out: Path | None, partial: bool = False) -> int:
    """A part with no verdicts yet stops the report (a decisions list must cover every part) unless `partial`,
    which writes the report over the parts that have verdicts: a progress view, never the list to apply."""
    pairs, problems, missing = check_dir(d)
    for x in problems:
        print(x, file=sys.stderr)
    if missing:
        print(f"parts with no verdicts yet ({len(missing)}): {', '.join(missing)}", file=sys.stderr)
        if not partial:
            print("report: parts pending; nothing written (--partial for a progress view)", file=sys.stderr)
            return 1
    if problems:
        print(f"report: {len(problems)} problem(s); nothing written", file=sys.stderr)
        return 1
    for name, rows in outputs(pairs).items():
        write_jsonl(d / name, rows)
    ui_pairs = [(row, v) for row, v in pairs if row["type"] == "ui"]
    text = render(pairs)
    if ui_pairs:
        for name, body in audit_ui.outputs(ui_pairs).items():
            (d / name).write_text(body, encoding="utf-8")
        text += audit_ui.render(ui_pairs)
    if out:
        out.write_text(text, encoding="utf-8")
    c = Counter(v["verdict"] for _, v in pairs)
    print(f"report: {len(pairs)} verdicts · match {c['match']} · correct {c['correct']} · "
          f"redraft {c['redraft']} · split {c['split']}"
          + (f" · {len(missing)} part(s) pending" if missing else ""))
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="wfj.dev.audit_batch", description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("cut")
    c.add_argument("--type", required=True, choices=TYPES)
    c.add_argument("--size", type=int, required=True)
    c.add_argument("--out-dir", type=Path, required=True)
    c.add_argument("--prefix", default="part")
    c.add_argument("--words", type=Path, nargs="*", default=[], help="readings batches already written")
    k = sub.add_parser("check")
    k.add_argument("part", type=Path)
    r = sub.add_parser("report")
    r.add_argument("dir", type=Path)
    r.add_argument("--out", type=Path)
    r.add_argument("--partial", action="store_true", help="progress view over the finished parts")
    a = ap.parse_args(argv)
    if a.cmd == "cut":
        if a.size < 1:
            ap.error("--size must be positive")
        return cut(data_root(), a.type, a.size, a.out_dir, a.prefix, a.words)
    if a.cmd == "check":
        return check_part(a.part)
    return report(a.dir, a.out, a.partial)


if __name__ == "__main__":
    sys.exit(main())
