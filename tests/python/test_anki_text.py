"""The Anki add-on's own words: both languages for every line, and what the last sync is said to have done."""

import re

from anki_addon import ADDON
from wfj_anki import sync, text
from wfj_anki.sync import Result


def test_every_line_has_both_languages_and_the_same_blanks():
    for key, (en, ja) in text.T.items():
        assert en.strip() and ja.strip(), key
        assert sorted(re.findall(r"\{(\w+)\}", en)) == sorted(re.findall(r"\{(\w+)\}", ja)), key
        assert "—" not in en + ja, key


def test_every_line_the_window_and_the_menu_ask_for_exists():
    source = (ADDON / "wfj_anki" / "ui.py").read_text(encoding="utf-8")
    asked = set(re.findall(r'\b(?:t|say|_say)\("(\w+)"', source))
    asked |= {key for pair in re.findall(r'\("(\w+)", "(\w+)"\), settings\.', source) for key in pair}
    assert asked and asked <= set(text.T)


def test_the_last_sync_in_words():
    assert text.summary(None, False) == "No sync yet."
    assert "No saved word list found" in text.summary(Result(), False)
    assert "has not written it for Anki yet" in text.summary(Result(files=1), False)
    assert "newer than this add-on" in text.summary(Result(files=1, tables=1, newer=True), False)
    assert (
        text.summary(Result(files=1, tables=1, words=7), False) == "Up to date: 7 word(s), nothing to change."
    )
    done = text.summary(
        Result(files=1, tables=1, words=7, added=2, updated=1, missing_images=3, missing_audio=4), False
    )
    assert done.splitlines() == [
        "2 new, 1 updated (7 word(s) in the game).",
        "3 screenshot(s) not found in the Screenshots folder.",
        "4 sentence(s) have sound files that were not found (is the voice pack installed?).",
    ]
    assert text.summary(Result(files=1, tables=1, words=7, added=2), True).startswith("新規 2")


def test_missing_media_makes_the_next_sync_look_again():
    assert Result(missing_audio=1).pending and Result(missing_images=1).pending
    assert not Result(added=3).pending


def test_a_sync_is_passed_over_while_nothing_changed():
    seen = ((("/game/file.lua", 10, 5),), "settings")
    assert sync.due(seen, None, None, False)  # the first one of a session
    assert not sync.due(seen, seen, Result(added=1), False)
    assert sync.due(
        ((("/game/file.lua", 11, 6),), "settings"), seen, Result(), False
    )  # the game wrote its file
    assert sync.due((seen[0], "other settings"), seen, Result(), False)
    assert sync.due(seen, seen, Result(missing_images=1), False)
    assert sync.due(seen, seen, Result(), True)  # the player asked


def test_the_hooks_the_sync_is_wired_to():
    source = (ADDON / "wfj_anki" / "ui.py").read_text(encoding="utf-8")
    for wiring in (
        "gui_hooks.profile_did_open.append",
        "mw.app.applicationStateChanged",
        "menuTools.addMenu",
        "gui_hooks.state_did_change.append",
        "gui_hooks.browser_will_show_context_menu.append",
    ):
        assert wiring in source
    assert "if mw.col is None or self.running" in source
