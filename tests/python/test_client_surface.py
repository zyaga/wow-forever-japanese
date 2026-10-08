"""The dependency manifest is built from the addon's own Lua, the probe asks the client about every
name in it, and the report classifies every entry."""

import re
from pathlib import Path

import pytest

from wfj.dev import client_surface as cs

ADDON = """
local SURFACE = "quest"
local TAB_WRITERS = { "QuestTabOne", "QuestTabTwo" }
local REGIONS = { title = "QuestTitleRegion" }

function Quest.init()
  Compat.declare(SURFACE, "frame", { "QuestFrame", "QuestFrameClassic" })
  for _, name in ipairs(TAB_WRITERS) do Compat.declare(SURFACE, name, { name }) end
  Compat.declare(SURFACE, "region", { REGIONS })
  Compat.declare(SURFACE, "dyn", { prefix .. "Suffix" })
  local widget = Compat.resolve("QuestProgressText")
  local made = Compat.resolve("QuestRow" .. i)
  local greeting = GetGreetingText()
  local loaded = C_AddOns.IsAddOnLoaded("Blizzard_TrainerUI")
  hooksecurefunc("QuestInfo_Display", Quest.onDisplay)
  frame:HookScript("OnShow", Quest.onShow)
end
"""


@pytest.fixture
def addon(tmp_path: Path) -> Path:
    root = tmp_path / "WoWForeverJapanese"
    (root / "UI").mkdir(parents=True)
    (root / "UI" / "QuestFrame.lua").write_text(ADDON, encoding="utf-8")
    return root


def _names(manifest, kind=None):
    return [e["name"] for e in manifest["entries"] if e.get("name") and (kind is None or e["kind"] == kind)]


def test_build_reads_every_call_shape(addon: Path):
    manifest = cs.build(addon)
    assert "QuestFrame" in _names(manifest) and "QuestFrameClassic" in _names(manifest)  # a literal list
    assert "QuestTabOne" in _names(manifest) and "QuestTabTwo" in _names(manifest)  # from the local table
    assert "QuestProgressText" in _names(manifest)  # Compat.resolve
    assert _names(manifest, "function") == ["QuestInfo_Display"]  # hooksecurefunc
    assert _names(manifest, "script") == ["OnShow"]  # HookScript
    assert _names(manifest, "api") == ["GetGreetingText", "C_AddOns.IsAddOnLoaded"]  # direct client APIs
    entry = next(e for e in manifest["entries"] if e["name"] == "QuestFrame")
    assert entry["file"] == "UI/QuestFrame.lua" and entry["surface"] == "questframe" and entry["line"] > 0


def test_a_name_it_cannot_resolve_is_kept_as_dynamic(addon: Path):
    manifest = cs.build(addon)
    dynamic = [e["dynamic"] for e in manifest["entries"] if not e.get("name")]
    assert any("prefix" in d for d in dynamic)  # the concatenated declare
    assert any("QuestRow" in d for d in dynamic)  # the concatenated resolve
    assert "QuestTitleRegion" in _names(cs.build(addon))  # a table it can expand is not dynamic
    assert "" not in dynamic


def test_build_refuses_a_missing_addon(tmp_path: Path):
    with pytest.raises(SystemExit, match="no addon directory"):
        cs.build(tmp_path / "nope")


def test_summary_counts_names_and_dynamics(addon: Path):
    lines = cs.summary(cs.build(addon))
    assert any(line.startswith("questframe: ") and "dynamic" in line for line in lines)
    assert lines[-1].startswith("total: ")


def test_a_declare_whose_candidates_are_a_variable_is_resolved_or_reported(tmp_path: Path):
    # the addon's dominant shape: `for key, names in pairs(CANDIDATES) do Compat.declare(S, key, names) end`
    root = tmp_path / "A"
    (root / "UI").mkdir(parents=True)
    (root / "UI" / "Bank.lua").write_text("""
local CANDIDATES = {
  frame = { "BankFrame" },
  cost = { "BankFrameSlotCost" },
}
function Bank.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  Compat.declare(SURFACE, "multi", {
    "BankSlotsFrame",
    "BankFramePurchaseInfo",
  })
end
""", encoding="utf-8")
    names = [e["name"] for e in cs.build(root)["entries"] if e.get("name")]
    assert {"BankFrame", "BankFrameSlotCost"} <= set(names)          # from the table of tables
    assert {"BankSlotsFrame", "BankFramePurchaseInfo"} <= set(names)  # a declare spanning lines


