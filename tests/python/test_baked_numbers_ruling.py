"""An item or spell tooltip whose Japanese has a number baked into it is refused by the runtime gate, so the
model redrafts it with `$N` / `$D` placeholders.

An item tooltip's English is a template the client fills. The predecessor corpus wrote the numbers it
happened to see straight into the Japanese, so the line is right for one item and wrong for the next, and
`Align.check` then shows the live English (ADR-007). In game, every food, drink and hearthstone tooltip was
English on a fully translated client. No re-import can fix it; the English never
changed.

`wfj.dev.rule_baked_numbers` records the decision the ADR-012 way, and `translate_batch cut --held-back`
then reaches the tooltip kinds as it already reached quest completion text.
"""

import json

import pytest

from wfj.core import decisions
from wfj.dev import rule_baked_numbers as rbn
from wfj.dev import translate_batch as tb
from wfj.io.jsonl_store import Store

HUMAN = {"class": "human", "translator": "Tammy", "source": "cqjt@3446c82", "imported": "2026-09-13"}
MACHINE = {"class": "machine", "model": "m", "source": "draft-x-sg5@2026-09-18", "imported": "2026-09-18"}
EATING = "Restores $o1 health over $d.  Must remain seated while eating."


def _ja(id_, ja, prov=HUMAN, field="description"):
    return {"id": id_, "field": field, "ja": ja, "status": "unaligned", "checks": [],
            "provenance": dict(prov), "english": None, "reasons": [], "conflicts": []}


def _en(id_, en, field="description"):
    return {"id": id_, "field": field, "en": en, "hash": "0" * 16, "src": "db2@1.60.1.69913"}


@pytest.fixture
def repo(tmp_path):
    (tmp_path / "data").mkdir()
    (tmp_path / "data" / "SCHEMA").write_text("1\n")
    (tmp_path / "docs" / "content").mkdir(parents=True)
    (tmp_path / "docs" / "content" / "translation-style-guide.md").write_text("# guide\n\nversion: sg5\n")
    data = tmp_path / "data"
    Store(data, english=True).save("item", [
        _en(117, EATING),                              # baked 18 / 61 → ruled
        _en(159, "Restores $o1 mana over $d."),        # baked → ruled
        _en(200, "Restores $s1 health."),              # already uses $N1 → left alone
        _en(300, "Teaches Frost Ward (Rank 5)."),      # the 5 IS in the English → left alone
        _en(400, "Restores $s1 health."),              # machine-written → not a ruling case
    ])
    Store(data).save("item", [
        _ja(117, "18秒間でhealthを61回復。"),
        _ja(159, "18秒間でmanaを151回復。"),
        _ja(200, "healthを$N1回復します。"),
        _ja(300, "Frost Ward（Rank 5）を習得します。"),
        _ja(400, "healthを70回復します。", MACHINE),
    ])
    return tmp_path


def test_only_a_number_the_english_cannot_produce_is_a_baked_line(repo):
    data = repo / "data"
    rule, ruled = rbn.select(Store(data).load("item"), Store(data, english=True).load("item"),
                             "description", None)
    assert sorted(ln["id"] for ln, _, _ in rule) == [117, 159] and ruled == []
    assert [missing for ln, _, missing in rule if ln["id"] == 117] == [["18", "61"]]


def test_a_placeholder_index_is_never_read_as_a_baked_number():
    """`$N1` and `$D1` carry an index, not a value the player sees."""
    assert rbn.baked("$D1かけてhealthを$N1回復します。", EATING) == []
    assert rbn.baked("$N10と$D2。", EATING) == []
    assert rbn.baked("18秒間でhealthを61回復。", EATING) == ["18", "61"]
    # a number the English does hold is fine
    assert rbn.baked("Frost Ward（Rank 5）を習得します。", "Teaches Frost Ward (Rank 5).") == []


def test_match_takes_one_set_at_a_time(repo):
    import re

    data = repo / "data"
    lines, english = Store(data).load("item"), Store(data, english=True).load("item")
    rule, _ = rbn.select(lines, english, "description", re.compile("while eating"))
    assert [ln["id"] for ln, _, _ in rule] == [117]


