-- a load-on-demand Blizzard addon's setup runs now when it is loaded, otherwise once on its ADDON_LOADED.
local H = require("tests.lua.spec.helpers")

describe("UI/LoadOnDemand", function()
  local LOD, loaded

  before_each(function()
    local ns = {}
    H.loadChunk("UI/LoadOnDemand.lua", "WoWForeverJapanese", ns)
    LOD = ns.LoadOnDemand
    loaded = {}
    LOD.init(function(name) return loaded[name] == true end)
  end)

  it("runs immediately for an addon that is already loaded", function()
    loaded.Blizzard_TalentUI = true
    local ran = 0
    assert.is_true(LOD.when("Blizzard_TalentUI", function() ran = ran + 1 end))
    assert.are.equal(1, ran)
    assert.are.equal(0, LOD.loaded("Blizzard_TalentUI")) -- nothing left waiting
  end)

  it("waits for that addon's ADDON_LOADED, runs once, and ignores other addons", function()
    local ran = {}
    assert.is_false(LOD.when("Blizzard_TrainerUI", function() ran[#ran + 1] = "a" end))
    LOD.when("Blizzard_TrainerUI", function() ran[#ran + 1] = "b" end)
    assert.are.equal(0, LOD.loaded("Blizzard_RaidUI"))
    assert.are.same({}, ran)
    assert.are.equal(2, LOD.loaded("Blizzard_TrainerUI"))
    assert.are.same({ "a", "b" }, ran)
    assert.are.equal(0, LOD.loaded("Blizzard_TrainerUI"))
    assert.are.same({ "a", "b" }, ran)
  end)

  it("a setup that errors does not stop the others; the error is raised after they ran", function()
    local ran = {}
    LOD.when("Blizzard_RaidUI", function() error("boom") end)
    LOD.when("Blizzard_RaidUI", function() ran[#ran + 1] = "second" end)
    assert.has_error(function() LOD.loaded("Blizzard_RaidUI") end, "boom")
    assert.are.same({ "second" }, ran)
  end)
end)