def test_a_commented_out_call_is_not_read_as_code(tmp_path: Path):
    root = tmp_path / "A"
    (root / "UI").mkdir(parents=True)
    (root / "UI" / "X.lua").write_text("""
-- Compat.declare(SURFACE, "ghost", { "GhostFrame" }) and GetGhostText() in prose
--[[ hooksecurefunc("BlockCommentFunction", fn) ]]
function X.init() Compat.declare(SURFACE, "real", { "RealFrame" }) end
""", encoding="utf-8")
    names = [e.get("name") for e in cs.build(root)["entries"]]
    assert "RealFrame" in names
    assert "GhostFrame" not in names and "GetGhostText" not in names
    assert "BlockCommentFunction" not in names


def test_a_method_hook_and_a_variable_script_type_are_recorded(tmp_path: Path):
    root = tmp_path / "A"
    (root / "UI").mkdir(parents=True)
    (root / "UI" / "Y.lua").write_text("""
local STATE_SCRIPTS = { "OnEnter", "OnMouseDown" }
function Y.init()
  hooksecurefunc(frame, "InitButtons", Y.onInit)
  for _, script in ipairs(STATE_SCRIPTS) do button:HookScript(script, Y.reapply) end
  other:HookScript(dynamicScript, Y.other)
end
""", encoding="utf-8")
    entries = cs.build(root)["entries"]
    assert ("method", "InitButtons") in [(e["kind"], e.get("name")) for e in entries]
    scripts = {e["name"] for e in entries if e["kind"] == "script" and e.get("name")}
    assert {"OnEnter", "OnMouseDown"} <= scripts
    assert any(e["kind"] == "script" and not e.get("name") for e in entries)  # the variable one, as dynamic


@pytest.mark.parametrize(
    ("answer", "in_source", "expected"),
    [
        ("yes", True, "works"),
        ("yes", False, "works"),
        ("no", True, "names only"),
        ("no", False, "rework"),
        (None, True, "unknown"),
        (None, False, "unknown"),
    ],
)
def test_verdict_reads_probe_first_then_source(answer, in_source, expected):
    entry = {"kind": "global", "name": "QuestFrame", "surface": "questframe"}
    probe = {"global|QuestFrame": answer} if answer else {}
    hits = {"QuestFrame": "questframe.lua" if in_source else ""}
    assert cs.verdict(entry, probe, hits)[0] == expected


def test_a_dynamic_entry_is_unknown_and_says_why():
    v, why = cs.verdict({"kind": "global", "name": None, "dynamic": 'p .. "Row"'}, {}, {})
    assert v == "unknown" and "dynamic" in why


def test_report_classifies_every_entry(addon: Path, tmp_path: Path):
    manifest = cs.build(addon)
    source = tmp_path / "ui"
    source.mkdir()
    (source / "questframe.lua").write_text("QuestFrame = CreateFrame('Frame')\n", encoding="utf-8")
    probe = {"global|QuestFrame": "yes", "script|OnShow": "no", "build": "11509"}
    result = cs.report(manifest, probe, source)
    assert result["build"] == "11509"
    assert len(result["rows"]) == len(manifest["entries"])
    assert all(r["verdict"] in ("works", "names only", "rework", "unknown") for r in result["rows"])
    assert all(r["evidence"] for r in result["rows"])
    counts = cs.by_surface(result["rows"])["questframe"]
    assert counts.get("works") and counts.get("unknown")


def test_source_hits_without_a_source_dir_is_empty(addon: Path):
    assert cs.source_hits(None, ["QuestFrame"]) == {}


SAVED = '''
WFJProbeDB = {
\t["build"] = {
\t\t"1.60.1", "69893", "Sep 17 2026", 11509,
\t},
\t["answers"] = {
\t\t["global|QuestFrame|questframe"] = "frame",
\t\t["function|QuestInfo_Display|questframe"] = "function",
\t\t["script|OnTooltipSetItem|tooltip"] = "no",
\t\t["api|C_AddOns.IsAddOnLoaded|loadondemand"] = "function",
\t\t["api|GetTrainerGreetingText|trainer"] = "no",
\t},
}
'''


