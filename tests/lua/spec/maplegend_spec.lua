-- UI/MapLegend.lua over QuestMapFrame.MapLegend replayed from camelot
-- blizzard_uipanels_game/mainline/maplegendframe.lua (SetupCategories :10–33, MapLegendButtonMixin:OnEnter :37–44),
-- maplegendframe.xml:41 and camelot/maplegendframedata.lua.
local Stub = require("tests.lua.spec.wow_stub")
local G = require("tests.lua.spec.stub_gamepanels")

local FILES = G.files("UI/MapLegend.lua")
local UI = {
  MAP_LEGEND_FRAME_LABEL = { "Map Legend", "マップ凡例" },
  MAP_LEGEND_CATEGORY_QUESTS = { "Quests", "クエスト" }, MAP_LEGEND_CATEGORY_MOVEMENT = { "Movement", "移動" },
  MAP_LEGEND_TURNIN = { "Turn In", "報告" }, MAP_LEGEND_TURNIN_TOOLTIP = { "Quests that are ready to be turned in",
    "報告できるクエスト" },
  MAP_LEGEND_FLIGHTPOINT = { "Flightpoint", "フライトポイント" },
  MAP_LEGEND_DELVE = { "Delve", "デルヴ" }, -- not in camelot's legend: never taken
}

-- A frame whose children the client created unnamed (GetChildren).
local function parent(kind)
  local f = CreateFrame(kind or "Frame")
  f.kids = {}
  function f.GetChildren(self) return unpack(self.kids) end
  return f
end

local function install(data)
  local quest = CreateFrame("Frame", "QuestMapFrame")
  local panel = CreateFrame("Frame")
  quest.MapLegend, quest.MapLegendTab = panel, CreateFrame("Frame")
  panel.TitleText = Stub.fontString(_G.MAP_LEGEND_FRAME_LABEL)
  local child = parent()
  panel.ScrollFrame = { ScrollChild = child }
  for _, cat in ipairs(data) do -- MapLegendMixin:SetupCategories
    local category = parent()
    category.TitleText = Stub.fontString(cat.title)
    child.kids[#child.kids + 1] = category
    for _, name in ipairs(cat) do category.kids[#category.kids + 1] = Stub.button(nil, name) end
  end
  return panel, child
end

describe("the world map legend on Forever", function()
  local WFJ

  before_each(function() WFJ = G.load(FILES, UI) end)
  after_each(function() G.clear({ "QuestMapFrame" }) end)

  it("heading, categories, entries and their tooltips translate; a word outside the legend's keys does not",
    function()
      local panel, child = install({ { title = "Quests", "Turn In", "Delve" }, { title = "Movement", "Flightpoint" } })
      assert.is_true(WFJ.MapLegend.init())
      panel:Show()
      assert.are.equal("マップ凡例", panel.TitleText:GetText())
      local quests, movement = child.kids[1], child.kids[2]
      assert.are.equal("クエスト", quests.TitleText:GetText())
      assert.are.equal("移動", movement.TitleText:GetText())
      assert.are.equal("報告", quests.kids[1]:GetText())
      assert.are.equal("Delve", quests.kids[2]:GetText())
      assert.is_true(G.unrecorded(WFJ, quests.kids[2]))
      assert.are.equal("フライトポイント", movement.kids[1]:GetText())
      G.tooltip(quests.kids[1], { "Turn In", UI.MAP_LEGEND_TURNIN_TOOLTIP[1] })
      assert.are.equal("報告", G.line(1))
      assert.are.equal("報告できるクエスト", G.line(2))
      G.tooltip(_G.QuestMapFrame.MapLegendTab, { "Map Legend" })
      assert.are.equal("マップ凡例", G.line(1))
      G.alt(WFJ, true)
      assert.are.equal("Quests", quests.TitleText:GetText())
      G.alt(WFJ, false)
      panel:Hide()
      assert.are.equal("Turn In", quests.kids[1]:GetText())
    end)

  it("wrong-typed names degrade without error; hooks install once", function()
    local panel, child = install({ { title = "Quests", "Turn In" } })
    child.kids[#child.kids + 1] = 5
    child.kids[1].kids[2] = "x"
    panel.TitleText = false
    _G.QuestMapFrame.MapLegendTab = 1
    assert.has_no.errors(function() assert.is_true(WFJ.MapLegend.init()) end)
    assert.has_no.errors(function() panel:Show() end)
    assert.are.equal("報告", child.kids[1].kids[1]:GetText())
    panel.ScrollFrame = 7
    assert.has_no.errors(function() assert.are.equal(0, WFJ.MapLegend.onShow()) end)
    assert.is_false(WFJ.MapLegend.init())
  end)

  it("no QuestMapFrame, or a wrong-typed one: init is false", function()
    assert.has_no.errors(function() assert.is_false(WFJ.MapLegend.init()) end)
    _G.QuestMapFrame = "x"
    assert.has_no.errors(function() assert.is_false(WFJ.MapLegend.init()) end)
    _G.QuestMapFrame = { MapLegend = 3 }
    assert.has_no.errors(function() assert.is_false(WFJ.MapLegend.init()) end)
  end)
end)
