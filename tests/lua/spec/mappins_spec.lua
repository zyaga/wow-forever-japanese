-- UI/MapPins.lua over pins as MapCanvasMixin:AcquirePin leaves them
-- (blizzard_mapcanvas/blizzard_mapcanvas.lua:280–288) and tooltips replayed from blizzard_sharedmapdataproviders
-- (sharedmappoitemplates.lua:139–157, flightpointdataprovider.lua:20–27, deathmapdataprovider.lua:39–49,
-- selectablegraveyarddataprovider.lua:57–73, waypointlocationdataprovider.lua:165–171). Place names stay English.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local Maps = require("tests.lua.spec.stub_maps")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/MapPins.lua"

local UI = {
  UNDISCOVERED_NEUTRAL_FLIGHTPOINT = { "Undiscovered Flightpoint", "未発見のフライトポイント" },
  CORPSE_RED = { "|cffff2020Corpse|r", "|cffff2020死体|r" },
  GRAVEYARD_SELECTED = { "Selected Graveyard", "選択中の墓地" },
  GRAVEYARD_SELECTED_TOOLTIP = { "You will resurrect at this graveyard.", "この墓地で復活します。" },
  GRAVEYARD_ELIGIBLE = { "Eligible Graveyard", "選択可能な墓地" },
  MAP_PIN_SHARING = { "Map Pin Sharing", "マップピンの共有" },
  MAP_PIN_REMOVE = { "<Ctrl click to remove pin>", "<Ctrl+クリックでピンを削除>" },
  VIGNETTE_SUGGESTED_GROUP_NUM = { "Suggested Players [%d]", "推奨人数 [%d]" },
  DUNGEON_MAP_PIN_FALLBACK_NAME = { "Dungeon", "ダンジョン" },
  CLOSE = { "Close", "閉じる" },
  -- a vignette's objective line (vignettedataprovider.lua:333–346)
  TOOLTIP_VIGNETTE_OBJECTIVE_DEFEAT = { "- Defeat %s", "- %sを倒す" },
  TOOLTIP_VIGNETTE_OBJECTIVE_DEFEAT_SHOW_HEALTH = { "- Defeat %s (Current Health: %s)", "- %sを倒す(残り体力: %s)" },
  -- the gamepad lines of the waypoint and quest pins (waypointlocationdataprovider.lua:173–174,
  -- questdataprovider.lua:274–275)
  MAP_PIN_SHARING_TOOLTIP_GAMEPAD = { "You can share this location with other players by inserting a link into chat.",
    "チャットにリンクを挿入すると、この場所をほかのプレイヤーと共有できます。" },
  MAP_PIN_TOGGLE_FOCUS = { "Toggle Focus on Marker", "マーカーへのフォーカスを切り替え" },
  MAP_PIN_TOGGLE_QUEST_FOCUS = { "Toggle Focus on Quest", "クエストへのフォーカスを切り替え" },
  MAP_PIN_TOGGLE_QUEST_DETAILS = { "Toggle Quest Details", "クエストの詳細を切り替え" },
}

local function en(key) return _G[key] end

