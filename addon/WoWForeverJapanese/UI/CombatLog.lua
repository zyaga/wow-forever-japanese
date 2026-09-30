-- UI/CombatLog.lua: the combat log's quick-button bar on Forever (surface "combatlog", area "ui", ADR-016).
-- Blizzard_CombatLog is load-on-demand and loaded at PLAYER_LOGIN (CombatLog_LoadUI,
-- blizzard_game/shared/eventimplementation.lua:175–178), which may be before or after this module's init: it is
-- waited for through WFJ.LoadOnDemand.when. The combat log's options are panes of the chat configuration window
-- (UI/ChatConfig.lua).
-- The one fixed word of the bar: the overflow button's hover, GameTooltip_SetTitle(GameTooltip, ADDITIONAL_FILTERS)
-- (blizzard_combatlog/mainline/blizzard_combatlog.xml:45–49): a help tooltip, owner
-- CombatLogQuickButtonFrame_CustomAdditionalFilterButton.
-- Never touched: the quick buttons (CombatLogQuickButtonFrameButton<N>): each shows a filter's name, which the
-- player edits and the client saves (blizzard_combatlog.lua:1594; blizzard_chatframe/mainline/chatconfigframe.xml:
-- 1366–1390), and the bar is laid out from the width of that text (lua:1595–1598). Combat log lines are chat lines.
local _, WFJ = ...
local CombatLog = {}
WFJ.CombatLog = CombatLog

local SURFACE = "combatlog"
CombatLog.SURFACE = SURFACE
local Compat = WFJ.Compat
local ADDON = "Blizzard_CombatLog"

CombatLog.NEVER_TOUCH = {}
for i = 1, 20 do CombatLog.NEVER_TOUCH[i] = "CombatLogQuickButtonFrameButton" .. i end -- MAX_COMBATLOG_FILTERS

local CANDIDATES = {
  overflow = { "CombatLogQuickButtonFrame_CustomAdditionalFilterButton" },
}
local OVERFLOW = { only = { "ADDITIONAL_FILTERS" } }

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
end

local done = false

-- Blizzard_CombatLog's part: runs once the addon is loaded (now, or on its ADDON_LOADED). → true when set up.
function CombatLog.setup()
  declare() -- its frames exist only now: forget what Compat memoized before
  local button = get("overflow")
  if done or type(button) ~= "table" then return false end
  done = true
  WFJ.HelpTooltip.register(button, OVERFLOW)
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init.
function CombatLog.init()
  declare()
  return WFJ.LoadOnDemand.when(ADDON, CombatLog.setup)
end
