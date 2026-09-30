"""The translation style version (ADR-023): one place for how a machine draft records which style
guide wrote it.

The style guide (`docs/content/translation-style-guide.md`) carries `version: sg<N>`. A draft of server-only
text (quest `progress` / `completion`, gossip `text`, book `text`) is imported under a
name ending in `-sg<N>` for that version, so its `provenance.source` reads `draft-<kind>-sg<N>@<date>`.
`status._rank` reads the version back from the source; `translate_batch` checks it when it writes an import
file and `wfj import draft` when it imports one.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any

STYLE_GUIDE = Path("docs/content/translation-style-guide.md")  # relative to the repo root
# Server-only text the style guide governs: type → fields. Other drafts (the UI dictionary) carry no version.
STYLED_FIELDS: dict[str, frozenset[str]] = {
    # every quest field a drafter writes is styled, so `import draft` checks the style version on all of them.
    "quest": frozenset({"title", "objectives", "description", "progress", "completion"}),
    "gossip": frozenset({"text"}),
    "book": frozenset({"text"}),
    "objective": frozenset({"text"}),  # server-written objective text
    "area": frozenset({"text"}),  # the quest cache's exploration / event objective text
}
DRAFT_NAME = re.compile(r"^[a-z0-9][a-z0-9-]{0,30}$")  # `wfj import draft --name`
NAME_VERSION = re.compile(r"-sg(\d+)$")  # a draft name's style version: `progress-sg3`
# the `-sg<N>` right before the date: `draft-progress-sg3@<date>`
SOURCE_VERSION = re.compile(r"-sg(\d+)@")
_GUIDE_VERSION = re.compile(r"^version:\s*sg(\d+)\s*$", re.M)


def guide_version(repo: Path) -> int:
    """The style guide's `version: sg<N>`; ValueError when the guide or the line is missing."""
    path = repo / STYLE_GUIDE
    if not path.is_file():
        raise ValueError(f"no style guide at {STYLE_GUIDE}")
    m = _GUIDE_VERSION.search(path.read_text(encoding="utf-8"))
    if not m:
        raise ValueError(f"no 'version: sg<N>' line in {STYLE_GUIDE}")
    return int(m.group(1))


def name_version(name: str) -> int | None:
    """The version a valid draft name ends in (`progress-sg3` → 3), else None."""
    m = NAME_VERSION.search(name) if DRAFT_NAME.match(name) else None
    return int(m.group(1)) if m else None


def source_version(provenance: dict[str, Any]) -> int:
    """The style version a machine draft was written under, from `-sg<N>@` in its source; 0 when none."""
    m = SOURCE_VERSION.search(str(provenance.get("source", "")))
    return int(m.group(1)) if m else 0


def check_name(name: str, version: int) -> None:
    """A draft name for server-only text must end in `-sg<version>` (the current style guide)."""
    if name_version(name) != version:
        raise ValueError(f"draft name {name!r} must end in -sg{version} (the style guide's version)")
