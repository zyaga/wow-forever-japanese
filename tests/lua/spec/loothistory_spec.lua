-- UI/LootHistory.lua over GroupLootHistoryFrame as camelot
-- blizzard_framexml/mainline/loothistory.lua:401–441 and loothistory.xml:98, 154, 193–427 build it. The title is
-- written directly at OnLoad (no SetTitle call); the spec also proves a later SetTitle keeps the Japanese.
local Stub = require("tests.lua.spec.wow_stub")
local X = require("tests.lua.spec.stub_framexml_hud")

local UI = {
  LOOT_ROLLS = { "Loot Rolls", "ロット履歴" }, LOOT_HISTORY_PASSED = { "Passed", "パス" },
  LOOT_HISTORY_ALL_PASSED = { "All Passed", "全員パス" },
  LOOT_HISTORY_INFO_TEXT = { "Loot rolls from group content are displayed here", "グループのロット結果がここに表示されます" },
  -- the tie line and the waiting-on tooltip line
  LOOT_HISTORY_CURRENT_WINNER = { "%s (%d)", "%s（%d）" }, LOOT_HISTORY_ROLL_TIE = { "Tie", "同点" },
  LOOT_HISTORY_WAITING_ON = { "Waiting on: ", "待機中: " },
}
local NAMES = { "GroupLootHistoryFrame" }

local function element(item, winner)
  local row = CreateFrame("Frame")
  row.ItemName = Stub.fontString(item)
  row.WinningRollInfo = { WinningRoll = Stub.fontString(winner) }
  row.AllPassedInfo = { AllPassedText = Stub.fontString("All Passed") }
  function row.GetRegions() return row.ItemName end
  return row
end

local function header()
  local row, label = CreateFrame("Frame"), Stub.fontString("Passed")
  function row.GetRegions() return label end
  return row, label
end

local function install()
  local f = CreateFrame("Frame", "GroupLootHistoryFrame")
  f.TitleContainer = { TitleText = Stub.fontString("Loot Rolls") }
  function f.SetTitle(self, t) self.TitleContainer.TitleText.text = t end
  f.NoInfoString = Stub.fontString(_G.LOOT_HISTORY_INFO_TEXT or "Loot rolls from group content are displayed here")
  f.ScrollBox = Stub.scrollBox()
end

describe("the group loot rolls window on Forever", function()
  local WFJ
  before_each(function()
    WFJ = X.load("UI/LootHistory.lua", UI, { before = install })
    assert.is_true(WFJ.LootHistory.init())
  end)
  after_each(function() X.teardown(NAMES) end)

  it("the title and the empty text translate; the title survives a second SetTitle", function()
    local f = _G.GroupLootHistoryFrame
    assert.are.equal("ロット履歴", f.TitleContainer.TitleText:GetText())
    assert.are.equal("グループのロット結果がここに表示されます", f.NoInfoString:GetText())
    f:SetTitle("Loot Rolls")
    assert.are.equal("ロット履歴", f.TitleContainer.TitleText:GetText())
    f:SetTitle("Loot Rolls")
    assert.are.equal("ロット履歴", f.TitleContainer.TitleText:GetText())
    X.alt(WFJ, true)
    assert.are.equal("Loot Rolls", f.TitleContainer.TitleText:GetText())
    X.alt(WFJ, false)
  end)

  it("rows translate as the view initializes them; item and player names stay English", function()
    local box = _G.GroupLootHistoryFrame.ScrollBox
    local row = element("Passed", "All Passed") -- an item and a player named like dictionary words
    box:initFrame(row, { lootListKey = 1 })
    local head, label = header()
    box:initFrame(head, { isPassedHeader = true })
    assert.are.equal("全員パス", row.AllPassedInfo.AllPassedText:GetText())
    assert.are.equal("パス", label:GetText())
    assert.are.equal("Passed", row.ItemName:GetText())
    assert.are.equal("All Passed", row.WinningRollInfo.WinningRoll:GetText())
    assert.is_true(X.unrecorded(WFJ, row.ItemName))
    -- the row is reused; on show every existing frame is walked again
    row.AllPassedInfo.AllPassedText.text = "All Passed"
    _G.GroupLootHistoryFrame:Show()
    assert.are.equal("全員パス", row.AllPassedInfo.AllPassedText:GetText())
  end)

  it("a tie's current-winner line translates, the roll kept; a leader named 'Tie' stays English", function()
    local box = _G.GroupLootHistoryFrame.ScrollBox
    local row = element("Linen Cloth", "")
    local winner = Stub.fontString("")
    row.PendingRollInfo = { CurrentWinnerText = winner }
    function row.Init(self, drop) -- loothistory.lua:150–158
      self.dropInfo = drop
      winner.text = (drop.isTied and "Tie" or drop.leader) .. " (" .. drop.roll .. ")"
    end
    box:initFrame(row, {}, function(r) r:Init({ isTied = true, roll = 87 }) end)
    assert.are.equal("同点（87）", winner:GetText())
    X.alt(WFJ, true)
    assert.are.equal("Tie (87)", winner:GetText())
    X.alt(WFJ, false)
    row:Init({ isTied = false, leader = "Tie", roll = 90 }) -- OnEvent re-Init: a player called Tie
    assert.are.equal("Tie (90)", winner:GetText())
    row:Init({ isTied = true, roll = 12 })
    assert.are.equal("同点（12）", winner:GetText())
    -- the row's tooltip: the waiting-on line, the players' names kept; the item title never matched
    local tt = _G.GameTooltip
    tt:SetOwner(row)
    tt:ClearLines()
    tt:AddLine("Tie")
    tt:AddLine("Waiting on: |cffc79c6eThrall|r, |cff3fc7ebJaina|r")
    tt:Show()
    assert.are.equal("Tie", _G.GameTooltipTextLeft1:GetText())
    assert.are.equal("待機中: |cffc79c6eThrall|r, |cff3fc7ebJaina|r", _G.GameTooltipTextLeft2:GetText())
  end)

  it("hooks once; wrong types raise nothing; without the frame init returns false", function()
    assert.is_false(WFJ.LootHistory.init())
    X.teardown(NAMES)
    local wrong = X.load("UI/LootHistory.lua", UI, { before = function()
      install()
      _G.GroupLootHistoryFrame.ScrollBox = "x"
      _G.GroupLootHistoryFrame.NoInfoString = 5
      _G.ScrollUtil = "x"
    end })
    assert.has_no.errors(function() assert.is_true(wrong.LootHistory.init()) end)
    assert.has_no.errors(function() wrong.LootHistory.onRow(nil); wrong.LootHistory.onRow("x", 3) end)
    X.teardown(NAMES)
    local bare = X.load("UI/LootHistory.lua", UI)
    assert.has_no.errors(function() assert.is_false(bare.LootHistory.init()) end)
  end)
end)
