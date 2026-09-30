-- Camelot-shaped stubs for the settings family: the Options window (SettingsPanel, its two ScrollBoxes and
-- SettingsTooltip), Edit Mode, quick keybind mode and the colour picker. Frames are wow_stub CreateFrame frames with a
-- child list (GetChildren / GetParent), so UI/LabelTree.lua walks them as it walks the client's. Client writes go to
-- `fs.text` (not counted as ours).
local Stub = require("tests.lua.spec.wow_stub")
local S = {}

-- A frame that knows its children. `key` (optional) is the parentKey on `parent`.
function S.node(kind, name, parent, key)
  local f = CreateFrame(kind or "Frame", name)
  f.kids = {}
  function f:GetChildren() return unpack(self.kids) end
  function f:GetParent() return self.parent end
  if parent then
    f.parent = parent
    parent.kids[#parent.kids + 1] = f
    if key then parent[key] = f end
  end
  return f
end

-- A FontString region of `frame` under parentKey `key`.
function S.label(frame, key, text)
  local fs = frame:addRegion(Stub.fontString(text or ""))
  if key then frame[key] = fs end
  return fs
end

-- A template button (its own text region) as a child.
function S.button(parent, key, text, name)
  local b = Stub.button(name, text)
  b.kids = {}
  function b:GetChildren() return unpack(self.kids) end
  function b:GetParent() return self.parent end
  b.parent = parent
  parent.kids[#parent.kids + 1] = b
  if key then parent[key] = b end
  return b
end

-- A Menu dropdown button: `Text` plus the UpdateText writer the Menu system calls on every selection.
function S.dropdown(parent, key, text)
  local d = S.node("DropdownButton", nil, parent, key)
  S.label(d, "Text", text)
  d.selection = text
  function d:UpdateText() self.Text.text = self.selection end
  function d:select(value) self.selection = value; self:UpdateText() end
  return d
end

function S.editBox(parent, key, text, name)
  local e = S.node("EditBox", name, parent, key)
  e.text = text or ""
  function e:HasText() return (self.text or "") ~= "" end
  S.label(e, "Instructions", "")
  return e
end

-- ── the Options window ────────────────────────────────────────────────────────────────────────────────────────
S.GAME, S.ADDONS = 1, 2

function S.category(name, set)
  return { name = name, GetName = function(self) return self.name end,
    GetCategorySet = function() return set or S.GAME end }
end

-- Row builders: each returns a frame the list's initializer has just filled (blizzard_settingcontrols.lua).
function S.checkboxRow(label)
  local row = S.node("Frame")
  S.label(row, "Text", label)
  S.node("CheckButton", nil, row, "Checkbox")
  S.node("Frame", nil, row, "Tooltip")
  return row
end

function S.dropdownRow(label, value)
  local row = S.checkboxRow(label)
  local control = S.node("Frame", nil, row, "Control")
  S.dropdown(control, "Dropdown", value)
  return row
end

function S.sliderRow(label, valueText)
  local row = S.checkboxRow(label)
  local slider = S.node("Frame", nil, row, "SliderWithSteppers")
  slider.Slider = S.node("Slider", nil, slider)
  S.label(slider, "RightText", valueText)
  return row
end

function S.headerRow(title)
  local row = S.node("Frame")
  S.label(row, "Title", title)
  return row
end

function S.sectionRow(name) -- SettingsExpandableSectionTemplate: Button.Text is a layer FontString
  local row = S.node("EventFrame")
  local b = S.node("Button", nil, row, "Button")
  S.label(b, "Text", name)
  return row
end

function S.bindingRow(name, key1, key2) -- KeyBindingFrameBindingTemplate
  local row = S.node("Frame")
  S.label(row, "Label", name)
  row.Buttons = {}
  for i, key in ipairs({ key1 or "", key2 or "" }) do
    local b = S.button(row, "Button" .. i, key)
    b.SelectedHighlight = {}
    row.Buttons[i] = b
  end
  return row
end

function S.previewRow(unitName) -- RaidFramePreviewTemplate: a unit frame showing the player's name
  local row = S.node("Frame")
  S.label(row, nil, _G.PREVIEW or "Preview")
  local unit = S.node("Button", nil, row, "RaidFrame")
  S.label(unit, "name", unitName)
  return row
end

function S.categoryRow(name)
  local row = S.node("Button")
  S.label(row, "Label", name)
  return row
end

function S.installSettingsPanel()
  Stub.installScrollUtil()
  _G.Settings = _G.Settings or {}
  _G.Settings.CategorySet = { Game = S.GAME, AddOns = S.ADDONS }
  local panel = S.node("Frame", "SettingsPanel")
  panel.NineSlice = S.node("Frame", nil, panel)
  S.label(panel.NineSlice, "Text", _G.SETTINGS_TITLE)
  S.button(panel, "CloseButton", _G.SETTINGS_CLOSE)
  S.button(panel, "ApplyButton", _G.SETTINGS_APPLY)
  for key, text in pairs({ GameTab = _G.SETTINGS_TAB_GAME, AddOnsTab = _G.SETTINGS_TAB_ADDONS }) do
    local tab = S.node("Button", nil, panel, key)
    S.label(tab, "Text", text)
  end
  S.label(panel, "OutputText", "")
  S.editBox(panel, "SearchBox", "")
  local categories = S.node("Frame", nil, panel, "CategoryList")
  categories.ScrollBox = Stub.scrollBox()
  local container = S.node("Frame", nil, panel, "Container")
  local list = S.node("Frame", nil, container, "SettingsList")
  local header = S.node("Frame", nil, list, "Header")
  S.label(header, "Title", "")
  S.button(header, "DefaultsButton", _G.SETTINGS_DEFAULTS)
  list.ScrollBox = Stub.scrollBox()
  panel.category = S.category("Graphics")
  function panel:GetCurrentCategory() return self.category end
  function panel.DisplayLayout() end
  -- DisplayCategory writes the header title, then DisplayLayout (blizzard_settingspanel.lua:875–905)
  function panel:DisplayCategory(category)
    self.category = category
    header.Title.text = category:GetName()
    self:DisplayLayout()
  end
  function panel:SetOutputText(text) self.OutputText.text = text end
  panel:SetScript("OnShow", function(self) self.NineSlice.Text.text = _G.SETTINGS_TITLE end)
  Stub.tooltipFrame("SettingsTooltip")
  return panel
end

-- DefaultTooltipMixin:OnEnter for an option: SetOwner, the name and body lines, Show.
function S.optionTooltip(owner, lines)
  local tt = _G.SettingsTooltip
  tt:SetOwner(owner)
  tt:ClearLines()
  for _, line in ipairs(lines) do tt:AddLine(line) end
  tt:Show()
end

function S.removeSettingsPanel()
  _G.SettingsPanel, _G.SettingsTooltip = nil, nil
  for i = 1, 12 do _G["SettingsTooltipTextLeft" .. i], _G["SettingsTooltipTextRight" .. i] = nil, nil end
  if _G.Settings then _G.Settings.CategorySet = nil end
end

-- ── Edit Mode ─────────────────────────────────────────────────────────────────────────────────────────────────
-- A HUD system with its selection overlay (editmodesystemtemplates.lua:3331–3346).
function S.system(manager, name)
  local system = S.node("Frame")
  local selection = S.node("Frame", nil, system, "Selection")
  S.label(selection, "Label", "")
  selection.selected = false
  function selection:UpdateLabelVisibility()
    self.Label.text = self.selected and name or _G.HUD_EDIT_MODE_INSTRUCTIONS_CLICK_TO_EDIT
  end
  manager.registeredSystemFrames[#manager.registeredSystemFrames + 1] = system
  return system
end

function S.installEditMode()
  local m = S.node("Frame", "EditModeManagerFrame")
  m.registeredSystemFrames = {}
  S.label(m, "Title", _G.HUD_EDIT_MODE_TITLE)
  S.label(m, "LayoutLabel", _G.HUD_EDIT_MODE_LAYOUT)
  S.dropdown(m, "LayoutDropdown", "Layout") -- a layout the player named "Layout"
  local grid = S.node("Frame", nil, m, "ShowGridCheckButton")
  S.label(grid, "Label", _G.HUD_EDIT_MODE_SHOW_GRID) -- labelText (editmodemanager.xml:81)
  local account = S.node("Frame", nil, m, "AccountSettings")
  local expander = S.node("Frame", nil, account, "Expander")
  S.label(expander, "Label", _G.HUD_EDIT_MODE_EXPAND_OPTIONS)
  function account:SetExpandedState(expanded)
    self.Expander.Label.text = expanded and _G.HUD_EDIT_MODE_COLLAPSE_OPTIONS or _G.HUD_EDIT_MODE_EXPAND_OPTIONS
  end
  S.button(m, "SaveChangesButton", _G.HUD_EDIT_MODE_SAVE_LAYOUT)

  local d = S.node("Frame", "EditModeSystemSettingsDialog")
  S.label(d, "Title", "")
  local settings = S.node("Frame", nil, d, "Settings")
  local buttons = S.node("Frame", nil, d, "Buttons")
  S.button(buttons, "RevertChangesButton", _G.HUD_EDIT_MODE_REVERT_CHANGES)
  d.pool = {}
  -- UpdateSettings re-acquires pooled setting frames and fills them (editmodedialogs.lua:598–643)
  function d:UpdateSettings()
    for i, spec in ipairs(self.specs or {}) do
      local f = self.pool[i]
      if not f then
        f = S.node("Frame", nil, settings)
        S.label(f, "Label", "")
        S.dropdown(f, "Dropdown", "")
        self.pool[i] = f
      end
      f.Label.text = spec[1]
      f.Dropdown:select(spec[2])
    end
  end
  function d.UpdateExtraButtons() end
  function d:AttachToSystemFrame(name, specs)
    self.Title.text, self.specs = name, specs
    self:UpdateSettings()
    self:UpdateExtraButtons()
  end

  local layout = S.node("Frame", "EditModeLayoutDialog")
  S.label(layout, "Title", "")
  S.button(layout, "AcceptButton", "")
  S.editBox(layout, "LayoutNameEditBox", "")
  function layout:ShowMode(title, name) -- SetupControlsForMode, then StaticPopupSpecial_Show
    self.Title.text = title
    self.AcceptButton:SetText(_G.SAVE)
    self.LayoutNameEditBox.text = name
    self:Show()
  end
  return m, d, layout
end

function S.removeEditMode()
  _G.EditModeManagerFrame, _G.EditModeSystemSettingsDialog, _G.EditModeLayoutDialog = nil, nil, nil
end

-- ── quick keybind mode, the colour picker ─────────────────────────────────────────────────────────────────────
function S.installQuickKeybind()
  local f = S.node("Button", "QuickKeybindFrame")
  local header = S.node("Frame", nil, f, "Header")
  S.label(header, "Text", _G.QUICK_KEYBIND_MODE)
  S.label(f, "InstructionText", _G.QUICK_KEYBIND_DESCRIPTION)
  S.label(f, "OutputText", "")
  S.button(f, "DefaultsButton", _G.RESET_TO_DEFAULT)
  S.button(f, "OkayButton", _G.OKAY)
  local check = S.node("CheckButton", nil, f, "UseCharacterBindingsButton")
  S.label(check, "Text", "|cffffffff" .. tostring(_G.CHARACTER_SPECIFIC_KEYBINDINGS) .. "|r")
  function f:SetOutputText(text) self.OutputText.text = text end
  Stub.tooltipFrame("QuickKeybindTooltip")
  return f
end

function S.removeQuickKeybind()
  _G.QuickKeybindFrame, _G.QuickKeybindTooltip = nil, nil
  for i = 1, 8 do _G["QuickKeybindTooltipTextLeft" .. i], _G["QuickKeybindTooltipTextRight" .. i] = nil, nil end
end

function S.installColorPicker()
  local f = S.node("Frame", "ColorPickerFrame")
  local header = S.node("Frame", nil, f, "Header")
  S.label(header, "Text", _G.COLOR_PICKER)
  local content = S.node("Frame", nil, f, "Content")
  local hex = S.editBox(content, "HexBox", "ffd100")
  hex.Instructions.text = _G.COLOR_PICKER_HEX
  local footer = S.node("Frame", nil, f, "Footer")
  S.button(footer, "CancelButton", _G.CANCEL)
  S.button(footer, "OkayButton", _G.OKAY)
  local opacity = S.node("Frame", "OpacityFrame")
  local slider = S.node("Slider", "OpacityFrameSlider", opacity)
  S.label(slider, nil, _G.OPACITY)
  return f, opacity
end

function S.removeColorPicker()
  _G.ColorPickerFrame, _G.OpacityFrame, _G.OpacityFrameSlider = nil, nil, nil
end

return S
