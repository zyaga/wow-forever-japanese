local H = require("tests.lua.spec.helpers")

describe("State: pub/sub fires in order, setters fire only on change", function()
  local WFJ
  before_each(function()
    H.coreStub()
    WFJ = H.loadChunks({ "Core/Const.lua", "Core/State.lua" })
  end)

  it("delivers args to handlers in registration order", function()
    local log = {}
    WFJ.State.on("x", function(a, b) log[#log + 1] = "first:" .. a .. b end)
    WFJ.State.on("x", function(a, b) log[#log + 1] = "second:" .. a .. b end)
    assert.are.equal(2, WFJ.State.fire("x", "p", "q"))
    assert.are.same({ "first:pq", "second:pq" }, log)
    assert.are.equal(0, WFJ.State.fire("nobody"))
  end)

  it("setEnabled fires only when the value changes", function()
    local n = 0
    WFJ.State.on("enabled", function() n = n + 1 end)
    assert.is_true(WFJ.State.enabled)
    assert.is_false(WFJ.State.setEnabled(true))
    assert.are.equal(0, n)
    assert.is_true(WFJ.State.setEnabled(false))
    assert.is_false(WFJ.State.setEnabled(false))
    assert.are.equal(1, n)
    assert.is_false(WFJ.State.enabled)
  end)

  it("setArea fires per id only on change; unknown areas read as disabled", function()
    local log = {}
    WFJ.State.on("area", function(id, v) log[#log + 1] = id .. "=" .. tostring(v) end)
    assert.is_false(WFJ.State.areaEnabled("quests"))
    assert.is_true(WFJ.State.setArea("quests", true))
    assert.is_false(WFJ.State.setArea("quests", true))
    assert.is_true(WFJ.State.setArea("quests", false))
    assert.are.same({ "quests=true", "quests=false" }, log)
    assert.is_true(WFJ.State.setArea("gossip", 1)) -- truthy coerces to boolean
    assert.is_true(WFJ.State.areaEnabled("gossip"))
  end)

  it("showsEnglish is the direction crossed with the key: Japanese first shows English while it is held", function()
    local S = WFJ.State
    assert.are.equal("ja", S.direction)
    assert.is_false(S.showsEnglish())
    S.setModifierHeld(true)
    assert.is_true(S.showsEnglish())
    S.setDirection("en")
    assert.is_false(S.showsEnglish()) -- English first, key held: the Japanese
    S.setModifierHeld(false)
    assert.is_true(S.showsEnglish()) -- English first, key up: the English
  end)

  it("fires language with the new value whenever what shows flips, by key or by direction, and only then", function()
    local S, log = WFJ.State, {}
    S.on("language", function(english) log[#log + 1] = english end)
    assert.is_false(S.setDirection("ja")) -- unchanged
    S.setModifierHeld(true)
    S.setModifierHeld(true)
    S.setDirection("en")
    S.setModifierHeld(false)
    S.setDirection("ja")
    assert.are.same({ true, false, true, false }, log)
    assert.is_false(S.setDirection("fr")) -- not a direction: ignored
    assert.are.equal("ja", S.direction)
  end)

  it("setModifierHeld fires only on change", function()
    local n = 0
    WFJ.State.on("modifier", function(v) n = n + 1; assert.is_boolean(v) end)
    assert.is_false(WFJ.State.setModifierHeld(false))
    assert.is_true(WFJ.State.setModifierHeld(true))
    assert.is_false(WFJ.State.setModifierHeld(true))
    assert.are.equal(1, n)
  end)
end)
