"""What one saved word becomes in Anki, and which of a note's fields a sync may write.

The rule for a note the add-on made: a field is written only while it still holds what the add-on last wrote there.
The note's `Sync` field keeps a fingerprint of each field's last written text, so a field the player changed by hand
is told apart from one the game changed, and the record travels with the collection. Nothing here touches Anki.
"""

from __future__ import annotations

import hashlib
import json
import time
import unicodedata
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Any

SCHEMA = 1  # the newest shape of the game's table this version reads

FIELDS = ["Key", "Word", "Reading", "Dictionary form", "Its reading", "Meaning", "Sentence", "Word (furigana)",
          "Japanese sentence", "Image", "Audio", "Source", "Quest", "Saved", "Lang", "Sync"]

# each field that is plain text, and the row value it shows
_TEXT = {"Word": "word", "Reading": "reading", "Dictionary form": "lemma", "Its reading": "lemmaReading",
         "Meaning": "meaning", "Sentence": "sentenceFurigana", "Word (furigana)": "wordFurigana",
         "Japanese sentence": "jaSentence", "Source": "source", "Quest": "questTitle", "Lang": "lang"}


@dataclass(frozen=True)
class Row:
    key: str
    client: Path  # the client folder the word was saved in: its media is there
    values: dict[str, Any]
    shot: str
    audio: tuple[str, ...]


def rows(tables: list[tuple[Any, Any]]) -> tuple[list[Row], bool]:
    """The words of every saved file, one per key (the newest file's when two hold the same key), in saved order.
    Also whether a table from a newer addon version was seen: it is passed over, never half read."""
    newer = False
    by_key: dict[str, tuple[float, Row]] = {}
    for saved, table in tables:
        if not isinstance(table, dict):
            continue
        schema = table.get("schema")
        if not isinstance(schema, int) or isinstance(schema, bool):
            continue
        if schema > SCHEMA:
            newer = True
            continue
        written = table.get("written")
        written = written if isinstance(written, (int, float)) and not isinstance(written, bool) else 0
        entries = table.get("rows")
        for entry in entries if isinstance(entries, list) else []:
            if not isinstance(entry, dict):
                continue
            key = entry.get("key")
            if not isinstance(key, str) or not key:
                continue
            if key in by_key and by_key[key][0] >= written:
                continue
            audio = entry.get("audio")
            by_key[key] = (written, Row(
                key=key, client=saved.client, values=entry, shot=_text(entry.get("shot")),
                audio=tuple(a for a in audio if isinstance(a, str)) if isinstance(audio, list) else ()))
    return [row for _, row in by_key.values()], newer


def _text(value: Any) -> str:
    if value is None or isinstance(value, (dict, list)):
        return ""
    if isinstance(value, bool):
        return ""
    return str(value)


def text_fields(row: Row) -> dict[str, str]:
    """The note's text fields as the game gives them."""
    out = {field: _text(row.values.get(name)) for field, name in _TEXT.items()}
    saved = row.values.get("saved")
    out["Saved"] = time.strftime("%Y-%m-%d", time.localtime(saved)) \
        if isinstance(saved, (int, float)) and not isinstance(saved, bool) else ""
    return out


def fingerprint(text: str) -> str:
    """A short mark of a field's text. Anki may store the same text in another Unicode form, so the form is fixed
    first."""
    return hashlib.sha1(unicodedata.normalize("NFC", text).encode("utf-8")).hexdigest()[:12]


def _record(text: str) -> tuple[dict[str, str], dict[str, str]]:
    try:
        record = json.loads(text) if text else {}
    except ValueError:
        record = {}
    if not isinstance(record, dict):
        record = {}
    wrote, sources = record.get("f"), record.get("src")
    return (dict(wrote) if isinstance(wrote, dict) else {}, dict(sources) if isinstance(sources, dict) else {})


def image_field(name: str) -> str:
    return f'<img src="{name}">'


def audio_field(names: list[str]) -> str:
    return "".join(f"[sound:{name}]" for name in names)


def note_changes(row: Row, current: dict[str, str] | None, fetch: Callable[[str, Row], str | None],
                 force: bool = False) -> tuple[dict[str, str], bool, bool]:
    """The fields to write for `row`: every field of a new note (`current` is None), else only the fields whose
    value changed and that the player has not edited. `fetch("image" | "audio", row)` brings the row's media into
    the collection and gives the field's text, or None when a file is missing. `force` writes edited fields too.
    → the fields to write, whether the image is missing, whether the audio is."""
    new = current is None
    now = current or {}
    wrote, sources = _record(now.get("Sync", ""))
    writes: dict[str, str] = {}

    def edited(field: str) -> bool:
        if new or force:
            return False
        last = wrote.get(field)
        if last is None:  # a field this note never had a value written to: empty means untouched
            return now.get(field, "") != ""
        return fingerprint(now.get(field, "")) != last

    def put(field: str, value: str) -> None:
        if new or now.get(field, "") != value:
            writes[field] = value
        wrote[field] = fingerprint(value)

    for field, value in text_fields(row).items():
        if not edited(field):
            put(field, value)

    missing = {"Image": False, "Audio": False}
    for field, kind, named in (("Image", "image", row.shot), ("Audio", "audio", list(row.audio))):
        if not named:
            # the game names no file (no screenshot taken, the voice pack off): what the note holds stays
            if new:
                put(field, "")
            continue
        if edited(field):
            continue
        mark = fingerprint(json.dumps(named))
        if not new and sources.get(field) == mark and now.get(field, "") != "":
            continue
        value = fetch(kind, row)
        if value is None:
            missing[field] = True
            if new:
                put(field, "")
            continue
        put(field, value)
        sources[field] = mark

    record = json.dumps({"f": wrote, "src": sources}, sort_keys=True)
    if new:
        writes["Key"] = row.key
    if record != now.get("Sync", ""):
        writes["Sync"] = record
    return writes, missing["Image"], missing["Audio"]
