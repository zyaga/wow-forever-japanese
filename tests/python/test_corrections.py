"""ADR-012: human decisions survive regeneration, a correction ranks first, and the correction shape."""

import argparse
from pathlib import Path

import pytest

from wfj.cmd import import_predecessor as imp
from wfj.core import decisions, paragraphs
from wfj.core.model import validate_line
from wfj.core.status import Scope, decide
from wfj.io.jsonl_store import Store

PRED = "tests/fixtures/predecessor"
QJP = "tests/fixtures/questjapanizer/QuestData.excerpt.lua"
CJQ = "tests/fixtures/craftjapanizer/QuestData.excerpt.lua"
DATE = "2026-09-13"

CORRECTION = {
    "class": "correction",
    "translator": "Tammy",
    "source": "correction@2026-09-14",
    "imported": "2026-09-14",
    "corrects": "cqjt@3446c82",
    "note": "a name spelled as the English spells it",
}
RULING = {"ruling": "accept", "by": "maintainer", "date": "2026-09-14"}


# ---- helpers ------------------------------------------------------------------------------------------------


def _repos(root: Path, tmp: Path) -> tuple[Path, Path]:
    q = tmp / "quest-repo"
    q.mkdir()
    (q / "QuestLogData.lua").write_text((root / PRED / "QuestLogData.excerpt.lua").read_text("utf-8"), "utf-8")
    t = tmp / "tooltip-repo"
    (t / "Data/Item").mkdir(parents=True)
    (t / "Data/Spell").mkdir(parents=True)
    (t / "Data/Item/ItemData.lua").write_text((root / PRED / "ItemData.excerpt.lua").read_text("utf-8"), "utf-8")
    (t / "Data/Spell/SpellData.lua").write_text((root / PRED / "SpellData.excerpt.lua").read_text("utf-8"), "utf-8")
    return q, t


@pytest.fixture
def bench(root, tmp_path, monkeypatch):
    data = tmp_path / "data"
    for t in ("quest", "item", "spell", "gossip", "unit"):
        (data / t).mkdir(parents=True)
    (data / "SCHEMA").write_text("1\n")
    monkeypatch.setattr(imp, "data_root", lambda start=None: data)
    q, t = _repos(root, tmp_path)
    ns = argparse.Namespace(
        quest_repo=str(q),
        tooltip_repo=str(t),
        commit_quest="3446c82",
        commit_tooltip="84db736",
        date=DATE,
        relabel_translator=None,
        questjapanizer=None,  # one-pass lineage args (the parser defaults)
        qjp_version=None,
        craftjapanizer_quest=None,
        cjq_version=None,
    )
    return data, ns


def _by(data: Path) -> dict:
    return {(ln["id"], ln["field"]): ln for ln in Store(data).load("quest")}


def _save(data: Path, by: dict) -> None:
    Store(data).save("quest", by.values())


