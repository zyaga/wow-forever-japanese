"""The window test: the scan addon opens the client's windows and saves the English lines left on screen; these
read that file and hold the result to the baseline of lines a window may keep."""

import shutil
import subprocess

import pytest

from wfj.dev import client_surface

SAVED = """
WFJScanDB = {
["probe"] = {
["test"] = { ["started"] = "2026-11-17 17:00:00", ["finished"] = "2026-11-17 17:02:00", ["build"] = "70961",
  ["errors"] = { ["Interface/AddOns/X/y.lua:5: attempt to index a nil value"] = 3 },
  ["blocked"] = { ["ADDON_ACTION_BLOCKED WFJScan CastSpell()"] = 1 }, ["popups"] = { } },
["live"] = {
["(nothing open)"] = { ["english"] = { ["ChatFrame1Tab.Text"] = "General" }, ["japanese"] = 9 },
["spellbook"] = { ["english"] = { ["ChatFrame1Tab.Text"] = "General", ["Book.b0462b3b0.SubName"] = "Passive",
  ["Book.b0462b6d0.Name"] = "Frost" }, ["japanese"] = 14 },
["map"] = { ["english"] = { ["ChatFrame1Tab.Text"] = "General" }, ["japanese"] = 14 },
["spellbook > Book.TabSystem.b0462ad20"] = { ["english"] = { ["Book.Row.Name"] = "Frost" }, ["japanese"] = 3 },
},
["opened"] = {
["MailFrame"] = { ["still"] = { ["InboxPrevPageButton.b2fd54320"] = "Prev" }, ["fixed"] = 3, ["hidden"] = 0 },
["UIParent.b26511d00"] = { ["still"] = { ["x"] = "Traits" }, ["fixed"] = 0, ["hidden"] = 2 },
["BankFrame"] = { ["still"] = { }, ["fixed"] = 4, ["hidden"] = 1 },
},
},
}
"""


def test_the_saved_result_is_read_per_window_with_the_idle_screen_filed_once():
    info, found = client_surface.read_window_test(SAVED)
    assert info == {"started": "2026-11-17 17:00:00", "finished": "2026-11-17 17:02:00", "build": "70961"}
    assert found == {
        ("always on screen", "General"),  # on screen with nothing open: never counted against a window
        ("spellbook", "Passive"), ("spellbook", "Frost"),
        ("spellbook > Book.TabSystem.*", "Frost"),  # a page of the window, named by its tab
        ("opened MailFrame", "Prev"),
        ("opened UIParent.*", "Traits"),  # a pooled frame's address is not part of its name
    }


def test_a_file_with_no_probe_reads_as_nothing():
    assert client_surface.read_window_test("WFJScanDB = { }") == ({}, set())


def test_only_a_line_the_baseline_does_not_allow_is_new_and_a_line_no_longer_seen_is_listed():
    _, found = client_surface.read_window_test(SAVED)
    baseline = client_surface.read_window_baseline(
        "# a comment\n"
        "spellbook\tFrost\ta specialization's name\n"
        "always on screen\tGeneral\ta chat tab\n"
        "map\tShow:\tfixed since\n"
    )
    new, gone = client_surface.window_test_report(found, baseline)
    assert new == ["opened MailFrame\tPrev", "opened UIParent.*\tTraits", "spellbook\tPassive"]
    assert gone == ["map\tShow:"]


def test_a_baseline_line_needs_its_reason():
    with pytest.raises(ValueError, match="line 1"):
        client_surface.read_window_baseline("spellbook\tFrost\n")


def test_the_sweeps_refuse_to_run_with_translation_off():
    lua = client_surface.TEXT_LUA
    assert lua.count("if not japaneseOn() then return end") == 2 and "if not japaneseOn() or InCombatLockdown()" in lua


def test_every_committed_baseline_parses_and_gives_each_line_a_reason(root):
    paths = [p for p in (root / "pipeline/ui_window_baseline.txt", root / "retail/pipeline/ui_window_baseline.txt")
             if p.exists()]
    assert paths
    for path in paths:
        rows = client_surface.read_window_baseline(path.read_text(encoding="utf-8"))
        assert all(reason for reason in rows.values()), path


def test_the_load_walk_waits_for_the_test_on_a_played_client():
    manifest = {"entries": [{"kind": "global", "name": "Foo", "surface": "foo", "lod": ["Blizzard_Foo"]}]}
    at_login = client_surface.probe_lua(manifest, walk=True, english=["Back"])
    on_test = client_surface.probe_lua(manifest, walk=True, english=["Back"], at_login=False)
    assert "local AT_LOGIN = true" in at_login and "local AT_LOGIN = false" in on_test
    assert "if not started and AT_LOGIN then" in on_test
    # the test loads the windows' addons itself, before it opens anything
    assert on_test.index('db.test.part = "load"') < on_test.index('db.test.part = "live"')
    assert "WFJScanWalk(function()" in on_test