def test_the_ruling_lands_on_the_hand_written_variant_and_is_carried(repo):
    data = repo / "data"
    lines = Store(data).load("item")
    rule, _ = rbn.select(lines, Store(data, english=True).load("item"), "description", None)
    assert rbn.apply_rulings([ln for ln, _, _ in rule], "the maintainer", "2026-09-18") == 2
    by_id = {ln["id"]: ln for ln in lines}
    for id_ in (117, 159):
        v = decisions.hand_written_variants(by_id[id_])[0]
        assert v["ruling"]["ruling"] == "reject" and v["ruling"]["note"] == rbn.NOTE
    for id_ in (200, 300, 400):
        assert not any(v.get("ruling") for v in decisions.variant_dicts(by_id[id_]))
    carried = [id_ for id_, _, v in decisions.carried(lines) if (v.get("ruling") or {}).get("ruling")]
    assert sorted(carried) == [117, 159]


def test_run_writes_nothing_without_apply(repo, capsys, monkeypatch):
    monkeypatch.setattr(rbn, "data_root", lambda: repo / "data")
    before = (repo / "data" / "item" / "item-0000.jsonl").read_bytes()
    assert rbn.main(["--date", "2026-09-18"]) == 0
    assert (repo / "data" / "item" / "item-0000.jsonl").read_bytes() == before
    out = capsys.readouterr().out
    assert "2 line(s) with a baked number" in out and "dry run" in out
    assert rbn.main(["--date", "2026-09-18", "--apply", "--examples", "0"]) == 0
    assert (repo / "data" / "item" / "item-0000.jsonl").read_bytes() != before


def test_the_ruling_date_is_required(repo, monkeypatch, capsys):
    monkeypatch.setattr(rbn, "data_root", lambda: repo / "data")
    with pytest.raises(SystemExit):
        rbn.main([])
    assert "--date" in capsys.readouterr().err


def test_a_ruled_tooltip_line_becomes_selectable_for_a_redraft(repo):
    """The point of the ruling: `cut --held-back` reaches it, and without the ruling it does not."""
    data = repo / "data"
    out = repo / "b.jsonl"
    assert tb.cut(data, "item_description", 10, out, held_back=True) == []
    lines = Store(data).load("item")
    rule, _ = rbn.select(lines, Store(data, english=True).load("item"), "description", None)
    rbn.apply_rulings([ln for ln, _, _ in rule], "the maintainer", "2026-09-18")
    Store(data).save("item", lines)
    rows = tb.cut(data, "item_description", 10, out, held_back=True)
    assert sorted(t[0] for r in rows for t in r["targets"]) == [117, 159]
    assert [r["slots"] for r in rows] == [2, 2]


def test_a_line_no_batch_can_redraft_is_never_ruled(tmp_path):
    """A ruling withdraws the hand-written Japanese, so it is taken only where a redraft can replace it:
    Forever-sourced English whose slots count. Otherwise the line is left with nothing."""
    data = tmp_path / "data"
    data.mkdir()
    (data / "SCHEMA").write_text("1\n")
    vanilla = dict(_en(10, "Restores $o1 mana over $d."), src="wago@1.15.9.69722")
    Store(data, english=True).save("item", [
        vanilla,
        _en(11, "$@spelldesc1133 Restores $o1 health."),  # uncountable: no batch is cut for it
        _en(12, "Restores $o1 health over $d."),
    ])
    Store(data).save("item", [_ja(10, "18秒間でmanaを151回復。"), _ja(11, "healthを61回復。"),
                              _ja(12, "18秒間でhealthを61回復。")])
    rule, _ = rbn.select(Store(data).load("item"), Store(data, english=True).load("item"), "description", None)
    assert [ln["id"] for ln, _, _ in rule] == [12]


