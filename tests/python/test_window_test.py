"""The window test: the scan addon opens the client's windows and saves the English lines left on screen; these
read that file and hold the result to the baseline of lines a window may keep."""

import argparse
import re
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

def _parts(lua: str) -> list[str]:
    """The window test's parts in run order, as `/wfjtest` builds them: each part's name with the read it calls."""
    run = lua[lua.index("SlashCmdList.WFJTEST = function(how)"):]
    table = run[run.index("local parts = {"):run.index("local byName = {}")]
    return [f"{name} {call}" for name, call in
            re.findall(r'\{ "(\w+)", function\(nxt\).*?(WFJScan\w+)', table, re.S)]


def _before(lua: str, first: str, then: str) -> bool:
    """Whether the part that calls `first` runs before the part that calls `then`."""
    calls = [p.split(" ")[1] for p in _parts(lua)]
    return calls.index(first) < calls.index(then)



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
    assert _before(on_test, "WFJScanWalk", "WFJScanLiveSweep")
    # a run of the live part alone loads the windows' addons first too
    assert '{ "live", function(nxt) outOfCombat(function() WFJScanLiveSweep(nxt) end) end, needs = "walk" }' in on_test


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
    assert "db.live[name] = record" in lua  # every page the player showed, read while it was open
    assert 'playerRead("character", characterShown,' in lua and 'playerRead("guild", guildShown,' in lua
    assert "ToggleGuildFrame" not in lua  # the guild window is never opened or paged by the test
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
    step = lua[lua.index("local function playerRead(name, shown, ASK, done)"):lua.index("SLASH_WFJTEST1")]
    assert step.index("db.live[name] = record") < step.index("readScreen()")
    assert 'characterReader:RegisterEvent("PLAYER_LOGOUT")' in step
    # a run that stopped at this step is still read: the window nobody read is a line of it
    stopped = saved.replace('["finished"] = "b"', '["part"] = "character"').replace('["character"] = {', '["x"] = {')
    assert ("character", client_surface.NOT_OPENED) in client_surface.read_window_test(stopped)[1]
    # and one that stopped a step earlier, waiting for the guild window, names both windows nobody read
    at_guild = stopped.replace('["part"] = "character"', '["part"] = "guild"')
    read = client_surface.read_window_test(at_guild)[1]
    assert ("guild", client_surface.NOT_OPENED) in read and ("character", client_surface.NOT_OPENED) in read
    # the raid window's own code errors outside a raid once it is loaded: the walk that loaded it takes the two
    # events that raise it off the raid window
    walk = client_surface.probe_lua({"entries": []}, walk=True, english=["Friends"], keys=["FRIENDS"])
    assert 'if addon == "Blizzard_RaidUI" and type(RaidFrame) == "table" and not IsInRaid() then' in walk
    assert 'RaidFrame:UnregisterEvent("UNIT_PET")' in walk and 'RaidFrame:UnregisterEvent("UNIT_NAME_UPDATE")' in walk


def test_a_window_this_client_does_not_have_is_named_and_not_failed():
    lua = client_surface.TEXT_LUA
    assert '{ "dungeon journal", function() ToggleEncounterJournal() end, "ToggleEncounterJournal" }' in lua
    assert "if LIVE[at][3] and _G[LIVE[at][3]] == nil then" in lua and "db.test.absent" in lua


def test_forevers_own_group_finder_is_opened_page_by_page_the_clients_way(root):
    lua = client_surface.TEXT_LUA
    # Forever loads the vanilla-style group finder, not the one PVEFrame_ToggleFrame opens
    assert "PVEFrame_ToggleFrame" not in lua
    for page, name in ((1, "group finder"), (2, "group finder > browse"), (3, "group finder > who")):
        assert f'{{ "{name}", groupFinder({page}), "GroupFinderVanillaStyle_LoadUI" }}' in lua
    assert "LFGVanilla_ToggleFrame(page)" in lua
    # a listing that is up is never taken down: its Back button unlists it, and the Delist button too
    assert "C_LFGList.HasActiveEntryInfo()" in lua and 'name:find("^LFGListing")' in lua
    assert "ACT.delist, ACT.unlist = true, true" in lua
    baseline = client_surface.read_window_baseline((root / "pipeline/ui_window_baseline.txt").read_text("utf-8"))
    assert ("group finder", client_surface.NOT_OPENED) not in baseline
    assert ("dungeon journal", client_surface.NOT_OPENED) in baseline  # blizzard_encounterjournal is not on Forever


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
    assert run.index("db.test.strings = { asked = #KEYS, missing = missing }") < run.index("WFJScanWalk(nxt)")
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


# a hover read that pointed at frames and found no English
HOVERED = '["hover"] = { ["friends"] = { ["made"] = 4, ["found"] = 4, ["tips"] = 3, ["english"] = { }, ["runs"] = { } } },'

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
        "read": 120, "japanese": 110, "unread": 4, "items": 9, "marked": 0, "refused": "", "load": {}, "why": {},
        "wrong": [("408498", "3 numbers in the Japanese, 4 on this client")],
        "changed": [("17", "2 numbers in the Japanese, 3 on this client")],
        "folded": [("279845", "one Japanese paragraph over 2 lines")],
        "reported": {},
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
    # most of the spells read is a run that looked; fewer than it could not read is one that did not
    assert client_surface.tooltip_problems({**clean, "read": 10}) == []
    assert client_surface.tooltip_problems({**clean, "read": 5})[0].startswith("tooltips not read: only 5 of 14")


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
    # a run saved by a test addon from before the names read is told to install the current one
    assert "ERROR names not read: this run's test addon has no such read" in out
    # and one from before every row was read says its tooltips were judged by one row only
    assert "ERROR tooltip rows not read: this run's test addon reads the description row only" in out
    # and one from before the frozen tooltip read says so too
    assert "ERROR frozen tooltip not read: this run's test addon has no such read" in out
    # and one from before the chat tools read
    assert "ERROR chat tools not read: this run's test addon has no such read" in out
    # and one from before the bag click read
    assert "ERROR bag click not read: this run's test addon has no such read" in out
    fine = TOOLTIPS.replace('["408498"] = "3 numbers in the Japanese, 4 on this client"', "").replace(
        '["279845"] = "one Japanese paragraph over 2 lines"', "").replace(
        '["783"] = "says it has no voice, and the voice pack does not list it"', "").replace(
        '["tooltips"] = {', '["names"] = { ["on"] = true, ["rows"] = { { ["kind"] = "player", '
        '["english"] = "Reyn", ["shown"] = "Reyn" } } },\n["tooltips"] = {').replace(
        # every row of every tooltip read, and none of them English
        '["read"] = 120,', '["read"] = 120, ["rows"] = { ["tooltips"] = 120, ["kept"] = 0, ["english"] = { }, ["runs"] = { } }, ')
    # and every hovered frame's tooltip read, none of them English
    fine = fine.replace('["tooltips"] = {', HOVERED + '\n["tooltips"] = {', 1)
    fine = fine.replace('["tooltips"] = {', FROZE + '\n["tooltips"] = {', 1)
    fine = fine.replace('["tooltips"] = {', CHAT + '\n' + MARKS + '\n["tooltips"] = {', 1)
    # and the bag click read, with nothing tainted by the addon
    fine = fine.replace('["tooltips"] = {', BAGGED + '\n["tooltips"] = {', 1)
    saved.write_text(fine, encoding="utf-8")
    assert client_surface._texts(args) == 0
    out = capsys.readouterr().out
    assert "names: 1 read, 0 shown in Japanese" in out
    assert ("frozen tooltip: 3 item and 0 spell tooltips frozen, 4 Japanese lines copied, 4 word cards, "
            "0 lines with a word that takes none; key CTRL-F") in out


def test_a_word_on_a_frozen_tooltip_with_no_card_fails_the_run_and_a_particle_does_not():
    record = {"items": 1, "spells": 1, "lines": 3, "cards": 2, "bound": "", "expect": True, "refused": "",
              "missing": [], "stuck": [], "uncarded": [
                  ("items 6265", "part", "必要: ファースト・エイド (100)", "ファースト・エイド"),
                  ("items 7000", "part", "必要: ファースト・エイド (100)", "ファースト・エイド"),
                  ("spells 133", "none", "売値: 40", "売値"),
                  ("items 6265", "part", "体力を回復します。", "を"),
              ]}
    problems = client_surface.freeze_problems(record)
    words = [p for p in problems if p.startswith("frozen tooltip word without a card")]
    # each line once, a particle never
    assert len(words) == 2
    assert any("ファースト・エイド in '必要: ファースト・エイド (100)' (items 6265)" in p for p in words)
    assert any("(no card on the line): 売値" in p for p in words)


def test_the_test_addon_carries_each_filled_spells_count_and_reads_tooltips_after_the_closed_windows(root):
    counts = client_surface.spell_value_counts(root / "data")
    assert len(counts) > 10000 and all(n >= 0 for n in counts.values())
    lua = client_surface.probe_lua({"entries": []}, walk=True, english=["Friends"], keys=["FRIENDS"],
                                   values={5: 2, 3: 1})
    assert "local VALUES = {\n  [3] = 1,\n  [5] = 2,\n}" in lua
    # the count is read the way the addon reads a line's values, and a fight is waited out first
    assert 'if not (last and text:sub(last, s - 1) == " to ") then n = n + 1 end' in lua
    assert _before(lua, "WFJScanClosedRead", "WFJScanTooltipRead")
    assert "outOfCombat(function() WFJScanTooltipRead(nxt) end)" in lua
    # a spell is asked for, and read at the moment the client says its text is there: asked cold the client
    # answers with nothing, and it does not keep the text of thousands of spells asked at once
    assert 'if type(load) == "function" then pcall(load, id) end' in lua
    assert 'tooltipReader:RegisterEvent("SPELL_DATA_LOAD_RESULT")' in lua
    assert 'tooltipReader:RegisterEvent("SPELL_TEXT_UPDATE")' in lua
    assert 'settle(id, "onText")' in lua and 'settle(id, "onLoad")' in lua and 'settle(id, "late")' in lua
    assert "flight < TOOLTIP_FLIGHT" in lua
    # a read that reads nothing stops and says so, and a flagged spell is recorded with both of its texts
    assert 'record.refused = "stopped: none of the first "' in lua
    assert '" | live: " .. english:gsub("%s+", " "):sub(1, 220)' in lua
    # a row the addon left English wears the not-translated marker, whose words are Japanese: never counted as
    # shown in Japanese
    assert 'local marked = type(shown) == "string" and shown:find("Not Translated]", 1, true) ~= nil' in lua
    assert "if hasJapanese(shown) and not marked then" in lua
    # a name plate and a unit's tooltip under the mouse are not text of the window being read; any other
    # tooltip is the window's own and is still read
    assert 'if not name:find("^NamePlate%d") and not (unitTip and name:find("^GameTooltipText")) then' in lua
    assert "GameTooltip:IsShown() and GameTooltip:GetUnit()" in lua
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
    assert _before(lua, "WFJScanTooltipRead", "WFJScanNoVoiceRead")
    assert "outOfCombat(function() WFJScanNoVoiceRead(nxt) end)" in lua
    body = lua[lua.index("local function WFJScanNoVoiceRead"):lua.index("-- The character window, opened by")]
    assert "AbandonQuest" not in body and "SetAbandonQuest" not in body and ":Click(" not in body