def _author_decisions(data: Path) -> None:
    """What a person might have written into data/ between two `make data` runs."""
    by = _by(data)
    # a correction on a line the input produces, and one on a key the input never produces
    by[(2, "description")]["conflicts"].append({"ja": "修正済みの説明文。", "provenance": dict(CORRECTION)})
    by[(90001, "title")] = {
        "id": 90001,
        "field": "title",
        "ja": "手で入れたタイトル",
        "status": "pending",
        "checks": [],
        "provenance": dict(CORRECTION),
        "english": None,
        "reasons": [],
        "conflicts": [],
    }
    # a ruling on an imported variant, and a ruled variant the predecessor input does not produce
    by[(2, "title")]["ruling"] = dict(RULING)
    qjp_objectives = imp.import_questjapanizer((ROOT / QJP).read_text("utf-8-sig"), "qjp@0.5.8", DATE).lines[
        (2, "objectives")
    ]
    by[(2, "objectives")]["conflicts"].append(
        {"ja": qjp_objectives["ja"], "provenance": qjp_objectives["provenance"], "ruling": dict(RULING)}
    )
    # a correction identical to the imported text is still a person's decision (kept); a second,
    # byte-identical correction is redundant
    by[(5, "title")]["conflicts"].append({"ja": by[(5, "title")]["ja"], "provenance": dict(CORRECTION)})
    by[(2, "description")]["conflicts"].append({"ja": "修正済みの説明文。", "provenance": dict(CORRECTION)})
    # a correction that only restores a paragraph break (ja_identity-equal to the import)
    six = by[(6, "description")]
    six["conflicts"].append({"ja": six["ja"].replace("。", "。\n\n", 1), "provenance": dict(CORRECTION)})
    # a person-rejected variant whose key the inputs no longer produce must not ship alone
    by[(90002, "title")] = {
        "id": 90002,
        "field": "title",
        "ja": "却下された題",
        "status": "rejected",
        "checks": [],
        "provenance": {"class": "human", "translator": "Tammy", "source": "cqjt@0000000", "imported": DATE},
        "english": None,
        "reasons": [],
        "conflicts": [],
        "ruling": {"ruling": "reject", "by": "maintainer", "date": "2026-09-14"},
    }
    # an imported line whose stored text drifted by whitespace only (not a decision)
    by[(6, "title")]["ja"] = by[(6, "title")]["ja"].replace("Garrick Padfoot", "Garrick  Padfoot")
    _save(data, by)


ROOT = Path(__file__).resolve().parents[2]


# ---- carry-over in `import predecessor` ---------------------------------------------------------


def test_corrections_and_rulings_survive_the_rebuild(bench, capsys):
    data, ns = bench
    assert imp.run_predecessor(ns) == 0
    pristine = _by(data)
    _author_decisions(data)
    capsys.readouterr()

    assert imp.run_predecessor(ns) == 0
    out = capsys.readouterr().out
    by = _by(data)

    # the correction is a variant of the rebuilt line, provenance intact; the orphan key is its line
    desc = by[(2, "description")]
    assert desc["ja"] == pristine[(2, "description")]["ja"]
    assert [c["provenance"] for c in desc["conflicts"] if c["ja"] == "修正済みの説明文。"] == [CORRECTION]
    assert by[(90001, "title")]["provenance"] == CORRECTION and by[(90001, "title")]["ja"] == "手で入れたタイトル"

    # the ruling is back on the rebuilt variant; the absent ruled variant is kept whole
    assert by[(2, "title")]["ruling"] == RULING
    ruled = [c for c in by[(2, "objectives")]["conflicts"] if c.get("ruling")]
    assert len(ruled) == 1 and ruled[0]["provenance"]["source"] == "qjp@0.5.8"

    # a correction equal to the import is kept as its own variant; the byte-identical duplicate is not
    assert [c["provenance"]["class"] for c in by[(5, "title")]["conflicts"]] == ["correction"]
    assert [c["ja"] for c in desc["conflicts"]].count("修正済みの説明文。") == 1
    assert "carried human decisions (corrections / ruled variants / redundant corrections): quest 4/2/1" in out

    # the paragraph-break-only correction survives (whitespace is significant for corrections)
    kept = [c for c in by[(6, "description")]["conflicts"] if c["provenance"]["class"] == "correction"]
    assert len(kept) == 1 and "\n\n" in kept[0]["ja"]

    # the orphaned reject is not resurrected as a lone shipping line, and that is printed
    assert (90002, "title") not in by
    assert "not carried: quest: 1 orphaned rejects" in out

    # a whitespace-only drift is rebuilt from the input, not kept
    assert by[(6, "title")]["ja"] == pristine[(6, "title")]["ja"]

    for ln in by.values():
        assert validate_line("quest", ln) == [], ln


