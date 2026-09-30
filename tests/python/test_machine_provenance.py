"""Machine-drafted text is traceable, hand-written text wins, drafts survive `make data`, and
`validate --base` protects hand-written lines. ADR-014."""

import argparse
import subprocess
from pathlib import Path

import pytest
from test_corrections import CORRECTION, _repos

from wfj.cmd import import_predecessor as imp
from wfj.cmd import validate
from wfj.core.model import english_line, validate_line
from wfj.core.status import Scope, decide
from wfj.io.jsonl_store import Store

MACHINE = {
    "class": "machine",
    "model": "draft-model-1",
    "critic": "critic-model-1",
    "source": "draft-quest@2026-09-14",
    "imported": "2026-09-14",
}
HUMAN = {"class": "human", "translator": "Tammy", "source": "cqjt@3446c82", "imported": "2026-09-13"}
ACCEPT = {"ruling": "accept", "by": "maintainer", "date": "2026-09-14"}


def _line(ja, prov, conflicts=(), field="title", id_=2):
    return {
        "id": id_,
        "field": field,
        "ja": ja,
        "status": "pending",
        "checks": [],
        "provenance": dict(prov),
        "english": None,
        "reasons": [],
        "conflicts": list(conflicts),
    }


# ---- the machine provenance shape ----------------------------------------------------------------------------


def test_machine_provenance_needs_a_model():
    assert validate_line("quest", _line("爪", MACHINE)) == []
    no_critic = {k: v for k, v in MACHINE.items() if k != "critic"}
    assert validate_line("quest", _line("爪", no_critic)) == []
    no_model = {k: v for k, v in MACHINE.items() if k != "model"}
    assert any("needs model" in p for p in validate_line("quest", _line("爪", no_model)))
    blank_critic = dict(MACHINE, critic="")
    assert any("critic" in p for p in validate_line("quest", _line("爪", blank_critic)))
    inside = _line("爪", HUMAN, conflicts=[{"ja": "爪2", "provenance": no_model}])
    assert any("needs model" in p for p in validate_line("quest", inside))


# ---- hand-written wins; machine never displaces it without a ruling ------------------------------------

SCOPE = Scope(
    kind="quest",
    fields={"title": "Sharptalon's Claw", "description": "Bring the claw.\n\nIt is sharp."},
    hashes={"title": "d311f9a5c36057a2", "description": "0d8319c7aaaaaaaa"},
    raw={"title": "Sharptalon's Claw", "description": "Bring the claw.$B$BIt is sharp."},
    src="pfquest@7786596",
)


def test_human_beats_machine_when_both_pass():
    line = _line("Sharptalonの鉤爪", MACHINE, conflicts=[{"ja": "Sharptalonの爪", "provenance": HUMAN}])
    d = decide(line, SCOPE, set(), "d311f9a5c36057a2")
    assert (d.status, d.winner) == ("trusted", 1)


def test_correction_beats_machine():
    line = _line("Sharptalonの鉤爪", MACHINE, conflicts=[{"ja": "Sharptalonの爪", "provenance": CORRECTION}])
    assert decide(line, SCOPE, set(), "d311f9a5c36057a2").winner == 1


def test_machine_does_not_replace_a_failing_human_without_a_ruling():
    # the human variant fails alignment (a name the English does not have); the machine draft passes
    line = _line("Thistle boreの鉤爪", HUMAN, conflicts=[{"ja": "Sharptalonの鉤爪", "provenance": MACHINE}])
    d = decide(line, SCOPE, set(), "d311f9a5c36057a2")
    assert d.status == "rejected"
    assert d.winner == 0
    assert d.reasons == ["alignment_failed:Thistle", "alignment_failed:bore"]  # the human's own reasons


def test_an_accept_ruling_lets_the_machine_variant_win():
    ruled = {"ja": "Sharptalonの鉤爪", "provenance": MACHINE, "ruling": ACCEPT}
    line = _line("Thistle boreの鉤爪", HUMAN, conflicts=[ruled])
    d = decide(line, SCOPE, set(), "d311f9a5c36057a2")
    assert (d.status, d.winner) == ("trusted", 1)


def test_machine_alone_ships_by_the_rules():
    d = decide(_line("Sharptalonの鉤爪", MACHINE), SCOPE, set(), "d311f9a5c36057a2")
    assert d.status == "trusted"


