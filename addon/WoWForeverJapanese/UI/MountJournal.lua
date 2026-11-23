-- UI/MountJournal.lua: the Mounts tab of the Collections window on Forever (surface "mountjournal", area "ui",
-- ADR-016). MountJournal is a child of CollectionsJournal (blizzard_collections/mainline/
-- blizzard_mountcollection.xml:217); Blizzard_Collections is load-on-demand, so this waits for it (UI/Collections.lua
-- has the entry point). Without MountJournal nothing is set up.
-- Static labels (XML text= or an OnLoad write, each restricted to its own key):
--   MountCount.Label TOTAL_MOUNTS (xml:423–427 labelText; CollectionsCountTemplateMixin:OnLoad, shared/
--     blizzard_collectiontemplates.lua:144–148);
--   MountDisplay.NoMounts ERR_NO_RIDING_SKILL: a window label here, not an error line (xml:443);
--   MountDisplay.InfoButton.New NEW_CAPS (xml:491); MountDisplay.ModelScene.TogglePlayer.TogglePlayerText
--     MOUNT_JOURNAL_PLAYER (xml:520–528);
--   BottomLeftInset.SlotRequirementLabel MOUNT_EQUIPMENT_UNLOCK_REQUIREMENT, written once in MountJournal_OnLoad when
--     C_MountJournal.MountEquipmentAvailable() (lua:161–171); whether camelot has mount equipment is an in-game check;
--   FilterDropdown's button text FILTER (blizzard_menu/mainline/menutemplates.xml:69).
-- Writers (globals called by name, post-hooked):
--   MountJournal_UpdateMountDisplay → MountButton text: UNWRAP, BINDING_NAME_DISMOUNT or MOUNT (lua:749–757);
--   MountJournal_UpdateEquipment → BottomLeftInset.SlotLabel: MOUNT_EQUIPMENT_NOTICE, or the equipment item's name
--     (lua:533, 540): the same FontString, hence `only`.
-- Pooled list rows (MountListButtonTemplate, xml:80–190; ScrollBox initializer lua:143–146), walked from the
-- ScrollBox's initialized-frame callback, keyed by widget: .new NEW_CAPS, .SteadyFlightLabel
-- MOUNT_JOURNAL_STEADY_FLIGHT_ONLY. A row's .name is a mount's name (MountJournal_InitMountButton, lua:258–262):
-- never a dictionary word; while names are on it shows the name's Japanese (UI/NameLabels) after the row's
-- initializer. A row is a plain Button (xml:80): its click selects the mount or opens its menu and its drag
-- button picks the mount up by the row's index (lua:865–905), so nothing on the way to a summon reads the label.
-- The initializer counts the name's lines only to nudge it beside the steady-flight note (lua:268–275), before
-- this write.
-- Tooltips (help-tooltip owners, each restricted to its keys):
--   MountButton: SetText(self:GetText()) + MOUNT_UNWRAP_TOOLTIP / MOUNT_SUMMON_TOOLTIP, then the selected mount's
--     usability error from C_MountJournal.GetMountUsabilityByID as an error line ("Requires Journeyman Riding skill",
--     SPELL_FAILED_JOURNEYMAN_RIDING_REQUIREMENT) [verified: forever-ui-1.60.1.71037 blizzard_collections/mainline/
--     blizzard_mountcollection.lua:843-863]. Which errors that call returns is the client's: the line may be any
--     error key UI/Errors shows (Errors.errorKeys), so the tooltip's keys are those plus the button's own, built per
--     index. A list row's tooltip is the mount's spell (MountJournalMountButton_UpdateTooltip → SetMountBySpellID,
--     lua:653-655): UI/Tooltip's;
--   BottomLeftInset.SuppressedMountEquipmentButton: MOUNT_EQUIPMENT_EXEMPT (lua:30–34).
-- Not here: the favourite-mount spell frame (hidden on camelot: BLIZZARD_COLLECTIONS_MOUNT_JOURNAL_SHOW_FAVORITES =
-- false, camelot/blizzard_collectionsconstants.lua:1; lua:1042–1044), the Skyriding flyout (shown only when
-- DragonridingUtil.IsDragonridingUnlocked(), lua:1170–1173), the filter and right-click menus (UI/Menus).
-- The shown mount's InfoButton.Name (MountJournal_UpdateMountDisplay writes the mount's name, mainline/
--   blizzard_mountcollection.lua:693) is never a dictionary word (NEVER_TOUCH); while names are on it shows the name's
--   Japanese (UI/NameLabels) after each update. The client measures it only to place the "New" badge of a mount not
--   unwrapped yet (:699–700); that pass writes the badge's anchor and the button's label, and the mount is summoned
--   from the button's own click, which reads MountJournal.selectedMountID, a field that pass never writes (:837–841).
--   [unverified: whether C_MountJournal.SummonByID is protected on Forever; a summon from the journal in combat
--   after a fanfare mount was shown would show it]
-- Never touched: the source and lore text (client tables), the search box, the count.
-- The search box's placeholder is a label of its own, written once with SEARCH by SearchBoxTemplate_OnLoad
--   (blizzard_sharedxml/shared/inputbox/inputboxtemplates.lua:175–178): shown; what the player types is not read.
local _, WFJ = ...
local MountJournal = {}
WFJ.MountJournal = MountJournal

