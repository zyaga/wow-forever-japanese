"""Quest `description` / `objectives` lines whose hand-written text
is cut short (rejected `truncated`, so nothing ships and the player reads English) are translated whole by
the model and replace that text.

`rule_held_back --field description|objectives` records the decision the ADR-012 way, as it does for
completion (`test_held_back_completion.py`), but only on lines with a `truncated` reason: a description
rejected for a misspelled name alone is a hand correction's job. `cut --held-back` then reaches the two quest
kinds.
"""

from pathlib import Path

import pytest

from wfj.core import decisions
from wfj.dev import rule_held_back as rhb
from wfj.dev import translate_batch as tb
from wfj.io.jsonl_store import Store

HUMAN = {"class": "human", "translator": "questjapanizer-wiki", "source": "cqjt@3446c82",
         "imported": "2026-09-13"}
HUMAN2 = {"class": "human", "translator": "Az", "source": "qjp@0.5.8", "imported": "2026-09-13"}
EN = "The kobolds took the mine, $N.$B$BDrive them out.$B$BThen return to me."
MODEL_EN = "The kobolds took the mine, {name}.\n\nDrive them out.\n\nThen return to me."


def _ja(id_, field, status, reasons=("truncated:1/3",), conflicts=(), **kw):
    return {"id": id_, "field": field, "ja": "コボルドが鉱山を奪った。", "status": status, "checks": [],
            "provenance": dict(HUMAN), "english": None, "reasons": list(reasons),
            "conflicts": [dict(c) for c in conflicts], **kw}


def _en(id_, field, en=EN):
    return {"id": id_, "field": field, "en": en, "hash": "0" * 16, "src": "wdb@1.15.9.69722"}


@pytest.fixture
def repo(tmp_path: Path) -> Path:
    (tmp_path / "data").mkdir()
    (tmp_path / "data" / "SCHEMA").write_text("1\n")
    (tmp_path / "docs" / "content").mkdir(parents=True)
    (tmp_path / "docs" / "content" / "translation-style-guide.md").write_text("# guide\n\nversion: sg9\n")
    data = tmp_path / "data"
    Store(data, english=True).save("quest", [
        _en(1, "description"),   # truncated → ruled
        _en(2, "description"),   # truncated + alignment_failed, two human variants → both ruled
        _en(3, "description"),   # alignment_failed only → a correction's job, not ruled
        _en(4, "description"),   # trusted → never touched
        _en(5, "objectives"),    # truncated objectives → ruled under --field objectives only
        _en(6, "completion"),    # truncated completion → the completion field, not description
        _en(7, "title"),         # a title → out of scope
    ])                           # quest 8 below has no English → out of scope
    Store(data).save("quest", [
        _ja(1, "description", "rejected"),
        _ja(2, "description", "rejected", reasons=("alignment_failed:Kobold", "truncated:1/3"),
            conflicts=[{"ja": "別訳", "provenance": HUMAN2}]),
        _ja(3, "description", "rejected", reasons=("alignment_failed:Kobold",)),
        _ja(4, "description", "trusted", reasons=()),
        _ja(5, "objectives", "rejected", reasons=("truncated:1/1",)),
        _ja(6, "completion", "rejected"),
        _ja(7, "title", "rejected"),
        _ja(8, "description", "rejected"),
    ])
    return tmp_path


def _ids(lines):
    return sorted(ln["id"] for ln in lines)


def _load(repo):
    data = repo / "data"
    return Store(data).load("quest"), Store(data, english=True).load("quest")


def test_description_selects_only_unshipped_truncated_lines_with_english(repo):
    lines, english = _load(repo)
    rule, ruled = rhb.held_back(lines, english, "description")
    # 3 is rejected for a name alone, 4 ships, 5 / 6 / 7 are other fields, 8 has no English
    assert _ids(rule) == [1, 2] and ruled == []


def test_objectives_selects_its_own_field(repo):
    lines, english = _load(repo)
    rule, _ = rhb.held_back(lines, english, "objectives")
    assert _ids(rule) == [5]


def test_completion_keeps_its_scope_any_rejection_reason(repo):
    """The default field is unchanged: any non-shipping completion line with hand-written text,
    not only truncated ones."""
    lines, english = _load(repo)
    assert _ids(rhb.held_back(lines, english)[0]) == [6]
    assert rhb.held_back(lines, english) == rhb.held_back(lines, english, "completion")


def test_the_default_run_is_the_completion_output_and_note(repo, monkeypatch, capsys):
    """Without --field the CLI prints and writes the completion count and the completion note."""
    monkeypatch.setattr(rhb, "data_root", lambda: repo / "data")
    assert rhb.main(["--date", "2026-09-23", "--examples", "0"]) == 0
    assert capsys.readouterr().out == (
        "held-back completion lines: 1\n(dry run; pass --apply to write the rulings)\n"
    )
    assert rhb.main(["--date", "2026-09-23", "--examples", "0", "--apply"]) == 0
    line = next(ln for ln in Store(repo / "data").load("quest") if ln["id"] == 6)
    assert line["ruling"]["note"] == rhb.NOTE


