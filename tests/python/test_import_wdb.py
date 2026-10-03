"""`wfj import english wdb`: Blizzard's cached quest text merged over pfQuest (ADR-020)."""

import struct
from pathlib import Path

import pytest

from wfj.cmd.import_ import run
from wfj.core.hashing import key
from wfj.core.model import english_line, validate_line
from wfj.core.normalize import normalize_v1
from wfj.io.jsonl_store import Store
from wfj.io.wdb import WdbError, read_ids, read_quests

FIXTURE = Path(__file__).resolve().parents[1] / "fixtures" / "wdb" / "questcache.wdb"
BUILD = "1.15.9.69722"
SRC = f"wdb@{BUILD}"


def _line(id_, field, en, src):
    return english_line(id_, field, en, key(normalize_v1(en)), src)


def _data(tmp_path: Path, monkeypatch) -> Path:
    data = tmp_path / "data"
    data.mkdir()
    (data / "SCHEMA").write_text("1\n")
    monkeypatch.chdir(tmp_path)
    return data


def _seed(data: Path) -> list[dict]:
    q = {x.id: x for x in read_quests(FIXTURE).quests}
    lines = [
        _line(170, "title", q[170].title, "pfquest@7786596"),  # same text as the cache
        _line(170, "objectives", "Kill some troggs.", "pfquest@7786596"),  # differs
        _line(170, "progress", "Tenacious little buggers, aren't they?", "vmangos@13b49dc"),
        _line(247, "objectives", "pfQuest objectives the cache has empty", "pfquest@7786596"),
        _line(9000, "title", "Only pfQuest has me", "pfquest@7786596"),
        _line(9000, "completion", "Only VMaNGOS has me", "vmangos@13b49dc"),
        _line(490, "title", "A pfQuest title for a placeholder id", "pfquest@7786596"),
    ]
    Store(data, english=True).save("quest", lines)
    return lines


def _run(*extra: str, build: str = BUILD) -> int:
    return run(["english", "wdb", str(FIXTURE), "--build", build, *extra])


def test_merge_over_pfquest(tmp_path, monkeypatch, capsys):
    data = _data(tmp_path, monkeypatch)
    seed = {(ln["id"], ln["field"]): ln for ln in _seed(data)}
    assert _run() == 0
    out = capsys.readouterr().out
    got = {(ln["id"], ln["field"]): ln for ln in Store(data, english=True).load("quest")}
    cache = {x.id: x for x in read_quests(FIXTURE).quests}
    # (a) a wdb line per non-empty cached field; (b) it replaces pfQuest's line for that key
    for qid, q in cache.items():
        for field in ("title", "objectives", "description"):
            text = getattr(q, field)
            if text.strip():
                ln = got[(qid, field)]
                assert ln["src"] == SRC and ln["en"] == text and ln["hash"] == key(normalize_v1(text))
                assert validate_line("quest", ln, english=True) == []
    # (c) every other key kept byte-identical: pfQuest where the cache is empty or absent, all VMaNGOS lines
    for k in [(170, "progress"), (247, "objectives"), (9000, "title"), (9000, "completion"), (490, "title")]:
        assert got[k] == seed[k]
    # (d) the placeholder quest writes nothing
    assert "10 placeholders" not in out and "1 placeholders dropped" in out
    assert not any(ln["src"] == SRC and ln["id"] == 490 for ln in got.values())
    # (e) per-field counts: title 170 same, objectives 170 changed, everything else new
    rows = {r.split()[0]: r.split()[1:] for r in out.splitlines() if r.split()[:1] in (["title"], ["objectives"], ["description"])}
    assert rows["title"] == ["1", "0", "4"]  # placeholders: 490 only in this fixture
    assert rows["objectives"] == ["0", "1", "3"]
    assert rows["description"] == ["0", "0", "4"]  # quest 247's cached description is empty


def test_build_mismatch_writes_nothing(tmp_path, monkeypatch, capsys):
    data = _data(tmp_path, monkeypatch)
    _seed(data)
    before = {p.name: p.read_bytes() for p in (data / "english" / "quest").iterdir()}
    assert _run(build="1.15.9.1") == 1
    assert "is build 69722, --build is 1.15.9.1" in capsys.readouterr().err
    assert _run(build="69722") == 1
    assert {p.name: p.read_bytes() for p in (data / "english" / "quest").iterdir()} == before


