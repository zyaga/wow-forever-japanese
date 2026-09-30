-- UI/MapPins.lua: the fixed words in a map pin's tooltip on Forever (inventory surface "mappins", records on
-- UI/HelpTooltip's surface "help", area "ui", ADR-016). The world map, the flight map and the zone map are
-- MapCanvas frames: every icon on them is a pooled pin (blizzard_mapcanvas/blizzard_mapcanvas.lua:280–286, one
-- CreateFramePool per pin template), and a pin builds its tooltip in its own OnMouseEnter on GameTooltip with itself
-- as the owner. A pin has no global name and does not exist before its map first shows it, so it cannot be
-- registered with UI/HelpTooltip at init. Instead GameTooltip:Show is post-hooked here (after HelpTooltip's own
-- hook, which found the owner unregistered and walked nothing): when the owner carries `pinTemplate` (the string
-- MapCanvasMixin:AcquirePin writes on every pin, blizzard_mapcanvas.lua:288) and that template is listed below,
-- the pin is registered as a help-tooltip owner restricted to that template's keys, and the tooltip is walked once.
-- From then on HelpTooltip's SetText / Show hooks follow that pin like any other owner. A pool is per template, so
-- a pin never changes template and its registration stays right for as long as the frame lives.
-- Every pin tooltip's first line can be a name (a flight point, a graveyard, a dungeon, a rare), so every entry is
-- an `only` list: a name never matches, even one that is also a dictionary word.
-- Writers (all blizzard_sharedmapdataproviders/, all end in GameTooltip:Show()):
--   FlightPointPinTemplate          BaseMapPoiPinMixin:CheckShowTooltip (sharedmappoitemplates.lua:139–157) with the
--                                   description flightpointdataprovider.lua:20–27 gives an undiscovered node
--   CorpsePinTemplate               CorpsePinMixin:OnMouseEnter, GameTooltip:SetText(CORPSE_RED)
--                                   (deathmapdataprovider.lua:39–49). DeathReleasePinTemplate shows "Spirit Healer",
--                                   a creature's name: not listed
--   SelectableGraveyardPinTemplate  selectablegraveyarddataprovider.lua:57–73
--   WaypointLocationPinTemplate     waypointlocationdataprovider.lua:165–175 (template name :3–5)
--   QuestPinTemplate                the gamepad-mode lines only (questdataprovider.lua:273–276; template name :3–4)
--   DungeonEntrancePinTemplate      the fallback name and the instruction line (dungeonentrancedataprovider.lua:
--                                   68–74) through CheckShowTooltip
--   MapLinkPinTemplate              maplinkdataprovider.lua:33–35 through CheckShowTooltip
--   QuestHubPinTemplate             the section headers and "+%d more" (questofferdataprovider.lua:570–608)
--   VignettePinTemplate / VignettePinPOIButtonTemplate   "Suggested Players [%d]" (vignettedataprovider.lua:322–331,
--                                   493–511; template names :3–23). The objective line carries a creature's name and
--                                   is an objective line: not listed
-- Another module adds its own map's templates with MapPins.add (UI/FlightMap: the flight map's node pins).
local _, WFJ = ...
local MapPins = {}
WFJ.MapPins = MapPins

local SURFACE = "mappins"
MapPins.SURFACE = SURFACE
local Compat = WFJ.Compat

MapPins.NEVER_TOUCH = {} -- a pin has no name widget of its own; its tooltip lines are restricted by `only`

-- A vignette's objective line, "- Defeat <name>" / "… (Current Health: <n%>)"
-- (VignettePinBaseMixin:GetObjectiveString, vignettedataprovider.lua:333–346): the creature's name kept as written
local VIGNETTE_KEYS = { "VIGNETTE_SUGGESTED_GROUP_NUM", "VIGNETTE_SUGGESTED_GROUP_NUM_RANGE",
  "TOOLTIP_VIGNETTE_OBJECTIVE_DEFEAT", "TOOLTIP_VIGNETTE_OBJECTIVE_DEFEAT_SHOW_HEALTH" }
