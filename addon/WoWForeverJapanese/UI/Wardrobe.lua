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
--     blizzard_wardrobe.xml:245; mainline/blizzard_wardrobe.lua:1700–1702; blizzard_sharedxml/shared/inputbox/
--     inputboxtemplates.xml:209–211, inputboxtemplates.lua:174–177]. Instructions is a FontString of its own beside
--     the EditBox, so what the player types is never read or written.
-- Writer: ItemsCollectionFrame.PagingFrame:Update → PageText COLLECTION_PAGE_NUMBER (Collections.paging).
-- Tooltips (help-tooltip owners, each restricted to its keys):
--   a slot button: SetText(WEAPON_ENCHANTMENT), or _G[self.slot] (HEADSLOT …), or LEFTSHOULDERSLOT /
--     RIGHTSHOULDERSLOT (mainline/blizzard_wardrobe.lua:430–449). The buttons are created in CreateSlotButtons into
--     SlotsFrame.Buttons (lua:460–; template parentArray, xml:99, 132);
--   SearchBox: WARDROBE_NO_SEARCH when disabled (lua:1744–1751); the EditBox's own text is never read or written;
--   DetailsFrame.LimitedSet: TRANSMOG_SET_LIMITED_TIME_SET_TOOLTIP (xml:679–685);
--   DetailsFrame.VariantSetsDropdown.PrecedingVariantIcon: TRANSMOG_SET_GRANTS_PRECEDING_VARIANTS (shared/
--     blizzard_wardrobe_sets.lua:85–89).
-- TrackingInterfaceShortcutsFrame's two XML labels, HeaderText WARDROBE_SHORTCUTS_TUTORIAL_2 and Text
--   WARDROBE_SHORTCUTS_TUTORIAL_3 (xml:164–180): a frame only ever appended to the shortcuts HelpTip
--   (WardrobeCollectionTutorialMixin, lua:1549–1571): static, shown with the other static labels. The HelpTip's own
--   text (_1) is UI/HelpTips'. Filter / right-click menus are UI/Menus'.
-- ADR-042: the variant dropdown's selection: a set's description, its variant word ("Green", "Blue";
--   ItemNameDescription through TransmogSet.ItemNameDescriptionID), written with VariantSetsDropdown:SetText
--   (shared/blizzard_wardrobe_sets.lua:307): post-hooked on the dropdown, the ItemNameDescription family only.
-- Set names (surface "wardrobe.names"): while names are on, each shows the name's Japanese (UI/NameLabels) where the
--   name list has it (a set shares its name with its set-bonus spells):
--   the details: SetsCollectionFrame:DisplaySet (the frame's own method, shared/blizzard_wardrobe_sets.lua:228–248)
--     writes Name, measures it (IsTruncated, :240) and, when it does not fit, writes LongName instead, then Label.
--     Post-hooked, so the client measures its own English: LongName (while shown) and Label, plain FontStrings
--     (mainline/blizzard_wardrobe.xml:640–655), are shown after it. So is Name while it is the one shown: an
--     AutoScalingFontStringMixin FontString (xml:626) whose SetText measures the text and sets its scale
--     (blizzard_sharedxml/secureutil.lua:55–104). Render writes it with that same SetText, so the scale is worked out
--     again for the Japanese (and for the English on the reveal key). Nothing protected follows in DisplaySet: the
--     rest of the pass fills the item buttons from a pool, dresses the model (TryOn) and sets the variant dropdown's
--     text (:249–334);
--   the list rows: WardrobeSetsScrollFrameButtonMixin:Init writes each row's Name and Label (:513–537), plain
--     FontStrings of a plain Button (shared/blizzard_wardrobe_sets.xml:4, 40–51); rows are followed with
--     ScrollUtil.AddInitializedFrameCallback and each row's Init is post-hooked once (ReinitializeButtonWithBaseSetID
--     calls it again, :714–722).
--   Released on WardrobeCollectionFrame's OnHide and shown again on the sets frame's OnShow.
-- Never touched: item names, the class dropdown's selection (a class name), the search box text (the EditBox itself;
-- its placeholder FontString is shown above).
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
  sets = { FRAME .. ".SetsCollectionFrame" }, setList = { FRAME .. ".SetsCollectionFrame.ListContainer.ScrollBox" },
  scrollUtil = { "ScrollUtil" },
}

local NAMES = SURFACE .. ".names"
Wardrobe.NAMES = NAMES
local rowKey = WFJ.Labels.keyer("row.")
local rowHooked = setmetatable({}, { __mode = "k" })

local function shown(fs) return type(fs) == "table" and type(fs.IsShown) == "function" and fs:IsShown() end

-- After DisplaySet: the name or the long name, whichever is shown, and the label. → the number of names shown
function Wardrobe.onDisplaySet()
  local sets = Compat.get(SURFACE, "sets")
  local details = type(sets) == "table" and sets.DetailsFrame or nil
  if type(details) ~= "table" then return 0 end
  local n = 0
  for _, f in ipairs({ { "Name", "set.name" }, { "LongName", "set.longName" } }) do
    if shown(details[f[1]]) then
      n = n + WFJ.NameLabels.show(NAMES, f[2], details[f[1]])
    else
      WFJ.SurfaceState.drop(NAMES, f[2])
    end
  end
  n = n + WFJ.NameLabels.show(NAMES, "set.label", details.Label)
  WFJ.Render.updateBanner(NAMES)
  return n
end

-- A list row after its Init.
local function showRow(row)
  if type(row) ~= "table" then return end
  for _, field in ipairs({ "Name", "Label" }) do
    local fs = row[field]
    if type(fs) == "table" then WFJ.NameLabels.show(NAMES, rowKey(fs), fs) end
  end
end

-- ScrollUtil callback: (owner, frame, elementData) for a new row, (frame, elementData) for the existing-frames pass.
-- Returns nothing: ForEachFrame stops at the first truthy return.
function Wardrobe.onSetRow(a, b)
  local row = a == Wardrobe and b or a
  if type(row) ~= "table" then return end
  if not rowHooked[row] and type(row.Init) == "function" then
    rowHooked[row] = true
    hooksecurefunc(row, "Init", showRow)
  end
  showRow(row)
end

-- The sets frame shows again after a release: its details and every existing row.
function Wardrobe.onSetsShow()
  Wardrobe.onDisplaySet()
  local box = Compat.get(SURFACE, "setList")
  if type(box) == "table" and type(box.ForEachFrame) == "function"
      and (type(box.HasView) ~= "function" or box:HasView()) then
    box:ForEachFrame(Wardrobe.onSetRow)
  end
end

function Wardrobe.releaseNames()
  return WFJ.Render.release(NAMES)
end

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
  local sets = get("sets")
  if type(sets) == "table" then
    if type(sets.DisplaySet) == "function" then hooksecurefunc(sets, "DisplaySet", Wardrobe.onDisplaySet) end
    if type(sets.HookScript) == "function" then sets:HookScript("OnShow", Wardrobe.onSetsShow) end
  end
  local box, util = get("setList"), get("scrollUtil")
  if type(box) == "table" and type(util) == "table" and type(util.AddInitializedFrameCallback) == "function" then
    util.AddInitializedFrameCallback(box, Wardrobe.onSetRow, Wardrobe,
      type(box.ForEachFrame) == "function" and (type(box.HasView) ~= "function" or box:HasView()))
  end
  local frame = get("frame")
  if type(frame.HookScript) == "function" then frame:HookScript("OnHide", Wardrobe.releaseNames) end
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
