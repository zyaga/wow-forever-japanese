-- UI/StackSplit.lua over StackSplitFrame as camelot blizzard_framexml/camelot/stacksplitframe.xml:15–65
-- and mainline/stacksplitframe.lua:29–62, 92–99 build and write it.
local Stub = require("tests.lua.spec.wow_stub")
local X = require("tests.lua.spec.stub_framexml_hud")

local UI = { OKAY = { "Okay", "OK" }, CANCEL = { "Cancel", "キャンセル" },
  STACKS = { "%d |4Stack:Stacks;", "%dスタック" }, TOTAL_STACKS = { "%d Total", "合計 %d" } }
local NAMES = { "StackSplitFrame" }

local function install()
  local f = CreateFrame("Frame", "StackSplitFrame")
  f.OkayButton, f.CancelButton = Stub.button(nil, "Okay"), Stub.button(nil, "Cancel")
  f.StackSplitText, f.StackItemCountText = Stub.fontString(""), Stub.fontString("")
  f.split, f.minSplit, f.isMultiStack = 1, 1, false
  function f.UpdateStackText(self)
    if self.isMultiStack then
      local n = self.split / self.minSplit
      self.StackSplitText.text = ("%d %s"):format(n, n == 1 and "Stack" or "Stacks")
      self.StackItemCountText.text = ("%d Total"):format(self.split)
    else
      self.StackSplitText.text = tostring(self.split)
    end
  end
  function f.ChooseFrameType(self, amount)
    self.isMultiStack = amount ~= 1
    self:UpdateStackText()
  end
end

describe("the stack split box on Forever", function()
  local WFJ
  before_each(function()
    WFJ = X.load("UI/StackSplit.lua", UI, { before = install })
    assert.is_true(WFJ.StackSplit.init())
  end)
  after_each(function() X.teardown(NAMES) end)

  it("the buttons translate on show; a bare count is left alone", function()
    local f = _G.StackSplitFrame
    f.split = 7
    f:ChooseFrameType(1)
    f:Show()
    assert.are.equal("OK", f.OkayButton:GetText())
    assert.are.equal("キャンセル", f.CancelButton:GetText())
    assert.are.equal("7", f.StackSplitText:GetText())
    assert.is_true(X.unrecorded(WFJ, f.StackSplitText))
  end)

  it("a merchant multi-stack purchase translates both lines after each writer, singular and plural", function()
    local f = _G.StackSplitFrame
    f.split, f.minSplit = 20, 20
    f:ChooseFrameType(20)
    assert.are.equal("1スタック", f.StackSplitText:GetText())
    assert.are.equal("合計 20", f.StackItemCountText:GetText())
    f.split = 60
    f:UpdateStackText()
    assert.are.equal("3スタック", f.StackSplitText:GetText())
    X.alt(WFJ, true)
    assert.are.equal("3 Stacks", f.StackSplitText:GetText())
    X.alt(WFJ, false)
  end)

  it("hooks once; wrong types and a missing frame leave English and raise nothing", function()
    assert.is_false(WFJ.StackSplit.init())
    assert.are.equal(1, #Stub.hooks["StackSplitFrame:UpdateStackText"])
    X.teardown(NAMES)
    local wrong = X.load("UI/StackSplit.lua", UI, { before = function()
      install()
      _G.StackSplitFrame.OkayButton = "x"
      _G.StackSplitFrame.UpdateStackText = 3
    end })
    assert.has_no.errors(function() assert.is_true(wrong.StackSplit.init()) end)
    assert.are.equal("キャンセル", _G.StackSplitFrame.CancelButton:GetText())
    X.teardown(NAMES)
    local none = X.load("UI/StackSplit.lua", UI, { before = function() _G.StackSplitFrame = 1 end })
    assert.is_false(none.StackSplit.init())
  end)
end)
