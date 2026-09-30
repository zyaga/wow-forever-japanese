-- UI/InstanceAbandon.lua over an InstanceAbandonFrame replayed from
-- camelot blizzard_framexml/mainline/instanceabandon.xml (:21–48) and .lua (OnShow :74–84, Refresh :120–149).
local Stub = require("tests.lua.spec.wow_stub")
local R = require("tests.lua.spec.stub_retail")

local UI = {
  VOTE_TO_ABANDON_VOTES_NEEDED = { "%d votes needed to abandon the instance.", "インスタンス放棄には%d票が必要です。" },
  VOTE_TO_ABANDON_VOTED_YES = { "You voted Yes", "賛成に投票しました" },
  VOTE_TO_ABANDON_VOTED_NO = { "You voted No", "反対に投票しました" },
}
local GLOBALS = { "InstanceAbandonFrame" }

local function build()
  local frame = CreateFrame("Frame", "InstanceAbandonFrame")
  R.tree(frame, { VoteText = "", ResponseText = "" })
  frame:SetScript("OnShow", function(self) -- InstanceAbandonMixin:OnShow
    self.VoteText.text = string.format(_G.VOTE_TO_ABANDON_VOTES_NEEDED, 3)
    self:Refresh()
  end)
  function frame.Refresh(self)
    self.ResponseText.text = self.response == nil and "" or (self.response and _G.VOTE_TO_ABANDON_VOTED_YES
      or _G.VOTE_TO_ABANDON_VOTED_NO)
  end
  return frame
end

R.suite(getfenv(1), {
  title = "the vote-to-abandon panel on Forever", module = "InstanceAbandon",
  file = "UI/InstanceAbandon.lua", root = "InstanceAbandonFrame", globals = GLOBALS, ui = UI, build = build,
  cases = {
    { "the vote count and the response are Japanese; Alt shows English", function(frame, WFJ)
      frame:Show()
      assert.are.equal("インスタンス放棄には3票が必要です。", frame.VoteText:GetText())
      frame.response = true
      frame:Refresh()
      assert.are.equal("賛成に投票しました", frame.ResponseText:GetText())
      frame.response = false
      frame:Refresh()
      assert.are.equal("反対に投票しました", frame.ResponseText:GetText())
      R.alt(WFJ, true)
      assert.are.equal("You voted No", frame.ResponseText:GetText())
      R.alt(WFJ, false)
    end },
  },
  name = function(frame, WFJ)
    frame:Show()
    frame.ResponseText.text = "Deadmines" -- anything else written there stays as written
    frame.response = nil
    frame:Refresh()
    assert.are.equal("", frame.ResponseText:GetText())
    assert.is_true(R.unrecorded(WFJ, frame.ResponseText))
  end,
  wrong = function(frame)
    frame.ResponseText = Stub
    frame.Refresh = function() end
    return function(f)
      f:Show()
      assert.are.equal("インスタンス放棄には3票が必要です。", f.VoteText:GetText())
    end
  end,
})
