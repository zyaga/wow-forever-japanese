-- UI/QuestTimer.lua: the quest timers panel on Forever (surface "questtimer", area "ui", ADR-016, ADR-029).
-- Blizzard_QuestTimer loads at login on camelot with its [Family] files (mainline/blizzard_questtimer.xml,
-- mainline/blizzard_questtimeroverrides.lua, blizzard_questtimer.lua): QuestTimerFrame is a child of
-- ObjectiveTrackerFrame and shows itself while a timed quest runs (QuestTimerMixin:UpdateIfNeeded on QUEST_LOG_UPDATE /
-- PLAYER_ENTERING_WORLD, blizzard_questtimer.lua:25–31). Without its Header frame nothing resolves and this module
-- does nothing.
-- The one word: QuestTimerFrame.Header (DialogHeaderTemplate, KeyValue textString = QUEST_TIMERS, mainline xml:
-- 18–26) → DialogHeaderMixin:OnLoad → Setup → Header.Text:SetText, then UpdateWidth sizes the header from the text
-- (blizzard_sharedxml/shared/dialog/dialogtemplates.lua:4–22). Written once at load; shown on the panel's OnShow
-- and released on its OnHide. The refit asks the header to measure itself again (its own UpdateWidth).
-- Never touched: a timer row's text (a formatted time, SecondsToTime) and its tooltip (the quest's title, shown
-- by the client as live English: mainline/blizzard_questtimeroverrides.lua:9–17).
local _, WFJ = ...
local QuestTimer = {}
WFJ.QuestTimer = QuestTimer

local SURFACE = "questtimer"
QuestTimer.SURFACE = SURFACE
local Compat = WFJ.Compat

QuestTimer.NEVER_TOUCH = {}

local CANDIDATES = { frame = { "QuestTimerFrame" }, header = { "QuestTimerFrame.Header" },
  headerText = { "QuestTimerFrame.Header.Text" } }
local HEADER = { only = { "QUEST_TIMERS" } }

local function get(key) return Compat.get(SURFACE, key) end

local function refit()
  local header = get("header")
  if type(header) == "table" and type(header.UpdateWidth) == "function" then header:UpdateWidth() end
end

-- → 1 | 0
function QuestTimer.show()
  local n = WFJ.Labels.show(SURFACE, "header", get("headerText"), refit, HEADER)
  WFJ.Render.updateBanner(SURFACE)
  return n
end

function QuestTimer.release() return WFJ.Render.release(SURFACE) end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function QuestTimer.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  local frame = get("frame")
  if hooked or type(frame) ~= "table" or type(get("headerText")) ~= "table" then return false end
  hooked = true
  if type(frame.HookScript) == "function" then
    frame:HookScript("OnShow", QuestTimer.show)
    frame:HookScript("OnHide", QuestTimer.release)
  end
  if type(frame.IsShown) == "function" and frame:IsShown() then QuestTimer.show() end
  return true
end