def test_read_saved_variables_takes_the_clients_own_file():
    out = cs.read_saved_variables(SAVED)
    assert out["global|QuestFrame"] == "yes" and out["value|global|QuestFrame"] == "frame"
    assert out["function|QuestInfo_Display"] == "yes"
    assert out["script|OnTooltipSetItem"] == "no"
    assert out["api|C_AddOns.IsAddOnLoaded"] == "yes"  # a namespaced API the addon calls directly
    assert out["api|GetTrainerGreetingText"] == "no"
    assert out["build"] == "11509"  # the interface number the TOC needs
    assert out["version"] == "1.60.1"


def test_saved_variables_answers_feed_the_same_report(addon: Path):
    manifest = cs.build(addon)
    result = cs.report(manifest, cs.read_saved_variables(SAVED), None)
    verdicts = {r["name"]: r["verdict"] for r in result["rows"] if r.get("name")}
    assert verdicts["QuestFrame"] == "works"
    assert verdicts["QuestInfo_Display"] == "works"
    assert result["build"] == "11509"


def test_the_probe_is_one_lua_file_for_the_scan_addon(addon: Path, tmp_path: Path):
    import shutil
    import subprocess

    manifest = cs.build(addon)
    out = tmp_path / "WFJScan" / "WFJScanProbe.lua"
    m = tmp_path / "m.json"
    m.write_text(__import__("json").dumps(manifest), encoding="utf-8")
    assert cs.main(["probe", "--manifest", str(m), "--out", str(out)]) == 0
    assert [p.name for p in out.parent.iterdir()] == ["WFJScanProbe.lua"]  # no TOC: WFJScan's own TOC loads it
    lua = out.read_text(encoding="utf-8")
    for kind, name in cs.probe_names(manifest):
        assert f'{{"{kind}","{name}",' in lua
    assert "WFJProbeDB" not in lua and "WFJScanDB.probe" in lua
    luac = shutil.which("luac") or shutil.which("luac5.1")
    if luac:  # the client parses this file; a syntax error would waste an in-game run
        assert subprocess.run([luac, "-p", str(out)], capture_output=True, check=False).returncode == 0


def test_the_probe_addon_resolves_a_namespaced_api(addon: Path, tmp_path: Path):
    # a dotted name must be split on a plain "."; an escaped pattern makes every C_* API read as missing
    lua = cs.probe_lua(cs.build(addon))
    assert 'name:find(".", 1, true)' in lua
    assert "strsplit(" in lua and "root[field]" in lua
    # And it must be shared by every kind. Resolving dotted names only inside the function / api branch
    # made a *global* candidate written in dotted form (C_Spell.GetSpellDescription, Enum.TooltipDataType) read
    # as missing on every client, the same bug as the escaped pattern, one branch over.
    body = lua.partition("local function sweep()")[2]
    assert "local function valueOf(name)" in lua.partition("local function sweep()")[0]
    assert "local value = valueOf(name)" in body
    assert "value = _G[ns]" not in body


def test_a_load_on_demand_surface_is_unknown_not_rework_until_its_addon_loads(tmp_path: Path):
    root = tmp_path / "A"
    (root / "UI").mkdir(parents=True)
    (root / "UI" / "Trainer.lua").write_text(
        'function T.init()\n'
        '  WFJ.LoadOnDemand.on("Blizzard_TrainerUI", T.setup)\n'
        '  Compat.declare(SURFACE, "greeting", { "ClassTrainerGreetingText" })\n'
        'end\n', encoding="utf-8")
    manifest = cs.build(root)
    entry = next(e for e in manifest["entries"] if e.get("name") == "ClassTrainerGreetingText")
    assert entry["lod"] == ["Blizzard_TrainerUI"]
    absent = {"global|ClassTrainerGreetingText": "no"}
    v, why = cs.verdict(entry, absent, {})
    assert v == "unknown" and "Blizzard_TrainerUI" in why      # never loaded: absence proves nothing
    loaded = {**absent, "loaded|Blizzard_TrainerUI": "yes"}
    assert cs.verdict(entry, loaded, {})[0] == "rework"        # loaded and still absent: really gone


def test_read_saved_variables_records_which_addons_loaded():
    sv = ('WFJProbeDB = {\n["loaded"] = {\n["Blizzard_TrainerUI"] = true,\n},\n'
          '["answers"] = {\n["global|ClassTrainerGreetingText|trainer"] = "no",\n},\n}\n')
    out = cs.read_saved_variables(sv)
    assert out["loaded|Blizzard_TrainerUI"] == "yes"
    assert out["global|ClassTrainerGreetingText"] == "no"


