"""ADR-016: the calls and field writes that carry taint or break Blizzard's layout never appear in the
addon. Hooks (`hooksecurefunc`, `HookScript`) are the only ways in; frames are owned only by Main.lua and
UI/Options.lua. Comments are ignored. Other writes to Blizzard tables are left to code review (a grep cannot
tell the addon's tables from Blizzard's)."""

import re
from pathlib import Path

import pytest

ADDON = Path("addon/WoWForeverJapanese")
# ADR-018: the settings UI modules create and script only their own frames (the pages' widgets, the key
# capture button, the override-binding owner, the AddOn List button), never a Blizzard frame's scripts.
FRAME_OWNERS = {"Main.lua", "UI/Options.lua", "UI/OptionsWidgets.lua", "UI/KeyCapture.lua", "UI/RevealBinding.lua",
                "UI/AddonListButton.lua",
                # the word-reading box scripts only its own covers (hover) and never a Blizzard frame
                "UI/Readings.lua",
                # the fix window and the minimap button script only their own frames
                "UI/FixWindow.lua", "UI/MinimapButton.lua"}

PATTERNS = {
    "PanelTemplates_SetTab": re.compile(r"\bPanelTemplates_SetTab\s*\("),
    "PanelTemplates_UpdateTabs": re.compile(r"\bPanelTemplates_UpdateTabs\s*\("),
    "PanelTemplates_SetDisabledTabState": re.compile(r"\bPanelTemplates_SetDisabledTabState\s*\("),
    "PanelTemplates_TabResize": re.compile(r"\bPanelTemplates_TabResize\s*\("),
    "ShowUIPanel": re.compile(r"\bShowUIPanel\s*\("),
    "HideUIPanel": re.compile(r"\bHideUIPanel\s*\("),
    "SetTextToFit": re.compile(r":SetTextToFit\s*\("),
    "UpdateButton call": re.compile(r":UpdateButton\s*\("),
    "SpellBookFrame:Update": re.compile(r"\bSpellBookFrame:Update\s*\("),
    ".selectedTab =": re.compile(r"\.selectedTab\s*=(?!=)"),
    ".bookType =": re.compile(r"\.bookType\s*=(?!=)"),
    ".tooltipText =": re.compile(r"\.tooltipText\s*=(?!=)"),
    ".UpdateTooltip =": re.compile(r"\.UpdateTooltip\s*=(?!=)"),
    "UIPanelWindows": re.compile(r"\bUIPanelWindows\b"),
    "Menu.ModifyMenu": re.compile(r"\bMenu\.ModifyMenu\b"),
}
SET_SCRIPT = re.compile(r":SetScript\s*\(")


def _code(text: str) -> str:
    """Lua with comments and string literals blanked (a pattern named in a comment or a string is not a call)."""
    text = re.sub(r"--\[(=*)\[.*?\]\1\]", "", text, flags=re.S)
    text = re.sub(r"--[^\n]*", "", text)
    return re.sub(r'"(?:\\.|[^"\\\n])*"|\'(?:\\.|[^\'\\\n])*\'', '""', text)


def violations(rel: str, text: str) -> list[str]:
    code = _code(text)
    out = [f"{rel}: {name}" for name, pat in PATTERNS.items() if pat.search(code)]
    if rel not in FRAME_OWNERS and SET_SCRIPT.search(code):
        out.append(f"{rel}: SetScript")
    return out


@pytest.mark.parametrize("name", [*PATTERNS, "SetScript"])
def test_each_pattern_is_detected(name):
    samples = {
        "PanelTemplates_SetTab": "PanelTemplates_SetTab(f, 2)",
        "PanelTemplates_UpdateTabs": "PanelTemplates_UpdateTabs (f)",
        "PanelTemplates_SetDisabledTabState": "PanelTemplates_SetDisabledTabState(t)",
        "PanelTemplates_TabResize": "PanelTemplates_TabResize(t, 0)",
        "ShowUIPanel": "ShowUIPanel(CharacterFrame)",
        "HideUIPanel": "HideUIPanel(CharacterFrame)",
        "SetTextToFit": "b:SetTextToFit(x)",
        "UpdateButton call": "button:UpdateButton()",
        "SpellBookFrame:Update": "SpellBookFrame:Update()",
        ".selectedTab =": "frame.selectedTab = 2",
        ".bookType =": "SpellBookFrame.bookType = 'pet'",
        ".tooltipText =": "b.tooltipText = x",
        ".UpdateTooltip =": "slot.UpdateTooltip = fn",
        "UIPanelWindows": "local w = UIPanelWindows.CharacterFrame",
        "Menu.ModifyMenu": "Menu.ModifyMenu('MENU_X', fn)",
        "SetScript": "frame:SetScript('OnShow', fn)",
    }
    found = violations("UI/Example.lua", samples[name])
    assert found, name
    # the same text in a comment or a string is not a call
    assert violations("UI/Example.lua", f"-- {samples[name]}\nlocal s = \"{samples[name].replace(chr(39), '')}\"") == []


def test_comparisons_and_frame_owners_are_allowed():
    assert violations("UI/Example.lua", "if frame.selectedTab == 3 then end") == []
    assert violations("Main.lua", "frame:SetScript('OnEvent', fn)") == []
    assert violations("UI/Example.lua", "hooksecurefunc(button, 'UpdateButton', fn)") == []


def test_the_addon_has_none(root):
    found = []
    for path in sorted((root / ADDON).rglob("*.lua")):
        rel = path.relative_to(root / ADDON).as_posix()
        if rel.startswith("Data/"):
            continue
        found += violations(rel, path.read_text(encoding="utf-8"))
    assert found == []


# The addon hooks no NPC-chatter, speech-bubble, subtitle, screen-tutorial or new-player-experience frame outside the
# module that owns it. Only UI/Speech.lua (NPC speech: raid boss emotes and chat bubbles) may name the chatter frames
# and only UI/Subtitles.lua (cinematic subtitle lines) the subtitle frame; nothing names the NPE / screen-tutorial code.
SCOPE_NAMES = ("SubtitlesFrame", "SHOW_SUBTITLE", "RaidBossEmoteFrame", "CHAT_MSG_RAID_BOSS_EMOTE", "ChatBubble",
               "TutorialMainFrame", "NewPlayerExperience")
OWNED = {
    "UI/Speech.lua": {"RaidBossEmoteFrame", "CHAT_MSG_RAID_BOSS_EMOTE", "ChatBubble"},
    "UI/Subtitles.lua": {"SubtitlesFrame", "SHOW_SUBTITLE"},
}


def test_no_subtitle_or_npe_hook(root):
    found = []
    for path in sorted((root / ADDON).rglob("*.lua")):
        rel = path.relative_to(root / ADDON).as_posix()
        if rel.startswith("Data/"):
            continue
        text = path.read_text(encoding="utf-8")
        for name in SCOPE_NAMES:
            if name in text and name not in OWNED.get(rel, set()):
                found.append(f"{rel}: {name}")
    assert found == []
