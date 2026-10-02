-- UI/Tooltip in combat: a hidden pass (every row's text secret) translates the client's own tooltip data for the
-- spell or item and writes it by row; the cooldown countdown is written by the client from its hidden duration
-- (UI/TimeLine); a buff tooltip, whose identity is hidden too, is left in English; the trace counts repeated passes
-- instead of filling up and names each row's line kind.
-- The stub tells a secret by its value, so the frame's hidden rows carry a trailing space here: the client's own
-- data rows, with the plain text, stay readable, as they do in game.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = { "Core/Const.lua", "Core/Compat.lua", "Core/Align.lua", "Core/State.lua", "Core/Settings.lua",
  "Core/Modifier.lua", "Core/Translator.lua", "Core/SurfaceState.lua", "Core/Normalize.lua", "Core/Hash.lua",
  "Core/Collector.lua", "UI/Font.lua", "UI/Render.lua", "UI/TimeLine.lua", "UI/Tooltip.lua", "UI/TooltipUnit.lua" }

-- Forever 1.60.1.70170's English for the cooldown line
local TIME_GLOBALS = {
  INT_SPELL_DURATION_SEC = "%d sec",
  INT_SPELL_DURATION_MIN = "%d min",
  INT_SPELL_DURATION_HOURS = "%d |4hour:hrs;",
  INT_SPELL_DURATION_DAYS = "%d |4day:days;",
  ITEM_COOLDOWN_TIME = "Cooldown remaining: %s",
}

-- the UI dictionary, reduced to whole lines
local UI_LINES = {
  ["Cooldown remaining: 37 sec"] = "残りクールダウン: 37秒", ["Cooldown remaining: 37 min"] = "残りクールダウン: 37分",
  ["Cooldown remaining: 37 hrs"] = "残りクールダウン: 37時間", ["Cooldown remaining: 37 days"] = "残りクールダウン: 37日",
  ["Rank 1"] = "ランク 1", ["40 yd range"] = "射程 40ヤード", ["Instant cast"] = "即時",
  ["Sell Price: 5c"] = "売値: 5c",
}

local AURA_EN = "Heals 12 damage every 3 seconds."
local AURA_JA = "$N2秒ごとに$N1のダメージを回復します。"
local AURA_SHOWN = "3秒ごとに12のダメージを回復します。"
local LINES = { "Rejuvenation", AURA_EN, "25 minutes remaining" }
local SHIELD_DESC = "Draws on the soul of the friendly target to shield them, absorbing 44 damage. Lasts 30 sec."
local SHIELD_JA = "味方にシールドを張り、44ダメージを吸収します。30秒間持続します。"
-- the frame's rows as the client writes them on a hidden pass (every text secret), with the countdown
local HIDDEN = { { "Power Word: Shield ", "Rank 1 " }, "40 yd range ", "Instant cast ", "Cooldown remaining: 2 sec ",
  SHIELD_DESC .. " ", " ", "Press F6 " }
-- the client's own data for spell 17 as it answers in game: five rows, the countdown hidden, the description typed
local COUNTDOWN_EN = "Cooldown remaining: 2 sec"
local SHIELD_ROWS = { { leftText = "Power Word: Shield", rightText = "Rank 1" }, { leftText = "40 yd range" },
  { leftText = "Instant cast" }, { leftText = COUNTDOWN_EN }, { leftText = SHIELD_DESC, type = 34 } }
local JERKY = "|Hitem:117:0:0:0:0:0:0:0|h[Tough Jerky]|h"
local JERKY_DESC = "Use: Restores 61 health over 18 sec. Must remain seated while eating."
local JERKY_HIDDEN = { "Tough Jerky ", JERKY_DESC .. " ", "Sell Price: 5c " }
local JERKY_ROWS = { { leftText = "Tough Jerky" }, { leftText = JERKY_DESC }, { leftText = "Sell Price: 5c" } }

local ROUNDING = { Up = 1, Nearest = 2, Down = 3 }

local DATA

-- The client's formatter for a hidden duration, modelled in Lua: it applies the breakpoints the addon hands it.
local function installFormatter()
  _G.Enum.NumericRuleFormatRounding = ROUNDING
  local function round(mode, x)
    if mode == ROUNDING.Up then return math.ceil(x) end
    if mode == ROUNDING.Down then return math.floor(x) end
    return math.floor(x + 0.5)
  end
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
      return pick.format:format(round(c and c.rounding or pick.rounding, self.left / (c and c.div or 1)))
    end
    return d
  end }
