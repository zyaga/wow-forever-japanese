-- UI/EventTrace.lua: the Event Log developer window on Forever (surfaces "eventtrace" and "eventtrace.static", area
-- "ui", ADR-016). Blizzard_EventTrace is load-on-demand: /etrace loads it and shows the window
-- (EventTrace_LoadUI, blizzard_chatframebase/shared/slashcommands.lua:1334–1336; blizzard_eventtrace/
-- blizzard_eventtrace_bootstrap.lua:3–5). It may load before or after this module's init: waited for through
-- WFJ.LoadOnDemand.when.
-- EventTrace is one frame (blizzard_eventtrace.xml:170) whose OnLoad writes every label once
-- (blizzard_eventtrace.lua:100–122): the title EventTrace:SetTitle(EVENTTRACE_HEADER) (lua:111, Labels.title); the
-- two view buttons (lua:171, 176); the log bar's label, Marker and Discard All (lua:195, 226–236); the filter bar's
-- label, Check All, Uncheck All and Discard All (lua:414, 427–436); the Options dropdown's own text (lua:462).
-- Rewritten later, each a method of the frame (the mixin's functions are copied onto it), post-hooked:
--   UpdatePlaybackButton (lua:182–184) → PlaybackButton.Label: EVENTTRACE_BUTTON_PLAY or _PAUSE;
--   DisplayEvents (lua:194–198) → Log.Bar.Label: EVENTTRACE_LOG_HEADER;
--   OnSearchDataProviderChanged (lua:205–209) → Log.Bar.Label: EVENTTRACE_RESULTS ("Results: %d").
-- Every label is restricted to the keys its writer shows.
-- eventTraceRow (ADR-038): a log message row: LeftLabel = FormatLine(id, message) = "<gray [001]> <orange
--   '--- %s ---'>" (EventTraceLogMessageButtonMixin:Init / SetLeftText, lua:800–809, 930–940;
--   EVENTTRACE_MESSAGE_FORMAT; the messages EVENTTRACE_LOG_START / _PAUSE / _PAUSE_WHILE_HIDDEN / _DISCARD /
--   EVENTTRACE_MARKER, lua:129, 135, 229, 240, 629). The id, the dashes and both colours are kept; the inner message
--   is matched by key. Rows are pooled: followed through both log ScrollBoxes' initialized-frame callback (Log.Events
--   / Log.Search, lua:285–286, 313–340) and the mixin's SetLeftText (a later-created row copies the hooked
--   function).
-- A log row's tooltip is EventTraceTooltip, a tooltip frame of its own (blizzard_eventtrace.xml:385): the row's
-- OnEnter adds the event name, EVENTTRACE_TIMESTAMP beside the time and one EVENTTRACE_ARG_FMT ("Arg %d") per argument
-- beside its value, then Shows it (lua:813–836). Followed through TooltipLines.follow, restricted to those two keys:
-- the event name and the argument values match neither.
-- Never touched: the search box (an EditBox), the event and filter rows (event names and their arguments, lua:890–960),
-- and the Options menu's entries (a dropdown / menu popup entry, UI/Menus).
local _, WFJ = ...
local EventTrace = {}
WFJ.EventTrace = EventTrace

local SURFACE = "eventtrace"
EventTrace.SURFACE = SURFACE
local STATIC = SURFACE .. ".static"
local Compat = WFJ.Compat
local ADDON = "Blizzard_EventTrace"

EventTrace.NEVER_TOUCH = { "EventTrace.Log.Bar.SearchBox" }

