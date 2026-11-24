-- UI/QuestFrame: the item names on the quest window's reward and choice buttons (QuestInfoRewardsFrame.RewardButtons,
-- each Name written by QuestInfo_ShowRewards, often from the item-load callback after the redraw returned,
-- mainline/questinfo.lua:516–556) and on the progress panel's required items (QuestProgressItem<i>Name, written by
-- QuestFrameProgressItems_Update, mainline/questframe.lua:230–300). While names are on each shows the item's Japanese.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/QuestFrame.lua"

describe("UI/QuestFrame's item names", function()
  local WFJ, buttons, required

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  -- QuestInfo_ShowRewards as the client runs it: each used button shown and named ("" = its item not loaded yet, so
  -- not named), the rest hidden.
  local function showRewards(names)
    for i, button in ipairs(buttons) do
      if names[i] then
        button:Show()
        if names[i] ~= "" then button.Name:SetText(names[i]) end
      else
        button:Hide()
      end
    end
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI()
    buttons = {}
    for i = 1, 3 do
      local b = CreateFrame("Button", nil, _G.QuestInfoRewardsFrame)
      b.Name = Stub.fontString("")
      buttons[i] = b
    end
    _G.QuestInfoRewardsFrame.RewardButtons = buttons
    Stub.quest.names = {}
    _G.QuestInfo_ShowRewards = function() showRewards(Stub.quest.names) end
    -- the reward panel's QuestInfo_Display reaches the rewards through the template's own reference
    local display = _G.QuestInfo_Display
    local rewardsElement = _G.QuestInfo_ShowRewards
    _G.QuestInfo_Display = function(template, parentFrame)
      display(template, parentFrame)
      if not template.questLog then rewardsElement() end
    end
    required = {}
    for i = 1, 6 do
      local b = CreateFrame("Button", "QuestProgressItem" .. i, _G.QuestFrameProgressPanel)
      b.Name = Stub.namedFontString("QuestProgressItem" .. i .. "Name", "")
      required[i] = b
    end
    Stub.quest.required = {}
    _G.QuestFrameProgressItems_Update = function()
      for i, b in ipairs(required) do
        local name = Stub.quest.required[i]
        if name then b:Show(); _G["QuestProgressItem" .. i .. "Name"]:SetText(name) else b:Hide() end
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
    _G.QuestFrame:Show()
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
  end)

  local function turnIn(names)
    Stub.quest.id = 2
    Stub.quest.names = names
    _G.QuestInfo_Display(_G.QUEST_TEMPLATE_REWARD, _G.QuestRewardScrollChildFrame)
  end

  it("the reward buttons show their items' Japanese; the reveal key and closing give the English back", function()
    turnIn({ "Bottle of Dalaran Noir", "Linen Cloth" })
    assert.are.equal("ボトル・オブ・ダララン・ノワール", buttons[1].Name:GetText())
    assert.are.equal("リネン・クロス", buttons[2].Name:GetText())
    alt(true)
    assert.are.equal("Bottle of Dalaran Noir", buttons[1].Name:GetText())
    alt(false)
    assert.are.equal("ボトル・オブ・ダララン・ノワール", buttons[1].Name:GetText())
    _G.QuestFrame:Hide()
    assert.are.equal("Bottle of Dalaran Noir", buttons[1].Name:GetText())
    assert.are.equal("Linen Cloth", buttons[2].Name:GetText())
  end)

  it("a name the client writes after the redraw (the item's data arriving) shows its Japanese", function()
    turnIn({ "", "" }) -- shown, not named yet
    assert.are.equal("", buttons[1].Name:GetText())
    buttons[1].Name:SetText("Bottle of Dalaran Noir") -- the item-load callback
    assert.are.equal("ボトル・オブ・ダララン・ノワール", buttons[1].Name:GetText())
    alt(true)
    assert.are.equal("Bottle of Dalaran Noir", buttons[1].Name:GetText())
    alt(false)
    assert.are.equal("ボトル・オブ・ダララン・ノワール", buttons[1].Name:GetText())
  end)

  it("a name written while the reveal key is held shows English, then Japanese on release", function()
    alt(true)
    turnIn({ "Linen Cloth" })
    assert.are.equal("Linen Cloth", buttons[1].Name:GetText())
    alt(false)
    assert.are.equal("リネン・クロス", buttons[1].Name:GetText())
    alt(true)
    assert.are.equal("Linen Cloth", buttons[1].Name:GetText())
  end)

  it("the redraw on QUEST_ITEM_UPDATE (QuestInfo_ShowRewards by name) shows the names again", function()
    turnIn({ "Linen Cloth" })
    Stub.quest.names = { "Bottle of Dalaran Noir" }
    _G.QuestInfo_ShowRewards()
    assert.are.equal("ボトル・オブ・ダララン・ノワール", buttons[1].Name:GetText())
  end)

  it("a name with no Japanese and a currency stay exactly as the client wrote them", function()
    turnIn({ "Nobody Known Sword", "Honor Points" })
    assert.are.equal("Nobody Known Sword", buttons[1].Name:GetText())
    assert.are.equal("Honor Points", buttons[2].Name:GetText())
    assert.are.equal(0, buttons[1].Name.calls.addonSetText)
    assert.are.equal(0, buttons[2].Name.calls.addonSetText)
  end)

  it("a button the client hid is never written", function()
    turnIn({ "Linen Cloth" })
    assert.are.equal(0, buttons[3].Name.calls.addonSetText)
  end)

  it("with names off nothing is written", function()
    WFJ.State.setNames(false)
    turnIn({ "Bottle of Dalaran Noir" })
    assert.are.equal("Bottle of Dalaran Noir", buttons[1].Name:GetText())
    assert.are.equal(0, buttons[1].Name.calls.addonSetText)
  end)

  it("the progress panel's required items show their Japanese after each update", function()
    Stub.quest.required = { "Linen Cloth", "Nobody Known Sword" }
    _G.QuestFrameProgressItems_Update()
    assert.are.equal("リネン・クロス", _G.QuestProgressItem1Name:GetText())
    assert.are.equal("Nobody Known Sword", _G.QuestProgressItem2Name:GetText())
    alt(true)
    assert.are.equal("Linen Cloth", _G.QuestProgressItem1Name:GetText())
    alt(false)
    _G.QuestFrame:Hide()
    assert.are.equal("Linen Cloth", _G.QuestProgressItem1Name:GetText())
  end)

  it("the quest log's details pane (MapQuestInfoRewardsFrame) is not this window's", function()
    local map = CreateFrame("Button", nil, _G.MapQuestInfoRewardsFrame)
    map.Name = Stub.fontString("Linen Cloth")
    map:Show()
    _G.MapQuestInfoRewardsFrame.RewardButtons = { map }
    _G.QuestInfo_Display(_G.QUEST_TEMPLATE_LOG, nil)
    assert.are.equal("Linen Cloth", map.Name:GetText())
    assert.are.equal(0, map.Name.calls.addonSetText)
  end)
end)
