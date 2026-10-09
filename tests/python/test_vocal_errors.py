"""`wfj.dev.vocal_errors`: each game voice id's kind of error, read from its sound files' names, with the
archive and the table reader stood in."""

from __future__ import annotations

import json
from types import SimpleNamespace

import pytest

from wfj.dev import vocal_errors as ve
from wfj.io.db2 import Db2Table

# VocalUISounds: (voice id, race, class, the male and female sound kits)
VOCAL = {1: (1, 1, 0, (100, 101)), 2: (1, 2, 0, (102, 0)), 3: (2, 1, 0, (103, 104)), 4: (3, 1, 0, (105, 0))}
# SoundKitEntry: (sound kit, file id); row 12 names its kit through the relation map
ENTRIES = {10: (100, 5001), 11: (101, 5002), 12: (0, 5003), 13: (103, 5004), 14: (104, 5005), 15: (105, 5006)}
LISTFILE = "\n".join([
    "5001;sound/character/errormessages/humanmale_err_outofrange01.ogg",
    "5002;sound/character/errormessages/humanfemale_err_outofrange02.ogg",
    "5003;sound/character/errormessages/orcmale_err_outofrange.ogg",
    "5004;sound/character/errormessages/humanmale_err_cantequiplevel01.ogg",
    "5005;sound/character/errormessages/humanfemale_err_cantequipskill01.ogg",
    "5006;sound/character/other/humanmale_err_ignored01.ogg",
]) + "\n"


class FakeArchive:
    def __init__(self, *args):
        self.args = args

    def read_file(self, fdid):
        return {ve.VOCAL_UI_SOUNDS: b"vocal", ve.SOUND_KIT_ENTRY: b"entries"}[fdid], []


@pytest.fixture
def tables(monkeypatch):
    def read(buf, string_fields, gaps, name):
        assert (string_fields, gaps) == (frozenset(), [])
        if name == "VocalUISounds":
            assert buf == b"vocal"
            return Db2Table(0, 0, 4, rows=dict(VOCAL))
        assert (buf, name) == (b"entries", "SoundKitEntry")
        return Db2Table(0, 0, 2, rows=dict(ENTRIES), relation={12: 102})

    monkeypatch.setattr(ve.db2, "read", read)


def test_a_voice_ids_kind_comes_from_its_files_names(tables, tmp_path):
    listfile = tmp_path / "listfile.csv"
    listfile.write_text(LISTFILE, encoding="utf-8")
    got, problems = ve.kinds(FakeArchive(), listfile)
    # two kinds in one voice id's files are one combined kind; a kit with no error file is left out
    assert got == {1: "outofrange", 2: "cantequiplevel-cantequipskill"}
    assert problems == ["voice id 3: no file"]


def test_main_writes_one_row_per_voice_id_with_its_source(tables, tmp_path, monkeypatch, capsys):
    listfile = tmp_path / "listfile.csv"
    listfile.write_text(LISTFILE, encoding="utf-8")
    monkeypatch.setattr(ve.casc, "LocalArchive", FakeArchive)
    monkeypatch.setattr(ve.casc, "read_build_info", lambda wow, product: SimpleNamespace(version="1.60.1.70245"))
    out = tmp_path / "error-kinds.jsonl"
    argv = ["--wow", str(tmp_path / "wow"), "--listfile", str(listfile), "--out", str(out)]
    assert ve.main(argv) == 0
    rows = [json.loads(ln) for ln in out.read_text(encoding="utf-8").splitlines()]
    assert [(r["voice_id"], r["kind"]) for r in rows] == [(1, "outofrange"), (2, "cantequiplevel-cantequipskill")]
    assert {r["provenance"]["source"] for r in rows} == {"client@1.60.1.70245"}
    io = capsys.readouterr()
    assert io.out == f"vocal errors: 2 voice ids, 2 kinds → {out}\n"
    assert io.err == "vocal errors: left out voice id 3: no file\n"
