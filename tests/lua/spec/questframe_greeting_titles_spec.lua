-- UI/QuestFrame's greeting panel quest buttons: each button from titleButtonPool shows its quest's Japanese title, an
-- active one by GetActiveQuestID / GetActiveTitle, an offered one by GetAvailableQuestInfo's quest id (its fifth
-- return) / GetAvailableTitle, through UI/QuestMap's title helper. The client numbers both lists from 1.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for _, f in ipairs(H.UI_FILES) do FILES[#FILES + 1] = f end
FILES[#FILES + 1] = "UI/QuestFrame.lua"
FILES[#FILES + 1] = "UI/QuestMap.lua"

local PLAYER = { name = "Reyn", class = "Hunter", race = "Night Elf" }
local TITLES = { [5] = { ja = "狼の毛皮", status = "." }, [9] = { ja = "失われた書物", status = "." } }
local TRIVIAL = { "|cff000000%s (low level)|r", "|cff000000%s (低レベル)|r" }

describe("UI/QuestFrame: the greeting panel's quest titles", function()
  local WFJ, active, offered, buttons

  -- a pooled title button as QuestFrameGreetingPanel_OnShow leaves it
  local function button(id, isActive, text)
    local b = Stub.button(nil, text)
    b.id, b.isActive, b.height = id, isActive, 16
    b.Icon = { GetHeight = function() return 16 end }
    function b:GetID() return self.id end
    function b:GetTextHeight() return self.fontString:GetHeight() end
    function b:SetHeight(h) self.height = h end
    return b
  end

  local function greet(list)
    buttons = list
    Stub.showGreeting()
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI()
    _G.TRIVIAL_QUEST_DISPLAY = TRIVIAL[1]
    _G.C_QuestLog = { GetTitleForQuestID = function() return nil end } -- greeting quests are read from their own API
    active = { { id = 5, title = "Wolf Pelts" } }
    offered = { { id = 9, title = "The Lost Tome" }, { id = 30, title = "Untranslated Errand" } }
    _G.GetActiveQuestID = function(i) return active[i] and active[i].id end
    _G.GetActiveTitle = function(i) return active[i] and active[i].title end
    _G.GetAvailableQuestInfo = function(i)
      if offered[i] then return false, 0, false, false, offered[i].id end
    end
    _G.GetAvailableTitle = function(i) return offered[i] and offered[i].title end
    buttons = {}
    _G.QuestFrameGreetingPanel.titleButtonPool = { EnumerateActive = function()
      local i = 0
      return function() i = i + 1; return buttons[i] end
    end }
    WFJ = H.loadChunks(FILES)
    local lookup = function(kind, id) if kind == "quest.title" then return TITLES[id] end end
    H.uiSetup(WFJ, {}, { lookup = lookup })
    WFJ.Lookup = { get = function(kind, id)
      if kind == "ui" and id == "TRIVIAL_QUEST_DISPLAY" then return { ja = TRIVIAL[2], status = "." } end
    end }
    WFJ.Collector.load(nil, H.collectorDeps({ lookup = lookup }))
    WFJ.QuestMap.init()
    assert.is_true(WFJ.QuestFrame.init({ key = function(en) return WFJ.Collector.key(en, PLAYER) end }))
  end)

  after_each(function()
    H.uiTeardown()
    for _, k in ipairs({ "TRIVIAL_QUEST_DISPLAY", "C_QuestLog", "GetActiveQuestID", "GetActiveTitle",
      "GetAvailableQuestInfo", "GetAvailableTitle" }) do
      _G[k] = nil
    end
    Stub.keys.alt = false
  end)

  it("active and offered buttons show their quests' Japanese titles; one with none stays English", function()
    local a = button(1, 1, "|cff000000Wolf Pelts|r")
    local o1 = button(1, 0, TRIVIAL[1]:format("The Lost Tome"))
    local o2 = button(2, 0, "|cff000000Untranslated Errand|r")
    greet({ a, o1, o2 })
    assert.are.equal("|cff000000狼の毛皮|r", a:GetText())
    assert.are.equal("|cff000000失われた書物 (低レベル)|r", o1:GetText())
    assert.are.equal("|cff000000Untranslated Errand|r", o2:GetText())
    assert.are.equal(WFJ.Font.PATH, (a:GetFontString():GetFont()))
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal("|cff000000Wolf Pelts|r", a:GetText())
    assert.are.equal(TRIVIAL[1]:format("The Lost Tome"), o1:GetText())
  end)

  it("the same number in both lists is told apart by isActive", function()
    active = { { id = 9, title = "The Lost Tome" } }
    offered = { { id = 5, title = "Wolf Pelts" } }
    local a = button(1, 1, "|cff000000The Lost Tome|r")
    local o = button(1, 0, "|cff000000Wolf Pelts|r")
    greet({ o, a })
    assert.are.equal("|cff000000失われた書物|r", a:GetText())
    assert.are.equal("|cff000000狼の毛皮|r", o:GetText())
  end)

  it("no pool, or no quest API, and the greeting still shows without an error", function()
    _G.QuestFrameGreetingPanel.titleButtonPool = nil
    assert.has_no.errors(function() greet({}) end)
    _G.QuestFrameGreetingPanel.titleButtonPool = { EnumerateActive = function()
      local i = 0
      return function() i = i + 1; return buttons[i] end
    end }
    _G.GetActiveQuestID, _G.GetAvailableQuestInfo = nil, nil
    local a = button(1, 1, "|cff000000Wolf Pelts|r")
    assert.has_no.errors(function() greet({ a }) end)
    assert.are.equal("|cff000000Wolf Pelts|r", a:GetText())
  end)
end)
