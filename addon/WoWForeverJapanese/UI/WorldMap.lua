-- UI/WorldMap.lua: the world map's own chrome on Forever (surface "worldmap", area "ui", ADR-016): the
-- words Blizzard_WorldMap (a login addon, blizzard_worldmap.toc) puts around the map canvas. The window title
-- (MAP_AND_QUEST_LOG / WORLD_MAP, blizzard_worldmap.lua:27, 36, 41) and the quest log side panel belong to
-- UI/QuestMap.lua, and pin tooltips to UI/MapPins.lua; zone, continent and floor names are names and stay English.
-- Every widget is a parentKey or a field WorldMapMixin:AddOverlayFrames writes (blizzard_worldmap.lua:318–356):
-- - NavBar.home: the navigation bar's first button. WorldMapNavBarMixin:OnLoad passes name = WORLD ("World") and
--   NavBar_Initialize writes it once with homeButton:SetText (blizzard_worldmaptemplates.lua:472–485;
--   blizzard_framexml/mainline/navigationbar.lua:5–18; the button is parentKey "home", navigationbar.xml:301). Every
--   other nav button is a map's name (NavBar_AddButton, navigationbar.lua:114) and is never looked at. A static
--   label restricted to WORLD, shown at init and on every OnShow of the map.
-- - WorldMapTrackingOptionsButton: its OnEnter builds GameTooltip with GameTooltip_SetTitle(MAP_FILTER)
--   (blizzard_worldmaptemplates.lua:357–361; camelot keeps that OnEnter, camelot/blizzard_worldmaptemplates.xml:42):
--   a help-tooltip owner restricted to MAP_FILTER. Its menu (the "Show:" title, the filter check boxes and their
--   description tooltips, :228–323) is a menu popup, the menu system's.
-- - WorldMapTrackingPinButton: OnEnter builds MAP_PIN, then MAP_PIN_TOOLTIP + MAP_PIN_TOOLTIP_INSTRUCTIONS, or
--   MAP_PIN_INVALID_MAP on a map that takes no pin (:435–447): a help-tooltip owner restricted to those four. The
--   button is not created when the game rule WorldMapTrackingPinDisabled is on (blizzard_worldmap.lua:331–335).
-- - The coordinates panel and the zone timer are overlay frames with no field on the map: they are found in
--   WorldMapFrame.overlayFrames (AddOverlayFrame, blizzard_worldmap.lua:452–463) by their own parentKeys
--   (PlayerCoords + CursorCoords; TimeLabel: blizzard_worldmaptemplates.xml:113–141, 209–222), never by position.
--   Both rewrite their text from an OnUpdate script (SetFormattedText every frame: WORLD_MAP_PLAYER_COORDS[_INTEGER],
--   WORLD_MAP_PLAYER_COORDS_MAP_NAME[_INTEGER] (whose %s is a map's name, kept as written),
--   WORLD_MAP_CURSOR_COORDS[_INTEGER], blizzard_worldmaptemplates.lua:553–610; NEXT_BATTLE :665–676), so each gets a
--   HookScript("OnUpdate") that runs after the client's and shows only a label whose holder is shown. The
--   coordinates are off unless the player turns them on (CVars worldMapShowPlayerCoords / worldMapShowCursorCoords,
--   :617–621), and the timer shows only on an outdoor-PvP map (C_PvP.GetOutdoorPvPWaitTime, :666).
-- Not here: the gamepad footer prompts (FRAME_ACTION_*, blizzard_worldmap.lua:1012–1098), the help plate
-- (WORLD_MAP_TUTORIAL1 / 4, :1292–1293; never shown: camelot hides its MainHelpPlateButton,
-- helpplateoverrides.lua:1–3), the completed-quests HelpTip (UI/HelpTips), the N'Zoth threat eye (a name),
-- and the filter counter, which camelot's template does not have (camelot/blizzard_worldmaptemplates.xml:4–46;
-- RefreshFilterCounter is a no-op, camelot/blizzard_worldmaptemplates.lua:5–7).
-- Release on the map's OnHide (the static home label stays: it is written once).
local _, WFJ = ...
local WorldMap = {}
WFJ.WorldMap = WorldMap

local SURFACE = "worldmap"
local STATIC = "worldmap.static"
WorldMap.SURFACE, WorldMap.STATIC = SURFACE, STATIC
local Compat = WFJ.Compat

-- The floor dropdown's and the nav buttons' text are map names; they are unnamed (overlay frames, pooled nav
-- buttons), so they are kept out by never being looked at, and the home button by its `only` list.
WorldMap.NEVER_TOUCH = {}

