-- UI/SettingsPanel.lua: the game's Options window on Forever (surfaces "settingspanel", "settingspanel.static" and
-- "settingspanel.tooltip", area "ui", ADR-016). Esc → Options opens SettingsPanel
-- (blizzard_settings_shared/blizzard_settingspanel.xml:4); its pages are data: Blizzard_SettingsDefinitions_Shared /
-- _Frame register categories, section headers and option initializers, and the panel draws them as pooled ScrollBox
-- rows. There is no per-option code here: rows are walked after the client fills them.
-- Static (SettingsPanelMixin:OnLoad, blizzard_settingspanel.lua:48–78; the title again in OnShow :181–187):
--   NineSlice.Text SETTINGS_TITLE, CloseButton SETTINGS_CLOSE, ApplyButton SETTINGS_APPLY, the list header's
--   DefaultsButton SETTINGS_DEFAULTS, GameTab / AddOnsTab (tabText SETTINGS_TAB_GAME / SETTINGS_TAB_ADDONS, xml:26–45).
-- Writers, each the frame's own method (the mixin is copied onto the frame; every call is `self:…()`):
--   SettingsPanel:DisplayLayout (:939–971): DisplayCategory writes the list header's Title from category:GetName()
--     (:880) and the search writes SETTINGS_SEARCH_RESULTS (:730); both then call DisplayLayout, so its post-hook
--     sees either title;
--   SettingsPanel:SetOutputText (:979–981): the key-binding messages: SETTINGS_BIND_KEY_TO_COMMAND_OR_CANCEL,
--     KEY_BOUND, KEYBINDINGFRAME_MOUSEWHEEL_ERROR, PRIMARY_KEY_UNBOUND_ERROR / KEY_UNBOUND_ERROR (:1009–1024);
--   the settings list: Container.SettingsList.ScrollBox (blizzard_settingslist.lua:50–88). Every row is built by its
--     initializer's InitFrame: SettingsListElementMixin:Init writes self.Text (blizzard_settingcontrols.lua:339),
--     SettingsListSectionHeaderMixin:Init the Title (:97), SettingsExpandableSectionMixin:Init Button.Text (:1855),
--     KeyBindingFrameBindingTemplateMixin:Init the binding's Label (blizzard_keybindings.lua:394), the custom
--     templates their own labels (graphics.xml:5–280, audio.xml, nameplates.xml, pingsystem.xml, colorblind.xml).
--     ScrollUtil.AddInitializedFrameCallback runs after the initializer (blizzard_sharedxml/shared/scroll/
--     scrollutil.lua:21–30, scrollboxlistview.lua:397–410), so each row is walked there with UI/LabelTree.lua,
--     restricted to this window's keys (UI/SettingsKeys.lua). Dropdown buttons' selected values are followed;
--   the category list: CategoryList.ScrollBox. SettingsCategoryListButtonMixin:Init writes Label from
--     category:GetName() (blizzard_categorylist.lua:94–97), the group header its Label (:30–31);
--   option tooltips: SettingsTooltip, built by Settings.InitTooltip / CreateOptionsInitTooltip
--     (blizzard_settings.lua:289–297, 416–491) and shown by DefaultTooltipMixin:OnEnter, followed by
--     UI/TooltipLines.lua: the name line, the tooltip body, the restart / reload notices. The per-option
--     "<label>: <tooltip>" lines are string.format composites (:454) and stay English.
-- AddOns: a category of the AddOns tab (category:GetCategorySet() == Settings.CategorySet.AddOns,
--   blizzard_categorylist.lua:316–326) is an addon's name and its page is the addon's: neither the category button,
--   the header title, the rows nor the tooltip are touched while one is displayed.
-- Never touched: the search box (an EditBox; LabelTree never enters one), the key buttons of a binding row (key
--   names: row.Buttons / CustomButton), slider value labels, the raid-frame and nameplate previews (unit names).
-- The dropdown popups' entries are not handled here. Narration reads some of these labels back for text-to-speech
--   only (blizzard_settingcontrols.lua:86, 482; blizzard_categorylist.lua:139).
local _, WFJ = ...
local SettingsPanel = {}
WFJ.SettingsPanel = SettingsPanel

local SURFACE = "settingspanel"
SettingsPanel.SURFACE = SURFACE
local STATIC = SURFACE .. ".static"
local TOOLTIP = SURFACE .. ".tooltip"
local Compat = WFJ.Compat

SettingsPanel.NEVER_TOUCH = { "SettingsPanel.SearchBox" }

