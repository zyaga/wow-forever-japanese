-- The Forever (camelot) client's Blizzard_Collections: CollectionsJournal with its five side tabs and the
-- MountJournal, PetJournal (the companion-pet journal camelot loads), ToyBox, HeirloomsJournal and
-- WardrobeCollectionFrame children, replaying the writes of the extracted 1.60.1 source:
--   blizzard_sharedxml/portraitframe.lua:4–14 (SetTitle → TitleContainer.TitleText),
--   blizzard_collections/shared/blizzard_collections.lua:72–112, 150–156 (titles per tab),
--   camelot/blizzard_collectionstabs.xml:20–46, blizzard_sharedxml/mainline/shareduipaneltemplates.lua:406–416,
--   shared/blizzard_collectiontemplates.lua:115–117, 144–148 (paging text, count label),
--   mainline/blizzard_mountcollection.{xml,lua} (lua:161–171, 533–540, 749–757, 842–861),
--   classic/blizzard_petcollection.{xml,lua} (lua:186–199, 570–609, 733–759),
--   mainline/blizzard_toybox.xml, camelot/blizzard_toyboxprogresstracker.xml,
--   mainline/blizzard_heirloomcollection.lua:449–452, 577–580,
--   mainline/blizzard_wardrobe.{xml,lua} (lua:430–449, 1741–1748), shared/blizzard_wardrobe_sets.lua:85–89.
-- A client write is stored as `fs.text = …` (not counted in fs.calls), so a spec can tell the addon's writes apart.
-- Requires wow_stub (Stub.install + Stub.installTooltipAPI first) and the English globals (H.uiSetup sets them).
local Stub = require("tests.lua.spec.wow_stub")

local C = { ADDON = "Blizzard_Collections" }

local function en(key) return _G[key] end
local function fs(text) return Stub.fontString(text or "") end

local function frame(kind, name, key)
  local f = CreateFrame(kind or "Frame", name)
  f.name = name or key
  return f
end

-- A Menu-system dropdown button: UpdateText writes the selection text into .Text (menutemplates.lua:530–540).
local function dropdown(key, text)
  local d = frame("DropdownButton", nil, key)
  d.Text = fs(text)
  d.selection = text
  function d.UpdateText(self) self.Text.text = self.selection end
  return d
end

-- CollectionsPagingFrameTemplate (mainline/blizzard_collectiontemplates.xml:4–40).
local function paging(key)
  local p = frame("Frame", nil, key)
  p.PageText = fs()
  p.currentPage, p.maxPages = 1, 1
  function p.Update(self)
    self.PageText.text = string.format(en("COLLECTION_PAGE_NUMBER"), self.currentPage, self.maxPages)
  end
  p:Update()
  return p
end

-- CollectionsCountTemplate: OnLoad writes Label from the labelText key value.
local function countBox(key, labelKey)
  local c = frame("Frame", nil, key)
  c.Count, c.Label = fs("0"), fs(en(labelKey))
  return c
end

local TAB_TITLES = { "MOUNTS", "PET_JOURNAL", "TOY_BOX", "HEIRLOOM", "WARDROBE" }

local function buildJournal()
  local j = frame("Frame", "CollectionsJournal")
  j.TitleContainer = { TitleText = fs() }
  function j.SetTitle(self, text) self.TitleContainer.TitleText.text = text end
  local tabs = frame("Frame", nil, "TabContainer")
  j.TabContainer = tabs
  tabs.Tabs = {}
  for i, def in ipairs({ { "MountsTab", "MOUNTS" }, { "PetsTab", "PET_JOURNAL" }, { "ToysTab", "TOY_BOX" },
    { "HeirloomsTab", "HEIRLOOMS" }, { "WardrobeTab", "WARDROBE" } }) do
    local tab = frame("Button", nil, def[1])
    tab.id, tab.tooltipText = i, en(def[2])
    tab:SetScript("OnEnter", function(self) -- SidePanelTabButtonMixin:OnEnter
      _G.GameTooltip:SetOwner(self)
      _G.GameTooltip:SetText(self.tooltipText)
    end)
    tabs[def[1]] = tab
    tabs.Tabs[i] = tab
  end
  j:SetTitle(en("COLLECTIONS")) -- CollectionsJournal_OnLoad
  function C.selectTab(id) -- CollectionsJournal_UpdateSelectedTab: the global HEIRLOOM does not exist → ""
    j:SetTitle(en(TAB_TITLES[id]) or "")
  end
  return j
