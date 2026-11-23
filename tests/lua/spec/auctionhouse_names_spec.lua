-- UI/AuctionHouse: item names. Each is the item's name in its quality colour, "|cffxxxxxx<name>|r", sometimes with
-- " (<item level>)" inside the colour and a count or a quality icon after it: the item displays' Name
-- (shared/blizzard_auctionhousesharedtemplates.lua:232, 306–314), the result rows' item cell
-- (tablebuilder.lua:702–713, 749–757), the summary lines (auctionsframe.lua:75) and the buy dialog's
-- AUCTION_HOUSE_DIALOG_ITEM_FORMAT "%s  x%s" around it (buydialog.lua:249–255). While names are on each shows the
-- item's Japanese with everything else kept byte for byte.
local Stub = require("tests.lua.spec.wow_stub")
local C = require("tests.lua.spec.stub_commerce")

local ADDON = "Blizzard_AuctionHouseUI"
local UI = { AUCTION_HOUSE_ALL_AUCTIONS = { "All Auctions", "すべてのオークション" } }
local DISPLAYS = { "ItemBuyFrame.ItemDisplay", "ItemSellFrame.ItemDisplay", "CommoditiesSellFrame.ItemDisplay",
  "CommoditiesBuyFrame.BuyDisplay.ItemDisplay", "AuctionsFrame.ItemDisplay" }

-- an item display: SetItemInternal writes the coloured name (:306–314), SetItemKey writes it again after it (:230–232)
local function itemDisplay()
  local d = CreateFrame("Button")
  d.Name = Stub.fontString("")
  function d.SetItemInternal(self, item) self.Name:SetText(item and item.text or "") end
  function d.SetItemKey(self, item)
    self:SetItemInternal(item)
    self.Name:SetText(item.keyText or item.text)
  end
  return d
end

-- a result row's item cell (AuctionHouseTableCellItemDisplayTemplate, tablebuilder.xml:124–166)
local function itemCell()
  local cell = CreateFrame("Frame")
  cell.Text, cell.ExtraInfo = Stub.fontString(""), Stub.fontString("")
  cell.measured = {}
  function cell.UpdateDisplay(self, text) -- :702–724: write, then measure for truncation
    self.Text:SetText(text)
    self.measured[#self.measured + 1] = self.Text:GetText()
  end
  return cell
end

describe("UI/AuctionHouse's item names", function()
  local WFJ, frame, list

  before_each(function()
    WFJ = C.fresh({ "UI/AuctionHouse.lua" }, UI)
    frame = C.window("AuctionHouseFrame")
    for _, path in ipairs(DISPLAYS) do C.set(frame, path, itemDisplay()) end
    C.tree(frame, { ["BuyDialog.ItemDisplay.ItemText"] = "", ["AuctionsFrame.SummaryList"] = { frame = true } })
    function frame.BuyDialog.SetItemID(self, text, quantity) -- :241–260
      self.ItemDisplay.ItemText:SetText(string.format("%s  x%s", text, quantity))
    end
    frame.AuctionsFrame.SummaryList.ScrollBox = Stub.scrollBox()
    list = CreateFrame("Frame")
    list.ScrollBox = Stub.scrollBox()
    frame.BrowseResultsFrame = { ItemList = list }
    Stub.loadedAddons[ADDON] = true
    WFJ.Data.add("name", {
      [WFJ.Names.key("Thunderfury")] = "サンダーフューリー\tさんだーふゅーりー",
      [WFJ.Names.key("Linen Cloth")] = "リネン・クロス\tりねん・くろす",
    })
    WFJ.State.setNames(true)
    WFJ.AuctionHouse.init()
    frame:Show()
  end)

  after_each(function() C.teardown({ "AuctionHouseFrame" }) end)

  it("the five item displays show the item's Japanese in its colour, the item level kept", function()
    for _, path in ipairs(DISPLAYS) do
      local d = C.at(frame, path)
      d:SetItemInternal({ text = "|cffa335eeThunderfury (29)|r" })
      assert.are.equal("|cffa335eeサンダーフューリー (29)|r", d.Name:GetText())
      d:SetItemKey({ text = "|cffffffffLinen Cloth|r" })
      assert.are.equal("|cffffffffリネン・クロス|r", d.Name:GetText())
    end
    local name = C.at(frame, DISPLAYS[1]).Name
    C.alt(WFJ, true)
    assert.are.equal("|cffffffffLinen Cloth|r", name:GetText())
    C.alt(WFJ, false)
    assert.are.equal("|cffffffffリネン・クロス|r", name:GetText())
    frame:Hide()
    assert.are.equal("|cffffffffLinen Cloth|r", name:GetText())
  end)

  it("the buy dialog's item line keeps its count", function()
    frame.BuyDialog:SetItemID("|cffffffffLinen Cloth|r", 20)
    assert.are.equal("|cffffffffリネン・クロス|r  x20", frame.BuyDialog.ItemDisplay.ItemText:GetText())
  end)

  it("a result row's item cell shows the Japanese after the client measured its English, icon and count kept",
    function()
      local cell = itemCell()
      local row = { cells = { cell } }
      list.ScrollBox:initFrame(row, {}, function(r) r.cells[1]:UpdateDisplay(
        "|cffa335eeThunderfury (29)|r |cff808080x2|r |A:Professions-ChatIcon-Quality-Tier3:17:15:1:0|a") end)
      assert.are.equal("|cffa335eeサンダーフューリー (29)|r |cff808080x2|r "
        .. "|A:Professions-ChatIcon-Quality-Tier3:17:15:1:0|a", cell.Text:GetText())
      cell:UpdateDisplay("|cffffffffLinen Cloth|r") -- the item's data arrived later (ITEM_KEY_ITEM_INFO_RECEIVED)
      assert.are.equal("|cffffffffリネン・クロス|r", cell.Text:GetText())
      assert.are.same({ "|cffa335eeThunderfury (29)|r |cff808080x2|r "
        .. "|A:Professions-ChatIcon-Quality-Tier3:17:15:1:0|a", "|cffffffffLinen Cloth|r" }, cell.measured)
    end)

  it("a summary line shows its item's Japanese; the all-auctions line stays a dictionary word", function()
    local box = frame.AuctionsFrame.SummaryList.ScrollBox
    local all, item = { Text = Stub.fontString("") }, { Text = Stub.fontString("") }
    box:initFrame(all, {}, function(line) line.Text.text = _G.AUCTION_HOUSE_ALL_AUCTIONS end)
    box:initFrame(item, {}, function(line) line.Text.text = "|cff1eff00Linen Cloth|r" end)
    assert.are.equal("すべてのオークション", all.Text:GetText())
    assert.are.equal("|cff1eff00リネン・クロス|r", item.Text:GetText())
  end)

  it("an item with no Japanese, and names off, leave the client's text", function()
    local d = C.at(frame, DISPLAYS[1])
    d:SetItemInternal({ text = "|cffa335eeNobody Known Sword|r" })
    assert.are.equal("|cffa335eeNobody Known Sword|r", d.Name:GetText())
    WFJ.State.setNames(false)
    d:SetItemInternal({ text = "|cffa335eeThunderfury|r" })
    frame.BuyDialog:SetItemID("|cffffffffLinen Cloth|r", 20)
    assert.are.equal("|cffa335eeThunderfury|r", d.Name:GetText())
    assert.are.equal(0, d.Name.calls.addonSetText)
    assert.are.equal(0, frame.BuyDialog.ItemDisplay.ItemText.calls.addonSetText)
  end)
end)
