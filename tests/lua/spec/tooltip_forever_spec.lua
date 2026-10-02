-- The tooltip surface's hook path.
--
-- Forever's tooltips are the `mainline` flavour: GameTooltip:HasScript("OnTooltipSetItem") is false (checked
-- in game), and HookScript on that name raises `bad argument #2`, which takes the whole addon down. The
-- client's own blizzard_sharedxmlgame/tooltip/tooltipdatahandler.lua uses
-- TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.<type>, fn), and so does the surface.
--
-- The contract these tests hold: one registration per data type, zero OnTooltipSet* HookScript calls, OnHide hooked
-- per frame, and the item and spell tooltips rendered through the post-calls.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = { "Core/Const.lua", "Core/Compat.lua", "Core/Align.lua", "Core/State.lua", "Core/Settings.lua",
  "Core/Modifier.lua", "Core/Translator.lua", "Core/SurfaceState.lua", "Core/Normalize.lua", "Core/Hash.lua",
  "Core/Collector.lua", "UI/Font.lua", "UI/Render.lua",
  "UI/TimeLine.lua", "UI/Tooltip.lua", "UI/TooltipUnit.lua" }

local DATA = {
  -- keyed by the kind the surface asks for; field-qualified because spell has two fields
  ["item.description"] = { [117] = { ja = "18秒間でhealthを61回復。回復中は\n座っている必要があります。", status = "u" } },
  ["spell.description"] = { [17] = { ja = "味方にシールドを張り、$N1ダメージを吸収します。$N2秒間持続します。", status = "u" } },
}
local JERKY = "|Hitem:117:0:0:0:0:0:0:0|h[Tough Jerky]|h"
local JERKY_LINES = { "Tough Jerky", "Use: Restores 61 health over 18 sec. Must remain seated while eating.",
  "Sell Price: 5c" }
local SHIELD_LINES = { "Power Word: Shield", "40 yd range", "Instant cast",
  "Draws on the soul of the friendly target to shield them, absorbing 44 damage. Lasts 30 sec." }

-- Loads the surface against a stub client of the given flavour. → WFJ, the tooltip frame
local function setup()
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
  Stub.spellDescriptions[17] =
    "Draws on the soul of the friendly target to shield them, absorbing 44 damage. Lasts 30 sec."
  return WFJ, _G.GameTooltip
end

local function fs(frameName, i) return _G[frameName .. "TextLeft" .. i] end

