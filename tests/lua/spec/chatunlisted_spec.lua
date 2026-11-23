-- UI/ChatUnlisted over a chat frame that keeps a history: a game-written chat line nothing translates gives the
-- collector the name of the interface string it was written from, and never its text.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local UI = {
  ERR_GROUP_FULL = { "Your party is full.", "パーティーがいっぱいです。" },
  -- a row that is no chat key: its line stays English, and its name is no news
  WINDOW_ONLY_TEMPLATE = { "%s is very far away.", "%sはとても遠くにいます。" },
}
-- the client's interface strings nobody listed
local STRINGS = {
  DRUNK_MESSAGE_OTHER1 = "%s seems to be sobering up.",
  TWIN_NOTICE_ONE = "%s has entered the arena.",
  TWIN_NOTICE_TWO = "%s has entered the arena.",
  GATES_NOTICE = "The gates are now open.",
  PLURAL_NOTICE = "%d |4player:players; joined the fight.",
  LABEL_PAIR = "%s: %s",
  LABEL_AND = "%s and %s",
  LABEL_RANK = "Rank %d",
  ONE_WORD = "Tipsy",
}
local NAMES = { "CHAT_FRAMES", "ChatTypeInfo", "ChatFrame1", "issecretvalue", "C_Timer", "debugprofilestop",
  "InCombatLockdown", "lowercase_string", "A_TABLE" }
local SYSTEM, SAY = 1, 2

