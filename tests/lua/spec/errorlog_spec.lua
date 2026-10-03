-- Core/ErrorLog: the wrap passes every error on, only this addon's errors are kept (counted, trimmed, the name
-- scrubbed), the pre-load buffer, the cap, the chat line, another handler on top, and sent errors.
local H = require("tests.lua.spec.helpers")

local OURS = "Interface/AddOns/WoWForeverJapanese/UI/Tooltip.lua:120: attempt to index a nil value"
local STACK = "[string \"@Interface/AddOns/WoWForeverJapanese/UI/Tooltip.lua\"]:120: in function <...>\n"
  .. "...rface/AddOns/WoWForeverJapanese/UI/MinimapButton.lua:144: in function <...rface/AddOns/"
  .. "WoWForeverJapanese/UI/MinimapButton.lua:141>"
local THEIRS = "Interface/AddOns/OtherAddon/Core.lua:5: bad argument"
local THEIR_STACK = "[string \"@Interface/AddOns/OtherAddon/Core.lua\"]:5: in main chunk"

local function fresh(o)
  o = o or {}
  local ns = {}
  H.loadChunks({ "Core/ErrorLog.lua" }, ns)
  local E = ns.ErrorLog
  local state = { printed = {}, stack = o.stack or STACK, name = o.name, at = "2026-10-03 14:40:00" }
  E.setDeps({ clock = function() return state.at end, name = function() return state.name end,
    stack = function() return state.stack end, print = function(s) state.printed[#state.printed + 1] = s end,
    accessible = o.accessible })
  return E, state
end

describe("Core/ErrorLog", function()
  after_each(function() _G.geterrorhandler, _G.seterrorhandler = nil, nil end)

  it("wraps the handler at file load when the client has one", function()
    local current = function() end
    _G.geterrorhandler = function() return current end
    _G.seterrorhandler = function(fn) current = fn end
    local before = current
    fresh()
    assert.are_not.equal(before, current)
  end)

  it("passes every error to the previous handler once, with its arguments, and returns its result", function()
    local E = fresh()
    local calls = {}
    local prev = function(...) calls[#calls + 1] = { ... }; return "shown" end
    local installed
    assert.is_true(E.install(function() return prev end, function(fn) installed = fn end))
    assert.are.equal("shown", installed(THEIRS, "extra"))
    assert.are.same({ { THEIRS, "extra" } }, calls)
    -- a second install never wraps twice
    assert.is_false(E.install(function() return installed end, function() error("not again") end))
  end)

  it("still passes the error on when recording raises or the message may not be read", function()
    local E, st = fresh({ accessible = function(v) return v ~= "secret" end })
    local n, installed = 0, nil
    E.install(function() return function() n = n + 1 end end, function(fn) installed = fn end)
    E.load({})
    E.setDeps({ clock = function() error("boom") end }) -- recording raises
    installed(OURS)
    E.setDeps({ clock = function() return st.at end })
    installed("secret")
    assert.are.equal(2, n)
    assert.are.equal(0, E.status().count)
  end)

  it("keeps only errors naming a file under WoWForeverJapanese/, in the client's truncated forms too", function()
    local E = fresh()
    assert.is_true(E.isOurs(OURS, ""))
    assert.is_true(E.isOurs("x", STACK))
    assert.is_true(E.isOurs("...rface/AddOns/WoWForeverJapanese/UI/X.lua:1: oops", nil))
    assert.is_true(E.isOurs("...oWForeverJapanese/Data/Reading/Reading_quest_0097.lua:2: oops", nil))
    assert.is_true(E.isOurs("...ForeverJapanese/Data/Reading/Reading_quest_0097.lua:2: oops", nil))
    assert.is_true(E.isOurs("Interface\\AddOns\\WoWForeverJapanese\\Core\\Lookup.lua:3: oops", nil))
    assert.is_false(E.isOurs(THEIRS, THEIR_STACK))
    assert.is_false(E.isOurs("Interface/AddOns/WoWForeverJapaneseX/a.lua:1: x", nil))
    assert.is_false(E.isOurs("Interface/AddOns/WFJProbe/WFJScan.lua:1: x", nil))
    assert.is_false(E.isOurs("Interface/AddOns/MyForeverJapanese/a.lua:1: x", nil))
    assert.is_false(E.isOurs(nil, nil))
  end)

  it("decides by the file the message names, else the top Lua frame; the wrapper's own frames never count", function()
    local E = fresh()
    local WRAP = "...rface/AddOns/WoWForeverJapanese/Core/ErrorLog.lua:146: in function <...ErrorLog.lua:143>"
    -- another addon's error, raised while our code was lower in the call chain: theirs
    assert.is_false(E.isOurs(THEIRS, STACK))
    -- a message naming Blizzard's file while our hook called it: not ours
    assert.is_false(E.isOurs("Interface/AddOns/Blizzard_X/X.lua:9: oops", STACK))
    -- a handler called outside an error: only the wrapper and a [C] frame above the caller
    assert.is_false(E.isOurs("no location", WRAP .. "\n[C]: in function 'pcall'\n" .. THEIR_STACK))
    assert.is_true(E.isOurs("no location", WRAP .. "\n[C]: ?\n" .. STACK))
    assert.is_false(E.isOurs("no location", WRAP))
    assert.is_false(E.isOurs("no location", nil))
  end)

  it("reads the stack at the error's level, offset 0 without an error height, none without the functions", function()
    local E = fresh()
    local asked
    local api = { debugstack = function(level) asked = level; return "s" end, height = function() return 9 end,
      errorHeight = function() return 4 end }
    assert.are.equal("s", E.stack(api))
    assert.are.equal(6, asked) -- 9 - (4 - 1), the client's own formula
    api.errorHeight = function() return nil end
    E.stack(api)
    assert.are.equal(9, asked)
    assert.is_nil(E.stack({ debugstack = api.debugstack }))
    assert.is_nil(E.stack(nil))
  end)

  it("ignores another addon's error", function()
    local E, st = fresh({ stack = THEIR_STACK })
    E.load({})
    assert.is_nil(E.record(THEIRS))
    assert.are.equal(0, E.status().count)
    assert.are.same({}, st.printed)
  end)

  it("stores message, trimmed stack, count, first and last time; a repeat counts; no locals", function()
    local long = {}
    for i = 1, 20 do long[i] = ("...rface/AddOns/WoWForeverJapanese/UI/X.lua:%d: in function <x>"):format(i) end
    local E, st = fresh({ stack = table.concat(long, "\n") })
    local log = {}
    E.load(log)
    local e = E.record(OURS .. string.rep("!", 600))
    assert.are.equal(E.MAX_MESSAGE, #e.msg)
    local lines = select(2, e.stack:gsub("\n", "")) + 1
    assert.is_true(lines <= E.MAX_STACK_LINES)
    assert.is_true(#e.stack <= E.MAX_STACK)
    assert.are.same({ "first", "last", "msg", "n", "stack" }, (function()
      local keys = {}
      for k in pairs(e) do keys[#keys + 1] = k end
      table.sort(keys)
      return keys
    end)())
    st.at = "2026-10-03 15:00:00"
    E.record(OURS .. string.rep("!", 600))
    assert.are.equal(1, #log.errors)
    assert.are.equal(2, log.errors[1].n)
    assert.are.equal("2026-10-03 14:40:00", log.errors[1].first)
    assert.are.equal("2026-10-03 15:00:00", log.errors[1].last)
  end)

  it("writes the player's name as <name>, whole words only", function()
    local E = fresh({ name = "Reyn" })
    assert.are.equal("<name> hit Reynolds; <name>.", E.scrub("Reyn hit Reynolds; Reyn.", "Reyn"))
    assert.are.equal("Ünaxö", E.scrub("Ünaxö", "naxö")) -- inside a word with a non-ASCII letter: left alone
    E.load({})
    local e = E.record("Interface/AddOns/WoWForeverJapanese/UI/A.lua:1: Reyn is nil")
    assert.are.equal("Interface/AddOns/WoWForeverJapanese/UI/A.lua:1: <name> is nil", e.msg)
  end)

  it("keeps a file named like the player, and scrubs before cutting so no part of the name is left", function()
    local E = fresh({ name = "Main" })
    assert.are.equal("Interface/AddOns/WoWForeverJapanese/Main.lua:5: <name> is nil",
      E.scrub("Interface/AddOns/WoWForeverJapanese/Main.lua:5: Main is nil", "Main"))
    E.load({})
    local msg = "Interface/AddOns/WoWForeverJapanese/UI/A.lua:1: " .. string.rep("x", E.MAX_MESSAGE - 52) .. " Main"
    local e = E.record(msg)
    assert.is_nil(e.msg:find("Mai", 1, true))
  end)

  it("scrubs errors recorded before the name was known once it is", function()
    local E, st = fresh()
    local log = {}
    E.load(log)
    E.record("Interface/AddOns/WoWForeverJapanese/UI/A.lua:1: Reyn is nil")
    st.name = "Reyn"
    assert.are.equal(1, E.rescrub())
    assert.is_nil(log.errors[1].msg:find("Reyn", 1, true))
  end)

  it("stores errors caught before the log loaded, and says so once", function()
    local E, st = fresh({ name = "Reyn" })
    E.record(OURS)
    E.record(OURS)
    assert.are.same({}, st.printed) -- nothing printed before the log loads
    local log = { version = 1, entries = {} }
    local list = E.load(log)
    assert.are.equal(log.errors, list)
    assert.are.equal(1, #list)
    assert.are.equal(2, list[1].n)
    assert.are.same({ E.SAY }, st.printed)
    -- a log from another load keeps its errors
    local E2 = fresh()
    assert.are.equal(1, #E2.load(log))
  end)

  it("keeps at most MAX_ERRORS: the oldest sent goes first; with none sent the first errors stay", function()
    local E = fresh()
    local log = {}
    E.load(log)
    local function err(i) return ("Interface/AddOns/WoWForeverJapanese/UI/A.lua:%d: x"):format(i) end
    for i = 1, E.MAX_ERRORS do E.record(err(i)) end
    E.markSent({ { msg = err(5), last = log.errors[5].last, n = 1 } })
    E.record(err(100))
    assert.are.equal(E.MAX_ERRORS, #log.errors)
    for _, e in ipairs(log.errors) do assert.are_not.equal(err(5), e.msg) end
    assert.is_nil(E.record(err(101))) -- full, none sent: the newest is dropped, the first (the cause) kept
    assert.are.equal(err(1), log.errors[1].msg)
    assert.are.equal(err(100), log.errors[#log.errors].msg)
  end)

  it("one entry for an error raised on a different table each time", function()
    local E = fresh()
    local log = {}
    E.load(log)
    for i = 1, 40 do
      E.record(("Interface/AddOns/WoWForeverJapanese/UI/A.lua:3: bad self (table: 0x%08x)"):format(i * 4096))
      E.record(("Interface/AddOns/WoWForeverJapanese/UI/A.lua:4: bad self (table: %016X)"):format(i * 4096))
    end
    assert.are.equal(2, #log.errors)
    assert.are.same({ 40, 40 }, { log.errors[1].n, log.errors[2].n })
  end)

  it("adds the counts of errors caught before the log loaded, and stamps them with the time", function()
    local E, st = fresh()
    st.at = ""
    E.record(OURS)
    E.record(OURS)
    E.record(OURS)
    st.at = "2026-10-03 14:41:00"
    local log = { errors = { { msg = OURS, stack = "", n = 2, first = "2026-10-02 10:00:00",
      last = "2026-10-02 10:05:00" } } }
    E.load(log)
    assert.are.equal(5, log.errors[1].n)
    assert.are.equal("2026-10-03 14:41:00", log.errors[1].last)
  end)

  it("drops saved entries it cannot read and records errors the addon caught itself", function()
    local E = fresh()
    local log = { errors = { "junk", { msg = 5 }, { msg = OURS, n = "x" } } }
    E.load(log)
    assert.are.equal(1, #log.errors)
    assert.are.equal(1, log.errors[1].n)
    assert.is_not_nil(E.recordCaught("Interface/AddOns/WoWForeverJapanese/UI/Bags.lua:7: setup failed"))
    assert.is_nil(E.recordCaught(THEIRS))
    assert.are.equal(2, E.status().count)
  end)

  it("prints one chat line for the first error of a session", function()
    local E, st = fresh()
    E.load({})
    E.record(OURS)
    E.record("Interface/AddOns/WoWForeverJapanese/UI/B.lua:9: other")
    assert.are.same({ "WFJ: the addon hit a Lua error. /wfj bug reports it." }, st.printed)
  end)

  it("knows when another handler replaced ours (BugGrabber), unless an error still reached it", function()
    local E = fresh()
    assert.is_false(E.ours()) -- nothing installed
    local installed
    E.install(function() return nil end, function(fn) installed = fn end)
    assert.is_true(E.ours())
    assert.is_true(E.checkOurs(function() return installed end))
    assert.is_false(E.checkOurs(function() return function() end end))
    E.load({})
    installed(OURS) -- another addon that chains still hands errors on to us
    assert.is_true(E.ours())
  end)

  it("marks only the shown errors sent; a repeat after that, or after showing, counts as new", function()
    local E, st = fresh()
    local log = {}
    E.load(log)
    E.record(OURS)
    local shown = { { msg = log.errors[1].msg, last = log.errors[1].last, n = 1 } }
    st.at = "2026-10-03 14:41:00"
    E.record("Interface/AddOns/WoWForeverJapanese/UI/B.lua:9: other")
    assert.are.equal(1, E.markSent(shown))
    assert.are.equal(1, #E.unsent())
    assert.are.same({ count = 2, unsent = 1 }, E.status())
    st.at = "2026-10-03 14:50:00"
    E.record(OURS) -- happens again: new for the next report
    assert.are.equal(2, #E.unsent())
    assert.are.equal(1, log.errors[1].n)
    assert.are.equal("2026-10-03 14:50:00", log.errors[1].first)
    -- shown, then repeated before I sent it: that occurrence was not in the report
    local again = { { msg = log.errors[1].msg, last = log.errors[1].last, n = log.errors[1].n } }
    E.record(OURS) -- the same second: the count tells the occurrences apart
    assert.are.equal(0, E.markSent(again))
  end)
end)
