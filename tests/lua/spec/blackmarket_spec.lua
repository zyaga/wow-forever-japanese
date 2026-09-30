-- UI/BlackMarket.lua over a BlackMarketFrame replayed from camelot blizzard_blackmarketui
-- (blizzard_blackmarketui.xml:332–684 static labels; blizzard_blackmarketui.lua:70–120 BlackMarketItemMixin:Init,
-- :170–218 BlackMarketFrame_UpdateHotItem). Item names, sellers and item types stay English. Client writes go to
-- `fs.text`.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local C = require("tests.lua.spec.stub_commerce")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/BlackMarket.lua"

local ADDON = "Blizzard_BlackMarketUI"

-- Forever GlobalStrings (build 1.60.1.69913) → a test Japanese
local UI = {
  HOT_ITEM = { "Hot Item!", "注目アイテム！" }, HOT_ITEM_SELLER = { "Seller:", "出品者:" },
  BLACK_MARKET_HOT_ITEM_CURRENT_BID = { "Current Bid:", "現在の入札額:" },
  BLACK_MARKET_YOUR_BID = { "Your Bid!", "あなたの入札！" },
  NAME = { "Name", "名前" }, REQ_LEVEL_ABBR = { "Lvl", "Lv" }, TYPE = { "Type", "種類" },
  CLOSES_IN = { "Time Left", "残り時間" }, AUCTION_CREATOR = { "Seller", "出品者" },
  CURRENT_BID = { "Current Bid", "現在の入札額" }, BID = { "Bid", "入札" },
  BLACK_MARKET_NO_ITEMS = { "There are no items at this time.\nPlease check back later.",
    "現在アイテムはありません。\n後でもう一度確認してください。" },
  AUCTION_TIME_LEFT1 = { "Short", "短い" }, AUCTION_TIME_LEFT4 = { "Very Long", "非常に長い" },
  AUCTION_TIME_LEFT1_DETAIL = { "Less than 30 mins", "30分未満" },
  BLACK_MARKET_HOT_ITEM_TIME_LEFT = { "Time Left: %s", "残り時間: %s" },
  AUCTION_TIME_LEFT4_DETAIL = { "Greater than 12 hrs", "12時間以上" },
}

local function en(key) return _G[key] end
local fs = Stub.fontString

local B = {} -- the replayed client state

local function column(text)
  local c = CreateFrame("Frame")
  c.Name = fs(text)
  return c
end

-- A BlackMarketItemTemplate row and its Init (lua:70–120).
local function newRow()
  local row = CreateFrame("Button")
  row.Name, row.Level, row.Type, row.Seller = fs(""), fs(""), fs(""), fs("")
  row.YourBid = fs(en("BLACK_MARKET_YOUR_BID"))
  row.TimeLeft = CreateFrame("Button")
  row.TimeLeft.Text = fs("")
  return row
end

local function initRow(row, data)
  row.Name.text, row.Level.text = data.name, tostring(data.level)
  row.Type.text, row.Seller.text = data.type, data.seller
  row.TimeLeft.Text.text = en("AUCTION_TIME_LEFT" .. data.timeLeft)
  row.TimeLeft.tooltip = en("AUCTION_TIME_LEFT" .. data.timeLeft .. "_DETAIL")
end

