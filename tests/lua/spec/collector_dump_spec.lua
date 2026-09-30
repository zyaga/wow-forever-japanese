-- the scripted session's SavedVariables text is the committed round-trip fixture the pipeline imports
-- (tests/python/test_import_collector.py). Regenerate after a deliberate change: WFJ_WRITE_FIXTURES=1 make test-lua
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local Loader = require("tests.lua.spec.loader")

local FIXTURE = "tests/fixtures/collector/WoWForeverJapanese.lua"

describe("collector dump fixture", function()
  it("the stub session serializes byte-identically to the committed fixture", function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI(); Stub.installGossipAPI()
    Loader.load("WoWForeverJapanese")
    Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese")
    Stub.fireAll("PLAYER_ENTERING_WORLD")
    require("tests.lua.spec.collector_session").run()
    local text = Stub.serializeSavedVariables({ "WFJ_DB", "WFJ_Collector" })

    if os.getenv("WFJ_WRITE_FIXTURES") == "1" then
      local f = assert(io.open(H.ROOT .. "/" .. FIXTURE, "w"))
      f:write(text)
      f:close()
    end
    assert.are.equal(H.readFile(FIXTURE), text)
    assert.are.same({ "1.15.9.69722" }, WFJ_Collector.builds)
    -- the file loads back as Lua and keeps its shape
    local chunk = assert(loadstring(text))
    local env = {}
    setfenv(chunk, env)
    chunk()
    assert.are.same(WFJ_Collector, env.WFJ_Collector)
  end)
end)
