-- UI/Taxi.lua: the flight master's route map on Forever (surface "taxi", area "ui", ADR-016 / ADR-029).
-- camelot loads blizzard_uipanels_game/shared/taxiframe.lua|xml. The server's TAXIMAP_OPENED picks the window:
-- GameEvent.HandleTaxiMapOpened shows TaxiFrame for Enum.UIMapSystem.Taxi and the load-on-demand FlightMapFrame
-- otherwise (blizzard_game/mainline/eventimplementation.lua:725–731); which one Forever's flight masters send is an
-- in-game check; UI/FlightMap.lua covers the other.
-- - Title: TaxiFrame_OnShow writes self.TitleText = FLIGHT_MAP (taxiframe.lua:44–47; TitleText is the
--   BaseBasicFrameTemplate's parentKey, blizzard_uipaneltemplates/mainline/uipaneltemplates.xml:577). It is written
--   with SetText on every show, not SetTitle, so it is shown from an OnShow post-hook (which runs after the client's).
-- - Tooltip: TaxiNodeOnButtonEnter(button) builds GameTooltip with the node's name on line 1, the fare, and for the
--   node the player stands on TAXINODEYOUAREHERE (taxiframe.lua:135–138, 203–208). The node buttons TaxiButton<i> are
--   created as the map needs them, so none is registered: the writer is a global called by name from the button
--   template's OnEnter (taxiframe.xml:9–11), post-hooked, and the tooltip is walked once restricted to that key.
-- Never touched: line 1 of that tooltip is a place name; the `only` restriction leaves it (and every other line)
-- alone. Release on TaxiFrame's OnHide.
local _, WFJ = ...
local Taxi = {}
WFJ.Taxi = Taxi

local SURFACE = "taxi"
Taxi.SURFACE = SURFACE
local Compat = WFJ.Compat

Taxi.NEVER_TOUCH = {}

local TITLE = { only = { "FLIGHT_MAP" } }
local HERE = { only = { "TAXINODEYOUAREHERE" } }

local function get(key) return Compat.get(SURFACE, key) end

function Taxi.onShow()
  local frame = get("frame")
  local n = WFJ.Labels.show(SURFACE, "title", type(frame) == "table" and frame.TitleText or nil, nil, TITLE)
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- hooksecurefunc target (TaxiNodeOnButtonEnter). → the number of dictionary lines
function Taxi.onNodeEnter()
  local tt = get("tooltip")
  if type(tt) ~= "table" then return 0 end
  return WFJ.HelpTooltip.walkAs(tt, HERE)
end

function Taxi.release()
  return WFJ.Render.release(SURFACE)
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function Taxi.init()
  Compat.declare(SURFACE, "frame", { "TaxiFrame" })
  Compat.declare(SURFACE, "tooltip", { "GameTooltip" })
  Compat.declare(SURFACE, "nodeEnter", { "TaxiNodeOnButtonEnter" })
  local frame = get("frame")
  if hooked or type(frame) ~= "table" or type(frame.HookScript) ~= "function" then return false end
  hooked = true
  frame:HookScript("OnShow", Taxi.onShow)
  frame:HookScript("OnHide", Taxi.release)
  if type(get("nodeEnter")) == "function" then hooksecurefunc("TaxiNodeOnButtonEnter", Taxi.onNodeEnter) end
  return true
end
