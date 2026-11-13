"""Each speaking creature's display id, shipped so the voice panel draws a head without the client's creature
cache (data/voice/displays.jsonl → Data/Displays.lua)."""

import json

import pytest
from wfj.cmd import generate, voice_displays
from wfj.emit import lua_writer

VM = "vmangos@13b49dc"


def rows(who, caches, vm, old=(), today="2026-11-13"):
    return voice_displays.display_rows(set(who), caches, vm, VM, list(old), today)


def test_the_client_cache_beats_vmangos_and_the_newest_cache_wins():
    caches = [(70888, {1: [11], 2: [21]}), (70938, {1: [12]})]
    vm = {1: [10], 2: [20], 3: [30]}
    got = rows({1, 2, 3}, caches, vm)
    assert [(r["creature"], r["display"], r["provenance"]["source"]) for r in got] == [
        (1, 12, "creaturecache@70938"),
        (2, 21, "creaturecache@70888"),
        (3, 30, VM),
    ]
    assert all(r["provenance"]["imported"] == "2026-11-13" for r in got)


def test_a_creature_with_no_display_anywhere_has_no_row_and_only_speakers_get_rows():
    got = rows({1, 2}, [(70938, {9: [90]})], {1: [10]})
    assert [r["creature"] for r in got] == [1]


def test_the_first_model_of_several_is_the_one_shipped():
    assert rows({1}, [(70938, {1: [7729, 7730]})], {})[0]["display"] == 7729


def test_an_unchanged_row_keeps_its_date_and_a_changed_one_gets_today():
    old = [
        {"creature": 1, "display": 12, "provenance": {"source": "creaturecache@70938", "imported": "2026-11-01"}},
        {"creature": 2, "display": 20, "provenance": {"source": VM, "imported": "2026-11-01"}},
    ]
    got = {r["creature"]: r for r in rows({1, 2}, [(70938, {1: [12], 2: [22]})], {2: [20]}, old)}
    assert got[1]["provenance"]["imported"] == "2026-11-01"
    assert got[2]["provenance"] == {"source": "creaturecache@70938", "imported": "2026-11-13"}
    assert got[2]["display"] == 22


def test_a_row_no_source_holds_any_more_is_kept():
    old = [{"creature": 5, "display": 50, "provenance": {"source": "creaturecache@70888", "imported": "2026-11-01"}}]
    got = rows({5}, [], {}, old)
    assert got == old


def test_a_row_a_creature_cache_gave_is_never_replaced_by_vmangos():
    old = [{"creature": 5, "display": 51, "provenance": {"source": "creaturecache@70888", "imported": "2026-11-01"}}]
    assert rows({5}, [], {5: [50]}, old) == old


def test_a_cache_whose_build_is_not_pinned_is_left_out_and_the_rest_still_builds(root, tmp_path, monkeypatch, capsys):
    import struct

    data = tmp_path / "data"
    (data / "voice").mkdir(parents=True)
    (data / "voice" / "speakers.jsonl").write_text(json.dumps({"key": "1-description", "speaker": 6119}) + "\n",
                                                   encoding="utf-8")
    caches = tmp_path / "creatures"
    caches.mkdir()
    good = (root / "tests/fixtures/wdb-creature/creaturecache-70938.wdb").read_bytes()
    (caches / "70938.wdb").write_bytes(good)
    unpinned = bytearray(good)
    struct.pack_into("<I", unpinned, 4, 99999)
    (caches / "99999.wdb").write_bytes(bytes(unpinned))
    monkeypatch.setattr(voice_displays, "data_root", lambda: data)
    monkeypatch.setattr(voice_displays.vmangos, "read_creatures", lambda db, who: {})
    assert voice_displays.run(["--creatures", str(caches), "--vmangos", "db", "--commit", "13b49dc"]) == 0
    assert "99999.wdb left out" in capsys.readouterr().err
    written = [json.loads(ln) for ln in (data / "voice" / "displays.jsonl").read_text("utf-8").splitlines()]
    assert [(r["creature"], r["provenance"]["source"]) for r in written] == [(6119, "creaturecache@70938")]


def test_a_missing_cache_folder_is_refused(tmp_path, monkeypatch):
    monkeypatch.setattr(voice_displays, "data_root", lambda: tmp_path)
    assert voice_displays.run(["--creatures", str(tmp_path / "nope"), "--vmangos", "db", "--commit", "x"]) == 1


def test_the_rows_are_sorted_by_creature():
    got = rows({30, 4, 200}, [], {30: [1], 4: [2], 200: [3]})
    assert [r["creature"] for r in got] == [4, 30, 200]


def test_the_command_reads_every_cache_in_the_folder(root, tmp_path, monkeypatch):
    data = tmp_path / "data"
    (data / "voice").mkdir(parents=True)
    (data / "voice" / "speakers.jsonl").write_text(
        "".join(json.dumps(r) + "\n" for r in [
            {"key": "1-description", "speaker": 6119},
            {"key": "2-description", "speaker": 8419, "others": [1291]},
            {"key": "3-description", "speaker": "narrator"},
        ]), encoding="utf-8")
    caches = tmp_path / "creatures"
    caches.mkdir()
    (caches / "70938.wdb").write_bytes((root / "tests/fixtures/wdb-creature/creaturecache-70938.wdb").read_bytes())
    monkeypatch.setattr(voice_displays, "data_root", lambda: data)
    monkeypatch.setattr(voice_displays.vmangos, "read_creatures", lambda db, who: {})
    assert voice_displays.run(["--creatures", str(caches), "--vmangos", "db", "--commit", "13b49dc"]) == 0
    written = [json.loads(ln) for ln in (data / "voice" / "displays.jsonl").read_text("utf-8").splitlines()]
    assert [(r["creature"], r["display"]) for r in written] == [(1291, 1439), (6119, 4864), (8419, 7729)]


def test_the_displays_are_one_lua_table_by_creature():
    rows_ = [{"creature": 6119, "display": 4864}, {"creature": 1291, "display": 1439}]
    assert lua_writer.displays_text(rows_) == "\n".join([
        lua_writer.HEADER.format(src="data/"),
        "local _, WFJ = ...",
        "WFJ.Data.displays = {",
        "  [1291] = 1439,",
        "  [6119] = 4864,",
        "}",
    ]) + "\n"


def test_the_committed_displays_ship_after_the_error_recordings(root, planned):
    written = [json.loads(ln) for ln in (root / "data/voice/displays.jsonl").read_text("utf-8").splitlines()]
    text = planned["Data/Displays.lua"]
    assert written and all(f"  [{r['creature']}] = {r['display']}," in text for r in written)
    assert generate.toc_files(planned)[:4] == [
        "Data/Meta.lua", "Data/Vectors.lua", "Data/ErrorSounds.lua", "Data/Displays.lua"]


@pytest.mark.parametrize("row, why", [
    ({"creature": "6119", "display": 1}, "needs an integer creature and display"),
    ({"creature": 2, "display": 0}, "needs an integer creature and display"),
    ({"creature": 2, "display": 1.5}, "needs an integer creature and display"),
    ({"creature": 1, "display": 3}, "a second row for creature 1"),
])
def test_a_bad_or_repeated_displays_row_is_refused(row, why):
    with pytest.raises(ValueError, match=why):
        generate._check_displays([{"creature": 1, "display": 2}, row])