def test_the_probe_addon_sweeps_again_when_an_addon_loads(tmp_path: Path):
    manifest = {"entries": [{"kind": "global", "name": "ClassTrainerFrame", "surface": "trainer"}]}
    lua = cs.probe_lua(manifest)
    assert 'RegisterEvent("ADDON_LOADED")' in lua
    assert "db.loaded[addon] = true" in lua
    assert 'if answer ~= "no" or db.answers[key] == nil then' in lua  # a later sweep only upgrades


def test_the_probe_addon_stamps_its_manifest_and_drops_other_answers(addon: Path, tmp_path: Path):
    # a client that still holds answers from an older manifest must not merge them
    lua = cs.probe_lua(cs.build(addon))
    assert re.search(r'local MANIFEST = "[0-9a-f]{12}"', lua)
    assert "db.manifest ~= MANIFEST" in lua
    other = cs.probe_lua({"entries": [{"kind": "global", "name": "Other", "surface": "x"}]})
    assert re.search(r'local MANIFEST = "([0-9a-f]{12})"', lua).group(1) != \
        re.search(r'local MANIFEST = "([0-9a-f]{12})"', other).group(1)


def test_a_method_hook_is_not_probed_as_a_global(tmp_path: Path):
    manifest = {"entries": [{"kind": "method", "name": "Update", "surface": "gossip"},
                            {"kind": "global", "name": "GossipFrame", "surface": "gossip"}]}
    assert cs.probe_names(manifest) == [("global", "GossipFrame")]
    v, why = cs.verdict(manifest["entries"][0], {}, {})
    assert v == "unknown" and "method hook" in why


def test_a_declare_the_parser_cannot_read_is_still_reported(tmp_path: Path):
    # a shape the regex cannot match must leave a dynamic row, never vanish
    root = tmp_path / "A"
    (root / "UI").mkdir(parents=True)
    (root / "UI" / "Z.lua").write_text(
        'function Z.init() Compat.declare(SURFACE, "k", { { "A" }, { "B" } }) end\n', encoding="utf-8")
    entries = cs.build(root)["entries"]
    assert entries and all(not e.get("name") for e in entries)
    assert any("cannot read" in e.get("dynamic", "") for e in entries)


def test_the_probe_resets_its_answers_when_the_client_build_changes(tmp_path: Path):
    manifest = {"entries": [{"kind": "global", "name": "QuestFrame", "surface": "questframe"}]}
    lua = cs.probe_lua(manifest)
    assert "db.client ~= build" in lua   # a patch that removes a frame must be able to say so
    assert "local build = select(2, GetBuildInfo())" in lua


# --- the window the player opened -------------------------------------------------------------
# The `lod` tag covers a surface whose Blizzard addon our own addon names in LoadOnDemand.when. A window the
# client builds on first show without a load-on-demand addon (guild is the open case) carries no tag, so
# without a second signal its absences read as proven even though nobody ever opened that window.

SAVED_WITH_ASKED = '''
WFJProbeDB = {
\t["build"] = {
\t\t"1.60.1", "69893", "Sep 17 2026", 16001,
\t},
\t["asked"] = {
\t\t["questlog"] = 2,
\t},
\t["answers"] = {
\t\t["global|QuestLogFrame|questlog"] = "no",
\t\t["global|GuildFrame|guild"] = "no",
\t},
}
'''


def test_asked_surfaces_reads_the_table_the_slash_command_writes():
    assert cs.asked_surfaces(SAVED_WITH_ASKED) == {"questlog": 2}


def test_a_probe_from_before_the_slash_command_has_none_and_keeps_the_lod_only_rule():
    # SAVED carries no ["asked"] table; None, not {}, so the older classification is kept rather than every
    # absence silently becoming unknown
    assert cs.asked_surfaces(SAVED) is None


