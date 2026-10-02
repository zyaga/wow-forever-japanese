-- UI/Tooltip in combat: a buff's Japanese is kept per aura (unit + auraInstanceID) so a buff first hovered in combat
-- still shows it; rows whose number moves (an aura's time left, a cooldown) are never written back from memory, and
-- the cooldown row a secret pass adds is written by UI/TimeLine; the trace counts repeated passes instead of filling
-- up, and names each row's line kind.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = { "Core/Const.lua", "Core/Compat.lua", "Core/Align.lua", "Core/State.lua", "Core/Settings.lua",
  "Core/Modifier.lua", "Core/Translator.lua", "Core/SurfaceState.lua", "Core/Normalize.lua", "Core/Hash.lua",
  "Core/Collector.lua", "UI/Font.lua", "UI/Render.lua", "UI/TimeLine.lua", "UI/Tooltip.lua", "UI/TooltipUnit.lua" }

-- Forever 1.60.1.70170's English for the time lines
local TIME_GLOBALS = {
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

-- the UI dictionary, reduced to whole lines: the time lines' samples (37) and one aura time a readable pass shows
local UI_LINES = {
  ["37 seconds remaining"] = "残り37秒", ["37 minutes remaining"] = "残り37分",
  ["37 hours remaining"] = "残り37時間", ["37 days remaining"] = "残り37日",
  ["Cooldown remaining: 37 sec"] = "クールダウン残り: 37秒", ["Cooldown remaining: 37 min"] = "クールダウン残り: 37分",
  ["Cooldown remaining: 37 hrs"] = "クールダウン残り: 37時間", ["Cooldown remaining: 37 days"] = "クールダウン残り: 37日",
  ["25 minutes remaining"] = "残り25分",
}

local AURA_EN = "Heals 12 damage every 3 seconds."
local AURA_JA = "$N2秒ごとに$N1のダメージを回復します。"
local AURA_SHOWN = "3秒ごとに12のダメージを回復します。"
local LINES = { "Rejuvenation", AURA_EN, "25 minutes remaining" }
local SHIELD_LINES = { "Power Word: Shield", "40 yd range", "Instant cast",
  "Draws on the soul of the friendly target to shield them, absorbing 44 damage. Lasts 30 sec." }
local JERKY = "|Hitem:117:0:0:0:0:0:0:0|h[Tough Jerky]|h"
local JERKY_LINES = { "Tough Jerky", "Use: Restores 61 health over 18 sec. Must remain seated while eating.",
  "Sell Price: 5c" }

local ROUNDING = { Up = 1, Nearest = 2, Down = 3 }
local GOLD, WHITE = { 1, 0.82, 0 }, { 1, 1, 1 }

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
    ["spell.aura"] = { [774] = { ja = AURA_JA, status = "u" }, [775] = { ja = "毎秒体力を回復します。", status = "." } },
    ["spell.description"] = { [17] = { ja = "味方にシールドを張り、$N1ダメージを吸収します。$N2秒間持続します。", status = "u" } },
    ["item.description"] = { [117] = { ja = "18秒間でhealthを61回復。回復中は\n座っている必要があります。", status = "u" } },
    ui = {},
  }
  for en, ja in pairs(UI_LINES) do DATA.ui[en] = { ja = ja, status = "." } end
  Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
  Stub.installTooltipAPI()
  for k, v in pairs(TIME_GLOBALS) do _G[k] = v end
  _G.date = function() return "12:00:00" end
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
  WFJ.UIIndex = { match = function(_, text) if UI_LINES[text] then return text, {} end end }
  Stub.spellDescriptions[17] = SHIELD_LINES[4]
  return WFJ, _G.GameTooltip
end

local function text(i) return _G["GameTooltipTextLeft" .. i]:GetText() end

-- the trace entry holding `needle` (the method hooks add a note after each pass, so it need not be the last)
local function traced(WFJ, needle)
  for i = #WFJ.Tooltip.trace, 1, -1 do
    if WFJ.Tooltip.trace[i]:find(needle, 1, true) then return WFJ.Tooltip.trace[i] end
  end
  return nil
end

-- the aura's data as C_UnitAuras returns it; it runs out 1500 s from now (the stub's clock stands at 0)
local function aura(key, spellId, lines)
  Stub.auraData[key] = { data = { spellId = spellId, expirationTime = 1500 }, lines = lines }
