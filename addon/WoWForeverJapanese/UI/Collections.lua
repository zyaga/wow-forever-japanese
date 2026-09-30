-- UI/Collections.lua: the Collections window on Forever: its frame, side tabs, and the two paged icon grids, the
-- Toy Box and the Heirlooms journal (surface "collections", area "ui", ADR-016). The mount, pet and
-- appearance journals are UI/MountJournal.lua, UI/PetJournal.lua and UI/Wardrobe.lua.
-- Entry point: CollectionsMicroButton is placed on camelot (blizzard_micromenu/camelot/
-- micromenucontaineroverrides.lua:13) → ToggleCollectionsJournal (blizzard_collections/
-- blizzard_collections_bootstrap.lua). Blizzard_Collections is load-on-demand (blizzard_collections.toc:3), so the
-- surface waits for it through WFJ.LoadOnDemand.when. Without CollectionsJournal nothing is set up.
-- camelot builds five side tabs: Mounts, Pets, Toys, Heirlooms, Appearances (camelot/blizzard_collectionstabs.xml:
-- 20–46; blizzard_collections.toc:22–23 swap the shared tab strip for it). There is no sixth tab, so the Campsites
-- journal (WarbandSceneJournal) is never selected (shared/blizzard_collections.lua:107–112).
--   title: CollectionsJournal_OnLoad SetTitle(COLLECTIONS) (shared/blizzard_collections.lua:152), then
--     CollectionsJournal_UpdateSelectedTab SetTitle(self:GetPageTitleText(tab)) on every show and tab click
--     (:81–83, :110): MOUNTS, PET_JOURNAL, TOY_BOX, WARDROBE. Tab 4's title is the global HEIRLOOM, which the
--     Forever GlobalStrings table does not have, so that title is "" (in-game check). Through Labels.title;
--   side tabs: a LargeSideTabButtonTemplate has no text; its tooltip is SidePanelTabButtonMixin:OnEnter →
--     GetAppropriateTooltip():SetText(self.tooltipText) (blizzard_sharedxml/mainline/shareduipaneltemplates.lua:
--     406–416) with MOUNTS / PET_JOURNAL / TOY_BOX / HEIRLOOMS / WARDROBE. Each tab is a help-tooltip owner
--     restricted to its own key;
--   Toy Box: ToyBox.ProgressTracker is camelot's count box (camelot/blizzard_toyboxprogresstracker.xml:4–9, isCount):
--     .Label = TOTAL_TOYS (CollectionsCountTemplateMixin:OnLoad, shared/blizzard_collectiontemplates.lua:144–148);
--     FilterDropdown's button text is FILTER (blizzard_menu/mainline/menutemplates.xml:69); the eighteen
--     spellButton<N>.new labels are NEW_CAPS (shared/blizzard_collectiontemplates.xml:99);
--   Heirlooms: HeirloomsMixin:LayoutCurrentPage writes each pooled header's .text with a HEIRLOOMS_CATEGORY_* word
--     (mainline/blizzard_heirloomcollection.lua:242–258, 449–452) and HeirloomsMixin:UpdateButton writes an entry's
--     .special with HEIRLOOMS_PVP (:577–580). Both frame lists are walked after the layout, keyed by widget. The tab
--     shows only when C_HeirloomInfo.HeirloomsAvailable() (shared/blizzard_collections.lua:20–22), in-game check;
--   paging: CollectionsPagingMixin:Update writes PageText with COLLECTION_PAGE_NUMBER (shared/
--     blizzard_collectiontemplates.lua:115–117); the mixin is copied onto each PagingFrame, so the hook is on the
--     frame (Collections.paging, shared with UI/Wardrobe.lua).
-- Never touched: toy and heirloom names (spellButton<N>.name, an entry's .name / .level), the class dropdown's
-- selection (a class name), the search boxes.
local _, WFJ = ...
local Collections = {}
WFJ.Collections = Collections

local SURFACE = "collections"
Collections.SURFACE = SURFACE
Collections.ADDON = "Blizzard_Collections"
local Compat = WFJ.Compat

Collections.NEVER_TOUCH = { "ToyBox.searchBox", "HeirloomsJournal.SearchBox", "HeirloomsJournal.ClassDropdown.Text" }

local TABS = { -- record key → { candidate, the one key its tooltip shows }
  mountsTab = { "CollectionsJournal.TabContainer.MountsTab", "MOUNTS" },
  petsTab = { "CollectionsJournal.TabContainer.PetsTab", "PET_JOURNAL" },
  toysTab = { "CollectionsJournal.TabContainer.ToysTab", "TOY_BOX" },
  heirloomsTab = { "CollectionsJournal.TabContainer.HeirloomsTab", "HEIRLOOMS" },
  wardrobeTab = { "CollectionsJournal.TabContainer.WardrobeTab", "WARDROBE" },
}
local CANDIDATES = {
  frame = { "CollectionsJournal" }, toyBox = { "ToyBox" }, toyLabel = { "ToyBox.ProgressTracker.Label" },
  toyFilter = { "ToyBox.FilterDropdown" }, toyPaging = { "ToyBox.PagingFrame" }, toyIcons = { "ToyBox.iconsFrame" },
  heirlooms = { "HeirloomsJournal" }, heirloomFilter = { "HeirloomsJournal.FilterDropdown" },
  heirloomPaging = { "HeirloomsJournal.PagingFrame" },
}

local TITLE = { only = { "COLLECTIONS", "MOUNTS", "PET_JOURNAL", "TOY_BOX", "WARDROBE" } }
local PAGE = { only = { "COLLECTION_PAGE_NUMBER" } }
local NEW = { only = { "NEW_CAPS" } }
local TOY_LABEL = { only = { "TOTAL_TOYS" } }
local HEADER = { only = { "HEIRLOOMS_CATEGORY_HEAD", "HEIRLOOMS_CATEGORY_SHOULDER", "HEIRLOOMS_CATEGORY_BACK",
  "HEIRLOOMS_CATEGORY_CHEST", "HEIRLOOMS_CATEGORY_LEGS", "HEIRLOOMS_CATEGORY_WEAPON",
  "HEIRLOOMS_CATEGORY_TRINKETS_RINGS_AND_NECKLACES" } }
local SPECIAL = { only = { "HEIRLOOMS_PVP" } }
-- ToyBox.iconsFrame.spellButton1 … spellButton18 are parentKeys (mainline/blizzard_toybox.xml:49–134)
local TOY_BUTTONS = 18

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  for key, tab in pairs(TABS) do Compat.declare(SURFACE, key, { tab[1] }) end
end

local headerKey = WFJ.Labels.keyer("heirloomHeader.") -- a pooled header's record key
local entryKey = WFJ.Labels.keyer("heirloomEntry.") -- a pooled entry's record key
local pagingHooked = setmetatable({}, { __mode = "k" })

-- A collections paging frame's "Page %d / %d" (shared with UI/Wardrobe.lua): shown now and after each Update. The
-- hook is installed once per frame. → 1 | 0 for the current text.
function Collections.paging(surface, recKey, paging)
  if type(paging) ~= "table" then return 0 end
  local function show() return WFJ.Labels.show(surface, recKey, paging.PageText, nil, PAGE) end
  if not pagingHooked[paging] and type(paging.Update) == "function" then
    pagingHooked[paging] = true
    hooksecurefunc(paging, "Update", show)
  end
  return show()
end

-- The Toy Box's load-time labels. → the number of dictionary words found.
function Collections.showToyBox()
  local items = { { "toyLabel", get("toyLabel"), TOY_LABEL } }
  local icons = get("toyIcons")
  if type(icons) == "table" then
    for i = 1, TOY_BUTTONS do
      local button = icons["spellButton" .. i] -- Blizzard's own parentKey, not a position in a list
      if type(button) == "table" then items[#items + 1] = { "toyNew" .. i, button.new, NEW } end
    end
  end
  local n = WFJ.Labels.showAll(SURFACE, items)
  return n + WFJ.Labels.dropdown(SURFACE, "toyFilter", get("toyFilter"))
end

-- hooksecurefunc target (HeirloomsJournal:UpdateButton(button)): the entry's "PvP" tag. → 1 | 0
function Collections.onHeirloomButton(_, entry)
  local special = type(entry) == "table" and entry.special or nil
  if type(special) ~= "table" then return 0 end
  return WFJ.Labels.show(SURFACE, entryKey(special), special, nil, SPECIAL)
end

-- hooksecurefunc target (HeirloomsJournal:LayoutCurrentPage). → the number of dictionary words found.
function Collections.onHeirlooms()
  local journal = get("heirlooms")
  if type(journal) ~= "table" then return 0 end
  local n = 0
  if type(journal.heirloomHeaderFrames) == "table" then
    for _, header in ipairs(journal.heirloomHeaderFrames) do
      local text = type(header) == "table" and header.text or nil
      if type(text) == "table" then n = n + WFJ.Labels.show(SURFACE, headerKey(text), text, nil, HEADER) end
    end
  end
  if type(journal.heirloomEntryFrames) == "table" then
    for _, entry in ipairs(journal.heirloomEntryFrames) do n = n + Collections.onHeirloomButton(journal, entry) end
  end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

local hooked = false

-- Blizzard_Collections' part: runs once the addon is loaded (now, or on its ADDON_LOADED). → true when set up.
function Collections.setup()
  declare() -- its frames exist only now: forget what Compat memoized before
  local frame = get("frame")
  if type(frame) ~= "table" then return false end
  WFJ.Labels.forbidNames(Collections.NEVER_TOUCH) -- its widgets exist only now (Main's registration found none)
  WFJ.Labels.title(SURFACE, frame, TITLE)
  Collections.showToyBox()
  Collections.paging(SURFACE, "toyPage", get("toyPaging"))
  Collections.paging(SURFACE, "heirloomPage", get("heirloomPaging"))
  WFJ.Labels.dropdown(SURFACE, "heirloomFilter", get("heirloomFilter"))
  if hooked then return false end
  hooked = true
  for key, tab in pairs(TABS) do WFJ.HelpTooltip.register(get(key), { only = { tab[2] } }) end
  local journal = get("heirlooms")
  if type(journal) == "table" then
    if type(journal.LayoutCurrentPage) == "function" then
      hooksecurefunc(journal, "LayoutCurrentPage", Collections.onHeirlooms)
    end
    if type(journal.UpdateButton) == "function" then
      hooksecurefunc(journal, "UpdateButton", Collections.onHeirloomButton)
    end
  end
  Collections.onHeirlooms()
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init. → true when the window
-- was set up now; false when it waits for Blizzard_Collections (or the client has no such window).
function Collections.init()
  declare()
  local ok = false
  WFJ.LoadOnDemand.when(Collections.ADDON, function() ok = Collections.setup() end)
  return ok
end