local PIN_KEYS = {
  FlightPointPinTemplate = { "UNDISCOVERED_FACTION_FLIGHTPOINT", "UNDISCOVERED_NEUTRAL_FLIGHTPOINT" },
  CorpsePinTemplate = { "CORPSE_RED" },
  SelectableGraveyardPinTemplate = { "GRAVEYARD_SELECTED", "GRAVEYARD_SELECTED_TOOLTIP", "GRAVEYARD_ELIGIBLE",
    "GRAVEYARD_ELIGIBLE_TOOLTIP" },
  -- gamepad lines (waypointlocationdataprovider.lua:173–175); the focus line is
  -- "<input icon>Toggle Focus on Marker" (GameTooltip_AddLineWithInputIcon, UIStrings `icon` form)
  WaypointLocationPinTemplate = { "MAP_PIN_SHARING", "MAP_PIN_SHARING_TOOLTIP", "MAP_PIN_REMOVE",
    "MAP_PIN_SHARING_TOOLTIP_GAMEPAD", "MAP_PIN_TOGGLE_FOCUS", "SHARE_IN_CHAT" },
  DungeonEntrancePinTemplate = { "DUNGEON_MAP_PIN_FALLBACK_NAME", "DUNGEON_POI_TOOLTIP_INSTRUCTION_LINE" },
  MapLinkPinTemplate = { "MAP_LINK_POI_TOOLTIP_INSTRUCTION_LINE" },
  QuestHubPinTemplate = { "QUEST_HUB_TOOLTIP_AVAILABLE_CONTENT_HEADER", "QUEST_HUB_TOOLTIP_AVAILABLE_QUESTS_HEADER",
    "QUEST_HUB_TOOLTIP_TRAVEL_HEADER", "QUEST_HUB_TOOLTIP_MORE_QUESTS_REMAINING",
    "MAP_LINK_POI_TOOLTIP_INSTRUCTION_LINE" },
  -- a quest's pin, gamepad mode only: "<input icon>Toggle Focus on Quest" / "… Quest Details"
  -- (QuestPinMixin:OnMouseEnter, questdataprovider.lua:273–276); line 1 is the quest's title, never listed
  QuestPinTemplate = { "MAP_PIN_TOGGLE_QUEST_FOCUS", "MAP_PIN_TOGGLE_QUEST_DETAILS" },
  VignettePinTemplate = VIGNETTE_KEYS,
  VignettePinPOIButtonTemplate = VIGNETTE_KEYS,
}

-- Lists the keys a pin template's tooltip may show (a map module's own pins). A template already listed is kept.
function MapPins.add(template, keys)
  if type(template) ~= "string" or type(keys) ~= "table" or PIN_KEYS[template] then return false end
  PIN_KEYS[template] = keys
  return true
end

-- → the key list of a pin template, or nil
function MapPins.keys(template)
  return PIN_KEYS[template]
end

-- hooksecurefunc target (GameTooltip:Show). → the number of dictionary lines (0 when the owner is not a listed pin,
-- or is registered already (HelpTooltip's own Show hook walked it just before this one).
function MapPins.onShow(tt)
  if type(tt) ~= "table" or type(tt.GetOwner) ~= "function" then return 0 end
  local owner = tt:GetOwner()
  if type(owner) ~= "table" or WFJ.HelpTooltip.registered(owner) then return 0 end
  local template = owner.pinTemplate
  local keys = type(template) == "string" and PIN_KEYS[template] or nil
  if not keys then return 0 end
  WFJ.HelpTooltip.register(owner, { only = keys })
  return WFJ.HelpTooltip.walk(tt)
end

local hooked = false

-- Called by Main after Compat.init and HelpTooltip.init (its Show hook must be installed first).
function MapPins.init()
  Compat.declare(SURFACE, "tooltip", { "GameTooltip" })
  if hooked then return false end
  local tt = Compat.get(SURFACE, "tooltip")
  if type(tt) ~= "table" or type(tt.Show) ~= "function" or type(tt.GetOwner) ~= "function" then return false end
  hooked = true
  hooksecurefunc(tt, "Show", MapPins.onShow)
  return true
end
