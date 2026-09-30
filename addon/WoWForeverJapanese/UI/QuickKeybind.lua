-- UI/QuickKeybind.lua: quick keybind mode's window on Forever (surfaces "quickkeybind" and "quickkeybind.tooltip",
-- area "ui", ADR-016). Blizzard_QuickKeybind is a login addon on camelot; QuickKeybindFrame
-- (blizzard_quickkeybind/quickkeybind.xml:89) opens from the Options window's key-bindings page and from Edit
-- Mode's action-bar settings (blizzard_editmode/shared/editmodesystemtemplates.lua:1219).
--   Static, XML text= or written once in OnLoad (quickkeybind.lua:106–124): Header.Text QUICK_KEYBIND_MODE,
--     InstructionText QUICK_KEYBIND_DESCRIPTION, CancelDescriptionText QUICK_KEYBIND_CANCEL_DESCRIPTION,
--     DefaultsButton RESET_TO_DEFAULT, CancelButton CANCEL, OkayButton OKAY. Walked at init and on OnShow with
--     UI/LabelTree.lua, restricted to this window's keys. UseCharacterBindingsButton.Text is the label wrapped in a
--     colour by concatenation (:124) and matches nothing.
--   QuickKeybindFrame:SetOutputText (:226–228) → OutputText: KEY_BOUND, KEYBINDINGFRAME_MOUSEWHEEL_ERROR,
--     PRIMARY_KEY_UNBOUND_ERROR / KEY_UNBOUND_ERROR (:234–245). Post-hooked.
--   QuickKeybindTooltip (xml:18; QuickKeybindButtonSetTooltip, lua:51–72): the binding's name, the bound key (a key
--     name: never in the key set), ESCAPE_TO_UNBIND, NOT_BOUND, PRESS_KEY_TO_BIND, followed by UI/TooltipLines.lua.
local _, WFJ = ...
local QuickKeybind = {}
WFJ.QuickKeybind = QuickKeybind

local SURFACE = "quickkeybind"
QuickKeybind.SURFACE = SURFACE
local TOOLTIP = SURFACE .. ".tooltip"
local Compat = WFJ.Compat

QuickKeybind.NEVER_TOUCH = {}

local CANDIDATES = {
  frame = { "QuickKeybindFrame" }, output = { "QuickKeybindFrame.OutputText" }, tooltip = { "QuickKeybindTooltip" },
}

local KEYS = WFJ.LabelTree.set(WFJ.SettingsKeys and WFJ.SettingsKeys.quickkeybind)
local ONLY = { only = KEYS }

local function get(key) return Compat.get(SURFACE, key) end

-- The window's labels (HookScript target for OnShow). → the number of dictionary words found.
function QuickKeybind.show()
  return WFJ.LabelTree.show(SURFACE, get("frame"), ONLY)
end

-- hooksecurefunc target (QuickKeybindFrame:SetOutputText). → 1 | 0
function QuickKeybind.onOutput()
  return WFJ.Labels.show(SURFACE, "output", get("output"), nil, ONLY)
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function QuickKeybind.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  local frame = get("frame")
  if hooked or type(frame) ~= "table" then return false end
  hooked = true
  if type(frame.HookScript) == "function" then frame:HookScript("OnShow", QuickKeybind.show) end
  if type(frame.SetOutputText) == "function" then hooksecurefunc(frame, "SetOutputText", QuickKeybind.onOutput) end
  WFJ.TooltipLines.follow(TOOLTIP, get("tooltip"), ONLY)
  QuickKeybind.show()
  return true
end
