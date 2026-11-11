"""English word cards: each line's English words matched to the Japanese word whose meaning they are."""

from wfj.core import english_cards as ec

WORDS = [
    ["川", "かわ", "川", "かわ", "river"],
    ["近く", "ちかく", "近く", "ちかく", "near"],
    ["狼", "おおかみ", "狼", "おおかみ", "wolves"],
    ["倒して", "たおして", "倒す", "たおす", "defeat"],
    ["毛皮", "けがわ", "毛皮", "けがわ", "pelts"],
    ["持ち帰って", "もちかえって", "持ち帰る", "もちかえる", "bring back"],
]
EN = "Defeat the wolves near the river and bring back their pelts."


def test_a_one_word_meaning_maps_the_token_with_its_stem_to_that_words_place():
    got = ec.invert(EN, WORDS)
    assert got == {"river": 1, "near": 2, "wolves": 3, "defeat": 4, "pelts": 5, "bring": 6}


def test_inflected_forms_of_the_meaning_match_and_every_form_in_the_line_is_listed():
    words = [["倒す", "たおす", "倒す", "たおす", "kill"]]
    assert ec.invert("He kills. They killed it. Killing is easy; kill them.", words) == {
        "kills": 1, "killed": 1, "killing": 1, "kill": 1,
    }


def test_the_meaning_as_the_sentence_uses_it_comes_before_the_one_in_brackets():
    words = [["倒す", "たおす", "倒す", "たおす", "kill (defeat)"]]
    assert ec.invert("Kill them.", words) == {"kill": 1}
    assert ec.invert("Defeat them.", words) == {"defeat": 1}  # only the bracketed sense is in the line
    assert ec.invert("Kill and defeat them.", words) == {"kill": 1}  # never both


def test_a_phrase_matches_only_when_all_its_content_words_are_in_the_line_and_maps_its_last_one():
    words = [["蝋燭", "ろうそく", "蝋燭", "ろうそく", "wax candles"]]
    assert ec.invert("A package of large wax candles.", words) == {"candles": 1}
    assert ec.invert("A package of candles.", words) == {}
    counter = [["体", "たい", "体", "たい", "counter for creatures"]]
    assert ec.invert("Kill 8 creatures.", counter) == {}


def test_a_word_claimed_by_an_earlier_japanese_word_is_not_taken_again():
    words = [
        ["獣", "けもの", "獣", "けもの", "beasts"],
        ["動物", "どうぶつ", "動物", "どうぶつ", "beasts"],
    ]
    assert ec.invert("More beasts!", words) == {"beasts": 1}


def test_a_function_word_meaning_matches_its_own_word():
    words = [["そちら", "そちら", "そちら", "そちら", "you (there)"], ["まだ", "まだ", "まだ", "まだ", "more (still)"]]
    assert ec.invert("More for you!", words) == {"you": 1, "more": 2}


def test_names_codes_and_entries_without_a_meaning_get_nothing():
    words = [["森", "もり"], ["狩人", "かりゅうど", "狩人", "かりゅうど", "hunter"]]
    en = "$N, the Hunter Ilthalaine waits in the forest. A hunter knows."
    # "Hunter" mid-sentence with a capital is a name here; the lower-case one is the word
    assert ec.invert(en, words) == {"hunter": 2}
    assert ec.invert("Hunters gather.", words) == {"hunters": 2}  # a sentence's first word is not a name


def test_contractions_are_one_word_as_the_addon_reads_them():
    words = [["しない", "しない", "する", "する", "don't"]]
    assert ec.invert("I don't know.", words) == {"don't": 1}


def test_the_row_is_sorted_and_never_the_lines_order():
    row = ec.pack(ec.invert(EN, WORDS))
    assert row == "bring=6 defeat=4 near=2 pelts=5 river=1 wolves=3"
    assert ec.pack({}) == ""


def test_tokens_are_what_the_addon_matches_runs_of_ascii_letters_and_apostrophes():
    assert ec.tokens("“Hunt”・don't, Reyn-san! 8 x") == ["Hunt", "don't", "Reyn", "san", "x"]


def test_a_contractions_first_word_and_the_words_that_take_no_card():
    assert [ec.base(w) for w in ("you're", "let's", "don't", "'s", "hunt")] == ["you", "let", "don", "'s", "hunt"]
    assert {"the", "of", "is", "have"} <= ec.NO_CARD and "you" not in ec.NO_CARD


