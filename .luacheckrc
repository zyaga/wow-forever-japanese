-- luacheck config. Lua 5.1 (WoW). `bit` is deliberately NOT a read_global: the addon must not use it (ADR-005).
-- Likewise no `CreateFont` and no `GameFont*` / `SystemFont*` object: fonts are set per FontString.
std = "lua51"
max_line_length = 120
codes = true

-- Blizzard API surface the addon uses. Every new API call is a reviewable diff here.
read_globals = {
  "C_AddOns", "CreateFrame", "GetTime", "print", "strsplit", "tostring", "tonumber",
  "UnitName", "UnitClass", "UnitRace", "UnitGUID", "GetBuildInfo", "IsBetaBuild", "UnitSex", "UNKNOWNOBJECT",
  "IsAltKeyDown", "IsControlKeyDown", "IsShiftKeyDown",
  -- Quest surfaces: the hook primitive + the quest / quest-log getters. Frame and writer names are
  -- reached through Compat's injected env and inventoried in UI/QuestFrame.lua / UI/QuestMap.lua.
  "hooksecurefunc",
  "GetQuestID", "GetTitleText", "GetQuestText", "GetObjectiveText", "GetProgressText", "GetRewardText",
  "GetQuestLogSelection", "GetQuestLogTitle", "GetQuestLogQuestText",
  -- The modifier's side / bound polls, its override binding, key capture, the toggle binding the settings
  -- page writes, combat state. Client frames (AddonList, HideUIPanel, the list's functions) go through Compat.
  "IsLeftAltKeyDown", "IsRightAltKeyDown", "IsLeftControlKeyDown", "IsRightControlKeyDown", "IsLeftShiftKeyDown",
  "IsRightShiftKeyDown", "IsKeyDown", "IsMouseButtonDown", "InCombatLockdown",
  -- Retry fonts the client refused before the bundled font file loaded (a fresh launch)
  -- [verified: classic_era Blizzard_APIDocumentationGenerated/UITimerDocumentation.lua NewTicker].
  "C_Timer",
  "SetOverrideBinding", "ClearOverrideBindings", "GetBindingKey", "GetBindingAction", "GetBindingText", "SetBinding",
  "SaveBindings", "GetCurrentBindingSet", "GetConvertedKeyOrButton", "CreateKeyChordStringUsingMetaKeyState",
  "IsMetaKey",
  -- The fix window's saved-at time, its tab pool, its ScrollBox list and its window frame [verified:
  -- forever-ui-1.60.1.70009 Blizzard_SharedXML: ScrollBoxLinearView.lua:246, ScrollUtil.lua, DataProvider.lua:277,
  -- Mainline/SharedUIPanelTemplates.lua:111].
  "time", "CreateFramePool", "CreateScrollBoxListLinearView", "ScrollUtil", "CreateDataProvider",
  "ScrollBoxConstants", "ButtonFrameTemplate_HidePortrait",
}

-- Globals the addon defines (SavedVariables, slash registrations, bindings).
globals = {
  "SlashCmdList", "WFJ_DB", "WFJ_Collector", "SLASH_WFJ1", "SLASH_WFJ2", "BINDING_HEADER_WFJ", "BINDING_NAME_WFJ_TOGGLE",
  "WFJ_ToggleTranslation", "WFJ_RevealKey", "BINDING_NAME_WFJ_REVEAL",
  -- The TOC's AddonCompartmentFunc handlers (Blizzard's addon dropdown calls them by name)
  "WFJ_OnAddonCompartmentClick", "WFJ_OnAddonCompartmentEnter", "WFJ_OnAddonCompartmentLeave",
}

files["addon/WoWForeverJapanese/Data/"] = { ignore = { ".*" } }
files["tests/lua/"] = {
  std = "+busted",
  read_globals = {
    "arg", "GetRealmName",
    -- installed by wow_stub.installQuestAPI: the client's quest frames, widgets, writers, templates
    "QuestFrame", "QuestLogFrame", "QuestFrameProgressPanel", "QuestDetailScrollFrame", "QuestRewardScrollFrame", "QuestProgressScrollFrame",
    "QuestLogDetailScrollFrame", "QuestDetailScrollChildFrame", "QuestRewardScrollChildFrame",
    "QuestInfoTitleHeader", "QuestInfoDescriptionText", "QuestInfoObjectivesText", "QuestInfoRewardText",
    "QuestProgressTitleText", "QuestProgressText", "QuestLogQuestTitle", "QuestLogObjectivesText",
    "QuestLogQuestDescription", "QuestLogTitle1",
    "QuestInfo_Display", "QuestFrameProgressPanel_OnShow", "QuestLog_UpdateQuestDetails",
    "QUEST_TEMPLATE_DETAIL", "QUEST_TEMPLATE_REWARD", "QUEST_TEMPLATE_LOG",
    -- The labels, buttons, greeting panel and game menu the stub builds, and C_Item
    "QuestInfoDescriptionHeader", "QuestInfoObjectivesHeader", "QuestInfoRewardsFrame", "QuestInfoSpellObjectiveLearnLabel",
    "QuestProgressRequiredItemsText", "QuestFrameGreetingPanel", "CurrentQuestsText", "AvailableQuestsText", "GreetingText",
    "QuestFrameAcceptButton", "QuestFrameDeclineButton", "QuestFrameCompleteButton", "QuestFrameGoodbyeButton",
    "QuestFrameCompleteQuestButton", "QuestFrameGreetingGoodbyeButton", "QuestLogFrameAbandonButton",
    "QuestFramePushQuestButton", "QuestFrameExitButton", "QuestLogTitleText", "QuestLogDescriptionTitle",
    "GameMenuFrame", "C_Item", "QuestInfoGroupSize", "QuestLogCollapseAllButton", "EnumerateFrames",
    -- The gossip window and the greeting panel's scroll frame (gossip_client.lua, installQuestAPI)
    "GossipFrame", "C_GossipInfo", "GOSSIP_OPTION_PREPEND", "QUEST_PREPEND", "NORMAL_QUEST_DISPLAY",
    "QuestGreetingScrollFrame", "GetGreetingText",
    -- The stub AddOn List and the settings pages' tooltip, plus the key / binding API the specs drive
    "AddonList", "AddonList_InitAddon", "WFJSettingsTooltip",
  },
  globals = { "WFJ", "_G" },
}
