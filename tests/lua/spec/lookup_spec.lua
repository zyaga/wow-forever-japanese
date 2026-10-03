-- Core/Lookup over the real generated shards (+ synthetic gossip).
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local Loader = require("tests.lua.spec.loader")

describe("Lookup.get / Lookup.gossip on the shipped data", function()
  local WFJ, L
  setup(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    WFJ = Loader.load("WoWForeverJapanese")
    L = WFJ.Lookup
  end)

  it("returns the trusted quest title with its status code and h1", function()
    assert.are.same({ ja = "Koboldキャンプの掃討", status = ".", h1 = 0x5d10a531 }, L.get("quest.title", 7))
  end)

  it("returns nil for an unshipped field, an unknown id, and an unknown kind", function()
    -- never drafted: the objective is a bare label ("Log"), which ships as the client's English
    assert.is_nil(L.get("quest.objectives", 78307))
    assert.is_nil(L.get("quest.progress", 5)) -- no progress English for this quest, so no Japanese ever ships
    assert.is_nil(L.get("quest.title", 999999))
    assert.is_nil(L.get("unit", 1))
    assert.is_nil(L.get("quest.name", 2))
    assert.is_nil(L.get("quest", 2)) -- quests need a field
    assert.is_nil(L.get(nil, 2))
    assert.is_nil(L.get(42, 2))
  end)

  it("items and spells ship unaligned (ADR-007) under their single-field kind", function()
    local itemId = next(WFJ.Data.item)
    local spellId = next(WFJ.Data.spell)
    -- a bare "spell" names no single field, so the kind carries it
    local item, spell = L.get("item", itemId), L.get("spell.description", spellId)
    assert.are.equal("u", item.status)
    assert.are.equal("u", spell.status)
    assert.is_string(item.ja)
    assert.is_number(item.h1)
    assert.are.same(item, L.get("item.description", itemId))
    assert.is_nil(L.get("spell", spellId))  -- ambiguous with two fields: refused, never guessed
  end)

  it("a branch line's table slot comes back as variants and shapes, with no ja", function()
    local variants = { "$N1と$N2。", "$N1。", shape = { "2/0", "1/0" } }
    WFJ.Data.add("spell", { [99999901] = { variants, nil, 0x12345678, nil, "um" } })
    local e = L.get("spell.description", 99999901)
    assert.is_nil(e.ja)
    assert.are.equal(variants, e.variants)
    assert.are.same({ "2/0", "1/0" }, e.shapes)
    assert.are.equal("u", e.status)
    assert.are.equal(0x12345678, e.h1)
    assert.is_nil(L.get("spell.aura", 99999901))
  end)

  it("gossip entries are keyed by the 16-hex key", function()
    assert.is_nil(L.gossip("0123456789abcdef"))
    local shipped = WFJ.Data.count("gossip")
    WFJ.Data.add("gossip", { ["0123456789abcdef"] = { "こんにちは", "." } })
    assert.are.same({ ja = "こんにちは", status = "." }, L.gossip("0123456789abcdef"))
    assert.are.equal(shipped + 1, WFJ.Data.count("gossip"))
  end)

  it("Lookup.get(\"gossip\", key) is Lookup.gossip(key): a row and a miss", function()
    WFJ.Data.add("gossip", { ["fedcba9876543210"] = { "さようなら", "s" } })
    assert.are.same(L.gossip("fedcba9876543210"), L.get("gossip", "fedcba9876543210"))
    assert.are.same({ ja = "さようなら", status = "s" }, L.get("gossip", "fedcba9876543210"))
    assert.is_nil(L.get("gossip", "0000000000000000"))
    assert.is_nil(L.get("gossip", nil))
  end)

  it("book rows are keyed rows like gossip; other kinds never read them", function()
    local shipped = WFJ.Data.count("book")
    assert.is_nil(L.get("book", "1111222233334444"))
    WFJ.Data.add("book", { ["1111222233334444"] = { "訳 book", "." } })
    assert.are.same({ ja = "訳 book", status = "." }, L.get("book", "1111222233334444"))
    assert.are.same(L.get("book", "1111222233334444"), L.keyed("book", "1111222233334444"))
    assert.are.equal(shipped + 1, WFJ.Data.count("book"))
    assert.is_nil(L.get("book", nil))
    assert.is_nil(L.gossip("1111222233334444"))
    assert.is_nil(L.keyed("quest", 2))
  end)

  it("trainer_greeting is not a data kind", function()
    assert.has_error(function() WFJ.Data.add("trainer_greeting", {}) end)
    assert.is_nil(L.keyed("trainer_greeting", "1111222233334444"))
  end)

  it("never returns an entry with an empty ja", function()
    for _, t in ipairs({ "quest", "item", "spell" }) do
      for id, row in pairs(WFJ.Data[t]) do
        for i, f in ipairs(WFJ.SLOTS[t].fields) do
          local e = L.get(#WFJ.SLOTS[t].fields > 1 and (t .. "." .. f) or t, id)
          -- a branch line is a table of variants instead (none empty), a sectioned line its heading and
          -- paragraphs
          if row[i] ~= nil then
            assert.is_true(e.variants and #e.variants > 0 or e.sections and #e.sections > 0 or #e.ja > 0, t .. id)
          else
            assert.is_nil(e)
          end
        end
      end
    end
  end)
end)
