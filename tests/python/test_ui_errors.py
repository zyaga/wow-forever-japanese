"""The UI errors frame (ADR-035). Every Forever ERR_* / SPELL_FAILED_* key is inventoried for the `errors`
surface, each one listed or excluded (the coverage test holds that), and every exclusion of one says why
in one of the ways ADR-035 allows."""

import re
from pathlib import Path

from test_ui_coverage import _exclusions, _inventory

from wfj.dev import ui_inventory

ERROR_KEY = re.compile(r"^(ERR|SPELL_FAILED)_[A-Z0-9_]+$")

# The reasons an error key may be excluded for: a pass-through wrapper, a link the dictionary never carries, a system
# the Forever client does not have (named with its evidence), and four more (a
# chat-only line, a unit menu entry, a housing screenshot reason, a retail-era system).
ALLOWED = re.compile(
    r"^a pass-through wrapper: its English is only \"%s\""
    r"|^a link \(\|H…\|h\) the dictionary never carries"
    r"|^not on Forever: .+(forever_addon_dispositions\.txt|\.toc)\)$"
    r"|chat / system message line|ChatFrameUtil|DEFAULT_CHAT_FRAME|primary chat frame"
    r"|^not displayed on Forever: |^a retail-era system"
)


def test_every_forever_error_key_is_inventoried_for_the_errors_surface(root: Path):
    assert "errors" in ui_inventory.DYNAMIC and "errors" in ui_inventory.FOREVER_WINDOWS
    inventory = _inventory(root)
    for surface in ("errors", "chatsystem"):  # the frame, and the same keys as SYSTEM chat lines (re-plan)
        keys = {k for k, surfaces in inventory.items() if surface in surfaces and ERROR_KEY.match(k)}
        assert len(keys) == 2723, surface  # every Forever 1.60.1.70170 ERR_* / SPELL_FAILED_* key with English (2,722 on 70009)


def test_the_keys_blizzards_lua_puts_in_the_frame_are_inventoried(root: Path):
    # named on an UIErrorsFrame call in the load set, or a helper family that feeds one
    errors = {k for k, surfaces in _inventory(root).items() if "errors" in surfaces}
    for key in ("ERR_NOT_ENOUGH_MONEY", "PAPERDOLL_AUTO_EQUIP_MINING_ONLY", "EQUIPMENT_SETS_TOO_MANY",
                "ERROR_CLUB_ACTION_INVITE_MEMBER", "ERROR_COMMUNITIES_IGNORED", "GUILD_RENAME_ERROR_NAME_INVALID",
                "REPORT_RESULT_TOO_MANY_REPORTS", "PING_FAILED_SPAMMING", "TOO_MANY_WATCHED_TOKENS"):
        assert key in errors, key


def test_the_uierrorsframe_is_a_surface(root: Path):
    lines = (root / "pipeline/forever_addon_dispositions.txt").read_text(encoding="utf-8").splitlines()
    (line,) = [ln for ln in lines if ln.startswith("blizzard_uierrorsframe ")]
    assert line.split()[1:3] == ["surface", "errors"]


def test_every_error_key_exclusion_gives_an_allowed_reason(root: Path):
    bad = {k: r for k, r in _exclusions(root).items() if ERROR_KEY.match(k) and not ALLOWED.search(r)}
    assert bad == {}


def test_no_errors_key_is_excluded_for_being_an_errors_frame_line(root: Path):
    # the errors frame is a surface now: "an error line, not window text: UIErrorsFrame" is no reason for any key it
    # can show (re-plan: the Lua-added lines' keys too)
    errors = {k for k, surfaces in _inventory(root).items() if "errors" in surfaces}
    stale = {k: r for k, r in _exclusions(root).items() if k in errors and "UIErrorsFrame" in r}
    assert stale == {}


def test_validate_mirrors_the_addon_argument_kinds():
    # Core/UIStrings.lua argKinds: the declared kinds, else every `%s` of an error key is `text`, else none
    from wfj.cmd import validate

    declared = {"ERR_ATTACK_PREVENTED_BY_MECHANIC_S": {1: "words"}}
    assert validate.key_arg_kinds("ERR_ATTACK_PREVENTED_BY_MECHANIC_S", declared) == {1: "words"}
    assert validate.key_arg_kinds("ERR_QUEST_ADD_KILL_SII", declared).get(1) == "text"
    assert validate.key_arg_kinds("SPELL_FAILED_ANYTHING", declared).get(3) == "text"
    assert validate.key_arg_kinds("QUEST_MONSTERS_KILLED", declared) == {}


