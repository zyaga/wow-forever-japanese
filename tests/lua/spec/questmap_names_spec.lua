-- UI/QuestMap: the item names on the quest log details pane's reward buttons (MapQuestInfoRewardsFrame.RewardButtons,
-- each Name written by QuestInfo_ShowRewards in map view, often from the item-load callback after the redraw returned,
-- mainline/questinfo.lua:516–556, 1051). While names are on each shows the item's Japanese.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local QStub = require("tests.lua.spec.stub_questmap")

local FILES = {}
for _, f in ipairs(H.UI_FILES) do FILES[#FILES + 1] = f end
FILES[#FILES + 1] = "UI/QuestFrame.lua"
FILES[#FILES + 1] = "UI/QuestMap.lua"

describe("UI/QuestMap's reward item names", function()
  local WFJ, Q, buttons

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI()
    Q = QStub.install()
    Q.quests[5] = { title = "Wolf Pelts", description = "Wolves.", objectives = "Collect.", level = 10 }
    buttons = {}
    for i = 1, 3 do
      local b = CreateFrame("Button", nil, _G.MapQuestInfoRewardsFrame)
      b.Name = Stub.fontString("")
      buttons[i] = b
    end
    _G.MapQuestInfoRewardsFrame.RewardButtons = buttons
    Q.rewardNames = {}
    -- the map's rewards call writes the buttons as QuestInfo_ShowRewards does ("" = shown, its item not loaded yet)
    local display = _G.QuestInfo_Display
    _G.QuestInfo_Display = function(template, parentFrame, ...)
      display(template, parentFrame, ...)
      if template ~= _G.QUEST_TEMPLATE_MAP_REWARDS then return end
      for i, b in ipairs(buttons) do
        local name = Q.rewardNames[i]
        if name then
          b:Show()
          if name ~= "" then b.Name:SetText(name) end
        else
          b:Hide()
        end
      end
    end
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, {})
    WFJ.Data.add("name", {
      [WFJ.Names.key("Bottle of Dalaran Noir")] = "ボトル・オブ・ダララン・ノワール\tぼとる・おぶ・だららん・のわーる",
      [WFJ.Names.key("Linen Cloth")] = "リネン・クロス\tりねん・くろす",
    })
    WFJ.State.setNames(true)
    assert.is_true(WFJ.QuestFrame.init())
    assert.is_true(WFJ.QuestMap.init())
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
  end)

  it("the reward buttons show their items' Japanese; the reveal key and closing the pane give the English back",
  function()
    Q.rewardNames = { "Bottle of Dalaran Noir", "Linen Cloth" }
    Q.showDetails(5)
    assert.are.equal("ボトル・オブ・ダララン・ノワール", buttons[1].Name:GetText())
    assert.are.equal("リネン・クロス", buttons[2].Name:GetText())
    alt(true)
    assert.are.equal("Bottle of Dalaran Noir", buttons[1].Name:GetText())
    alt(false)
    assert.are.equal("ボトル・オブ・ダララン・ノワール", buttons[1].Name:GetText())
    Q.closeDetails()
    assert.are.equal("Bottle of Dalaran Noir", buttons[1].Name:GetText())
    assert.are.equal("Linen Cloth", buttons[2].Name:GetText())
  end)

  it("a name the client writes after the redraw (the item's data arriving) shows its Japanese", function()
    Q.rewardNames = { "" }
    Q.showDetails(5)
    assert.are.equal("", buttons[1].Name:GetText())
    buttons[1].Name:SetText("Linen Cloth") -- the item-load callback
    assert.are.equal("リネン・クロス", buttons[1].Name:GetText())
    alt(true)
    assert.are.equal("Linen Cloth", buttons[1].Name:GetText())
    alt(false)
    assert.are.equal("リネン・クロス", buttons[1].Name:GetText())
  end)

  it("another quest's rewards replace the names", function()
    Q.rewardNames = { "Linen Cloth" }
    Q.showDetails(5)
    Q.rewardNames = { "Bottle of Dalaran Noir" }
    Q.showDetails(5)
    assert.are.equal("ボトル・オブ・ダララン・ノワール", buttons[1].Name:GetText())
    alt(true)
    assert.are.equal("Bottle of Dalaran Noir", buttons[1].Name:GetText())
  end)

  it("a name with no Japanese, a hidden button and names off are never written", function()
    Q.rewardNames = { "Nobody Known Sword" }
    Q.showDetails(5)
    assert.are.equal("Nobody Known Sword", buttons[1].Name:GetText())
    assert.are.equal(0, buttons[1].Name.calls.addonSetText)
    assert.are.equal(0, buttons[2].Name.calls.addonSetText)
    WFJ.State.setNames(false)
    Q.rewardNames = { "Linen Cloth" }
    Q.showDetails(5)
    assert.are.equal("Linen Cloth", buttons[1].Name:GetText())
    assert.are.equal(0, buttons[1].Name.calls.addonSetText)
  end)

  it("the quest window's reward buttons are not the pane's", function()
    Q.rewardNames = { "Linen Cloth" }
    Q.showDetails(5)
    _G.QuestFrame:Show()
    _G.QuestFrame:Hide() -- the quest window's release
    assert.are.equal("リネン・クロス", buttons[1].Name:GetText())
  end)
end)
