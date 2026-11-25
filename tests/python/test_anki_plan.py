"""What a sync of the Anki add-on adds, rewrites and leaves alone, against a stand-in for the collection."""

import html
from pathlib import Path

from anki_addon import FIXTURES  # noqa: F401  (puts the add-on on the path)
from wfj_anki import plan, sync
from wfj_anki.discover import SavedFile

CLIENT = Path("/game/_forever_")
FILE = SavedFile(CLIENT, CLIENT / "WTF/Account/ONE/SavedVariables/WoWForeverJapanese.lua")


def row(**over):
    base = {
        "key": "quest.description:456:生き物",
        "lang": "",
        "word": "生き物",
        "reading": "いきもの",
        "lemma": "生き物",
        "lemmaReading": "いきもの",
        "meaning": "living thing",
        "sentence": "少しの<b>生き物</b>たちを狩れ。",
        "wordFurigana": "生[い]き 物[もの]",
        "sentenceFurigana": "少しの<b>生[い]き 物[もの]</b>たちを狩れ。",
        "jaSentence": "",
        "source": "quest",
        "questId": 456,
        "questTitle": "生き物を減らせ",
        "saved": 1790000000,
        "shot": "",
        "audio": {},
    }
    base.update(over)
    return base


def table(*rows, written=1790000000, voice=True):
    return {"schema": 1, "written": written, "voice": voice, "rows": list(rows)}


class Collection:
    """The collection as the sync sees it: the add-on's notes by key, other notes it must never see, and media."""

    def __init__(self, files=()):
        self.mine = {}  # note id → fields
        self.media = {}
        self.files = set(files)  # the files that exist in the game's folders
        self.stored = []
        self.next = 1
        self.seen = {}

    def marks(self):
        return dict(self.seen)

    def set_marks(self, marks):
        self.seen = dict(marks)

    def notes(self):
        return {html.unescape(fields["Key"]): (note_id, dict(fields)) for note_id, fields in self.mine.items()}

    def add(self, fields):
        self.mine[self.next] = dict(fields)
        self.next += 1

    def update(self, note_id, writes):
        self.mine[note_id].update(writes)

    def store(self, kind, path):
        if str(path) not in self.files:
            return None
        self.stored.append(str(path))
        return "wfj-" + Path(path).name

    def note(self, key=None):
        if key is None:
            assert len(self.mine) == 1
            return next(iter(self.mine.values()))
        return next(f for f in self.mine.values() if f["Key"] == key)


def run(col, *tables, reset=None, again=False):
    return sync.apply(col, [(FILE, t) for t in tables], reset=reset, again=again)


def test_a_new_word_becomes_one_note_with_its_fields():
    col = Collection()
    result = run(col, table(row()))
    assert (result.added, result.updated) == (1, 0)
    note = col.note()
    assert note["Key"] == "quest.description:456:生き物"
    assert note["Word"] == "生き物"
    assert note["Reading"] == "いきもの"
    assert note["Dictionary form"] == "生き物"
    assert note["Its reading"] == "いきもの"
    assert note["Meaning"] == "living thing"
    assert note["Sentence"] == "少しの<b>生[い]き 物[もの]</b>たちを狩れ。"
    assert note["Word (furigana)"] == "生[い]き 物[もの]"
    assert note["Source"] == "quest"
    assert note["Quest"] == "生き物を減らせ"
    assert note["Quest ID"] == "456"
    assert note["Saved"].startswith("2026-")
    assert note["Lang"] == ""
    assert note["Image"] == "" and note["Audio"] == ""
    assert set(note) == set(plan.FIELDS)


def test_the_same_data_twice_adds_and_changes_nothing():
    col = Collection()
    run(col, table(row()))
    before = {k: dict(v) for k, v in col.mine.items()}
    result = run(col, table(row()))
    assert (result.added, result.updated) == (0, 0)
    assert col.mine == before


def test_a_changed_value_rewrites_that_field_only():
    col = Collection()
    run(col, table(row()))
    before = dict(col.note())
    result = run(col, table(row(meaning="a living thing")))
    assert (result.added, result.updated) == (0, 1)
    after = col.note()
    changed = {f for f in plan.FIELDS if after[f] != before[f]}
    assert changed == {"Meaning", "Sync"}
    assert after["Meaning"] == "a living thing"


