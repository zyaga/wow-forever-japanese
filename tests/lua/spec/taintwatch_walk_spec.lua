-- UI/TaintWatch's background walk: how much one step may do, when it runs, and that a table left in the middle is
-- finished later. issecurevariable is stubbed: a key listed in `taint` reads as written by the addon named there.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

describe("UI/TaintWatch: the walk", function()
  local WFJ, TW, taint, looked, now

  local function entriesOf(kind)
    local out = {}
    for _, e in ipairs(WFJ_Log.entries) do if e.kind == kind then out[#out + 1] = e end end
    return out
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    WFJ = H.loadChunks({ "Core/Const.lua", "Core/Compat.lua", "Core/Diag.lua", "UI/TaintWatch.lua" })
    WFJ.Compat.init(function(name) return _G[name] end)
    TW = WFJ.TaintWatch
    WFJ_Log = WFJ.Diag.load(nil)
    WFJ.Diag.setDeps({ clock = function() return "2026-10-04 10:00:00" end, print = function() end })
    _G.date = function() return "10:00:00" end
    taint, looked, now = {}, {}, 0
    _G.issecurevariable = function(t, key)
      if key == nil then key, t = t, _G end
      if t ~= _G then looked[key] = (looked[key] or 0) + 1 end
      local by = taint[key] and taint[key].t == t and taint[key].by or nil -- a global: t is _G
      return by == nil, by
    end
    _G.debugstack = function() return "[C]: ?" end
    _G.debugprofilestop = function() return now end
    -- one root of the walk's own list, wide enough to take several steps
    _G.StanceBar = {}
    for i = 1, 1200 do _G.StanceBar["field" .. i] = i end
    taint.field777 = { t = _G.StanceBar, by = "WoWForeverJapanese" }
  end)

  after_each(function()
    _G.issecurevariable, _G.debugstack, _G.debugprofilestop, _G.StanceBar = nil, nil, nil, nil
  end)

  it("reads every key of a table wider than one step exactly once, and finds the tainted one", function()
    TW.finish()
    local seen, twice = 0, 0
    for i = 1, 1200 do
      local n = looked["field" .. i] or 0
      if n >= 1 then seen = seen + 1 end
      if n > 1 then twice = twice + 1 end
    end
    assert.are.equal(1200, seen)
    assert.are.equal(0, twice)
    local found = entriesOf("origin")
    assert.are.equal(1, #found)
    assert.are.equal("StanceBar.field777", found[1].msg)
  end)

  it("a step stops at its key limit and at its time limit", function()
    assert.is_true(TW.originStep() <= TW.ORIGIN_KEYS) -- the step that starts the round
    assert.is_true(TW.originStep() <= TW.ORIGIN_KEYS)
    -- a clock that moves a millisecond per look: the step ends after ORIGIN_MS of them, mid-table
    _G.debugprofilestop = function()
      now = now + 1
      return now
    end
    assert.is_true(TW.originStep() <= TW.ORIGIN_MS + 1)
  end)

  it("a round asked for with a reason ends with the scan's entry: fields by kind and the addon's globals", function()
    taint.WFJ_DB = { t = _G, by = "WoWForeverJapanese" }
    _G.WFJ_DB = {}
    assert.is_true(TW.summaryAfter("block CastSpellByName()"))
    assert.are.equal(0, #entriesOf("taint")) -- nothing is read in the call itself
    TW.finish()
    local scans = entriesOf("taint")
    assert.are.equal(1, #scans)
    assert.are.equal("block CastSpellByName()", scans[1].reason)
    assert.is_truthy(scans[1].fields:find("StanceBar.field777 (WoWForeverJapanese)", 1, true))
    assert.are.equal("WFJ_DB", scans[1].globals)
    _G.WFJ_DB = nil
  end)

  it("the bar sweep reads one bar a call", function()
    local stance, main
    for i, name in ipairs(TW.BARS) do
      if name == "StanceBar" then stance = i elseif name == "MainActionBar" then main = i end
    end
    assert.are.equal(0, TW.sweepBars(main))
    assert.are.equal(0, #entriesOf("turned"))
    assert.are.equal(1, TW.sweepBars(stance))
    assert.are.equal("bar sweep", entriesOf("turned")[1].reason)
    assert.are.equal(0, TW.sweepBars(stance)) -- a field is reported once
  end)

  it("after its round the walk reads nothing until the game refuses an action, and then a set number of times",
    function()
      TW.finish()
      assert.is_true(TW.walkDone())
      looked = {}
      for _ = 1, 50 do assert.are.equal(0, TW.originStep()) end
      assert.is_nil(next(looked))
      for _ = 2, TW.ORIGIN_ROUNDS do
        assert.is_true(TW.walkAgain())
        assert.is_true(TW.walkAgain()) -- asking twice before it ran is one round
        looked = {}
        TW.finish()
        assert.is_true((looked.field1 or 0) >= 1) -- read again in the new round
      end
      assert.is_false(TW.walkAgain())
    end)
end)
