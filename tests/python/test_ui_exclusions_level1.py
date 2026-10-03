"""No stale exclusion on a level-1 path. Every key a level-1 widget asks for (the menu tags and the unit-menu lists,
the help plate and tutorial HelpTips, the chat header, the unit tooltip lines, the buff durations, the event toast,
the gossip prepend) is in the dictionary and never excluded, and none of them is still deferred to the menus and
callouts work. NUM_FREE_SLOTS, BACKGROUND and MACRO carry no stale reasons ("|4 plural grammar", "regex noise")."""

import re
from pathlib import Path

from wfj.io import wago

ADDON = "addon/WoWForeverJapanese"


def _exclusions(root: Path) -> dict[str, str]:
    out = {}
    for raw in (root / "pipeline/ui_exclusions.txt").read_text(encoding="utf-8").splitlines():
        if raw.strip() and not raw.startswith("#"):
            key, reason = raw.split("  # ", 1)
            out[key.strip()] = reason
    return out


def _quoted(text: str) -> set[str]:
    return set(re.findall(r'"([A-Z][A-Z0-9_]*)"', text))


def _block(text: str, start: str, end: str) -> str:
    assert start in text, start
    return text.split(start, 1)[1].split(end, 1)[0]


def _level1_keys(root: Path) -> set[str]:
    ui = root / ADDON / "UI"
    menus = (ui / "Menus.lua").read_text(encoding="utf-8")
    keys = _quoted(_block(menus, "local CHAT_SHORTCUT_KEYS = {", "\nlocal function specOf"))
    unit = (ui / "MenusUnit.lua").read_text(encoding="utf-8")
    keys |= _quoted(_block(unit, "KEYS = {", "},") + _block(unit, "TOOLTIPS = {", "},"))
    helptips = (ui / "HelpTips.lua").read_text(encoding="utf-8")
    keys |= _quoted(_block(helptips, "HelpTips.KEYS = {", "}") + _block(helptips, "HelpTips.PLATE_KEYS = {", "}"))
    keys |= _quoted(_block((ui / "TooltipUnit.lua").read_text(encoding="utf-8"), "TooltipUnit.KEYS = {", "}"))
    keys |= _quoted(_block((ui / "ChatTabs.lua").read_text(encoding="utf-8"), "local HEADER = {", "}"))
    keys |= _quoted(_block((ui / "HudLabels.lua").read_text(encoding="utf-8"), "local DURATION = {", "}"))
    alerts = (ui / "Alerts.lua").read_text(encoding="utf-8")
    keys |= _quoted(_block(alerts, "local TOAST_TITLE_KEYS = {", "}") + _block(alerts, "local TOAST_DESCRIPTION = {", "\n"))
    keys |= {"GOSSIP_OPTION_PREPEND", "QUEST_PREPEND"}
    return keys


def test_every_level1_widget_key_is_listed_and_none_is_excluded(root):
    keys = _level1_keys(root)
    assert len(keys) > 150  # the whole set, not a sample
    listed = set(wago.read_keys(root / "pipeline/ui_keys.txt"))
    excluded = _exclusions(root)
    assert sorted(keys - listed) == []
    assert sorted(keys & set(excluded)) == []


def test_stale_level1_reasons_stay_gone(root):
    excluded = _exclusions(root)
    # the three stale reasons stay gone
    listed = set(wago.read_keys(root / "pipeline/ui_keys.txt"))
    assert {"NUM_FREE_SLOTS", "BACKGROUND", "MACRO"} <= listed
    assert not {"NUM_FREE_SLOTS", "BACKGROUND", "MACRO"} & set(excluded)


def test_the_options_window_tooltips_moved_out_of_the_composite_exclusion(root):
    # the "<label>: <tooltip>" composite is rendered now (UIStrings optionTip); no option tooltip is still
    # excluded for it, and the two sample spell names the Options window speaks stay English (names stay in English)
    excluded = _exclusions(root)
    assert not [k for k, r in excluded.items() if r.startswith("a dropdown option's tooltip")]
    assert "name" in excluded["CAA_SAMPLE_SPELLNAME"] and "name" in excluded["CAA_SAMPLE_DEBUFFNAME"]
