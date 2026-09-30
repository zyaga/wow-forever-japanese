"""`wfj report check|intake|apply` end to end on a small store: a fix report from the issue body to data/,
readings, ATTRIBUTION.md and the reply; every refusal of a decisions file; a second run changes nothing."""

import json
import shutil
from pathlib import Path

import pytest

from wfj.cmd import fix_report as cmd
from wfj.core import fix_report as F
from wfj.core.hashing import key
from wfj.core.normalize import normalize_v1
from wfj.core.readings import ja_hash
from wfj.dev.gen_attribution import with_correctors
from wfj.io.jsonl_store import Store

EN = "Look to the Stars"
WDB = "wdb@1.60.1.70009"
HUMAN = {"class": "human", "translator": "Tammy", "source": "cqjt@3446c82", "imported": "2026-09-13"}
MACHINE = {"class": "machine", "model": "drafter-1", "source": "draft-q-sg6@2026-09-18", "imported": "2026-09-18"}
SHIPPED = {175: ("星座を求めて", HUMAN), 176: ("星座を探せ", MACHINE), 177: ("星々を求め", HUMAN), 178: ("星を仰げ", MACHINE)}
DATE, MODEL = "2026-09-28", "model-test"
W = {
    "星を見よ": [["星", "ほし", "星", "ほし", "star"], ["見よ", "みよ", "見る", "みる", "look (at)"]],
    "星を探せ": [["星", "ほし", "星", "ほし", "stars"], ["探せ", "さがせ", "探す", "さがす", "look for"]],
    "星を求めよ": [["星", "ほし", "星", "ほし", "stars"], ["求めよ", "もとめよ", "求める", "もとめる", "seek"]],
}


def _h(en):
    return key(normalize_v1(en))


@pytest.fixture
def repo(tmp_path, root):
    data = tmp_path / "data"
    data.mkdir()
    (data / "SCHEMA").write_text("1\n")
    lines = [{"id": i, "field": "title", "ja": ja, "status": "trusted", "checks": [], "provenance": dict(p),
              "english": {"hash": _h(EN), "src": WDB}, "reasons": [], "conflicts": []} for i, (ja, p) in SHIPPED.items()]
    Store(data).save("quest", lines)
    Store(data, english=True).save("quest", [{"id": i, "field": "title", "en": EN, "hash": _h(EN), "src": WDB} for i in SHIPPED])
    (tmp_path / "pipeline").mkdir()
    (tmp_path / "pipeline" / "allowlist.txt").write_text("")
    (tmp_path / "docs" / "content").mkdir(parents=True)
    (tmp_path / "docs" / "content" / "translation-style-guide.md").write_text("version: sg9\n")
    shutil.copy(root / "ATTRIBUTION.md", tmp_path / "ATTRIBUTION.md")
    return data


def _fix(id_, reason, ja="", note=""):
    return F.Fix("quest", id_, "title", ja_hash(SHIPPED[id_][0]), reason, note=note, ja=ja)


def _body(fixes, credit="Kaori"):
    rep = F.Report(addon="1.0.0", client="1.60.1.70009", fixes=fixes)
    return (f"### Report\n\n```text\n{F.render(rep)}```\n\n### Credit me as\n\n{credit}\n\n"
            "### Permission\n\n- [X] Japanese I wrote in this report may ship\n")


FIXES = [
    _fix(175, "awkward", ja="星を見よ", note="stiff"),
    _fix(176, "wrong"),
    _fix(177, "typo"),
    _fix(178, "other"),
    F.Fix("quest", 175, "objectives", "0" * 16, "wrong"),  # no such line
]
DECISIONS = [
    {"type": "quest", "id": 175, "field": "title", "decision": "use", "ja": "星を見よ", "note": "Reads naturally.",
     "words": W["星を見よ"]},
    {"type": "quest", "id": 176, "field": "title", "decision": "rewrite", "ja": "星を探せ", "note": "Stars, not constellations.",
     "words": W["星を探せ"]},
    {"type": "quest", "id": 177, "field": "title", "decision": "rewrite", "ja": "星を求めよ", "note": "Imperative, like the English.",
     "words": W["星を求めよ"]},
    {"type": "quest", "id": 178, "field": "title", "decision": "keep", "note": "仰げ is the right register for a quest title."},
]


