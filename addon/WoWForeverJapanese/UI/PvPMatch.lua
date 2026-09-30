-- UI/PvPMatch.lua: the battleground scoreboard and the match results window on Forever (surface "pvpmatch", area
-- "ui", ADR-016). Blizzard_PVPMatch loads at login on camelot (blizzard_pvpmatch.toc: "## AllowLoadGameType:
-- standard, camelot") and builds PVPMatchScoreboard (pvpmatchscoreboard.xml:5) and PVPMatchResults
-- (pvpmatchresults.xml:50). Entry points: PVP_MATCH_COMPLETE → PVPMatchResults:BeginShow (pvpmatchresults.lua:205–
-- 207), and TogglePVPScoreboardOrResults from the queue status button and its menu
-- (blizzard_queuestatusframe/mainline/queuestatusframe.lua:311, 1343, 1573–1593). Without either
-- frame init returns false and nothing is touched.
-- Writers, each post-hooked:
--   PVPMatchResults:Init (pvpmatchresults.lua:108–186, from BeginShow :253 as self:Init()) → header
--     PVP_MATCH_VICTORY / _DEFEAT / _DRAW / PVP_SCOREBOARD_MATCH_COMPLETE (:120–132), leaveButton
--     PVP_MATCH_LEAVE_BUTTON (:137); requeueButton PVP_QUEUE_AGAIN and the two earnings headers
--     PVP_PROGRESS_REWARDS_HEADER / PVP_ITEM_REWARDS_HEADER are written once in OnLoad (:81–86);
--   the frame's OnUpdate (pvpmatchresults.xml:456 → lua:378–387) runs self.UpdateLeaveButton every frame, a closure
--     Init re-creates for each match (:142–150): it rewrites leaveButton with PVP_MATCH_LEAVE_BUTTON, or with
--     PVP_LEAVE_BUTTON_TIME ("%s (%s)": the button word and a one-letter countdown) while the instance is shutting
--     down. The closure cannot be hooked once, so the button is re-shown from a HookScript on OnUpdate, restricted to
--     those two keys (the template's first argument is an `entry`, its second is kept as written: Core/UIStrings
--     ARGS; without that ARGS line the countdown form stays English);
--   PVPMatchResults:DisplayRewards (:257–368) → InitHonorFrame / InitConquestFrame / InitRatingFrame (:411–449):
--     honorText PVP_HONOR_CHANGE, conquestText PVP_CONQUEST_CHANGE, ratingText PVP_RATING_CHANGE /
--     PVP_RATING_UNCHANGED (the value is FormatValueWithSign output, "+25");
--   the rating button's tooltip (PVPMatchResultsRatingMixin:OnEnter, :529–557: GameTooltip_SetTitle, AddNormalLine,
--     Show), registered with UI/HelpTooltip, restricted to the rating keys;
--   ConstructPVPMatchTable(tableBuilder, …) (pvpmatchtable.lua:340–481; a global, called from both windows' Init)
--     builds the column headers through PVPHeaderStringMixin:Init, which writes header.text (:130–150). After it,
--     every active header (tableBuilder:EnumerateHeaders, blizzard_sharedxml/tablebuilder.lua:278–280) is shown,
--     restricted to the column words, and registered for its Lua-built tooltip (PVPHeaderMixin:OnEnter, :44–58).
--     A stat column's name and tooltip are client-table text (C_PvP.GetMatchPVPStatColumns, :371–386):
--     ADR-042 adds the PvpColumn family to the header set and PvpColumnTooltip (with PvpColumn, the tooltip's
--     title) to the tooltip set ("Flag Captures", "Number of times you have captured the flag"). Headers are pooled:
--     records are keyed by widget;
--   tableBuilder:AddRow (tablebuilder.lua:323–342, called for every initialized row by ScrollUtil.RegisterTableBuilder,
--     blizzard_sharedxml/shared/scroll/scrollutil.lua:1661–1665) → the honor-level cell's tooltip
--     (PVPCellHonorLevelMixin:OnEnter, pvpmatchtable.lua:115–122, HONOR_LEVEL_TOOLTIP). Icon cells are registered
--     once each (they are pooled) and restricted to that key, so the class cell's tooltip (a spec and a class name
--     (:87–98)) never matches. No cell text is read: the cells hold names and live numbers.
--   Tab1 of both windows is ALL, written in OnLoad (pvpmatchresults.lua:90, pvpmatchscoreboard.lua:24).
-- Never touched: Tab2 / Tab3 of both windows (a faction name and a count, PVP_TAB_FILTER_COUNTED, :169–170 /
-- scoreboard :64–65), the name cells (player names), the matchmaking text (two templates joined with "\n" around
-- colour-wrapped values, pvpmatchutil.lua:121: a composite, ui_exclusions).
local _, WFJ = ...
local PvPMatch = {}
WFJ.PvPMatch = PvPMatch

