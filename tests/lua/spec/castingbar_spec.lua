-- UI/CastingBar.lua over a PlayerCastingBarFrame replayed from camelot
-- blizzard_uipanels_game/shared/castingbarframe.lua (OnEvent :107–150, HandleInterruptOrSpellFailed :541–560,
-- GetInterruptText :615–635).
local Stub = require("tests.lua.spec.wow_stub")
local G = require("tests.lua.spec.stub_gamepanels")

local FILES = G.files("UI/CastingBar.lua")
local UI = { FAILED = { "Failed", "失敗" }, INTERRUPTED = { "Interrupted", "中断" },
  SPELL_INTERRUPTED_BY = { "Interrupted: %s", "中断: %s" }, RESET = { "Reset", "リセット" } }
local NAMES = { "PlayerCastingBarFrame", "issecretvalue" }

local function patch(WFJ) -- the Core/UIStrings entry this surface needs
  WFJ.UIStrings.ARGS.SPELL_INTERRUPTED_BY = { [1] = "text" }
end

local function install()
  local bar = CreateFrame("StatusBar", "PlayerCastingBarFrame")
  bar.Text = Stub.fontString("")
  bar.CastTimeText = Stub.fontString("1.5 s")
  bar:RegisterEvent("UNIT_SPELLCAST_START")
  bar:RegisterEvent("UNIT_SPELLCAST_FAILED")
  bar:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
  bar:SetScript("OnEvent", function(self, event, _, spell, by)
    if type(self.Text) ~= "table" then return end
    if event == "UNIT_SPELLCAST_START" then self.Text.text = spell
    elseif event == "UNIT_SPELLCAST_FAILED" then self.Text.text = _G.FAILED
    elseif by then self.Text.text = _G.SPELL_INTERRUPTED_BY:format("|cffc69b6d" .. by .. "|r")
    else self.Text.text = _G.INTERRUPTED end
  end)
  return bar
end

describe("the player's casting bar on Forever", function()
  local WFJ

  before_each(function() WFJ = G.load(FILES, UI, patch) end)
  after_each(function() G.clear(NAMES) end)

  it("Failed / Interrupted translate; the interrupter's name and every spell name stay English", function()
    local bar = install()
    WFJ.Labels.forbidNames(WFJ.CastingBar.NEVER_TOUCH)
    assert.is_true(WFJ.CastingBar.init())
    bar:fire("UNIT_SPELLCAST_START", "player", "Reset") -- a spell named like a dictionary word
    assert.are.equal("Reset", bar.Text:GetText())
    assert.is_true(G.unrecorded(WFJ, bar.Text))
    bar:fire("UNIT_SPELLCAST_FAILED", "player")
    assert.are.equal("失敗", bar.Text:GetText())
    G.alt(WFJ, true)
    assert.are.equal("Failed", bar.Text:GetText())
    G.alt(WFJ, false)
    bar:fire("UNIT_SPELLCAST_START", "player", "Frostbolt") -- the next cast: the record and the font go at once
    assert.are.equal("Frostbolt", bar.Text:GetText())
    assert.is_true(G.unrecorded(WFJ, bar.Text))
    assert.are.equal("Fonts\\FRIZQT__.TTF", (bar.Text:GetFont()))
    bar:fire("UNIT_SPELLCAST_INTERRUPTED", "player")
    assert.are.equal("中断", bar.Text:GetText())
    bar:fire("UNIT_SPELLCAST_INTERRUPTED", "player", nil, "Garrosh")
    assert.are.equal("中断: |cffc69b6dGarrosh|r", bar.Text:GetText())
    assert.are.equal("1.5 s", bar.CastTimeText:GetText())
  end)

  it("a text the client flags as secret is never read further", function()
    local bar = install()
    _G.issecretvalue = function() return true end
    assert.is_true(WFJ.CastingBar.init())
    bar:fire("UNIT_SPELLCAST_FAILED", "player")
    assert.are.equal("Failed", bar.Text:GetText())
  end)

  it("wrong-typed names degrade without error; the hook installs once", function()
    local bar = install()
    _G.issecretvalue = 3
    assert.has_no.errors(function() assert.is_true(WFJ.CastingBar.init()) end)
    bar.Text = "x"
    assert.has_no.errors(function() bar:fire("UNIT_SPELLCAST_FAILED", "player") end)
    assert.is_false(WFJ.CastingBar.init())
  end)

  it("no bar or a wrong-typed one: init is false and nothing is touched", function()
    assert.has_no.errors(function() assert.is_false(WFJ.CastingBar.init()) end)
    _G.PlayerCastingBarFrame = 1
    assert.has_no.errors(function() assert.is_false(WFJ.CastingBar.init()) end)
  end)
end)
