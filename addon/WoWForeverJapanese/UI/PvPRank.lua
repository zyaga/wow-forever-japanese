-- UI/PvPRank.lua: the character window's PvP rank panel on Forever (surface "pvprank", area "ui", ADR-016).
-- `camelot` does not load the Classic honor frame (Blizzard_UIPanels_Game.toc:75–79 gate Vanilla\HonorFrame.* and
-- HonorFrame_Shared to vanilla/tbc/wrath/classic); it loads [Game]\PVPRankFrame.lua|xml [AllowLoadGameType camelot]
-- (toc:213–214), a season / renown rank panel parented to CharacterFrame (camelot/pvprankframe.xml:3). It is a
-- different feature, not a rename, so it is its own surface.
-- Every widget is parentKey-only (dotted Compat names). Writers, each the frame's own method (the mixin is copied
-- onto the frame at load and every call is `self:…()`), post-hooked on the frame:
--   PVPRankFrame:Update (pvprankframe.lua:90–122; OnShow :46, OnEvent :74) →
--     MainInfoFrame.CurrentSeasonField   format(EXPANSION_SEASON_NAME, '', season): " Season 1" (:102)
--     MainInfoFrame.CurrentRankField     PVP_RANK_NUMBER_AND_TITLE ("Rank %d - %s", %s = the rank title, kept
--                                        English), or PVP_RANK_0_NAME ("Civilian", a rank title: left English)
--     MainInfoFrame.CurrentRankProgressField  PVP_RANK_CURRENT_PROGRESS (:119)
--   PVPRankFrame:UpdateSeasonCountdownTimer (:78–88; a C_Timer ticker calls it every second while the frame is
--     shown, :50–58) → SeasonTimerField SEASON_ENDS_IN_TIME with a SecondsFormatter duration (two unabbreviated
--     units, D_DAYS / D_HOURS / D_MINUTES / D_SECONDS, blizzard_sharedxml/timeutil.lua:84–87). The hook shows one
--     widget and nothing else, so the ticker stays cheap;
--   PVPRankFrame.DetailFrame:Refresh (:132–217, via CharacterFrameSidePaneMixin, camelot/characterframe.lua:
--     850–951) → Subtitle PVP_RANK_NUMBER, EmptyText PVP_RANK_DETAIL_UNAVAILABLE, the Description's FontString
--     PVP_RANK_SEASON_RANKUP_DESCRIPTION (a ScrollingFontTemplate: its FontString is written directly, so the
--     scroll container keeps the height the English measured; in-game check), and the pooled rows' Labels
--     (rowPools, characterframe.lua:840–845): PVP_RANK_SEASON_PROGRESS[_NO_MAX], PVP_RANK_WEEKLY_CAP_INCREASE,
--     PVP_RANK_NEXT_REWARD, PVP_RANK_REWARDS_VENDOR_HORDE / _ALLIANCE. A reward row's description is server text
--     and never matches the row set. Rows are keyed by widget, never by position.
-- Never touched: DetailFrame.Title (the rank title, GetPVPRankText), the rank badge's level number.
local _, WFJ = ...
local PvPRank = {}
WFJ.PvPRank = PvPRank

local SURFACE = "pvprank"
PvPRank.SURFACE = SURFACE
local Compat = WFJ.Compat

PvPRank.NEVER_TOUCH = { "PVPRankFrame.DetailFrame.Title",
  "PVPRankFrame.MainInfoFrame.RankProgressBarDisplay.NextRewardLevel.LevelLabel" }

local CANDIDATES = {
  frame = { "PVPRankFrame" }, detail = { "PVPRankFrame.DetailFrame" },
  timer = { "PVPRankFrame.SeasonTimerField" }, season = { "PVPRankFrame.MainInfoFrame.CurrentSeasonField" },
  rank = { "PVPRankFrame.MainInfoFrame.CurrentRankField" },
  progress = { "PVPRankFrame.MainInfoFrame.CurrentRankProgressField" },
  subtitle = { "PVPRankFrame.DetailFrame.Subtitle" }, empty = { "PVPRankFrame.DetailFrame.EmptyText" },
  description = { "PVPRankFrame.DetailFrame.Description" },
}

