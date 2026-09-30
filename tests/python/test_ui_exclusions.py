"""The "cannot translate" exclusions. Menus and HelpTip callouts are translated (menus are in scope), so every key the menu and HelpTip surfaces may show is listed;
SocialUIFrame's keys cite the in-game check that the system is off on Forever; the wordless texture keys say "no
words"; and every composite exclusion says whether it is permanent or waits on a named follow-up form."""

import re
from pathlib import Path

from wfj.io import wago

ADDON = Path("addon/WoWForeverJapanese")
_EXCL = re.compile(r"^([A-Z][A-Z0-9_]*|ItemSubClass:\d+:\d+)\s+#\s+(\S.*)$")
_COMPOSITE = re.compile(r"composite|concatenated|fragment", re.IGNORECASE)


def _exclusions(root: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for raw in (root / "pipeline/ui_exclusions.txt").read_text(encoding="utf-8").splitlines():
        m = _EXCL.match(raw)
        if m:
            out[m.group(1)] = m.group(2)
    return out


def _block(text: str, start: str, end: str) -> str:
    assert start in text, start
    return text.split(start, 1)[1].split(end, 1)[0]


def _menu_keys(root: Path) -> set[str]:
    """Every key UI/Menus.lua names: each tag's `keys = { … }` / `tooltips = { … }` and the key lists
    declared before TAGS and shared by several tags (CHAT_SHORTCUT_KEYS, WORLD_MAP_FILTERS), and the unit menus'
    lists in UI/MenusUnit.lua (KEYS, TOOLTIPS); the tag data in UI/MenusTags.lua and the per-`which` lists in
    MenusUnit.WHICH (plain `{ … }` lists inside WHICH); the untagged menus' specs in UI/MenusUntagged.lua."""
    text = (root / ADDON / "UI/Menus.lua").read_text(encoding="utf-8")
    body = "local CHAT_SHORTCUT_KEYS = {" + _block(text, "local CHAT_SHORTCUT_KEYS = {", "\n}\n")
    unit = (root / ADDON / "UI/MenusUnit.lua").read_text(encoding="utf-8")
    body += unit + (root / ADDON / "UI/MenusTags.lua").read_text(encoding="utf-8")
    body += (root / ADDON / "UI/MenusUntagged.lua").read_text(encoding="utf-8")  # the untagged menus' specs
    keys: set[str] = set()
    if "WHICH" in unit:
        which = unit[unit.index("WHICH"):].split("function WFJ.MenusUnit.tags", 1)[0]  # the lists, not the builder
        keys |= set(re.findall(r'"([A-Z][A-Z0-9_]*)"', which))
    for m in re.finditer(r"\b(?:keys|tooltips|KEYS|TOOLTIPS|CHAT_SHORTCUT_KEYS|WORLD_MAP_FILTERS)\s*=\s*\{([^}]*)\}",
                         body):
        keys |= set(re.findall(r'"([A-Z][A-Z0-9_]*)"', m.group(1)))
    return keys


def _helptip_keys(root: Path) -> set[str]:
    text = (root / ADDON / "UI/HelpTips.lua").read_text(encoding="utf-8")
    body = _block(text, "HelpTips.KEYS = {", "}") + _block(text, "HelpTips.PLATE_KEYS = {", "}")  # and the help-plate tooltip's texts
    return set(re.findall(r'"([A-Z][A-Z0-9_]*)"', body))


def test_no_exclusion_keeps_the_lifted_no_menus_line(root):
    # menus are in scope, so no reason may rest on a "no menus" rule
    stale = {k: r for k, r in _exclusions(root).items() if "no menus" in r}
    assert not stale


def test_every_menu_and_helptip_key_is_listed(root):
    # a key the surface may show is a listed key, never an exclusion
    listed = set(wago.read_keys(root / "pipeline/ui_keys.txt"))
    excluded = set(_exclusions(root))
    menus, tips = _menu_keys(root), _helptip_keys(root)
    assert len(menus) > 50 and len(tips) >= 15  # the parse found the tables
    assert not (menus | tips) - listed
    assert not (menus | tips) & excluded


def test_socialui_reasons_cite_the_in_game_check(root):
    # SocialUIFrame is off on Forever (C_SocialUI.IsSystemEnabled() → false, checked in game). The card view's
    # reasons take the form "…IsSystemEnabled() (<source>), false on Forever"
    def cites(r):
        return "IsSystemEnabled() = false" in r or ("IsSystemEnabled()" in r and "false on Forever (in game" in r)

    missing = [k for k, r in _exclusions(root).items() if "SocialUIFrame" in r and not cites(r)]
    assert not missing
    assert any("SocialUIFrame" in r for r in _exclusions(root).values())


def test_wordless_texture_keys_say_no_words(root):
    # these carry a texture, but the reason they are excluded is that they have no words of their own
    excluded = _exclusions(root)
    for key in (
        "CURRENCY_QUANTITY_TEMPLATE",
        "ITEM_QUANTITY_TEMPLATE",
        # (not BONUS_OBJECTIVE_REWARD_WITH_COUNT_FORMAT: only the Classic Era inventory had it, no Forever window does)
        "COMMUNITY_MEMBER_NOTE_FORMAT",
        "SOCIAL_UI_FRIENDS_LIST_BATTLE_NET_FRIEND_NOTE_FORMAT",
        "SOCIAL_UI_FRIENDS_LIST_BATTLE_NET_FRIEND_NOTE_OFFLINE_FORMAT",
    ):
        assert "texture" not in excluded[key].lower(), key
        assert "no words" in excluded[key], key


def test_every_composite_reason_is_permanent_or_a_named_follow_up(root):
    # a composite is listed with the form that renders it, or its reason says it is permanent (and why) or
    # which form it waits on; no other composite reason
    excluded = _exclusions(root)
    loose = [k for k, r in excluded.items() if _COMPOSITE.search(r) and not r.startswith(("permanent: ", "follow-up: "))]
    assert not loose
    assert any(_COMPOSITE.search(r) for r in excluded.values())
    # the two composites a form now renders are listed (the quest list title tooltip; the Spirit paragraphs)
    listed = set(wago.read_keys(root / "pipeline/ui_keys.txt"))
    assert {"CLICK_QUEST_DETAILS", "SPIRIT_STANDING_WARNING"} <= listed