def test_reimport_is_a_byte_no_op(tmp_path, monkeypatch):
    data = _data(tmp_path, monkeypatch)
    _seed(data)
    assert _run() == 0
    first = {p.name: p.read_bytes() for p in (data / "english" / "quest").iterdir()}
    assert _run() == 0
    assert {p.name: p.read_bytes() for p in (data / "english" / "quest").iterdir()} == first


def test_coverage_and_missing_list(tmp_path, monkeypatch, capsys):
    _data(tmp_path, monkeypatch)
    questv2 = tmp_path / "QuestV2.csv"
    # cached: 25, 170, 172, 247, 498 + placeholder 490 (answered too). Unanswered: 137, 9999, 12000.
    questv2.write_text("ID,UniqueBitFlag\n25,1\n137,2\n170,3\n490,4\n9999,5\n12000,6\n")
    missing = tmp_path / "missing.txt"
    assert _run("--questv2", str(questv2), "--missing", str(missing)) == 0
    out = capsys.readouterr().out
    assert "answered 3 / 5 QuestV2 ids below 10000" in out
    assert "answered 3 / 6 all QuestV2 ids" in out
    assert "cached ids not in QuestV2: 3" in out  # 172, 247, 498
    assert "unanswered: 3 ids" in out
    assert missing.read_text() == "137\n9999\n12000\n"


def test_missing_needs_questv2(tmp_path, monkeypatch, capsys):
    _data(tmp_path, monkeypatch)
    assert _run("--missing", str(tmp_path / "m.txt")) == 1
    assert "--missing needs --questv2" in capsys.readouterr().err


def _cut(tmp_path: Path, keep: set[int]) -> Path:
    """The fixture cache with only the records in `keep` (a wiped or smaller cache of the same build)."""
    from wfj.io import wdb

    buf, out, off = FIXTURE.read_bytes(), [], wdb.HEADER_SIZE
    while True:
        qid, length = wdb.RECORD_HEADER.unpack_from(buf, off)
        if qid == 0 and length == 0:
            break
        if qid in keep:
            out.append(buf[off : off + 8 + length])
        off += 8 + length
    path = tmp_path / "smaller.wdb"
    path.write_bytes(buf[: wdb.HEADER_SIZE] + b"".join(out) + b"\0" * 8)
    return path


def test_a_smaller_cache_of_the_same_build_is_refused(tmp_path, monkeypatch, capsys):
    data = _data(tmp_path, monkeypatch)
    _seed(data)
    assert _run() == 0
    before = {p.name: p.read_bytes() for p in (data / "english" / "quest").iterdir()}
    small = _cut(tmp_path, {170, 490})  # drops 25, 172, 247, 498
    assert run(["english", "wdb", str(small), "--build", BUILD]) == 1
    err = capsys.readouterr().err
    assert "4 quest(s) with wdb@1.15.9.69722 English are not in smaller.wdb (25, 172, 247, 498" in err
    assert {p.name: p.read_bytes() for p in (data / "english" / "quest").iterdir()} == before
    # --allow-shrink is the explicit decision
    assert run(["english", "wdb", str(small), "--build", BUILD, "--allow-shrink"]) == 0
    assert "not in this cache: 4 (their English deleted, --allow-shrink)" in capsys.readouterr().out
    got = {(ln["id"], ln["field"]) for ln in Store(data, english=True).load("quest") if ln["src"] == SRC}
    assert {i for i, _ in got} == {170}


def test_a_cache_of_another_build_replaces_the_earlier_build(tmp_path, monkeypatch, capsys):
    data = _data(tmp_path, monkeypatch)
    _seed(data)
    store = Store(data, english=True)
    store.save("quest", [*store.load("quest"), _line(9999, "title", "An Era-only quest", "wdb@1.15.8.12345")])
    assert _run() == 0  # 1.15.9.69722: the earlier build's quest 9999 is not refused
    assert "quests with earlier wdb English not in this cache: 1 (earlier build; they fall back to pfQuest)" in (
        capsys.readouterr().out
    )


