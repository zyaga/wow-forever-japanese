"""Stat-word redraft: every shipped machine item and spell line that keeps a stat word in English letters,
redrafted with the interface's Japanese (`core/stat_words`). A word swap, not a new translation.

    python -m wfj.dev.draft_stat_words OUT_DIR --tag MODEL=TAG [--tag MODEL=TAG …] [--skip FILE]

Writes to OUT_DIR:

- `<tag>.<type>.jsonl`: draft rows `{id, field, ja}` for `wfj import draft`, one file per drafting model
  and type, because a draft names one model and each redrafted line keeps the model that wrote its words.
  `--tag` gives each drafting model the short tag its file and draft name carry; a model with no tag fails
  the run (named)
- `contexts.txt`: every distinct stretch of text around a swapped word with its count, to read for a
  stat word that is really a name before importing
- `lint.txt`: lines where the swap brought a `translate_lint` problem the old line did not have

`--skip FILE` lists `<type> <id> <field>` lines to leave out (a stat word the read found to be a name).

    python -m wfj.dev.draft_stat_words --move-accepts DATE

After the import: an accepted machine line that replaced hand-written text ruled `reject` keeps winning over
its redraft, because an accept beats every tiebreak. This moves the accept onto the redraft of that same text,
which then wins. The ruling keeps who made it, its date and its reason, and its note says where it moved;
the hand-written variants stay ruled `reject`.
A draft row differs from its line only by the swapped words: the run fails when reversing the swaps
does not give the old text back. Exit 1 when a swap brought a lint problem.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path
from typing import Any

from wfj.core import align, stat_words
from wfj.core.report import SHIPPED
from wfj.dev.glossary import GLOSSARY, read_glossary, read_required
from wfj.dev.lint_names import exempt_words
from wfj.dev.translate_lint import ALLOWLIST, check_row
from wfj.io.jsonl_store import Store

TYPES = ("item", "spell")
KIND = {("item", "description"): "item_description", ("spell", "description"): "spell_description",
        ("spell", "aura"): "spell_aura"}
CONTEXT = 12  # characters kept on each side of a swapped word in contexts.txt


def selected(line: dict[str, Any]) -> bool:
    """A shipped machine line that keeps a stat word in English letters on its own."""
    return (
        line["provenance"]["class"] == "machine"
        and line["status"] in SHIPPED
        and bool(stat_words.find(line["ja"]))
    )


def unswap(old: str, new: str) -> bool:
    """`new` is `old` with only stat words swapped: walking both texts, every stretch outside a stat word
    `old` keeps in English letters on its own (`stat_words.spans`, a whole Latin run) is identical, and each
    such word became exactly its Japanese."""
    at_old = at_new = 0
    for start, end, word in stat_words.spans(old):
        same = old[at_old:start]
        if new[at_new: at_new + len(same)] != same:
            return False
        at_new += len(same)
        ja = stat_words.STAT_WORDS[word]
        if new[at_new: at_new + len(ja)] != ja:
            return False
        at_new += len(ja)
        at_old = end
    return new[at_new:] == old[at_old:]


def contexts(ja: str) -> list[str]:
    """The text around each word the swap replaces, and nothing else."""
    return [ja[max(0, a - CONTEXT): b + CONTEXT].replace("\n", " ") for a, b, _ in stat_words.spans(ja)]


def draft(
    root: Path, tags: dict[str, str], skip: set[tuple[str, int, str]]
) -> tuple[dict[tuple[str, str], list[dict]], Counter]:
    """(tag, type) → draft rows, and the contexts of every swapped word."""
    store = Store(root / "data")
    out: dict[tuple[str, str], list[dict]] = {}
    seen: Counter = Counter()
    for type_ in TYPES:
        for line in store.load(type_):
            if not selected(line) or (type_, line["id"], line["field"]) in skip:
                continue
            model = line["provenance"]["model"]
            if model not in tags:
                raise ValueError(f"{type_} {line['id']}/{line['field']}: no draft tag for model {model}")
            new = stat_words.settle(line["ja"])
            if not unswap(line["ja"], new) or stat_words.find(new):
                raise ValueError(f"{type_} {line['id']}/{line['field']}: the swap is not clean")
            out.setdefault((tags[model], type_), []).append(
                {"id": line["id"], "field": line["field"], "ja": new})
            seen.update(contexts(line["ja"]))
    return out, seen


def lint_problems(root: Path, rows: dict[tuple[str, str], list[dict]]) -> list[str]:
    """Problems `translate_lint` finds on a redrafted line that it did not find on the line it replaces,
    for every line whose own English the store has (a line read against spliced spell text has none)."""
    allowlist = align.load_allowlist((root / ALLOWLIST).read_text(encoding="utf-8"))
    glossary = exempt_words(read_glossary(root / GLOSSARY))
    required = read_required(root / GLOSSARY)
    store, english = Store(root / "data"), Store(root / "data", english=True)
    out = []
    for type_ in TYPES:
        en = {(ln["id"], ln["field"]): ln["en"] for ln in english.load(type_)}
        old = {(ln["id"], ln["field"]): ln["ja"] for ln in store.load(type_)}
        for tag_type, drafted in rows.items():
            if tag_type[1] != type_:
                continue
            for row in drafted:
                k = (row["id"], row["field"])
                if k not in en:
                    continue
                batch_row = {"kind": KIND[(type_, row["field"])], "en": en[k]}
                before = set(check_row(batch_row, old[k], allowlist, glossary, required))
                added = [r for r in check_row(batch_row, row["ja"], allowlist, glossary, required)
                         if r not in before]
                if added:
                    out.append(f"{type_} {row['id']} {row['field']}: {'; '.join(added)}")
    return out


def moved_note(note: str, date_: str) -> str:
    return (f"{note} (moved on {date_} to this line's stat-word swap, with the maintainer's decision that "
            "tooltip stat words use the interface's Japanese, style guide sg12)").lstrip()


def move_accepts(lines: list[dict[str, Any]], date_: str) -> int:
    """Move `ruling: accept` from each accepted machine winner onto its stat-word redraft (a conflict entry
    from a `stat-words-` draft whose text is exactly the winner's, swapped), keeping its `by`, `date` and
    reason. Returns lines changed."""
    n = 0
    for ln in lines:
        ruling = ln.get("ruling") or {}
        if ln["provenance"]["class"] != "machine" or ruling.get("ruling") != "accept":
            continue
        for c in ln.get("conflicts", []):
            source = str(c["provenance"].get("source", ""))
            redraft = source.startswith("draft-stat-words-") and not c.get("ruling")
            if redraft and c["ja"] == stat_words.settle(ln["ja"]):
                c["ruling"] = {**ruling, "note": moved_note(str(ruling.get("note", "")), date_)}
                del ln["ruling"]
                n += 1
                break
    return n


def read_skip(path: Path | None) -> set[tuple[str, int, str]]:
    if path is None:
        return set()
    out = set()
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].split()
        if line:
            out.add((line[0], int(line[1]), line[2]))
    return out


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(prog="draft_stat_words", description=__doc__.split("\n\n")[0])
    ap.add_argument("out", type=Path, nargs="?")
    ap.add_argument("--tag", action="append", default=[], metavar="MODEL=TAG")
    ap.add_argument("--skip", type=Path)
    ap.add_argument("--move-accepts", metavar="DATE")
    args = ap.parse_args(argv)
    root = Path(__file__).resolve().parents[3]
    if args.move_accepts:
        store = Store(root / "data")
        for type_ in TYPES:
            lines = store.load(type_)
            n = move_accepts(lines, args.move_accepts)
            store.save(type_, lines)
            print(f"{type_}: moved {n} accept ruling(s) onto the redraft")
            # an accept left on a line that still keeps a stat word: its redraft is missing or already ruled
            for ln in lines:
                if (ln.get("ruling") or {}).get("ruling") == "accept" and selected(ln):
                    print(f"  not moved: {type_} {ln['id']} {ln['field']}")
        return 0
    if args.out is None:
        ap.error("OUT_DIR is required unless --move-accepts")
    if bad := [t for t in args.tag if "=" not in t]:
        ap.error(f"--tag takes MODEL=TAG, not {', '.join(bad)}")
    tags = dict(t.split("=", 1) for t in args.tag)
    rows, seen = draft(root, tags, read_skip(args.skip))
    args.out.mkdir(parents=True, exist_ok=True)
    for (tag, type_), drafted in sorted(rows.items()):
        text = "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in drafted)
        (args.out / f"{tag}.{type_}.jsonl").write_text(text, encoding="utf-8")
        print(f"{tag}.{type_}.jsonl: {len(drafted)} rows")
    (args.out / "contexts.txt").write_text(
        "".join(f"{n}\t{c}\n" for c, n in seen.most_common()), encoding="utf-8")
    problems = lint_problems(root, rows)
    (args.out / "lint.txt").write_text("".join(p + "\n" for p in problems), encoding="utf-8")
    print(f"contexts: {len(seen)} distinct · lint: {len(problems)} new problems")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
