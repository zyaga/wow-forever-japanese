-- UI/Gossip's quest rows: an offered or active quest row in the NPC talk window shows its quest's Japanese title by
-- the row's quest id, through UI/QuestMap's title helper, and a released row lets go of that title's record. The
-- client is replayed by gossip_client.lua (offered quests get ids 101.., active ones 201..).
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for _, f in ipairs(H.UI_FILES) do FILES[#FILES + 1] = f end
FILES[#FILES + 1] = "UI/QuestMap.lua"
FILES[#FILES + 1] = "UI/Gossip.lua"

local PLAYER = { name = "Reyn", class = "Hunter", race = "Night Elf" }
local NPC = { name = "Innkeeper Allison", guid = "Creature-0-4372-0-17-6740-0000A1B2C3" }

local TITLES = { [101] = { ja = "狼の毛皮", status = "." }, [201] = { ja = "失われた書物", status = "." } }
local LOG = { [201] = "The Lost Tome" } -- an offered quest is not in the log

describe("UI/Gossip: quest rows", function()
  local WFJ, SS, sb

  local function key(en) return WFJ.Collector.key(en, PLAYER) end

  local function rowsOf(kind)
    local out = {}
    for _, i in ipairs(sb:visibleIndices()) do
      if sb.frames[i].kind == kind then out[#out + 1] = sb.frames[i] end
    end
    return out
  end

  local function titleRecords()
    local n = 0
    for k in pairs(SS.records("gossip")) do if k:find("^title%.") then n = n + 1 end end
    return n
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installGossipAPI(12)
    _G.C_QuestLog = { GetTitleForQuestID = function(id) return LOG[id] end }
    WFJ = H.loadChunks(FILES)
    SS = WFJ.SurfaceState
    WFJ.Compat.init(function(name) return _G[name] end)
    WFJ.Settings.load(nil, 1, {})
    local function lookup(kind, id) if kind == "quest.title" then return TITLES[id] end end
    WFJ.Collector.load(nil, H.collectorDeps({ lookup = lookup }))
    WFJ.Render.init(WFJ.Translator.new({
      enabled = function() return WFJ.State.enabled end,
      areaEnabled = WFJ.State.areaEnabled,
      modifierHeld = WFJ.Modifier.isDown,
      lookup = lookup,
      marker = function(n) return WFJ.Settings.get("marker." .. n) end,
    }))
    WFJ.QuestMap.init() -- declares the quest log API the title helper reads (Main runs it at load)
    assert.is_true(WFJ.Gossip.init({ key = key }))
    sb = GossipFrame.GreetingPanel.ScrollBox
  end)

  after_each(function()
    _G.C_QuestLog = nil
    Stub.keys.alt = false
  end)

  it("offered and active rows show their quest's Japanese title inside the row colour; Alt shows the English",
    function()
      Stub.showGossip({ text = "Hail.", npc = NPC, available = { "Wolf Pelts", "Untranslated Errand" },
        active = { "The Lost Tome" } })
      local available, active = rowsOf("available"), rowsOf("active")
      assert.are.equal("|cff000000狼の毛皮|r", available[1]:GetText())
      assert.are.equal("|cff000000Untranslated Errand|r", available[2]:GetText())
      assert.are.equal("|cff000000失われた書物|r", active[1]:GetText())
      assert.are.equal(WFJ.Font.PATH, (available[1]:GetFontString():GetFont()))
      assert.is_table(SS.get("gossip", "title.101"))
      assert.is_table(SS.get("gossip", "title.201"))
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      assert.are.equal("|cff000000Wolf Pelts|r", available[1]:GetText())
      assert.are.equal("|cff000000The Lost Tome|r", active[1]:GetText())
      Stub.keys.alt = false; WFJ.Modifier.refresh()
      assert.are.equal("|cff000000狼の毛皮|r", available[1]:GetText())
    end)

  it("a released row drops its title's record; a row taken from the pool again shows its quest afresh", function()
    Stub.showGossip({ text = "Hail.", npc = NPC, available = { "Wolf Pelts" }, active = { "The Lost Tome" } })
    assert.are.equal(2, titleRecords())
    -- a new page while open: every row is released (the quest rows go back to their pools)
    Stub.showGossip({ text = "Hail.", npc = NPC, options = { "Goodbye." } })
    assert.are.equal(0, titleRecords())
    assert.are.equal(0, #rowsOf("available"))
    Stub.showGossip({ text = "Hail.", npc = NPC, available = { "Wolf Pelts" } })
    assert.are.equal(1, titleRecords())
    assert.are.equal("|cff000000狼の毛皮|r", rowsOf("available")[1]:GetText())
  end)

  it("a row for a quest with no title anywhere is left as the client wrote it", function()
    LOG[201] = nil
    Stub.showGossip({ text = "Hail.", npc = NPC, active = { "" } })
    assert.are.equal("|cff000000|r", rowsOf("active")[1]:GetText())
    assert.are.equal(0, titleRecords())
    LOG[201] = "The Lost Tome"
  end)
end)
