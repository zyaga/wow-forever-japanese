"""The add-on's note type: its name, its fields and its one card, built from the chosen card choices.

The look belongs to the note type, so a changed choice rewrites the template and every card follows, old and new.
The template files hold both fronts and the front's audio between marker comments; the choice keeps one.
"""

from __future__ import annotations

import re
from pathlib import Path

from . import plan
from .settings import Settings

NAME = "WoW Forever Japanese"
DECK = "WoW Forever Japanese"
CARD = "Card"
FIELDS = plan.FIELDS
# a field no other note type of that name would have: how the add-on knows a note type is its own
OWN_FIELD = "Sync"

_HERE = Path(__file__).resolve().parent / "templates"
_BLOCK = re.compile(r"<!--(\w+)-->(.*?)<!--/\1-->\n?", re.DOTALL)


def _keep(template: str, kept: set[str]) -> str:
    return _BLOCK.sub(lambda m: m.group(2) + "\n" if m.group(1) in kept else "", template)


def card(settings: Settings, folder: Path = _HERE) -> tuple[str, str, str]:
    """→ the front template, the back template and the styling, for these choices."""
    kept = {settings.front}
    if settings.audio == "front":
        kept.add("audio")
    front = _keep((folder / "front.html").read_text(encoding="utf-8"), kept)
    back = (folder / "back.html").read_text(encoding="utf-8")
    css = (folder / "style.css").read_text(encoding="utf-8")
    return front, back, css
