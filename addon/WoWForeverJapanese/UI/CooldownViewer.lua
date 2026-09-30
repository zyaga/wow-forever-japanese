-- UI/CooldownViewer.lua: the Cooldown Settings window and its alert editors on Forever (surface "cooldownviewer",
-- area "ui", ADR-016). Blizzard_CooldownViewer is a login addon whose TOC names camelot
-- (blizzard_cooldownviewer.toc: `## AllowLoadGameType: standard, camelot`). The window is CooldownViewerSettings
-- (cooldownviewersettings.xml:139, ButtonFrameTemplate, parent UIParent, hidden), opened by the /cdm and
-- /cooldownmanager slash commands (slashcommandregistration.lua:1–3) and from edit mode
-- (blizzard_editmode/shared/editmodesystemtemplates.lua:1244, 3015). Without the frame init returns false and nothing
-- is touched.
-- Static text and its writers (every widget is parentKey-only, so every name is a dotted Compat candidate):
--   title: self:SetTitle(COOLDOWN_VIEWER_SETTINGS_TITLE) in OnLoad (cooldownviewersettings.lua:824) → Labels.title;
--   SearchBox.Instructions: SearchBoxTemplate's placeholder, instructionText COOLDOWN_VIEWER_SETTINGS_SEARCH_
--     INSTRUCTIONS (xml:188–191). The EditBox itself is never touched;
--   the three side tabs (SpellsTab, AurasTab, GroupBuffsTab, xml:154–187) own help tooltips: SidePanelTabButtonMixin:
--     OnEnter → SetOwner(self) → the setup function (GROUP_AURAS title + _DISABLED_TOOLTIP line, lua:900–908) or
--     SetText(self.tooltipText) → Show (blizzard_sharedxml/mainline/shareduipaneltemplates.lua,
--     SidePanelTabButtonMixin:OnEnter). Registered with UI/HelpTooltip, restricted to their four keys;
--   UndoButton (xml:262–272, UIButtonTemplate) owns a help tooltip: tooltipTitle / disabledTooltip
--     COOLDOWN_VIEWER_SETTINGS_BUTTON_REVERT_CHANGES_TOOLTIP (blizzard_sharedxml/shared/button/uibuttontemplate.lua:
--     20–53, sharedtooltiptemplates.lua:133–140). Its own text is "Revert " .. an atlas markup (lua:1208–1210),
--     written by UIButtonMixin:RunCustomTextFormatter (uibuttontemplate.lua:120–126; also on OnEnable / OnDisable,
--     :84–103): it is shown through the `iconAfter` label form (the atlas kept verbatim), re-shown after each run,
--     and resizes the button as the client does (text width + 20);
--   category headers: CooldownViewerSettingsMixin:RefreshLayout (lua:1513–1529; from OnShow :1472–1476 and
--     SetCurrentCategories :1510) releases and re-acquires the pooled categories (categoryPool, lua:826–828), and each
--     Init writes Header:SetHeaderText(categoryObj:GetTitle()) (lua:676–680) into Header.Name
--     (ListHeaderThreeSliceMixin:GetTitleRegion, blizzard_sharedxml/listtemplates.lua:167–169). RefreshLayout is
--     post-hooked on the frame and the active categories are walked, keyed by widget, restricted to the seven
--     COOLDOWN_VIEWER_SETTINGS_CATEGORY_* keys;
--   the Group Buffs tab's two section headers: GroupBuffFilterMixin:OnLoad writes GROUP_BUFF_FILTER_SECTION_SHOWN /
--     _HIDDEN once (groupbufffilter.lua:286–298, 235–239) into shownSection / hiddenSection .Header.Name;
--   the item tooltips written in Lua: an empty slot's GameTooltip_SetTitle(COOLDOWN_VIEWER_SETTINGS_EMPTY_SLOT_
--     TOOLTIP) (lua:219–226), a potion category's title + description (cooldownvieweritemdata.lua:405–424, 986–992)
--     and a tracked trinket's COOLDOWN_VIEWER_TRINKET_[NO_]AURA_TOOLTIP_LABEL lines (:895–940). The tooltip's owner is
--     the pooled item (GameTooltip_SetDefaultAnchor(tooltip, self), :828–836). Every other tooltip of an item is a
--     spell, item or aura tooltip, so an item is never registered as a help owner: each active item's OnEnter is
--     post-hooked once (HookScript, keyed by widget) and the tooltip is walked once (HelpTooltip.walkAs, restricted to
--     those keys) only when the item says it is an empty slot, a potion category, or a tracked equipment slot, and
--     never when it uses a dynamic (aura) appearance.
--   the alert editors CooldownViewerSettingsEditAlert (cooldownviewersettingsalerts.xml:3) and
--     GroupBuffFilterEditVisualAlert (groupbufffilter.xml:84), both CooldownViewerEditAlertBaseTemplate: Title
--     (COOLDOWN_VIEWER_SETTINGS_ALERT_DIALOG_TITLE, cooldownviewereditalertbase.xml:13), PrimaryLabel (…LABEL_TYPE /
--     GROUP_BUFF_FILTER_VISUAL_ALERT_DIALOG_LABEL_VISUAL_TYPE, written in OnLoad), EventLabel (…LABEL_EVENT),
--     PayloadLabel (…LABEL_SOUND_TYPE / _VISUAL_TYPE, rewritten by SetupDropdowns, cooldownviewersettingsalerts.lua:
--     170–172), AddButton (…MENU_BUTTON_ADD_ALERT / _EDIT_EXISTING_ALERT, UpdateAddButton via Display,
--     cooldownviewereditalertbase.lua:38–45). Display and SetupDropdowns are post-hooked on each frame. The
--     dropdown buttons' own selection text (SetSelectionText, cooldownviewersettingsalerts.lua:90–92, 109–111,
--     136–138; groupbufffilter.lua:194–196) is followed through the button's UpdateText like Labels.dropdown, but
--     restricted: the type (Sound / Visual), the event (COOLDOWN_VIEWER_SETTINGS_ALERT_WHEN_*), and for the payload
--     only Text to Speech and the ten visual alert labels (CDMVIS_*, blizzard_visualalerts/visualalerttemplates.lua:
--     77–86); a sound's label is its name ("RotaryPhoneDial") and stays English.
--   the four HUD viewers in edit mode: EssentialCooldownViewer, UtilityCooldownViewer, BuffIconCooldownViewer,
--     BuffBarCooldownViewer (cooldownviewer.xml:298–338): their Selection child writes Label:SetText(the system name,
--     HUD_EDIT_MODE_SYSTEM_*) in UpdateLabelVisibility and shows it as a tooltip it owns (blizzard_editmode/shared/
--     editmodesystemtemplates.lua:3316–3345). Only the Selection is read, restricted to those four keys.
-- Never touched: the HUD viewers' items. On this client a cooldown number, a charge count, an aura stack and an aura
--   instance can be secret values (blizzard_sharedxmlbase/securetypes.lua:6, blizzard_cooldownviewer/
--   cooldownviewersecure.lua:4–6), so no text of a HUD item is ever read or matched here. The alert editors' Name (a
--   spell name), a bar item's Name, the search box, the layout dropdown (a layout's name is the player's).
-- Not here: menu / dropdown popup entries (UI/Menus), the layout dialogs (shown with StaticPopupSpecial_Show,
--   blizzard_editmode/shared/editmodedialogs.lua:93–96, ADR-015 §5), the two StaticPopups (lua:8–28), chat lines.
local _, WFJ = ...
local CooldownViewer = {}
WFJ.CooldownViewer = CooldownViewer

