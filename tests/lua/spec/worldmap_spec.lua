-- The world map chrome on Forever: UI/WorldMap.lua over a WorldMapFrame replayed from camelot
-- blizzard_worldmap (blizzard_worldmap.lua:318–356, 452–463; blizzard_worldmaptemplates.lua:357–361, 435–447,
-- 472–485, 553–610, 665–676). Map names stay English; the window title is UI/QuestMap's.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local Maps = require("tests.lua.spec.stub_maps")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/WorldMap.lua"

-- Forever GlobalStrings (build 1.60.1.69913) → a test Japanese
local UI = {
  WORLD = { "World", "ワールド" },
  MAP_FILTER = { "Map Filter", "マップフィルター" },
  MAP_PIN = { "Map Pin", "マップピン" },
  MAP_PIN_TOOLTIP = { "Place a locational pin on the map that can be tracked and shared with other players.",
    "マップに位置ピンを置きます。追跡したり、他のプレイヤーと共有したりできます。" },
  MAP_PIN_TOOLTIP_INSTRUCTIONS = { "Click this button and then the map to drop a pin or <Ctrl click directly on "
    .. "the map>", "このボタンをクリックしてからマップをクリックするとピンを置けます（または<マップを直接Ctrl+クリック>）" },
  MAP_PIN_INVALID_MAP = { "You can't place a pin on this map.", "このマップにはピンを置けません。" },
  WORLD_MAP_PLAYER_COORDS = { "Player: %.1f, %.1f", "プレイヤー: %.1f, %.1f" },
  WORLD_MAP_PLAYER_COORDS_INTEGER = { "Player: %d, %d", "プレイヤー: %d, %d" },
  WORLD_MAP_CURSOR_COORDS = { "Cursor: %.1f, %.1f", "カーソル: %.1f, %.1f" },
  WORLD_MAP_CURSOR_COORDS_INTEGER = { "Cursor: %d, %d", "カーソル: %d, %d" },
  WORLD_MAP_CROSSHAIR_COORDS = { "Crosshair: %.1f, %.1f", "照準: %.1f, %.1f" }, -- gamepad mode
  WORLD_MAP_CROSSHAIR_COORDS_INTEGER = { "Crosshair: %d, %d", "照準: %d, %d" },
  NEXT_BATTLE = { "Next Battle: %1$02d:%2$02d:%3$02d", "次の戦闘: %1$02d:%2$02d:%3$02d" },
  CLOSE = { "Close", "閉じる" },
}

local function en(key) return _G[key] end

