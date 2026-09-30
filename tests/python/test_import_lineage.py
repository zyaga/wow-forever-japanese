"""The relabel flag, the QuestJapanizer / CraftJapanizer_Quest importers, merge semantics, and the dotted-name
Lua reader."""

import inspect
import json

import pytest

from wfj.cmd import import_, import_draft, import_english
from wfj.cmd import import_predecessor as imp
from wfj.core.model import validate_line
from wfj.io.jsonl_store import Store
from wfj.io.lua_reader import parse_assignment

QJP = "tests/fixtures/questjapanizer/QuestData.excerpt.lua"
CJQ = "tests/fixtures/craftjapanizer/QuestData.excerpt.lua"
PRED = "tests/fixtures/predecessor/QuestLogData.excerpt.lua"
DATE = "2026-09-13"


def _read(root, rel):
    return (root / rel).read_text(encoding="utf-8-sig")


# ---- --relabel-translator ---------------------------------------------------------------------------------


def test_predecessor_refuses_exclude_translator(tmp_path, monkeypatch):
    data = tmp_path / "data"
    (data / "quest").mkdir(parents=True)
    monkeypatch.setattr(imp, "data_root", lambda start=None: data)
    with pytest.raises(SystemExit) as e:
        import_.run(["predecessor", "--quest-repo", "q", "--tooltip-repo", "t", "--exclude-translator", "Tammy"])
    assert e.value.code == 2
    assert list(data.rglob("*")) == [data / "quest"]  # nothing written anywhere under data/


def test_no_exclusion_path_remains():
    assert "exclude" not in inspect.signature(imp.import_quests).parameters
    assert "exclude" not in inspect.signature(imp.Collector.carry).parameters
    source = "".join(inspect.getsource(m) for m in (import_, imp, import_english, import_draft))
    for gone in ("exclude_translator", "carried_excluded"):
        assert gone not in source, gone


def test_relabel_translator_renames_and_counts(root):
    text = _read(root, PRED)
    full = imp.import_quests(text, "cqjt@3446c82", DATE)
    victim = sorted({ln["provenance"]["translator"] for ln in full.lines.values()})[0]
    col = imp.import_quests(text, "cqjt@3446c82", DATE, relabel={victim: "questjapanizer-wiki"})
    tags = {ln["provenance"]["translator"] for ln in col.lines.values()}
    assert victim not in tags and "questjapanizer-wiki" in tags
    assert col.relabelled > 0 and len(col.lines) == len(full.lines)  # nothing dropped, only renamed


def test_predecessor_import_normalises_breaks_and_placeholders(root):
    col = imp.import_quests(_read(root, PRED), "cqjt@3446c82", DATE)
    desc = col.lines[(2, "description")]["ja"]
    assert "\n\n" in desc and "  " not in desc  # the two-space break became canonical
    assert col.lines[(2, "title")]["ja"] == "Sharptalonの鉤爪"  # titles untouched


# ---- QuestJapanizer ---------------------------------------------------------------------------------------


def test_questjapanizer_wiki_rows_only_with_credit_and_paragraphs(root):
    col = imp.import_questjapanizer(_read(root, QJP), "qjp@0.5.8", DATE)
    ids = {i for i, _ in col.lines}
    assert ids == {2, 456}  # 1452 is `auto` (machine) and must not land
    assert col.dropped == 1
    d456 = col.lines[(456, "description")]
    assert d456["ja"].count("\n\n") == 2  # three paragraphs
    assert "翻訳" not in d456["ja"] and d456["provenance"]["translator"] == "Az"
    assert d456["provenance"]["source"] == "qjp@0.5.8" and d456["provenance"]["class"] == "human"
    assert "{name}" in d456["ja"] and "{class}" in d456["ja"] and "YOUR_" not in d456["ja"]
    assert col.lines[(456, "completion")]["ja"] == "よくやってくれた、{name}。"
    d2 = col.lines[(2, "description")]
    assert d2["provenance"]["translator"] == "questjapanizer-wiki"  # uncredited → the community
    for (id_, _), ln in col.lines.items():
        assert validate_line("quest", ln) == [], (id_, ln)


# ---- CraftJapanizer_Quest ---------------------------------------------------------------------------------


