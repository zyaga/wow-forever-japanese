-- UI/PvPMatch.lua: the battleground scoreboard and the match results window on Forever (surface "pvpmatch", area
-- "ui", ADR-016). Blizzard_PVPMatch loads at login on camelot (blizzard_pvpmatch.toc:4: "## AllowLoadGameType:
-- standard, camelot"). camelot builds its own two windows: the toc loads PVPMatchResults.lua|xml and
-- PVPMatchScoreboard.lua|xml for standard only and the Camelot\ copies for camelot (blizzard_pvpmatch.toc:10–18), which
-- build PVPMatchScoreboard (camelot/pvpmatchscoreboard.xml:5) and PVPMatchResults (camelot/pvpmatchresults.xml:5).
-- Entry points: PVP_MATCH_COMPLETE → PVPMatchResults:BeginShow (camelot/pvpmatchresults.lua:112–115, 119–122), and
-- TogglePVPScoreboardOrResults from the queue status button and its menu
-- (blizzard_queuestatusframe/mainline/queuestatusframe.lua:121, 1140, 1215, 1370–1390). Without either frame init
-- returns false and nothing is touched.
-- Writers, each post-hooked:
--   PVPMatchResults:Init (camelot/pvpmatchresults.lua:48–99, from BeginShow :120; it returns at once while the match's
--     window is set up, :49–52, and the post-hook re-shows the same lines) → header (HeaderContainer.Text, OnLoad
--     :28): the winner's line VICTORY_TEXT1 "Alliance Wins" / VICTORY_TEXT0 "Horde Wins", wrapped in that team's
--     colour (PVPMatchUtil.GetCellColor(…):WrapTextInColorCode, :60–62; the `wrapped` label form keeps the colour
--     around the Japanese), or PVP_MATCH_DRAW (:64); leaveButton PVP_MATCH_LEAVE_BUTTON (:70). Tab1 is ALL, written
--     once in OnLoad (:35);
--   the frame's OnUpdate (camelot/pvpmatchresults.xml:146 → lua:132–141) runs self.UpdateLeaveButton every frame, a
--     closure Init re-creates for each match (:75–83): it rewrites leaveButton with PVP_MATCH_LEAVE_BUTTON, or with
--     PVP_LEAVE_BUTTON_TIME ("%s (%s)": the button word and a one-letter countdown) while the instance is shutting
--     down. The closure cannot be hooked once, so the button is re-shown from a HookScript on OnUpdate, restricted to
--     those two keys (the template's first argument is an `entry`, its second is kept as written: Core/UIStrings
--     ARGS; without that ARGS line the countdown form stays English);
--   ConstructPVPMatchTable(tableBuilder, …) (pvpmatchtable.lua:377–520; a global, called from both windows' Init,
--     camelot/pvpmatchresults.lua:98, camelot/pvpmatchscoreboard.lua:50) builds the column headers through
--     PVPHeaderStringMixin:Init, which writes header.text (pvpmatchtable.lua:154–174). On camelot the kills column is
--     KILLS (GetHonorableKillsHeaderTextID, camelot/pvpmatchtableoverrides.lua:34–36, called at pvpmatchtable.lua:439)
--     and a last column SCORE_HONOR_GAINED "Honor\nGained" with no tooltip is added (TryAddHonorColumn,
--     camelot/pvpmatchtableoverrides.lua:38–43, called at pvpmatchtable.lua:517). After it, every active header
--     (tableBuilder:EnumerateHeaders, blizzard_sharedxml/tablebuilder.lua:278–280) is shown, restricted to the column
--     words, and registered for its Lua-built tooltip (PVPHeaderMixin:OnEnter, pvpmatchtable.lua:44–58).
--     A stat column's name and tooltip are client-table text (C_PvP.GetMatchPVPStatColumns, :408–423):
--     ADR-042 adds the PvpColumn family to the header set and PvpColumnTooltip (with PvpColumn, the tooltip's
--     title) to the tooltip set ("Flag Captures", "Number of times you have captured the flag"). The header set
--     also holds the PvpStat family (PVPStat.Description_lang): it names stats the column-header table does not
--     ("Towers Assaulted"), and which of the two tables a column name comes from is [unverified]. Headers are pooled:
--     records are keyed by widget;
--   tableBuilder:AddRow (tablebuilder.lua:323–342, called for every initialized row by ScrollUtil.RegisterTableBuilder,
--     blizzard_sharedxml/shared/scroll/scrollutil.lua:1663) → the honor-level cell's tooltip
--     (PVPCellHonorLevelMixin:OnEnter, pvpmatchtable.lua:139–146, HONOR_LEVEL_TOOLTIP; on Forever
--     PVP_RANK_NUMBER_AND_TITLE, camelot/pvpmatchtableoverrides.lua:25–32). Icon cells are registered
--     once each (they are pooled) and restricted to those two keys, so the class cell's tooltip (a spec and a
--     class name (:87–99)) never matches. No cell text is read: the cells hold names and live numbers.
--   Tab1 of the scoreboard is ALL, written in OnLoad (camelot/pvpmatchscoreboard.lua:24).
-- Forever's results window has no rewards, rating or queue-again button: DisplayRewards and the reward frames are
-- empty (camelot/pvpmatchresults.lua:124–126, 151–165).
-- Never touched: Tab2 / Tab3 of both windows (a faction name and a count, PVP_TAB_FILTER_COUNTED,
-- camelot/pvpmatchresults.lua:89–90, camelot/pvpmatchscoreboard.lua:67–68), the scoreboard's HeaderContainer.Text
-- (the map's zone name, UpdateMapName :53–59), the name cells (player names).
local _, WFJ = ...
local PvPMatch = {}
WFJ.PvPMatch = PvPMatch

local SURFACE = "pvpmatch"
PvPMatch.SURFACE = SURFACE
local Compat = WFJ.Compat

PvPMatch.NEVER_TOUCH = { "PVPScoreFrameTab2", "PVPScoreFrameTab3", "PVPScoreboardTab2", "PVPScoreboardTab3",
  "PVPMatchScoreboard.HeaderContainer.Text" }

local CANDIDATES = {
  results = { "PVPMatchResults" }, scoreboard = { "PVPMatchScoreboard" }, construct = { "ConstructPVPMatchTable" },
  header = { "PVPMatchResults.header", "PVPMatchResults.HeaderContainer.Text" },
  leave = { "PVPMatchResults.buttonContainer.leaveButton" },
  resultsAll = { "PVPMatchResults.content.tabContainer.tabGroup.tab1", "PVPScoreFrameTab1" },
  scoreboardAll = { "PVPMatchScoreboard.Content.TabContainer.TabGroup.Tab1", "PVPScoreboardTab1" },
  resultsTable = { "PVPMatchResults.tableBuilder" }, scoreboardTable = { "PVPMatchScoreboard.tableBuilder" },
}

local LEAVE = { only = { "PVP_MATCH_LEAVE_BUTTON", "PVP_LEAVE_BUTTON_TIME" } }
local INIT = {
  { "header", { only = { "VICTORY_TEXT0", "VICTORY_TEXT1", "PVP_MATCH_DRAW" } } },
  { "leave", LEAVE },
  { "resultsAll", { only = { "ALL" } } },
}
local SCOREBOARD = { { "scoreboardAll", { only = { "ALL" } } } }
-- KILLS and SCORE_HONOR_GAINED are camelot's (camelot/pvpmatchtableoverrides.lua:34–43); SCORE_HONORABLE_KILLS is
-- the shared table's own header (pvpmatchtable.lua:369–370), which camelot's override replaces with KILLS
local HEADER = { only = { "NAME", "SCORE_KILLING_BLOWS", "KILLS", "SCORE_HONORABLE_KILLS", "DEATHS",
  "SCORE_DAMAGE_DONE", "SCORE_HEALING_DONE", "BATTLEGROUND_MATCHMAKING_VALUE", "BATTLEGROUND_RATING",
  "BATTLEGROUND_NEW_RATING", "SCORE_RATING_CHANGE", "SCORE_HONOR_GAINED" } }
local HEADER_TOOLTIP = { only = { "KILLING_BLOW_TOOLTIP_TITLE", "KILLING_BLOW_TOOLTIP",
  "HONORABLE_KILLS_TOOLTIP_TITLE", "HONORABLE_KILLS_TOOLTIP", "DEATHS_TOOLTIP_TITLE", "DEATHS_TOOLTIP",
  "DAMAGE_DONE_TOOLTIP_TITLE", "DAMAGE_DONE_TOOLTIP", "HEALING_DONE_TOOLTIP_TITLE", "HEALING_DONE_TOOLTIP",
  "BATTLEGROUND_MATCHMAKING_VALUE_TOOLTIP_TITLE", "BATTLEGROUND_MATCHMAKING_VALUE_TOOLTIP",
  "BATTLEGROUND_RATING_TOOLTIP_TITLE", "BATTLEGROUND_NEW_RATING_TOOLTIP_TITLE", "BATTLEGROUND_NEW_RATING_TOOLTIP",
  "RATING_CHANGE_TOOLTIP_TITLE", "RATING_CHANGE_TOOLTIP" } }
-- On Forever the cell shows the PvP rank and its title instead; the title stays English (ARGS)
-- [verified: blizzard_pvpmatch/camelot/pvpmatchtableoverrides.lua:25–32]
local HONOR_CELL_TOOLTIP = { only = { "HONOR_LEVEL_TOOLTIP", "PVP_RANK_NUMBER_AND_TITLE" } }

local function get(key) return Compat.get(SURFACE, key) end

local function showList(list)
  local items = {}
  for _, s in ipairs(list) do items[#items + 1] = { s[1], get(s[1]), s[2] } end
  return WFJ.Labels.showAll(SURFACE, items)
end

-- hooksecurefunc target (PVPMatchResults:Init) and the results window's OnShow. → the number of dictionary words.
function PvPMatch.onResultsInit() return showList(INIT) end

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
        local only = WFJ.Labels.familiesWith(HEADER.only, "PvpColumn", "PvpStat")
        n = n + WFJ.Labels.show(SURFACE, headerKey(text), text, nil, only)
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
    if type(results.HookScript) == "function" then
      results:HookScript("OnShow", PvPMatch.onResultsInit)
      results:HookScript("OnUpdate", PvPMatch.onLeaveButton)
    end
    hookTable(get("resultsTable"))
    PvPMatch.onResultsInit()
  end
  if type(scoreboard) == "table" then
    if type(scoreboard.HookScript) == "function" then scoreboard:HookScript("OnShow", PvPMatch.onScoreboardShow) end
    hookTable(get("scoreboardTable"))
    PvPMatch.onScoreboardShow()
  end
  if type(get("construct")) == "function" then hooksecurefunc("ConstructPVPMatchTable", PvPMatch.onTable) end
  return true
end
