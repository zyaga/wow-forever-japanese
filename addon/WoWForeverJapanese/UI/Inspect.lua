-- UI/Inspect.lua: the inspect window on Forever (surface "inspect", area "ui", ADR-016 / ADR-029).
-- Blizzard_InspectUI is load-on-demand (its TOC: `## LoadOnDemand: 1`); InspectUnit loads it
-- (blizzard_inspectui/mainline/blizzard_inspectui_bootstrap.lua:3–15), called by the unit menu's Inspect entry
-- (blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:289) and by /inspect
-- (blizzard_chatframebase/shared/slashcommands.lua:917). `camelot` loads [Game]\Blizzard_InspectUI.lua|xml,
-- [Game]\Blizzard_InspectUI_Overrides.lua, [Game]\InspectPaperDollFrame.xml and the mainline paper doll / PvP / guild
-- files (the TOC's AllowLoadGameType lines). The overrides file runs after the main file and leaves two sub-frames,
-- InspectPaperDollFrame and InspectGuildFrame (camelot/blizzard_inspectui_overrides.lua:2): InspectPVPFrame is
-- built but never shown (InspectSwitchTabs only shows INSPECTFRAME_SUBFRAMES, camelot/blizzard_inspectui.lua:185–198),
-- the guild's realm line and achievement points are hidden (overrides.lua:35–41, mainline/inspectguildframe.lua:
-- 16–17), and the bottom tabs InspectFrameTab1 / 2 are hidden="true" (camelot/blizzard_inspectui.xml:15, 27).
-- Static labels (XML text=): InspectPaperDollFrame.InspectTalents INSPECT_TALENTS_BUTTON (camelot/
--   inspectpaperdollframe.xml:77–78).
-- Writers:
--   InspectPaperDollFrame:SetLevel (the frame's own mixin method, mainline/inspectpaperdollframe.lua:28–55) →
--     InspectLevelText, SetFormattedText(PLAYER_LEVEL | PLAYER_LEVEL_NO_SPEC, level, colour, [spec,] class): spec and
--     class are kept as written (the same keys UI/Character.lua shows on the player's own level line);
--   InspectGuildFrame_Update (a global, called by name from InspectGuildFrame_OnShow and the INSPECT_READY handler,
--     mainline/inspectguildframe.lua:6–18, 20–37) → guildLevel INSPECT_GUILD_FACTION ("%s Guild", the faction's name
--     kept) and guildNumMembers INSPECT_GUILD_NUM_MEMBERS.
-- Help tooltips (GameTooltip, the owner registered with its own keys): the Talents button's UNAVAILABLE line
--   (GameTooltip_AddErrorLine, inspectpaperdollframe.lua:285–293) and an empty equipment slot's SetText(<SLOT>SLOT /
--   RELICSLOT) (lua:223–233; the slot names are INSPECTPAPERDOLLFRAME_SLOTS, overrides.lua:9–29).
-- Never touched: the window title, which is the inspected player's name (SetTitle(GetUnitName(…)), camelot/
--   blizzard_inspectui.lua:138, 155, 168), the guild's name, the hidden realm line.
--   A window without InspectPaperDollFrame.InspectTalents is not this module's (nothing is set up).
local _, WFJ = ...
local Inspect = {}
WFJ.Inspect = Inspect

local SURFACE = "inspect"
Inspect.SURFACE = SURFACE
local Compat = WFJ.Compat
local ADDON = "Blizzard_InspectUI"

Inspect.NEVER_TOUCH = { "InspectFrame.TitleContainer.TitleText", "InspectGuildFrame.guildName",
  "InspectGuildFrame.guildRealmName" }

local SLOTS = { "InspectHeadSlot", "InspectNeckSlot", "InspectShoulderSlot", "InspectBackSlot", "InspectChestSlot",
  "InspectShirtSlot", "InspectTabardSlot", "InspectWristSlot", "InspectHandsSlot", "InspectWaistSlot",
  "InspectLegsSlot", "InspectFeetSlot", "InspectFinger0Slot", "InspectFinger1Slot", "InspectTrinket0Slot",
  "InspectTrinket1Slot", "InspectMainHandSlot", "InspectSecondaryHandSlot", "InspectRangedSlot" }
local SLOT_KEYS = { "HEADSLOT", "NECKSLOT", "SHOULDERSLOT", "BACKSLOT", "CHESTSLOT", "SHIRTSLOT", "TABARDSLOT",
  "WRISTSLOT", "HANDSSLOT", "WAISTSLOT", "LEGSSLOT", "FEETSLOT", "FINGER0SLOT", "FINGER1SLOT", "TRINKET0SLOT",
  "TRINKET1SLOT", "MAINHANDSLOT", "SECONDARYHANDSLOT", "RANGEDSLOT", "RELICSLOT" }

local CANDIDATES = {
  frame = { "InspectFrame" }, paperDoll = { "InspectPaperDollFrame" },
  talents = { "InspectPaperDollFrame.InspectTalents" }, level = { "InspectLevelText" },
  guildUpdate = { "InspectGuildFrame_Update" }, guildFaction = { "InspectGuildFrame.guildLevel" },
  guildMembers = { "InspectGuildFrame.guildNumMembers" },
}

local TALENTS = { only = { "INSPECT_TALENTS_BUTTON" } }
local TALENTS_TOOLTIP = { only = { "UNAVAILABLE" } }
local LEVEL = { only = { "PLAYER_LEVEL", "PLAYER_LEVEL_NO_SPEC" } }
local FACTION = { only = { "INSPECT_GUILD_FACTION" } }
local MEMBERS = { only = { "INSPECT_GUILD_NUM_MEMBERS" } }
local SLOT_TOOLTIP = { only = SLOT_KEYS }

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  for _, name in ipairs(SLOTS) do Compat.declare(SURFACE, "slot." .. name, { name }) end
end

-- The label the client writes once at load. → 1 | 0
function Inspect.showStatic()
  local n = WFJ.Labels.show(SURFACE, "talents", get("talents"), nil, TALENTS)
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- hooksecurefunc target (InspectPaperDollFrame:SetLevel). → 1 | 0
function Inspect.onLevel()
  return WFJ.Labels.show(SURFACE, "level", get("level"), nil, LEVEL)
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
  local talents = get("talents")
  if type(get("frame")) ~= "table" or type(talents) ~= "table" then return false end
  WFJ.Labels.forbidNames(Inspect.NEVER_TOUCH) -- its widgets exist only now (Main's registration found none)
  Inspect.showStatic()
  if hooked then return false end
  hooked = true
  local paperDoll = get("paperDoll")
  if type(paperDoll) == "table" and type(paperDoll.SetLevel) == "function" then
    hooksecurefunc(paperDoll, "SetLevel", Inspect.onLevel)
  end
  if type(get("guildUpdate")) == "function" then hooksecurefunc("InspectGuildFrame_Update", Inspect.onGuild) end
  WFJ.HelpTooltip.register(talents, TALENTS_TOOLTIP)
  for _, name in ipairs(SLOTS) do
    local slot = get("slot." .. name)
    if type(slot) == "table" then WFJ.HelpTooltip.register(slot, SLOT_TOOLTIP) end
  end
  Inspect.onLevel()
  Inspect.onGuild()
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init.
function Inspect.init()
  declare()
  return WFJ.LoadOnDemand.when(ADDON, Inspect.setup)
end
