-- UI/CoinPickup.lua over CoinPickupFrame as camelot blizzard_framexml/mainline/coinpickupframe.xml:37,
-- 69, 78 builds it; the amount is `money .. symbol` (coinpickupframe.lua:72).
local Stub = require("tests.lua.spec.wow_stub")
local X = require("tests.lua.spec.stub_framexml_hud")

local UI = { OKAY = { "Okay", "OK" }, COINPICKUP_CANCEL = { "Cancel", "キャンセル" }, CANCEL = { "Cancel", "キャンセル" } }
local NAMES = { "CoinPickupFrame", "CoinPickupOkayButton", "CoinPickupCancelButton", "CoinPickupText" }

local function install()
  CreateFrame("Frame", "CoinPickupFrame")
  Stub.button("CoinPickupOkayButton", "Okay")
  Stub.button("CoinPickupCancelButton", "Cancel")
  Stub.namedFontString("CoinPickupText", "12g")
end

describe("the money pickup box on Forever", function()
  local WFJ
  before_each(function()
    WFJ = X.load("UI/CoinPickup.lua", UI, { before = install })
    WFJ.Labels.forbidNames(WFJ.CoinPickup.NEVER_TOUCH)
    assert.is_true(WFJ.CoinPickup.init())
  end)
  after_each(function() X.teardown(NAMES) end)

  it("both buttons translate on show; the amount is never touched", function()
    _G.CoinPickupFrame:Show()
    assert.are.equal("OK", _G.CoinPickupOkayButton:GetText())
    assert.are.equal("キャンセル", _G.CoinPickupCancelButton:GetText())
    _G.CoinPickupText.text = "Okay"
    assert.are.equal(0, WFJ.Labels.show("coinpickup", "x", _G.CoinPickupText))
    assert.are.equal("Okay", _G.CoinPickupText:GetText())
    X.alt(WFJ, true)
    assert.are.equal("Cancel", _G.CoinPickupCancelButton:GetText())
    X.alt(WFJ, false)
  end)

  it("init runs once; wrong types and a missing frame leave English and raise nothing", function()
    assert.is_false(WFJ.CoinPickup.init())
    X.teardown(NAMES)
    local wrong = X.load("UI/CoinPickup.lua", UI, { before = function()
      install()
      _G.CoinPickupOkayButton = true
    end })
    assert.has_no.errors(function() assert.is_true(wrong.CoinPickup.init()) end)
    assert.are.equal("キャンセル", _G.CoinPickupCancelButton:GetText())
    X.teardown(NAMES)
    assert.is_false(X.load("UI/CoinPickup.lua", UI).CoinPickup.init())
  end)
end)
