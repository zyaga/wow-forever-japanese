"""The add-on's settings, as Anki keeps them (a JSON object per add-on). A value that is not one of the
choices
counts as not set, so a hand-edited config can never stop a sync."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

FRONTS = ("sentence", "word")  # what the front of a card shows
AUDIOS = ("back", "front")  # the side the sentence's recording first plays on


@dataclass(frozen=True)
class Settings:
    folder: str = ""  # the World of Warcraft folder; empty: look in the usual places
    front: str = FRONTS[0]
    audio: str = AUDIOS[0]


def from_config(conf: Any) -> Settings:
    conf = conf if isinstance(conf, dict) else {}
    folder, front, audio = conf.get("folder"), conf.get("front"), conf.get("audio")
    return Settings(
        folder=folder.strip() if isinstance(folder, str) else "",
        front=front if front in FRONTS else FRONTS[0],
        audio=audio if audio in AUDIOS else AUDIOS[0],
    )


def to_config(settings: Settings) -> dict[str, str]:
    return {"folder": settings.folder, "front": settings.front, "audio": settings.audio}
