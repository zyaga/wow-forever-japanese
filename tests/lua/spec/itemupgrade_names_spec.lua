-- UI/ItemUpgrade: the item's name, ItemInfo.ItemName, written in its quality colour by ItemInfo:Setup and by
-- PlayUpgradedCelebration (mainline/blizzard_itemupgradeui.lua:646, 992). While names are on it shows the item's
-- Japanese with the colour code kept, after the client's Setup (which lays the panel out on the English, :1009).
local Stub = require("tests.lua.spec.wow_stub")
local C = require("tests.lua.spec.stub_commerce")

local UI = { ITEM_UPGRADE = { "Item Upgrade", "アイテム強化" } }

describe("UI/ItemUpgrade's item name", function()
  local WFJ, frame, name

  before_each(function()
    WFJ = C.fresh({ "UI/ItemUpgrade.lua" }, UI)
    frame = C.window("ItemUpgradeFrame")
    C.tree(frame, { ["ItemInfo.ItemName"] = "", ["ItemInfo.MissingItemText"] = "" })
    name = frame.ItemInfo.ItemName
    frame.upgradeInfo = { name = "Bandit Cloak", colour = "|cff0070dd" }
    function frame.ItemInfo.Setup(self, info) -- ItemUpgradeItemInfoMixin:Setup (lua:981–1010)
      if info then self.ItemName:SetText(info.colour .. info.name .. "|r") end
    end
    function frame.PlayUpgradedCelebration(self) -- lua:642–646: the upgraded quality's colour
      self.ItemInfo.ItemName:SetText("|cffa335ee" .. self.upgradeInfo.name .. "|r")
    end
    Stub.loadedAddons.Blizzard_ItemUpgradeUI = true
    WFJ.Data.add("name", { [WFJ.Names.key("Bandit Cloak")] = "バンディット・クローク\tばんでぃっと・くろーく" })
    WFJ.State.setNames(true)
    assert.is_true(WFJ.ItemUpgrade.init())
    frame:Show()
  end)

  after_each(function() C.teardown({ "ItemUpgradeFrame" }) end)

  it("shows the item's Japanese in its colour after Setup and after the celebration", function()
    frame.ItemInfo:Setup(frame.upgradeInfo)
    assert.are.equal("|cff0070ddバンディット・クローク|r", name:GetText())
    C.alt(WFJ, true)
    assert.are.equal("|cff0070ddBandit Cloak|r", name:GetText())
    C.alt(WFJ, false)
    frame:PlayUpgradedCelebration()
    assert.are.equal("|cffa335eeバンディット・クローク|r", name:GetText())
    frame:Hide()
    assert.are.equal("|cffa335eeBandit Cloak|r", name:GetText())
  end)

  it("an item with no Japanese, and names off, leave the client's text", function()
    frame.ItemInfo:Setup({ name = "Nobody Known Sword", colour = "|cff0070dd" })
    assert.are.equal("|cff0070ddNobody Known Sword|r", name:GetText())
    WFJ.State.setNames(false)
    frame.ItemInfo:Setup(frame.upgradeInfo)
    assert.are.equal("|cff0070ddBandit Cloak|r", name:GetText())
    assert.are.equal(0, name.calls.addonSetText)
  end)
end)