local function loadBlackMarket(o)
  o = o or {}
  local frame = CreateFrame("Frame", "BlackMarketFrame")
  frame:addRegion(fs("Black Market\nAuction House")) -- BLACK_MARKET_TITLE (xml:348)
  local hot = CreateFrame("Frame")
  frame.HotDeal = hot
  hot.Title, hot.SellerTAG = fs(en("HOT_ITEM")), fs(en("HOT_ITEM_SELLER"))
  hot.Name, hot.Seller, hot.Type, hot.Level = fs(""), fs(""), fs(""), fs("")
  hot.TimeLeft = CreateFrame("Frame")
  hot.TimeLeft.Text = fs("")
  hot.BlackMarketHotItemBidPrice = CreateFrame("Frame", "HotItemCurrentBidMoneyFrame")
  hot.BlackMarketHotItemBidPrice.CurrentBid = fs(en("BLACK_MARKET_HOT_ITEM_CURRENT_BID"))
  hot.BlackMarketHotItemBidPrice.YourBid = fs(en("BLACK_MARKET_YOUR_BID"))
  frame.ColumnName, frame.ColumnLevel = column(en("NAME")), column(en("REQ_LEVEL_ABBR"))
  frame.ColumnType, frame.ColumnDuration = column(en("TYPE")), column(en("CLOSES_IN"))
  frame.ColumnHighBidder, frame.ColumnCurrentBid = column(en("AUCTION_CREATOR")), column(en("CURRENT_BID"))
  frame.Inset = CreateFrame("Frame")
  frame.Inset.NoItems = fs(en("BLACK_MARKET_NO_ITEMS"))
  frame.BidButton = Stub.button(nil, en("BID"))
  local price = CreateFrame("Frame", "BlackMarketBidPrice")
  price:addRegion(fs(en("BID")))
  CreateFrame("EditBox", "BlackMarketBidPriceGold")
  frame.ScrollBox = o.scrollBox or Stub.scrollBox()
  _G.BlackMarketFrame_UpdateHotItem = function(self)
    local h = B.hot
    self.HotDeal.Name.text, self.HotDeal.Seller.text, self.HotDeal.Type.text = h.name, h.seller, h.type
    self.HotDeal.TimeLeft.Text.text = string.format(en("BLACK_MARKET_HOT_ITEM_TIME_LEFT"),
      en("AUCTION_TIME_LEFT" .. h.timeLeft))
    self.HotDeal.TimeLeft.tooltip = en("AUCTION_TIME_LEFT" .. h.timeLeft .. "_DETAIL")
  end
  Stub.loadedAddons[ADDON] = true
  return frame
end

