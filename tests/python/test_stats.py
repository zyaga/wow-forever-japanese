"""`wfj stats` lists collected gossip keys by how many NPCs say them (the blast radius)."""

from pathlib import Path

from wfj.cmd import stats
from wfj.core import report
from wfj.core.hashing import key
from wfj.core.model import english_line, entry, provenance
from wfj.core.normalize import normalize_v1
from wfj.io.jsonl_store import Store

SRC = "collector@1.15.9.69722"


def _g(en: str, npcs: list[int]) -> dict:
    k = key(normalize_v1(en))
    return english_line(k, "text", en, k, SRC, npcs=npcs)


def test_gossip_radius_orders_by_npc_count_then_key():
    long = "Greetings, $N. " + "The winds carry news from every corner of Azeroth, and I hear all of it. " * 2
    english = [_g("Goodbye.", [1, 2, 3]), _g(long, [9]), _g("I want to browse your goods.", [4])]
    shipped = entry(english[2]["id"], "text", "品物を見せてくれ。", status="trusted",
                    prov=provenance("machine", "draft@2026-09-14", "2026-09-14"))
    text = report.gossip_radius(english, [shipped])
    lines = text.splitlines()
    assert lines[0] == "gossip: 3 keys with English · 1 translated"
    assert lines[1] == f"    3 {english[0]['id']} -         Goodbye."
    rest = sorted(english[1:], key=lambda ln: ln["id"])
    for row, ln in zip(lines[2:], rest, strict=True):
        assert row.startswith(f"    1 {ln['id']} ")
    by_id = {ln["id"]: row for ln, row in zip(rest, lines[2:], strict=True)}
    assert "trusted" in by_id[english[2]["id"]]
    assert by_id[english[1]["id"]].endswith(long[:60] + "…")
    assert report.gossip_radius([], []) == "gossip: no collected English"


def test_gossip_radius_caps_the_listing():
    english = [_g(f"Line number {i}.", [i]) for i in range(1, 31)]
    assert len(report.gossip_radius(english, []).splitlines()) == 1 + report.GOSSIP_TOP


def test_stats_prints_the_gossip_section(tmp_path: Path, monkeypatch, capsys):
    data = tmp_path / "data"
    data.mkdir()
    (data / "SCHEMA").write_text("1\n")
    monkeypatch.chdir(tmp_path)
    assert stats.run([]) == 0
    assert "gossip: no collected English" in capsys.readouterr().out
    Store(data, english=True).save("gossip", [_g("Goodbye.", [1, 2])])
    assert stats.run([]) == 0
    assert "gossip: 1 keys with English · 0 translated" in capsys.readouterr().out


# ADR-019: the offline list of quest lines to fix.
PF, VM = "pfquest@7786596", "vmangos@13b49dc"
PROV = provenance("human", "cqjt@3446c82", "2026-09-13", translator="Tammy")
ORDER = ["title", "objectives", "description", "progress", "completion"]


def _q(id_, field, ja, status, en):
    ln = entry(id_, field, ja, status=status, prov=PROV)
    ln["english"] = {"hash": key(normalize_v1(en)), "src": VM}
    return ln


def _e(id_, field, en, src):
    return english_line(id_, field, en, key(normalize_v1(en)), src)


def test_stale_report_rows():
    lines = [_q(7, "completion", "よくやった", "stale", "Well done."), _q(7, "title", "題", "trusted", "Title")]
    english = [_e(7, "completion", "Well done, citizen.", VM), _e(7, "title", "Title", PF)]
    rows = report.stale_rows(lines, english, ORDER)
    assert rows == [{
        "id": 7, "field": "completion", "status": "stale", "ja": "よくやった", "en": None, "src": VM, "of": None,
        "others": [{"src": VM, "en": "Well done, citizen.", "hash": key(normalize_v1("Well done, citizen."))}],
    }]


def test_stale_report_collector_mismatch():
    col = "collector@1.15.9.69722"
    lines = [
        _q(9, "completion", "よくやった", "trusted", "Well done."),
        _q(9, "progress", "まだか", "trusted", "Not yet?"),
        _q(10, "completion", "却下", "rejected", "Nope."),  # not shipped: never listed
    ]
    english = [
        _e(9, "completion", "Well done.", VM), _e(9, "completion", "Well done, hero.", col),
        _e(9, "progress", "Not yet?", VM), _e(9, "progress", "Not yet?", col),  # every source agrees: no row
        _e(10, "completion", "Other.", col),
    ]
    rows = report.stale_rows(lines, english, ORDER)
    assert [(r["id"], r["field"]) for r in rows] == [(9, "completion")]
    assert rows[0]["en"] == "Well done." and rows[0]["src"] == VM
    assert rows[0]["others"] == [{"src": col, "en": "Well done, hero.", "hash": key(normalize_v1("Well done, hero."))}]


