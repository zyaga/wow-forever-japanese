-- UI/BlackMarket: the hot item's Name (BlackMarketFrame_UpdateHotItem, blizzard_blackmarketui.lua:170–173) and each
-- pooled row's Name (BlackMarketItemMixin:Init, :70–74) hold an item's name. While names are on each shows the item's
-- Japanese; sellers and item types are unchanged.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/BlackMarket.lua"

local ADDON = "Blizzard_BlackMarketUI"
local fs = Stub.fontString

describe("UI/BlackMarket's item names", function()
  local WFJ, frame, hot

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  local function newRow()
    local row = CreateFrame("Button")
    row.Name, row.Seller, row.Type = fs(""), fs(""), fs("")
    return row
  end
  local function initRow(row, data) -- the client writes the row (BlackMarketItemMixin:Init)
    row.Name:SetText(data.name)
    row.Seller:SetText(data.seller)
    row.Type:SetText(data.type)
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, {})
    frame = CreateFrame("Frame", "BlackMarketFrame")
    frame.HotDeal = CreateFrame("Frame")
    frame.HotDeal.Name, frame.HotDeal.Seller = fs(""), fs("")
    frame.ScrollBox = Stub.scrollBox()
    hot = {}
    _G.BlackMarketFrame_UpdateHotItem = function(self)
      self.HotDeal.Name:SetText(hot.name)
      self.HotDeal.Seller:SetText(hot.seller)
    end
    Stub.loadedAddons[ADDON] = true
    WFJ.Data.add("name", {
      [WFJ.Names.key("Thunderfury")] = "サンダーフューリー\tさんだーふゅーりー",
      [WFJ.Names.key("Linen Cloth")] = "リネン・クロス\tりねん・くろす",
    })
    WFJ.State.setNames(true)
    assert.is_true(WFJ.BlackMarket.init())
    frame:Show()
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    _G.BlackMarketFrame, _G.BlackMarketFrame_UpdateHotItem = nil, nil
  end)

  it("the hot item's name shows its Japanese; the reveal key and closing give the English back", function()
    hot.name, hot.seller = "Thunderfury", "Linen Cloth" -- a seller who shares an item's name
    _G.BlackMarketFrame_UpdateHotItem(frame)
    assert.are.equal("サンダーフューリー", frame.HotDeal.Name:GetText())
    assert.are.equal("Linen Cloth", frame.HotDeal.Seller:GetText())
    alt(true)
    assert.are.equal("Thunderfury", frame.HotDeal.Name:GetText())
    alt(false)
    assert.are.equal("サンダーフューリー", frame.HotDeal.Name:GetText())
    frame:Hide()
    assert.are.equal("Thunderfury", frame.HotDeal.Name:GetText())
  end)

  it("a pooled row shows its item's Japanese, and a reused row its new item's", function()
    local row = newRow()
    frame.ScrollBox:initFrame(row, { name = "Thunderfury", seller = "Linen Cloth", type = "Weapon" }, initRow)
    assert.are.equal("サンダーフューリー", row.Name:GetText())
    assert.are.equal("Linen Cloth", row.Seller:GetText())
    frame.ScrollBox:initFrame(row, { name = "Linen Cloth", seller = "Goya", type = "Cloth" }, initRow)
    assert.are.equal("リネン・クロス", row.Name:GetText())
    alt(true)
    assert.are.equal("Linen Cloth", row.Name:GetText())
    alt(false)
    frame.ScrollBox:initFrame(row, { name = "Nobody Known Sword", seller = "Goya", type = "Weapon" }, initRow)
    assert.are.equal("Nobody Known Sword", row.Name:GetText())
  end)

  it("with names off nothing is written", function()
    WFJ.State.setNames(false)
    hot.name, hot.seller = "Thunderfury", "Goya"
    _G.BlackMarketFrame_UpdateHotItem(frame)
    local row = newRow()
    frame.ScrollBox:initFrame(row, { name = "Linen Cloth", seller = "Goya", type = "Cloth" }, initRow)
    assert.are.equal("Thunderfury", frame.HotDeal.Name:GetText())
    assert.are.equal("Linen Cloth", row.Name:GetText())
    assert.are.equal(0, frame.HotDeal.Name.calls.addonSetText)
    assert.are.equal(0, row.Name.calls.addonSetText)
  end)
end)