end

local function listRow(extra)
  local row = frame("Button")
  row.name, row.new = fs(), fs(en("NEW_CAPS"))
  for k, v in pairs(extra or {}) do row[k] = v end
  return row
end

local function buildMounts(parent)
  local m = frame("Frame", "MountJournal")
  m.parent = parent
  m.MountCount = countBox("MountCount", "TOTAL_MOUNTS")
  m.MountButton = Stub.button("MountJournalMountButton", en("MOUNT"))
  m.searchBox = frame("EditBox", "MountJournalSearchBox")
  m.FilterDropdown = dropdown("FilterDropdown", en("FILTER"))
  local display = frame("Frame", nil, "MountDisplay")
  m.MountDisplay = display
  display.NoMounts = fs(en("ERR_NO_RIDING_SKILL"))
  local info = frame("Button", nil, "InfoButton")
  display.InfoButton = info
  info.Name, info.Source, info.Lore, info.New = fs(), fs(), fs(), fs(en("NEW_CAPS"))
  display.ModelScene = { TogglePlayer = { TogglePlayerText = fs(en("MOUNT_JOURNAL_PLAYER")) } }
  local inset = frame("Frame", nil, "BottomLeftInset")
  m.BottomLeftInset = inset
  inset.SlotLabel = fs()
  inset.SlotRequirementLabel = fs(string.format(en("MOUNT_EQUIPMENT_UNLOCK_REQUIREMENT"), "20"))
  inset.SuppressedMountEquipmentButton = frame("Button", nil, "SuppressedMountEquipmentButton")
  m.ScrollBox = Stub.scrollBox()
  C.mountRows = {}
  function C.mountRow(i, data) -- MountJournal_InitMountButton
    local row = C.mountRows[i]
    if not row then
      row = listRow({ SteadyFlightLabel = fs(en("MOUNT_JOURNAL_STEADY_FLIGHT_ONLY")) })
      C.mountRows[i] = row
    end
    m.ScrollBox:initFrame(row, data, function(r, d) r.name.text = d.name end)
    return row
  end
  _G.MountJournal_UpdateMountDisplay = function() -- lua:749–757, 692–710
    local s = C.mount or {}
    info.Name.text, info.Source.text, info.Lore.text = s.name or "", s.source or "", s.lore or ""
    local key = s.needsFanfare and "UNWRAP" or (s.active and "BINDING_NAME_DISMOUNT" or "MOUNT")
    m.MountButton.fontString.text = en(key)
  end
  _G.MountJournal_UpdateEquipment = function() -- lua:533, 540
    inset.SlotLabel.text = C.equipmentName or en("MOUNT_EQUIPMENT_NOTICE")
  end
  _G.MountJournal_UpdateEquipment()
  return m
end

local function buildPets(parent)
  local p = frame("Frame", "PetJournal")
  p.parent = parent
  p.PetCount = countBox("PetCount", "BATTLE_PETS_TOTAL_PETS")
  p.SummonButton = Stub.button("PetJournalSummonButton", en("BATTLE_PET_SUMMON"))
  p.searchBox = frame("EditBox", "PetJournalSearchBox")
  p.FilterDropdown = dropdown("FilterDropdown", en("FILTER"))
  local random = frame("Frame", nil, "SummonRandomPetSpellFrame")
  p.SummonRandomPetSpellFrame = random
  random.Label = fs()
  random.labelText = en("PET_JOURNAL_SUMMON_RANDOM_FAVORITE_PET")
  function random.UpdateDisplay(self) self.Label.text = self.labelText end
  random:UpdateDisplay()
  local card = frame("Frame", "PetJournalPetCard")
  p.PetCard = card
  local info = frame("Button", "PetJournalPetCardPetInfo")
  card.PetInfo = info
  info.name, info.subName, info.new = fs(), fs(), fs(en("NEW_CAPS"))
  p.ScrollBox = Stub.scrollBox()
  C.petRows = {}
  function C.petRow(i, data) -- PetJournal_InitPetButton
    local row = C.petRows[i]
    if not row then
      row = listRow({ subName = fs() })
      C.petRows[i] = row
    end
    p.ScrollBox:initFrame(row, data, function(r, d) r.name.text = d.name end)
    return row
  end
  _G.PetJournal_UpdateSummonButtonState = function() -- lua:186–199
    local s = C.pet or {}
    local key = s.summoned and "PET_DISMISS" or (s.needsFanfare and "UNWRAP" or "BATTLE_PET_SUMMON")
    p.SummonButton.fontString.text = en(key)
  end
  _G.PetJournal_UpdatePetCard = function() -- lua:570–609
    local s = C.pet
    if not s then
      info.name.text = en("PET_JOURNAL_CARD_NAME_DEFAULT")
      return
    end
    info.name.text = s.customName or s.name
    info.subName.text = s.customName and s.name or ""
  end
  _G.PetJournal_UpdatePetCard()
  return p
