-- UI/TooltipUnit's quest lines: the line kinds the client tags each row with, a quest title found by the hash of its
-- English (the addon ships no English), and the minimap mouseover's single-line block (names, a title, objectives).
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for _, f in ipairs(H.UI_FILES) do FILES[#FILES + 1] = f end
for _, f in ipairs({ "UI/QuestMap.lua", "UI/TimeLine.lua", "UI/Tooltip.lua", "UI/TooltipUnit.lua" }) do
  FILES[#FILES + 1] = f
end

local UI = {
  QUEST_MONSTERS_KILLED = { "%2$d/%3$d %1$s slain", "%1$sを倒す: %2$d/%3$d" },
  TOOLTIP_UNIT_LEVEL = { "Level %s", "レベル %s" },
}

-- Enum.TooltipDataLineType as Forever numbers it (only the kinds these specs use)
local LINE_TYPES = { None = 0, UnitName = 2, QuestObjective = 8, QuestTitle = 17, UnitOwner = 16 }

-- quest id → { English title, Japanese title }. 11 and 12 share a title and its Japanese; 21 and 22 share a title
-- with different Japanese (a chain's parts).
local QUESTS = {
  [5] = { "Wolf Pelts", "狼の毛皮" },
  [11] = { "The Balance of Nature", "自然の均衡" }, [12] = { "The Balance of Nature", "自然の均衡" },
  [21] = { "Report to Goldshire", "Goldshireへの報告" }, [22] = { "Report to Goldshire", "Goldshireに報告せよ" },
  [30] = { "Untranslated Errand", nil },
}

describe("UI/TooltipUnit: quest titles and line kinds", function()
  local WFJ, tt, inLog

  local function left(i) return _G["GameTooltipTextLeft" .. i]:GetText() end
  local function kinds(list)
    local lines = {}
    for i, kind in ipairs(list) do lines[i] = { lineIndex = i, type = LINE_TYPES[kind] } end
    return { lines = lines }
  end
  -- the client's order: lines, the Unit post-calls, then Show
  local function hover(lines, data)
    tt:SetOwner(_G.UIParent, "ANCHOR_CURSOR")
    tt:SetText(lines[1])
    for i = 2, #lines do tt:AddLine(lines[i]) end
    for _, fn in ipairs(Stub.tooltipPostCalls[2] or {}) do fn(tt, data) end
    tt:Show()
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    _G.Enum.TooltipDataLineType = LINE_TYPES
    _G.UIParent = _G.UIParent or CreateFrame("Frame", "UIParent")
    inLog = {}
    _G.C_QuestLog = { GetLogIndexForQuestID = function(id) return inLog[id] end }
    WFJ = H.loadChunks(FILES)
    local function h1(en) return (WFJ.Hash.h32x2(WFJ.Normalize.v1(WFJ.Collector.text(en)))) end
    local titles = {}
    WFJ.Data = { quest = {} }
    for id, q in pairs(QUESTS) do
      WFJ.Data.quest[id] = true
      if q[2] then titles[id] = { ja = q[2], status = ".", h1 = h1(q[1]) } end
    end
    WFJ.Lookup = { get = function(kind, id) if kind == "quest.title" then return titles[id] end end }
    H.uiSetup(WFJ, UI, { lookup = function(kind, id) if kind == "quest.title" then return titles[id] end end })
    WFJ.HelpTooltip.init()
    tt = _G.GameTooltip
  end)

  after_each(function()
    H.uiTeardown()
    _G.C_QuestLog = nil
    Stub.keys.alt = false
  end)

  describe("lineKinds", function()
    it("names each row's kind from the client's lineIndex", function()
      local data = { lines = { { lineIndex = 1, type = 2 }, { lineIndex = 3, type = 17 }, { type = 8 },
        { lineIndex = 4 } } }
      assert.are.same({ [1] = "UnitName", [3] = "QuestTitle" }, WFJ.TooltipUnit.lineKinds(data))
    end)

    it("no data, no lines or no enum: no kinds", function()
      assert.are.same({}, WFJ.TooltipUnit.lineKinds(nil))
      assert.are.same({}, WFJ.TooltipUnit.lineKinds({}))
      _G.Enum.TooltipDataLineType = nil
      assert.are.same({}, WFJ.TooltipUnit.lineKinds(kinds({ "UnitName" })))
    end)
  end)

  describe("questFor", function()
    it("a title only one quest has", function()
      assert.are.equal(5, WFJ.TooltipUnit.questFor("Wolf Pelts"))
    end)

    it("a title several quests share with the same Japanese: any of them", function()
      local id = WFJ.TooltipUnit.questFor("The Balance of Nature")
      assert.is_true(id == 11 or id == 12)
    end)

    it("a title shared with different Japanese: the one in the quest log, else none", function()
      local id, why = WFJ.TooltipUnit.questFor("Report to Goldshire")
      assert.is_nil(id)
      assert.are.equal("quests sharing the title differ", why)
      inLog[22] = 3
      assert.are.equal(22, WFJ.TooltipUnit.questFor("Report to Goldshire"))
      inLog[21] = 1 -- both held: still not told apart
      assert.is_nil(WFJ.TooltipUnit.questFor("Report to Goldshire"))
    end)

    it("an unknown, empty, missing or secret title: none, with the reason", function()
      assert.are.same({ nil, "no quest with that title" }, { WFJ.TooltipUnit.questFor("Some Other Quest") })
      assert.are.same({ nil, "no readable title" }, { WFJ.TooltipUnit.questFor("") })
      assert.are.same({ nil, "no readable title" }, { WFJ.TooltipUnit.questFor(nil) })
      _G.issecretvalue = function(v) return v == "Wolf Pelts" end
      assert.are.same({ nil, "no readable title" }, { WFJ.TooltipUnit.questFor("Wolf Pelts") })
      _G.issecretvalue = nil
    end)
  end)

  describe("the Unit post-call", function()
    before_each(function() assert.is_true(WFJ.TooltipUnit.init()) end)

    it("a QuestTitle row shows its quest's Japanese; the name row and an unknown title stay", function()
      hover({ "Young Thistle Boar", "Level 2", "Wolf Pelts", "0/4 Young Thistle Boar slain", "Untranslated Errand" },
        kinds({ "UnitName", "None", "QuestTitle", "QuestObjective", "QuestTitle" }))
      assert.are.equal("Young Thistle Boar", left(1))
      assert.are.equal("レベル 2", left(2))
      assert.are.equal("狼の毛皮", left(3))
      assert.is_truthy(left(4):find("Young Thistle Boarを倒す: 0/4", 1, true))
      assert.are.equal("Untranslated Errand", left(5))
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      assert.are.equal("Wolf Pelts", left(3))
      Stub.keys.alt = false; WFJ.Modifier.refresh()
      assert.are.equal("狼の毛皮", left(3))
      tt:Hide()
      assert.are.equal(0, WFJ.SurfaceState.count(WFJ.TooltipUnit.SURFACE))
    end)

    it("a title on a row the client did not tag QuestTitle is read as a unit line, not a quest", function()
      hover({ "Young Thistle Boar", "Wolf Pelts" }, kinds({ "UnitName", "None" }))
      assert.are.equal("Wolf Pelts", left(2))
    end)

    it("a first row tagged QuestTitle is read from row 1", function()
      hover({ "Wolf Pelts", "0/4 Young Thistle Boar slain" }, kinds({ "QuestTitle", "QuestObjective" }))
      assert.are.equal("狼の毛皮", left(1))
      -- untagged, row 1 is a name and is never read
      hover({ "Wolf Pelts", "Level 2" }, kinds({ "UnitName", "None" }))
      assert.are.equal("Wolf Pelts", left(1))
    end)

    it("the trace names the row's quest, or why it has none", function()
      WFJ.Tooltip.trace = {}
      hover({ "Young Thistle Boar", "Report to Goldshire", "Wolf Pelts" },
        kinds({ "UnitName", "QuestTitle", "QuestTitle" }))
      local last = WFJ.Tooltip.trace[#WFJ.Tooltip.trace]
      assert.is_truthy(last:find("row 2 quest title: quests sharing the title differ", 1, true), last)
      assert.is_truthy(last:find("row 3 quest title: quest 5", 1, true), last)
      WFJ.Tooltip.trace = nil
    end)
  end)

  describe("the minimap mouseover block", function()
    local BLOCK = "|cffffffffInnkeeper Allison|r\nWolf Pelts\n|cffffffff- 2/7 Young Nightsaber slain"

    it("the name is kept, the title and the objective are Japanese, colour codes stay, gold goes first", function()
      local ja, notes = WFJ.TooltipUnit.minimapBlock("Innkeeper Allison\nWolf Pelts|cffffffff\n"
        .. "- 2/7 Young Nightsaber slain")
      assert.are.equal("|cffffd100Innkeeper Allison\n狼の毛皮|cffffffff\n- Young Nightsaberを倒す: 2/7", ja)
      assert.are.same({ "title quest 5" }, notes)
    end)

    it("a block that opens with its own colour code takes no gold", function()
      local ja = WFJ.TooltipUnit.minimapBlock(BLOCK)
      assert.are.equal("|cffffffffInnkeeper Allison|r\n狼の毛皮\n|cffffffff- Young Nightsaberを倒す: 2/7", ja)
    end)

    it("nothing to change, one line only, or a secret block: nil", function()
      assert.is_nil((WFJ.TooltipUnit.minimapBlock("Innkeeper Allison\nUntranslated Errand\n- Run")))
      assert.is_nil(WFJ.TooltipUnit.minimapBlock("Wolf Pelts"))
      assert.is_nil(WFJ.TooltipUnit.minimapBlock(nil))
      _G.issecretvalue = function(v) return v == BLOCK end
      assert.is_nil(WFJ.TooltipUnit.minimapBlock(BLOCK))
      _G.issecretvalue = nil
    end)

    it("a one-line tooltip holding the block is written whole; the modifier held leaves the client's", function()
      assert.is_true(WFJ.TooltipUnit.init())
      hover({ BLOCK })
      assert.are.equal("|cffffffffInnkeeper Allison|r\n狼の毛皮\n|cffffffff- Young Nightsaberを倒す: 2/7", left(1))
      assert.is_true(WFJ.Font.dressed(_G.GameTooltipTextLeft1)) -- the Japanese face, outside any record
      WFJ.TooltipUnit.release()
      assert.is_false(WFJ.Font.dressed(_G.GameTooltipTextLeft1))
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      hover({ BLOCK })
      assert.are.equal(BLOCK, left(1))
    end)
  end)

  describe("registration", function()
    it("the minimap mouseover, game object and corpse tooltips take the same post-call when the client has them",
      function()
        _G.Enum.TooltipDataType.MinimapMouseover = 22
        _G.Enum.TooltipDataType.Object = 33
        assert.is_true(WFJ.TooltipUnit.init())
        assert.are.equal(WFJ.TooltipUnit.onUnit, Stub.tooltipPostCalls[2][1])
        assert.are.equal(WFJ.TooltipUnit.onUnit, Stub.tooltipPostCalls[22][1])
        assert.are.equal(WFJ.TooltipUnit.onUnit, Stub.tooltipPostCalls[33][1])
        -- Corpse is a type this client does not have: nothing else is registered
        local types = {}
        for t, list in pairs(Stub.tooltipPostCalls) do if #list > 0 then types[#types + 1] = t end end
        table.sort(types)
        assert.are.same({ 2, 22, 33 }, types)
        assert.is_true(WFJ.TooltipUnit.init()) -- once only
        assert.are.equal(1, #Stub.tooltipPostCalls[22])
      end)
  end)
end)