def test_stale_report_deterministic(tmp_path: Path, monkeypatch, capsys):
    data = tmp_path / "data"
    data.mkdir()
    (data / "SCHEMA").write_text("1\n")
    monkeypatch.chdir(tmp_path)
    Store(data).save("quest", [_q(12, "completion", "b", "stale", "B."), _q(3, "title", "a", "stale", "A.")])
    Store(data, english=True).save("quest", [_e(3, "title", "A!", PF), _e(12, "completion", "B!", VM)])
    out = tmp_path / "stale.jsonl"
    assert stats.run(["--stale", str(out)]) == 0
    first = out.read_bytes()
    assert stats.run(["--stale", str(out)]) == 0
    assert out.read_bytes() == first
    ids = [line.split(",")[0] for line in first.decode().splitlines()]
    assert ids == ['{"id": 3', '{"id": 12']
    assert "stale report: 2 quest lines" in capsys.readouterr().out


def test_stats_output_unchanged_without_flag(tmp_path: Path, monkeypatch, capsys):
    data = tmp_path / "data"
    data.mkdir()
    (data / "SCHEMA").write_text("1\n")
    monkeypatch.chdir(tmp_path)
    Store(data).save("quest", [_q(3, "title", "a", "stale", "A.")])
    Store(data, english=True).save("quest", [_e(3, "title", "A!", PF)])
    assert stats.run([]) == 0
    plain = capsys.readouterr().out
    assert stats.run(["--stale", str(tmp_path / "s.jsonl")]) == 0
    with_flag = capsys.readouterr().out
    assert with_flag.startswith(plain) and "stale report" not in plain


def _dump(path: Path, entries: dict[tuple[int, str], str]) -> Path:
    rows = []
    for (id_, field), en in entries.items():
        h = key(normalize_v1(en))
        e = en.replace("\\", "\\\\").replace('"', '\\"')
        rows.append(f'["quest:{id_}:{field}"] = {{ t = "quest", i = {id_}, f = "{field}", h = "{h}", e = "{e}", b = 1 }},')
    path.write_text(
        'WFJ_Collector = { version = 1, builds = { "1.15.9.69722" }, entries = {\n' + "\n".join(rows) + "\n} }\n",
        encoding="utf-8",
    )
    return path


def test_stale_report_reads_a_dump_where_a_curated_source_has_the_field(tmp_path: Path, monkeypatch, capsys):
    """A dump not imported yet: `stats --stale --dump` lists the line whose live English differs from the
    stored VMaNGOS English."""
    data = tmp_path / "data"
    data.mkdir()
    (data / "SCHEMA").write_text("1\n")
    monkeypatch.chdir(tmp_path)
    Store(data, english=True).save("quest", [_e(9, "completion", "Well done.", VM), _e(9, "progress", "Not yet?", VM)])
    Store(data).save("quest", [_q(9, "completion", "よくやった", "trusted", "Well done."),
                               _q(9, "progress", "まだか", "trusted", "Not yet?")])
    dump = _dump(tmp_path / "WoWForeverJapanese.lua", {(9, "completion"): "Well done, hero.", (9, "progress"): "Not yet?"})
    out = tmp_path / "stale.jsonl"
    assert stats.run(["--stale", str(out)]) == 0
    assert out.read_text() == ""
    assert stats.run(["--stale", str(out), "--dump", str(dump), "--dump", str(dump)]) == 0
    import json

    rows = [json.loads(x) for x in out.read_text(encoding="utf-8").splitlines()]
    assert [(r["id"], r["field"]) for r in rows] == [(9, "completion")]
    assert rows[0]["others"] == [
        {"src": "collector@1.15.9.69722", "en": "Well done, hero.", "hash": key(normalize_v1("Well done, hero."))}
    ]  # the same dump twice is listed once


def test_stale_report_errors_are_one_line(tmp_path: Path, monkeypatch, capsys):
    data = tmp_path / "data"
    data.mkdir()
    (data / "SCHEMA").write_text("1\n")
    monkeypatch.chdir(tmp_path)
    assert stats.run(["--stale", str(tmp_path / "missing-dir" / "s.jsonl")]) == 1
    assert len(capsys.readouterr().err.strip().splitlines()) == 1
    assert stats.run(["--stale", str(tmp_path / "s.jsonl"), "--dump", str(tmp_path / "absent.lua")]) == 1
    assert len(capsys.readouterr().err.strip().splitlines()) == 1
