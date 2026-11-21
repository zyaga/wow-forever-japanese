"""The window test: the scan addon opens the client's windows and saves the English lines left on screen; these
read that file and hold the result to the baseline of lines a window may keep."""

import argparse
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
    sweep = client_surface.TEXT_LUA % ('  ["Back"] = true,', '  "BACK",', "  [5] = 2,")
    script = tmp_path / "sim.lua"
    script.write_text(head + sweep[sweep.index("-- The text sweep."):] + tail, encoding="utf-8")
    out = subprocess.run([lua, str(script)], check=False, capture_output=True, text=True, timeout=120)
    assert out.returncode == 0, out.stderr
    lines = out.stdout.strip().splitlines()
    assert lines[-1] == "clicked 19 | twice:  | missed:", lines[-1]
    assert "list left at 0" in lines  # the list the run scrolled is back at its first row
    # Japanese in the client's face is written down (a label, a typing box, an HTML paragraph); Japanese in the
    # bundled face and English in any face are not
    assert [ln for ln in lines if ln.startswith("boxed ")] == [
        "boxed FakeFrame.Html | Fonts\\FRIZQT__.TTF",
        "boxed FakeFrame.Motd.Label | Fonts\\FRIZQT__.TTF",
        "boxed FakeFrame.NoteBox | Fonts\\FRIZQT__.TTF",
    ]
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


def test_a_pooled_frames_address_is_recognised_whatever_it_starts_with():
    pooled = client_surface._POOLED
    for name in ("ScrollTarget.b0462b3b0.Text", "ScrollTarget.c765a8010.Button", "ScrollTarget.9914c3950"):
        assert "*" in pooled.sub("*", name), name
    assert pooled.sub("*", "CalendarDayButton10 Deadbeefed Facade") == "CalendarDayButton10 Deadbeefed Facade"


def test_the_sweep_never_clicks_an_icon_a_party_button_or_another_addons_bag():
    lua = client_surface.TEXT_LUA
    assert 'return nil, "an icon with no words"' in lua
    for word in ("party", "raid", "friendslist", "communitieslist", "baganator"):
        assert f'"{word}"' in lua, word
    for window in ("EditMode", "BarberShop", "PetBattle"):
        assert f'"{window}"' in lua, window  # the open sweep leaves these closed


def test_a_window_that_did_not_open_is_a_line_of_the_result():
    saved = """
WFJScanDB = {
["probe"] = {
["live"] = {
["(nothing open)"] = { ["japanese"] = 3, ["english"] = { } },
["group finder"] = { ["japanese"] = 3, ["english"] = { } },
},
["test"] = {
["finished"] = "2026-11-18 10:00:30",
["started"] = "2026-11-18 10:00:00",
["build"] = "70961",
["unopened"] = { ["group finder"] = "the toggle opened nothing" },
},
},
}
"""
    _info, found = client_surface.read_window_test(saved)
    assert ("group finder", client_surface.NOT_OPENED) in found
    new, _gone = client_surface.window_test_report(found, {})
    assert new == ["group finder\t(did not open)"]  # fails the check until the baseline says why
    allowed = {("group finder", client_surface.NOT_OPENED): "the test character is below the level it needs"}
    assert client_surface.window_test_report(found, allowed)[0] == []


def test_a_sweep_started_again_ends_the_finished_run_and_one_test_runs_at_a_time():
    lua = client_surface.TEXT_LUA
    assert lua.count("db.test.finished = nil") == 2  # the live sweep and the open sweep
    assert 'print("WFJ test: already running")' in lua and "testRunning = false" in lua
    assert '"[live] click: "' in lua  # a click that raises is counted, not passed over


def test_the_sweep_never_answers_an_invitation_or_sends_a_query():
    lua = client_surface.TEXT_LUA
    for word in ("tentative", "ok", "select", "continue", "who", "calendarview", "whoframe", "guildcontrol"):
        assert f'"{word}"' in lua, word