def test_craftjapanizer_named_status1_rows_only(root):
    col = imp.import_craftjapanizer_quest(_read(root, CJQ), "cjq@2012031300", DATE)
    ids = {i for i, _ in col.lines}
    assert ids == {2, 8746}  # the unnamed status-0 and status-1 rows are skipped
    assert col.dropped == 2
    d2 = col.lines[(2, "description")]
    assert d2["provenance"] == {
        "class": "human",
        "translator": "Tammy",
        "source": "cjq@2012031300",
        "imported": DATE,
        "origins": ["cjq@2012031300#1"],
    }
    assert "\n\n" in d2["ja"]  # the two-space break
    assert (2, "progress") not in col.lines  # empty fields omitted
    assert (8746, "completion") in col.lines
    for ln in col.lines.values():
        assert validate_line("quest", ln) == []


def test_lua_reader_accepts_dotted_assignment():
    name, t = parse_assignment('CraftJapanizer_Quest.Data={["2"]={"a","b"}}')
    assert name == "CraftJapanizer_Quest.Data" and t.get("2").positional() == ["a", "b"]
    name, _ = parse_assignment("Plain = {}")
    assert name == "Plain"


# ---- merge into the existing store ------------------------------------------------------------------


def _seeded(existing):
    col = imp.Collector()
    col.seed(existing)
    return col


def test_merge_identical_appends_origin_and_different_appends_variant():
    prov_a = {"class": "human", "translator": "Tammy", "source": "cqjt@3446c82", "imported": DATE}
    base = imp.Collector()
    base.add(2, "description", "同じ文。\n\n二段落。", prov_a, "cqjt@3446c82#1")
    existing = list(base.lines.values())

    col = _seeded(existing)
    prov_b = {"class": "human", "translator": "Az", "source": "qjp@0.5.8", "imported": DATE, "origins": ["x"]}
    col.add(2, "description", "同じ文。\n\n二段落。", prov_b, "qjp@0.5.8#7")  # identical → origin only
    col.add(2, "completion", "新しい行。", prov_b, "qjp@0.5.8#7")  # new key → new line
    col.add(2, "description", "違う文。", prov_b, "qjp@0.5.8#7")  # different → variant

    line = col.lines[(2, "description")]
    assert line["provenance"]["translator"] == "Tammy"  # the existing line keeps its own provenance
    assert line["provenance"]["origins"] == ["cqjt@3446c82#1", "qjp@0.5.8#7"]
    assert [c["ja"] for c in line["conflicts"]] == ["違う文。"]
    assert line["conflicts"][0]["provenance"]["origins"] == ["qjp@0.5.8#7"]
    assert "origins" not in prov_b or line["conflicts"][0]["provenance"]["origins"] != ["x"]
    assert col.lines[(2, "completion")]["provenance"]["source"] == "qjp@0.5.8"
    assert col.collapsed == 1 and col.conflicts == 1


def test_lineage_runs_are_byte_stable(root, tmp_path, monkeypatch):
    """The whole chain (predecessor excerpt → qjp → cjq) twice into a tmp data root: identical files."""
    data = tmp_path / "data"
    for t in ("quest", "item", "spell", "gossip", "unit"):
        (data / t).mkdir(parents=True)
    (data / "SCHEMA").write_text("1\n")
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(imp, "data_root", lambda start=None: data)

    def chain():
        store = Store(data)
        pred = imp.import_quests(
            _read(root, PRED), "cqjt@3446c82", DATE, relabel={"CraftJapanizer": "questjapanizer-wiki"}
        )
        store.save("quest", pred.lines.values())
        for rel, fn, src in ((QJP, imp.import_questjapanizer, "qjp@0.5.8"), (CJQ, imp.import_craftjapanizer_quest, "cjq@2012031300")):
            ns = type("A", (), {"file": str(root / rel), "date": DATE})()
            imp._run_lineage(ns, fn, src)
        return {p.name: p.read_bytes() for p in (data / "quest").glob("*.jsonl")}

    first = chain()
    second = chain()
    assert first == second and first
    lines = [json.loads(ln) for f in (data / "quest").glob("*.jsonl") for ln in f.read_text().splitlines()]
    srcs = {ln["provenance"]["source"].split("@")[0] for ln in lines}
    assert srcs == {"cqjt", "qjp", "cjq"}
    l456 = [ln for ln in lines if ln["id"] == 456 and ln["field"] == "description"]
    assert l456 and l456[0]["provenance"]["source"] == "qjp@0.5.8"


