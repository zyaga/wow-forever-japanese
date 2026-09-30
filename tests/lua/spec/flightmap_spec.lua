-- UI/FlightMap.lua over a FlightMapFrame replayed from camelot
-- blizzard_flightmap (blizzard_flightmap.lua:5–19, 51–56; fm_flightpathdataprovider.lua:240–269;
-- fm_zonesummarydataprovider.lua:42–60) and the click-to-zoom provider (blizzard_sharedmapdataproviders/
-- clicktozoomdataprovider.lua:36–57). Flight point and zone names stay English; either load order.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local Maps = require("tests.lua.spec.stub_maps")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/MapPins.lua"
FILES[#FILES + 1] = "UI/FlightMap.lua"

local ADDON = "Blizzard_FlightMap"

local UI = {
  FLIGHT_MAP = { "Flight Map", "飛行マップ" },
  TAXINODEYOUAREHERE = { "You are here", "現在地" },
  TAXI_PATH_UNREACHABLE = { "Not Discovered", "未発見" },
  FLIGHT_MAP_CLICK_TO_ZOOM_IN = { "<Click to Zoom In>", "<クリックで拡大>" },
  FLIGHT_MAP_CLICK_TO_ZOOM_HINT = { "Click to Zoom In", "クリックで拡大" },
  FLIGHT_MAP_CLICK_TO_ZOOM_OUT_HINT = { "Right-Click to Zoom Out", "右クリックで縮小" },
  WORLD = { "World", "ワールド" }, -- a word a place may happen to be called
}

local function en(key) return _G[key] end

describe("the flight map on Forever", function()
  local WFJ, frame

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  local function load()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    Maps.clear()
  end

  local function setup(loadedFirst)
    load()
    assert.is_true(WFJ.MapPins.init())
    if loadedFirst then
      frame = Maps.flightMap(en)
      assert.is_true(WFJ.FlightMap.init())
    else
      assert.is_false(WFJ.FlightMap.init()) -- waits for the addon
      frame = Maps.flightMap(en)
      assert.are.equal(1, WFJ.LoadOnDemand.loaded(ADDON))
    end
  end

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    Maps.clear()
  end)

  for _, order in ipairs({ { true, "loaded at login" }, { false, "loaded on demand" } }) do
    describe("Blizzard_FlightMap " .. order[2], function()
      before_each(function() setup(order[1]) end)

      it("the title renders Japanese after SetTitle, keeps it after a second SetTitle, and a name is left alone",
        function()
          local title = frame.BorderFrame.TitleContainer.TitleText
          assert.are.equal("飛行マップ", title:GetText())
          frame:ResetTitleAndPortraitIcon() -- RemoveAllData re-titles the window (fm_flightpathdataprovider.lua:8–10)
          assert.are.equal("飛行マップ", title:GetText())
          alt(true)
          assert.are.equal("Flight Map", title:GetText())
          alt(false)
          frame.BorderFrame:SetTitle("World") -- not this title's key
          assert.are.equal("World", title:GetText())
          assert.are.equal(1, #Stub.hooks["?:SetTitle"])
        end)

      it("a node pin's tooltip: the fixed line translates, the flight point's name does not", function()
        local pin = Maps.pin("FlightMap_FlightPointPinTemplate")
        Maps.tooltip(pin, { "World", en("TAXINODEYOUAREHERE") })
        assert.are.equal("World", Maps.line(1))
        assert.are.equal("現在地", Maps.line(2))
        Maps.tooltip(pin, { "Ironforge, Dun Morogh", en("TAXI_PATH_UNREACHABLE") })
        assert.are.equal("Ironforge, Dun Morogh", Maps.line(1))
        assert.are.equal("未発見", Maps.line(2))
      end)

      it("the zone summary tooltip (owner: the map itself) and the two zoom hints translate", function()
        Maps.tooltip(frame, { "World", en("FLIGHT_MAP_CLICK_TO_ZOOM_IN") })
        assert.are.equal("World", Maps.line(1)) -- a zone's name
        assert.are.equal("<クリックで拡大>", Maps.line(2))
        assert.are.equal("クリックで拡大", frame.zoom.MapLabel.Text:GetText())
        assert.are.equal("右クリックで縮小", frame.zoom.ZoomOutMapLabel.Text:GetText())
        frame:Show()
        frame:Hide() -- written once by the client: the hints stay; the title is released
        assert.are.equal("クリックで拡大", frame.zoom.MapLabel.Text:GetText())
        assert.are.equal("Flight Map", frame.BorderFrame.TitleContainer.TitleText:GetText())
        frame:Show()
        assert.are.equal("飛行マップ", frame.BorderFrame.TitleContainer.TitleText:GetText())
      end)
    end)
  end

  it("client names bound to the wrong type degrade to English with no error", function()
    load()
    local map = Maps.flightMap(en)
    map.BorderFrame = "border"
    map.dataProviders = { [1] = true, ["x"] = true, [{ MapLabel = 3, ZoomOutMapLabel = {} }] = true,
      [{ MapLabel = { Text = 9 }, ZoomOutMapLabel = { Text = "t" } }] = true }
    assert.has_no.errors(function() assert.is_true(WFJ.FlightMap.init()) end)
    assert.has_no.errors(function() map:Show() end)
    load()
    _G.FlightMapFrame = 12
    Stub.loadedAddons[ADDON] = true
    assert.has_no.errors(function() WFJ.FlightMap.init() end)
  end)

  it("without the frame, nothing is set up", function()
    load()
    Stub.loadedAddons[ADDON] = true
    assert.is_true(WFJ.FlightMap.init()) -- the setup ran …
    assert.is_false(WFJ.FlightMap.setup()) -- … and found no frame
  end)
end)