describe("UI/Tooltip hooks the client's data processor", function()
  after_each(function() _G.issecretvalue, _G.GetActionInfo, _G.C_TooltipInfo = nil, nil, nil end)

  it("takes the data-processor path and hooks no OnTooltipSet* script", function()
    local WFJ = setup()
    assert.are.equal(6, WFJ.Tooltip.init())
    local _, _, _, path = WFJ.Tooltip.resolved()
    assert.are.equal("dataprocessor", path)
    assert.is_not_nil(WFJ.Tooltip.modern())
    -- exactly one registration per data type, for the whole client, not one per frame
    assert.are.equal(1, #Stub.tooltipPostCalls[0])
    assert.are.equal(1, #Stub.tooltipPostCalls[1])
    for _, name in ipairs(WFJ.Tooltip.FRAMES) do
      assert.is_nil(_G[name].scripts.OnTooltipSetItem, name)
      assert.is_nil(_G[name].scripts.OnTooltipSetSpell, name)
      assert.is_function(_G[name].scripts.OnHide, name) -- a plain widget script
    end
  end)

  it("renders the item tooltip through the Item post-call", function()
    local WFJ, tt = setup()
    WFJ.Tooltip.init()
    Stub.setItemTooltip(tt, JERKY, JERKY_LINES)
    assert.are.equal(DATA["item.description"][117].ja, fs("GameTooltip", 2):GetText())
    assert.are.equal("Tough Jerky", fs("GameTooltip", 1):GetText())
    assert.are.equal("Sell Price: 5c", fs("GameTooltip", 3):GetText())
  end)

  it("renders the spell tooltip through the Spell post-call, reading the description the client offers",
    function()
      local WFJ, tt = setup()
      WFJ.Tooltip.init()
      -- Forever answered the bare GetSpellDescription absent (in-game probe); the stub carries only
      -- C_Spell.GetSpellDescription, which Compat resolves as a dotted candidate.
      local _, _, api = WFJ.Tooltip.resolved()
      assert.is_true(api)
      Stub.setSpellTooltip(tt, 17, SHIELD_LINES)
      assert.are.equal("Power Word: Shield", fs("GameTooltip", 1):GetText())
      assert.is_truthy(fs("GameTooltip", 4):GetText():find("シールド", 1, true))
    end)

  -- the client's own tooltip data for spell 17, as C_TooltipInfo.GetSpellByID answers it in game: plain rows,
  -- the countdown hidden, the description typed. The stub tells a secret by its value, so the frame's hidden
  -- rows carry a trailing space and the data rows stay readable, as they do in game.
  local COUNTDOWN = "Cooldown remaining: 1 sec"
  local SHIELD_ROWS = { { leftText = SHIELD_LINES[1], rightText = "Rank 1" }, { leftText = SHIELD_LINES[2] },
    { leftText = SHIELD_LINES[3] }, { leftText = COUNTDOWN }, { leftText = SHIELD_LINES[4], type = 34 } }
  local HIDDEN = { SHIELD_LINES[1] .. " ", SHIELD_LINES[2] .. " ", SHIELD_LINES[3] .. " ", COUNTDOWN .. " ",
    SHIELD_LINES[4] .. " ", " ", "Press F6 " }
  local function hiddenClient()
    _G.Enum.TooltipDataLineType = { None = 0, SpellName = 13, SpellDescription = 34 }
    _G.C_TooltipInfo = { GetSpellByID = function(id) if id == 17 then return { id = 17, lines = SHIELD_ROWS } end end }
  end
  local function hide(lines, more)
    local secret = {}
    for _, l in ipairs(lines) do secret[l] = true end
    for _, v in ipairs(more or {}) do secret[v] = true end
    _G.issecretvalue = function(v) return secret[v] == true end
  end
  local function hiddenPass(tt, id)
    tt.spell = { name = SHIELD_LINES[1], id = id or 17 }
    tt.item = nil
    tt.primaryInfo = { tooltipData = { lines = { { lineIndex = 1, type = 13 }, { lineIndex = 2, type = 0 },
      { lineIndex = 3, type = 0 }, { lineIndex = 4, type = 0 }, { lineIndex = 5, type = 34 } } } }
    tt:writeLines(HIDDEN)
    Stub.fireTooltipSet(tt, "Spell")
  end

  it("a hidden pass reads no row: it translates the client's own data for the spell and writes it by row", function()
    -- an action button's tooltip in combat: every row's text is secret, the spell id is not
    local WFJ, tt = setup()
    WFJ.Tooltip.init()
    hiddenClient()
    tt.owner = "ActionButton1"
    hide(HIDDEN, { COUNTDOWN })
    assert.has_no.errors(function() hiddenPass(tt) end)
    assert.is_truthy(fs("GameTooltip", 5):GetText():find("シールド", 1, true))
    assert.are.equal(SHIELD_LINES[1] .. " ", fs("GameTooltip", 1):GetText()) -- the name is never replaced
    assert.are.equal(COUNTDOWN .. " ", fs("GameTooltip", 4):GetText()) -- no duration API in this stub: left
    assert.are.equal("Press F6 ", fs("GameTooltip", 7):GetText()) -- another addon's row: left
    assert.are.equal(1, WFJ.Tooltip.hidden.written)
    -- the spell id hidden too (a secret stands in for it here): the owner's action slot names it
    tt.owner = { action = 5 }
    _G.GetActionInfo = function(slot) if slot == 5 then return "spell", 17 end end
    hide(HIDDEN, { COUNTDOWN, "hidden id" })
    assert.has_no.errors(function() hiddenPass(tt, "hidden id") end)
    assert.is_truthy(fs("GameTooltip", 5):GetText():find("シールド", 1, true))
    -- no slot either: nothing can be looked up, the English stays
    tt.owner = "ActionButton1"
    hiddenPass(tt, "hidden id")
    assert.are.equal(SHIELD_LINES[4] .. " ", fs("GameTooltip", 5):GetText())
    assert.are.equal("the spell or item itself is hidden", WFJ.Tooltip.hidden.last)
    -- the modifier held: the client's English stays
    hide(HIDDEN, { COUNTDOWN })
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    hiddenPass(tt)
    assert.are.equal(SHIELD_LINES[4] .. " ", fs("GameTooltip", 5):GetText())
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    -- readable again: the ordinary path, with records
    _G.issecretvalue = nil
    Stub.setSpellTooltip(tt, 17, SHIELD_LINES)
    assert.is_truthy(fs("GameTooltip", 4):GetText():find("シールド", 1, true))
    _G.C_TooltipInfo, _G.GetActionInfo = nil, nil
  end)

  it("the trace records each pass row by row and writes a secret value as <secret>, never reading it", function()
    local WFJ, tt = setup()
    WFJ.Tooltip.init()
    hiddenClient()
    WFJ.Tooltip.trace = {}
    tt.owner = "ActionButton1"
    Stub.setSpellTooltip(tt, 17, SHIELD_LINES)
    hide(HIDDEN, { COUNTDOWN })
    assert.has_no.errors(function() hiddenPass(tt) end)
    _G.issecretvalue = nil
    assert.are.equal(2, #WFJ.Tooltip.trace)
    assert.is_truthy(WFJ.Tooltip.trace[1]:find("readable spell", 1, true))
    assert.is_truthy(WFJ.Tooltip.trace[2]:find("secret spell id=17", 1, true))
    assert.is_truthy(WFJ.Tooltip.trace[2]:find("<secret>", 1, true))
    assert.is_truthy(WFJ.Tooltip.trace[2]:find("-> wrote 1 (data rows 5, hidden: 4", 1, true))
    WFJ.Tooltip.trace = nil
    _G.C_TooltipInfo = nil
  end)

  it("ignores a tooltip whose data type is not the one the handler registered for", function()
    local WFJ, tt = setup()
    WFJ.Tooltip.init()
    Stub.setItemTooltip(tt, JERKY, JERKY_LINES)
    local before = fs("GameTooltip", 2):GetText()
    -- the Spell handler, handed an item tooltip: IsTooltipType(Spell) is false, so it must not touch it
    Stub.tooltipPostCalls[1][1](tt)
    assert.are.equal(before, fs("GameTooltip", 2):GetText())
  end)

  it("ignores a tooltip frame the addon never declared", function()
    local WFJ = setup()
    WFJ.Tooltip.init()
    local other = Stub.tooltipFrame("SomeOtherAddonTooltip")
    Stub.setItemTooltip(other, JERKY, JERKY_LINES)
    assert.are.equal(JERKY_LINES[2], _G.SomeOtherAddonTooltipTextLeft2:GetText())
  end)

  it("keeps the spell-description API absent when the client has neither name", function()
    Stub.noSpellDescriptionAPI = true
    local WFJ = setup()
    WFJ.Tooltip.init()
    local _, _, api = WFJ.Tooltip.resolved()
    assert.is_false(api)
    Stub.noSpellDescriptionAPI = false
  end)
end)
