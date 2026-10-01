-- Camelot-shaped map frames for the map specs (UI/WorldMap, UI/MapPins, UI/FlightMap, UI/BattlefieldMap),
-- replayed from the Forever client's blizzard_worldmap, blizzard_mapcanvas, blizzard_sharedmapdataproviders,
-- blizzard_flightmap and blizzard_battlefieldmap. Client writes go to `fs.text`.
local Stub = require("tests.lua.spec.wow_stub")
local M = {}

-- A pooled map pin as MapCanvasMixin:AcquirePin leaves it (blizzard_mapcanvas.lua:280–288).
function M.pin(template)
  local pin = CreateFrame("Frame")
  pin.pinTemplate = template
  return pin
end

-- A tooltip the way a pin's OnMouseEnter builds it: SetOwner, SetText / AddLine …, Show.
function M.tooltip(owner, lines)
  local tt = _G.GameTooltip
  tt:SetOwner(owner, "ANCHOR_RIGHT")
  tt:SetText(lines[1])
  for i = 2, #lines do tt:AddLine(lines[i]) end
  tt:Show()
  return tt
end

function M.line(i) return _G["GameTooltipTextLeft" .. i]:GetText() end

-- WorldMapFrame with the overlay frames WorldMapMixin:AddOverlayFrames creates (blizzard_worldmap.lua:318–356).
function M.worldMap(en)
  local frame = CreateFrame("Frame", "WorldMapFrame")
  frame.overlayFrames = {}
  local function overlay(f)
    frame.overlayFrames[#frame.overlayFrames + 1] = f
    return f
  end
  local floor = overlay(Stub.button(nil, "Ironforge")) -- the floor dropdown: a map's name
  frame.floorDropdown = floor
  frame.WorldMapTrackingOptionsButton = overlay(CreateFrame("DropdownButton"))
  frame.WorldMapTrackingPinButton = overlay(CreateFrame("Button"))
  local nav = overlay(CreateFrame("Frame"))
  frame.NavBar = nav
  nav.home = Stub.button(nil, en("WORLD")) -- NavBar_Initialize: homeButton:SetText(homeData.name)
  nav.zone = Stub.button(nil, "World") -- a nav button: a map's name (here one that is also a dictionary word)
  local coords = overlay(CreateFrame("Frame"))
  frame.coords = coords
  for _, key in ipairs({ "PlayerCoords", "CursorCoords", "CrosshairCoords" }) do
    coords[key] = CreateFrame("Frame")
    coords[key].Label = Stub.fontString("")
  end
  -- WorldMapCoordsPanelMixin:OnUpdate (blizzard_worldmaptemplates.lua:572–610)
  coords:SetScript("OnUpdate", function(self)
    local s = M.state
    self.PlayerCoords.shown = s.player ~= nil
    if s.player then
      if s.player.map then
        self.PlayerCoords.Label.text = ("Player: %.1f, %.1f (%s)"):format(s.player[1], s.player[2], s.player.map)
      else
        self.PlayerCoords.Label.text = en(s.tenths and "WORLD_MAP_PLAYER_COORDS" or "WORLD_MAP_PLAYER_COORDS_INTEGER")
          :format(s.player[1], s.player[2])
      end
    end
    -- the mouse writes CursorCoords, the gamepad its own CrosshairCoords (blizzard_worldmaptemplates.lua:601–619)
    local holder = s.crosshair and self.CrosshairCoords or self.CursorCoords
    self.CursorCoords.shown = s.cursor ~= nil and not s.crosshair
    self.CrosshairCoords.shown = s.cursor ~= nil and s.crosshair == true
    if s.cursor then
      local base = s.crosshair and "WORLD_MAP_CROSSHAIR_COORDS" or "WORLD_MAP_CURSOR_COORDS"
      holder.Label.text = en(s.tenths and base or base .. "_INTEGER"):format(s.cursor[1], s.cursor[2])
    end
  end)
  local timer = overlay(CreateFrame("Frame"))
  frame.timer = timer
  timer.TimeLabel = Stub.fontString("")
  timer.TimeLabel.shown = false
  timer:SetScript("OnUpdate", function(self) -- WorldMapZoneTimerMixin:OnUpdate (:665–676)
    local t = M.state.battle
    self.TimeLabel.shown = t ~= nil
    -- NEXT_BATTLE is positional ("%1$02d:…"), which the client's format takes and plain Lua's does not
    if t then self.TimeLabel.text = ("Next Battle: %02d:%02d:%02d"):format(t[1], t[2], t[3]) end
  end)
  return frame
end

-- FlightMapFrame (blizzard_flightmap.xml:5–36, blizzard_flightmap.lua:5–19, 51–56).
function M.flightMap(en)
  local frame = CreateFrame("Frame", "FlightMapFrame")
  local border = CreateFrame("Frame")
  frame.BorderFrame = border
  border.TitleContainer = { TitleText = Stub.fontString("") }
  function border.SetTitle(self, text) self.TitleContainer.TitleText.text = text end
  function frame.ResetTitleAndPortraitIcon(self) self.BorderFrame:SetTitle(en("FLIGHT_MAP")) end
  local zoom = { MapLabel = { Text = Stub.fontString(en("FLIGHT_MAP_CLICK_TO_ZOOM_HINT")) },
    ZoomOutMapLabel = { Text = Stub.fontString(en("FLIGHT_MAP_CLICK_TO_ZOOM_OUT_HINT")) } }
  frame.zoom = zoom
  frame.dataProviders = { [zoom] = true, [{ name = "FlightMap_FlightPathDataProviderMixin" }] = true }
  frame:ResetTitleAndPortraitIcon()
  Stub.loadedAddons["Blizzard_FlightMap"] = true
  return frame
end

-- BattlefieldMapTab (mainline/blizzard_battlefieldmap.xml:3, 41).
function M.battlefieldMap(en)
  local tab = Stub.button("BattlefieldMapTab", en("BATTLEFIELD_MINIMAP"))
  Stub.loadedAddons["Blizzard_BattlefieldMap"] = true
  return tab
end

function M.clear()
  _G.WorldMapFrame, _G.FlightMapFrame, _G.BattlefieldMapTab = nil, nil, nil
  M.state = {}
end

M.state = {}
return M