NAMES = """
WFJScanDB = {
["probe"] = {
["test"] = { ["started"] = "2026-11-22 17:00:00", ["finished"] = "2026-11-22 17:05:00", ["build"] = "70959" },
["names"] = { ["on"] = true, ["rows"] = {
  { ["kind"] = "item", ["english"] = "Hearthstone", ["shown"] = "ハースストーン" },
  { ["kind"] = "item", ["english"] = "Worn Shortsword", ["shown"] = "Worn Shortsword" },
  { ["kind"] = "spell", ["english"] = "Unknown New Spell", ["shown"] = "Unknown New Spell" },
  { ["kind"] = "zone", ["english"] = "Elwynn Forest", ["shown"] = "エルウィン・フォレスト" },
  { ["kind"] = "player", ["english"] = "Thrall", ["shown"] = "スロール" },
  { ["kind"] = "unit", ["english"] = "Kobold Vermin", ["shown"] = "コボルド" },
} },
},
}
"""
JAPANESE = {"Hearthstone": "ハースストーン", "Worn Shortsword": "ウォーン・ショートソード",
            "Elwynn Forest": "エルウィン・フォレスト", "Thrall": "スロール", "Kobold Vermin": "コボルド・バーミン"}


def test_the_names_read_fails_on_a_name_left_english_a_wrong_japanese_and_a_players_name_changed():
    record = client_surface.read_names(NAMES)
    assert record["on"] is True and record["refused"] == "" and len(record["rows"]) == 6
    assert record["rows"][0] == ("item", "Hearthstone", "ハースストーン")
    assert client_surface.names_problems(record, JAPANESE) == [
        "name left English: item Worn Shortsword (its Japanese is ウォーン・ショートソード)",
        "name not as the name list spells it: unit Kobold Vermin shows コボルド, the list has コボルド・バーミン",
        "player's name changed: Thrall shows スロール",
    ]
    # a name the list has no line for stays the client's English: nothing to report
    assert not any("Unknown New Spell" in p for p in client_surface.names_problems(record, JAPANESE))


def test_the_names_read_says_why_it_proved_nothing():
    assert client_surface.read_names(TOOLTIPS) is None
    assert client_surface.names_problems(None, JAPANESE)[0].startswith("names not read: this run's test addon")
    off = {"on": False, "refused": "", "rows": []}
    assert client_surface.names_problems(off, JAPANESE) == [
        "names not read: Japanese names are off (/wfj intro, pick Japanese names, Confirm, then run it again)"]
    assert client_surface.names_problems({**off, "on": True}, JAPANESE) == [
        "names not read: nothing with a name could be read"]
    assert client_surface.names_problems({**off, "on": True, "refused": "boom"}, JAPANESE) == [
        "names not read: boom"]


def test_the_names_read_runs_after_the_no_voice_read_and_only_shows_tooltips():
    lua = client_surface.probe_lua({"entries": []}, walk=True, english=["Friends"], keys=["FRIENDS"])
    assert _before(lua, "WFJScanNoVoiceRead", "WFJScanNamesRead")
    assert "outOfCombat(function() WFJScanNamesRead(nxt) end)" in lua
    body = lua[lua.index("local function WFJScanNamesRead"):lua.index("-- The character window, opened by")]
    assert "UseContainerItem" not in body and "PickupContainerItem" not in body and ":Click(" not in body
    # a player's name and a name the client hides are never taken for a game name
    assert "UnitIsPlayer" in body and "readable(" in body
    # the names setting is read, never written: the run shows what this player sees
    assert 'settings["names.japanese"] == true' in lua and "names.japanese\"] =" not in body


# a word status read with nothing wrong
MARKS = ('["marks"] = { ["window"] = 9, ["frames"] = 3, ["shown"] = 14, ["expect"] = true, ["english"] = { }, '
         '["stale"] = { }, ["tags"] = { } },')


def test_the_word_status_read_opens_the_known_words_window_and_changes_no_status():
    lua = client_surface.probe_lua({"entries": []}, walk=True, english=["Friends"], keys=["FRIENDS"])
    assert _before(lua, "WFJScanChatRead", "WFJScanMarksRead")
    assert _before(lua, "WFJScanMarksRead", "WFJScanFreezeRead")
    body = lua[lua.index("local function WFJScanMarksRead"):lua.index("-- The chat tools read.")]
    # the addon's own command opens the window, and a window the player had open is left open
    assert body.count('slash("known")') == 1 and "if not wasOpen then slash(" in body
    assert "if not wasOpen then window:Hide() end" in body
    # it clicks nothing and imports nothing, so no status changes; no setting is written
    assert ":Click(" not in body and "GetScript(" not in body and "SetText(" not in body
    assert "saved[" not in body and "saved.enabled =" not in body
    # every frame that carries marks is looked at, never a forbidden one
    assert "EnumerateFrames(frame)" in body and "frame:IsForbidden()" in body


def test_the_word_status_read_fails_english_in_the_window_marks_left_behind_and_a_tag_that_is_no_percent():
    def run(record: str) -> list[str]:
        return client_surface.marks_problems(client_surface.read_marks(
            "WFJScanDB = {\n[\"probe\"] = {\n" + record + "\n},\n}\n"))

    assert run(MARKS) == []
    assert client_surface.marks_problems(None) == [
        "word status not read: this run's test addon has no such read (make scan-install, then run it again)"]
    assert run(MARKS.replace('["expect"] = true', '["expect"] = true, ["refused"] = "the known words window did '
                             'not open"')) == ["word status not read: the known words window did not open"]
    assert run(MARKS.replace('["window"] = 9', '["window"] = 0')) == ["known words window shows no text"]
    assert run(MARKS.replace('["english"] = { }', '["english"] = { "Known words" }')) == [
        "known words window left English: 'Known words'"]
    # English first shows the window in English: nothing to fail there
    assert run(MARKS.replace('["expect"] = true', '["expect"] = false')
               .replace('["english"] = { }', '["english"] = { "Known words" }')) == []
    assert run(MARKS.replace('["stale"] = { }', '["stale"] = { "questframe.detail" }')) == [
        "word status marks left on a text that is gone (questframe.detail)"]
    assert run(MARKS.replace('["tags"] = { }', '["tags"] = { "nil" }')) == [
        "score tag does not show a percent: 'nil'"]
    # a run with no marked text on screen is not a fault: a character with no quest open shows none
    assert run(MARKS.replace('["frames"] = 3, ["shown"] = 14', '["frames"] = 0, ["shown"] = 0')) == []


# a chat tools read with nothing wrong
CHAT = ('["chat"] = { ["topics"] = 9, ["phrases"] = 132, ["words"] = 12, ["expect"] = true, ["blank"] = { }, '
        '["copy"] = "WFJ テスト", '
        '["sizes"] = { "592x380" }, ["english"] = { } },')


def test_the_chat_tools_read_opens_the_addons_own_windows_and_never_types_into_chat():
    lua = client_surface.probe_lua({"entries": []}, walk=True, english=["Friends"], keys=["FRIENDS"])
    assert _before(lua, "WFJScanNamesRead", "WFJScanChatRead")
    assert _before(lua, "WFJScanChatRead", "WFJScanFreezeRead")
    body = lua[lua.index("local function WFJScanChatRead"):lua.index("local function WFJScanFreezeRead")]
    # the addon's own command opens and closes the card, then opens the words window
    assert body.count('slash("phrases")') == 2 and body.count('slash("chatwords")') == 1
    # a card the player had open is left open, and the copy box is opened by the copy icon's own handler
    assert "if not wasOpen then slash(" in body and 'icon:GetScript("OnClick")' in body
    # it never clicks a phrase, so nothing is typed into chat or sent
    assert ":Click(" not in body and "SendChatMessage" not in body and "Insert(" not in body
    # no setting is written: the run shows what this player sees
    assert "settings[" not in body and "settings.enabled =" not in body


def test_the_chat_tools_read_fails_a_blank_tab_a_card_that_changes_size_and_english_left_in_a_heading():
    def run(record: str) -> list[str]:
        return client_surface.chat_problems(client_surface.read_chat(
            "WFJScanDB = {\n[\"probe\"] = {\n" + record + "\n},\n}\n"))

    assert run(CHAT) == []
    assert client_surface.chat_problems(None) == [
        "chat tools not read: this run's test addon has no such read (make scan-install, then run it again)"]
    assert run(CHAT.replace('["expect"] = true', '["expect"] = true, ["refused"] = "the phrase card did not open"')) == [
        "chat tools not read: the phrase card did not open"]
    assert run(CHAT.replace('["topics"] = 9', '["topics"] = 0')) == [
        "phrase card has no topics"]
    assert run(CHAT.replace('["blank"] = { }', '["blank"] = { "tab combat\\tno words" }')) == [
        "phrase card: tab combat (no words)"]
    assert run(CHAT.replace('{ "592x380" }', '{ "592x380", "592x412" }')) == [
        "phrase card changes size between topics: 592x380, 592x412"]
    assert run(CHAT.replace('["english"] = { }', '["english"] = { "phrase card heading\\tPhrase book" }')) == [
        "chat tools left English: 'Phrase book' (phrase card heading)"]
    assert run(CHAT.replace('["expect"] = true', '["expect"] = true, ["stuck"] = true')) == [
        "phrase card did not close on its own command"]
    assert run(CHAT.replace('["expect"] = true',
                            '["expect"] = true, ["refusedWords"] = "the chat words window did not open"')) == [
        "chat words window not read: the chat words window did not open"]
    assert run(CHAT.replace('["words"] = 12', '["words"] = 0')) == [
        "chat words window shows no text"]
    assert run(CHAT.replace('["copy"] = "WFJ テスト"', '["refusedCopy"] = "the copy box did not open"')) == [
        "copy box not read: the copy box did not open"]
    assert run(CHAT.replace('"WFJ テスト"', '"|cffffffffWFJ テスト|r"')) == [
        "copy box holds '|cffffffffWFJ テスト|r', not the line without its codes ('WFJ テスト')"]


# a frozen tooltip read with nothing wrong
FROZE = ('["freeze"] = { ["items"] = 3, ["lines"] = 4, ["cards"] = 4, ["bound"] = "CTRL-F", ["expect"] = true, '
         '["missing"] = { }, ["stuck"] = { } },')


def test_the_frozen_tooltip_read_runs_last_and_presses_only_the_freeze_binding():
    lua = client_surface.probe_lua({"entries": []}, walk=True, english=["Friends"], keys=["FRIENDS"])
    assert _parts(lua)[-1] == "freeze WFJScanFreezeRead"
    assert "outOfCombat(function() WFJScanFreezeRead(nxt) end)" in lua
    body = lua[lua.index("local function WFJScanFreezeRead"):lua.index("-- The character window, opened by")]
    # it runs what the key runs, twice per tooltip, and never clicks or uses an item
    assert body.count("WFJ_FreezeTooltip()") == 2
    assert "UseContainerItem" not in body and "PickupContainerItem" not in body and ":Click(" not in body
    # no setting is written: the run shows what this player sees
    assert "settings[" not in body.replace('settings["readings.enabled"] ~= false', "")


def test_the_frozen_tooltip_read_fails_a_missing_line_a_copy_left_open_and_a_copy_with_no_cards():
    def run(record: str) -> list[str]:
        return client_surface.freeze_problems(client_surface.read_freeze(
            "WFJScanDB = {\n[\"probe\"] = {\n" + record + "\n},\n}\n"))

    assert run(FROZE) == []
    assert client_surface.freeze_problems(None) == [
        "frozen tooltip not read: this run's test addon has no such read (make scan-install, then run it again)"]
    assert run(FROZE.replace('["items"] = 3', '["items"] = 0')) == [
        "frozen tooltip not read: the character carries no item to freeze"]
    assert run(FROZE.replace('["missing"] = { }', '["missing"] = { ["6948"] = "1 of 4 lines not on the copy" }')) == [
        "frozen tooltip copy wrong: item 6948 (1 of 4 lines not on the copy)"]
    assert run(FROZE.replace('["stuck"] = { }', '["stuck"] = { ["6948"] = "left showing" }')) == [
        "frozen tooltip did not close: item 6948 (left showing)"]
    assert run(FROZE.replace('["cards"] = 4', '["cards"] = 0')) == [
        "frozen tooltip has no word cards: 4 Japanese lines copied, none took a card"]
    # with English showing or the reading box off no card is due
    assert run(FROZE.replace('["cards"] = 4', '["cards"] = 0').replace("true", "false")) == []


