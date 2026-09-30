-- UI/LossOfControl.lua over a LossOfControlFrame replayed from
-- camelot blizzard_framexml/lossofcontrolframe.xml (:4–91) and LossOfControlMixin:SetUpDisplay (.lua:142–207).
local Stub = require("tests.lua.spec.wow_stub")
local R = require("tests.lua.spec.stub_retail")

local UI = {
  LOSS_OF_CONTROL_DISPLAY_STUN = { "Stunned", "スタン" }, LOSS_OF_CONTROL_DISPLAY_FEAR = { "Feared", "恐怖" },
  LOSS_OF_CONTROL_DISPLAY_INTERRUPT_SCHOOL = { "%s Locked", "%s封印" },
  LOSS_OF_CONTROL_SECONDS = { "seconds", "秒" }, SPELL_SCHOOL2_CAP = { "Fire", "火炎" },
  -- "Disabled" owns its Japanese here; the settings word keeps 無効
  LOSS_OF_CONTROL_DISPLAY_PACIFYSILENCE = { "Disabled", "行動不能" }, ADDON_DISABLED = { "Disabled", "無効" },
}
local GLOBALS = { "LossOfControlFrame" }

local function build()
  local frame = CreateFrame("Frame", "LossOfControlFrame")
  R.tree(frame, { AbilityName = "", ["TimeLeft.NumberText"] = "8.8",
    ["TimeLeft.SecondsText"] = _G.LOSS_OF_CONTROL_SECONDS })
  function frame.SetUpDisplay(self, _, data) -- lua:142–167
    self.AbilityName.text = data.text
    self.TimeLeft.NumberText.text = data.time
    self:Show()
  end
  return frame
end

R.suite(getfenv(1), {
  title = "the loss-of-control alert on Forever", module = "LossOfControl", file = "UI/LossOfControl.lua",
  root = "LossOfControlFrame", globals = GLOBALS, ui = UI, build = build,
  args = { LOSS_OF_CONTROL_DISPLAY_INTERRUPT_SCHOOL = { [1] = "word" } },
  cases = {
    { "the effect and 'seconds' are Japanese after each SetUpDisplay; Alt shows English", function(frame, WFJ)
      frame:SetUpDisplay(true, { text = "Stunned", time = "3.2" })
      assert.are.equal("スタン", frame.AbilityName:GetText())
      assert.are.equal("秒", frame.TimeLeft.SecondsText:GetText())
      frame:SetUpDisplay(true, { text = "Feared", time = "2" })
      assert.are.equal("恐怖", frame.AbilityName:GetText())
      frame:SetUpDisplay(true, { text = "Fire Locked", time = "4" })
      assert.are.equal("火炎封印", frame.AbilityName:GetText())
      R.alt(WFJ, true)
      assert.are.equal("Fire Locked", frame.AbilityName:GetText())
      R.alt(WFJ, false)
    end },
    { "'Disabled' shows its own word, while the shared English keeps the other key's", function(frame, WFJ)
      frame:SetUpDisplay(true, { text = "Disabled", time = "2" })
      assert.are.equal("行動不能", frame.AbilityName:GetText())
      assert.are.equal("ADDON_DISABLED", (WFJ.UIIndex:match("Disabled")))
      assert.are.equal(0, WFJ.UIIndex.counts.ambiguous)
    end },
  },
  name = function(frame, WFJ)
    frame:SetUpDisplay(true, { text = "Hammer of Justice", time = "Stunned" }) -- a spell's own text, a number field
    assert.are.equal("Hammer of Justice", frame.AbilityName:GetText())
    assert.are.equal("Stunned", frame.TimeLeft.NumberText:GetText())
    assert.is_true(R.unrecorded(WFJ, frame.TimeLeft.NumberText))
    frame:SetUpDisplay(true, { text = "Fire", time = "1" }) -- a dictionary word that is not an alert word
    assert.are.equal("Fire", frame.AbilityName:GetText())
  end,
  wrong = function(frame)
    frame.TimeLeft.SecondsText = Stub -- a table that is no widget
    return function(f)
      f:SetUpDisplay(true, { text = "Stunned", time = "1" })
      assert.are.equal("スタン", f.AbilityName:GetText())
    end
  end,
})