BOXED = """
WFJScanDB = {
["probe"] = {
["test"] = { ["started"] = "2026-11-18 11:00:00", ["finished"] = "2026-11-18 11:01:00", ["build"] = "70959" },
["live"] = {
["(nothing open)"] = { ["english"] = { }, ["japanese"] = 2, ["boxes"] = { ["Hud.Line"] = "Fonts\\\\ARIALN.TTF" } },
["guild"] = { ["english"] = { }, ["japanese"] = 9,
  ["boxes"] = { ["Hud.Line"] = "Fonts\\\\ARIALN.TTF", ["CommunitiesFrame.Info.MOTD"] = "Fonts\\\\FRIZQT__.TTF" } },
["guild > CommunitiesFrame.RosterTab"] = { ["english"] = { }, ["japanese"] = 4,
  ["boxes"] = { ["ScrollTarget.b0462b3b0.Note"] = "Fonts\\\\FRIZQT__.TTF" } },
},
},
}
"""


def test_japanese_in_a_font_without_it_is_a_line_of_the_result():
    _info, found = client_surface.read_window_test(BOXED)
    boxes = client_surface.BOXES
    assert found == {
        ("always on screen", f"{boxes} Hud.Line"),  # on screen with nothing open: filed once
        ("guild", f"{boxes} CommunitiesFrame.Info.MOTD"),
        ("guild > CommunitiesFrame.RosterTab", f"{boxes} ScrollTarget.*.Note"),  # a pooled row, without its address
    }
    new, _gone = client_surface.window_test_report(found, {})
    assert len(new) == 3  # each fails the check until it is fixed or the baseline says why
    allowed = {("guild", f"{boxes} CommunitiesFrame.Info.MOTD"): "a reason"}
    assert f"guild\t{boxes} CommunitiesFrame.Info.MOTD" not in client_surface.window_test_report(found, allowed)[0]


def test_the_sweeps_face_is_the_addons_bundled_face(root):
    font = (root / "addon/WoWForeverJapanese/UI/Font.lua").read_text(encoding="utf-8")
    face = client_surface.JAPANESE_FACE
    assert f'\\\\Fonts\\\\{face}.ttf"' in font  # Font.PATH names the file the sweep takes as able to draw Japanese
    assert f'local JAPANESE_FACE = "{face}"' in client_surface.TEXT_LUA
    # the bytes are written as Lua escapes: kana and kanji lead bytes, never the characters Python would make of them
    assert 'text:find("[\\227-\\233\\239]")' in client_surface.TEXT_LUA


def test_a_warning_is_a_problem_and_a_run_that_could_not_watch_for_errors_says_so():
    saved = """
WFJScanDB = {
["probe"] = {
["test"] = { ["started"] = "2026-11-18 12:10:34", ["finished"] = "2026-11-18 12:11:11", ["build"] = "70959",
  ["errors"] = { }, ["blocked"] = { }, ["handler"] = "another addon keeps the error handler",
  ["warnings"] = { ["[load] a frame was shown while it may not be"] = 2 } },
},
}
"""
    assert client_surface.read_test_problems(saved) == [
        "errors not watched: another addon keeps the error handler",
        "warning x2: [load] a frame was shown while it may not be",
    ]
    lua = client_surface.TEXT_LUA
    assert 'watcher:RegisterEvent("LUA_WARNING")' in lua
    assert "if geterrorhandler() ~= grab then" in lua


def test_a_character_in_no_guild_fails_the_guild_pages_instead_of_passing_them():
    lua = client_surface.TEXT_LUA
    assert 'db.test.unopened["guild pages"] = "this character is in no guild"' in lua
    saved = """
WFJScanDB = {
["probe"] = {
["live"] = { ["(nothing open)"] = { ["english"] = { } }, ["guild"] = { ["english"] = { } } },
["test"] = { ["started"] = "a", ["finished"] = "b", ["build"] = "70959",
  ["unopened"] = { ["guild pages"] = "this character is in no guild" } },
},
}
"""
    _info, found = client_surface.read_window_test(saved)
    assert client_surface.window_test_report(found, {})[0] == ["guild pages\t(did not open)"]


