"""One sync: the game's saved words into the collection. The collection is whatever `apply` is handed, so the
rules are tested without Anki; `collection.py` is the real one."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any, Protocol

from . import discover, plan, savedvars

TABLE = "WFJ_Anki"


class Notes(Protocol):
    def notes(self) -> dict[str, tuple[Any, dict[str, str]]]: ...  # the add-on's notes: key → (id, fields)
    def add(self, fields: dict[str, str]) -> None: ...
    def update(self, note_id: Any, writes: dict[str, str]) -> None: ...
    def store(self, kind: str, path: Path) -> str | None: ...  # a file into the media; its name there, or None


@dataclass
class Result:
    added: int = 0
    updated: int = 0
    missing_images: int = 0
    missing_audio: int = 0
    words: int = 0
    files: int = 0
    newer: bool = False  # a saved file was written by a newer addon version than this add-on reads

    @property
    def pending(self) -> bool:
        """Media was missing: the next sync looks again even when no saved file changed."""
        return self.missing_images > 0 or self.missing_audio > 0


def read(files: list[discover.SavedFile]) -> list[tuple[discover.SavedFile, Any]]:
    return [(f, savedvars.read(f.path, TABLE)) for f in files]


def apply(col: Notes, tables: list[tuple[discover.SavedFile, Any]], reset: set[str] | None = None) -> Result:
    """Add a note for each word that has none and rewrite what changed in the others. With `reset`, only the notes
    of those keys are touched, and every field of them is written from the game."""
    rows, newer = plan.rows(tables)
    result = Result(words=len(rows), files=len(tables), newer=newer)
    notes = col.notes()
    stored: dict[Path, str | None] = {}

    def store(kind: str, path: Path | None) -> str | None:
        if path is None:
            return None
        if path not in stored:
            stored[path] = col.store(kind, path)
        return stored[path]

    def fetch(kind: str, row: plan.Row) -> str | None:
        if kind == "image":
            name = store(kind, discover.screenshot(row.client, row.shot))
            return plan.image_field(name) if name else None
        names = []
        for relative in row.audio:
            name = store(kind, discover.sound(row.client, relative))
            if not name:
                return None
            names.append(name)
        return plan.audio_field(names)

    for row in rows:
        existing = notes.get(row.key)
        if reset is not None and (existing is None or row.key not in reset):
            continue
        writes, no_image, no_audio = plan.note_changes(row, existing[1] if existing else None, fetch,
                                                       force=reset is not None)
        result.missing_images += no_image
        result.missing_audio += no_audio
        if existing is None:
            col.add({field: writes.get(field, "") for field in plan.FIELDS})
            result.added += 1
        elif writes:
            col.update(existing[0], writes)
            result.updated += 1
    return result
