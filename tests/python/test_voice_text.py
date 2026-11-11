"""What the engine reads for a line: the shipped Japanese with its names in kana, no space before a kanji, the
player's stand-in in kana, and the listed single words in kana where they stand alone."""

from __future__ import annotations

from wfj.core import voice, voice_text

NAMES = {"Lydon": "ライドン", "Venture Company": "ベンチャー・カンパニー"}
KANA_WORDS = frozenset({("金", "かね"), ("獣", "けもの")})


def read(ja: str, words=(), key: str = "1-description"):
    return voice_text.voice_text(ja, key, (), words, NAMES.get, KANA_WORDS)


def test_a_line_with_nothing_to_fix_is_the_speech_text():
    ja = "よく来たな。話を聞いてくれ。"
    assert read(ja) == (voice.speech_text(ja, "1-description"), [])


def test_an_english_name_is_said_in_kana():
    assert read("Lydonの毒はVenture Companyに効く。") == ("ライドンの毒はベンチャー・カンパニーに効く。", [])


def test_a_name_with_no_japanese_is_reported_and_left():
    assert read("Lydonの毒はGnomereganに効く。") == ("ライドンの毒はGnomereganに効く。", ["Gnomeregan"])


def test_a_space_before_a_kanji_is_removed_and_one_before_kana_is_kept():
    assert read("本当か? 素晴らしいわ。")[0] == "本当か?素晴らしいわ。"
    assert read("本当か？　君は強い。")[0] == "本当か？君は強い。"
    assert read("本当か? すばらしいわ。")[0] == "本当か? すばらしいわ。"


def test_a_space_after_a_name_and_before_a_kanji_is_removed():
    assert read("Lydon 殿の毒だ。")[0] == "ライドン殿の毒だ。"


def test_the_stand_in_for_the_player_is_said_in_kana():
    assert read("よくやった、{name}。")[0] == "よくやった、ぼうけんしゃ。"
    assert read("勇敢な冒険者よ。")[0] == "勇敢なぼうけんしゃよ。"


def test_a_listed_word_is_kana_only_where_it_stands_alone():
    words = [("金", "かね"), ("払う", "はらう"), ("金貨", "きんか"), ("大金", "たいきん")]
    assert read("金を払う。金貨も大金もだ。", words)[0] == "かねを払う。金貨も大金もだ。"


def test_a_listed_word_read_another_way_stays_kanji():
    assert read("金の鎧だ。", [("金", "きん"), ("鎧", "よろい")])[0] == "金の鎧だ。"


def test_each_standing_of_a_listed_word_is_found_in_order():
    words = [("獣", "けもの"), ("野獣", "やじゅう"), ("獣", "けもの")]
    assert read("獣だ。野獣ではない、獣だ。", words)[0] == "けものだ。野獣ではない、けものだ。"
