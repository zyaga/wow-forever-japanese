-- UI/Cinematic.lua over MovieFrame.CloseDialog and
-- CinematicFrameCloseDialog replayed from camelot blizzard_framexml/movieframe.xml (:12–65) and
-- shared/cinematicframe.xml (:35–62). The cinematic's own summary line stays as the client wrote it.
local Stub = require("tests.lua.spec.wow_stub")
local R = require("tests.lua.spec.stub_retail")

local UI = {
  CONFIRM_CLOSE_CINEMATIC = { "Are you sure you want to cancel this cinematic?", "このムービーをキャンセルしますか？" },
  YES = { "Yes", "はい" }, NO = { "No", "いいえ" },
}
local GLOBALS = { "MovieFrame", "CinematicFrameCloseDialog", "CinematicFrameCloseDialogText",
  "CinematicFrameCloseDialogConfirmButton", "CinematicFrameCloseDialogResumeButton" }

local function build()
  local movie = CreateFrame("Frame", "MovieFrame")
  R.tree(movie, { ["CloseDialog.Title"] = _G.CONFIRM_CLOSE_CINEMATIC, ["CloseDialog.Summary"] = "",
    ["CloseDialog.Buttons.ConfirmButton"] = { button = _G.YES },
    ["CloseDialog.Buttons.ResumeButton"] = { button = _G.NO } })
  CreateFrame("Frame", "CinematicFrameCloseDialog")
  Stub.namedFontString("CinematicFrameCloseDialogText", _G.CONFIRM_CLOSE_CINEMATIC)
  _G.CinematicFrameCloseDialogConfirmButton = Stub.button(nil, _G.YES)
  _G.CinematicFrameCloseDialogResumeButton = Stub.button(nil, _G.NO)
  return movie
end

R.suite(getfenv(1), {
  title = "the cinematic close dialogs on Forever", module = "Cinematic", file = "UI/Cinematic.lua",
  root = "MovieFrame", globals = GLOBALS, ui = UI, build = build,
  cases = {
    { "both dialogs are Japanese when shown; Alt shows English", function(frame, WFJ)
      frame.CloseDialog:Show()
      assert.are.equal("このムービーをキャンセルしますか？", frame.CloseDialog.Title:GetText())
      assert.are.equal("はい", frame.CloseDialog.Buttons.ConfirmButton:GetText())
      assert.are.equal("いいえ", frame.CloseDialog.Buttons.ResumeButton:GetText())
      _G.CinematicFrameCloseDialog:Show()
      assert.are.equal("このムービーをキャンセルしますか？", _G.CinematicFrameCloseDialogText:GetText())
      assert.are.equal("はい", _G.CinematicFrameCloseDialogConfirmButton:GetText())
      R.alt(WFJ, true)
      assert.are.equal("No", _G.CinematicFrameCloseDialogResumeButton:GetText())
      R.alt(WFJ, false)
    end },
  },
  name = function(frame, WFJ)
    frame.CloseDialog.Summary.text = "Yes" -- the cinematic's summary, whatever it says
    frame.CloseDialog:Show()
    assert.are.equal("Yes", frame.CloseDialog.Summary:GetText())
    assert.is_true(R.unrecorded(WFJ, frame.CloseDialog.Summary))
  end,
  wrong = function(frame)
    frame.CloseDialog.Buttons = 9
    _G.CinematicFrameCloseDialogText = "x"
    return function(f)
      f.CloseDialog:Show()
      assert.are.equal("このムービーをキャンセルしますか？", f.CloseDialog.Title:GetText())
      assert.are.equal("はい", _G.CinematicFrameCloseDialogConfirmButton:GetText())
    end
  end,
})