end

local function buildToyBox(parent)
  local t = frame("Frame", "ToyBox")
  t.parent = parent
  t.ProgressTracker = countBox("ProgressTracker", "TOTAL_TOYS")
  t.searchBox = frame("EditBox", nil, "searchBox")
  t.FilterDropdown = dropdown("FilterDropdown", en("FILTER"))
  t.PagingFrame = paging("ToyPagingFrame")
  t.iconsFrame = frame("Frame", nil, "iconsFrame")
  for i = 1, 18 do
    local b = frame("CheckButton")
    b.name, b.new = fs(), fs(en("NEW_CAPS"))
    t.iconsFrame["spellButton" .. i] = b
  end
  return t
end

local function buildHeirlooms(parent)
  local h = frame("Frame", "HeirloomsJournal")
  h.parent = parent
  h.SearchBox = frame("EditBox", "HeirloomsJournalSearchBox")
  h.FilterDropdown = dropdown("FilterDropdown", en("FILTER"))
  h.ClassDropdown = dropdown("ClassDropdown", "Hunter")
  h.PagingFrame = paging("HeirloomPagingFrame")
  h.heirloomHeaderFrames, h.heirloomEntryFrames = {}, {}
  function h.UpdateButton(_, button) -- lua:558–626
    button.name.text = button.item.name
    button.special.text = button.item.pvp and en("HEIRLOOMS_PVP") or ""
  end
  -- layout = { "HEIRLOOMS_CATEGORY_HEAD", { name = …, pvp = … }, … } (a header key or an entry), lua:442–490
  function h.LayoutCurrentPage(self)
    local headers, entries = 0, 0
    for _, data in ipairs(C.heirloomPage or {}) do
      if type(data) == "string" then
        headers = headers + 1
        local header = self.heirloomHeaderFrames[headers]
        if not header then
          header = frame("Frame")
          header.text = fs()
          self.heirloomHeaderFrames[headers] = header
        end
        header.text.text = en(data)
      else
        entries = entries + 1
        local entry = self.heirloomEntryFrames[entries]
        if not entry then
          entry = frame("CheckButton")
          entry.name, entry.special, entry.level = fs(), fs(), fs()
          self.heirloomEntryFrames[entries] = entry
        end
        entry.item = data
        self:UpdateButton(entry)
      end
    end
  end
  return h
end

local SLOTS = { "HEADSLOT", "SHOULDERSLOT", "BACKSLOT", "MAINHANDSLOT" }

