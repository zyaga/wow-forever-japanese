"""`dev/apply_review`: a stale hand-written line read against its new English is kept (baseline re-stamped)
or corrected (a `correction` variant edited from the person's Japanese), never redrafted."""

import json

import pytest

from wfj.cmd.check import build_scopes, check_type
from wfj.core.hashing import key
from wfj.core.normalize import normalize_v1
from wfj.dev import apply_review
from wfj.io.jsonl_store import Store

OLD, NEW = "Look To The Stars", "Look to the Stars"
WDB = "wdb@1.60.1.70009"
HUMAN = {"class": "human", "translator": "Tammy", "source": "cqjt@3446c82", "imported": "2026-09-13"}
EARLIER = {"class": "correction", "translator": "Tammy", "source": "correction@2026-09-20", "imported": "2026-09-20",
           "corrects": "cqjt@3446c82"}
RULED = {"by": "maintainer", "date": "2026-09-25", "model": "m"}


def _h(en):
    return key(normalize_v1(en))


def _store(d, prov=HUMAN, status="stale", en=NEW):
    line = {"id": 175, "field": "title", "ja": "星座を求めて", "status": status, "checks": [], "provenance": dict(prov),
            "english": {"hash": _h(OLD), "src": "wdb@1.15.9.69722"}, "reasons": [], "conflicts": []}
    Store(d).save("quest", [line])
    Store(d, english=True).save("quest", [{"id": 175, "field": "title", "en": en, "hash": _h(en), "src": WDB}] if en else [])


def _apply(d, rows, scope="stale"):
    lines = Store(d).load("quest")
    c = apply_review.apply(lines, rows, build_scopes(Store(d, english=True), "quest"), RULED, scope)
    return lines, c


def _checked(d, lines):
    return check_type(lines, build_scopes(Store(d, english=True), "quest"), set())[0]


def test_keep_restamps_the_baseline_and_the_line_is_fresh(tmp_path):
    _store(tmp_path)
    lines, c = _apply(tmp_path, [{"type": "quest", "id": 175, "field": "title", "decision": "keep", "note": "case"}])
    assert c["keep"] == 1 and lines[0]["english"] == {"hash": _h(NEW), "src": WDB}
    assert lines[0]["ja"] == "星座を求めて" and lines[0]["provenance"] == HUMAN and lines[0]["conflicts"] == []
    assert _checked(tmp_path, lines)["status"] == "trusted"


def test_correct_adds_a_correction_over_the_persons_line(tmp_path):
    _store(tmp_path)
    row = {"type": "quest", "id": 175, "field": "title", "decision": "correct", "ja": "星を見よ", "note": "reworded"}
    lines, c = _apply(tmp_path, [row])
    line = lines[0]
    assert c["correct"] == 1 and line["ja"] == "星を見よ"
    assert line["provenance"]["class"] == "correction" and line["provenance"]["translator"] == "Tammy"
    assert line["provenance"]["corrects"] == "cqjt@3446c82" and line["provenance"]["source"] == "correction@2026-09-25"
    assert line["conflicts"][0]["ja"] == "星座を求めて" and "ruling" not in line["conflicts"][0]  # the person's text kept
    out = _checked(tmp_path, lines)
    assert out["status"] == "trusted" and out["ja"] == "星を見よ"


def test_an_earlier_correction_is_superseded_and_the_new_one_names_its_layer(tmp_path):
    _store(tmp_path, prov=EARLIER)
    row = {"type": "quest", "id": 175, "field": "title", "decision": "correct", "ja": "星を見よ", "note": "reworded"}
    lines, c = _apply(tmp_path, [row])
    assert c["superseded"] == 1 and lines[0]["provenance"]["corrects"] == "cqjt@3446c82"
    assert lines[0]["conflicts"][0]["ruling"]["ruling"] == "reject"


@pytest.mark.parametrize(("kw", "message"), [
    ({"status": "trusted"}, "not a stale line"),
    ({"prov": {"class": "machine", "model": "m", "source": "draft-q-sg9@2026-09-23", "imported": "2026-09-23"}},
     "not a stale line"),
    ({"en": None}, "no English"),
])
def test_refuses_what_it_must_not_touch(tmp_path, kw, message):
    _store(tmp_path, **kw)
    with pytest.raises(ValueError, match=message):
        _apply(tmp_path, [{"type": "quest", "id": 175, "field": "title", "decision": "keep", "note": "x"}])


def test_a_decisions_file_needs_a_note_and_ja_only_on_correct(tmp_path):
    p = tmp_path / "d.jsonl"
    for row, message in [({"decision": "keep"}, "note"), ({"decision": "keep", "ja": "x", "note": "n"}, "only there"),
                         ({"decision": "correct", "note": "n"}, "only there"), ({"decision": "drop", "note": "n"}, "one of")]:
        p.write_text(json.dumps({"type": "quest", "id": 1, "field": "title", **row}) + "\n", encoding="utf-8")
        with pytest.raises(ValueError, match=message):
            apply_review.read_decisions(p)


def test_a_row_decided_twice_is_refused(tmp_path):
    # a duplicate is reported, never resolved last-wins
    p = tmp_path / "d.jsonl"
    row = {"type": "quest", "id": 1, "field": "title", "decision": "keep", "note": "n"}
    p.write_text(json.dumps(row) + "\n" + json.dumps({**row, "decision": "correct", "ja": "x"}) + "\n", encoding="utf-8")
    with pytest.raises(ValueError, match="decided twice"):
        apply_review.read_decisions(p)


