local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local CORE = { "Core/Const.lua", "Core/State.lua", "Core/Settings.lua", "Core/Modifier.lua" }
local IDS = { "enabled", "modifier", "area.quests", "area.gossip", "area.itemTooltips", "area.spellTooltips",
  "area.interface", "area.books", "marker.stale", "marker.missing", "readings.enabled", "readings.glosses",
  "minimapButton" }
local DEFAULTS = { enabled = true, modifier = "alt", ["area.quests"] = true, ["area.gossip"] = true,
  ["area.itemTooltips"] = true, ["area.spellTooltips"] = true, ["area.interface"] = true, ["area.books"] = true,
  ["marker.stale"] = true,
  ["marker.missing"] = true, -- on by default
  ["readings.enabled"] = true, -- on by default
  ["readings.glosses"] = true, -- on by default
  minimapButton = true } -- on by default

describe("Settings registry", function()
  local WFJ, S
  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    WFJ = H.loadChunks(CORE)
    S = WFJ.Settings
  end)

  -- every setting has an Options row, so none is hidden
  it("defines exactly these ids, in order; none is hidden", function()
    local ids = {}
    for i, d in ipairs(S.list()) do
      ids[i] = d.id
      assert.is_nil(d.hidden, d.id)
    end
    assert.are.same(IDS, ids)
  end)

  it("returns the documented defaults on an empty WFJ_DB", function()
    S.load(nil, 1, {})
    for id, v in pairs(DEFAULTS) do assert.are.equal(v, S.get(id), id) end
  end)

  it("rejects a wrong type / a choice outside choices and leaves the stored value", function()
    S.load(nil, 1, {})
    local ok, why = S.set("enabled", "maybe")
    assert.is_false(ok); assert.is_truthy(why:find("on|off", 1, true))
    assert.is_true(S.get("enabled"))
    ok, why = S.set("modifier", "meta")
    assert.is_false(ok); assert.is_truthy(why:find("expected a key", 1, true)) -- kind "key"
    assert.are.equal("alt", S.get("modifier"))
    ok, why = S.set("nope", true)
    assert.is_false(ok); assert.is_truthy(why:find("unknown setting", 1, true))
  end)

  it("coerces on/off strings and booleans, and persists into the db", function()
    local db = S.load(nil, 1, {})
    assert.is_true(S.set("enabled", "off"))
    assert.is_false(S.get("enabled")); assert.is_false(db.settings.enabled)
    assert.is_true(S.set("enabled", true))
    assert.is_true(db.settings.enabled)
    assert.is_true(S.set("modifier", "shift"))
    assert.are.equal("shift", db.settings.modifier)
  end)

  it("raises on a duplicate define", function()
    assert.has_error(function() S.define{ id = "enabled", kind = "boolean", default = true } end)
    assert.has_error(function() S.define{ id = "weird", kind = "number", default = 1 } end)
  end)

  it("find is case-insensitive", function()
    assert.are.equal("area.itemTooltips", S.find("area.itemtooltips"))
    assert.are.equal("enabled", S.find("ENABLED"))
    assert.is_nil(S.find("area.nothing"))
  end)

  it("set before load is a programming error", function()
    assert.has_error(function() S.set("enabled", false) end)
  end)

  it("apply runs on set and exactly once per setting on load, with the effective value", function()
    local seen = {}
    S.define{ id = "test.x", kind = "boolean", default = true, apply = function(v) seen[#seen + 1] = v end }
    S.load({ schema = 1, settings = { ["test.x"] = false } }, 1, {})
    assert.are.same({ false }, seen)
    S.set("test.x", true)
    assert.are.same({ false, true }, seen)
  end)

  it("matches string values case-insensitively", function()
    S.load(nil, 1, {})
    assert.is_true(S.set("modifier", "ALT"))
    assert.are.equal("alt", S.get("modifier"))
    assert.is_true(S.set("enabled", "OFF"))
    assert.is_false(S.get("enabled"))
  end)

  it("validates stored values on load and falls back to the default", function()
    local db = S.load({ schema = 1, settings = { modifier = "meta", enabled = "yes", ["marker.stale"] = "OFF" } },
      1, {})
    assert.are.equal("alt", S.get("modifier")); assert.is_nil(db.settings.modifier)
    assert.is_true(S.get("enabled")); assert.is_nil(db.settings.enabled)
    assert.is_false(S.get("marker.stale")); assert.is_false(db.settings["marker.stale"])
    assert.are.equal("alt", WFJ.Modifier.key())
  end)

  it("apply hooks mirror into State on load", function()
    S.load({ schema = 1, settings = { enabled = false, ["area.gossip"] = false } }, 1, {})
    assert.is_false(WFJ.State.enabled)
    assert.is_false(WFJ.State.areaEnabled("gossip"))
    assert.is_true(WFJ.State.areaEnabled("quests"))
    assert.is_true(WFJ.State.areaEnabled("items"))
    assert.is_true(WFJ.State.areaEnabled("spells"))
  end)
end)

describe("Settings kind \"key\" and the modifier's toggle check", function()
  local WFJ, S
  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    WFJ = H.loadChunks({ "Core/Const.lua", "Core/Compat.lua", "Core/State.lua", "Core/Settings.lua",
      "Core/Modifier.lua" })
    WFJ.Compat.init(function(name) return _G[name] end)
    S = WFJ.Settings
  end)

  it("an invalid key is refused with its reason and the stored value stays", function()
    S.load(nil, 1, {})
    local ok, why = S.set("modifier", "BUTTON1")
    assert.is_false(ok)
    assert.is_truthy(why:find("expected a key", 1, true))
    assert.are.equal("alt", S.get("modifier"))
    assert.has_error(function() S.define{ id = "x.key", kind = "key", default = "alt" } end)
  end)

  it("the modifier cannot be the toggle's key; only an exact key conflicts", function()
    S.load(nil, 1, {})
    Stub.bindings.J = "WFJ_TOGGLE"
    local ok, why = S.set("modifier", "j")
    assert.is_false(ok)
    assert.is_truthy(why:find("turning translation on / off", 1, true))
    assert.are.equal("alt", S.get("modifier"))
    assert.are.same({}, Stub.bindingCalls)
    Stub.bindings = { ["CTRL-J"] = "WFJ_TOGGLE" }
    assert.is_true((S.set("modifier", "j")))
    assert.are.equal("J", S.get("modifier"))
  end)

  it("every non-hidden setting carries its Japanese label", function()
    WFJ = H.loadChunks({ "Core/Collector.lua" }, WFJ)
    for _, d in ipairs(S.list()) do
      if not d.hidden then assert.is_true(type(d.ja) == "string" and #d.ja > 0, d.id) end
    end
  end)
end)
