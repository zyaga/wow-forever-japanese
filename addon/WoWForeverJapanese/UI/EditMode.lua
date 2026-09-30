-- UI/EditMode.lua: HUD Edit Mode on Forever (surfaces "editmode" and "editmode.dialog", area "ui", ADR-016).
-- Blizzard_EditMode is a login addon on camelot; the Esc menu's "Edit Mode" button shows EditModeManagerFrame
-- (blizzard_gamemenu/shared/gamemenuframe.lua:237–238). The window and its dialogs are data-driven (setting names
-- and option texts come from shared/editmodesettingdisplayinfo.lua), so labels are walked with UI/LabelTree.lua,
-- restricted to Edit Mode's keys (UI/SettingsKeys.lua); no per-setting code.
--   EditModeManagerFrame (shared/editmodemanager.xml:4–560): Title HUD_EDIT_MODE_TITLE, LayoutLabel (lua:32), the
--     grid / snap / advanced check buttons, the AccountSettings check buttons and category titles, Save / Revert.
--     All written at load; walked at init and on OnShow. AccountSettings:SetExpandedState rewrites Expander.Label
--     (editmodemanager.lua:2916–2918) and SetupStatusTrackingBar2 a check button's label (:2572–2573): both hooked
--     to re-walk. The expander's own text carries |A arrow markup and stays English.
--   EditModeSystemSettingsDialog (shared/editmodedialogs.xml:254): AttachToSystemFrame writes Title from the
--     system's name and calls UpdateDialog → UpdateSettings, which re-acquires the pooled dropdown / slider /
--     checkbox setting frames and fills them (SetupSetting: Label, MinText / MaxText, the dropdown's selection;
--     editmodedialogs.lua:537–660, editmodetemplates.lua:24–140), then the extra buttons
--     (editmodesystemtemplates.lua:542, 1219–1264). The title is written before UpdateDialog runs, so post-hooks
--     on UpdateSettings and UpdateExtraButtons see everything; pooled frames are keyed by widget.
--   EditModeLayoutDialog / EditModeImportLayoutDialog / EditModeImportLayoutLinkDialog / EditModeUnsavedChangesDialog:
--     each fills its title and buttons and then shows itself (SetupControlsForMode → StaticPopupSpecial_Show,
--     editmodedialogs.lua:93–96, 231–258, 310–335, 434–447), so OnShow sees the final text. A title with a layout
--     name ("%s") keeps the name as written. Their EditBoxes are never entered.
--   The selection overlay of every HUD system: Selection:UpdateLabelVisibility writes "Click to Edit" or the
--     system's name into Label (or HorizontalLabel / VerticalLabel) on every hover and selection
--     (editmodesystemtemplates.lua:3331–3361). Each registered system's Selection is hooked once, when the manager
--     is shown (EditModeManagerFrame.registeredSystemFrames, editmodemanager.lua:24, 225); its hover tooltip
--     (GetAppropriateTooltip():SetText(system name), :3316–3323) goes through HelpTooltip.
-- Never touched: EditModeManagerFrame.LayoutDropdown: its text is a layout's name, the player's own or a preset's
--   inside HUD_EDIT_MODE_PRESET_LAYOUT (editmodemanager.lua:1367). The dropdown's popup (copy / rename / import /
--   share) is UI/Menus'. The "layout applied" and "copied to clipboard" lines are chat messages (:777, 1606).
local _, WFJ = ...
local EditMode = {}
WFJ.EditMode = EditMode

local SURFACE = "editmode"
EditMode.SURFACE = SURFACE
local DIALOG = SURFACE .. ".dialog"
-- The HUD systems' selection overlays ("Click to Edit", the system's name) sit on the HUD, not in a window:
-- their own surface, which UI/Readings lists as non-window (no word cards)
local SELECTION = SURFACE .. ".selection"
EditMode.SELECTION = SELECTION
local Compat = WFJ.Compat

local MANAGER = "EditModeManagerFrame"
EditMode.NEVER_TOUCH = { MANAGER .. ".LayoutDropdown" }

local DIALOGS = { "EditModeLayoutDialog", "EditModeImportLayoutDialog", "EditModeImportLayoutLinkDialog",
  "EditModeUnsavedChangesDialog" }
local CANDIDATES = {
  manager = { MANAGER }, account = { MANAGER .. ".AccountSettings" }, systemDialog = { "EditModeSystemSettingsDialog" },
}
for _, name in ipairs(DIALOGS) do CANDIDATES[name] = { name } end

local KEYS = WFJ.LabelTree.set(WFJ.SettingsKeys and WFJ.SettingsKeys.editmode)
local ONLY = { only = KEYS }

local function get(key) return Compat.get(SURFACE, key) end

-- The manager window's labels. → the number of dictionary words found.
function EditMode.showManager()
  return WFJ.LabelTree.show(SURFACE, get("manager"), ONLY)
end

-- hooksecurefunc target (the system settings dialog's UpdateSettings / UpdateExtraButtons).
function EditMode.onSystemDialog()
  return WFJ.LabelTree.show(DIALOG, get("systemDialog"), ONLY)
end

local selections = setmetatable({}, { __mode = "k" }) -- Selection frame → true once hooked

local function showSelection(selection)
  WFJ.LabelTree.show(SELECTION, selection, ONLY)
end

-- Hooks every registered HUD system's selection overlay once. → the number hooked now.
function EditMode.followSelections()
  local manager = get("manager")
  local systems = type(manager) == "table" and manager.registeredSystemFrames or nil
  if type(systems) ~= "table" then return 0 end
  local n = 0
  for _, system in pairs(systems) do
    local selection = type(system) == "table" and system.Selection or nil
    if type(selection) == "table" and not selections[selection] then
      selections[selection] = true
      if type(selection.UpdateLabelVisibility) == "function" then
        hooksecurefunc(selection, "UpdateLabelVisibility", showSelection)
        n = n + 1
      end
      -- a selection another surface already owns keeps its own keys (the cooldown viewers' Selection is registered by
      -- UI/CooldownViewer with its HUD_EDIT_MODE_SYSTEM_* keys; re-registering would replace them)
      if not WFJ.HelpTooltip.registered(selection) then WFJ.HelpTooltip.register(selection, ONLY) end
    end
    if type(selection) == "table" then showSelection(selection) end
  end
  return n
end

-- HookScript target (EditModeManagerFrame OnShow, after EnterEditMode showed the selections).
function EditMode.onShow()
  EditMode.showManager()
  EditMode.followSelections()
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function EditMode.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  local manager = get("manager")
  if hooked or type(manager) ~= "table" then return false end -- a client without Edit Mode
  hooked = true
  if type(manager.HookScript) == "function" then manager:HookScript("OnShow", EditMode.onShow) end
  local account = get("account")
  if type(account) == "table" then
    for _, method in ipairs({ "SetExpandedState", "SetupStatusTrackingBar2" }) do
      if type(account[method]) == "function" then hooksecurefunc(account, method, EditMode.showManager) end
    end
  end
  local dialog = get("systemDialog")
  if type(dialog) == "table" then
    for _, method in ipairs({ "UpdateSettings", "UpdateExtraButtons" }) do
      if type(dialog[method]) == "function" then hooksecurefunc(dialog, method, EditMode.onSystemDialog) end
    end
  end
  for _, name in ipairs(DIALOGS) do
    local frame = get(name)
    if type(frame) == "table" and type(frame.HookScript) == "function" then
      frame:HookScript("OnShow", function(self) WFJ.LabelTree.show(DIALOG, self, ONLY) end)
    end
  end
  EditMode.showManager()
  return true
end
