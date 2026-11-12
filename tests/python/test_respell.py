"""A name's Japanese spelled from its English: the assembly rules, and the result being a valid name line."""

from __future__ import annotations

import json

import pytest

from wfj.cmd import names as cmd
from wfj.core import names, respell
from wfj.io.names_store import load_lines, load_words, save_lines, save_words

SPELL = {
    "black": "ブラック",
    "dragonflight": "ドラゴンフライト",
    "argent": "アージェント",
    "dawn": "ドーン",
    "might": "マイト",
    "of": "オブ",
    "the": "ザ",
    "menethil": "メネシル",
    "hallow": "ハロウ",
    "end": "エンド",
    "head": "ヘッド",
    "shot": "ショット",
    "safe": "セーフ",
    "zone": "ゾーン",
    "plans": "プラン",
    "fiery": "ファイアリー",
    "plate": "プレート",
    "gauntlets": "ガントレット",
    "death": "デス",
    "decay": "ディケイ",
    "tier": "ティア",
    "zin": "ジン",
    "malor": "マロール",
    "hand": "ハンド",
    "level": "レベル",
    "epic": "エピック",
    "bonus": "ボーナス",
    "druid": "ドルイド",
    "shaman": "シャーマン",
}


@pytest.mark.parametrize(
    ("en", "ja", "reading"),
    [
        ("Black Dragonflight", "ブラック・ドラゴンフライト", "ぶらっく・どらごんふらいと"),
        ("BLACK dragonflight", "ブラック・ドラゴンフライト", "ぶらっく・どらごんふらいと"),
        ("The Argent Dawn", "アージェント・ドーン", "あーじぇんと・どーん"),
        ("Might of Menethil", "マイト・オブ・メネシル", "まいと・おぶ・めねしる"),
        ("Hand of the Dawn", "ハンド・オブ・ザ・ドーン", "はんど・おぶ・ざ・どーん"),
        ("Hallow's End", "ハロウズ・エンド", "はろうず・えんど"),
        ("Zin-Malor", "ジン・マロール", "じん・まろーる"),
        ("Head Shot II", "ヘッド・ショット2", "へっど・しょっとに"),
        ("Level 80 Epic", "レベル80・エピック", "れべるはちじゅう・えぴっく"),
        ("[DNT] Safe zone", "セーフ・ゾーン", "せーふ・ぞーん"),
        ("Plans: Fiery Plate Gauntlets", "プラン：ファイアリー・プレート・ガントレット", "ぷらん・ふぁいありー・ぷれーと・がんとれっと"),
        ("Death & Decay", "デス・アンド・ディケイ", "です・あんど・でぃけい"),
        ("Druid/Shaman", "ドルイド・シャーマン", "どるいど・しゃーまん"),
        ("Tier 2 - 6P Bonus", "ティア2・6ピー・ボーナス", "てぃあに・ろくぴー・ぼーなす"),
    ],
)
def test_a_name_is_spelled_from_its_words(en, ja, reading):
    assert respell.assemble(en, SPELL.get) == (ja, reading, [])


def test_a_letter_of_an_abbreviation_is_read_by_its_name_never_as_a_numeral():
    spell = {"scribbled": "スクリブルド", "broken": "ブロークン", "button": "バトン", "mark": "マーク"}
    assert respell.assemble("Scribbled I.O.U.", spell.get)[0] == "スクリブルド・アイ・オー・ユー"
    assert respell.assemble("I.O.U", spell.get)[0] == "アイ・オー・ユー"
    assert respell.assemble("Broken I.W.I.N. Button", spell.get)[0] == "ブロークン・アイ・ダブリュー・アイ・エヌ・バトン"
    assert respell.assemble("F.I.C.A", spell.get)[0] == "エフ・アイ・シー・エー"
    assert respell.assemble("Mark IV", spell.get)[0] == "マーク4"  # a numeral with no full stop is still a number


def test_a_possessive_keeps_its_sound_with_either_apostrophe_and_an_inner_apostrophe_stays_in_the_word():
    spell = {"gallow": "ギャロウ", "end": "エンド", "tavern": "タバーン", "ahn'qiraj": "アンキラージ"}
    assert respell.assemble("Gallow's End Tavern", spell.get)[0] == "ギャロウズ・エンド・タバーン"
    assert respell.assemble("Gallow’s End", spell.get)[0] == "ギャロウズ・エンド"
    assert respell.assemble("Ahn'Qiraj", spell.get)[0] == "アンキラージ"


