-- UI/TooltipData.lua: the tooltip-data kinds no other module translates (pipeline/tooltip_data_types.txt). The client
-- builds them in C from TooltipDataProcessor data and runs the post-calls registered per kind
-- (tooltipdatahandler.lua): a currency (camelot blizzard_tokenui.lua:170, 760), a mount or companion
-- (blizzard_mountcollection.lua:653, classic blizzard_petcollection.lua:423), an equipment set (camelot
-- paperdollframe.lua:2691), a raid lock (raidframe.lua:237), a totem (totemframe.lua:73), and party members' quest
-- progress (questobjectivetracker.lua:149), and a spell flyout (matched in its own families). Line 1 is the thing's
-- name and stays English; every later line goes
-- through the dictionary on UI/HelpTooltip's surface (HelpTooltip.adopt: released on OnHide, re-rendered on Alt).
-- [unverified in game: which lines each kind carries; a line matching no key stays as the client wrote it]
local _, WFJ = ...
local TooltipData = {}
WFJ.TooltipData = TooltipData

local Compat = WFJ.Compat
local OPTS = { from = 2 }
-- The kinds whose later lines are names too (a set's items, a lock's bosses, party members' names): only the
-- strings those tooltips show around them, never the whole dictionary, so no name meets a dictionary word.
-- [unverified in game: the lines each carries]
local function restricted(keys) return { from = 2, only = keys } end
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

-- A spellbook or action-bar flyout's tooltip: its name and description, both SpellFlyout rows (a category, not a
-- spell), matched in those two families only, line 1 included.
local function walkFlyout(tt)
  if type(tt) ~= "table" or tt ~= Compat.resolve("GameTooltip") then return 0 end
  return WFJ.HelpTooltip.adopt(tt, WFJ.Labels.families("FlyoutName", "FlyoutDescription"))
end
TooltipData.walkFlyout = walkFlyout

-- → true when the post-calls were registered
function TooltipData.init()
  local processor = Compat.resolve("TooltipDataProcessor")
  local enum = Compat.resolve("Enum")
  local types = type(enum) == "table" and enum.TooltipDataType or nil
  if type(processor) ~= "table" or type(processor.AddTooltipPostCall) ~= "function" or type(types) ~= "table" then
    return false
  end
  if types.Currency ~= nil then processor.AddTooltipPostCall(types.Currency, walk) end
  if types.Mount ~= nil then processor.AddTooltipPostCall(types.Mount, walk) end
  if types.CompanionPet ~= nil then processor.AddTooltipPostCall(types.CompanionPet, walk) end
  if types.EquipmentSet ~= nil then processor.AddTooltipPostCall(types.EquipmentSet, walkWith(SET_OPTS)) end
  if types.InstanceLock ~= nil then processor.AddTooltipPostCall(types.InstanceLock, walkWith(LOCK_OPTS)) end
  if types.Totem ~= nil then processor.AddTooltipPostCall(types.Totem, walk) end
  if types.QuestPartyProgress ~= nil then
    processor.AddTooltipPostCall(types.QuestPartyProgress, walkWith(partyOpts))
  end
  if types.Flyout ~= nil then processor.AddTooltipPostCall(types.Flyout, walkFlyout) end
  return true
end
