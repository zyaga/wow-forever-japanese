"""Quest `completion` lines whose hand-written variants are all rejected ship nothing, so the model translates
the whole line and replaces that text.

`wfj.dev.rule_held_back` records the decision the ADR-012 way: `ruling: reject` on every hand-written
variant. `translate_batch cut --held-back` then selects those lines, the provenance guard stops barring the
machine draft (ADR-014 §3), and `validate --base` accepts the resulting hand-written → machine change
(ADR-014 §5). A shipping hand-written line is never selected, never ruled, and still protected.
"""

import subprocess
from pathlib import Path

import pytest

from wfj.cmd import validate
from wfj.core import decisions
from wfj.core.model import english_line
from wfj.core.status import Scope, decide
from wfj.dev import rule_held_back as rhb
from wfj.dev import translate_batch as tb
from wfj.io.jsonl_store import Store

HUMAN = {"class": "human", "translator": "Tammy", "source": "cqjt@3446c82", "imported": "2026-09-13"}
HUMAN2 = {"class": "human", "translator": "Az", "source": "qjp@0.5.8", "imported": "2026-09-13"}
CORRECTION = {"class": "correction", "translator": "Az", "source": "correction@2026-09-14",
              "imported": "2026-09-14", "corrects": "qjp@0.5.8"}
MACHINE = {"class": "machine", "model": "model-a", "source": "draft-completion-sg3@2026-09-15",
           "imported": "2026-09-15"}
REJECT = {"ruling": "reject", "by": "maintainer", "date": "2026-09-15"}
EN = "Well done, $N! You have earned this.$B$BTake it and go."
MODEL_EN = "Well done, {name}! You have earned this.\n\nTake it and go."


def _ja(id_, field, status, prov, conflicts=(), reasons=("truncated:1/2",), **kw):
    return {"id": id_, "field": field, "ja": "よくやった、{name}!", "status": status, "checks": [],
            "provenance": dict(prov), "english": None, "reasons": list(reasons),
            "conflicts": [dict(c) for c in conflicts], **kw}


def _en(id_, field, en=EN):
    return {"id": id_, "field": field, "en": en, "hash": "0" * 16, "src": "vmangos@13b49dc"}


@pytest.fixture
def repo(tmp_path: Path) -> Path:
    """A store covering every case the ruling has to tell apart."""
    (tmp_path / "data").mkdir()
    (tmp_path / "data" / "SCHEMA").write_text("1\n")
    (tmp_path / "docs" / "content").mkdir(parents=True)
    (tmp_path / "docs" / "content" / "translation-style-guide.md").write_text("# guide\n\nversion: sg3\n")
    data = tmp_path / "data"
    Store(data, english=True).save("quest", [
        _en(1, "completion"),   # rejected human, English present → held back
        _en(2, "completion"),   # rejected human + a second human variant → both ruled
        _en(3, "completion"),   # trusted human → never touched
        _en(4, "completion"),   # stale human → never touched
        _en(5, "completion"),   # rejected, correction variant → ruled (a correction is hand-written)
        _en(6, "completion"),   # rejected, machine only (no hand-written) → not a ruling case
        _en(7, "progress"),     # another field → out of scope
        _en(8, "description"),  # another field → out of scope
    ])                          # quest 9 below has no English → out of scope
    Store(data).save("quest", [
        _ja(1, "completion", "rejected", HUMAN),
        _ja(2, "completion", "rejected", HUMAN, [{"ja": "別訳", "provenance": HUMAN2}],
            reasons=("duplicate_conflict",)),
        _ja(3, "completion", "trusted", HUMAN, reasons=()),
        _ja(4, "completion", "stale", HUMAN, reasons=()),
        _ja(5, "completion", "rejected", CORRECTION),
        _ja(6, "completion", "rejected", MACHINE),
        _ja(7, "progress", "rejected", HUMAN),
        _ja(8, "description", "rejected", HUMAN),
        _ja(9, "completion", "rejected", HUMAN),
    ])
    return tmp_path


def _ids(lines):
    return sorted(ln["id"] for ln in lines)


