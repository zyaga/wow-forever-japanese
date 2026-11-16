local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local Loader = require("tests.lua.spec.loader")

-- Counts the files `loadfile` parses while `fn` runs.
local function parsedDuring(fn)
  local real, parsed = _G.loadfile, {}
  _G.loadfile = function(path, ...)
    parsed[#parsed + 1] = path
    return real(path, ...)
  end
  local ok, err = pcall(fn)
  _G.loadfile = real
  assert(ok, err)
  return parsed
end

local function loadAddon()
  Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
  Stub.installQuestAPI(); Stub.installTooltipAPI(); Stub.installGossipAPI()
  return Loader.load("WoWForeverJapanese")
end

describe("the test helper parses each addon file once per process", function()
  it("a second whole-addon load parses no file again, and still builds a namespace of its own", function()
    local first = loadAddon()
    local second
    local parsed = parsedDuring(function() second = loadAddon() end)
    assert.are.same({}, parsed)
    assert.are_not.equal(first, second)
    assert.are_not.equal(first.Settings, second.Settings)
    assert.is_table(second.Settings)
  end)

  it("a pure load parses its own copy each time: it gives the chunk an environment of its own", function()
    local parsed = parsedDuring(function()
      H.loadPure("Core/Normalize.lua", "WoWForeverJapanese", {})
      H.loadPure("Core/Normalize.lua", "WoWForeverJapanese", {})
    end)
    assert.are.equal(2, #parsed)
  end)
end)
