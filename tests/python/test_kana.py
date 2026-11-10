"""Kana lines (ADR-077): readings, names and numbers turned into kana; every voiced line has a current one;
the name tables are generated but never loaded by the TOC."""

from __future__ import annotations

import pytest

from wfj.cmd import voice_kana
from wfj.core import kana


@pytest.mark.parametrize(
    "text, spoken",
    [
        ("3匹", "さんびき"),
        ("1本", "いっぽん"),
        ("10本", "じゅっぽん"),
        ("6個", "ろっこ"),
        ("2人", "ふたり"),
        ("20日", "はつか"),
        ("4時間", "よじかん"),
        ("5分間", "ごふんかん"),
        ("1つ目", "ひとつめ"),
        ("2週間前", "にしゅうかんまえ"),
        ("14日分", "じゅうよっかぶん"),
        ("何匹か", "なんびきか"),
        ("300ゴールド", "さんびゃくゴールド"),
        ("1.5倍", "いちてんごばい"),
        ("1,000", "せん"),
        ("２年前", "にねんまえ"),
    ],
)
def test_numbers_are_read_with_their_counters(text, spoken):
    assert kana.spell_numbers(text) == spoken


def test_readings_names_and_numbers_become_kana():
    names = {"Thrall": "スロール", "Orgrimmar": "おーぐりまー"}
    ja = "{name}、Orgrimmarで待つThrallに$N1匹の狼を届けてくれ。"
    words = [["待つ", "まつ"], ["匹", "ひき"], ["狼", "おおかみ"], ["届けてくれ", "とどけてくれ"]]
    text, problems = kana.build(ja, "1-description", ["3"], words, names.get)
    assert problems == []
    assert text == "ぼうけんしゃ、おーぐりまーでまつスロールにさんびきのおおかみをとどけてくれ。"


def test_a_line_with_a_missing_reading_or_name_is_not_built():
    text, problems = kana.build("Kalimdorの森。", "g-0000000000000001", [], [["森", "もり"]], {}.get)
    assert text is None and any("Kalimdor" in p for p in problems)
    text, problems = kana.build("森と川。", "g-0000000000000001", [], [["森", "もり"]], {}.get)
    assert text is None and any("川" in p for p in problems)


def test_kana_problems():
    assert kana.kana_problems("すろーるのもり。") == []
    assert kana.kana_problems("森") and kana.kana_problems("Thrall") and kana.kana_problems("3びき")


def test_every_voiced_line_has_a_current_kana_line(root):
    bad = voice_kana.problems(root / "data")
    assert bad == [], f"{len(bad)} voiced lines without a current kana line (wfj voice kana), e.g. {bad[:5]}"


def test_name_tables_are_generated_but_not_loaded(root):
    addon = root / "addon" / "WoWForeverJapanese"
    assert any((addon / "Data" / "Names").glob("Names_*.lua"))
    toc = (addon / "WoWForeverJapanese.toc").read_text(encoding="utf-8")
    assert "Names" not in toc


def test_a_name_with_digits_and_a_count_glued_to_a_name():
    names = {"NG-5": "エヌジーご", "mageweave cloth": "まおりのぬの"}
    text, problems = kana.build("NG-5とmageweave cloth60枚。", "g-0000000000000002", [], [], names.get)
    assert problems == [] and text == "エヌジーごとまおりのぬのろくじゅうまい。"
