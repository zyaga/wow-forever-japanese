-- UI/Inspect.lua: the inspect window on Forever (surface "inspect", area "ui", ADR-016 / ADR-029).
-- Blizzard_InspectUI is load-on-demand (its TOC: `## LoadOnDemand: 1`); InspectUnit loads it
-- (blizzard_inspectui/mainline/blizzard_inspectui_bootstrap.lua:3–15), called by the unit menu's Inspect entry
-- (blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:289) and by /inspect
-- (blizzard_chatframebase/shared/slashcommands.lua:917). `camelot` loads [Game]\Blizzard_InspectUI.lua|xml,
-- [Game]\InspectPaperDollFrame.xml, [Game]\InspectPVPFrame.lua|xml, [Game]\InspectGuildFrame.lua|xml and the
-- mainline paper doll code (the TOC's AllowLoadGameType lines). Three sub-frames, INSPECTFRAME_SUBFRAMES
-- (camelot/blizzard_inspectui.lua:11): InspectPaperDollFrame, InspectPVPFrame, InspectGuildFrame, picked by the
-- side mode tabs (InspectSwitchTabs, :154–162). The bottom tabs InspectFrameTab1–3 are hidden="true"
-- (camelot/blizzard_inspectui.xml:15, 28, 41).
-- Writers:
--   InspectPaperDollFrame:SetLevel (the frame's own mixin method, mainline/inspectpaperdollframe.lua:28–55) →
--     InspectLevelText, SetFormattedText(PLAYER_LEVEL | PLAYER_LEVEL_NO_SPEC, level, colour, [spec,] class): spec and
--     class are kept as written (the same keys UI/Character.lua shows on the player's own level line);
--   InspectPVPFrame:Update (the frame's own mixin method; OnShow and INSPECT_HONOR_UPDATE call it,
--     camelot/inspectpvpframe.lua:94–103, 105–133), each a MainInfoFrame field, as UI/PvPRank.lua covers the
--     player's own rank panel:
--     CurrentSeasonField   format(EXPANSION_SEASON_NAME, '', season) (:117)
--     CurrentRankField     PVP_RANK_NUMBER_AND_TITLE ("Rank %d - %s", %s = the rank title, kept English), or
--                          PVP_RANK_0_NAME ("Civilian", a rank title: left English) (:120–126)
--     CurrentRankProgressField  PVP_RANK_CURRENT_PROGRESS (:128)
--     HonorableKillsField  HONORABLE_KILLS (:130)
--     LifetimeHKsField / TodayHKsField  format("%s: %d", HONOR_LIFETIME | HONOR_TODAY, kills) (:131–132): the
--                          word is matched as a part and the ": <number>" tail kept as written;
--   InspectGuildFrame_Update (a global, called by name from InspectGuildFrame_OnShow and the INSPECT_READY handler,
--     camelot/inspectguildframe.lua:5–15, 17–34) → guildLevel INSPECT_GUILD_FACTION ("%s Guild", the faction's name
--     kept) and guildNumMembers INSPECT_GUILD_NUM_MEMBERS.
-- Help tooltips (GameTooltip, the owner registered with its own keys): an empty equipment slot's SetText(<SLOT>SLOT /
--   RELICSLOT) (mainline/inspectpaperdollframe.lua:223–233; the slot names are INSPECTPAPERDOLLFRAME_SLOTS,
--   camelot/blizzard_inspectui.lua:13–33), and the three side mode tabs InspectFrameModeTab1–3, whose tooltipText is
--   CHARACTER_INFO / PLAYER_V_PLAYER / GUILD (camelot/blizzard_inspectui.xml:60–74), shown by
--   SidePanelTabButtonMixin:OnEnter → SetText(self.tooltipText) (blizzard_sharedxml/mainline/
--   shareduipaneltemplates.lua:406–420).
-- Never touched: the window title, which is the inspected player's name (SetTitle(GetUnitName(…)), camelot/
--   blizzard_inspectui.lua:112, 141), the guild's name, and the PvP badge's rank number (NextRewardLevel's
--   LevelLabel, camelot/inspectpvpframe.lua:84).
--   A window without InspectPaperDollFrame is not this module's (nothing is set up).
local _, WFJ = ...
local Inspect = {}
WFJ.Inspect = Inspect

local SURFACE = "inspect"
Inspect.SURFACE = SURFACE
local Compat = WFJ.Compat
local ADDON = "Blizzard_InspectUI"

Inspect.NEVER_TOUCH = { "InspectFrame.TitleContainer.TitleText", "InspectGuildFrame.guildName",
  "InspectPVPFrame.MainInfoFrame.RankProgressBarDisplay.NextRewardLevel.LevelLabel" }

local SLOTS = { "InspectHeadSlot", "InspectNeckSlot", "InspectShoulderSlot", "InspectBackSlot", "InspectChestSlot",
  "InspectShirtSlot", "InspectTabardSlot", "InspectWristSlot", "InspectHandsSlot", "InspectWaistSlot",
  "InspectLegsSlot", "InspectFeetSlot", "InspectFinger0Slot", "InspectFinger1Slot", "InspectTrinket0Slot",
  "InspectTrinket1Slot", "InspectMainHandSlot", "InspectSecondaryHandSlot", "InspectRangedSlot" }
local SLOT_KEYS = { "HEADSLOT", "NECKSLOT", "SHOULDERSLOT", "BACKSLOT", "CHESTSLOT", "SHIRTSLOT", "TABARDSLOT",
  "WRISTSLOT", "HANDSSLOT", "WAISTSLOT", "LEGSSLOT", "FEETSLOT", "FINGER0SLOT", "FINGER1SLOT", "TRINKET0SLOT",
  "TRINKET1SLOT", "MAINHANDSLOT", "SECONDARYHANDSLOT", "RANGEDSLOT", "RELICSLOT" }
-- each side tab restricted to its one tooltipText key
local MODE_TABS = { { "InspectFrameModeTab1", "CHARACTER_INFO" }, { "InspectFrameModeTab2", "PLAYER_V_PLAYER" },
  { "InspectFrameModeTab3", "GUILD" } }

local PVP_INFO = "InspectPVPFrame.MainInfoFrame."
local CANDIDATES = {
  frame = { "InspectFrame" }, paperDoll = { "InspectPaperDollFrame" }, level = { "InspectLevelText" },
  pvp = { "InspectPVPFrame" }, season = { PVP_INFO .. "CurrentSeasonField" },
  rank = { PVP_INFO .. "CurrentRankField" }, progress = { PVP_INFO .. "CurrentRankProgressField" },
  kills = { PVP_INFO .. "HonorableKillsField" }, lifetime = { PVP_INFO .. "LifetimeHKsField" },
  today = { PVP_INFO .. "TodayHKsField" },
  guildUpdate = { "InspectGuildFrame_Update" }, guildFaction = { "InspectGuildFrame.guildLevel" },
  guildMembers = { "InspectGuildFrame.guildNumMembers" },
}

local LEVEL = { only = { "PLAYER_LEVEL", "PLAYER_LEVEL_NO_SPEC" } }
local FACTION = { only = { "INSPECT_GUILD_FACTION" } }
local MEMBERS = { only = { "INSPECT_GUILD_NUM_MEMBERS" } }
local SLOT_TOOLTIP = { only = SLOT_KEYS }
local PVP = {
  { "season", { only = { "EXPANSION_SEASON_NAME" } } },
  { "rank", { only = { "PVP_RANK_NUMBER_AND_TITLE" } } }, -- never PVP_RANK_0_NAME: a rank title stays English
  { "progress", { only = { "PVP_RANK_CURRENT_PROGRESS" } } },
  { "kills", { only = { "HONORABLE_KILLS" } } },
}
-- "<word>: <count>" lines: the record key, and the one word each may start with
local KILL_COUNTS = { { "lifetime", { "HONOR_LIFETIME" } }, { "today", { "HONOR_TODAY" } } }

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  for _, name in ipairs(SLOTS) do Compat.declare(SURFACE, "slot." .. name, { name }) end
  for _, tab in ipairs(MODE_TABS) do Compat.declare(SURFACE, "tab." .. tab[1], { tab[1] }) end
end

-- One kill count line: the word before ": " is a part restricted to `only`, the count after it kept as written; any
-- other text drops the record and stays as the client wrote it. → 1 | 0
local function showCount(recKey, only)
  local fs = WFJ.Labels.widget(get(recKey))
  local text = fs and fs:GetText()
  local head, count
  if type(text) == "string" then head, count = text:match("^(.-): (%-?%d+)$") end
  local part = head and WFJ.Labels.part(head, only)
  return WFJ.Labels.showArgs(SURFACE, recKey, get(recKey), part and part.key,
    part and { form = "seq", parts = { part, ": " .. count } } or nil)
end

-- hooksecurefunc target (InspectPaperDollFrame:SetLevel). → 1 | 0
function Inspect.onLevel()
  return WFJ.Labels.show(SURFACE, "level", get("level"), nil, LEVEL)
end

-- hooksecurefunc target (InspectPVPFrame:Update). → the number of dictionary words found.
function Inspect.onPvP()
  local n = 0
  for _, f in ipairs(PVP) do n = n + WFJ.Labels.show(SURFACE, f[1], get(f[1]), nil, f[2]) end
  for _, c in ipairs(KILL_COUNTS) do n = n + showCount(c[1], c[2]) end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- hooksecurefunc target (InspectGuildFrame_Update). → the number of dictionary words found.
function Inspect.onGuild()
  local n = WFJ.Labels.show(SURFACE, "guildFaction", get("guildFaction"), nil, FACTION)
    + WFJ.Labels.show(SURFACE, "guildMembers", get("guildMembers"), nil, MEMBERS)
  WFJ.Render.updateBanner(SURFACE)
  return n
end

local hooked = false

-- Blizzard_InspectUI's part: runs once the addon is loaded (now, or on its ADDON_LOADED). → true when set up.
function Inspect.setup()
  declare() -- its frames exist only now: forget what Compat memoized before
  local paperDoll = get("paperDoll")
  if type(get("frame")) ~= "table" or type(paperDoll) ~= "table" then return false end
  WFJ.Labels.forbidNames(Inspect.NEVER_TOUCH) -- its widgets exist only now (Main's registration found none)
  if hooked then return false end
  hooked = true
  if type(paperDoll.SetLevel) == "function" then hooksecurefunc(paperDoll, "SetLevel", Inspect.onLevel) end
  local pvp = get("pvp")
  if type(pvp) == "table" and type(pvp.Update) == "function" then hooksecurefunc(pvp, "Update", Inspect.onPvP) end
  if type(get("guildUpdate")) == "function" then hooksecurefunc("InspectGuildFrame_Update", Inspect.onGuild) end
  for _, name in ipairs(SLOTS) do
    local slot = get("slot." .. name)
    if type(slot) == "table" then WFJ.HelpTooltip.register(slot, SLOT_TOOLTIP) end
  end
  for _, tab in ipairs(MODE_TABS) do
    local owner = get("tab." .. tab[1])
    if type(owner) == "table" then WFJ.HelpTooltip.register(owner, { only = { tab[2] } }) end
  end
  Inspect.onLevel()
  Inspect.onPvP()
  Inspect.onGuild()
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init.
function Inspect.init()
  declare()
  return WFJ.LoadOnDemand.when(ADDON, Inspect.setup)
end
