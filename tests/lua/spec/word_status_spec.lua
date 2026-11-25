-- Core/WordStatus: a word's key, its status with and without one set by the player, the learn-next set and what
-- the saved word list and the study cards do to it. Pure: loaded with no WoW globals.
local H = require("tests.lua.spec.helpers")

local function load(saved)
  local WFJ = {}
  H.loadPure("Core/Data.lua", "WoWForeverJapanese", WFJ)
  H.loadPure("Core/Glosses.lua", "WoWForeverJapanese", WFJ)
  H.loadPure("Core/WordFrequency.lua", "WoWForeverJapanese", WFJ)
  H.loadPure("Core/WordStatus.lua", "WoWForeverJapanese", WFJ)
  WFJ.Readings = {
    tokenWords = function() return { { "ウォリアー", "Warrior" } } end,
    contractionHead = function(lower) return lower:match("^(%a+)'") end,
  }
  WFJ.Data.add("gloss", { [1] = "倒す\tたおす\tdefeat", [2] = "倒す\tたおす\tdefeated", [3] = "敵\tてき\tenemy" })
  WFJ.Data.add("freqJa", { ["倒す\tたおす"] = "9,0,0,0,0,0", ["敵\tてき"] = "8,0,0,0,0,0",
    ["だろう\tだろう"] = "7,0,0,0,0,0", ["増加\tぞうか"] = "6,0,0,0,0,0", ["増加する\tぞうかする"] = "5,0,0,0,0,0",
    ["谷\tたに"] = "4,0,0,0,0,0" })
  WFJ.Data.add("freqEn", { enemy = "7,0,0,0,0,0", you = "5,0,0,0,0,0", gold = "2,0,0,0,0,0" })
  WFJ.Data.add("grammar", { ["だろう\tだろう"] = "1" })
  local kept = WFJ.WordStatus.load(saved)
  return WFJ.WordStatus, kept, WFJ
end

