-- UI/LootHistory.lua: the group loot rolls window (/loot) on Forever (surface "loothistory", area "ui",
-- ADR-016). Blizzard_FrameXML loads mainline/loothistory.lua|xml and camelot/loothistory.lua on camelot (the override
-- only stops the window opening by itself: LootHistoryFrameMixin:ShouldAutoOpen → false, camelot/loothistory.lua:1–3).
-- Entry points in the load set: the /loot slash command (blizzard_chatframebase/shared/slashcommands.lua:1431 →
-- ToggleLootHistoryFrame) and a loot-history chat link (blizzard_uipanels_game/mainline/itemrefhandlers.lua:101).
--   GroupLootHistoryFrame.TitleContainer.TitleText   LOOT_ROLLS, written directly in InitRegions at OnLoad
--                                                    (loothistory.lua:440); no SetTitle call; Labels.title shows it
--                                                    and would follow a SetTitle if one were ever made
--   GroupLootHistoryFrame.NoInfoString               static LOOT_HISTORY_INFO_TEXT (loothistory.xml:427)
--   ScrollBox rows (LootHistoryElementTemplate)      AllPassedInfo.AllPassedText static LOOT_HISTORY_ALL_PASSED
--                                                    (xml:98); the "Passed" header's unnamed label
--                                                    LOOT_HISTORY_PASSED (xml:154), found by the client's English
-- Rows come from a ScrollBox element factory (loothistory.lua:401–428); they are reached through
-- ScrollUtil.AddInitializedFrameCallback (existing frames, then every frame the view initializes) and keyed by
-- widget, never by position.
-- PendingRollInfo.CurrentWinnerText is LOOT_HISTORY_CURRENT_WINNER "%s (%d)" with the leader's name, or
-- LOOT_HISTORY_ROLL_TIE when dropInfo.isTied (loothistory.lua:150–158, in LootHistoryElementMixin:Init). The line is
-- shown (key-only, the `words` argument "Tie" in Japanese, the roll kept) ONLY when the row's dropInfo.isTied: a
-- player whose name is a dictionary word ("Tie") is never translated (names stay in English); otherwise the line has
-- no word of its own and stays as written. Init also runs from the row's OnEvent (:17–22): each row's Init is
-- post-hooked once.
-- The row's own tooltip (SetTooltip, owner = the row, :46–108) ends with "Waiting on: " .. the players' names
-- (LOOT_HISTORY_WAITING_ON, the `prefix` form, names kept): the row is registered with that one key, so the item-name
-- title is never matched.
-- Never touched: ItemName (an item), WinningRollInfo.WinningRoll (a player), a leader's name, the EncounterDropdown
-- (encounter names; its popup is UI/Menus').
-- Without GroupLootHistoryFrame nothing is hooked.
local _, WFJ = ...
local LootHistory = {}
WFJ.LootHistory = LootHistory

local SURFACE = "loothistory"
LootHistory.SURFACE = SURFACE
local Compat = WFJ.Compat

LootHistory.NEVER_TOUCH = {}

local CANDIDATES = {
  frame = { "GroupLootHistoryFrame" }, noInfo = { "GroupLootHistoryFrame.NoInfoString" },
  box = { "GroupLootHistoryFrame.ScrollBox" }, scrollUtil = { "ScrollUtil" },
}
local TITLE = { only = { "LOOT_ROLLS" } }
local NO_INFO = { only = { "LOOT_HISTORY_INFO_TEXT" } }
local ALL_PASSED = { only = { "LOOT_HISTORY_ALL_PASSED" } }
local PASSED = { only = { "LOOT_HISTORY_PASSED" } }
local rowKey = WFJ.Labels.keyer("row.") -- a pooled row label's record key
local WINNER = { only = { "LOOT_HISTORY_CURRENT_WINNER" } }
local ROW_TIP = { only = { "LOOT_HISTORY_WAITING_ON" } }
local initHooked = setmetatable({}, { __mode = "k" })

-- The current-winner line of a row, shown only for a tie (see the header).
local function showWinner(row)
  local pending = row.PendingRollInfo
  local text = type(pending) == "table" and pending.CurrentWinnerText or nil
  if type(text) ~= "table" then return end
  local key = rowKey(text)
  if type(row.dropInfo) == "table" and row.dropInfo.isTied then
    WFJ.Labels.show(SURFACE, key, text, nil, WINNER)
  else
    WFJ.SurfaceState.drop(SURFACE, key) -- a leader's name: never ours
  end
end

local function get(key) return Compat.get(SURFACE, key) end

-- ScrollUtil callback: (owner, frame, elementData) for a newly initialized row, (frame, elementData) on the
-- existing-frames pass. Returns nothing (ForEachFrame stops at the first truthy return).
-- The header's label is looked for only on a row the view built as the "Passed" header (elementData.isPassedHeader,
-- loothistory.lua:411): an item row's regions include its ItemName, and an item can be called "Passed".
function LootHistory.onRow(a, b, c)
  local row, data = a, b
  if a == LootHistory then row, data = b, c end
  if type(row) ~= "table" then return end
  local info = row.AllPassedInfo
  local text = type(info) == "table" and info.AllPassedText or nil
  if type(text) == "table" then WFJ.Labels.show(SURFACE, rowKey(text), text, nil, ALL_PASSED) end
  showWinner(row)
  WFJ.HelpTooltip.register(row, ROW_TIP)
  if not initHooked[row] and type(row.Init) == "function" then
    initHooked[row] = true
    hooksecurefunc(row, "Init", showWinner)
  end
  if type(data) == "table" and data.isPassedHeader then
    local header = WFJ.Labels.region(row, "LOOT_HISTORY_PASSED")
    if header then WFJ.Labels.show(SURFACE, rowKey(header), header, nil, PASSED) end
  end
end

-- HookScript target (GroupLootHistoryFrame OnShow). → the number of words found on the frame itself.
function LootHistory.onShow()
  local n = WFJ.Labels.title(SURFACE, get("frame"), TITLE)
    + WFJ.Labels.show(SURFACE, "noInfo", get("noInfo"), nil, NO_INFO)
  local box = get("box")
  if type(box) == "table" and type(box.ForEachFrame) == "function" then box:ForEachFrame(LootHistory.onRow) end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

local hooked = false

-- Called by Main after Compat.init.
function LootHistory.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  local frame = get("frame")
  if hooked or type(frame) ~= "table" then return false end -- no GroupLootHistoryFrame
  hooked = true
  if type(frame.HookScript) == "function" then frame:HookScript("OnShow", LootHistory.onShow) end
  local util, box = get("scrollUtil"), get("box")
  if type(util) == "table" and type(util.AddInitializedFrameCallback) == "function" and type(box) == "table"
      and type(box.ForEachFrame) == "function" then
    util.AddInitializedFrameCallback(box, LootHistory.onRow, LootHistory, true)
  end
  LootHistory.onShow()
  return true
end