# ---- the ruling selects only the held-back completion lines --------------------------------------------------


def test_only_non_shipping_completion_lines_with_hand_written_text_are_ruled(repo):
    data = repo / "data"
    rule, ruled = rhb.held_back(Store(data).load("quest"), Store(data, english=True).load("quest"))
    # 3 / 4 ship (never touched), 6 has no hand-written variant, 7 / 8 are other fields, 9 has no English
    assert _ids(rule) == [1, 2, 5] and ruled == []


def test_the_ruling_lands_on_every_hand_written_variant_and_nothing_else(repo):
    data = repo / "data"
    lines = Store(data).load("quest")
    rule, _ = rhb.held_back(lines, Store(data, english=True).load("quest"))
    assert rhb.apply_rulings(rule, "maintainer", "2026-09-15") == 4  # 1 + 2 (two variants) + 5
    by_id = {ln["id"]: ln for ln in lines}
    for id_ in (1, 2, 5):
        for v in decisions.hand_written_variants(by_id[id_]):
            assert v["ruling"] == {"ruling": "reject", "by": "maintainer", "date": "2026-09-15",
                                   "note": rhb.NOTE}
    for id_ in (3, 4, 6, 7, 8, 9):  # shipping, machine-only, other fields, no English
        assert not any(v.get("ruling") for v in decisions.variant_dicts(by_id[id_]))


def test_a_line_whose_hand_written_text_already_carries_a_ruling_is_left_alone(repo):
    data = repo / "data"
    lines = Store(data).load("quest")
    next(ln for ln in lines if ln["id"] == 1)["ruling"] = {"ruling": "accept", "by": "maintainer",
                                                           "date": "2026-09-14"}
    rule, ruled = rhb.held_back(lines, Store(data, english=True).load("quest"))
    assert _ids(rule) == [2, 5] and _ids(ruled) == [1]


def test_run_writes_nothing_without_apply(repo, capsys):
    before = (repo / "data" / "quest" / "quest-0000.jsonl").read_bytes()
    rhb.run(repo / "data", "maintainer", "2026-09-15", examples=1, apply=False)
    assert (repo / "data" / "quest" / "quest-0000.jsonl").read_bytes() == before
    out = capsys.readouterr().out
    assert "held-back completion lines: 3" in out and "dry run" in out
    rhb.run(repo / "data", "maintainer", "2026-09-15", examples=0, apply=True)
    assert (repo / "data" / "quest" / "quest-0000.jsonl").read_bytes() != before


def test_the_ruling_date_is_required_and_must_be_a_date(repo, monkeypatch, capsys):
    # a ruling is dated by the decision it records; no default can stamp an old date on a new set of lines
    monkeypatch.setattr(rhb, "data_root", lambda: repo / "data")
    with pytest.raises(SystemExit):
        rhb.main([])
    assert "--date" in capsys.readouterr().err
    with pytest.raises(SystemExit):
        rhb.main(["--date", "15/09/2026"])
    assert rhb.main(["--date", "2026-09-16"]) == 0  # dry run


def test_the_rulings_are_carried_across_a_rebuild(repo):
    """`make data` rebuilds imported text from the pinned inputs; a ruled variant is carried instead
    (ADR-012 §1). `Collector.carry` putting them back is covered by
    `test_corrections.test_corrections_and_rulings_survive_the_rebuild`; here: every ruling reaches the
    carry set, on the hand-written variant it was written on."""
    data = repo / "data"
    lines = Store(data).load("quest")
    rule, _ = rhb.held_back(lines, Store(data, english=True).load("quest"))
    rhb.apply_rulings(rule, "maintainer", "2026-09-15")
    carried = [
        (id_, v) for id_, field, v in decisions.carried(lines)
        if (v.get("ruling") or {}).get("ruling") == "reject"
    ]
    assert sorted(id_ for id_, _ in carried) == [1, 2, 2, 5]
    assert all(decisions.is_hand_written(v["provenance"]) for _, v in carried)
    assert all(v["ruling"]["note"] == rhb.NOTE for _, v in carried)