end

local function duration(seconds)
  local d = _G.C_DurationUtil.CreateDuration()
  d:SetTimeFromStart(GetTime(), seconds)
  return d
end

local function setup()
  DATA = {
    ["spell.aura"] = { [774] = { ja = AURA_JA, status = "u" } },
    ["spell.description"] = { [17] = { ja = "味方にシールドを張り、$N1ダメージを吸収します。$N2秒間持続します。", status = "u" } },
    ["item.description"] = { [117] = { ja = "18秒間でhealthを61回復。回復中は\n座っている必要があります。", status = "u" } },
    ui = {},
  }
  for en, ja in pairs(UI_LINES) do DATA.ui[en] = { ja = ja, status = "." } end
  Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
  Stub.installTooltipAPI()
  for k, v in pairs(TIME_GLOBALS) do _G[k] = v end
  _G.date = function() return "12:00:00" end
  _G.Enum.TooltipDataLineType = { None = 0, UnitName = 2, QuestTitle = 17, SpellDescription = 34 }
  _G.C_TooltipInfo = {
    GetSpellByID = function(id) if id == 17 then return { id = 17, lines = SHIELD_ROWS } end end,
    GetItemByID = function(id) if id == 117 then return { id = 117, lines = JERKY_ROWS } end end,
  }
  _G.GetActionInfo = nil
  _G.C_Item = _G.C_Item or {}
  local WFJ = H.loadChunks(FILES)
  WFJ.Compat.init(function(name) return _G[name] end)
  WFJ.Settings.load(nil, 1, {})
  WFJ.Render.init(WFJ.Translator.new({
    enabled = function() return WFJ.State.enabled end,
    areaEnabled = WFJ.State.areaEnabled,
    modifierHeld = WFJ.Modifier.isDown,
    lookup = function(kind, id) return DATA[kind] and DATA[kind][id] end,
    marker = function(n) return WFJ.Settings.get("marker." .. n) end,
    align = WFJ.Align.check,
  }))
  WFJ.Lookup = { get = function(kind, id) return DATA[kind] and DATA[kind][id] end }
  WFJ.UIIndex = { match = function(_, t) if UI_LINES[t] then return t, {} end end }
  Stub.spellDescriptions[17] = SHIELD_DESC
  WFJ.Tooltip.init()
  return WFJ, _G.GameTooltip
end

local function text(i) return _G["GameTooltipTextLeft" .. i]:GetText() end
local function right(i) return _G["GameTooltipTextRight" .. i]:GetText() end

