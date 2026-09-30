-- Labels shown at load are Japanese before a window's first show, so a tab's OnShow resize measures
-- the Japanese; a selected / deselected / disabled tab keeps the bundled font after the client swaps font objects.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local UI = { CHARACTER = { "Character", "キャラクター" }, REPUTATION = { "Reputation", "評判" } }

describe("static labels and tab fonts", function()
  local WFJ, tab1, tab2, frame

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI()
    WFJ = H.loadChunks(H.UI_FILES)
    frame = CreateFrame("Frame", "TestPanel")
    tab1, tab2 = Stub.tab("TestPanelTab1", "Character"), Stub.tab("TestPanelTab2", "Reputation")
    frame.tabs = { tab1, tab2 }
    H.uiSetup(WFJ, UI)
    WFJ.Labels.showAll("test.static", { { "tab1", tab1 }, { "tab2", tab2 } })
  end)

  after_each(H.uiTeardown)

  it("a tab shown after load is measured with its Japanese text", function()
    assert.are.equal("キャラクター", tab1:GetText())
    tab1:Show()
    assert.are.equal("キャラクター", tab1.measured)
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal("Character", tab1:GetText())
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    assert.are.equal("キャラクター", tab1:GetText())
  end)

  it("PanelTemplates_SelectTab / DeselectTab / UpdateTabs keep the bundled font on translated tabs", function()
    assert.are.equal(WFJ.Font.PATH, (tab1:GetFontString():GetFont()))
    _G.PanelTemplates_SelectTab(tab1)
    assert.are.equal(WFJ.Font.PATH, (tab1:GetFontString():GetFont()))
    _G.PanelTemplates_DeselectTab(tab1)
    assert.are.equal(WFJ.Font.PATH, (tab1:GetFontString():GetFont()))
    frame.selectedTab = 2
    _G.PanelTemplates_UpdateTabs(frame)
    assert.are.equal(WFJ.Font.PATH, (tab2:GetFontString():GetFont()))
    _G.PanelTemplates_SetDisabledTabState(tab2)
    assert.are.equal(WFJ.Font.PATH, (tab2:GetFontString():GetFont()))
  end)

  it("a tab showing English (modifier held) is left in the client's font", function()
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    _G.PanelTemplates_SelectTab(tab1)
    assert.are.equal(Stub.TAB_FONT, (tab1:GetFontString():GetFont()))
    local other = Stub.tab("OtherTab", "Unknown")
    _G.PanelTemplates_SelectTab(other)
    assert.are.equal(Stub.TAB_FONT, (other:GetFontString():GetFont()))
  end)
end)
