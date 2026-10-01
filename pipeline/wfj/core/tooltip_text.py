"""Tooltip Japanese as it ships: the translator's manual line breaks joined (ADR-049).

The hand-written tooltip corpus breaks its lines by hand (`ダメージを⏎与えます。`), written for the
narrow tooltips of the original client. The client wraps a tooltip line itself, so a manual break now
lands wherever the translator's width ran out, mid-sentence, and the client's own wrap adds a second
break before it. The shipped text of a hand-written line (`human` / `correction`) drops a single break
the English does not have; `data/` keeps the text as the person wrote it. A paragraph break (a blank
line) is kept; a line whose English carries single breaks of its own keeps every break, because nothing
says which of the Japanese's breaks are the English's; a machine line is never touched (its breaks mirror
the template, inclusions and lists included). Carriage returns are dropped from every line, so a `\\r\\n`
break counts as one and none ships. Two Latin words a break kept apart get a space, so names do not run
together.

`shipped_ja` is the one place this happens: `generate` writes it, and the fix-report intake hashes it,
so a report's hash matches what the player saw.
"""

from __future__ import annotations

import re
from typing import Any

from wfj.core import decisions

SINGLE_BREAK = re.compile(r"(?<!\n)\n(?!\n)")
TYPES = ("item", "spell")
_ASCII = re.compile(r"[A-Za-z0-9]")


def _singles(text: str) -> int:
    return len(SINGLE_BREAK.findall(text.replace("\r\n", "\n")))


def _join(m: re.Match[str], text: str) -> str:
    before, after = text[m.start() - 1 : m.start()], text[m.end() : m.end() + 1]
    return " " if _ASCII.match(before) and _ASCII.match(after) else ""


def join_breaks(ja: str, en: str | None) -> str:
    """`ja` with carriage returns dropped and its single line breaks removed when `en` has none."""
    text = ja.replace("\r\n", "\n").replace("\r", "")
    if "\n" not in text or en is None or _singles(en) > 0:
        return text
    return SINGLE_BREAK.sub(lambda m: _join(m, text), text)


def shipped_ja(line: dict[str, Any], en: str | None) -> str:
    """The Japanese of a shipped item or spell line as the addon ships it: carriage returns dropped on every
    line, the manual breaks of a hand-written one joined."""
    ja = line.get("ja")
    if not isinstance(ja, str):
        return ja
    if not decisions.is_hand_written(line.get("provenance") or {}):
        return ja.replace("\r\n", "\n").replace("\r", "")
    return join_breaks(ja, en)


def joined(lines: list[dict[str, Any]], english: dict[tuple[int, str], str]) -> list[dict[str, Any]]:
    """Copies of `lines` whose `ja` is `shipped_ja`; a line that does not change is the same object."""
    out = []
    for ln in lines:
        text = shipped_ja(ln, english.get((ln["id"], ln["field"])))
        out.append(ln if text == ln.get("ja") else {**ln, "ja": text})
    return out
