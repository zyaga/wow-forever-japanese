-- UI/PetJournal.lua: the Pet Journal tab of the Collections window on Forever (surface "petjournal", area "ui",
-- ADR-016). camelot loads the companion-pet journal, not the battle-pet one: blizzard_collections.toc:30
-- excludes Shared\Blizzard_PetCollection.xml for camelot and :32–33 load Classic\Blizzard_PetCollection.lua|xml,
-- whose globals replace the shared file's. So there is no loadout, no pet card stats and no Find Battle button; the
-- strings of those widgets are excluded as not displayed. Blizzard_Collections is load-on-demand, so this waits for
-- it (UI/Collections.lua has the entry point). Without PetJournal nothing is set up.
-- Static labels (XML text= or an OnLoad write, each restricted to its own key):
--   PetCount.Label BATTLE_PETS_TOTAL_PETS (classic/blizzard_petcollection.xml:129–132 labelText);
--   SummonRandomPetSpellFrame.Label PET_JOURNAL_SUMMON_RANDOM_FAVORITE_PET (xml:140–145; UIPanelSpellButtonFrameMixin
--     :UpdateDisplay writes self.labelText on load and on SetSpellID, blizzard_uipaneltemplates/shared/
--     uipanelspellbuttonframe.lua:76–92, post-hooked on the frame);
--   PetCard.PetInfo.new NEW_CAPS (xml:244); FilterDropdown's button text FILTER.
-- Writers (globals called by name, post-hooked):
--   PetJournal_UpdateSummonButtonState → SummonButton text: PET_DISMISS, UNWRAP or BATTLE_PET_SUMMON (classic/
--     blizzard_petcollection.lua:186–199);
--   PetJournal_UpdatePetCard → PetCard.PetInfo.name: PET_JOURNAL_CARD_NAME_DEFAULT when nothing is selected, else
--     the pet's (custom) name (lua:570–609): the same FontString, hence `only`.
-- Pooled list rows (CompanionListButtonTemplate, xml:5–125; ScrollBox initializer lua:28–31), walked from the
-- ScrollBox's initialized-frame callback, keyed by widget: .new NEW_CAPS. A row's .name / .subName are pet names.
-- Tooltips (help-tooltip owners, each restricted to its keys):
--   PetCount: BATTLE_PETS_TOTAL_PETS + BATTLE_PETS_TOTAL_PETS_TOOLTIP (lua:733–738);
--   SummonButton: SetText(self:GetText()) + BATTLE_PETS_UNWRAP_TOOLTIP / BATTLE_PETS_SUMMON_TOOLTIP (lua:741–759);
--   PetCard.PetInfo: BATTLE_PET_NOT_TRADABLE, ITEM_UNIQUE (xml:267–283); its title is the species name and its
--     other lines are source / description text from client tables, never matched.
-- Not here: the filter and right-click menus (UI/Menus).
-- Never touched: pet names and custom names, the search box.
local _, WFJ = ...
local PetJournal = {}
WFJ.PetJournal = PetJournal

local SURFACE = "petjournal"
PetJournal.SURFACE = SURFACE
local Compat = WFJ.Compat
local ADDON = "Blizzard_Collections"

local CARD = "PetJournal.PetCard.PetInfo"
PetJournal.NEVER_TOUCH = { CARD .. ".subName", "PetJournal.searchBox" }