BAGGED = ('["bagclick"] = { ["checked"] = 412, ["ours"] = { }, '
          '["others"] = { ["ContainerFrame1.Items[2].bagID"] = "Baganator" } },')


def test_the_bag_click_read_runs_out_of_combat_before_the_freeze_and_never_uses_an_item():
    lua = client_surface.probe_lua({"entries": []}, walk=True, english=["Friends"], keys=["FRIENDS"])
    assert _before(lua, "WFJScanNamesRead", "WFJScanBagClickRead")
    assert _before(lua, "WFJScanBagClickRead", "WFJScanFreezeRead")
    assert "outOfCombat(function() WFJScanBagClickRead(nxt) end)" in lua
    body = lua[lua.index("local function WFJScanBagClickRead"):lua.index("-- The frozen tooltip read.")]
    assert "UseContainerItem" not in body and ":Click(" not in body and "PickupContainerItem" not in body
    # the interface is hidden and shown again, as Dialogue UI and Alt+Z do, the next frames are waited for so an
    # error they raise lands in the run, and the bags are left as they were
    assert body.index("SetUIVisibility(false)") < body.index("SetUIVisibility(true)") < body.index("C_Timer.After(")
    assert "OpenAllBags()" in body and "CloseAllBags()" in body
    # any bag item button on screen is pointed at, a bag addon's too, never found by a frame name alone
    assert "EnumerateFrames()" in body and "GetBagID" in body


def test_the_bag_click_read_lists_the_same_values_the_addon_watches():
    from pathlib import Path

    def names(text: str, table: str) -> list[str]:
        body = re.search(table + r" = \{(.*?)\}", text, re.S)
        assert body is not None, table
        return re.findall(r'"([^"]+)"', body.group(1))

    watch = (Path(__file__).resolve().parents[2] / "addon/WoWForeverJapanese/UI/TaintWatch.lua").read_text(
        encoding="utf-8")
    lua = client_surface.TEXT_LUA
    assert names(lua, "local BAG_CLICK_GLOBALS") == names(watch, "TaintWatch.BAG_CLICK_GLOBALS")
    assert names(lua, "local BAG_CLICK_MERCHANT") == names(watch, "TaintWatch.BAG_CLICK_MERCHANT")


def test_the_bag_click_read_fails_a_value_carrying_the_addons_taint_and_only_lists_another_addons():
    def saved(record: str) -> str:
        return "WFJScanDB = {\n[\"probe\"] = {\n" + record + "\n},\n}\n"

    def run(record: str) -> list[str]:
        return client_surface.bagclick_problems(client_surface.read_bagclick(saved(record)))

    assert run(BAGGED) == []
    read = client_surface.read_bagclick(saved(BAGGED))
    assert read is not None
    assert read["others"] == {"ContainerFrame1.Items[2].bagID": "Baganator"}
    assert client_surface.bagclick_problems(None) == [
        "bag click not read: this run's test addon has no such read (make scan-install, then run it again)"]
    tainted = BAGGED.replace(
        '["ours"] = { }', '["ours"] = { "after the interface came back\\tMerchantFrame.selectedTab" }')
    assert run(tainted) == [
        "bag click value tainted by the addon (after the interface came back): MerchantFrame.selectedTab"]
    refused = BAGGED.replace(
        '["others"]', '["refused"] = "the client has no SetUIVisibility or OpenAllBags", ["others"]')
    assert run(refused) == [
        "bag click read only as the run left it: the client has no SetUIVisibility or OpenAllBags"]
    # a run that reached no bag item never ran the path under test: it fails and says how far the frames got
    unreached = BAGGED.replace(
        '["others"]', '["skipped"] = { ["bagButtons"] = 858, ["shown"] = 8, ["badSlot"] = 3, ["empty"] = 5, '
        '["errors"] = 0 }, ["others"]')
    assert run(unreached) == [
        "bag click pointed at no bag item: badSlot 3, bagButtons 858, empty 5, errors 0, shown 8"]
    assert run(unreached.replace('["checked"] = 412', '["checked"] = 412, ["tooltips"] = 8')) == []
    lua = client_surface.probe_lua({"entries": []}, walk=True, english=["Friends"], keys=["FRIENDS"])
    body = lua[lua.index("local function WFJScanBagClickRead"):lua.index("-- The frozen tooltip read.")]
    # the bag addon's buttons are waited for, and a bag item's tooltip is shown whatever addon draws the bags
    assert "local ok, err = pcall(pointAndHide)" in body and "GameTooltip:SetBagItem(bag, slot)" in body
    # a fight that started during the wait leaves the interface alone, and the bags are closed again either way
    assert 'record.refused = "a fight started before the interface could be hidden and shown"' in body


def test_one_part_of_the_window_test_runs_alone_and_is_judged_alone(tmp_path):
    """`/wfjtest <part>` runs one part (with the part it needs), and `make window-test` judges that part and the
    errors of its run: the rest of the saved file is an earlier run's."""
    lua = client_surface.probe_lua({"entries": []}, walk=True, english=["Friends"], keys=["FRIENDS"])
    names = lua[lua.index('local TEST_PART_NAMES = "') + 25:].split('"', 1)[0].split(", ")
    assert names == [p.split(" ")[0] for p in _parts(lua)]
    run = lua[lua.index("SlashCmdList.WFJTEST = function(how)"):]
    assert 'print("WFJ test: no part named " .. section .. ". Parts: " .. TEST_PART_NAMES)' in run
    assert "code = WFJScanAddonCode, section = section }" in run
    # an earlier run's failing freeze record is not this run's
    bad_freeze = FROZE.replace('["cards"] = 4', '["cards"] = 0')
    saved = "WFJScanDB = {\n[\"probe\"] = {\n" + bad_freeze + "\n" + BAGGED + "\n},\n}\n"
    assert client_surface._own_reads(saved, "bagclick") == []
    assert client_surface._own_reads(saved, "freeze") != []

LEFT = """
WFJScanDB = {
["probe"] = {
["test"] = { ["started"] = "2026-11-22 18:00:00", ["finished"] = "2026-11-22 18:05:00", ["build"] = "70959" },
["names"] = { ["on"] = true, ["rows"] = { { ["kind"] = "player", ["english"] = "Reyn", ["shown"] = "Reyn" } } },
["freeze"] = { ["items"] = 3, ["lines"] = 4, ["cards"] = 4, ["bound"] = "CTRL-F", ["expect"] = true, ["missing"] = { }, ["stuck"] = { } },
["chat"] = { ["topics"] = 9, ["phrases"] = 132, ["words"] = 12, ["expect"] = true, ["blank"] = { }, ["copy"] = "WFJ テスト", ["sizes"] = { "592x380" }, ["english"] = { } },
["marks"] = { ["window"] = 9, ["frames"] = 3, ["shown"] = 14, ["expect"] = true, ["english"] = { }, ["stale"] = { }, ["tags"] = { } },
["bagclick"] = { ["checked"] = 412, ["ours"] = { }, ["others"] = { } },
["novoice"] = { ["quests"] = 1, ["said"] = 0, ["pack"] = false, ["listed"] = 0, ["wrong"] = { } },
["hover"] = { ["map"] = { ["made"] = 3, ["found"] = 3, ["tips"] = 2, ["english"] = { }, ["runs"] = { } } },
["tooltips"] = { ["read"] = 50, ["japanese"] = 45, ["unread"] = 0, ["items"] = 3,
  ["rows"] = { ["tooltips"] = 50, ["kept"] = 0, ["english"] = { }, ["runs"] = { } },
  ["wrong"] = { }, ["changed"] = { ["17"] = "2 numbers in the Japanese, 3 on this client" }, ["folded"] = { },
  ["left"] = {
    ["17"] = { ["reason"] = "values", ["why"] = "2 numbers in the Japanese, 3 on this client",
      ["text"] = "Absorbs 48 damage for 30 sec, 3 times." },
    ["400"] = { ["reason"] = "hole", ["why"] = "a gap", ["text"] = "Lasts until cancelled." },
    ["9"] = { ["reason"] = "name", ["why"] = "Thrall", ["text"] = "Summons a friend." },
    ["8"] = { ["reason"] = "icon", ["why"] = "icon slot 1, and the live line has 0 icons", ["text"] = "Grants a rune." },
  },
  ["leftItems"] = { ["6948"] = "Use: Returns you to home.", ["117"] = "Use: Restores 61 health." },
  ["icons"] = { ["8"] = { ["line"] = false, ["shown"] = false, ["japanese"] = false },
    ["12"] = { ["line"] = true, ["shown"] = false, ["japanese"] = true } } },
},
}
"""


def test_the_tooltip_read_lists_each_spell_and_item_left_english_with_its_reason():
    left = client_surface.read_left_english(LEFT)
    assert left["spells"] == [
        ("8", "icon", "icon slot 1, and the live line has 0 icons", "Grants a rune."),
        ("9", "name", "Thrall", "Summons a friend."),
        ("17", "values", "2 numbers in the Japanese, 3 on this client", "Absorbs 48 damage for 30 sec, 3 times."),
        ("400", "hole", "a gap", "Lasts until cancelled."),
    ]
    assert left["items"] == [("117", "Use: Restores 61 health."), ("6948", "Use: Returns you to home.")]
    # the open question of the rune spells: does the client's line carry the icon the Japanese asks for
    assert left["icons"] == [("8", False, False, False), ("12", True, False, True)]
    assert client_surface.read_left_english(TOOLTIPS) is None  # a test addon from before the list
    assert client_surface.read_left_english(SAVED) is None


INCLUDED = """
WFJScanDB = {
["probe"] = {
["tooltips"] = { ["read"] = 2, ["japanese"] = 0, ["unread"] = 0, ["items"] = 0,
  ["spliced"] = {
    ["1319309"] = { ["reason"] = "values", ["why"] = "2 numbers in the Japanese, 0 on this client",
      ["text"] = "Moonkin Aura\\r\\n\\r\\n\\r\\nLeader of the Pack\\r\\n",
      ["included"] = { ["24907"] = "loaded true, known false, text: (no text)",
        ["24932"] = "loaded false, known false, text: (no text)" },
      ["includedAfter"] = { ["24907"] = "loaded true, known false, text: (no text)",
        ["24932"] = "loaded true, known false, text: (no text)" },
      ["cold"] = "English, the client's line holds 0 numbers",
      ["waited"] = "English, the client's line holds 2 numbers",
      ["after"] = "Japanese, the client's line holds 2 numbers" },
    ["17"] = { ["reason"] = "values", ["why"] = "2 numbers in the Japanese, 3 on this client", ["text"] = "Absorbs." },
  } },
},
}
"""


