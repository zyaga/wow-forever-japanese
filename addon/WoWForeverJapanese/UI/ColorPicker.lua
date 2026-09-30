-- UI/ColorPicker.lua: the colour picker on Forever (surface "colorpicker", area "ui", ADR-016).
-- Blizzard_ColorPickerFrame is a login addon on camelot; ColorPickerFrame (mainline/colorpickerframe.xml:75) opens
-- from every colour swatch (chat colours, the Options window's colour-blind and nameplate swatches, raid markers).
--   Static: Header.Text COLOR_PICKER (the DialogHeaderTemplate's textString, xml:82–86), Footer.CancelButton CANCEL
--     and Footer.OkayButton OKAY (xml:187–198), and OpacityFrame's OPACITY label (xml:20). Walked at init and on
--     each frame's OnShow with UI/LabelTree.lua, restricted to this window's keys.
--   Content.HexBox is an EditBox (the hex colour, read back on every edit, colorpickerframe.lua:129–163): never
--     entered. Its placeholder, HexBox.Instructions (COLOR_PICKER_HEX, lua:124), is a FontString of its own that the
--     client only writes once; it is shown by itself.
-- The gamepad prompts (ACTION_LABEL_ADJUST_COLOR …, lua:242–245) are drawn by GamepadSharedUtility, not this window.
local _, WFJ = ...
local ColorPicker = {}
WFJ.ColorPicker = ColorPicker

local SURFACE = "colorpicker"
ColorPicker.SURFACE = SURFACE
local Compat = WFJ.Compat

ColorPicker.NEVER_TOUCH = { "ColorPickerFrame.Content.HexBox" }

local CANDIDATES = {
  frame = { "ColorPickerFrame" }, opacity = { "OpacityFrame" },
  hexLabel = { "ColorPickerFrame.Content.HexBox.Instructions" },
}

local KEYS = WFJ.LabelTree.set(WFJ.SettingsKeys and WFJ.SettingsKeys.colorpicker)
local ONLY = { only = KEYS }

local function get(key) return Compat.get(SURFACE, key) end

-- Both frames' labels (HookScript target for their OnShow). → the number of dictionary words found.
function ColorPicker.show()
  return WFJ.LabelTree.show(SURFACE, get("frame"), ONLY) + WFJ.LabelTree.show(SURFACE, get("opacity"), ONLY)
    + WFJ.Labels.show(SURFACE, "hexLabel", get("hexLabel"), nil, { only = { "COLOR_PICKER_HEX" } })
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function ColorPicker.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  local frame = get("frame")
  -- a ColorPickerFrame without Content / Header / Footer is not this shape
  if hooked or type(frame) ~= "table" or type(frame.Content) ~= "table" then return false end
  hooked = true
  for _, key in ipairs({ "frame", "opacity" }) do
    local f = get(key)
    if type(f) == "table" and type(f.HookScript) == "function" then f:HookScript("OnShow", ColorPicker.show) end
  end
  ColorPicker.show()
  return true
end