-- a hidden pass: every line text the client writes on the frame is one the addon may not read, and so is anything
-- in `more` (the client's hidden data rows, a hidden id)
local function hide(lines, more)
  local secret = {}
  for _, l in ipairs(lines) do
    if type(l) == "table" then secret[l[1]] = true; secret[l[2]] = true else secret[l] = true end
  end
  for _, v in ipairs(more or {}) do secret[v] = true end
  _G.issecretvalue = function(v) return secret[v] == true end
end

-- the frame's rows as the client typed them: the spell's name row and its description row
local function typeRows(tt, descRow)
  local lines = {}
  for i = 1, descRow do lines[i] = { lineIndex = i, type = i == descRow and 34 or (i == 1 and 13 or 0) } end
  tt.primaryInfo = { tooltipData = { lines = lines } }
end

-- the frame's rows written by the client, then the Spell post-call
local function spellPass(tt, lines, descRow, id)
  tt.spell = { name = "Power Word: Shield", id = id or 17 }
  tt.item = nil
  if descRow then typeRows(tt, descRow) else tt.primaryInfo = nil end
  tt:writeLines(lines)
  Stub.fireTooltipSet(tt, "Spell")
end

describe("UI/Tooltip: hidden passes", function()
  after_each(function() _G.issecretvalue, _G.GetActionInfo = nil, nil end)

  describe("a spell on the action bar", function()
    it("every row comes from the client's data: the right column, the structural rows and the description", function()
      local WFJ, tt = setup()
      tt.owner = "ActionButton1"
      hide(HIDDEN, { COUNTDOWN_EN })
      spellPass(tt, HIDDEN, 5)
      assert.are.equal("Power Word: Shield ", text(1)) -- the name is never replaced
      assert.are.equal("ランク 1", right(1))
      assert.are.equal("射程 40ヤード", text(2))
      assert.are.equal("即時", text(3))
      assert.are.equal(SHIELD_JA, text(5))
      assert.are.equal("Press F6 ", text(7)) -- rows past the client's data (another addon's) are left alone
      assert.are.equal(1, WFJ.Tooltip.hidden.written)
      assert.is_truthy(WFJ.Tooltip.hidden.last:find("data rows 5, hidden: 4", 1, true))
      assert.is_truthy(WFJ.Tooltip.hidden.last:find("description row 5 from the client's data", 1, true))
      assert.is_true(WFJ.Font.dressed(_G.GameTooltipTextLeft5)) -- a written row wears the bundled face
    end)

    it("the countdown row, hidden in the client's data too, is written by the client from the hidden cooldown",
      function()
        local WFJ, tt = setup()
        installFormatter()
        tt.owner = "ActionButton1"
        _G.C_Spell.GetSpellCooldownDuration = function(id) if id == 17 then return duration(1.4) end end
        hide(HIDDEN, { COUNTDOWN_EN })
        spellPass(tt, HIDDEN, 5)
        assert.are.equal("残りクールダウン: 2秒", text(4))
        assert.are.equal(SHIELD_JA, text(5))
        assert.is_truthy(WFJ.Tooltip.hidden.last:find("countdown row 4: hidden, written by the client", 1, true))
        -- the countdown keeps the rule as it counts: 100 s left reads as 2 minutes
        _G.C_Spell.GetSpellCooldownDuration = function() return duration(100) end
        spellPass(tt, HIDDEN, 5)
        assert.are.equal("残りクールダウン: 2分", text(4))
        -- no duration from the client: the row is left as the client wrote it
        _G.C_Spell.GetSpellCooldownDuration = nil
        spellPass(tt, HIDDEN, 5)
        assert.are.equal("Cooldown remaining: 2 sec ", text(4))
        assert.is_truthy(WFJ.Tooltip.hidden.last:find("countdown row 4: no cooldown duration API", 1, true))
      end)

    it("the frame's typed description row places the rows when the client's data lacks the countdown", function()
      local WFJ, tt = setup()
      installFormatter()
      tt.owner = "ActionButton1"
      _G.C_Spell.GetSpellCooldownDuration = function() return duration(1.4) end
      local fourRows = { SHIELD_ROWS[1], SHIELD_ROWS[2], SHIELD_ROWS[3], SHIELD_ROWS[5] }
      _G.C_TooltipInfo.GetSpellByID = function() return { id = 17, lines = fourRows } end
      hide(HIDDEN)
      -- the description is row 5 on the frame and row 4 in the data: row 4 is the frame's own, the countdown
      spellPass(tt, HIDDEN, 5)
      assert.are.equal("残りクールダウン: 2秒", text(4))
      assert.are.equal(SHIELD_JA, text(5))
      assert.are.equal("即時", text(3))
      -- no typed rows from the frame: the rows meet one to one and the description comes from the data's row
      spellPass(tt, HIDDEN)
      assert.are.equal(SHIELD_JA, text(4))
      -- the frame's description above the data's: no row can be placed, only the description is written
      spellPass(tt, HIDDEN, 3)
      assert.are.equal(SHIELD_JA, text(3))
      assert.are.equal("40 yd range ", text(2))
      assert.is_truthy(WFJ.Tooltip.hidden.last:find("row 3 on the frame but row 4 in the data", 1, true))
    end)

    it("the spell id hidden too: the owner's action slot names it; no slot, or English wanted, writes nothing",
      function()
        -- a secret stands in for the hidden id here (the stub tells a secret by its value)
        local WFJ, tt = setup()
        tt.owner = { action = 5 }
        _G.GetActionInfo = function(slot) if slot == 5 then return "spell", 17 end end
        hide(HIDDEN, { COUNTDOWN_EN, "hidden id" })
        spellPass(tt, HIDDEN, 5, "hidden id")
        assert.are.equal(SHIELD_JA, text(5))
        tt.owner = "ActionButton1"
        spellPass(tt, HIDDEN, 5, "hidden id")
        assert.are.equal(SHIELD_DESC .. " ", text(5))
        assert.are.equal("the spell or item itself is hidden", WFJ.Tooltip.hidden.last)
        hide(HIDDEN, { COUNTDOWN_EN })
        Stub.keys.alt = true; WFJ.Modifier.refresh()
        spellPass(tt, HIDDEN, 5)
        assert.are.equal(SHIELD_DESC .. " ", text(5))
        assert.are.equal("English wanted", WFJ.Tooltip.hidden.last)
        Stub.keys.alt = false; WFJ.Modifier.refresh()
        _G.GetActionInfo = nil
      end)

    it("the client's data hidden as a whole: the description comes from the spell API, the rest is left", function()
      local WFJ, tt = setup()
      tt.owner = "ActionButton1"
      _G.C_TooltipInfo.GetSpellByID = function() return { id = 17, lines = { { leftText = "x" } } } end
      hide(HIDDEN, { "x" })
      spellPass(tt, HIDDEN, 5)
      assert.are.equal(SHIELD_JA, text(5))
      assert.are.equal("40 yd range ", text(2))
      assert.is_truthy(WFJ.Tooltip.hidden.last:find("description row 5 from the spell API", 1, true))
      -- no data at all and the spell API hidden too: nothing is written and /wfj debug counts the pass as left
      _G.C_TooltipInfo.GetSpellByID = nil
      hide(HIDDEN, { SHIELD_DESC })
      spellPass(tt, HIDDEN, 5)
      assert.are.equal(SHIELD_DESC .. " ", text(5))
      assert.are.equal(1, WFJ.Tooltip.hidden.written)
      assert.are.equal(1, WFJ.Tooltip.hidden.left)
      assert.is_truthy(WFJ.Tooltip.hidden.last:find("no C_TooltipInfo.GetSpellByID", 1, true))
    end)

    it("readable again: the ordinary path renders through records, after a hidden pass on the same frame", function()
      local _, tt = setup()
      tt.owner = "ActionButton1"
      hide(HIDDEN, { COUNTDOWN_EN })
      spellPass(tt, HIDDEN, 5)
      _G.issecretvalue = nil
      local readable = { "Power Word: Shield", "40 yd range", "Instant cast", SHIELD_DESC }
      spellPass(tt, readable)
      assert.are.equal(SHIELD_JA, text(4))
      assert.are.equal("射程 40ヤード", text(2))
    end)
  end)

  describe("fonts after a hidden pass", function()
    it("a row a hidden pass dressed keeps the bundled face when the tooltip hides, and a later render on the "
      .. "same rows (the minimap's quest block, a creature) still wears it", function()
      local WFJ, tt = setup()
      tt.owner = "ActionButton1"
      hide(HIDDEN, { COUNTDOWN_EN })
      spellPass(tt, HIDDEN, 5)
      WFJ.Tooltip.release(tt) -- OnHide: the face is not given back
      assert.is_true(WFJ.Font.dressed(_G.GameTooltipTextLeft5))
      assert.are.equal(WFJ.Font.PATH, (_G.GameTooltipTextLeft5:GetFont()))
      _G.issecretvalue = nil
      -- the next render through records on the same widgets: Japanese in the bundled face, never the client's
      local readable = { "Power Word: Shield", "40 yd range", "Instant cast", SHIELD_DESC }
      spellPass(tt, readable)
      assert.are.equal(SHIELD_JA, text(4))
      assert.are.equal(WFJ.Font.PATH, (_G.GameTooltipTextLeft4:GetFont()))
      assert.are.equal(WFJ.Font.PATH, (_G.GameTooltipTextLeft2:GetFont()))
      WFJ.Tooltip.release(tt)
      spellPass(tt, readable)
      assert.are.equal(WFJ.Font.PATH, (_G.GameTooltipTextLeft4:GetFont()))
    end)
  end)

  describe("an item on the action bar", function()
    it("the item named by the owner's action slot, its run and the other rows from the client's data", function()
      local _, tt = setup()
      tt.owner = { action = 24 }
      _G.GetActionInfo = function(slot) if slot == 24 then return "item", 117 end end
      hide(JERKY_HIDDEN, { JERKY })
      tt.item = { name = "Tough Jerky", link = JERKY }
      tt.spell = nil
      tt.primaryInfo = nil
      tt:writeLines(JERKY_HIDDEN)
      Stub.fireTooltipSet(tt, "Item")
      assert.are.equal("Tough Jerky ", text(1))
      assert.are.equal(DATA["item.description"][117].ja, text(2))
      assert.are.equal("売値: 5c", text(3))
      _G.GetActionInfo = nil
    end)

    it("a hidden data row of an item is its cooldown, written from the seconds left, or left when hidden", function()
      local WFJ, tt = setup()
      tt.owner = { action = 24 }
      _G.GetActionInfo = function() return "item", 117 end
      local countdown = "Cooldown remaining: 75 sec"
      _G.C_TooltipInfo.GetItemByID = function() return { id = 117, lines = { JERKY_ROWS[1], { leftText = countdown },
        JERKY_ROWS[2], JERKY_ROWS[3] } } end
      local lines = { "Tough Jerky ", "Cooldown remaining: 75 sec ", JERKY_DESC .. " ", "Sell Price: 5c " }
      _G.C_Item.GetItemCooldown = function(id) if id == 117 then return 0, 75, 1 end end
      hide(lines, { JERKY, countdown })
      tt.item = { name = "Tough Jerky", link = JERKY }
      tt.spell = nil
      tt.primaryInfo = nil
      tt:writeLines(lines)
      Stub.fireTooltipSet(tt, "Item")
      assert.are.equal("残りクールダウン: 75秒", text(2))
      assert.are.equal(DATA["item.description"][117].ja, text(3))
      assert.are.equal("売値: 5c", text(4))
      _G.C_Item.GetItemCooldown = function() return 1000.25, 2.75, 1 end
      hide(lines, { JERKY, countdown, 1000.25, 2.75 })
      tt:writeLines(lines)
      Stub.fireTooltipSet(tt, "Item")
      assert.are.equal("Cooldown remaining: 75 sec ", text(2))
      assert.is_truthy(WFJ.Tooltip.hidden.last:find("countdown row 2: item cooldown hidden", 1, true))
      _G.GetActionInfo, _G.C_Item.GetItemCooldown = nil, nil
    end)
  end)

  describe("a buff in combat", function()
    local function aura(key, spellId, lines)
      Stub.auraData[key] = { data = { spellId = spellId, expirationTime = 1500 }, lines = lines }
    end

    it("is left in the client's English, which buff it is being hidden too, and is Japanese again once readable",
      function()
        local WFJ, tt = setup()
        WFJ.Tooltip.trace = {}
        aura("player#11", 774, LINES)
        -- first hovered in combat: the aura id itself is secret, the rows too
        hide(LINES, { 11 })
        assert.has_no.errors(function() tt:SetUnitAuraByAuraInstanceID("player", 11) end)
        assert.are.equal(AURA_EN, text(2))
        assert.are.equal(0, WFJ.Tooltip.auraErrors)
        local found = false
        for _, e in ipairs(WFJ.Tooltip.trace) do
          if e:find("secret aura", 1, true) and e:find("the client hides which buff it is", 1, true) then
            found = true
          end
        end
        assert.is_true(found)
        -- the fight ends: the rows are readable and the ordinary path renders
        _G.issecretvalue = nil
        tt:rebuild(LINES)
        assert.are.equal(AURA_SHOWN, text(2))
        -- the rows hidden again mid-hover: the records are let go without reading them, the English stays
        hide(LINES)
        assert.has_no.errors(function() tt:rebuild(LINES) end)
        assert.are.equal(AURA_EN, text(2))
        WFJ.Tooltip.trace = nil
      end)
  end)

  describe("the trace", function()
    local SHIELD_LINES = { "Power Word: Shield", "40 yd range", "Instant cast", SHIELD_DESC }
    local JERKY_LINES = { "Tough Jerky", JERKY_DESC, "Sell Price: 5c" }

    it("an identical pass is counted on the entry before it, not added again", function()
      local WFJ, tt = setup()
      WFJ.Tooltip.trace = {}
      tt.owner = "ActionButton1"
      for _ = 1, 3 do Stub.setSpellTooltip(tt, 17, SHIELD_LINES) end
      local t = WFJ.Tooltip.trace
      assert.are.equal(1, #t)
      local tail = "\n  (seen 3 times, last 12:00:00)"
      assert.are.equal(tail, t[1]:sub(-#tail))
      assert.are.equal(1, select(2, t[1]:gsub("seen %d+ times", ""))) -- the count is replaced, not appended
      Stub.setItemTooltip(tt, JERKY, JERKY_LINES) -- another pass starts a new entry
      assert.are.equal(2, #t)
      Stub.setSpellTooltip(tt, 17, SHIELD_LINES) -- and the spell again is a new entry after it
      assert.are.equal(3, #t)
      WFJ.Tooltip.trace = nil
    end)

    it("a hidden pass names every data row, the row map and the countdown's duration in its entry", function()
      local WFJ, tt = setup()
      installFormatter()
      WFJ.Tooltip.trace = {}
      tt.owner = "ActionButton1"
      _G.C_Spell.GetSpellCooldownDuration = function() return duration(1.4) end
      hide(HIDDEN, { COUNTDOWN_EN })
      spellPass(tt, HIDDEN, 5)
      local entry = WFJ.Tooltip.trace[1]
      assert.is_truthy(entry:find("secret spell id=17", 1, true), entry)
      assert.is_truthy(entry:find('data 1 ? "Power Word: Shield" | "Rank 1"', 1, true), entry)
      assert.is_truthy(entry:find("data 4 ? <hidden>", 1, true), entry)
      assert.is_truthy(entry:find('data 5 SpellDescription "Draws', 1, true), entry)
      assert.is_truthy(entry:find("map 1=1 2=2 3=3 4=4 5=5, extra", 1, true), entry)
      assert.is_truthy(entry:find("countdown row 4: hidden, written by the client (duration table", 1, true), entry)
      -- the rows are read for the trace after the pass wrote them: the stub's rows are plain again, the client's
      -- keep their secret aspect
      assert.is_truthy(entry:find("\n  5 SpellDescription L", 1, true), entry)
      WFJ.Tooltip.trace = nil
    end)

    it("a note is one line, counted the same way; with the trace off nothing is kept", function()
      local WFJ = setup()
      WFJ.Tooltip.trace = nil
      assert.has_no.errors(function() WFJ.Tooltip.traceNote("not one of ours") end)
      WFJ.Tooltip.trace = {}
      WFJ.Tooltip.traceNote("aura post-call on X: not one of ours")
      WFJ.Tooltip.traceNote("aura post-call on X: not one of ours")
      WFJ.Tooltip.traceNote("aura post-call on X: not one of ours")
      assert.are.same({ "[12:00:00] aura post-call on X: not one of ours (seen 3 times)" }, WFJ.Tooltip.trace)
      WFJ.Tooltip.traceNote("SetUnitAura(player, 1, HELPFUL) called")
      assert.are.equal(2, #WFJ.Tooltip.trace)
      WFJ.Tooltip.trace = nil
    end)

    it("each row names its line kind from the tooltip data, or ? where the client gave none", function()
      local WFJ, tt = setup()
      WFJ.Tooltip.trace = {}
      tt:writeLines({ "Young Thistle Boar", "Wolf Pelts", "Level 2" })
      tt.primaryInfo = { tooltipData = { lines = { { lineIndex = 1, type = 2 }, { lineIndex = 2, type = 17 } } } }
      WFJ.Tooltip.traceFrame(tt, "unit", nil, WFJ.Tooltip.lines(tt), "-> wrote 0")
      local entry = WFJ.Tooltip.trace[1]
      assert.is_truthy(entry:find("\n  1 UnitName L \"Young Thistle Boar\"", 1, true), entry)
      assert.is_truthy(entry:find("\n  2 QuestTitle L \"Wolf Pelts\"", 1, true), entry)
      assert.is_truthy(entry:find("\n  3 ? L \"Level 2\"", 1, true), entry)
      WFJ.Tooltip.trace = nil
    end)
  end)
end)

describe("UI/TimeLine: the cooldown countdown by Blizzard's one-term rule", function()
  after_each(function() _G.issecretvalue = nil end)

  it("seconds round up; a larger unit takes over at 1.5 of it and rounds up", function()
    local WFJ = setup()
    local P = WFJ.TimeLine.predict
    assert.are.same({ "sec", 2 }, { P(1.4) })
    assert.are.same({ "sec", 89 }, { P(89) })
    assert.are.same({ "min", 2 }, { P(90) })
    assert.are.same({ "min", 2 }, { P(100) })
    assert.are.same({ "min", 90 }, { P(5399) })
    assert.are.same({ "hour", 2 }, { P(5400) })
    assert.are.same({ "day", 2 }, { P(129600) })
    assert.are.equal("残りクールダウン: 2秒", WFJ.TimeLine.render(1.4))
    assert.are.equal("残りクールダウン: 90分", WFJ.TimeLine.render(5399))
  end)

  it("the client's formatter carries the rule: four breakpoints, every unit rounded up, built once", function()
    local WFJ = setup()
    installFormatter()
    local f = WFJ.TimeLine.formatter()
    assert.is_not_nil(f)
    local thresholds = {}
    for i, b in ipairs(f.breakpoints) do
      thresholds[i] = b.threshold
      assert.are.equal(ROUNDING.Up, b.components and b.components[1].rounding or b.rounding)
    end
    assert.are.same({ 0, 90, 5400, 129600 }, thresholds)
    assert.are.equal(f, WFJ.TimeLine.formatter())
    assert.is_truthy(WFJ.TimeLine.status():find("ready", 1, true))
  end)

  it("writes a hidden duration through the client, a readable number of seconds in Lua, nothing for no cooldown",
    function()
      local WFJ = setup()
      installFormatter()
      local fs = Stub.namedFontString("TimeLineProbe", "", "Fonts\\FRIZQT__.TTF", 12, "")
      assert.is_true(WFJ.TimeLine.writeDuration(fs, duration(1.4)))
      assert.are.equal("残りクールダウン: 2秒", fs:GetText())
      assert.is_true(WFJ.TimeLine.writeSeconds(fs, 75))
      assert.are.equal("残りクールダウン: 75秒", fs:GetText())
      local ok, why = WFJ.TimeLine.writeSeconds(fs, 0)
      assert.is_nil(ok)
      assert.are.equal("no cooldown running", why)
      ok, why = WFJ.TimeLine.writeDuration(fs, nil)
      assert.is_nil(ok)
      assert.are.equal("no duration object", why)
    end)

  it("without the client's rule formatter no hidden line is written, and the status says why", function()
    local WFJ = setup()
    _G.C_StringUtil = nil
    local fs = Stub.namedFontString("TimeLineProbe2", "", "Fonts\\FRIZQT__.TTF", 12, "")
    local ok, why = WFJ.TimeLine.writeDuration(fs, {})
    assert.is_nil(ok)
    assert.are.equal("no rule formatter", why)
    assert.is_truthy(WFJ.TimeLine.status():find("no rule formatter", 1, true))
  end)
end)
