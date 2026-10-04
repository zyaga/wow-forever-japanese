-- UI/SpellBook.lua: the spellbook's fixed words (surface "spellbook", area "ui", ADR-016, ADR-029).
-- The book is PlayerSpellsFrame.SpellBookFrame in the load-on-demand Blizzard_PlayerSpells (blizzard_playerspells.toc:
-- 2, :32–46), set up through WFJ.LoadOnDemand.when. Every child is a parentKey, so every name is a dotted Compat
-- candidate.
-- - Title: PlayerSpellsFrameMixin:UpdateFrameTitle → self:SetTitle(SPELLBOOK | TALENTS | SPECIALIZATION |
--   TALENTS_INSPECT_FORMAT) [verified: blizzard_playerspells/blizzard_playerspellsframe.lua:155–171] writes
--   self.TitleContainer.TitleText [verified: blizzard_sharedxml/portraitframe.lua:4–14]. The host serves the talents
--   tab too, so this module owns the title (surface "playerspells", released on the host's OnHide).
--   TALENTS_LINK_FORMAT carries a spec and a class name; both are kept as written.
-- - Page: PagingControlsMixin:UpdateControls → PageText:SetFormattedText(PAGE_NUMBER_WITH_MAX | PAGE_NUMBER)
--   [verified: blizzard_pagedcontent/blizzard_pagingcontrols.lua:110–127, xml:40–42].
--   The title and the page line are followed by UI/TextWatch, not by hooks on UpdateFrameTitle / UpdateControls:
--   those run inside the spellbook's own passes, and nothing of this addon runs there.
-- - The page's spell items and category / search-result headers are left exactly as the client writes them. When it
--   refills an item, Blizzard measures the item's three lines (TrimTextSpace: GetText, GetStringHeight, GetLineHeight,
--   spellbook/blizzard_spellbookitem.lua:163–180) and the page measures its headers (ApplyLayout). A FontString this
--   addon has written Japanese or its font into returns those measurements tainted by this addon [traced in game,
--   ADR-058], so the refill runs tainted: it writes the item's actionBarStatus (:312–325) and, on a hover, the action
--   bars' highlight marks and layout (:509–566), and the bars are then blocked in combat
--   (docs/architecture/client-limits.md).
-- - Settings menu: the "show all spell ranks" checkbox is a Menu element under the tag "MENU_SPELL_BOOK_SETTINGS"
--   (spellbook/blizzard_spellbookframe.lua:191, 205–226; camelot/spellbook/blizzard_spellbookframe.lua:9–43; not for
--   Rogue / Warrior). The checkbox initializer closes over the English (blizzard_menu/menutemplates.lua:341–354,
--   mainline/menuvariants.lua:9–22), so rewriting the description's text would not show; Menu.ModifyMenu (menu.lua:
--   2724) adds an initializer of our own to each element, which runs after the client's and shows button.fontString
--   restricted to MENU_KEYS (surface "spellbook.menu"). Menu buttons are pooled and their compositor resets the
--   fontString with SetFontObject on reuse (blizzard_menu/compositor.lua:66–74, 388), so a record must not outlive
--   its button: a resetter of our own (menu.lua:455–457), which MenuMixin:DiscardChildFrames runs on every element
--   frame before the compositor detaches and the frame is released (menu.lua:1667–1697), drops that button's record.
--   The surface is also forgotten when the book hides.
-- - The search box's placeholder, SearchBox.Instructions, is written once by SearchBoxTemplate_OnLoad from the
--   KeyValue instructionText = SPELLBOOK_SEARCH_INSTRUCTIONS (spellbookframe.xml:103–107; blizzard_sharedxml/shared/
--   inputbox/inputboxtemplates.lua:175–178) and only shown / hidden after that (:131–133): a static label (never
--   the EditBox's own text).
-- - The "Hide Passives" entry's tooltip while searching (SPELLBOOK_SEARCH_HIDE_PASSIVES_DISABLED,
--   spellbookframe.lua:192–197) is built by MenuUtil.ShowTooltipEx on GameTooltip with the menu button as owner, then
--   Show() (blizzard_menu/menuutil.lua:98–106, 293–298): each settings-menu button is a help-tooltip owner restricted
--   to that key.
-- Release the page and the menu on the book's OnHide.
local _, WFJ = ...
local SpellBook = {}
WFJ.SpellBook = SpellBook

