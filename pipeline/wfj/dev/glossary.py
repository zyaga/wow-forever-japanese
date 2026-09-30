"""The translation glossary: recurring English words that are translated, not kept in English
letters, with their Japanese: `pipeline/translation_glossary.tsv`, `<English>\t<Japanese>[\trequired]` per
line. A `required` term must appear in exactly the glossary's Japanese (`translate_lint`'s `glossary:<term>`).
"""

from __future__ import annotations

import re
from pathlib import Path

GLOSSARY = Path("pipeline/translation_glossary.tsv")  # relative to the repo root


def _glossary_rows(path: Path) -> list[tuple[str, str, bool]]:
    rows: list[tuple[str, str, bool]] = []
    seen: set[str] = set()
    for n, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not raw.strip() or raw.startswith("#"):
            continue
        cells = raw.split("\t")
        if len(cells) not in (2, 3) or not cells[0].strip() or not cells[1].strip():
            raise ValueError(f"{path.name}:{n}: need '<English>\\t<Japanese>[\\trequired]'")
        if len(cells) == 3 and cells[2].strip() != "required":
            raise ValueError(f"{path.name}:{n}: the third column may only be 'required'")
        key = cells[0].strip().casefold()
        if key in seen:
            raise ValueError(f"{path.name}:{n}: {cells[0].strip()!r} listed twice")
        seen.add(key)
        rows.append((key, cells[1].strip(), len(cells) == 3))
    return rows


def read_glossary(path: Path) -> dict[str, str]:
    """`<English>\\t<Japanese>[\\trequired]` per line, `#` comments. English compares case-insensitively."""
    return {en: ja for en, ja, _ in _glossary_rows(path)}


def read_required(path: Path) -> dict[str, str]:
    """The glossary terms marked `required`: a draft must use exactly that Japanese."""
    return {en: ja for en, ja, required in _glossary_rows(path) if required}


def term_pattern(term: str) -> re.Pattern[str]:
    """The term or its plural (`dwarf` / `dwarfs` / `dwarves`, `night elf` / `night elves`), whole words. The
    boundary is any non-Latin character, so a word kept in English letters inside Japanese (`Warriorを`)
    matches."""
    forms = [re.escape(term) + "(?:s|es)?"]
    if term.endswith("f"):
        forms.append(re.escape(term[:-1]) + "ves")
    return re.compile(r"(?<![A-Za-z])(?:" + "|".join(forms) + r")(?![A-Za-z])", re.I)
