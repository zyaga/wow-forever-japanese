"""Interface strings seen in chat: the collector kind that holds a string's name and no text, its way through
a dump file and a send string, and the tracked list the import writes."""

import re
from pathlib import Path

import pytest
from test_collector_dump import dump, entry
from test_collector_send import body, pack
from test_collector_send import entry as packed

from wfj.cmd import collector
from wfj.cmd.import_ import run as import_run
from wfj.io import ui_keys_seen, wago
from wfj.io.collector_dump import UiKey, check_entry, read_dump
from wfj.io.collector_send import _table, decode

NAME = "DRUNK_MESSAGE_OTHER1"
BUILD = "1.60.1.71037"
_EXCLUDED = re.compile(r"^([A-Z][A-Z0-9_]*)\s+#\s+\S")


def ui_key(name=NAME, *, b=1, k=None, more="") -> str:
    """A `uikey` entry as the client writes it into the saved file."""
    return f'["{k or "uikey:" + name}"] = {{ ["t"] = "uikey", ["i"] = "{name}", ["b"] = {b},{more} }},'


def _data_dir(tmp_path: Path, monkeypatch) -> Path:
    (tmp_path / "data").mkdir()
    (tmp_path / "data" / "SCHEMA").write_text("1\n")
    monkeypatch.chdir(tmp_path)
    return tmp_path / "data"


def test_a_dump_file_gives_the_names_apart_from_the_english():
    d = read_dump(dump(entry("quest", 7, "title", "A Fine Day"), ui_key(), ui_key("AAA_FIRST"), builds=f'"{BUILD}",\n'))
    assert [(en.type_, en.id_) for en in d.entries] == [("quest", 7)]
    assert d.ui_keys == [UiKey("AAA_FIRST", BUILD), UiKey(NAME, BUILD)]
    assert not d.rejected


@pytest.mark.parametrize(
    ("text", "why"),
    [
        (ui_key("lower_case"), "bad_id"),
        (ui_key("Rex seems to be sobering up."), "bad_id"),
        (ui_key("A" * 129), "bad_id"),
        (ui_key(k="uikey:OTHER_NAME"), "bad_key"),
        (ui_key(k=f"uikey:{NAME}:text"), "bad_key"),
        (ui_key(more=' ["e"] = "Rex seems to be sobering up.",'), "bad_field"),
        (ui_key(more=' ["h"] = "0123456789abcdef",'), "bad_field"),
        (ui_key(more=' ["f"] = "text",'), "bad_field"),
        (ui_key(more=' ["p"] = "Warrior|Human",'), "bad_field"),
        (ui_key(more=' ["n"] = { 5 },'), "bad_field"),
        (ui_key(b=9), "no_build"),
    ],
)
def test_an_entry_with_a_bad_name_or_any_text_on_it_is_left_out(text, why):
    d = read_dump(dump(text))
    assert d.ui_keys == [] and d.entries == [] and d.rejected == {why: 1}


def test_a_send_string_carries_the_names():
    send = decode(pack(
        [packed("quest", 2, "title", "A title"), {"t": "uikey", "i": NAME, "b": 1},
         {"t": "uikey", "i": "Rex seems to be sobering up.", "b": 1},
         {"t": "uikey", "i": "WITH_TEXT", "b": 1, "e": "Rex seems to be sobering up."}],
        [BUILD],
    ))
    assert [(en.type_, en.id_) for en in send.dump.entries] == [("quest", 2)]
    assert send.dump.ui_keys == [UiKey(NAME, BUILD)]
    assert send.dump.rejected == {"bad_id": 1, "bad_field": 1}


def test_a_name_packed_twice_is_dropped_like_any_duplicate():
    send = decode(pack([{"t": "uikey", "i": NAME, "b": 1}, {"t": "uikey", "i": NAME, "b": 1}], [BUILD]))
    assert send.dump.ui_keys == [] and send.dump.rejected == {"duplicate_key": 2}


def test_a_reader_that_does_not_know_the_kind_leaves_the_entry_out():
    """The line check is what a pipeline from before this kind runs on every entry: it finds no key it can
    build from the entry and rejects it, never reading the name as an id or as text."""
    found, why = check_entry(f"uikey:{NAME}", _table({"t": "uikey", "i": NAME, "b": 1}), [BUILD])
    assert found is None and why == "bad_key"


