-- UI/Transmog.lua: the transmogrifier window on Forever (surface "transmog", area "ui", ADR-016, ADR-029).
-- Load-on-demand Blizzard_Transmog (blizzard_transmog.toc: LoadOnDemand 1, no game-type gate); its [Bootstrap] file
-- registers Enum.PlayerInteractionType.Transmogrifier at login → LoadAddOn + TransmogFrame
-- (blizzard_transmog_bootstrap.lua:3–17), so the window opens when a transmogrifier NPC sends that interaction.
-- Whether Forever has one is an in-game question. Set up through WFJ.LoadOnDemand.when. Every child is a parentKey
-- (dotted Compat names).
-- Title: TransmogFrame:SetTitle(TRANSMOGRIFY) in OnLoad (blizzard_transmog.lua:114), through Labels.title.
-- Static labels (XML text=, blizzard_transmog.xml; each restricted to its own key):
--   OutfitCollection.UsableDiscountText (:45), .PurchaseOutfitButton.Text (:140), .SaveOutfitButton (:153); the
--   outfit popup's header OutfitPopup.BorderBox.EditBoxHeaderText (KeyValue editBoxHeaderText, :194, written by the
--   icon selector's OnLoad); CharacterPreview.ToggleOptions.HideIgnoredToggle / SheatheWeaponToggle /
--   PreviewedWeaponToggle .Text (:378, 396, 414); under WardrobeCollection.TabContent: ItemsFrame.DisplayTypes
--   .DisplayTypeEquippedButton (:549), ItemsFrame.SecondaryAppearanceToggle.Text (:591), SetsFrame / CustomSetsFrame
--   .PagedContent.NoEntriesText (:644, 701), CustomSetsFrame.NewCustomSetButton (:677), SituationsFrame
--   .DescriptionText / .DefaultsButton / .EnabledToggle.Text / .ApplyButton (:735–784); each search box's
--   ProgressFrame.LoadingFrame.Text and .ProgressFrame.ProgressBar.Text (TransmogSearchBoxTemplate,
--   blizzard_transmogtemplates.xml:643, 676; ItemsFrame.SearchBox and SetsFrame.SearchBox, blizzard_transmog.xml:526,
--   627).
-- Writers, each the frame's own method called as `self:…()`, post-hooked on the instance:
--   ItemsFrame:RefreshActiveSlotTitle (lua:1817–1847) → ActiveSlotTitle: a slot word (_G[slot name], or
--     WEAPON_ENCHANTMENT / LEFTSHOULDERSLOT / RIGHTSHOULDERSLOT); with an option set it is TRANSMOG_ACTIVE_SLOT_TITLE_
--     FORMAT filled by gsub (a composite with an option name), which the restriction leaves alone;
--   ItemsFrame:RefreshDisplayTypeButtons (lua:1921–2025) → DisplayTypeUnassignedButton:SetText(
--     TRANSMOG_SLOT_DISPLAY_TYPE_UNASSIGNED | _ARTIFACT) (:2016–2019);
--   ItemsFrame:InitFilterButton → FilterButton:SetText(SOURCES) (lua:1747–1748), and the sets filter's own text,
--     through Labels.dropdown; the filter menus' entries are the menu system's;
--   the four tabs WardrobeCollection:AddNamedTab(TRANSMOG_TAB_ITEMS / _SETS / _CUSTOM_SETS / _SITUATIONS)
--     (lua:1485–1491) → TabHeaders:GetTabButton(id).Text, rewritten by each tab's UpdateTabText
--     (blizzard_sharedxml/shared/tabsystem/tabsystemtemplates.lua:167–196; a disabled tab's text is colour-wrapped
--     and stays English).
-- Tooltips (help-tooltip owners, each restricted): CharacterPreview.ClearAllPendingButton (lua:892–895),
--   OutfitCollection.SaveOutfitButton (lua:320–327, 441–451), the two display-type buttons (lua:1636–1640,
--   2019–2024), CustomSetsFrame.NewCustomSetButton's disabled reasons (lua:2898–2910), SituationsFrame.ApplyButton's
--   (lua:3120–3129) and UndoButton's tooltipText (xml:796), and every outfit slot button, acquired from
--   CharacterPreview's two slot pools in :SetupSlots (lua:821–822, 990–1060): a slot word, TRANSMOGRIFY_TOOLTIP_HIDDEN,
--   TRANSMOGRIFY_ILLUSION_INVALID_ITEM (blizzard_transmogtemplates.lua:227–310, 370–381). Appearance names on the
--   same owners never match.
-- The sheathe toggle's checkbox owns FormatBindingKeyIntoText(TRANSMOG_SHEATHE_WEAPON_TOOLTIP, "TOGGLESHEATH",
--   …): "<text> |cffffd200(<key>)|r", the `binding` form (lua:857–864, blizzard_sharedxml/bindingutil.lua:175–186);
--   each situation's dropdown default text, red- or grey-wrapped TRANSMOG_SITUATIONS_NO_VALID_OPTIONS
--   (TransmogWardrobeSituationsMixin:Refresh, lua:3104–3120; the `wrapped` form), after Refresh and each UpdateText.
-- Never touched: outfit, set and custom-set names, appearance / item / illusion names, situation option names, the
--   search boxes, the outfit popup's name EditBox, money. The item models' NEW badge (NewVisual.NewString,
--   blizzard_transmogtemplates.xml:1029) needs no hook: NEW_CAPS ships as "NEW" (kept in English letters),
--   which is what the badge already shows.
-- Release on TransmogFrame's OnHide.
local _, WFJ = ...
local Transmog = {}
WFJ.Transmog = Transmog