def test_dry_run_checks_everything_and_writes_nothing(tmp_path, monkeypatch, capsys):
    data = _data(tmp_path, monkeypatch)
    _seed(data)
    before = {p.name: p.read_bytes() for p in (data / "english" / "quest").iterdir()}
    questv2 = tmp_path / "QuestV2.csv"
    questv2.write_text("ID,UniqueBitFlag\n25,1\n137,2\n")
    missing = tmp_path / "missing.txt"
    assert _run("--dry-run", "--questv2", str(questv2), "--missing", str(missing)) == 0
    assert "[dry run: nothing written]" in capsys.readouterr().out
    assert {p.name: p.read_bytes() for p in (data / "english" / "quest").iterdir()} == before
    assert not missing.exists()
    assert _run("--dry-run", build="1.15.9.1") == 1  # the build check runs in a dry run too


def test_area_and_objective_texts(tmp_path, monkeypatch, capsys):
    """The area description as type `area` / field `text` keyed by the quest id (no
    quest `area` line); each objective's own text as `objective`, keyed by its QuestObjective id."""
    data = _data(tmp_path, monkeypatch)
    _seed(data)
    assert _run() == 0
    out = capsys.readouterr().out
    eng = Store(data, english=True)
    assert not any(ln["field"] == "area" for ln in eng.load("quest"))
    area = {ln["id"]: ln for ln in eng.load("area")}
    en = "Scout the gazebo on Mystral Lake that overlooks the nearby Alliance outpost."
    assert area[25] == {"id": 25, "field": "text", "en": en, "hash": key(normalize_v1(en)), "src": SRC}
    assert all(validate_line("area", ln, english=True) == [] for ln in area.values())
    objectives = {ln["id"]: ln for ln in eng.load("objective")}
    assert {i: ln["en"] for i, ln in objectives.items()} == {381177: "Rescue Drull", 381178: "Rescue Tog'thar"}
    for ln in objectives.values():
        assert ln["field"] == "text" and ln["src"] == SRC and ln["hash"] == key(normalize_v1(ln["en"]))
        assert validate_line("objective", ln, english=True) == []
    assert "english objective (wdb@1.15.9.69722): 2 objective texts" in out
    assert "area              0       0      1" in out


def _record_498() -> tuple[bytes, int, bytearray]:
    """The fixture file, the byte offset of quest 498's record and a copy of its payload (two objective texts)."""
    from wfj.io import wdb

    buf, off = FIXTURE.read_bytes(), wdb.HEADER_SIZE
    while True:
        qid, length = wdb.RECORD_HEADER.unpack_from(buf, off)
        if qid == 498:
            return buf, off, bytearray(buf[off + 8 : off + 8 + length])
        off += 8 + length


def test_an_objective_cached_under_two_quests_is_an_error(tmp_path, monkeypatch, capsys):
    from wfj.io import wdb

    data = _data(tmp_path, monkeypatch)
    buf, _, record = _record_498()
    record[0:4] = (99498).to_bytes(4, "little")  # the same record under another quest id
    twin = tmp_path / "twin.wdb"
    body = buf[: len(buf) - 8] + wdb.RECORD_HEADER.pack(99498, len(record)) + bytes(record) + b"\0" * 8
    twin.write_bytes(body)
    assert run(["english", "wdb", str(twin), "--build", BUILD]) == 1
    assert "objective 381177 is cached under two quests" in capsys.readouterr().err
    assert not (data / "english" / "objective").exists()
    # the dry run the Makefile's wdb-preflight runs before any import step stops on it too
    assert run(["english", "wdb", str(twin), "--build", BUILD, "--dry-run"]) == 1


def _patched_498(tmp_path: Path, at: int, value: bytes) -> Path:
    buf, off, record = _record_498()
    record[at : at + len(value)] = value
    path = tmp_path / "patched.wdb"
    path.write_bytes(buf[: off + 8] + bytes(record) + buf[off + 8 + len(record) :])
    return path


def test_objective_text_must_be_utf8_and_keyed(tmp_path, monkeypatch, capsys):
    """Kept strict: a bad objective text or a text under QuestObjective id 0 stops the import (and
    so wdb-preflight, before any store is written), naming the quest and the objective."""
    from wfj.io import wdb

    data = _data(tmp_path, monkeypatch)
    first = wdb.layout_for(69722).objectives_at
    text_at = first + wdb.OBJECTIVE_SIZE
    for at, value, message in (
        (text_at, b"\xff", "quest 498: objective 0 text is not UTF-8"),
        (first, b"\0\0\0\0", "quest 498: objective 0 has text but QuestObjective id 0"),
    ):
        path = _patched_498(tmp_path, at, value)
        assert run(["english", "wdb", str(path), "--build", BUILD, "--dry-run"]) == 1
        assert message in capsys.readouterr().err
    assert not (data / "english" / "objective").exists()


