"""wfj stats: coverage report over the committed data (no writes), then the gossip blast radius.

  wfj stats [--stale PATH [--dump SAVEDVARIABLES]...] [--delta REF [--capture PATH]]
      --stale: also write the quest lines to fix as JSONL (report.stale_rows)
      --dump:  compare with a collector dump's quest English as well (the live client's text, which
               `import english collector` does not store where pfQuest / VMaNGOS already has the field)
      --delta: also print what data/english gained, lost or changed since a git ref
               (report.english_delta), and the translation lines whose status moved
      --capture: write the turn-in capture list as JSONL: quests new or changed since REF
               (report.capture_rows)
      --unseen-since: count the English lines a client-table source has never provided
               (report.unseen_since): after a `--merge union` import, the ids that client has never had,
               and how many of them ship Japanese today
"""

from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Sequence
from pathlib import Path

from wfj.cmd.check import TYPES, vanilla_ids
from wfj.core import report
from wfj.core.model import FIELDS, english_line
from wfj.io.collector_dump import read_dump
from wfj.io.git_store import load_english_at, load_lines_at
from wfj.io.jsonl_store import Store
from wfj.paths import data_root

DELTA_TYPES = ("quest", "item", "spell", "ui", "gossip", "objective", "area", "book")


def dump_english(path: Path) -> list[dict]:
    """A collector dump's quest entries as English lines (src collector@<build>), validated by read_dump."""
    dump = read_dump(path.read_text(encoding="utf-8-sig"))
    return [
        english_line(e.id_, e.field, e.en, e.hash_, f"collector@{e.build}")
        for e in dump.entries
        if e.type_ == "quest"
    ]


def run(argv: Sequence[str]) -> int:
    p = argparse.ArgumentParser(prog="wfj stats")
    p.add_argument("--stale", metavar="PATH", help="write stale / English-mismatched quest lines as JSONL")
    p.add_argument("--dump", metavar="FILE", action="append", default=[], help="a collector dump to compare")
    p.add_argument("--delta", metavar="REF", help="print the data/english delta since a git ref")
    p.add_argument("--capture", metavar="PATH", help="write the turn-in capture list (needs --delta)")
    p.add_argument(
        "--unseen-since",
        metavar="SRC",
        help="count English lines a client-table source has never provided, e.g. db2@1.60.1.69913 or "
        "just db2: after a union import these are the ids that client has never shipped",
    )
    a = p.parse_args(list(argv))
    if a.dump and not a.stale:
        p.error("--dump needs --stale")
    if a.capture and not a.delta:
        p.error("--capture needs --delta")
    root = data_root()
    try:
        extra = [ln for d in a.dump for ln in dump_english(Path(d))]
        base = load_english_at(root.parent, a.delta, DELTA_TYPES) if a.delta else None
        base_lines = load_lines_at(root.parent, a.delta, TYPES, english=False) if a.delta else None
    except (ValueError, OSError) as e:  # read before printing anything: a bad dump or ref is a one-line error
        print(f"wfj stats: {e}", file=sys.stderr)
        return 1
    store, english = Store(root), Store(root, english=True)
    lines = {t: store.load(t) for t in TYPES}
    print(report.render(report.tally(lines), report.headline(lines, vanilla_ids(english))))
    print()
    print(report.gossip_radius(english.load("gossip"), store.load("gossip")))
    if a.unseen_since:
        seen = {t: english.load(t) for t in DELTA_TYPES}
        counts = report.unseen_since(seen, lines, a.unseen_since)
        print()
        print(f"English lines {a.unseen_since} has never provided:")
        total = unseen_total = shipping_total = 0
        for type_, (all_, unseen, shipping) in counts.items():
            total += all_
            unseen_total += unseen
            shipping_total += shipping
            if unseen:
                print(f"  {type_:18} {unseen:6} of {all_:6}   ({shipping} ship Japanese today)")
        print(f"  {'TOTAL':18} {unseen_total:6} of {total:6}   ({shipping_total} ship Japanese today)")
        print(
            "  a line still stamped by an older source is one this client has never had; when the count"
            "\n  stops falling between builds, those lines can be dropped on evidence rather than a guess"
        )
    if a.stale:
        rows = report.stale_rows(lines["quest"], english.load("quest") + extra, FIELDS["quest"])
        try:
            with Path(a.stale).open("w", encoding="utf-8", newline="\n") as f:
                for r in rows:
                    f.write(json.dumps(r, ensure_ascii=False) + "\n")
        except OSError as e:
            print(f"wfj stats: {e}", file=sys.stderr)
            return 1
        print()
        print(f"stale report: {len(rows)} quest lines → {a.stale}")
    if base is not None:
        head = {t: english.load(t) for t in DELTA_TYPES}
        print()
        shifts = {t: report.status_shift(base_lines[t], lines[t]) for t in TYPES}
        print(report.render_status_shift(a.delta, shifts))
        print()
        print(report.render_delta(a.delta, {t: report.english_delta(base[t], head[t]) for t in DELTA_TYPES}))
        if a.capture:
            rows = report.capture_rows(base["quest"], head["quest"])
            try:
                with Path(a.capture).open("w", encoding="utf-8", newline="\n") as f:
                    for r in rows:
                        f.write(json.dumps(r, ensure_ascii=False) + "\n")
            except OSError as e:
                print(f"wfj stats: {e}", file=sys.stderr)
                return 1
            print(f"capture list: {len(rows)} quests → {a.capture}")
    return 0
