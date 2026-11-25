"""The Anki add-on against a real Anki collection, in a throwaway folder: what it adds and rewrites, and that a
card's schedule and review history are the same before and after.

It needs Anki's own Python (the one Anki runs on), named by ANKI_PYTHON or found where Anki's launcher keeps it.
Where Anki is not installed the tests are skipped: the same rules run against a stand-in in test_anki_plan.py.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest
from anki_addon import ADDON
from wfj_anki import notetype


def anki_python() -> str | None:
    named = os.environ.get("ANKI_PYTHON")
    if named:
        return named if Path(named).is_file() else None
    home = Path.home()
    places = {
        "darwin": home / "Library/Application Support/AnkiProgramFiles/.venv/bin/python",
        "win32": home / "AppData/Local/AnkiProgramFiles/.venv/Scripts/python.exe",
    }
    found = places.get(sys.platform, home / ".local/share/AnkiProgramFiles/.venv/bin/python")
    return str(found) if found.is_file() else None


@pytest.fixture(scope="module")
def seen(tmp_path_factory):
    python = anki_python()
    if python is None:
        pytest.skip("Anki is not installed here")
    folder = tmp_path_factory.mktemp("anki")
    run = subprocess.run(
        [python, str(ADDON / "tests" / "real_collection.py"), str(folder)],
        capture_output=True,
        text=True,
        timeout=300,
        check=False,
    )
    assert run.returncode == 0, run.stderr[-3000:]
    return json.loads(run.stdout.strip().splitlines()[-1])


def counts(result):
    return result["added"], result["updated"]


def test_the_note_type_the_note_and_its_one_card(seen):
    assert seen["prepared"] is True
    assert seen["fields"] == notetype.FIELDS
    assert counts(seen["first"]) == (1, 0)
    assert seen["deck"] == notetype.DECK
    assert seen["cards"] == 1
    note = seen["note"]
    assert note["Sentence"] == "少しの<b>生[い]き 物[もの]</b>たちを狩れ。"
    assert note["Meaning"] == "living thing"


def test_the_media_is_in_the_collection_and_the_picture_is_made_smaller(seen):
    assert seen["media"] == ["wfj-WoWScrnShot_112526_101500.jpg", "wfj-a-1.mp3", "wfj-a-2.mp3"]
    assert seen["note"]["Image"] == '<img src="wfj-WoWScrnShot_112526_101500.jpg">'
    assert seen["note"]["Audio"] == "[sound:wfj-a-1.mp3][sound:wfj-a-2.mp3]"
    assert seen["picture_width"] == 1600
    assert 0 < seen["picture_bytes"] < seen["source_bytes"]
    assert (seen["first"]["missing_images"], seen["first"]["missing_audio"]) == (0, 0)


def test_the_same_data_again_touches_nothing(seen):
    assert counts(seen["second"]) == (0, 0)
    assert seen["second_untouched"] is True


def test_a_changed_value_rewrites_one_field_and_keeps_the_schedule_and_the_reviews(seen):
    assert seen["studied"] is True and seen["reviews"] == 1
    assert counts(seen["third"]) == (0, 1)
    assert seen["changed_fields"] == ["Meaning", "Sync"]
    assert seen["meaning"] == "a living thing"
    assert seen["schedule_kept"] is True
    assert seen["reviews_kept"] is True


def test_a_hand_edit_is_kept_and_reset_puts_the_games_value_back(seen):
    assert seen["edit_kept"] == ["my own words", "イキモノ"]
    assert counts(seen["reset"]) == (0, 1)
    assert seen["after_reset"] == "again"
    assert seen["schedule_kept_after_reset"] is True
    assert seen["reviews_kept_after_reset"] is True


def test_a_note_of_the_players_own_with_the_same_key_is_never_touched(seen):
    assert seen["other_untouched"] is True
    assert (seen["own_notes"], seen["all_notes"]) == (1, 2)


def test_a_note_deleted_in_anki_is_not_made_again_until_asked(seen):
    assert (seen["deleted_stays"]["added"], seen["deleted_stays"]["deleted"]) == (0, 1)
    assert (seen["deleted_back"]["added"], seen["deleted_back"]["deleted"]) == (1, 0)


def test_a_word_gone_from_the_game_keeps_its_note(seen):
    assert counts(seen["gone"]) == (0, 0)
    assert seen["still_there"] is True


def test_a_card_choice_rewrites_the_template_and_no_note(seen):
    assert seen["choice_changed"] is True and seen["template_differs"] is True
    assert seen["choice_again"] is False
    assert seen["notes_untouched_by_choice"] is True
    assert seen["card_count_after_choice"] == 1
    # Anki's own rendering of the "word alone" front, with the audio on it
    question = seen["question"]
    assert 'class="wfj-word wfj-alone"' in question and 'class="wfj-sentence"' not in question
    assert "[anki:play:q:0][anki:play:q:1]" in question  # Anki's marks for the two sound files


def test_a_card_the_player_restyled_is_left_until_a_choice_changes(seen):
    assert seen["own_styling_left"] is True
    assert seen["choice_rewrites_styling"] is True


def test_an_older_note_type_gains_the_new_field_and_loses_nothing(seen):
    assert seen["upgraded"] is True
    assert seen["fields_after_upgrade"] is True
    assert seen["note_kept_through_upgrade"] is True
    assert seen["schedule_kept_through_upgrade"] is True


def test_a_note_type_of_the_same_name_that_is_the_players_is_left_alone(seen):
    assert seen["own_name_when_taken"] == notetype.NAME + " (add-on)"
    assert seen["theirs_fields"] == ["Key"]


def test_the_settings_window_shows_and_saves_the_choices(tmp_path):
    python = anki_python()
    if python is None:
        pytest.skip("Anki is not installed here")
    run = subprocess.run(
        [python, str(ADDON / "tests" / "settings_window.py"), str(tmp_path)],
        capture_output=True,
        text=True,
        timeout=300,
        check=False,
    )
    assert run.returncode == 0, run.stderr[-3000:]
    seen = json.loads(run.stdout.strip().splitlines()[-1])
    for name, language in (
        ("settings-en.png", "Found 2 saved word list(s)."),
        ("settings-ja.png", "単語帳が 2 件見つかりました。"),
    ):
        assert (tmp_path / name).stat().st_size > 0
        window = seen[name]
        assert window["found"] == language
        assert window["saved"] == [
            {"folder": "D:/Games/World of Warcraft", "front": "word", "audio": "back"}
        ]
        assert window["status"].count("\n") == 1
        assert window["empty"] != window["found"]
