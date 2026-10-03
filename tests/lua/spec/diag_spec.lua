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
    local e = D.log("memory", "sample", { n = 3, ok = true, t = {} })
    assert.are.same({ kind = "memory", msg = "sample", at = "2026-10-03 14:40:00", up = 12, memKB = 2048, n = 3,
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
    D.session({ build = "1.60.1.70205", version = "0.1.0", initErrors = { { surface = "gossip", err = "boom" } } })
    assert.are.same({ "session", "gossip" }, { db.entries[2].kind, db.entries[2].failed })
    assert.are.same({ "init", "gossip", "boom" }, { db.entries[3].kind, db.entries[3].msg, db.entries[3].err })
    assert.are.equal(3, #D.lines(10))
  end)
end)
