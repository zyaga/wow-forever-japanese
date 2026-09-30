-- The quest timers panel on the Forever (camelot) client: UI/QuestTimer.lua over a QuestTimerFrame
-- replayed from blizzard_questtimer/mainline/blizzard_questtimer.xml (Header: DialogHeaderTemplate, textString
-- QUEST_TIMERS) and blizzard_sharedxml/shared/dialog/dialogtemplates.lua (Setup → Text:SetText, UpdateWidth).
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/QuestTimer.lua"

local UI = { QUEST_TIMERS = { "Quest Timers", "クエストタイマー" }, SEARCH = { "Search", "検索" } }

describe("the quest timers panel on the Forever client", function()
  local WFJ, SS, widths

  local function install(shape)
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    SS = WFJ.SurfaceState
    H.uiSetup(WFJ, UI)
    widths = 0
    local frame = CreateFrame("Frame", "QuestTimerFrame")
    frame.Header = CreateFrame("Frame", nil, frame)
    frame.Header.Text = Stub.fontString(_G.QUEST_TIMERS)
    function frame.Header.UpdateWidth() widths = widths + 1 end
    frame.row = { Text = Stub.fontString("Search") } -- a timer row (never ours), holding a dictionary word
    if shape then shape(frame) end
    return WFJ.QuestTimer.init()
  end

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    _G.QuestTimerFrame = nil
  end)

  it("the header renders when the panel shows, the header is measured again, and hiding restores English", function()
    assert.is_true(install())
    local text = _G.QuestTimerFrame.Header.Text
    assert.are.equal("Quest Timers", text:GetText()) -- hidden: untouched
    _G.QuestTimerFrame:Show()
    assert.are.equal("クエストタイマー", text:GetText())
    assert.are.equal(WFJ.Font.PATH, (text:GetFont()))
    assert.is_true(widths >= 1)
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal("Quest Timers", text:GetText())
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    _G.QuestTimerFrame:Hide()
    assert.are.equal("Quest Timers", text:GetText())
    assert.are.equal(0, SS.count("questtimer"))
    assert.are.equal("Search", _G.QuestTimerFrame.row.Text:GetText()) -- a row is never walked
    assert.is_false(WFJ.QuestTimer.init()) -- once
  end)

  it("a header that holds anything else stays English, even a dictionary word", function()
    install(function(frame) frame.Header.Text.text = "Search" end)
    _G.QuestTimerFrame:Show()
    assert.are.equal("Search", _G.QuestTimerFrame.Header.Text:GetText())
  end)

  it("a panel already shown at init is rendered at once", function()
    install(function(frame) frame.shown = true end)
    assert.are.equal("クエストタイマー", _G.QuestTimerFrame.Header.Text:GetText())
  end)

  it("client names bound to the wrong type degrade to untouched English with no error", function()
    assert.has_no.errors(function()
      assert.is_false(install(function(frame) frame.Header.Text = "moved" end))
      _G.QuestTimerFrame:Show()
    end)
    assert.has_no.errors(function()
      assert.is_true(install(function(frame) frame.Header.UpdateWidth = "moved" end))
      _G.QuestTimerFrame:Show()
    end)
    assert.are.equal("クエストタイマー", _G.QuestTimerFrame.Header.Text:GetText())
  end)

  it("without the mainline header init returns false and touches nothing", function()
    assert.is_false(install(function(frame) frame.Header = nil end))
    _G.QuestTimerFrame = nil
    assert.is_false(WFJ.QuestTimer.init())
    assert.are.equal(0, SS.count("questtimer"))
  end)
end)
