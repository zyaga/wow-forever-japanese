-- UI/GamepadEdit.lua over a GamepadActionBarEditFrame replayed from camelot's
-- blizzard_gamepadactionbars/actionbareditframe.xml:3–110 / .lua:216, 985–990. The action being bound is a name and
-- stays English. Client writes go to `fs.text`.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/GamepadEdit.lua"

-- Forever GlobalStrings (build 1.60.1.69913) → a test Japanese
local UI = {
  GAMEPAD_EDIT_FRAME_BIND_INFO_FRAME_TITLE = { "Bind to Action Bar", "アクションバーに割り当て" },
  GAMEPAD_EDIT_FRAME_BIND_INFO_FRAME_BIND_INSTRUCTION = { "Press the button combination you want to use for:",
    "割り当てたいボタンの組み合わせを押してください:" },
  GAMEPAD_EDIT_FRAME_EDIT_ACTION_BARS_INFO_FRAME_TITLE = { "Edit Action Bars", "アクションバーの編集" },
  GAMEPAD_EDIT_FRAME_EDIT_ACTION_BARS_INFO_FRAME_PICKUP_INSTRUCTION = {
    "Press the button combination you want to change.", "変更したいボタンの組み合わせを押してください。" },
}

local function installEditFrame()
  local frame = CreateFrame("Frame", "GamepadActionBarEditFrame")
  frame.BindingInfoFrame = {
    TitleBox = { TitleText = Stub.fontString(UI.GAMEPAD_EDIT_FRAME_BIND_INFO_FRAME_TITLE[1]) },
    BindInstructionText = Stub.fontString(UI.GAMEPAD_EDIT_FRAME_BIND_INFO_FRAME_BIND_INSTRUCTION[1]),
    ActionName = Stub.fontString(""),
  }
  frame.EditActionBarsInfoFrame = {
    TitleBox = { TitleText = Stub.fontString(UI.GAMEPAD_EDIT_FRAME_EDIT_ACTION_BARS_INFO_FRAME_TITLE[1]) },
    PickupInstructionText = Stub.fontString(UI.GAMEPAD_EDIT_FRAME_EDIT_ACTION_BARS_INFO_FRAME_PICKUP_INSTRUCTION[1]),
  }
  return frame
end

describe("the gamepad action-bar edit window on Forever", function()
  local WFJ

  local function setup(install)
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    if install then install() end
    WFJ.Labels.forbidNames(WFJ.GamepadEdit.NEVER_TOUCH)
  end

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    _G.GamepadActionBarEditFrame = nil
  end)

  it("the four labels render Japanese; Alt shows English; the action's name is never taken", function()
    setup(installEditFrame)
    assert.is_true(WFJ.GamepadEdit.init())
    local frame = _G.GamepadActionBarEditFrame
    assert.are.equal("アクションバーに割り当て", frame.BindingInfoFrame.TitleBox.TitleText:GetText())
    assert.are.equal("割り当てたいボタンの組み合わせを押してください:", frame.BindingInfoFrame.BindInstructionText:GetText())
    assert.are.equal("アクションバーの編集", frame.EditActionBarsInfoFrame.TitleBox.TitleText:GetText())
    assert.are.equal("変更したいボタンの組み合わせを押してください。",
      frame.EditActionBarsInfoFrame.PickupInstructionText:GetText())
    Stub.keys.alt = true
    WFJ.Modifier.refresh()
    assert.are.equal("Edit Action Bars", frame.EditActionBarsInfoFrame.TitleBox.TitleText:GetText())
    Stub.keys.alt = false
    WFJ.Modifier.refresh()
    -- a macro the player named exactly like a dictionary entry
    frame.BindingInfoFrame.ActionName.text = "Edit Action Bars"
    frame:Show()
    assert.are.equal("Edit Action Bars", frame.BindingInfoFrame.ActionName:GetText())
    assert.are.equal(0, WFJ.Labels.show("gamepadedit", "x", frame.BindingInfoFrame.ActionName))
  end)

  it("client names bound to the wrong type degrade to English with no error", function()
    setup(function()
      local frame = installEditFrame()
      frame.BindingInfoFrame.TitleBox = "moved"
      frame.EditActionBarsInfoFrame = 4
    end)
    assert.has_no.errors(function() assert.is_true(WFJ.GamepadEdit.init()) end)
    assert.are.equal("割り当てたいボタンの組み合わせを押してください:",
      _G.GamepadActionBarEditFrame.BindingInfoFrame.BindInstructionText:GetText())
  end)

  it("init runs once; without the frame it returns false", function()
    setup(installEditFrame)
    assert.is_true(WFJ.GamepadEdit.init())
    assert.is_false(WFJ.GamepadEdit.init())
    _G.GamepadActionBarEditFrame = nil
    setup(nil)
    assert.has_no.errors(function() assert.is_false(WFJ.GamepadEdit.init()) end)
  end)
end)