local CANDIDATES = {
  frame = { "WorldMapFrame" },
  home = { "WorldMapFrame.NavBar.home" },
  filterButton = { "WorldMapFrame.WorldMapTrackingOptionsButton" },
  pinButton = { "WorldMapFrame.WorldMapTrackingPinButton" },
  overlays = { "WorldMapFrame.overlayFrames" },
}

local HOME = { only = { "WORLD" } }
local FILTER_TOOLTIP = { only = { "MAP_FILTER" } }
local PIN_TOOLTIP = { only = { "MAP_PIN", "MAP_PIN_TOOLTIP", "MAP_PIN_TOOLTIP_INSTRUCTIONS", "MAP_PIN_INVALID_MAP" } }
local PLAYER = { only = { "WORLD_MAP_PLAYER_COORDS", "WORLD_MAP_PLAYER_COORDS_INTEGER",
  "WORLD_MAP_PLAYER_COORDS_MAP_NAME", "WORLD_MAP_PLAYER_COORDS_MAP_NAME_INTEGER" } }
-- In gamepad mode the same label reads "Crosshair: …" (blizzard_worldmaptemplates.lua:604–606)
local CURSOR = { only = { "WORLD_MAP_CURSOR_COORDS", "WORLD_MAP_CURSOR_COORDS_INTEGER", "WORLD_MAP_CROSSHAIR_COORDS",
  "WORLD_MAP_CROSSHAIR_COORDS_INTEGER" } }
local TIMER = { only = { "NEXT_BATTLE" } }

local function get(key) return Compat.get(SURFACE, key) end

local function shown(widget)
  return type(widget) == "table" and type(widget.IsShown) == "function" and widget:IsShown() and true or false
end

-- The navigation bar's home button ("World"). → 1 | 0
function WorldMap.showHome()
  return WFJ.Labels.show(STATIC, "home", get("home"), nil, HOME)
end

-- HookScript("OnUpdate") target on the coordinates panel: the two labels, each only while its holder is shown (a
-- hidden holder keeps a stale text the client no longer writes). → the number of dictionary words found
function WorldMap.onCoords(panel)
  if type(panel) ~= "table" then return 0 end
  local n = 0
  for _, item in ipairs({ { "player", panel.PlayerCoords, PLAYER }, { "cursor", panel.CursorCoords, CURSOR } }) do
    local holder = item[2]
    if shown(holder) and type(holder.Label) == "table" then
      n = n + WFJ.Labels.show(SURFACE, item[1], holder.Label, nil, item[3])
    end
  end
  return n
end

-- HookScript("OnUpdate") target on the zone timer ("Next Battle: 00:12:30"). → 1 | 0
function WorldMap.onTimer(timer)
  local label = type(timer) == "table" and timer.TimeLabel or nil
  if not shown(label) then return 0 end
  return WFJ.Labels.show(SURFACE, "timer", label, nil, TIMER)
end

local updateHooked = setmetatable({}, { __mode = "k" })

-- Finds the coordinates panel and the zone timer among the map's overlay frames by their parentKeys and hooks each
-- OnUpdate once. → the number of frames hooked by this call
local function hookOverlays()
  local overlays = get("overlays")
  if type(overlays) ~= "table" then return 0 end
  local n = 0
  for _, overlay in pairs(overlays) do
    if type(overlay) == "table" and not updateHooked[overlay] and type(overlay.HookScript) == "function" then
      local fn
      if type(overlay.PlayerCoords) == "table" and type(overlay.CursorCoords) == "table" then
        fn = WorldMap.onCoords
      elseif type(overlay.TimeLabel) == "table" then
        fn = WorldMap.onTimer
      end
      if fn then
        updateHooked[overlay] = true
        overlay:HookScript("OnUpdate", function(self) fn(self) end)
        n = n + 1
      end
    end
  end
  return n
end

-- HookScript("OnShow") target on WorldMapFrame. → the number of dictionary words found
function WorldMap.onShow()
  hookOverlays() -- a frame the first init did not find yet
  local n = WorldMap.showHome()
  WFJ.Render.updateBanner(SURFACE)
  return n
end

function WorldMap.onHide()
  return WFJ.Render.release(SURFACE)
end

local hooked = false

-- Called by Main after Compat.init and HelpTooltip.init.
function WorldMap.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  local frame = get("frame")
  if hooked or type(frame) ~= "table" then return false end
  hooked = true
  local filterButton, pinButton = get("filterButton"), get("pinButton")
  if type(filterButton) == "table" then WFJ.HelpTooltip.register(filterButton, FILTER_TOOLTIP) end
  if type(pinButton) == "table" then WFJ.HelpTooltip.register(pinButton, PIN_TOOLTIP) end
  if type(frame.HookScript) == "function" then
    frame:HookScript("OnShow", WorldMap.onShow)
    frame:HookScript("OnHide", WorldMap.onHide)
  end
  hookOverlays()
  WorldMap.showHome()
  return true
end