def test_a_spell_left_english_for_its_numbers_says_how_the_client_held_each_spell_it_splices_in(root):
    # the probe carries, per spell, the spells its English splices in: Druidic Auras prints two auras' text
    includes = client_surface.spell_includes(root / "data", [1319309, 403789, 17])
    assert includes[1319309] == [24907, 24932]
    assert {412788, 412789} <= set(includes[403789])
    assert 17 not in includes
    lua = client_surface.probe_lua({"entries": []}, walk=True, english=["Friends"], values={1319309: 2},
                                   includes={1319309: [24907, 24932]})
    assert "WFJScanIncludes = {\n  [1319309] = { 24907, 24932 },\n}" in lua
    # the whole line is kept, each spliced-in spell is asked for, and the line is read again at the end
    assert 'if reason == "values" then noteIncluded(record, id, english) end' in lua
    # one shown in Japanese once loaded is no longer left English; a line that is only the client's gap for a spell
    # in angle brackets (it never fills that form in) is a gap, not a tooltip the game changed
    assert "record.left[tostring(id)], record.changed[tostring(id)] = nil, nil" in lua
    assert 'local GAP = "<%d+>"' in lua and "local gap = english:find(GAP) ~= nil" in lua
    # a line with no words yet that splices in a spell is read again once that spell loaded
    assert "if type(WFJScanIncludes) == \"table\" and WFJScanIncludes[id] and not english:find(GAP) then" in lua
    # the tooltip waits off the screen, only until the spells it splices in loaded
    assert 'GameTooltip:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", -200, -200)' in lua
    assert "if not allCached(id) and waited < TOOLTIP_PATIENCE then" in lua
    assert "pcall(C_Spell.RequestLoadSpellData, sid)" in lua
    assert "recheckIncluded(record, function() readReported(record, done) end)" in lua
    # at the end each is shown cold, looked at again after a wait without showing it, and shown again
    assert "entry.cold = shownState(id)" in lua and "entry.waited = shownState(id)" in lua
    assert "entry.after = shownState(id)" in lua
    # shown in Japanese once what it splices in loaded: counted, and no detail
    assert client_surface.included_lines(INCLUDED) == [
        "spliced-in spells: 2 spells read before the spells they splice in had loaded, 1 shown in Japanese once "
        "they had",
        "INCL  spell 17 (2 numbers in the Japanese, 3 on this client), its whole line: Absorbs.",
        "INCL    shown cold: not read",
        "INCL    the same tooltip after a wait: not read",
        "INCL    shown again: not read",
    ]
    still = INCLUDED.replace('"Japanese, the client\'s line holds 2 numbers"',
                             '"English, the client\'s line holds 2 numbers"')
    lines = client_surface.included_lines(still)
    at = next(i for i, line in enumerate(lines) if line.startswith("INCL  spell 1319309"))
    assert lines[at:at + 6] == [
        "INCL  spell 1319309 (2 numbers in the Japanese, 0 on this client), its whole line: "
        "Moonkin Aura\\r\\n\\r\\n\\r\\nLeader of the Pack\\r\\n",
        "INCL    splices in 24907: when read, loaded true, known false, text: (no text)",
        "INCL    splices in 24907: at the end, loaded true, known false, text: (no text)",
        "INCL    splices in 24932: when read, loaded false, known false, text: (no text)",
        "INCL    splices in 24932: at the end, loaded true, known false, text: (no text)",
        "INCL    shown cold: English, the client's line holds 0 numbers",
    ]
    assert client_surface.included_lines(LEFT) == []
    # shown in Japanese once what it splices in loaded: no fault
    assert client_surface.included_problems(INCLUDED) == []
    # still English with every spliced-in spell loaded: its Japanese does not fit the whole line, a failure
    assert client_surface.included_problems(still) == [
        "tooltip still English with every spell it splices in loaded: spell 1319309 "
        "(English, the client's line holds 2 numbers)"]
    # a spliced-in spell the client never loaded leaves the line short: not this addon's fault
    unloaded = still.replace('["24932"] = "loaded true', '["24932"] = "loaded false')
    assert client_surface.included_problems(unloaded) == []


def test_untranslated_lines_are_listed_apart_from_faults_and_the_clients_own_gaps_are_only_counted():
    left = client_surface.read_left_english(LEFT)
    new = ["spellbook\tFrost", "group finder\t(did not open)", f"guild\t{client_surface.BOXES} Motd"]
    rows, holes = client_surface.untranslated(left, new, {117})
    assert holes == 1
    assert rows == [  # by reason, in the order of LEFT_REASONS
        "spell 8\ticon\ticon slot 1, and the live line has 0 icons\tGrants a rune.",
        "spell 17\tvalues\t2 numbers in the Japanese, 3 on this client\tAbsorbs 48 damage for 30 sec, 3 times.",
        "spell 9\tname\tThrall\tSummons a friend.",
        "item 6948\tnone\tno Japanese ships for this item\tUse: Returns you to home.",
        "item 117\tother\tJapanese ships for this item and the line stayed English\tUse: Restores 61 health.",
        # a window's English stays a failure of the run as well: listed here so it is reported with the rest
        "window spellbook\twindow\tnot allowed by the baseline, so it also fails the run\tFrost",
    ]
    assert client_surface.untranslated(None, [], set()) == ([], 0)


def test_the_result_says_what_was_left_english_on_every_run_and_that_list_alone_fails_nothing(
        tmp_path, capsys, monkeypatch):
    monkeypatch.setattr(client_surface, "_items_with_japanese", lambda: {117})
    saved = tmp_path / "WFJScan.lua"
    saved.write_text(LEFT, encoding="utf-8")
    args = argparse.Namespace(saved=saved, baseline=tmp_path / "none.txt", log=None)
    assert client_surface._texts(args) == 0
    out = capsys.readouterr().out.rstrip().splitlines()
    assert "left English, not a fault: 5 lines (and 1 gap the client printed for a spell this character does not " \
           "know, counted and not listed)" in out
    assert "LEFT  spell 9\tname\tThrall\tSummons a friend." in out
    assert "icon slots: 2 spells whose Japanese holds one; the client's line carried an icon on 1, the row shown " \
           "on 0; shown in Japanese on 1" in out
    assert out[-1] == ("Report this list to the maintainer and ask what to do with it: translate these lines with "
                       "this change, or name where they go.")
    # a failing run says it too
    saved.write_text(LEFT.replace('["wrong"] = { }, ["changed"]',
                                  '["wrong"] = { ["5"] = "1 numbers in the Japanese, 2 on this client" }, ["changed"]'),
                     encoding="utf-8")
    assert client_surface._texts(args) == 1
    out = capsys.readouterr().out.rstrip().splitlines()
    assert "ERROR tooltip numbers in the wrong places: spell 5 (1 numbers in the Japanese, 2 on this client)" in out
    assert out[-1].startswith("Report this list to the maintainer")


def _lua():
    lua = shutil.which("luajit") or shutil.which("lua5.1") or shutil.which("lua")
    if lua is None:
        pytest.skip("no Lua interpreter")
    return lua


def _sweep() -> str:
    return client_surface.TEXT_LUA % ('  ["Back"] = true,', '  "BACK",', "  [5] = 2,")


def test_the_reason_a_spell_stayed_english_is_read_by_the_addons_own_gate(root, tmp_path):
    lua = _lua()
    align = (root / "addon/WoWForeverJapanese/Core/Align.lua").read_text(encoding="utf-8")
    gate = client_surface.gate_lua(align, {
        1: ("$N1のダメージを与えます。", "u"),
        2: ("$I1 ルーンを刻みます。", "u"),
        3: ("Thrallを呼びます。", "u"),
        4: ("$N1のダメージを与え、5秒間スタンさせます。", "u"),
        5: ("$D1の間、攻撃力が上がります。", "u"),
        6: ("$N1のダメージを与えます。", "u"),
        7: ("$D1後に攻撃力が上がります。", "u"),
    })
    sweep = _sweep()
    reasons = sweep[sweep.index("local UNITS = {"):sweep.index("local function noteSpell")]
    driver = """
local VALUES = { [1] = 1, [4] = 1, [6] = 1 }
SPELL_DURATION_UNTIL_CANCELLED = "until cancelled"
""" + reasons + """
for _, case in ipairs({
  { 1, "Deals 10 to 20 Fire damage, then 5 more." },
  { 2, "Carves a rune." },
  { 3, "Summons a friend." },
  { 4, "Deals 30 damage and stuns the target." },
  { 5, "Increases attack power until cancelled." },
  { 6, "Deals <1234> damage." },
  { 6, "Deals 30 damage." },
  { 7, "Increases attack power until cancelled." },
  { 9, "Deals 30 damage." },
}) do
  local reason, why = leftWhy(case[1], case[2])
  print(case[1] .. " " .. reason .. " | " .. why)
end
"""
    script = tmp_path / "why.lua"
    script.write_text(gate + driver, encoding="utf-8")
    out = subprocess.run([lua, str(script)], check=False, capture_output=True, text=True, timeout=60)
    assert out.returncode == 0, out.stderr
    assert out.stdout.splitlines() == [
        "1 values | 1 numbers in the Japanese, 2 on this client",
        "2 icon | icon slot 1, and the live line has 0 icons",
        "3 name | Thrall",
        "4 number | 5",
        "5 other | the gate's checks pass on this line",
        "6 hole | the client printed a gap for a spell this character does not know",
        "6 other | the gate's checks pass on this line",
        "7 words | the client wrote words where a duration goes, and the Japanese there cannot take them",
        "9 none | no Japanese ships for it",
    ]


def test_the_number_check_reads_the_live_line_the_way_the_addons_gate_does(root, tmp_path):
    lua = _lua()
    align = (root / "addon/WoWForeverJapanese/Core/Align.lua").read_text(encoding="utf-8")
    gate = client_surface.gate_lua(align, {
        1: ("$D1の間、ベアの強さを授けます。", "u"),
        2: ("ワイバーン・ストライクのアビリティを得ます：$I1\n$N1のダメージを与えます。", "u"),
        3: ("$N1のダメージを与え、$N2回復します。", "u"),
    })
    sweep = _sweep()
    piece = sweep[sweep.index("local function valueCount"):sweep.index("local function shownRow")]
    reasons = sweep[sweep.index("local UNITS = {"):sweep.index("local function leftWhy")]
    driver = """
local VALUES = { [1] = 1, [2] = 1, [3] = 2 }
SPELL_DURATION_UNTIL_CANCELLED = "until canceled"
""" + piece + reasons + """
for _, case in ipairs({
  { 1, "Grants the strength of the Bear for until canceled." },
  { 2, "Gain the Wyvern Strike ability: |T135125:24|t" },
  { 3, "Deals 30 damage." },
  { 3, "Deals 30 damage and heals 5." },
}) do
  print(case[1] .. " " .. tostring(gateCount(case[1], case[2])))
end
"""
    script = tmp_path / "count.lua"
    script.write_text(gate + driver, encoding="utf-8")
    out = subprocess.run([lua, str(script)], check=False, capture_output=True, text=True, timeout=60)
    assert out.returncode == 0, out.stderr
    # a worded duration holds its value's place, a granted ability's heading needs none, a missing number is caught
    assert out.stdout.splitlines() == ["1 true", "2 true", "3 false", "3 true"]