def test_an_import_never_collapses_into_a_correction():
    col = imp.Collector()
    col.lines[(2, "title")] = {
        "id": 2, "field": "title", "ja": "同じ題", "status": "trusted", "checks": [], "provenance": dict(CORRECTION),
        "english": None, "reasons": [], "conflicts": [],
    }
    wiki = {"class": "human", "translator": "Kaz", "source": "qjp@0.5.8", "imported": DATE}
    col.add(2, "title", "同じ題", wiki, "qjp@0.5.8#9")
    line = col.lines[(2, "title")]
    assert line["provenance"] == CORRECTION  # no adopted credit, no origins
    assert [c["provenance"]["source"] for c in line["conflicts"]] == ["qjp@0.5.8"]


def test_empty_store_prints_zero_carries(bench, capsys):
    data, ns = bench
    assert imp.run_predecessor(ns) == 0
    out = capsys.readouterr().out
    assert "quest 0/0/0 · item 0/0/0 · spell 0/0/0" in out
    assert "not carried:" not in out  # nothing skipped → no line


# ---- byte-stable chain with the lineage importers ---------------------------------------------------------


def test_chain_is_byte_stable_and_a_ruled_lineage_variant_collapses_once(bench):
    data, ns = bench
    assert imp.run_predecessor(ns) == 0
    _author_decisions(data)

    def chain() -> dict:
        assert imp.run_predecessor(ns) == 0
        for rel, fn, src in ((QJP, imp.import_questjapanizer, "qjp@0.5.8"), (CJQ, imp.import_craftjapanizer_quest, "cjq@2012031300")):
            imp._run_lineage(argparse.Namespace(file=str(ROOT / rel), date=DATE), fn, src)
        return {p.name: p.read_bytes() for p in (data / "quest").glob("*.jsonl")}

    first = chain()
    second = chain()
    assert first == second and first

    objectives = _by(data)[(2, "objectives")]
    same = [v for v in [objectives, *objectives["conflicts"]] if v["provenance"]["source"] == "qjp@0.5.8"]
    assert len(same) == 1 and same[0]["ruling"] == RULING
    origins = same[0]["provenance"]["origins"]
    assert len(origins) == len(set(origins))


def test_carried_is_canonical_regardless_of_variant_order():
    a = {"class": "correction", "translator": "A", "source": "correction@2026-09-14", "imported": DATE}
    b = {"class": "human", "translator": "B", "source": "qjp@0.5.8", "imported": DATE}
    line = {"id": 7, "field": "title", "ja": "x", "provenance": b, "ruling": RULING, "conflicts": [{"ja": "y", "provenance": a}]}
    swapped = {"id": 7, "field": "title", "ja": "y", "provenance": a, "conflicts": [{"ja": "x", "provenance": b, "ruling": RULING}]}
    assert decisions.carried([line]) == decisions.carried([swapped])
    assert [v["ja"] for _, _, v in decisions.carried([line])] == ["y", "x"]  # corrections first


# ---- ranking -----------------------------------------------------------------------------------------------

EN_RAW = "Greetings, $N. Kill the Thistle Boar.$B$BThe rains were heavy.$B$BJourney forth, young $c."
EN_NORM = EN_RAW.replace("$B$B", " ").replace("$N", "Reyn").replace("$c", "druid")
JA3 = "御機嫌よう、{name}。Thistle Boarを倒せ。\n\n今年の春は雨が多かった。\n\n若き{class}よ、行け。"
JA2 = "御機嫌よう、{name}。Thistle Boarを倒せ。\n\n今年の春は雨が多かった、若き{class}よ、行け。"


def _scope() -> Scope:
    return Scope(kind="quest", fields={"description": EN_NORM}, raw={"description": EN_RAW}, hashes={"description": "h"}, src="pfquest@7786596")


def _line(ja: str, prov: dict, conflicts: list) -> dict:
    return {"id": 456, "field": "description", "ja": ja, "status": "pending", "checks": [], "provenance": prov,
            "english": None, "reasons": [], "conflicts": conflicts}


QJP_AZ = {"class": "human", "translator": "Az", "source": "qjp@0.5.8", "imported": DATE}
FIX = {"class": "correction", "translator": "Az", "source": "correction@2026-09-14", "imported": "2026-09-14",
       "corrects": "qjp@0.5.8", "note": "Thistle bore → Thistle Boar"}