def test_the_check_counts_the_names_and_never_prints_one():
    ok, text = collector.summary(body(pack([{"t": "uikey", "i": NAME, "b": 1}], [BUILD])))
    assert ok and "**This send reads.**" in text
    assert "| Entries | 0 |" in text and "| interface string names | 1 |" in text and BUILD in text
    assert NAME not in text


def test_the_import_writes_the_names_to_the_tracked_list(tmp_path: Path, monkeypatch, capsys):
    _data_dir(tmp_path, monkeypatch)
    saved = tmp_path / "WoWForeverJapanese.lua"
    saved.write_text(dump(ui_key(), ui_key("AAA_FIRST"), builds=f'"{BUILD}",\n'), encoding="utf-8")
    assert import_run(["english", "collector", str(saved)]) == 0
    out = capsys.readouterr().out
    assert "interface strings seen in chat: 2 added (pipeline/ui_keys_seen_in_chat.txt)" in out
    path = tmp_path / ui_keys_seen.PATH
    text = path.read_text(encoding="utf-8")
    assert text == ui_keys_seen.HEADER + f"AAA_FIRST\n{NAME}\n"
    assert not (tmp_path / "data" / "english").exists()  # a name is no English line

    # a send with one known name and one new one: only the new one is added, the list stays sorted
    issue = tmp_path / "body.txt"
    issue.write_text(body(pack([{"t": "uikey", "i": NAME, "b": 1}, {"t": "uikey", "i": "BBB_SECOND", "b": 1}], [BUILD])))
    assert collector.run(["intake", "--file", str(issue), "--number", "7"]) == 0
    out = capsys.readouterr().out
    assert "interface strings seen in chat: 1 added" in out and "  BBB_SECOND" in out
    assert path.read_text(encoding="utf-8") == ui_keys_seen.HEADER + f"AAA_FIRST\nBBB_SECOND\n{NAME}\n"
    before = path.stat().st_mtime_ns
    assert collector.run(["intake", "--file", str(issue), "--number", "7"]) == 0  # again: nothing written
    assert path.stat().st_mtime_ns == before


def test_merge_keeps_a_hand_edited_header_and_refuses_what_is_no_name(tmp_path: Path):
    path = tmp_path / "list.txt"
    path.write_text("# my header\n\nZZZ_LAST\n", encoding="utf-8")
    assert ui_keys_seen.merge(path, ["MMM_MID", "ZZZ_LAST", "Rex seems to be sobering up.", "lower"]) == ["MMM_MID"]
    assert path.read_text(encoding="utf-8") == "# my header\nMMM_MID\nZZZ_LAST\n"


def test_every_name_seen_in_chat_is_translated_or_excluded(root):
    """The tracked list: a name the game wrote into chat untranslated is either in the dictionary or left out
    with a reason. A name in neither is a chat line nobody decided about."""
    path = root / ui_keys_seen.PATH
    text = path.read_text(encoding="utf-8")
    assert text.startswith("#"), "the list has lost its header"
    _, names = ui_keys_seen.read(path)
    assert names == sorted(set(names)), "the list is one name per line, sorted, none twice"
    assert all(ui_keys_seen.UI_KEY_NAME.fullmatch(n) for n in names)
    keys = set(wago.read_keys(root / "pipeline/ui_keys.txt"))
    excluded = set()
    for raw in (root / "pipeline/ui_exclusions.txt").read_text(encoding="utf-8").splitlines():
        m = _EXCLUDED.match(raw)
        if m:
            excluded.add(m.group(1))
    undecided = [n for n in names if n not in keys and n not in excluded]
    assert undecided == [], (
        f"seen in chat but neither in ui_keys.txt nor in ui_exclusions.txt: {undecided[:20]}"
    )


def test_the_check_fails_on_a_name_nobody_decided_about(root, tmp_path: Path):
    """The same check over a list that holds a name in neither file."""
    path = tmp_path / "list.txt"
    ui_keys_seen.merge(path, ["A_NAME_NOBODY_LISTED_ANYWHERE"])
    _, names = ui_keys_seen.read(path)
    keys = set(wago.read_keys(root / "pipeline/ui_keys.txt"))
    excluded = (root / "pipeline/ui_exclusions.txt").read_text(encoding="utf-8")
    assert [n for n in names if n not in keys and not re.search(rf"^{n}\s+#", excluded, re.M)] == names