local STATIC_LABELS = { -- record key → { candidate, the one key it shows }
  countLabel = { "PetJournal.PetCount.Label", "BATTLE_PETS_TOTAL_PETS" },
  randomPet = { "PetJournal.SummonRandomPetSpellFrame.Label", "PET_JOURNAL_SUMMON_RANDOM_FAVORITE_PET" },
  cardNew = { CARD .. ".new", "NEW_CAPS" },
}
local STATIC_ORDER = {}
for key in pairs(STATIC_LABELS) do STATIC_ORDER[#STATIC_ORDER + 1] = key end
table.sort(STATIC_ORDER)

local CANDIDATES = {
  frame = { "PetJournal" }, summonButton = { "PetJournal.SummonButton" }, cardName = { CARD .. ".name" },
  card = { CARD }, count = { "PetJournal.PetCount" }, filter = { "PetJournal.FilterDropdown" },
  randomPet = { "PetJournal.SummonRandomPetSpellFrame" },
  list = { "PetJournal.ScrollBox" }, scrollUtil = { "ScrollUtil" },
  updateSummon = { "PetJournal_UpdateSummonButtonState" }, updateCard = { "PetJournal_UpdatePetCard" },
}

local BUTTON = { only = { "BATTLE_PET_SUMMON", "PET_DISMISS", "UNWRAP" } }
local BUTTON_TOOLTIP = { only = { "BATTLE_PET_SUMMON", "PET_DISMISS", "UNWRAP", "BATTLE_PETS_UNWRAP_TOOLTIP",
  "BATTLE_PETS_SUMMON_TOOLTIP" } }
local COUNT_TOOLTIP = { only = { "BATTLE_PETS_TOTAL_PETS", "BATTLE_PETS_TOTAL_PETS_TOOLTIP" } }
local CARD_TOOLTIP = { only = { "BATTLE_PET_NOT_TRADABLE", "ITEM_UNIQUE" } }
local CARD_NAME = { only = { "PET_JOURNAL_CARD_NAME_DEFAULT" } }
local ROW_NEW = { only = { "NEW_CAPS" } }

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  for key, l in pairs(STATIC_LABELS) do Compat.declare(SURFACE, "static." .. key, { l[1] }) end
end

local newKey = WFJ.Labels.keyer("row.new.") -- a pooled row's record key

-- The labels the client writes once at load. → the number of dictionary words found.
function PetJournal.showStatic()
  local items = {}
  for _, key in ipairs(STATIC_ORDER) do
    items[#items + 1] = { key, get("static." .. key), { only = { STATIC_LABELS[key][2] } } }
  end
  local n = WFJ.Labels.showAll(SURFACE, items)
  return n + WFJ.Labels.dropdown(SURFACE, "filter", get("filter"))
end

-- hooksecurefunc target (SummonRandomPetSpellFrame:UpdateDisplay). → 1 | 0
function PetJournal.onRandomPet()
  return WFJ.Labels.show(SURFACE, "randomPet", get("static.randomPet"), nil,
    { only = { STATIC_LABELS.randomPet[2] } })
end

-- hooksecurefunc target (PetJournal_UpdateSummonButtonState). → 1 | 0
function PetJournal.onSummonButton()
  return WFJ.Labels.show(SURFACE, "summonButton", get("summonButton"), nil, BUTTON)
end

-- hooksecurefunc target (PetJournal_UpdatePetCard). → 1 | 0
function PetJournal.onCard()
  return WFJ.Labels.show(SURFACE, "cardName", get("cardName"), nil, CARD_NAME)
end

-- One pooled list row after its initializer ran (see UI/MountJournal.onRow for the two argument shapes).
function PetJournal.onRow(a, b)
  local row = a
  if a == PetJournal then row = b end
  if type(row) ~= "table" or type(row.new) ~= "table" then return end
  WFJ.Labels.show(SURFACE, newKey(row.new), row.new, nil, ROW_NEW)
end

local hooked = false

-- Blizzard_Collections' part: runs once the addon is loaded (now, or on its ADDON_LOADED). → true when set up.
function PetJournal.setup()
  declare() -- its frames exist only now: forget what Compat memoized before
  if type(get("frame")) ~= "table" then return false end
  WFJ.Labels.forbidNames(PetJournal.NEVER_TOUCH) -- its widgets exist only now (Main's registration found none)
  PetJournal.showStatic()
  if hooked then return false end
  hooked = true
  if type(get("updateSummon")) == "function" then
    hooksecurefunc("PetJournal_UpdateSummonButtonState", PetJournal.onSummonButton)
  end
  if type(get("updateCard")) == "function" then hooksecurefunc("PetJournal_UpdatePetCard", PetJournal.onCard) end
  local random = get("randomPet")
  if type(random) == "table" and type(random.UpdateDisplay) == "function" then
    hooksecurefunc(random, "UpdateDisplay", PetJournal.onRandomPet)
  end
  WFJ.HelpTooltip.register(get("summonButton"), BUTTON_TOOLTIP)
  WFJ.HelpTooltip.register(get("count"), COUNT_TOOLTIP)
  WFJ.HelpTooltip.register(get("card"), CARD_TOOLTIP)
  local list, util = get("list"), get("scrollUtil")
  if type(list) == "table" and type(util) == "table" and type(util.AddInitializedFrameCallback) == "function" then
    util.AddInitializedFrameCallback(list, PetJournal.onRow, PetJournal, true)
  end
  PetJournal.onSummonButton()
  PetJournal.onCard()
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init. → true when the tab was
-- set up now; false when it waits for Blizzard_Collections (or the client has no such window).
function PetJournal.init()
  declare()
  local ok = false
  WFJ.LoadOnDemand.when(ADDON, function() ok = PetJournal.setup() end)
  return ok
end