local function buildWardrobe(parent)
  local w = frame("Frame", "WardrobeCollectionFrame")
  w.parent = parent
  w.ItemsTab = Stub.tab("WardrobeCollectionFrameTab1", en("WARDROBE_ITEMS"))
  w.SetsTab = Stub.tab("WardrobeCollectionFrameTab2", en("WARDROBE_SETS"))
  local search = frame("EditBox", "WardrobeCollectionFrameSearchBox")
  w.SearchBox = search
  search.ProgressFrame = { LoadingFrame = { Text = fs(en("SEARCH_LOADING_TEXT")) },
    ProgressBar = { text = fs(en("SEARCH_PROGRESS_BAR_TEXT")) } }
  w.FilterButton = dropdown("FilterButton", en("FILTER"))
  w.ClassDropdown = dropdown("ClassDropdown", "Hunter")
  local items = frame("Frame", nil, "ItemsCollectionFrame")
  w.ItemsCollectionFrame = items
  items.PagingFrame = paging("WardrobePagingFrame")
  items.Models = {}
  for i = 1, 3 do
    local model = frame("DressUpModel")
    model.NewString = fs(en("NEW_CAPS"))
    items.Models[i] = model
  end
  items.SlotsFrame = frame("Frame", nil, "SlotsFrame")
  items.SlotsFrame.Buttons = {}
  for i, slot in ipairs(SLOTS) do
    local b = frame("Button")
    b.slot = slot
    items.SlotsFrame.Buttons[i] = b
  end
  local sets = frame("Frame", nil, "SetsCollectionFrame")
  w.SetsCollectionFrame = sets
  local details = frame("Frame", nil, "DetailsFrame")
  sets.DetailsFrame = details
  details.Name, details.LongName, details.Label = fs(), fs(), fs()
  details.LimitedSet = frame("Frame", nil, "LimitedSet")
  details.LimitedSet.Text = fs(en("TRANSMOG_SET_LIMITED_TIME_SET"))
  details.VariantSetsDropdown = dropdown("VariantSetsDropdown", "Mythic")
  details.VariantSetsDropdown.PrecedingVariantIcon = frame("Frame", nil, "PrecedingVariantIcon")
  -- the frame appended to the shortcuts HelpTip, two XML labels (mainline/blizzard_wardrobe.xml:164–180)
  local shortcuts = CreateFrame("Frame", "TrackingInterfaceShortcutsFrame")
  shortcuts.HeaderText = fs(en("WARDROBE_SHORTCUTS_TUTORIAL_2"))
  shortcuts.Text = fs(en("WARDROBE_SHORTCUTS_TUTORIAL_3"))
  return w
end

-- Builds the whole window and marks the addon loaded. → CollectionsJournal
function C.load()
  C.mount, C.pet, C.equipmentName, C.heirloomPage = nil, nil, nil, nil
  local journal = buildJournal()
  buildMounts(journal)
  buildPets(journal)
  buildToyBox(journal)
  buildHeirlooms(journal)
  buildWardrobe(journal)
  Stub.loadedAddons[C.ADDON] = true
  return journal
end

C.GLOBALS = { "CollectionsJournal", "MountJournal", "MountJournalMountButton", "MountJournalSearchBox",
  "MountJournal_UpdateMountDisplay", "MountJournal_UpdateEquipment", "PetJournal", "PetJournalSummonButton",
  "PetJournalSearchBox", "PetJournalPetCard", "PetJournalPetCardPetInfo", "PetJournal_UpdateSummonButtonState",
  "PetJournal_UpdatePetCard", "ToyBox", "HeirloomsJournal", "HeirloomsJournalSearchBox", "WardrobeCollectionFrame",
  "WardrobeCollectionFrameTab1", "WardrobeCollectionFrameTab2", "WardrobeCollectionFrameSearchBox",
  "TrackingInterfaceShortcutsFrame" }

function C.unload()
  for _, name in ipairs(C.GLOBALS) do _G[name] = nil end
end

