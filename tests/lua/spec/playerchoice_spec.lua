-- The player choice window on Forever: UI/PlayerChoice.lua over a PlayerChoiceFrame and its toggle
-- buttons replayed from camelot blizzard_playerchoice (blizzard_playerchoice.lua:25–29, togglebutton.lua:48–77),
-- load-on-demand in both load orders. The choice's own server text stays as the client wrote it.
local Stub = require("tests.lua.spec.wow_stub")
local R = require("tests.lua.spec.stub_retail")

local UI = {
  PLAYER_CHOICE_GRID_HEADER = { "What story would you like to hear?", "どの物語を聞きたい？" },
  PLAYER_CHOICE_GRID_DESC = { "Stay a while and listen to stories of the past from Azeroth and beyond.",
    "しばし留まり、アゼロスとその彼方の過去の物語に耳を傾けよう。" },
  HIDE = { "Hide", "隠す" },
  PLAYER_CHOICE_QUALITY_STRING_RARE = { "|cff0070ddRare|r|n|n", "|cff0070ddレア|r|n|n" },
}
local GLOBALS = { "PlayerChoiceFrame", "GenericPlayerChoiceToggleButton", "CypherPlayerChoiceToggleButton",
  "TorghastPlayerChoiceToggleButton", "PlayerChoicePowerChoiceTemplateMixin",
  "PlayerChoiceGenericPowerChoiceOptionTemplateMixin" }

-- A power-choice option as the client builds one from the mixin (powerchoicetemplate.lua:205–229): its
-- OptionText writes a SimpleHTML (no GetText), modelled by `html`.
local function option(rarityText, description)
  local o = { optionInfo = { description = description } }
  local html = Stub.fontString("")
  o.OptionText = { useHTML = false, textObject = html, html = html }
  function o.OptionText.SetText(self, t) self.textObject.text = t end
  function o.GetRarityDescriptionString() return rarityText end
  o.SetupOptionText = _G.PlayerChoiceGenericPowerChoiceOptionTemplateMixin.SetupOptionText
  return o
end

local function toggle(name)
  local button = CreateFrame("Button", name)
  button.Text = Stub.fontString("")
  function button.UpdateButtonState(self, pending) -- togglebutton.lua:73
    self.Text.text = _G.PlayerChoiceFrame:IsShown() and _G.HIDE or (pending or "")
  end
  return button
end

local function build()
  local frame = CreateFrame("Frame", "PlayerChoiceFrame")
  R.tree(frame, { GridNoSelectionHeader = _G.PLAYER_CHOICE_GRID_HEADER,
    GridNoSelectionDescription = _G.PLAYER_CHOICE_GRID_DESC, Title = "" })
  toggle("GenericPlayerChoiceToggleButton")
  toggle("CypherPlayerChoiceToggleButton")
  local function setup(self)
    self.OptionText:SetText(self:GetRarityDescriptionString() .. self.optionInfo.description)
  end
  _G.PlayerChoicePowerChoiceTemplateMixin = { SetupOptionText = setup }
  _G.PlayerChoiceGenericPowerChoiceOptionTemplateMixin = { SetupOptionText = setup }
  return frame
end

R.suite(getfenv(1), {
  title = "the player choice window on Forever", module = "PlayerChoice", file = "UI/PlayerChoice.lua",
  addon = "Blizzard_PlayerChoice", root = "PlayerChoiceFrame", globals = GLOBALS, ui = UI, build = build,
  cases = {
    { "the grid labels and the toggle's Hide are Japanese; Alt shows English", function(frame, WFJ)
      frame:Show()
      assert.are.equal("どの物語を聞きたい？", frame.GridNoSelectionHeader:GetText())
      local button = _G.GenericPlayerChoiceToggleButton
      button:UpdateButtonState()
      assert.are.equal("隠す", button.Text:GetText())
      R.alt(WFJ, true)
      assert.are.equal("Hide", button.Text:GetText())
      R.alt(WFJ, false)
    end },
    { "playerChoicePrefix: the rarity word is Japanese, the server description kept; Alt shows English",
      function(frame, WFJ)
        frame:Show()
        local o = option("|cff0070ddRare|r|n|n", "Gain 5% Haste. Stacks.")
        o:SetupOptionText()
        assert.are.equal("|cff0070ddレア|r|n|nGain 5% Haste. Stacks.", o.OptionText.html:GetText())
        R.alt(WFJ, true)
        assert.are.equal("|cff0070ddRare|r|n|nGain 5% Haste. Stacks.", o.OptionText.html:GetText())
        R.alt(WFJ, false)
        local plain = option("", "Rare") -- no rarity: the description alone, even a dictionary-like word, stays
        plain:SetupOptionText()
        assert.are.equal("Rare", plain.OptionText.html:GetText())
      end },
  },
  name = function(frame, WFJ)
    frame:Hide()
    local button = _G.CypherPlayerChoiceToggleButton
    button:UpdateButtonState("Choose Your Fate") -- the choice's pending text from the server
    assert.are.equal("Choose Your Fate", button.Text:GetText())
    assert.is_true(R.unrecorded(WFJ, button.Text))
    frame.Title.text = "Hide"
    frame:Show()
    assert.are.equal("Hide", frame.Title:GetText())
    assert.is_true(R.unrecorded(WFJ, frame.Title))
  end,
  wrong = function(frame)
    frame.GridNoSelectionDescription = Stub
    _G.CypherPlayerChoiceToggleButton = "x"
    return function(f)
      f:Show()
      assert.are.equal("どの物語を聞きたい？", f.GridNoSelectionHeader:GetText())
      _G.GenericPlayerChoiceToggleButton:UpdateButtonState()
      assert.are.equal("隠す", _G.GenericPlayerChoiceToggleButton.Text:GetText())
    end
  end,
})