def test_a_letter_outside_ascii_is_part_of_its_word_and_a_word_nobody_spelled_is_reported():
    assert respell.assemble("Café", {"café": "カフェ"}.get) == ("カフェ", "かふぇ", [])
    assert respell.assemble("Jörmungandr", {}.get) == (None, None, ["Jörmungandr"])
    assert respell.assemble("黒 Dragon", {}.get) == (None, None, ["黒", "Dragon"])


def test_a_comma_inside_a_name_is_kept_with_no_dot_after_it():
    spell = {"black": "ブラック", "dawn": "ドーン", "and": "アンド", "end": "エンド"}
    assert respell.assemble("Black, Dawn and End", spell.get)[0] == "ブラック、ドーン・アンド・エンド"


def test_a_leading_the_stays_when_it_is_the_whole_name():
    assert respell.assemble("The", SPELL.get) == ("ザ", "ざ", [])


def test_a_word_with_no_spelling_is_reported_and_nothing_is_spelled():
    assert respell.assemble("Black Unknownword Dawn", SPELL.get) == (None, None, ["Unknownword"])


def test_a_name_that_is_only_a_tag_has_nothing_to_spell():
    assert respell.assemble("[UNUSED]", SPELL.get) == (None, None, [])


def test_the_words_of_a_name_are_what_the_assembly_looks_up():
    assert respell.words("The Hallow's End II [DNT] 2P") == ["The", "Hallow", "End"]


def test_an_assembled_name_is_a_valid_name_line():
    for en in ("Black Dragonflight", "Head Shot II", "Plans: Fiery Plate Gauntlets", "Tier 2 - 6P Bonus"):
        ja, reading, _ = respell.assemble(en, SPELL.get)
        line = names.new_line(en, "2026-11-11")
        line.update(
            ids={"item": [1]},
            ja=ja,
            reading=reading,
            status="trusted",
            provenance={"class": "machine", "model": "m", "source": "respell@2026-11-11", "imported": "2026-11-11"},
        )
        assert names.line_problems(names.ordered(line)) == []


# ── the commands: export the words with no katakana spelling, import the spellings, respell the names ──

TODAY = "2026-11-11"
DRAFT = {"class": "machine", "model": "m", "source": "draft-names-test1@2026-11-10", "imported": "2026-11-10"}
HUMAN = {"class": "human", "source": "hearthstone@256589", "imported": "2026-11-10"}
FIXED = {"class": "correction", "translator": "a player", "source": "report@12345", "corrects": "hearthstone@256589",
         "imported": "2026-11-10"}


def _line(en: str, ja: str, reading: str, prov: dict = DRAFT, free: bool = False) -> dict:
    ln = names.new_line(en, TODAY)
    ln.update(ids={"item": [1]}, ja=ja, reading=reading, free=free, status="trusted", provenance=dict(prov))
    return names.ordered(ln)


def _word(en: str, ja: str, check: bool = True) -> dict:
    return {"en": en, "ja": ja, "check": check, "provenance": dict(DRAFT)}


@pytest.fixture
def store(tmp_path):
    save_lines(
        tmp_path,
        [
            _line("Black Dragonflight", "黒いドラゴンフライト", "くろいどらごんふらいと"),
            _line("Black Gloves", "黒い手袋", "くろいてぶくろ", free=True),
            _line("Zin-Malor", "ジン・マロール", "じん・まろーる"),
            _line("Orgrimmar", "オーグリマー", "おーぐりまー", prov=HUMAN),
            _line("Stormwind", "嵐風", "らんぷう", prov=FIXED),
            _line("[DNT]", "開発用", "かいはつよう"),
        ],
    )
    save_words(
        tmp_path,
        [
            _word("Black", "黒い", check=False),
            _word("Dragonflight", "ドラゴンフライト"),
            _word("Zin", "ジン"),
            _word("Malor", "マロール"),
            _word("Orgrimmar", "オーグリマー"),
        ],
    )
    return tmp_path


