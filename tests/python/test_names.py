"""Japanese names (ADR-078): the name store, the glossary, Hearthstone, drafting import, the one-spelling
check, and the committed store being complete and current."""

from __future__ import annotations

import json
import re
from pathlib import Path

import pytest

from wfj.cmd import generate
from wfj.cmd import names as cmd
from wfj.core import names
from wfj.emit import lua_writer
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


def test_every_name_is_the_spelling_of_its_english_words(root):
    """The whole table: a name nobody corrected by hand is its words' katakana, put together by the rules, so
    a translated name cannot come back with a re-pull or a drafting round."""
    data = root / "data"
    problems = cmd.respell_problems(load_lines(data), load_words(data))
    assert problems == [], f"{len(problems)} names are not spelled from their English, e.g. {problems[:5]}"


def test_no_possessive_is_a_bare_zu_after_a_sound_that_changes_it(root):
    """The whole table, read without the assembly: where a name's parts line up with its words, the part of
    a possessive word is never its spelling with ズ put on when that spelling ends in ト, ク, フ, プ or ズ. (A
    word ending in ス with no possessive of its own is a name with no spelling, which the test above reports.)"""
    from wfj.core import respell

    data = root / "data"
    spelled = {w["en"].casefold(): w["ja"] for w in load_words(data)}
    bad = []
    for ln in load_lines(data):
        if ln["status"] != "trusted" or ln["provenance"]["class"] != "machine" or "ズ" not in ln["ja"]:
            continue
        owners = {m.casefold() for m in re.findall(r"([^\W\d_](?:[^\W\d_]|['’])*?)['’]s\b", ln["en"])}
        ws = [w.casefold() for w in respell.words(ln["en"])]
        parts = [p for p in re.split("[・：（）、！？＋]", ln["ja"]) if p]
        for w, part in zip(ws, parts, strict=False) if len(ws) == len(parts) else ():
            ja = spelled.get(w, "")
            if w in owners and ja and ja[-1] in "トクフプズ" and part == ja + "ズ":
                bad.append(f"{ln['en']} = {ln['ja']}")
    assert bad == [], f"{len(bad)} names put a bare ズ on a possessive, e.g. {bad[:5]}"


def test_every_word_has_one_katakana_spelling(root):
    words = load_words(root / "data")
    seen: dict[str, set[str]] = {}
    for w in words:  # a word may be listed in two capitalisations; it is still spelled one way
        seen.setdefault(w["en"].casefold(), set()).add(w["ja"])
    twice = sorted(k for k, ja in seen.items() if len(ja) > 1)
    assert twice == [], f"{len(twice)} words are spelled more than one way, e.g. {twice[:5]}"
    other = sorted(w["en"] for w in words if not names.KATAKANA.match(w["ja"]))
    assert other == [], f"{len(other)} words are not spelled in katakana, e.g. {other[:5]}"


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


def test_latin_runs_skip_tooltip_markup():
    ja = (
        "$?a5487|a9634[|CFFFFFFFF必要：Cat Form|R][|CFFFF2020必要：Cat Form|R]、|cnIQ1:Peacebloom|r、"
        "%S1のShadowダメージ。$?pc142418[さらに][]"
    )
    assert names.latin_runs(ja) == ["Cat Form", "Cat Form", "Peacebloom", "Shadow"]


def test_table_names_read_item_suffixes_and_flight_points(tmp_path):
    (tmp_path / "ItemNameDescription.csv").write_text(
        "ID,Description_lang\n14231,Sanctified\n14455,of the Monkey\n", encoding="utf-8"
    )
    (tmp_path / "TaxiNodes.csv").write_text(
        'ID,Name_lang\n4,"Sentinel Hill, Westfall"\n2913,Quest Path 9571: 1.60.0 - Shaman\n', encoding="utf-8"
    )
    assert cmd.table_names(tmp_path) == {"suffix": {14455: "of the Monkey"}, "taxi": {4: "Sentinel Hill, Westfall"}}
    assert cmd.table_names(tmp_path / "absent") == {"suffix": {}, "taxi": {}}