def test_a_second_run_leaves_applied_rows_as_they_are(tmp_path):
    _store(tmp_path)
    row = {"type": "quest", "id": 175, "field": "title", "decision": "correct", "ja": "星を見よ", "note": "reworded"}
    lines, c = _apply(tmp_path, [row])
    Store(tmp_path).save("quest", lines)
    again, c2 = _apply(tmp_path, [row])  # before `make check`: the line still says stale
    assert c2 == {"keep": 0, "correct": 0, "redraft": 0, "superseded": 0, "already": 1}
    assert again == lines


# the audit scope: any shipped hand-written line, decisions correct / redraft


@pytest.mark.parametrize("status", ["trusted", "unaligned", "stale"])
def test_audit_corrects_any_shipped_hand_written_line(tmp_path, status):
    _store(tmp_path, status=status)
    row = {"type": "quest", "id": 175, "field": "title", "decision": "correct", "ja": "星を見よ", "note": "typo"}
    lines, c = _apply(tmp_path, [row], "audit")
    line = lines[0]
    assert c["correct"] == 1 and line["ja"] == "星を見よ" and line["provenance"]["class"] == "correction"
    assert line["provenance"]["note"].startswith("Typo") and "audit" in line["provenance"]["note"]
    assert line["conflicts"][0]["ja"] == "星座を求めて"


def test_audit_redraft_rules_every_hand_written_variant_reject(tmp_path):
    _store(tmp_path, prov=EARLIER, status="trusted")
    lines = Store(tmp_path).load("quest")
    lines[0]["conflicts"] = [{"ja": "星座", "provenance": dict(HUMAN)}]
    Store(tmp_path).save("quest", lines)
    row = {"type": "quest", "id": 175, "field": "title", "decision": "redraft", "note": "another quest's text"}
    lines, c = _apply(tmp_path, [row], "audit")
    line = lines[0]
    assert c["redraft"] == 1 and line["ja"] == "星座を求めて"  # the text stays; the ruling stops it shipping
    for v in (line, line["conflicts"][0]):
        assert v["ruling"]["ruling"] == "reject" and v["ruling"]["note"].startswith("Another quest's text")
    assert _checked(tmp_path, lines)["status"] == "rejected"
    Store(tmp_path).save("quest", lines)
    again, c2 = _apply(tmp_path, [row], "audit")
    assert c2["already"] == 1 and again == lines


@pytest.mark.parametrize(("kw", "message"), [
    ({"status": "rejected"}, "not a shipped line"),
    ({"prov": {"class": "machine", "model": "m", "source": "draft-q-sg9@2026-09-23", "imported": "2026-09-23"},
      "status": "trusted"}, "not a shipped line"),
])
def test_audit_refuses_what_it_must_not_touch(tmp_path, kw, message):
    _store(tmp_path, **kw)
    row = {"type": "quest", "id": 175, "field": "title", "decision": "redraft", "note": "x"}
    with pytest.raises(ValueError, match=message):
        _apply(tmp_path, [row], "audit")


def test_the_stale_scope_is_unchanged_it_takes_no_redraft_and_no_trusted_line(tmp_path):
    p = tmp_path / "d.jsonl"
    p.write_text(json.dumps({"type": "quest", "id": 1, "field": "title", "decision": "redraft", "note": "n"}) + "\n",
                 encoding="utf-8")
    with pytest.raises(ValueError, match="one of"):
        apply_review.read_decisions(p)
    assert apply_review.read_decisions(p, "audit")[0]["decision"] == "redraft"
    _store(tmp_path, status="trusted")
    with pytest.raises(ValueError, match="not a stale line"):
        _apply(tmp_path, [{"type": "quest", "id": 175, "field": "title", "decision": "keep", "note": "x"}])


def test_audit_takes_no_keep(tmp_path):
    p = tmp_path / "d.jsonl"
    p.write_text(json.dumps({"type": "quest", "id": 1, "field": "title", "decision": "keep", "note": "n"}) + "\n",
                 encoding="utf-8")
    with pytest.raises(ValueError, match="one of"):
        apply_review.read_decisions(p, "audit")


def test_templates_scope_corrects_a_shipped_line_and_names_its_scope(tmp_path):
    """The baked numbers of a hand-written line on an included / branching template are rewritten as a
    correction, under the templates scope: any shipped line, like the audit, its notes naming the scope."""
    _store(tmp_path, status="unaligned")
    row = {"type": "quest", "id": 175, "field": "title", "decision": "correct", "ja": "星を見よ", "note": "$N1"}
    lines, c = _apply(tmp_path, [row], scope="templates")
    assert c["correct"] == 1 and lines[0]["provenance"]["note"].startswith("$N1")
    assert "placeholders" in lines[0]["provenance"]["note"]


def test_stat_words_scope_corrects_a_shipped_line_and_names_its_reason(tmp_path):
    _store(tmp_path, status="trusted", en=OLD)
    row = {"type": "quest", "id": 175, "field": "title", "decision": "correct", "ja": "星を見よ",
           "note": "Stat words written with the interface's Japanese"}
    lines, c = _apply(tmp_path, [row], scope="stat-words")
    assert c["correct"] == 1 and lines[0]["provenance"]["class"] == "correction"
    assert "that tooltip stat words use the interface's Japanese" in lines[0]["provenance"]["note"]
