-- Buff and debuff tooltips. The client shows an aura through GameTooltip:SetUnitAura / SetUnitBuff /
-- SetUnitDebuff or their *ByAuraInstanceID twins and never runs the Spell post-call for it (Forever types it
-- Enum.TooltipDataType.UnitAura). The surface registers one UnitAura post-call and reads the spell id from
-- C_UnitAuras with the call's own arguments, as Blizzard's PTR reporter does.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = { "Core/Const.lua", "Core/Compat.lua", "Core/Align.lua", "Core/State.lua", "Core/Settings.lua",
  "Core/Modifier.lua", "Core/Translator.lua", "Core/SurfaceState.lua", "Core/Normalize.lua", "Core/Hash.lua",
  "Core/Collector.lua", "UI/Font.lua", "UI/Render.lua", "UI/TimeLine.lua", "UI/Tooltip.lua",
  "UI/TooltipUnit.lua" }

-- Rejuvenation-like: the aura line carries the live values the Japanese fills
local AURA_EN = "Heals 12 damage every 3 seconds."
local AURA_JA = "$N2秒ごとに$N1のダメージを回復します。"
local AURA_SHOWN = "3秒ごとに12のダメージを回復します。"
local DATA

local function reset()
  DATA = {
    ["spell.aura"] = { [774] = { ja = AURA_JA, status = "u" } },
    ["spell.description"] = { [774] = { ja = "説明文。", status = "." }, [8936] = { ja = "説明文。", status = "." } },
    ui = { SPELL_TIME_REMAINING_MIN = { ja = "残り25分", status = "." } },
  }
end

local function setup()
  reset()
  Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
  Stub.installTooltipAPI()
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
  -- the UI dictionary, reduced to the one "remaining" line these tooltips carry
  WFJ.UIIndex = { match = function(_, text)
    if text == "25 min remaining" then return "SPELL_TIME_REMAINING_MIN", {} end
  end }
  return WFJ, _G.GameTooltip
end

local function aura(key, spellId, lines)
  Stub.auraData[key] = { data = spellId ~= nil and { spellId = spellId } or nil, lines = lines }
end

local function text(i) return _G["GameTooltipTextLeft" .. i]:GetText() end

local LINES = { "Rejuvenation", AURA_EN, "25 min remaining" }

-- method → how to call it and the key its getter reads
local CALLS = {
  { "SetUnitAura", { "player", 1, "HELPFUL" }, "player:1:HELPFUL" },
  { "SetUnitBuff", { "target", 2 }, "target:2:HELPFUL" },
  { "SetUnitDebuff", { "target", 3 }, "target:3:HARMFUL" },
  { "SetUnitAuraByAuraInstanceID", { "player", 901 }, "player#901" },
  { "SetUnitBuffByAuraInstanceID", { "party1", 902, "HELPFUL" }, "party1#902" },
  { "SetUnitDebuffByAuraInstanceID", { "raid3", 903, "HARMFUL" }, "raid3#903" },
}

