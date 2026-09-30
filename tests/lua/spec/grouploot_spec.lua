-- UI/GroupLoot.lua over GroupLootFrame1–4 and MasterLooterFrame replayed
-- from camelot blizzard_uipanels_game/mainline/grouplootframe.xml (LootRollButtonTemplate :3–22, :482–548) and
-- grouplootframe.lua (:335–353 reasons, :851–852 master looter title).
local Stub = require("tests.lua.spec.wow_stub")
local G = require("tests.lua.spec.stub_gamepanels")

local FILES = G.files("UI/GroupLoot.lua")
local UI = { NEED = { "Need", "ニード" }, GREED = { "Greed", "グリード" }, PASS = { "Pass", "パス" },
  TRANSMOGRIFICATION = { "Transmogrification", "トランスモグ" },
  LOOT_ROLL_INELIGIBLE_REASON1 = { "Your class may not roll need on this item.",
    "あなたのクラスはこのアイテムにニードできません。" },
  ASSIGN_LOOT = { "Assign Loot", "ルートの割り当て" } }
local NAMES = { "GroupLootFrame1", "GroupLootFrame2", "GroupLootFrame3", "GroupLootFrame4", "MasterLooterFrame" }

local function install()
  for i = 1, 4 do
    local frame = CreateFrame("Frame", "GroupLootFrame" .. i)
    frame.Name = Stub.fontString("Need") -- an item called "Need"
    frame.LootButtonContainer = {}
    for _, b in ipairs({ "NeedButton", "PassButton", "GreedButton", "TransmogButton" }) do
      frame.LootButtonContainer[b] = CreateFrame("Button")
    end
  end
  local master = G.titled("MasterLooterFrame", _G.ASSIGN_LOOT) -- MasterLooterFrame_OnLoad
  master.Item = { ItemName = Stub.fontString("Assign Loot") }
  return master
end

describe("group loot on Forever", function()
  local WFJ

  before_each(function() WFJ = G.load(FILES, UI) end)
  after_each(function() G.clear(NAMES) end)

  it("the roll buttons' tooltips translate, with the ineligible reason; the item's name stays English", function()
    install()
    WFJ.Labels.forbidNames(WFJ.GroupLoot.NEVER_TOUCH)
    assert.is_true(WFJ.GroupLoot.init())
    assert.are.equal(16, WFJ.GroupLoot.registered())
    local need = _G.GroupLootFrame2.LootButtonContainer.NeedButton
    G.tooltip(need, { "Need", UI.LOOT_ROLL_INELIGIBLE_REASON1[1] })
    assert.are.equal("ニード", G.line(1))
    assert.are.equal(UI.LOOT_ROLL_INELIGIBLE_REASON1[2], G.line(2))
    G.tooltip(_G.GroupLootFrame1.LootButtonContainer.PassButton, { "Pass" })
    assert.are.equal("パス", G.line(1))
    G.alt(WFJ, true)
    assert.are.equal("Pass", G.line(1))
    G.alt(WFJ, false)
    assert.are.equal("Need", _G.GroupLootFrame2.Name:GetText())
    assert.is_true(G.unrecorded(WFJ, _G.GroupLootFrame2.Name))
  end)

  it("the master looter's title renders Japanese and keeps it after a second SetTitle; the item name does not",
    function()
      local master = install()
      WFJ.Labels.forbidNames(WFJ.GroupLoot.NEVER_TOUCH)
      assert.is_true(WFJ.GroupLoot.init())
      master:Show()
      assert.are.equal("ルートの割り当て", master.TitleContainer.TitleText:GetText())
      master:SetTitle(_G.ASSIGN_LOOT)
      assert.are.equal("ルートの割り当て", master.TitleContainer.TitleText:GetText())
      assert.are.equal("Assign Loot", master.Item.ItemName:GetText())
      master:Hide()
      assert.are.equal("Assign Loot", master.TitleContainer.TitleText:GetText())
    end)

  it("wrong-typed names degrade without error", function()
    install()
    _G.GroupLootFrame1 = 9
    _G.GroupLootFrame2.LootButtonContainer = "x"
    _G.GroupLootFrame3.LootButtonContainer.NeedButton = false
    _G.MasterLooterFrame = 1
    assert.has_no.errors(function() assert.is_true(WFJ.GroupLoot.init()) end)
    assert.are.equal(7, WFJ.GroupLoot.registered())
    assert.is_false(WFJ.GroupLoot.init())
  end)

  it("no roll frames, or ones without a LootButtonContainer: init is false", function()
    assert.has_no.errors(function() assert.is_false(WFJ.GroupLoot.init()) end)
    local bare = CreateFrame("Frame", "GroupLootFrame1")
    bare.NeedButton = CreateFrame("Button")
    assert.is_false(WFJ.GroupLoot.init())
    assert.is_false(WFJ.HelpTooltip.registered(bare.NeedButton))
  end)
end)
