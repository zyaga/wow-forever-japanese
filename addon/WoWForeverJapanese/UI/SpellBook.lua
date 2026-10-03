-- UI/SpellBook.lua: the spellbook's fixed words (surface "spellbook", area "ui", ADR-016, ADR-029).
-- The book is PlayerSpellsFrame.SpellBookFrame in the load-on-demand Blizzard_PlayerSpells (blizzard_playerspells.toc:
-- 2, :32–46), set up through WFJ.LoadOnDemand.when. Every child is a parentKey, so every name is a dotted Compat
-- candidate.
-- - Title: PlayerSpellsFrameMixin:UpdateFrameTitle → self:SetTitle(SPELLBOOK | TALENTS | SPECIALIZATION |
--   TALENTS_INSPECT_FORMAT) [verified: blizzard_playerspells/blizzard_playerspellsframe.lua:155–171], called by
--   method lookup from SetTab (:190) and SetInspecting (:306): hooked on the host frame. SetTitle writes
--   self.TitleContainer.TitleText [verified: blizzard_sharedxml/portraitframe.lua:4–14]. The host serves the talents
--   tab too, so this module owns the one hook (surface "playerspells", released on the host's OnHide).
--   TALENTS_LINK_FORMAT carries a spec and a class name and is not a key here.
-- - Page: PagingControlsMixin:UpdateControls → PageText:SetFormattedText(PAGE_NUMBER_WITH_MAX | PAGE_NUMBER)
--   [verified: blizzard_pagedcontent/blizzard_pagingcontrols.lua:110–127, xml:40–42], called by method lookup
--   (:11, :39, :54): hooked on the book's PagingControls instance.
-- - Spell items are pooled (no globals). SpellBookFrameMixin:OnPagedSpellsUpdate is registered BY REFERENCE
--   (spellbook/blizzard_spellbookframe.lua:46), so an instance hook would miss it; it triggers the EventRegistry event
--   "PlayerSpellsFrame.SpellBookFrame.DisplayedSpellsChanged" (:91) after every page is laid out and initialised
--   (blizzard_pagedcontent/blizzard_pagedcontentframe.lua:494–575). The callback walks ForEachDisplayedSpell (:608–614)
--   and shows each item's SubName (rank / passive / profession rank, SUBTEXT_KEYS) and RequiredLevel
--   (SPELLBOOK_AVAILABLE_AT / SPELLBOOK_TRAINABLE / BOOSTED_CHAR_SPELL_TEMPLOCK) [verified:
--   spellbook/blizzard_spellbookitem.lua:183–252, 295–301]. The subtext can arrive later, inside
--   ContinueWithCancelOnSpellLoad (:190–199), and a data refresh re-runs UpdateVisuals without the event (:81–109), so
--   each item seen gets instance post-hooks on UpdateSubName and UpdateVisuals (both called as self:…). Records are
--   keyed by the item's spell slot (spellBank.slotIndex), never by its position on the page; a slot no longer shown is
--   dropped on the next walk. Item .Name (the spell name) is never read or written, except a flyout's name
--   (showFlyoutName). The subtext is matched only against the rank / passive / profession-rank keys and the listed
--   SpellSubtext:<spellID> fingerprint rows
--   ("Racial Passive", "Summon"): it is client data.
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
-- - Search results: DisplayFullSearchResults groups the results under HEADER elements whose text is a
--   SPELLBOOK_SEARCH_HEADER_* word (spellbook/blizzard_spellbooksearch.lua:5–36, 217–265); SpellBookHeaderMixin:Init
--   writes it to the header's .Text (spellbook/blizzard_spellbooktemplates.lua:3–7). Header frames are laid out with
--   the items, so the same DisplayedSpellsChanged pass walks PagedSpellsFrame:EnumerateFrames()
--   (blizzard_pagedcontentframe.lua:194–196) for frames that are not spell items. Category headers there carry
--   skill-line names, so the walk is restricted to HEADER_KEYS; records are keyed by the header widget.
-- - The search box's placeholder, SearchBox.Instructions, is written once by SearchBoxTemplate_OnLoad from the
--   KeyValue instructionText = SPELLBOOK_SEARCH_INSTRUCTIONS (spellbookframe.xml:103–107; blizzard_sharedxml/shared/
--   inputbox/inputboxtemplates.lua:175–178) and only shown / hidden after that (:131–133): a static label (never
--   the EditBox's own text).
-- - The "Hide Passives" entry's tooltip while searching (SPELLBOOK_SEARCH_HIDE_PASSIVES_DISABLED,
--   spellbookframe.lua:192–197) is built by MenuUtil.ShowTooltipEx on GameTooltip with the menu button as owner, then
--   Show() (blizzard_menu/menuutil.lua:98–106, 293–298): each settings-menu button is a help-tooltip owner restricted
--   to that key.
-- Release the items and page on the book's OnHide.
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
local DISPLAYED_EVENT = "PlayerSpellsFrame.SpellBookFrame.DisplayedSpellsChanged"
local MENU_TAG = "MENU_SPELL_BOOK_SETTINGS"

-- Keys each widget may show (a widget restricted to them never takes another dictionary word).
local SUBTEXT_KEYS = { SPELL_PASSIVE = true, TOOLTIP_TALENT_RANK_CURRENT_ONLY = true, RANK = true, APPRENTICE = true,
  JOURNEYMAN = true, EXPERT = true, ARTISAN = true }
-- The Spell table's own subtexts ("Racial Passive"), fingerprint rows keyed by one spell each; a pet family
-- or a form name ("Cat", "Bear") is a name and is never listed (names stay in English)
for _, id in ipairs({ 2481, 5227, 126, 768, 1229432, 1262975, 1262982, 1263001, 8099, 8100, 8101, 12178 }) do
  SUBTEXT_KEYS["SpellSubtext:" .. id] = true
end
-- "Summon" is also BATTLE_PET_SUMMON's English: the exact entry answers before the fingerprint row, so the key that
-- carries the same Japanese is allowed too (otherwise Summon Imp's subtext stays English)
SUBTEXT_KEYS.BATTLE_PET_SUMMON = true
-- A linked build's title, TALENTS_LINK_FORMAT:format(spec, class) (blizzard_playerspellsframe.lua:162): both
-- names kept as written
local HOST_TITLE_KEYS = { SPELLBOOK = true, TALENTS = true, SPECIALIZATION = true, TALENTS_INSPECT_FORMAT = true,
  TALENTS_LINK_FORMAT = true }
local PAGE_WITH_MAX_KEYS = { PAGE_NUMBER = true, PAGE_NUMBER_WITH_MAX = true }
local REQUIRED_KEYS = { SPELLBOOK_AVAILABLE_AT = true, SPELLBOOK_TRAINABLE = true, BOOSTED_CHAR_SPELL_TEMPLOCK = true }
local HEADER_KEYS = { SPELLBOOK_SEARCH_HEADER_EXACT = true, SPELLBOOK_SEARCH_HEADER_RELATED = true,
  SPELLBOOK_SEARCH_HEADER_NAME = true, SPELLBOOK_SEARCH_HEADER_DESCRIPTION = true,
  SPELLBOOK_SEARCH_HEADER_GENERIC = true, SPELLBOOK_SEARCH_HEADER_RESULTS = true }
local SEARCH_KEYS = { SPELLBOOK_SEARCH_INSTRUCTIONS = true }
local MENU_TOOLTIP_KEYS = { SPELLBOOK_SEARCH_HIDE_PASSIVES_DISABLED = true }
local MENU_KEYS = { SHOW_ALL_SPELL_RANKS = true, SPELLBOOK_FILTER_PASSIVES = true, SPELLBOOK_USE_FLYOUTS = true,
  SPELLBOOK_COMPACT_VIEW = true }
SpellBook.CAMELOT_KEYS = { title = HOST_TITLE_KEYS, page = PAGE_WITH_MAX_KEYS, required = REQUIRED_KEYS,
  menu = MENU_KEYS, header = HEADER_KEYS, search = SEARCH_KEYS, menuTooltip = MENU_TOOLTIP_KEYS }

-- Widgets this module must never record: none by name (a pooled item's .Name, the spell name, is never read).
SpellBook.NEVER_TOUCH = {}

-- The host title after UpdateFrameTitle. → 1 | 0
function SpellBook.showTitle()
  return WFJ.Labels.showAll(HOST, { { "title", Compat.get(SURFACE, "title"), { only = HOST_TITLE_KEYS } } })
end

-- The page text after PagingControls:UpdateControls. → 1 | 0
function SpellBook.showPageText()
  local n = WFJ.Labels.show(SURFACE, "page", Compat.get(SURFACE, "pageText"), nil, { only = PAGE_WITH_MAX_KEYS })
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- An item's spell slot: the logical element its records are keyed by. → "bank.slot" | nil
local function slotOf(item)
  if type(item) ~= "table" or item.slotIndex == nil then return nil end
  return tostring(item.spellBank) .. "." .. tostring(item.slotIndex)
end

-- One item's subtext. → 1 | 0
function SpellBook.showItemSub(item)
  local slot = slotOf(item)
  if not slot then return 0 end
  return WFJ.Labels.show(SURFACE, "sub." .. slot, item.SubName, nil, { only = SUBTEXT_KEYS })
end

-- A flyout item's name (Portal, Summon Demon): a SpellFlyout row, a category rather than a spell, so it is matched
-- in that family only (blizzard_spellbookitem.lua:184, 203). A spell item's name is never read. → 1 | 0
local function showFlyoutName(item, slot)
  local info = item.spellBookItemInfo
  local enum = Compat.resolve("Enum")
  local flyout = type(enum) == "table" and type(enum.SpellBookItemType) == "table" and enum.SpellBookItemType.Flyout
  if type(info) ~= "table" or flyout == nil or info.itemType ~= flyout then
    WFJ.SurfaceState.drop(SURFACE, "name." .. slot) -- a pooled item that showed a flyout before
    return 0
  end
  return WFJ.Labels.show(SURFACE, "name." .. slot, item.Name, nil, WFJ.Labels.families("FlyoutName"))
end

-- One item's subtext, required-level line and, for a flyout, its name. → the number of dictionary words
function SpellBook.showItem(item)
  local slot = slotOf(item)
  if not slot then return 0 end
  return SpellBook.showItemSub(item)
    + WFJ.Labels.show(SURFACE, "req." .. slot, item.RequiredLevel, nil, { only = REQUIRED_KEYS })
    + showFlyoutName(item, slot)
end

-- The pool builds an item and runs Init → UpdateSpellData → UpdateVisuals →
-- UpdateSubName (blizzard_spellbookitem.lua:27–31, 95–109, 183–188) before DisplayedSpellsChanged reaches our walk,
-- so an instance hook added by the walk comes too late for the item's first subtext. SpellBookItemMixin is hooked
-- too: the XML mixin copies its methods when the pool creates a frame, so every frame made after setup carries the
-- hook; frames made before it get instance hooks here (never both).
local mixinHooked = nil -- SpellBookItemMixin, once hooked
local itemHooked = setmetatable({}, { __mode = "k" })
local function hookItem(item)
  if itemHooked[item] then return end
  itemHooked[item] = true
  for method, fn in pairs({ UpdateSubName = SpellBook.showItemSub, UpdateVisuals = SpellBook.showItem }) do
    if type(item[method]) == "function" and not (mixinHooked and item[method] == mixinHooked[method]) then
      hooksecurefunc(item, method, fn)
    end
  end
end

-- → true when the item mixin was hooked
local function hookItemMixin()
  local mixin = Compat.get(SURFACE, "itemMixin")
  if mixinHooked or type(mixin) ~= "table" or type(mixin.UpdateSubName) ~= "function"
      or type(mixin.UpdateVisuals) ~= "function" then
    return false
  end
  hooksecurefunc(mixin, "UpdateSubName", SpellBook.showItemSub)
  hooksecurefunc(mixin, "UpdateVisuals", SpellBook.showItem)
  mixinHooked = mixin
  return true
end

local headerKey = WFJ.Labels.keyer("header.") -- a pooled header frame's record key

-- The search-result headers laid out on this page. → the number shown
local function showHeaders(book, seen)
  local paged = book.PagedSpellsFrame
  if type(paged) ~= "table" or type(paged.EnumerateFrames) ~= "function" then return 0 end
  local n = 0
  for _, frame in paged:EnumerateFrames() do
    local item = type(frame) == "table" and type(frame.HasValidData) == "function" and frame:HasValidData()
    if type(frame) == "table" and not item and frame.Text ~= nil then
      local key = headerKey(frame)
      seen[key] = true
      n = n + WFJ.Labels.show(SURFACE, key, frame.Text, nil, { only = HEADER_KEYS })
    end
  end
  return n
end

-- The EventRegistry callback for DisplayedSpellsChanged (and the setup's first pass). → the number of words shown
function SpellBook.onDisplayedSpells()
  local book = Compat.get(SURFACE, "book")
  if type(book) ~= "table" or type(book.ForEachDisplayedSpell) ~= "function" then return 0 end
  local seen, n = {}, 0
  book:ForEachDisplayedSpell(function(item)
    local slot = slotOf(item)
    if not slot then return end
    seen["sub." .. slot], seen["req." .. slot], seen["name." .. slot] = true, true, true
    hookItem(item)
    n = n + SpellBook.showItem(item)
  end)
  n = n + showHeaders(book, seen)
  local gone = {}
  for key in pairs(WFJ.SurfaceState.records(SURFACE)) do
    if (key:find("^sub%.") or key:find("^req%.") or key:find("^name%.") or key:find("^header%.")) and not seen[key] then
      gone[#gone + 1] = key
    end
  end
  for _, key in ipairs(gone) do WFJ.SurfaceState.drop(SURFACE, key) end
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
  Compat.declare(SURFACE, "paging", { "PlayerSpellsFrame.SpellBookFrame.PagedSpellsFrame.PagingControls" })
  Compat.declare(SURFACE, "eventRegistry", { "EventRegistry" })
  Compat.declare(SURFACE, "modifyMenu", { "Menu.ModifyMenu" })
  Compat.declare(SURFACE, "searchInstructions", { "PlayerSpellsFrame.SpellBookFrame.SearchBox.Instructions" })
  Compat.declare(SURFACE, "title", { "PlayerSpellsFrame.TitleContainer.TitleText" })
  Compat.declare(SURFACE, "pageText", { "PlayerSpellsFrame.SpellBookFrame.PagedSpellsFrame.PagingControls.PageText" })
end

local camelotHooked, camelotWaiting = false, false

-- The Blizzard_PlayerSpells part: runs once that addon is loaded (now, or on its ADDON_LOADED). Declared again here:
-- a declare clears Compat's memo, which holds `false` for a name looked up before the addon loaded.
function SpellBook.setupCamelot()
  declareCamelot()
  SpellBook.showSearchStatic()
  if camelotHooked then return false end
  local host, book = Compat.get(SURFACE, "host"), Compat.get(SURFACE, "book")
  if type(host) ~= "table" or type(book) ~= "table" then return false end
  camelotHooked = true
  if type(host.UpdateFrameTitle) == "function" then hooksecurefunc(host, "UpdateFrameTitle", SpellBook.showTitle) end
  if type(host.HookScript) == "function" then host:HookScript("OnHide", SpellBook.releaseHost) end
  if type(book.HookScript) == "function" then book:HookScript("OnHide", SpellBook.releaseBook) end
  local paging = Compat.get(SURFACE, "paging")
  if type(paging) == "table" and type(paging.UpdateControls) == "function" then
    hooksecurefunc(paging, "UpdateControls", SpellBook.showPageText)
  end
  local registry = Compat.get(SURFACE, "eventRegistry")
  if type(registry) == "table" and type(registry.RegisterCallback) == "function" then
    registry:RegisterCallback(DISPLAYED_EVENT, SpellBook.onDisplayedSpells, SpellBook)
  end
  local modifyMenu = Compat.get(SURFACE, "modifyMenu")
  if type(modifyMenu) == "function" then modifyMenu(MENU_TAG, SpellBook.onSettingsMenu) end
  Compat.declare(SURFACE, "itemMixin", { "SpellBookItemMixin" })
  hookItemMixin()
  -- what the client already wrote before this ran (the addon may load after the frame was shown)
  SpellBook.showTitle()
  SpellBook.showPageText()
  SpellBook.onDisplayedSpells()
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
