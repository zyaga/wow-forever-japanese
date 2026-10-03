"""What each served text column is: the surface that ships it in Japanese, or why it is left out.

`pipeline/served_columns.txt` (generated, `make served-columns`) lists every text column the client serves.
`pipeline/served_dispositions.txt` (written by hand) gives each one exactly one disposition, one per line:

    <table>.f<field>  <disposition>  # evidence

A disposition is one of:

- `surface:<type>.<field>`: the text ships through a data type (`surface:spell.aura`), or
  `surface:ui:<Family>` through a UI key family (`surface:ui:FactionDescription`).
- `names`: names of people, places, creatures, items, spells, zones, factions, titles. Names stay English.
- `internal`: developer text the client never prints (file paths, script, tokens, filter lists). The evidence
  says what the values are.
- `no-display`: real prose the Forever client has no in-game place for. The evidence cites the UI source that
  shows it (a gated addon, a glue screen where addons do not run).
- `covered-by:<table>.f<field>`: the same text reaches the screen through another listed column.
- `empty`: no non-empty row on this build.

A server cache (`wdb-<name>.*`) is listed with its record count and needs a disposition the same way. A table
the reader cannot open is listed as `<table>.*` and needs a disposition too. `internal`, `no-display`
and `covered-by` need evidence; nothing else is accepted, so a column is never left out without a stated
reason.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

KINDS = ("surface", "names", "internal", "no-display", "covered-by", "empty")
NEEDS_EVIDENCE = ("internal", "no-display", "covered-by")
_LINE = re.compile(r"^(\S+)\s+(\S+)\s*(?:#\s*(.*))?$")
_SURFACE = re.compile(r"^(?:ui:[A-Za-z]+|[a-z]+\.(?:[a-z]+|\*))$")
_COLUMN = re.compile(r"^[a-z0-9_]+\.(?:f\d+|\*)$|^(?:hash-[0-9a-f]{8}|wdb-[a-z0-9_]+)\.\*$")


@dataclass(frozen=True)
class Disposition:
    kind: str
    target: str  # the surface or the covering column; "" for the other kinds
    evidence: str

    @property
    def label(self) -> str:
        return f"{self.kind}:{self.target}" if self.target else self.kind


def parse(path: Path) -> tuple[dict[str, Disposition], list[str]]:
    """({column: disposition}, problems) from a dispositions file; `#` lines are comments."""
    out: dict[str, Disposition] = {}
    problems: list[str] = []
    for n, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not raw.strip() or raw.startswith("#"):
            continue
        m = _LINE.match(raw.strip())
        if not m:
            problems.append(f"{path.name}:{n}: not `<column>  <disposition>  # evidence`")
            continue
        column, label, evidence = m.group(1), m.group(2), (m.group(3) or "").strip()
        kind, _, target = label.partition(":")
        if not _COLUMN.match(column):
            problems.append(f"{path.name}:{n}: {column} is not a column (<table>.f<field> or <table>.*)")
        if kind not in KINDS:
            problems.append(f"{path.name}:{n}: {column}: {label} is not one of {', '.join(KINDS)}")
            continue
        if kind == "surface" and not _SURFACE.match(target):
            problems.append(f"{path.name}:{n}: {column}: surface needs <type>.<field> or ui:<Family>")
        if kind == "covered-by" and not _COLUMN.match(target):
            problems.append(f"{path.name}:{n}: {column}: covered-by needs the covering column")
        if kind not in ("surface", "covered-by") and target:
            problems.append(f"{path.name}:{n}: {column}: {kind} takes no target")
        if kind in NEEDS_EVIDENCE and not evidence:
            problems.append(f"{path.name}:{n}: {column}: {kind} needs evidence after `#`")
        if column in out:
            problems.append(f"{path.name}:{n}: {column} has a second disposition")
            continue
        out[column] = Disposition(kind, target, evidence)
    return out, problems


def check(columns: dict[str, str], dispositions: dict[str, Disposition]) -> list[str]:
    """Every served column has a disposition, every disposition names a served column, and a covering
    column is itself served and shipped by a surface."""
    problems = [
        f"{c}: served but has no disposition ({columns[c]})"
        for c in sorted(columns.keys() - dispositions.keys())
    ]
    problems += [
        f"{c}: has a disposition but is no longer served"
        for c in sorted(dispositions.keys() - columns.keys())
    ]
    for c, d in sorted(dispositions.items()):
        if d.kind == "covered-by":
            other = dispositions.get(d.target)
            if d.target not in columns or other is None or other.kind != "surface":
                problems.append(f"{c}: covered by {d.target}, which is not a served column with a surface")
        if d.kind == "empty" and c in columns and not _empty(columns[c]):
            problems.append(f"{c}: marked empty but has text ({columns[c]})")
    return problems


def _empty(counts: str) -> bool:
    m = re.search(r"\btext=(\d+)", counts)
    return bool(m) and m.group(1) == "0"


def text_lines(counts: str) -> int:
    """The non-empty value count of a served_columns line's counts (a cache's record count; 0 for an
    unreadable table)."""
    m = re.search(r"\b(?:text|records)=(\d+)", counts)
    return int(m.group(1)) if m else 0