describe("UI/Tooltip: buff and debuff tooltips", function()
  after_each(function() Stub.keys.alt = false end)

  it("one UnitAura post-call, which also sees every rebuild; a method hook only notes the call in the trace",
    function()
      local WFJ, tt = setup()
      WFJ.Tooltip.init()
      local _, _, _, _, auras = WFJ.Tooltip.resolved()
      assert.are.equal(6, auras)
      assert.are.equal(1, #Stub.tooltipPostCalls[7])
      WFJ.Tooltip.init()
      assert.are.equal(1, #Stub.tooltipPostCalls[7])
      -- the hook writes nothing: with the trace off the call leaves no note, with it on one line names the call
      aura("player:1:HELPFUL", 774, LINES)
      tt:SetUnitAura("player", 1, "HELPFUL")
      assert.are.equal(AURA_SHOWN, text(2))
      WFJ.Tooltip.trace = {}
      tt:SetUnitAura("player", 1, "HELPFUL")
      assert.are.equal(AURA_SHOWN, text(2))
      local called = 0
      for _, line in ipairs(WFJ.Tooltip.trace) do
        if line:find("SetUnitAura(player, 1, HELPFUL) called", 1, true) then called = called + 1 end
      end
      assert.are.equal(1, called)
      WFJ.Tooltip.trace = nil
    end)

  it("a Forever rebuild rewrites the lines without calling a method, and the Japanese comes back", function()
    local WFJ, tt = setup()
    WFJ.Tooltip.init()
    aura("player:1:HELPFUL", 774, LINES)
    tt:SetUnitAura("player", 1, "HELPFUL")
    assert.are.equal(AURA_SHOWN, text(2))
    -- TOOLTIP_DATA_UPDATE: the client rewrites every line from its data (the stack or the timer changed)
    tt:rebuild({ "Rejuvenation", "Heals 14 damage every 3 seconds.", "24 min remaining" })
    assert.are.equal("3秒ごとに14のダメージを回復します。", text(2))
  end)

  it("every method shows the aura line in Japanese, filled from the live line", function()
    for _, c in ipairs(CALLS) do
      local WFJ, tt = setup()
      WFJ.Tooltip.init()
      aura(c[3], 774, LINES)
      tt[c[1]](tt, unpack(c[2]))
      assert.are.equal(AURA_SHOWN, text(2), c[1])
      assert.are.equal("Rejuvenation", text(1), c[1]) -- the name is never replaced
    end
  end)

  it("a gate failure, the modifier held and a stale entry behave as on spell tooltips", function()
    local WFJ, tt = setup()
    WFJ.Settings.set("marker.missing", false) -- on by default; this test reads the text, not the marker
    WFJ.Tooltip.init()
    -- the live line has no second number: $N2 cannot fill, the gate refuses, English stays
    aura("player:1:HELPFUL", 774, { "Rejuvenation", "Heals 12 damage.", "" })
    tt:SetUnitAura("player", 1, "HELPFUL")
    assert.are.equal("Heals 12 damage.", text(2))
    -- the modifier shows the client's English
    Stub.keys.alt = true
    aura("player:2:HELPFUL", 774, LINES)
    tt:SetUnitAura("player", 2, "HELPFUL")
    assert.are.equal(AURA_EN, text(2))
    Stub.keys.alt = false
    -- stale: still gated, applied with the marker when it passes
    DATA["spell.aura"][774].status = "s"
    tt:SetUnitAura("player", 2, "HELPFUL")
    assert.is_truthy(text(2):find(AURA_SHOWN, 1, true))
  end)

  it("a buff no level-1 character sees (Campfire Nearby) and a spell description from the served-text round show"
    .. " their Japanese; Alt shows the English", function()
    local WFJ, tt = setup()
    local campfire = "The pleasant smoke of a campfire drifts in the air from somewhere nearby."
    DATA["spell.aura"][1283391] = { ja = "どこか近くから、キャンプファイアの心地よい煙が漂ってきます。", status = "u" }
    DATA["spell.description"][45] = { ja = "周囲の敵をノックバックします。", status = "u" }
    WFJ.Tooltip.init()
    aura("player:4:HELPFUL", 1283391, { "Campfire Nearby", campfire, "" })
    tt:SetUnitAura("player", 4, "HELPFUL")
    assert.are.equal("どこか近くから、キャンプファイアの心地よい煙が漂ってきます。", text(2))
    assert.are.equal("Campfire Nearby", text(1)) -- the name stays English
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal(campfire, text(2))
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    Stub.spellDescriptions[45] = "Knocks nearby enemies back."
    Stub.setSpellTooltip(tt, 45, { "Knockback", "Knocks nearby enemies back." })
    assert.are.equal("周囲の敵をノックバックします。", text(2))
  end)

  it("a spell with a description and no aura shows no Japanese on its aura tooltip", function()
    local WFJ, tt = setup()
    WFJ.Settings.set("marker.missing", false) -- on by default; this test reads the text, not the marker
    WFJ.Tooltip.init()
    aura("target:1:HARMFUL", 8936, { "Regrowth", "Heals 5 damage every 2 sec.", "" })
    tt:SetUnitDebuff("target", 1)
    assert.are.equal("Heals 5 damage every 2 sec.", text(2))
  end)

  it("an empty or UI-dictionary line 2 is never the aura line", function()
    local WFJ, tt = setup()
    WFJ.Tooltip.init()
    local seen = {}
    WFJ.Collector.record = function(_, _, field) seen[#seen + 1] = field end
    aura("player:1:HELPFUL", 774, { "Rejuvenation", "25 min remaining" })
    tt:SetUnitAura("player", 1, "HELPFUL")
    assert.are.equal("残り25分", text(2)) -- a UI record, not the aura text
    aura("player:2:HELPFUL", 774, { "Rejuvenation", "" })
    tt:SetUnitAura("player", 2, "HELPFUL")
    assert.are.equal("", text(2))
    assert.are.same({}, seen) -- neither was recorded as aura English
  end)

  it("an unreadable aura leaves the tooltip untouched and raises nothing", function()
    local WFJ, tt = setup()
    WFJ.Tooltip.init()
    aura("player:1:HELPFUL", nil, LINES) -- the getter answers nil
    assert.has_no.errors(function() tt:SetUnitAura("player", 1, "HELPFUL") end)
    assert.are.equal(AURA_EN, text(2))
    Stub.auraData["player:2:HELPFUL"] = { data = { spellId = "774" }, lines = LINES } -- not a number
    tt:SetUnitAura("player", 2, "HELPFUL")
    assert.are.equal(AURA_EN, text(2))
    -- a secret value (Forever's SecretWhenUnitAuraRestricted): reading it raises
    Stub.auraData["player:3:HELPFUL"] = { data = setmetatable({}, { __index = function() error("secret") end }),
      lines = LINES }
    assert.has_no.errors(function() tt:SetUnitAura("player", 3, "HELPFUL") end)
    assert.are.equal(AURA_EN, text(2))
    -- a getter that raises
    local W2, tt2 = setup()
    _G.C_UnitAuras.GetAuraDataByIndex = function() error("restricted") end
    W2.Tooltip.init()
    aura("player:4:HELPFUL", 774, LINES)
    assert.has_no.errors(function() tt2:SetUnitAura("player", 4, "HELPFUL") end)
    assert.are.equal(AURA_EN, text(2))
    -- no C_UnitAuras on the client at all: the post-call runs, nothing is shown, nothing raises
    local W3, tt3 = setup()
    _G.C_UnitAuras = nil
    W3.Tooltip.init()
    aura("player:5:HELPFUL", 774, LINES)
    assert.has_no.errors(function() tt3:SetUnitAura("player", 5, "HELPFUL") end)
    assert.are.equal(AURA_EN, text(2))
  end)

  it("QA: a line another addon appended is never the aura text on Forever", function()
    local WFJ, tt = setup()
    WFJ.Tooltip.init()
    local seen = {}
    WFJ.Collector.record = function(_, _, field) seen[#seen + 1] = field end
    -- an aura whose client-written tooltip is the name alone; an id addon appended "Spell ID: 774"
    Stub.auraData["player:1:HELPFUL"] = { data = { spellId = 774 }, lines = { "Rejuvenation" },
      extra = { "Spell ID: 774" } }
    tt:SetUnitAura("player", 1, "HELPFUL")
    assert.are.equal("Spell ID: 774", text(2))
    assert.are.same({}, seen)
  end)

  it("QA: filters beyond HELPFUL / HARMFUL pass through; the instance getter gets no filter", function()
    local WFJ, tt = setup()
    WFJ.Tooltip.init()
    aura("player:1:HELPFUL", 774, LINES)
    tt:SetUnitAura("player", 1, "HELPFUL|PLAYER")
    assert.are.equal(AURA_SHOWN, text(2))
    aura("target:3:HARMFUL", 774, LINES)
    tt:SetUnitDebuff("target", 3, "RAID")
    assert.are.equal(AURA_SHOWN, text(2))
    -- the instance getter is (unit, auraInstanceID): spied on before init, when Compat resolves it
    local W2, tt2 = setup()
    local args
    local get = _G.C_UnitAuras.GetAuraDataByAuraInstanceID
    _G.C_UnitAuras.GetAuraDataByAuraInstanceID = function(...) args = { n = select("#", ...) }; return get(...) end
    W2.Tooltip.init()
    aura("party1#902", 774, LINES)
    tt2:SetUnitBuffByAuraInstanceID("party1", 902, "HELPFUL")
    assert.are.equal(2, args.n)
    assert.are.equal(AURA_SHOWN, text(2))
    assert.are.equal(0, WFJ.Tooltip.auraErrors)
  end)

  it("QA: a secret line text leaves the tooltip alone, and any error in the handler is counted, not raised", function()
    local WFJ, tt = setup()
    WFJ.Tooltip.init()
    aura("player:1:HELPFUL", 774, LINES)
    tt:SetUnitAura("player", 1, "HELPFUL")
    assert.are.equal(AURA_SHOWN, text(2))
    -- restricted: the client's text is secret and so is which buff it is; nothing is compared or raised, and the
    -- client's own line stays (a buff in combat has no readable handle to look its Japanese up by)
    _G.issecretvalue = function(v) return v == "Heals 13 damage every 3 seconds." end
    assert.has_no.errors(function() tt:rebuild({ "Rejuvenation", "Heals 13 damage every 3 seconds.", "" }) end)
    assert.are.equal("Heals 13 damage every 3 seconds.", text(2))
    _G.issecretvalue = nil
    -- readable again: the Japanese comes back on its own
    tt:rebuild(LINES)
    assert.are.equal(AURA_SHOWN, text(2))
    -- an error inside the handler: counted, the tooltip left as the client wrote it
    WFJ.UIIndex = { match = function() error("boom") end }
    local before = WFJ.Tooltip.auraErrors
    assert.has_no.errors(function() tt:SetUnitAura("player", 1, "HELPFUL") end)
    assert.are.equal(before + 1, WFJ.Tooltip.auraErrors)
  end)

  it("the other lines go through the structural path", function()
    local WFJ, tt = setup()
    WFJ.Tooltip.init()
    aura("player:1:HELPFUL", 774, LINES)
    tt:SetUnitAura("player", 1, "HELPFUL")
    assert.are.equal("残り25分", text(3))
  end)

  it("the aura line's English is recorded as spell / aura", function()
    local WFJ, tt = setup()
    WFJ.Tooltip.init()
    local seen = {}
    WFJ.Collector.record = function(kind, id, field, raw) seen[#seen + 1] = { kind, id, field, raw } end
    aura("player:1:HELPFUL", 774, LINES)
    tt:SetUnitAura("player", 1, "HELPFUL")
    assert.are.same({ { "spell", 774, "aura", AURA_EN } }, seen)
    assert.is_true(WFJ.Collector.KINDS.spell.aura)
    -- a spell whose aura does not ship: line 2 is only a positional guess, so it is not recorded
    aura("player:2:HELPFUL", 8936, { "Regrowth", "Heals 5 damage every 2 sec.", "" })
    tt:SetUnitAura("player", 2, "HELPFUL")
    assert.are.equal(1, #seen)
  end)

  it("an aura never runs the spell handler, a spell never runs the aura handler", function()
    local WFJ, tt = setup()
    WFJ.Tooltip.init()
    local spells = 0
    local onSpell = WFJ.Tooltip.onSpell
    WFJ.Tooltip.onSpell = function(...) spells = spells + 1; return onSpell(...) end
    aura("player:1:HELPFUL", 774, LINES)
    tt:SetUnitAura("player", 1, "HELPFUL")
    assert.are.equal(0, spells)
    Stub.spellDescriptions[774] = "Heals the target."
    Stub.setSpellTooltip(tt, 774, { "Rejuvenation", "Heals the target." })
    assert.are.equal("説明文。", text(2))
    local auras = 0
    local onAura = WFJ.Tooltip.onAura
    WFJ.Tooltip.onAura = function(...) auras = auras + 1; return onAura(...) end
    Stub.setSpellTooltip(tt, 774, { "Rejuvenation", "Heals the target." })
    assert.are.equal(0, auras)
  end)
end)
