-- UI/Font: the bundled face offered to the shared font registry (LibSharedMedia-3.0) when another addon has loaded
-- it, so an addon that lets the player pick a font can draw Japanese. The registry here is a stand-in with the
-- real one's Register(mediatype, key, data, langmask) and its western bit.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local Loader = require("tests.lua.spec.loader")

-- The whole addon through ADDON_LOADED, with `libStub` as the global LibStub (nil: none installed).
local function boot(libStub)
  Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
  Stub.installQuestAPI(); Stub.installTooltipAPI(); Stub.installGossipAPI()
  _G.LibStub = libStub
  _G.WFJ_DB = nil
  local WFJ = Loader.load("WoWForeverJapanese")
  Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese")
  return WFJ
end

-- A LibStub whose LibSharedMedia-3.0 records every Register call. `register` replaces what Register does.
local function registry(register)
  local calls, asked = {}, {}
  local lib = { LOCALE_BIT_western = 128 }
  function lib.Register(_, mediatype, key, data, langmask)
    calls[#calls + 1] = { mediatype = mediatype, key = key, data = data, langmask = langmask }
    if register then return register() end
    return true
  end
  local stub = setmetatable({}, { __call = function(_, major, silent)
    asked[#asked + 1] = { major = major, silent = silent }
    if major == "LibSharedMedia-3.0" then return lib end
    if not silent then error("no such library: " .. tostring(major)) end
    return nil
  end })
  return stub, calls, asked
end

describe("UI/Font: the shared font registry", function()
  after_each(function() _G.LibStub = nil end)

  it("registers the bundled face once, under the addon's name, asking for the registry silently", function()
    local stub, calls, asked = registry()
    local WFJ = boot(stub)
    assert.is_true(WFJ.loaded)
    assert.are.same({ { mediatype = "font", key = "WoW Forever Japanese", data = WFJ.Font.PATH, langmask = 128 } },
      calls)
    assert.are.same({ major = "LibSharedMedia-3.0", silent = true }, asked[1])
    assert.is_false(WFJ.Font.share()) -- already offered this session
    assert.are.equal(1, #calls)
  end)

  it("does nothing, and raises nothing, with no LibStub at all", function()
    local WFJ = boot(nil)
    assert.is_true(WFJ.loaded)
    assert.is_false(WFJ.Font.share())
  end)

  it("does nothing when LibStub has no shared font registry", function()
    local asked = {}
    local stub = setmetatable({}, { __call = function(_, major, silent)
      asked[#asked + 1] = { major = major, silent = silent }
      if not silent then error("no such library: " .. tostring(major)) end
      return nil
    end })
    local WFJ = boot(stub)
    assert.is_true(WFJ.loaded)
    assert.are.same({ major = "LibSharedMedia-3.0", silent = true }, asked[1])
    assert.is_false(WFJ.Font.share())
  end)

  it("a registry that raises, or turns the font down, never stops the load", function()
    local stub, calls = registry(function() error("registry broke") end)
    local WFJ = boot(stub)
    assert.is_true(WFJ.loaded)
    assert.are.equal(1, #calls)
    local stub2, calls2 = registry(function() return false end)
    WFJ = boot(stub2)
    assert.is_true(WFJ.loaded)
    assert.are.equal(1, #calls2)
  end)
end)
