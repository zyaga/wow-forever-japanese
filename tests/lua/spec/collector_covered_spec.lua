-- Core/Collector: a line counts, is sent and is kept only while the addon cannot show it in Japanese; NPC names are
-- kept for the English store but never counted; prune drops what a newer addon covers.
local H = require("tests.lua.spec.helpers")

local PLAYER = { name = "Reyn", class = "Hunter", race = "Night Elf" }

local function loadCollector()
  H.coreStub()
  local ns = H.loadChunks({ "Core/Const.lua", "Core/Normalize.lua", "Core/Hash.lua", "Core/State.lua",
    "Core/Settings.lua" })
  H.loadPure("Core/Collector.lua", nil, ns)
  return ns
end

describe("Core/Collector covered lines", function()
  local WFJ, C, shipped, aligned, alignCalls

  -- `aligned(entry, lines)` stands in for the addon's align gate (Main wires WFJ.Align)
  local function deps(o)
    o = o or {}
    local d = {
      enabled = function() return true end,
      lookup = o.lookup or function(kind, id) return shipped[kind] and shipped[kind][id] end,
      player = function() return PLAYER end,
      build = function() return "1.60.1.70338" end,
      print = function() end,
      aligns = function(entry, lines)
        alignCalls[#alignCalls + 1] = { entry = entry, lines = lines }
        return aligned(entry, lines)
      end,
    }
    if o.noAligns then d.aligns = nil end
    return d
  end

  local function h1Of(e)
    return (WFJ.Hash.h32x2(WFJ.Normalize.v1(e)))
  end

  local function keysOf(list)
    local out = {}
    for i, item in ipairs(list) do out[i] = item.key end
    return out
  end

  local function entry(t, i, f, e, p)
    local h1, h2 = WFJ.Hash.h32x2(WFJ.Normalize.v1(e))
    return { t = t, i = i, f = f, h = WFJ.Hash.hex8(h1) .. WFJ.Hash.hex8(h2), e = e, b = 1, p = p }
  end

  local function saved(list, sent)
    local entries = {}
    for _, e in ipairs(list) do entries[e.t .. ":" .. e.i .. ":" .. e.f] = e end
    return { version = 1, builds = { "1.60.1.70291" }, entries = entries, sent = sent or {} }
  end

  before_each(function()
    WFJ = loadCollector()
    C = WFJ.Collector
    shipped, alignCalls = {}, {}
    aligned = function() return false end
  end)

  describe("tooltips", function()
    it("a description with its numbers filled in is known when the shipped Japanese aligns with it", function()
      local db = C.load(nil, deps())
      shipped["spell.description"] = { [5] = { ja = "$D1かけて体力を$N1回復します。", status = "u", h1 = 1 } }
      aligned = function(e, lines) return e.ja ~= nil and lines[1] == "Restores 70 health over 18 sec." end
      assert.are.equal("known", C.record("spell", 5, "description", "Restores 70 health over 18 sec."))
      assert.is_nil(db.entries["spell:5:description"])
      assert.are.same({ "Restores 70 health over 18 sec." }, alignCalls[1].lines)
    end)

    it("one whose Japanese does not align is recorded and counted; so is one with no Japanese", function()
      local db = C.load(nil, deps())
      shipped["item.description"] = { [9] = { ja = "x", status = "u", h1 = 1 } }
      assert.are.equal("recorded", C.record("item", 9, "description", "Use: Restores 58 health."))
      assert.are.equal("recorded", C.record("spell", 6, "aura", "Stunned."))
      assert.is_table(db.entries["item:9:description"])
      assert.are.equal(2, C.unsentCount())
    end)

    it("the align gate sees the recorded paragraphs, one line each", function()
      C.load(nil, deps())
      shipped["spell.aura"] = { [7] = { ja = "x", status = "u", h1 = 1 } }
      C.record("spell", 7, "aura", "First line.\nSecond line.")
      assert.are.same({ "First line.", "Second line." }, alignCalls[1].lines)
    end)

    it("an empty Japanese is no translation, and without an align gate nothing is covered", function()
      C.load(nil, deps())
      aligned = function() return true end
      shipped["spell.description"] = { [5] = { ja = "", status = "u", h1 = 1 } }
      assert.are.equal("recorded", C.record("spell", 5, "description", "Restores 70 health."))
      C.load(nil, deps({ noAligns = true }))
      shipped["spell.description"][5].ja = "x"
      assert.are.equal("recorded", C.record("spell", 5, "description", "Restores 70 health."))
    end)

    it("a stored tooltip line covered by the shipped data is not counted or sent", function()
      shipped["spell.description"] = { [5] = { ja = "x", status = "u", h1 = 1 } }
      aligned = function() return true end
      C.load(saved({ entry("spell", 5, "description", "Restores 70 health.") }), deps())
      assert.are.equal(0, C.unsentCount())
      local list, left = C.pending()
      assert.are.same({}, list)
      assert.are.equal(1, left)
    end)
  end)

  describe("quest lines with the class or race", function()
    it("a race the English writes literally (lowercase) is known for a player of that race", function()
      local db = C.load(nil, deps())
      shipped["quest.completion"] = { [747] = { ja = "x", status = ".",
        h1 = h1Of("The night elf of Narache thank you, $N.") } }
      assert.are.equal("known", C.record("quest", 747, "completion", "The night elf of Narache thank you, Reyn."))
      assert.is_nil(db.entries["quest:747:completion"])
    end)

    it("a stored $C line matches the class word as written or lowercased", function()
      shipped["quest.description"] = {
        [1] = { ja = "x", status = ".", h1 = h1Of("Find the Hunter trainer, $N.") },
        [2] = { ja = "x", status = ".", h1 = h1Of("Find the hunter trainer, $N.") },
        [3] = { ja = "x", status = ".", h1 = h1Of("Find the $C trainer, $N.") },
      }
      C.load(saved({
        entry("quest", 1, "description", "Find the $C trainer, $N.", "Hunter|Night Elf"),
        entry("quest", 2, "description", "Find the $C trainer, $N.", "Hunter|Night Elf"),
        entry("quest", 3, "description", "Find the $C trainer, $N.", "Hunter|Night Elf"),
      }), deps())
      assert.are.equal(0, C.unsentCount())
    end)

    it("the class and the race are tried apart: one literal, the other a token", function()
      shipped["quest.description"] = { [4] = { ja = "x", status = ".",
        h1 = h1Of("A young $R, a wise hunter.") } }
      C.load(saved({ entry("quest", 4, "description", "A young $R, a wise $C.", "Hunter|Night Elf") }), deps())
      assert.are.equal(0, C.unsentCount())
    end)

    it("a line filled from live values matches its masked hash with the race written out", function()
      local norm = C.mask(WFJ.Normalize.v1("Bring me 10 night elf tails."))
      shipped["quest.objectives"] = { [8] = { ja = "$N1本", status = ".", h1 = (WFJ.Hash.h32x2(norm)) } }
      C.load(nil, deps())
      assert.are.equal("known", C.record("quest", 8, "objectives", "Bring me 7 night elf tails."))
    end)

    it("a reworded line stays recorded and counted", function()
      shipped["quest.description"] = { [922] = { ja = "x", status = ".",
        h1 = h1Of("He walks the Cenarion Enclave, $N.") } }
      local db = C.load(nil, deps())
      assert.are.equal("recorded", C.record("quest", 922, "description", "He walks the Cenarian Enclave, Reyn."))
      assert.is_table(db.entries["quest:922:description"])
      assert.are.equal(1, C.unsentCount())
    end)

    it("a word the recorder's class or race only spells (no p) gets no literal forms", function()
      shipped["quest.description"] = { [5] = { ja = "x", status = ".", h1 = h1Of("Find the hunter trainer, $N.") } }
      C.load(saved({ entry("quest", 5, "description", "Find the $C trainer, $N.") }), deps())
      assert.are.equal(1, C.unsentCount())
    end)
  end)

  describe("NPC names", function()
    it("are recorded but never counted, and go only with another line", function()
      local db = C.load(nil, deps())
      assert.are.equal("recorded", C.recordNpc("Creature-0-0-0-0-3100-0000000000", "Senani Thunderheart"))
      assert.is_table(db.entries["npc:3100:name"])
      assert.are.equal(0, C.unsentCount())
      assert.are.equal(0, C.status().unsent)
      local list, left, _, names = C.pending()
      assert.are.same({}, list)
      assert.are.equal(0, left)
      assert.are.equal(0, names)
      C.record("quest", 3, "title", "Still English")
      list, left, _, names = C.pending()
      assert.are.same({ "npc:3100:name", "quest:3:title" }, keysOf(list))
      assert.are.equal(0, left)
      assert.are.equal(1, names)
      assert.are.equal(1, C.unsentCount())
    end)

    it("send all carries them", function()
      C.load(nil, deps())
      C.recordNpc("Creature-0-0-0-0-3100-0000000000", "Senani Thunderheart")
      local list, _, _, names = C.pending(true)
      assert.are.same({ "npc:3100:name" }, keysOf(list))
      assert.are.equal(1, names)
    end)
  end)

  describe("gossip", function()
    it("is unchanged: known under any candidate key, else recorded and counted", function()
      local db = C.load(nil, deps())
      assert.are.equal("recorded", C.recordGossip("Hello there, traveler.", nil))
      assert.are.equal(1, C.unsentCount())
      shipped.gossip = { [C.key("Hello there, traveler.", PLAYER)] = { ja = "やあ。", status = "." } }
      assert.are.equal(0, C.unsentCount())
      shipped.gossip[C.key("Good day, Reyn.", PLAYER)] = { ja = "こんにちは。", status = "." }
      assert.are.equal("known", C.recordGossip("Good day, Reyn.", nil))
      assert.is_nil(db.entries["gossip:" .. C.key("Good day, Reyn.", PLAYER) .. ":text"])
    end)
  end)

  describe("prune", function()
    local covered, reworded, npc, tooltip, coveredTip

    before_each(function()
      covered = entry("quest", 2, "title", "Sharptalon's Claw")
      reworded = entry("quest", 922, "description", "He walks the Cenarian Enclave, $N.")
      npc = entry("npc", 3100, "name", "Senani Thunderheart")
      tooltip = entry("item", 9, "description", "Use: Restores 58 health.")
      coveredTip = entry("spell", 5, "description", "Restores 70 health.")
      shipped["quest.title"] = { [2] = { ja = "x", status = ".", h1 = h1Of("Sharptalon's Claw") } }
      shipped["quest.description"] = { [922] = { ja = "x", status = ".",
        h1 = h1Of("He walks the Cenarion Enclave, $N.") } }
      shipped["spell.description"] = { [5] = { ja = "x", status = "u", h1 = 1 } }
      aligned = function(e) return e == shipped["spell.description"][5] end
    end)

    it("drops covered entries and their sent rows, keeps the rest, and recounts the bytes", function()
      local db = C.load(saved({ covered, reworded, npc, tooltip, coveredTip },
        { ["quest:2:title"] = covered.h, ["npc:3100:name"] = npc.h }), deps())
      assert.are.equal(2, C.prune())
      local keys = {}
      for k in pairs(db.entries) do keys[#keys + 1] = k end
      table.sort(keys)
      assert.are.same({ "item:9:description", "npc:3100:name", "quest:922:description" }, keys)
      assert.are.same({ ["npc:3100:name"] = npc.h }, db.sent)
      local want = C.sentSize("npc:3100:name")
      for k, e in pairs(db.entries) do want = want + C.size(k, e.e, e.n, e.p) end
      assert.are.equal(want, db.bytes)
      assert.is_false(C.onDisk("quest:2:title", covered.h))
      assert.is_true(C.onDisk("item:9:description", tooltip.h))
      assert.are.equal(0, C.prune())
    end)

    it("never touches a file from a newer version", function()
      local file = saved({ covered })
      file.version = 2
      C.load(file, deps())
      assert.are.equal(0, C.prune())
      assert.is_table(file.entries["quest:2:title"])
    end)

    it("keeps an entry whose check fails with an error", function()
      local db = C.load(saved({ covered, coveredTip }), deps({ lookup = function(kind, id)
        if kind == "quest.title" then error("broken row") end
        return shipped[kind] and shipped[kind][id]
      end }))
      assert.are.equal(1, C.prune())
      assert.is_table(db.entries["quest:2:title"])
      assert.is_nil(db.entries["spell:5:description"])
    end)

    it("before load, nothing to prune", function()
      assert.are.equal(0, C.prune())
    end)
  end)

  it("Main wires the align gate and prunes after the UI index is built", function()
    local src = H.readFile("addon/WoWForeverJapanese/Main.lua")
    local index = src:find('step("uiindex"', 1, true)
    local prune = src:find('step("collectorprune"', 1, true)
    assert.is_number(index)
    assert.is_number(prune)
    assert.is_true(prune > index)
    assert.is_truthy(src:find("aligns = ", 1, true))
  end)
end)