def test_the_test_shows_no_window_bare_and_reads_the_error_catchers_list():
    lua = client_surface.TEXT_LUA
    run = lua[lua.index("SlashCmdList.WFJTEST = function(how)"):]
    assert "WFJScanOpenSweep" not in run  # a window shown bare errors on the character the test runs on
    assert "SlashCmdList.WFJOPEN = WFJScanOpenSweep" in lua  # still there to run alone
    assert "db.opened = nil" in run  # an earlier run's bare-window list is not read as this run's
    assert "grabber:GetDB()" in run and "readGrabbed()" in run
    # what the run added: the counter after, less the counter before it started
    assert '(tonumber(e.counter) or 1) - (before[tostring(e.message)] or 0)' in run
    saved = """
WFJScanDB = {
["probe"] = {
["test"] = { ["started"] = "a", ["finished"] = "b", ["build"] = "70959", ["blocked"] = { },
  ["errors"] = { ["[grabbed] TutorialFrame.lua:338: Usage: GetPrevCompleatedTutorial @ [TutorialFrame.lua]:338"] = 6 } },
},
}
"""
    assert client_surface.read_test_problems(saved) == [
        "error x6: [grabbed] TutorialFrame.lua:338: Usage: GetPrevCompleatedTutorial @ [TutorialFrame.lua]:338"]


def test_the_character_window_is_read_while_the_player_has_it_open_and_never_opened_or_closed():
    lua = client_surface.TEXT_LUA
    assert "ToggleCharacter" not in lua  # opened by an addon, its show script raises an error every time
    run = lua[lua.index("SlashCmdList.WFJTEST = function(how)"):]
    # the test closes windows as it goes: it does not start with this one open
    assert 'print("WFJ test: close the character window first, then run it again")' in run
    assert "WFJScanCharacterRead(function()" in run
    # asked in chat and mid-screen, and again until it opens: a reload before this step leaves the run unfinished
    assert "UIErrorsFrame:AddMessage(ASK" in lua and "sinceAsk >= CHARACTER_ASK" in lua
    assert 'db.live["character"] = record' in lua  # every page the player showed, read while it was open
    saved = """
WFJScanDB = {
["probe"] = {
["live"] = { ["(nothing open)"] = { ["english"] = { } },
  ["character"] = { ["english"] = { ["PaperDollFrame.Title"] = "Reputation" }, ["japanese"] = 30, ["boxes"] = { } } },
["test"] = { ["started"] = "a", ["finished"] = "b", ["build"] = "70959" },
},
}
"""
    assert client_surface.read_window_test(saved)[1] == {("character", "Reputation")}
    not_opened = saved.replace('["build"] = "70959"', '["build"] = "70959", ["unopened"] = { ["character"] = "not opened" }')
    assert ("character", client_surface.NOT_OPENED) in client_surface.read_window_test(not_opened)[1]
    # what was read is kept from the first read, and a reload with the window still open ends the run
    step = lua[lua.index("local function WFJScanCharacterRead(done)"):lua.index("SLASH_WFJTEST1")]
    assert step.index('db.live["character"] = record') < step.index("readScreen()")
    assert 'characterReader:RegisterEvent("PLAYER_LOGOUT")' in step
    # a run that stopped at this step is still read: the window nobody read is a line of it
    stopped = saved.replace('["finished"] = "b"', '["part"] = "character"').replace('["character"] = {', '["x"] = {')
    assert ("character", client_surface.NOT_OPENED) in client_surface.read_window_test(stopped)[1]


def test_a_window_this_client_does_not_have_is_named_and_not_failed():
    lua = client_surface.TEXT_LUA
    assert '{ "group finder", function() PVEFrame_ToggleFrame() end, "PVEFrame_ToggleFrame" }' in lua
    assert "if LIVE[at][3] and _G[LIVE[at][3]] == nil then" in lua and "db.test.absent" in lua


def test_closed_windows_are_read_without_being_shown_and_listed_to_read():
    lua = client_surface.TEXT_LUA
    read = lua[lua.index("local function WFJScanClosedRead(done)"):lua.index("local characterReader")]
    assert ":Show(" not in read and ":Click(" not in read  # nothing is shown or clicked
    assert "not tested[top]" in read  # a window the live sweep opened was judged open
    saved = """
WFJScanDB = {
["probe"] = {
["closed"] = { ["MailFrame"] = { ["InboxPrevPageButton.b2fd54320.Text"] = "Prev" },
  ["UIParent.b26511d00"] = { ["x"] = "Traits" } },
["test"] = { ["started"] = "a", ["finished"] = "b", ["build"] = "70959" },
},
}
"""
    _info, found = client_surface.read_window_test(saved)
    assert found == {("closed MailFrame", "Prev"), ("closed UIParent.*", "Traits")}


