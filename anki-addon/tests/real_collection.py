"""Runs the add-on against a real Anki collection in a throwaway folder and prints what it saw, as JSON.

Run with the Python that Anki itself runs on, so `anki` (and Qt) are the real ones:

    <Anki's python> anki-addon/tests/real_collection.py <empty folder>

The test suite starts it (tests/python/test_anki_real.py) and checks the answers; nothing here touches a profile.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ADDON = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ADDON))

from anki.collection import Collection  # noqa: E402

from wfj_anki import discover, media, notetype, sync  # noqa: E402
from wfj_anki.collection import AnkiNotes  # noqa: E402
from wfj_anki.settings import Settings  # noqa: E402

KEY = "quest.description:456:生き物"
SHOT = "WoWScrnShot_112526_101500.jpg"
AUDIO = ["WoWForeverJapanese_VoiceA/Sound/a-1.mp3", "WoWForeverJapanese_VoiceA/Sound/a-2.mp3"]


def row(**over):
    base = {
        "key": KEY, "lang": "", "word": "生き物", "reading": "いきもの", "lemma": "生き物", "lemmaReading": "いきもの",
        "meaning": "living thing", "sentence": "少しの<b>生き物</b>たちを狩れ。", "wordFurigana": "生[い]き 物[もの]",
        "sentenceFurigana": "少しの<b>生[い]き 物[もの]</b>たちを狩れ。", "jaSentence": "", "source": "quest",
        "questId": 456, "questTitle": "生き物を減らせ", "saved": 1790000000, "shot": SHOT, "audio": AUDIO,
    }
    base.update(over)
    return base


def table(*rows, written=1790000000):
    return {"schema": 1, "written": written, "voice": True, "rows": list(rows)}


def game(folder: Path) -> discover.SavedFile:
    """A game folder with one big screenshot and two sound files."""
    from aqt.qt import QColor, QImage

    client = folder / "World of Warcraft" / "_forever_"
    (client / "Screenshots").mkdir(parents=True)
    image = QImage(3840, 2160, QImage.Format.Format_RGB32)
    image.fill(QColor(40, 30, 80))
    image.save(str(client / "Screenshots" / SHOT), "JPG", 95)
    sounds = client / "Interface" / "AddOns" / "WoWForeverJapanese_VoiceA" / "Sound"
    sounds.mkdir(parents=True)
    (sounds / "a-1.mp3").write_bytes(b"ID3 one")
    (sounds / "a-2.mp3").write_bytes(b"ID3 two")
    saved = client / "WTF" / "Account" / "ONE" / "SavedVariables"
    saved.mkdir(parents=True)
    (saved / discover.SAVED_NAME).write_text("WFJ_Anki = {}\n", encoding="utf-8")
    return discover.saved_files(folder / "World of Warcraft")[0]


def card_state(col, note_id):
    return col.db.all("select type, queue, due, ivl, factor, reps, lapses, left, odue, did from cards "
                      "where nid = ? order by ord", note_id)


def main() -> None:
    folder = Path(sys.argv[1])
    out: dict[str, object] = {}
    saved = game(folder)
    col = Collection(str(folder / "collection.anki2"))
    try:
        # a note of the player's own, in another note type, that holds the same key in its first field
        basic = col.models.by_name("Basic")
        other = col.new_note(basic)
        other["Front"], other["Back"] = KEY, "made by hand"
        col.add_note(other, col.decks.id("Default"))
        other_before = (list(other.fields), col.db.scalar("select mod from notes where id = ?", other.id))

        notes = AnkiNotes(col, Settings(), shrink=media.qt_shrink)
        out["prepared"] = notes.prepare()
        out["fields"] = [f["name"] for f in notes.model["flds"]]
        out["first"] = vars(sync.apply(notes, [(saved, table(row()))]))
        mine = notes.notes()
        note_id, fields = mine[KEY]
        out["note"] = fields
        out["deck"] = col.decks.name(col.db.scalar("select did from cards where nid = ?", note_id))
        out["cards"] = col.db.scalar("select count() from cards where nid = ?", note_id)
        media_dir = Path(col.media.dir())
        out["media"] = sorted(p.name for p in media_dir.iterdir() if p.name.startswith(media.PREFIX))
        picture = media_dir / f"{media.PREFIX}{Path(SHOT).stem}.jpg"
        out["picture_bytes"] = picture.stat().st_size if picture.is_file() else 0
        out["source_bytes"] = (saved.client / "Screenshots" / SHOT).stat().st_size
        from aqt.qt import QImage
        out["picture_width"] = QImage(str(picture)).width()

        # the same data again
        mod = col.db.scalar("select mod from notes where id = ?", note_id)
        out["second"] = vars(sync.apply(notes, [(saved, table(row()))]))
        out["second_untouched"] = col.db.scalar("select mod from notes where id = ?", note_id) == mod

        # study the card, so it has a schedule and a review on record
        col.decks.select(col.decks.id(notetype.DECK))
        card = col.sched.getCard()
        out["studied"] = card is not None and card.nid == note_id
        if card is not None:
            col.sched.answerCard(card, 3)
        state = card_state(col, note_id)
        reviews = col.db.all("select * from revlog order by id")
        out["reviews"] = len(reviews)

        # the game's value changes
        out["third"] = vars(sync.apply(notes, [(saved, table(row(meaning="a living thing")))]))
        after = notes.notes()[KEY][1]
        out["changed_fields"] = sorted(f for f in fields if fields[f] != after[f])
        out["meaning"] = after["Meaning"]
        out["schedule_kept"] = card_state(col, note_id) == state
        out["reviews_kept"] = col.db.all("select * from revlog order by id") == reviews

        # a field edited by hand, then a reset
        note = col.get_note(note_id)
        note["Meaning"] = "my own words"
        col.update_note(note)
        sync.apply(notes, [(saved, table(row(meaning="again", reading="イキモノ")))])
        kept = notes.notes()[KEY][1]
        out["edit_kept"] = (kept["Meaning"], kept["Reading"])
        out["reset"] = vars(sync.apply(notes, [(saved, table(row(meaning="again", reading="イキモノ")))],
                                       reset=notes.keys_of([note_id, other.id])))
        out["after_reset"] = notes.notes()[KEY][1]["Meaning"]
        out["schedule_kept_after_reset"] = card_state(col, note_id) == state
        out["reviews_kept_after_reset"] = col.db.all("select * from revlog order by id") == reviews

        # the player's own note
        other = col.get_note(other.id)
        out["other_untouched"] = (list(other.fields),
                                  col.db.scalar("select mod from notes where id = ?", other.id)) == other_before
        out["own_notes"] = len(notes.notes())
        out["all_notes"] = col.db.scalar("select count() from notes")

        # a word gone from the game
        out["gone"] = vars(sync.apply(notes, [(saved, table())]))
        out["still_there"] = KEY in notes.notes()

        # another card choice: the template changes, no note does
        mods = col.db.all("select id, mod from notes order by id")
        before = (notes.model["tmpls"][0]["qfmt"], notes.model["tmpls"][0]["afmt"])
        chosen = AnkiNotes(col, Settings(front="word", audio="front"), shrink=media.qt_shrink)
        out["choice_changed"] = chosen.prepare()
        out["template_differs"] = (chosen.model["tmpls"][0]["qfmt"], chosen.model["tmpls"][0]["afmt"]) != before
        out["choice_again"] = chosen.prepare()
        out["notes_untouched_by_choice"] = col.db.all("select id, mod from notes order by id") == mods
        out["card_count_after_choice"] = col.db.scalar("select count() from cards where nid = ?", note_id)
        out["question"] = col.get_note(note_id).cards()[0].question()

        # a note type the add-on made in an earlier version, with one field fewer
        model = chosen.model
        col.models.remove_field(model, next(f for f in model["flds"] if f["name"] == "Japanese sentence"))
        col.models.update_dict(model)
        older = AnkiNotes(col, Settings(), shrink=media.qt_shrink)
        out["upgraded"] = older.prepare()
        out["fields_after_upgrade"] = sorted(f["name"] for f in older.model["flds"]) == sorted(notetype.FIELDS)
        out["note_kept_through_upgrade"] = older.notes()[KEY][1]["Word"] == "生き物"
        out["schedule_kept_through_upgrade"] = card_state(col, note_id) == state

        # a note type of the same name that is the player's own
        col2 = Collection(str(folder / "second.anki2"))
        try:
            theirs = col2.models.new(notetype.NAME)
            col2.models.add_field(theirs, col2.models.new_field("Key"))
            template = col2.models.new_template("Card")
            template["qfmt"], template["afmt"] = "{{Key}}", "{{Key}}"
            col2.models.add_template(theirs, template)
            col2.models.add_dict(theirs)
            apart = AnkiNotes(col2, Settings())
            apart.prepare()
            out["own_name_when_taken"] = apart.model["name"]
            out["theirs_fields"] = [f["name"] for f in col2.models.by_name(notetype.NAME)["flds"]]
        finally:
            col2.close()
    finally:
        col.close()
    print(json.dumps(out, ensure_ascii=False, default=str))


if __name__ == "__main__":
    main()