local SURFACE = "cooldownviewer"
CooldownViewer.SURFACE = SURFACE
local Compat = WFJ.Compat

local ALERT, GROUP_ALERT = "CooldownViewerSettingsEditAlert", "GroupBuffFilterEditVisualAlert"
local VIEWERS = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer",
  "BuffBarCooldownViewer" }

CooldownViewer.NEVER_TOUCH = { ALERT .. ".Name", GROUP_ALERT .. ".Name", "CooldownViewerSettings.SearchBox",
  "CooldownViewerSettings.LayoutDropdown.Text" }

local CANDIDATES = {
  frame = { "CooldownViewerSettings" }, search = { "CooldownViewerSettings.SearchBox.Instructions" },
  spellsTab = { "CooldownViewerSettings.SpellsTab" }, aurasTab = { "CooldownViewerSettings.AurasTab" },
  groupTab = { "CooldownViewerSettings.GroupBuffsTab" }, undo = { "CooldownViewerSettings.UndoButton" },
  shownHeader = { "CooldownViewerSettings.GroupBuffFilter.shownSection.Header.Name" },
  hiddenHeader = { "CooldownViewerSettings.GroupBuffFilter.hiddenSection.Header.Name" },
  alert = { ALERT }, groupAlert = { GROUP_ALERT },
  tooltip = { "GameTooltip" }, isSecret = { "issecretvalue" }, categoryEnum = { "Enum.CooldownViewerCategory" },
}
for _, name in ipairs(VIEWERS) do CANDIDATES["viewer." .. name] = { name } end

