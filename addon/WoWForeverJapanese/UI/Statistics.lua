-- UI/Statistics.lua: the character window's Statistics tab on Forever (surface "statistics", area "ui",
-- ADR-042). Blizzard_Statistics is a camelot-only addon loaded at login (blizzard_statistics.toc: AllowLoadGameType
-- camelot, no LoadOnDemand); StatisticsFrame is a child of CharacterFrame (camelot/statisticsframe.xml:117), one of
-- its sub-frames (blizzard_uipanels_game/camelot/characterframeconstants.lua:1, 30–31). The tab and the window title
-- are UI/Character's.
-- Every row is client-table text (pipeline/forever_addon_dispositions.txt): StatisticsFrame.ScrollBox, a tree list of
-- pooled rows (statisticsframe.lua:70–91), followed with ScrollUtil.AddInitializedFrameCallback and keyed by widget:
--   a top-level header (StatisticsHeaderMixin:Initialize, lua:196–199) writes `.Name` with a category name
--     (GetCategoryInfo, lua:150): the AchievementCategory family only;
--   an entry or a sub-header (StatisticsEntryMixin:Initialize, lua:235–240; StatisticsSubHeaderMixin, :287–296)
--     writes `.Content.Name`: a sub-category's name (elementData.isCategory) or a statistic's name, the title of the
--     statistic's achievement row (GetAchievementInfo, lua:123): the AchievementCategory or the achievement
--     families only. The UNKNOWN fallback (lua:136, 153) is a GlobalString and stays as the client wrote it.
-- Never touched: the values ("--" or a number, `.Content.Value`).
local _, WFJ = ...
local Statistics = {}
WFJ.Statistics = Statistics

local SURFACE = "statistics"
Statistics.SURFACE = SURFACE
local Compat = WFJ.Compat

Statistics.NEVER_TOUCH = {}

local CANDIDATES = { frame = { "StatisticsFrame" }, scrollBox = { "StatisticsFrame.ScrollBox" },
  scrollUtil = { "ScrollUtil" } }

local function get(key) return Compat.get(SURFACE, key) end

local rowKey = WFJ.Labels.keyer("row.") -- a pooled row's record key: follows the widget, never its index

-- ScrollUtil's initialized-frame callback: (owner, frame, node) for a new row, (frame, node) for the rows that
-- already exist. Returns nothing (ForEachFrame stops at the first truthy return).
function Statistics.onRow(a, b, c)
  local row, node = a, b
  if a == Statistics then row, node = b, c end
  if type(row) ~= "table" then return end
  local data = type(node) == "table" and type(node.GetData) == "function" and node:GetData() or nil
  local content = row.Content
  if type(content) == "table" then
    local isCategory = type(data) == "table" and data.isCategory == true
    local only = isCategory and WFJ.Achievement.categoryOnly() or WFJ.Achievement.textOnly()
    WFJ.Labels.show(SURFACE, rowKey(row), content.Name, nil, only)
  else
    WFJ.Labels.show(SURFACE, rowKey(row), row.Name, nil, WFJ.Achievement.categoryOnly())
  end
  WFJ.Render.updateBanner(SURFACE)
end

function Statistics.release()
  return WFJ.Render.release(SURFACE)
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function Statistics.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  local frame, box, util = get("frame"), get("scrollBox"), get("scrollUtil")
  if hooked or type(frame) ~= "table" or type(box) ~= "table" then return false end -- no StatisticsFrame
  hooked = true
  if type(util) == "table" and type(util.AddInitializedFrameCallback) == "function" then
    util.AddInitializedFrameCallback(box, Statistics.onRow, Statistics, true)
  end
  if type(frame.HookScript) == "function" then frame:HookScript("OnHide", Statistics.release) end
  return true
end