def test_a_bracketed_hint_is_never_a_function_words_meaning_and_inner_brackets_are_read_through():
    speak = [["話して下さい", "はなしてください", "話す", "はなす", "please speak (with)"]]
    assert ec.invert("Please speak with him.", speak) == {"speak": 1}
    assert ec.invert("Go with him.", speak) == {}  # "with" alone is only the hint
    seen = [["見てきた", "みてきた", "見る", "みる", "have (you) seen"]]
    assert ec.invert("Have you seen it?", seen) == {"seen": 1}
    at = [["いる", "いる", "いる", "いる", "is (at)"], ["ある", "ある", "ある", "ある", "(that) is"]]
    assert ec.invert("He is at the inn that is near.", at) == {}
    unsaid = [["こと", "こと", "こと", "こと", "(that)"], ["こと", "こと", "こと", "こと", "(thing)"]]
    assert ec.invert("The thing that matters.", unsaid) == {"thing": 2}


# ── the generated files ────────────────────────────────────────────────────


def _rows(root):
    import re

    for path in sorted((root / "addon" / "WoWForeverJapanese" / "Data" / "English").glob("English_*.lua")):
        if path.name in ("English_Pron.lua", "English_Common.lua"):  # the two word tables, not line rows
            continue
        for packed in re.findall(r' = "([^"]*)"', path.read_text(encoding="utf-8")):
            yield path.name, packed


def test_every_shipped_row_is_a_sorted_set_of_single_lower_case_words(root):
    seen = 0
    for name, packed in _rows(root):
        words = [pair.rpartition("=")[0] for pair in packed.split()]
        assert words == sorted(set(words)), name  # by word, each once: never the sentence's order
        assert all(w == w.lower() and ec.tokens(w) == [w] for w in words), name
        assert all(pair.rpartition("=")[2].isdigit() for pair in packed.split()), name
        seen += 1
    assert seen > 40000


def test_no_shipped_file_holds_a_line_of_the_games_english(root):
    """A sample of real lines: none of them, nor any run of six of its words, is in the shipped rows."""
    import json

    text = " ".join(packed for _, packed in _rows(root))
    plain = " ".join(pair.rpartition("=")[0] for pair in text.split())
    lines = [json.loads(ln) for ln in (root / "data/english/quest/quest-0000.jsonl").read_text().splitlines()[:400]]
    checked = 0
    for ln in lines:
        words = [w.lower() for w in ec.tokens(ln["en"])]
        if len(set(words)) < 8 or words == sorted(words):
            continue
        for i in range(0, len(words) - 5, 3):
            assert " ".join(words[i : i + 6]) not in plain, ln["en"][:60]
        checked += 1
    assert checked > 100


def test_the_pronunciation_table_names_its_source_and_generate_reads_no_network(root):
    from wfj.core import pronunciation as pr

    said, version = pr.parse_table((root / "data/english/pronunciation.tsv").read_text(encoding="utf-8"))
    assert len(version) == 40 and len(said) > 10000
    assert all(set(spelled) <= pr.FONT_SAFE for spelled in said.values())
    for module in ("core/english_cards.py", "core/pronunciation.py", "cmd/generate.py", "cmd/english_cards.py"):
        source = (root / "pipeline/wfj" / module).read_text(encoding="utf-8")
        assert not any(name in source for name in ("urllib", "requests", "socket", "http.client")), module


def test_the_common_list_is_valid_and_every_line_has_provenance(root):
    from wfj.cmd import generate

    words = generate.load_common_words(root / "data" / "english")
    assert 100 < len(words) < 500
    assert not set(words) & ec.NO_CARD


def test_a_common_list_line_without_provenance_or_with_two_words_stops_generate(tmp_path):
    import pytest
    from wfj.cmd import generate

    prov = '"provenance": {"class": "machine"}'
    cases = [
        '{"word": "you", "ja": "あなた", "reading": "あなた"}',
        '{"word": "of course", "ja": "もちろん", "reading": "もちろん", ' + prov + "}",
        '{"word": "You", "ja": "あなた", "reading": "あなた", ' + prov + "}",
        '{"word": "you", "ja": "あ なた", "reading": "あなた", ' + prov + "}",
    ]
    for line in cases:
        (tmp_path / generate.COMMON_WORDS).write_text(line + "\n", encoding="utf-8")
        with pytest.raises(ValueError):
            generate.load_common_words(tmp_path)
    (tmp_path / generate.COMMON_WORDS).write_text(cases[0][:-1] + ", " + prov + "}\n", encoding="utf-8")
    assert generate.load_common_words(tmp_path) == {"you": ("あなた", "あなた")}
