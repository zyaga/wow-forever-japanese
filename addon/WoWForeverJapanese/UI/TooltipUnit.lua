-- UI/TooltipUnit.lua: the lines the client composes on a unit's mouseover tooltip on Forever: the
-- level / creature-type line ("Level 1 Humanoid", "Level 12 Elite Beast"), the corpse line and the skinning / herb /
-- ore lines. The client builds the unit tooltip from C_TooltipInfo and then runs the TooltipDataProcessor post-calls
-- for Enum.TooltipDataType.Unit (the same system UI/Tooltip uses for items, spells and auras); the lines are
-- GlobalStrings it fills (TOOLTIP_UNIT_LEVEL*, UNIT_*LEVEL_TEMPLATE, UNIT_SKINNABLE_*, CORPSE_TOOLTIP) [unverified:
-- which of them this build's C code sends].
-- This surface keeps its OWN records, rather than borrowing UI/HelpTooltip's walk:
-- TooltipDataHandlerMixin:InternalProcessInfo runs the post-calls and then calls `self:Show()` on the next line
-- [verified: blizzard_sharedxmlgame/tooltip/tooltipdatahandler.lua:298–300], and HelpTooltip's own Show hook treats a
-- tooltip whose owner it does not have registered as foreign, forgetting every record on its surface, which put the
-- client's English straight back over these lines. Records here are keyed by line, re-rendered on a modifier change
-- like every surface's, and released on the tooltip's OnHide so a later item or spell tooltip never inherits them.
-- Only lines 2 and below are read, and only against the keys below: line 1 is the unit's name, and a guild line
-- ("<Guild>"), a title or any server line matches none of them, so it stays as the client wrote it (names stay
-- in English). A race, class or pet family inside a level line is kept as shown; a creature type ("Humanoid") takes
-- its CreatureType row. A player's tooltip never takes the creature-type templates: "Level 60 Undead" is the same
-- text for an Undead player (race, stays English) and an undead creature, and only the unit tells them apart
-- (C_PlayerInfo.GUIDIsPlayer on the tooltip data's guid, as blizzard_objectapi/mainline/playerlocation.lua:59 does).
-- A client with no tooltip data processor is left untouched (init returns false).
local _, WFJ = ...
local TooltipUnit = {}
WFJ.TooltipUnit = TooltipUnit

local SURFACE = "tooltip.unit"
TooltipUnit.SURFACE = SURFACE
local Compat = WFJ.Compat

TooltipUnit.KEYS = { "TOOLTIP_UNIT_LEVEL", "TOOLTIP_UNIT_LEVEL_TYPE", "TOOLTIP_UNIT_LEVEL_RACE",
  "TOOLTIP_UNIT_LEVEL_RACE_TYPE", "UNIT_LEVEL_TEMPLATE", "UNIT_TYPE_LEVEL_TEMPLATE", "UNIT_PLUS_LEVEL_TEMPLATE",
  "UNIT_TYPE_PLUS_LEVEL_TEMPLATE", "UNIT_LEVEL_DEAD_TEMPLATE", "UNIT_SKINNABLE_LEATHER", "UNIT_SKINNABLE_HERB",
  "UNIT_SKINNABLE_ROCK", "UNIT_SKINNABLE_BOLTS", "CORPSE_TOOLTIP" }
local ONLY = { only = TooltipUnit.KEYS }
local CREATURE_TEMPLATES = { UNIT_TYPE_LEVEL_TEMPLATE = true, UNIT_TYPE_PLUS_LEVEL_TEMPLATE = true }
local PLAYER_KEYS = {}
for _, k in ipairs(TooltipUnit.KEYS) do
  if not CREATURE_TEMPLATES[k] then PLAYER_KEYS[#PLAYER_KEYS + 1] = k end
end
local ONLY_PLAYER = { only = PLAYER_KEYS }

-- Is the tooltip's unit a player? A missing or secret guid, or no C_PlayerInfo, counts as not a player. → boolean
local function isPlayer(data)
  local guid = type(data) == "table" and data.guid or nil
  if type(guid) ~= "string" then return false end
  local isSecret = Compat.resolve("issecretvalue")
  if type(isSecret) == "function" and isSecret(guid) then return false end
  local info = Compat.resolve("C_PlayerInfo")
  if type(info) ~= "table" or type(info.GUIDIsPlayer) ~= "function" then return false end
  return info.GUIDIsPlayer(guid) == true
end
TooltipUnit.isPlayer = isPlayer
local MAX_LINES = 30 -- a unit tooltip is a handful of lines; the walk stops at the client's own count anyway

local refitting = false

-- One Show() after a pass that changed a line, so the frame fits the Japanese; our own re-entry is ignored.
local function refitFor(tt)
  return function()
    if refitting then return end
    refitting = true
    tt:Show()
    refitting = false
  end
end

-- The Unit post-call (tooltip, tooltip data): GameTooltip only (its OnHide releases these records).
-- → the number of lines shown
function TooltipUnit.onUnit(tt, data)
  if tt == nil or tt ~= Compat.get(SURFACE, "GameTooltip") or type(tt.NumLines) ~= "function" then return 0 end
  local name = tt:GetName()
  if type(name) ~= "string" then return 0 end
  local lines = math.min(tt:NumLines() or 0, MAX_LINES)
  local refit, n, only = refitFor(tt), 0, isPlayer(data) and ONLY_PLAYER or ONLY
  for i = 2, lines do -- line 1 is the unit's name: never read, never written
    local fs = Compat.resolve(name .. "TextLeft" .. i)
    if type(fs) == "table" then n = n + WFJ.Labels.show(SURFACE, "L" .. i, fs, refit, only) end
  end
  for i = lines + 1, MAX_LINES do WFJ.SurfaceState.drop(SURFACE, "L" .. i) end
  return n
end

-- HookScript target (GameTooltip OnHide): the frame's lines are gone. → records released
function TooltipUnit.release()
  return WFJ.Render.release(SURFACE)
end

local hooked = false

-- Called by Main after Tooltip.init. → true when the Unit post-call was registered
function TooltipUnit.init()
  Compat.declare(SURFACE, "GameTooltip", { "GameTooltip" })
  if hooked then return true end
  local processor, types = WFJ.Tooltip.modern()
  if not processor or types.Unit == nil then return false end
  local tt = Compat.get(SURFACE, "GameTooltip")
  if type(tt) ~= "table" or type(tt.HookScript) ~= "function" then return false end
  processor.AddTooltipPostCall(types.Unit, TooltipUnit.onUnit)
  tt:HookScript("OnHide", TooltipUnit.release)
  hooked = true
  return true
end