def test_a_field_edited_by_hand_is_kept_while_the_others_update():
    col = Collection()
    run(col, table(row()))
    col.note()["Meaning"] = "my own note"
    result = run(col, table(row(meaning="a living thing", reading="イキモノ")))
    assert result.updated == 1
    assert col.note()["Meaning"] == "my own note"
    assert col.note()["Reading"] == "イキモノ"
    # and stays kept on every later sync
    run(col, table(row(meaning="another", reading="イキモノ")))
    assert col.note()["Meaning"] == "my own note"


def test_an_edit_that_puts_the_games_value_back_is_no_longer_an_edit():
    col = Collection()
    run(col, table(row()))
    col.note()["Meaning"] = "mine"
    run(col, table(row()))
    col.note()["Meaning"] = "living thing"
    run(col, table(row(meaning="changed")))
    assert col.note()["Meaning"] == "changed"


def test_reset_rewrites_an_edited_field_from_the_game():
    col = Collection()
    run(col, table(row(), row(key="k2", word="数")))
    col.note("quest.description:456:生き物")["Meaning"] = "mine"
    col.note("k2")["Meaning"] = "also mine"
    result = run(col, table(row(), row(key="k2", word="数")), reset={"quest.description:456:生き物"})
    assert result.updated == 1
    assert col.note("quest.description:456:生き物")["Meaning"] == "living thing"
    assert col.note("k2")["Meaning"] == "also mine"  # not one of the notes asked for
    assert result.added == 0


def test_a_word_gone_from_the_game_keeps_its_note():
    col = Collection()
    run(col, table(row(), row(key="k2", word="数")))
    before = dict(col.note("k2"))
    result = run(col, table(row()))
    assert (result.added, result.updated) == (0, 0)
    assert col.note("k2") == before


def test_media_is_stored_and_named_in_the_fields():
    shot = CLIENT / "Screenshots" / "WoWScrnShot_112526_101500.jpg"
    a1 = CLIENT / "Interface/AddOns/WoWForeverJapanese_VoiceA/Sound/a-1.mp3"
    a2 = CLIENT / "Interface/AddOns/WoWForeverJapanese_VoiceA/Sound/a-2.mp3"
    col = Collection(files={str(shot), str(a1), str(a2)})
    audio = ["WoWForeverJapanese_VoiceA/Sound/a-1.mp3", "WoWForeverJapanese_VoiceA/Sound/a-2.mp3"]
    result = run(col, table(row(shot=shot.name, audio=audio)))
    note = col.note()
    assert note["Image"] == '<img src="wfj-WoWScrnShot_112526_101500.jpg">'
    assert note["Audio"] == "[sound:wfj-a-1.mp3][sound:wfj-a-2.mp3]"
    assert (result.missing_images, result.missing_audio) == (0, 0)
    # nothing is stored again while the row names the same files
    col.stored.clear()
    again = run(col, table(row(shot=shot.name, audio=audio)))
    assert col.stored == [] and again.updated == 0


def test_a_missing_file_leaves_the_field_and_is_tried_again():
    shot = CLIENT / "Screenshots" / "WoWScrnShot_112526_101500.jpg"
    a1 = CLIENT / "Interface/AddOns/WoWForeverJapanese_VoiceA/Sound/a-1.mp3"
    audio = ["WoWForeverJapanese_VoiceA/Sound/a-1.mp3", "WoWForeverJapanese_VoiceA/Sound/a-2.mp3"]
    col = Collection(files={str(a1)})  # no screenshot, and one of the two sound files
    result = run(col, table(row(shot=shot.name, audio=audio)))
    assert (result.added, result.missing_images, result.missing_audio) == (1, 1, 1)
    assert col.note()["Image"] == "" and col.note()["Audio"] == ""
    col.files |= {str(shot), str(a1.with_name("a-2.mp3"))}
    result = run(col, table(row(shot=shot.name, audio=audio)))
    assert (result.updated, result.missing_images, result.missing_audio) == (1, 0, 0)
    assert col.note()["Image"] != "" and col.note()["Audio"].count("[sound:") == 2