@pytest.mark.parametrize(
    ("surface", "asked", "expected"),
    [
        ("questlog", {"questlog": 2}, "rework"),      # asked with the window open, still absent: real
        ("guild", {"questlog": 2}, "unknown"),        # never asked with its window open: no evidence
        ("guild", {"guild": 0}, "unknown"),
        ("guild", {"guild": 1}, "rework"),
        ("guild", None, "rework"),                    # an older probe keeps the lod-only rule
    ],
)
def test_an_absence_outside_a_lod_surface_only_counts_where_the_window_was_opened(surface, asked, expected):
    entry = {"kind": "global", "name": "GuildFrame", "surface": surface}
    assert cs.verdict(entry, {"global|GuildFrame": "no"}, {}, asked)[0] == expected


def test_the_lod_rule_still_wins_over_the_asked_rule():
    # a load-on-demand surface whose addon never loaded is unknown for that reason, which is the better message
    entry = {"kind": "global", "name": "ClassTrainerFrame", "surface": "trainer", "lod": ["Blizzard_TrainerUI"]}
    v, why = cs.verdict(entry, {"global|ClassTrainerFrame": "no"}, {}, {"trainer": 0})
    assert v == "unknown" and "Blizzard_TrainerUI was not loaded" in why


def test_a_present_answer_is_works_whatever_the_asked_table_says():
    entry = {"kind": "global", "name": "QuestFrame", "surface": "questframe"}
    assert cs.verdict(entry, {"global|QuestFrame": "yes"}, {}, {})[0] == "works"


def test_report_lists_the_surfaces_never_asked_with_their_window_open():
    manifest = {"entries": [
        {"kind": "global", "name": "QuestLogFrame", "surface": "questlog", "file": "f", "line": 1},
        {"kind": "global", "name": "GuildFrame", "surface": "guild", "file": "f", "line": 2},
    ]}
    asked = cs.asked_surfaces(SAVED_WITH_ASKED)
    result = cs.report(manifest, cs.read_saved_variables(SAVED_WITH_ASKED), None, asked)
    assert result["unopened"] == ["guild"]
    assert result["asked"] == asked
    verdicts = {r["surface"]: r["verdict"] for r in result["rows"]}
    assert verdicts["questlog"] == "rework"     # asked properly, still absent
    assert verdicts["guild"] == "unknown"       # absent, but never fairly asked


def test_report_without_an_asked_table_reports_no_unopened_surfaces():
    manifest = {"entries": [{"kind": "global", "name": "QuestFrame", "surface": "questframe",
                             "file": "f", "line": 1}]}
    result = cs.report(manifest, cs.read_saved_variables(SAVED), None, None)
    assert result["unopened"] == [] and result["asked"] is None


def test_the_probe_addon_offers_the_slash_command_and_tracks_what_is_left(addon: Path, tmp_path: Path):
    lua = cs.probe_lua(cs.build(addon))
    assert 'SLASH_WFJPROBE1 = "/wfjprobe"' in lua
    assert "db.asked[arg]" in lua                  # a manual sweep marks the surface it was told about
    assert "surfaces still unasked" in lua                 # in-game progress: what is left to do
    assert "asked = {}" in lua   # reset with the rest of the DB


# --- window-less surfaces and dotted names of any depth ---------------------------------------------


def _addon_with(tmp_path: Path, files: dict[str, str]) -> Path:
    root = tmp_path / "A"
    for rel, text in files.items():
        (root / rel).parent.mkdir(parents=True, exist_ok=True)
        (root / rel).write_text(text, encoding="utf-8")
    return root


def test_core_main_and_binding_modules_are_windowless_and_window_modules_are_not(tmp_path: Path):
    root = _addon_with(tmp_path, {
        "Core/Modifier.lua": 'local x = Compat.resolve("IsAltKeyDown")\n',
        "Main.lua": 'local y = Compat.resolve("C_AddOns.IsAddOnLoaded")\n',
        "UI/KeyCapture.lua": 'Compat.declare(SURFACE, "bind", { "GetBindingKey" })\n',
        "UI/RevealBinding.lua": 'Compat.declare(SURFACE, "clear", { "ClearOverrideBindings" })\n',
        "UI/Slash.lua": 'local z = Compat.resolve("SlashCmdList")\n',
        "UI/Mail.lua": 'Compat.declare(SURFACE, "frame", { "MailFrame" })\n',
    })
    by_surface = {e["surface"]: e.get("windowless", False) for e in cs.build(root)["entries"]}
    assert by_surface == {"modifier": True, "main": True, "keycapture": True, "revealbinding": True,
                          "slash": True, "mail": False}


