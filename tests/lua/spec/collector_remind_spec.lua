-- Core/CollectorRemind: the once-a-day chat line that collected English is waiting, and when it stays quiet.
local H = require("tests.lua.spec.helpers")

local PLAYER = { name = "Reyn", class = "Hunter", race = "Night Elf" }
local DAY = 86400

local function load()
  H.coreStub()
  local ns = H.loadChunks({ "Core/Const.lua", "Core/Normalize.lua", "Core/Hash.lua", "Core/State.lua",
    "Core/Settings.lua" })
  H.loadPure("Core/Collector.lua", nil, ns)
  H.loadPure("Core/CollectorRemind.lua", nil, ns)
  return ns
end

describe("Core/CollectorRemind.due", function()
  local R
  setup(function() R = load().CollectorRemind end)

  local function state(o)
    local s = { enabled = true, remind = true, readOnly = false, unsent = 12, today = 100, last = 99,
      disclosedNow = false }
    for k, v in pairs(o or {}) do s[k] = v end
    return s
  end

  it("is the count when every condition holds", function()
    assert.are.equal(12, R.due(state()))
    assert.are.equal(10, R.due(state({ unsent = 10 })))
    assert.are.equal(10, R.due(state({ unsent = 10, last = nil }))) -- never reminded before
  end)

  it("is nil when any one condition fails", function()
    assert.is_nil(R.due(state({ remind = false })))
    assert.is_nil(R.due(state({ enabled = false })))
    assert.is_nil(R.due(state({ readOnly = true })))
    assert.is_nil(R.due(state({ unsent = 9 })))
    assert.is_nil(R.due(state({ unsent = 0 })))
    assert.is_nil(R.due(state({ last = 100 }))) -- already reminded today
    assert.is_nil(R.due(state({ disclosedNow = true }))) -- the first-time notice's login
  end)

  it("the line names the count and both commands", function()
    local line = R.line(12)
    assert.is_truthy(line:find("^WFJ: 12 lines of English"))
    assert.is_truthy(line:find("/wfj collector send", 1, true))
    assert.is_truthy(line:find("/wfj collector remind off", 1, true))
  end)
end)

