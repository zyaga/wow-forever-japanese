"""The source stamp of the client-table CSVs (ADR-021): which source and build each CSV in a folder
came from.

`make tables-extract` and `make wago-fetch` write `tables-source.txt` next to the CSVs they write, one line
per table (`<table> <src>@<build>`) after every CSV is in place. The client-table imports (`wago-ids`,
`client-text`, `wago-ui`) read it and refuse, writing nothing, when a CSV has no stamp or a stamp other than
the `--src` / `--build` they were given: the label written into every English line then always names where the
text came from (a `make wago-fetch` into a folder after `make tables-extract` restamps those tables `wago`). A
CSV's table is its file name up to the first dot (`ItemSparse.csv`, `ItemSparse.excerpt.csv`)."""

from __future__ import annotations

from collections.abc import Iterable
from pathlib import Path

FILE = "tables-source.txt"
HEADER = "# <table> <src>@<build>: written by make tables-extract / make wago-fetch; do not edit\n"
REWRITE = "make tables-extract (db2) or make wago-fetch (wago) rewrites the CSVs and their stamp"


def table_of(csv: Path) -> str:
    return Path(csv).name.split(".", 1)[0]


def read(folder: Path) -> dict[str, str]:
    """{table: "<src>@<build>"}; {} when the folder has no stamp. A malformed line or a table listed twice
    raises ValueError (a duplicate is never resolved silently)."""
    path = Path(folder) / FILE
    if not path.is_file():
        return {}
    out: dict[str, str] = {}
    for n, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) != 2 or "@" not in parts[1]:
            raise ValueError(f"{path}:{n}: not `<table> <src>@<build>`: {line!r}")
        if parts[0] in out:
            raise ValueError(f"{path}:{n}: {parts[0]} stamped twice")
        out[parts[0]] = parts[1]
    return out


def write(folder: Path, tables: Iterable[str], label: str) -> None:
    """Stamp `tables` with `label` (`<src>@<build>`), keeping the other tables' lines."""
    stamps = read(folder)
    for t in tables:
        stamps[t] = label
    _save(folder, stamps)


def clear(folder: Path, tables: Iterable[str]) -> None:
    """Drop the stamp lines of `tables` (keeping the others). Run BEFORE their CSVs are replaced: a run cut
    off between the move and the new stamp then leaves those tables unstamped, which the imports refuse, never
    stamped with the old source."""
    stamps = read(folder)
    if not any(t in stamps for t in tables):
        return
    _save(folder, {t: label for t, label in stamps.items() if t not in set(tables)})


def _save(folder: Path, stamps: dict[str, str]) -> None:
    body = "".join(f"{t} {stamps[t]}\n" for t in sorted(stamps))
    (Path(folder) / FILE).write_text(HEADER + body, encoding="utf-8")


def check(csvs: Iterable[Path], src: str, build: str) -> None:
    """Every CSV is stamped `<src>@<build>`; otherwise ValueError naming the file, both labels and the fix."""
    want = f"{src}@{build}"
    for name in csvs:
        csv = Path(name)
        got = read(csv.parent).get(table_of(csv))
        if got is None:
            raise ValueError(f"{csv}: no source stamp for {table_of(csv)} in {csv.parent / FILE}; {REWRITE}")
        if got != want:
            raise ValueError(
                f"{csv}: stamped {got}, the import was told --src {src} --build {build}; the CSV came from "
                f"elsewhere; pass the stamped source and build, or {REWRITE}"
            )
