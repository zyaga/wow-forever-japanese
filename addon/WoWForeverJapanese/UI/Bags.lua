-- UI/Bags.lua: the bags' fixed words (surface "bags", area "ui", ADR-016).
-- Camelot loads the mainline [Family]\ContainerFrame.lua|xml (+ [Game]\ContainerFrame.lua) and the Shared / [Game]
-- MainMenuBarBagButtons at login [verified: blizzard_uipanels_game.toc:118–124; blizzard_mainmenubarbagbuttons.toc].
--   titles: ContainerFrame_GenerateFrame is the global every open path calls (mainline/containerframe.lua:207,
--     277, 290–292, 1287); it calls frame:UpdateName() → SetTitle(C_Container.GetBagName(id)), or COMBINED_BAG_TITLE
--     on ContainerFrameCombinedBags (:916–918, 2907–2909) → TitleContainer.TitleText. Backpack id 0 →
--     BACKPACK_TOOLTIP ("Backpack") or COMBINED_BAG_TITLE; the keyring → KEYRING; every other title is an item name
--     and is never matched (its record, if any, is dropped).
--   ContainerFrame1..7 and ContainerFrameCombinedBags (xml:300–308), each with $parentPortraitButton (xml:250, 314):
--     ContainerFramePortraitButtonMixin:OnEnter SetText(BACKPACK_TOOLTIP / KEYRING / the bag's item name) [+ binding]
--     then AddLine(CLICK_BAG_SETTINGS) (lua:2000–2040); a bag's portrait also adds BAG_FILTER_ASSIGNED_TO with
--     the bag's filter list (lua:2022–2027, ContainerFrameUtil_ConvertFilterFlagsToList joins BAG_FILTER_LABELS with
--     LIST_DELIMITER, lua:2319–2335): the `entryList` argument kind shows every filter in Japanese.
--   the backpack's AddSlotsButton is created lazily by UpdateAddSlots (lua:2614–2620, unnamed): registered from the
--     GenerateFrame hook once it exists; inline OnEnter SetText(BACKPACK_AUTHENTICATOR_INCREASE_SIZE) (xml:47–51).
--   BagItemAutoSortButton (parent ContainerFrame1, shown on the backpack, lua:1124–1141): inline OnEnter
--     GameTooltip_SetTitle(BAG_CLEANUP_BAGS) + AddNormalLine(BAG_CLEANUP_BAGS_DESCRIPTION) + Show (xml:345–367).
--   the extended (padlocked) slots: UpdateExtended creates each one's extendedFrame lazily (lua:1956–1979); its
--     XML OnEnter is the global ContainerFrameExtendedItemButton_OnEnter → GameTooltip_SetTitle(
--     BACKPACK_AUTHENTICATOR_INCREASE_SIZE) + Show (xml:35, lua:1622–1627). A template script is bound when the frame
--     is created, so a post-hook on the global reaches every extended frame; it registers the frame and walks the
--     tooltip it just showed.
--   the bag search box's placeholder: BagItemSearchBox.Instructions, written once by SearchBoxTemplate_OnLoad
--     (SEARCH, blizzard_sharedxml/shared/inputbox/inputboxtemplates.lua:177); a static label. The EditBox
--     itself stays untouched.
--   bag bar: MainMenuBarBackpackButton (SetTitle BACKPACK_TOOLTIP + binding + NUM_FREE_SLOTS "13 Empty Slots
--     (Total)", shared/mainmenubarbagbuttons.lua:284–297), KeyRingButton
--     (SetText(KEYRING), camelot/mainmenubarbagbuttons.lua:179–183), CharacterBag0..3Slot and CharacterReagentBag0Slot
--     (empty: SetTitle EQUIP_CONTAINER / EQUIP_CONTAINER_REAGENT; a bag: SetInventoryItem, an item tooltip, never
--     walked; shared/mainmenubarbagbuttons.lua:102–127; mainline/mainmenubarbagbuttontemplates.xml:85–117). A
--     bag's item tooltip gets BAG_FILTER_ASSIGNED_TO appended (:112–118), after the slot's OnEnterInternal (called as
--     self:OnEnterInternal(), :99), shown by HelpTooltip.appended, the item's own lines left to UI/Tooltip.
-- The key binding appended by AppendText ("Backpack |cffffd200(B)|r") is HelpTooltip's (its AppendText walk puts the
-- English back in front of the suffix and matches the `binding` form). No hook of our own; the client's Show refits.
-- Untouched: BagItemSearchBox's own text (an EditBox), bag and item names.
local _, WFJ = ...
local Bags = {}
WFJ.Bags = Bags

local SURFACE = "bags"
Bags.SURFACE = SURFACE
local Compat = WFJ.Compat

-- Widgets this module must never record: the bag search EditBox.
Bags.NEVER_TOUCH = { "BagItemSearchBox" }

local MAX_FRAMES = 7 -- ContainerFrame1..7 [verified: mainline/containerframe.xml:300–306]
local BAG_SLOTS = 4 -- CharacterBag0Slot..CharacterBag3Slot
local BACKPACK_ID = 0