@pytest.mark.parametrize(
    ("entry", "expected"),
    [
        # no `asked` entry, absent at the login sweep → rework, because there is no window to open
        ({"kind": "api", "name": "GetBindingKey", "surface": "keycapture", "windowless": True}, "rework"),
        ({"kind": "global", "name": "IsAltKeyDown", "surface": "modifier", "windowless": True}, "rework"),
        # the rule still holds for a window surface nobody opened
        ({"kind": "global", "name": "MailFrame", "surface": "mail"}, "unknown"),
    ],
)
def test_a_windowless_absence_is_rework_without_an_asked_entry(entry, expected):
    answer = {f"{entry['kind']}|{entry['name']}": "no"}
    assert cs.verdict(entry, answer, {}, {"questlog": 1})[0] == expected


def test_a_windowless_absence_still_in_the_source_is_names_only():
    entry = {"kind": "api", "name": "GetBindingKey", "surface": "keycapture", "windowless": True}
    assert cs.verdict(entry, {"api|GetBindingKey": "no"}, {"GetBindingKey": "bindingutil.lua"}, {})[0] == "names only"


def test_report_never_lists_a_windowless_surface_as_unopened():
    manifest = {"entries": [
        {"kind": "global", "name": "SlashCmdList", "surface": "slash", "windowless": True, "file": "f", "line": 1},
        {"kind": "global", "name": "MailFrame", "surface": "mail", "file": "f", "line": 2},
    ]}
    probe = {"global|SlashCmdList": "no", "global|MailFrame": "no"}
    result = cs.report(manifest, probe, None, {})
    assert result["unopened"] == ["mail"]
    assert {r["surface"]: r["verdict"] for r in result["rows"]} == {"slash": "rework", "mail": "unknown"}


def test_the_probe_addon_skips_windowless_surfaces_in_what_is_left(tmp_path: Path):
    manifest = {"entries": [
        {"kind": "global", "name": "SlashCmdList", "surface": "slash", "windowless": True},
        {"kind": "global", "name": "MailFrame", "surface": "mail"},
    ]}
    lua = cs.probe_lua(manifest)
    assert 'local WINDOWLESS = { ["slash"] = true, }' in lua
    assert "if not WINDOWLESS[surface] and" in lua
    assert "has no window" in lua


def test_saved_variables_parse_a_three_segment_name():
    # parser side: `_SV_ENTRY` took at most one dot, so a deeper answer was never read
    sv = ('WFJProbeDB = {\n["answers"] = {\n["global|Enum.TooltipDataType.Item|tooltip"] = "number",\n'
          '["function|C_Spell.GetSpellDescription|tooltip"] = "function",\n},\n}\n')
    out = cs.read_saved_variables(sv)
    assert out["global|Enum.TooltipDataType.Item"] == "yes"
    assert out["value|global|Enum.TooltipDataType.Item"] == "number"
    assert out["function|C_Spell.GetSpellDescription"] == "yes"


def _lua() -> str | None:
    import shutil

    return shutil.which("luajit") or shutil.which("lua5.1") or shutil.which("lua")


def test_the_probe_resolves_a_three_segment_name(tmp_path: Path):
    # probe side: valueOf walks every segment like Core/Compat.lua's lookup
    import subprocess

    manifest = {"entries": [{"kind": "global", "name": "Enum.TooltipDataType.Item", "surface": "tooltip"}]}
    lua = cs.probe_lua(manifest)
    fn = lua[lua.index("local function valueOf(name)"): lua.index("local function sweep()")]
    assert 'for _, segment in ipairs(segments) do' in fn
    interpreter = _lua()
    if interpreter is None:
        pytest.skip("no Lua interpreter")
    script = tmp_path / "walk.lua"
    script.write_text(
        # strsplit is the client's; this stand-in splits on a plain "." like it does
        'function strsplit(sep, s) local t = {} for p in s:gmatch("[^.]+") do t[#t + 1] = p end '
        'return unpack(t) end\n'
        'unpack = unpack or table.unpack\n'
        'Enum = { TooltipDataType = { Item = 0, Spell = 1 } }\n'
        'C_Spell = { GetSpellDescription = function() end }\n'
        'Scalar = 5\n'
        + fn +
        'print(valueOf("Enum.TooltipDataType.Item"), valueOf("Enum.TooltipDataType.Spell"),\n'
        '  type(valueOf("Enum.TooltipDataType")), type(valueOf("C_Spell.GetSpellDescription")),\n'
        '  valueOf("Enum.Missing.Item"), valueOf("Scalar.x.y"), valueOf("Nope.a.b"))\n',
        encoding="utf-8")
    run = subprocess.run([interpreter, str(script)], capture_output=True, text=True, check=False)
    assert run.returncode == 0, run.stderr
    assert run.stdout.split() == ["0", "1", "table", "function", "nil", "nil", "nil"]


