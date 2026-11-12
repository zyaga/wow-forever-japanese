"""Pronunciation for English word cards: the dictionary's phones respelled the way Japanese-English
dictionaries write them, in letters the addon's font can draw."""

from wfj.core import pronunciation as pr


def spell(phones: str) -> str:
    return pr.spell(phones.split())


def test_vowels_and_consonants_take_the_dictionary_style_letters():
    assert spell("K AE1 T") == "kæt"
    assert spell("S IH1 T") == "sit"  # i, not the small capital the font lacks
    assert spell("B EH1 D") == "bed"
    assert spell("TH IH1 NG") == "θiŋ"
    assert spell("DH AH0") == "ðə"
    assert spell("SH UW1 Z") == "ʃuːz"
    assert spell("JH AH1 JH") == "dʒʌdʒ"
    assert spell("CH OY1 S") == "tʃɔis"
    assert spell("HH AW1 S") == "haus"
    assert spell("Y EH1 S") == "jes"


def test_the_stressed_and_unstressed_forms_of_the_two_vowels_that_change():
    assert spell("B ER1 D") == "bəːrd"
    assert spell("W AO1 T ER0") == "ˈwɔːtər"
    assert spell("AH0 B AW1 T") == "əˈbaut"
    assert spell("K AH1 T") == "kʌt"


def test_one_syllable_takes_no_stress_mark_and_longer_words_mark_the_stressed_syllables_start():
    assert spell("D IH0 F IY1 T") == "diˈfiːt"
    assert spell("K R IY1 CH ER0 Z") == "ˈkriːtʃərz"
    assert spell("AH0 S T R EY1") == "əˈstrei"  # str opens the syllable
    assert spell("AE1 D V ER0 B") == "ˈædvərb"  # dv cannot open one: the mark falls between
    assert spell("IH2 N F ER0 M EY1 SH AH0 N") == "ˌinfərˈmeiʃən"
    # a cluster that opens the word belongs to its first syllable even when no other syllable could open with it
    assert spell("TH W AO1 R T IH0 D") == "ˈθwɔːrtid"
    assert spell("S F EH1 R IH0 K AH0 L") == "ˈsferikəl"


def test_every_letter_used_is_one_the_bundled_font_draws():
    used = set("".join(pr.VOWELS_STRESSED.values()) + "".join(pr.VOWELS_UNSTRESSED.values())
               + "".join(pr.CONSONANTS.values()) + "ˈˌ")
    assert used <= pr.FONT_SAFE


def test_parse_takes_the_first_pronunciation_of_each_word_and_skips_comments():
    text = "defeat D IH0 F IY1 T\nread R EH1 D\nread(2) R IY1 D\nhouse HH AW1 S # place\n;;; note\n'bout B AW1 T\n"
    assert pr.parse(text) == {"defeat": "diˈfiːt", "read": "red", "house": "haus", "'bout": "baut"}


def test_an_unknown_phone_drops_the_word_rather_than_guessing():
    assert pr.parse("odd XX1 T\nok OW1 K EY1\n") == {"ok": "ˈouˈkei"}


def test_the_table_is_tab_separated_sorted_and_names_its_source():
    text = pr.table({"wolves": "wulvz", "defeat": "diˈfiːt"}, "abc123")
    assert text.splitlines() == [
        "# source: CMU Pronouncing Dictionary (cmusphinx/cmudict) @ abc123; respelled by wfj",
        "defeat\tdiˈfiːt",
        "wolves\twulvz",
    ]
    assert pr.parse_table(text) == ({"defeat": "diˈfiːt", "wolves": "wulvz"}, "abc123")
