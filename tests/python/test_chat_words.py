"""The chat word lists: the general lists made from the shipped readings, and the hand-written chat list."""

import json

import pytest

from wfj.core import chat_words as cw
from wfj.emit import lua_writer

GO = ("行く", "いく", "to go")
KILL = ("倒す", "たおす", "to defeat")
TODAY = ("今日", "きょう", "today")
MEANINGS = {GO: 3, KILL: 7, TODAY: 1, ("それ", "それ", "that"): 9}


def rec(words, english=""):
    out = {"id": 1, "field": "description", "words": words}
    if english:
        out["english"] = english
    return out


def test_a_japanese_word_gets_the_reading_and_meaning_it_is_used_with_most():
    records = [
        rec([["今日", "きょう", *TODAY], ["行き", "いき", *GO]]),
        rec([["今日", "こんにち"], ["行き", "いき", *GO]]),
        rec([["今日", "きょう", *TODAY]]),
    ]
    assert cw.japanese_rows(records, MEANINGS) == {"今日": "きょう=1", "行き": "いき=3"}


def test_a_pair_with_a_meaning_wins_over_a_more_used_pair_without_one():
    records = [rec([["行き", "ゆき"]]), rec([["行き", "ゆき"]]), rec([["行き", "いき", *GO]])]
    assert cw.japanese_rows(records, MEANINGS) == {"行き": "いき=3"}


def test_words_a_chat_card_cannot_use_are_left_out():
    records = [
        rec([["の", "の"]]),  # one kana
        rec([["それ", "それ"]]),  # a kana word with no meaning: nothing to show
        rec([["それ", "それ", "それ", "それ", "that"]]),  # the same word with a meaning is kept
        rec([["Lv上げ", "れべるあげ"]]),  # holds Latin letters
        rec([["一二三四五六七八九十一二三", "いち"]]),  # longer than the addon looks for
        rec([["森", "もり"]]),
    ]
    assert cw.japanese_rows(records, MEANINGS) == {"それ": "それ=9", "森": "もり"}


def test_an_english_word_gets_the_dictionary_form_of_the_japanese_word_used_for_it_most():
    records = [
        rec([["倒し", "たおし", *KILL]], "kill=1"),
        rec([["倒して", "たおして", *KILL]], "kill=1 kills=1"),
        rec([["行き", "いき", *GO]], "kill=1"),
    ]
    assert cw.english_rows(records, MEANINGS) == {"kill": "倒す=たおす=7", "kills": "倒す=たおす=7"}


def test_an_english_row_that_points_past_its_words_or_at_a_word_with_no_meaning_is_skipped():
    records = [rec([["森", "もり"]], "forest=1 wood=4"), rec([["倒し", "たおし", *KILL]], "Kill=1 it's=1")]
    assert cw.english_rows(records, MEANINGS) == {"it's": "倒す=たおす=7"}


def test_a_word_keeps_its_file_whatever_else_is_listed():
    assert cw.shard_of("今日", 12) == cw.shard_of("今日", 12)
    assert {cw.shard_of(w, 4) for w in ("a", "b", "c", "d", "e", "f", "g", "h", "i", "j")} <= {0, 1, 2, 3}
    files = cw.shards({"今日": "きょう=1", "行き": "いき=3"}, 12)
    assert sum(len(rows) for rows in files.values()) == 2
    assert files[cw.shard_of("今日", 12)]["今日"] == "きょう=1"


PROV = {"class": "machine", "model": "m", "source": "chat@2026-11-24", "imported": "2026-11-24"}


def write(root, name, rows):
    (root / "chat").mkdir(exist_ok=True)
    (root / "chat" / name).write_text(
        "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8"
    )