# ---- the cutter picks the ruled lines up, and only with --held-back -------------------------------------------


def _rule(repo: Path) -> None:
    rhb.run(repo / "data", "maintainer", "2026-09-15", examples=0, apply=True)


def test_held_back_selects_the_ruled_lines_and_the_default_cut_is_unchanged(repo, capsys):
    out = repo / "batch.jsonl"
    before = [r["targets"] for r in tb.cut(repo / "data", "completion", 10, out)]
    _rule(repo)
    assert [r["targets"] for r in tb.cut(repo / "data", "completion", 10, out)] == before == []
    rows = tb.cut(repo / "data", "completion", 10, out, held_back=True)
    # one row per distinct English; 1 / 2 / 5 share it, so they group together
    assert rows and sorted(t[0] for r in rows for t in r["targets"]) == [1, 2, 5]
    assert rows[0]["en"] == MODEL_EN
    assert "in scope (completion, sg3, held back): 3 lines · 1 unique" in capsys.readouterr().out


def test_an_unruled_hand_written_variant_still_keeps_the_line_out(repo):
    data = repo / "data"
    lines = Store(data).load("quest")
    rule, _ = rhb.held_back(lines, Store(data, english=True).load("quest"))
    rhb.apply_rulings(rule, "maintainer", "2026-09-15")
    # take the ruling back off the second human variant of quest 2: one unruled hand-written variant is enough
    next(ln for ln in lines if ln["id"] == 2)["conflicts"][0].pop("ruling")
    Store(data).save("quest", lines)
    rows = tb.cut(data, "completion", 10, repo / "batch.jsonl", held_back=True)
    assert sorted(t[0] for r in rows for t in r["targets"]) == [1, 5]


def test_held_back_reaches_only_the_kinds_a_ruling_covers(repo):
    """The rulings cover quest completion; the tooltip kinds, where the hand-written Japanese has a number
    baked into it and the runtime gate refuses it; quest description / objectives cut short; and quest titles
    found wrong on review. Nothing else may be redrafted over hand-written text."""
    for kind in ("progress", "gossip", "book", "objective"):
        with pytest.raises(SystemExit, match="only"):
            tb.cut(repo / "data", kind, 10, repo / "batch.jsonl", held_back=True)
    assert {"completion", "quest_title", "quest_description", "quest_objectives", "item_description",
                                  "spell_description", "spell_aura"} == tb.HELD_BACK_KINDS


# ---- the machine draft wins, and validate accepts the change --------------------------------------------------

SCOPE = Scope("quest", {"completion": "Well done!"}, {"completion": "Well done!"})


def test_the_machine_draft_wins_over_a_reject_ruled_hand_written_variant():
    line = {"id": 1, "field": "completion", "ja": "半分だけの訳", "status": "rejected", "checks": [],
            "provenance": dict(HUMAN), "english": None, "reasons": ["truncated:1/2"],
            "conflicts": [{"ja": "よくやった!", "provenance": dict(MACHINE)}], "ruling": dict(REJECT)}
    d = decide(line, SCOPE, set(), None)
    assert (d.status, d.winner) == ("trusted", 1)
    # without the ruling the hand-written text bars the draft (machine text never replaces a human translation
    # without a recorded ruling): it is not a candidate at all, so
    # the line falls back to the hand-written variant and whatever the rules make of it
    line.pop("ruling")
    assert decide(line, SCOPE, set(), None).winner == 0