local TITLE = { only = { "COOLDOWN_VIEWER_SETTINGS_TITLE" } }
local SEARCH = { only = { "COOLDOWN_VIEWER_SETTINGS_SEARCH_INSTRUCTIONS" } }
local TAB_TOOLTIP = { only = { "COOLDOWN_VIEWER_SETTINGS_TAB_SPELLS", "COOLDOWN_VIEWER_SETTINGS_TAB_BUFFS",
  "COOLDOWN_VIEWER_SETTINGS_TAB_GROUP_AURAS", "COOLDOWN_VIEWER_SETTINGS_TAB_GROUP_AURAS_DISABLED_TOOLTIP" } }
local UNDO_TOOLTIP = { only = { "COOLDOWN_VIEWER_SETTINGS_BUTTON_REVERT_CHANGES_TOOLTIP" } }
local UNDO = { only = { "COOLDOWN_VIEWER_SETTINGS_BUTTON_REVERT_CHANGES" } }
local CATEGORY = { only = { "COOLDOWN_VIEWER_SETTINGS_CATEGORY_ESSENTIAL", "COOLDOWN_VIEWER_SETTINGS_CATEGORY_UTILITY",
  "COOLDOWN_VIEWER_SETTINGS_CATEGORY_TRACKED_BUFF", "COOLDOWN_VIEWER_SETTINGS_CATEGORY_TRACKED_BARS",
  "COOLDOWN_VIEWER_SETTINGS_CATEGORY_EQUIP_ACTIVE", "COOLDOWN_VIEWER_SETTINGS_CATEGORY_EQUIP_PASSIVE",
  "COOLDOWN_VIEWER_SETTINGS_CATEGORY_NOT_IN_BAR" } }
local SECTION = { only = { "GROUP_BUFF_FILTER_SECTION_SHOWN", "GROUP_BUFF_FILTER_SECTION_HIDDEN" } }
local EMPTY_TOOLTIP = { only = { "COOLDOWN_VIEWER_SETTINGS_EMPTY_SLOT_TOOLTIP" } }
local POTION_TOOLTIP = { only = { "COOLDOWN_VIEWER_TOOLTIP_POTION_COMBAT_TITLE",
  "COOLDOWN_VIEWER_TOOLTIP_POTION_COMBAT_DESCRIPTION", "COOLDOWN_VIEWER_TOOLTIP_POTION_HEALTH_TITLE",
  "COOLDOWN_VIEWER_TOOLTIP_POTION_HEALTH_DESCRIPTION" } }
local TRINKET_TOOLTIP = { only = { "COOLDOWN_VIEWER_TRINKET_AURA_TOOLTIP_LABEL",
  "COOLDOWN_VIEWER_TRINKET_NO_AURA_TOOLTIP_LABEL" } }
