local H = require("tests.lua.spec.helpers")

describe("Compat: resolver over an injected env", function()
  local WFJ, world
  before_each(function()
    WFJ = {}
    H.loadPure("Core/Compat.lua", "WoWForeverJapanese", WFJ)
    world = {}
    WFJ.Compat.init(function(name) return world[name] end)
  end)

  it("returns the first candidate the env resolves, else nil", function()
    world.QuestInfoDescriptionText = "desc-widget"
    WFJ.Compat.declare("quest", "description", { "QuestDescriptionText", "QuestInfoDescriptionText" })
    WFJ.Compat.declare("quest", "reward", { "QuestInfoRewardText" })
    assert.are.equal("desc-widget", WFJ.Compat.get("quest", "description"))
    assert.is_nil(WFJ.Compat.get("quest", "reward"))
    assert.is_nil(WFJ.Compat.get("nobody", "nothing"))
  end)

  it("lists unresolved declarations sorted", function()
    world.B = true
    WFJ.Compat.declare("tooltip", "line", { "B" })
    WFJ.Compat.declare("quest", "title", { "Nope" })
    WFJ.Compat.declare("gossip", "greeting", { "Nope2" })
    assert.are.same({ "gossip.greeting", "quest.title" }, WFJ.Compat.unresolved())
  end)

  it("memoizes a resolution until re-declared or re-initialized", function()
    WFJ.Compat.declare("s", "k", { "X" })
    assert.is_nil(WFJ.Compat.get("s", "k"))
    world.X = "late"
    assert.is_nil(WFJ.Compat.get("s", "k"))
    WFJ.Compat.declare("s", "k", { "X" })
    assert.are.equal("late", WFJ.Compat.get("s", "k"))
    world.X = nil
    WFJ.Compat.init(function(name) return world[name] end)
    assert.is_nil(WFJ.Compat.get("s", "k"))
  end)

  it("treats a `false` global as unresolved, consistently", function()
    world.Flag = false
    WFJ.Compat.declare("s", "flag", { "Flag" })
    assert.is_nil(WFJ.Compat.get("s", "flag"))
    assert.is_nil(WFJ.Compat.get("s", "flag"))
    assert.are.same({ "s.flag" }, WFJ.Compat.unresolved())
  end)

  it("returns nil when the canvas registration yields no category", function()
    local addOnCalls = 0
    world.Settings = {
      RegisterCanvasLayoutCategory = function() return nil end,
      RegisterAddOnCategory = function() addOnCalls = addOnCalls + 1 end,
    }
    assert.is_nil(WFJ.Compat.registerOptions({}, "WFJ"))
    assert.are.equal(0, addOnCalls)
    assert.is_false(WFJ.Compat.openOptions())
  end)

  it("registers the pages through the Settings API (parent, AddOns, subcategories) and opens each by id", function()
    local calls = {}
    world.Settings = {
      RegisterCanvasLayoutCategory = function(frame, name)
        calls[#calls + 1] = "canvas:" .. name
        return { frame = frame, GetID = function() return 7 end }
      end,
      RegisterAddOnCategory = function() calls[#calls + 1] = "addon" end,
      RegisterCanvasLayoutSubcategory = function(parent, _, name)
        calls[#calls + 1] = "sub:" .. name .. ":" .. parent:GetID()
        local id = name == "Two" and 8 or 9
        return { GetID = function() return id end }
      end,
      OpenToCategory = function(id) calls[#calls + 1] = "open:" .. tostring(id) end,
    }
    assert.is_false(WFJ.Compat.openOptions())
    local pages = { { id = "main", frame = {}, name = "WFJ" }, { id = "two", frame = {}, name = "Two" },
      { id = "three", frame = {}, name = "Three" } }
    assert.are.equal(7, WFJ.Compat.registerOptions(pages))
    assert.is_true(WFJ.Compat.openOptions())
    assert.is_true(WFJ.Compat.openOptions("three"))
    assert.is_true(WFJ.Compat.openOptions("nope"))
    -- subcategories before RegisterAddOnCategory, "the last step" (Blizzard_ImplementationReadme.lua:42–43)
    assert.are.same({ "canvas:WFJ", "sub:Two:7", "sub:Three:7", "addon", "open:7", "open:9", "open:7" }, calls)
  end)

  it("degrades to nil / false when the Settings API is absent, and to the parent without subcategories", function()
    local pages = { { id = "main", frame = {}, name = "WFJ" }, { id = "two", frame = {}, name = "Two" } }
    assert.is_nil(WFJ.Compat.registerOptions(pages))
    assert.is_false(WFJ.Compat.openOptions())
    world.Settings = { RegisterCanvasLayoutCategory = function() end } -- half an API is no API
    assert.is_nil(WFJ.Compat.registerOptions(pages))
    local opened
    world.Settings = {
      RegisterCanvasLayoutCategory = function() return { GetID = function() return 5 end } end,
      RegisterAddOnCategory = function() end,
      OpenToCategory = function(id) opened = id end,
    }
    assert.are.equal(5, WFJ.Compat.registerOptions(pages))
    assert.is_true(WFJ.Compat.openOptions("two"))
    assert.are.equal(5, opened)
  end)

  it("reports addon memory only when the API exists", function()
    assert.is_nil(WFJ.Compat.memoryKB())
    local updated = false
    world.UpdateAddOnMemoryUsage = function() updated = true end
    world.GetAddOnMemoryUsage = function(name) return name == "WoWForeverJapanese" and 512 or 0 end
    assert.are.equal(512, WFJ.Compat.memoryKB())
    assert.is_true(updated)
    world.GetAddOnMemoryUsage = function() error("boom") end
    assert.is_nil(WFJ.Compat.memoryKB())
  end)

  it("contains no frame access or _G in the source (lint-core-gate)", function()
    local src = H.readFile("addon/WoWForeverJapanese/Core/Compat.lua")
    assert.is_nil(src:find("_G", 1, true))
    assert.is_nil(src:find("CreateFrame(", 1, true))
  end)
end)