# --- the probe lives in the scan dev addon -----------------------------------------------------------------
# It shares the scan's saved table, WFJScanDB, and may only ever replace WFJScanDB.probe: the rest is the quest
# scan's progress for the current build, which a probe reset must never cost.

_HARNESS = '''
unpack = unpack or table.unpack
function strsplit(sep, s) local t = {} for p in s:gmatch("[^.]+") do t[#t + 1] = p end return unpack(t) end
local handlers = {}
function CreateFrame()
  return { RegisterEvent = function() end, HasScript = function() return true end,
           SetScript = function(_, _, fn) handlers[#handlers + 1] = fn end }
end
BUILD = BUILD or "70245"
function GetBuildInfo() return "1.60.1", BUILD, "Oct 1 2026", 16001 end
SlashCmdList = {}
QuestFrame = {}
function print() end
local function fire(event, addon) for _, fn in ipairs(handlers) do fn(nil, event, addon) end end
'''

_SCAN_STATE = '''
WFJScanDB = { version = 1, builds = { ["1.60.1.70245"] = { phase = "recheck", pos = 42,
  answered = { [1] = true, [50001] = true } } } }
local builds, entry = WFJScanDB.builds, WFJScanDB.builds["1.60.1.70245"]
local function scanIntact()
  local e = WFJScanDB.builds["1.60.1.70245"]
  return WFJScanDB.version == 1 and WFJScanDB.builds == builds and e == entry and e.phase == "recheck"
    and e.pos == 42 and e.answered[1] == true and e.answered[50001] == true
end
'''

_MANIFEST = {"entries": [{"kind": "global", "name": "QuestFrame", "surface": "questframe"},
                         {"kind": "global", "name": "GoneFrame", "surface": "questframe"}]}


def _run_lua(tmp_path: Path, body: str) -> list[str]:
    import subprocess

    interpreter = _lua()
    if interpreter is None:
        pytest.skip("no Lua interpreter")
    script = tmp_path / "run.lua"
    script.write_text(body, encoding="utf-8")
    run = subprocess.run([interpreter, str(script)], capture_output=True, text=True, check=False)
    assert run.returncode == 0, run.stderr
    return run.stdout.split()


def _probe_chunk(manifest) -> str:
    # each load of the probe is its own chunk, as each /reload is in the client
    lua = cs.probe_lua(manifest)
    return "do\n" + _HARNESS + lua + "\nfire('PLAYER_LOGIN')\nend\n"


def test_the_probe_sweeps_into_its_own_table_and_leaves_the_scan_state_alone(tmp_path: Path):
    out = _run_lua(tmp_path, _SCAN_STATE + _probe_chunk(_MANIFEST) + '''
local p = WFJScanDB.probe
io.write(tostring(scanIntact()), " ", p.answers["global|QuestFrame|questframe"], " ",
  p.answers["global|GoneFrame|questframe"], " ", p.client, "\\n")
''')
    assert out == ["true", "frame", "no", "70245"]


def test_the_probe_creates_the_scan_table_when_there_is_none(tmp_path: Path):
    out = _run_lua(tmp_path, _probe_chunk(_MANIFEST) + '''
local keys = {}
for k in pairs(WFJScanDB) do keys[#keys + 1] = k end
io.write(table.concat(keys, ","), " ", WFJScanDB.probe.answers["global|QuestFrame|questframe"], "\\n")
''')
    assert out == ["probe", "frame"]