def test_a_blank_objective_text_under_id_0_is_not_an_error(tmp_path, monkeypatch):
    """Whitespace-only text is never written, so an id 0 beside it does not stop the preflight."""
    from wfj.io import wdb

    _data(tmp_path, monkeypatch)
    first = wdb.layout_for(69722).objectives_at
    buf, off, record = _record_498()
    record[first : first + 4] = b"\0\0\0\0"
    text_len = record[first + wdb.OBJECTIVE_FIXED]  # the inner list is empty on this build
    start = first + wdb.OBJECTIVE_SIZE
    record[start : start + text_len] = b" " * text_len
    path = tmp_path / "blank.wdb"
    path.write_bytes(buf[: off + 8] + bytes(record) + buf[off + 8 + len(record) :])
    assert run(["english", "wdb", str(path), "--build", BUILD, "--dry-run"]) == 0


def test_read_ids_answers_without_decoding_a_payload(tmp_path):
    """The rescan list must be derivable from a cache whose payload layout is not decoded yet; the
    Forever build's case. `read_ids` walks the framing only, so it answers where `read_quests` refuses."""
    build, ids = read_ids(FIXTURE)
    assert build == 69722
    known = read_quests(FIXTURE)
    assert ids == sorted([q.id for q in known.quests] + known.placeholders)  # placeholders included: cached

    # the same file with one payload replaced by bytes no layout explains
    buf = bytearray(FIXTURE.read_bytes())
    qid, length = struct.unpack_from("<II", buf, 24)
    buf[32 : 32 + length] = struct.pack("<I", qid) + bytes(length - 4)
    broken = tmp_path / "questcache.wdb"
    broken.write_bytes(bytes(buf))
    with pytest.raises(WdbError, match=f"quest {qid}"):
        read_quests(broken)
    assert read_ids(broken) == (build, ids)


def test_read_ids_reports_a_broken_frame(tmp_path):
    buf = bytearray(FIXTURE.read_bytes())
    struct.pack_into("<I", buf, 28, len(buf))  # a record longer than the file
    bad = tmp_path / "questcache.wdb"
    bad.write_bytes(bytes(buf))
    with pytest.raises(WdbError, match="runs past the end"):
        read_ids(bad)
    with pytest.raises(WdbError, match="not a quest cache"):
        read_ids(_write(tmp_path / "x.wdb", b"NOPE" + bytes(32)))


def _write(path: Path, data: bytes) -> Path:
    path.write_bytes(data)
    return path


FOREVER = Path(__file__).resolve().parents[1] / "fixtures" / "wdb-forever" / "questcache.wdb"
FOREVER_BUILD = "1.60.1.69913"


def test_imports_the_forever_cache_and_its_conditional_text(tmp_path, monkeypatch, capsys):
    """The Forever build imports through the same path, and the conditional description it carries becomes
    keyed English (the empty entry of quest 94978 writes nothing)."""
    data = _data(tmp_path, monkeypatch)
    assert run(["english", "wdb", str(FOREVER), "--build", FOREVER_BUILD]) == 0
    out = capsys.readouterr().out
    src = f"wdb@{FOREVER_BUILD}"
    assert f"english quest ({src}): 12 records · 11 quests · 1 placeholders dropped" in out
    assert f"english gossip ({src}): 1 keyed texts" in out
    text = next(t for q in read_quests(FOREVER).quests if q.id == 92596 for _, _, t in q.conditional)
    gossip = {ln["id"]: ln for ln in Store(data, english=True).load("gossip")}
    assert gossip[key(normalize_v1(text))]["en"] == text

    got = {(ln["id"], ln["field"]): ln for ln in Store(data, english=True).load("quest")}
    cache = {q.id: q for q in read_quests(FOREVER).quests}
    for qid, q in cache.items():
        for field in ("title", "objectives", "description"):
            text = getattr(q, field)
            assert ((qid, field) in got) == bool(text.strip())
            if text.strip():
                assert got[(qid, field)]["en"] == text and got[(qid, field)]["src"] == src
    assert got[(1665, "objectives")]["en"] == "Bring Bartleby's Mug to Burlguard"
    # the area description is type `area`, keyed by the quest id
    area = {ln["id"]: ln for ln in Store(data, english=True).load("area")}
    assert {qid for qid, q in cache.items() if q.area.strip()} == set(area)
    assert area[95771]["en"] == "Scout through the Fargodeep Mine" and area[95771]["src"] == src
    # no line anywhere carries the conditional variant
    assert not any("even for a mage such as yourself" in ln["en"] for ln in got.values())
    objectives = {ln["id"]: ln for ln in Store(data, english=True).load("objective")}
    assert objectives[478338]["en"] == "Listen to Elaadrin" and objectives[478338]["src"] == src