def test_a_flight_point_is_exported_with_its_parts(tmp_path):
    hill = trusted("Sentinel Hill", "センチネル・ヒル", "せんちねる・ひる")
    point = names.ordered(dict(names.new_line("Sentinel Hill, Westfall", TODAY), ids={"taxi": [4]}))
    root = _store(tmp_path, [hill, point])
    cmd.export(root, tmp_path / "out", 10, None)
    (row,) = [json.loads(r) for r in (tmp_path / "out" / "batch-000.jsonl").read_text().splitlines()]
    assert row["kinds"] == {"taxi": 1}
    assert row["parts"] == [["Sentinel Hill", "センチネル・ヒル", "せんちねる・ひる"], None]


@pytest.mark.parametrize(
    ("ja", "reading", "parts"),
    [
        ("スロール", "すろーる", [("スロール", "すろーる")]),
        ("アイアン・フォージ", "あいあん・ふぉーじ", [("アイアン", "あいあん"), ("・", "・"), ("フォージ", "ふぉーじ")]),
        ("アイアン・フォージ", "あいあんふぉーじ", [("アイアン", "あいあん"), ("・", ""), ("フォージ", "ふぉーじ")]),
        ("森の番人", "もりのばんにん", [("森", "もり"), ("の", "の"), ("番人", "ばんにん")]),
        ("マスター整備士", "ますたーせいびし", [("マスター", "ますたー"), ("整備士", "せいびし")]),
    ],
)
def test_align_gives_each_part_of_a_name_its_reading(ja, reading, parts):
    assert names.align(ja, reading) == parts


@pytest.mark.parametrize(
    ("ja", "reading"),
    [("ノスリ", "すのり"), ("スロール", "すろーるず"), ("森の番人", "もりばんにん"), ("スロール", "")],
)
def test_align_refuses_a_reading_that_does_not_fit(ja, reading):
    assert names.align(ja, reading) is None


def test_a_generated_name_row_is_its_japanese_and_reading_without_the_english():
    line = trusted("Thrall", "スロール", "すろーる")
    text = lua_writer.names_text("00", [line])
    assert f'["{line["id"]}"] = "スロール\\tすろーる",' in text
    assert "Thrall" not in text
    assert 'WFJ.Data.add("name", {' in text


def test_name_tables_load_last_in_the_toc():
    planned = {
        "Data/Names/Names_0a.lua": "",
        "Data/Meta.lua": "",
        "Data/Names/Names_00.lua": "",
        "Data/Quest/Quest_0000.lua": "",
    }
    assert generate.toc_files(planned) == [
        "Data/Meta.lua",
        "Data/Quest/Quest_0000.lua",
        "Data/Names/Names_00.lua",
        "Data/Names/Names_0a.lua",
    ]


JA_NAMES = {
    "Stormwind": "ストームウィンド",
    "Kobold Vermin": "コボルド・バーミン",
    "Zul'Gurub": "ズルグルブ",
    "mageweave cloth": "メイジウィーブ・クロス",
    "Linen Cloth": "リネン・クロス",
}


@pytest.mark.parametrize(
    ("ja", "out"),
    [
        ("StormwindでKobold Verminを10匹倒せ。", "ストームウィンドでコボルド・バーミンを10匹倒せ。"),
        ("Zul'Gurub、そしてUnknown Place。", "ズルグルブ、そしてUnknown Place。"),
        ("mageweave cloth60枚を集めよ。", "メイジウィーブ・クロス60枚を集めよ。"),
        ("Kobold Vermin 10", "コボルド・バーミン 10"),
        ("|cffffd100Stormwind|rへ行け、{name}。", "|cffffd100ストームウィンド|rへ行け、{name}。"),
        ("|Hitem:2589::::|h[Linen Cloth]|hを$N1枚。", "|Hitem:2589::::|h[リネン・クロス]|hを$N1枚。"),
        ("|TInterface\\Icons\\Stormwind:16|t Stormwind", "|TInterface\\Icons\\Stormwind:16|t ストームウィンド"),
        ("%sはStormwindにいる。%d", "%sはストームウィンドにいる。%d"),
        ("名前なし。", "名前なし。"),
    ],
)
def test_replace_runs_puts_each_names_japanese_where_its_english_stood(ja, out):
    assert names.replace_runs(ja, JA_NAMES.get) == out