describe("Core/WordStatus", function()
  it("keys a word by its dictionary form and that form's reading", function()
    local S = load()
    local lang, a = S.keyOf({ word = "倒して", reading = "たおして", gloss = 1 })
    local _, b = S.keyOf({ word = "倒した", reading = "たおした", gloss = 2 })
    assert.are.equal("ja", lang)
    assert.are.equal("倒す\tたおす", a)
    assert.are.equal(a, b)
    assert.are.same({ "ja", "谷\tたに" }, { S.keyOf({ word = "谷", reading = "たに", gloss = false }) })
    -- a chat word brings its dictionary form on its card
    assert.are.same({ "ja", "行く\tいく" },
      { S.keyOf({ word = "行きませんか", reading = "いき", card = { lemma = "行く", lemmaReading = "いく" } }) })
  end)

  it("gives a name and a class or race word no key", function()
    local S = load()
    assert.is_nil(S.keyOf({ word = "ストームウィンド", reading = "ストームウィンド", name = true }))
    assert.is_nil(S.keyOf({ word = "ウォリアー", reading = "ウォリアー",
      card = { lemma = "ウォリアー", lemmaReading = "ウォリアー", meaning = "Warrior (a class)" } }))
    assert.is_nil(S.keyOf(nil))
  end)

  it("keys an English word by its lower-cased form, a contraction by its first word, a plural by its singular", function()
    local S = load()
    local card = { english = true, ja = "敵", jaReading = "てき" }
    assert.are.same({ "en", "enemy" }, { S.keyOf({ word = "Enemy", card = card }) })
    assert.are.equal("you", S.englishKey("you're"))
    assert.are.equal("gold", S.englishKey("Golds"))
    assert.are.equal("zebra", S.englishKey("Zebra")) -- no row: the word itself
  end)

  it("starts a word unknown, a grammar word ignored and a suru verb of a known noun known", function()
    local S = load()
    assert.are.equal("unknown", S.get("ja", "倒す\tたおす"))
    assert.are.equal("ignored", S.get("ja", "だろう\tだろう"))
    assert.are.equal("unknown", S.get("ja", "増加する\tぞうかする"))
    S.set("ja", "増加\tぞうか", "known")
    assert.are.equal("known", S.get("ja", "増加する\tぞうかする"))
    assert.are.equal("unknown", S.get("en", "enemy"))
  end)

  it("lets a status the player set win, an explicit unknown included", function()
    local S, kept = load()
    S.set("ja", "増加\tぞうか", "known")
    S.set("ja", "増加する\tぞうかする", "unknown")
    S.set("ja", "だろう\tだろう", "unknown")
    assert.are.equal("unknown", S.get("ja", "増加する\tぞうかする"))
    assert.are.equal("unknown", S.get("ja", "だろう\tだろう"))
    assert.are.equal("u", kept.ja["だろう\tだろう"])
    -- an unknown word that would be unknown anyway keeps no entry
    S.set("ja", "敵\tてき", "known")
    S.set("ja", "敵\tてき", "unknown")
    assert.is_nil(kept.ja["敵\tてき"])
  end)

  it("steps unknown, learning, known, unknown, and takes an ignored word back to unknown", function()
    local S = load()
    local key = "倒す\tたおす"
    assert.are.equal("learning", S.step("ja", key))
    assert.are.equal("known", S.step("ja", key))
    assert.are.equal("unknown", S.step("ja", key))
    assert.are.equal("ignored", S.ignore("ja", key))
    assert.are.equal("unknown", S.step("ja", key))
    assert.are.equal("ignored", S.ignore("ja", key))
    assert.are.equal("unknown", S.ignore("ja", key))
  end)

  it("lists the most used unknown words to learn next, and follows every change at once", function()
    local S = load()
    S.LEARN_NEXT = 2
    assert.is_true(S.learnNext("ja", "倒す\tたおす"))
    assert.is_true(S.learnNext("ja", "敵\tてき"))
    assert.is_false(S.learnNext("ja", "増加\tぞうか"))
    assert.is_false(S.learnNext("ja", "だろう\tだろう")) -- a grammar word is ignored, so it is never one
    S.set("ja", "倒す\tたおす", "learning")
    assert.is_false(S.learnNext("ja", "倒す\tたおす"))
    assert.is_true(S.learnNext("ja", "増加\tぞうか")) -- the next unknown word moved up
    S.set("ja", "敵\tてき", "ignored")
    assert.is_true(S.learnNext("ja", "増加する\tぞうかする"))
  end)

  it("keeps the two languages apart", function()
    local S, kept = load()
    S.set("en", "enemy", "known")
    assert.are.equal("known", S.get("en", "enemy"))
    assert.are.same({}, kept.ja)
    assert.are.same({ 1, 0, 0 }, { S.counts("en") })
    assert.are.same({ 0, 0, 1 }, { S.counts("ja") }) -- the grammar word
  end)

  it("keeps its statuses across a load, and drops an entry that is not one", function()
    local S, kept = load({ schema = 1, ja = { ["敵\tてき"] = "k", ["谷\tたに"] = "x", [7] = "k" }, en = { enemy = "l" } })
    assert.are.equal("known", S.get("ja", "敵\tてき"))
    assert.are.equal("learning", S.get("en", "enemy"))
    assert.is_nil(kept.ja["谷\tたに"])
    assert.is_nil(kept.ja[7])
  end)

  it("never writes a table saved by a newer version", function()
    local newer = { schema = 2, ja = { ["敵\tてき"] = "k" }, shape = "new" }
    local S, kept = load(newer)
    assert.are.equal(newer, kept)
    assert.is_true(S.readonly())
    assert.is_false(S.set("ja", "倒す\tたおす", "known"))
    assert.is_nil(S.step("ja", "倒す\tたおす"))
    assert.are.same({ schema = 2, ja = { ["敵\tてき"] = "k" }, shape = "new" }, newer)
  end)

  it("makes a saved word learning and a word with a stable study card known, and never moves one down", function()
    local S = load()
    local entries = {
      { key = "a", word = "倒して", reading = "たおして", lemma = "倒す", lemmaReading = "たおす" },
      { key = "b", word = "敵", reading = "てき", lemma = "敵", lemmaReading = "てき" },
      { key = "c", word = "谷", reading = "たに", lemma = "", lemmaReading = "" },
      { key = "d", word = "Enemy", lang = "en" },
      { key = "e", word = "ウォリアー", reading = "ウォリアー" },
    }
    S.set("ja", "谷\tたに", "known")
    local cards = { b = { s = 21 }, c = { s = 3 }, d = { s = 40 } }
    S.sync(entries, function(key) return cards[key] end)
    assert.are.equal("learning", S.get("ja", "倒す\tたおす"))
    assert.are.equal("known", S.get("ja", "敵\tてき"))
    assert.are.equal("known", S.get("ja", "谷\tたに")) -- known stays known beside a young card
    assert.are.equal("known", S.get("en", "enemy"))
    -- an ignored word stays ignored whatever its card says, and a known word is not made learning by a save
    S.set("ja", "敵\tてき", "ignored")
    S.sync(entries, function(key) return cards[key] end)
    assert.are.equal("ignored", S.get("ja", "敵\tてき"))
    S.set("ja", "倒す\tたおす", "known")
    S.sync(entries, function() return nil end)
    assert.are.equal("known", S.get("ja", "倒す\tたおす"))
  end)

  it("keeps the last import's numbers per language", function()
    local S, kept = load()
    assert.is_nil(S.lastImport("ja"))
    S.noteImport("ja", { marked = 3, already = 1, kept = 0, missing = 2 })
    assert.are.equal(3, S.lastImport("ja").marked)
    assert.is_nil(S.lastImport("en"))
    assert.are.equal(2, kept.lastImport.ja.missing)
  end)
end)