def test_validate_reads_the_chat_families_from_the_addon(root: Path):
    # Core/UIStringKeys.lua CHAT_FAMILIES is the one list; validate reads it and gives a family key the
    # addon's all-`text` kinds, a declared key its declared kinds, and a key outside every family none
    from wfj.cmd import validate

    chat = validate.ui_chat_families(root / "addon" / "WoWForeverJapanese")
    assert len(chat) >= 30
    assert validate.key_arg_kinds("LOOT_ITEM_SELF", {}, chat).get(1) == "text"
    assert validate.key_arg_kinds("COMBATLOG_XPGAIN_FIRSTPERSON", {}, chat).get(2) == "text"
    assert validate.key_arg_kinds("LEVEL_UP_STAT", {"LEVEL_UP_STAT": {1: "words"}}, chat) == {1: "words"}
    assert validate.key_arg_kinds("QUEST_MONSTERS_KILLED", {}, chat) == {}


def test_no_listed_system_chat_template_matches_unrestricted(root: Path):
    # A listed key the chat surface inventories whose English captures `%s` must be matched by key only: an error
    # key, a CHAT_FAMILIES key, or in UIStrings.ONLY. Anything else would become an unrestricted template on every
    # surface. CHAT_FAMILIES and ui_inventory's chatsystem families are two lists, so this test keeps them in step.
    import json

    from wfj.cmd import validate

    lua = (root / "addon/WoWForeverJapanese/Core/UIStringKeys.lua").read_text(encoding="utf-8")
    block = re.search(r"UIStrings\.ONLY = \{(.*?)\n\}", lua, re.S)
    assert block
    only = set(re.findall(r"([A-Z0-9_]+) = true", block.group(1)))
    chat = validate.ui_chat_families(root / "addon" / "WoWForeverJapanese")
    listed = {ln.strip() for ln in (root / "pipeline/ui_keys.txt").read_text(encoding="utf-8").splitlines()
              if ln.strip() and not ln.startswith("#")}
    english = {}
    for path in (root / "data/english/ui").glob("*.jsonl"):
        for line in path.read_text(encoding="utf-8").splitlines():
            row = json.loads(line)
            english[row["id"]] = row["en"]
    chat_keys = {k for k, surfaces in _inventory(root).items() if "chatsystem" in surfaces}
    loose = sorted(k for k in chat_keys & listed if "%s" in english.get(k, "") and not validate.is_error_key(k)
                   and not any(p.search(k) for p in chat) and k not in only)
    assert loose == []


def test_the_lines_blizzards_lua_prints_into_chat_are_inventoried(root: Path):
    # ui_inventory.chat_call_keys scans the load set for
    # AddSystemMessage / DisplaySystemMessage* / DEFAULT_CHAT_FRAME:AddMessage calls
    chat = {k for k, surfaces in _inventory(root).items() if "chatsystem" in surfaces}
    for key in ("ONLINE_SAFETY_NOTICE", "CHATLOGENABLED", "ROLE_CHANGED_INFORM", "READY_CHECK_YOU_WERE_AFK",
                "NO_RAID_INSTANCES_SAVED"):
        assert key in chat, key
    assert ui_inventory._CHAT_CALL.search('ChatFrameUtil.AddSystemMessage(ONLINE_SAFETY_NOTICE);')
    assert ui_inventory._CHAT_CALL.search("DEFAULT_CHAT_FRAME:AddMessage(CHATLOGDISABLED, info.r, info.g, info.b)")


def test_no_chat_key_is_excluded_for_being_a_chat_line(root: Path):
    # chat is a surface: "a chat / system message line, not window text" is no reason any more
    chat = {k for k, surfaces in _inventory(root).items() if "chatsystem" in surfaces}
    stale = re.compile(r"chat / (error / )?system message line|not window text|not a window|^a chat line")
    assert {k: r for k, r in _exclusions(root).items() if k in chat and stale.search(r)} == {}
