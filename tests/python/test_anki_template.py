"""The Anki add-on's card: what each choice puts on the front and the back, for a Japanese and an English word."""

import importlib.util
import re

from anki_addon import ADDON
from wfj_anki import notetype
from wfj_anki.settings import Settings

_spec = importlib.util.spec_from_file_location("render_cards", ADDON / "tools" / "render_cards.py")
render_cards = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(render_cards)

WORDS = render_cards.samples("shot.jpg")


def sides(word, **choices):
    front, back, css = notetype.card(Settings(**choices))
    return render_cards.render(front, WORDS[word]), render_cards.render(back, WORDS[word]), css


def text(html):
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", html)).strip()


def test_the_front_has_no_reading_and_marks_the_saved_word():
    front, _, _ = sides("japanese")
    assert "<rt>" not in front and "[" not in front
    assert "<b>倒して</b>" in front
    assert "森を荒らすコボルドを" in front.replace(" ", "")
    assert "to defeat" not in front
    assert "<img" not in front


def test_the_back_has_readings_the_word_its_form_meaning_image_and_audio():
    _, back, _ = sides("japanese")
    assert "<ruby><rb>森</rb><rt>もり</rt></ruby>" in back
    assert "<b><ruby><rb>倒</rb><rt>たお</rt></ruby>して</b>" in back
    assert "倒す" in back and "たおす" in back
    assert "to defeat, to bring down" in back
    assert '<img src="shot.jpg">' in back
    assert "replay-button" in back
    assert "コボルドのろうそく" in back


def test_word_alone_puts_only_the_word_on_the_front():
    front, back, _ = sides("japanese", front="word")
    assert text(front) == "コボルドのろうそく 倒して"
    assert "森" not in front
    assert "<rt>もり</rt>" in back  # the back is the same


def test_the_audio_sits_on_the_side_the_choice_names():
    front, back, _ = sides("japanese", audio="back")
    assert "replay-button" not in front and "replay-button" in back
    front, back, _ = sides("japanese", audio="front")
    assert "replay-button" in front and "replay-button" in back
    front, _, _ = sides("japanese", front="word", audio="front")
    assert "replay-button" in front


def test_an_english_word_shows_english_on_the_front_and_japanese_on_the_back():
    front, back, _ = sides("english")
    assert "Bring me eight of their <b>candles</b>" in front
    assert "ろうそく" not in front.replace("コボルドのろうそく", "")
    assert "KAN-dlz" in back
    assert "ろうそくを八本持ち帰ってほしい。" in back
    assert "辞書形" not in back  # an English word has no dictionary form
    front, _, _ = sides("english", front="word")
    assert text(front) == "コボルドのろうそく candles"


def test_no_marker_or_unfilled_field_is_left_in_a_card():
    for word in WORDS:
        for front in ("sentence", "word"):
            for audio in ("back", "front"):
                q, a, _ = sides(word, front=front, audio=audio)
                for side in (q, a):
                    assert "{{" not in side and "<!--" not in side


def test_the_templates_name_only_fields_the_note_type_has():
    for choices in ({}, {"front": "word", "audio": "front"}):
        q, a, _ = notetype.card(Settings(**choices))
        named = set(re.findall(r"\{\{[#^/]?(?:furigana:|kanji:)?([^}]+)\}\}", q + a))
        assert named <= set(notetype.FIELDS)


def test_every_page_of_the_reel_is_made():
    pages = render_cards.pages("shot.jpg")
    assert len(pages) == 12  # two words: two fronts and one back each, light and dark
    assert all("nightMode" in html for stem, html in pages.items() if stem.endswith("dark"))