-- record key → { path under EventTrace, the keys it shows }
local LABELS = {
  viewLog = { "SubtitleBar.ViewLog.Label", { "EVENTTRACE_LOG_HEADER" } },
  viewFilter = { "SubtitleBar.ViewFilter.Label", { "EVENTTRACE_FILTER_HEADER" } },
  logBar = { "Log.Bar.Label", { "EVENTTRACE_LOG_HEADER", "EVENTTRACE_RESULTS" } },
  mark = { "Log.Bar.MarkButton.Label", { "EVENTTRACE_BUTTON_MARKER" } },
  playback = { "Log.Bar.PlaybackButton.Label", { "EVENTTRACE_BUTTON_PLAY", "EVENTTRACE_BUTTON_PAUSE" } },
  logDiscard = { "Log.Bar.DiscardAllButton.Label", { "EVENTTRACE_BUTTON_DISCARD_FILTER" } },
  filterBar = { "Filter.Bar.Label", { "EVENTTRACE_FILTER_HEADER" } },
  checkAll = { "Filter.Bar.CheckAllButton.Label", { "EVENTTRACE_BUTTON_ENABLE_FILTERS" } },
  uncheckAll = { "Filter.Bar.UncheckAllButton.Label", { "EVENTTRACE_BUTTON_DISABLE_FILTERS" } },
  filterDiscard = { "Filter.Bar.DiscardAllButton.Label", { "EVENTTRACE_BUTTON_DISCARD_FILTER" } },
}
local ORDER = {}
for key in pairs(LABELS) do ORDER[#ORDER + 1] = key end
table.sort(ORDER)

local TITLE = { only = { "EVENTTRACE_HEADER" } }
local WRITERS = { "UpdatePlaybackButton", "DisplayEvents", "OnSearchDataProviderChanged" }

local CANDIDATES = {
  frame = { "EventTrace" }, options = { "EventTrace.SubtitleBar.OptionsDropdown" },
  tooltip = { "EventTraceTooltip" }, mixin = { "EventTraceLogMessageButtonMixin" }, scrollUtil = { "ScrollUtil" },
  events = { "EventTrace.Log.Events.ScrollBox" }, search = { "EventTrace.Log.Search.ScrollBox" },
}
local ROWS = SURFACE .. ".rows"
local MESSAGES = { "EVENTTRACE_LOG_START", "EVENTTRACE_LOG_PAUSE", "EVENTTRACE_LOG_PAUSE_WHILE_HIDDEN",
  "EVENTTRACE_LOG_DISCARD", "EVENTTRACE_MARKER" }
local TOOLTIP = { only = { "EVENTTRACE_TIMESTAMP", "EVENTTRACE_ARG_FMT" } }
EventTrace.TOOLTIP_SURFACE = "eventtrace.tooltip"
local rowKey = WFJ.Labels.keyer("row.")

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  for key, l in pairs(LABELS) do Compat.declare(SURFACE, "label." .. key, { "EventTrace." .. l[1] }) end
end

-- Every label, the title and the dropdown's text. HookScript / hooksecurefunc target. → the number of words found.
function EventTrace.refresh()
  local items = {}
  for _, key in ipairs(ORDER) do items[#items + 1] = { key, get("label." .. key), { only = LABELS[key][2] } } end
  local n = WFJ.Labels.showAll(STATIC, items)
  n = n + WFJ.Labels.title(SURFACE, get("frame"), TITLE)
  local options = get("options")
  if type(options) == "table" then n = n + WFJ.Labels.dropdown(SURFACE, "options", options) end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- The eventTraceRow form: "<id> |cAARRGGBB--- <message> ---|r" → `seq` args | nil
function EventTrace.rowArgs(text)
  if type(text) ~= "string" then return nil end
  local head, message, tail = text:match("^(.- |c%x%x%x%x%x%x%x%x%-%-%- )(.-)( %-%-%-|r)$")
  local part = head and WFJ.Labels.part(message, MESSAGES)
  return part and { form = "seq", parts = { head, part, tail } } or nil
end

-- One log message row after its text was written (an initialized-frame callback: (owner, frame, data) or (frame,
-- data); or the mixin's SetLeftText: (row, data)). Returns nothing (ForEachFrame stops at a truthy return).
function EventTrace.onRow(a, b)
  local row = a
  if a == EventTrace then row = b end
  local label = type(row) == "table" and row.LeftLabel or nil
  if type(label) ~= "table" or type(label.GetText) ~= "function" then return end
  local recKey = rowKey(label)
  local rec = WFJ.SurfaceState.get(ROWS, recKey)
  if rec and rec.fs == label and rec.applied ~= nil and rec.applied == label:GetText() then return end -- still ours
  local args = EventTrace.rowArgs(label:GetText())
  WFJ.Labels.showArgs(ROWS, recKey, label, args and args.parts[2].key, args)
end

local done = false

-- Blizzard_EventTrace's part: runs once the addon is loaded (now, or on its ADDON_LOADED). → true when set up.
function EventTrace.setup()
  declare() -- its frames exist only now: forget what Compat memoized before
  local frame = get("frame")
  if done or type(frame) ~= "table" then return false end
  done = true
  WFJ.Labels.forbidNames(EventTrace.NEVER_TOUCH)
  for _, method in ipairs(WRITERS) do
    if type(frame[method]) == "function" then hooksecurefunc(frame, method, EventTrace.refresh) end
  end
  if type(frame.HookScript) == "function" then frame:HookScript("OnShow", EventTrace.refresh) end
  local mixin, util = get("mixin"), get("scrollUtil")
  if type(mixin) == "table" and type(mixin.SetLeftText) == "function" then
    hooksecurefunc(mixin, "SetLeftText", EventTrace.onRow)
  end
  if type(util) == "table" and type(util.AddInitializedFrameCallback) == "function" then
    for _, key in ipairs({ "events", "search" }) do
      local box = get(key)
      if type(box) == "table" then util.AddInitializedFrameCallback(box, EventTrace.onRow, EventTrace, true) end
    end
  end
  WFJ.TooltipLines.follow(EventTrace.TOOLTIP_SURFACE, get("tooltip"), TOOLTIP)
  EventTrace.refresh()
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init. → true when set up now;
-- false when the addon has not loaded yet (setup then runs on its ADDON_LOADED) or without the frame.
function EventTrace.init()
  declare()
  local ready = false -- true only when the addon is loaded now and its window was set up
  WFJ.LoadOnDemand.when(ADDON, function() ready = EventTrace.setup() end)
  return ready
end