def test_the_ruling_carries_the_truncated_note_on_every_hand_written_variant(repo):
    lines, english = _load(repo)
    rule, _ = rhb.held_back(lines, english, "description")
    assert rhb.apply_rulings(rule, "maintainer", "2026-09-23", "description") == 3  # 1 + 2 (two variants)
    by_id = {ln["id"]: ln for ln in lines}
    for id_ in (1, 2):
        for v in decisions.hand_written_variants(by_id[id_]):
            assert v["ruling"] == {"ruling": "reject", "by": "maintainer", "date": "2026-09-23",
                                   "note": rhb.NOTE_TRUNCATED}
    for id_ in (3, 4, 5, 6, 7, 8):
        assert not any(v.get("ruling") for v in decisions.variant_dicts(by_id[id_]))
    assert "cut short" in rhb.NOTE_TRUNCATED and "cut short" not in rhb.NOTE


def test_an_already_ruled_line_is_reported_not_rewritten(repo):
    lines, english = _load(repo)
    next(ln for ln in lines if ln["id"] == 1)["ruling"] = {"ruling": "accept", "by": "maintainer",
                                                           "date": "2026-09-14"}
    rule, ruled = rhb.held_back(lines, english, "description")
    assert _ids(rule) == [2] and _ids(ruled) == [1]


def test_main_takes_field_and_run_is_dry_by_default(repo, monkeypatch, capsys):
    monkeypatch.setattr(rhb, "data_root", lambda: repo / "data")
    shard = repo / "data" / "quest" / "quest-0000.jsonl"
    before = shard.read_bytes()
    assert rhb.main(["--date", "2026-09-23", "--field", "description"]) == 0
    out = capsys.readouterr().out
    assert "held-back description lines: 2" in out and "quest 1 description" in out and "dry run" in out
    assert shard.read_bytes() == before
    with pytest.raises(SystemExit):
        rhb.main(["--date", "2026-09-23", "--field", "title"])
    assert rhb.main(["--date", "2026-09-23", "--field", "objectives", "--apply"]) == 0
    assert shard.read_bytes() != before


# ---- the cutter reaches the two quest kinds with --held-back ---------------------------------------------------


def test_cut_held_back_selects_ruled_description_lines_only(repo, capsys):
    data = repo / "data"
    out = repo / "batch.jsonl"
    assert tb.cut(data, "quest_description", 10, out) == []  # hand-written text keeps them all out
    assert tb.cut(data, "quest_description", 10, out, held_back=True) == []  # nothing ruled yet
    rhb.run(data, "maintainer", "2026-09-23", examples=0, apply=True, field="description")
    rows = tb.cut(data, "quest_description", 10, out, held_back=True)
    assert sorted(t[0] for r in rows for t in r["targets"]) == [1, 2]
    assert rows[0]["en"] == MODEL_EN
    assert "held back" in capsys.readouterr().out
    assert tb.cut(data, "quest_description", 10, out) == []  # without the flag: unchanged


def test_cut_held_back_skips_a_line_with_one_unruled_hand_written_variant(repo):
    data = repo / "data"
    rhb.run(data, "maintainer", "2026-09-23", examples=0, apply=True, field="description")
    lines = Store(data).load("quest")
    next(ln for ln in lines if ln["id"] == 2)["conflicts"][0].pop("ruling")
    Store(data).save("quest", lines)
    rows = tb.cut(data, "quest_description", 10, repo / "batch.jsonl", held_back=True)
    assert sorted(t[0] for r in rows for t in r["targets"]) == [1]


def test_cut_held_back_objectives(repo):
    data = repo / "data"
    rhb.run(data, "maintainer", "2026-09-23", examples=0, apply=True, field="objectives")
    rows = tb.cut(data, "quest_objectives", 10, repo / "batch.jsonl", held_back=True)
    assert [t for r in rows for t in r["targets"]] == [[5, "objectives"]]


def test_cut_held_back_reaches_a_ruled_quest_title(repo):
    """A title line whose hand-written variants are all ruled `reject` is redrafted whole; one
    unruled hand-written variant still keeps it out."""
    data = repo / "data"
    lines = Store(data).load("quest")
    title = next(ln for ln in lines if ln["id"] == 7)
    title["ruling"] = {"ruling": "reject", "by": "maintainer", "date": "2026-09-23"}
    Store(data).save("quest", lines)
    rows = tb.cut(data, "quest_title", 10, repo / "batch.jsonl", held_back=True)
    assert [t for r in rows for t in r["targets"]] == [[7, "title"]]
    title.pop("ruling")
    Store(data).save("quest", lines)
    assert tb.cut(data, "quest_title", 10, repo / "batch.jsonl", held_back=True) == []