local CANDIDATES = {
  generate       = { "ContainerFrame_GenerateFrame" },
  keyringId      = { "KEYRING_CONTAINER" },
  backpackButton = { "MainMenuBarBackpackButton" },
  keyringButton  = { "KeyRingButton" },
  combinedPortrait = { "ContainerFrameCombinedBagsPortraitButton", "ContainerFrameCombinedBags.PortraitButton" },
  autoSort       = { "BagItemAutoSortButton" },
  reagentSlot    = { "CharacterReagentBag0Slot" },
  searchHint     = { "BagItemSearchBox.Instructions" },
  extendedEnter  = { "ContainerFrameExtendedItemButton_OnEnter" },
}
local BACKPACK_TITLE = { "BACKPACK_TOOLTIP", "COMBINED_BAG_TITLE" }
local PORTRAIT_KEYS = { "BACKPACK_TOOLTIP", "KEYRING", "CLICK_BAG_SETTINGS", "BAG_FILTER_ASSIGNED_TO" }
local FILTER = { only = { "BAG_FILTER_ASSIGNED_TO" } }
local ADD_SLOTS_KEYS = { "BACKPACK_AUTHENTICATOR_INCREASE_SIZE" }
local BACKPACK_KEYS = { "BACKPACK_TOOLTIP", "NUM_FREE_SLOTS" }
local SEARCH_KEYS = { "SEARCH" }
for i = 1, MAX_FRAMES do
  CANDIDATES["portrait" .. i] = { "ContainerFrame" .. i .. "PortraitButton" }
end
for i = 0, BAG_SLOTS - 1 do CANDIDATES["bagSlot" .. i] = { "CharacterBag" .. i .. "Slot" } end

local function get(key) return Compat.get(SURFACE, key) end

-- hooksecurefunc target: a bag frame was built for container `id`. → 1 when its title is a dictionary word, else 0.
function Bags.onGenerate(frame, _, id)
  if type(frame) ~= "table" or type(frame.GetName) ~= "function" then return 0 end
  local name = frame:GetName()
  if type(name) ~= "string" then return 0 end
  local recKey = "ui.title." .. name
  local fs = Compat.resolve(name .. ".TitleContainer.TitleText")
  if type(frame.AddSlotsButton) == "table" then -- created lazily on the backpack
    WFJ.HelpTooltip.register(frame.AddSlotsButton, { only = ADD_SLOTS_KEYS })
  end
  local keyring = get("keyringId")
  local only
  if id == BACKPACK_ID then
    only = BACKPACK_TITLE
  elseif keyring ~= nil and id == keyring then
    only = { "KEYRING" }
  end
  local n = 0
  if fs and only then
    n = WFJ.Labels.show(SURFACE, recKey, fs, nil, { only = only })
  else
    WFJ.SurfaceState.drop(SURFACE, recKey) -- an item name now: never ours
  end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

local function register(owner, keys)
  if type(owner) ~= "table" then return 0 end
  WFJ.HelpTooltip.register(owner, { only = keys })
  return 1
end

-- Registers every help-tooltip owner. → the number registered.
function Bags.registerOwners()
  local n = register(get("backpackButton"), BACKPACK_KEYS)
    + register(get("keyringButton"), { "KEYRING" })
  for i = 0, BAG_SLOTS - 1 do
    local slot = get("bagSlot" .. i)
    n = n + register(slot, { "EQUIP_CONTAINER" })
    if type(slot) == "table" and type(slot.OnEnterInternal) == "function" then -- the filter line
      hooksecurefunc(slot, "OnEnterInternal", Bags.onBagSlotEnter)
    end
  end
  for i = 1, MAX_FRAMES do
    n = n + register(get("portrait" .. i), PORTRAIT_KEYS)
  end
  n = n + register(get("combinedPortrait"), PORTRAIT_KEYS)
    + register(get("autoSort"), { "BAG_CLEANUP_BAGS", "BAG_CLEANUP_BAGS_DESCRIPTION" })
    + register(get("reagentSlot"), { "EQUIP_CONTAINER_REAGENT" })
  return n
end

-- A bag slot's item tooltip was built (with its filter line appended). → the number of dictionary lines
function Bags.onBagSlotEnter()
  return WFJ.HelpTooltip.appended(nil, FILTER)
end

-- The extended-slot OnEnter post-hook: the client just showed the tooltip. → the number of dictionary lines
function Bags.onExtendedEnter(frame)
  if type(frame) ~= "table" then return 0 end
  WFJ.HelpTooltip.register(frame, { only = ADD_SLOTS_KEYS })
  local tt = _G.GameTooltip
  if type(tt) ~= "table" or type(tt.GetOwner) ~= "function" or tt:GetOwner() ~= frame then return 0 end
  return WFJ.HelpTooltip.walk(tt)
end

-- The search box placeholder. → 1 | 0
function Bags.showSearchHint()
  return WFJ.Labels.show(SURFACE, "ui.search", get("searchHint"), nil, { only = SEARCH_KEYS })
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function Bags.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  if hooked then return false end
  hooked = true
  if type(get("generate")) == "function" then hooksecurefunc("ContainerFrame_GenerateFrame", Bags.onGenerate) end
  if type(get("extendedEnter")) == "function" then
    hooksecurefunc("ContainerFrameExtendedItemButton_OnEnter", Bags.onExtendedEnter)
  end
  Bags.registerOwners()
  Bags.showSearchHint()
  return true
end
