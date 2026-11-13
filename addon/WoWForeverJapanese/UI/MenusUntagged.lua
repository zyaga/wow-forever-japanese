-- UI/MenusUntagged.lua: the dropdown menus whose generator sets no tag (ADR-033, ADR-088): the Options window's
-- dropdowns (Settings.InitDropdown, blizzard_settings_shared/blizzard_settings.lua:563–581) and two context menus.
-- Edit Mode's setting dropdowns are never reached: Edit Mode stays as the client writes it (ADR-069).
-- Like every menu (UI/Menus), these are written once the client has shown them, never while it builds them. The
-- client fires no "Menu.OpenMenuTag" for a menu without a tag (blizzard_menu/menu.lua:2453-2459), so this module only
-- recognises a menu before it opens and records its owner region; UI/Menus asks for it (MenusUntagged.specFor) on
-- "MenuProxy.OnShow", where the menu frame reports that owner (GetOwnerRegion, menu.lua:1906–1908). Nothing here
-- writes to a menu description.
-- - The Options dropdowns are recorded as the client sets them up: Settings.InitDropdown is called through the
--   Settings table (blizzard_settingcontrols.lua:903, 1621; blizzard_settingsdefinitions_shared/graphics.lua:315), so
--   a post-hook on it sees every one. Each menu matches only its window's keys (its spec below): a font or a locale
--   name is no key and stays English (names stay in English).
-- - Untagged *context* menus: MenuUtil.CreateContextMenu builds the root description and calls
--   Menu.PopulateDescription (the generator, then SecureModifyMenu, which returns at once on no tag) before it opens
--   the menu (blizzard_menu/menuutil.lua:151–161; menu.lua:2751–2765). A post-hook on Menu.PopulateDescription reads
--   the populated, untagged description and records its owner when one of two openers made it:
--     the Group Finder's search-entry menu (LFGBrowseMixin:CreateSearchEntryMenu, blizzard_groupfinder_vanillastyle/
--     blizzard_lfgvanilla_browse.lua:975–1007): its owner is an unnamed frame and its generator an anonymous closure,
--     so it is recognised by an entry whose text is LFG_LIST_REPORT_GROUP_FOR or REPORT_GROUP_FINDER_ADVERTISEMENT
--     (both have a space: never a character name); its first element, the leader's name, is its title;
--     the crafting-orders recipe list's (…customerordersrecipelist.lua:96–97, 115–117): the owner is the list element
--     and the generator its own contextMenuGenerator (…customerordersbrowseorders.lua:139–155).
local _, WFJ = ...
local MenusUntagged = {}
WFJ.MenusUntagged = MenusUntagged

local Compat = WFJ.Compat
local DECLARE = "help.menus.untagged"