def test_a_newer_machine_variant_ranks_with_other_machine_text_by_the_rules():
    other = dict(MACHINE, source="draft-quest@2026-10-01")
    line = _line("Sharptalonの鉤爪", MACHINE, conflicts=[{"ja": "Thistle boreの鉤爪", "provenance": other}])
    assert decide(line, SCOPE, set(), "d311f9a5c36057a2").winner == 0  # the only passing variant


# Between two passing machine drafts the newer style guide version wins, then the newer import.
SG2 = dict(MACHINE, source="draft-progress-sg2@2026-09-15", imported="2026-09-15")
SG3 = dict(MACHINE, source="draft-progress-sg3@2026-09-15", imported="2026-09-15")


def test_the_newer_style_version_wins_between_two_passing_machine_drafts():
    line = _line("Sharptalonの爪", SG2, conflicts=[{"ja": "Sharptalonの鉤爪", "provenance": SG3}])
    d = decide(line, SCOPE, set(), "d311f9a5c36057a2")
    assert (d.status, d.winner) == ("trusted", 1) and "tiebreak" in d.checks


def test_the_style_version_ranks_before_the_import_date():
    older_sg3 = dict(SG3, source="draft-progress-sg3@2026-09-14", imported="2026-09-14")
    newer_sg2 = dict(SG2, source="draft-progress-sg2@2026-09-16", imported="2026-09-16")
    line = _line("Sharptalonの爪", newer_sg2, conflicts=[{"ja": "Sharptalonの鉤爪", "provenance": older_sg3}])
    assert decide(line, SCOPE, set(), "d311f9a5c36057a2").winner == 1


def test_a_source_without_a_style_version_counts_as_zero():
    unnamed = dict(MACHINE, source="draft-quest@2026-09-16", imported="2026-09-16")
    line = _line("Sharptalonの爪", unnamed, conflicts=[{"ja": "Sharptalonの鉤爪", "provenance": SG2}])
    assert decide(line, SCOPE, set(), "d311f9a5c36057a2").winner == 1
    same = _line("Sharptalonの爪", unnamed, conflicts=[{"ja": "Sharptalonの鉤爪", "provenance": dict(
        MACHINE, source="draft-quest@2026-09-14", imported="2026-09-14")}])
    assert decide(same, SCOPE, set(), "d311f9a5c36057a2").winner == 0  # both 0: the newer import wins


def test_hand_written_text_still_beats_the_newest_style_version():
    line = _line("Sharptalonの鉤爪", SG3, conflicts=[{"ja": "Sharptalonの爪", "provenance": HUMAN}])
    assert decide(line, SCOPE, set(), "d311f9a5c36057a2").winner == 1
    fixed = _line("Sharptalonの鉤爪", SG3, conflicts=[{"ja": "Sharptalonの爪", "provenance": CORRECTION}])
    assert decide(fixed, SCOPE, set(), "d311f9a5c36057a2").winner == 1


# ---- machine drafts survive the predecessor rebuild ----------------------------------------------------


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
        date="2026-09-13",
        relabel_translator=None,
        questjapanizer=None,  # one-pass lineage args (the parser defaults)
        qjp_version=None,
        craftjapanizer_quest=None,
        cjq_version=None,
    )
    return data, ns


def _by(data: Path) -> dict:
    return {(ln["id"], ln["field"]): ln for ln in Store(data).load("quest")}


def test_machine_drafts_are_carried_and_the_rebuild_is_byte_stable(bench, capsys):
    data, ns = bench
    assert imp.run_predecessor(ns) == 0
    by = _by(data)
    by[(2, "title")]["conflicts"].append({"ja": "機械の題", "provenance": dict(MACHINE)})
    by[(2, "objectives")]["conflicts"].append({"ja": by[(2, "objectives")]["ja"], "provenance": dict(MACHINE)})
    by[(90003, "title")] = _line("機械だけの題", MACHINE, id_=90003)
    Store(data).save("quest", by.values())
    capsys.readouterr()

    assert imp.run_predecessor(ns) == 0
    out = capsys.readouterr().out
    after = _by(data)
    kept = [c for c in after[(2, "title")]["conflicts"] if c["ja"] == "機械の題"]
    assert kept and kept[0]["provenance"] == MACHINE
    assert after[(90003, "title")]["provenance"] == MACHINE  # an id the inputs never produce keeps the draft
    # a draft identical to the rebuilt imported text adds nothing: counted redundant, not duplicated
    assert not [c for c in after[(2, "objectives")]["conflicts"] if c["provenance"] == MACHINE]
    assert "carried machine drafts (kept / redundant): quest 2/1" in out

    snapshot = {p: p.read_bytes() for p in (data / "quest").glob("*.jsonl")}
    assert imp.run_predecessor(ns) == 0
    assert {p: p.read_bytes() for p in (data / "quest").glob("*.jsonl")} == snapshot


