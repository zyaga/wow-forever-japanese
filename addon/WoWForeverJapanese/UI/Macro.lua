-- UI/Macro.lua: the macro window on Forever (surface "macro", area "ui", ADR-016 / ADR-029).
-- Blizzard_MacroUI is load-on-demand; ShowMacroFrame / MacroFrame_LoadUI live in its [Bootstrap] file
-- (blizzard_macroui/blizzard_macroui_bootstrap.lua) and are called by the game menu's Macros button
-- (blizzard_gamemenu/shared/gamemenuframe.lua:261), /macro (blizzard_chatframebase/shared/slashcommands.lua:1218),
-- the chat menu button (blizzard_chatframebase/mainline/chatframemenubutton.lua:91) and the click-binding window's
-- OnLoad (blizzard_clickbindingui/blizzard_clickbindingui.lua:594).
-- Static labels (XML text=, blizzard_macroui/blizzard_macroui.xml): an unnamed CREATE_MACROS header (:40),
--   MacroFrameEnterMacroText ENTER_MACRO_LABEL (:73), MacroEditButton CHANGE_MACRO_NAME_ICON (:108),
--   MacroCancelButton CANCEL (:159), MacroSaveButton SAVE (:168), MacroFrameTab1 GENERAL_MACROS (:183),
--   MacroDeleteButton DELETE (:213), MacroNewButton NEW (:225), MacroExitButton EXIT (:234);
--   MacroFrameTab2's OnLoad writes SetFormattedText(CHARACTER_SPECIFIC_MACROS, UnitName("player")) (:204–207); the
--   player's name is kept as written.
-- Writers:
--   MacroFrameText's OnTextChanged (an inline XML handler, xml:126–136) → MacroFrameCharLimitText,
--     SetFormattedText(MACROFRAME_CHAR_LIMIT, n). The EditBox's script is followed with HookScript; its text is
--     never read or written;
--   the name-and-icon popup (MacroPopupFrame, IconSelectorPopupFrameTemplate, blizzard_macroiconselector.xml:3–10):
--     BorderBox.EditBoxHeaderText MACRO_POPUP_TEXT (written at OnLoad, blizzard_sharedxml/mainline/
--     shareduipaneltemplates.lua:1844), OkayButton / CancelButton, SelectedIconHeader ICON_SELECTION_TITLE_CURRENT
--     (shareduipaneltemplates.xml:1796), and SelectedIconDescription after MacroPopupFrame:SetSelectedIconText
--     (ICON_SELECTION_CLICK / ICON_SELECTION_NOTINLIST, shareduipaneltemplates.lua:1969–1972).
-- Help tooltips (GameTooltip): tab 2's title when truncated (xml:198–203); Edit / Delete / New in click-binding mode
--   add CLICK_BINDING_BUTTON_DISABLED (blizzard_macroui.lua:233–246).
-- Never touched: the macro body EditBox, the selected macro's name, the macro buttons' names, the popup's name
--   EditBox. The delete confirmation is a StaticPopup (ADR-015 §5).
local _, WFJ = ...
local Macro = {}
WFJ.Macro = Macro

local SURFACE = "macro"
Macro.SURFACE = SURFACE
local Compat = WFJ.Compat
local ADDON = "Blizzard_MacroUI"
local POPUP = "MacroPopupFrame.BorderBox"
local ICON_TEXT = POPUP .. ".SelectedIconArea.SelectedIconText"

Macro.NEVER_TOUCH = { "MacroFrameText", "MacroFrameSelectedMacroName", "MacroFrameSelectedMacroButton.Name",
  POPUP .. ".IconSelectorEditBox" }

