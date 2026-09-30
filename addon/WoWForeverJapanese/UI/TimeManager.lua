-- UI/TimeManager.lua: the clock window, the stopwatch and the minimap clock's tooltip on Forever (surface
-- "timemanager", area "ui", ADR-016). Blizzard_TimeManager is load-on-demand by its TOC, but `camelot` loads
-- it at PLAYER_LOGIN (blizzard_game/shared/eventimplementation.lua:175–178 → TimeManager_LoadUI), so it is waited for
-- through WFJ.LoadOnDemand.when. Entry points: a click on the minimap clock (TimeManagerClockButton_OnClick →
-- TimeManager_Toggle, blizzard_timemanager/mainline/blizzard_timemanager.lua:376–388), the /stopwatch command
-- (blizzard_chatframebase/shared/slashcommands.lua:1255–1258) and the window's own "Show Stopwatch" check.
-- TimeManagerFrame is a ButtonFrameTemplate but never calls SetTitle: its title is an unnamed FontString
-- text="TIMEMANAGER_TITLE" (blizzard_timemanager.xml:25), found by Labels.region.
-- Static labels (XML text=, or written once by an OnLoad script; each restricted to its own key):
--   TimeManagerStopwatchFrameText TIMEMANAGER_SHOW_STOPWATCH (xml:40), TimeManagerAlarmTimeLabel
--   TIMEMANAGER_ALARM_TIME (xml:74), TimeManagerAlarmMessageLabel TIMEMANAGER_ALARM_MESSAGE (xml:106),
--   TimeManagerAlarmEnabledButtonText TIMEMANAGER_ALARM_ENABLED (xml:134), TimeManagerMilitaryTimeCheckText
--   TIMEMANAGER_24HOURMODE (xml:146), TimeManagerLocalTimeCheckText TIMEMANAGER_LOCALTIME (xml:161),
--   StopwatchTitle STOPWATCH_TITLE (xml:299).
-- The AM / PM dropdown's own selection text (TimeManagerFrame.AlarmTimeFrame.AMPMDropdown, xml:92; radios
--   TIMEMANAGER_AM / TIMEMANAGER_PM, lua:218–219) follows Labels.dropdown. The popup's entries are the menu system's.
--   The hour and minute dropdowns hold digits only.
-- Help tooltip, owner TimeManagerClockButton (TimeManagerClockButton_UpdateTooltip, lua:493–510, re-run by the
--   button's one-second ticker while hovered, lua:356–361, 396–399): TIMEMANAGER_ALARM_TOOLTIP_TURN_OFF, or
--   GameTime_UpdateTooltip's TIMEMANAGER_TOOLTIP_TITLE / _REALMTIME / _LOCALTIME (blizzard_framexmlutil/
--   gametimeutil.lua:95–107) then GAMETIME_TOOLTIP_TOGGLE_CLOCK. The alarm message the player typed is the first
--   line while the alarm fires: the owner is restricted to those keys, so it is never matched.
-- Never touched: the alarm message EditBox, the two clock tickers and the stopwatch digits (numbers).
local _, WFJ = ...
local TimeManager = {}
WFJ.TimeManager = TimeManager

local SURFACE = "timemanager"
TimeManager.SURFACE = SURFACE
local Compat = WFJ.Compat
local ADDON = "Blizzard_TimeManager"

TimeManager.NEVER_TOUCH = { "TimeManagerAlarmMessageEditBox", "TimeManagerFrameTicker", "TimeManagerClockTicker",
  "StopwatchTickerHour", "StopwatchTickerMinute", "StopwatchTickerSecond" }

-- Static labels: record key → { candidate, the one key it shows }.
local STATIC_LABELS = {
  showStopwatch = { "TimeManagerStopwatchFrameText", "TIMEMANAGER_SHOW_STOPWATCH" },
  alarmTime = { "TimeManagerAlarmTimeLabel", "TIMEMANAGER_ALARM_TIME" },
  alarmMessage = { "TimeManagerAlarmMessageLabel", "TIMEMANAGER_ALARM_MESSAGE" },
  alarmEnabled = { "TimeManagerAlarmEnabledButtonText", "TIMEMANAGER_ALARM_ENABLED" },
  militaryTime = { "TimeManagerMilitaryTimeCheckText", "TIMEMANAGER_24HOURMODE" },
  localTime = { "TimeManagerLocalTimeCheckText", "TIMEMANAGER_LOCALTIME" },
  stopwatchTitle = { "StopwatchTitle", "STOPWATCH_TITLE" },
}
local STATIC_ORDER = {}
for key in pairs(STATIC_LABELS) do STATIC_ORDER[#STATIC_ORDER + 1] = key end
table.sort(STATIC_ORDER)

local CANDIDATES = {
  frame = { "TimeManagerFrame" }, stopwatch = { "StopwatchFrame" }, clock = { "TimeManagerClockButton" },
  ampm = { "TimeManagerFrame.AlarmTimeFrame.AMPMDropdown" },
}

local TITLE_KEY = "TIMEMANAGER_TITLE"
local CLOCK_TOOLTIP = { only = { "TIMEMANAGER_TOOLTIP_TITLE", "TIMEMANAGER_TOOLTIP_REALMTIME",
  "TIMEMANAGER_TOOLTIP_LOCALTIME", "GAMETIME_TOOLTIP_TOGGLE_CLOCK", "TIMEMANAGER_ALARM_TOOLTIP_TURN_OFF" } }

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  for key, l in pairs(STATIC_LABELS) do Compat.declare(SURFACE, "static." .. key, { l[1] }) end
end

-- The labels the client writes once at load, the window's unnamed title and the AM / PM selection.
-- HookScript target (TimeManagerFrame / StopwatchFrame OnShow). → the number of dictionary words found.
function TimeManager.showStatic()
  local items = {}
  for _, key in ipairs(STATIC_ORDER) do
    items[#items + 1] = { key, get("static." .. key), { only = { STATIC_LABELS[key][2] } } }
  end
  items[#items + 1] = { "title", WFJ.Labels.region(get("frame"), TITLE_KEY), { only = { TITLE_KEY } } }
  local n = WFJ.Labels.showAll(SURFACE, items)
  return n + WFJ.Labels.dropdown(SURFACE, "ampm", get("ampm"))
end

local hooked = false

-- Blizzard_TimeManager's part: runs once the addon is loaded (now, or on its ADDON_LOADED). → true when set up.
function TimeManager.setup()
  declare() -- its frames exist only now: forget what Compat memoized before
  local frame = get("frame")
  -- only the mainline-family frame, with its TitleContainer (UI/Labels.title), is served
  if type(frame) ~= "table" or type(frame.TitleContainer) ~= "table" then return false end
  WFJ.Labels.forbidNames(TimeManager.NEVER_TOUCH) -- its widgets exist only now (Main's registration found none)
  TimeManager.showStatic()
  if hooked then return false end
  hooked = true
  if type(frame.HookScript) == "function" then frame:HookScript("OnShow", TimeManager.showStatic) end
  local stopwatch = get("stopwatch")
  if type(stopwatch) == "table" and type(stopwatch.HookScript) == "function" then
    stopwatch:HookScript("OnShow", TimeManager.showStatic)
  end
  local clock = get("clock")
  if type(clock) == "table" then WFJ.HelpTooltip.register(clock, CLOCK_TOOLTIP) end
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init.
function TimeManager.init()
  declare()
  local set = false
  local ran = WFJ.LoadOnDemand.when(ADDON, function() set = TimeManager.setup() end)
  return ran and set
end
