-- UI/GhostFrame.lua over GhostFrame as camelot blizzard_framexml/ghostframe.xml:3–19 builds it.
local Stub = require("tests.lua.spec.wow_stub")
local X = require("tests.lua.spec.stub_framexml_hud")

local UI = { RETURN_TO_GRAVEYARD = { "Return to Graveyard", "墓地に戻る" }, NONE = { "None", "なし" } }
local NAMES = { "GhostFrame", "GhostFrameContentsFrameText" }

local function install()
  CreateFrame("Button", "GhostFrame")
  Stub.namedFontString("GhostFrameContentsFrameText", "Return to Graveyard")
end

describe("the Return to Graveyard button on Forever", function()
  local WFJ
  before_each(function()
    WFJ = X.load("UI/GhostFrame.lua", UI, { before = install })
    assert.is_true(WFJ.GhostFrame.init())
  end)
  after_each(function() X.teardown(NAMES) end)

  it("the label translates at init and on show; Alt shows English; another word there is left alone", function()
    assert.are.equal("墓地に戻る", _G.GhostFrameContentsFrameText:GetText())
    X.alt(WFJ, true)
    assert.are.equal("Return to Graveyard", _G.GhostFrameContentsFrameText:GetText())
    X.alt(WFJ, false)
    _G.GhostFrameContentsFrameText.text = "None" -- not this widget's key
    _G.GhostFrame:Show()
    assert.are.equal("None", _G.GhostFrameContentsFrameText:GetText())
    assert.is_true(X.unrecorded(WFJ, _G.GhostFrameContentsFrameText))
  end)

  it("init runs once; wrong types and a missing frame return false without error", function()
    assert.is_false(WFJ.GhostFrame.init())
    X.teardown(NAMES)
    local wrong = X.load("UI/GhostFrame.lua", UI, { before = function()
      install()
      _G.GhostFrameContentsFrameText = "x"
    end })
    assert.has_no.errors(function() assert.is_false(wrong.GhostFrame.init()) end)
    X.teardown(NAMES)
    assert.is_false(X.load("UI/GhostFrame.lua", UI).GhostFrame.init())
  end)
end)
