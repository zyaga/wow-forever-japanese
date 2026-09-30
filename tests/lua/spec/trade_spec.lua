-- The trade window on Forever: UI/Trade.lua over a TradeFrame replayed from camelot
-- blizzard_uipanels_game/mainline/tradeframe.lua (TradeFrame_Update :68–83, _UpdatePlayerItem :96–118,
-- _UpdateTargetItem :145–166, _UpdateWarnings :85–93) and tradeframe.xml.
local Stub = require("tests.lua.spec.wow_stub")
local G = require("tests.lua.spec.stub_gamepanels")

local FILES = G.files("UI/Trade.lua")
local UI = {
  TRADE = { "Trade", "トレード" }, CANCEL = { "Cancel", "キャンセル" },
  TRADEFRAME_ENCHANT_SLOT_LABEL = { "Will not be traded", "トレードされません" },
  TRADEFRAME_NOT_MODIFIED_TEXT = { "Item not yet modified", "アイテムは未変更です" },
  TRADE_WARNING_CHANGED_OFFER = { "%s has changed their trade offer. Please ensure you are receiving the correct "
    .. "items and gold.", "%sがトレード内容を変更しました。受け取るアイテムとゴールドが正しいか確認してください。" },
}
local NAMES = { "TradeFrame", "TradeFrameTradeButton", "TradeFrameCancelButton", "TradeFramePlayerEnchantText",
  "TradeFrameRecipientEnchantText", "TradeFramePlayerNameText", "TradeFrameRecipientNameText",
  "TradeFrame_UpdatePlayerItem", "TradeFrame_UpdateTargetItem" }

local T = {} -- replayed client state: T.playerEnchant / T.targetEnchant = name | nil; T.hasItem

local function patch(WFJ) -- the Core/UIStrings entries this surface needs
  WFJ.UIStrings.ARGS.TRADE_WARNING_CHANGED_OFFER = { [1] = "text" }
  WFJ.UIStrings.LABELS.TRADEFRAME_NOT_MODIFIED_TEXT = "wrapped"
end