describe("the world map chrome on Forever", function()
  local WFJ, SS, frame

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  local function unrecorded(widget)
    for _, bucket in pairs(SS.surfaces()) do
      for _, rec in pairs(bucket) do
        if rec.fs == widget or (type(rec.fs) == "table" and rec.fs.button == widget) then return false end
      end
    end
    return true
  end

  local function tick(overlay) overlay.scripts.OnUpdate(overlay, 0.016) end

  local function load()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    SS = WFJ.SurfaceState
    H.uiSetup(WFJ, UI)
    Maps.clear()
  end

  before_each(function()
    load()
    frame = Maps.worldMap(en)
    assert.is_true(WFJ.WorldMap.init())
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    Maps.clear()
  end)

  it("the home button translates; a nav button and the floor dropdown (map names) stay English", function()
    assert.are.equal("ワールド", frame.NavBar.home:GetText())
    assert.are.equal("World", frame.NavBar.zone:GetText()) -- a map called "World" is a name
    assert.is_true(unrecorded(frame.NavBar.zone))
    assert.are.equal("Ironforge", frame.floorDropdown:GetText())
    assert.is_true(unrecorded(frame.floorDropdown))
    alt(true)
    assert.are.equal("World", frame.NavBar.home:GetText())
    alt(false)
    frame:Show() -- re-shown: still Japanese, and it survives the map hiding (written once by the client)
    frame:Hide()
    assert.are.equal("ワールド", frame.NavBar.home:GetText())
  end)

  it("the filter and pin buttons' tooltips translate, restricted to their own keys", function()
    Maps.tooltip(frame.WorldMapTrackingOptionsButton, { en("MAP_FILTER") })
    assert.are.equal("マップフィルター", Maps.line(1))
    Maps.tooltip(frame.WorldMapTrackingPinButton, { en("MAP_PIN"), en("MAP_PIN_TOOLTIP"), " ",
      en("MAP_PIN_TOOLTIP_INSTRUCTIONS") })
    assert.are.equal("マップピン", Maps.line(1))
    assert.are.equal(UI.MAP_PIN_TOOLTIP[2], Maps.line(2))
    assert.are.equal(UI.MAP_PIN_TOOLTIP_INSTRUCTIONS[2], Maps.line(4))
    Maps.tooltip(frame.WorldMapTrackingPinButton, { en("MAP_PIN"), en("MAP_PIN_INVALID_MAP") })
    assert.are.equal("このマップにはピンを置けません。", Maps.line(2))
    Maps.tooltip(frame.WorldMapTrackingPinButton, { "Close" }) -- not one of this owner's keys
    assert.are.equal("Close", Maps.line(1))
    Maps.tooltip(frame.NavBar, { en("MAP_FILTER") }) -- not a registered owner
    assert.are.equal("Map Filter", Maps.line(1))
  end)

  it("the coordinates follow every OnUpdate write; a hidden holder is left alone; Alt shows English", function()
    Maps.state = { tenths = true, player = { 45.3, 12.0 }, cursor = { 7.5, 80.1 } }
    tick(frame.coords)
    assert.are.equal("プレイヤー: 45.3, 12.0", frame.coords.PlayerCoords.Label:GetText())
    assert.are.equal("カーソル: 7.5, 80.1", frame.coords.CursorCoords.Label:GetText())
    Maps.state = { tenths = false, player = { 46, 12 } }
    tick(frame.coords)
    assert.are.equal("プレイヤー: 46, 12", frame.coords.PlayerCoords.Label:GetText())
    alt(true)
    assert.are.equal("Player: 46, 12", frame.coords.PlayerCoords.Label:GetText())
    alt(false)
    -- the player is on another map: the template carries that map's name, which is not a number and stays as written
    Maps.state = { tenths = true, player = { 1.0, 2.0, map = "Elwynn Forest" } }
    tick(frame.coords)
    assert.are.equal("Player: 1.0, 2.0 (Elwynn Forest)", frame.coords.PlayerCoords.Label:GetText())
  end)

  it("the crosshair coordinates (gamepad mode, their own label) translate; Alt shows English", function()
    Maps.state = { tenths = true, crosshair = true, cursor = { 7.5, 80.1 } }
    tick(frame.coords)
    assert.are.equal("照準: 7.5, 80.1", frame.coords.CrosshairCoords.Label:GetText())
    Maps.state = { tenths = false, crosshair = true, cursor = { 8, 80 } }
    tick(frame.coords)
    assert.are.equal("照準: 8, 80", frame.coords.CrosshairCoords.Label:GetText())
    alt(true)
    assert.are.equal("Crosshair: 8, 80", frame.coords.CrosshairCoords.Label:GetText())
    alt(false)
  end)

  it("each coordinates label takes only its own keys", function()
    frame.coords.CursorCoords.Label.text = "Crosshair: 8, 80"
    frame.coords.CursorCoords.shown = true
    WFJ.WorldMap.onCoords(frame.coords)
    assert.are.equal("Crosshair: 8, 80", frame.coords.CursorCoords.Label:GetText())
  end)

  it("the zone timer translates while it is shown", function()
    Maps.state = { battle = { 0, 12, 30 } }
    tick(frame.timer)
    assert.are.equal("次の戦闘: 00:12:30", frame.timer.TimeLabel:GetText())
    Maps.state = {}
    tick(frame.timer)
    assert.is_false(frame.timer.TimeLabel:IsShown())
  end)

  it("the map hiding releases the live labels", function()
    Maps.state = { tenths = true, player = { 45.3, 12.0 } }
    tick(frame.coords)
    frame:Hide()
    assert.are.equal("Player: 45.3, 12.0", frame.coords.PlayerCoords.Label:GetText())
  end)

  it("an overlay added after init is hooked on the next OnShow, once", function()
    local late = CreateFrame("Frame")
    late.TimeLabel = Stub.fontString("Next Battle: 01:02:03")
    frame.overlayFrames[#frame.overlayFrames + 1] = late
    frame:Show()
    frame:Show()
    late.scripts.OnUpdate(late)
    assert.are.equal("次の戦闘: 01:02:03", late.TimeLabel:GetText())
    assert.is_false(WFJ.WorldMap.init()) -- a second init hooks nothing
  end)

  it("a client name bound to the wrong type degrades to English with no error", function()
    load()
    local map = Maps.worldMap(en)
    map.NavBar = 7
    map.WorldMapTrackingOptionsButton = "button"
    map.WorldMapTrackingPinButton = true
    map.overlayFrames = { 1, "x", { PlayerCoords = 3, CursorCoords = {} }, { TimeLabel = "t" } }
    assert.has_no.errors(function() assert.is_true(WFJ.WorldMap.init()) end)
    assert.has_no.errors(function() map:Show() end)
    assert.has_no.errors(function() WFJ.WorldMap.onCoords({ PlayerCoords = 3, CursorCoords = "x" }) end)
    assert.has_no.errors(function() WFJ.WorldMap.onTimer(5) end)
    load()
    _G.WorldMapFrame = "not a frame"
    assert.has_no.errors(function() assert.is_false(WFJ.WorldMap.init()) end)
  end)

  it("without the frame, init returns false", function()
    load()
    assert.is_false(WFJ.WorldMap.init())
  end)
end)
