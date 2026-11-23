-- UI/LootHistory: a row's ItemName holds the item's name (LootHistoryElementMixin:Init, blizzard_framexml/mainline/
-- loothistory.lua:111–120; Init runs again from the row's OnEvent, :17–22). While names are on it shows the item's
-- Japanese; the winner's name is unchanged.
local Stub = require("tests.lua.spec.wow_stub")
local X = require("tests.lua.spec.stub_framexml_hud")

local NAMES = { "GroupLootHistoryFrame" }

local function install()
  local f = CreateFrame("Frame", "GroupLootHistoryFrame")
  f.TitleContainer = { TitleText = Stub.fontString("Loot Rolls") }
  f.ScrollBox = Stub.scrollBox()
end

local function element()
  local row = CreateFrame("Frame")
  row.ItemName = Stub.fontString("")
  row.WinningRollInfo = { WinningRoll = Stub.fontString("") }
  function row.GetRegions() return row.ItemName end
  function row.Init(self, drop)
    self.dropInfo = drop
    self.ItemName:SetText(drop.item)
    self.WinningRollInfo.WinningRoll:SetText(drop.winner or "")
  end
  return row
end

describe("UI/LootHistory's item names", function()
  local WFJ, box

  before_each(function()
    WFJ = X.load("UI/LootHistory.lua", {}, { before = install })
    WFJ.Data.add("name", {
      [WFJ.Names.key("Thunderfury")] = "サンダーフューリー\tさんだーふゅーりー",
      [WFJ.Names.key("Linen Cloth")] = "リネン・クロス\tりねん・くろす",
    })
    WFJ.State.setNames(true)
    assert.is_true(WFJ.LootHistory.init())
    box = _G.GroupLootHistoryFrame.ScrollBox
    _G.GroupLootHistoryFrame:Show()
  end)
  after_each(function() X.teardown(NAMES) end)

  it("a row's item shows its Japanese; the reveal key and closing give the English back", function()
    local row = element()
    box:initFrame(row, {}, function(r) r:Init({ item = "Thunderfury", winner = "Linen Cloth" }) end)
    assert.are.equal("サンダーフューリー", row.ItemName:GetText())
    assert.are.equal("Linen Cloth", row.WinningRollInfo.WinningRoll:GetText()) -- a player
    X.alt(WFJ, true)
    assert.are.equal("Thunderfury", row.ItemName:GetText())
    X.alt(WFJ, false)
    _G.GroupLootHistoryFrame:Hide()
    assert.are.equal("Thunderfury", row.ItemName:GetText())
    _G.GroupLootHistoryFrame:Show() -- every existing row is walked again
    assert.are.equal("サンダーフューリー", row.ItemName:GetText())
  end)

  it("a row the client initializes again (its OnEvent) shows the new item's Japanese", function()
    local row = element()
    box:initFrame(row, {}, function(r) r:Init({ item = "" }) end) -- the item's data not loaded yet
    row:Init({ item = "Linen Cloth" })
    assert.are.equal("リネン・クロス", row.ItemName:GetText())
    row:Init({ item = "Nobody Known Sword" })
    assert.are.equal("Nobody Known Sword", row.ItemName:GetText())
  end)

  it("with names off nothing is written", function()
    WFJ.State.setNames(false)
    local row = element()
    box:initFrame(row, {}, function(r) r:Init({ item = "Thunderfury" }) end)
    assert.are.equal("Thunderfury", row.ItemName:GetText())
    assert.are.equal(0, row.ItemName.calls.addonSetText)
  end)
end)
