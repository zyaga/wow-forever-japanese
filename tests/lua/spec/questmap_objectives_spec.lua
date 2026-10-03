local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local QStub = require("tests.lua.spec.stub_questmap")

-- Objective lines on the camelot tracker, the quest list and the map details. A client template
-- ("3/10 Kobold Vermin slain", QUEST_MONSTERS_KILLED) keeps the name and the counts as written; an objective's own
-- server text is found by its fingerprint (Core/Objectives) and keeps the count where the client put it.
local FILES = {}
for _, f in ipairs(H.UI_FILES) do FILES[#FILES + 1] = f end
FILES[#FILES + 1] = "Core/Objectives.lua"
FILES[#FILES + 1] = "UI/QuestFrame.lua"
FILES[#FILES + 1] = "UI/QuestMap.lua"

local UI = {
  QUEST_MONSTERS_KILLED = { "%2$d/%3$d %1$s slain", "%1$sを倒す: %2$d/%3$d" },
  QUEST_FACTION_NEEDED = { "%2$s / %3$s %1$s", "%1$s: %2$s / %3$s" },
  FACTION_STANDING_LABEL4 = { "Neutral", "中立" }, FACTION_STANDING_LABEL5 = { "Friendly", "友好" },
  COMPLETE = { "Complete", "完了" }, PARENS_TEMPLATE = { "(%s)", "(%s)" },
  TRACKER_HEADER_QUESTS = { "Quests", "クエスト" },
  CLICK_QUEST_DETAILS = { "<Click to view Quest Details>", "<クリックでクエストの詳細を表示>" },
  -- a shorter key sharing the kill line's shape: never read on an objective widget
  SPELL_STACK = { "%2$d/%3$d %1$s", "スタック" },
  -- camelot's elite tag and the content-tracking module's client lines
  ELITE = { "Elite", "エリート" },
  CONTENT_TRACKING_RETRIEVING_INFO = { "|cffff0000Retrieving information...|r", "|cffff0000情報を取得中...|r" },
  CONTENT_TRACKING_LOCATION_UNAVAILABLE = { "|cffff0000Location unavailable|r", "|cffff0000場所が不明です|r" },
  CONTENT_TRACKING_ROUTE_UNAVAILABLE = { "|cffff0000Route unavailable|r", "|cffff0000経路が不明です|r" },
  OPTIONAL_QUEST_OBJECTIVE_DESCRIPTION = { "%s (Optional)", "%s(任意)" },
  -- the gamepad lines in place of the click hint (questmapframe.lua:2292–2294)
  MAP_PIN_TOGGLE_QUEST_FOCUS = { "Toggle Focus on Quest", "クエストへのフォーカスを切り替え" },
  CONTEXT_ACTION_LABEL_MORE_ACTIONS = { "More", "その他" },
}

-- QuestObjective id → { English, Japanese }; two ids share "Tower Marked" with different Japanese (ambiguous)
local OBJECTIVES = {
  [380142] = { "Archive Burned", "Archiveを焼き払う" },
  [380900] = { "Tower Marked", "Towerに印をつける" }, [380901] = { "Tower Marked", "Towerを示す" },
}

local QUEST = { title = "Burning Archives", description = "Burn it.", objectives = "Burn the archive.", level = 20 }

describe("UI/QuestMap: objective lines", function()
  local WFJ, SS, QM, Q, DATA, registry

  local function objectiveRows()
    local rows = {}
    local function h1(text) return (WFJ.Hash.h32x2(WFJ.Normalize.v1(text))) end
    for id, pair in pairs(OBJECTIVES) do rows[id] = { pair[2], h1(pair[1]), "." } end
    return rows, h1
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI()
    Q = QStub.install()
    Q.quests[9] = { title = QUEST.title, description = QUEST.description, objectives = QUEST.objectives, level = 20,
      leaderboard = { { text = "3/10 Kobold Vermin slain" }, { text = "0/1 Archive Burned" } } }
    Q.log, Q.watched[9] = { 9 }, true
    -- EventRegistry: RegisterCallback(event, fn, owner) → fn(owner, ...) on TriggerEvent
    registry = { cbs = {} }
    function registry:RegisterCallback(event, fn, owner) self.cbs[event] = function(...) return fn(owner, ...) end end
    _G.EventRegistry = registry
    WFJ = H.loadChunks(FILES)
    DATA = {}
    H.uiSetup(WFJ, UI, { lookup = function(kind, id) return DATA[kind] and DATA[kind][id] end })
    local rows, h1 = objectiveRows()
    DATA.objective = {}
    for id, row in pairs(rows) do DATA.objective[id] = { ja = row[1], status = row[3] } end
    WFJ.ObjectiveIndex = WFJ.Objectives.build({ rows = rows, hash = h1 })
    SS, QM = WFJ.SurfaceState, WFJ.QuestMap
    assert.is_true(WFJ.QuestFrame.init())
    assert.is_true(QM.init())
  end)

  after_each(function() H.uiTeardown(); _G.EventRegistry = nil end)

  local function trackerLines()
    Q.updateTracker()
    local block = _G.QuestObjectiveTracker:GetExistingBlock(9)
    return block, block.usedLines
  end

  describe("the client's objective templates", function()
    it("a kill line keeps the mob name and both counts", function()
      local _, lines = trackerLines()
      assert.are.equal("Kobold Verminを倒す: 3/10", lines[1].Text:GetText())
    end)

    it("a faction line shows the standings in Japanese and the faction as written", function()
      Q.quests[9].leaderboard = { { text = "Neutral / Friendly Darnassus" } }
      local _, lines = trackerLines()
      assert.are.equal("Darnassus: 中立 / 友好", lines[1].Text:GetText())
    end)
  end)

  describe("the objective's own text, found by its fingerprint", function()
    it("the tracker: count before the text, kept where the client put it", function()
      local _, lines = trackerLines()
      assert.are.equal("0/1 Archiveを焼き払う", lines[2].Text:GetText())
    end)

    it("the count after the text (the older order) and no count at all", function()
      Q.quests[9].leaderboard = { { text = "Archive Burned: 0/1" }, { text = "Archive Burned" } }
      local _, lines = trackerLines()
      assert.are.equal("Archiveを焼き払う: 0/1", lines[1].Text:GetText())
      assert.are.equal("Archiveを焼き払う", lines[2].Text:GetText())
    end)

    it("a line that matches nothing, and an ambiguous fingerprint, stay the client's English", function()
      Q.quests[9].leaderboard = { { text = "0/1 Tower Marked" }, { text = "Find the lost relic" } }
      local _, lines = trackerLines()
      assert.are.equal("0/1 Tower Marked", lines[1].Text:GetText())
      assert.are.equal("Find the lost relic", lines[2].Text:GetText())
      assert.are.equal(0, SS.count(QM.TRACKER_OBJECTIVES))
      assert.are.equal(2, WFJ.ObjectiveIndex.counts.ambiguous)
    end)

    it("an area row is read as an objective line, its count kept; a fingerprint shared with an objective"
      .. " under different Japanese is not shown", function()
      local rows, h1 = objectiveRows()
      local area = { [62] = { "Fargodeep Mineを偵察する", h1("Scout through the Fargodeep Mine"), "." },
        [2240] = { "Towerを示す", h1("Tower Marked"), "." } }
      rows[380901] = nil -- "Tower Marked" is now one objective row, made ambiguous only by the area row
      DATA.objective[380901] = nil
      DATA.area = { [62] = { ja = area[62][1], status = "." }, [2240] = { ja = area[2240][1], status = "." } }
      WFJ.ObjectiveIndex = WFJ.Objectives.build({ hash = h1,
        sources = { { type = "objective", rows = rows }, { type = "area", rows = area } } })
      Q.quests[9].leaderboard = { { text = "0/1 Scout through the Fargodeep Mine" }, { text = "0/1 Tower Marked" },
        { text = "0/1 Archive Burned" } }
      local _, lines = trackerLines()
      assert.are.equal("0/1 Fargodeep Mineを偵察する", lines[1].Text:GetText())
      assert.are.equal("0/1 Tower Marked", lines[2].Text:GetText())
      assert.are.equal("0/1 Archiveを焼き払う", lines[3].Text:GetText())
      assert.are.equal(2, WFJ.ObjectiveIndex.counts.ambiguous)
      assert.are.same({ objective = 2, area = 2 }, WFJ.ObjectiveIndex.counts.byType)
    end)

    it("a quest with no counted objectives: its whole objective text on one line is the quest's Japanese", function()
      local h1 = (WFJ.Hash.h32x2(WFJ.Normalize.v1(QUEST.objectives)))
      DATA["quest.objectives"] = { [9] = { ja = "記録庫を焼き払え。", status = ".", h1 = h1 } }
      WFJ.Lookup = { get = function(kind, id) return DATA[kind] and DATA[kind][id] end }
      Q.quests[9].leaderboard = { { text = QUEST.objectives }, { text = "Burn something else." } }
      local _, lines = trackerLines()
      assert.are.equal("記録庫を焼き払え。", lines[1].Text:GetText())
      assert.are.equal("Burn something else.", lines[2].Text:GetText()) -- not the quest's text: as written
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      assert.are.equal(QUEST.objectives, lines[1].Text:GetText())
      Stub.keys.alt = false; WFJ.Modifier.refresh()
    end)

    it("a quest's completion log line is its keyed text (quest-cache text keyed like NPC dialogue)", function()
      local log = "Speak with Deathguard Billmuth at Tyr's Watch."
      DATA.gossip = { k1 = { ja = "Tyr's WatchのDeathguard Billmuthと話す。", status = "." } }
      local shipped = WFJ.ShippedGossipKey
      WFJ.ShippedGossipKey = function(text) if text == log then return "k1" end end
      WFJ.Lookup = { get = function(kind, id) return DATA[kind] and DATA[kind][id] end }
      Q.quests[9].leaderboard = { { text = log } }
      local _, lines = trackerLines()
      assert.are.equal("Tyr's WatchのDeathguard Billmuthと話す。", lines[1].Text:GetText())
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      assert.are.equal(log, lines[1].Text:GetText())
      Stub.keys.alt = false; WFJ.Modifier.refresh()
      WFJ.ShippedGossipKey = shipped
    end)

    it("the block's height follows the line's height change, and the modifier restores the English", function()
      Q.quests[9].leaderboard = { { text = "0/1 Archive Burned" } }
      local block, lines = trackerLines()
      assert.are.equal(lines[1]:GetHeight(), lines[1].Text:GetHeight()) -- the line is sized to the Japanese
      local laid, ja = block.height, lines[1].Text:GetHeight()
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      assert.are.equal("0/1 Archive Burned", lines[1].Text:GetText())
      assert.are.equal(lines[1]:GetHeight(), lines[1].Text:GetHeight())
      assert.are_not.equal(ja, lines[1].Text:GetHeight()) -- the stub wraps the Japanese onto a second line
      assert.are.equal(laid + (lines[1].Text:GetHeight() - ja), block.height)
      Stub.keys.alt = false; WFJ.Modifier.refresh()
      assert.are.equal("0/1 Archiveを焼き払う", lines[1].Text:GetText())
    end)

    it("the quest list's objective rows", function()
      Q.updateList()
      local texts = {}
      for row in _G.QuestScrollFrame.objectiveFramePool:EnumerateActive() do texts[row.Text:GetText()] = true end
      assert.is_true(texts["Kobold Verminを倒す: 3/10"])
      assert.is_true(texts["0/1 Archiveを焼き払う"])
    end)

    it("the map details' objectives, a finished one with its (Complete) tag in Japanese", function()
      Q.quests[9].leaderboard = { { text = "3/10 Kobold Vermin slain" }, { text = "1/1 Archive Burned", done = true } }
      Q.showDetails(9)
      assert.are.equal("Kobold Verminを倒す: 3/10", Q.objectiveStrings[1]:GetText())
      assert.are.equal("1/1 Archiveを焼き払う (完了)", Q.objectiveStrings[2]:GetText())
      Q.closeDetails()
      assert.are.equal("1/1 Archive Burned (Complete)", Q.objectiveStrings[2]:GetText())
    end)
  end)

  describe("the list title's tooltip (CLICK_QUEST_DETAILS)", function()
    it("its hint line and objective lines translate after QuestMapLogTitleButton.OnEnter; the title stays", function()
      local tt, button = _G.GameTooltip, CreateFrame("Button")
      tt:SetOwner(button, "ANCHOR_RIGHT")
      tt:AddLine(QUEST.title)
      tt:AddLine("3/10 Kobold Vermin slain")
      tt:AddLine("<Click to view Quest Details>")
      tt:Show()
      registry.cbs["QuestMapLogTitleButton.OnEnter"](button, 9)
      assert.are.equal(QUEST.title, _G.GameTooltipTextLeft1:GetText())
      assert.are.equal("Kobold Verminを倒す: 3/10", _G.GameTooltipTextLeft2:GetText())
      assert.are.equal("<クリックでクエストの詳細を表示>", _G.GameTooltipTextLeft3:GetText())
    end)
  end)

  describe("the title tooltip in gamepad mode", function()
    it("the input-icon lines translate with the icon kept; Alt shows English", function()
      local icon = "|A:Gamepad_Ltr_X_64:30:30|a" -- CreateAtlasMarkup(atlas, 30, 30), no space before the text
      local tt, button = _G.GameTooltip, CreateFrame("Button")
      tt:SetOwner(button, "ANCHOR_RIGHT")
      tt:AddLine(QUEST.title)
      tt:AddLine(icon .. "Toggle Focus on Quest")
      tt:AddLine(icon .. "More")
      tt:Show()
      registry.cbs["QuestMapLogTitleButton.OnEnter"](button, 9)
      assert.are.equal(QUEST.title, _G.GameTooltipTextLeft1:GetText())
      assert.are.equal(icon .. "クエストへのフォーカスを切り替え", _G.GameTooltipTextLeft2:GetText())
      assert.are.equal(icon .. "その他", _G.GameTooltipTextLeft3:GetText())
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      assert.are.equal(icon .. "Toggle Focus on Quest", _G.GameTooltipTextLeft2:GetText())
      assert.are.equal(icon .. "More", _G.GameTooltipTextLeft3:GetText())
      Stub.keys.alt = false; WFJ.Modifier.refresh()
      assert.are.equal(icon .. "クエストへのフォーカスを切り替え", _G.GameTooltipTextLeft2:GetText())
    end)
  end)

  describe("elite tags and content-tracking lines", function()
    it("the elite tag (PARENS_TEMPLATE of ELITE) on the list's title button; the title stays", function()
      Q.quests[9].elite = true
      Q.updateList()
      local b = Q.rows()[9]
      assert.are.equal("(エリート)", b.TagText:GetText())
      assert.are.equal("[20+] Burning Archives", b.Text:GetText())
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      assert.are.equal("(Elite)", b.TagText:GetText())
      Stub.keys.alt = false; WFJ.Modifier.refresh()
    end)

    it("the title button grows with a wrapped Japanese objective, and the list is laid out again",
      function()
        local contents = _G.QuestScrollFrame.Contents
        local function expected(b)
          local total = 8 + b.Text:GetHeight()
          for row in _G.QuestScrollFrame.objectiveFramePool:EnumerateActive() do
            if row.questID == 9 then total = total + row:GetHeight() + 3 end
          end
          return total + 6
        end
        local before = contents.layouts
        Q.updateList()
        local b = Q.rows()[9]
        local english = 8 + b.Text:GetHeight() + 6
        for _, line in ipairs(Q.quests[9].leaderboard) do
          english = english + Stub.textHeight(line.text, { path = "Fonts\\FRIZQT__.TTF", size = 13 }, 200) + 3
        end
        assert.are_not.equal(english, b:GetHeight()) -- the Japanese rows are taller
        assert.are.equal(expected(b), b:GetHeight())
        assert.are.equal(before + 1, contents.layouts) -- once for the whole update
        Stub.keys.alt = true; WFJ.Modifier.refresh()
        assert.are.equal(english, b:GetHeight())
        assert.are.equal(expected(b), b:GetHeight())
        Stub.keys.alt = false; WFJ.Modifier.refresh()
        assert.are.equal(expected(b), b:GetHeight())
      end)

    it("a count with thousands separators is split and kept", function()
      local ns = {}
      H.loadPure("Core/Objectives.lua", nil, ns)
      assert.are.same({ "0/1,200 ", "Archive Burned", "" }, { ns.Objectives.split("0/1,200 Archive Burned") })
      assert.are.same({ "", "Archive Burned", ": 1,200/1,200" }, { ns.Objectives.split("Archive Burned: 1,200/1,200") })
      Q.quests[9].leaderboard = { { text = "1,200/1,200 Archive Burned" }, { text = "0/1,200 Kobold Vermin slain" } }
      local _, lines = trackerLines()
      assert.are.equal("1,200/1,200 Archiveを焼き払う", lines[1].Text:GetText())
      assert.are.equal("Kobold Verminを倒す: 0/1,200", lines[2].Text:GetText())
    end)

    it("the title tooltip's QUEST_DASH objective lines: the dash kept, the objective in Japanese",
      function()
      _G.QUEST_DASH = "- "
      local tt, button = _G.GameTooltip, CreateFrame("Button")
      tt:SetOwner(button, "ANCHOR_RIGHT")
      tt:AddLine(QUEST.title)
      tt:AddLine("- 3/10 Kobold Vermin slain")
      tt:AddLine("- 0/1 Archive Burned")
      tt:AddLine("- Find the lost relic")
      tt:AddLine("<Click to view Quest Details>")
      tt:Show()
      registry.cbs["QuestMapLogTitleButton.OnEnter"](button, 9)
      assert.are.equal(QUEST.title, _G.GameTooltipTextLeft1:GetText())
      assert.are.equal("- Kobold Verminを倒す: 3/10", _G.GameTooltipTextLeft2:GetText())
      assert.are.equal("- 0/1 Archiveを焼き払う", _G.GameTooltipTextLeft3:GetText())
      assert.are.equal("- Find the lost relic", _G.GameTooltipTextLeft4:GetText())
      assert.are.equal("<クリックでクエストの詳細を表示>", _G.GameTooltipTextLeft5:GetText())
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      assert.are.equal("- 3/10 Kobold Vermin slain", _G.GameTooltipTextLeft2:GetText())
      Stub.keys.alt = false; WFJ.Modifier.refresh()
      assert.are.equal("- 0/1 Archiveを焼き払う", _G.GameTooltipTextLeft3:GetText())
      tt:Hide()
      assert.are.equal("- 0/1 Archive Burned", _G.GameTooltipTextLeft3:GetText())
      _G.QUEST_DASH = nil
    end)

    it("the content-tracking block's client lines translate; its header (the tracked thing's name) and the "
      .. "server's objective text stay", function()
        -- AdventureObjectiveTracker (blizzard_adventureobjectivetracker.lua:139–180): GetBlock, SetHeader(title),
        -- AddObjective(1, …) and AddObjective(2, …) per ProcessTrackingEntry
        local module = CreateFrame("Frame", "AdventureObjectiveTracker")
        module.usedBlocks = {}
        function module.GetBlock(mod, id)
          local block = mod.usedBlocks[id]
          if not block then
            block = { id = id, HeaderText = Stub.fontString(""), usedLines = {}, height = 0 }
            function block:SetHeader(text) self.HeaderText.text = text; self.height = self.HeaderText:GetHeight() end
            function block:SetHeight(h) self.laidOut = h end
            function block:AddObjective(key, text)
              local line = self.usedLines[key]
              if not line then
                line = { Text = Stub.fontString("") }
                line.Text.width = 120
                function line.SetHeight(l, h) l.h = h end
                function line.GetHeight(l) return l.h end
                self.usedLines[key] = line
              end
              line.parentBlock, line.used = self, true
              line.Text.text = text
              line:SetHeight(line.Text:GetHeight())
              self.height = self.height + line:GetHeight()
              return line
            end
            mod.usedBlocks[id] = block
          end
          return block
        end
        function module.GetExistingBlock(mod, id) return mod.usedBlocks[id] end
        function module:Process(id, title, first, second) -- ProcessTrackingEntry's writes
          local block = self:GetBlock(id)
          block:SetHeader(title)
          block:AddObjective(1, first)
          if second then block:AddObjective(2, second) end
          block:SetHeight(block.height)
          return block
        end
        WFJ.QuestMap.hookTrackers()
        local block = module:Process(1001, "Elite", _G.CONTENT_TRACKING_RETRIEVING_INFO)
        assert.are.equal("|cffff0000情報を取得中...|r", block.usedLines[1].Text:GetText())
        assert.are.equal("Elite", block.HeaderText:GetText()) -- a tracked thing named like a dictionary word
        block = module:Process(1001, "Hogger", "Defeat Hogger", _G.CONTENT_TRACKING_LOCATION_UNAVAILABLE)
        assert.are.equal("Defeat Hogger", block.usedLines[1].Text:GetText())
        assert.are.equal("|cffff0000場所が不明です|r", block.usedLines[2].Text:GetText())
        block = module:Process(1001, "Hogger", "Defeat Hogger", _G.CONTENT_TRACKING_ROUTE_UNAVAILABLE)
        assert.are.equal("|cffff0000経路が不明です|r", block.usedLines[2].Text:GetText())
        block = module:Process(1001, "Hogger", "Defeat Hogger", "Elwynn Forest. Near the lake. (Optional)")
        assert.are.equal("Elwynn Forest. Near the lake.(任意)", block.usedLines[2].Text:GetText())
        Stub.keys.alt = true; WFJ.Modifier.refresh()
        assert.are.equal("Elwynn Forest. Near the lake. (Optional)", block.usedLines[2].Text:GetText())
        Stub.keys.alt = false; WFJ.Modifier.refresh()
        _G.AdventureObjectiveTracker = nil
      end)
  end)

  describe("the tracker's Quests header on a fresh launch", function()
    it("a font the client refuses at load is applied by the retry (as a real /wfj debug showed: 1 failure, 0 pending)",
      function()
        -- the module's OnLoad wrote "Quests" before the addon loaded; the bundled font file is not ready yet
        Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc") -- a fresh client: nothing shown yet
        Stub.installQuestAPI(); Stub.installTooltipAPI()
        QStub.install()
        Stub.fontSetFails = true
        local W = H.loadChunks(FILES)
        H.uiSetup(W, UI)
        W.QuestMap.init()
        local header = _G.QuestObjectiveTracker.Header.Text
        assert.are.equal("クエスト", header:GetText())
        assert.are_not.equal(W.Font.PATH, (header:GetFont()))
        assert.is_true(W.Render.pendingFonts() > 0)
        Stub.fontSetFails = false
        W.Render.retryFonts()
        assert.are.equal(W.Font.PATH, (header:GetFont()))
        assert.are.equal(0, W.Render.pendingFonts())
      end)
  end)

  describe("Core/Objectives is pure", function()
    it("loads under an empty environment and splits the count on either side", function()
      local ns = {}
      H.loadPure("Core/Objectives.lua", nil, ns)
      assert.are.same({ "3/10 ", "Kobold Vermin slain", "" }, { ns.Objectives.split("3/10 Kobold Vermin slain") })
      assert.are.same({ "", "Archive Burned", ": 0/1" }, { ns.Objectives.split("Archive Burned: 0/1") })
      assert.are.same({ "", "Rescue Drull", "" }, { ns.Objectives.split("Rescue Drull") })
    end)
  end)
end)