def test_the_collector_is_paused_while_the_test_shows_tooltips_and_the_players_value_put_back(tmp_path):
    lua = _lua()
    sweep = _sweep()
    piece = sweep[sweep.index('local COLLECTOR = "collector.enabled"'):sweep.index("-- The tooltip read.")]
    script = tmp_path / "pause.lua"
    script.write_text("""
local handlers = {}
function CreateFrame()
  return { RegisterEvent = function() end, SetScript = function(_, _, fn) handlers[#handlers + 1] = fn end }
end
WFJScanDB = { probe = {} }
WFJ_DB = { settings = {} }
""" + piece + """
local done = 0
local finish = collectorPaused(function() done = done + 1 end)
print("paused " .. tostring(WFJ_DB.settings["collector.enabled"]))
finish()
print("back " .. tostring(WFJ_DB.settings["collector.enabled"]) .. " " .. done)
WFJ_DB.settings["collector.enabled"] = false
collectorPaused(function() end)
handlers[1](nil, "PLAYER_LOGOUT")
print("reload " .. tostring(WFJ_DB.settings["collector.enabled"]) .. " " .. tostring(WFJScanDB.probe.collectorPaused))
WFJ_DB.settings["collector.enabled"] = true
collectorPaused(function() end)
handlers[1](nil, "PLAYER_LOGIN")
print("login " .. tostring(WFJ_DB.settings["collector.enabled"]))
""", encoding="utf-8")
    out = subprocess.run([lua, str(script)], check=False, capture_output=True, text=True, timeout=60)
    assert out.returncode == 0, out.stderr
    # never set (on by default) stays never set; a player's off stays off; a crash mid-read is undone at login
    assert out.stdout.splitlines() == ["paused false", "back nil 1", "reload false nil", "login true"]
    tooltips = sweep[sweep.index("local function WFJScanTooltipRead(done)"):sweep.index("-- The no-voice read.")]
    assert tooltips.index("done = collectorPaused(done)") < tooltips.index("local record =")
    names = sweep[sweep.index("local function WFJScanNamesRead(done)"):sweep.index("-- The character window,")]
    assert names.index("if not record.on then return done() end") < names.index("done = collectorPaused(done)")


def test_the_done_line_counts_faults_and_lines_left_english_by_kind():
    lua = client_surface.TEXT_LUA
    run = lua[lua.index("SlashCmdList.WFJTEST = function(how)"):]
    assert run.index("pcall(sayCounts, db)") < run.index('print("WFJ test done:')
    assert '"WFJ test: faults: ' in lua and '"WFJ test: left English, not a fault: ' in lua


def test_the_test_addon_carries_the_addons_own_gate_and_each_spells_shipped_japanese(root, tmp_path):
    japanese = client_surface.spell_japanese(root / "data", [10, 17])
    assert set(japanese) == {10, 17}
    assert all(ja and status in ("u", "s", ".") for ja, status in japanese.values())
    align = (root / "addon/WoWForeverJapanese/Core/Align.lua").read_text(encoding="utf-8")
    lua = client_surface.probe_lua({"entries": []}, walk=True, english=["Friends"], keys=["FRIENDS"],
                                   values={10: 2, 17: 3}, japanese=japanese, gate=align)
    assert "function Align.check(" in lua  # the addon's own file, whole
    assert lua.index("ShippedAlign = shipped.Align") < lua.index("-- The text sweep.")
    assert "[10] = {" in lua and "[17] = {" in lua
    luajit = shutil.which("luajit")
    if luajit:
        probe = tmp_path / "WFJScanProbe.lua"
        probe.write_text(lua, encoding="utf-8")
        out = subprocess.run([luajit, "-b", str(probe), str(tmp_path / "probe.out")], check=False,
                             capture_output=True, timeout=60)
        assert out.returncode == 0, out.stderr.decode("utf-8", "replace")


LATIN = """
WFJScanDB = {
["probe"] = {
["live"] = {
["(nothing open)"] = {
["english"] = {},
["latin"] = {
["PlayerName"] = "Zyaga",
},
},
["character"] = {
["english"] = {},
["latin"] = {
["PlayerName"] = "Zyaga",
["CharacterLevelText"] = "レベル 1 Warrior",
["SkillRow.960176b40.Name"] = "Hearthstone",
["PvPInfo"] = "報酬はKobold Verminで購入できます。",
["PlayerSpellsFrame.SpellBookFrame.Row.Name"] = "Hearthstone",
["ChatFrame1.Line"] = "Hearthstone",
["SomeAddon.Label"] = "Sort bags",
["Abbrev"] = "PvP",
["QuestObjectiveTracker.Line1"] = "0/8 Solid Sharpening Stone",
["QuestObjectiveTracker.Line2"] = "Kobold Vermin: 3/10",
["QuestObjectiveTracker.Line3"] = "0/8 Unknown Trinket",
},
},
},
["names"] = {
["on"] = true,
["target"] = {
["target tooltip row 2"] = "Level 40",
["target tooltip row 4"] = "12/12 Saltwater Murloc Eye",
},
},
},
}
"""


def test_a_game_name_left_english_in_a_window_is_a_line_of_the_result():
    latin = client_surface.read_latin(LATIN)
    assert set(latin) == {"always on screen", "character", "the target's tooltip"}
    names = {**JAPANESE, "Warrior": "ウォリアー", "PvP": "ピーブイピー",
             "Solid Sharpening Stone": "ソリッド・シャープニング・ストーン",
             "Saltwater Murloc Eye": "ソルトウォーター・マーロック・アイ"}
    faults, protected, other = client_surface.latin_names(latin, names, frozenset({"PvP"}))
    # a whole text that is a name, a name with only counts around it (an objective line), and a name inside
    # Japanese text; a text on screen with no window open is filed once; chat is what players typed; a
    # kept-as-written word is never a fault
    assert faults == {
        ("character", "(name left English) Hearthstone"),
        ("character", "(name left English) Warrior"),
        ("character", "(name left English) Kobold Vermin"),
        ("character", "(name left English) Solid Sharpening Stone"),
        # the targeted creature's objective row, read by the names read
        ("the target's tooltip", "(name left English) Saltwater Murloc Eye"),
    }
    assert protected == {"the spellbook": 1}
    # a name the list has no line for, with its counts, is other English, never a fault
    assert other == [("always on screen", "Zyaga"), ("character", "0/8 Unknown Trinket"), ("character", "PvP"),
                     ("character", "Sort bags"), ("the target's tooltip", "Level 40")]
    # the baseline allows one with its reason, like any other line of the result
    allowed = {("character", "(name left English) Warrior"): "a reason"}
    new, _ = client_surface.window_test_report(faults, allowed)
    assert len(new) == 4 and not any("Warrior" in row for row in new)


def test_every_window_read_keeps_its_latin_text_only_with_japanese_names_on():
    lua = client_surface.probe_lua({"entries": []}, walk=True, english=["Friends"], keys=["FRIENDS"])
    body = lua[lua.index("local function readScreen"):lua.index("-- What the test clicks in an open window")]
    assert "namesOn() and {} or nil" in body and "not ENGLISH[plain]" in body
    # the character window's reads are joined, like its English
    assert "record.latin[name] = text" in lua


def test_the_latin_text_of_the_last_hand_read_stands_for_a_plain_run_with_japanese_names_on():
    """A plain run does not read the guild and character windows. The Latin text the last `/wfjtest hand` kept
    of them is held to the name list for it, while that read is of the same build and the run kept Latin text."""
    lua = client_surface.TEXT_LUA
    # the hand read keeps each window's whole record, its Latin text with it
    step = lua[lua.index("local function playerRead("):lua.index("local function WFJScanCharacterRead")]
    assert "latin = namesOn() and {} or nil" in step and "db.live[name] = record" in step
    assert "guild = db.live.guild, character = db.live.character" in lua

    def saved(build: str, live_latin: str = '["latin"] = { ["PlayerName"] = "Zyaga" },') -> str:
        return ('WFJScanDB = { ["probe"] = {\n'
                '  ["test"] = { ["started"] = "a", ["finished"] = "b", ["build"] = "71037", ["hand"] = false },\n'
                '  ["live"] = { ["(nothing open)"] = { ["english"] = { }, ' + live_latin + ' } },\n'
                '  ["hand"] = { ["build"] = "' + build + '", ["at"] = "c",\n'
                '    ["guild"] = { ["english"] = { }, ["latin"] = { ["Roster.Row.Class"] = "Warrior" } },\n'
                '    ["character"] = { ["english"] = { }, ["latin"] = { ["SkillRow.Name"] = "Hearthstone" } } },\n'
                "} }\n")

    latin = client_surface.read_latin(saved("71037"))
    assert latin == {"always on screen": {"PlayerName": "Zyaga"}, "guild": {"Roster.Row.Class": "Warrior"},
                     "character": {"SkillRow.Name": "Hearthstone"}}
    faults = client_surface.latin_names(latin, {**JAPANESE, "Warrior": "ウォリアー"}, frozenset())[0]
    assert faults == {("guild", "(name left English) Warrior"), ("character", "(name left English) Hearthstone")}
    # a hand read of another build stands for nothing, and a run with names off holds no name to the list
    assert set(client_surface.read_latin(saved("70959"))) == {"always on screen"}
    assert client_surface.read_latin(saved("71037", live_latin="")) == {}
    # a hand run reads the two windows itself: nothing is taken from the kept read
    hand_run = saved("71037").replace('["hand"] = false', '["hand"] = true')
    assert set(client_surface.read_latin(hand_run)) == {"always on screen"}


def test_a_run_that_read_too_few_spells_fails_and_says_why_the_rest_were_not_read():
    few = {"read": 27, "unread": 13360, "japanese": 27, "items": 16, "wrong": [], "folded": [], "refused": ""}
    assert client_surface.tooltip_problems(few) == ["tooltips not read: only 27 of 13387 spells could be read"]
    why = {"its text is no line of the tooltip": (360, ["9: 2 lines"]),
           "no text 4s after it was asked for (loaded: true, text said ready: false)": (13000, ["17", "18"])}
    said = client_surface.tooltip_problems({**few, "why": why})
    # the commonest reason first, each with how many spells and a few of them
    assert said[0].endswith("spells could be read (13000 no text 4s after it was asked for (loaded: true, text "
                            "said ready: false), e.g. ['17', '18']; 360 its text is no line of the tooltip, "
                            "e.g. ['9: 2 lines'])")
    assert client_surface.tooltip_problems({**few, "read": 13000, "unread": 387}) == []
    # the reasons are read from the record the test addon keeps them in
    saved = TOOLTIPS.replace('["items"] = 9,', '["items"] = 9, ["why"] = { ["no text from the client"] = '
                             '{ ["n"] = 4, ["ids"] = { "17: 1 lines, last: Frostbolt" } } },')
    assert client_surface.read_tooltips(saved)["why"] == {
        "no text from the client": (4, ["17: 1 lines, last: Frostbolt"])}


def test_the_tests_own_refused_click_is_listed_and_a_shut_group_finder_says_why():
    assert any("WFJScan SetAvatarTexture()" in own for own in client_surface.OWN_REFUSALS)
    lua = client_surface.probe_lua({"entries": []}, walk=True, english=["Friends"], keys=["FRIENDS"])
    assert "the client kept it shut: finder style " in lua


def test_an_error_is_reported_with_its_whole_call_stack():
    """The first frame says where an error was raised; its cause is further down (a click of the test's on a
    guild tab, three frames below a refused call). The result keeps the stack and the report prints it."""
    saved = """
WFJScanDB = {
["probe"] = {
["test"] = { ["started"] = "a", ["finished"] = "b", ["build"] = "71037",
  ["errors"] = { ["[grabbed] AddOn 'WFJScan' tried to call the protected function 'SetAvatarTexture()'."] = 6 },
  ["stacks"] = { ["[grabbed] AddOn 'WFJScan' tried to call the protected function 'SetAvatarTexture()'."] =
    "[C]: in function 'SetAvatarTexture' < CommunitiesList.lua:523: in function 'Init' < [C]: in function 'Click'" } },
},
}
"""
    assert client_surface.read_test_problems(saved) == [
        "error x6: [grabbed] AddOn 'WFJScan' tried to call the protected function 'SetAvatarTexture()'. @ "
        "[C]: in function 'SetAvatarTexture' < CommunitiesList.lua:523: in function 'Init' < [C]: in function 'Click'"]
    lua = client_surface.TEXT_LUA
    assert 'if not line:find("BugGrabber", 1, true)' in lua  # the catcher's own frames say nothing
    assert "db.test.stacks[key] = stackOf(e.stack)" in lua and "pcall(debugstack, 2)" in lua


