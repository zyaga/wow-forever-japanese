-- The flight master's map on Forever: UI/Taxi.lua over a TaxiFrame replayed from camelot
-- blizzard_uipanels_game/shared/taxiframe.lua (TaxiFrame_OnShow :44–47, TaxiNodeOnButtonEnter :135–208).
local Stub = require("tests.lua.spec.wow_stub")
local G = require("tests.lua.spec.stub_gamepanels")

local FILES = G.files("UI/Taxi.lua")
local UI = { FLIGHT_MAP = { "Flight Map", "飛行マップ" }, TAXINODEYOUAREHERE = { "You are here", "現在地" },
  WORLD = { "World", "ワールド" } }
local NAMES = { "TaxiFrame", "TaxiNodeOnButtonEnter" }

local function install()
  local frame = CreateFrame("Frame", "TaxiFrame")
  frame.TitleText = Stub.fontString("")
  frame:SetScript("OnShow", function(self)
    if type(self.TitleText) == "table" then self.TitleText.text = _G.FLIGHT_MAP end
  end)
  _G.TaxiNodeOnButtonEnter = function(button)
    local tt = _G.GameTooltip
    tt:SetOwner(button, "ANCHOR_RIGHT")
    tt:AddLine(button.node)
    if button.current then tt:AddLine(_G.TAXINODEYOUAREHERE) end
    tt:Show()
  end
  return frame
end

describe("the flight master's map on Forever", function()
  local WFJ

  before_each(function() WFJ = G.load(FILES, UI) end)
  after_each(function() G.clear(NAMES) end)

  it("the title is re-shown on every show; Alt shows English; hide restores", function()
    local frame = install()
    assert.is_true(WFJ.Taxi.init())
    frame:Show()
    assert.are.equal("飛行マップ", frame.TitleText:GetText())
    frame:Hide()
    assert.are.equal("Flight Map", frame.TitleText:GetText())
    frame:Show()
    assert.are.equal("飛行マップ", frame.TitleText:GetText())
    G.alt(WFJ, true)
    assert.are.equal("Flight Map", frame.TitleText:GetText())
  end)

  it("the node tooltip: 'You are here' translates; the node's name (even a dictionary word) stays English",
    function()
      install()
      assert.is_true(WFJ.Taxi.init())
      local button = CreateFrame("Button", "TaxiButton1")
      button.node, button.current = "World", true -- a node named like a dictionary word
      _G.TaxiNodeOnButtonEnter(button)
      assert.are.equal("World", G.line(1))
      assert.are.equal("現在地", G.line(2))
      assert.is_false(WFJ.HelpTooltip.registered(button)) -- walked once; the owner is not left registered
      _G.TaxiButton1 = nil
    end)

  it("wrong-typed names degrade without error; hooks install once", function()
    local frame = install()
    _G.TaxiNodeOnButtonEnter = 4
    frame.TitleText = "x"
    assert.has_no.errors(function() assert.is_true(WFJ.Taxi.init()) end)
    assert.has_no.errors(function() frame:Show() end)
    assert.is_false(WFJ.Taxi.init())
  end)

  it("no TaxiFrame: init is false and nothing is touched", function()
    assert.has_no.errors(function() assert.is_false(WFJ.Taxi.init()) end)
    assert.is_nil(Stub.hooks["TaxiNodeOnButtonEnter"])
  end)
end)
