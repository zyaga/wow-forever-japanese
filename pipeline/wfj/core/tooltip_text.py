"""Tooltip Japanese as it ships: the translator's manual line breaks joined (ADR-049).

The hand-written tooltip corpus breaks its lines by hand (`ダメージを⏎与えます。`), written for the
narrow tooltips of the original client. The client wraps a tooltip line itself, so a manual break now
lands wherever the translator's width ran out, mid-sentence, and the client's own wrap adds a second
break before it. The shipped text drops a single break the English does not have; `data/` keeps the
text as the person wrote it. A paragraph break (a blank line) is kept, and a line whose English carries
single breaks of its own keeps every break, because nothing says which of the Japanese's breaks are the
English's.
"""

from __future__ import annotations

import re
from typing import Any

SINGLE_BREAK = re.compile(r"(?<!\n)\n(?!\n)")
TYPES = ("item", "spell")


def _singles(text: str) -> int:
    return len(SINGLE_BREAK.findall(text.replace("\r\n", "\n")))


def join_breaks(ja: str, en: str | None) -> str:
    """`ja` with its single line breaks removed when `en` has none; unchanged otherwise."""
    if "\n" not in ja or en is None or _singles(en) > 0:
        return ja
    return SINGLE_BREAK.sub("", ja)


def joined(lines: list[dict[str, Any]], english: dict[tuple[int, str], str]) -> list[dict[str, Any]]:
    """Copies of `lines` whose `ja` is joined against the line's English; a line without English is
    untouched."""
    out = []
    for ln in lines:
        ja = ln.get("ja")
        text = join_breaks(ja, english.get((ln["id"], ln["field"]))) if isinstance(ja, str) else ja
        out.append(ln if text == ja else {**ln, "ja": text})
    return out
