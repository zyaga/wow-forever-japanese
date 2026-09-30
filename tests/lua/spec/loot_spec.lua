-- UI/Loot.lua over a LootFrame replayed from camelot
-- blizzard_uipanels_game/mainline/lootframe.lua (Open :233–262, LootFrameItemElementMixin:Init :621–626) and
-- scrollingflatpanel.lua:5–6 (SetTitle(panelTitle)).
local Stub = require("tests.lua.spec.wow_stub")
local G = require("tests.lua.spec.stub_gamepanels")

local FILES = G.files("UI/Loot.lua")
local UI = { ITEMS = { "Items", "アイテム" }, ITEM_QUALITY1_DESC = { "Common", "コモン" },
  ITEM_QUALITY3_DESC = { "Rare", "レア" } }

local function install()
  local frame = G.titled("LootFrame")
  frame.ScrollBox = Stub.scrollBox()
  frame:SetTitle(_G.ITEMS) -- ScrollingFlatPanelMixin:OnLoad
  return frame
end

-- LootFrameItemElementMixin:Init on a pooled row; a money row has no QualityText.
local function itemRow(name, quality)
  local row = { Text = Stub.fontString(""), QualityText = Stub.fontString("") }
  return row, function(r)
    r.Text.text = name
    r.QualityText.text = _G["ITEM_QUALITY" .. quality .. "_DESC"]
  end
end

describe("the loot window on Forever", function()
  local WFJ

  before_each(function() WFJ = G.load(FILES, UI) end)
  after_each(function() G.clear({ "LootFrame" }) end)

  it("the title renders Japanese after SetTitle, and keeps it after a second SetTitle", function()
    local frame = install()
    assert.is_true(WFJ.Loot.init())
    local title = frame.TitleContainer.TitleText
    assert.are.equal("アイテム", title:GetText())
    frame:SetTitle(_G.ITEMS)
    assert.are.equal("アイテム", title:GetText())
    frame:SetTitle("Rare") -- not this title's key
    assert.are.equal("Rare", title:GetText())
    frame:SetTitle(_G.ITEMS)
    G.alt(WFJ, true)
    assert.are.equal("Items", title:GetText())
  end)

  it("a row's quality word translates; the item's name never does; a reused row follows its new text", function()
    local frame = install()
    assert.is_true(WFJ.Loot.init())
    frame:Show()
    local row, init = itemRow("Rare", 3) -- an item whose name is also a dictionary word
    frame.ScrollBox:initFrame(row, { slotIndex = 1 }, init)
    assert.are.equal("レア", row.QualityText:GetText())
    assert.are.equal("Rare", row.Text:GetText())
    assert.is_true(G.unrecorded(WFJ, row.Text))
    local _, again = itemRow("Linen Cloth", 1)
    frame.ScrollBox:initFrame(row, { slotIndex = 2 }, again)
    assert.are.equal("コモン", row.QualityText:GetText())
    local money = { Text = Stub.fontString("12 Copper") }
    assert.has_no.errors(function() frame.ScrollBox:initFrame(money, { slotIndex = 3 }) end)
    assert.are.equal("12 Copper", money.Text:GetText())
    frame:Hide()
    assert.are.equal("Common", row.QualityText:GetText())
  end)

  it("rows laid out before init are picked up; wrong-typed names degrade without error", function()
    local frame = install()
    local row, init = itemRow("Linen Cloth", 1)
    frame.ScrollBox:initFrame(row, { slotIndex = 1 }, init)
    _G.ScrollUtil = 5
    assert.has_no.errors(function() assert.is_true(WFJ.Loot.init()) end)
    assert.are.equal("Common", row.QualityText:GetText()) -- no ScrollUtil: rows stay English
    assert.are.equal("アイテム", frame.TitleContainer.TitleText:GetText())
  end)

  it("no LootFrame, a wrong-typed one, or one without its ScrollBox: init is false", function()
    assert.has_no.errors(function() assert.is_false(WFJ.Loot.init()) end)
    _G.LootFrame = "x"
    assert.has_no.errors(function() assert.is_false(WFJ.Loot.init()) end)
    _G.LootFrame = nil
    local bare = G.titled("LootFrame", "Items")
    assert.is_false(WFJ.Loot.init())
    assert.are.equal("Items", bare.TitleContainer.TitleText:GetText())
  end)
end)