-- The Japanese dictionary the four collections specs share: KEY = { English, Japanese }.
C.UI = {
  COLLECTIONS = { "Account Collections", "アカウントコレクション" }, MOUNTS = { "Mounts", "マウント" },
  PET_JOURNAL = { "Pet Journal", "ペットジャーナル" }, TOY_BOX = { "Toy Box", "おもちゃ箱" },
  HEIRLOOMS = { "Heirlooms", "家宝" }, WARDROBE = { "Appearances", "外見" },
  COLLECTION_PAGE_NUMBER = { "Page %d / %d", "ページ %d / %d" }, TOTAL_TOYS = { "Total Toys", "おもちゃ総数" },
  NEW_CAPS = { "NEW", "新規" }, FILTER = { "Filter", "フィルター" },
  HEIRLOOMS_CATEGORY_HEAD = { "Head", "頭" }, HEIRLOOMS_CATEGORY_WEAPON = { "Weapons", "武器" },
  HEIRLOOMS_PVP = { "PvP", "PvP戦" },
  TOTAL_MOUNTS = { "Total Mounts", "マウント総数" }, MOUNT = { "Mount", "騎乗" }, UNWRAP = { "Unwrap", "開封" },
  BINDING_NAME_DISMOUNT = { "Dismount", "降りる" },
  MOUNT_UNWRAP_TOOLTIP = { "Open to receive your new mount.", "開封して新しいマウントを受け取ります。" },
  MOUNT_SUMMON_TOOLTIP = { "Summons or dismisses your selected mount.", "選択したマウントを召喚または解除します。" },
  ERR_NO_RIDING_SKILL = { "You can learn riding and obtain a mount from your riding trainer at level 10",
    "レベル10で騎乗トレーナーから騎乗を習得し、マウントを入手できます" },
  MOUNT_JOURNAL_PLAYER = { "Show Character", "キャラクターを表示" },
  MOUNT_JOURNAL_STEADY_FLIGHT_ONLY = { "Steady Flight Only", "安定飛行のみ" },
  MOUNT_EQUIPMENT_NOTICE = { "Enhance your mounts with Mount Equipment", "マウント装備でマウントを強化しよう" },
  MOUNT_EQUIPMENT_UNLOCK_REQUIREMENT = { "Mount Equipment unlocked at Level %s", "マウント装備はレベル%sで解放" },
  MOUNT_EQUIPMENT_EXEMPT = {
    "Your active mount doesn't benefit from Mount Equipment because it already has an ability.",
    "現在のマウントは既にアビリティを持っているため、マウント装備の効果を受けません。" },
  BATTLE_PETS_TOTAL_PETS = { "Total Pets", "ペット総数" },
  BATTLE_PETS_TOTAL_PETS_TOOLTIP = { "Total number of pets owned.", "所有しているペットの総数。" },
  BATTLE_PET_SUMMON = { "Summon", "召喚" }, PET_DISMISS = { "Dismiss", "帰還" },
  BATTLE_PETS_UNWRAP_TOOLTIP = { "Open to receive your new pet.", "開封して新しいペットを受け取ります。" },
  BATTLE_PETS_SUMMON_TOOLTIP = { "Summons or dismisses your selected pet.", "選択したペットを召喚または解除します。" },
  PET_JOURNAL_CARD_NAME_DEFAULT = { "Select a pet from the list on the left.", "左のリストからペットを選択してください。" },
  BATTLE_PET_NOT_TRADABLE = { "This pet is not tradeable.", "このペットは取引できません。" },
  ITEM_UNIQUE = { "Unique", "ユニーク" },
  PET_JOURNAL_SUMMON_RANDOM_FAVORITE_PET = { "Summon Random\nFavorite Pet", "お気に入りのペットを\nランダムに召喚" },
  WARDROBE_ITEMS = { "Items", "アイテム" }, WARDROBE_SETS = { "Sets", "セット" },
  SEARCH_LOADING_TEXT = { "Loading...", "読み込み中..." }, SEARCH_PROGRESS_BAR_TEXT = { "Searching", "検索中" },
  TRANSMOG_SET_LIMITED_TIME_SET = { "Limited Time Set", "期間限定セット" },
  WARDROBE_SHORTCUTS_TUTORIAL_2 = { "|cFFFFD200[Shift Click]|r", "|cFFFFD200[Shiftクリック]|r" },
  WARDROBE_SHORTCUTS_TUTORIAL_3 = { "Set up tracking for the source of an appearance.",
    "外見の入手元の追跡を設定します。" },
  TRANSMOG_SET_LIMITED_TIME_SET_TOOLTIP = { "This set can be collected during the current season only.",
    "このセットは現在のシーズン中のみ収集できます。" },
  TRANSMOG_SET_GRANTS_PRECEDING_VARIANTS = { "Completing this appearance set unlocks all preceding set variants.",
    "この外見セットを完成させると、それ以前のセットバリエーションがすべて解放されます。" },
  WARDROBE_NO_SEARCH = { "Search is not available for this category.", "このカテゴリーでは検索できません。" },
  WEAPON_ENCHANTMENT = { "Weapon Enchantment", "武器エンチャント" },
  LEFTSHOULDERSLOT = { "Left Shoulder", "左肩" }, RIGHTSHOULDERSLOT = { "Right Shoulder", "右肩" },
  HEADSLOT = { "Head", "頭" },
  CLOSE = { "Close", "閉じる" }, -- a word a mount, a pet or a set may happen to be called
}

return C