def test_a_reject_ruling_is_permanent_even_when_the_ruled_text_later_passes():
    # quests 3106 / 5625: completion lines ruled `reject`, no draft imported. If new English, an allowlist entry or a rule
    # change makes the ruled text pass, it still must not ship; the ruling is what a person decided.
    passing = {"id": 1, "field": "completion", "ja": "よくやった!", "status": "rejected", "checks": [],
               "provenance": dict(HUMAN), "english": None, "reasons": ["truncated:1/2"], "conflicts": [],
               "ruling": dict(REJECT)}
    d = decide(passing, SCOPE, set(), None)
    assert (d.status, d.reasons, d.winner) == ("rejected", ["ruled_reject"], 0)
    # still failing: the line keeps its own reasons, as before the ruling
    failing = dict(passing, ja="Well done!")
    assert decide(failing, SCOPE, set(), None).reasons == ["not_japanese"]
    # two ruled hand-written variants and nothing else: neither ships
    both = dict(passing, conflicts=[{"ja": "見事だ!", "provenance": dict(HUMAN2), "ruling": dict(REJECT)}])
    assert decide(both, SCOPE, set(), None).status == "rejected"


def _git_repo(tmp_path: Path, lines) -> Path:
    repo = tmp_path / "gitrepo"
    repo.mkdir()
    subprocess.run(["git", "init", "-q", "-b", "main"], cwd=repo, check=True)
    _save(repo, lines)
    subprocess.run(["git", "add", "-A"], cwd=repo, check=True)
    subprocess.run(["git", "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "base"],
                   cwd=repo, check=True)
    return repo


def _save(repo: Path, lines) -> None:
    data = repo / "data"
    data.mkdir(exist_ok=True)
    (data / "SCHEMA").write_text("1\n", encoding="utf-8")
    Store(data).save("quest", lines, allow_empty=True)
    Store(data, english=True).save(
        "quest", [english_line(1, "completion", "Well done!", "0" * 16, "vmangos@13b49dc")], allow_empty=True
    )


def test_validate_accepts_the_change_when_every_hand_written_variant_is_ruled_reject(tmp_path):
    repo = _git_repo(tmp_path, [_ja(1, "completion", "rejected", HUMAN)])
    ruled = _ja(1, "completion", "trusted", MACHINE, reasons=(),
                conflicts=[{"ja": "半分だけの訳", "provenance": HUMAN, "ruling": dict(REJECT)}])
    _save(repo, [ruled])
    assert validate.rule_provenance(repo / "data", Store(repo / "data"), "HEAD") == []


def test_validate_refuses_reject_rulings_that_replace_a_shipping_hand_written_line(tmp_path):
    # the held-back ruling covers text that shipped nothing; a line that shipped hand-written text needs its own ruling
    repo = _git_repo(tmp_path, [_ja(1, "completion", "trusted", HUMAN, reasons=())])
    ruled = _ja(1, "completion", "trusted", MACHINE, reasons=(),
                conflicts=[{"ja": "よくやった、{name}!", "provenance": HUMAN, "ruling": dict(REJECT)}])
    _save(repo, [ruled])
    (problem,) = validate.rule_provenance(repo / "data", Store(repo / "data"), "HEAD")
    assert problem.startswith("provenance: quest 1/completion was human and shipped (trusted) at HEAD, now machine")
    assert "ruling: accept" in problem
    # the explicit new ruling: `accept` on the machine line
    _save(repo, [dict(ruled, ruling={"ruling": "accept", "by": "maintainer", "date": "2026-09-16"})])
    assert validate.rule_provenance(repo / "data", Store(repo / "data"), "HEAD") == []
    # a malformed (string) ruling is not an accept, and does not crash the check
    _save(repo, [dict(ruled, ruling="accept")])
    assert len(validate.rule_provenance(repo / "data", Store(repo / "data"), "HEAD")) == 1


def test_validate_still_refuses_the_change_when_a_hand_written_variant_is_unruled(tmp_path):
    repo = _git_repo(tmp_path, [_ja(1, "completion", "rejected", HUMAN)])
    # two hand-written variants, only one ruled: the provenance rule still protects the line
    unruled = _ja(1, "completion", "trusted", MACHINE, reasons=(), conflicts=[
        {"ja": "半分だけの訳", "provenance": HUMAN, "ruling": dict(REJECT)},
        {"ja": "別訳", "provenance": HUMAN2},
    ])
    _save(repo, [unruled])
    assert validate.rule_provenance(repo / "data", Store(repo / "data"), "HEAD") == [
        "provenance: quest 1/completion was human at HEAD, now machine"
    ]
