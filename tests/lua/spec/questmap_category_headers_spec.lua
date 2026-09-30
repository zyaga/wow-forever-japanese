-- ADR-042: the quest list's category headers (QuestLogQuests_AddStandardHeaderButton → button:SetText(
-- info.title), mainline/questmapframe.lua:2044–2048; ListHeaderVisualTemplate's title region). A header is a zone name
-- or a QuestSort word ("Seasonal"); only the QuestSort family is matched, so a zone name is never changed, even one
-- another dictionary row happens to share.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local QStub = require("tests.lua.spec.stub_questmap")

local FILES = {}
for _, f in ipairs(H.UI_FILES) do FILES[#FILES + 1] = f end
FILES[#FILES + 1] = "Core/Objectives.lua"
FILES[#FILES + 1] = "UI/QuestFrame.lua"
FILES[#FILES + 1] = "UI/QuestMap.lua"

local UI = {
  ["QuestSort:22"] = { "Seasonal", "季節" },
  ["QuestSort:-24"] = { "Epic", "エピック" },
  ["AchievementCategory:14777"] = { "Elwynn Forest", "エルウィンの森(カテゴリ)" }, -- another family's row
  ZONE_WORD = { "Duskwood", "ダスクウッド" }, -- a dictionary word a zone header shares
}

describe("UI/QuestMap: the quest list's category headers", function()
  local WFJ, Q, headers

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  -- headerFramePool (questmapframe.lua:1229): pooled header buttons; the client wrote each one's title before
  -- QuestLogQuests_Update returns
  local function headerPool()
    local pool = { active = {} }
    function pool:EnumerateActive() return pairs(self.active) end
    return pool
  end
  local function header(title, plain)
    local button
    if plain then
      button = Stub.fontString(title) -- a header whose own text is the region (no GetTitleRegion)
    else
      button = CreateFrame("Button")
      button.title = Stub.fontString(title)
      function button.GetTitleRegion(self) return self.title end
    end
    headers.active[button] = true
    return button
  end
  local function text(button) return (button.title or button):GetText() end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI()
    Q = QStub.install()
    Q.quests[9] = { title = "Burning Archives", description = "Burn it.", objectives = "Burn the archive.", level = 20 }
    Q.log = { 9 }
    _G.EventRegistry = { RegisterCallback = function() end }
    headers = headerPool()
    _G.QuestScrollFrame.headerFramePool = headers
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    assert.is_true(WFJ.QuestFrame.init())
    assert.is_true(WFJ.QuestMap.init())
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    _G.EventRegistry = nil
  end)

  it("a QuestSort header is Japanese after the list update; Alt shows English", function()
    local seasonal, epic = header("Seasonal"), header("Epic", true)
    Q.updateList()
    assert.are.equal("季節", text(seasonal))
    assert.are.equal("エピック", text(epic))
    alt(true)
    assert.are.equal("Seasonal", text(seasonal))
    alt(false)
    assert.are.equal("季節", text(seasonal))
  end)

  it("a zone header is never changed, even when another family's row or a dictionary word has its English",
    function()
      local elwynn, duskwood, westfall = header("Elwynn Forest"), header("Duskwood"), header("Westfall")
      Q.updateList()
      assert.are.equal("Elwynn Forest", text(elwynn))
      assert.are.equal("Duskwood", text(duskwood))
      assert.are.equal("Westfall", text(westfall))
      assert.are.equal(0, elwynn.title.calls.addonSetText)
    end)

  it("a pooled header reused for a zone: the English stays", function()
    local button = header("Seasonal")
    Q.updateList()
    assert.are.equal("季節", text(button))
    button.title.text = "Elwynn Forest"
    Q.updateList()
    assert.are.equal("Elwynn Forest", text(button))
    alt(true); alt(false)
    assert.are.equal("Elwynn Forest", text(button))
  end)

  it("a header pool or header of the wrong shape raises nothing", function()
    headers.active[7] = true
    headers.active[{ GetTitleRegion = function() error("moved") end }] = true
    assert.has_no.errors(function() Q.updateList() end)
    _G.QuestScrollFrame.headerFramePool = { EnumerateActive = "moved" }
    assert.has_no.errors(function() Q.updateList() end)
  end)
end)