def _intake(repo, fixes=FIXES, credit="Kaori"):
    assert cmd.intake(repo, 12, _body(fixes, credit), "gh-user", None, False) == 0
    return repo.parent / "batches" / "reports" / "issue-12"


def _decide(folder, rows):
    (folder / "decisions.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows))


def _snapshot(repo):
    return {p: p.read_bytes() for p in sorted(repo.rglob("*.jsonl"))} | {"A": (repo.parent / "ATTRIBUTION.md").read_bytes()}


def _line(repo, id_):
    return next(ln for ln in Store(repo).load("quest") if ln["id"] == id_ and ln["field"] == "title")


def test_form_sections_and_credit():
    s = cmd.form_sections("### Report\n\nabc\n\n### Credit me as\n\n_No response_\n")
    assert s == {"Report": "abc", "Credit me as": ""}
    assert cmd.clean_credit(" A|b\nc ") == "Abc"


def test_credit_names_carry_no_markup(capsys):
    # the credit ships in ATTRIBUTION.md: letters of any script, digits, spaces and `._-` only
    assert cmd.clean_credit("[Official site](https://phish.example)") == "Official sitehttpsphish.example"
    assert cmd.clean_credit("<img src=x onerror=1>") == "img srcx onerror1"
    assert cmd.clean_credit("@maintainer") == "maintainer"
    assert cmd.clean_credit("かおり\u200b\u202eevil") == "かおりevil"  # zero-width and bidi controls go
    assert cmd.clean_credit("Kao_ri-2.0  x") == "Kao_ri-2.0 x"
    assert len(cmd.clean_credit("a" * 99)) == cmd.CREDIT_MAX


def test_the_check_comment_renders_nothing_a_player_wrote(repo):
    # header tokens are limited; every echoed value sits in a code span with no @ or backtick
    ok, text = cmd.summary(_body([_fix(175, "wrong")]).replace("addon 1.0.0", "addon ![x](https://e.example)"), repo)
    assert not ok and "expected `addon" not in text  # the refusal's own backticks are neutralised too
    error = text.split("could not be read:** ", 1)[1].split("\n", 1)[0]
    assert error.startswith("`") and error.endswith("`") and error.count("`") == 2  # one code span, no breakout
    body = _body([_fix(175, "wrong")]).replace("client 1.60.1.70009", "client @octocat")
    ok, text = cmd.summary(body, repo)
    assert ok and "@octocat" not in text and "`＠octocat`" in text
    bad = _body([_fix(175, "wrong")]).replace("wrong\nend", "wrong\nhello `@someone` [x](https://e)\nend")
    ok, text = cmd.summary(bad, repo)
    error = text.split("could not be read:** ", 1)[1].split("\n", 1)[0]
    assert not ok and "@" not in error and error.count("`") == 2 and "＠someone" in error


def test_check_exits_3_on_an_internal_error(repo, tmp_path, monkeypatch, capsys):
    body = tmp_path / "body.txt"
    body.write_text(_body([_fix(175, "wrong")]))
    monkeypatch.setattr(cmd, "data_root", lambda: repo)
    assert cmd.run(["check", "--body-file", str(body)]) == 0
    monkeypatch.setattr(cmd, "summary", lambda *a: (_ for _ in ()).throw(RuntimeError("boom")))
    assert cmd.run(["check", "--body-file", str(body)]) == cmd.EXIT_INTERNAL
    assert "internal error" in capsys.readouterr().err


def test_a_gh_failure_is_a_message_not_a_traceback(repo, monkeypatch, capsys):
    class Done:
        returncode, stdout, stderr = 1, "", "HTTP 401: Bad credentials"

    monkeypatch.setattr(cmd.subprocess, "run", lambda *a, **k: Done())
    monkeypatch.setattr(cmd, "data_root", lambda: repo)
    assert cmd.run(["intake", "--issue", "12"]) == 1
    assert "could not read issue #12: HTTP 401" in capsys.readouterr().out


def test_intake_writes_its_files_together_or_not_at_all(repo, monkeypatch):
    folder = repo.parent / "batches" / "reports" / "issue-12"
    real = Path.write_text

    def failing(self, *a, **k):
        if self.name == ".skipped.jsonl.tmp":
            raise OSError("disk full")
        return real(self, *a, **k)

    monkeypatch.setattr(Path, "write_text", failing)
    with pytest.raises(OSError):
        cmd.intake(repo, 12, _body(FIXES), "gh-user", None, False)
    assert not folder.exists() or not any(folder.iterdir())


def test_without_the_permission_box_the_players_japanese_never_ships(repo, capsys):
    # the author can untick the box by editing the issue; intake reads it again
    body = _body(FIXES).replace("- [X] Japanese", "- [ ] Japanese")
    assert cmd.intake(repo, 12, body, "gh-user", None, False) == 0
    assert "Permission box is NOT ticked" in capsys.readouterr().out
    folder = repo.parent / "batches" / "reports" / "issue-12"
    assert json.loads((folder / "meta.json").read_text())["consent"] is False
    _decide(folder, DECISIONS)
    assert cmd.apply(repo, 12, MODEL, DATE, "maintainer", False) == 1
    assert "Permission box is not ticked" in capsys.readouterr().out


def test_intake_again_after_apply_still_finds_the_lines_this_report_changed(repo):
    # after apply the lines ship this report's Japanese, not the hash the player saw
    folder = _intake(repo)
    _decide(folder, DECISIONS)
    assert cmd.apply(repo, 12, MODEL, DATE, "maintainer", False) == 0
    assert cmd.intake(repo, 12, _body(FIXES), "gh-user", None, True) == 0
    triage = [json.loads(x) for x in (folder / "triage.jsonl").read_text().splitlines()]
    assert [t["id"] for t in triage] == [175, 176, 177, 178]
    assert {t["id"]: t["ja"] for t in triage}[176] == "星を探せ"
    # a changed decision on a line this report already rewrote applies over its own correction
    rows = [dict(r) for r in DECISIONS]
    rows[2] = dict(rows[2], ja="星を探し求めよ", words=[["星", "ほし", "星", "ほし", "stars"],
                                                  ["探し求めよ", "さがしもとめよ", "探し求める", "さがしもとめる", "seek out"]])
    _decide(folder, rows)
    assert cmd.apply(repo, 12, MODEL, DATE, "maintainer", False) == 0
    line = _line(repo, 177)
    assert line["ja"] == "星を探し求めよ" and line["provenance"]["report"] == 12
    # the report's first correction is kept as a variant, ruled out (the store orders variants itself)
    first = [v for v in line["conflicts"] if v["ja"] == "星を求めよ"]
    assert first and first[0]["ruling"]["ruling"] == "reject"


def test_intake_triages_and_skips(repo):
    folder = _intake(repo)
    triage = [json.loads(x) for x in (folder / "triage.jsonl").read_text().splitlines()]
    skipped = [json.loads(x) for x in (folder / "skipped.jsonl").read_text().splitlines()]
    assert [t["id"] for t in triage] == [175, 176, 177, 178]
    t = triage[0]
    assert (t["en"], t["ja"], t["class"], t["suggestion"], t["credit"]) == (EN, "星座を求めて", "human", "星を見よ", "Kaori")
    assert skipped == [{"n": 5, "type": "quest", "id": 175, "field": "objectives", "reason": "wrong", "skip": F.NO_LINE}]
    assert json.loads((folder / "meta.json").read_text())["credit"] == "Kaori"
    assert cmd.intake(repo, 12, _body(FIXES), "", None, False) == 1  # an existing triage is not overwritten


def test_intake_credit_falls_back_to_the_author(repo):
    folder = _intake(repo, credit="_No response_")
    assert json.loads((folder / "meta.json").read_text())["credit"] == "gh-user"


def test_apply_writes_each_decision_with_its_provenance(repo):
    folder = _intake(repo)
    _decide(folder, DECISIONS)
    assert cmd.apply(repo, 12, MODEL, DATE, "maintainer", False) == 0
    used = _line(repo, 175)
    assert used["ja"] == "星を見よ" and used["status"] == "trusted"
    assert used["provenance"] == {
        "class": "correction", "translator": "Kaori", "source": f"correction@{DATE}", "imported": DATE,
        "corrects": "cqjt@3446c82", "note": used["provenance"]["note"], "report": 12}
    assert used["conflicts"][0]["ja"] == "星座を求めて"  # the person's line is kept as a variant
    machine = _line(repo, 176)
    assert machine["ja"] == "星を探せ" and machine["conflicts"] == []
    assert machine["provenance"] == {"class": "machine", "model": MODEL, "source": f"report-12-sg9@{DATE}",
                                     "imported": DATE, "report": 12}
    keep = _line(repo, 178)
    assert keep["ja"] == "星を仰げ" and keep["provenance"] == MACHINE


def test_a_rewrite_of_a_persons_line_is_a_correction_never_a_machine_variant(repo):
    """Machine output replaces a human line only as a correction carrying the report."""
    folder = _intake(repo)
    _decide(folder, DECISIONS)
    cmd.apply(repo, 12, MODEL, DATE, "maintainer", False)
    line = _line(repo, 177)
    assert line["ja"] == "星を求めよ" and line["provenance"]["class"] == "correction"
    assert line["provenance"]["translator"] == "Tammy" and line["provenance"]["model"] == MODEL
    assert line["provenance"]["report"] == 12
    assert all(v["provenance"]["class"] != "machine" for v in line["conflicts"])


def test_apply_writes_the_readings_attribution_and_reply(repo):
    folder = _intake(repo)
    _decide(folder, DECISIONS)
    cmd.apply(repo, 12, MODEL, DATE, "maintainer", False)
    recs = {r["id"]: r for r in Store(repo / "reading").load("quest")}
    assert set(recs) == {175, 176, 177}
    for id_, ja in ((175, "星を見よ"), (176, "星を探せ"), (177, "星を求めよ")):
        assert recs[id_]["ja_hash"] == ja_hash(ja) and recs[id_]["words"] == W[ja]
        assert recs[id_]["provenance"]["source"] == "readings@report-12"
    attribution = (repo.parent / "ATTRIBUTION.md").read_text()
    assert "## Correctors" in attribution and "- Kaori: #12\n" in attribution
    assert "Tammy: #" not in attribution  # a model rewrite credits no corrector
    reply = (folder / "reply.md").read_text()
    for part in ("| 1 | quest 175 · title | **Changed**: your Japanese ships.", "| 2 | quest 176 · title | **Changed**: rewritten.",
                 "| 4 | quest 178 · title | **Kept**: 仰げ", "| 5 | quest 175 · objectives | **Skipped**"):
        assert part in reply, part


def test_a_second_run_changes_nothing(repo):
    folder = _intake(repo)
    _decide(folder, DECISIONS)
    cmd.apply(repo, 12, MODEL, DATE, "maintainer", False)
    before = _snapshot(repo)
    reply = (folder / "reply.md").read_bytes()
    assert cmd.apply(repo, 12, MODEL, DATE, "maintainer", False) == 0
    assert _snapshot(repo) == before and (folder / "reply.md").read_bytes() == reply


def test_dry_run_writes_nothing(repo):
    folder = _intake(repo)
    _decide(folder, DECISIONS)
    before = _snapshot(repo)
    assert cmd.apply(repo, 12, MODEL, DATE, "maintainer", True) == 0
    assert _snapshot(repo) == before and not (folder / "reply.md").exists()


def _without(i):
    return [r for n, r in enumerate(DECISIONS) if n != i]


def _edit(i, **kw):
    rows = [dict(r) for r in DECISIONS]
    rows[i].update(kw)
    return [{k: v for k, v in r.items() if v is not None} for r in rows]


@pytest.mark.parametrize("rows, message", [
    (_without(3), "no decision for quest 178/title"),
    (DECISIONS + [dict(DECISIONS[3])], "decided twice"),
    (DECISIONS + [{"type": "quest", "id": 9, "field": "title", "decision": "keep", "note": "x"}], "not a triaged fix"),
    (_edit(0, decision="maybe"), "decision must be one of"),
    (_edit(1, decision="use"), "`use` on a fix with no Japanese"),
    (_edit(3, ja="星"), "`keep` carries no ja"),
    (_edit(1, ja=None, words=None), "needs the new ja"),
    (_edit(2, note=""), "every decision carries a note"),
    (_edit(1, ja="星座を探せ /Us" + "ers/someone/notes"), "the ja cannot go into the public data (home path)"),
    (_edit(2, words=None), "words: words must be a non-empty list"),
    (_edit(2, words=[["月", "つき", "月", "つき", "moon"]]), "not found in the Japanese"),
    (_edit(1, ja="星座を探せ", words=[["星座", "せいざ", "星座", "せいざ", "constellation"]]), "already ships"),
    (_edit(0, extra=1), "unexpected keys"),
])
def test_a_wrong_decisions_file_writes_nothing(repo, rows, message, capsys):
    folder = _intake(repo)
    _decide(folder, rows)
    before = _snapshot(repo)
    assert cmd.apply(repo, 12, MODEL, DATE, "maintainer", False) == 1
    assert message in capsys.readouterr().out
    assert _snapshot(repo) == before and not (folder / "reply.md").exists()


def test_check_summary_good_stale_and_broken(repo):
    body = _body([_fix(175, "awkward", ja="星を見よ"), F.Fix("quest", 176, "title", "1" * 16, "wrong")])
    ok, text = cmd.summary(body, repo)
    assert ok and "**Report read: 2 fix(es)**" in text
    assert "| 1 | quest `175` · title | awkward / unnatural | yes | ready |" in text
    assert "changed after your game build" in text
    ok, text = cmd.summary(body.replace("end 2", "end 3"), repo)
    assert not ok and "could not be read" in text and "the paste was cut" in text
    ok, text = cmd.summary(_body([]), repo)
    assert not ok and "holds no fixes" in text


def test_correctors_section_leaves_every_other_section_unchanged(root):
    text = (root / "ATTRIBUTION.md").read_text(encoding="utf-8")
    assert with_correctors(text, {}) == text
    added = with_correctors(text, {"zed": [3], "Alpha": [2, 9]})
    assert added.index("- Alpha: #2, #9") < added.index("- zed: #3") < added.index("## Lineage")
    assert with_correctors(added, {}) == text
    assert with_correctors(added, {"zed": [3], "Alpha": [2, 9]}) == added


def test_cli_registers_report(root):
    from wfj.cli import VERBS

    assert VERBS["report"][1] is cmd.run
    assert Path(root / "Makefile").read_text().count("wfj report ") >= 2


def test_which_lines_take_words():
    assert cmd.needs_words("quest", "星を見よ") and cmd.needs_words("ui", "報酬")
    assert not cmd.needs_words("item", "布の切れ端")  # no readings for tooltips
    assert not cmd.needs_words("gossip", "|cffffd100星|rを見よ")  # an escape: the word box refuses it
    assert not cmd.needs_words("book", "<html><body><p>手紙</p></body></html>")
