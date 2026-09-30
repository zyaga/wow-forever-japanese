local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local CORE = { "Core/Const.lua", "Core/State.lua", "Core/Settings.lua", "Core/Modifier.lua" }

describe("Settings.load: migrations and the downgrade backup", function()
  local WFJ, S
  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    WFJ = H.loadChunks(CORE)
    S = WFJ.Settings
  end)

  it("first run creates a fresh db at the current schema", function()
    local db = S.load(nil, 2, {})
    assert.are.equal(2, db.schema)
    assert.are.same({}, db.settings)
    assert.is_nil(db.backup)
    assert.are.equal(WFJ.VERSION, db.build.addon)
    assert.are.equal(0, #Stub.prints)
  end)

  it("upgrade runs each migration step exactly once, in order, and stores the new schema", function()
    local calls = {}
    local migrations = {
      [2] = function(db) calls[#calls + 1] = 2; db.settings.migrated2 = true end,
      [3] = function(db) calls[#calls + 1] = 3; db.settings.migrated3 = true end,
    }
    local db = S.load({ schema = 1, settings = { enabled = false } }, 3, migrations)
    assert.are.same({ 2, 3 }, calls)
    assert.are.equal(3, db.schema)
    assert.is_true(db.settings.migrated2); assert.is_true(db.settings.migrated3)
    assert.is_false(db.settings.enabled)
  end)

  it("a missing migration step is a no-op (additive schema)", function()
    local db = S.load({ schema = 1, settings = {} }, 2, {})
    assert.are.equal(2, db.schema)
  end)

  it("downgrade backs up the whole table, resets, and prints once", function()
    local newer = { schema = 3, settings = { enabled = false }, foo = 1 }
    local db = S.load(newer, 2, {})
    assert.are_not.equal(newer, db)
    assert.are.equal(newer, db.backup)
    assert.are.equal(2, db.schema)
    assert.are.same({}, db.settings)
    assert.is_true(S.get("enabled"))
    assert.are.equal(1, #Stub.prints)
    assert.is_truthy(Stub.prints[1]:find("downgrade", 1, true))
  end)

  it("keeps only the newest backup; backups never nest", function()
    local first = S.load({ schema = 3, settings = {} }, 2, {})
    assert.is_truthy(first.backup)
    first.schema = 4 -- pretend a newer version ran on top of this table
    local second = S.load(first, 2, {})
    assert.are.equal(first, second.backup)
    assert.is_nil(second.backup.backup)
  end)

  it("preserves unknown keys on a same-schema load", function()
    local db = S.load({ schema = 2, settings = {}, foo = 1 }, 2, {})
    assert.are.equal(1, db.foo)
    assert.are.equal(2, db.schema)
  end)

  it("treats a non-integer or NaN schema as current", function()
    local ran = false
    local db = S.load({ schema = 0.5, settings = {} }, 1, { [1] = function() ran = true end })
    assert.are.equal(1, db.schema); assert.is_false(ran); assert.is_nil(db.backup)
    db = S.load({ schema = 0 / 0, settings = {} }, 1, {})
    assert.are.equal(1, db.schema); assert.is_nil(db.backup)
  end)

  it("tolerates a hand-damaged table", function()
    local db = S.load({ settings = "nope" }, 1, {})
    assert.are.equal(1, db.schema)
    assert.are.same({}, db.settings)
  end)

  it("a WFJ_DB saved before area.interface existed loads with it on and no migration", function()
    local db = S.load({ schema = 1, settings = { enabled = true, ["area.itemTooltips"] = false } }, 1, {})
    assert.are.equal(1, db.schema)
    assert.is_nil(db.settings["area.interface"]) -- nothing written: the default lives in define
    assert.is_true(S.get("area.interface"))
    assert.is_true(WFJ.State.areaEnabled("ui"))
    assert.is_false(WFJ.State.areaEnabled("items"))
  end)

  it("a WFJ_DB saved before area.books existed loads with it on and no migration", function()
    local db = S.load({ schema = 1, settings = { enabled = true, ["area.interface"] = false } }, 1, {})
    assert.are.equal(1, db.schema)
    assert.is_nil(db.settings["area.books"])
    assert.is_true(S.get("area.books"))
    assert.is_true(WFJ.State.areaEnabled("books"))
    assert.is_true(S.set("area.books", false))
    assert.is_false(WFJ.State.areaEnabled("books"))
  end)

  it("uses Const.SCHEMA and Settings.MIGRATIONS by default", function()
    local db = S.load(nil)
    assert.are.equal(WFJ.SCHEMA, db.schema)
  end)
end)

describe("Settings.load keeps every modifier saved before modifiers became keys", function()
  it("keeps alt / ctrl / shift / lalt / Q, drops a chord or junk to alt, never bumps the schema", function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    local S = H.loadChunks(CORE).Settings
    for stored, want in pairs({ alt = "alt", ctrl = "ctrl", shift = "shift", lalt = "lalt", Q = "Q",
      ["CTRL-Q"] = "alt", ["bogus key"] = "alt" }) do
      local db = S.load({ schema = 1, settings = { modifier = stored } }, 1, {})
      assert.are.equal(want, S.get("modifier"), stored)
      assert.are.equal(1, db.schema)
      if want == stored then assert.are.equal(stored, db.settings.modifier) else assert.is_nil(db.settings.modifier) end
    end
  end)
end)
