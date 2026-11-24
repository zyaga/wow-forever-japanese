-- UI/GroupLoot: a roll frame's Name (GroupLootFrame_SetupItemDisplay, mainline/grouplootframe.lua:312–324, called by
-- name from GroupLootFrame_OnShow, :371–372) and MasterLooterFrame.Item.ItemName (MasterLooterFrame_Show, :882–884)
-- hold an item's name. While names are on each shows the item's Japanese.
local Stub = require("tests.lua.spec.wow_stub")
local G = require("tests.lua.spec.stub_gamepanels")

local FILES = G.files("UI/GroupLoot.lua")
local NAMES = { "GroupLootFrame1", "GroupLootFrame2", "GroupLootFrame3", "GroupLootFrame4", "MasterLooterFrame",
  "GroupLootFrame_SetupItemDisplay", "MasterLooterFrame_Show" }

describe("UI/GroupLoot's item names", function()
  local WFJ, rolls, master

  local function install()
    rolls = {}
    for i = 1, 4 do
      local frame = CreateFrame("Frame", "GroupLootFrame" .. i)
      frame.Name = Stub.fontString("")
      frame.LootButtonContainer = { NeedButton = CreateFrame("Button") }
      frame:Hide()
    end
    _G.GroupLootFrame_SetupItemDisplay = function(self)
      if not rolls[self] then return false end
      self.Name:SetText(rolls[self])
      return true
    end
    master = G.titled("MasterLooterFrame", "Assign Loot")
    master.Item = { ItemName = Stub.fontString("") }
    master:Hide()
    _G.MasterLooterFrame_Show = function(name)
      master.Item.ItemName:SetText(name)
      master:Show()
    end
  end

  -- GroupLootFrame_OnShow (an XML function= script) calls the writer by name
  local function roll(i, name)
    local frame = _G["GroupLootFrame" .. i]
    rolls[frame] = name
    frame:Show()
    _G.GroupLootFrame_SetupItemDisplay(frame)
    return frame
  end

  before_each(function()
    WFJ = G.load(FILES, {})
    install()
    WFJ.Data.add("name", {
      [WFJ.Names.key("Thunderfury")] = "サンダーフューリー\tさんだーふゅーりー",
      [WFJ.Names.key("Linen Cloth")] = "リネン・クロス\tりねん・くろす",
    })
    WFJ.State.setNames(true)
    WFJ.Labels.forbidNames(WFJ.GroupLoot.NEVER_TOUCH)
    assert.is_true(WFJ.GroupLoot.init())
  end)

  after_each(function()
    G.alt(WFJ, false)
    G.clear(NAMES)
  end)

  it("a roll frame's item shows its Japanese; the reveal key and the frame closing give the English back", function()
    local one = roll(1, "Thunderfury")
    local two = roll(2, "Linen Cloth")
    assert.are.equal("サンダーフューリー", one.Name:GetText())
    assert.are.equal("リネン・クロス", two.Name:GetText())
    G.alt(WFJ, true)
    assert.are.equal("Thunderfury", one.Name:GetText())
    G.alt(WFJ, false)
    one:Hide()
    assert.are.equal("Thunderfury", one.Name:GetText())
    assert.are.equal("リネン・クロス", two.Name:GetText()) -- another roll is still open
  end)

  it("a roll frame reused for another item shows the new item's Japanese", function()
    local one = roll(1, "Thunderfury")
    one:Hide()
    roll(1, "Linen Cloth")
    assert.are.equal("リネン・クロス", one.Name:GetText())
  end)

  it("the master looter's item shows its Japanese, after each show; closing gives the English back", function()
    _G.MasterLooterFrame_Show("Thunderfury")
    assert.are.equal("サンダーフューリー", master.Item.ItemName:GetText())
    _G.MasterLooterFrame_Show("Linen Cloth") -- another item while the window is open
    assert.are.equal("リネン・クロス", master.Item.ItemName:GetText())
    G.alt(WFJ, true)
    assert.are.equal("Linen Cloth", master.Item.ItemName:GetText())
    G.alt(WFJ, false)
    master:Hide()
    assert.are.equal("Linen Cloth", master.Item.ItemName:GetText())
  end)

  it("an item with no Japanese and names off are never written", function()
    local one = roll(1, "Nobody Known Sword")
    assert.are.equal(0, one.Name.calls.addonSetText)
    WFJ.State.setNames(false)
    local two = roll(2, "Linen Cloth")
    _G.MasterLooterFrame_Show("Thunderfury")
    assert.are.equal("Linen Cloth", two.Name:GetText())
    assert.are.equal(0, two.Name.calls.addonSetText)
    assert.are.equal(0, master.Item.ItemName.calls.addonSetText)
  end)
end)
