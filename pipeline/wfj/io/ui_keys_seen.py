"""The list of client interface strings players' clients wrote into chat while the addon had no Japanese
for them: `pipeline/ui_keys_seen_in_chat.txt`, one name per line, sorted.

The collector keeps such a string's name and never the chat line (docs/systems/collector.md, "Interface
strings seen in chat"); the collector import adds the names here. The game's own code writes these lines,
so no client file lists which strings reach chat: play is the only way to find them.
"""

from __future__ import annotations

from collections.abc import Iterable
from pathlib import Path

from wfj.io.collector_dump import UI_KEY_NAME

PATH = Path("pipeline") / "ui_keys_seen_in_chat.txt"
HEADER = """\
# Client interface strings the game wrote into chat while the addon had no Japanese for them, by name.
# Players' English Collectors found them in play (the collector keeps the string's name, never the chat line);
# `make import-collector` and `make collector-intake` add names here. One name per line, sorted.
# Each name is either listed in pipeline/ui_keys.txt and translated (a chat line also needs its key in
# UIStrings.CHAT_FAMILIES), or given a line with its reason in pipeline/ui_exclusions.txt.
# tests/python/test_ui_keys_seen_in_chat.py fails while a name here is in neither.
"""


def read(path: Path) -> tuple[str, list[str]]:
    """→ (the comment lines at the top, the names). A missing file is the default header and no names."""
    if not path.is_file():
        return HEADER, []
    header: list[str] = []
    names: list[str] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line.startswith("#"):
            if not names:
                header.append(raw)
        elif line:
            names.append(line)
    return ("\n".join(header) + "\n" if header else HEADER), names


def merge(path: Path, found: Iterable[str]) -> list[str]:
    """Adds the names not listed yet and writes the file sorted; an unchanged list is not rewritten. A name
    that is not a global string's name is never written. → the names added, sorted"""
    header, names = read(path)
    have = set(names)
    added = sorted({n for n in found if UI_KEY_NAME.fullmatch(n)} - have)
    if added or not path.is_file():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(header + "".join(n + "\n" for n in sorted(have | set(added))), encoding="utf-8")
    return added
