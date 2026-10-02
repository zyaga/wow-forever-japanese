-- UI/TimeLine: the time a tooltip counts down. Every rule the client could be using is a candidate; readable lines rule
-- candidates out; a hidden line is written by the client's own formatter only once that formatter has been checked
-- against the rule. The dictionary is reduced to the eight time lines (Forever's English, a sample number of 37), and
-- the client's formatter is modelled in Lua: it applies the breakpoints the addon hands it.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

-- Forever 1.60.1.70170's English for the two families
local GLOBALS = {
  SPELL_TIME_REMAINING_SEC = "%d |4second:seconds; remaining",
  SPELL_TIME_REMAINING_MIN = "%d |4minute:minutes; remaining",
  SPELL_TIME_REMAINING_HOURS = "%d |4hour:hours; remaining",
  SPELL_TIME_REMAINING_DAYS = "%d |4day:days; remaining",
  INT_SPELL_DURATION_SEC = "%d sec",
  INT_SPELL_DURATION_MIN = "%d min",
  INT_SPELL_DURATION_HOURS = "%d |4hour:hrs;",
  INT_SPELL_DURATION_DAYS = "%d |4day:days;",
  ITEM_COOLDOWN_TIME = "Cooldown remaining: %s",
}

-- the sample line the module asks the dictionary for → its Japanese
local JA = {
  ["37 seconds remaining"] = "残り37秒", ["37 minutes remaining"] = "残り37分",
  ["37 hours remaining"] = "残り37時間", ["37 days remaining"] = "残り37日",
  ["Cooldown remaining: 37 sec"] = "クールダウン残り: 37秒", ["Cooldown remaining: 37 min"] = "クールダウン残り: 37分",
  ["Cooldown remaining: 37 hrs"] = "クールダウン残り: 37時間", ["Cooldown remaining: 37 days"] = "クールダウン残り: 37日",
}

local ROUNDING = { Up = 1, Nearest = 2, Down = 3 }

local function round(mode, x)
  if mode == ROUNDING.Up then return math.ceil(x) end
  if mode == ROUNDING.Down then return math.floor(x) end
  return math.floor(x + 0.5)
end

-- The client's formatter as the addon builds it: the breakpoint with the highest threshold the time reaches, its
-- number rounded as that breakpoint says. `sloppy` models a client that ignores the rounding asked for.
local function installFormatter(sloppy)
  _G.C_StringUtil = { CreateNumericRuleFormatter = function()
    local f = {}
    function f:SetBreakpoints(b) self.breakpoints = b end
    return f
  end }
  _G.C_DurationUtil = { CreateDuration = function()
    local d = {}
    function d:SetTimeFromStart(start, seconds) self.left = start + seconds - GetTime() end
    function d:FormatRemainingDuration(f)
      local pick
      for _, b in ipairs(f.breakpoints) do
        if self.left >= b.threshold and (not pick or b.threshold >= pick.threshold) then pick = b end
      end
      local c = pick.components and pick.components[1]
      local mode = sloppy and ROUNDING.Nearest or (c and c.rounding or pick.rounding)
      return pick.format:format(round(mode, self.left / (c and c.div or 1)))
    end
    return d
  end }
end

-- A duration the client hands over for a hidden line: only the formatter can read it.
local function duration(seconds)
  local d = _G.C_DurationUtil.CreateDuration()
  d:SetTimeFromStart(GetTime(), seconds)
  return d
end

describe("UI/TimeLine", function()
  local WFJ, T

  local function load()
    WFJ = H.loadChunks({ "Core/Compat.lua", "UI/TimeLine.lua" })
    WFJ.Compat.init(function(name) return _G[name] end)
    WFJ.UIIndex = { match = function(_, en) if JA[en] then return en, {} end end }
    WFJ.Render = { preview = function(_, en, _, _, _, key) return JA[key] or en end }
    T = WFJ.TimeLine
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    for k, v in pairs(GLOBALS) do _G[k] = v end
    _G.Enum = { NumericRuleFormatRounding = ROUNDING }
    load()
  end)

  after_each(function()
    for k in pairs(GLOBALS) do _G[k] = nil end
    _G.Enum, _G.C_StringUtil, _G.C_DurationUtil, _G.issecretvalue = nil, nil, nil, nil
  end)

  describe("what was learnt is kept per client build", function()
    it("a fresh save starts empty under this build; the same build keeps it; another build starts over", function()
      local saved = {}
      local db = T.load(saved)
      assert.are.equal("1.15.9.69722", saved.timeRule.build)
      assert.are.equal(saved.timeRule, db)
      saved.timeRule.cooldown = { out = { ["1/up/up"] = true }, seen = 3 }
      T.load(saved)
      assert.are.equal(3, saved.timeRule.cooldown.seen)
      _G.GetBuildInfo = function() return "1.60.1", "70170", "Oct 1 2026", 11600 end
      T.load(saved)
      assert.are.same({ build = "1.60.1.70170" }, saved.timeRule)
    end)

    it("no saved table: a session-only state, and the rule is Blizzard's", function()
      assert.are.same({}, T.load(nil))
      assert.are.equal("1.5/up/up", T.rule("aura").id)
    end)
  end)

  describe("reading a time line", function()
    it("an aura's time left, plural and singular, and a cooldown", function()
      assert.are.same({ "aura", "min", 9 }, { T.parse("9 minutes remaining") })
      assert.are.same({ "aura", "min", 1 }, { T.parse("1 minute remaining") })
      assert.are.same({ "aura", "sec", 45 }, { T.parse("45 seconds remaining") })
      assert.are.same({ "aura", "hour", 2 }, { T.parse("2 hours remaining") })
      assert.are.same({ "cooldown", "sec", 2 }, { T.parse("Cooldown remaining: 2 sec") })
      assert.are.same({ "cooldown", "min", 10 }, { T.parse("Cooldown remaining: 10 min") })
      assert.are.same({ "cooldown", "hour", 1 }, { T.parse("Cooldown remaining: 1 hour") })
      assert.are.same({ "cooldown", "hour", 3 }, { T.parse("Cooldown remaining: 3 hrs") })
      assert.are.equal("aura", T.family("9 minutes remaining"))
      assert.are.equal("cooldown", T.family("Cooldown remaining: 2 sec"))
    end)

    it("any other line, an empty or missing one and a secret one are no time line", function()
      assert.is_nil(T.parse("Heals 12 damage every 3 seconds."))
      assert.is_nil(T.parse("Lasts 30 sec"))
      assert.is_nil(T.parse("9 minutes remaining (Complete)"))
      assert.is_nil(T.parse(""))
      assert.is_nil(T.parse(nil))
      _G.issecretvalue = function(v) return v == "9 minutes remaining" end
      assert.is_nil(T.parse("9 minutes remaining"))
      assert.is_nil(T.family("9 minutes remaining"))
    end)
  end)

  describe("the candidate rules", function()
    local function candidate(id)
      for _, c in ipairs(T.CANDIDATES) do if c.id == id then return c end end
    end

    it("eighteen: switch at 1 or 1.5 units, seconds and larger units rounded up, to nearest or down", function()
      assert.are.equal(18, #T.CANDIDATES)
      assert.are.same({ "sec", 90 }, { T.predict(candidate("1.5/up/up"), 89.6) })
      assert.are.same({ "min", 2 }, { T.predict(candidate("1/up/up"), 89.6) })
      assert.are.same({ "min", 1 }, { T.predict(candidate("1/up/down"), 89.6) })
      assert.are.same({ "min", 2 }, { T.predict(candidate("1.5/up/nearest"), 90.4) })
      assert.are.same({ "sec", 2 }, { T.predict(candidate("1.5/up/up"), 1.4) })
      assert.are.same({ "sec", 1 }, { T.predict(candidate("1.5/down/up"), 1.4) })
      assert.are.same({ "sec", 1 }, { T.predict(candidate("1.5/nearest/up"), 1.4) })
      assert.are.same({ "hour", 2 }, { T.predict(candidate("1.5/up/up"), 5400.4) })
      assert.are.same({ "day", 2 }, { T.predict(candidate("1.5/up/up"), 129600.4) })
      assert.are.same({ "hour", 36 }, { T.predict(candidate("1.5/up/up"), 129599.6) })
    end)

    it("each readable line rules out the candidates that would have written something else", function()
      -- 1.4 s shown as 2: only rounding the seconds up agrees
      assert.are.equal(6, T.observe("cooldown", 1.4, "Cooldown remaining: 2 sec"))
      -- 75 s shown as 2 min: the switch is at one unit and minutes round up
      assert.are.equal(1, T.observe("cooldown", 75, "Cooldown remaining: 2 min"))
      assert.are.equal("1/up/up", T.rule("cooldown").id)
      -- the aura family learns on its own
      assert.are.equal("1.5/up/up", T.rule("aura").id)
      -- a line no candidate would have written: nothing left, no rule
      assert.are.equal(0, T.observe("cooldown", 75, "Cooldown remaining: 5 min"))
      local rule, why = T.rule("cooldown")
      assert.is_nil(rule)
      assert.are.equal("no rule fits what the game showed", why)
    end)

    it("a line of the other family, a secret one or a time already run out teaches nothing", function()
      assert.is_nil(T.observe("cooldown", 540, "9 minutes remaining"))
      assert.is_nil(T.observe("aura", 0, "1 second remaining"))
      assert.is_nil(T.observe("aura", -3, "1 second remaining"))
      assert.is_nil(T.observe("aura", "540", "9 minutes remaining"))
      _G.issecretvalue = function(v) return v == 540 end
      assert.is_nil(T.observe("aura", 540, "9 minutes remaining"))
      _G.issecretvalue = nil
      assert.are.equal(18, #T.CANDIDATES)
      assert.are.equal(1, #T.recent.cooldown) -- the unread line is kept for /wfj debug
      assert.is_truthy(T.recent.cooldown[1]:find("unread 540.0 s", 1, true))
      assert.are.equal(0, #T.recent.aura)
      assert.are.equal("1.5/up/up", T.rule("aura").id)
    end)

    it("the rule: the one left, else the first of Blizzard's two still alive, else none", function()
      assert.are.same({ "1.5/up/up", "1.5/down/up" }, T.DEFAULTS)
      assert.are.equal("1.5/up/up", T.rule("aura").id)
      -- 1.4 s shown as 1: rounding up is out, Blizzard's second (seconds as they are) is not
      T.observe("aura", 1.4, "1 second remaining")
      assert.are.equal("1.5/down/up", T.rule("aura").id)
      -- 1.6 s shown as 2: rounding down is out too; six candidates left, none of them Blizzard's
      assert.are.equal(6, T.observe("aura", 1.6, "2 seconds remaining"))
      local rule, why = T.rule("aura")
      assert.is_nil(rule)
      assert.are.equal("6 rules still possible, Blizzard's ruled out", why)
    end)
  end)

  describe("status lines for /wfj debug", function()
    it("one line per family, with the candidates left and the recent lines when there is no rule", function()
      local lines = T.status()
      assert.are.equal("aura: rule 1.5/up/up, 0 lines seen, formatter not checked yet", lines[1])
      assert.are.equal("cooldown: rule 1.5/up/up, 0 lines seen, formatter not checked yet", lines[2])
      T.observe("aura", 1.4, "1 second remaining")
      T.observe("aura", 1.6, "2 seconds remaining")
      lines = T.status()
      assert.are.equal("aura: 6 rules still possible, Blizzard's ruled out, 2 lines seen, formatter not checked yet",
        lines[1])
      assert.are.equal("  aura rules left (switch/seconds/larger units): "
        .. "1/nearest/up 1/nearest/nearest 1/nearest/down 1.5/nearest/up 1.5/nearest/nearest 1.5/nearest/down",
        lines[2])
      assert.are.equal("  aura 1.4 s -> sec 1", lines[3])
      assert.are.equal("  aura 1.6 s -> sec 2", lines[4])
      assert.are.equal("cooldown: rule 1.5/up/up, 0 lines seen, formatter not checked yet", lines[5])
    end)
  end)

  describe("writing a line", function()
    it("a readable number of seconds, in Japanese by the rule", function()
      local fs = Stub.fontString("Cooldown remaining: 2 sec")
      assert.are.same({ true, "1.4 s, written" }, { T.writeSeconds(fs, "cooldown", 1.4) })
      assert.are.equal("クールダウン残り: 2秒", fs:GetText())
      T.writeSeconds(fs, "aura", 540)
      assert.are.equal("残り9分", fs:GetText())
      T.writeSeconds(fs, "aura", 5400.4)
      assert.are.equal("残り2時間", fs:GetText())
    end)

    it("no rule, or no Japanese for the unit: nothing is written", function()
      local fs = Stub.fontString("Cooldown remaining: 5 min")
      T.observe("cooldown", 75, "Cooldown remaining: 5 min")
      assert.are.same({ nil, "no rule fits what the game showed" }, { T.writeSeconds(fs, "cooldown", 75) })
      assert.are.equal("Cooldown remaining: 5 min", fs:GetText())
      JA["37 days remaining"] = nil
      local ok, why = T.writeSeconds(fs, "aura", 129600.4)
      JA["37 days remaining"] = "残り37日"
      assert.is_nil(ok)
      assert.are.equal("no Japanese", why)
      assert.are.equal("Cooldown remaining: 5 min", fs:GetText())
    end)

    it("a hidden duration is refused while the client's formatter has not been checked", function()
      -- no duration API at all: the self-test cannot run, so the formatter stays unchecked
      local fs = Stub.fontString("<hidden>")
      local hidden = { FormatRemainingDuration = function() error("must not be asked") end }
      assert.are.same({ nil, "formatter not checked for rule 1.5/up/up" }, { T.writeDuration(fs, "aura", hidden) })
      assert.are.equal("<hidden>", fs:GetText())
      assert.is_true(T.learning())
    end)
  end)

  describe("the client's formatter, checked against the rule", function()
    it("a formatter that applies the rule passes the self-test and then writes hidden lines", function()
      installFormatter(false)
      assert.is_true(T.selfTest())
      assert.is_false(T.learning())
      assert.are.equal("aura: rule 1.5/up/up, 0 lines seen, formatter checked", T.status()[1])
      local fs = Stub.fontString("<hidden>")
      assert.are.same({ true, "hidden, written by the client" }, { T.writeDuration(fs, "aura", duration(540)) })
      assert.are.equal("残り9分", fs:GetText())
      T.writeDuration(fs, "cooldown", duration(1.4))
      assert.are.equal("クールダウン残り: 2秒", fs:GetText())
    end)

    it("a formatter that rounds otherwise fails the self-test, and no hidden line is written", function()
      installFormatter(true)
      assert.is_false(T.selfTest())
      local status = T.status()[1]
      assert.is_truthy(status:find("formatter disagreed: self-test: formatter \"残り0秒\", rule \"残り1秒\" at 0.4 s",
        1, true), status)
      local fs = Stub.fontString("<hidden>")
      local ok, why = T.writeDuration(fs, "aura", duration(540))
      assert.is_nil(ok)
      assert.is_truthy(why:find("^formatter disagreed"))
      assert.are.equal("<hidden>", fs:GetText())
      assert.is_true(T.learning())
    end)

    it("an unchecked formatter is self-tested on the first hidden line, then used", function()
      installFormatter(false)
      local fs = Stub.fontString("<hidden>")
      assert.is_true((T.writeDuration(fs, "cooldown", duration(75))))
      assert.are.equal("クールダウン残り: 75秒", fs:GetText()) -- Blizzard's rule: 75 s is below 1.5 minutes
    end)

    it("a readable line with its duration checks the formatter: agreeing, then disagreeing", function()
      installFormatter(false)
      assert.is_true(T.checkFormatter("aura", duration(540), 540))
      assert.are.equal("aura: rule 1.5/up/up, 0 lines seen, formatter checked", T.status()[1])
      local wrong = { FormatRemainingDuration = function() return "残り8分" end }
      assert.is_false(T.checkFormatter("aura", wrong, 540))
      assert.is_truthy(T.status()[1]:find("disagreed: formatter \"残り8分\", rule \"残り9分\" at 540.0 s", 1, true))
      -- a secret number of seconds: nothing to check
      _G.issecretvalue = function(v) return v == 541 end
      assert.is_nil(T.checkFormatter("aura", duration(541), 541))
    end)
  end)
end)