describe("the black market window on Forever", function()
  local WFJ, SS

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  local function unrecorded(widget)
    for _, bucket in pairs(SS.surfaces()) do
      for _, rec in pairs(bucket) do
        if rec.fs == widget then return false end
      end
    end
    return true
  end

  local function fresh()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    SS = WFJ.SurfaceState
    H.uiSetup(WFJ, UI)
    B.hot = { name = "Type", seller = "Name", type = "Bid", timeLeft = 4 }
  end

  local function setup(loadedFirst)
    fresh()
    if loadedFirst then
      loadBlackMarket()
      assert.is_true(WFJ.BlackMarket.init())
    else
      assert.is_false(WFJ.BlackMarket.init()) -- waits for the addon
      loadBlackMarket()
      assert.are.equal(1, WFJ.LoadOnDemand.loaded(ADDON))
    end
  end

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    _G.BlackMarketFrame, _G.BlackMarketBidPrice, _G.BlackMarketBidPriceGold = nil, nil, nil
    _G.HotItemCurrentBidMoneyFrame, _G.BlackMarketFrame_UpdateHotItem = nil, nil
  end)

  for _, order in ipairs({ { true, "loaded at login" }, { false, "loaded on demand" } }) do
    describe("Blizzard_BlackMarketUI " .. order[2], function()
      before_each(function() setup(order[1]) end)

      it("the hot-item labels, the column headers and the bid controls are Japanese; the title stays", function()
        local f = _G.BlackMarketFrame
        assert.are.equal("Black Market\nAuction House", (f:GetRegions()):GetText()) -- a place's name
        assert.are.equal("注目アイテム！", f.HotDeal.Title:GetText())
        assert.are.equal("出品者:", f.HotDeal.SellerTAG:GetText())
        assert.are.equal("現在の入札額:", f.HotDeal.BlackMarketHotItemBidPrice.CurrentBid:GetText())
        assert.are.equal("あなたの入札！", f.HotDeal.BlackMarketHotItemBidPrice.YourBid:GetText())
        assert.are.equal("名前", f.ColumnName.Name:GetText())
        assert.are.equal("Lv", f.ColumnLevel.Name:GetText())
        assert.are.equal("種類", f.ColumnType.Name:GetText())
        assert.are.equal("残り時間", f.ColumnDuration.Name:GetText())
        assert.are.equal("出品者", f.ColumnHighBidder.Name:GetText())
        assert.are.equal("現在の入札額", f.ColumnCurrentBid.Name:GetText())
        assert.are.equal("現在アイテムはありません。\n後でもう一度確認してください。", f.Inset.NoItems:GetText())
        assert.are.equal("入札", f.BidButton:GetText())
        assert.are.equal("入札", (_G.BlackMarketBidPrice:GetRegions()):GetText())
        alt(true)
        assert.are.equal("Hot Item!", f.HotDeal.Title:GetText())
        assert.are.equal("Bid", f.BidButton:GetText())
        alt(false)
      end)

      it("the hot item: an item, a seller and a type that spell UI words stay English", function()
        local f = _G.BlackMarketFrame
        -- the time-left line's `%s` is a time-band word (`words`: "Very Long"; the core entry is in
        -- Core/UIStrings)
        C.args(WFJ, UI, { BLACK_MARKET_HOT_ITEM_TIME_LEFT = { [1] = "words" } })
        _G.BlackMarketFrame_UpdateHotItem(f)
        assert.are.equal("残り時間: 非常に長い", f.HotDeal.TimeLeft.Text:GetText())
        assert.are.equal("Type", f.HotDeal.Name:GetText())
        assert.are.equal("Name", f.HotDeal.Seller:GetText())
        assert.are.equal("Bid", f.HotDeal.Type:GetText())
        assert.is_true(unrecorded(f.HotDeal.Name))
        assert.is_true(unrecorded(f.HotDeal.Seller))
        assert.is_true(unrecorded(f.HotDeal.Type))
        -- the time-left tooltip of the hot item
        local tt = _G.GameTooltip
        tt:SetOwner(f.HotDeal.TimeLeft)
        tt:SetText(f.HotDeal.TimeLeft.tooltip)
        assert.are.equal("12時間以上", _G.GameTooltipTextLeft1:GetText())
      end)

      it("pooled rows: the time band, its tooltip and the bid flag translate; a reused row shows its new band",
        function()
          local box = _G.BlackMarketFrame.ScrollBox
          local row = newRow()
          box:initFrame(row, { name = "Bid", level = 60, type = "Type", seller = "Name", timeLeft = 1 }, initRow)
          assert.are.equal("短い", row.TimeLeft.Text:GetText())
          assert.are.equal("あなたの入札！", row.YourBid:GetText())
          assert.are.equal("Bid", row.Name:GetText())
          assert.are.equal("Name", row.Seller:GetText())
          assert.are.equal("Type", row.Type:GetText())
          assert.is_true(unrecorded(row.Name))
          assert.is_true(unrecorded(row.Seller))
          assert.is_true(unrecorded(row.Type))
          local tt = _G.GameTooltip
          tt:SetOwner(row.TimeLeft)
          tt:SetText(row.TimeLeft.tooltip)
          assert.are.equal("30分未満", _G.GameTooltipTextLeft1:GetText())
          box:initFrame(row, { name = "Thunderfury", level = 60, type = "Weapon", seller = "Goya", timeLeft = 4 },
            initRow)
          assert.are.equal("非常に長い", row.TimeLeft.Text:GetText())
          alt(true)
          assert.are.equal("Very Long", row.TimeLeft.Text:GetText())
          alt(false)
          _G.BlackMarketFrame:Hide()
          assert.is_true(unrecorded(row.TimeLeft.Text))
          assert.are.equal("注目アイテム！", _G.BlackMarketFrame.HotDeal.Title:GetText()) -- static labels stay
        end)
    end)
  end

  it("rows laid out before the addon was seen are walked at setup", function()
    fresh()
    local f = loadBlackMarket()
    local row = newRow()
    f.ScrollBox:initFrame(row, { name = "x", level = 1, type = "y", seller = "z", timeLeft = 1 }, initRow)
    assert.is_true(WFJ.BlackMarket.init())
    assert.are.equal("短い", row.TimeLeft.Text:GetText())
  end)

  it("client names bound to the wrong type degrade to English with no error", function()
    fresh()
    local f = loadBlackMarket({ scrollBox = "not a table" })
    f.HotDeal, f.ColumnName, f.BidButton = 7, "x", true
    _G.BlackMarketBidPrice, _G.BlackMarketFrame_UpdateHotItem, _G.ScrollUtil = 3, "nope", 1
    assert.has_no.errors(function() assert.is_true(WFJ.BlackMarket.init()) end)
    assert.are.equal("種類", f.ColumnType.Name:GetText()) -- the rest of the window still renders
    assert.has_no.errors(function() WFJ.BlackMarket.onRow(WFJ.BlackMarket, 5) end)
    assert.has_no.errors(function() WFJ.BlackMarket.onRow({ TimeLeft = 1, YourBid = "x" }) end)
  end)

  it("hooks install once; without the addon init returns false and touches nothing", function()
    setup(true)
    assert.is_false(WFJ.BlackMarket.init())
    assert.are.equal(1, #Stub.hooks["BlackMarketFrame_UpdateHotItem"])
    fresh()
    _G.BlackMarketFrame = nil
    assert.has_no.errors(function() assert.is_false(WFJ.BlackMarket.init()) end)
    Stub.loadedAddons[ADDON] = true -- the addon reported loaded, its frame absent
    assert.has_no.errors(function() assert.is_false(WFJ.BlackMarket.setup()) end)
  end)
end)
