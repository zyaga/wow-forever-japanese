"""The add-on's side of an Anki collection: its note type, its deck, its notes and the media. The only module
that
calls Anki's collection, and it writes nothing but note types, notes' fields and media files: never a card, a
review or a schedule."""

from __future__ import annotations

import html
from pathlib import Path
from typing import Any

from . import media, notetype, plan
from .settings import Settings

# where the collection keeps a mark of the card the add-on last wrote: the card is rewritten when the add-on's
# own card changes (a card choice, a new version), never because the player changed the note type's template
CARD_MARK = "wowForeverJapaneseCard"
# and, for each place words are saved, the newest word a sync has seen: a word no newer than that with no note
# was deleted by the player, and stays deleted
SEEN_MARK = "wowForeverJapaneseSeen"


class AnkiNotes:
    def __init__(self, col: Any, settings: Settings, shrink: media.Shrink | None = None):
        self.col = col
        self.settings = settings
        self.shrink = shrink
        self.model: dict[str, Any] | None = None
        self._undo: int | None = None  # the sync's one step in Anki's undo list, started by its first write

    # ── the note type and the deck ───────────────────────────────────────────

    def _own(self) -> dict[str, Any] | None:
        """The add-on's note type. One of the same name that lacks the add-on's own field is the player's, and
        is
        left alone: the add-on's then takes a second name."""
        for name in (notetype.NAME, notetype.NAME + " (add-on)"):
            model = self.col.models.by_name(name)
            if model is None:
                self._name = name
                return None
            if any(f["name"] == notetype.OWN_FIELD for f in model["flds"]):
                return model
        raise RuntimeError("two note types use the add-on's names")

    def prepare(self) -> bool:
        """Make the note type, or bring one made earlier up to date: missing fields added (no note loses one),
        the
        card's template and styling as the choices have them. → whether anything was written."""
        front, back, css = notetype.card(self.settings)
        mark = plan.fingerprint("\0".join((front, back, css)))
        models = self.col.models
        model = self._own()
        if model is None:
            model = models.new(self._name)
            for name in notetype.FIELDS:
                models.add_field(model, models.new_field(name))
            template = models.new_template(notetype.CARD)
            template["qfmt"], template["afmt"] = front, back
            models.add_template(model, template)
            model["css"] = css
            models.add_dict(model)
            self.col.set_config(CARD_MARK, mark)
            self.model = models.by_name(self._name)
            return True
        changed = False
        have = {f["name"] for f in model["flds"]}
        for name in notetype.FIELDS:
            if name not in have:
                models.add_field(model, models.new_field(name))
                changed = True
        template = model["tmpls"][0]
        rewrite = self.col.get_config(CARD_MARK, None) != mark
        if rewrite and (template["qfmt"], template["afmt"], model["css"]) != (front, back, css):
            template["qfmt"], template["afmt"], model["css"] = front, back, css
            changed = True
        if changed:
            models.update_dict(model)
            model = models.get(model["id"])
        if rewrite:
            self.col.set_config(CARD_MARK, mark)
        self.model = model
        return changed

    def _deck(self) -> Any:
        return self.col.decks.id(notetype.DECK)

    # ── what a sync asks for ─────────────────────────────────────────────────

    def notes(self) -> dict[tuple[str, str], tuple[Any, dict[str, str]]]:
        assert self.model is not None
        names = [f["name"] for f in self.model["flds"]]
        found = {}
        for note_id, joined in self.col.db.all("select id, flds from notes where mid = ?", self.model["id"]):
            # Anki before 25.07 runs on Python 3.9, where zip() takes no `strict`
            fields = dict(zip(names, joined.split("\x1f")))
            named = (html.unescape(fields.get("Game", "")), html.unescape(fields.get("Key", "")))
            if named[1] and named not in found:
                found[named] = (note_id, fields)
        return found

    def _writing(self) -> None:
        if self._undo is None:
            self._undo = self.col.add_custom_undo_entry(notetype.NAME)

    def finish(self) -> Any:
        """Close the sync's undo step. → Anki's record of what changed, or None when no note was written."""
        if self._undo is None:
            return None
        changes = self.col.merge_undo_entries(self._undo)
        self._undo = None
        return changes

    def add(self, fields: dict[str, str], tags: list[str]) -> None:
        assert self.model is not None
        self._writing()
        note = self.col.new_note(self.model)
        for name, value in fields.items():
            note[name] = value
        for tag in tags:
            note.add_tag(tag)
        self.col.add_note(note, self._deck())

    def update(self, note_id: Any, writes: dict[str, str], tags: list[str]) -> None:
        self._writing()
        note = self.col.get_note(note_id)
        for name, value in writes.items():
            note[name] = value
        for tag in tags:
            note.add_tag(tag)
        self.col.update_note(note)

    def marks(self) -> dict[str, float]:
        marks = self.col.get_config(SEEN_MARK, None)
        return dict(marks) if isinstance(marks, dict) else {}

    def set_marks(self, marks: dict[str, float]) -> None:
        self.col.set_config(SEEN_MARK, marks)

    def store(self, kind: str, path: Path) -> str | None:
        ready = media.picture(path, self.shrink) if kind == "image" else media.sound(path)
        if ready is None:
            return None
        name, data = ready
        return self.col.media.write_data(name, data)

    def keys_of(self, note_ids: list[Any]) -> set[tuple[str, str]]:
        """The game and word key of those notes that are the add-on's."""
        assert self.model is not None
        keys = set()
        for note_id in note_ids:
            note = self.col.get_note(note_id)
            if note.mid == self.model["id"] and note["Key"]:
                keys.add((html.unescape(note["Game"]), html.unescape(note["Key"])))
        return keys