local SURFACE = "transmog"
Transmog.SURFACE = SURFACE
local Compat = WFJ.Compat
local ADDON = "Blizzard_Transmog"
local F = "TransmogFrame"
local ITEMS = F .. ".WardrobeCollection.TabContent.ItemsFrame"
local SETS = F .. ".WardrobeCollection.TabContent.SetsFrame"
local CUSTOM = F .. ".WardrobeCollection.TabContent.CustomSetsFrame"
local SITUATIONS = F .. ".WardrobeCollection.TabContent.SituationsFrame"
local TOGGLES = F .. ".CharacterPreview.ToggleOptions"

Transmog.NEVER_TOUCH = { ITEMS .. ".SearchBox", SETS .. ".SearchBox",
  F .. ".OutfitPopup.BorderBox.IconSelectorEditBox" }

-- the slot words a slot title / slot tooltip may be (TransmogUtil.GetSlotName → a *SLOT global; lua:1823–1838)
local SLOT_WORDS = { "HEADSLOT", "SHOULDERSLOT", "BACKSLOT", "CHESTSLOT", "SHIRTSLOT", "TABARDSLOT", "WRISTSLOT",
  "HANDSSLOT", "WAISTSLOT", "LEGSSLOT", "FEETSLOT", "MAINHANDSLOT", "SECONDARYHANDSLOT", "RANGEDSLOT",
  "WEAPON_ENCHANTMENT", "LEFTSHOULDERSLOT", "RIGHTSHOULDERSLOT" }