local SURFACE = "spellbook"
local STATIC = "spellbook.static"
SpellBook.SURFACE = SURFACE
local Compat = WFJ.Compat

local HOST = "playerspells" -- the PlayerSpellsFrame title (spellbook and talents tabs)
local MENU = "spellbook.menu"
SpellBook.HOST, SpellBook.MENU = HOST, MENU
local PLAYER_SPELLS = "Blizzard_PlayerSpells"
local MENU_TAG = "MENU_SPELL_BOOK_SETTINGS"

-- Keys each widget may show (a widget restricted to them never takes another dictionary word).
-- A linked build's title, TALENTS_LINK_FORMAT:format(spec, class) (blizzard_playerspellsframe.lua:162): both
-- names kept as written
local HOST_TITLE_KEYS = { SPELLBOOK = true, TALENTS = true, SPECIALIZATION = true, TALENTS_INSPECT_FORMAT = true,
  TALENTS_LINK_FORMAT = true }
local PAGE_WITH_MAX_KEYS = { PAGE_NUMBER = true, PAGE_NUMBER_WITH_MAX = true }
local SEARCH_KEYS = { SPELLBOOK_SEARCH_INSTRUCTIONS = true }
local MENU_TOOLTIP_KEYS = { SPELLBOOK_SEARCH_HIDE_PASSIVES_DISABLED = true }
local MENU_KEYS = { SHOW_ALL_SPELL_RANKS = true, SPELLBOOK_FILTER_PASSIVES = true, SPELLBOOK_USE_FLYOUTS = true,
  SPELLBOOK_COMPACT_VIEW = true }
SpellBook.CAMELOT_KEYS = { title = HOST_TITLE_KEYS, page = PAGE_WITH_MAX_KEYS, menu = MENU_KEYS, search = SEARCH_KEYS,
  menuTooltip = MENU_TOOLTIP_KEYS }

-- Widgets this module must never record: none by name (no spell item is read or written).
SpellBook.NEVER_TOUCH = {}

-- The host title, when the client wrote it. → 1 | 0
function SpellBook.showTitle()
  return WFJ.Labels.showAll(HOST, { { "title", Compat.get(SURFACE, "title"), { only = HOST_TITLE_KEYS } } })
end

-- The page text, when the client wrote it. → 1 | 0
function SpellBook.showPageText()
  local n = WFJ.Labels.show(SURFACE, "page", Compat.get(SURFACE, "pageText"), nil, { only = PAGE_WITH_MAX_KEYS })
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- The search box's placeholder (static). → 1 | 0
function SpellBook.showSearchStatic()
  return WFJ.Labels.showAll(STATIC, { { "searchInstructions", Compat.get(SURFACE, "searchInstructions"),
    { only = SEARCH_KEYS } } })
end

-- One settings-menu button, after the client's initializer wrote its English into button.fontString (keyed by that
-- label: menu buttons are pooled). → 1 | 0
function SpellBook.showMenuButton(button)
  local fs = type(button) == "table" and button.fontString or nil
  local en = type(fs) == "table" and type(fs.GetText) == "function" and fs:GetText() or nil
  WFJ.HelpTooltip.register(button, { only = MENU_TOOLTIP_KEYS }) -- the entry's own tooltip (Hide Passives)
  if type(en) ~= "string" or en == "" then return 0 end
  -- through Labels.menuText: the Menu compositor forbids SetFont on its FontStrings
  return WFJ.Labels.show(MENU, "menu." .. en, WFJ.Labels.menuText(fs), nil, { only = MENU_KEYS })
