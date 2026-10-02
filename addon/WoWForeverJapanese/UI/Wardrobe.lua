-- UI/Wardrobe.lua: the Appearances tab of the Collections window on Forever (surface "wardrobe", area "ui",
-- ADR-016). WardrobeCollectionFrame is a child of CollectionsJournal (blizzard_collections/mainline/
-- blizzard_wardrobe.xml:185) with camelot overrides that hide uncollected appearances and the progress bar
-- (camelot/blizzard_wardrobe.lua:2–20). Blizzard_Collections is load-on-demand, so this waits for it
-- (UI/Collections.lua has the entry point and the paging helper). Without the frame nothing is set up.
-- Static labels (XML text=, each restricted to its own key):
--   ItemsTab WARDROBE_ITEMS, SetsTab WARDROBE_SETS (xml:197, 210);
--   SearchBox.ProgressFrame.LoadingFrame.Text SEARCH_LOADING_TEXT, .ProgressBar.text SEARCH_PROGRESS_BAR_TEXT
--     (xml:322, 355);
--   SetsCollectionFrame.DetailsFrame.LimitedSet.Text TRANSMOG_SET_LIMITED_TIME_SET (xml:671);
--   each ItemsCollectionFrame.Models[…].NewString NEW_CAPS (xml:41; the models are XML children listed in the
--     parentArray, xml:445 onward), keyed by widget;
--   FilterButton's text FILTER (blizzard_menu/mainline/menutemplates.xml:69);
--   SearchBox.Instructions SEARCH, the search box's placeholder: SearchBoxTemplate's instructionText, written once by
--     WardrobeCollectionFrameSearchBoxMixin:OnLoad → SearchBoxTemplate_OnLoad [verified: mainline/
--     blizzard_wardrobe.xml:245; mainline/blizzard_wardrobe.lua:1698–1700; blizzard_sharedxml/shared/inputbox/
--     inputboxtemplates.xml:206–208, inputboxtemplates.lua:174–177]. Instructions is a FontString of its own beside
--     the EditBox, so what the player types is never read or written.
-- Writer: ItemsCollectionFrame.PagingFrame:Update → PageText COLLECTION_PAGE_NUMBER (Collections.paging).
-- Tooltips (help-tooltip owners, each restricted to its keys):
--   a slot button: SetText(WEAPON_ENCHANTMENT), or _G[self.slot] (HEADSLOT …), or LEFTSHOULDERSLOT /
--     RIGHTSHOULDERSLOT (mainline/blizzard_wardrobe.lua:430–449). The buttons are created in CreateSlotButtons into
--     SlotsFrame.Buttons (lua:460–; template parentArray, xml:99, 132);
--   SearchBox: WARDROBE_NO_SEARCH when disabled (lua:1741–1748); the EditBox's own text is never read or written;
--   DetailsFrame.LimitedSet: TRANSMOG_SET_LIMITED_TIME_SET_TOOLTIP (xml:679–685);
--   DetailsFrame.VariantSetsDropdown.PrecedingVariantIcon: TRANSMOG_SET_GRANTS_PRECEDING_VARIANTS (shared/
--     blizzard_wardrobe_sets.lua:85–89).
-- TrackingInterfaceShortcutsFrame's two XML labels, HeaderText WARDROBE_SHORTCUTS_TUTORIAL_2 and Text
--   WARDROBE_SHORTCUTS_TUTORIAL_3 (xml:164–180): a frame only ever appended to the shortcuts HelpTip
--   (WardrobeCollectionTutorialMixin, lua:1548–1569): static, shown with the other static labels. The HelpTip's own
--   text (_1) is UI/HelpTips'. Filter / right-click menus are UI/Menus'.
-- ADR-042: the variant dropdown's selection: a set's description, its variant word ("Green", "Blue";
--   ItemNameDescription through TransmogSet.ItemNameDescriptionID), written with VariantSetsDropdown:SetText
--   (shared/blizzard_wardrobe_sets.lua:307): post-hooked on the dropdown, the ItemNameDescription family only.
-- Never touched: set names and labels (item-set names), item names, the class dropdown's selection (a class name),
-- the search box text (the EditBox itself; its placeholder FontString is shown above).
local _, WFJ = ...
local Wardrobe = {}
WFJ.Wardrobe = Wardrobe

local SURFACE = "wardrobe"
Wardrobe.SURFACE = SURFACE
local Compat = WFJ.Compat
local ADDON = "Blizzard_Collections"

local FRAME = "WardrobeCollectionFrame"
local DETAILS = FRAME .. ".SetsCollectionFrame.DetailsFrame"
Wardrobe.NEVER_TOUCH = { FRAME .. ".SearchBox", FRAME .. ".ClassDropdown.Text", DETAILS .. ".Name",
  DETAILS .. ".LongName", DETAILS .. ".Label" }