-- { record key, path, the key(s) the widget may show }
local LABELS = {
  { "discount", F .. ".OutfitCollection.UsableDiscountText", { "TRANSMOG_USABLE_DISCOUNT" } },
  { "purchase", F .. ".OutfitCollection.PurchaseOutfitButton.Text", { "TRANSMOG_PURCHASE_OUTFIT_SLOT" } },
  { "save", F .. ".OutfitCollection.SaveOutfitButton", { "TRANSMOG_SAVE_OUTFIT" } },
  { "popupHeader", F .. ".OutfitPopup.BorderBox.EditBoxHeaderText", { "TRANSMOG_OUTFIT_SLOT_POPUP_TEXT" } },
  { "hideIgnored", TOGGLES .. ".HideIgnoredToggle.Text", { "TRANSMOG_HIDE_UNASSIGNED_SLOTS" } },
  { "sheathe", TOGGLES .. ".SheatheWeaponToggle.Text", { "TRANSMOG_SHEATHE_WEAPON" } },
  { "previewedWeapon", TOGGLES .. ".PreviewedWeaponToggle.Text", { "TRANSMOG_PREVIEWED_WEAPON_TOGGLE" } },
  { "activeSlot", ITEMS .. ".ActiveSlotTitle", SLOT_WORDS },
  { "equipped", ITEMS .. ".DisplayTypes.DisplayTypeEquippedButton", { "TRANSMOG_SLOT_DISPLAY_TYPE_EQUIPPED" } },
  { "unassigned", ITEMS .. ".DisplayTypes.DisplayTypeUnassignedButton",
    { "TRANSMOG_SLOT_DISPLAY_TYPE_UNASSIGNED", "TRANSMOG_SLOT_DISPLAY_TYPE_UNASSIGNED_ARTIFACT" } },
  { "rightShoulder", ITEMS .. ".SecondaryAppearanceToggle.Text", { "TRANSMOGRIFY_RIGHT_SHOULDER" } },
  { "setsNone", SETS .. ".PagedContent.NoEntriesText", { "TRANSMOG_SETS_NONE" } },
  { "customNone", CUSTOM .. ".PagedContent.NoEntriesText", { "TRANSMOG_CUSTOM_SETS_NONE" } },
  { "customNew", CUSTOM .. ".NewCustomSetButton", { "TRANSMOG_CUSTOM_SET_NEW" } },
  { "situationsText", SITUATIONS .. ".DescriptionText", { "TRANSMOG_SITUATIONS_DESCRIPTION" } },
  { "situationsDefaults", SITUATIONS .. ".DefaultsButton", { "TRANSMOG_SITUATIONS_DEFAULTS" } },
  { "situationsEnabled", SITUATIONS .. ".EnabledToggle.Text", { "TRANSMOG_SITUATIONS_ENABLED" } },
  { "situationsApply", SITUATIONS .. ".ApplyButton", { "TRANSMOG_SITUATIONS_APPLY" } },
}
for _, box in ipairs({ { "items", ITEMS }, { "sets", SETS } }) do
  LABELS[#LABELS + 1] = { box[1] .. ".loading", box[2] .. ".SearchBox.ProgressFrame.LoadingFrame.Text",
    { "SEARCH_LOADING_TEXT" } }
  LABELS[#LABELS + 1] = { box[1] .. ".progress", box[2] .. ".SearchBox.ProgressFrame.ProgressBar.Text",
    { "SEARCH_PROGRESS_BAR_TEXT" } }
end
local LABEL_OPTS = {}
for _, l in ipairs(LABELS) do LABEL_OPTS[l[1]] = { only = l[3] } end

local FILTERS = { { "itemsFilter", ITEMS .. ".FilterButton" }, { "setsFilter", SETS .. ".FilterButton" } }
local TABS = { itemsTabID = "TRANSMOG_TAB_ITEMS", setsTabID = "TRANSMOG_TAB_SETS",
  custmSetsTabID = "TRANSMOG_TAB_CUSTOM_SETS", situationsTabID = "TRANSMOG_TAB_SITUATIONS" }
local TAB_ORDER = { "itemsTabID", "setsTabID", "custmSetsTabID", "situationsTabID" }
local TITLE = { only = { "TRANSMOGRIFY" } }