def test_a_field_with_media_is_never_emptied():
    shot = CLIENT / "Screenshots" / "WoWScrnShot_112526_101500.jpg"
    a1 = CLIENT / "Interface/AddOns/WoWForeverJapanese_VoiceA/Sound/a-1.mp3"
    col = Collection(files={str(shot), str(a1)})
    run(col, table(row(shot=shot.name, audio=["WoWForeverJapanese_VoiceA/Sound/a-1.mp3"])))
    before = dict(col.note())
    # the pack was off at logout, and the screenshot is gone from the list
    result = run(col, table(row(shot="", audio={}), voice=False))
    assert result.updated == 0
    assert col.note() == before
    # and a file deleted from the game's folder later changes nothing either
    col.files.clear()
    run(col, table(row(shot=shot.name, audio=["WoWForeverJapanese_VoiceA/Sound/a-1.mp3"])))
    assert col.note() == before


def test_a_new_recording_replaces_the_old_one():
    a1 = CLIENT / "Interface/AddOns/WoWForeverJapanese_VoiceA/Sound/a-1.mp3"
    b1 = CLIENT / "Interface/AddOns/WoWForeverJapanese_VoiceA/Sound/b-1.mp3"
    col = Collection(files={str(a1), str(b1)})
    run(col, table(row(audio=["WoWForeverJapanese_VoiceA/Sound/a-1.mp3"])))
    run(col, table(row(audio=["WoWForeverJapanese_VoiceA/Sound/b-1.mp3"])))
    assert col.note()["Audio"] == "[sound:wfj-b-1.mp3]"


def test_a_path_outside_the_games_folders_is_never_read():
    col = Collection(files={"/etc/passwd", str(CLIENT / "Screenshots" / ".." / "secret.jpg")})
    result = run(col, table(row(shot="../secret.jpg", audio=["../../../etc/passwd"])))
    assert col.stored == []
    assert col.note()["Image"] == "" and col.note()["Audio"] == ""
    assert (result.missing_images, result.missing_audio) == (1, 1)


def test_an_english_word_carries_its_japanese_sentence():
    col = Collection()
    run(
        col,
        table(
            row(
                key="quest.description:456:en:creatures",
                lang="en",
                word="creatures",
                reading="KREE-churz",
                lemma="",
                lemmaReading="",
                meaning="生き物 (いきもの)",
                wordFurigana="creatures",
                sentenceFurigana="Hunt a few <b>creatures</b>.",
                jaSentence="少しの生き物たちを狩れ。",
            )
        ),
    )
    note = col.note()
    assert note["Lang"] == "en"
    assert note["Sentence"] == "Hunt a few <b>creatures</b>."
    assert note["Japanese sentence"] == "少しの生き物たちを狩れ。"


def test_the_same_key_in_two_files_takes_the_newest():
    col = Collection()
    other = SavedFile(Path("/game/_retail_"), Path("/game/_retail_/WTF/Account/ONE/SavedVariables/x.lua"))
    result = sync.apply(
        col,
        [
            (FILE, table(row(meaning="old"), written=100)),
            (other, table(row(meaning="new"), row(key="k2"), written=200)),
        ],
    )
    assert result.added == 2
    assert col.note("quest.description:456:生き物")["Meaning"] == "new"


def test_tables_and_rows_that_are_not_what_the_addon_writes_are_passed_over():
    col = Collection()
    bad = [
        None,
        {},
        {"schema": 2, "rows": [row()]},
        {"schema": 1, "rows": "x"},
        {"schema": 1, "rows": [None, {"word": "no key"}, {"key": ""}, {"key": 5}, row(key="ok", word=7)]},
    ]
    result = sync.apply(col, [(FILE, t) for t in bad])
    assert result.added == 1
    assert col.note("ok")["Word"] == "7"
    assert result.newer is True  # a table from a newer addon version was seen


def test_a_field_added_by_a_later_version_fills_an_older_note():
    col = Collection()
    run(col, table(row()))
    note = col.note()
    del note["Japanese sentence"]  # as a note made before the field existed reads: no value, no record of one
    import json

    record = json.loads(note["Sync"])
    record["f"].pop("Japanese sentence", None)
    note["Sync"] = json.dumps(record)
    note["Japanese sentence"] = ""
    run(col, table(row(jaSentence="文。")))
    assert col.note()["Japanese sentence"] == "文。"