local TIMER = { only = { "SEASON_ENDS_IN_TIME" } }
local MAIN = {
  { "season", { only = { "EXPANSION_SEASON_NAME" } } },
  { "rank", { only = { "PVP_RANK_NUMBER_AND_TITLE" } } }, -- never PVP_RANK_0_NAME: a rank title stays English
  { "progress", { only = { "PVP_RANK_CURRENT_PROGRESS" } } },
}
local SUBTITLE = { only = { "PVP_RANK_NUMBER" } }
local EMPTY = { only = { "PVP_RANK_DETAIL_UNAVAILABLE" } }
local DESCRIPTION = { only = { "PVP_RANK_SEASON_RANKUP_DESCRIPTION" } }
local ROW = { only = { "PVP_RANK_SEASON_PROGRESS", "PVP_RANK_SEASON_PROGRESS_NO_MAX", "PVP_RANK_WEEKLY_CAP_INCREASE",
  "PVP_RANK_NEXT_REWARD", "PVP_RANK_REWARDS_VENDOR_HORDE", "PVP_RANK_REWARDS_VENDOR_ALLIANCE" } }

local function get(key) return Compat.get(SURFACE, key) end

-- A stable record key per pooled row label (records follow the widget, not the index).
local rowKey = WFJ.Labels.keyer("row.")

-- The Description frame's FontString (ScrollingFontMixin:GetFontString, scrolltemplates.lua:337–340). → fs | nil
local function descriptionText()
  local desc = get("description")
  if type(desc) ~= "table" or type(desc.GetFontString) ~= "function" then return nil end
  local ok, fs = pcall(desc.GetFontString, desc)
  return ok and type(fs) == "table" and fs or nil
end

-- hooksecurefunc target (PVPRankFrame:UpdateSeasonCountdownTimer, every second while shown). → 1 | 0
function PvPRank.onTimer()
  return WFJ.Labels.show(SURFACE, "timer", get("timer"), nil, TIMER)
end

-- hooksecurefunc target (PVPRankFrame:Update). → the number of dictionary words found.
function PvPRank.onUpdate()
  local n = 0
  for _, m in ipairs(MAIN) do n = n + WFJ.Labels.show(SURFACE, m[1], get(m[1]), nil, m[2]) end
  n = n + PvPRank.onTimer()
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- hooksecurefunc target (PVPRankFrame.DetailFrame:Refresh). → the number of dictionary words found.
function PvPRank.onRefresh()
  local show = WFJ.Labels.show
  local n = show(SURFACE, "subtitle", get("subtitle"), nil, SUBTITLE)
    + show(SURFACE, "empty", get("empty"), nil, EMPTY)
    + show(SURFACE, "description", descriptionText(), nil, DESCRIPTION)
  local detail = get("detail")
  local pools = type(detail) == "table" and detail.rowPools or nil
  if type(pools) == "table" and type(pools.EnumerateActive) == "function" then
    for row in pools:EnumerateActive() do
      local label = type(row) == "table" and row.Label or nil
      if type(label) == "table" then n = n + show(SURFACE, rowKey(label), label, nil, ROW) end
    end
  end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function PvPRank.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  local frame = get("frame")
  if hooked or type(frame) ~= "table" then return false end -- no PVPRankFrame
  hooked = true
  if type(frame.Update) == "function" then hooksecurefunc(frame, "Update", PvPRank.onUpdate) end
  if type(frame.UpdateSeasonCountdownTimer) == "function" then
    hooksecurefunc(frame, "UpdateSeasonCountdownTimer", PvPRank.onTimer)
  end
  local detail = get("detail")
  if type(detail) == "table" and type(detail.Refresh) == "function" then
    hooksecurefunc(detail, "Refresh", PvPRank.onRefresh)
  end
  PvPRank.onUpdate()
  PvPRank.onRefresh()
  return true
end
