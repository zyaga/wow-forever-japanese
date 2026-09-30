-- UI/FlightMap.lua: the flight map on Forever (surface "flightmap", area "ui", ADR-016): the MapCanvas
-- flight-master window of the load-on-demand Blizzard_FlightMap (blizzard_flightmap.toc:4). Entry point:
-- TAXIMAP_OPENED → GameEvent.HandleTaxiMapOpened shows the classic TaxiFrame when the server names
-- Enum.UIMapSystem.Taxi and calls ShowFlightMapFrame() otherwise (blizzard_game/mainline/eventimplementation.lua:
-- 726–732), which loads the addon and shows FlightMapFrame (blizzard_flightmap_bootstrap.lua:3–11). Which of the two
-- a Forever flight master opens is the server's choice and an in-game check; UI/Taxi.lua serves the other one.
-- Set up through WFJ.LoadOnDemand.when (either load order).
-- - Title: FlightMapMixin:UpdateTitleAndPortraitIcon → self.BorderFrame:SetTitle(titleText)
--   (blizzard_flightmap.lua:16–19), FLIGHT_MAP from ResetTitleAndPortraitIcon (:12–14; OnLoad :26 → :5–10, and each
--   RemoveAllData, fm_flightpathdataprovider.lua:8–10). BorderFrame is a PortraitFrameTemplate
--   (blizzard_flightmap.xml:11): Labels.title on it, restricted to FLIGHT_MAP. The other title, FLIGHT_MAP_BASTION, is
--   written only for a Shadowlands texture kit (fm_flightpathdataprovider.lua:40–48) and is not a key.
-- - Node pins (FlightMap_FlightPointPinTemplate, fm_flightpathdataprovider.lua:178): OnMouseEnter builds GameTooltip
--   with the node's name (a place: English), then TAXINODEYOUAREHERE, a money line, or TAXI_PATH_UNREACHABLE
--   (:240–269). Pins are pooled and unnamed: the template's keys are handed to UI/MapPins, which registers each pin
--   as a help-tooltip owner the first time its tooltip shows.
-- - Zone summary: at minimum zoom FlightMap_ZoneSummaryDataProvider builds GameTooltip with FlightMapFrame itself
--   as the owner: the zone's name (English), FLIGHT_MAP_WORLD_QUESTS when there are any, FLIGHT_MAP_CLICK_TO_ZOOM_IN
--   (fm_zonesummarydataprovider.lua:42–60): FlightMapFrame is a help-tooltip owner restricted to those two keys.
-- - The click-to-zoom hints: ClickToZoomDataProviderMixin:OnAdded creates two label frames and writes each once,
--   MapLabel.Text (FLIGHT_MAP_CLICK_TO_ZOOM_HINT) and ZoomOutMapLabel.Text (FLIGHT_MAP_CLICK_TO_ZOOM_OUT_HINT)
--   (blizzard_sharedmapdataproviders/clicktozoomdataprovider.lua:36–57, 124–126; only the flight map adds that
--   provider, blizzard_flightmap.lua:55). The provider has no field on the map: it is the key of
--   FlightMapFrame.dataProviders (blizzard_mapcanvas.lua:192) that carries both labels. Static labels.
-- Release on the map's OnHide (the two static hints stay).
local _, WFJ = ...
local FlightMap = {}
WFJ.FlightMap = FlightMap

local SURFACE = "flightmap"
local STATIC = "flightmap.static"
FlightMap.SURFACE, FlightMap.STATIC = SURFACE, STATIC
local Compat = WFJ.Compat
local ADDON = "Blizzard_FlightMap"
local PIN_TEMPLATE = "FlightMap_FlightPointPinTemplate"

FlightMap.NEVER_TOUCH = {} -- node and zone names only ever appear as tooltip lines, which `only` keeps out

local CANDIDATES = {
  frame = { "FlightMapFrame" },
  border = { "FlightMapFrame.BorderFrame" },
  providers = { "FlightMapFrame.dataProviders" },
}

local TITLE = { only = { "FLIGHT_MAP" } }
local PIN_KEYS = { "TAXINODEYOUAREHERE", "TAXI_PATH_UNREACHABLE" }
local SUMMARY = { only = { "FLIGHT_MAP_CLICK_TO_ZOOM_IN", "FLIGHT_MAP_WORLD_QUESTS" } }
local ZOOM_IN = { only = { "FLIGHT_MAP_CLICK_TO_ZOOM_HINT" } }
local ZOOM_OUT = { only = { "FLIGHT_MAP_CLICK_TO_ZOOM_OUT_HINT" } }

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
end

-- The window title. → 1 | 0
function FlightMap.showTitle()
  return WFJ.Labels.title(SURFACE, get("border"), TITLE)
end

-- The click-to-zoom provider's two hint labels. → the number of dictionary words found
function FlightMap.showHints()
  local providers = get("providers")
  if type(providers) ~= "table" then return 0 end
  local n = 0
  for provider in pairs(providers) do
    local zoomIn = type(provider) == "table" and provider.MapLabel or nil
    local zoomOut = type(provider) == "table" and provider.ZoomOutMapLabel or nil
    if type(zoomIn) == "table" and type(zoomOut) == "table" then
      n = n + WFJ.Labels.show(STATIC, "zoomIn", zoomIn.Text, nil, ZOOM_IN)
        + WFJ.Labels.show(STATIC, "zoomOut", zoomOut.Text, nil, ZOOM_OUT)
    end
  end
  return n
end

-- HookScript("OnShow") target on FlightMapFrame. → the number of dictionary words found
function FlightMap.onShow()
  local n = FlightMap.showTitle() + FlightMap.showHints()
  WFJ.Render.updateBanner(SURFACE)
  return n
end

function FlightMap.onHide()
  return WFJ.Render.release(SURFACE)
end

local hooked = false

-- Blizzard_FlightMap's part: runs once the addon is loaded (now, or on its ADDON_LOADED). → true when set up.
function FlightMap.setup()
  declare() -- its frames exist only now: forget what Compat memoized before
  local frame = get("frame")
  if hooked or type(frame) ~= "table" then return false end
  hooked = true
  WFJ.MapPins.add(PIN_TEMPLATE, PIN_KEYS)
  WFJ.HelpTooltip.register(frame, SUMMARY)
  if type(frame.HookScript) == "function" then
    frame:HookScript("OnShow", FlightMap.onShow)
    frame:HookScript("OnHide", FlightMap.onHide)
  end
  FlightMap.onShow()
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, LoadOnDemand.init and MapPins.init.
function FlightMap.init()
  declare()
  return WFJ.LoadOnDemand.when(ADDON, FlightMap.setup)
end