local function install()
  local frame = G.titled("TradeFrame")
  Stub.button("TradeFrameTradeButton", "Trade")
  Stub.button("TradeFrameCancelButton", "Cancel")
  Stub.namedFontString("TradeFramePlayerEnchantText", "Will not be traded")
  Stub.namedFontString("TradeFrameRecipientEnchantText", "Will not be traded")
  Stub.namedFontString("TradeFramePlayerNameText", "Trade")     -- a player called "Trade"
  Stub.namedFontString("TradeFrameRecipientNameText", "Cancel") -- … and one called "Cancel"
  for i = 1, 7 do
    Stub.namedFontString("TradePlayerItem" .. i .. "Name", "")
    Stub.namedFontString("TradeRecipientItem" .. i .. "Name", "")
    NAMES[#NAMES + 1] = "TradePlayerItem" .. i .. "Name"
    NAMES[#NAMES + 1] = "TradeRecipientItem" .. i .. "Name"
  end
  local function write(fs, id, enchant)
    if id == 7 then
      if not T.hasItem then fs.text = ""
      elseif enchant then fs.text = "|cff20ff20" .. enchant .. "|r"
      else fs.text = "|cffffffff" .. _G.TRADEFRAME_NOT_MODIFIED_TEXT .. "|r" end
    else
      fs.text = "Item not yet modified" -- an item that happens to carry the dictionary word as its name
    end
  end
  _G.TradeFrame_UpdatePlayerItem = function(id) write(_G["TradePlayerItem" .. id .. "Name"], id, T.playerEnchant) end
  _G.TradeFrame_UpdateTargetItem = function(id) write(_G["TradeRecipientItem" .. id .. "Name"], id, T.targetEnchant) end
  return frame
end

describe("the trade window on Forever", function()
  local WFJ

  before_each(function()
    WFJ = G.load(FILES, UI, patch)
    T.playerEnchant, T.targetEnchant, T.hasItem = nil, nil, true
  end)
  after_each(function() G.clear(NAMES) end)

  it("static labels and the enchant slot's fixed word translate; names and item names stay English", function()
    local frame = install()
    WFJ.Labels.forbidNames(WFJ.Trade.NEVER_TOUCH)
    assert.is_true(WFJ.Trade.init())
    frame:Show()
    assert.are.equal("トレード", _G.TradeFrameTradeButton:GetText())
    assert.are.equal("キャンセル", _G.TradeFrameCancelButton:GetText())
    assert.are.equal("トレードされません", _G.TradeFramePlayerEnchantText:GetText())
    assert.are.equal("トレードされません", _G.TradeFrameRecipientEnchantText:GetText())
    assert.are.equal("Trade", _G.TradeFramePlayerNameText:GetText())
    assert.are.equal("Cancel", _G.TradeFrameRecipientNameText:GetText())
    assert.is_true(G.unrecorded(WFJ, _G.TradeFramePlayerNameText))
    for id = 1, 7 do _G.TradeFrame_UpdatePlayerItem(id); _G.TradeFrame_UpdateTargetItem(id) end
    assert.are.equal("|cffffffffアイテムは未変更です|r", _G.TradePlayerItem7Name:GetText())
    assert.are.equal("|cffffffffアイテムは未変更です|r", _G.TradeRecipientItem7Name:GetText())
    assert.are.equal("Item not yet modified", _G.TradePlayerItem3Name:GetText()) -- an item's name
    assert.is_true(G.unrecorded(WFJ, _G.TradePlayerItem3Name))
    T.playerEnchant = "Enchant Weapon - Crusader"
    _G.TradeFrame_UpdatePlayerItem(7)
    assert.are.equal("|cff20ff20Enchant Weapon - Crusader|r", _G.TradePlayerItem7Name:GetText())
    G.alt(WFJ, true)
    assert.are.equal("Trade", _G.TradeFrameTradeButton:GetText())
    assert.are.equal("|cffffffffItem not yet modified|r", _G.TradeRecipientItem7Name:GetText())
    G.alt(WFJ, false)
    frame:Hide()
    assert.are.equal("Trade", _G.TradeFrameTradeButton:GetText())
  end)

  it("the changed-offer warning tooltip translates around the player's name", function()
    install()
    assert.is_true(WFJ.Trade.init())
    G.tooltip(_G.TradeFrameTradeButton, { UI.TRADE_WARNING_CHANGED_OFFER[1]:format("Thrall") })
    assert.are.equal(UI.TRADE_WARNING_CHANGED_OFFER[2]:format("Thrall"), G.line(1))
    G.tooltip(_G.TradeFrameTradeButton, { "Trade" }) -- not this owner's key
    assert.are.equal("Trade", G.line(1))
  end)

  it("wrong-typed names degrade without error; hooks install once", function()
    install()
    _G.TradeFrameCancelButton = 7
    _G.TradeFramePlayerEnchantText = "x"
    _G.TradeFrame_UpdateTargetItem = {}
    assert.has_no.errors(function() assert.is_true(WFJ.Trade.init()) end)
    assert.has_no.errors(function() _G.TradeFrame:Show() end)
    assert.are.equal("トレード", _G.TradeFrameTradeButton:GetText())
    assert.is_false(WFJ.Trade.init())
    assert.are.equal(1, #Stub.hooks["TradeFrame_UpdatePlayerItem"])
    assert.is_nil(Stub.hooks["TradeFrame_UpdateTargetItem"])
  end)

  it("no TradeFrame or a TradeFrame of the wrong type: init is false", function()
    assert.has_no.errors(function() assert.is_false(WFJ.Trade.init()) end)
    _G.TradeFrame = 3
    assert.has_no.errors(function() assert.is_false(WFJ.Trade.init()) end)
  end)
end)
