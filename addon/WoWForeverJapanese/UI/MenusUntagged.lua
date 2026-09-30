-- UI/MenusUntagged.lua: the dropdown menus whose generator sets no tag (ADR-033): the Options window's
-- dropdowns (Settings.InitDropdown, blizzard_settings_shared/blizzard_settings.lua:552–568) and Edit Mode's setting
-- dropdowns (EditModeSettingDropdownMixin:SetupSetting, blizzard_editmode/shared/editmodetemplates.lua:22–53).
-- Menu.ModifyMenu only reaches a tagged description (SecureModifyMenu returns on no tag, blizzard_menu/menu.lua:
-- 2708–2717), so these are reached through the dropdown button itself: OpenMenu always regenerates (GenerateMenu
-- populates a new root description, then RegisterMenu(rootDescription) stores it), and only then asks the manager to
-- open it (blizzard_menu/dropdownbutton.lua:108–131, 178–207, 255–264). A post-hook on that dropdown's RegisterMenu
-- therefore holds the populated description at the point a ModifyMenu callback would, before any element frame
-- exists, and UI/Menus' walk adds the same initializers (so the menu is laid out with the Japanese).
-- The other candidate, the "MenuProxy.OnShow" registry event (menu.lua:1802–1806), fires after the menu is laid out
-- in English, which would need a second layout pass: not used.
-- The dropdowns are found as the client sets them up: Settings.InitDropdown is called through the Settings table
-- (blizzard_settingcontrols.lua:873, 1589; blizzard_settingsdefinitions_shared/graphics.lua:319), so a post-hook on
-- it sees every one; Edit Mode's rows come from the settings dialog's pool after login, each copying the mixin's
-- (hooked) SetupSetting when it is made. Each menu matches only its window's keys (Menus.UNTAGGED): a font, a
-- locale or a layout name is no key and stays English (names stay in English).
-- Untagged *context* menus: MenuUtil.CreateContextMenu builds the root description, calls
-- Menu.PopulateDescription (the generator, then SecureModifyMenu, which returns at once on no tag) and only then
-- opens the menu (blizzard_menu/menuutil.lua:151–161; menu.lua:2708–2722); it looks the field up at call time, so a
-- post-hook on Menu.PopulateDescription holds the populated, untagged description before any element frame exists:
-- the point a ModifyMenu callback runs at, so the menu is laid out with the Japanese. The hook also runs for every
-- tagged menu and DropdownButton: it acts only on an untagged description one of two openers made:
--   the Group Finder's search-entry menu (LFGBrowseMixin:CreateSearchEntryMenu, blizzard_groupfinder_vanillastyle/
--   blizzard_lfgvanilla_browse.lua:948–980): its owner is an undefined frame and its generator an anonymous closure,
--   so it is recognised by an entry whose text is LFG_LIST_REPORT_GROUP_FOR or REPORT_GROUP_FINDER_ADVERTISEMENT
--   (both have a space: never a character name); its first element, the leader's name, is the title (titleIsName);
--   the crafting-orders recipe list's (…customerordersrecipelist.lua:96–97, 115–117): the owner is the list element
--   and the generator its own contextMenuGenerator (…customerordersbrowseorders.lua:139–155).
-- Rejected: a post-hook on LFGBrowseFrame.CreateSearchEntryMenu (after layout, needs a relayout);
-- replacing the method (taints the invite path); the "MenuProxy.OnShow" event (after layout).
local _, WFJ = ...
local MenusUntagged = {}
WFJ.MenusUntagged = MenusUntagged

local Compat = WFJ.Compat
local DECLARE = "help.menus.untagged"

-- Menus whose generator sets no tag, walked through the dropdown's own RegisterMenu; never registered
-- with Menu.ModifyMenu. Each matches only its window's keys (UI/SettingsKeys).
-- Two untagged context menus, walked from the Menu.PopulateDescription post-hook (the LFG search
-- entry's title is the leader's name; blizzard_lfgvanilla_browse.lua:1403–1419 for GROUP_INVITE). UI/Menus reads
-- these specs like its own tags (Menus.showElement / onMenu).
local SETTINGS_KEYS = WFJ.SettingsKeys or {}
WFJ.Menus.UNTAGGED = {
  SETTINGS_DROPDOWN = { source = "blizzard_settings.lua:552", keys = SETTINGS_KEYS.options or {} },
  EDIT_MODE_DROPDOWN = { source = "editmodetemplates.lua:22", keys = SETTINGS_KEYS.editmode or {} },
  CONTEXT_LFG_SEARCH_ENTRY = { source = "blizzard_lfgvanilla_browse.lua:954", titleIsName = true,
    keys = { "SEND_MESSAGE", "GROUP_INVITE", "LFG_LIST_REPORT_GROUP_FOR", "REPORT_GROUP_FINDER_ADVERTISEMENT" } },
  CONTEXT_CUSTOMER_ORDER_RECIPE = { source = "blizzard_professionscustomerordersbrowseorders.lua:142",
    keys = { "BATTLE_PET_FAVORITE", "BATTLE_PET_UNFAVORITE" } },
}