-- Static labels: record key → { candidate, the keys it can show }.
local STATIC_LABELS = {
  enterText = { "MacroFrameEnterMacroText", { "ENTER_MACRO_LABEL" } },
  edit = { "MacroEditButton", { "CHANGE_MACRO_NAME_ICON" } }, cancel = { "MacroCancelButton", { "CANCEL" } },
  save = { "MacroSaveButton", { "SAVE" } }, delete = { "MacroDeleteButton", { "DELETE" } },
  new = { "MacroNewButton", { "NEW" } }, exit = { "MacroExitButton", { "EXIT" } },
  tab1 = { "MacroFrameTab1", { "GENERAL_MACROS" } }, tab2 = { "MacroFrameTab2", { "CHARACTER_SPECIFIC_MACROS" } },
  popupHeader = { POPUP .. ".EditBoxHeaderText", { "MACRO_POPUP_TEXT" } },
  popupOkay = { POPUP .. ".OkayButton", { "OKAY" } }, popupCancel = { POPUP .. ".CancelButton", { "CANCEL" } },
  popupIconHeader = { ICON_TEXT .. ".SelectedIconHeader", { "ICON_SELECTION_TITLE_CURRENT" } },
}
local STATIC_ORDER = {}
for key in pairs(STATIC_LABELS) do STATIC_ORDER[#STATIC_ORDER + 1] = key end
table.sort(STATIC_ORDER)

local CANDIDATES = {
  frame = { "MacroFrame" }, body = { "MacroFrameText" },
  charLimit = { "MacroFrameCharLimitText" }, popup = { "MacroPopupFrame" },
  iconText = { ICON_TEXT .. ".SelectedIconDescription" },
}

local HEADER = { only = { "CREATE_MACROS" } }
local CHAR_LIMIT = { only = { "MACROFRAME_CHAR_LIMIT" } }
local ICON_TEXT_ONLY = { only = { "ICON_SELECTION_CLICK", "ICON_SELECTION_NOTINLIST" } }
local TAB2_TOOLTIP = { only = { "CHARACTER_SPECIFIC_MACROS" } }
local DISABLED_TOOLTIP = { only = { "CLICK_BINDING_BUTTON_DISABLED" } }

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  for key, l in pairs(STATIC_LABELS) do Compat.declare(SURFACE, "static." .. key, { l[1] }) end
end

-- hooksecurefunc / HookScript target (MacroFrameText's OnTextChanged). → 1 | 0
function Macro.onCharLimit()
  return WFJ.Labels.show(SURFACE, "charLimit", get("charLimit"), nil, CHAR_LIMIT)
end

-- hooksecurefunc target (MacroPopupFrame:SetSelectedIconText). → 1 | 0
function Macro.onIconText()
  return WFJ.Labels.show(SURFACE, "popupIconText", get("iconText"), nil, ICON_TEXT_ONLY)
end

-- The labels the client writes at load, and again on the window's OnShow. → the number of dictionary words found.
function Macro.showStatic()
  local items = {}
  for _, key in ipairs(STATIC_ORDER) do
    items[#items + 1] = { key, get("static." .. key), { only = STATIC_LABELS[key][2] } }
  end
  items[#items + 1] = { "header", WFJ.Labels.region(get("frame"), "CREATE_MACROS"), HEADER }
  local n = WFJ.Labels.showAll(SURFACE, items)
  return n + Macro.onCharLimit() + Macro.onIconText()
end

local hooked = false

-- Blizzard_MacroUI's part: runs once the addon is loaded (now, or on its ADDON_LOADED). → true when set up.
function Macro.setup()
  declare() -- its frames exist only now: forget what Compat memoized before
  local frame = get("frame")
  if type(frame) ~= "table" then return false end
  WFJ.Labels.forbidNames(Macro.NEVER_TOUCH) -- its widgets exist only now (Main's registration found none)
  Macro.showStatic()
  if hooked then return false end
  hooked = true
  if type(frame.HookScript) == "function" then frame:HookScript("OnShow", Macro.showStatic) end
  local body = get("body")
  if type(body) == "table" and type(body.HookScript) == "function" then
    body:HookScript("OnTextChanged", Macro.onCharLimit)
  end
  local popup = get("popup")
  if type(popup) == "table" and type(popup.SetSelectedIconText) == "function" then
    hooksecurefunc(popup, "SetSelectedIconText", Macro.onIconText)
  end
  local tab2 = get("static.tab2")
  if type(tab2) == "table" then WFJ.HelpTooltip.register(tab2, TAB2_TOOLTIP) end
  for _, key in ipairs({ "edit", "delete", "new" }) do
    local button = get("static." .. key)
    if type(button) == "table" then WFJ.HelpTooltip.register(button, DISABLED_TOOLTIP) end
  end
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init.
function Macro.init()
  declare()
  return WFJ.LoadOnDemand.when(ADDON, Macro.setup)
end