local STATIC_LABELS = { -- record key → { candidate, the one key it shows }
  itemsTab = { FRAME .. ".ItemsTab", "WARDROBE_ITEMS" }, setsTab = { FRAME .. ".SetsTab", "WARDROBE_SETS" },
  loading = { FRAME .. ".SearchBox.ProgressFrame.LoadingFrame.Text", "SEARCH_LOADING_TEXT" },
  searching = { FRAME .. ".SearchBox.ProgressFrame.ProgressBar.text", "SEARCH_PROGRESS_BAR_TEXT" },
  limitedSet = { DETAILS .. ".LimitedSet.Text", "TRANSMOG_SET_LIMITED_TIME_SET" },
  searchHint = { FRAME .. ".SearchBox.Instructions", "SEARCH" },
  shortcutsHeader = { "TrackingInterfaceShortcutsFrame.HeaderText", "WARDROBE_SHORTCUTS_TUTORIAL_2" },
  shortcutsText = { "TrackingInterfaceShortcutsFrame.Text", "WARDROBE_SHORTCUTS_TUTORIAL_3" },
}
local STATIC_ORDER = {}
for key in pairs(STATIC_LABELS) do STATIC_ORDER[#STATIC_ORDER + 1] = key end
table.sort(STATIC_ORDER)

local CANDIDATES = {
  frame = { FRAME }, filter = { FRAME .. ".FilterButton" }, search = { FRAME .. ".SearchBox" },
  items = { FRAME .. ".ItemsCollectionFrame" }, paging = { FRAME .. ".ItemsCollectionFrame.PagingFrame" },
  slots = { FRAME .. ".ItemsCollectionFrame.SlotsFrame" }, limitedSet = { DETAILS .. ".LimitedSet" },
  precedingVariant = { DETAILS .. ".VariantSetsDropdown.PrecedingVariantIcon" },
  variant = { DETAILS .. ".VariantSetsDropdown" },
}

-- The variant dropdown's word after its SetText. → 1 | 0
function Wardrobe.onVariant()
  local dropdown = Compat.get(SURFACE, "variant")
  local text = type(dropdown) == "table" and dropdown.Text or nil
  return WFJ.Labels.show(SURFACE, "variant", text, nil, WFJ.Labels.families("ItemNameDescription"))
end

local NEW = { only = { "NEW_CAPS" } }
local SLOT_TOOLTIP = { only = { "WEAPON_ENCHANTMENT", "LEFTSHOULDERSLOT", "RIGHTSHOULDERSLOT", "HEADSLOT",
  "SHOULDERSLOT", "BACKSLOT", "CHESTSLOT", "SHIRTSLOT", "TABARDSLOT", "WRISTSLOT", "HANDSSLOT", "WAISTSLOT",
  "LEGSSLOT", "FEETSLOT", "MAINHANDSLOT", "SECONDARYHANDSLOT", "RANGEDSLOT" } }
local SEARCH_TOOLTIP = { only = { "WARDROBE_NO_SEARCH" } }
local LIMITED_TOOLTIP = { only = { "TRANSMOG_SET_LIMITED_TIME_SET_TOOLTIP" } }
local VARIANT_TOOLTIP = { only = { "TRANSMOG_SET_GRANTS_PRECEDING_VARIANTS" } }

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  for key, l in pairs(STATIC_LABELS) do Compat.declare(SURFACE, "static." .. key, { l[1] }) end
end

local newKey = WFJ.Labels.keyer("model.new.") -- an item model's record key (follows the widget, not its place)

-- The labels the client writes once at load. → the number of dictionary words found.
function Wardrobe.showStatic()
  local items = {}
  for _, key in ipairs(STATIC_ORDER) do
    items[#items + 1] = { key, get("static." .. key), { only = { STATIC_LABELS[key][2] } } }
  end
  local frame = get("items")
  if type(frame) == "table" and type(frame.Models) == "table" then
    for _, model in ipairs(frame.Models) do
      local new = type(model) == "table" and model.NewString or nil
      if type(new) == "table" then items[#items + 1] = { newKey(new), new, NEW } end
    end
  end
  local n = WFJ.Labels.showAll(SURFACE, items)
  return n + WFJ.Labels.dropdown(SURFACE, "filter", get("filter"))
end

local hooked = false

-- Blizzard_Collections' part: runs once the addon is loaded (now, or on its ADDON_LOADED). → true when set up.
function Wardrobe.setup()
  declare() -- its frames exist only now: forget what Compat memoized before
  if type(get("frame")) ~= "table" then return false end
  WFJ.Labels.forbidNames(Wardrobe.NEVER_TOUCH) -- its widgets exist only now (Main's registration found none)
  Wardrobe.showStatic()
  local shared = WFJ.Collections
  if type(shared) == "table" and type(shared.paging) == "function" then
    shared.paging(SURFACE, "page", get("paging"))
  end
  if hooked then return false end
  hooked = true
  local slots = get("slots")
  if type(slots) == "table" and type(slots.Buttons) == "table" then
    for _, button in ipairs(slots.Buttons) do WFJ.HelpTooltip.register(button, SLOT_TOOLTIP) end
  end
  WFJ.HelpTooltip.register(get("search"), SEARCH_TOOLTIP)
  WFJ.HelpTooltip.register(get("limitedSet"), LIMITED_TOOLTIP)
  WFJ.HelpTooltip.register(get("precedingVariant"), VARIANT_TOOLTIP)
  local variant = get("variant")
  if type(variant) == "table" and type(variant.SetText) == "function" then
    hooksecurefunc(variant, "SetText", Wardrobe.onVariant)
  end
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init. → true when the tab was
-- set up now; false when it waits for Blizzard_Collections (or the client has no such window).
function Wardrobe.init()
  declare()
  local ok = false
  WFJ.LoadOnDemand.when(ADDON, function() ok = Wardrobe.setup() end)
  return ok
end