def test_a_listed_error_of_the_games_own_is_set_aside_only_with_a_stack_clear_of_our_code(root):
    """The raid window's own code errors outside a raid once it is loaded. Such an error is listed with its
    reason and does not fail the run; the same message with our code in its stack, or with no stack, does."""
    listed = client_surface.read_game_errors(
        "# a comment\nBlizzard_RaidUI.lua:87: attempt to compare number with nil\tthe game's own\n")
    message = "error x1: [grabbed] .../Blizzard_RaidUI.lua:87: attempt to compare number with nil"
    own = message + " @ [Interface/AddOns/Blizzard_RaidUI/Mainline/Blizzard_RaidUI.lua]:87: in function 'x'"
    ours = message + " @ [Interface/AddOns/WoWForeverJapanese/UI/Raid.lua]:3 < [Interface/AddOns/Blizzard_RaidUI]"
    test = message + " @ [Interface/AddOns/WFJScan/WFJScanProbe.lua]:9"
    tainted = "error x1: Blizzard_RaidUI.lua:87: attempt to compare number with nil (execution tainted by 'X') @ s"
    other = "error x1: SomethingElse.lua:1: boom @ [Interface/AddOns/Blizzard_RaidUI]"
    # raised twice, once through our code: one stack is kept, so the run marks the message itself
    twice = message + " [ran through this addon's code] @ [Interface/AddOns/Blizzard_RaidUI/Mainline/x.lua]:87"
    found = client_surface.game_own_errors([own, ours, test, tainted, other, message, twice], listed)
    assert found == {own: "the game's own"}
    with pytest.raises(ValueError):
        client_surface.read_game_errors("only one column\n")
    text = (root / "pipeline/ui_test_game_errors.txt").read_text(encoding="utf-8")
    assert all(why for why in client_surface.read_game_errors(text).values())


def test_a_plain_run_does_not_wait_for_the_windows_the_player_opens_and_the_last_hand_read_stands_for_them():
    """`/wfjtest` ends by itself. The guild and character windows are read by `/wfjtest hand`; what that read
    stands for a plain run while the build is the same, and a build with no such read owes one."""
    lua = client_surface.TEXT_LUA
    assert 'if how ~= "hand" then' in lua and "db.test.hand = false" in lua
    assert lua.index('if how ~= "hand" then') < lua.index("WFJScanGuildRead(function()")
    assert "db.hand = { build = db.test.build" in lua

    def saved(hand: str) -> str:
        return ('WFJScanDB = { ["probe"] = {\n'
                '  ["test"] = { ["started"] = "a", ["finished"] = "b", ["build"] = "71037", ["hand"] = false },\n'
                '  ["live"] = { ["(nothing open)"] = { ["english"] = { }, ["boxes"] = { }, ["japanese"] = 0 } },\n'
                "  " + hand + "\n} }\n")

    owed = client_surface.read_window_test(saved(""))[1]
    assert owed == {("guild", client_surface.HAND_OWED), ("character", client_surface.HAND_OWED)}
    def record(build: str) -> str:
        return ('["hand"] = { ["build"] = "' + build + '", ["at"] = "c", ["guild"] = { ["english"] = '
                '{ ["A"] = "Veteran" }, ["boxes"] = { }, ["japanese"] = 3 }, ["character"] = { ["english"] = { }, '
                '["boxes"] = { }, ["japanese"] = 9 } },')

    info, found = client_surface.read_window_test(saved(record("71037")))
    assert found == {("guild", "Veteran")} and info["hand"] == "read by hand on c"
    # a hand read of another build is no read of this one, and neither is one made with other addon code
    assert client_surface.read_window_test(saved(record("70959")))[1] == owed
    other_code = record("71037").replace('["at"] = "c"', '["at"] = "c", ["code"] = "abc"')
    assert client_surface.read_window_test(saved(other_code))[1] == owed
    # the hand read keeps only its own windows: a window the hand run did not open is not owed by a plain run
    assert 'if window == "guild" or window == "character" or window == "guild pages" then' in lua
    # a hand run says nothing about a kept read (a Lua true is no text of the run)
    hand_run = saved("").replace('["hand"] = false', '["hand"] = true')
    assert "hand" not in client_surface.read_window_test(hand_run)[0]


def test_an_error_that_ever_ran_through_our_code_is_marked_whatever_stack_was_kept():
    lua = client_surface.TEXT_LUA
    assert "if ok and oursIn(stack) then db.test.ours[key] = true end" in lua
    assert "if oursIn(e.stack) then db.test.ours[key] = true end" in lua
    saved = """WFJScanDB = { ["probe"] = { ["test"] = { ["started"] = "a", ["finished"] = "b",
  ["errors"] = { ["[live] boom"] = 2 }, ["stacks"] = { ["[live] boom"] = "[Interface/AddOns/Blizzard_X]:1" },
  ["ours"] = { ["[live] boom"] = true } } } }
"""
    assert client_surface.read_test_problems(saved) == [
        "error x2: [live] boom [ran through this addon's code] @ [Interface/AddOns/Blizzard_X]:1"]


def test_the_manifest_carries_a_stamp_of_the_addons_code_without_its_data(tmp_path):
    addon = tmp_path / "Addon"
    (addon / "UI").mkdir(parents=True)
    (addon / "Data").mkdir()
    (addon / "UI" / "A.lua").write_text("local x = 1\n", encoding="utf-8")
    (addon / "Data" / "D.lua").write_text("return {}\n", encoding="utf-8")
    first = client_surface.build(addon)["code"]
    (addon / "Data" / "D.lua").write_text("return { 1 }\n", encoding="utf-8")
    assert client_surface.build(addon)["code"] == first
    (addon / "UI" / "A.lua").write_text("local x = 2\n", encoding="utf-8")
    assert client_surface.build(addon)["code"] != first
    lua = client_surface.probe_lua({"entries": [], "code": first}, walk=True, english=["Friends"], keys=["FRIENDS"])
    assert f'WFJScanAddonCode = "{first}"' in lua


def test_the_items_listed_for_the_run_are_shown_by_id_and_every_line_is_kept(root):
    """An item a player reported is listed with its reason; the run shows it by id and keeps each line beside
    what the tooltip shows, so one run says what that item's tooltip reads on this client."""
    listed = client_surface.listed_items((root / "pipeline/ui_test_items.txt").read_text(encoding="utf-8"))
    assert listed and all(isinstance(i, int) and why for i, why in listed.items())
    with pytest.raises(ValueError):
        client_surface.listed_items("12\n")
    lua = client_surface.probe_lua({"entries": []}, walk=True, english=["Friends"], keys=["FRIENDS"],
                                   items=[7, 3, 7])
    assert "WFJScanReportedItems = { 3, 7 }" in lua
    assert "readReported(record, done)" in lua and "pcall(GameTooltip.SetItemByID, GameTooltip, id)" in lua
    saved = """WFJScanDB = { ["probe"] = { ["test"] = { ["started"] = "a", ["finished"] = "b" },
  ["tooltips"] = { ["read"] = 1, ["reported"] = { ["6461"] = { "A => (English)", "B => C" } } } } }
"""
    assert client_surface.read_tooltips(saved)["reported"] == {"6461": ["A => (English)", "B => C"]}


def test_a_spells_row_is_found_in_the_tooltips_own_data_and_a_missing_row_is_never_judged():
    lua = client_surface.probe_lua({"entries": []}, walk=True, english=["Friends"], keys=["FRIENDS"])
    body = lua[lua.index("local function readSpell"):lua.index("-- one item's tooltip, already shown")]
    # the query's line list can be longer than the tooltip on screen: its index is only the fallback
    assert "GetPrimaryTooltipInfo" in body and "row = own or typed or row" in body
    assert body.index("row = own or typed or row") < body.index("shownRow(row)")
    # the row is the one the client drew the line on, never the line's place in the list
    assert "own = line.lineIndex" in body and "typed = line.lineIndex" in body
    # a row the tooltip does not have is counted as not read, never as English
    assert "if row > GameTooltip:NumLines() then" in body
    assert "the row of its text is past the tooltip's last row" in body


def test_a_name_on_a_unit_a_player_controls_is_not_held_to_the_name_list():
    lua = client_surface.probe_lua({"entries": []}, walk=True, english=["Friends"], keys=["FRIENDS"])
    body = lua[lua.index("local function readScreen"):lua.index("-- What the test clicks in an open window")]
    # a hunter's pet keeps whatever name it has: the addon leaves it, and the run does not flag it
    assert "and not playersUnit(frame) then" in body
    assert "UnitPlayerControlled" in lua[lua.index("local function playersUnit"):lua.index("local function readScreen")]


def test_a_window_the_player_may_not_open_is_named_and_not_failed_and_still_tested_where_it_is():
    lua = client_surface.probe_lua({"entries": []}, walk=True, english=["Friends"], keys=["FRIENDS"])
    body = lua[lua.index("local function groupFinder"):lua.index("local LIVE = {")]
    # the client's own conditions are asked first: an account without the group finder has no window to test
    assert "CanPlayerUsePremadeGroup" in body and "error(NOT_AVAILABLE" in body
    assert body.index("error(NOT_AVAILABLE") < body.index("LFGVanilla_ToggleFrame(page)")
    # such a window joins the windows this client does not have, never the windows that did not open
    assert "tostring(err):sub(1, #NOT_AVAILABLE) == NOT_AVAILABLE" in lua
    # and the three pages are still in the sweep for a player who has it
    assert lua.count('{ "group finder') == 3


ROWS = """
WFJScanDB = {
["probe"] = {
["tooltips"] = {
["read"] = 2,
["rows"] = {
["tooltips"] = 2,
["kept"] = 3,
["english"] = {
["Rank #"] = {
["n"] = 40,
["at"] = "spell 133 row 1 Right",
},
["Requires Dagger"] = {
["n"] = 3,
["at"] = "spell 53 row 4 Left",
},
},
["runs"] = {
["Shadow"] = {
["n"] = 12,
["at"] = "spell 686 row 4 Left",
},
},
},
},
},
}
"""


def test_every_row_of_every_tooltip_is_read_and_any_english_fails_the_run():
    tooltips, english, runs = client_surface.read_tooltip_rows(ROWS)
    assert tooltips == 2
    # most frequent first, each with one tooltip that shows it
    assert english == [(40, "Rank #", "spell 133 row 1 Right"), (3, "Requires Dagger", "spell 53 row 4 Left")]
    assert runs == [(12, "Shadow", "spell 686 row 4 Left")]
    assert client_surface.tooltip_row_problems(ROWS) == [
        "English on tooltips: 2 kinds of row with no Japanese and 1 English words inside Japanese rows, over 2 "
        "tooltips (listed below as ROW and WORD)"]
    # a result made by a test addon that read the description row only says so instead of passing
    assert client_surface.tooltip_row_problems(TOOLTIPS)[0].startswith("tooltip rows not read")
    lua = client_surface.probe_lua({"entries": []}, walk=True, english=["Friends"], keys=["FRIENDS"])
    body = lua[lua.index("local function noteRows"):lua.index("-- why a spell was not read")]
    # both columns of every row, with a name inside a Japanese row kept as a word
    assert '{ "Left", "Right" }' in body and "englishIn(plain, function(into, key) keep(rows[into]" in body
    judge = lua[lua.index("local function englishIn"):lua.index("-- The tooltip's own data")]
    assert 'found("english",' in judge and 'found("runs", run)' in judge
    assert lua.count("noteRows(record,") >= 2  # spells and items