end

-- a secret pass: every line text the client writes is one the addon may not read
local function hideTexts(lines, more)
  local secret = {}
  for _, l in ipairs(lines) do secret[l] = true end
  for _, v in ipairs(more or {}) do secret[v] = true end
  _G.issecretvalue = function(v) return secret[v] == true end
end

describe("UI/Tooltip: buffs in combat and moving numbers", function()
  after_each(function()
    _G.issecretvalue = nil
    for k in pairs(TIME_GLOBALS) do _G[k] = nil end
    _G.date, _G.C_StringUtil, _G.C_DurationUtil, _G.C_TooltipInfo = nil, nil, nil, nil
    Stub.keys.alt = false
  end)

  describe("the aura memory", function()
    it("a buff first shown in combat takes what an earlier show of the same aura instance wrote", function()
      local WFJ, tt = setup()
      WFJ.Tooltip.init()
      WFJ.Tooltip.trace = {}
      aura("player#901", 774, LINES)
      tt:SetUnitBuffByAuraInstanceID("player", 901, "HELPFUL")
      assert.are.equal(AURA_SHOWN, text(2))
      assert.are.equal("残り25分", text(3))
      tt:Hide() -- the tooltip forgets its own Japanese
      -- in combat a minute later: every line secret, the time moved on
      local later = { LINES[1], LINES[2], "24 minutes remaining" }
      aura("player#901", 774, later)
      hideTexts(later)
      tt:SetUnitBuffByAuraInstanceID("player", 901, "HELPFUL")
      assert.are.equal(AURA_SHOWN, text(2))
      assert.are.equal("24 minutes remaining", text(3)) -- a time is never written back from memory
      assert.is_truthy(traced(WFJ, "from the aura's memory"))
      assert.is_truthy(traced(WFJ, "from the aura's memory"):find("secret aura", 1, true))
      WFJ.Tooltip.trace = nil
    end)

    it("only the instance-id methods name an aura: an index method's buff is not remembered", function()
      local WFJ, tt = setup()
      WFJ.Tooltip.init()
      WFJ.Tooltip.trace = {}
      aura("player:1:HELPFUL", 774, LINES)
      tt:SetUnitAura("player", 1, "HELPFUL")
      assert.are.equal(AURA_SHOWN, text(2))
      tt:Hide()
      hideTexts(LINES)
      tt:SetUnitAura("player", 1, "HELPFUL")
      assert.are.equal(AURA_EN, text(2))
      -- the player's buff falls to the buff bar's model (not loaded here), which cannot name it either
      assert.is_truthy(traced(WFJ, "aura not known ("))
      WFJ.Tooltip.trace = nil
    end)

    it("another aura instance on the same unit is not taken for the remembered one", function()
      local WFJ, tt = setup()
      WFJ.Tooltip.init()
      aura("player#901", 774, LINES)
      aura("player#902", 774, LINES)
      tt:SetUnitBuffByAuraInstanceID("player", 901, "HELPFUL")
      tt:Hide()
      hideTexts(LINES)
      tt:SetUnitBuffByAuraInstanceID("player", 902, "HELPFUL")
      assert.are.equal(AURA_EN, text(2))
    end)

    it("the memory is capped: past 400 auras it starts again", function()
      local WFJ, tt = setup()
      WFJ.Tooltip.init()
      for i = 1, 401 do
        aura("player#" .. i, 774, LINES)
        tt:SetUnitBuffByAuraInstanceID("player", i, "HELPFUL")
      end
      tt:Hide()
      hideTexts(LINES)
      tt:SetUnitBuffByAuraInstanceID("player", 1, "HELPFUL")
      assert.are.equal(AURA_EN, text(2)) -- forgotten when the memory started again
      tt:Hide()
      tt:SetUnitBuffByAuraInstanceID("player", 401, "HELPFUL")
      assert.are.equal(AURA_SHOWN, text(2)) -- kept after it
    end)

    it("the player's auras are learnt from the client's tooltip data, with no hover", function()
      local WFJ, tt = setup()
      WFJ.Tooltip.init()
      local plain = { "Renew", "Restores health every second.", "25 minutes remaining" }
      Stub.auraData["player:1:HELPFUL"] = { data = { spellId = 775, auraInstanceID = 950, expirationTime = 1500 } }
      Stub.auraData["player#950"] = { data = { spellId = 775, auraInstanceID = 950, expirationTime = 1500 },
        lines = plain }
      _G.C_TooltipInfo = { GetUnitAuraByAuraInstanceID = function(unit, id)
        if unit == "player" and id == 950 then
          return { lines = { { leftText = plain[1] }, { leftText = plain[2] }, { leftText = plain[3] } } }
        end
      end }
      assert.are.equal(1, WFJ.Tooltip.learnPlayerAuras())
      hideTexts(plain)
      tt:SetUnitBuffByAuraInstanceID("player", 950, "HELPFUL")
      assert.are.equal("Renew", text(1))
      assert.are.equal("毎秒体力を回復します。", text(2))
      assert.are.equal("25 minutes remaining", text(3)) -- a time row is not learnt
    end)

    -- the gate needs the line itself to fill live values ($N, status "u", the usual case)
    it("a learnt aura whose Japanese carries live values is filled from the learnt line", function()
      local WFJ, tt = setup()
      WFJ.Tooltip.init()
      Stub.auraData["player:1:HELPFUL"] = { data = { spellId = 774, auraInstanceID = 951, expirationTime = 1500 } }
      Stub.auraData["player#951"] = { data = { spellId = 774, auraInstanceID = 951, expirationTime = 1500 },
        lines = LINES }
      _G.C_TooltipInfo = { GetUnitAuraByAuraInstanceID = function()
        return { lines = { { leftText = LINES[1] }, { leftText = LINES[2] }, { leftText = LINES[3] } } }
      end }
      assert.are.equal(1, WFJ.Tooltip.learnPlayerAuras())
      hideTexts(LINES)
      tt:SetUnitBuffByAuraInstanceID("player", 951, "HELPFUL")
      assert.are.equal(AURA_SHOWN, text(2))
    end)

    it("an aura's time row on a secret pass is written by the client's formatter from the aura's duration", function()
      local WFJ, tt = setup()
      installFormatter()
      WFJ.Tooltip.init()
      local left = 1500 -- the aura's expiration time agrees: the formatter is checked on the readable pass
      _G.C_UnitAuras.GetAuraDuration = function(unit, id)
        if unit == "player" and id == 901 then return duration(left) end
      end
      aura("player#901", 774, LINES)
      tt:SetUnitBuffByAuraInstanceID("player", 901, "HELPFUL")
      assert.are.equal("aura: rule 1.5/up/up, 1 lines seen, formatter checked", WFJ.TimeLine.status()[1])
      left = 1440
      hideTexts({ LINES[1], LINES[2], "24 minutes remaining" })
      tt:rebuild({ LINES[1], LINES[2], "24 minutes remaining" })
      assert.are.equal(AURA_SHOWN, text(2))
      assert.are.equal("残り24分", text(3))
    end)
  end)

  describe("the cooldown row a secret pass adds", function()
    local function paint(colours)
      for i, c in ipairs(colours) do _G["GameTooltipTextLeft" .. i]:SetTextColor(c[1], c[2], c[3]) end
    end
    local SPELL_COLOURS = { WHITE, WHITE, WHITE, GOLD }
    local WITH_COUNTDOWN = { SHIELD_LINES[1], SHIELD_LINES[2], SHIELD_LINES[3], "Cooldown remaining: 2 sec",
      SHIELD_LINES[4] }

    local function spellPasses(WFJ, tt, hidden)
      WFJ.Tooltip.init()
      tt.owner = "ActionButton1"
      tt.spell = { name = SHIELD_LINES[1], id = 17 }
      tt:writeLines(SHIELD_LINES)
      paint(SPELL_COLOURS)
      Stub.fireTooltipSet(tt, "Spell")
      local ja = text(4)
      assert.is_truthy(ja:find("シールド", 1, true))
      hideTexts(WITH_COUNTDOWN, hidden)
      tt:writeLines(WITH_COUNTDOWN)
      paint({ WHITE, WHITE, WHITE, WHITE, GOLD })
      Stub.fireTooltipSet(tt, "Spell")
      return ja
    end

    it("a spell's readable cooldown: the seconds left, in Japanese by the rule", function()
      local WFJ, tt = setup()
      _G.C_Spell.GetSpellCooldown = function() return { startTime = 0, duration = 1.4 } end
      local ja = spellPasses(WFJ, tt)
      assert.are.equal("クールダウン残り: 2秒", text(4))
      assert.are.equal(ja, text(5))
    end)

    it("a spell's hidden cooldown: the client's formatter writes it from the cooldown's duration", function()
      local WFJ, tt = setup()
      installFormatter()
      local START, LENGTH = 1000.25, 2.75 -- values the addon may not read on the secret pass
      local readable = true
      _G.C_Spell.GetSpellCooldown = function()
        if readable then return { startTime = 0, duration = 0 } end
        return { startTime = START, duration = LENGTH }
      end
      _G.C_Spell.GetSpellCooldownDuration = function() return duration(1.4) end
      WFJ.Tooltip.trace = {}
      local ja = spellPasses(WFJ, tt, (function() readable = false; return { START, LENGTH } end)())
      assert.are.equal("クールダウン残り: 2秒", text(4))
      assert.are.equal(ja, text(5))
      assert.is_truthy(traced(WFJ, "countdown row 4: hidden, written by the client"))
      WFJ.Tooltip.trace = nil
    end)

    local function itemPasses(WFJ, tt, hidden)
      WFJ.Tooltip.init()
      tt.owner = "ContainerFrame1Item1"
      Stub.setItemTooltip(tt, JERKY, JERKY_LINES)
      paint({ WHITE, GOLD, WHITE })
      Stub.setItemTooltip(tt, JERKY, JERKY_LINES) -- the colours as the client paints them before the post-call
      paint({ WHITE, GOLD, WHITE })
      local ja = text(2)
      local lines = { JERKY_LINES[1], "Cooldown remaining: 75 sec", JERKY_LINES[2], JERKY_LINES[3] }
      hideTexts(lines, hidden)
      tt:writeLines(lines)
      paint({ WHITE, WHITE, GOLD, WHITE })
      Stub.fireTooltipSet(tt, "Item")
      return ja
    end

    it("an item's cooldown is read and written in Japanese", function()
      local WFJ, tt = setup()
      _G.C_Item.GetItemCooldown = function(id) if id == 117 then return 0, 75, 1 end end
      local ja = itemPasses(WFJ, tt)
      assert.are.equal("クールダウン残り: 75秒", text(2))
      assert.are.equal(ja, text(3))
    end)

    it("an item's hidden cooldown leaves the client's row", function()
      local WFJ, tt = setup()
      _G.C_Item.GetItemCooldown = function() return 1000.25, 2.75, 1 end
      WFJ.Tooltip.trace = {}
      local ja = itemPasses(WFJ, tt, { 1000.25, 2.75 })
      assert.are.equal("Cooldown remaining: 75 sec", text(2))
      assert.are.equal(ja, text(3))
      assert.is_truthy(traced(WFJ, "countdown row 2: item cooldown hidden"))
      WFJ.Tooltip.trace = nil
    end)

    it("a readable cooldown line teaches the rule", function()
      local WFJ, tt = setup()
      WFJ.Tooltip.init()
      local left = 75
      _G.C_Item.GetItemCooldown = function() return 0, left, 1 end
      -- 75 s shown as 2 min: the client switches at one minute and rounds minutes up; Blizzard's rules are out
      Stub.setItemTooltip(tt, JERKY, { JERKY_LINES[1], "Cooldown remaining: 2 min", JERKY_LINES[2] })
      assert.is_nil(WFJ.TimeLine.rule("cooldown"))
      -- 1.4 s shown as 2 sec: seconds round up too
      left = 1.4
      Stub.setItemTooltip(tt, JERKY, { JERKY_LINES[1], "Cooldown remaining: 2 sec", JERKY_LINES[2] })
      assert.are.equal("1/up/up", WFJ.TimeLine.rule("cooldown").id)
      assert.are.equal("1.5/up/up", WFJ.TimeLine.rule("aura").id) -- the other family learns on its own
    end)
  end)

  describe("the trace", function()
    it("an identical pass is counted on the entry before it, not added again", function()
      local WFJ, tt = setup()
      WFJ.Tooltip.init()
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

    it("a note is one line, counted the same way; with the trace off nothing is kept", function()
      local WFJ = setup()
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
      _G.Enum.TooltipDataLineType = { None = 0, UnitName = 2, QuestTitle = 17 }
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