-- Menus whose generator sets no tag. Each matches only its window's keys (UI/SettingsKeys); the LFG search entry's
-- first element is the leader's name (blizzard_lfgvanilla_browse.lua:1430–1446 for GROUP_INVITE). UI/Menus reads
-- these specs like its own tags.
local SETTINGS_KEYS = WFJ.SettingsKeys or {}
-- The Options window's dropdown entries: the window's keys plus the Text on Target menu's "Effects" (an owned key,
-- combatoverrides.lua:213), which the window's own labels must not take: there "Effects" is the volume slider.
local SETTINGS_MENU_KEYS = { "SHOW_TARGET_EFFECTS" }
for _, key in ipairs(SETTINGS_KEYS.options or {}) do SETTINGS_MENU_KEYS[#SETTINGS_MENU_KEYS + 1] = key end
-- The Combat page's "Text on Me" checkboxes: each one's hover is its label as the title and its tooltip as the line
-- (Settings.CreateDropdownCheckbox's SetTooltip, blizzard_settings_shared/blizzard_settings.lua:508–513; the pairs
-- at blizzard_settingsdefinitions_frame/mainline/combatoverrides.lua:75–87).
local TEXT_ON_ME_TOOLTIPS = {
  "COMBAT_TEXT_SHOW_DODGE_PARRY_MISS_TEXT", "OPTION_TOOLTIP_COMBAT_TEXT_SHOW_DODGE_PARRY_MISS",
  "COMBAT_TEXT_SHOW_RESISTANCES_TEXT", "OPTION_TOOLTIP_COMBAT_TEXT_SHOW_RESISTANCES",
  "COMBAT_TEXT_SHOW_REPUTATION_TEXT", "OPTION_TOOLTIP_COMBAT_TEXT_SHOW_REPUTATION",
  "COMBAT_TEXT_SHOW_REACTIVES_TEXT", "OPTION_TOOLTIP_COMBAT_TEXT_SHOW_REACTIVES",
  "COMBAT_TEXT_SHOW_FRIENDLY_NAMES_TEXT", "OPTION_TOOLTIP_COMBAT_TEXT_SHOW_FRIENDLY_NAMES",
  "COMBAT_TEXT_SHOW_COMBAT_STATE_TEXT", "OPTION_TOOLTIP_COMBAT_TEXT_SHOW_COMBAT_STATE",
  "SHOW_COMBAT_HEALING_ABSORB_SELF", "OPTION_TOOLTIP_SHOW_COMBAT_HEALING_ABSORB_SELF",
  "COMBAT_TEXT_SHOW_COMBO_POINTS_TEXT", "OPTION_TOOLTIP_COMBAT_TEXT_SHOW_COMBO_POINTS",
  "COMBAT_TEXT_SHOW_LOW_HEALTH_MANA_TEXT", "OPTION_TOOLTIP_COMBAT_TEXT_SHOW_LOW_HEALTH_MANA",
  "COMBAT_TEXT_SHOW_ENERGIZE_TEXT", "OPTION_TOOLTIP_COMBAT_TEXT_SHOW_ENERGIZE",
  "COMBAT_TEXT_SHOW_PERIODIC_ENERGIZE_TEXT", "OPTION_TOOLTIP_COMBAT_TEXT_SHOW_PERIODIC_ENERGIZE",
  "COMBAT_TEXT_SHOW_HONOR_GAINED_TEXT", "OPTION_TOOLTIP_COMBAT_TEXT_SHOW_HONOR_GAINED",
  "COMBAT_TEXT_SHOW_AURAS_TEXT", "OPTION_TOOLTIP_COMBAT_TEXT_SHOW_AURAS" }
-- Under tags of this module's own: the client never fires "Menu.OpenMenuTag" with one, so only specFor reaches them.
local UNTAGGED = {
  SETTINGS_DROPDOWN = { source = "blizzard_settings.lua:563", keys = SETTINGS_MENU_KEYS,
    tooltips = TEXT_ON_ME_TOOLTIPS },
  CONTEXT_LFG_SEARCH_ENTRY = { source = "blizzard_lfgvanilla_browse.lua:1014", titleIsName = true,
    keys = { "SEND_MESSAGE", "GROUP_INVITE", "LFG_LIST_REPORT_GROUP_FOR", "REPORT_GROUP_FINDER_ADVERTISEMENT" } },
  CONTEXT_CUSTOMER_ORDER_RECIPE = { source = "blizzard_professionscustomerordersbrowseorders.lua:142",
    keys = { "BATTLE_PET_FAVORITE", "BATTLE_PET_UNFAVORITE" } },
}
for tag, spec in pairs(UNTAGGED) do WFJ.Menus.TAGS[tag] = spec end

-- owner region → tag: the Options dropdowns once set up, a context menu's owner each time it is populated
local owners = setmetatable({}, { __mode = "k" })

-- Records one dropdown for `tag` (a Menus.TAGS key of an untagged menu). → true when newly recorded
function MenusUntagged.hookDropdown(dropdown, tag)
  if type(dropdown) ~= "table" or owners[dropdown] then return false end
  owners[dropdown] = tag
  return true
end

-- The tag recorded for a menu frame's owner region. → tag | nil
function MenusUntagged.specFor(owner)
  return owner ~= nil and owners[owner] or nil
end

local function secret(value) return WFJ.SurfaceState.secret(value) end

-- The recognition behind onPopulate. → the pseudo-tag recorded, or nil
local function populate(generator, owner, desc)
  if owner == nil or type(desc) ~= "table" or type(desc.GetTag) ~= "function" or desc:GetTag() ~= nil then
    return nil
  end
  if type(desc.EnumerateElementDescriptions) ~= "function" then return nil end
  if type(owner) == "table" and generator ~= nil and owner.contextMenuGenerator == generator then
    owners[owner] = "CONTEXT_CUSTOMER_ORDER_RECIPE"
    return "CONTEXT_CUSTOMER_ORDER_RECIPE"
  end
  local report, advert = Compat.get(DECLARE, "reportGroup"), Compat.get(DECLARE, "reportAdvert") -- the client's English
  -- an element description's text: MenuUtil.GetElementText (menuutil.lua:176–178) when the client has it
  local util = Compat.get(DECLARE, "menuUtil")
  local textOf = type(util) == "table" and type(util.GetElementText) == "function" and util.GetElementText
    or function(d) return type(d) == "table" and d.text or nil end
  for _, child in desc:EnumerateElementDescriptions() do
    local text = textOf(child)
    if not secret(text) and type(text) == "string" and (text == report or text == advert) then
      owners[owner] = "CONTEXT_LFG_SEARCH_ENTRY"
      return "CONTEXT_LFG_SEARCH_ENTRY"
    end
  end
  return nil
end

local reported = {} -- error text → true: each distinct error is recorded once, not on every menu opened

-- The Menu.PopulateDescription post-hook (generator, ownerRegion, description, …). It runs for every menu the client
-- opens, so it never raises: an error is recorded where the load errors are (WFJ.initErrors, surface
-- "menus.untagged", printed by /wfj debug) and the menu opens in English. → the pseudo-tag recorded, or nil
function MenusUntagged.onPopulate(generator, owner, desc)
  local ok, tag = pcall(populate, generator, owner, desc)
  if ok then return tag end
  local err = tostring(tag)
  if not reported[err] then
    reported[err] = true
    WFJ.initErrors = WFJ.initErrors or {}
    WFJ.initErrors[#WFJ.initErrors + 1] = { surface = "menus.untagged", err = err }
  end
  return nil
end

local hooked = false

-- Called by Main after Menus.init. → the number of setup functions hooked (0–2)
function MenusUntagged.init()
  Compat.declare(DECLARE, "settings", { "Settings" })
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
  return n
end
