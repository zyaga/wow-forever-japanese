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
  "UI/Tooltip.lua" }

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

  it("a secret pass reads nothing and raises nothing; it puts back what the last readable pass wrote", function()
    -- an action button's tooltip turns secret while its spell casts or cools down: the client rewrites the English
    local WFJ, tt = setup()
    WFJ.Tooltip.init()
    local secret = {}
    for _, l in ipairs(SHIELD_LINES) do secret[l] = true end
    for _, l in ipairs(JERKY_LINES) do secret[l] = true end
    -- nothing rendered yet: a secret pass leaves the English
    _G.issecretvalue = function(v) return secret[v] == true end
    assert.has_no.errors(function() Stub.setSpellTooltip(tt, 17, SHIELD_LINES) end)
    assert.are.equal(SHIELD_LINES[4], fs("GameTooltip", 4):GetText())
    _G.issecretvalue = nil
    -- a readable pass renders, then a secret pass for the same spell keeps the Japanese instead of flashing English
    Stub.setSpellTooltip(tt, 17, SHIELD_LINES)
    local ja = fs("GameTooltip", 4):GetText()
    assert.is_truthy(ja:find("シールド", 1, true))
    _G.issecretvalue = function(v) return secret[v] == true end
    assert.has_no.errors(function() Stub.setSpellTooltip(tt, 17, SHIELD_LINES) end)
    assert.are.equal(ja, fs("GameTooltip", 4):GetText())
    assert.are.equal("Power Word: Shield", fs("GameTooltip", 1):GetText())
    -- the spell id secret too: the same owner stands for it
    tt.owner = "ActionButton1"
    _G.issecretvalue = nil
    Stub.setSpellTooltip(tt, 17, SHIELD_LINES)
    secret[17] = true
    _G.issecretvalue = function(v) return secret[v] == true end
    assert.has_no.errors(function() Stub.setSpellTooltip(tt, 17, SHIELD_LINES) end)
    assert.are.equal(ja, fs("GameTooltip", 4):GetText())
    -- another owner (another button): nothing is put back
    tt.owner = "ActionButton2"
    Stub.setSpellTooltip(tt, 17, SHIELD_LINES)
    assert.are.equal(SHIELD_LINES[4], fs("GameTooltip", 4):GetText())
    tt.owner = "ActionButton1"
    secret[17] = nil
    -- another item on the same frame: nothing to put back, the English stays
    assert.has_no.errors(function() Stub.setItemTooltip(tt, JERKY, JERKY_LINES) end)
    assert.are.equal(JERKY_LINES[2], fs("GameTooltip", 2):GetText())
    -- the modifier held: the client's English stays
    _G.issecretvalue = nil
    Stub.setSpellTooltip(tt, 17, SHIELD_LINES)
    _G.issecretvalue = function(v) return secret[v] == true end
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    Stub.setSpellTooltip(tt, 17, SHIELD_LINES)
    assert.are.equal(SHIELD_LINES[4], fs("GameTooltip", 4):GetText())
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    _G.issecretvalue = nil
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