def test_the_wrong_build_for_the_forever_cache_is_refused(tmp_path, monkeypatch, capsys):
    _data(tmp_path, monkeypatch)
    assert run(["english", "wdb", str(FOREVER), "--build", BUILD]) == 1
    assert "questcache.wdb is build 69913" in capsys.readouterr().err


def test_union_keeps_the_earlier_builds_quests_a_newer_cache_never_served(tmp_path, monkeypatch, capsys):
    """Forever's server answers under a third of the quest ids Classic Era's did: content the beta
    has not enabled. A replace would drop those quests from Blizzard's own text back to pfQuest's; union
    keeps them at the build that served them."""
    data = _data(tmp_path, monkeypatch)
    assert _run() == 0  # the Classic Era cache first
    capsys.readouterr()
    era = {(ln["id"], ln["field"]): ln for ln in Store(data, english=True).load("quest")}
    era_objectives = {ln["id"]: ln for ln in Store(data, english=True).load("objective")}
    era_area = {ln["id"]: ln for ln in Store(data, english=True).load("area")}
    assert era_objectives and era_area and any(ln["src"] == SRC for ln in era.values())

    assert run(["english", "wdb", str(FOREVER), "--build", FOREVER_BUILD, "--merge", "union"]) == 0
    out = capsys.readouterr().out
    assert "kept at that build's src" in out
    now = {(ln["id"], ln["field"]): ln for ln in Store(data, english=True).load("quest")}

    forever = {q.id for q in read_quests(FOREVER).quests}
    kept = [k for k, ln in era.items() if ln["src"] == SRC and k[0] not in forever]
    assert kept, "the fixtures must share no quest ids for this to mean anything"
    for k in kept:
        assert now[k] == era[k]  # same text, same src: the older build still vouches for it
    # and where Forever does serve the quest, its text wins
    for qid, q in {q.id: q for q in read_quests(FOREVER).quests}.items():
        if q.title.strip():
            assert now[(qid, "title")]["src"] == f"wdb@{FOREVER_BUILD}"
            assert now[(qid, "title")]["en"] == q.title
    # objective lines follow the same rule
    objectives = {ln["id"]: ln for ln in Store(data, english=True).load("objective")}
    for oid, ln in era_objectives.items():
        if oid not in {o for q in read_quests(FOREVER).quests for o, _ in q.objective_texts}:
            assert objectives[oid] == ln
    # area lines follow their quest: kept where Forever did not answer it, Forever's where it did
    area = {ln["id"]: ln for ln in Store(data, english=True).load("area")}
    assert [qid for qid in era_area if qid not in forever]
    for qid, ln in era_area.items():
        if qid not in forever:
            assert area[qid] == ln
    for q in read_quests(FOREVER).quests:
        assert (q.id in area) == bool(q.area.strip())
        if q.area.strip():
            assert area[q.id]["src"] == f"wdb@{FOREVER_BUILD}" and area[q.id]["en"] == q.area


def test_replace_is_the_default_and_still_drops_the_earlier_build(tmp_path, monkeypatch, capsys):
    data = _data(tmp_path, monkeypatch)
    assert _run() == 0
    capsys.readouterr()
    era = {(ln["id"], ln["field"]) for ln in Store(data, english=True).load("quest")}
    assert run(["english", "wdb", str(FOREVER), "--build", FOREVER_BUILD]) == 0
    assert "they fall back to pfQuest" in capsys.readouterr().out
    now = {(ln["id"], ln["field"]) for ln in Store(data, english=True).load("quest")}
    forever = {q.id for q in read_quests(FOREVER).quests}
    assert any(k for k in era - now if k[0] not in forever)  # the earlier build's lines are gone
    # so are its area lines; only this cache's remain
    area = Store(data, english=True).load("area")
    assert area and {ln["src"] for ln in area} == {f"wdb@{FOREVER_BUILD}"}