def test_export_lists_each_word_with_no_katakana_spelling_once(store, tmp_path):
    out = tmp_path / "out"
    assert cmd.export_respell(store, out, 100) == 2
    rows = [json.loads(r) for r in (out / "respell-000.jsonl").read_text(encoding="utf-8").splitlines()]
    assert [(r["en"], r["count"]) for r in rows] == [("black", 2), ("gloves", 1)]
    assert rows[0]["examples"] == ["Black Dragonflight", "Black Gloves"]


def _batch(tmp_path, rows) -> object:
    p = tmp_path / "batch.jsonl"
    p.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")
    return p


def test_import_replaces_a_translated_spelling_and_adds_a_new_word(store, tmp_path):
    batch = _batch(tmp_path, [{"en": "black", "ja": "ブラック"}, {"en": "gloves", "ja": "グローブ"}])
    n, rejected = cmd.import_respell(store, batch, "m2", "respell-1", TODAY, False)
    assert (n, rejected) == (2, [])
    words = {w["en"]: w for w in load_words(store)}
    assert (words["Black"]["ja"], words["Black"]["check"]) == ("ブラック", True)
    assert words["Black"]["provenance"]["source"] == "draft-names-respell-1@2026-11-11"
    assert words["gloves"]["ja"] == "グローブ"
    assert words["Dragonflight"]["provenance"] == DRAFT  # a word that was katakana is not touched


def test_import_refuses_a_spelling_that_is_not_katakana_or_fights_one_that_exists(store, tmp_path):
    batch = _batch(tmp_path, [{"en": "black", "ja": "黒"}, {"en": "dragonflight", "ja": "ドラゴンフライツ"}])
    n, rejected = cmd.import_respell(store, batch, "m2", "respell-1", TODAY, False)
    assert n == 0
    assert len(rejected) == 2 and "katakana" in rejected[0] and "already" in rejected[1]
    assert {w["en"]: w["ja"] for w in load_words(store)}["Black"] == "黒い"


def test_respell_rewrites_every_translated_name_and_leaves_the_rest(store, tmp_path):
    before = {ln["en"]: ln for ln in load_lines(store)}
    batch = _batch(tmp_path, [{"en": "black", "ja": "ブラック"}, {"en": "gloves", "ja": "グローブ"}])
    cmd.import_respell(store, batch, "m2", "respell-1", TODAY, False)
    counts = cmd.respell(store, TODAY, False)
    assert counts == {"respelled": 2, "kept": 3, "nothing to spell": 1, "word with no spelling": 0}
    after = {ln["en"]: ln for ln in load_lines(store)}
    assert (after["Black Dragonflight"]["ja"], after["Black Dragonflight"]["reading"]) == (
        "ブラック・ドラゴンフライト",
        "ぶらっく・どらごんふらいと",
    )
    assert (after["Black Gloves"]["ja"], after["Black Gloves"]["free"]) == ("ブラック・グローブ", False)
    assert after["Black Gloves"]["provenance"] == {
        "class": "machine",
        "source": "respell@2026-11-11",
        "imported": "2026-11-11",
    }
    for en in ("Zin-Malor", "Orgrimmar", "Stormwind", "[DNT]"):  # equal already (two), a player's fix, no words
        assert after[en] == before[en]


def test_a_name_with_a_word_nobody_has_spelled_is_left_and_the_rest_are_written(store, tmp_path):
    cmd.import_respell(store, _batch(tmp_path, [{"en": "black", "ja": "ブラック"}]), "m2", "respell-1", TODAY, False)
    counts = cmd.respell(store, TODAY, False)
    assert (counts["word with no spelling"], counts["respelled"]) == (1, 1)
    after = {ln["en"]: ln["ja"] for ln in load_lines(store)}
    assert (after["Black Dragonflight"], after["Black Gloves"]) == ("ブラック・ドラゴンフライト", "黒い手袋")
    assert any("Gloves" in p for p in cmd.respell_problems(load_lines(store), load_words(store)))


