-- UI/WorldMap: the names on the world map while Japanese names are on. The area label (AreaLabelFrameTemplate, its
-- Name written from its own OnUpdate, blizzard_sharedmapdataproviders/arealabeldataprovider.lua:74–155, 194–239)
-- shows a place's Japanese. The navigation bar's map buttons stay English: the client measures each one as it
-- writes it on every map change (navigationbar.lua:114–123), the pass that places the map's pins.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local Maps = require("tests.lua.spec.stub_maps")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/WorldMap.lua"

local UI = { WORLD = { "World", "ワールド" } }

describe("the world map's names", function()
  local WFJ, frame, label, hover

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  -- one frame of the label's OnUpdate: the client writes the name under the mouse (or clears it)
  local function tick() label.scripts.OnUpdate(label, 0.016) end

  local function unrecorded(widget)
    for _, bucket in pairs(WFJ.SurfaceState.surfaces()) do
      for _, rec in pairs(bucket) do
        if rec.fs == widget or (type(rec.fs) == "table" and rec.fs.button == widget) then return false end
      end
    end
    return true
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    Maps.clear()
    frame = Maps.worldMap(function(key) return _G[key] end)
    -- the area label data provider (blizzard_worldmap.lua:245–248; MapCanvasMixin:AddDataProvider keys the table by
    -- the provider, blizzard_mapcanvas.lua:191–193)
    label = CreateFrame("Frame", nil, frame)
    label.Name, label.Description = Stub.fontString(""), Stub.fontString("")
    label.labelInfoByType = {}
    label:Show()
    hover = nil
    label:SetScript("OnUpdate", function(self)
      if self.Name.text ~= (hover or "") then self.Name:SetText(hover or "") end -- EvaluateLabels: only when dirty
    end)
    local provider = { Label = label }
    frame.dataProviders = { [provider] = true }
    frame.NavBar.zone.fontString.text = "Eastern Kingdoms"
    WFJ.Data.add("name", {
      [WFJ.Names.key("Elwynn Forest")] = "エルウィン・フォレスト\tえるうぃん・ふぉれすと",
      [WFJ.Names.key("Goldshire")] = "ゴールドシャイア\tごーるどしゃいあ",
      [WFJ.Names.key("Eastern Kingdoms")] = "イースタン・キングダムズ\tいーすたん・きんぐだむず",
    })
    WFJ.State.setNames(true)
    assert.is_true(WFJ.WorldMap.init())
    frame:Show()
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    Maps.clear()
  end)

  it("the area under the mouse shows its Japanese; the reveal key and the map closing give the English back", function()
    hover = "Goldshire"
    tick()
    assert.are.equal("ゴールドシャイア", label.Name:GetText())
    tick() -- the next frames leave it as it is
    assert.are.equal("ゴールドシャイア", label.Name:GetText())
    alt(true)
    assert.are.equal("Goldshire", label.Name:GetText())
    alt(false)
    assert.are.equal("ゴールドシャイア", label.Name:GetText())
    hover = "Elwynn Forest"
    tick()
    assert.are.equal("エルウィン・フォレスト", label.Name:GetText())
    frame:Hide()
    assert.are.equal("Elwynn Forest", label.Name:GetText())
  end)

  it("the mouse leaving the area clears the label, and an unknown place stays as written", function()
    hover = "Goldshire"
    tick()
    hover = nil
    tick()
    assert.are.equal("", label.Name:GetText())
    hover = "Nobody Known Vale"
    tick()
    assert.are.equal("Nobody Known Vale", label.Name:GetText())
    assert.are.equal(1, label.Name.calls.addonSetText) -- only the Japanese it showed for Goldshire
  end)

  it("a zone shown with its level range: the name in Japanese, the coloured range as the client wrote it", function()
    -- name .. color .. " (" .. min .. "-" .. max .. ")" .. FONT_COLOR_CODE_CLOSE (arealabeldataprovider.lua:103–107)
    hover = "Elwynn Forest|cffffff00 (1-10)|r"
    tick()
    assert.are.equal("エルウィン・フォレスト|cffffff00 (1-10)|r", label.Name:GetText())
    alt(true)
    assert.are.equal("Elwynn Forest|cffffff00 (1-10)|r", label.Name:GetText())
    alt(false)
    hover = "Nobody Known Vale|cffffff00 (5)|r"
    tick()
    assert.are.equal("Nobody Known Vale|cffffff00 (5)|r", label.Name:GetText())
  end)

  it("with names off the label is never written", function()
    WFJ.State.setNames(false)
    hover = "Goldshire"
    tick()
    assert.are.equal("Goldshire", label.Name:GetText())
    assert.are.equal(0, label.Name.calls.addonSetText)
  end)

  it("the navigation bar's map buttons stay English: the client measures them on every map change", function()
    frame:Show()
    assert.are.equal("Eastern Kingdoms", frame.NavBar.zone:GetText())
    assert.is_true(unrecorded(frame.NavBar.zone))
    assert.are.equal("ワールド", frame.NavBar.home:GetText()) -- the home button is a dictionary word
  end)

  it("a map with no area label provider loads without an error", function()
    frame.dataProviders = nil
    assert.has_no.errors(function() frame:Show() end)
  end)
end)