def test_a_new_manifest_or_build_resets_only_the_probe(tmp_path: Path):
    other = {"entries": [{"kind": "global", "name": "QuestFrame", "surface": "questframe"}]}
    out = _run_lua(tmp_path, _SCAN_STATE + _probe_chunk(_MANIFEST) + '''
WFJScanDB.probe.asked.questframe = 3
''' + _probe_chunk(other) + '''
io.write(tostring(scanIntact()), " ", tostring(WFJScanDB.probe.answers["global|GoneFrame|questframe"]), " ",
  tostring(WFJScanDB.probe.asked.questframe), "\\n")
WFJScanDB.probe.asked.questframe = 2
BUILD = "70300"
''' + _probe_chunk(other) + '''
io.write(tostring(scanIntact()), " ", WFJScanDB.probe.client, " ", tostring(WFJScanDB.probe.asked.questframe),
  "\\n")
''')
    # another manifest drops the old answers and the asked counts; so does another client build
    assert out == ["true", "nil", "nil", "true", "70300", "nil"]


def test_a_later_sweep_never_downgrades_a_found_answer(tmp_path: Path):
    out = _run_lua(tmp_path, _SCAN_STATE + _probe_chunk(_MANIFEST) + '''
WFJScanDB.probe.answers["global|GoneFrame|questframe"] = "frame"   -- found while its window was open
''' + _probe_chunk(_MANIFEST) + '''
io.write(tostring(scanIntact()), " ", WFJScanDB.probe.answers["global|GoneFrame|questframe"], "\\n")
''')
    assert out == ["true", "frame"]


SAVED_SCAN = '''
WFJScanDB = {
\t["builds"] = {
\t\t["1.60.1.70245"] = {
\t\t\t["phase"] = "done",
\t\t\t["build"] = {
\t\t\t\t"9.9.9", -- [1]
\t\t\t},
\t\t},
\t},
\t["probe"] = {
\t\t["client"] = "69893",
\t\t["build"] = {
\t\t\t"1.60.1", -- [1]
\t\t\t"69893", -- [2]
\t\t\t"Sep 17 2026", -- [3]
\t\t\t16001, -- [4]
\t\t},
\t\t["loaded"] = {
\t\t\t["Blizzard_TrainerUI"] = true,
\t\t},
\t\t["asked"] = {
\t\t\t["questlog"] = 2,
\t\t},
\t\t["answers"] = {
\t\t\t["global|QuestFrame|questframe"] = "frame",
\t\t\t["function|QuestInfo_Display|questframe"] = "function",
\t\t\t["script|OnTooltipSetItem|tooltip"] = "no",
\t\t\t["api|C_AddOns.IsAddOnLoaded|loadondemand"] = "function",
\t\t\t["api|GetTrainerGreetingText|trainer"] = "no",
\t\t},
\t},
\t["version"] = 1,
}
'''


def test_the_scan_addons_saved_file_reads_like_the_old_probe_file():
    out = cs.read_saved_variables(SAVED_SCAN)
    old = cs.read_saved_variables(SAVED)
    assert {k: v for k, v in out.items() if k not in ("build", "loaded|Blizzard_TrainerUI")} == \
        {k: v for k, v in old.items() if k != "build"}
    assert out["build"] == "16001" and out["version"] == "1.60.1"   # the probe's build, never the scan's
    assert out["loaded|Blizzard_TrainerUI"] == "yes"
    assert cs.asked_surfaces(SAVED_SCAN) == {"questlog": 2}
    assert cs.asked_surfaces(SAVED_SCAN.replace('\t\t["asked"] = {\n\t\t\t["questlog"] = 2,\n\t\t},\n', "")) is None


def test_report_reads_the_scan_addons_saved_file(addon: Path, tmp_path: Path, capsys):
    import json

    manifest = tmp_path / "m.json"
    manifest.write_text(json.dumps(cs.build(addon)), encoding="utf-8")
    saved = tmp_path / "WFJScan.lua"
    names = cs.probe_names(cs.build(addon))
    rows = "".join(f'\t\t\t["{k}|{n}|questframe"] = "frame",\n' for k, n in names)
    saved.write_text(SAVED_SCAN.replace('\t\t\t["global|QuestFrame|questframe"] = "frame",\n', rows),
                     encoding="utf-8")
    out = tmp_path / "v.json"
    assert cs.main(["report", "--manifest", str(manifest), "--probe", str(saved), "--out", str(out)]) == 0
    result = json.loads(out.read_text(encoding="utf-8"))
    assert result["build"] == "16001"
    assert {r["name"]: r["verdict"] for r in result["rows"] if r.get("name")}["QuestFrame"] == "works"
    assert "questframe:" in capsys.readouterr().out