def test_translated_english_lists_lines_whose_japanese_differs(tmp_path):
    (tmp_path / "ui").mkdir()
    (tmp_path / "english/ui").mkdir(parents=True)
    (tmp_path / "ui/a.jsonl").write_text(
        '{"id": "BACK", "ja": "戻る"}\n{"id": "NEW", "ja": "NEW"}\n', encoding="utf-8")
    (tmp_path / "english/ui/a.jsonl").write_text(
        '{"id": "BACK", "en": "Back"}\n{"id": "NEW", "en": "NEW"}\n{"id": "NONE", "en": "No Japanese"}\n',
        encoding="utf-8")
    # a line with no Japanese is English by design; it is the missing-translation list's job, not this one's
    assert client_surface.translated_english(tmp_path) == ["Back"]


LOG = """
WFJ_Log = {
["errors"] = {
{ ["first"] = "2026-11-17 16:00:00", ["last"] = "2026-11-17 16:30:00", ["msg"] = "old.lua:1: before the run", ["n"] = 2 },
{ ["first"] = "2026-11-17 16:00:00", ["last"] = "2026-11-17 17:01:00", ["msg"] = "ButtonText.lua:59: bad argument", ["n"] = 17 },
},
["entries"] = {
{ ["at"] = "2026-11-17 16:59:00", ["kind"] = "init", ["msg"] = "early", ["err"] = "before the run" },
{ ["at"] = "2026-11-17 17:00:30", ["kind"] = "init", ["msg"] = "loadondemand.X", ["err"] = "ScrollBox.lua:595: nil" },
{ ["at"] = "2026-11-17 17:01:00", ["kind"] = "memory", ["msg"] = "sample" },
},
}
"""


def test_the_runs_errors_are_the_scan_addons_counts_and_the_addons_own_log_since_it_started():
    assert client_surface.read_test_problems(SAVED, LOG) == [
        "addon error x17: ButtonText.lua:59: bad argument",
        "addon load step failed: loadondemand.X: ScrollBox.lua:595: nil",
        "error x3: Interface/AddOns/X/y.lua:5: attempt to index a nil value",
        "refused x1: ADDON_ACTION_BLOCKED WFJScan CastSpell()",
    ]
    assert client_surface.read_test_problems("WFJScanDB = { }") == []


def test_the_test_records_errors_and_refused_actions_and_puts_confirmations_away():
    lua = client_surface.TEXT_LUA
    assert "seterrorhandler(shown)" in lua and "ADDON_ACTION_FORBIDDEN" in lua  # recorded, then the handler put back
    assert 'if kind ~= "Button" then return nil, "a checkbox" end' in lua  # a checkbox is never clicked
    assert "if putAway() then" in lua
    for word in ("buy", "delete", "send", "abandon", "cast", "talent", "merchant"):
        assert f'"{word}"' in lua, word  # a button that acts is left alone


def test_the_sweep_clicks_every_entry_of_a_reused_list_once_and_nothing_that_acts(root, tmp_path):
    """The generated sweep, run against a stand-in window: a category list drawn with a few reused rows, one
    category open at a time, more entries than fit; three tabs; a Delete button, a checkbox and a button outside
    the window, each of which raises when clicked."""
    lua = shutil.which("luajit") or shutil.which("lua5.1") or shutil.which("lua")
    if lua is None:
        pytest.skip("no Lua interpreter")
    head, tail = (root / "tests/fixtures/window_test_sim.lua").read_text(encoding="utf-8").split("--[[SWEEP]]\n")
    sweep = client_surface.TEXT_LUA % '  ["Back"] = true,'
    script = tmp_path / "sim.lua"
    script.write_text(head + sweep[sweep.index("-- The text sweep."):] + tail, encoding="utf-8")
    out = subprocess.run([lua, str(script)], capture_output=True, text=True, timeout=120)
    assert out.returncode == 0, out.stderr
    lines = out.stdout.strip().splitlines()
    assert lines[-1] == "clicked 19 | twice:  | missed:", lines[-1]
    clicked = [ln.split("=", 1)[1] for ln in lines if "=" in ln and not ln.startswith("clicked")]
    assert clicked == [
        "Tab 2", "Tab 3",  # the pages first; the page in front is not clicked again
        "Summary", "Characters", "Quests", "Eastern Kingdoms", "Kalimdor", "Outland",  # a category, then its own
        "Exploration", "Azeroth", "Draenor", "Housing", "Delves", "Player vs. Player", "Arena", "Battlegrounds",
        "Dungeons & Raids", "Professions", "Reputation",  # the rows below the fold, reached by scrolling
    ]


def test_the_tabs_run_clicks_page_switchers_only():
    lua = client_surface.TEXT_LUA
    assert 'pagesOnly = how == "tabs"' in lua and "if not pagesOnly then" in lua
    assert 'clicks = pagesOnly and "tabs" or "all"' in lua  # the saved run says which kind it was
