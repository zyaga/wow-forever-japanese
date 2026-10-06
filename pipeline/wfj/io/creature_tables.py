"""Who a creature display shows, from the client's own tables (CSVs written by `make tables-extract`): its
gender, and for a character-model display its race and sex. Voice casting reads it (docs/systems/voice.md).

- `CreatureDisplayInfo.Gender`: 0 male, 1 female, 2 none (every display, monsters included).
- `CreatureDisplayInfo.ExtendedDisplayInfoID` → `CreatureDisplayInfoExtra.DisplayRaceID` / `DisplaySexID`
  (0 male, 1 female): set only for displays built like a player character.
- `ChrRaces.ClientFileString`: the race's name ("NightElf", "Tauren").
"""

from __future__ import annotations

import csv
from dataclasses import dataclass
from pathlib import Path

from wfj.io import tables_stamp

TABLES = ("CreatureDisplayInfo", "CreatureDisplayInfoExtra", "ChrRaces")
_GENDER = {0: "male", 1: "female", 2: "none"}


@dataclass(frozen=True)
class Display:
    gender: str  # male · female · none
    race: str | None  # ChrRaces name, lowercased ("nightelf"); None for a display not built like a character


def _rows(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def read(folder: Path) -> tuple[dict[int, Display], str]:
    """display id → Display, and the source label of the three tables (`client@<build>`). Raises
    FileNotFoundError naming a missing table, ValueError when the three were extracted from different
    builds or are unstamped."""
    for t in TABLES:
        if not (folder / f"{t}.csv").is_file():
            raise FileNotFoundError(f"{folder / (t + '.csv')}: run make tables-extract")
    stamps = tables_stamp.read(folder)
    labels = {stamps.get(t) for t in TABLES}
    if None in labels or len(labels) != 1:
        raise ValueError(f"{folder}: {', '.join(TABLES)} are not stamped from one build ({labels})")
    build = next(iter(labels)).split("@", 1)[1]
    races = {int(r["ID"]): r["ClientFileString"].strip().lower() for r in _rows(folder / "ChrRaces.csv")}
    extra = {
        int(r["ID"]): (int(r["DisplayRaceID"]), int(r["DisplaySexID"]))
        for r in _rows(folder / "CreatureDisplayInfoExtra.csv")
    }
    out: dict[int, Display] = {}
    for r in _rows(folder / "CreatureDisplayInfo.csv"):
        gender = _GENDER.get(int(r["Gender"]), "none")
        race = None
        ext = extra.get(int(r["ExtendedDisplayInfoID"]))
        if ext:
            race = races.get(ext[0])
            gender = _GENDER.get(ext[1], gender)
        out[int(r["ID"])] = Display(gender, race)
    return out, f"client@{build}"
