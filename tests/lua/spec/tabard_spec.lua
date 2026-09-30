-- The tabard designer on Forever: UI/Tabard.lua over a TabardFrame replayed from camelot
-- blizzard_uipanels_game/mainline/tabardframe.lua (TabardFrame_Open :21–27, _UpdateButtons :90–106) and
-- tabardframe.xml.
local Stub = require("tests.lua.spec.wow_stub")
local G = require("tests.lua.spec.stub_gamepanels")

local FILES = G.files("UI/Tabard.lua")
local UI = {
  EMBLEM_SYMBOL = { "Icon", "アイコン" }, EMBLEM_SYMBOL_COLOR = { "Icon Color", "アイコンの色" },
  EMBLEM_BORDER = { "Border", "縁取り" }, EMBLEM_BORDER_COLOR = { "Border Color", "縁取りの色" },
  EMBLEM_BACKGROUND = { "Background", "背景" }, TABARDVENDORCOST = { "Cost:", "費用:" },
  ACCEPT = { "Accept", "承諾" }, CANCEL = { "Cancel", "キャンセル" },
  TABARDVENDORGREETING = { "Greetings! Choose the symbol and colors of your guild.",
    "ようこそ！ギルドのシンボルと色を選んでください。" },
  TABARDVENDORNOGUILDGREETING = { "You must be a guild master to purchase a tabard, but feel free to browse.",
    "タバードを購入できるのはギルドマスターだけですが、ご自由にご覧ください。" },
}
local NAMES = { "TabardFrame", "TabardFrameNameText", "TabardFrameGreetingText", "TabardFrameCostLabel",
  "TabardFrameAcceptButton", "TabardFrameCancelButton", "TabardFrame_UpdateButtons" }
local ROWS = { "EMBLEM_SYMBOL", "EMBLEM_SYMBOL_COLOR", "EMBLEM_BORDER", "EMBLEM_BORDER_COLOR", "EMBLEM_BACKGROUND" }

local T = {}

local function install()
  local frame = G.titled("TabardFrame")
  Stub.namedFontString("TabardFrameNameText", "Border") -- a designer NPC named like a dictionary word
  Stub.namedFontString("TabardFrameGreetingText", _G.TABARDVENDORGREETING)
  Stub.namedFontString("TabardFrameCostLabel", _G.TABARDVENDORCOST)
  Stub.button("TabardFrameAcceptButton", _G.ACCEPT)
  Stub.button("TabardFrameCancelButton", _G.CANCEL)
  for i, key in ipairs(ROWS) do
    Stub.namedFontString("TabardFrameCustomization" .. i .. "Text", _G[key])
    NAMES[#NAMES + 1] = "TabardFrameCustomization" .. i .. "Text"
  end
  _G.TabardFrame_UpdateButtons = function()
    _G.TabardFrameGreetingText.text = T.guildMaster and _G.TABARDVENDORGREETING or _G.TABARDVENDORNOGUILDGREETING
  end
  return frame
end

describe("the tabard designer on Forever", function()
  local WFJ

  before_each(function()
    WFJ = G.load(FILES, UI)
    T.guildMaster = true
  end)
  after_each(function() G.clear(NAMES) end)

  it("labels and the greeting translate; the greeting follows its writer; the NPC's name stays English", function()
    local frame = install()
    WFJ.Labels.forbidNames(WFJ.Tabard.NEVER_TOUCH)
    assert.is_true(WFJ.Tabard.init())
    frame:Show()
    assert.are.equal("アイコン", _G.TabardFrameCustomization1Text:GetText())
    assert.are.equal("縁取りの色", _G.TabardFrameCustomization4Text:GetText())
    assert.are.equal("費用:", _G.TabardFrameCostLabel:GetText())
    assert.are.equal("承諾", _G.TabardFrameAcceptButton:GetText())
    assert.are.equal(UI.TABARDVENDORGREETING[2], _G.TabardFrameGreetingText:GetText())
    assert.are.equal("Border", _G.TabardFrameNameText:GetText())
    assert.is_true(G.unrecorded(WFJ, _G.TabardFrameNameText))
    T.guildMaster = false
    _G.TabardFrame_UpdateButtons()
    assert.are.equal(UI.TABARDVENDORNOGUILDGREETING[2], _G.TabardFrameGreetingText:GetText())
    G.alt(WFJ, true)
    assert.are.equal(UI.TABARDVENDORNOGUILDGREETING[1], _G.TabardFrameGreetingText:GetText())
    G.alt(WFJ, false)
    frame:Hide()
    assert.are.equal("Accept", _G.TabardFrameAcceptButton:GetText())
  end)

  it("wrong-typed names degrade without error; hooks install once", function()
    local frame = install()
    _G.TabardFrameCostLabel = 1
    _G.TabardFrameCustomization2Text = "x"
    _G.TabardFrame_UpdateButtons = "y"
    assert.has_no.errors(function() assert.is_true(WFJ.Tabard.init()) end)
    assert.has_no.errors(function() frame:Show() end)
    assert.are.equal("アイコン", _G.TabardFrameCustomization1Text:GetText())
    assert.is_false(WFJ.Tabard.init())
  end)

  it("no TabardFrame: init is false and nothing is touched", function()
    assert.has_no.errors(function() assert.is_false(WFJ.Tabard.init()) end)
    assert.is_nil(Stub.hooks["TabardFrame_UpdateButtons"])
  end)
end)
