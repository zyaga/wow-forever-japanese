-- Core/Collector: known / changed / unknown, dedupe, privacy text, own output, cap, NPC ids, load.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local Loader = require("tests.lua.spec.loader")

local PLAYER = { name = "Reyn", class = "Hunter", race = "Night Elf" }

-- Core/Collector under the std-lib-only environment, on top of the (pure) modules it reads.
local function loadCollector()
  H.coreStub()
  local ns = H.loadChunks({ "Core/Const.lua", "Core/Normalize.lua", "Core/Hash.lua", "Core/State.lua",
    "Core/Settings.lua" })
  H.loadPure("Core/Collector.lua", nil, ns)
  return ns
end

describe("Core/Collector", function()
  local WFJ, C, prints, shipped, on, player, lookups

  local function deps()
    return {
      enabled = function() return on end,
      lookup = function(kind, id)
        lookups[#lookups + 1] = { kind, id }
        return shipped[kind] and shipped[kind][id]
      end,
      player = function() return player end,
      build = function() return "1.15.9.69722" end,
      print = function(msg) prints[#prints + 1] = msg end,
    }
  end

  local function h1Of(e)
    return (WFJ.Hash.h32x2(WFJ.Normalize.v1(e)))
  end

  before_each(function()
    WFJ = loadCollector()
    C = WFJ.Collector
    prints, shipped, on, player, lookups = {}, {}, true, PLAYER, {}
  end)

  it("loads under a std-lib-only environment and defines collector.enabled", function()
    local d = WFJ.Settings.list()
    assert.are.equal("collector.enabled", d[#d].id)
    assert.are.equal("boolean", d[#d].kind)
    assert.is_true(d[#d].default)
    assert.is_nil(d[#d].hidden)
    assert.are.equal(4 * 1024 * 1024, C.CAP_BYTES)
  end)

  -- the quest live check's fingerprints are the h1 of the Collector.keys candidates.
  describe("fingerprints", function()
    local function h1OfKey(k) return tonumber(k:sub(1, 8), 16) end

    it("equals the h1 of each distinct candidate key, in the same order", function()
      for _, raw in ipairs({ "Well done, Reyn. Take this.", "Good hunting, young hunter.", "Hello there!",
        "Reyn, the Night Elf hunter tower awaits." }) do
        local keys, fps = C.keys(raw, PLAYER), C.fingerprints(raw, PLAYER)
        assert.are.equal(#keys, #fps, raw)
        for i, k in ipairs(keys) do
          assert.are.equal(h1OfKey(k), fps[i], raw)
          local p = ({ PLAYER, { name = PLAYER.name }, nil })[i]
          if #keys == 3 then assert.are.equal(h1Of(C.text(raw, p)), fps[i], raw) end
        end
      end
    end)

    it("a line with the race as a token and the class word literal matches (quest 458's turn-in)", function()
      local fps = C.fingerprints("I see you found me, young night elf. A wise hunter sent you.", PLAYER)
      local want = h1Of("I see you found me, young $R. A wise hunter sent you.")
      local found = false
      for _, h in ipairs(fps) do found = found or h == want end
      assert.is_true(found)
    end)

    it("lowercase class text matches the $c template's hash (quest 456's \"young druid\")", function()
      local fps = C.fingerprints("Journey forth, young hunter.", PLAYER)
      assert.are.equal(h1Of("Journey forth, young $c."), fps[1])
    end)

    it("a short name in the text adds its candidates and reports the comparison inconclusive", function()
      local jo = { name = "Jo", class = "Hunter", race = "Night Elf" }
      local fps, inconclusive = C.fingerprints("Well done, Jo.", jo)
      assert.is_true(inconclusive)
      assert.are.equal(h1Of("Well done, $N."), fps[#fps]) -- the short-name candidate matches the $N template
      assert.are.same({ fps[1] }, { h1Of("Well done, Jo.") }) -- the literal text is still the first candidate
      local other, inc2 = C.fingerprints("Well done, hunter.", jo) -- not in the text: compared, conclusive
      assert.are.equal(2, #other); assert.is_nil(inc2)
      local _, memoInc = C.fingerprints("Well done, Jo.", jo) -- the memo keeps the flag
      assert.is_true(memoInc)
      local _, long = C.fingerprints("Well done, Reyn.", PLAYER)
      assert.is_nil(long)
    end)

    it("memoizes per player and text, and drops the memo at MEMO_MAX", function()
      local a = C.fingerprints("Hello there, Reyn.", PLAYER)
      assert.are.equal(a, C.fingerprints("Hello there, Reyn.", PLAYER)) -- same table: no second hash pass
      assert.are_not.equal(a, C.fingerprints("Hello there, Reyn.", { name = "Reyn", class = "Mage", race = "Human" }))
      for i = 1, C.MEMO_MAX do C.fingerprints("Line " .. i, PLAYER) end
      local b = C.fingerprints("Hello there, Reyn.", PLAYER)
      assert.are_not.equal(a, b)
      assert.are.same(a, b)
    end)

    it("a call before the player is known is not memoized: the same text fingerprints once they are", function()
      assert.are.same({}, C.fingerprints("Well done, Reyn.", { name = "Reyn" }))
      assert.are.equal(2, #C.fingerprints("Well done, Reyn.", PLAYER)) -- name replaced · nothing replaced
    end)

    it("no fingerprints for empty text or a player not known yet", function()
      assert.are.same({}, C.fingerprints(nil, PLAYER))
      assert.are.same({}, C.fingerprints("", PLAYER))
      assert.are.same({}, C.fingerprints("Hello.", nil))
      assert.are.same({}, C.fingerprints("Hello.", { name = "Reyn", class = "Hunter" }))
      assert.are.same({}, C.fingerprints("Hello.", { name = "", class = "Hunter", race = "Night Elf" }))
    end)
  end)

  describe("known / changed / unknown", function()
    it("a quest field whose shipped h1 matches the live English is known and not written", function()
      local db = C.load(nil, deps())
      shipped["quest.title"] = { [2] = { ja = "x", status = ".", h1 = h1Of("Sharptalon's Claw") } }
      assert.are.equal("known", C.record("quest", 2, "title", "Sharptalon's Claw"))
      assert.are.same({ { "quest.title", 2 } }, lookups)
      assert.is_nil(next(db.entries))
      assert.are.equal(0, db.bytes)
    end)

    it("a different shipped h1 (changed) and no row (unknown) are recorded", function()
      local db = C.load(nil, deps())
      shipped["quest.description"] = { [2] = { ja = "x", status = ".", h1 = 12345 } }
      assert.are.equal("recorded", C.record("quest", 2, "description", "Kill Sharptalon."))
      assert.are.equal("recorded", C.record("quest", 3, "completion", "Well done."))
      local e = db.entries["quest:2:description"]
      assert.are.same({ t = "quest", i = 2, f = "description", h = WFJ.Hash.key("Kill Sharptalon."),
        e = "Kill Sharptalon.", b = 1 }, e)
      assert.are.same({ "1.15.9.69722" }, db.builds)
      assert.are.equal(C.size("quest:2:description", "Kill Sharptalon.") + C.size("quest:3:completion", "Well done."),
        db.bytes)
    end)

    it("items and spells look up field-qualified (spell has two fields); NPCs look nothing up", function()
      C.load(nil, deps())
      C.record("item", 117, "description", "Use: Restores 61 health over 18 sec.")
      C.record("spell", 17, "description", "Absorbs 44 damage.")
      C.record("npc", 3100, "name", "Senani Thunderheart")
      assert.are.same({ { "item.description", 117 }, { "spell.description", 17 } }, lookups)
    end)

    it("off when the setting is off or before load", function()
      assert.are.equal("off", C.record("quest", 2, "title", "Before load"))
      local db = C.load(nil, deps())
      on = false
      assert.are.equal("off", C.record("quest", 2, "title", "Sharptalon's Claw"))
      assert.is_nil(next(db.entries))
    end)

    it("refuses bad kinds, fields, ids and empty text", function()
      C.load(nil, deps())
      assert.are.same({ "refused", "bad_kind" }, { C.record("gossip", 2, "text", "Hi") }) -- recordGossip only
      assert.are.same({ "refused", "bad_kind" }, { C.record("quest", 2, "name", "Hi") })
      assert.are.same({ "refused", "bad_id" }, { C.record("quest", 0, "title", "Hi") })
      assert.are.same({ "refused", "bad_id" }, { C.record("quest", 2.5, "title", "Hi") })
      assert.are.same({ "refused", "empty" }, { C.record("quest", 2, "title", "") })
      assert.are.same({ "refused", "empty" }, { C.record("quest", 2, "title", nil) })
      assert.are.same({ "refused", "empty" }, { C.record("quest", 2, "title", "|cffffffff|r  ") })
    end)
  end)

  describe("dedupe and replace", function()
    it("the same key and text is seen, in this session and after a reload of the saved table", function()
      local db = C.load(nil, deps())
      assert.are.equal("recorded", C.record("quest", 2, "progress", "Did you get it?"))
      local bytes = db.bytes
      assert.are.equal("seen", C.record("quest", 2, "progress", "Did  you get it? "))
      assert.are.equal(bytes, db.bytes)
      local again = C.load(db, deps())
      assert.are.equal("seen", C.record("quest", 2, "progress", "Did you get it?"))
      assert.are.equal(bytes, again.bytes)
    end)

    it("a changed text for the same key replaces the entry and adjusts bytes", function()
      local db = C.load(nil, deps())
      C.record("quest", 2, "progress", "Did you get it?")
      assert.are.equal("replaced", C.record("quest", 2, "progress", "Did you get the claw yet?"))
      local n = 0
      for _ in pairs(db.entries) do n = n + 1 end
      assert.are.equal(1, n)
      assert.are.equal("Did you get the claw yet?", db.entries["quest:2:progress"].e)
      assert.are.equal(C.size("quest:2:progress", "Did you get the claw yet?"), db.bytes)
    end)
  end)

  describe("privacy text and hash parity", function()
    it("Normalize.v1 of the stored text hashes to every shared vector's key", function()
      for _, c in ipairs(H.vectors().cases) do
        local e = C.text(c.raw, c.player)
        if c.id == "player-04" then
          -- "A hunter walks in.": quest text also restores the lowercase class (lowercase $c)
          assert.are.equal("A $C walks in. $C, greetings.", e)
        else
          assert.are.equal(c.key, WFJ.Hash.key(WFJ.Normalize.v1(e)), c.id)
        end
      end
    end)

    it("lowercase $c / $r text matches pfQuest's English, so quest 456 is known (found in-game)", function()
      local druid = { name = "Reyn", class = "Druid", race = "Night Elf" }
      local pfquest = "Greetings, $N.  I am Conservator Ilthalaine.$b$bUnfortunately, the nightsaber and thistle "
        .. "boar populations grew too large.  Journey forth, young $c, and thin the boar and saber populations. "
        .. "Go, $r."
      local live = "Greetings, Reyn.  I am Conservator Ilthalaine.\n\nUnfortunately, the nightsaber and thistle "
        .. "boar populations grew too large.  Journey forth, young druid, and thin the boar and saber populations. "
        .. "Go, night elf."
      local e = C.text(live, druid)
      assert.is_truthy(e:find("young $C, and thin", 1, true))
      assert.is_truthy(e:find("Go, $R.", 1, true))
      assert.are.equal(WFJ.Hash.key(WFJ.Normalize.v1(pfquest)), WFJ.Hash.key(WFJ.Normalize.v1(e)))
      local d = deps()
      player = druid
      local h1 = WFJ.Hash.h32x2(WFJ.Normalize.v1(pfquest))
      shipped["quest.description"] = { [456] = { ja = "x", status = ".", h1 = h1 } }
      C.load(nil, d)
      assert.are.equal("known", C.record("quest", 456, "description", live))
      -- item / spell text keeps lowercase words: only quest text carries $c / $r
      assert.are.equal("recorded", C.record("spell", 9, "description", "Shapeshift into a druid form."))
    end)

    it("writes Blizzard's tokens: $N/$C/$R for the player, $B$B between paragraphs, markup stripped", function()
      local e = C.text("Well met, Reyn.\n\nThe |cffffd200Hunter|r of the Night Elf.$BGo.|nNow.", PLAYER)
      assert.are.equal("Well met, $N.$B$BThe $C of the $R.$B$BGo.$B$BNow.", e)
      local db = C.load(nil, deps())
      C.record("quest", 9, "description", "Well met, Reyn.\n\n  The Hunter awaits.\n")
      assert.are.equal("Well met, $N.$B$BThe $C awaits.", db.entries["quest:9:description"].e)
      -- a $C / $R line names the recording character, so the pipeline knows whose word the token was
      assert.are.equal("Hunter|Night Elf", db.entries["quest:9:description"].p)
      C.record("quest", 10, "description", "Well met, Reyn.")
      assert.is_nil(db.entries["quest:10:description"].p) -- no class or race token: nothing more stored
      -- the file reloads with it, and the byte count includes it
      local again = C.load(db, deps())
      assert.are.equal("Hunter|Night Elf", again.entries["quest:9:description"].p)
    end)

    it("a break inside a link label never splits the link", function()
      assert.are.equal("Take [Linen$B$BCloth] home.", C.text("Take |Hitem:2589|h[Linen|nCloth]|h home.", nil))
    end)

    it("refuses the player's name in item, spell and NPC text instead of substituting it", function()
      local db = C.load(nil, deps())
      player = { name = "Guard", class = "Warrior", race = "Human" }
      assert.are.same({ "refused", "own_name" }, { C.record("npc", 68, "name", "Stormwind City Guard") })
      assert.are.same({ "refused", "own_name" }, { C.record("spell", 1, "description", "Calls a Guard to aid you.") })
      assert.are.equal("recorded", C.record("spell", 2, "description", "The Warrior strikes."))
      assert.are.equal("The Warrior strikes.", db.entries["spell:2:description"].e) -- class/race: quests only
    end)

    it("refuses a short name that normalize_v1 cannot replace (even next to markup) and an unknown player", function()
      C.load(nil, deps())
      player = { name = "Al", class = "Mage", race = "Human" }
      assert.are.same({ "refused", "short_name" }, { C.record("quest", 2, "completion", "Well done, Al.") })
      assert.are.same({ "refused", "short_name" }, { C.record("quest", 3, "completion", "|cffffffffAl|r here") })
      assert.are.equal("recorded", C.record("quest", 2, "title", "Also fine"))
      player = { name = "Reyn" } -- class/race not known yet: quest text would keep a literal class word
      assert.are.same({ "refused", "no_player" }, { C.record("quest", 5, "title", "Well met, Hunter") })
      assert.are.equal("recorded", C.record("spell", 5, "description", "Well met, Hunter"))
      player = {}
      assert.are.same({ "refused", "no_player" }, { C.record("quest", 4, "title", "Anything") })
    end)
  end)

  describe("our own output is never English", function()
    it("refuses kana, kanji-only and ideographic punctuation, marker messages anywhere, and bind-location text",
    function()
      local db = C.load(nil, deps())
      assert.are.same({ "refused", "own_text" }, { C.record("item", 117, "description", "18秒間でhealthを61回復。") })
      assert.are.same({ "refused", "own_text" }, { C.record("item", 118, "description", "使用: 攻撃力 +10") })
      assert.are.same({ "refused", "own_text" }, { C.record("item", 119, "description", "Use: Restores 5 health、") })
      for name, message in pairs(WFJ.MARKER) do
        assert.are.same({ "refused", "own_text" },
          { C.record("quest", 2, "title", "|cffffd100" .. message .. "|r\nSharptalon's Claw") }, name)
        assert.are.same({ "refused", "own_text" }, { C.record("quest", 3, "title", "Claw " .. message .. " ") }, name)
      end
      assert.are.same({ "refused", "skip" },
        { C.record("item", 6948, "description", "Use: Returns you to Goldshire. Speak to an Innkeeper.") })
      assert.are.same({ "refused", "skip" }, { C.record("spell", 556, "description", "Returns you to Goldshire.") })
      assert.are.same({ "refused", "skip" }, { C.record("spell", 8690, "description", "Returns you to Goldshire.") })
      assert.is_nil(next(db.entries))
    end)
  end)

  describe("cap", function()
    it("stops at the cap with one message per session; clear resumes", function()
      local db = C.load(nil, deps())
      C.CAP_BYTES = C.size("quest:1:title", "First") + 10
      assert.are.equal("recorded", C.record("quest", 1, "title", "First"))
      assert.are.equal("capped", C.record("quest", 2, "title", "Second"))
      assert.are.equal("capped", C.record("quest", 3, "title", "Third"))
      assert.is_nil(db.entries["quest:2:title"])
      assert.is_true(db.capped)
      assert.are.equal(1, #prints)
      assert.is_truthy(prints[1]:find("collector full", 1, true))
      assert.are.equal(1, C.clear())
      assert.is_false(db.capped)
      assert.are.equal("recorded", C.record("quest", 2, "title", "Second"))
    end)

    it("a later successful write clears the full flag; the size estimate counts escapes", function()
      local db = C.load(nil, deps())
      C.CAP_BYTES = C.size("quest:1:title", "A long first title") + 10
      C.record("quest", 1, "title", "A long first title")
      assert.are.equal("capped", C.record("quest", 2, "title", "Second"))
      assert.are.equal("replaced", C.record("quest", 1, "title", "Short"))
      assert.is_false(db.capped)
      assert.are.equal(C.size("k", 'a"b') - C.size("k", "ab"), 2)
    end)
  end)

  describe("NPCs", function()
    it("reduces a creature GUID to its id and nothing else", function()
      assert.are.equal(3100, C.creatureId("Creature-0-4372-0-17-3100-0000A1B2C3"))
      assert.are.equal(28670, C.creatureId("Vehicle-0-4372-571-2-28670-00002B4A1D"))
      assert.is_nil(C.creatureId("Player-4372-0ABCDEF1"))
      assert.is_nil(C.creatureId("Pet-0-4372-0-17-165189-0100C4F0D2"))
      assert.is_nil(C.creatureId("GameObject-0-4372-0-17-1617-00002B4A1D"))
      assert.is_nil(C.creatureId(nil))
      assert.is_nil(C.creatureId("garbage"))
    end)

    it("records the name under npc:<id>:name, never the GUID; refuses the player's own name", function()
      local db = C.load(nil, deps())
      assert.are.equal("recorded", C.recordNpc("Creature-0-4372-0-17-3100-0000A1B2C3", "Senani Thunderheart"))
      assert.are.equal("Senani Thunderheart", db.entries["npc:3100:name"].e)
      assert.are.same({ "refused", "own_name" }, { C.recordNpc("Creature-0-4372-0-17-99-0000A1B2C3", "Reyn") })
      assert.are.same({ "refused", "no_creature" }, { C.recordNpc("Player-4372-0ABCDEF1", "Someone") })
    end)
  end)

  describe("per-session memo", function()
    it("the same text for the same key answers without normalizing, hashing or looking up again", function()
      C.load(nil, deps())
      assert.are.equal("recorded", C.record("quest", 2, "title", "A title"))
      assert.are.equal("seen", C.record("quest", 2, "title", "A title"))
      assert.are.same({ "refused", "own_text" }, { C.record("quest", 3, "title", "日本語") })
      assert.are.same({ "refused", "own_text" }, { C.record("quest", 3, "title", "日本語") })
      assert.are.equal(1, #lookups)
      player = {}
      assert.are.same({ "refused", "no_player" }, { C.record("quest", 4, "title", "Later") })
      player = PLAYER -- a refusal that depends on state is not replayed
      assert.are.equal("recorded", C.record("quest", 4, "title", "Later"))
    end)

    it("without a client build nothing is recorded (an entry without one cannot be imported)", function()
      local d = deps()
      d.build = function() return nil end
      local db = C.load(nil, d)
      assert.are.same({ "refused", "no_build" }, { C.record("quest", 2, "title", "A title") })
      d.build = function() return "1.15 9" end -- would not be a valid `collector@<build>` source
      assert.are.same({ "refused", "no_build" }, { C.record("quest", 3, "title", "A title") })
      assert.is_nil(next(db.entries))
    end)
  end)

  describe("load", function()
    it("nil becomes a fresh version-1 dump", function()
      assert.are.same({ version = 1, disclosed = false, builds = {}, bytes = 0, capped = false, entries = {} },
        C.load(nil, deps()))
    end)

    it("resets non-table parts, drops invalid entries and recomputes bytes", function()
      local good = { t = "quest", i = 2, f = "title", h = "0123456789abcdef", e = "Title", b = 1 }
      local saved = {
        version = 1, bytes = 999999, capped = "yes", disclosed = true, builds = { "1.15.9.69722" },
        entries = {
          ["quest:2:title"] = good,
          ["quest:3:title"] = { t = "quest", i = 4, f = "title", h = "0123456789abcdef", e = "Wrong key" },
          ["quest:5:name"] = { t = "quest", i = 5, f = "name", h = "0123456789abcdef", e = "Bad field" },
          ["item:6:description"] = { t = "item", i = 6, f = "description", h = "XYZ", e = "Bad hash" },
          ["spell:7:description"] = { t = "spell", i = 7, f = "description", h = "0123456789abcdef", e = "" },
          ["spell:8:description"] = { t = "spell", i = 8, f = "description", h = "0123456789abcdef", e = "x", b = 9 },
          ["npc:9:name"] = { t = "npc", i = 9, f = "name", h = "0123456789abcdef", e = "x", realm = "Nope" },
        },
      }
      local db = C.load(saved, deps())
      assert.are.equal(saved, db)
      assert.are.same({ ["quest:2:title"] = good }, db.entries)
      assert.are.equal(C.size("quest:2:title", "Title"), db.bytes)
      assert.is_false(db.capped)
      assert.is_true(db.disclosed)
      local broken = C.load({ version = 1, entries = "nope", builds = 3 }, deps())
      assert.are.same({}, broken.entries)
      assert.are.same({}, broken.builds)
      -- a hole in a hand-edited builds list never moves an existing index
      local holed = C.load({ version = 1, builds = { [2] = "1.15.8.1" }, entries = {} }, deps())
      C.record("quest", 7, "title", "Seven")
      assert.are.equal("1.15.8.1", holed.builds[2])
      assert.are.equal("1.15.9.69722", holed.builds[holed.entries["quest:7:title"].b])
    end)

    it("a dump from a newer version is kept untouched and recording pauses", function()
      assert.is_true(C.load({ version = "2" }, deps()) ~= nil and C.status().readOnly)
      prints = {}
      local saved = { version = 2, entries = { anything = { kept = true } }, future = "field" }
      local db = C.load(saved, deps())
      assert.are.equal(saved, db)
      assert.are.same({ version = 2, entries = { anything = { kept = true } }, future = "field" }, db)
      assert.are.equal(1, #prints)
      assert.are.same({ "refused", "read_only" }, { C.record("quest", 2, "title", "Title") })
      assert.is_nil(C.clear())
      assert.is_false(C.disclose())
      assert.is_truthy(C.describe():find("paused", 1, true))
    end)
  end)

  describe("never raises", function()
    it("an erroring dependency is counted, not thrown", function()
      local d = deps()
      d.lookup = function() error("boom") end
      C.load(nil, d)
      local result, msg = C.record("quest", 2, "title", "Title")
      assert.are.equal("error", result)
      assert.is_truthy(msg:find("boom", 1, true))
      assert.are.equal(1, C.status().errors)
      assert.is_truthy(C.describe():find("1 error", 1, true))
    end)
  end)

  describe("disclosure, status, clear", function()
    it("discloses once, keeps the flag across clear, and not while off", function()
      local db = C.load(nil, deps())
      on = false
      assert.is_false(C.disclose())
      assert.is_false(db.disclosed)
      on = true
      assert.is_true(C.disclose())
      assert.are.equal(2, #prints)
      assert.is_truthy(prints[2]:find("/wfj collector off", 1, true))
      assert.is_false(C.disclose())
      C.record("quest", 2, "title", "Title")
      assert.are.equal(1, C.clear())
      assert.is_true(db.disclosed)
      assert.are.same({}, db.entries)
      assert.are.equal("on · 0 entries · 0.0 KB of 4.0 MB", C.describe())
    end)
  end)
end)

describe("Core/Collector gossip kind", function()
  local WFJ, C, shipped, player

  local function deps()
    return {
      enabled = function() return true end,
      lookup = function(kind, id) return shipped[kind] and shipped[kind][id] end,
      player = function() return player end,
      build = function() return "1.15.9.69722" end,
      print = function() end,
    }
  end

  local INN = "Creature-0-4372-0-17-6740-0000A1B2C3"
  local GUARD = "Creature-0-4372-0-17-1423-0000D4E5F6"

  before_each(function()
    WFJ = loadCollector()
    C = WFJ.Collector
    shipped, player = {}, PLAYER
  end)

  it("stores the line in Blizzard's tokens under its gossip key, with the speaker's creature id", function()
    local db = C.load(nil, deps())
    local raw = "Well met, Reyn. A hunter needs rest too."
    local key = C.key(raw, PLAYER)
    assert.are.equal(16, #key)
    assert.are.equal("recorded", C.recordGossip(raw, INN))
    local e = db.entries["gossip:" .. key .. ":text"]
    assert.are.same({ t = "gossip", i = key, f = "text", h = key, e = "Well met, $N. A $C needs rest too.", b = 1,
      n = { 6740 }, p = "Hunter|Night Elf" }, e)
    assert.are.equal(C.size("gossip:" .. key .. ":text", e.e, e.n, e.p), db.bytes)
    assert.are.equal(WFJ.Hash.key(WFJ.Normalize.v1(e.e)), key)
    assert.are.equal("seen", C.recordGossip(raw, INN)) -- memo
  end)

  it("a shipped row for the key makes the line known", function()
    local db = C.load(nil, deps())
    local raw = "Greetings, traveller."
    shipped.gossip = { [C.key(raw, PLAYER)] = { ja = "ようこそ、旅の人。", status = "." } }
    assert.are.equal("known", C.recordGossip(raw, INN))
    assert.is_nil(next(db.entries))
  end)

  it("another NPC with the same line joins n: sorted, unique, capped; a non-creature adds nothing", function()
    local db = C.load(nil, deps())
    local raw = "Goodbye."
    C.recordGossip(raw, INN)
    assert.are.equal("seen", C.recordGossip(raw, GUARD))
    local e = db.entries["gossip:" .. C.key(raw, PLAYER) .. ":text"]
    assert.are.same({ 1423, 6740 }, e.n)
    assert.are.equal(C.size("gossip:" .. e.i .. ":text", e.e, e.n), db.bytes)
    assert.are.equal("seen", C.recordGossip(raw, "Player-4372-0ABCDEF1"))
    assert.are.same({ 1423, 6740 }, e.n)
    for id = 1, 40 do C.recordGossip(raw, ("Creature-0-1-0-1-%d-0000000001"):format(10000 + id)) end
    assert.are.equal(C.NPC_CAP, #e.n)
    local other = "A line said by no creature."
    assert.are.equal("recorded", C.recordGossip(other, nil))
    assert.is_nil(db.entries["gossip:" .. C.key(other, PLAYER) .. ":text"].n)
  end)

  it("refuses as quest text does", function()
    C.load(nil, deps())
    assert.are.same({ "refused", "empty" }, { C.recordGossip("", INN) })
    assert.are.same({ "refused", "own_text" }, { C.recordGossip("こんにちは", INN) })
    player = { name = "Reyn", class = nil, race = "Night Elf" }
    assert.are.same({ "refused", "no_player" }, { C.recordGossip("Hello there.", INN) })
    player = { name = "Al", class = "Hunter", race = "Night Elf" }
    assert.are.same({ "refused", "short_name" }, { C.recordGossip("Hello, Al.", INN) })
    assert.are.same({ "refused", "bad_kind" }, { C.record("gossip", 1, "text", "Hello.") })
  end)

  it("load keeps valid gossip entries and drops malformed ones", function()
    local key = C.key("Goodbye.", PLAYER)
    local good = { t = "gossip", i = key, f = "text", h = key, e = "Goodbye.", b = 1, n = { 1423, 6740 } }
    local saved = { version = 1, builds = { "1.15.9.69722" }, entries = {
      ["gossip:" .. key .. ":text"] = good,
      ["gossip:0000000000000000:text"] = { t = "gossip", i = "0000000000000000", f = "text", h = key, e = "x", b = 1 },
      ["gossip:" .. key .. ":name"] = { t = "gossip", i = key, f = "name", h = key, e = "x", b = 1 },
      ["gossip:1:text"] = { t = "gossip", i = 1, f = "text", h = key, e = "x", b = 1 },
      ["gossip:" .. key .. "x:text"] = { t = "gossip", i = key .. "x", f = "text", h = key, e = "x", b = 1 },
      ["quest:2:title"] = { t = "quest", i = 2, f = "title", h = key, e = "x", b = 1, n = { 1 } },
    } }
    saved.entries["gossip:" .. key .. ":text"] = good
    local bad = {}
    for k, v in pairs(good) do bad[k] = v end
    bad.n = { 1.5 }
    local db = C.load(saved, deps())
    assert.are.same({ ["gossip:" .. key .. ":text"] = good }, db.entries)
    db = C.load({ version = 1, builds = { "1.15.9.69722" }, entries = { ["gossip:" .. key .. ":text"] = bad } }, deps())
    assert.is_nil(next(db.entries))
  end)
end)

-- a whole stub session through the real surfaces writes nothing personal.
describe("Collector through the loaded addon", function()
  it("a stub session writes only the documented shape and no personal string", function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI(); Stub.installGossipAPI()
    Loader.load("WoWForeverJapanese")
    Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese")
    Stub.fireAll("PLAYER_ENTERING_WORLD")
    require("tests.lua.spec.collector_session").run()

    local db = WFJ_Collector
    local top = {}
    for k in pairs(db) do top[#top + 1] = k end
    table.sort(top)
    assert.are.same({ "builds", "bytes", "capped", "disclosed", "entries", "version" }, top)
    local n = 0
    for key, e in pairs(db.entries) do
      n = n + 1
      -- n: a gossip entry's NPC ids; p: "Class|Race" next to a $C / $R line
      local shape = { t = 1, i = 1, f = 1, h = 1, e = 1, b = 1, n = 1, p = 1 }
      for k in pairs(e) do assert.is_truthy(shape[k], key .. "." .. k) end
    end
    assert.is_true(n >= 8)
    local function scan(v)
      if type(v) == "string" then
        assert.is_nil(v:find("Reyn", 1, true), v)
        assert.is_nil(v:find("Creature-", 1, true), v)
        assert.is_nil(v:find("Player-", 1, true), v)
        assert.is_nil(v:find(GetRealmName(), 1, true), v)
      elseif type(v) == "table" then
        for k, x in pairs(v) do scan(k); scan(x) end
      end
    end
    scan(db)
    assert.are.equal("$N, your aim is true. The $C of the $R is welcome.", db.entries["quest:2:completion"].e)
  end)
end)

-- Short-name candidate keys (ADR-024) and the quest known check on the female-variant h1.
describe("Core/Collector short names and h1f", function()
  local WFJ, C
  local KA = { name = "Ka", class = "Hunter", race = "Night Elf" }

  before_each(function()
    H.coreStub()
    WFJ = H.loadChunks({ "Core/Const.lua", "Core/Normalize.lua", "Core/Hash.lua", "Core/State.lua",
      "Core/Settings.lua" })
    H.loadPure("Core/Collector.lua", nil, WFJ)
    C = WFJ.Collector
  end)

  local function key(e) return WFJ.Hash.key(WFJ.Normalize.v1(e)) end

  it("the three existing candidates first, then the short-name ones, deduplicated", function()
    local raw = "Well met, Ka. The hunter lodge awaits."
    local keys = C.keys(raw, KA)
    assert.are.same({ key("Well met, Ka. The $C lodge awaits."), key(raw),
      key("Well met, $N. The $C lodge awaits."), key("Well met, $N. The hunter lodge awaits.") }, keys)
    -- the name as part of a word is never replaced
    assert.are.same({ key("Kara says hello."), }, C.keys("Kara says hello.", KA))
  end)

  it("a name of 3+ code points gets exactly today's candidates", function()
    local reyn = { name = "Reyn", class = "Hunter", race = "Night Elf" }
    local raw = "Well met, Reyn. The hunter lodge awaits."
    assert.are.same({ key("Well met, $N. The $C lodge awaits."), key("Well met, $N. The hunter lodge awaits."),
      key(raw) }, C.keys(raw, reyn))
  end)

  it("markup next to a short name is stripped before the name is replaced", function()
    assert.are.equal(key("Hello, $N."), C.keys("Hello, |cffffd100Ka|r.", KA)[2])
  end)

  it("a quest line filled from live values is known by its masked h1; a rewording is recorded", function()
    -- 0x782db28c: the pipeline's key of mask_values(normalize_v1("Collect $1oa Lady's Tear Moss, $N."))
    local shipped = { ja = "Lady's Tear Mossを$N1個集める。", h1 = 0x782db28c }
    local reyn = { name = "Reyn", class = "Hunter", race = "Night Elf" }
    C.load(nil, H.collectorDeps({ player = function() return reyn end,
      lookup = function(kind, id) if kind == "quest.objectives" and id == 7 then return shipped end end }))
    assert.are.equal("known", C.record("quest", 7, "objectives", "Collect 10 Lady's Tear Moss, Reyn."))
    assert.are.equal("recorded", C.record("quest", 7, "objectives", "Gather 10 Lady's Tear Moss, Reyn."))
    -- the same key from the live side: the two masks agree
    assert.are.same({ 0x782db28c }, { C.fingerprints("Collect 25 Lady's Tear Moss, Reyn.", reyn, true)[1] })
    -- a number with separators is one `#`, as the pipeline masks it
    assert.are.equal("Collect # or # or # of # things.", C.mask("Collect 12 or 1,000 or 2.5 of 7 things."))
  end)

  it("the quest known check accepts the field's h1f", function()
    local female = "Welcome, sister."
    local shipped = { h1 = WFJ.Hash.h32x2(WFJ.Normalize.v1("Welcome, brother.")),
      h1f = WFJ.Hash.h32x2(WFJ.Normalize.v1(female)) }
    local reyn = { name = "Reyn", class = "Hunter", race = "Night Elf" }
    local collected = C.load(nil, H.collectorDeps({ player = function() return reyn end,
      lookup = function(kind, id) if kind == "quest.progress" and id == 5 then return shipped end end }))
    assert.are.equal("known", C.record("quest", 5, "progress", female))
    assert.are.equal("recorded", C.record("quest", 5, "progress", "Welcome, cousin."))
    assert.is_table(collected.entries)
  end)
end)


describe("Core/Collector plural class and race words", function()
  local C, N, Hs
  before_each(function()
    local ns = loadCollector()
    C, N, Hs = ns.Collector, ns.Normalize, ns.Hash
  end)
  local function key(en) return Hs.key(N.v1(en)) end
  local function has(list, k)
    for _, v in ipairs(list) do if v == k then return true end end
    return false
  end

  it("a plural the server built from $cs or $Rs finds the line stored with the token", function()
    local druid = { name = "Wowforever", class = "Druid", race = "Night Elf" }
    local live = "Well met, Wowforever. It is good to see that druids like yourself are taking an active part."
    assert.is_true(has(C.keys(live, druid),
      key("Well met, $n. It is good to see that $cs like yourself are taking an active part.")))
    local orc = { name = "Grok", class = "Warrior", race = "Orc" }
    assert.is_true(has(C.keys("Orcs like you, Grok, are welcome.", orc), key("$Rs like you, $N, are welcome.")))
  end)

  it("a literal plural still finds the line stored with the word", function()
    local druid = { name = "Wowforever", class = "Druid", race = "Night Elf" }
    local live = "The druids of Moonglade await, Wowforever."
    assert.is_true(has(C.keys(live, druid), key("The druids of Moonglade await, $N.")))
  end)
end)