def good(root):
    write(root, cw.WORDS_JA, [{"word": "よろ", "reading": "よろ", "meaning": "short for よろしく", "provenance": PROV}])
    write(root, cw.WORDS_EN, [{"word": "lfm", "ja": "メンバー募集中", "provenance": PROV}])
    write(root, cw.PHRASES, [
        {"id": 1, "topic": "greetings", "en": "Hello!", "ja": "こんにちは！", "provenance": PROV},
        {"id": 2, "topic": "combat", "en": "I'm out of mana.", "ja": "マナがありません。", "provenance": PROV},
    ])


def test_the_chat_list_loads_and_becomes_one_lua_file(tmp_path):
    good(tmp_path)
    chat = cw.load(tmp_path)
    assert chat.words_ja == {"よろ": ("よろ", "short for よろしく")}
    assert chat.words_en == {"lfm": "メンバー募集中"}
    assert [p["id"] for p in chat.phrases] == [1, 2]
    text = lua_writer.chat_list_text(chat)
    assert 'WFJ.Data.add("chatword", {' in text and '["よろ"] = "よろ\\tshort for よろしく",' in text
    assert 'WFJ.Data.add("chatwordEn", {' in text and '["lfm"] = "メンバー募集中",' in text
    assert 'WFJ.Data.add("phrase", {' in text and '[1] = "greetings\\tHello!\\tこんにちは！",' in text


def test_no_chat_folder_is_no_chat_list(tmp_path):
    assert cw.load(tmp_path) is None


@pytest.mark.parametrize(
    ("name", "row", "why"),
    [
        (cw.WORDS_JA, {"word": "おつ", "reading": "おつ", "meaning": "thanks"}, "provenance"),
        (cw.WORDS_JA, {"word": "よろ", "reading": "よろ", "meaning": "again", "provenance": PROV}, "twice"),
        (cw.WORDS_JA, {"word": "おつ", "reading": "お\tつ", "meaning": "x", "provenance": PROV}, "tab"),
        (cw.WORDS_EN, {"word": "LFG", "ja": "募集", "provenance": PROV}, "lower"),
        (cw.WORDS_EN, {"word": "lfm", "ja": "募集", "provenance": PROV}, "twice"),
        (cw.PHRASES, {"id": 2, "topic": "t", "en": "Bye!", "ja": "またね！", "provenance": PROV}, "twice"),
        (cw.PHRASES, {"id": 3, "topic": "t", "en": "hello!", "ja": "やあ！", "provenance": PROV}, "twice"),
        (cw.PHRASES, {"id": 3, "topic": "t", "en": "Hello! Friend.", "ja": "やあ、友よ。", "provenance": PROV},
         "starts"),
        (cw.PHRASES, {"id": 3, "topic": "t", "en": "Bye!", "ja": "こんにちは！またね", "provenance": PROV}, "starts"),
        (cw.PHRASES, {"id": 3, "topic": "t", "en": "Bye·now", "ja": "またね", "provenance": PROV}, "dot"),
    ],
)
def test_a_bad_chat_row_is_refused(tmp_path, name, row, why):
    good(tmp_path)
    with open(tmp_path / "chat" / name, "a", encoding="utf-8") as f:
        f.write(json.dumps(row, ensure_ascii=False) + "\n")
    with pytest.raises(ValueError, match=why):
        cw.load(tmp_path)


def test_a_phrase_or_a_chat_word_of_several_words_that_is_a_line_of_the_games_english_is_refused(tmp_path):
    good(tmp_path)
    chat = cw.load(tmp_path)
    assert cw.game_english_clashes(chat, ["Welcome!", "Tank"]) == []
    assert cw.game_english_clashes(chat, ["hello! ", "x"]) == ["phrase 1: Hello!"]
    write(tmp_path, cw.WORDS_EN, [
        {"word": "tank", "ja": "タンク", "provenance": PROV},
        {"word": "pull more", "ja": "もっと釣る", "provenance": PROV},
    ])
    chat = cw.load(tmp_path)
    # one word is never a clash: the addon may ship single English words
    assert cw.game_english_clashes(chat, ["Tank", "Pull more"]) == ["word: pull more"]
