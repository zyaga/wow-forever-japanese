-- UI/TooltipData.lua: the tooltip-data kinds no other module translates (pipeline/tooltip_data_types.txt). The client
-- builds them in C from TooltipDataProcessor data and runs the post-calls registered per kind
-- (tooltipdatahandler.lua): a currency (camelot blizzard_tokenui.lua:170, 760), a mount or companion
-- (blizzard_mountcollection.lua:653, classic blizzard_petcollection.lua:423), an equipment set (camelot
-- paperdollframe.lua:2728), a raid lock (raidframe.lua:237), a totem (totemframe.lua:73), and party members' quest
-- progress (questobjectivetracker.lua:149), and a spell flyout (matched in its own families). Line 1 is the thing's
-- name: its Japanese while names are on (the `names` option), as is a later line that is a game name (a lock's
-- bosses); every later line goes through the dictionary on UI/HelpTooltip's surface (HelpTooltip.adopt: released
-- on OnHide, re-rendered on Alt). A currency's description is a restricted family (ADR-042), named here so a
-- currency shown anywhere (a quest reward, a vendor's price) gets it, not only the currency window's own rows.
-- [unverified in game: which lines each kind carries; a line matching no key stays as the client wrote it]
local _, WFJ = ...
local TooltipData = {}
WFJ.TooltipData = TooltipData

local Compat = WFJ.Compat
local OPTS = { from = 2, names = "ui" }
-- The kinds whose later lines are names too (a set's items, a lock's bosses, party members' names): only the
-- strings those tooltips show around them, never the whole dictionary, so no name meets a dictionary word.
-- [unverified in game: the lines each carries]
local function restricted(keys) return { from = 2, only = keys, names = "ui" } end
local LOCK_OPTS = restricted({ "BOSS_ALIVE", "BOSS_DEAD", "LOCKED" })
local SET_OPTS = restricted({ "EQUIPMENT_MANAGER_IGNORE_SLOT", "EQUIPMENT_MANAGER_PLACE_IN_BAGS" })
local function partyOpts()
  local QM = WFJ.QuestMap
  return restricted(type(QM) == "table" and QM.OBJECTIVE_KEYS or {})
end

local function walkWith(opts)
  return function(tt)
    if type(tt) ~= "table" or tt ~= Compat.resolve("GameTooltip") then return 0 end
    return WFJ.HelpTooltip.adopt(tt, type(opts) == "function" and opts() or opts)
  end
end
local walk = walkWith(OPTS)
TooltipData.walk = walk
local function currencyOpts()
  return { from = 2, names = "ui", also = WFJ.Labels.families("CurrencyDescription").only }
end

-- A spellbook or action-bar flyout's tooltip: its name and description, both SpellFlyout rows (a category, not a
-- spell), matched in those two families only, line 1 included.
local function walkFlyout(tt)
  if type(tt) ~= "table" or tt ~= Compat.resolve("GameTooltip") then return 0 end
  return WFJ.HelpTooltip.adopt(tt, WFJ.Labels.families("FlyoutName", "FlyoutDescription"))
end
TooltipData.walkFlyout = walkFlyout

-- A mount's or a companion's tooltip whose spell UI/Tooltip found is that module's, lines and description both:
-- the interface lines are walked here only when it found none.
local function walkUnlessSpell(tt, data)
  local T = WFJ.Tooltip
  if type(T) == "table" and type(T.spellOf) == "function" and tt == Compat.resolve("GameTooltip")
      and T.spellOf(tt, data) ~= nil then
    return 0
  end
  return walk(tt)
end

local function timed(label, fn) return WFJ.Perf.wrap(label, fn) end -- a post-call timed under `label` (Core/Perf)

-- → true when the post-calls were registered
function TooltipData.init()
  local processor = Compat.resolve("TooltipDataProcessor")
  local enum = Compat.resolve("Enum")
  local types = type(enum) == "table" and enum.TooltipDataType or nil
  if type(processor) ~= "table" or type(processor.AddTooltipPostCall) ~= "function" or type(types) ~= "table" then
    return false
  end
  if types.Currency ~= nil then
    processor.AddTooltipPostCall(types.Currency, timed("tooltip.currency", walkWith(currencyOpts)))
  end
  if types.Mount ~= nil then
    processor.AddTooltipPostCall(types.Mount, timed("tooltip.mount", walkUnlessSpell))
  end
  if types.CompanionPet ~= nil then
    processor.AddTooltipPostCall(types.CompanionPet, timed("tooltip.pet", walkUnlessSpell))
  end
  if types.EquipmentSet ~= nil then
    processor.AddTooltipPostCall(types.EquipmentSet, timed("tooltip.set", walkWith(SET_OPTS)))
  end
  if types.InstanceLock ~= nil then
    processor.AddTooltipPostCall(types.InstanceLock, timed("tooltip.lock", walkWith(LOCK_OPTS)))
  end
  if types.Totem ~= nil then processor.AddTooltipPostCall(types.Totem, timed("tooltip.totem", walk)) end
  if types.QuestPartyProgress ~= nil then
    processor.AddTooltipPostCall(types.QuestPartyProgress, timed("tooltip.party", walkWith(partyOpts)))
  end
  if types.Flyout ~= nil then processor.AddTooltipPostCall(types.Flyout, timed("tooltip.flyout", walkFlyout)) end
  return true
end
