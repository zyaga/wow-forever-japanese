"""The style guide has a version and real corpus examples that still equal `data/`; the glossary
holds translated words, never names, and spells races and classes the way the addon fills `{race}` / `{class}`."""

import re
from pathlib import Path

import pytest

from wfj.core import align, language, stat_words
from wfj.core.report import SHIPPED
from wfj.dev import translate_lint as tl
from wfj.dev.translate_batch import STYLE_GUIDE, model_english, style_version
from wfj.io.jsonl_store import Store

EXAMPLE = re.compile(r"```example quest=(\d+) field=(\w+)\nEN:\n(.*?)\nJA:\n(.*?)\n```", re.S)
MIN_EXAMPLES = 12


@pytest.fixture(scope="module")
def guide(root: Path) -> str:
    return (root / STYLE_GUIDE).read_text(encoding="utf-8")


@pytest.fixture(scope="module")
def quest(root: Path):
    data = root / "data"
    ja = {(ln["id"], ln["field"]): ln for ln in Store(data).load("quest")}
    en = {(ln["id"], ln["field"]): ln for ln in Store(data, english=True).load("quest")}
    return ja, en


def test_guide_has_a_version(root: Path):
    assert style_version(root) >= 1


def test_examples_equal_the_trusted_human_corpus(guide, quest):
    ja, en = quest
    examples = EXAMPLE.findall(guide)
    assert len(examples) >= MIN_EXAMPLES
    assert len({(i, f) for i, f, _, _ in examples}) == len(examples), "an example is cited twice"
    for id_, field, en_text, ja_text in examples:
        key = (int(id_), field)
        line = ja[key]
        assert line["provenance"]["class"] == "human", key
        assert line["ja"] == ja_text, key
        if key not in en:
            # a quest Forever does not serve (8765) keeps its human Japanese in data/ but lost its English
            # and does not ship; the example still shows the register, its Japanese still equal to the corpus
            assert line["status"] == "rejected" and line["reasons"] == ["no_english_id"], key
            continue
        assert line["status"] == "trusted", key
        assert model_english(en[key]["en"]) == en_text, key


PLACEHOLDERS_LUA = Path("addon/WoWForeverJapanese/Core/Placeholders.lua")
# English word → the key of Placeholders.CLASS / Placeholders.RACE that the addon fills `{class}` / `{race}` from
TOKEN_WORDS = {
    "warrior": "WARRIOR", "paladin": "PALADIN", "hunter": "HUNTER", "rogue": "ROGUE", "priest": "PRIEST",
    "shaman": "SHAMAN", "mage": "MAGE", "warlock": "WARLOCK", "druid": "DRUID",
    "human": "Human", "orc": "Orc", "dwarf": "Dwarf", "night elf": "NightElf", "undead": "Scourge",
    "tauren": "Tauren", "gnome": "Gnome", "troll": "Troll",
}
ADJECTIVES = {"dwarven": "dwarf", "orcish": "orc", "gnomish": "gnome"}
# Titles and common nouns used alone: fixed renderings chosen for the glossary, not corpus counts
TITLES = {
    "captain": "隊長", "king": "王", "kingdom": "王国", "his majesty": "陛下", "guard": "衛兵", "master": "師匠",
    "township": "町", "messenger": "使者", "daughter": "娘",
    "warchief": "大族長", "inn": "宿屋", "chief": "族長", "chieftain": "族長", "colonel": "大佐", "lady": "奥方",
    "professor": "教授", "highlord": "大君主", "stable master": "厩舎長",
    "trainer": "トレーナー", "arch druid": "大ドルイド", "creators": "創造主",
    "officer": "士官", "commendation officer": "表彰官", "commander": "司令官", "queen": "女王", "prince": "王子",
    "emperor": "皇帝", "duke": "公爵", "council": "評議会", "general": "将軍", "private": "二等兵", "lieutenant": "副官",
    "marshal": "元帥", "cap'n": "船長", "grand crusader": "大十字軍長", "guardian": "守護者",
    "guild master": "ギルドマスター", "flamekeeper": "炎の守り手", "lorekeeper": "伝承の守り手",
    "battlemaster": "戦場指揮官", "goddess": "女神", "foreman": "現場監督", "prospector": "探鉱者",
    "alchemist": "錬金術師", "fisherman": "釣り人", "skinner": "皮はぎ職人", "temple": "神殿", "bank": "銀行",
    "southeast": "南東", "holy light": "聖なる光", "creator": "創造主", "lord": "主",
    "ambassador": "大使", "father": "神父", "templar": "テンプル騎士", "grunt": "兵卒",
    "blacksmith": "鍛冶屋", "tradesman": "商人", "earthshaper": "大地の形成者",
    "auction house": "オークションハウス",
    "sunday": "日曜日", "monday": "月曜日", "tuesday": "火曜日", "wednesday": "水曜日",
    "thursday": "木曜日", "friday": "金曜日", "saturday": "土曜日",
    # book heading / letter words
    "diary": "日記", "day": "日", "fate": "運命", "state": "状況", "volume": "巻", "report": "報告", "army": "軍",
    "honor": "名誉",
    # more titles used on their own
    "mayor": "町長", "clerk": "書記", "baron": "男爵", "princess": "王女", "necromancer": "死霊術師",
    "executioner": "処刑人", "city architect": "都市建築家", "magus": "魔導師",
    "quartermaster": "補給係", "archbishop": "大司教", "chambermaid": "客室係",
}


