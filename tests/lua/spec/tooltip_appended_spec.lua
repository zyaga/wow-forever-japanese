-- ADR-038: the lines the auction house appends to an item tooltip
-- (AuctionHouseUtil.AddAuctionHouseTooltipInfo, blizzard_auctionhouseui/shared/blizzard_auctionhouseutil.lua:301–306)
-- render Japanese through HelpTooltip.appended while the item's own lines stay with the item path; the cell tooltips
-- (tablebuilder.lua:380–448, 555–603), the WoW Token time-left line (tokenSell, util.lua:4, 263–279), the sold prefix
-- (:741), the buy dialog's notification button (buydialog.lua:32–44) and the token tutorial's balance line
-- (wowtokenframe.lua:359–365). Names (sellers, bidders, items) stay English; Alt shows the client's English.
local Stub = require("tests.lua.spec.wow_stub")
local C = require("tests.lua.spec.stub_commerce")

local ADDON = "Blizzard_AuctionHouseUI"
local GLOBALS = { "AuctionHouseFrame", "AuctionHouseUtil" }

local UI = {
  AUCTION_HOUSE_TOOLTIP_SELLER_FORMAT = { "Seller: |cffffffff%s|r", "出品者: |cffffffff%s|r" },
  AUCTION_HOUSE_TOOLTIP_MULTIPLE_SELLERS_FORMAT = { "Sellers: |cffffffff%s|r", "出品者たち: |cffffffff%s|r" },
  AUCTION_HOUSE_TOOLTIP_OVERFLOW_SELLERS_FORMAT = { "Sellers: |cffffffff%s, and %s more|r",
    "出品者たち: |cffffffff%s、ほか%s人|r" },
  AUCTION_HOUSE_TOOLTIP_DURATION_FORMAT = { "Time Left: |cffffffff%s|r", "残り時間: |cffffffff%s|r" },
  AUCTION_HOUSE_TOOLTIP_TIME_LEFT_LONG = { "2-12 hr", "2～12時間" },
  AUCTION_HOUSE_TIME_LEFT_FORMAT_ACTIVE = { "Time left: |cffffffff%s|r", "残り: |cffffffff%s|r" },
  AUCTION_HOUSE_BUYER_FORMAT = { "Buyer: |cffffffff%s|r", "購入者: |cffffffff%s|r" },
  AUCTION_HOUSE_HIGH_BIDDER_FORMAT = { "High Bidder: |cffffffff%s|r", "最高入札者: |cffffffff%s|r" },
  AUCTION_HOUSE_AUCTION_SOLD_PREFIX = { "|cff00ff00Sold: |r", "|cff00ff00売却済: |r" },
  ESTIMATED_TIME_TO_SELL_LABEL = { "Estimated Time To Sell:|n", "売却までの予想時間:|n" },
  AUCTION_HOUSE_DIALOG_PER_UNIT_INCREASE = { "|cffffd100Per Unit Increase:|r", "|cffffd100単価の上昇:|r" },
  AUCTION_HOUSE_DIALOG_TOTAL_INCREASE = { "|cffffd100Total Increase:|r", "|cffffd100合計の上昇:|r" },
  TOKEN_TRY_AGAIN_LATER = { "Please wait %s before trying again.", "%s待ってから再度お試しください。" },
  INT_SPELL_DURATION_SEC = { "%d sec", "%d秒" },
  TUTORIAL_TOKEN_GAME_TIME_STEP_2_BALANCE = { "2. Redeem it for 30 days of game|ntime (or %s of Blizzard Balance).",
    "2. 30日間のゲームタイム|n(または%sのBlizzard Balance)と交換します。" },
  -- a dictionary word that is also an item's name
  SWORDS = { "Swords", "剣" },
}
local function en(key) return _G[key] end

local function build()
  local frame = C.window("AuctionHouseFrame")
  C.tree(frame, { ["WoWTokenResults.Buyout"] = { button = "Buyout" },
    ["BuyDialog.Notification.Button"] = { button = "" },
    ["WoWTokenResults.GameTimeTutorial.LeftDisplay.Tutorial3"] = "" })
  _G.AuctionHouseUtil = {
    AddAuctionHouseTooltipInfo = function(tt, rowData)
      tt:AddLine(" ")
      tt:AddLine(en("AUCTION_HOUSE_TOOLTIP_SELLER_FORMAT"):format(rowData.owner))
      tt:AddLine(en("AUCTION_HOUSE_TOOLTIP_DURATION_FORMAT"):format(en("AUCTION_HOUSE_TOOLTIP_TIME_LEFT_LONG")))
    end,
  }
  Stub.loadedAddons[ADDON] = true
  return frame
end