local SYSTEM = { only = { "HUD_EDIT_MODE_SYSTEM_ESSENTIAL_COOLDOWNS", "HUD_EDIT_MODE_SYSTEM_UTILITY_COOLDOWNS",
  "HUD_EDIT_MODE_SYSTEM_TRACKED_BUFFS", "HUD_EDIT_MODE_SYSTEM_TRACKED_BUFF_BARS" } }

-- The alert editors' labels: widget field → the keys it can show.
local ALERT_LABELS = {
  { "Title", { "COOLDOWN_VIEWER_SETTINGS_ALERT_DIALOG_TITLE" } },
  { "PrimaryLabel", { "COOLDOWN_VIEWER_SETTINGS_ALERT_DIALOG_LABEL_TYPE",
    "GROUP_BUFF_FILTER_VISUAL_ALERT_DIALOG_LABEL_VISUAL_TYPE" } },
  { "EventLabel", { "COOLDOWN_VIEWER_SETTINGS_ALERT_DIALOG_LABEL_EVENT" } },
  { "PayloadLabel", { "COOLDOWN_VIEWER_SETTINGS_ALERT_DIALOG_LABEL_SOUND_TYPE",
    "COOLDOWN_VIEWER_SETTINGS_ALERT_DIALOG_LABEL_VISUAL_TYPE" } },
  { "AddButton", { "COOLDOWN_VIEWER_SETTINGS_ALERT_MENU_BUTTON_ADD_ALERT",
    "COOLDOWN_VIEWER_SETTINGS_ALERT_MENU_BUTTON_EDIT_EXISTING_ALERT" } },
}
local VISUALS = { "CDMVIS_MARCHING_ANTS", "CDMVIS_MARCHING_ANTS_CYAN", "CDMVIS_MARCHING_ANTS_RED",
  "CDMVIS_MARCHING_ANTS_GREEN", "CDMVIS_MARCHING_ANTS_BLUE", "CDMVIS_FLASH", "CDMVIS_FLASH_CYAN", "CDMVIS_FLASH_RED",
  "CDMVIS_FLASH_GREEN", "CDMVIS_FLASH_BLUE" }
local PAYLOAD = { "COOLDOWN_VIEWER_SETTINGS_ALERT_LABEL_SOUND_TYPE_TEXT_TO_SPEECH" }
for _, key in ipairs(VISUALS) do PAYLOAD[#PAYLOAD + 1] = key end
-- The alert editors' dropdown buttons: widget field → the keys its selection text can show (never a sound's name).
local ALERT_DROPDOWNS = {
  { "TypeDropdown", { "COOLDOWN_VIEWER_SETTINGS_ALERT_TYPE_SOUND", "COOLDOWN_VIEWER_SETTINGS_ALERT_TYPE_VISUAL" } },
  { "EventDropdown", { "COOLDOWN_VIEWER_SETTINGS_ALERT_WHEN_AVAILABLE", "COOLDOWN_VIEWER_SETTINGS_ALERT_WHEN_PANDEMIC",
    "COOLDOWN_VIEWER_SETTINGS_ALERT_WHEN_ON_COOLDOWN", "COOLDOWN_VIEWER_SETTINGS_ALERT_WHEN_CHARGE_GAINED",
    "COOLDOWN_VIEWER_SETTINGS_ALERT_WHEN_AURA_APPLIED", "COOLDOWN_VIEWER_SETTINGS_ALERT_WHEN_AURA_REMOVED" } },
  { "PayloadDropdown", PAYLOAD }, { "VisualDropdown", VISUALS },
}

local function get(key) return Compat.get(SURFACE, key) end

-- → true when `value` is a secret value on this client (never on a client without the API).
local function secret(value)
  local fn = get("isSecret")
  if type(fn) ~= "function" then return false end
  local ok, result = pcall(fn, value)
  return ok and result == true
end