local owners = setmetatable({}, { __mode = "k" }) -- dropdown → its pseudo-tag, once hooked

-- Hooks one dropdown's RegisterMenu for `tag` (a Menus.UNTAGGED key). → true when newly hooked
function MenusUntagged.hookDropdown(dropdown, tag)
  if type(dropdown) ~= "table" or owners[dropdown] or type(dropdown.RegisterMenu) ~= "function" then return false end
  owners[dropdown] = tag
  hooksecurefunc(dropdown, "RegisterMenu", function(self, root) WFJ.Menus.onMenu(owners[self], root, nil) end)
  return true
end

-- An element description's text: MenuUtil.GetElementText (menuutil.lua:176–178) when the client has it.
local function elementText(desc)
  local util = Compat.get(DECLARE, "menuUtil")
  if type(util) == "table" and type(util.GetElementText) == "function" then return util.GetElementText(desc) end
  return type(desc) == "table" and desc.text or nil
end

-- The walk behind onPopulate. → the number of elements given ours
local function populate(generator, owner, desc)
  if type(desc) ~= "table" or type(desc.GetTag) ~= "function" or desc:GetTag() ~= nil then return 0 end
  if type(desc.EnumerateElementDescriptions) ~= "function" then return 0 end
  if type(owner) == "table" and generator ~= nil and owner.contextMenuGenerator == generator then
    return WFJ.Menus.onMenu("CONTEXT_CUSTOMER_ORDER_RECIPE", desc, nil)
  end
  local report, advert = Compat.get(DECLARE, "reportGroup"), Compat.get(DECLARE, "reportAdvert") -- the client's English
  local title, found, first = nil, false, true
  for _, child in desc:EnumerateElementDescriptions() do
    local text = elementText(child)
    if first then title, first = text, false end
    if type(text) == "string" and (text == report or text == advert) then found = true end
  end
  if not found then return 0 end
  return WFJ.Menus.onMenu("CONTEXT_LFG_SEARCH_ENTRY", desc, { name = type(title) == "string" and title or nil })
end

local reported = {} -- error text → true: each distinct error is recorded once, not on every menu opened

-- The Menu.PopulateDescription post-hook (generator, ownerRegion, description, …). It runs for every menu the client
-- opens, so it never raises: an error is recorded where the load errors are (WFJ.initErrors, surface
-- "menus.untagged", printed by /wfj debug) and the menu opens in English. → the number of elements given ours
function MenusUntagged.onPopulate(generator, owner, desc)
  local ok, n = pcall(populate, generator, owner, desc)
  if ok then return n end
  local err = tostring(n)
  if not reported[err] then
    reported[err] = true
    WFJ.initErrors = WFJ.initErrors or {}
    WFJ.initErrors[#WFJ.initErrors + 1] = { surface = "menus.untagged", err = err }
  end
  return 0
end

local hooked = false

-- Called by Main after Menus.init. → the number of setup functions hooked (0–3)
function MenusUntagged.init()
  Compat.declare(DECLARE, "settings", { "Settings" })
  Compat.declare(DECLARE, "editMode", { "EditModeSettingDropdownMixin" })
  Compat.declare(DECLARE, "menu", { "Menu" })
  Compat.declare(DECLARE, "menuUtil", { "MenuUtil" })
  Compat.declare(DECLARE, "reportGroup", { "LFG_LIST_REPORT_GROUP_FOR" })
  Compat.declare(DECLARE, "reportAdvert", { "REPORT_GROUP_FINDER_ADVERTISEMENT" })
  if hooked then return 0 end
  hooked = true
  local n = 0
  local menu = Compat.get(DECLARE, "menu")
  if type(menu) == "table" and type(menu.PopulateDescription) == "function" then
    hooksecurefunc(menu, "PopulateDescription", MenusUntagged.onPopulate)
    n = n + 1
  end
  local settings = Compat.get(DECLARE, "settings")
  if type(settings) == "table" and type(settings.InitDropdown) == "function" then
    hooksecurefunc(settings, "InitDropdown", function(dropdown)
      MenusUntagged.hookDropdown(dropdown, "SETTINGS_DROPDOWN")
    end)
    n = n + 1
  end
  local editMode = Compat.get(DECLARE, "editMode")
  if type(editMode) == "table" and type(editMode.SetupSetting) == "function" then
    hooksecurefunc(editMode, "SetupSetting", function(row)
      MenusUntagged.hookDropdown(type(row) == "table" and row.Dropdown or nil, "EDIT_MODE_DROPDOWN")
    end)
    n = n + 1
  end
  return n
end