local SURFACE = "pvpmatch"
PvPMatch.SURFACE = SURFACE
local Compat = WFJ.Compat

PvPMatch.NEVER_TOUCH = { "PVPScoreFrameTab2", "PVPScoreFrameTab3", "PVPScoreboardTab2", "PVPScoreboardTab3",
  "PVPMatchResults.content.tabContainer.matchmakingText", "PVPMatchScoreboard.Content.TabContainer.MatchmakingText" }

local CANDIDATES = {
  results = { "PVPMatchResults" }, scoreboard = { "PVPMatchScoreboard" }, construct = { "ConstructPVPMatchTable" },
  header = { "PVPMatchResults.header" }, leave = { "PVPMatchResults.buttonContainer.leaveButton" },
  requeue = { "PVPMatchResults.buttonContainer.requeueButton" },
  resultsAll = { "PVPMatchResults.content.tabContainer.tabGroup.tab1", "PVPScoreFrameTab1" },
  scoreboardAll = { "PVPMatchScoreboard.Content.TabContainer.TabGroup.Tab1", "PVPScoreboardTab1" },
  rewardsHeader = { "PVPMatchResults.content.earningsContainer.rewardsContainer.header" },
  progressHeader = { "PVPMatchResults.content.earningsContainer.progressContainer.header" },
  honor = { "PVPMatchResults.content.earningsContainer.progressContainer.honor.text" },
  conquest = { "PVPMatchResults.content.earningsContainer.progressContainer.conquest.text" },
  rating = { "PVPMatchResults.content.earningsContainer.progressContainer.rating.text" },
  ratingButton = { "PVPMatchResults.content.earningsContainer.progressContainer.rating.button" },
  resultsTable = { "PVPMatchResults.tableBuilder" }, scoreboardTable = { "PVPMatchScoreboard.tableBuilder" },
}

local LEAVE = { only = { "PVP_MATCH_LEAVE_BUTTON", "PVP_LEAVE_BUTTON_TIME" } }
local INIT = {
  { "header", { only = { "PVP_MATCH_VICTORY", "PVP_MATCH_DEFEAT", "PVP_MATCH_DRAW",
    "PVP_SCOREBOARD_MATCH_COMPLETE" } } },
  { "leave", LEAVE },
  { "requeue", { only = { "PVP_QUEUE_AGAIN" } } },
  { "resultsAll", { only = { "ALL" } } },
  { "rewardsHeader", { only = { "PVP_ITEM_REWARDS_HEADER" } } },
  { "progressHeader", { only = { "PVP_PROGRESS_REWARDS_HEADER" } } },
}
local REWARDS = {
  { "honor", { only = { "PVP_HONOR_CHANGE" } } },
  { "conquest", { only = { "PVP_CONQUEST_CHANGE" } } },
  { "rating", { only = { "PVP_RATING_CHANGE", "PVP_RATING_UNCHANGED" } } },
}
local SCOREBOARD = { { "scoreboardAll", { only = { "ALL" } } } }
local RATING_TOOLTIP = { only = { "PVP_RATING_HEADER", "PVP_RATING_PREVIOUS", "PVP_RATING_GAINED", "PVP_RATING_NEW",
  "PVP_RATING_CURRENT", "BATTLEGROUND_YOUR_AVERAGE_RATING", "BATTLEGROUND_ENEMY_AVERAGE_RATING",
  "BATTLEGROUND_YOUR_PERSONAL_RATING", "BATTLEGROUND_ROLE_AVERAGE_MMV" } }
local HEADER = { only = { "NAME", "SCORE_KILLING_BLOWS", "SCORE_HONORABLE_KILLS", "DEATHS", "SCORE_DAMAGE_DONE",
  "SCORE_HEALING_DONE", "BATTLEGROUND_MATCHMAKING_VALUE", "BATTLEGROUND_RATING", "BATTLEGROUND_NEW_RATING",
  "SCORE_RATING_CHANGE" } }
local HEADER_TOOLTIP = { only = { "KILLING_BLOW_TOOLTIP_TITLE", "KILLING_BLOW_TOOLTIP",
  "HONORABLE_KILLS_TOOLTIP_TITLE", "HONORABLE_KILLS_TOOLTIP", "DEATHS_TOOLTIP_TITLE", "DEATHS_TOOLTIP",
  "DAMAGE_DONE_TOOLTIP_TITLE", "DAMAGE_DONE_TOOLTIP", "HEALING_DONE_TOOLTIP_TITLE", "HEALING_DONE_TOOLTIP",
  "BATTLEGROUND_MATCHMAKING_VALUE_TOOLTIP_TITLE", "BATTLEGROUND_MATCHMAKING_VALUE_TOOLTIP",
  "BATTLEGROUND_RATING_TOOLTIP_TITLE", "BATTLEGROUND_NEW_RATING_TOOLTIP_TITLE", "BATTLEGROUND_NEW_RATING_TOOLTIP",
  "RATING_CHANGE_TOOLTIP_TITLE", "RATING_CHANGE_TOOLTIP" } }
