"""The fix report text (core/fix_report): the shared vectors both ways, every refusal, and resolving a fix
to its store line."""

import json

import pytest

from wfj.core import fix_report as F
from wfj.core.readings import ja_hash
from wfj.dev import gen_report_vectors


def _vectors(root):
    rows = [json.loads(ln) for ln in (root / "vectors" / "report_vectors.jsonl").read_text(encoding="utf-8").splitlines()]
    return [r for r in rows if r["kind"] == "case"], [r for r in rows if r["kind"] == "bad"]


def test_committed_files_match_regeneration(root, tmp_path):
    gen_report_vectors.write(tmp_path)
    for name in ("report_vectors.jsonl", "report_vectors.lua"):
        assert (tmp_path / name).read_text(encoding="utf-8") == (root / "vectors" / name).read_text(encoding="utf-8"), name


def test_vectors_cover_the_hard_parts(root):
    cases, bad = _vectors(root)
    text = "".join(c["text"] for c in cases)
    fixes = [f for c in cases for f in c["fixes"]]
    assert {f["type"] for f in fixes} == set(F.TYPES)
    assert {f["reason"] for f in fixes} == set(F.REASONS)
    assert "\\x7c" in text and "\\n" in text and "\\\\" in text and "|" not in text
    assert any(len(f.get("note", "").encode()) == F.NOTE_MAX for f in fixes)
    assert any(len(f.get("ja", "").encode()) == F.JA_MAX for f in fixes)
    assert any(":" in str(f["id"]) for f in fixes)
    assert len(bad) >= 20


def test_every_case_renders_and_parses_back(root):
    cases, _ = _vectors(root)
    for c in cases:
        rep = F.Report(addon=c["addon"], client=c["client"], fixes=[F.Fix(**f) for f in c["fixes"]])
        assert F.render(rep) == c["text"], c["id"]
        back = F.parse(c["text"])
        assert (back.addon, back.client) == (c["addon"], c["client"])
        assert [f.as_dict() for f in back.fixes] == c["fixes"], c["id"]


def test_every_bad_text_is_refused_with_its_reason(root):
    _, bad = _vectors(root)
    for b in bad:
        with pytest.raises(F.ReportError) as e:
            F.parse(b["text"])
        assert b["error"] in str(e.value), (b["id"], str(e.value))


def _report(fixes: int) -> str:
    lines = ["WFJ-REPORT 1", "addon v0.1.0 client 1.60.1.70009"]
    lines += [f"fix quest {n} title 0011223344556677 typo" for n in range(1, fixes + 1)]
    return "\n".join([*lines, f"end {fixes}"]) + "\n"


def test_a_report_holds_no_more_fixes_than_the_addon_keeps(root):
    assert len(F.parse(_report(F.FIXES_MAX)).fixes) == F.FIXES_MAX
    with pytest.raises(F.ReportError, match=f"at most {F.FIXES_MAX} fixes"):
        F.parse(_report(F.FIXES_MAX + 1))
    reports = (root / "addon/WoWForeverJapanese/Core/Reports.lua").read_text(encoding="utf-8")
    assert f"Reports.CAP = {F.FIXES_MAX}\n" in reports


@pytest.mark.parametrize("bad", ["\u00b2", "\u0663", "9" * 11, "9" * 5000, "07", "-7", "7.0"])
def test_an_id_that_is_not_a_plain_number_is_refused(bad):
    text = f"WFJ-REPORT 1\naddon v0.1.0 client 1.60.1.70009\nfix quest {bad} title 0011223344556677 typo\nend 1\n"
    with pytest.raises(F.ReportError):
        F.parse(text)


def test_the_block_is_found_inside_an_issue_body():
    rep = F.Report(fixes=[F.Fix("quest", 5, "title", ja_hash("星"), "typo", ja="星 ")])
    body = "### Report\n\n```text\n" + F.render(rep) + "```\n\n### Credit me as\n\n_No response_\n"
    got = F.parse(body.replace("\n", "\r\n"))
    assert got.fixes[0].ja == "星 "  # a value keeps its trailing space


def test_escape_round_trip():
    s = "a|b\\c\nd\\n"
    assert F.unescape(F.escape(s)) == s
    assert "|" not in F.escape(s) and "\n" not in F.escape(s)


def _line(id_, ja, status="trusted", en_hash="0" * 16, field="title"):
    return {"id": id_, "field": field, "ja": ja, "status": status, "checks": [],
            "provenance": {"class": "machine", "model": "m", "source": "d@2026-09-18", "imported": "2026-09-18"},
            "english": {"hash": en_hash, "src": "x@1234"}, "reasons": [], "conflicts": []}


def test_resolve_finds_the_line_or_says_why():
    lines = [_line(1, "星"), _line(2, "月", status="rejected")]
    assert F.resolve(F.Fix("quest", 1, "title", ja_hash("星"), "wrong"), lines) == (lines[0], None)
    assert F.resolve(F.Fix("quest", 1, "title", ja_hash("太陽"), "wrong"), lines) == (None, F.ALREADY_CHANGED)
    assert F.resolve(F.Fix("quest", 2, "title", ja_hash("月"), "wrong"), lines) == (None, F.NOT_SHIPPING)
    assert F.resolve(F.Fix("quest", 3, "title", ja_hash("月"), "wrong"), lines) == (None, F.NO_LINE)


def test_a_book_fix_lands_on_the_page_that_ships_under_its_english():
    h = "8f0e2a11b3c4d5e6"
    pages = [_line(12, "手紙", en_hash=h, field="text"), _line(11, "手紙", en_hash=h, field="text", status="stale"),
             _line(13, "別", en_hash="1" * 16, field="text")]
    line, why = F.resolve(F.Fix("book", h, "text", ja_hash("手紙"), "awkward"), pages)
    assert why is None and line["id"] == 12  # a current page before a stale one of the same English
    assert F.resolve(F.Fix("book", "2" * 16, "text", ja_hash("手紙"), "awkward"), pages) == (None, F.NO_LINE)