def test_union_keeps_the_cache_over_pfquest_and_takes_an_answered_quest_whole():
    """pfQuest, imported first, never replaces an earlier build's cached line: a later union import
    restores only what its own cache holds. A quest the new cache answered keeps only the new
    cache's fields, because Forever reuses quest ids for different quests."""
    from wfj.cmd.import_english import merge_source

    def ln(id_, field, src, en="x"):
        return {"id": id_, "field": field, "en": en, "hash": "0" * 16, "src": src}

    era = [ln(1, "title", "wdb@1.15.9.69722", "Old One"), ln(1, "objectives", "wdb@1.15.9.69722", "Old obj"),
           ln(2, "title", "wdb@1.15.9.69722", "Kept Two")]
    after_pf = merge_source("quest", era, [ln(1, "title", "pfquest@x"), ln(2, "title", "pfquest@x"),
                                            ln(3, "title", "pfquest@x")], "pfquest", outranked_by=("wdb",))
    assert {(r["id"], r["field"], r["src"].split("@")[0]) for r in after_pf} == {
        (1, "title", "wdb"), (1, "objectives", "wdb"), (2, "title", "wdb"), (3, "title", "pfquest")}
    forever = [ln(1, "title", "wdb@1.60.1.69913", "New One")]  # quest 1 answered, no objectives any more
    merged = merge_source("quest", after_pf, forever, "wdb", True, answered={1})
    got = {(r["id"], r["field"]): r["src"] for r in merged}
    assert got[(1, "title")] == "wdb@1.60.1.69913"
    assert (1, "objectives") not in got                   # the answered quest is taken whole
    assert got[(2, "title")] == "wdb@1.15.9.69722"        # an unanswered quest keeps its older build
    assert got[(3, "title")] == "pfquest@x"


def test_under_union_pfquest_does_not_fill_a_field_the_answered_quest_left_empty():
    """Quest 5639 is answered on Forever with a title only. pfQuest (imported first) wrote its
    objectives and description; under union they are dropped, so a reused id never pairs an old quest's English
    with a new title."""
    from wfj.cmd.import_english import merge_source, take_answered_whole

    def ln(id_, field, src):
        return {"id": id_, "field": field, "en": "x", "hash": "0" * 16, "src": src}

    existing = [ln(5639, "objectives", "pfquest@x"), ln(5639, "description", "pfquest@x"),
                ln(5639, "completion", "vmangos@y"), ln(7, "objectives", "pfquest@x")]
    merged = merge_source("quest", existing, [ln(5639, "title", "wdb@1.60.1.69913")], "wdb", True, answered={5639})
    merged = take_answered_whole(merged, {5639})
    got = {(r["id"], r["field"]) for r in merged}
    assert got == {(5639, "title"), (5639, "completion"), (7, "objectives")}


def test_conditional_descriptions_and_completion_logs_are_keyed_text():
    """A quest's conditional description and its completion log line become keyed English (gossip, by the hash
    of the text): the client shows them with no id the addon can read. Keyed English is additive."""
    from types import SimpleNamespace

    import pytest as _pytest

    from wfj.cmd.import_english import _add_keyed, _wdb_keyed_lines

    quests = [
        SimpleNamespace(conditional=((137888, 3595, "You are born kaldorei, druid."), (0, 0, "")),
                        completion_log="Speak with Deathguard Billmuth at Tyr's Watch."),
        SimpleNamespace(conditional=(), completion_log=""),
    ]
    lines = _wdb_keyed_lines(SimpleNamespace(quests=quests), SRC)
    assert sorted(ln["en"] for ln in lines) == [
        "Speak with Deathguard Billmuth at Tyr's Watch.", "You are born kaldorei, druid."]
    for ln in lines:
        assert ln["id"] == ln["hash"] == key(normalize_v1(ln["en"])) and ln["src"] == SRC
        assert validate_line("gossip", ln, english=True) == []
    vm = english_line(lines[0]["id"], "text", lines[0]["en"], lines[0]["id"], "vmangos@13b49dc")
    merged, added = _add_keyed([vm], lines)
    assert added == 1 and merged[0] is vm  # a key another source has keeps its line
    clash = dict(vm, en="Other English")
    with _pytest.raises(ValueError, match="names two texts"):
        _add_keyed([clash], lines)