# A stand-in client for the hover read: frames with enter and leave scripts that build GameTooltip line by line,
# the way a list row's script does, and a log of what ran. Each test adds its own window and drives the read.
HOVER_STUBS = r"""
local log, frames = {}, {}
local combat = false
function InCombatLockdown() return combat end
function debugprofilestop() return os.clock() * 1000 end
UIParent = { name = "UIParent" }
local tip = { lines = {}, shown = false }
GameTooltip = {}
function GameTooltip:IsShown() return tip.shown end
function GameTooltip:NumLines() return #tip.lines end
function GameTooltip:Hide() tip.shown, tip.lines, tip.unit = false, {}, nil end
function GameTooltip:GetUnit() if tip.unit then return "Someone", tip.unit end end
function GameTooltip:AddLine(text) tip.lines[#tip.lines + 1] = text; tip.shown = true end
for i = 1, 12 do
  _G["GameTooltipTextLeft" .. i] = { IsShown = function() return tip.lines[i] ~= nil end,
    GetText = function() return tip.lines[i] end }
  _G["GameTooltipTextRight" .. i] = { IsShown = function() return false end, GetText = function() return nil end }
end
local saved = { test = { part = "live" } }
local function probeDb() return saved end
local function fontString(text)
  return { GetObjectType = function() return "FontString" end, GetText = function() return text end }
end
-- `lines`: what its enter script writes on the tooltip; `texts`: what the frame itself shows
local function frame(name, parent, o)
  o = o or {}
  local f = { name = name, parent = parent }
  function f:IsForbidden() return false end
  function f:IsVisible() return true end
  function f:IsProtected() return o.protected == true end
  function f:IsMouseMotionEnabled() return o.mouse ~= false end
  function f:GetDebugName() return self.name end
  function f:GetParent() return self.parent end
  function f:GetAttribute(key) return o.attributes and o.attributes[key] end
  function f:GetChildren() end
  function f:GetRegions()
    local out = {}
    for _, t in ipairs(o.texts or {}) do out[#out + 1] = fontString(t) end
    return unpack(out)
  end
  local scripts = {}
  if o.lines or o.enter then
    scripts.OnEnter = function(self, motion)
      log[#log + 1] = "enter " .. self.name .. " " .. tostring(motion) .. " " .. tostring(saved.test.part)
      if o.enter then o.enter(self) end
      for _, line in ipairs(o.lines or {}) do GameTooltip:AddLine(line) end
    end
    scripts.OnLeave = function(self) log[#log + 1] = "leave " .. self.name .. " " .. tostring(tip.shown) end
  end
  function f:GetScript(which) return scripts[which] end
  frames[#frames + 1] = f
  return f
end
function EnumerateFrames(prev)
  if not prev then return frames[1] end
  for i, f in ipairs(frames) do if f == prev then return frames[i + 1] end end
end
"""


# run after the hover read is defined: it drives the read the way the sweep does, once a frame
HOVER_DRIVER = r"""
local function drive(window, roots)
  local ticks = 0
  if hoverBegin(window, roots) then
    while hoverStep() do ticks = ticks + 1 end
  end
  return ticks
end
local function dump(rec)
  for _, kind in ipairs({ "english", "runs" }) do
    local keys = {}
    for key in pairs(rec[kind]) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
      local row = rec[kind][key]
      print(kind .. " " .. key .. " | " .. row.n .. " | " .. row.frame .. " | " .. row.raw)
    end
  end
  print("counts made=" .. rec.made .. " found=" .. rec.found .. " skipped=" .. rec.skipped .. " denied=" .. rec.denied
    .. " tips=" .. rec.tips .. " units=" .. rec.units .. " capped=" .. tostring(rec.capped)
    .. " stopped=" .. tostring(rec.stopped))
end
"""


def _hover_piece() -> str:
    """The pieces of the generated sweep the hover read runs on: the Japanese test, a pooled row's name, whether a
    frame is in the window, the tooltip rules and the hover read itself."""
    sweep = _sweep()

    def cut(start: str, end: str) -> str:
        return sweep[sweep.index(start):sweep.index(end)]

    return (cut("local function hasJapanese", "local function boxed")
            + cut("local function unaddressed", "-- The action word a name holds")
            + cut("local function under", "-- A button as its place in the window")
            + cut("-- How a tooltip's rows are judged", "local TAB_TICKS"))


def _run_hover(tmp_path, scenario: str) -> list[str]:
    lua = _lua()
    script = tmp_path / "hover.lua"
    script.write_text(HOVER_STUBS + _hover_piece() + HOVER_DRIVER + scenario, encoding="utf-8")
    out = subprocess.run([lua, str(script)], check=False, capture_output=True, text=True, timeout=60)
    assert out.returncode == 0, out.stderr
    return out.stdout.splitlines()


def test_a_rows_hover_tooltip_in_english_is_kept_and_a_japanese_one_and_a_players_own_text_are_not(tmp_path):
    lines = _run_hover(tmp_path, r"""
local window = frame("GuildWindow", UIParent)
frame("GuildWindow.Roster.ScrollTarget.9910000a0", window,
  { texts = { "Zyaga", "good tank" }, lines = { "Zyaga", "Level 60 Warrior", "Note: good tank", "|cffffffffElwynn Forest|r" } })
frame("GuildWindow.Info", window, { lines = { "ギルド情報", "|T123:0|tギルドの説明" } })
frame("GuildWindow.Member", window, { lines = { "メンバーはKobold Verminと話す。NPCに。" } })
frame("GuildWindow.Unit", window, { enter = function() tip.unit = "player" end, lines = { "Thrall", "<Horde Guild>" } })
frame("GuildWindow.Loading", window, { lines = { RETRIEVING_ITEM_INFO } })
frame("GuildWindow.Silent", window, { enter = function() end })
frame("GuildWindow.NoMouse", window, { mouse = false, lines = { "Never Read" } })
frame("Elsewhere", UIParent, { lines = { "Outside the window" } })
RETRIEVING_ITEM_INFO = "Retrieving item information"
drive("guild", { [window] = true })
for _, line in ipairs(log) do print(line) end
dump(saved.hover.guild)
print("tooltip up after: " .. tostring(tip.shown))
""")
    # the player's own name and note are the row's own data, the label around the note is still read; the unit's
    # tooltip, the tooltip still loading and the Japanese one leave nothing; an abbreviation is kept as written
    assert [ln for ln in lines if ln.startswith(("english ", "runs "))] == [
        "english Elwynn Forest | 1 | GuildWindow.Roster.ScrollTarget.* | ||cffffffffElwynn Forest||r",
        "english Level # Warrior | 1 | GuildWindow.Roster.ScrollTarget.* | Level 60 Warrior",
        "english Note: | 1 | GuildWindow.Roster.ScrollTarget.* | Note: good tank",
        "runs Kobold Vermin | 1 | GuildWindow.Member | メンバーはKobold Verminと話す。NPCに。",
    ]
    assert "counts made=6 found=6 skipped=0 denied=0 tips=3 units=1 capped=nil stopped=nil" in lines
    # each frame's leave script runs after its enter script, with its tooltip still up, before the next is entered;
    # the script is run as the client runs it (the mouse moved onto it), under the run's hover part
    hovers = [ln for ln in lines if ln.startswith(("enter ", "leave "))]
    assert hovers[0] == "enter GuildWindow.Roster.ScrollTarget.9910000a0 true hover"
    assert hovers[1] == "leave GuildWindow.Roster.ScrollTarget.9910000a0 true"
    for enter, leave in zip(hovers[::2], hovers[1::2], strict=True):
        assert enter.startswith("enter ") and leave.startswith("leave ") and enter.split()[1] == leave.split()[1]
    assert not any("NoMouse" in ln or "Elsewhere" in ln for ln in hovers)
    assert lines[-1] == "tooltip up after: false"


def test_a_protected_frame_a_secure_template_and_a_denied_name_are_never_pointed_at(tmp_path):
    lines = _run_hover(tmp_path, r"""
local window = frame("Window", UIParent)
local function boom() error("pointed at") end
frame("Window.Protected", window, { protected = true, enter = boom })
frame("Window.Secure", window, { attributes = { type = "spell" }, enter = boom })
frame("Window.ActionButton1", window, { enter = boom })
frame("Window.MultiBarBottomLeftButton2", window, { enter = boom })
frame("PlayerSpellsFrame.SpellBookFrame.Row", window, { enter = boom })
frame("WorldMapFrame.NavBar.Home", window, { enter = boom })
frame("Window.ItemTooltip", window, { enter = boom })
frame("Window.Row", window, { lines = { "行" } })
drive("map", { [window] = true })
for _, line in ipairs(log) do print(line) end
dump(saved.hover.map)
""")
    assert [ln for ln in lines if ln.startswith("enter ")] == ["enter Window.Row true hover"]
    assert "counts made=1 found=1 skipped=0 denied=7 tips=1 units=0 capped=nil stopped=nil" in lines


def test_another_addons_window_is_never_pointed_at_and_a_friends_name_is_no_english(tmp_path):
    lines = _run_hover(tmp_path, r"""
C_AddOns = {
  GetNumAddOns = function() return 4 end,
  GetAddOnInfo = function(i) return ({ "Baganator", "Blizzard_Collections", "WoWForeverJapanese", "WFJScan" })[i] end,
  IsAddOnLoaded = function() return true end,
}
C_FriendList = { GetNumFriends = function() return 1 end,
  GetFriendInfoByIndex = function() return { name = "Cakepop-Realm" } end }
BNGetNumFriends = function() return 1 end
C_BattleNet = { GetFriendAccountInfo = function()
  return { accountName = "Jack", battleTag = "ActionJacksn#1234", gameAccountInfo = { characterName = "Jaxx" } } end }
local window = frame("SocialUIFrame", UIParent)
local function boom() error("pointed at") end
frame("Baganator_SingleViewBackpackViewFrameblizzard.SearchWidget", window, { enter = boom })
frame("SocialUIFrame.FriendsList.ScrollTarget.9910000a1", window,
  { texts = { "Jack" }, lines = { "ActionJacksn", "Cakepop", "Jaxx" } })
frame("SocialUIFrame.Status", window, { lines = { "Online" } })
GetNumGuildMembers = function() return 1 end
GetGuildRosterInfo = function() return "Aneis Carter-Realm", "Initiate", 4, 30, "Mage", "", "Tailor/eng", "" end
GuildControlGetNumRanks = function() return 1 end
GuildControlGetRankName = function() return "Veteran" end
frame("SocialUIFrame.Guild.9910000a3", window, { lines = { "Aneis Carter", "Initiate", "Veteran", "Tailor/eng" } })
drive("friends", { [window] = true })
for _, line in ipairs(log) do print(line) end
dump(saved.hover.friends)
""")
    assert not any("Baganator" in ln for ln in lines if ln.startswith("enter "))
    # the friends' names are the players' own; an English word of the client's is still found
    assert [ln for ln in lines if ln.startswith(("english ", "runs "))] == [
        "english Online | 1 | SocialUIFrame.Status | Online"]


def test_a_skill_and_recipe_heading_is_held_to_the_two_names_it_is_made_of():
    record = {"refused": None, "on": True, "rows": [
        ("spell", "Enchanting: Enchant Cloak - Dodge", "エンチャンティング: エンチャント・クローク・ドッジ"),
        ("spell", "Enchanting: Enchant Cloak - Stealth", "エンチャンティング: Enchant Cloak - Stealth"),
        ("spell", "Mining: Unknown Thing", "マイニング: 何か")]}
    names = {"Enchanting": "エンチャンティング", "Enchant Cloak - Dodge": "エンチャント・クローク・ドッジ",
             "Enchant Cloak - Stealth": "エンチャント・クローク・ステルス", "Mining": "マイニング"}
    assert client_surface.names_problems(record, names) == [
        "name changed with no line in the name list: spell Mining: Unknown Thing shows マイニング: 何か",
        "name not as the name list spells it: spell Enchanting: Enchant Cloak - Stealth shows "
        "エンチャンティング: Enchant Cloak - Stealth, the list has エンチャンティング: エンチャント・クローク・ステルス"]