def _friends(counts: str) -> str:
    head = 'WFJScanDB = {\n["probe"] = {\n["test"] = { ["started"] = "a", ["finished"] = "b", ["build"] = "70959", '
    return head + '["friends"] = { ' + counts + " } },\n},\n}\n"


def test_a_friends_window_that_lost_its_friends_fails_the_run_though_nothing_errored():
    lua = client_surface.TEXT_LUA
    assert "db.test.friends = friendsDrawn(roots)" in lua
    empty = _friends('["battlenet"] = 14, ["game"] = 2, ["listed"] = 0, ["drawn"] = 0')
    assert client_surface.read_test_problems(empty) == [
        "friends list is empty: the client counts 16 friends and the window drew none "
        "({'battlenet': 14, 'game': 2, 'listed': 0, 'drawn': 0})"]
    full = _friends('["battlenet"] = 14, ["game"] = 2, ["listed"] = 18, ["drawn"] = 9')
    assert client_surface.read_test_problems(full) == []
    nobody = _friends('["battlenet"] = 0, ["game"] = 0, ["listed"] = 0, ["drawn"] = 0')
    assert client_surface.read_test_problems(nobody) == []  # a character with no friends has an empty list
    # a count the client keeps from addon code is never read as zero
    unread = _friends('["battlenet"] = "secret", ["game"] = "secret", ["listed"] = 0, ["drawn"] = 0')
    assert client_surface.read_test_problems(unread)[0].startswith("friends list not checked:")


def test_the_test_lists_the_dictionary_strings_the_client_does_not_hand_to_addons(tmp_path):
    # the addon matches a line on screen by the English it reads from the client's own string: a string the client
    # keeps from addon code can be matched by nothing, and no window sweep sees why the line stayed English
    (tmp_path / "ui").mkdir()
    (tmp_path / "ui" / "ui-T.jsonl").write_text(
        '{"id": "TOOLTIP_ITEM_STAT_MANA_REGEN_INCREASE", "field": "text", "ja": "x"}\n'
        '{"id": "AchievementTitle:1", "field": "text", "ja": "y"}\n{"id": "BACK", "field": "text", "ja": ""}\n',
        encoding="utf-8")
    assert client_surface.translated_keys(tmp_path) == ["TOOLTIP_ITEM_STAT_MANA_REGEN_INCREASE"]
    lua = client_surface.probe_lua({"entries": []}, walk=True, english=["Back"], keys=["B_KEY", "A_KEY"])
    assert 'local KEYS = {\n  "A_KEY",\n  "B_KEY",\n}' in lua
    run = lua[lua.index("SlashCmdList.WFJTEST = function(how)"):]
    assert 'if type(_G[key]) ~= "string" then missing[#missing + 1] = key end' in run
    assert run.index("db.test.strings = { asked = #KEYS, missing = missing }") < run.index("WFJScanWalk(function()")
    saved = """
WFJScanDB = {
["probe"] = {
["test"] = { ["started"] = "a", ["finished"] = "b", ["build"] = "70959",
  ["strings"] = { ["asked"] = 3, ["missing"] = { "TOOLTIP_ITEM_STAT_B", "TOOLTIP_ITEM_STAT_A", } } },
},
}
"""
    assert client_surface.read_missing_strings(saved) == (3, ["TOOLTIP_ITEM_STAT_A", "TOOLTIP_ITEM_STAT_B"])
    assert client_surface.read_missing_strings("WFJScanDB = {\n}\n") == (0, [])