local PANEL = "SettingsPanel"
local LIST = PANEL .. ".Container.SettingsList"
local CANDIDATES = {
  frame = { PANEL }, title = { PANEL .. ".NineSlice.Text" }, close = { PANEL .. ".CloseButton" },
  apply = { PANEL .. ".ApplyButton" }, gameTab = { PANEL .. ".GameTab" }, addOnsTab = { PANEL .. ".AddOnsTab" },
  defaults = { LIST .. ".Header.DefaultsButton" }, header = { LIST .. ".Header.Title" },
  list = { LIST .. ".ScrollBox" }, categories = { PANEL .. ".CategoryList.ScrollBox" },
  output = { PANEL .. ".OutputText" }, search = { PANEL .. ".SearchBox" }, tooltip = { "SettingsTooltip" },
  addOnSet = { "Settings.CategorySet.AddOns" }, scrollUtil = { "ScrollUtil" },
  setupBinding = { "BindingButtonTemplate_SetupBindingButton" },
}

local KEYS = WFJ.LabelTree.set(WFJ.SettingsKeys and WFJ.SettingsKeys.options)
local ONLY = { only = KEYS }
-- The tooltip also shows the muted-account paragraph the chat option appends, red-wrapped after its own
-- tooltip (GetDisabledChatTooltip, blizzard_settingsdefinitions_frame/social.lua:21–29; the `paragraphs` form with
-- a colour-wrapped part), and a graphics option's "Recommended: <value>" line (the `colon` form)
local TIP_KEYS = {}
for key in pairs(KEYS) do TIP_KEYS[key] = true end
TIP_KEYS.OPTION_TOOLTIP_DISABLE_CHAT_ACCOUNT_MUTE = true
-- Build 1.60.1.70009 appends an age-restriction paragraph in the same slot (social.lua:27), same form
TIP_KEYS.OPTION_TOOLTIP_DISABLE_CHAT_AGE_RESTRICTED_MINOR = true
TIP_KEYS.OPTION_TOOLTIP_DISABLE_CHAT_AGE_RESTRICTED_UNVERIFIED = true
TIP_KEYS.VIDEO_OPTIONS_RECOMMENDED = true
local TIP = { only = TIP_KEYS }

local function get(key) return Compat.get(SURFACE, key) end

