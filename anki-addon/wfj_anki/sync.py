"""One sync: the game's saved words into the collection. The collection is whatever `apply` is handed, so the
rules are tested without Anki; `collection.py` is the real one."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any, Protocol

from . import discover, plan, savedvars

TABLE = "WFJ_Anki"


class Notes(Protocol):
    # the add-on's notes: (game, key) → (id, fields); a note made before notes named their game has ""
    def notes(self) -> dict[tuple[str, str], tuple[Any, dict[str, str]]]: ...
    def add(self, fields: dict[str, str], tags: list[str]) -> None: ...
    def update(self, note_id: Any, writes: dict[str, str], tags: list[str]) -> None: ...
    # a file into the media; its name there, or None
    def store(self, kind: str, path: Path) -> str | None: ...
    # for each place words are saved, the newest word a sync has seen
    def marks(self) -> dict[str, float]: ...
    def set_marks(self, marks: dict[str, float]) -> None: ...


@dataclass
class Result:
    added: int = 0
    updated: int = 0
    missing_images: int = 0
    missing_audio: int = 0
    words: int = 0
    files: int = 0
    tables: int = 0  # the saved files that hold the table the game writes for the add-on
    deleted: int = 0  # words left without a note: the player deleted their notes in Anki
    newer: bool = False  # a saved file was written by a newer addon version than this add-on reads

    @property
    def pending(self) -> bool:
        """Media was missing: the next sync looks again even when no saved file changed."""
        return self.missing_images > 0 or self.missing_audio > 0


def read(files: list[discover.SavedFile]) -> list[tuple[discover.SavedFile, Any]]:
    return [(f, savedvars.read(f.path, TABLE)) for f in files]


class _Media:
    """The rows' files into the collection, each file once a sync."""

    def __init__(self, col: Notes):
        self.col = col
        self.stored: dict[Path, str | None] = {}

    def _store(self, kind: str, path: Path | None) -> str | None:
        if path is None:
            return None
        if path not in self.stored:
            self.stored[path] = self.col.store(kind, path)
        return self.stored[path]

    def fetch(self, kind: str, row: plan.Row) -> str | None:
        """The field's text for the row's image or audio, or None when a file is missing."""
        if kind == "image":
            name = self._store(kind, discover.screenshot(row.client, row.shot))
            return plan.image_field(name) if name else None
        names = []
        for relative in row.audio:
            name = self._store(kind, discover.sound(row.client, relative))
            if not name:
                return None
            names.append(name)
        return plan.audio_field(names)


def _sizes(_kind: str, row: plan.Row) -> object:
    """Each of the row's sound files with its size: a line voiced again keeps its file names."""
    sizes = []
    for relative in row.audio:
        path = discover.sound(row.client, relative)
        try:
            sizes.append([relative, path.stat().st_size if path else None])
        except OSError:
            sizes.append([relative, None])
    return sizes


def games(tables: list[tuple[discover.SavedFile, Any]]) -> list[tuple[str, int, bool]]:
    """Each game the saved files are from: its name, how many words it holds for Anki, and whether its addon
    has written its list for Anki at all."""
    by_game: dict[str, list[tuple[discover.SavedFile, Any]]] = {}
    for saved, table in tables:
        by_game.setdefault(discover.game(saved.client), []).append((saved, table))
    return [
        (game, len(plan.rows(group)[0]), any(isinstance(table, dict) for _, table in group))
        for game, group in by_game.items()
    ]


def apply(
    col: Notes,
    tables: list[tuple[discover.SavedFile, Any]],
    reset: set[tuple[str, str]] | None = None,
    again: bool = False,
) -> Result:
    """Add a note for each new word and rewrite what changed in the others. With `reset`, only the notes of
    those games and keys are touched, and every field of them is written from the game.

    A word a sync has seen before and that has no note now was deleted in Anki by the player: it is not added
    again, unless `again` asks for every word of the game's list to have a note."""
    rows, newer = plan.rows(tables)
    result = Result(
        words=len(rows),
        files=len(tables),
        newer=newer,
        tables=sum(1 for _, table in tables if isinstance(table, dict)),
    )
    notes = col.notes()
    media = _Media(col)
    seen_before = dict(col.marks())
    for row in rows:
        named = row.identity
        # a note made before notes named their game is the word's note for the first game that has the word
        unnamed = ("", row.key)
        existing = notes.get(named)
        if existing is None and unnamed in notes:
            named, existing = unnamed, notes.pop(unnamed)
        if reset is not None and (existing is None or named not in reset):
            continue
        if existing is None and not again and row.saved <= seen_before.get(row.source, -1):
            result.deleted += 1
            continue
        writes, no_image, no_audio = plan.note_changes(
            row, existing[1] if existing else None, media.fetch, force=reset is not None, state=_sizes
        )
        result.missing_images += no_image
        result.missing_audio += no_audio
        # the game's tag goes on with the game's name, once: a tag the player takes off stays off
        tags = [plan.game_tag(row.game)] if "Game" in writes else []
        if existing is None:
            col.add({field: writes.get(field, "") for field in plan.FIELDS}, tags)
            result.added += 1
        elif writes:
            col.update(existing[0], writes, tags)
            result.updated += 1
    if reset is None:
        marks = dict(seen_before)
        for row in rows:
            marks[row.source] = max(marks.get(row.source, -1), row.saved)
        if marks != seen_before:
            col.set_marks(marks)
    return result


def due(seen: object, last_seen: object, last: Result | None, asked: bool) -> bool:
    """Whether a sync has anything to look at: the player asked, a saved file or a setting changed since the
    last one (`seen` against `last_seen`), or the last one could not find some media."""
    return asked or seen != last_seen or bool(last and last.pending)