describe("map pin tooltips on Forever", function()
  local WFJ

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

  before_each(function()
    load()
    assert.is_true(WFJ.MapPins.init())
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    Maps.clear()
  end)

  it("a listed pin's fixed lines translate on its first tooltip and on every later one; the place name does not",
    function()
      local pin = Maps.pin("FlightPointPinTemplate")
      assert.is_false(WFJ.HelpTooltip.registered(pin))
      Maps.tooltip(pin, { "Thelsamar", en("UNDISCOVERED_NEUTRAL_FLIGHTPOINT") })
      assert.are.equal("Thelsamar", Maps.line(1))
      assert.are.equal("未発見のフライトポイント", Maps.line(2))
      assert.is_true(WFJ.HelpTooltip.registered(pin))
      alt(true)
      assert.are.equal("Undiscovered Flightpoint", Maps.line(2))
      alt(false)
      Maps.tooltip(pin, { en("UNDISCOVERED_NEUTRAL_FLIGHTPOINT") }) -- a node with no name: the description is line 1
      assert.are.equal("未発見のフライトポイント", Maps.line(1))
    end)

  it("each template takes only its own keys: a name that is also a dictionary word stays English", function()
    local grave = Maps.pin("SelectableGraveyardPinTemplate")
    Maps.tooltip(grave, { en("GRAVEYARD_SELECTED"), en("GRAVEYARD_SELECTED_TOOLTIP") })
    assert.are.equal("選択中の墓地", Maps.line(1))
    assert.are.equal("この墓地で復活します。", Maps.line(2))
    Maps.tooltip(grave, { "Close" }) -- a graveyard called "Close"
    assert.are.equal("Close", Maps.line(1))
    Maps.tooltip(Maps.pin("CorpsePinTemplate"), { en("CORPSE_RED") })
    assert.are.equal("|cffff2020死体|r", Maps.line(1))
    Maps.tooltip(Maps.pin("DeathReleasePinTemplate"), { "|cffff2020Spirit Healer|r" }) -- a creature's name
    assert.are.equal("|cffff2020Spirit Healer|r", Maps.line(1))
    Maps.tooltip(Maps.pin("WaypointLocationPinTemplate"), { en("MAP_PIN_SHARING"), "…", en("MAP_PIN_REMOVE") })
    assert.are.equal("マップピンの共有", Maps.line(1))
    assert.are.equal("<Ctrl+クリックでピンを削除>", Maps.line(3))
    Maps.tooltip(Maps.pin("VignettePinTemplate"), { "Dungeon", "Suggested Players [5]" }) -- a rare called "Dungeon"
    assert.are.equal("Dungeon", Maps.line(1))
    assert.are.equal("推奨人数 [5]", Maps.line(2))
  end)

  it("a vignette's Defeat objective, the creature's name kept (with and without its health)", function()
    Maps.tooltip(Maps.pin("VignettePinTemplate"),
      { "Hogger", "- Defeat Hogger", "- Defeat Hogger (Current Health: 80%)" })
    assert.are.equal("Hogger", Maps.line(1))
    assert.are.equal("- Hoggerを倒す", Maps.line(2))
    assert.are.equal("- Hoggerを倒す(残り体力: 80%)", Maps.line(3))
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal("- Defeat Hogger", Maps.line(2))
    Stub.keys.alt = false; WFJ.Modifier.refresh()
  end)

  it("the waypoint and quest pins' gamepad lines, the input icon kept; the quest's title stays", function()
    local icon = "|A:Gamepad_Ltr_A_64:30:30|a" -- CreateAtlasMarkup(atlas, 30, 30), no space before the text
    Maps.tooltip(Maps.pin("WaypointLocationPinTemplate"),
      { en("MAP_PIN_SHARING"), en("MAP_PIN_SHARING_TOOLTIP_GAMEPAD"), icon .. en("MAP_PIN_TOGGLE_FOCUS") })
    assert.are.equal("チャットにリンクを挿入すると、この場所をほかのプレイヤーと共有できます。", Maps.line(2))
    assert.are.equal(icon .. "マーカーへのフォーカスを切り替え", Maps.line(3))
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal(en("MAP_PIN_SHARING_TOOLTIP_GAMEPAD"), Maps.line(2))
    assert.are.equal(icon .. "Toggle Focus on Marker", Maps.line(3))
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    Maps.tooltip(Maps.pin("QuestPinTemplate"), { "Burning Archives", "- 3/10 Kobold Vermin slain",
      icon .. en("MAP_PIN_TOGGLE_QUEST_FOCUS"), icon .. en("MAP_PIN_TOGGLE_QUEST_DETAILS") })
    assert.are.equal("Burning Archives", Maps.line(1))
    assert.are.equal("- 3/10 Kobold Vermin slain", Maps.line(2))
    assert.are.equal(icon .. "クエストへのフォーカスを切り替え", Maps.line(3))
    assert.are.equal(icon .. "クエストの詳細を切り替え", Maps.line(4))
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal(icon .. "Toggle Quest Details", Maps.line(4))
    Stub.keys.alt = false; WFJ.Modifier.refresh()
  end)

  it("an unlisted template, a frame with no template and a wrong-typed template are left alone with no error",
    function()
      Maps.tooltip(Maps.pin("BonusObjectivePinTemplate"), { en("GRAVEYARD_SELECTED") })
      assert.are.equal("Selected Graveyard", Maps.line(1))
      Maps.tooltip(CreateFrame("Frame"), { en("GRAVEYARD_SELECTED") })
      assert.are.equal("Selected Graveyard", Maps.line(1))
      local odd = Maps.pin({ "FlightPointPinTemplate" })
      assert.has_no.errors(function() Maps.tooltip(odd, { en("UNDISCOVERED_NEUTRAL_FLIGHTPOINT") }) end)
      assert.are.equal("Undiscovered Flightpoint", Maps.line(1))
      assert.has_no.errors(function() assert.are.equal(0, WFJ.MapPins.onShow(nil)) end)
      local numeric = { GetOwner = function() return 3 end }
      assert.has_no.errors(function() assert.are.equal(0, WFJ.MapPins.onShow(numeric)) end)
    end)

  it("another module can add its map's template once; a listed template is kept", function()
    assert.is_true(WFJ.MapPins.add("FlightMap_FlightPointPinTemplate", { "DUNGEON_MAP_PIN_FALLBACK_NAME" }))
    assert.is_false(WFJ.MapPins.add("FlightMap_FlightPointPinTemplate", { "CLOSE" }))
    assert.is_false(WFJ.MapPins.add("CorpsePinTemplate", { "CLOSE" }))
    assert.is_false(WFJ.MapPins.add(4, { "CLOSE" }))
    assert.are.same({ "CORPSE_RED" }, WFJ.MapPins.keys("CorpsePinTemplate"))
  end)

  it("the hook installs once; a wrong-typed tooltip hooks nothing", function()
    assert.is_false(WFJ.MapPins.init())
    assert.are.equal(1, #Stub.hooks["GameTooltip:Show"] - 1) -- HelpTooltip's own Show hook, then this one
    load()
    _G.GameTooltip = "tooltip"
    assert.has_no.errors(function() assert.is_false(WFJ.MapPins.init()) end)
  end)
end)