local function chatFrame()
  local frame = { history = {} }
  function frame:AddMessage(message, r, g, b, ...)
    self.history[#self.history + 1] = { message = message, r = r, g = g, b = b, extra = { ... } }
  end
  function frame:TransformMessages(predicate, transform)
    for _, e in ipairs(self.history) do
      if predicate(e.message, e.r, e.g, e.b, unpack(e.extra)) then
        e.message = transform(e.message, e.r, e.g, e.b, unpack(e.extra))
      end
    end
  end
  function frame:Last() return self.history[#self.history].message end
  return frame
end

describe("chat lines no interface string was listed for", function()
  local WFJ, U, C, db, frame, timers, secrets, combat, now, tick, calls

  local function system(text) frame:AddMessage(text, 1, 1, 0, SYSTEM) end
  -- every frame the timer asked for, until none is left → frames run
  local function frames()
    local n = 0
    while #timers > 0 do
      local fn = table.remove(timers, 1)
      fn()
      n = n + 1
      assert.is_true(n < 10000)
    end
    return n
  end
  local function entries()
    local keys = {}
    for key in pairs(db.entries) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
  end
  -- every string anywhere in a saved table
  local function strings(t, out)
    out = out or {}
    for k, v in pairs(t) do
      if type(k) == "string" then out[#out + 1] = k end
      if type(v) == "string" then out[#out + 1] = v end
      if type(v) == "table" then strings(v, out) end
    end
    return out
  end

  before_each(function()
    timers, secrets, combat, now, tick, calls = {}, {}, false, 0, 0, {}
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    local files = {}
    for i, f in ipairs(H.UI_FILES) do files[i] = f end
    for _, f in ipairs({ "UI/Errors.lua", "UI/ChatSystem.lua", "UI/ChatUnlisted.lua" }) do files[#files + 1] = f end
    WFJ = H.loadChunks(files)
    _G.ChatTypeInfo = { SYSTEM = { id = SYSTEM }, SAY = { id = SAY } }
    _G.ChatFrame1 = chatFrame()
    _G.CHAT_FRAMES = { "ChatFrame1" }
    _G.issecretvalue = function(v) return secrets[v] == true end
    _G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
    _G.debugprofilestop = function()
      now = now + tick
      return now
    end
    _G.InCombatLockdown = function() return combat end
    for name, text in pairs(STRINGS) do _G[name] = text end
    _G.lowercase_string = "%s seems to be sobering up, quietly."
    _G.A_TABLE = { "%s seems to be sobering up." }
    H.uiSetup(WFJ, UI)
    U, C, frame = WFJ.ChatUnlisted, WFJ.Collector, _G.ChatFrame1
    local deps = H.collectorDeps({ enabled = function() return WFJ.Settings.get("collector.enabled") end })
    deps.uiKey = function(name) return WFJ.UIIndex.rows[name] ~= nil end
    db = C.load(nil, deps)
    local record = C.recordUiKey
    C.recordUiKey = function(name)
      calls[#calls + 1] = name
      return record(name)
    end
    assert.is_true(WFJ.ChatSystem.init())
  end)
  after_each(function()
    H.uiTeardown()
    for _, n in ipairs(NAMES) do _G[n] = nil end
    for name in pairs(STRINGS) do _G[name] = nil end
  end)

  it("keeps the string's name for an untranslated system line, and nothing of the line", function()
    system("Rex seems to be sobering up.")
    assert.are.equal("Rex seems to be sobering up.", frame:Last()) -- the line stays as the client wrote it
    assert.are.same({}, entries()) -- nothing is looked up inside the chat frame's own call
    assert.is_true(frames() >= 1)
    assert.are.same({ "uikey:DRUNK_MESSAGE_OTHER1" }, entries())
    assert.are.same({ t = "uikey", i = "DRUNK_MESSAGE_OTHER1", b = 1 }, db.entries["uikey:DRUNK_MESSAGE_OTHER1"])
    for _, s in ipairs(strings(db)) do
      assert.is_nil(s:find("Rex", 1, true), s)
      assert.is_nil(s:find("sobering", 1, true), s)
      assert.is_nil(s:find(" ", 1, true), s) -- no text at all: keys, names, a build
    end
  end)

  it("a line that fits several strings keeps each name; one that fits none keeps nothing", function()
    system("Rex has entered the arena.")
    system("Nobody wrote a string for this line.")
    frames()
    assert.are.same({ "uikey:TWIN_NOTICE_ONE", "uikey:TWIN_NOTICE_TWO" }, entries())
  end)

  it("a sentence with no specifier is found by its whole text, a plural template in either form", function()
    system("The gates are now open.")
    system("1 player joined the fight.")
    system("The gates are now open, mostly.")
    frames()
    assert.are.same({ "uikey:GATES_NOTICE", "uikey:PLURAL_NOTICE" }, entries())
    db.entries = {}
    system("12 players joined the fight.") -- the name was handed over once this session
    frames()
    assert.are.same({}, entries())
  end)

  it("a line a player typed records nothing, whatever it says", function()
    frame:AddMessage("Rex seems to be sobering up.", 1, 1, 1, SAY, nil, nil, nil, { "x", "Rex" })
    frame:AddMessage("Rex seems to be sobering up.", 1, 1, 1) -- no chat type: print(), another addon
    assert.are.equal(0, #timers)
    assert.are.equal("idle", (U.status()))
    assert.are.same({}, entries())
  end)

  it("a secret line records nothing", function()
    secrets["Rex seems to be sobering up."] = true
    system("Rex seems to be sobering up.")
    assert.is_false(U.seen("Rex seems to be sobering up."))
    assert.are.equal(0, #timers)
    assert.are.same({}, entries())
  end)

  it("a translated line records nothing and never starts the index", function()
    system("Your party is full.")
    assert.are.equal("パーティーがいっぱいです。", frame:Last())
    assert.are.equal(0, #timers)
    assert.are.equal("idle", (U.status()))
  end)

  it("a string the addon has Japanese for is no candidate, even where its line stays English", function()
    system("Rex is very far away.")
    assert.are.equal("Rex is very far away.", frame:Last())
    frames()
    assert.are.same({}, entries())
  end)

  it("with the collector off nothing is queued, built or kept", function()
    WFJ.Settings.set("collector.enabled", false)
    system("Rex seems to be sobering up.")
    assert.are.equal(0, #timers)
    assert.are.equal("idle", (U.status()))
    assert.are.same({}, entries())
  end)

  it("in combat the index is not built; the line is looked up once combat ends", function()
    combat = true
    system("Rex seems to be sobering up.")
    frames()
    assert.are.equal("idle", (U.status()))
    assert.are.same({}, entries())
    U.flush() -- still in combat: the step asks and leaves again
    frames()
    assert.are.equal("idle", (U.status()))
    combat = false
    U.flush()
    frames()
    assert.are.equal("ready", (U.status()))
    assert.are.same({ "uikey:DRUNK_MESSAGE_OTHER1" }, entries())
  end)

  it("a template of specifiers and a few letters is never a candidate", function()
    for _, text in ipairs({ "%s", "%s: %s", "%s %s", "%s and %s", "Rank %d", "%d/%d", "|cffff0000%s|r" }) do
      assert.is_false(U.consider("SOME_NAME", text), text)
    end
    assert.is_false(U.consider("ONE_WORD_LONG", "Intoxicated")) -- no specifier and no second word
    assert.is_false(U.consider("lower_name", "%s seems to be sobering up."))
    assert.is_false(U.consider("LONG_TEXT", ("%s reads a long page. "):rep(40)))
    system("Rex: hello there")
    system("Rex and Ann")
    system("Rank 3")
    system("Tipsy")
    frames()
    assert.are.same({}, entries())
    assert.is_true(U.consider("SOME_NAME", "%s has died.")) -- the shortest kind of sentence that is one
  end)

  it("one name is recorded once a session, and a repeated line is not looked up again", function()
    system("Rex seems to be sobering up.")
    system("Ann seems to be sobering up.")
    system("Rex seems to be sobering up.")
    frames()
    system("Bob seems to be sobering up.")
    assert.are.equal(1, #timers)
    frames()
    system("Rex seems to be sobering up.")
    assert.are.equal(0, #timers) -- this line was handed over before
    assert.are.same({ "DRUNK_MESSAGE_OTHER1" }, calls)
    assert.are.same({ "uikey:DRUNK_MESSAGE_OTHER1" }, entries())
  end)

  it("the work is spread over frames by the clock, and the walk goes on where it stopped", function()
    U.CHECK_EVERY = 4
    tick = U.BUDGET_MS -- every reading of the clock ends the slice
    system("Rex seems to be sobering up.")
    local n = frames()
    assert.is_true(n > 3, tostring(n))
    assert.are.equal("ready", (U.status()))
    assert.are.same({ "uikey:DRUNK_MESSAGE_OTHER1" }, entries())
  end)

  it("globals are only read", function()
    local before = {}
    for k, v in pairs(_G) do before[k] = v end
    system("Rex seems to be sobering up.")
    frames()
    for k, v in pairs(_G) do assert.are.equal(before[k], v, tostring(k)) end
    for k in pairs(before) do assert.is_not_nil(_G[k], tostring(k)) end
  end)

  it("lines past the queue's room are dropped, and an error ends the lookups without reaching the chat", function()
    for i = 1, U.QUEUE_MAX + 5 do system("Player" .. i .. " did a thing nobody listed.") end
    local _, _, _, waiting = U.status()
    assert.are.equal(U.QUEUE_MAX, waiting)
    WFJ.UIStrings.chatPattern = function() error("boom") end
    frames()
    system("Rex seems to be sobering up.")
    assert.are.equal(0, #timers)
    assert.are.same({}, entries())
    assert.are.equal("Rex seems to be sobering up.", frame:Last())
  end)
end)
