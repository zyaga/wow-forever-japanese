-- UI/CombatFeedback.lua over CombatFeedback_OnCombatEvent replayed from camelot
-- blizzard_framexml/mainline/combatfeedback.lua:26–95. Client writes go to `fs.text`.
local Stub = require("tests.lua.spec.wow_stub")
local X = require("tests.lua.spec.stub_framexml_hud")

local UI = {
  MISS = { "Miss", "ミス" }, DODGE = { "Dodge", "回避" }, BLOCK = { "Block", "ブロック" },
  COMBAT_TEXT_BLOCK_REDUCED = { "%s (Block)", "%s（ブロック）" },
  RANK = { "Rank", "ランク" }, -- a dictionary word this widget can never legitimately hold
}
local NAMES = { "CombatFeedback_OnCombatEvent" }

local function install()
  _G.CombatFeedback_OnCombatEvent = function(self, event, _, amount)
    local text
    if event == "WOUND" then text = tostring(amount)
    elseif event == "BLOCK_REDUCED" then text = _G.COMBAT_TEXT_BLOCK_REDUCED:format(tostring(amount))
    elseif event == "NAME" then text = "Rank"
    else text = _G[event] end
    self.feedbackText.text = text
  end
end

describe("the portrait combat words on Forever", function()
  local WFJ, player, pet
  before_each(function()
    WFJ = X.load("UI/CombatFeedback.lua", UI, { before = install })
    player = { feedbackText = Stub.fontString("") }
    pet = { feedbackText = Stub.fontString("") }
    assert.is_true(WFJ.CombatFeedback.init())
  end)
  after_each(function() X.teardown(NAMES) end)

  it("a combat word translates per unit frame; a number and a word outside the set are left alone", function()
    _G.CombatFeedback_OnCombatEvent(player, "MISS")
    _G.CombatFeedback_OnCombatEvent(pet, "DODGE")
    assert.are.equal("ミス", player.feedbackText:GetText())
    assert.are.equal("回避", pet.feedbackText:GetText())
    X.alt(WFJ, true)
    assert.are.equal("Miss", player.feedbackText:GetText())
    X.alt(WFJ, false)
    _G.CombatFeedback_OnCombatEvent(player, "WOUND", nil, 1234)
    assert.are.equal("1234", player.feedbackText:GetText())
    assert.is_true(X.unrecorded(WFJ, player.feedbackText))
    _G.CombatFeedback_OnCombatEvent(player, "BLOCK_REDUCED", nil, 40)
    assert.are.equal("40（ブロック）", player.feedbackText:GetText())
    _G.CombatFeedback_OnCombatEvent(player, "NAME")
    assert.are.equal("Rank", player.feedbackText:GetText())
  end)

  it("a unit frame without a text widget, or with a wrong-typed one, raises nothing", function()
    assert.has_no.errors(function()
      WFJ.CombatFeedback.onCombatEvent({})
      WFJ.CombatFeedback.onCombatEvent({ feedbackText = "x" })
      WFJ.CombatFeedback.onCombatEvent(nil)
    end)
  end)

  it("hooks once; a wrong-typed writer and no writer return false", function()
    assert.is_false(WFJ.CombatFeedback.init())
    assert.are.equal(1, #Stub.hooks["CombatFeedback_OnCombatEvent"])
    X.teardown(NAMES)
    local wrong = X.load("UI/CombatFeedback.lua", UI, { before = function() _G.CombatFeedback_OnCombatEvent = {} end })
    assert.has_no.errors(function() assert.is_false(wrong.CombatFeedback.init()) end)
    X.teardown(NAMES)
    local none = X.load("UI/CombatFeedback.lua", UI)
    assert.is_false(none.CombatFeedback.init())
  end)
end)