@pytest.mark.parametrize("bad", ['Other = {["1"]={"x"}}', 'QuestJapanizer_QuestData = {["1"]="notatable"}'])
def test_questjapanizer_rejects_wrong_shapes(bad):
    with pytest.raises(ValueError):
        imp.import_questjapanizer(bad, "qjp@0.5.8", DATE)


# ---- credits, placeholders, merge hygiene --------------------------------------------------------------------


@pytest.mark.parametrize(
    "raw, text, credit",
    [
        ("本文。翻訳:Az", "本文。", "Az"),
        ("本文。  翻訳： Pepper Pot", "本文。", "Pepper Pot"),
        ("本文。  翻訳　Forsaken", "本文。", "Forsaken"),
        ("本文。[翻訳：Narks]", "本文。", "Narks"),
        ("本文。  翻訳: Kaz, Tammy", "本文。", "Kaz, Tammy"),
        ("本文。  翻訳: Towayve  <blockquote>", "本文。", "Towayve"),
        ("翻訳者に感謝する本文。", "翻訳者に感謝する本文。", None),  # 翻訳 inside the prose is not a credit
    ],
)
def test_strip_credit_forms(raw, text, credit):
    assert imp.strip_credit(imp.prepare_ja("description", raw)) == (text, credit)


def test_prepare_ja_placeholders_any_case_and_markup():
    assert imp.prepare_ja("description", "<Class>よ、<NAME>。YOUR_RACE <blockquote>") == "{class}よ、{name}。{race}"


def test_questjapanizer_credit_on_completion_is_stripped_and_used_as_fallback():
    text = (
        'QuestJapanizer_QuestData = {\n'
        '["442"] = {["Title"]="T", ["Description"]="本文だ。", ["Completion"]="終わり。翻訳:Yumiko", ["TranslationStat"]="wiki"},\n'
        '["443"] = {["Title"]="T", ["Description"]="本文だ。翻訳:Az", ["Completion"]="終わり。翻訳:Yumiko", ["TranslationStat"]="wiki"},\n'
        '}'
    )
    col = imp.import_questjapanizer(text, "qjp@0.5.8", DATE)
    assert col.lines[(442, "completion")]["ja"] == "終わり。"
    assert col.lines[(442, "description")]["provenance"]["translator"] == "Yumiko"
    assert col.lines[(443, "description")]["provenance"]["translator"] == "Az"  # Description credit wins
    assert col.credit_tails == 0


def test_merge_adopts_named_credit_over_community_label_and_dedupes_variants():
    anon = {"class": "human", "translator": "questjapanizer-wiki", "source": "cqjt@3446c82", "imported": DATE}
    named = {"class": "human", "translator": "Tammy", "source": "qjp@0.5.8", "imported": DATE}
    col = imp.Collector()
    col.add(2, "description", "同じ文。", anon, "cqjt@3446c82#1")
    col.add(2, "description", "同じ文。", named, "qjp@0.5.8#1")  # identical → credit adopted, source kept
    line = col.lines[(2, "description")]
    assert line["provenance"]["translator"] == "Tammy" and line["provenance"]["source"] == "cqjt@3446c82"
    assert col.credited == 1
    col.add(2, "description", "違う文。", named, "qjp@0.5.8#1")  # a variant
    col.add(2, "description", "違う文。", named, "cjq@2012031300#1")  # identical to that variant → one more origin
    col.add(2, "description", "違う文。", named, "cjq@2012031300#1")  # the same origin again → no duplicate
    assert [c["ja"] for c in line["conflicts"]] == ["違う文。"]
    assert line["conflicts"][0]["provenance"]["origins"] == ["qjp@0.5.8#1", "cjq@2012031300#1"]
    assert col.conflicts == 1 and col.collapsed == 3


def test_relabel_flag_requires_old_equals_new():
    with pytest.raises(SystemExit):
        imp._parse_relabel(["CraftJapanizer"])
    assert imp._parse_relabel(["A=B", "C=D=E"]) == {"A": "B", "C": "D=E"}