describe("auction house appended and cell tooltip lines", function()
  local WFJ, frame

  before_each(function()
    WFJ = C.fresh({ "UI/AuctionHouse.lua" }, UI)
    -- the core's kinds for this key (a no-op once Core/UIStrings declares it)
    C.args(WFJ, UI, { TUTORIAL_TOKEN_GAME_TIME_STEP_2_BALANCE = { [1] = "verbatim" } })
    frame = build()
    assert.is_true(WFJ.AuctionHouse.init())
    frame:Show()
  end)
  after_each(function() C.teardown(GLOBALS) end)

  it("the seller and time-left lines are Japanese, the item's own lines untouched; Alt shows English", function()
    local tt = _G.GameTooltip
    tt:SetOwner(frame, "ANCHOR_RIGHT")
    Stub.setItemTooltip(tt, "|cffffffff|Hitem:1|h[Swords]|h|r", { "Swords", "Main Hand" })
    _G.AuctionHouseUtil.AddAuctionHouseTooltipInfo(tt, { owner = "Thrall" })
    assert.are.equal("Swords", _G.GameTooltipTextLeft1:GetText()) -- the item's name: a dictionary word, untouched
    assert.is_true(C.unrecorded(WFJ, _G.GameTooltipTextLeft1))
    assert.are.equal("出品者: |cffffffffThrall|r", _G.GameTooltipTextLeft4:GetText())
    assert.are.equal("残り時間: |cffffffff2～12時間|r", _G.GameTooltipTextLeft5:GetText())
    C.alt(WFJ, true)
    assert.are.equal("Seller: |cffffffffThrall|r", _G.GameTooltipTextLeft4:GetText())
    C.alt(WFJ, false)
    tt:Hide()
    assert.are.equal("Seller: |cffffffffThrall|r", _G.GameTooltipTextLeft4:GetText()) -- released on hide
  end)

  it("cell tooltips: the row's time left and sellers, a bid cell's bidder with the name kept", function()
    local prefix = Stub.fontString(en("AUCTION_HOUSE_AUCTION_SOLD_PREFIX"))
    local row = { cells = { { Text = Stub.fontString("x"), Prefix = prefix },
      { Text = Stub.fontString("") } } }
    WFJ.AuctionHouse.onRow(row)
    assert.are.equal("|cff00ff00売却済: |r", row.cells[1].Prefix:GetText())
    C.tooltip(row, { en("AUCTION_HOUSE_TIME_LEFT_FORMAT_ACTIVE"):format("|cffffffff2 Hr|r") })
    assert.are.equal("残り: |cffffffff|cffffffff2 Hr|r|r", _G.GameTooltipTextLeft1:GetText())
    C.tooltip(row, { en("AUCTION_HOUSE_TOOLTIP_TIME_LEFT_LONG") })
    assert.are.equal("2～12時間", _G.GameTooltipTextLeft1:GetText())
    C.tooltip(row.cells[2], { en("AUCTION_HOUSE_HIGH_BIDDER_FORMAT"):format("Jaina") })
    assert.are.equal("最高入札者: |cffffffffJaina|r", _G.GameTooltipTextLeft1:GetText())
  end)

  it("tokenSell: the WHITE label in Japanese, the band too; a line that is not the label stays", function()
    local cell = { Text = Stub.fontString("") }
    function cell.ShowTooltip(self)
      local tt = _G.GameTooltip
      tt:SetOwner(self)
      tt:AddLine("|cffffffff" .. en("ESTIMATED_TIME_TO_SELL_LABEL") .. "|r" .. self.band)
      tt:Show()
    end
    WFJ.AuctionHouse.onRow({ cells = { cell } })
    _G.GameTooltip:ClearLines()
    cell.band = en("AUCTION_HOUSE_TOOLTIP_TIME_LEFT_LONG")
    cell:ShowTooltip()
    assert.are.equal("|cffffffff売却までの予想時間:|n|r2～12時間", _G.GameTooltipTextLeft1:GetText())
    C.alt(WFJ, true)
    assert.are.equal("|cffffffffEstimated Time To Sell:|n|r2-12 hr", _G.GameTooltipTextLeft1:GetText())
    C.alt(WFJ, false)
    _G.GameTooltip:ClearLines()
    cell.band = "Soonish" -- not a band entry: kept as written
    cell:ShowTooltip()
    assert.are.equal("|cffffffff売却までの予想時間:|n|rSoonish", _G.GameTooltipTextLeft1:GetText())
  end)

  it("the buy dialog's increases, the token buyout's wait and the balance tutorial line", function()
    local tt = _G.GameTooltip
    tt:SetOwner(frame.BuyDialog.Notification.Button)
    tt:AddDoubleLine(en("AUCTION_HOUSE_DIALOG_PER_UNIT_INCREASE"), "5g")
    tt:AddDoubleLine(en("AUCTION_HOUSE_DIALOG_TOTAL_INCREASE"), "50g")
    tt:Show()
    assert.are.equal("|cffffd100単価の上昇:|r", _G.GameTooltipTextLeft1:GetText())
    assert.are.equal("|cffffd100合計の上昇:|r", _G.GameTooltipTextLeft2:GetText())
    assert.are.equal("5g", _G.GameTooltipTextRight1:GetText())
    C.tooltip(frame.WoWTokenResults.Buyout, { en("TOKEN_TRY_AGAIN_LATER"):format("45 sec") })
    assert.are.equal("45秒待ってから再度お試しください。", _G.GameTooltipTextLeft1:GetText())
    local tutorial3 = frame.WoWTokenResults.GameTimeTutorial.LeftDisplay.Tutorial3
    tutorial3.text = en("TUTORIAL_TOKEN_GAME_TIME_STEP_2_BALANCE"):format("$20.00")
    WFJ.AuctionHouse.showAll()
    assert.are.equal("2. 30日間のゲームタイム|n(または$20.00のBlizzard Balance)と交換します。", tutorial3:GetText())
  end)
end)
