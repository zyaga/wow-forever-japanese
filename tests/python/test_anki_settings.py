"""The Anki add-on's settings: defaults when nothing is saved, and a bad value never breaks a sync."""

from anki_addon import FIXTURES  # noqa: F401  (puts the add-on on the path)

from wfj_anki import settings


def test_defaults_when_nothing_is_saved():
    for conf in (None, {}, "x"):
        s = settings.from_config(conf)
        assert (s.folder, s.front, s.audio) == ("", "sentence", "back")


def test_a_saved_choice_is_read_back():
    s = settings.from_config({"folder": " /Games/World of Warcraft ", "front": "word", "audio": "front"})
    assert (s.folder, s.front, s.audio) == ("/Games/World of Warcraft", "word", "front")
    assert settings.from_config(settings.to_config(s)) == s


def test_an_unknown_value_falls_back_to_the_default():
    s = settings.from_config({"folder": 5, "front": "both", "audio": None})
    assert (s.folder, s.front, s.audio) == ("", "sentence", "back")


def test_the_shipped_config_is_the_defaults():
    import json

    from anki_addon import ADDON

    shipped = json.loads((ADDON / "wfj_anki" / "config.json").read_text(encoding="utf-8"))
    assert shipped == settings.to_config(settings.from_config(None))