def test_replace_runs_leaves_html_tags_alone_on_an_html_page():
    page = "<HTML><BODY><H1 align=\"center\">Stormwind</H1><P>Kobold Verminの話。</P></BODY></HTML>"
    want = "<HTML><BODY><H1 align=\"center\">ストームウィンド</H1><P>コボルド・バーミンの話。</P></BODY></HTML>"
    assert names.replace_runs(page, {**JA_NAMES, "BODY": "ボディ", "P": "ピー", "HTML": "x"}.get, html=True) == want


def test_the_name_vectors_are_current_and_cover_every_shape(root, tmp_path):
    from wfj.dev import gen_name_vectors

    gen_name_vectors.write(root / "data", tmp_path)
    for name in ("name_vectors.jsonl", "name_vectors.lua"):
        made = (tmp_path / name).read_text(encoding="utf-8")
        assert made == (root / "vectors" / name).read_text(encoding="utf-8"), f"{name}: run make vectors"
    rows = [json.loads(r) for r in (root / "vectors" / "name_vectors.jsonl").read_text(encoding="utf-8").splitlines()]
    hashes = [r["en"] for r in rows if r["t"] == "hash"]
    lines = [r for r in rows if r["t"] == "line"]
    assert len(hashes) >= 200 and len(lines) >= 300
    for shape, test in gen_name_vectors.SHAPES.items():
        assert any(test(en) for en in hashes), shape
    assert any(r["html"] for r in lines) and any(r["ja"] != r["out"] for r in lines)


def test_words_kept_as_written_on_screen():
    keep = frozenset({"PvP", "World of Warcraft"})
    for word in ("PvP", "World of Warcraft", "v", "a", "II", "XIV"):
        assert names.kept_as_written(word, keep), word
    for word in ("Cooking", "Stormwind", "Alterac Valley", "Mix"):
        assert not names.kept_as_written(word, keep), word


def test_the_shipped_name_tables_leave_out_the_words_kept_as_written():
    repo = Path(__file__).resolve().parents[2]
    keep = generate.load_kept_as_written(repo / "data")
    assert {"PvP", "NPC", "GM", "WoW", "Blizzard", "World of Warcraft"} <= keep
    shipped = "".join(p.read_text(encoding="utf-8") for p in (repo / "addon/WoWForeverJapanese/Data/Names").glob("*.lua"))
    for ln in load_lines(repo / "data"):
        if ln["status"] == "trusted" and names.kept_as_written(ln["en"], keep):
            assert f'"{ln["id"]}"' not in shipped, ln["en"]


def test_replace_runs_leaves_an_interface_lines_own_markup():
    known = {"Fishing": "フィッシング", "a": "ア", "guide": "ガイド"}
    line = "|A:newplayerchat-chaticon-guide:0:0:0:0|a|Kq1|kとFishingを %d |4guide:guides;"
    assert names.replace_runs(line, known.get) == (
        "|A:newplayerchat-chaticon-guide:0:0:0:0|a|Kq1|kとフィッシングを %d |4guide:guides;"
    )


def test_replace_runs_joins_a_suffixed_items_two_names():
    known = {"Bandit Cloak": "バンディット・クローク", "of the Owl": "オブ・ジ・アウル"}
    assert names.replace_runs("売却: Bandit Cloak of the Owl", known.get) == (
        "売却: バンディット・クローク・オブ・ジ・アウル"
    )
    assert names.replace_runs("Cloak of Nothing Knownを", known.get) == "Cloak of Nothing Knownを"