def test_a_passing_correction_beats_a_passing_import_with_more_paragraphs():
    d = decide(_line(JA3 + "。", QJP_AZ, [{"ja": JA2, "provenance": FIX}]), _scope(), set(), "h")
    assert d.status == "trusted" and d.winner == 1 and "tiebreak" in d.checks


def test_a_passing_correction_beats_an_equal_import_from_any_source():
    cqjt = {"class": "human", "translator": "Tammy", "source": "cqjt@3446c82", "imported": DATE}
    d = decide(_line(JA3 + "。", cqjt, [{"ja": JA3, "provenance": FIX}]), _scope(), set(), "h")
    assert d.winner == 1


def test_a_failing_correction_does_not_ship_and_does_not_block_a_passing_import():
    wrong = JA3.replace("Thistle Boar", "Thistle Bore")
    d = decide(_line(JA3, QJP_AZ, [{"ja": wrong, "provenance": FIX}]), _scope(), set(), "h")
    assert d.status == "trusted" and d.winner == 0


# ---- shape -------------------------------------------------------------------------------------------------


def test_a_correction_needs_a_translator_and_corrects_even_inside_conflicts():
    no_translator = {k: v for k, v in FIX.items() if k != "translator"}
    no_corrects = {k: v for k, v in FIX.items() if k != "corrects"}
    assert any("correction provenance needs a translator" in p for p in validate_line("quest", _line(JA3, no_translator, [])))
    assert any("needs corrects" in p for p in validate_line("quest", _line(JA3, no_corrects, [])))
    # the documented authoring path puts the correction in `conflicts`, validated there too
    waiting = _line(JA3, QJP_AZ, [{"ja": JA2, "provenance": no_translator}])
    assert any("correction provenance needs a translator" in p for p in validate_line("quest", waiting))
    assert validate_line("quest", _line(JA3, QJP_AZ, [{"ja": JA2, "provenance": FIX}])) == []


def test_a_correction_is_judged_by_the_layer_it_corrects():
    wiki_fix = {"class": "correction", "translator": "questjapanizer-wiki", "source": "correction@2026-09-14",
                "imported": "2026-09-14", "corrects": "cqjt@3446c82"}
    assert paragraphs.first_paragraph_only(wiki_fix)
    assert not paragraphs.first_paragraph_only({**wiki_fix, "corrects": "qjp@0.5.8"})
    assert not paragraphs.first_paragraph_only({k: v for k, v in wiki_fix.items() if k != "corrects"})


def test_a_reject_ruling_on_a_lineage_only_line_is_kept_across_the_rebuild():
    """Decisions are carried before the lineage sources merge, so a line only a lineage source produces
    (quest 1958 objectives) does not exist yet at the first carry. Its `reject` ruling is held back and carried
    again after the merge, onto the variant with the same text; one whose line never appears is still orphaned."""
    human = {"class": "human", "translator": "Az", "source": "qjp@0.5.8", "imported": "2026-09-13",
             "origins": ["qjp@0.5.8#1"]}
    ruling = {"ruling": "reject", "by": "maintainer", "date": "2026-09-24", "note": "another quest's text"}
    col = imp.Collector()
    col.carry(1958, "objectives", {"ja": "別クエストの文", "provenance": dict(human), "ruling": dict(ruling)})
    col.carry(9999, "objectives", {"ja": "消えた行", "provenance": dict(human), "ruling": dict(ruling)})
    assert col.orphaned_rejects == 2 and (1958, "objectives") not in col.lines
    col.add(1958, "objectives", "別クエストの文", dict(human), "qjp@0.5.8#1")  # the lineage merge produces it
    pending, col.orphans, col.orphaned_rejects = col.orphans, [], 0
    for id_, field, variant in pending:
        col.carry(id_, field, variant)
    assert col.lines[(1958, "objectives")]["ruling"] == ruling
    assert col.orphaned_rejects == 1 and (9999, "objectives") not in col.lines
