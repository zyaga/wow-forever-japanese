-- Core/Data + the generated layout.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local Loader = require("tests.lua.spec.loader")

local function coreNS()
  H.coreStub()
  local ns = {}
  H.loadChunk("Core/Const.lua", "WoWForeverJapanese", ns)
  H.loadPure("Core/Data.lua", "WoWForeverJapanese", ns)
  H.loadPure("Core/Lookup.lua", "WoWForeverJapanese", ns)
  return ns
end

describe("Core/Data.add", function()
  it("loads Data and Lookup under a std-lib-only environment (pure)", function()
    local ns = coreNS()
    assert.is_function(ns.Data.add)
    assert.is_function(ns.Lookup.get)
  end)

  it("copies rows in by id and counts them", function()
    local ns = coreNS()
    ns.Data.add("quest", { [2] = { "a" }, [5] = { "b" } })
    ns.Data.add("quest", { [7] = { "c" } })
    assert.are.equal("a", ns.Data.quest[2][1])
    assert.are.equal(3, ns.Data.count("quest"))
    assert.are.equal(0, ns.Data.count("gossip"))
  end)

  it("raises on a duplicate id and on an unknown type", function()
    local ns = coreNS()
    ns.Data.add("item", { [117] = { "x", 0x1, "u" } })
    assert.has_error(function() ns.Data.add("item", { [117] = { "y", 0x1, "u" } }) end)
    assert.has_error(function() ns.Data.add("unit", { [1] = { "x" } }) end)
  end)

  it("round-trips the escaping fixture written by the Python writer", function()
    local ns = coreNS()
    local chunk = assert(loadfile(H.ROOT .. "/tests/fixtures/lua/escape_fixture.lua"))
    chunk("WoWForeverJapanese", ns)
    local row = ns.Data.quest[1]
    assert.are.equal('He said "hi"\\ok\n[tag] |cffff0000red|r\ttab\001end\r', row[1])
    assert.is_nil(row[2])
    assert.are.equal("改行\nあり", row[3])
    assert.are.equal(0xd311f9a5, row[6])
    assert.are.equal(".msmm", row[11])
    assert.are.equal("[[]]", ns.Data.quest[2][2])
    assert.are.equal("m.mmm", ns.Data.quest[2][11])
  end)
end)

describe("generated layout matches Core/Const.lua", function()
  local WFJ
  setup(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    WFJ = Loader.load("WoWForeverJapanese")
  end)

  it("Meta.fields equals SLOTS.fields for every type, and rows have the status slot", function()
    assert.is_table(WFJ.Data.meta)
    for _, t in ipairs({ "quest", "item", "spell" }) do
      assert.are.same(WFJ.SLOTS[t].fields, WFJ.Data.meta.fields[t], t)
      assert.are.equal(WFJ.Data.meta.counts[t], WFJ.Data.count(t), t)
      local _, row = next(WFJ.Data[t])
      assert.is_string(row[WFJ.SLOTS[t].status], t)
      assert.are.equal(#WFJ.SLOTS[t].fields, #row[WFJ.SLOTS[t].status], t)
    end
    assert.are.equal(11, WFJ.SLOTS.quest.female) -- twin of schema.SLOTS["quest"]["female"]
    assert.is_nil(WFJ.SLOTS.item.female); assert.is_nil(WFJ.SLOTS.spell.female)
    assert.are.equal(1, WFJ.Data.meta.schema)
    assert.are.equal(WFJ.SCHEMA, WFJ.Data.meta.schema)
    assert.are.equal("7786596", WFJ.Data.meta.english.pfquest)
  end)

  it("area is laid out as objective is ({ text, h1, status }), in Meta and Const alike", function()
    for _, t in ipairs({ "objective", "area" }) do
      assert.are.same({ fields = { "text" }, hash = 1, status = 3, index = { text = 1 } }, WFJ.SLOTS[t], t)
      assert.are.same(WFJ.SLOTS[t].fields, WFJ.Data.meta.fields[t], t)
      assert.are.equal(WFJ.Data.meta.counts[t], WFJ.Data.count(t), t)
    end
  end)

  it("ui rows are { text, h1, status } keyed by global-string name, counted in Meta", function()
    assert.are.same({ fields = { "text" }, hash = 1, status = 3, index = { text = 1 } }, WFJ.SLOTS.ui)
    assert.are.equal(WFJ.Data.meta.counts.ui, WFJ.Data.count("ui"))
    assert.is_true(WFJ.Data.count("ui") > 0)
    local row = WFJ.Data.ui.ACCEPT
    assert.are.equal(3, #row)
    assert.is_string(row[1]); assert.is_number(row[2]); assert.are.equal(".", row[3])
    local e = WFJ.Lookup.get("ui", "ACCEPT")
    assert.are.same({ ja = row[1], status = ".", h1 = row[2] }, e)
    assert.is_nil(WFJ.Lookup.get("ui", "NOT_A_KEY"))
  end)

  it("ships the hash vectors and every case passes in-client (debug hash data)", function()
    local V = WFJ.Data.vectors
    assert.is_table(V)
    assert.are.equal(#H.vectors().cases, #V.cases)
    for _, c in ipairs(V.cases) do
      assert.are.equal(c.key, WFJ.Hash.keyOf(c.raw, c.player), c.id)
    end
  end)
end)
