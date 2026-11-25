"""The Anki add-on reads the game's saved file as the client writes it, and never fails on a bad one."""

from anki_addon import FIXTURES

from wfj_anki import savedvars

SAVED = FIXTURES / "WoWForeverJapanese.lua"


def test_reads_the_table_the_client_wrote():
    table = savedvars.read(SAVED, "WFJ_Anki")
    assert table["schema"] == 1
    assert table["written"] == 1790000000
    assert table["voice"] is True
    rows = table["rows"]
    assert [r["key"] for r in rows] == ["quest.description:456:生き物", "gossip:0123456789abcdef:狩る"]
    first = rows[0]
    assert first["sentenceFurigana"] == "少しの<b>生[い]き 物[もの]</b>たちを狩れ。"
    assert first["questId"] == 456
    assert first["ratio"] == -0.5
    assert first["audio"] == ["WoWForeverJapanese_VoiceA/Sound/a-1.mp3", "WoWForeverJapanese_VoiceA/Sound/a-2.mp3"]
    assert rows[1]["audio"] == {}  # an empty table has no shape: the caller treats it as no files


def test_string_escapes_and_bytes_written_as_numbers():
    first = savedvars.read(SAVED, "WFJ_Anki")["rows"][0]
    assert first["meaning"] == "living\\thing\nline \u2014 dash"


def test_other_tables_in_the_file_are_read_by_their_own_name():
    assert savedvars.read(SAVED, "WFJ_DB") == {"schema": 3, "note": 'a } brace and "quotes" -- not a comment'}
    assert savedvars.read(SAVED, "WFJ_Study") == {"schema": 1}


def test_a_missing_file_or_table_gives_nothing(tmp_path):
    assert savedvars.read(tmp_path / "none.lua", "WFJ_Anki") is None
    assert savedvars.read(SAVED, "WFJ_Nothing") is None


def test_a_damaged_file_gives_nothing_and_never_raises(tmp_path):
    whole = SAVED.read_text(encoding="utf-8")
    start = whole.index("WFJ_Anki")
    for cut in (start + 12, start + 80, start + 200, len(whole) - 40):
        path = tmp_path / "cut.lua"
        path.write_text(whole[:cut], encoding="utf-8")
        assert savedvars.read(path, "WFJ_Anki") is None
    assert savedvars.parse("WFJ_Anki = function() end", "WFJ_Anki") is None
    assert savedvars.parse("WFJ_Anki = " + "{" * 5000, "WFJ_Anki") is None
    binary = tmp_path / "bin.lua"
    binary.write_bytes(b"WFJ_Anki = {\xff\xfe\x00")
    assert savedvars.read(binary, "WFJ_Anki") is None


def test_keys_without_brackets_and_number_keys():
    text = 'T = { a = 1, [2] = "two", [1] = "one", ["b"] = { 1, 2, 3 }, c = false, d = nil, e = 0x10, f = 1e3 }'
    assert savedvars.parse(text, "T") == {"a": 1, 2: "two", 1: "one", "b": [1, 2, 3], "c": False, "d": None,
                                          "e": 16, "f": 1000.0}
    assert savedvars.parse('T = { [1] = "one", [2] = "two" }', "T") == ["one", "two"]