-- `obj:method()` when it is a function and does not raise. → its first result | nil
local function call(obj, method)
  if type(obj) ~= "table" or type(obj[method]) ~= "function" then return nil end
  local ok, result = pcall(obj[method], obj)
  if ok then return result end
  return nil
end

local categoryKey = WFJ.Labels.keyer("category.") -- a pooled category header's record key

-- An active pool's objects. → iterator (nothing when `pool` is not a pool)
local function active(pool)
  if type(pool) == "table" and type(pool.EnumerateActive) == "function" then return pool:EnumerateActive() end
  return function() return nil end
end

-- Which restricted walk an item's Lua-written tooltip may take. → opts | nil (a spell / item / aura tooltip)
local function itemTooltipOpts(item)
  if call(item, "UsesDynamicAppearance") then return nil end -- an aura tooltip: may carry secret values
  if call(item, "IsEmptyCategory") == true then return EMPTY_TOOLTIP end
  if type(call(item, "GetSpellCategoryTooltipTitle")) == "string" then return POTION_TOOLTIP end
  local enum = get("categoryEnum")
  local tracked = type(enum) == "table" and enum.EquipSlotTracked or nil
  if tracked ~= nil and type(item.GetEquipSlotTooltipTypes) == "function" then
    local ok, canDisplay, _, category = pcall(item.GetEquipSlotTooltipTypes, item)
    if ok and canDisplay and category == tracked then return TRINKET_TOOLTIP end
  end
  return nil
end