def _token_spellings(root: Path) -> dict[str, str]:
    lua = (root / PLACEHOLDERS_LUA).read_text(encoding="utf-8")
    return dict(re.findall(r'(\w+) = "([^"]+)"', lua))


def test_race_and_class_words_use_the_addon_token_spellings(root: Path):
    """Races and classes in katakana, spelled as `{race}` / `{class}` expand."""
    glossary = tl.read_glossary(root / tl.GLOSSARY)
    spelled = _token_spellings(root)
    for word, key in TOKEN_WORDS.items():
        assert glossary.get(word) == spelled[key], word
    for adjective, word in ADJECTIVES.items():
        assert glossary.get(adjective) == glossary[word], adjective


def test_titles_use_the_ruled_renderings_and_are_not_required(root: Path):
    glossary, required = tl.read_glossary(root / tl.GLOSSARY), tl.read_required(root / tl.GLOSSARY)
    allowlist = align.load_allowlist((root / tl.ALLOWLIST).read_text(encoding="utf-8"))
    for term, jp in TITLES.items():
        assert glossary.get(term) == jp and term not in required and term not in allowlist, term
        assert language.is_japanese(jp, "text"), term


def test_glossary_renderings_are_single(root: Path):
    """One rendering per term: a drafter copies a `/` pair literally (translate_lint's `slash`)."""
    for term, jp in tl.read_glossary(root / tl.GLOSSARY).items():
        assert "/" not in jp and "／" not in jp, term


def test_glossary_words_are_translated_not_names(root: Path, quest):
    glossary = {t: j for t, j in tl.read_glossary(root / tl.GLOSSARY).items()
                if t not in TOKEN_WORDS and t not in ADJECTIVES and t not in TITLES}
    allowlist = align.load_allowlist((root / tl.ALLOWLIST).read_text(encoding="utf-8"))
    ja, en = quest
    human = [(en[k]["en"].casefold(), ln["ja"]) for k, ln in ja.items()
             if k in en and ln["status"] == "trusted" and ln["provenance"]["class"] == "human"]
    for term, jp in glossary.items():
        assert term not in allowlist, f"{term} is an allowlisted English word"
        assert language.is_japanese(jp, "text") and not re.search(r"[A-Za-z]", jp), term
        word = re.compile(rf"\b{re.escape(term)}\b", re.I)
        uses = [j for e, j in human if word.search(e)]
        kept = sum(1 for j in uses if word.search(j))
        translated = sum(1 for j in uses if jp in j)
        assert translated > kept, f"{term}: corpus keeps it in English {kept}× vs {jp} {translated}×"