local HONOR_CELL_TOOLTIP = { only = { "HONOR_LEVEL_TOOLTIP" } }

local function get(key) return Compat.get(SURFACE, key) end

local function showList(list)
  local items = {}
  for _, s in ipairs(list) do items[#items + 1] = { s[1], get(s[1]), s[2] } end
  return WFJ.Labels.showAll(SURFACE, items)
end

-- hooksecurefunc target (PVPMatchResults:Init) and the results window's OnShow. → the number of dictionary words.
function PvPMatch.onResultsInit() return showList(INIT) end

-- hooksecurefunc target (PVPMatchResults:DisplayRewards). → the number of dictionary words found.
function PvPMatch.onRewards() return showList(REWARDS) end

-- HookScript target (PVPMatchResults OnUpdate): the leave button, which the client rewrites every frame. → 1 | 0
function PvPMatch.onLeaveButton()
  return WFJ.Labels.show(SURFACE, "leave", get("leave"), nil, LEAVE)
end

-- The scoreboard's own label (its OnShow). → the number of dictionary words found.
function PvPMatch.onScoreboardShow() return showList(SCOREBOARD) end

local headerKey = WFJ.Labels.keyer("column.") -- a pooled header's record key (follows the widget)

-- hooksecurefunc target (ConstructPVPMatchTable(tableBuilder, useAlternateColor)). → the number of dictionary words
function PvPMatch.onTable(tableBuilder)
  if type(tableBuilder) ~= "table" or type(tableBuilder.EnumerateHeaders) ~= "function" then return 0 end
  local n = 0
  for header in tableBuilder:EnumerateHeaders() do
    if type(header) == "table" then
      WFJ.HelpTooltip.register(header, WFJ.Labels.familiesWith(HEADER_TOOLTIP.only, "PvpColumn", "PvpColumnTooltip"))
      local text = header.text
      if type(text) == "table" then
        n = n + WFJ.Labels.show(SURFACE, headerKey(text), text, nil, WFJ.Labels.familiesWith(HEADER.only, "PvpColumn"))
      end
    end
  end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- hooksecurefunc target (tableBuilder:AddRow(row, dataProviderKey)): the row's icon cells own the honor-level
-- tooltip. A text cell (a name, a number) is skipped; nothing is read from any cell.
function PvPMatch.onRow(_, row)
  local cells = type(row) == "table" and row.cells or nil
  if type(cells) ~= "table" then return end
  for _, cell in ipairs(cells) do
    if type(cell) == "table" and type(cell.icon) == "table" and cell.text == nil
        and not WFJ.HelpTooltip.registered(cell) then
      WFJ.HelpTooltip.register(cell, HONOR_CELL_TOOLTIP)
    end
  end
end

local function hookTable(tableBuilder)
  if type(tableBuilder) ~= "table" then return end
  if type(tableBuilder.AddRow) == "function" then hooksecurefunc(tableBuilder, "AddRow", PvPMatch.onRow) end
  PvPMatch.onTable(tableBuilder)
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function PvPMatch.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  local results, scoreboard = get("results"), get("scoreboard")
  if hooked or (type(results) ~= "table" and type(scoreboard) ~= "table") then return false end
  hooked = true
  if type(results) == "table" then
    if type(results.Init) == "function" then hooksecurefunc(results, "Init", PvPMatch.onResultsInit) end
    if type(results.DisplayRewards) == "function" then
      hooksecurefunc(results, "DisplayRewards", PvPMatch.onRewards)
    end
    if type(results.HookScript) == "function" then
      results:HookScript("OnShow", PvPMatch.onResultsInit)
      results:HookScript("OnUpdate", PvPMatch.onLeaveButton)
    end
    local ratingButton = get("ratingButton")
    if type(ratingButton) == "table" then WFJ.HelpTooltip.register(ratingButton, RATING_TOOLTIP) end
    hookTable(get("resultsTable"))
    PvPMatch.onResultsInit()
    PvPMatch.onRewards()
  end
  if type(scoreboard) == "table" then
    if type(scoreboard.HookScript) == "function" then scoreboard:HookScript("OnShow", PvPMatch.onScoreboardShow) end
    hookTable(get("scoreboardTable"))
    PvPMatch.onScoreboardShow()
  end
  if type(get("construct")) == "function" then hooksecurefunc("ConstructPVPMatchTable", PvPMatch.onTable) end
  return true
end