def test_a_fix_round_may_replace_a_katakana_spelling_but_never_a_players_fix(store, tmp_path):
    words = {w["en"]: w for w in load_words(store)}
    words["Tiger"] = {"en": "Tiger", "ja": "トラ", "check": True, "provenance": dict(HUMAN)}  # from a card
    words["Stormwind"] = {"en": "Stormwind", "ja": "ストームウィンド", "check": True, "provenance": dict(FIXED)}
    save_words(store, words.values())
    batch = _batch(tmp_path, [{"en": "tiger", "ja": "タイガー"}, {"en": "stormwind", "ja": "ストームウインド"}])
    assert cmd.import_respell(store, batch, "m2", "respell-fix", TODAY, False)[0] == 0  # refused without it
    n, rejected = cmd.import_respell(store, batch, "m2", "respell-fix", TODAY, False, replace=True)
    after = {w["en"]: w["ja"] for w in load_words(store)}
    assert (n, after["Tiger"], after["Stormwind"]) == (1, "タイガー", "ストームウィンド")
    assert len(rejected) == 1 and "person" in rejected[0]


def test_a_name_from_a_card_is_spelled_from_the_english_like_the_rest(store):
    save_lines(store, [*load_lines(store), _line("Tiger", "トラ", "とら", prov=HUMAN)])
    save_words(store, [*load_words(store), _word("black", "ブラック"), _word("gloves", "グローブ"), _word("tiger", "タイガー")])
    cmd.respell(store, TODAY, False)
    assert {ln["en"]: ln["ja"] for ln in load_lines(store)}["Tiger"] == "タイガー"


def test_a_katakana_name_that_is_a_translation_is_spelled_again(store):
    lines = load_lines(store) + [_line("Scorpion", "サソリ", "さそり")]
    save_lines(store, lines)
    save_words(store, [*load_words(store), _word("black", "ブラック"), _word("gloves", "グローブ"), _word("scorpion", "スコーピオン")])
    cmd.respell(store, TODAY, False)
    assert {ln["en"]: ln["ja"] for ln in load_lines(store)}["Scorpion"] == "スコーピオン"


def test_words_learn_their_spelling_from_a_name_already_spelled_out(store):
    save_lines(store, load_lines(store) + [_line("Xandar Goodbeard", "ザンダー・グッドビアード", "ざんだー・ぐっどびあーど")])
    n, differ = cmd.learn_spellings(store, False)
    words = {w["en"]: w["ja"] for w in load_words(store)}
    assert (n, differ) == (2, [])
    assert (words["Xandar"], words["Goodbeard"]) == ("ザンダー", "グッドビアード")


def test_a_possessive_name_teaches_no_spelling(store):
    """Its part ends in the possessive's own sound, which is not part of the word."""
    save_lines(store, load_lines(store) + [_line("Wendle's Rest", "ウェンドルズ・レスト", "うぇんどるず・れすと")])
    n, _ = cmd.learn_spellings(store, False)
    words = {w["en"] for w in load_words(store)}
    assert n == 0 and "Wendle" not in words and "Rest" not in words


def test_a_name_that_spells_a_word_another_way_is_reported_not_learned(store):
    save_lines(store, load_lines(store) + [_line("Zin Hold", "ジーン・ホールド", "じーん・ほーるど")])
    n, differ = cmd.learn_spellings(store, False)
    assert n == 1 and len(differ) == 1 and "Zin" in differ[0]  # Hold is learned, Zin keeps its spelling
    assert {w["en"]: w["ja"] for w in load_words(store)}["Zin"] == "ジン"


def test_a_new_name_is_spelled_from_its_words_with_no_naming_round(store):
    new = names.new_line("Black Zin", TODAY)
    new["ids"] = {"unit": [7]}
    save_lines(store, [*load_lines(store), names.ordered(new)])
    save_words(store, [*load_words(store), _word("black", "ブラック"), _word("gloves", "グローブ")])
    cmd.respell(store, TODAY, False)
    line = {ln["en"]: ln for ln in load_lines(store)}["Black Zin"]
    assert (line["status"], line["ja"], line["reading"]) == ("trusted", "ブラック・ジン", "ぶらっく・じん")


def test_the_check_holds_a_name_to_the_spelling_of_its_words(store):
    lines, words = load_lines(store), [*load_words(store), _word("black", "ブラック"), _word("gloves", "グローブ")]
    bad = cmd.respell_problems(lines, words)
    assert len(bad) == 2 and "ブラック・ドラゴンフライト" in "".join(bad)
    save_words(store, words)
    cmd.respell(store, TODAY, False)
    assert cmd.respell_problems(load_lines(store), load_words(store)) == []
