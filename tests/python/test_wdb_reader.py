"""The quest-cache reader (`pipeline/wfj/io/wdb.py`) on real records cut from a
`questcache.wdb` (`wfj.dev.cut_wdb_fixture`), and every malformed shape it must refuse. The
Forever 1.60.1.69913 fixture has a different payload layout: one pinned `Layout` per build, and a build with
no pinned layout is refused."""

import json
import struct
from pathlib import Path

import pytest

from wfj.cmd.import_ import run
from wfj.io import wdb

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures"
FIXTURE = FIXTURES / "wdb"  # Classic Era 1.15.9.69722
FOREVER = FIXTURES / "wdb-forever"  # Forever 1.60.1.69913


def _records(buf: bytes) -> list[tuple[int, bytes]]:
    out, off = [], wdb.HEADER_SIZE
    while True:
        qid, length = wdb.RECORD_HEADER.unpack_from(buf, off)
        if qid == 0 and length == 0:
            return out
        out.append((qid, buf[off + 8 : off + 8 + length]))
        off += 8 + length


def _build(header: bytes, records: list[tuple[int, bytes]], terminator: bool = True) -> bytes:
    body = b"".join(struct.pack("<II", q, len(p)) + p for q, p in records)
    return header + body + (struct.pack("<II", 0, 0) if terminator else b"")


@pytest.fixture(scope="module")
def real() -> bytes:
    return (FIXTURE / "questcache.wdb").read_bytes()


def test_reads_the_real_records():
    cache = wdb.read_quests(FIXTURE / "questcache.wdb")
    expected = json.loads((FIXTURE / "expected.json").read_text(encoding="utf-8"))
    assert cache.build == expected["build"] == 69722
    assert cache.layout is not None and cache.layout.build == 69722
    assert cache.placeholders == expected["placeholders"] == [490]
    assert _as_json(cache.quests) == expected["quests"]
    by_id = {q.id: q for q in cache.quests}
    assert [q.id for q in cache.quests] == sorted(by_id) == [25, 170, 172, 247, 498]
    # the area description and each objective's own text, keyed by its QuestObjective id
    assert by_id[25].area == "Scout the gazebo on Mystral Lake that overlooks the nearby Alliance outpost."
    assert by_id[498].objective_texts == ((381177, "Rescue Drull"), (381178, "Rescue Tog'thar"))
    assert by_id[170].objective_texts == ()  # kill objectives carry no text of their own
    assert by_id[170].title == "A New Threat"
    assert by_id[170].objectives == "Balir Frosthammer wants you to kill 6 Rockjaw Troggs and 6 Burly Rockjaw Troggs."
    assert "$g lad : lass;" in by_id[170].description and "$b$b" in by_id[170].description
    assert by_id[170].description.endswith("help drive the troggs back.")
    assert by_id[247].objectives == ""  # an empty field decodes as empty
    assert by_id[498].title and "Rescue Drull" not in by_id[498].objectives  # objective descriptions are skipped
    assert by_id[172].title == "Children's Week"


def _as_json(quests) -> list[dict]:
    return [
        {
            **vars(q),
            "objective_texts": [list(t) for t in q.objective_texts],
            "conditional": [list(c) for c in q.conditional],
        }
        for q in quests
    ]


def _expect_error(tmp_path: Path, data: bytes, *needles: str) -> None:
    path = tmp_path / "questcache.wdb"
    path.write_bytes(data)
    with pytest.raises(wdb.WdbError) as err:
        wdb.read_quests(path)
    for needle in ("questcache.wdb", *needles):
        assert needle in str(err.value)


def _patch(payload: bytes, at: int, value: bytes) -> bytes:
    return payload[:at] + value + payload[at + len(value) :]


def test_malformed_files_are_errors(tmp_path, real):
    header, recs = real[: wdb.HEADER_SIZE], _records(real)
    _expect_error(tmp_path, b"XXXX" + real[4:], "not a quest cache")
    _expect_error(tmp_path, real[:8] + b"RFrf" + real[12:], "not enUS")
    _expect_error(tmp_path, _build(header, recs, terminator=False), "without the zero terminator")
    _expect_error(tmp_path, _build(header, recs) + b"\0", "after the zero terminator")
    truncated = _build(header, recs)[: wdb.HEADER_SIZE + 8 + 100]
    _expect_error(tmp_path, truncated, "quest 170", "runs past the end")
    q, p = recs[0]
    _expect_error(tmp_path, _build(header, [(q, p + b"x"), *recs[1:]]), "quest 170", "strings end at")
    _expect_error(tmp_path, _build(header, [(q, p[:-1]), *recs[1:]]), "quest 170", "strings end at")
    bad_utf8 = _patch(p, len(p) - 5, b"\xff")
    _expect_error(tmp_path, _build(header, [(q, bad_utf8), *recs[1:]]), "quest 170", "not UTF-8")
    _expect_error(tmp_path, _build(header, [*recs, recs[0]]), "quest 170 is cached twice")
    _expect_error(tmp_path, _build(header, [(q, _patch(p, 0, struct.pack("<I", 171))), *recs[1:]]), "names quest 171")
    at480 = _patch(p, 480, struct.pack("<I", 1))
    _expect_error(tmp_path, _build(header, [(q, at480), *recs[1:]]), "the u32 at 480 is not zero")
    _expect_error(tmp_path, _build(header, [(q, p[:300])]), "shorter than the fixed part")
    lay = wdb.layout_for(69722)
    flag_at = lay.objectives_at + wdb.OBJECTIVE_SIZE - 1
    _expect_error(tmp_path, _build(header, [(q, _patch(p, flag_at, b"\x81")), *recs[1:]]), "unknown bits")
    # the bits after the nine string lengths carry this build's value, not just "zero"
    bits = _patch(p, lay.bits_at + wdb.BITS_BYTES - 1, bytes([p[lay.bits_at + wdb.BITS_BYTES - 1] | 1]))
    _expect_error(tmp_path, _build(header, [(q, bits), *recs[1:]]), "the bits after the string lengths")


