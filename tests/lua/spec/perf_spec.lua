-- Core/Perf: per-frame timing of the addon's write paths, the slow-frame log, the session report and the trail.
local H = require("tests.lua.spec.helpers")

local function fresh()
  local ns = {}
  H.loadPure("Core/Diag.lua", "WoWForeverJapanese", ns)
  H.loadPure("Core/Perf.lua", "WoWForeverJapanese", ns)
  ns.Diag.setDeps({ now = function() return 1 end, mem = function() return 0 end,
    clock = function() return "2026-11-07 17:00:00" end, print = function() end })
  local db = ns.Diag.load(nil)
  local w = { ms = 0, kb = 100, frame = 1, trail = {} }
  ns.Perf.setDeps({ clock = function() return w.ms end, mem = function(what) return what == "count" and w.kb end,
    frame = function() return w.frame end, trail = function(label) w.trail[#w.trail + 1] = label end })
  return ns.Perf, db, w
end

local function slowEntries(db)
  local out = {}
  for _, e in ipairs(db.entries) do if e.kind == "slow" then out[#out + 1] = e end end
  return out
end

-- one timed call of `ms` milliseconds allocating `kb` KB under `label`
local function call(P, w, label, ms, kb)
  local t0, k0 = P.start(label)
  w.ms, w.kb = w.ms + ms, w.kb + (kb or 0)
  P.stop(label, t0, k0)
end

describe("Core/Perf", function()
  it("logs a label whose frame total passed SLOW_MS once, when a later frame starts; a quick label logs nothing",
    function()
      local P, D, w = fresh()
      call(P, w, "items", P.SLOW_MS - 2, 40)
      call(P, w, "items", 3, 10)
      call(P, w, "quest", 1)
      assert.are.equal(0, #slowEntries(D)) -- the frame is not over yet
      w.frame = 2
      call(P, w, "quest", 1)
      local slow = slowEntries(D)
      assert.are.equal(1, #slow)
      assert.are.equal("items", slow[1].msg)
      assert.are.same({ P.SLOW_MS + 1, 50, 2 }, { slow[1].ms, slow[1].kb, slow[1].calls })
    end)

  it("a repeat raises n and keeps the largest frame time", function()
    local P, D, w = fresh()
    call(P, w, "items", P.SLOW_MS + 4)
    w.frame = 2
    call(P, w, "items", P.SLOW_MS + 1)
    w.frame = 3
    call(P, w, "items", 0)
    local slow = slowEntries(D)
    assert.are.equal(1, #slow)
    assert.are.same({ 2, P.SLOW_MS + 4 }, { slow[1].n, slow[1].ms })
  end)

  it("counts only the outermost call of a label, so a pass that calls itself is not counted twice", function()
    local P, _, w = fresh()
    local t0, k0 = P.start("help")
    call(P, w, "help", 5)
    w.ms = w.ms + 1
    P.stop("help", t0, k0)
    local r = P.report(10)
    assert.are.same({ label = "help", calls = 1, ms = 6, max = 6 }, r[1])
  end)

  it("a label left open by an error in an earlier frame counts again from the next frame", function()
    local P, _, w = fresh()
    P.start("items") -- the call raised before its stop
    w.frame = 2
    call(P, w, "items", 2)
    assert.are.equal(1, P.report(10)[1].calls)
  end)

  it("reports the session's labels by total time, at most n, and reset empties them", function()
    local P, _, w = fresh()
    call(P, w, "a", 1)
    call(P, w, "b", 5)
    call(P, w, "b", 2)
    call(P, w, "c", 3)
    local r = P.report(2)
    assert.are.same({ { label = "b", calls = 2, ms = 7, max = 5 }, { label = "c", calls = 1, ms = 3, max = 3 } }, r)
    P.reset()
    assert.are.same({}, P.report(10))
  end)

  it("hands each finished frame's labels to the trail as one line, in the order they ran", function()
    local P, _, w = fresh()
    call(P, w, "items", 1)
    call(P, w, "quest", 1)
    call(P, w, "items", 1)
    assert.are.same({}, w.trail) -- the frame is still running
    w.frame = 2
    call(P, w, "items", 1)
    w.frame = 3
    call(P, w, "items", 1)
    P.flush() -- the taint watch reads the ring: the frame so far goes in too
    assert.are.same({ "items quest", "items", "items" }, w.trail)
    P.flush()
    assert.are.equal(3, #w.trail) -- nothing timed since
  end)

  it("does nothing without its clock, and a stop with no start is ignored", function()
    local ns = {}
    H.loadPure("Core/Perf.lua", "WoWForeverJapanese", ns)
    local t0, k0 = ns.Perf.start("x")
    assert.is_nil(t0)
    ns.Perf.stop("x", t0, k0)
    assert.are.same({}, ns.Perf.report(10))
  end)
end)