-- true when `category` belongs to the AddOns tab (an addon's name and page).
local function isAddOn(category)
  local set = get("addOnSet")
  if set == nil or type(category) ~= "table" or type(category.GetCategorySet) ~= "function" then return false end
  local ok, value = pcall(category.GetCategorySet, category)
  return ok and value == set
end

-- true while the search box holds text: the list then shows search results, not the current category's page.
local function searching()
  local search = get("search")
  if type(search) ~= "table" or type(search.HasText) ~= "function" then return false end
  local ok, has = pcall(search.HasText, search)
  return ok and has == true
end

-- true while the list shows an addon's page (a search is decided per row, below).
local function addOnPage()
  local frame = get("frame")
  if type(frame) ~= "table" or type(frame.GetCurrentCategory) ~= "function" or searching() then return false end
  local ok, category = pcall(frame.GetCurrentCategory, frame)
  return ok and isAddOn(category)
end

-- Search results mix every category's options: each group follows a header row the client builds with
-- CreateSettingsListSearchCategoryInitializer(category), template SettingsListSearchCategoryTemplate and data
-- { category = … } (blizzard_settings_shared/blizzard_settingslist.lua:36–38; blizzard_settingspanel.lua:612–680).
-- → the category of the group `elementData` sits in: the nearest such header at or above it in the list's data, or
-- nil when that cannot be read (the row is then left as written).
local SEARCH_HEADER = "SettingsListSearchCategoryTemplate"
local function searchCategory(elementData)
  local box = get("list")
  if type(box) ~= "table" or type(box.GetDataProvider) ~= "function" then return nil end
  local ok, provider = pcall(box.GetDataProvider, box)
  if not ok or type(provider) ~= "table" or type(provider.FindIndex) ~= "function"
      or type(provider.Find) ~= "function" then
    return nil
  end
  local found, index = pcall(provider.FindIndex, provider, elementData)
  if not found or type(index) ~= "number" then return nil end
  for i = index, 1, -1 do
    local okFind, element = pcall(provider.Find, provider, i)
    if okFind and type(element) == "table" and element.frameTemplate == SEARCH_HEADER then
      return type(element.data) == "table" and element.data.category or nil
    end
  end
  return nil
end

-- What a row walk leaves alone: a binding row's key buttons (key names), a slider's value labels (rewritten on every
-- drag, by no method of the row), the raid-frame / nameplate previews (unit names).
local function skip(frame)
  if frame.SelectedHighlight ~= nil or frame.selectedHighlight ~= nil then return true end
  if type(frame.Slider) == "table" and type(frame.RightText) == "table" then return true end
  if type(frame.GetParent) ~= "function" then return false end
  local ok, parent = pcall(frame.GetParent, frame)
  return ok and type(parent) == "table" and (parent.RaidFrame == frame or parent.NamePlate == frame)
end
local ROW = { only = KEYS, skip = skip }

-- ScrollUtil's initialized-frame callback: (owner, frame, elementData) for a new row, (frame, elementData) for the
-- iterateExisting pass. Returns nothing: ForEachFrame stops at the first truthy return (see UI/Raid.onRow).
local function rowOf(a, b, c)
  if a == SettingsPanel then return b, c end
  return a, b
end

function SettingsPanel.onRow(a, b, c)
  local row, elementData = rowOf(a, b, c)
  if type(row) ~= "table" or addOnPage() then return end
  if searching() then -- a result row: only under a Blizzard category's header, never an addon's
    local category = searchCategory(elementData)
    if category == nil or isAddOn(category) then return end
  end
  WFJ.LabelTree.show(SURFACE, row, ROW)
end

function SettingsPanel.onCategoryRow(a, b, c)
  local row, elementData = rowOf(a, b, c)
  if type(row) ~= "table" then return end
  local data = type(elementData) == "table" and elementData.data or nil
  if type(data) == "table" and isAddOn(data.category) then return end
  WFJ.LabelTree.show(SURFACE, row, ONLY)
end

-- hooksecurefunc target (SettingsPanel:DisplayLayout). → 1 | 0
function SettingsPanel.onLayout()
  if addOnPage() then
    WFJ.SurfaceState.drop(SURFACE, "header")
    return 0
  end
  return WFJ.Labels.show(SURFACE, "header", get("header"), nil, ONLY)
end

-- hooksecurefunc target (SettingsPanel:SetOutputText). → 1 | 0
function SettingsPanel.onOutput()
  return WFJ.Labels.show(SURFACE, "output", get("output"), nil, ONLY)
end

-- The labels the client writes at load (the title again on every OnShow). → the number of dictionary words found.
function SettingsPanel.showStatic()
  local items = {}
  for _, key in ipairs({ "title", "close", "apply", "defaults" }) do items[#items + 1] = { key, get(key), ONLY } end
  local n = WFJ.Labels.showAll(STATIC, items)
  for _, key in ipairs({ "gameTab", "addOnsTab" }) do n = n + WFJ.LabelTree.show(STATIC, get(key), ONLY) end
  return n
end

-- HookScript target (SettingsPanel OnShow): the static labels, and every row already built (a row the client did
-- not re-initialize keeps its record; one it rewrote is taken again).
function SettingsPanel.onShow()
  SettingsPanel.showStatic()
  SettingsPanel.onLayout()
  for _, item in ipairs({ { "list", SettingsPanel.onRow }, { "categories", SettingsPanel.onCategoryRow } }) do
    local box = get(item[1])
    if type(box) == "table" and type(box.ForEachFrame) == "function" then box:ForEachFrame(item[2]) end
  end
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
-- A binding row's key buttons hold key names and are never walked, but an empty slot shows
-- GRAY_FONT_COLOR-wrapped NOT_BOUND ("Not Bound"), written by the GLOBAL BindingButtonTemplate_SetupBindingButton
-- (blizzard_sharedxml/bindingutil.lua:216–231, called by name from blizzard_keybindings.lua:377–381). A post-hook
-- shows only that word (the `wrapped` form); a key name never matches it. → 1 | 0
local NOT_BOUND = { only = { "NOT_BOUND" } }
local keyButtonKey = WFJ.Labels.keyer("keybutton.")
function SettingsPanel.onSetupBinding(_, button)
  if type(button) ~= "table" then return 0 end
  return WFJ.Labels.show(SURFACE, keyButtonKey(button), button, nil, NOT_BOUND)
end

function SettingsPanel.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  local frame = get("frame")
  if hooked or type(frame) ~= "table" or type(get("list")) ~= "table" then return false end
  hooked = true
  if type(frame.DisplayLayout) == "function" then hooksecurefunc(frame, "DisplayLayout", SettingsPanel.onLayout) end
  if type(frame.SetOutputText) == "function" then hooksecurefunc(frame, "SetOutputText", SettingsPanel.onOutput) end
  if type(frame.HookScript) == "function" then frame:HookScript("OnShow", SettingsPanel.onShow) end
  local util = get("scrollUtil")
  if type(util) == "table" and type(util.AddInitializedFrameCallback) == "function" then
    util.AddInitializedFrameCallback(get("list"), SettingsPanel.onRow, SettingsPanel, true)
    if type(get("categories")) == "table" then
      util.AddInitializedFrameCallback(get("categories"), SettingsPanel.onCategoryRow, SettingsPanel, true)
    end
  end
  WFJ.TooltipLines.follow(TOOLTIP, get("tooltip"), TIP, function() return not addOnPage() end)
  if type(get("setupBinding")) == "function" then
    hooksecurefunc("BindingButtonTemplate_SetupBindingButton", SettingsPanel.onSetupBinding)
  end
  SettingsPanel.showStatic()
  return true
end