def test_an_unpinned_build_is_refused(tmp_path, real):
    """ADR-020: a build with no verified layout stops the import rather than guessing one."""
    path = tmp_path / "questcache.wdb"
    path.write_bytes(real[:4] + struct.pack("<I", 99999) + real[8:])
    with pytest.raises(wdb.WdbError, match=r"build 99999 has no pinned payload layout \(pinned: 69722, 69913, 70009\)"):
        wdb.read_quests(path)
    assert "wdb_layout" in str(pytest.raises(wdb.WdbError, wdb.read_quests, path).value)
    # the framing still reads, which is what a rescan list needs
    assert wdb.read_ids(path) == (99999, sorted(q for q, _ in _records(real)))


def test_reads_the_forever_records():
    """The Forever payload layout: every part of it exercised by some record in the fixture."""
    cache = wdb.read_quests(FOREVER / "questcache.wdb")
    expected = json.loads((FOREVER / "expected.json").read_text(encoding="utf-8"))
    assert cache.build == expected["build"] == 69913
    assert cache.layout is not None and cache.layout.build == 69913
    assert cache.placeholders == expected["placeholders"] == [802]
    assert _as_json(cache.quests) == expected["quests"]
    by_id = {q.id: q for q in cache.quests}
    assert by_id[84399].title == "Ka-Boom!"  # none of the new lists: the plain case
    assert by_id[6843].objectives == "" and by_id[6843].description == ""  # no objectives, no prose
    # the 12-byte list before the objectives (3 entries) does not shift the prose
    assert by_id[1665].objectives == "Bring Bartleby's Mug to Burlguard"
    assert by_id[1665].description.startswith("Ok, here's my mug.")
    # an objective's own inner list (12 entries) does not shift it either
    assert by_id[93165].objectives.startswith("Speak with") or by_id[93165].objectives
    assert len(by_id[93165].description) == 380
    assert by_id[95771].area == "Scout through the Fargodeep Mine"  # an area description, no objectives
    assert by_id[92709].objective_texts == ((478338, "Listen to Elaadrin"),)
    assert by_id[94978].area == "Tame a Windsong Crawler"
    # The conditional-text arrays: a whole variant of the description, keyed by a PlayerCondition. Quest
    # 92596's own description is the one for a non-mage; the conditional entry is the mage's. Read so the
    # payload adds up and reported, but never imported; see the reader's note on the key.
    assert by_id[92596].conditional[0][:2] == (137886, 0)
    assert "even for a mage such as yourself" in by_id[92596].conditional[0][2]
    assert "even though you are not initiated as a mage" in by_id[92596].description
    assert by_id[94978].conditional == ((0, 0, ""),)  # an entry may be empty
    assert all(not q.conditional for q in cache.quests if q.id not in (92596, 94978))


def test_the_70009_layout_is_the_69913_offsets(tmp_path):
    """Forever 1.60.1.70009 kept 69913's payload layout (dev/wdb_layout over the full 70009 scan). The pin
    is its own entry with its own evidence, and the 69913 fixture, restamped 70009, reads the same quests."""
    from dataclasses import replace

    assert replace(wdb.layout_for(70009), build=69913, evidence="") == replace(wdb.layout_for(69913), evidence="")
    real = (FOREVER / "questcache.wdb").read_bytes()
    path = tmp_path / "questcache.wdb"
    path.write_bytes(real[:4] + struct.pack("<I", 70009) + real[8:])
    cache = wdb.read_quests(path)
    assert cache.build == 70009 and cache.layout is not None and cache.layout.build == 70009
    assert _as_json(cache.quests) == _as_json(wdb.read_quests(FOREVER / "questcache.wdb").quests)


def test_the_two_layouts_do_not_read_each_other(tmp_path):
    """Each pinned layout reads its own build and none of the other's records, so a wrong pick is loud."""
    for src, other in ((FIXTURE, 69913), (FOREVER, 69722)):
        path = src / "questcache.wdb"
        assert wdb.read_quests(path).quests  # its own layout reads it
        with pytest.raises(wdb.WdbError):
            wdb.read_quests(path, layout=wdb.layout_for(other))


def test_import_of_a_malformed_file_writes_nothing(tmp_path, monkeypatch, capsys, real):
    data = tmp_path / "data"
    data.mkdir()
    (data / "SCHEMA").write_text("1\n")
    monkeypatch.chdir(tmp_path)
    bad = tmp_path / "questcache.wdb"
    bad.write_bytes(real[:-8])  # no terminator
    assert run(["english", "wdb", str(bad), "--build", "1.15.9.69722"]) == 1
    err = capsys.readouterr().err.strip().splitlines()
    assert len(err) == 1 and err[0].startswith("wfj import: questcache.wdb:")
    assert not (data / "english").exists()
