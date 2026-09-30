"""`wfj stats --delta REF [--capture PATH]`: data/english since a git ref, and the turn-in capture
list."""

import json
import subprocess
from pathlib import Path

import pytest

from wfj.cmd import stats
from wfj.core.hashing import key
from wfj.core.model import english_line
from wfj.core.normalize import normalize_v1
from wfj.io.jsonl_store import Store


def _l(id_, field, en, src="pfquest@7786596"):
    return english_line(id_, field, en, key(normalize_v1(en)), src)


def _git(repo: Path, *args: str) -> None:
    subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True)


@pytest.fixture
def repo(tmp_path: Path, monkeypatch) -> Path:
    data = tmp_path / "data"
    data.mkdir()
    (data / "SCHEMA").write_text("1\n")
    eng = Store(data, english=True)
    eng.save("quest", [
        _l(1, "title", "Kept"), _l(1, "description", "Same text"),
        _l(2, "title", "Old title"), _l(2, "objectives", "Old objectives"),
        _l(2, "completion", "Reward text", "vmangos@13b49dc"),
        _l(3, "title", "Removed later"),
    ])
    eng.save("item", [_l(10, "name", "Linen Cloth", "wago@1.15.9.69722")])
    _git(tmp_path, "init", "-q")
    _git(tmp_path, "-c", "user.email=t@t", "-c", "user.name=t", "add", "data")
    _git(tmp_path, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "base")
    eng.save("quest", [
        _l(1, "title", "Kept"), _l(1, "description", "Same text"),
        _l(2, "title", "New title", "wdb@1.15.9.69722"), _l(2, "objectives", "Old objectives"),
        _l(2, "description", "A description only the cache has", "wdb@1.15.9.69722"),
        _l(2, "completion", "Reward text", "vmangos@13b49dc"),
        _l(4, "title", "Brand new", "wdb@1.15.9.69722"), _l(4, "progress", "Progress", "vmangos@13b49dc"),
    ])
    eng.save("item", [_l(10, "name", "Linen Cloth", "wago@1.15.9.69722"), _l(11, "name", "Wool Cloth", "wago@1.15.9.69722")])
    monkeypatch.chdir(tmp_path)
    return tmp_path


def test_delta_counts(repo, capsys):
    assert stats.run(["--delta", "HEAD"]) == 0
    out = capsys.readouterr().out
    assert "english delta since HEAD:" in out
    rows = {ln.split()[0]: ln.split()[1:] for ln in out.split("english delta since HEAD:")[1].splitlines()[2:]}
    assert rows["quest"] == ["1", "1", "2", "description=1", "title=1"]
    assert rows["item"] == ["1", "0", "0", "-"]
    for t in ("spell", "ui", "gossip"):
        assert rows[t] == ["0", "0", "0", "-"]


def test_capture_rows_and_determinism(repo, capsys):
    path = repo / "capture.jsonl"
    assert stats.run(["--delta", "HEAD", "--capture", str(path)]) == 0
    first = path.read_bytes()
    rows = [json.loads(x) for x in first.decode().splitlines()]
    assert rows == [
        {"id": 2, "title": "New title", "change": "changed", "fields": ["title", "description"],
         "progress_src": None, "completion_src": "vmangos@13b49dc"},
        {"id": 4, "title": "Brand new", "change": "new", "fields": ["title"],
         "progress_src": "vmangos@13b49dc", "completion_src": None},
    ]
    assert "capture list: 2 quests" in capsys.readouterr().out
    assert stats.run(["--delta", "HEAD", "--capture", str(path)]) == 0
    assert path.read_bytes() == first


def test_bad_ref_is_one_line_error_and_writes_nothing(repo, capsys):
    path = repo / "capture.jsonl"
    assert stats.run(["--delta", "no-such-ref", "--capture", str(path)]) == 1
    captured = capsys.readouterr()
    assert captured.out == ""
    assert captured.err.strip() == "wfj stats: unknown git ref 'no-such-ref'"
    assert not path.exists()


def test_capture_needs_delta(repo):
    with pytest.raises(SystemExit) as e:
        stats.run(["--capture", "x.jsonl"])
    assert e.value.code == 2


def test_default_output_unchanged_by_the_flags(repo, capsys):
    assert stats.run([]) == 0
    plain = capsys.readouterr().out
    assert stats.run(["--delta", "HEAD"]) == 0
    with_delta = capsys.readouterr().out
    assert with_delta.startswith(plain) and "english delta" not in plain


def test_delta_lists_the_client_table_types_and_the_status_shift(repo, capsys):
    """Objective / book rows, and translation lines whose status moved."""
    data = repo / "data"
    eng = Store(data, english=True)
    eng.save("objective", [english_line(381177, "text", "Rescue Drull", key(normalize_v1("Rescue Drull")), "wdb@1.15.9.69722")])
    eng.save("book", [_l(1, "text", "Page one.", "vmangos@13b49dc")])
    assert stats.run(["--delta", "HEAD"]) == 0
    out = capsys.readouterr().out
    rows = {ln.split()[0]: ln.split()[1:] for ln in out.split("english delta since HEAD:")[1].splitlines()[2:]}
    assert rows["objective"] == ["1", "0", "0", "-"]
    assert rows["book"] == ["1", "0", "0", "-"]
    assert "trainer_greeting" not in rows
    shift = out.split("status shift since HEAD:")[1].split("english delta")[0]
    assert "  item: none" in shift and "  quest: none" in shift


def test_status_shift_counts_moves():
    from wfj.core import report

    base = [{"id": 1, "field": "description", "status": "unaligned"}, {"id": 2, "field": "description", "status": "trusted"}]
    head = [{"id": 1, "field": "description", "status": "stale"}, {"id": 3, "field": "description", "status": "trusted"}]
    shift = report.status_shift(base, head)
    assert shift == {("description", "unaligned", "stale"): 1, ("description", "trusted", "-"): 1,
                     ("description", "-", "trusted"): 1}
    text = report.render_status_shift("HEAD", {"item": shift, "spell": report.status_shift(base, base)})
    assert "  item: description -→trusted 1, description trusted→- 1, description unaligned→stale 1" in text
    assert "  spell: none" in text
