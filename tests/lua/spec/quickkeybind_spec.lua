-- Quick keybind mode on Forever: UI/QuickKeybind.lua over a QuickKeybindFrame and QuickKeybindTooltip
-- replayed from blizzard_quickkeybind (quickkeybind.xml:18–89, quickkeybind.lua:51–72, 106–124, 226–245).
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local S = require("tests.lua.spec.stub_settings")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
for _, f in ipairs({ "UI/LabelTree.lua", "UI/TooltipLines.lua", "UI/SettingsKeys.lua", "UI/QuickKeybind.lua" }) do
  FILES[#FILES + 1] = f
end

local UI = {
  QUICK_KEYBIND_MODE = { "Quick Keybind Mode", "クイックキー割り当てモード" },
  QUICK_KEYBIND_DESCRIPTION = { "You are in Quick Keybind Mode. Mouse over a button and press the desired key to set "
    .. "the binding for that button.", "クイックキー割り当てモードです。ボタンにマウスを重ねてキーを押すと割り当てられます。" },
  RESET_TO_DEFAULT = { "Reset To Default", "デフォルトに戻す" }, OKAY = { "Okay", "OK" },
  CHARACTER_SPECIFIC_KEYBINDINGS = { "Character Specific Keybindings", "キャラクター別のキー割り当て" },
  KEY_BOUND = { "Key Bound Successfully", "キーを割り当てました" }, NOT_BOUND = { "Not Bound", "未割り当て" },
  PRESS_KEY_TO_BIND = { "Press a key to set the binding for this action.", "キーを押すとこのアクションに割り当てます。" },
  BINDING_NAME_ACTIONBUTTON1 = { "Action Button 1", "アクションボタン1" },
  KEY_SPACE = { "Space", "スペース" }, -- a key name: in the dictionary, never one of this window's keys
}

describe("quick keybind mode on Forever", function()
  local WFJ, frame

  local function load()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
  end

  before_each(function()
    load()
    frame = S.installQuickKeybind()
    assert.is_true(WFJ.QuickKeybind.init())
  end)

  after_each(function()
    H.uiTeardown()
    S.removeQuickKeybind()
  end)

  it("the labels and buttons translate; the colour-wrapped checkbox label is a composite and stays", function()
    assert.are.equal("クイックキー割り当てモード", frame.Header.Text:GetText())
    assert.are.equal(UI.QUICK_KEYBIND_DESCRIPTION[2], frame.InstructionText:GetText())
    assert.are.equal("デフォルトに戻す", frame.DefaultsButton:GetText())
    assert.are.equal("OK", frame.OkayButton:GetText())
    assert.are.equal("|cffffffffCharacter Specific Keybindings|r", frame.UseCharacterBindingsButton.Text:GetText())
  end)

  it("the output line follows SetOutputText", function()
    frame:SetOutputText("Key Bound Successfully")
    assert.are.equal("キーを割り当てました", frame.OutputText:GetText())
  end)

  it("QuickKeybindTooltip: the binding's name and the hints translate; the bound key's name stays", function()
    local tt = _G.QuickKeybindTooltip
    tt:SetOwner(frame)
    tt:ClearLines()
    local lines = { "Action Button 1", "Space", "Not Bound", "Press a key to set the binding for this action." }
    for _, line in ipairs(lines) do
      tt:AddLine(line)
    end
    tt:Show()
    assert.are.equal("アクションボタン1", _G.QuickKeybindTooltipTextLeft1:GetText())
    assert.are.equal("Space", _G.QuickKeybindTooltipTextLeft2:GetText())
    assert.are.equal("未割り当て", _G.QuickKeybindTooltipTextLeft3:GetText())
    assert.are.equal("キーを押すとこのアクションに割り当てます。", _G.QuickKeybindTooltipTextLeft4:GetText())
    tt:Hide()
    assert.are.equal(0, WFJ.SurfaceState.count("quickkeybind.tooltip"))
  end)

  it("wrong-typed client names degrade with no error; a client without the frame is skipped", function()
    assert.has_no.errors(function()
      for _, bad in ipairs({ 42, "text", true }) do
        frame.Header, frame.InstructionText = bad, bad
        frame:Show()
        _G.QuickKeybindTooltip.GetName = function() return bad end
        _G.QuickKeybindTooltip:Show()
        WFJ.QuickKeybind.onOutput()
      end
    end)
    assert.is_false(WFJ.QuickKeybind.init())
    load()
    S.removeQuickKeybind()
    assert.has_no.errors(function() assert.is_false(WFJ.QuickKeybind.init()) end)
  end)
end)