local SURFACE = "mountjournal"
MountJournal.SURFACE = SURFACE
local Compat = WFJ.Compat
local ADDON = "Blizzard_Collections"

local INFO = "MountJournal.MountDisplay.InfoButton"
MountJournal.NEVER_TOUCH = { INFO .. ".Name", INFO .. ".Source", INFO .. ".Lore", "MountJournal.searchBox",
  "MountJournal.MountCount.Count" }

local STATIC_LABELS = { -- record key → { candidate, the one key it shows }
  countLabel = { "MountJournal.MountCount.Label", "TOTAL_MOUNTS" },
  noMounts = { "MountJournal.MountDisplay.NoMounts", "ERR_NO_RIDING_SKILL" },
  infoNew = { INFO .. ".New", "NEW_CAPS" },
  togglePlayer = { "MountJournal.MountDisplay.ModelScene.TogglePlayer.TogglePlayerText", "MOUNT_JOURNAL_PLAYER" },
  slotRequirement = { "MountJournal.BottomLeftInset.SlotRequirementLabel", "MOUNT_EQUIPMENT_UNLOCK_REQUIREMENT" },
  searchHint = { "MountJournal.searchBox.Instructions", "SEARCH" },
}
local STATIC_ORDER = {}
for key in pairs(STATIC_LABELS) do STATIC_ORDER[#STATIC_ORDER + 1] = key end
table.sort(STATIC_ORDER)

local CANDIDATES = {
  frame = { "MountJournal" }, mountButton = { "MountJournal.MountButton" }, name = { INFO .. ".Name" },
  slotLabel = { "MountJournal.BottomLeftInset.SlotLabel" },
  suppressed = { "MountJournal.BottomLeftInset.SuppressedMountEquipmentButton" },
  filter = { "MountJournal.FilterDropdown" }, list = { "MountJournal.ScrollBox" }, scrollUtil = { "ScrollUtil" },
  updateDisplay = { "MountJournal_UpdateMountDisplay" }, updateEquipment = { "MountJournal_UpdateEquipment" },
  initButton = { "MountJournal_InitMountButton" },
}

local BUTTON_KEYS = { "MOUNT", "UNWRAP", "BINDING_NAME_DISMOUNT" }
local BUTTON = { only = BUTTON_KEYS }
local BUTTON_TOOLTIP_KEYS = { "MOUNT", "UNWRAP", "BINDING_NAME_DISMOUNT", "MOUNT_UNWRAP_TOOLTIP",
  "MOUNT_SUMMON_TOOLTIP" }
-- The button's keys and every error key, one set per index (an index rebuilt brings its own error keys). Without
-- UI/Errors, the button's keys alone.
local tooltipSet, tooltipIndex
local function buttonTooltipKeys()
  local index = WFJ.UIIndex
  if tooltipSet == nil or tooltipIndex ~= index then
    tooltipSet, tooltipIndex = {}, index
    for _, key in ipairs(BUTTON_TOOLTIP_KEYS) do tooltipSet[key] = true end
    if index and WFJ.Errors and type(WFJ.Errors.errorKeys) == "function" then
      for key in pairs(WFJ.Errors.errorKeys(index)) do tooltipSet[key] = true end
    end
  end
  return tooltipSet
end
-- HelpTooltip keeps the opts it was given: `only` is read at each walk, so it always names the current index's set
local BUTTON_TOOLTIP = setmetatable({}, { __index = function(_, field)
  if field == "only" then return buttonTooltipKeys() end
end })
local SLOT = { only = { "MOUNT_EQUIPMENT_NOTICE" } }
local SUPPRESSED_TOOLTIP = { only = { "MOUNT_EQUIPMENT_EXEMPT" } }
local ROW_NEW = { only = { "NEW_CAPS" } }
local ROW_STEADY = { only = { "MOUNT_JOURNAL_STEADY_FLIGHT_ONLY" } }

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  for key, l in pairs(STATIC_LABELS) do Compat.declare(SURFACE, "static." .. key, { l[1] }) end
end

local newKey = WFJ.Labels.keyer("row.new.") -- a pooled row's record keys
local steadyKey = WFJ.Labels.keyer("row.steady.")
local nameKey = WFJ.Labels.keyer("row.name.")

-- The labels the client writes once at load. → the number of dictionary words found.
function MountJournal.showStatic()
  local items = {}
  for _, key in ipairs(STATIC_ORDER) do
    items[#items + 1] = { key, get("static." .. key), { only = { STATIC_LABELS[key][2] } } }
  end
  local n = WFJ.Labels.showAll(SURFACE, items)
  return n + WFJ.Labels.dropdown(SURFACE, "filter", get("filter"))
end

-- hooksecurefunc target (MountJournal_UpdateMountDisplay): the mount button's word and the mount's name. → 0..2
function MountJournal.onDisplay()
  return WFJ.Labels.show(SURFACE, "mountButton", get("mountButton"), nil, BUTTON)
    + WFJ.NameLabels.show(SURFACE, "name", get("name"))
end

-- hooksecurefunc target (MountJournal_UpdateEquipment). → 1 | 0
function MountJournal.onEquipment()
  return WFJ.Labels.show(SURFACE, "slotLabel", get("slotLabel"), nil, SLOT)
end

-- One pooled list row after its initializer ran (ScrollUtil's initialized-frame callback: (owner, frame, elementData)
-- for a new row, (frame, elementData) for the iterateExisting pass). Returns nothing: ForEachFrame stops at the
-- first truthy return (see UI/Raid.onRow).
function MountJournal.onRow(a, b)
  local row = a
  if a == MountJournal then row = b end
  if type(row) ~= "table" then return end
  if type(row.new) == "table" then WFJ.Labels.show(SURFACE, newKey(row.new), row.new, nil, ROW_NEW) end
  local steady = row.SteadyFlightLabel
  if type(steady) == "table" then WFJ.Labels.show(SURFACE, steadyKey(steady), steady, nil, ROW_STEADY) end
  if type(row.name) == "table" then WFJ.NameLabels.show(SURFACE, nameKey(row.name), row.name) end
end

local hooked = false

-- Blizzard_Collections' part: runs once the addon is loaded (now, or on its ADDON_LOADED). → true when set up.
function MountJournal.setup()
  declare() -- its frames exist only now: forget what Compat memoized before
  if type(get("frame")) ~= "table" then return false end
  WFJ.Labels.forbidNames(MountJournal.NEVER_TOUCH) -- its widgets exist only now (Main's registration found none)
  MountJournal.showStatic()
  if hooked then return false end
  hooked = true
  if type(get("updateDisplay")) == "function" then
    hooksecurefunc("MountJournal_UpdateMountDisplay", MountJournal.onDisplay)
  end
  if type(get("updateEquipment")) == "function" then
    hooksecurefunc("MountJournal_UpdateEquipment", MountJournal.onEquipment)
  end
  WFJ.HelpTooltip.register(get("mountButton"), BUTTON_TOOLTIP)
  WFJ.HelpTooltip.register(get("suppressed"), SUPPRESSED_TOOLTIP)
  local list, util = get("list"), get("scrollUtil")
  if type(list) == "table" and type(util) == "table" and type(util.AddInitializedFrameCallback) == "function" then
    util.AddInitializedFrameCallback(list, MountJournal.onRow, MountJournal, true)
  end
  -- Selecting a mount fills the old and the new row again by calling the row's initializer itself, past the
  -- list's callback [verified: forever-ui-1.60.1.71037 blizzard_collections/mainline/
  -- blizzard_mountcollection.lua:790-815]: without this the selected row's name went back to English.
  if type(get("initButton")) == "function" then
    hooksecurefunc("MountJournal_InitMountButton", function(button) MountJournal.onRow(button) end)
  end
  MountJournal.onDisplay()
  MountJournal.onEquipment()
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init. → true when the tab was
-- set up now; false when it waits for Blizzard_Collections (or the client has no such window).
function MountJournal.init()
  declare()
  local ok = false
  WFJ.LoadOnDemand.when(ADDON, function() ok = MountJournal.setup() end)
  return ok
end
