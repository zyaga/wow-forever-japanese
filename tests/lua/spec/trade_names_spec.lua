-- UI/Trade: the item names on slots 1–6 of both sides (TradePlayerItem<i>Name / TradeRecipientItem<i>Name, written by
-- TradeFrame_UpdatePlayerItem / _UpdateTargetItem, mainline/tradeframe.lua:101–171). While names are on each shows
-- the item's Japanese; the enchant slot (7) and the players' names are unchanged.
local Stub = require("tests.lua.spec.wow_stub")
local G = require("tests.lua.spec.stub_gamepanels")

local FILES = G.files("UI/Trade.lua")
local NAMES = { "TradeFrame", "TradeFrameTradeButton", "TradeFrameCancelButton", "TradeFramePlayerEnchantText",
  "TradeFrameRecipientEnchantText", "TradeFramePlayerNameText", "TradeFrameRecipientNameText",
  "TradeFrame_UpdatePlayerItem", "TradeFrame_UpdateTargetItem" }

local items = { player = {}, target = {} }

local function install()
  local frame = G.titled("TradeFrame")
  Stub.button("TradeFrameTradeButton", "Trade")
  Stub.button("TradeFrameCancelButton", "Cancel")
  Stub.namedFontString("TradeFramePlayerNameText", "Linen Cloth") -- a player who shares an item's name
  Stub.namedFontString("TradeFrameRecipientNameText", "Someone")
  for i = 1, 7 do
    Stub.namedFontString("TradePlayerItem" .. i .. "Name", "")
    Stub.namedFontString("TradeRecipientItem" .. i .. "Name", "")
    NAMES[#NAMES + 1] = "TradePlayerItem" .. i .. "Name"
    NAMES[#NAMES + 1] = "TradeRecipientItem" .. i .. "Name"
  end
  _G.TradeFrame_UpdatePlayerItem = function(id) _G["TradePlayerItem" .. id .. "Name"]:SetText(items.player[id]) end
  _G.TradeFrame_UpdateTargetItem = function(id) _G["TradeRecipientItem" .. id .. "Name"]:SetText(items.target[id]) end
  return frame
end

describe("UI/Trade's item names", function()
  local WFJ, frame

  before_each(function()
    WFJ = G.load(FILES, {})
    items.player, items.target = {}, {}
    frame = install()
    WFJ.Data.add("name", {
      [WFJ.Names.key("Linen Cloth")] = "リネン・クロス\tりねん・くろす",
      [WFJ.Names.key("Copper Ore")] = "コッパー・オア\tこっぱー・おあ",
    })
    WFJ.State.setNames(true)
    WFJ.Labels.forbidNames(WFJ.Trade.NEVER_TOUCH)
    assert.is_true(WFJ.Trade.init())
    frame:Show()
  end)

  after_each(function()
    G.alt(WFJ, false)
    G.clear(NAMES)
  end)

  it("both sides' items show their Japanese; the reveal key and closing give the English back", function()
    items.player[1], items.target[2] = "Linen Cloth", "Copper Ore"
    _G.TradeFrame_UpdatePlayerItem(1)
    _G.TradeFrame_UpdateTargetItem(2)
    assert.are.equal("リネン・クロス", _G.TradePlayerItem1Name:GetText())
    assert.are.equal("コッパー・オア", _G.TradeRecipientItem2Name:GetText())
    G.alt(WFJ, true)
    assert.are.equal("Linen Cloth", _G.TradePlayerItem1Name:GetText())
    G.alt(WFJ, false)
    assert.are.equal("リネン・クロス", _G.TradePlayerItem1Name:GetText())
    frame:Hide()
    assert.are.equal("Linen Cloth", _G.TradePlayerItem1Name:GetText())
    assert.are.equal("Copper Ore", _G.TradeRecipientItem2Name:GetText())
  end)

  it("an item taken out of a slot leaves the slot empty", function()
    items.player[1] = "Linen Cloth"
    _G.TradeFrame_UpdatePlayerItem(1)
    items.player[1] = nil
    _G.TradeFrame_UpdatePlayerItem(1)
    assert.are.equal("", _G.TradePlayerItem1Name:GetText() or "")
    G.alt(WFJ, true)
    G.alt(WFJ, false)
    assert.are.equal("", _G.TradePlayerItem1Name:GetText() or "")
  end)

  it("an item with no Japanese, the players' names and names off are never written", function()
    items.player[1] = "Nobody Known Sword"
    _G.TradeFrame_UpdatePlayerItem(1)
    assert.are.equal(0, _G.TradePlayerItem1Name.calls.addonSetText)
    assert.are.equal("Linen Cloth", _G.TradeFramePlayerNameText:GetText())
    WFJ.State.setNames(false)
    items.target[1] = "Linen Cloth"
    _G.TradeFrame_UpdateTargetItem(1)
    assert.are.equal("Linen Cloth", _G.TradeRecipientItem1Name:GetText())
    assert.are.equal(0, _G.TradeRecipientItem1Name.calls.addonSetText)
  end)
end)
