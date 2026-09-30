"""The stat-word redraft only swaps stat words, only on shipped machine lines, and groups rows by model."""

import pytest

from wfj.dev import draft_stat_words as dsw


def _line(ja, cls="machine", status="unaligned", model="model-a", id_=1, field="description"):
    prov = {"class": cls, "source": "draft-x-sg5@2026-09-18"}
    if cls == "machine":
        prov["model"] = model
    return {"id": id_, "field": field, "ja": ja, "status": status, "provenance": prov}


def test_selects_only_shipped_machine_lines_with_a_stat_word():
    assert dsw.selected(_line("healthを$N1回復します。"))
    assert not dsw.selected(_line("体力を$N1回復します。"))
    assert not dsw.selected(_line("healthを$N1回復します。", cls="human"))
    assert not dsw.selected(_line("healthを$N1回復します。", cls="correction"))
    assert not dsw.selected(_line("healthを$N1回復します。", status="rejected"))


def test_unswap_accepts_only_stat_word_swaps():
    old = "$D1かけてhealthを$N1、Manaを$N2回復します。"
    assert dsw.unswap(old, "$D1かけて体力を$N1、マナを$N2回復します。")
    assert not dsw.unswap(old, "$D1かけて体力を$N1、マナを$N3回復します。")  # a value changed too
    assert not dsw.unswap(old, "$D1かけてマナを$N1、マナを$N2回復します。")  # the wrong word
    assert not dsw.unswap(old, old + "。")


def test_draft_groups_rows_by_model_and_type(tmp_path, monkeypatch):
    lines = {
        "item": [_line("healthを$N1回復します。", id_=1), _line("体力を回復。", id_=2)],
        "spell": [_line("Staminaが$N1増加します。", id_=3, model="model-b"),
                  _line("manaを$N1回復します。", id_=4, field="aura")],
    }

    class FakeStore:
        def __init__(self, *_a, **_k):
            pass

        def load(self, type_):
            return lines[type_]

    monkeypatch.setattr(dsw, "Store", FakeStore)
    rows, seen = dsw.draft(tmp_path, {"model-a": "a", "model-b": "b"}, skip={("spell", 4, "aura")})
    assert rows == {
        ("a", "item"): [{"id": 1, "field": "description", "ja": "体力を$N1回復します。"}],
        ("b", "spell"): [{"id": 3, "field": "description", "ja": "スタミナが$N1増加します。"}],
    }
    assert sum(seen.values()) == 2


def test_move_accepts_moves_the_accept_onto_the_redraft_of_the_same_text():
    accept = {"ruling": "accept", "by": "maintainer", "date": "2026-09-18", "note": "redraft"}
    redraft = {"ja": "体力を$N1回復します。",
               "provenance": {"class": "machine", "model": "model-a",
                              "source": "draft-stat-words-a-sg12@2026-09-30", "imported": "2026-09-30"}}
    other = {"ja": "体力を$N2回復します。",
             "provenance": {"class": "machine", "model": "model-a",
                            "source": "draft-stat-words-a-sg12@2026-09-30", "imported": "2026-09-30"}}
    line = dict(_line("healthを$N1回復します。"), ruling=dict(accept), conflicts=[other, redraft])
    unruled = dict(_line("healthを$N1回復します。"), conflicts=[dict(redraft)])
    assert dsw.move_accepts([line, unruled], "2026-09-30") == 1
    assert "ruling" not in line
    assert redraft["ruling"]["ruling"] == "accept" and "ruling" not in other
    # who ruled, when and why survive the move
    assert redraft["ruling"]["by"] == "maintainer" and redraft["ruling"]["date"] == "2026-09-18"
    assert redraft["ruling"]["note"].startswith("redraft (moved on 2026-09-30 to this line's stat-word swap")
    assert "ruling" not in unruled["conflicts"][0]


def test_a_model_without_a_tag_fails_the_run(tmp_path, monkeypatch):
    class FakeStore:
        def __init__(self, *_a, **_k):
            pass

        def load(self, type_):
            return [_line("healthを$N1回復します。", model="model-c")] if type_ == "item" else []

    monkeypatch.setattr(dsw, "Store", FakeStore)
    with pytest.raises(ValueError, match="model-c"):
        dsw.draft(tmp_path, {"model-a": "a"}, skip=set())


def test_contexts_are_only_the_swapped_words():
    assert dsw.contexts("Mana ShieldとHealthstone、manaを回復") == ["Healthstone、manaを回復"]
