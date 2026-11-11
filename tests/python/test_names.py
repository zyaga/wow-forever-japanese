"""Japanese names (ADR-078): the name store, the glossary, Hearthstone, drafting import, the one-spelling
check, and the committed store being complete and current."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from wfj.cmd import names as cmd
from wfj.core import names
from wfj.io.names_store import load_lines, load_words, save_lines

TODAY = "2026-11-10"


def trusted(en: str, ja: str, reading: str, **kw) -> dict:
    ln = names.new_line(en, TODAY)
    ln.update(
        ids={"unit": [1]},
        ja=ja,
        reading=reading,
        status="trusted",
        provenance={
            "class": "machine",
            "model": "m",
            "source": "draft-names-test1@2026-11-10",
            "imported": TODAY,
        },
        **kw,
    )
    return names.ordered(ln)


def test_id_is_the_hash_of_the_normalized_english():
    assert names.name_id("  Orgrimmar ") == names.name_id("Orgrimmar")
    assert names.new_line("Orgrimmar", TODAY)["id"] == names.name_id("Orgrimmar")


def test_latin_runs_skip_markup_and_trailing_counts():
    ja = "{name}よ、Stormwindの$N1体のKobold Vermin 10を倒し、|cff00ff00Zul'Gurub|rへ行け。Un'Goro Crater."
    assert names.latin_runs(ja) == ["Stormwind", "Kobold Vermin", "Zul'Gurub", "Un'Goro Crater"]


def test_merge_adds_ids_never_removes_or_rewrites():
    old = [trusted("Thrall", "スロール", "すろーる")]
    lines, added = names.merge(
        old, {"Thrall": {"unit": [4949]}, "Orgrimmar": {"area": [1637]}}, ["Kalimdor"], TODAY
    )
    by_en = {ln["en"]: ln for ln in lines}
    assert added == 2
    assert by_en["Thrall"]["ids"] == {"unit": [1, 4949]} and by_en["Thrall"]["ja"] == "スロール"
    assert by_en["Orgrimmar"]["status"] == "missing" and by_en["Kalimdor"]["prose"] is True
    again, added = names.merge(lines, {"Thrall": {"unit": [4949]}}, [], TODAY)
    assert added == 0 and again == lines


@pytest.mark.parametrize(
    "change, problem",
    [
        ({"id": "0000000000000000"}, "is not the hash"),
        ({"ja": "Thrall"}, "Latin letters"),
        ({"reading": "スロール"}, "not hiragana"),
        ({"reading": "すろる"}, "not the hiragana of"),
        ({"ja": "山のノスリ", "reading": "やまのすのり"}, "does not fit"),
        ({"ja": "粗い研ぎ石", "reading": "あらいといし"}, "does not fit"),
        ({"ids": {}, "prose": False}, "no game id"),
        ({"ids": {"npc": [1]}}, "kinds of"),
        ({"provenance": {"class": "machine"}}, "source must look like"),
    ],
)
def test_line_problems(change, problem):
    ln = trusted("Thrall", "スロール", "すろーる")
    ln.update(change)
    assert any(problem in p for p in names.line_problems(ln)), names.line_problems(ln)


def test_a_good_line_and_a_missing_line_pass():
    assert names.line_problems(trusted("Thrall", "スロール", "すろーる")) == []
    missing = names.new_line("Thrall", TODAY)
    missing["prose"] = True
    assert names.line_problems(missing) == []


def test_spelling_check_holds_names_to_checked_words():
    words = [
        {
            "en": "Stormwind",
            "ja": "ストームウィンド",
            "check": True,
            "provenance": {"class": "human", "source": "hearthstone@256589", "imported": TODAY},
        }
    ]
    good = trusted("Stormwind Guard", "ストームウィンドの衛兵", "すとーむうぃんどのえいへい")
    bad = trusted("Stormwind City", "ストームウインド市", "すとーむういんどし")
    free = trusted("Stormwind Keep", "王城", "おうじょう", free=True)
    out = names.spelling_problems([good, bad, free], words)
    assert len(out) == 1 and "Stormwind City" in out[0]


def _cards(tmp: Path, cards: list[tuple[int, str, str]]) -> tuple[Path, Path]:
    ja = tmp / "jaJP.json"
    en = tmp / "enUS.json"
    ja.write_text(json.dumps([{"dbfId": i, "name": j} for i, _, j in cards]), encoding="utf-8")
    en.write_text(json.dumps([{"dbfId": i, "name": e} for i, e, _ in cards]), encoding="utf-8")
    return ja, en


def _store(tmp: Path, lines: list[dict]) -> Path:
    root = tmp / "data"
    (root / "english").mkdir(parents=True)
    save_lines(root, lines)
    return root


def test_hearthstone_fills_exact_katakana_names_and_words(tmp_path):
    root = _store(
        tmp_path,
        [
            names.ordered(dict(names.new_line(e, TODAY), ids={"unit": [1]}))
            for e in ("Thrall", "Polymorph", "Defias Bandit")
        ],
    )
    human = trusted("Ragnaros", "ラグナロス", "らぐなろす")
    human["provenance"] = {"class": "human", "source": "correction@2026-11-01", "imported": TODAY}
    save_lines(root, [*load_lines(root), human])
    ja, en = _cards(
        tmp_path,
        [
            (1, "Thrall", "スロール"),
            (2, "Polymorph", "動物変身"),
            (3, "Defias Ringleader", "デファイアス・リングリーダー"),
            (4, "Defias Cannon", "デファイアス・キャノン"),
            (5, "Ragnaros", "ラグナ"),
        ],
    )
    counts = cmd.apply_hearthstone(root, cmd.hearthstone_pairs(ja, en), "256589", TODAY)
    by_en = {ln["en"]: ln for ln in load_lines(root)}
    assert (
        by_en["Thrall"]["ja"] == "スロール"
        and by_en["Thrall"]["provenance"]["source"] == "hearthstone@256589"
    )
    assert (
        by_en["Polymorph"]["status"] == "missing"
    )  # kanji: no reading from Hearthstone, drafted with a hint
    assert by_en["Ragnaros"]["ja"] == "ラグナロス"  # a human line is never touched
    words = {w["en"]: w for w in load_words(root)}
    assert words["Defias"]["ja"] == "デファイアス" and words["Defias"]["check"] is True
    assert counts["names filled"] == 1


def test_import_fills_rejects_and_adds_words(tmp_path):
    root = _store(
        tmp_path,
        [
            names.ordered(dict(names.new_line(e, TODAY), ids={"unit": [1]}))
            for e in ("Ashenvale Hunter", "Thrall")
        ],
    )
    ids = {ln["en"]: ln["id"] for ln in load_lines(root)}
    batch = tmp_path / "b.jsonl"
    batch.write_text(
        "\n".join(
            json.dumps(r, ensure_ascii=False)
            for r in [
                {
                    "id": ids["Ashenvale Hunter"],
                    "ja": "アッシェンヴェイルの狩人",
                    "reading": "あっしぇんゔぇいるのかりゅうど",
                    "free": False,
                    "words": [["Ashenvale", "アッシェンヴェイル"]],
                },
                {"id": ids["Thrall"], "ja": "Thrall", "reading": "すろーる", "free": False},
                {"id": "ffffffffffffffff", "ja": "x", "reading": "x", "free": False},
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    n, rejected = cmd.import_batch(root, batch, "test-model", "test1", TODAY, dry_run=False)
    assert n == 1 and len(rejected) == 2
    by_en = {ln["en"]: ln for ln in load_lines(root)}
    assert by_en["Ashenvale Hunter"]["provenance"]["source"] == "draft-names-test1@2026-11-10"
    assert by_en["Thrall"]["status"] == "missing"
    assert {w["en"] for w in load_words(root)} == {"Ashenvale"}


# The committed store: complete, valid, and current with every English name the game shows.


def test_committed_names_are_valid(root):
    assert cmd.problems(root / "data") == []


def test_every_name_has_japanese(root):
    left = [ln["en"] for ln in load_lines(root / "data") if ln["status"] == "missing"]
    assert left == [], f"{len(left)} names with no Japanese (wfj names export / import), e.g. {left[:10]}"


def test_every_english_name_has_a_line(root):
    """A re-pull, a collector send or a translation that brings a new name fails here until `wfj names
    collect` and a drafting round give it a line."""
    data = root / "data"
    have = {ln["id"]: ln for ln in load_lines(data)}
    want: dict[str, set[str]] = {}
    for en, kinds in cmd.english_names(data).items():
        want.setdefault(names.name_id(en), set()).update(kinds)
    for en in cmd.prose_names(data):
        want.setdefault(names.name_id(en), set()).add("prose")
    absent = sorted(i for i in want if i not in have)
    assert absent == [], f"{len(absent)} English names with no data/name line (wfj names collect)"


def test_latin_runs_leave_a_glued_count_to_its_counter():
    assert names.latin_runs("mageweave cloth60枚とNG-5") == ["mageweave cloth", "NG-5"]


def test_names_that_differ_only_in_case_read_one_way():
    a = trusted("Aerie Peak", "エアリー峰", "えありーほう")
    b = trusted("Aerie peak", "エアリー・ピーク", "えありー・ぴーく")
    assert len(names.case_problems([a, b])) == 1
    b.update(ja="エアリー峰", reading="えありーほう")
    assert names.case_problems([a, b]) == []
    sap = trusted("sap", "樹液", "じゅえき", free=True)
    assert names.case_problems([trusted("Sap", "昏倒", "こんとう"), sap]) == []


def test_glossary_words_match_whatever_their_case():
    words = [
        {
            "en": "Kil'Jaeden",
            "ja": "キルジェイデン",
            "check": True,
            "provenance": {"class": "human", "source": "hearthstone@256589", "imported": TODAY},
        }
    ]
    line = trusted("KIL'JAEDEN's Fury", "キルジェデンの怒り", "きるじぇでんのいかり")
    assert len(names.spelling_problems([line], words)) == 1


def test_duplicate_ids_are_reported(tmp_path):
    line = trusted("Thrall", "スロール", "すろーる")
    root = tmp_path / "data"
    (root / "name").mkdir(parents=True)
    (root / "name" / f"name-{line['id'][:2]}.jsonl").write_text(
        "".join(json.dumps(line, ensure_ascii=False) + "\n" for _ in range(2)), encoding="utf-8"
    )
    assert any("lines with one id" in p for p in cmd.problems(root))


def test_a_names_row_never_turns_a_hint_into_a_checked_word(tmp_path):
    root = _store(tmp_path, [names.ordered(dict(names.new_line("Iron Helm", TODAY), ids={"item": [1]}))])
    hint = {
        "en": "Iron",
        "ja": "鉄",
        "check": False,
        "provenance": {
            "class": "machine",
            "model": "m",
            "source": "draft-names-vocab1@2026-11-10",
            "imported": TODAY,
        },
    }
    from wfj.io.names_store import save_words

    save_words(root, [hint])
    batch = tmp_path / "b.jsonl"
    batch.write_text(
        json.dumps(
            {
                "id": names.name_id("Iron Helm"),
                "ja": "鉄の兜",
                "reading": "てつのかぶと",
                "free": False,
                "words": [["Iron", "アイアン"]],
            },
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )
    cmd.import_batch(root, batch, "test-model", "test1", TODAY, dry_run=False)
    assert load_words(root) == [hint]


def test_a_glossary_word_listed_twice_is_reported(tmp_path):
    root = _store(tmp_path, [names.ordered(dict(names.new_line("Thrall", TODAY), ids={"unit": [1]}))])
    word = {
        "en": "Thrall",
        "ja": "スロール",
        "check": True,
        "provenance": {"class": "human", "source": "hearthstone@256589", "imported": TODAY},
    }
    (root / "name" / "words.jsonl").write_text(
        "".join(json.dumps(word, ensure_ascii=False) + "\n" for _ in range(2)), encoding="utf-8"
    )
    assert any("listed 2 times" in p for p in cmd.problems(root))


@pytest.mark.parametrize(
    "ja, reading",
    [
        ("マスター整備士キャストパイプ", "ますたーせいびしきゃすとぱいぷ"),
        ("釣り技能＋15", "つりぎのうぷらすじゅうご"),
        ("テスト：ハイバーグの宝箱", "てすと・はいばーぐのたからばこ"),
        ("エス・エイチ・イー（非クエスト）", "えす・えいち・いーひくえすと"),
    ],
)
def test_a_reading_that_reads_the_kana_as_written_fits(ja, reading):
    assert names.align(ja, reading) is not None


def test_spoken_keeps_the_katakana_as_written():
    assert (
        names.spoken("マスター整備士キャストパイプ", "ますたーせいびしきゃすとぱいぷ")
        == "マスターせいびしキャストパイプ"
    )
    assert names.spoken("山のノスリ", "やまのすのり") is None


def test_a_kanji_word_reads_as_the_quest_text_reads_it():
    known = {"乗組員": {"のりくみいん"}, "大杖": {"つえ"}, "麦酒": {"ばくしゅ"}, "手甲": {"てっこう"}}.get
    assert "乗組員" in names.kanji_word_problem("乙女号の乗組員", "おとめごうのじょうくみいん", known)
    assert names.kanji_word_problem("乙女号の乗組員", "おとめごうののりくみいん", known) is None
    assert names.kanji_word_problem("大杖", "つえ", known) is None
    assert names.kanji_word_problem("ライ麦酒", "らいむぎしゅ", known) is None  # ライ麦 + 酒, not 麦酒
    assert "手甲" in names.kanji_word_problem("勇猛の手甲", "ゆうもうのてこう", known)


def test_a_checked_word_may_take_a_voiced_first_sound():
    glossary = names.checked_glossary([{"en": "Spider", "ja": "クモ", "check": True}])
    assert names.misspelled(trusted("Venom Spider", "毒グモ", "どくぐも"), glossary) == []
    assert names.misspelled(trusted("Venom Spider", "毒蜘蛛", "どくぐも"), glossary) == []
    assert names.misspelled(trusted("Venom Spider", "毒蛇", "どくへび"), glossary) == [("Spider", "クモ")]
