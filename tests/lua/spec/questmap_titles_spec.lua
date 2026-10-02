-- UI/QuestMap's title helper as the talk and quest greeting windows use it: a quest row wrapped in a template with
-- words of its own ("%s (low level)", "%s (ignored)") gets the dictionary's Japanese words around a Japanese title and
-- keeps the English ones around the English title; and one objective line in Japanese without a record.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for _, f in ipairs(H.UI_FILES) do FILES[#FILES + 1] = f end
FILES[#FILES + 1] = "UI/QuestMap.lua"

local UI = {
  QUEST_MONSTERS_KILLED = { "%2$d/%3$d %1$s slain", "%1$sを倒す: %2$d/%3$d" },
  PARENS_TEMPLATE = { "(%s)", "(%s)" },
  COMPLETE = { "Complete", "完了" },
}

-- the wrappers' Japanese as the dictionary ships it (Forever 1.60.1.70170's English)
local WRAPPERS = {
  TRIVIAL_QUEST_DISPLAY = { "|cff000000%s (low level)|r", "|cff000000%s (低レベル)|r" },
  IGNORED_QUEST_DISPLAY = { "|cff000000%s (ignored)|r", "|cff000000%s (無視)|r" },
}

local TITLES = { [5] = { ja = "狼の毛皮", status = "." }, [9] = { ja = "失われた書物", status = "." } }
local SURFACE = "gossip"

describe("UI/QuestMap: quest-row titles and objective lines", function()
  local WFJ, QM, SS, wrappers, log

  local function trivial(title) return WRAPPERS.TRIVIAL_QUEST_DISPLAY[1]:format(title) end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    log = { [5] = "Wolf Pelts" } -- quest 9 is offered, not in the log: the API has no title for it
    _G.C_QuestLog = { GetTitleForQuestID = function(id) return log[id] end }
    for key, pair in pairs(WRAPPERS) do _G[key] = pair[1] end
    WFJ = H.loadChunks(FILES)
    wrappers = {}
    for key, pair in pairs(WRAPPERS) do wrappers[key] = { ja = pair[2], status = "." } end
    WFJ.Lookup = { get = function(kind, id) if kind == "ui" then return wrappers[id] end end }
    H.uiSetup(WFJ, UI, { lookup = function(kind, id) if kind == "quest.title" then return TITLES[id] end end })
    QM, SS = WFJ.QuestMap, WFJ.SurfaceState
    QM.init()
  end)

  after_each(function()
    H.uiTeardown()
    for key in pairs(WRAPPERS) do _G[key] = nil end
    _G.C_QuestLog = nil
    Stub.keys.alt = false
  end)

  describe("decoration", function()
    it("a wrapper with words of its own: its English halves and the Japanese suffix", function()
      assert.are.same({ "|cff000000", " (low level)|r", " (低レベル)|r" },
        { QM.decoration(trivial("Wolf Pelts"), "Wolf Pelts") })
      assert.are.same({ "|cff000000", " (ignored)|r", " (無視)|r" },
        { QM.decoration("|cff000000Wolf Pelts (ignored)|r", "Wolf Pelts") })
    end)

    it("no Japanese for the wrapper, or a Japanese one opening differently: no Japanese suffix", function()
      wrappers.TRIVIAL_QUEST_DISPLAY = nil
      assert.are.same({ "|cff000000", " (low level)|r" }, { QM.decoration(trivial("Wolf Pelts"), "Wolf Pelts") })
      wrappers.TRIVIAL_QUEST_DISPLAY = { ja = "%s (低レベル)", status = "." }
      local p, s, j = QM.decoration(trivial("Wolf Pelts"), "Wolf Pelts")
      assert.are.same({ "|cff000000", " (low level)|r" }, { p, s })
      assert.is_nil(j)
    end)

    it("the plain row colour and an undecorated title are as before", function()
      assert.are.same({ "|cff000000", "|r" }, { QM.decoration("|cff000000Wolf Pelts|r", "Wolf Pelts") })
      assert.are.same({ "", "" }, { QM.decoration("Wolf Pelts", "Wolf Pelts") })
    end)
  end)

  describe("showTitle", function()
    it("a low-level row: the Japanese title inside the Japanese words; Alt gives back the English row", function()
      local fs = Stub.fontString(trivial("Wolf Pelts"))
      assert.are.equal(1, QM.showTitle(SURFACE, 5, fs, nil, "Wolf Pelts"))
      assert.are.equal("|cff000000狼の毛皮 (低レベル)|r", fs:GetText())
      local rec = SS.get(SURFACE, "title.5")
      assert.are.equal("狼の毛皮", rec.fs:GetText()) -- the adapter reads the title without the Japanese words
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      assert.are.equal(trivial("Wolf Pelts"), fs:GetText())
      assert.are.equal("Wolf Pelts", rec.fs:GetText()) -- and without the English ones
      Stub.keys.alt = false; WFJ.Modifier.refresh()
      assert.are.equal("|cff000000狼の毛皮 (低レベル)|r", fs:GetText())
      -- shown again while still ours: the same record, nothing rewritten
      local writes = fs.calls.addonSetText
      assert.are.equal(1, QM.showTitle(SURFACE, 5, fs, nil, "Wolf Pelts"))
      assert.are.equal(writes, fs.calls.addonSetText)
    end)

    it("an ignored row the same way; a wrapper with no Japanese keeps its English words", function()
      local fs = Stub.fontString("|cff000000Wolf Pelts (ignored)|r")
      QM.showTitle(SURFACE, 5, fs, nil, "Wolf Pelts")
      assert.are.equal("|cff000000狼の毛皮 (無視)|r", fs:GetText())
      wrappers.TRIVIAL_QUEST_DISPLAY = nil
      local other = Stub.fontString(trivial("Wolf Pelts"))
      QM.showTitle("questframe.greeting", 5, other, nil, "Wolf Pelts")
      assert.are.equal("|cff000000狼の毛皮 (low level)|r", other:GetText())
    end)

    it("an offered quest the log has no title for is shown from the title the caller read", function()
      local fs = Stub.fontString("|cff000000The Lost Tome|r")
      assert.are.equal(0, QM.showTitle(SURFACE, 9, fs))
      assert.are.equal("|cff000000The Lost Tome|r", fs:GetText())
      assert.are.equal(1, QM.showTitle(SURFACE, 9, fs, nil, "The Lost Tome"))
      assert.are.equal("|cff000000失われた書物|r", fs:GetText())
    end)

    it("the row it sits on is the record's row", function()
      local row = CreateFrame("Button")
      local fs = Stub.fontString("Wolf Pelts")
      QM.showTitle(SURFACE, 5, fs, nil, nil, row)
      assert.are.equal("狼の毛皮", fs:GetText())
      assert.are.equal(row, SS.get(SURFACE, "title.5").meta.ctx.row)
    end)

    it("a quest id of 0, a widget it cannot read or a text that is not the title: nothing shown", function()
      local fs = Stub.fontString("Wolf Pelts")
      assert.are.equal(0, QM.showTitle(SURFACE, 0, fs, nil, "Wolf Pelts"))
      assert.are.equal(0, QM.showTitle(SURFACE, 5, { GetText = function() return "Wolf Pelts" end }, nil,
        "Wolf Pelts"))
      assert.are.equal(0, QM.showTitle(SURFACE, 5, Stub.fontString("Something else"), nil, "Wolf Pelts"))
      assert.are.equal("Wolf Pelts", fs:GetText())
      assert.are.equal(0, SS.count(SURFACE))
    end)
  end)

  describe("dropWidget", function()
    it("with no record key, every record on the widget's adapter goes", function()
      local fs = Stub.fontString(trivial("Wolf Pelts"))
      QM.showTitle(SURFACE, 5, fs, nil, "Wolf Pelts")
      assert.are.equal(1, SS.count(SURFACE))
      QM.dropWidget(SURFACE, nil, fs)
      assert.are.equal(0, SS.count(SURFACE))
      -- a widget that never had an adapter: nothing to drop, nothing raised
      assert.has_no.errors(function() QM.dropWidget(SURFACE, nil, Stub.fontString("x")) end)
      assert.has_no.errors(function() QM.dropWidget(SURFACE, nil, nil) end)
    end)
  end)

  describe("objectiveJapanese", function()
    it("an objective line in Japanese, with or without the finished tag; anything else nil", function()
      assert.are.equal("Young Nightsaberを倒す: 2/7", QM.objectiveJapanese("2/7 Young Nightsaber slain", SURFACE))
      assert.are.equal("Young Nightsaberを倒す: 7/7 (完了)",
        QM.objectiveJapanese("7/7 Young Nightsaber slain (Complete)", SURFACE))
      assert.is_nil(QM.objectiveJapanese("Find the tome.", SURFACE))
      assert.is_nil(QM.objectiveJapanese("", SURFACE))
      assert.is_nil(QM.objectiveJapanese(nil, SURFACE))
      assert.are.equal(0, SS.count(SURFACE)) -- no record is kept
    end)
  end)
end)
