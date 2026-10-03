-- Core/Diag: the diagnostics log (load, log, cap), hook watching, blocked actions and the session entry.
local H = require("tests.lua.spec.helpers")

local function fresh()
  local ns = {}
  H.loadPure("Core/Diag.lua", "WoWForeverJapanese", ns)
  local printed = {}
  ns.Diag.setDeps({ now = function() return 12.7 end, mem = function() return 2048.4 end,
    clock = function() return "2026-10-03 14:40:00" end, print = function(s) printed[#printed + 1] = s end })
  return ns.Diag, printed
end

describe("Core/Diag", function()
  it("starts a fresh log for a missing or other-version table and keeps a current one", function()
    local D = fresh()
    assert.are.same({ version = 1, entries = {} }, D.load(nil))
    assert.are.same({ version = 1, entries = {} }, D.load({ version = 2, entries = { {} } }))
    local kept = { version = 1, entries = { { kind = "session" } } }
    assert.are.equal(kept, D.load(kept))
  end)

  it("writes kind, message, time, uptime and memory; fields keep plain values only; the oldest go first", function()
    local D = fresh()
    local db = D.load(nil)
    local e = D.log("memory", "sample", { count = 3, ok = true, t = {} })
    assert.are.same({ kind = "memory", msg = "sample", at = "2026-10-03 14:40:00", up = 12, memKB = 2048, count = 3,
      ok = true, t = "table" }, e)
    for i = 1, D.MAX_ENTRIES + 5 do D.log("x", tostring(i)) end
    assert.are.equal(D.MAX_ENTRIES, #db.entries)
    assert.are.equal(tostring(6), db.entries[1].msg)
  end)

  it("a repeat in the session counts on its entry; sessions are kept when the oldest are dropped", function()
    local D = fresh()
    local db = D.load(nil)
    D.session({ build = "b", version = "v" })
    for _ = 1, 3 do D.onBlocked("ADDON_ACTION_BLOCKED", "WoWForeverJapanese", "MainActionBar:SetPointBase()",
      "WoWForeverJapanese") end
    assert.are.equal(2, #db.entries)
    assert.are.same({ 3, "2026-10-03 14:40:00" }, { db.entries[2].n, db.entries[2].last })
    assert.matches("×3", D.lines(1)[1])
    for i = 1, D.MAX_ENTRIES + 5 do D.log("x", tostring(i)) end
    assert.are.equal("session", db.entries[1].kind)
    assert.are.equal(D.MAX_ENTRIES, #db.entries)
  end)

  it("logs a watched hook once when it stops being a function, with where it went", function()
    local D, printed = fresh()
    local db = D.load(nil)
    local frame = setmetatable({}, { __index = { AddMessage = function() end } })
    frame.AddMessage = function() end
    assert.is_true(D.watch(frame, "AddMessage", "ChatFrame1"))
    assert.is_false(D.watch(frame, "AddMessage", "ChatFrame1"))
    assert.are.equal(0, D.checkHooks())
    frame.AddMessage = nil
    getmetatable(frame).__index.AddMessage = nil
    assert.are.equal(1, D.checkHooks())
    assert.are.equal(0, D.checkHooks())
    local e = db.entries[1]
    assert.are.same({ "hook", "ChatFrame1", "AddMessage", "nil", "nil", "nil" },
      { e.kind, e.frame, e.method, e.seen, e.own, e.inherited })
    assert.are.equal(1, #printed)
  end)

  it("logs a blocked action only when it names this addon, and the session with any failed setup", function()
    local D = fresh()
    local db = D.load(nil)
    assert.is_nil(D.onBlocked("ADDON_ACTION_BLOCKED", "OtherAddon", "CastSpell()", "WoWForeverJapanese"))
    local e = D.onBlocked("ADDON_ACTION_FORBIDDEN", "WoWForeverJapanese", "UNKNOWN()", "WoWForeverJapanese")
    assert.are.same({ "blocked", "UNKNOWN()", "ADDON_ACTION_FORBIDDEN" }, { e.kind, e.fn, e.event })
    D.initFailed("gossip", "boom")
    D.session({ build = "1.60.1.70205", version = "0.1.0", initErrors = { { surface = "gossip", err = "boom" } } })
    assert.are.same({ "init", "gossip", "boom" }, { db.entries[2].kind, db.entries[2].msg, db.entries[2].err })
    assert.are.same({ "session", "gossip" }, { db.entries[3].kind, db.entries[3].failed })
    assert.are.equal(3, #D.lines(10))
    -- the count is clamped to whole lines, 1..MAX_LINES
    assert.are.equal(2, #D.lines(2.5))
    assert.are.equal(1, #D.lines(0))
    assert.are.equal(3, #D.lines(1e9))
    assert.are.equal(3, #D.lines("x"))
  end)

  it("over the cap a memory sample goes first, then a problem; sessions are capped on their own", function()
    local D = fresh()
    local db = D.load(nil)
    for i = 1, D.MAX_SESSIONS + 3 do D.session({ build = tostring(i) }) end
    local sessions = 0
    for _, e in ipairs(db.entries) do if e.kind == "session" then sessions = sessions + 1 end end
    assert.are.equal(D.MAX_SESSIONS, sessions)
    assert.are.equal("4", db.entries[1].build)
    D.log("memory", "sample")
    for i = 1, D.MAX_ENTRIES - D.MAX_SESSIONS - 1 do D.log("blocked", tostring(i)) end
    assert.are.equal(D.MAX_ENTRIES, #db.entries)
    D.log("hook", "new")
    assert.are.equal("hook", db.entries[#db.entries].kind) -- the new problem is kept
    for _, e in ipairs(db.entries) do assert.are_not.equal("memory", e.kind) end
    D.log("hook", "newer")
    assert.are.equal("newer", db.entries[#db.entries].msg)
    assert.are.equal("2", (function()
      for _, e in ipairs(db.entries) do if e.kind == "blocked" then return e.msg end end
    end)()) -- the oldest problem went
  end)

  it("a hook another function replaced is gone too; an entry's own fields are never overwritten", function()
    local D = fresh()
    local db = D.load(nil)
    local frame = { AddMessage = function() end }
    D.watch(frame, "AddMessage", "ChatFrame1")
    frame.AddMessage = function() end -- a mixin applied again: our wrapper is gone
    assert.are.equal(1, D.checkHooks())
    assert.are.equal("replaced", db.entries[1].seen)
    local e = D.log("x", "y", { kind = "other", n = 9, last = "never", extra = 1 })
    assert.are.same({ "x", nil, nil, 1 }, { e.kind, e.n, e.last, e.extra })
  end)
end)