def test_durations_mode_selects_a_named_unit_and_logs_its_own_note(tmp_path):
    """`$N2秒間` for a `$d` passes the gate (the number matches) and is wrong the moment the client renders
    minutes, so duration units are never assumed."""
    data = tmp_path / "data"
    data.mkdir()
    (data / "SCHEMA").write_text("1\n")
    Store(data, english=True).save("spell", [
        _en(99, "Decreases attack power by $s1.  Lasts $d."),
        _en(98, "Decreases attack power by $s1.  Lasts $d."),
    ])
    lines = [_ja(99, "攻撃力を$N1下げます。$N2秒間持続します。"), _ja(98, "攻撃力を$N1下げます。$D1持続します。")]
    rule, _ = rbn.select(lines, Store(data, english=True).load("spell"), "description", None, durations=True)
    assert [(ln["id"], missing) for ln, _, missing in rule] == [(99, ["duration_as_value:N2", "duration_missing:D1"])]
    rbn.apply_rulings([ln for ln, _, _ in rule], "the maintainer", "2026-09-18", rbn.NOTE_DURATION)
    assert "never assumed" in lines[0]["ruling"]["note"]


def test_a_book_title_is_a_name_and_never_ruled():
    """`The Path of the Protector` is an item description that is a book's title. Names stay in English, so
    nothing redrafts it and a ruling would only withdraw the hand-written line."""
    assert rbn.is_title("The Path of the Protector")
    assert rbn.is_title("A Tale of a Female Troll and Her Tiger")
    assert not rbn.is_title("Restores $o1 health over $d.")
    assert not rbn.is_title("Increases your Stamina by 5")  # "your" is a lower-case word of four letters


def test_the_current_corpus_has_nothing_left_to_rule():
    """Every line the rulings could take has been taken and redrafted: a whole-corpus dry run rules nothing."""
    from pathlib import Path

    data = Path(__file__).resolve().parents[2] / "data"
    for type_ in rbn.TYPES:
        for field in ("description", "aura"):
            for durations in (False, True):
                rule, _ = rbn.select(Store(data).load(type_), Store(data, english=True).load(type_), field, None,
                                     durations=durations)
                assert rule == [], (type_, field, durations, [ln["id"] for ln, _, _ in rule][:10])


def test_a_redraft_of_a_ruled_line_carries_accept():
    """`validate --base` in CI: a reject ruling alone lets a draft replace only text that shipped
    nothing; replacing a SHIPPING hand-written line needs `ruling: accept` on the machine line too."""
    note = {"ruling": "reject", "by": "the maintainer", "date": "2026-09-18", "note": rbn.NOTE}
    ruled = dict(_ja(117, "$D1かけてhealthを$N1回復します。", MACHINE),
                 conflicts=[{"ja": "18秒間でhealthを61回復。", "provenance": dict(HUMAN), "ruling": dict(note)}])
    unruled = dict(_ja(118, "healthを$N1回復します。", MACHINE),
                   conflicts=[{"ja": "healthを61回復。", "provenance": dict(HUMAN)}])
    plain = _ja(119, "healthを$N1回復します。", MACHINE)
    assert rbn.accept_redrafts([ruled, unruled, plain], "the maintainer", "2026-09-18") == 1
    assert ruled["ruling"]["ruling"] == "accept" and ruled["ruling"]["note"] == rbn.NOTE_ACCEPT
    assert "ruling" not in unruled and "ruling" not in plain
    from wfj.core.model import validate_line

    assert validate_line("item", ruled) == []


def test_the_data_carries_the_writer_notes_exactly(root):
    # accept_redrafts recognises a ruled hand-written variant by its note, so the notes in data/ must equal the
    # writer's constants: a reworded constant would otherwise stop matching the lines it wrote, silently.
    seen = set()
    for kind in ("item", "spell"):
        for path in sorted((root / "data" / kind).glob("*.jsonl")):
            for raw in path.read_text(encoding="utf-8").splitlines():
                for variant in json.loads(raw).get("conflicts") or []:
                    if variant["provenance"]["class"] == "human":
                        seen.add((variant.get("ruling") or {}).get("note"))
    assert rbn.NOTE in seen
    assert rbn.NOTE_DURATION in seen