def test_an_import_identical_to_a_machine_draft_stays_its_own_variant():
    col = imp.Collector()
    col.seed([_line("機械の題", MACHINE)])
    col.add(2, "title", "機械の題", HUMAN, "cqjt@3446c82#1")
    line = col.lines[(2, "title")]
    assert line["provenance"] == MACHINE  # no origin appended to the model's variant
    assert [c["provenance"]["class"] for c in line["conflicts"]] == ["human"]


# ---- validate --base protects every hand-written line --------------------------------------------------


def _commit(repo: Path, msg: str) -> None:
    subprocess.run(["git", "add", "-A"], cwd=repo, check=True)
    subprocess.run(
        ["git", "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", msg], cwd=repo, check=True
    )


def _write(repo: Path, lines) -> None:
    data = repo / "data"
    data.mkdir(exist_ok=True)
    (data / "SCHEMA").write_text("1\n", encoding="utf-8")
    Store(data).save("quest", lines, allow_empty=True)
    en = english_line(1, "title", "X", "d311f9a5c36057a2", "pfquest@7786596")
    Store(data, english=True).save("quest", [en], allow_empty=True)


def test_validate_flags_human_or_correction_turned_machine(tmp_path):
    repo = tmp_path / "repo"
    repo.mkdir()
    subprocess.run(["git", "init", "-q", "-b", "main"], cwd=repo, check=True)
    _write(repo, [_line("人", HUMAN, id_=1), _line("訂", CORRECTION, id_=2), _line("機", MACHINE, id_=3)])
    _commit(repo, "base")
    _write(repo, [_line("機", MACHINE, id_=1), _line("機", MACHINE, id_=2), _line("訂", CORRECTION, id_=3)])
    problems = validate.rule_provenance(repo / "data", Store(repo / "data"), "HEAD")
    assert problems == [
        "provenance: quest 1/title was human at HEAD, now machine",
        "provenance: quest 2/title was correction at HEAD, now machine",
    ]  # machine → correction (id 3) is the hand-written replacement path and passes


# ---- rulings and ties ----------------------------------------------------------------------------------------------


def test_a_rejected_human_variant_does_not_ship_and_does_not_bar_the_machine_draft():
    # a person ruled the human text out; the machine draft is the only candidate left
    rejected = {"ruling": "reject", "by": "maintainer", "date": "2026-09-15"}
    line = dict(_line("Sharptalonの爪", HUMAN, conflicts=[{"ja": "Sharptalonの鉤爪", "provenance": MACHINE}]),
                ruling=rejected)
    d = decide(line, SCOPE, set(), "d311f9a5c36057a2")
    assert (d.status, d.winner) == ("trusted", 1)
    # a reject ruling is permanent: a lone ruled variant never ships, even though it passes
    lone = dict(_line("Sharptalonの爪", HUMAN), ruling=rejected)
    d = decide(lone, SCOPE, set(), "d311f9a5c36057a2")
    assert (d.status, d.reasons, d.winner) == ("rejected", ["ruled_reject"], 0)


def test_the_newer_machine_draft_wins_a_tie_between_drafts():
    # a later batch under another name must not un-ship the line as a duplicate_conflict
    later = dict(MACHINE, source="draft-audit@2026-10-01", imported="2026-10-01")
    line = _line("Sharptalonの鉤爪", MACHINE, conflicts=[{"ja": "Sharptalonの爪", "provenance": later}])
    d = decide(line, SCOPE, set(), "d311f9a5c36057a2")
    assert (d.status, d.winner) == ("trusted", 1)


def test_validate_accepts_a_machine_line_that_won_by_an_accept_ruling(tmp_path):
    # an explicit, logged accept ruling lets machine text replace a human line, so CI must not fail it
    repo = tmp_path / "repo"
    repo.mkdir()
    subprocess.run(["git", "init", "-q", "-b", "main"], cwd=repo, check=True)
    _write(repo, [_line("人", HUMAN, id_=1)])
    _commit(repo, "base")
    accepted = dict(_line("機", MACHINE, id_=1), ruling={"ruling": "accept", "by": "maintainer", "date": "2026-09-15"})
    _write(repo, [accepted])
    assert validate.rule_provenance(repo / "data", Store(repo / "data"), "HEAD") == []