def test_the_saved_runs_build_is_held_to_the_clients(tmp_path, capsys):
    """A result saved before the client updated is a run of the build before: the reader finds the client's
    build beside the saved file and says so."""
    install = tmp_path / "World of Warcraft"
    saved = install / "_forever_" / "WTF" / "Account" / "A" / "SavedVariables" / "WFJScan.lua"
    saved.parent.mkdir(parents=True)
    saved.write_text("WFJScanDB = {}\n", encoding="utf-8")
    assert client_surface.client_build_beside(saved) is None  # no .build.info: nothing to compare with
    (install / ".build.info").write_text(
        "Product!STRING:0|Version!STRING:0|Build Key!HEX:16|Active!DEC:1\n"
        "wowf|1.60.1.70959|abcd|1\nwow|12.1.5.70783|ef01|1\n", encoding="utf-8")
    assert client_surface.client_build_beside(saved) == "70959"
    assert client_surface.client_build_beside(tmp_path / "elsewhere" / "WFJScan.lua") is None
    # a finished run of the build before fails the read, whatever it found
    saved.write_text(
        'WFJScanDB = {\n["probe"] = {\n["live"] = { ["(nothing open)"] = { ["english"] = { } } },\n'
        '["test"] = { ["started"] = "a", ["finished"] = "b", ["build"] = "70938" },\n},\n}\n', encoding="utf-8")
    args = argparse.Namespace(saved=saved, baseline=tmp_path / "none.txt", log=None)
    assert client_surface._texts(args) == 2
    assert "is of build 70938 and the client is on 70959 now" in capsys.readouterr().out


TOOLTIPS = """
WFJScanDB = {
["probe"] = {
["test"] = { ["started"] = "2026-11-21 17:00:00", ["finished"] = "2026-11-21 17:05:00", ["build"] = "70959" },
["novoice"] = { ["quests"] = 3, ["said"] = 2, ["pack"] = true, ["listed"] = 40,
  ["wrong"] = { ["783"] = "says it has no voice, and the voice pack does not list it" } },
["tooltips"] = { ["read"] = 120, ["japanese"] = 110, ["unread"] = 4, ["items"] = 9,
  ["wrong"] = { ["408498"] = "3 numbers in the Japanese, 4 on this client" },
  ["changed"] = { ["17"] = "2 numbers in the Japanese, 3 on this client" },
  ["folded"] = { ["279845"] = "one Japanese paragraph over 2 lines" } },
},
}
"""


def test_the_tooltip_read_fails_on_moved_numbers_and_a_line_written_over_and_lists_what_the_game_changed():
    tooltips = client_surface.read_tooltips(TOOLTIPS)
    assert tooltips == {
        "read": 120, "japanese": 110, "unread": 4, "items": 9, "refused": "",
        "wrong": [("408498", "3 numbers in the Japanese, 4 on this client")],
        "changed": [("17", "2 numbers in the Japanese, 3 on this client")],
        "folded": [("279845", "one Japanese paragraph over 2 lines")],
    }
    # a spell left English because the game changed it is a list to draft from, never a failure
    assert client_surface.tooltip_problems(tooltips) == [
        "tooltip numbers in the wrong places: spell 408498 (3 numbers in the Japanese, 4 on this client)",
        "tooltip lines written over: item 279845 (one Japanese paragraph over 2 lines)",
    ]


def test_a_run_that_read_no_tooltip_fails_instead_of_passing():
    assert client_surface.read_tooltips(SAVED) is None
    assert client_surface.tooltip_problems(None)[0].startswith("tooltips not read: this run's test addon")
    clean = {"read": 0, "japanese": 0, "unread": 9, "items": 0, "refused": "", "wrong": [], "changed": [],
             "folded": []}
    assert client_surface.tooltip_problems(clean) == ["tooltips not read: no spell tooltip could be read"]
    assert client_surface.tooltip_problems({**clean, "refused": "items: boom"}) == ["tooltips not read: items: boom"]
    assert client_surface.tooltip_problems({**clean, "read": 5}) == []


def test_the_result_command_fails_a_run_with_a_tooltip_problem_and_prints_what_changed(tmp_path, capsys):
    saved = tmp_path / "WFJScan.lua"
    saved.write_text(TOOLTIPS, encoding="utf-8")
    args = argparse.Namespace(saved=saved, baseline=tmp_path / "none.txt", log=None)
    assert client_surface._texts(args) == 1
    out = capsys.readouterr().out
    assert "tooltips: 120 spells read (110 in Japanese, 4 the client had not loaded), 9 items; 1 spells left" in out
    assert "read  changed spell\t17\t2 numbers in the Japanese, 3 on this client" in out
    assert "ERROR tooltip numbers in the wrong places: spell 408498" in out
    assert "no-voice message: 3 quests read in the quest log, 2 said they have no voice; voice pack loaded, 40" in out
    assert "ERROR no-voice message: quest 783 says it has no voice, and the voice pack does not list it" in out
    fine = TOOLTIPS.replace('["408498"] = "3 numbers in the Japanese, 4 on this client"', "").replace(
        '["279845"] = "one Japanese paragraph over 2 lines"', "").replace(
        '["783"] = "says it has no voice, and the voice pack does not list it"', "")
    saved.write_text(fine, encoding="utf-8")
    assert client_surface._texts(args) == 0


