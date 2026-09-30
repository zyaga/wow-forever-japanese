-- UI/EditMode.lua over frames replayed from blizzard_editmode/shared
-- (editmodemanager.xml:4–560, editmodemanager.lua:24–32, 2916–2918; editmodedialogs.lua:231–258, 537–660;
-- editmodesystemtemplates.lua:3331–3346). A layout's name stays as the player wrote it.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local S = require("tests.lua.spec.stub_settings")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
for _, f in ipairs({ "UI/LabelTree.lua", "UI/TooltipLines.lua", "UI/SettingsKeys.lua", "UI/EditMode.lua" }) do
  FILES[#FILES + 1] = f
end

-- Forever GlobalStrings (build 1.60.1.69913) → a test Japanese
local UI = {
  HUD_EDIT_MODE_TITLE = { "HUD Edit Mode", "HUD編集モード" }, HUD_EDIT_MODE_LAYOUT = { "Layout:", "レイアウト:" },
  HUD_EDIT_MODE_SHOW_GRID = { "Show Grid", "グリッドを表示" },
  HUD_EDIT_MODE_EXPAND_OPTIONS = { "Expand Options |A:editmode-down-arrow:16:11:0:3|a",
    "オプションを展開 |A:editmode-down-arrow:16:11:0:3|a" },
  HUD_EDIT_MODE_COLLAPSE_OPTIONS = { "Collapse Options |A:editmode-up-arrow:16:11:0:3|a",
    "オプションを折りたたむ |A:editmode-up-arrow:16:11:0:3|a" },
  HUD_EDIT_MODE_SAVE_LAYOUT = { "Save", "保存" }, HUD_EDIT_MODE_REVERT_CHANGES = { "Revert Changes", "変更を元に戻す" },
  HUD_EDIT_MODE_INSTRUCTIONS_CLICK_TO_EDIT = { "Click to Edit", "クリックして編集" },
  HUD_EDIT_MODE_MINIMAP_LABEL = { "Minimap", "ミニマップ" },
  HUD_EDIT_MODE_SETTING_MINIMAP_HEADER_UNDERNEATH = { "Header Underneath", "ヘッダーを下に配置" },
  HUD_EDIT_MODE_SETTING_AURA_FRAME_ICON_DIRECTION_LEFT = { "Left", "左" },
  HUD_EDIT_MODE_SETTING_AURA_FRAME_ICON_DIRECTION_RIGHT = { "Right", "右" },
  HUD_EDIT_MODE_NAME_LAYOUT_DIALOG_TITLE = { "Name the New Layout", "新しいレイアウトの名前" },
  -- the %s is a layout's name: Core/UIStrings.ARGS names it `text`, so it is kept exactly as written
  HUD_EDIT_MODE_RENAME_LAYOUT_DIALOG_TITLE = { "Enter New Name for Layout %s", "レイアウト%sの新しい名前を入力" },
  SAVE = { "Save", "保存" },
  LAYOUT_WORD = { "Layout", "配置" }, -- in the dictionary, never an Edit Mode key: a layout the player called "Layout"
}

describe("HUD Edit Mode on Forever", function()
  local WFJ, manager, dialog, layout

  local function load()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
  end

  before_each(function()
    load()
    manager, dialog, layout = S.installEditMode()
    WFJ.Labels.forbidNames(WFJ.EditMode.NEVER_TOUCH)
    assert.is_true(WFJ.EditMode.init())
  end)

  after_each(function()
    H.uiTeardown()
    S.removeEditMode()
  end)

  it("the manager's labels translate at load; the layout dropdown holds a name and is never touched", function()
    assert.are.equal("HUD編集モード", manager.Title:GetText())
    assert.are.equal("レイアウト:", manager.LayoutLabel:GetText())
    assert.are.equal("グリッドを表示", manager.ShowGridCheckButton.Label:GetText())
    assert.are.equal("保存", manager.SaveChangesButton:GetText())
    assert.are.equal("Layout", manager.LayoutDropdown.Text:GetText())
    manager.LayoutDropdown:select("Layout")
    assert.are.equal("Layout", manager.LayoutDropdown.Text:GetText())
    assert.is_nil(Stub.hooks["?:UpdateText"]) -- not followed either
  end)

  it("SetExpandedState re-walks the window; the expander's |A-carrying label stays English", function()
    manager.ShowGridCheckButton.Label.text = _G.HUD_EDIT_MODE_SHOW_GRID -- the client rewrote a label
    manager.AccountSettings:SetExpandedState(true)
    assert.are.equal(UI.HUD_EDIT_MODE_COLLAPSE_OPTIONS[1], manager.AccountSettings.Expander.Label:GetText())
    assert.are.equal("グリッドを表示", manager.ShowGridCheckButton.Label:GetText())
    manager.AccountSettings:SetExpandedState(false)
    assert.are.equal(UI.HUD_EDIT_MODE_EXPAND_OPTIONS[1], manager.AccountSettings.Expander.Label:GetText())
  end)

  it("the system settings dialog: title, pooled setting names and dropdown values, re-used for another system",
    function()
      dialog:AttachToSystemFrame("Minimap", { { "Header Underneath", "Left" } })
      assert.are.equal("ミニマップ", dialog.Title:GetText())
      assert.are.equal("ヘッダーを下に配置", dialog.pool[1].Label:GetText())
      assert.are.equal("左", dialog.pool[1].Dropdown.Text:GetText())
      dialog.pool[1].Dropdown:select("Right")
      assert.are.equal("右", dialog.pool[1].Dropdown.Text:GetText())
      assert.are.equal("変更を元に戻す", dialog.Buttons.RevertChangesButton:GetText())
      dialog:AttachToSystemFrame("Some Addon Frame", { { "Layout", "Custom Value" } })
      assert.are.equal("Some Addon Frame", dialog.Title:GetText())
      assert.are.equal("Layout", dialog.pool[1].Label:GetText())
      assert.are.equal("Custom Value", dialog.pool[1].Dropdown.Text:GetText())
    end)

  it("selection overlays are hooked once when the manager shows; the label follows hover and selection", function()
    local system = S.system(manager, "Minimap")
    manager:Show()
    manager:Show()
    assert.are.equal(1, #Stub.hooks["?:UpdateLabelVisibility"])
    system.Selection:UpdateLabelVisibility()
    assert.are.equal("クリックして編集", system.Selection.Label:GetText())
    system.Selection.selected = true
    system.Selection:UpdateLabelVisibility()
    assert.are.equal("ミニマップ", system.Selection.Label:GetText())
    assert.is_true(WFJ.HelpTooltip.registered(system.Selection))
  end)

  it("a selection another surface already registered keeps its own keys (the cooldown viewers)",
    function()
    local system = S.system(manager, "Minimap")
    local theirs = { only = { "HUD_EDIT_MODE_SYSTEM_ESSENTIAL_COOLDOWNS" } }
    local calls = {}
    local register = WFJ.HelpTooltip.register
    WFJ.HelpTooltip.register = function(owner, opts)
      calls[#calls + 1] = opts
      return register(owner, opts)
    end
    WFJ.HelpTooltip.register(system.Selection, theirs) -- UI/CooldownViewer's registration comes first
    manager:Show()
    WFJ.HelpTooltip.register = register
    assert.are.equal(1, #calls) -- Edit Mode did not register the same Selection again
    assert.are.equal(theirs, calls[1])
  end)

  it("a layout dialog: title and button translate on show; a layout's name inside a title is kept; no EditBox entered",
    function()
    layout:ShowMode(_G.HUD_EDIT_MODE_NAME_LAYOUT_DIALOG_TITLE, "Layout")
    assert.are.equal("新しいレイアウトの名前", layout.Title:GetText())
    layout:Hide()
    layout:ShowMode(string.format(_G.HUD_EDIT_MODE_RENAME_LAYOUT_DIALOG_TITLE, "Layout"), "Layout")
    -- HUD_EDIT_MODE_RENAME_LAYOUT_DIALOG_TITLE's %s is a name (UIStrings.ARGS text): kept exactly as written
    assert.are.equal("レイアウトLayoutの新しい名前を入力", layout.Title:GetText())
    assert.are.equal("保存", layout.AcceptButton:GetText())
    assert.are.equal("Layout", layout.LayoutNameEditBox:GetText())
  end)

  it("wrong-typed client names degrade with no error; a client without Edit Mode is skipped", function()
    assert.has_no.errors(function()
      for _, bad in ipairs({ 42, "text", true }) do
        manager.registeredSystemFrames = { bad, { Selection = bad }, { Selection = { UpdateLabelVisibility = bad } } }
        manager.Title = bad
        manager:Show()
        manager.registeredSystemFrames = bad
        manager:Show()
        dialog.Title = bad
        dialog:UpdateSettings()
      end
    end)
    assert.is_false(WFJ.EditMode.init()) -- hooks install once
    load()
    S.removeEditMode()
    assert.has_no.errors(function() assert.is_false(WFJ.EditMode.init()) end)
  end)
end)