local SLOT_TIP = { only = {} }
for i, k in ipairs(SLOT_WORDS) do SLOT_TIP.only[i] = k end
SLOT_TIP.only[#SLOT_TIP.only + 1] = "TRANSMOGRIFY_TOOLTIP_HIDDEN"
SLOT_TIP.only[#SLOT_TIP.only + 1] = "TRANSMOGRIFY_ILLUSION_INVALID_ITEM"
-- { path, the keys its tooltip may show }
local TOOLTIPS = {
  { F .. ".CharacterPreview.ClearAllPendingButton", { "TRANSMOGRIFY_CLEAR_ALL_PENDING" } },
  { F .. ".OutfitCollection.SaveOutfitButton",
    { "TRANSMOG_SAVE_OUTFIT_TOOLTIP", "TRANSMOG_SAVE_OUTFIT_CANNOT_AFFORD_TOOLTIP" } },
  { ITEMS .. ".DisplayTypes.DisplayTypeEquippedButton",
    { "TRANSMOG_SLOT_DISPLAY_TYPE_EQUIPPED", "TRANSMOG_SLOT_DISPLAY_TYPE_EQUIPPED_TOOLTIP" } },
  { ITEMS .. ".DisplayTypes.DisplayTypeUnassignedButton",
    { "TRANSMOG_SLOT_DISPLAY_TYPE_UNASSIGNED", "TRANSMOG_SLOT_DISPLAY_TYPE_UNASSIGNED_ARTIFACT",
      "TRANSMOG_SLOT_DISPLAY_TYPE_UNASSIGNED_TOOLTIP", "TRANSMOG_SLOT_DISPLAY_TYPE_UNASSIGNED_ARTIFACT_TOOLTIP" } },
  { CUSTOM .. ".NewCustomSetButton",
    { "TRANSMOG_CUSTOM_SET_NEW_TOOLTIP_DISABLED", "TRANSMOG_CUSTOM_SET_NEW_TOOLTIP_DISABLED_MAX_COUNT" } },
  { SITUATIONS .. ".ApplyButton", { "TRANSMOG_SITUATIONS_APPLY_DISABLED_TOOLTIP" } },
  { SITUATIONS .. ".UndoButton", { "TRANSMOG_SITUATIONS_UNDO" } },
  { TOGGLES .. ".SheatheWeaponToggle.Checkbox", { "TRANSMOG_SHEATHE_WEAPON_TOOLTIP" } },
}
local SITUATION = { only = { "TRANSMOG_SITUATIONS_NO_VALID_OPTIONS" } }
local situationKey = WFJ.Labels.keyer("situation.") -- a pooled situation dropdown's record key

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  Compat.declare(SURFACE, "frame", { F })
  Compat.declare(SURFACE, "wardrobe", { F .. ".WardrobeCollection" })
  Compat.declare(SURFACE, "items", { ITEMS })
  Compat.declare(SURFACE, "preview", { F .. ".CharacterPreview" })
  Compat.declare(SURFACE, "situations", { SITUATIONS })
  for _, l in ipairs(LABELS) do Compat.declare(SURFACE, l[1], { l[2] }) end
  for _, d in ipairs(FILTERS) do Compat.declare(SURFACE, d[1], { d[2] }) end
  for i, t in ipairs(TOOLTIPS) do Compat.declare(SURFACE, "tip" .. i, { t[1] }) end
end

-- One tab button of the wardrobe's TabSystem, by the id field the wardrobe stores (lua:1488–1491). → the button | nil
local function tab(field)
  local wardrobe = get("wardrobe")
  if type(wardrobe) ~= "table" then return nil end
  local system, id = wardrobe.TabHeaders, wardrobe[field]
  if type(system) ~= "table" or type(system.GetTabButton) ~= "function" or id == nil then return nil end
  local button = system:GetTabButton(id)
  return type(button) == "table" and button or nil
end

-- The four tab labels (each tab's Text, restricted to its own key). → the number of dictionary words found
function Transmog.showTabs()
  local n = 0
  for _, field in ipairs(TAB_ORDER) do
    local button = tab(field)
    n = n + WFJ.Labels.show(SURFACE, "tab." .. field, button and button.Text or nil, nil, { only = { TABS[field] } })
  end
  return n
end

-- hooksecurefunc target (CharacterPreview:SetupSlots): every active outfit slot button owns its tooltip. → the count
function Transmog.onSlots()
  local preview = get("preview")
  if type(preview) ~= "table" then return 0 end
  local n = 0
  for _, field in ipairs({ "CharacterAppearanceSlotFramePool", "CharacterIllusionSlotFramePool" }) do
    local pool = preview[field]
    if type(pool) == "table" and type(pool.EnumerateActive) == "function" then
      for slot in pool:EnumerateActive() do
        if type(slot) == "table" then
          WFJ.HelpTooltip.register(slot, SLOT_TIP)
          n = n + 1
        end
      end
    end
  end
  return n
end

-- hooksecurefunc target (SituationsFrame:Refresh): each active situation's dropdown default text. → the count
function Transmog.onSituations()
  local frame, n = get("situations"), 0
  local pool = type(frame) == "table" and frame.SituationFramePool or nil
  if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then return 0 end
  for situation in pool:EnumerateActive() do
    local dropdown = type(situation) == "table" and situation.Dropdown or nil
    if type(dropdown) == "table" and type(dropdown.Text) == "table" then
      n = n + WFJ.Labels.dropdown(SURFACE, situationKey(dropdown), dropdown, SITUATION)
    end
  end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- The whole window as it is now (OnShow and every writer hook). → the number of dictionary words found
function Transmog.showAll()
  local n = WFJ.Labels.title(SURFACE, get("frame"), TITLE)
  for _, l in ipairs(LABELS) do n = n + WFJ.Labels.show(SURFACE, l[1], get(l[1]), nil, LABEL_OPTS[l[1]]) end
  for _, d in ipairs(FILTERS) do n = n + WFJ.Labels.dropdown(SURFACE, d[1], get(d[1])) end
  n = n + Transmog.showTabs()
  WFJ.Render.updateBanner(SURFACE)
  return n
end

function Transmog.release()
  return WFJ.Render.release(SURFACE)
end

local function hook(target, method, fn)
  if type(target) == "table" and type(target[method]) == "function" then hooksecurefunc(target, method, fn) end
end

local hooked, waiting = false, false

-- Runs once Blizzard_Transmog is loaded (now, or on its ADDON_LOADED). Declared again here: a declare clears
-- Compat's memo, which holds `false` for a name looked up before the addon loaded.
function Transmog.setup()
  declare()
  local frame = get("frame")
  if hooked or type(frame) ~= "table" then return false end
  hooked = true
  WFJ.Labels.forbidNames(Transmog.NEVER_TOUCH) -- its widgets exist only now (Main's pass ran before the load)
  if type(frame.HookScript) == "function" then
    frame:HookScript("OnShow", Transmog.showAll)
    frame:HookScript("OnHide", Transmog.release)
  end
  local items = get("items")
  for _, method in ipairs({ "RefreshActiveSlotTitle", "RefreshDisplayTypeButtons", "InitFilterButton" }) do
    hook(items, method, Transmog.showAll)
  end
  for _, field in ipairs(TAB_ORDER) do hook(tab(field), "UpdateTabText", Transmog.showTabs) end
  hook(get("preview"), "SetupSlots", Transmog.onSlots)
  hook(get("situations"), "Refresh", Transmog.onSituations)
  for i, t in ipairs(TOOLTIPS) do WFJ.HelpTooltip.register(get("tip" .. i), { only = t[2] }) end
  Transmog.onSlots()
  Transmog.showAll() -- what the client already wrote (the addon may load after the frame was shown)
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init. → true when the window
-- exists now, false while it waits for Blizzard_Transmog.
function Transmog.init()
  declare()
  if hooked then return false end
  if not waiting then
    waiting = true
    return WFJ.LoadOnDemand.when(ADDON, Transmog.setup) and hooked
  end
  return false
end