def test_the_test_addon_carries_each_filled_spells_count_and_reads_tooltips_after_the_closed_windows(root):
    counts = client_surface.spell_value_counts(root / "data")
    assert len(counts) > 10000 and all(n >= 0 for n in counts.values())
    lua = client_surface.probe_lua({"entries": []}, walk=True, english=["Friends"], keys=["FRIENDS"],
                                   values={5: 2, 3: 1})
    assert "local VALUES = {\n  [3] = 1,\n  [5] = 2,\n}" in lua
    # the count is read the way the addon reads a line's values, and a fight is waited out first
    assert 'if not (last and text:sub(last, s - 1) == " to ") then n = n + 1 end' in lua
    assert lua.index("WFJScanClosedRead(function()") < lua.index("outOfCombat(function() WFJScanTooltipRead(")
    assert lua.index("WFJScanTooltipRead(function()") < lua.index("WFJScanCharacterRead(function()\n")
    # a spell's text is asked for before its tooltip is read: asked cold, the client answers with nothing
    assert lua.index("pcall(load, ids[asking])") < lua.index("pcall(readSpell, record, ids[at], describe)")
    assert "if waited < TOOLTIP_SETTLE then" in lua
    # nothing is clicked or used: tooltips are only shown
    body = lua[lua.index("local function readItems"):lua.index("local function WFJScanTooltipRead")]
    assert "UseContainerItem" not in body and "PickupContainerItem" not in body and ":Click(" not in body


def test_the_no_voice_read_fails_on_a_wrong_message_and_on_a_log_with_no_quest():
    record = client_surface.read_no_voice(TOOLTIPS)
    assert record == {"quests": 3, "said": 2, "listed": 40, "pack": True, "refused": "",
                      "wrong": [("783", "says it has no voice, and the voice pack does not list it")]}
    assert client_surface.no_voice_problems(record) == [
        "no-voice message: quest 783 says it has no voice, and the voice pack does not list it"]
    assert client_surface.read_no_voice(SAVED) is None
    assert client_surface.no_voice_problems(None)[0].startswith("no-voice message not read: this run's test addon")
    empty = {**record, "quests": 0, "wrong": []}
    assert client_surface.no_voice_problems(empty) == [
        "no-voice message not read: the quest log holds no quest (take one, then run it again)"]
    assert client_surface.no_voice_problems({**empty, "refused": "boom"}) == ["no-voice message not read: boom"]
    assert client_surface.no_voice_problems({**empty, "quests": 2}) == []


def test_the_no_voice_read_keeps_the_voice_entrys_own_list_and_shows_quests_the_clients_way():
    lua = client_surface.probe_lua({"entries": []}, walk=True, english=["Friends"], keys=["FRIENDS"])
    # the list is taken as the addon is handed it, so the read holds the pane to the same lines
    assert 'hooksecurefunc("WoWForeverJapanese_VoiceNotMade", function(list)' in lua
    assert "pcall(QuestMapFrame_ShowQuestDetails, quests[at])" in lua
    assert 'listedNoVoice[showing .. "-description"] == true' in lua
    assert lua.index("WFJScanTooltipRead(function()") < lua.index("outOfCombat(function() WFJScanNoVoiceRead(")
    assert lua.index("WFJScanNoVoiceRead(function()") < lua.index("WFJScanCharacterRead(function()\n")
    body = lua[lua.index("local function WFJScanNoVoiceRead"):lua.index("-- The character window, opened by")]
    assert "AbandonQuest" not in body and "SetAbandonQuest" not in body and ":Click(" not in body