def test_an_item_with_a_random_suffix_is_held_to_its_name_and_its_suffix():
    # as the run of build 71091 showed them: the item's and the suffix's lines joined, which the addon writes
    record = {"refused": None, "on": True, "rows": [
        ("item", "Charged Gear of Strength", "チャージド・ギア・オブ・ストレングス"),
        ("item", "Field Plate Vambraces of Nature Protection", "Field Plate Vambraces of Nature Protection"),
        ("item", "Band of the Unknown", "バンド")]}
    names = {"Charged Gear": "チャージド・ギア", "of Strength": "オブ・ストレングス",
             "Field Plate Vambraces": "フィールド・プレート・ヴァンブレイス",
             "of Nature Protection": "オブ・ネイチャー・プロテクション"}
    assert client_surface.names_problems(record, names) == [
        "name changed with no line in the name list: item Band of the Unknown shows バンド",
        "name left English: item Field Plate Vambraces of Nature Protection (its Japanese is "
        "フィールド・プレート・ヴァンブレイス・オブ・ネイチャー・プロテクション)"]


def test_the_hovers_of_a_window_are_capped_and_a_long_list_does_not_take_them_all(tmp_path):
    lines = _run_hover(tmp_path, r"""
local window = frame("Calendar", UIParent)
for i = 1, 70 do frame("Calendar.DayButton" .. i, window, { texts = { tostring(i) }, lines = { "予定" } }) end
frame("Calendar.Filter", window, { lines = { "Filter" } })
drive("calendar", { [window] = true })
dump(saved.hover.calendar)
-- a later page of the same window finds nothing more to point at once the cap is reached
print("again " .. tostring(hoverBegin("calendar", { [window] = true })))
local entered = 0
for _, line in ipairs(log) do if line:find("^enter ") then entered = entered + 1 end end
print("entered " .. entered .. " filter " .. tostring(log[3] == "enter Calendar.Filter true hover"))
""")
    assert "counts made=60 found=71 skipped=11 denied=0 tips=60 units=0 capped=true stopped=nil" in lines
    assert "english Filter | 1 | Calendar.Filter | Filter" in lines
    # one of each kind in turn: the filter button is the second frame pointed at, not the 71st
    assert lines[-2:] == ["again false", "entered 60 filter true"]


def test_a_fight_stops_the_hovering_and_nothing_is_pointed_at_in_one(tmp_path):
    lines = _run_hover(tmp_path, r"""
local window = frame("Friends", UIParent)
frame("Friends.Row1", window, { lines = { "Friend One" } })
frame("Friends.Row2", window, { enter = function() combat = true end, lines = { "Friend Two" } })
frame("Friends.Row3", window, { lines = { "Friend Three" } })
drive("friends", { [window] = true })
for _, line in ipairs(log) do print(line) end
dump(saved.hover.friends)
print("tooltip up after: " .. tostring(tip.shown))
print("again " .. tostring(hoverBegin("friends", { [window] = true })))
combat = false
print("other window " .. tostring(hoverBegin("help", { [window] = true })))
""")
    assert "WFJ test: a fight started, so hovering stopped in the friends window" in lines
    hovers = [ln for ln in lines if ln.startswith(("enter ", "leave "))]
    # the second row's tooltip, up when the fight started, is put away; the third row is never entered
    assert hovers == ["enter Friends.Row1 true hover", "leave Friends.Row1 true",
                      "enter Friends.Row2 true hover", "leave Friends.Row2 true"]
    assert "counts made=2 found=3 skipped=1 denied=0 tips=1 units=0 capped=nil stopped=a fight started" in lines
    assert "tooltip up after: false" in lines and "again false" in lines
    assert "other window true" in lines  # a fight stops the window it started in


def test_the_clients_own_script_runner_is_used_where_the_client_has_one(tmp_path):
    lines = _run_hover(tmp_path, r"""
function ExecuteFrameScript(frame, script, ...)
  log[#log + 1] = "client runs " .. script
  local handler = frame:GetScript(script)
  if handler then handler(frame, ...) end
end
local window = frame("Window", UIParent)
frame("Window.Row", window, { lines = { "Listed for" } })
drive("group finder", { [window] = true })
for _, line in ipairs(log) do print(line) end
print("part after " .. saved.test.part)
""")
    assert lines == ["client runs OnEnter", "enter Window.Row true hover", "client runs OnLeave",
                     "leave Window.Row true", "part after live"]


def test_the_sweep_hovers_each_page_before_the_next_click_and_the_hand_read_hovers_its_windows():
    lua = client_surface.TEXT_LUA
    sweep = lua[lua.index("local function WFJScanLiveSweep"):lua.index("SLASH_WFJLIVE1")]
    assert "db.hover = {}" in sweep  # each run starts its own record
    assert sweep.count("if hoverBegin(window, roots) then") == 2  # the window, then each page a click showed
    assert sweep.index('if state == "hover" then') < sweep.index("if InCombatLockdown() then return end")
    step = lua[lua.index("local function playerRead("):lua.index("local function WFJScanCharacterRead")]
    # the tooltip up is put away before the screen is read, and each read finds the page's new frames
    assert step.index("hoverStep(true)") < step.index("readScreen()") < step.index("hoverBegin(name, roots)")
    assert 'HAND_FRAMES = { guild = "CommunitiesFrame", character = "CharacterFrame" }' in lua
    # the hand read's hover record is kept with its lines, for the plain runs it stands for
    assert "hover = { guild = hover.guild, character = hover.character }" in lua


def test_the_hover_read_leaves_alone_every_widget_the_result_counts_as_protected():
    lua = client_surface.TEXT_LUA
    deny = lua[lua.index("local HOVER_DENY = {"):lua.index("-- the window being hovered")]
    for pattern, _ in client_surface.PROTECTED_NAME_WIDGETS:
        for part in pattern.pattern.split("|"):
            assert '"' + part.replace("\\.", "%%.") + '"' in deny, part


HOVER_SAVED = """
WFJScanDB = {
["probe"] = {
["test"] = { ["started"] = "a", ["finished"] = "b", ["build"] = "71037", ["hand"] = false },
["live"] = { ["(nothing open)"] = { ["english"] = { } } },
["hover"] = {
["guild"] = { ["made"] = 9, ["found"] = 12, ["skipped"] = 3, ["denied"] = 2, ["tips"] = 7, ["units"] = 1,
  ["english"] = {
    ["Level # Warrior"] = { ["n"] = 4, ["frame"] = "Roster.ScrollTarget.*", ["raw"] = "Level 60 Warrior" },
    ["Elwynn Forest"] = { ["n"] = 2, ["frame"] = "Roster.ScrollTarget.*", ["raw"] = "||cffffffffElwynn Forest||r" },
  },
  ["runs"] = { ["Kobold Vermin"] = { ["n"] = 1, ["frame"] = "Roster.Info", ["raw"] = "x" } } },
["calendar"] = { ["made"] = 60, ["found"] = 80, ["skipped"] = 20, ["denied"] = 0, ["tips"] = 30, ["capped"] = true,
  ["stopped"] = "a fight started", ["english"] = { }, ["runs"] = { } },
},
},
}
"""


def test_the_hover_read_is_read_per_window_and_english_fails_the_run_unless_allowed():
    hover = client_surface.read_hover(HOVER_SAVED)
    assert set(hover) == {"guild", "calendar"}
    guild = hover["guild"]
    assert (guild["made"], guild["skipped"], guild["denied"], guild["tips"], guild["units"]) == (9, 3, 2, 7, 1)
    assert guild["english"] == [(4, "Level # Warrior", "Roster.ScrollTarget.*", "Level 60 Warrior"),
                                (2, "Elwynn Forest", "Roster.ScrollTarget.*", "||cffffffffElwynn Forest||r")]
    assert hover["calendar"]["capped"] and hover["calendar"]["stopped"] == "a fight started"
    names = {"Elwynn Forest": "エルウィン・フォレスト", "Kobold Vermin": "コボルド・バーミン"}
    # names off: a game name stays English and fails nothing; the interface line still fails
    faults, allowed = client_surface.hover_faults(hover, {}, names, frozenset(), names_on=False)
    assert faults == [("guild", 4, "Level # Warrior", "Roster.ScrollTarget.*", "Level 60 Warrior")] and allowed == 2
    # names on: the name the list has Japanese for is left English, a fault
    faults, _ = client_surface.hover_faults(hover, {}, names, frozenset(), names_on=True)
    assert [f[2] for f in faults] == ["Level # Warrior", "Elwynn Forest", "Kobold Vermin"]
    # the baseline allows a line with its reason, on the window or a page of it
    baseline = {("guild", "(hover) Level # Warrior"): "a reason"}
    assert client_surface.hover_faults(hover, baseline, names, frozenset(), names_on=False)[0] == []
    problems = client_surface.hover_problems(hover, faults)
    assert problems == [
        "hover stopped in calendar: a fight started (run it again out of combat)",
        "English on hovered tooltips: 3 rows or words in 1 windows (listed below as HOVER)",
    ]


def test_a_run_with_no_hover_read_or_no_hover_fails_and_the_hand_reads_hover_stands_for_a_plain_run():
    assert client_surface.read_hover(SAVED) is None
    assert client_surface.hover_problems(None, [])[0].startswith("hover not read: this run's test addon")
    idle = {"map": {"made": 0, "stopped": "", "english": [], "runs": []}}
    assert client_surface.hover_problems(idle, []) == ["hover not read: no frame of any window was pointed at"]
    hand = HOVER_SAVED.replace('["hover"] = {\n["guild"]', '["hand"] = { ["build"] = "71037", ["at"] = "c", '
                               '["hover"] = {\n["guild"]', 1).replace('\n["calendar"]', ' } },\n["hover"] = {\n["calendar"]')
    assert set(client_surface.read_hover(hand)) == {"guild", "calendar"}
    # a hand read of another build stands for nothing
    assert set(client_surface.read_hover(hand.replace('"build"] = "71037", ["at"]', '"build"] = "1", ["at"]'))) == {
        "calendar"}


def test_the_result_command_prints_each_hovered_english_row_and_the_counts_per_window(tmp_path, capsys, monkeypatch):
    monkeypatch.setattr(client_surface, "_name_list", lambda: ({"Elwynn Forest": "エルウィン・フォレスト"}, frozenset()))
    saved = tmp_path / "WFJScan.lua"
    saved.write_text(HOVER_SAVED, encoding="utf-8")
    baseline = tmp_path / "ui_window_baseline.txt"
    baseline.write_text("guild\t(hover) Kobold Vermin\ta reason\ncalendar\t(hover) Gone Line\tfixed since\n",
                        encoding="utf-8")
    args = argparse.Namespace(saved=saved, baseline=baseline, log=None)
    assert client_surface._texts(args) == 1
    out = capsys.readouterr().out.splitlines()
    assert "hover: guild: 9 hovered, 3 skipped (7 tooltips read, 2 left alone)" in out
    assert "hover: calendar: 60 hovered, 20 skipped (30 tooltips read, 0 left alone, cap reached, stopped: a fight " \
           "started)" in out
    assert "HOVER x4 Level # Warrior (guild Roster.ScrollTarget.*: Level 60 Warrior)" in out
    assert not any(ln.startswith("HOVER") and "Kobold" in ln for ln in out)  # the baseline allows it
    assert not any(ln.startswith("HOVER") and "Elwynn" in ln for ln in out)  # a name, with names off
    assert "ERROR English on hovered tooltips: 1 rows or words in 1 windows (listed below as HOVER)" in out
    assert "gone  calendar\t(hover) Gone Line" in out  # a hover line the baseline still lists, no longer seen