end

-- The resetter: the menu is discarding this button (closing, or regenerating). → the number of records dropped
function SpellBook.resetMenuButton(button)
  local fs = type(button) == "table" and WFJ.Labels.menuText(button.fontString) or nil
  if fs == nil then return 0 end
  local gone = {}
  for key, rec in pairs(WFJ.SurfaceState.records(MENU)) do
    if rec.fs == fs then gone[#gone + 1] = key end
  end
  for _, key in ipairs(gone) do WFJ.SurfaceState.drop(MENU, key) end
  WFJ.Render.updateBanner(MENU)
  return #gone
end

-- Menu.ModifyMenu callback (owner, rootDescription, contextData). → the number of elements given our initializer
function SpellBook.onSettingsMenu(_, root)
  if type(root) ~= "table" or type(root.EnumerateElementDescriptions) ~= "function" then return 0 end
  local n = 0
  for _, desc in root:EnumerateElementDescriptions() do
    if type(desc) == "table" and type(desc.AddInitializer) == "function" then
      desc:AddInitializer(SpellBook.showMenuButton)
      if type(desc.AddResetter) == "function" then desc:AddResetter(SpellBook.resetMenuButton) end
      n = n + 1
    end
  end
  return n
end

function SpellBook.releaseBook()
  WFJ.Render.forget(MENU)
  return WFJ.Render.release(SURFACE)
end

function SpellBook.releaseHost()
  return WFJ.Render.release(HOST)
end

local function declareCamelot()
  Compat.declare(SURFACE, "host", { "PlayerSpellsFrame" })
  Compat.declare(SURFACE, "book", { "PlayerSpellsFrame.SpellBookFrame" })
  Compat.declare(SURFACE, "modifyMenu", { "Menu.ModifyMenu" })
  Compat.declare(SURFACE, "searchInstructions", { "PlayerSpellsFrame.SpellBookFrame.SearchBox.Instructions" })
  Compat.declare(SURFACE, "title", { "PlayerSpellsFrame.TitleContainer.TitleText" })
  Compat.declare(SURFACE, "pageText", { "PlayerSpellsFrame.SpellBookFrame.PagedSpellsFrame.PagingControls.PageText" })
end

local camelotSetUp, camelotWaiting = false, false

-- The Blizzard_PlayerSpells part: runs once that addon is loaded (now, or on its ADDON_LOADED). Declared again here:
-- a declare clears Compat's memo, which holds `false` for a name looked up before the addon loaded.
function SpellBook.setupCamelot()
  declareCamelot()
  SpellBook.showSearchStatic()
  if camelotSetUp then return false end
  local host, book = Compat.get(SURFACE, "host"), Compat.get(SURFACE, "book")
  if type(host) ~= "table" or type(book) ~= "table" then return false end
  camelotSetUp = true
  if type(host.HookScript) == "function" then host:HookScript("OnHide", SpellBook.releaseHost) end
  if type(book.HookScript) == "function" then book:HookScript("OnHide", SpellBook.releaseBook) end
  WFJ.TextWatch.add(Compat.get(SURFACE, "title"), SpellBook.showTitle)
  WFJ.TextWatch.add(Compat.get(SURFACE, "pageText"), SpellBook.showPageText)
  local modifyMenu = Compat.get(SURFACE, "modifyMenu")
  if type(modifyMenu) == "function" then modifyMenu(MENU_TAG, SpellBook.onSettingsMenu) end
  -- what the client already wrote before this ran (the addon may load after the frame was shown)
  SpellBook.showTitle()
  SpellBook.showPageText()
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init. The book waits on
-- Blizzard_PlayerSpells. → true when it was set up now (the addon was already loaded), false otherwise
function SpellBook.init()
  declareCamelot()
  if camelotWaiting then return false end
  camelotWaiting = true
  return WFJ.LoadOnDemand.when(PLAYER_SPELLS, SpellBook.setupCamelot)
end