def test_reset_rewrites_an_edited_image_and_audio_too():
    shot = CLIENT / "Screenshots" / "WoWScrnShot_112526_101500.jpg"
    a1 = CLIENT / "Interface/AddOns/WoWForeverJapanese_VoiceA/Sound/a-1.mp3"
    col = Collection(files={str(shot), str(a1)})
    data = table(row(shot=shot.name, audio=["WoWForeverJapanese_VoiceA/Sound/a-1.mp3"]))
    run(col, data)
    col.note()["Image"], col.note()["Audio"] = '<img src="mine.jpg">', "[sound:mine.mp3]"
    run(col, data)
    assert col.note()["Image"] == '<img src="mine.jpg">'  # kept by an ordinary sync
    result = run(col, data, reset={"quest.description:456:生き物"})
    assert result.updated == 1
    assert col.note()["Image"] == '<img src="wfj-WoWScrnShot_112526_101500.jpg">'
    assert col.note()["Audio"] == "[sound:wfj-a-1.mp3]"


def test_a_note_deleted_in_anki_stays_deleted():
    col = Collection()
    run(col, table(row(), row(key="k2", word="数", saved=1790000100)))
    gone = next(i for i, f in col.mine.items() if f["Key"] == "k2")
    del col.mine[gone]
    later = table(row(), row(key="k2", word="数", saved=1790000100), row(key="k3", word="森", saved=1790000200))
    result = run(col, later)
    assert (result.added, result.deleted) == (1, 1)  # the new word arrives, the deleted one does not come back
    assert {f["Key"] for f in col.mine.values()} == {"quest.description:456:生き物", "k3"}
    # until the player asks for every word again
    result = run(col, later, again=True)
    assert (result.added, result.deleted) == (1, 0)
    assert len(col.mine) == 3


def test_another_account_s_older_words_are_still_new():
    col = Collection()
    run(col, table(row(saved=1790000500)))
    other = SavedFile(Path("/game/_retail_"), Path("/game/_retail_/WTF/Account/TWO/SavedVariables/x.lua"))
    result = sync.apply(col, [(FILE, table(row(saved=1790000500))), (other, table(row(key="k2", saved=1780000000)))])
    assert result.added == 1


def test_a_line_voiced_again_under_the_same_file_name_replaces_the_recording(tmp_path):
    client = tmp_path / "_forever_"
    sound = client / "Interface/AddOns/WoWForeverJapanese_VoiceA/Sound/a-1.mp3"
    sound.parent.mkdir(parents=True)
    sound.write_bytes(b"first")
    saved = SavedFile(client, client / "WTF/Account/ONE/SavedVariables/WoWForeverJapanese.lua")

    class Disk(Collection):
        def store(self, kind, path):
            if not Path(path).is_file():
                return None
            self.stored.append(Path(path).read_bytes())
            return f"voiced{len(self.stored)}.mp3"

    col = Disk()
    data = [(saved, table(row(audio=["WoWForeverJapanese_VoiceA/Sound/a-1.mp3"])))]
    sync.apply(col, data)
    sync.apply(col, data)
    assert col.stored == [b"first"]
    sound.write_bytes(b"voiced again")
    result = sync.apply(col, data)
    assert col.stored == [b"first", b"voiced again"] and result.updated == 1
    assert col.note()["Audio"] == "[sound:voiced2.mp3]"
    # the pack is taken out: the card keeps its recording, and nothing is reported missing
    sound.unlink()
    result = sync.apply(col, data)
    assert (result.updated, result.missing_audio) == (0, 0)
    assert col.note()["Audio"] == "[sound:voiced2.mp3]"


def test_a_key_with_markup_in_it_is_matched_and_never_shown_as_markup():
    col = Collection()
    run(col, table(row(key="chat:chat:<b>&x")))
    assert col.note()["Key"] == "chat:chat:&lt;b&gt;&amp;x"
    assert run(col, table(row(key="chat:chat:<b>&x"))).added == 0