describe("Core/CollectorRemind.run", function()
  local WFJ, R, C, printed, db

  local function record(n)
    for i = 1, n do C.record("quest", 1000 + i, "title", "A Quest Title " .. i) end
  end
  local function say(msg) printed[#printed + 1] = msg end

  before_each(function()
    WFJ = load()
    R, C = WFJ.CollectorRemind, WFJ.Collector
    WFJ.Modifier = { setKey = function() end } -- Settings.load applies every setting, the hold key too
    WFJ.Settings.load(nil, 1, {})
    printed, db = {}, {}
  end)

  it("prints once at 10 unsent lines, keeps the day in the settings table, and stays quiet the rest of that day",
    function()
      local saved = C.load(nil, H.collectorDeps({ player = function() return PLAYER end }))
      record(10)
      local now = 100 * DAY + 3600
      assert.are.equal(10, R.run(db, now, say, false))
      assert.are.same({ R.line(10) }, printed)
      assert.are.equal(100, db.collectorReminded)
      assert.is_nil(saved.collectorReminded) -- the collector's own file gets no time
      for k in pairs(saved) do assert.is_not_equal("reminded", k) end
      assert.is_nil(R.run(db, now + 3600, say, false)) -- a reload the same day
      assert.are.equal(1, #printed)
      assert.are.equal(10, R.run(db, now + DAY, say, false)) -- the next day
      assert.are.equal(2, #printed)
    end)

  it("prints nothing with 9 lines, with the reminder off, or with the collector off", function()
    local on = true
    C.load(nil, H.collectorDeps({ player = function() return PLAYER end, enabled = function() return on end }))
    record(9)
    assert.is_nil(R.run(db, 5 * DAY, say, false))
    record(1)
    WFJ.Settings.set("collector.remind", false)
    assert.is_nil(R.run(db, 5 * DAY, say, false))
    WFJ.Settings.set("collector.remind", true)
    on = false
    assert.is_nil(R.run(db, 5 * DAY, say, false))
    assert.are.same({}, printed)
    assert.is_nil(db.collectorReminded)
  end)

  it("the first-time notice's login counts as today's reminder", function()
    C.load(nil, H.collectorDeps({ player = function() return PLAYER end }))
    record(12)
    assert.is_nil(R.run(db, 7 * DAY, say, true))
    assert.are.equal(7, db.collectorReminded)
    assert.is_nil(R.run(db, 7 * DAY + 60, say, false)) -- a reload later that day
    assert.are.same({}, printed)
  end)

  it("the unsent count equals the send list's length, sent and translated lines left out", function()
    local shipped = {}
    C.load(nil, H.collectorDeps({ player = function() return PLAYER end,
      lookup = function(kind, id) return shipped[kind] and shipped[kind][id] end }))
    record(5)
    shipped["quest.title"] = { [1001] = { ja = "x", status = ".",
      h1 = (WFJ.Hash.h32x2(WFJ.Normalize.v1("A Quest Title 1"))) } }
    assert.are.equal(4, C.unsentCount())
    assert.are.equal(#C.pending(), C.unsentCount())
    assert.are.equal(4, C.status().unsent)
  end)

  it("prints nothing for a collector file from a newer version", function()
    C.load({ version = 2, entries = {}, builds = {} }, H.collectorDeps())
    assert.is_nil(R.run(db, 5 * DAY, say, false))
    assert.are.same({}, printed)
  end)

  it("the setting is on by default and carries both languages", function()
    local def
    for _, d in ipairs(WFJ.Settings.list()) do if d.id == "collector.remind" then def = d end end
    assert.are.equal("boolean", def.kind)
    assert.is_true(def.default)
    assert.is_truthy(def.label:find("Remind", 1, true))
    assert.is_truthy(def.ja:find("知らせる", 1, true))
    assert.is_true(WFJ.Settings.get("collector.remind"))
  end)
end)

describe("the reminder at PLAYER_ENTERING_WORLD", function()
  local Stub = require("tests.lua.spec.wow_stub")
  local Loader = require("tests.lua.spec.loader")

  local function boot(saved)
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI(); Stub.installGossipAPI()
    _G.WFJ_Collector = saved
    _G.WFJ_DB = { schema = 1, settings = {} }
    local WFJ = Loader.load("WoWForeverJapanese")
    Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese")
    return WFJ
  end
  local function reminders()
    local n = 0
    for _, line in ipairs(Stub.prints) do
      if line:find("lines of English the addon has no Japanese for", 1, true) then n = n + 1 end
    end
    return n
  end

  it("prints on login, not on a zone change, and once a day across a reload", function()
    local entries = {}
    for i = 1, 10 do
      entries["quest:" .. (3000 + i) .. ":title"] = { t = "quest", i = 3000 + i, f = "title",
        h = ("%016x"):format(i), e = "Quest " .. i, b = 1 }
    end
    local WFJ = boot({ version = 1, builds = { "1.60.1.70205" }, entries = entries, bytes = 100, disclosed = true })
    Stub.prints = {}
    Stub.fireAll("PLAYER_ENTERING_WORLD", false, false) -- a zone change
    assert.are.equal(0, reminders())
    Stub.fireAll("PLAYER_ENTERING_WORLD", true, false) -- login
    assert.are.equal(1, reminders())
    assert.are.same({}, WFJ.initErrors)
    assert.is_number(_G.WFJ_DB.collectorReminded)
    Stub.fireAll("PLAYER_ENTERING_WORLD", false, true) -- a reload the same day
    assert.are.equal(1, reminders())
  end)

  it("stays quiet on the login that shows the first-time notice", function()
    local entries = {}
    for i = 1, 10 do
      entries["quest:" .. (3000 + i) .. ":title"] = { t = "quest", i = 3000 + i, f = "title",
        h = ("%016x"):format(i), e = "Quest " .. i, b = 1 }
    end
    boot({ version = 1, builds = { "1.60.1.70205" }, entries = entries, bytes = 100 })
    Stub.prints = {}
    Stub.fireAll("PLAYER_ENTERING_WORLD", true, false)
    assert.are.equal(0, reminders())
  end)
end)