-- HookScript target (a settings item's OnEnter, after the client built the tooltip). → the number of lines found
function CooldownViewer.onItemEnter(item)
  local tt = get("tooltip")
  if type(tt) ~= "table" or type(tt.GetOwner) ~= "function" or tt:GetOwner() ~= item then return 0 end
  local opts = itemTooltipOpts(item)
  if not opts then return 0 end
  local first = Compat.resolve((call(tt, "GetName") or "GameTooltip") .. "TextLeft1")
  if type(first) == "table" and type(first.GetText) == "function" and secret(first:GetText()) then return 0 end
  return WFJ.HelpTooltip.walkAs(tt, opts)
end

local itemHooked = setmetatable({}, { __mode = "k" })
local function hookItem(item)
  if type(item) ~= "table" or itemHooked[item] or type(item.HookScript) ~= "function" then return end
  itemHooked[item] = true
  item:HookScript("OnEnter", CooldownViewer.onItemEnter)
end

-- hooksecurefunc target (CooldownViewerSettings:RefreshLayout) and the OnShow pass: the pooled category headers, the
-- group-buff section headers, and the item tooltip hooks. → the number of dictionary words found
function CooldownViewer.onRefreshLayout()
  local show, n = WFJ.Labels.show, 0
  local frame = get("frame")
  for category in active(type(frame) == "table" and frame.categoryPool or nil) do
    local header = type(category) == "table" and category.Header or nil
    local name = type(header) == "table" and header.Name or nil
    if type(name) == "table" then n = n + show(SURFACE, categoryKey(name), name, nil, CATEGORY) end
    for item in active(type(category) == "table" and category.itemPool or nil) do hookItem(item) end
  end
  n = n + show(SURFACE, "section.shown", get("shownHeader"), nil, SECTION)
    + show(SURFACE, "section.hidden", get("hiddenHeader"), nil, SECTION)
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- The window's labels that are written once. → the number of dictionary words found
-- The undo button's "Revert |A…|a" after the client's formatter ran. → 1 | 0
function CooldownViewer.onUndoText()
  local button = get("undo")
  if type(button) ~= "table" then return 0 end
  local function refit()
    if type(button.SetWidth) == "function" and type(button.GetTextWidth) == "function" then
      button:SetWidth(button:GetTextWidth() + 20)
    end
  end
  return WFJ.Labels.show(SURFACE, "undo", type(button.Text) == "table" and button.Text or button, refit, UNDO)
end

function CooldownViewer.showStatic()
  local n = WFJ.Labels.title(SURFACE, get("frame"), TITLE)
    + WFJ.Labels.show(SURFACE, "search", get("search"), nil, SEARCH) + CooldownViewer.onUndoText()
  return n + CooldownViewer.onRefreshLayout()
end

-- A dropdown button's own selection text, restricted to `keys` (Labels.dropdown takes no restriction, and a payload
-- dropdown can hold a sound's name). The button's UpdateText is post-hooked once. → 1 | 0
local dropdownHooked = setmetatable({}, { __mode = "k" })
local function showDropdown(recKey, dropdown, keys)
  if type(dropdown) ~= "table" or type(dropdown.Text) ~= "table" then return 0 end
  local opts = { only = keys }
  if not dropdownHooked[dropdown] and type(dropdown.UpdateText) == "function" then
    dropdownHooked[dropdown] = true
    hooksecurefunc(dropdown, "UpdateText", function(self) WFJ.Labels.show(SURFACE, recKey, self.Text, nil, opts) end)
  end
  return WFJ.Labels.show(SURFACE, recKey, dropdown.Text, nil, opts)
end

-- One alert editor's labels, button and dropdown texts, as records `<which>.<field>`. → the number found
function CooldownViewer.showAlert(which)
  local frame = get(which)
  if type(frame) ~= "table" then return 0 end
  local n = 0
  for _, l in ipairs(ALERT_LABELS) do
    n = n + WFJ.Labels.show(SURFACE, which .. "." .. l[1], frame[l[1]], nil, { only = l[2] })
  end
  for _, d in ipairs(ALERT_DROPDOWNS) do n = n + showDropdown(which .. "." .. d[1], frame[d[1]], d[2]) end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

local function hookAlert(which)
  local frame = get(which)
  if type(frame) ~= "table" then return end
  local function pass() CooldownViewer.showAlert(which) end
  for _, method in ipairs({ "Display", "SetupDropdowns", "SetupDropdown" }) do
    if type(frame[method]) == "function" then hooksecurefunc(frame, method, pass) end
  end
  pass()
end

-- One HUD viewer's edit-mode selection: its label and the tooltip it owns. Nothing else of a viewer is read.
local function hookViewer(name)
  local viewer = get("viewer." .. name)
  local selection = type(viewer) == "table" and viewer.Selection or nil
  if type(selection) ~= "table" then return end
  local function pass() WFJ.Labels.show(SURFACE, "system." .. name, selection.Label, nil, SYSTEM) end
  if type(selection.UpdateLabelVisibility) == "function" then
    hooksecurefunc(selection, "UpdateLabelVisibility", pass)
  end
  WFJ.HelpTooltip.register(selection, SYSTEM)
  pass()
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function CooldownViewer.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  local frame = get("frame")
  if hooked or type(frame) ~= "table" then return false end -- no CooldownViewerSettings
  hooked = true
  if type(frame.RefreshLayout) == "function" then
    hooksecurefunc(frame, "RefreshLayout", CooldownViewer.onRefreshLayout)
  end
  if type(frame.HookScript) == "function" then frame:HookScript("OnShow", CooldownViewer.showStatic) end
  for _, key in ipairs({ "spellsTab", "aurasTab", "groupTab" }) do
    WFJ.HelpTooltip.register(get(key), TAB_TOOLTIP)
  end
  local undo = get("undo")
  WFJ.HelpTooltip.register(undo, UNDO_TOOLTIP)
  if type(undo) == "table" and type(undo.RunCustomTextFormatter) == "function" then
    hooksecurefunc(undo, "RunCustomTextFormatter", CooldownViewer.onUndoText)
  end
  if type(undo) == "table" and type(undo.HookScript) == "function" then
    undo:HookScript("OnEnable", CooldownViewer.onUndoText)
    undo:HookScript("OnDisable", CooldownViewer.onUndoText)
  end
  hookAlert("alert")
  hookAlert("groupAlert")
  for _, name in ipairs(VIEWERS) do hookViewer(name) end
  CooldownViewer.showStatic()
  return true
end