UI_RULES = ("1. Meaning in context", "2. Length that fits", "3. Register", "4. Consistency", "5. Format intact",
            "6. Names stay English")
# the pairs the interface-text section cites: key → (English, Japanese); each still ships as cited
UI_EXAMPLES = {
    "CLOSE": ("Close", "閉じる"),
    "CustomizationChoice:1153": ("Close", "寄せ"),
    "ACCEPT": ("Accept", "承諾"),
    "ABANDON_QUEST": ("Abandon Quest", "クエスト放棄"),
    "ERR_INV_FULL": ("Inventory is full.", "バッグがいっぱいです。"),
    "ABANDON_QUEST_CONFIRM": ('Abandon "%s"?', "「%s」を放棄しますか？"),
    "ITEM_MIN_LEVEL": ("Requires Level %d", "必要レベル %d"),
    "EmoteText:528": ("You wave at %s.", "あなたは%sに手を振った。"),
}


def test_guide_has_the_interface_text_rules(guide):
    section = guide.split("## Interface text (UI strings)", 1)
    assert len(section) == 2, "no interface text section"
    body = section[1].split("\n## ", 1)[0]
    for rule in UI_RULES:
        assert f"\n### {rule}\n" in body, rule


def test_interface_text_examples_still_ship(guide, root: Path):
    ja = {ln["id"]: ln for ln in Store(root / "data").load("ui")}
    en = {ln["id"]: ln["en"] for ln in Store(root / "data", english=True).load("ui")}
    for key, (en_text, ja_text) in UI_EXAMPLES.items():
        assert f"`{ja_text}`" in guide, key
        assert en[key] == en_text and ja[key]["ja"] == ja_text and ja[key]["status"] == "trusted", key


TERMS_ROW = re.compile(r"^\| ([a-z ,]+) \| (\S+) \| ([^|]+) \|$", re.M)


def test_settled_interface_terms_hold_on_every_shipped_ui_line(guide, root: Path):
    table = guide.split("Settled interface terms", 1)[1].split("\n\n", 2)[1]
    terms = TERMS_ROW.findall(table)
    assert len(terms) >= 7
    ja = {ln["id"]: ln["ja"] for ln in Store(root / "data").load("ui") if ln["status"] in SHIPPED}
    en = {ln["id"]: ln["en"] for ln in Store(root / "data", english=True).load("ui")}
    bad = []
    for english, _, others in terms:
        word = re.compile(r"\b(" + "|".join(re.escape(t.strip()) for t in english.split(",")) + r")s?\b", re.I)
        wrong = [o.strip() for o in others.split(",")]
        bad += [(k, english) for k, j in ja.items() if k in en and word.search(en[k]) and any(w in j for w in wrong)]
    assert bad == []


def _stat_rows(guide: str) -> dict[str, tuple[str, list[str]]]:
    table = guide.split("Settled interface terms", 1)[1].split("\n\n", 2)[1]
    rows = {en: (ja, [o.strip() for o in others.split(",")]) for en, ja, others in TERMS_ROW.findall(table)}
    return {en: rows[en] for en in stat_words.STAT_WORDS if en in rows}


def test_stat_word_rows_match_the_code(guide):
    rows = _stat_rows(guide)
    assert {en: ja for en, (ja, _) in rows.items()} == stat_words.STAT_WORDS
    for en, (_, others) in rows.items():
        assert en in others, en  # never kept in English letters
        assert set(others) - {en} == set(stat_words.NOT_SPELLINGS.get(en, ())), en


def test_shipped_tooltips_use_the_settled_stat_words(root: Path):
    # Hand-written lines too: each one carries a stat-word correction (ADR-048)
    bad = [
        (type_, ln["id"], ln["field"], stat_words.find(ln["ja"]) + stat_words.not_spellings(ln["ja"]))
        for type_ in ("item", "spell")
        for ln in Store(root / "data").load(type_)
        if ln["status"] in SHIPPED
        and (stat_words.find(ln["ja"]) or stat_words.not_spellings(ln["ja"]))
    ]
    assert bad == []
