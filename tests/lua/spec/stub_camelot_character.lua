-- The Forever (camelot) character window: CharacterFrame's icon mode tabs, the paperdoll level line,
-- the stat-pane ScrollBoxes, an equipment slot, and ReputationFrame (its list ScrollBox and its detail side pane),
-- replaying the writes of the extracted 1.60.1 source:
--   blizzard_uipanels_game/camelot/characterframe.lua:832–951 (CharacterFrameSidePaneMixin), 1049–1298 (stat pane),
--   characterframe.xml:170–234, 574–603; camelot/paperdollframe.lua:497–558 (level lines), 2181–2221 (slot and stat
--   tooltips), 2428–2437 (PaperDollFrame_SetLabelAndText); blizzard_framexmlutil/itemutil.lua:395–414;
--   blizzard_sharedxml/mainline/shareduipaneltemplates.lua:406–420 (mode tab tooltip);
--   camelot/reputationframe.lua:274–435, 509–531, 650–677, 735–819, 875–930, reputationframe.xml:3–367.
-- A client write is stored as `fs.text = …` (not counted in fs.calls), so a spec can tell the addon's writes apart.
-- Requires wow_stub (Stub.install + Stub.installTooltipAPI first). Globals are set and read through _G.
local Stub = require("tests.lua.spec.wow_stub")

local RC = {}

RC.EN = {
  CHARACTER_FRAME_TAB_CHARACTER = "Character", CHARACTER_FRAME_TAB_REPUTATION = "Reputation",
  CHARACTER_FRAME_TAB_SKILLS = "Skills", CHARACTER_FRAME_TAB_PVP = "PvP", CHARACTER_FRAME_TAB_CURRENCY = "Currency",
  CHARACTER_FRAME_TAB_STATISTICS = "Statistics",
  PLAYER_LEVEL = "Level %s |c%s%s %s|r", PLAYER_LEVEL_NO_SPEC = "Level %s |c%s%s|r",
  UNIT_TYPE_LEVEL_TEMPLATE = "Level %d %s", STAT_FORMAT = "%s:", HEADSLOT = "Head",
  STAT_CATEGORY_GENERAL = "General", STAT_CATEGORY_PRIMARY_ATTRIBUTES = "Primary Attributes",
  STAT_CATEGORY_RESISTANCE = "Resistances",
  SPELL_STAT3_NAME = "Stamina", DEFAULT_STAMINA_TOOLTIP = "Increases health points.", DAMAGE_SCHOOL3 = "Fire",
  REPUTATION_DETAIL_SELECT_PROMPT = "Select a faction to view its details.",
  REPUTATION_TOOLTIP_ACCOUNT_WIDE_LABEL = "Reputation is shared across your Warband.",
  AT_WAR = "At War", MOVE_TO_INACTIVE = "Move to Inactive", SHOW_FACTION_ON_MAINSCREEN = "Show as Experience Bar",
  VIEW_RENOWN_BUTTON_LABEL = "View Renown", REPUTATION_AT_WAR_DESCRIPTION = "Turning this on lets you attack them.",
  REPUTATION_MOVE_TO_INACTIVE = "Moves this faction to the Inactive list.",
  REPUTATION_SHOW_AS_XP = "Shows this faction as a bar below your action bars.",
  FACTION_STANDING_LABEL5 = "Friendly", FACTION_STANDING_LABEL5_FEMALE = "Friendly",
  FACTION_STANDING_LABEL6 = "Honored", FACTION_STANDING_LABEL6_FEMALE = "Honored",
  FACTION_INACTIVE = "Inactive", FACTION_OTHER = "Other", REPUTATION_PROGRESS_FORMAT = "%s / %s",
  RENOWN_LEVEL_LABEL = "Renown %d",
  EQUIPSET_EQUIP = "Equip", SAVE = "Save", PAPERDOLL_NEWEQUIPMENTSET = "New Set", DELETE = "Delete",
  EQUIPMENT_SET_SETTINGS = "Settings", GEARSETS_POPUP_TEXT = "Enter Set Name (Max 16 Characters):",
  ICON_SELECTION_CLICK = "Click to view in the list", ICON_SELECTION_NOTINLIST = "This icon is not in the list",
}
local function G(key) return _G[key] or RC.EN[key] end
RC.G = G

local function hoverTooltip(owner, first, rest)
  local tt = _G.GameTooltip
  tt:SetOwner(owner, "ANCHOR_RIGHT")
  tt:ClearLines() -- the client's SetOwner starts an empty tooltip
  if first then tt:SetText(first) end
  for _, line in ipairs(rest or {}) do tt:AddLine(line) end
  tt:Show()
end

-- ───────────────────────────────────── the paperdoll (CharacterFrame) ─────────────────────────────────────
local function installPaperDoll()
  local cf = CreateFrame("Frame", "CharacterFrame")
  cf.TitleContainer = { TitleText = Stub.fontString("Reyn") } -- SetTitle(UnitPVPName("player"))
  local keys = { "CHARACTER", "REPUTATION", "SKILLS", "PVP", "CURRENCY", "STATISTICS" }
  for i, k in ipairs(keys) do
    local tab = CreateFrame("Frame", "CharacterFrameModeTab" .. i)
    tab.tooltipText = G("CHARACTER_FRAME_TAB_" .. k) -- KeyValue tooltipText (characterframe.xml:574–603)
    tab:SetScript("OnEnter", function(self) hoverTooltip(self, self.tooltipText) end)
  end
  CreateFrame("Frame", "PaperDollFrame")
  Stub.namedFontString("CharacterLevelText", "")
  -- RC.player = { level, color, spec, class, pet = { level, family } | nil }
  RC.player = { level = "60", color = "ffc79c6e", spec = "Protection", class = "Warrior" }
  _G.PaperDollFrame_SetLevel = function() -- paperdollframe.lua:497–531
    local p = RC.player
    if p.spec then
      _G.CharacterLevelText.text = G("PLAYER_LEVEL"):format(p.level, p.color, p.spec, p.class)
    else
      _G.CharacterLevelText.text = G("PLAYER_LEVEL_NO_SPEC"):format(p.level, p.color, p.class)
    end
  end
  _G.PaperDollFrame_SetPetLevel = function() -- :533–558
    local pet = RC.player.pet
    if pet then _G.CharacterLevelText.text = G("UNIT_TYPE_LEVEL_TEMPLATE"):format(pet.level, pet.family) end
  end
  _G.PaperDollFrame_UpdateStats = function() end -- the ScrollBox path is driven by RC.setStats
  -- an equipment slot: an empty slot's tooltip is SetText(<SLOT>SLOT) (itemutil.lua:395–414)
  local slot = CreateFrame("Button", "CharacterHeadSlot")
  RC.headItem = nil
  slot:SetScript("OnEnter", function(self)
    if RC.headItem then
      _G.GameTooltip:SetOwner(self)
      Stub.setItemTooltip(_G.GameTooltip, RC.headItem, { "Lionheart Helm" })
    else
      hoverTooltip(self, G("HEADSLOT"))
    end
  end)
  -- the stat panes: CharacterStatsPaneScrollBox / CharacterStatsPanePetScrollBox, each with its ScrollBox
  for _, name in ipairs({ "CharacterStatsPaneScrollBox", "CharacterStatsPanePetScrollBox" }) do
    local pane = CreateFrame("Frame", name)
    pane.ScrollBox = Stub.scrollBox()
    pane.pool = { header = {}, stat = {} }
  end
end

local function statRow(kind)
  local row = CreateFrame("Frame")
  if kind == "header" then
    row.Title = Stub.fontString("")
  else
    row.Label, row.Value = Stub.fontString(""), Stub.fontString("")
    row:SetScript("OnEnter", function(self) -- CharacterStatFrameMixin:OnEnter → PaperDollStatTooltip
      if not self.tooltip then return end
      hoverTooltip(self, self.tooltip, { self.tooltip2 })
    end)
  end
  return row
end

-- ───────────────────── the equipment manager pane and its name-and-icon popup (camelot) ─────────────────────
local function installEquipmentManager()
  local pane = CreateFrame("Frame", nil, _G.PaperDollFrame)
  _G.PaperDollFrame.EquipmentManagerPane = pane
  pane.EquipSet = Stub.button(nil, G("EQUIPSET_EQUIP")) -- xml text= (paperdollframe.xml:545, 555)
  pane.SaveSet = Stub.button(nil, G("SAVE"))
  pane.NewSet = CreateFrame("Button")
  pane.NewSet:addRegion(Stub.fontString(G("PAPERDOLL_NEWEQUIPMENTSET"))) -- unnamed FontString (xml:24)
  pane.ScrollBox = Stub.scrollBox()
  RC.setRows = {}
  local popup = CreateFrame("Frame", "GearManagerPopupFrame")
  popup.BorderBox = {
    EditBoxHeaderText = Stub.fontString(G("GEARSETS_POPUP_TEXT")), -- OnLoad (shareduipaneltemplates.lua:1844)
    IconSelectorEditBox = Stub.fontString(""),
    SelectedIconArea = { SelectedIconText = { SelectedIconDescription = Stub.fontString("") } },
  }
  RC.iconInList = true
  local function describe(text)
    popup.BorderBox.SelectedIconArea.SelectedIconText.SelectedIconDescription.text = text
  end
  function popup.SetSelectedIconText() -- shareduipaneltemplates.lua:1967–1975
    describe(RC.iconInList and G("ICON_SELECTION_CLICK") or G("ICON_SELECTION_NOTINLIST"))
  end
  popup.IconSelector = { selectedCallback = function() describe(G("ICON_SELECTION_CLICK")) end }
  function popup.IconSelector.SetSelectedIndex(self, i) self.selectedIndex = i end
  function popup.IconSelector.OnSelection(self, i) -- blizzard_selectorui.lua:3–9
    if self.selectedCallback then self.selectedCallback(i) end
    self:SetSelectedIndex(i)
  end
end

-- Replays PaperDollEquipmentManagerPane_Update → SetDataProvider: pooled GearSetButtonTemplate rows, `.text` = the
-- set's name; DeleteButton / EditButton tooltips (paperdollframe.xml:309–357). → the rows
function RC.setGearSets(names)
  local box = _G.PaperDollFrame.EquipmentManagerPane.ScrollBox
  for i, name in ipairs(names) do
    local row = RC.setRows[i]
    if not row then
      row = CreateFrame("Button")
      row.text = Stub.fontString("")
      row.DeleteButton, row.EditButton = CreateFrame("Button"), CreateFrame("Button")
      row.DeleteButton:SetScript("OnEnter", function(self) hoverTooltip(self, G("DELETE")) end)
      row.EditButton:SetScript("OnEnter", function(self) hoverTooltip(self, G("EQUIPMENT_SET_SETTINGS")) end)
      RC.setRows[i] = row
    end
    box:initFrame(row, { index = i }, function(frame) frame.text.text = name end)
  end
  return RC.setRows
end

-- Replays CharacterStatsPaneScrollBoxMixin:UpdateStats → SetDataProvider: every element is initialized again on a
-- pooled row (the i-th header / stat row of the pane). `list` = { { header = "English" } | { label = "English",
-- value, tooltip, tooltip2 } }. → the rows, in order.
function RC.setStats(list, paneName)
  local pane = _G[paneName or "CharacterStatsPaneScrollBox"]
  local used, out = { header = 0, stat = 0 }, {}
  for i, e in ipairs(list) do
    local kind = e.header and "header" or "stat"
    used[kind] = used[kind] + 1
    local row = pane.pool[kind][used[kind]]
    if not row then row = statRow(kind); pane.pool[kind][used[kind]] = row end
    pane.ScrollBox:initFrame(row, e, function(frame, data)
      if data.header then
        frame.Title.text = data.header -- CharacterStatFrameCategoryScrollBoxElementMixin:Init
      else
        frame.Label.text = G("STAT_FORMAT"):format(data.label) -- PaperDollFrame_SetLabelAndText
        frame.Value.text = data.value or ""
        frame.tooltip, frame.tooltip2 = data.tooltip, data.tooltip2
      end
    end)
    out[i] = row
  end
  return out
end

-- ───────────────────────────────────── ReputationFrame (camelot) ─────────────────────────────────────
local function newPaneRow()
  local row = CreateFrame("Frame")
  row.Label = Stub.fontString("")
  row.Label.width = 200
  function row.Label.GetStringHeight(fs) return fs:GetHeight() end
  row.height = 1
  function row.GetHeight(self) return self.height end
  function row.SetHeight(self, h) self.height = h end
  return row
end

local function checkbox(detail, key, labelKey, tooltipKey)
  local cb = CreateFrame("CheckButton")
  cb.Label = Stub.fontString(G(labelKey)) -- xml text= (reputationframe.xml:266, 300, 328)
  cb:SetScript("OnEnter", function(self) hoverTooltip(self, nil, { G(tooltipKey) }) end) -- lua:875–930
  detail[key] = cb
end

local function installReputation()
  local frame = CreateFrame("Frame", "ReputationFrame")
  frame.ScrollBox = Stub.scrollBox()
  RC.repPool = { header = {}, entry = {} }
  local detail = CreateFrame("Frame", nil, frame)
  frame.ReputationDetailFrame = detail
  detail.EmptyText = Stub.fontString("")
  detail.Title, detail.Subtitle, detail.Description = Stub.fontString(""), Stub.fontString(""), Stub.fontString("")
  RC.layouts = 0
  detail.Content = { Layout = function() RC.layouts = RC.layouts + 1 end }
  local pools = { free = {}, active = {} }
  function pools.EnumerateActive(self)
    local i = 0
    return function() i = i + 1; return self.active[i] end
  end
  function pools.ReleaseAll(self)
    for _, row in ipairs(self.active) do table.insert(self.free, row); row:Hide() end
    self.active = {}
  end
  function pools.Acquire(self)
    local row = table.remove(self.free) or newPaneRow()
    self.active[#self.active + 1] = row
    row:Show()
    return row
  end
  detail.rowPools = pools
  RC.paneRows = pools
  -- CharacterFrameSidePaneMixin (characterframe.lua:850–951), copied onto the instance
  function detail.SetPaneTitle(self, title, subtitle)
    self.Title.text = title or ""
    self.Subtitle.text = subtitle or ""
  end
  function detail.ResetRows(self) self.rowPools:ReleaseAll() end
  function detail.AddWrappedRow(self, text)
    local row = self.rowPools:Acquire()
    row.Label.text = text or ""
    row:SetHeight(math.max(1, row.Label:GetStringHeight()))
  end
  function detail.LayoutRows(self) self.Content:Layout() end
  function detail.SetEmpty(self, text)
    self:ResetRows()
    self:LayoutRows()
    self:SetPaneTitle(nil, nil)
    self.EmptyText.text = text or ""
    self.EmptyText:Show()
  end
  checkbox(detail, "AtWarCheckbox", "AT_WAR", "REPUTATION_AT_WAR_DESCRIPTION")
  checkbox(detail, "MakeInactiveCheckbox", "MOVE_TO_INACTIVE", "REPUTATION_MOVE_TO_INACTIVE")
  checkbox(detail, "WatchFactionCheckbox", "SHOW_FACTION_ON_MAINSCREEN", "REPUTATION_SHOW_AS_XP")
  detail.ViewRenownButton = Stub.button(nil, G("VIEW_RENOWN_BUTTON_LABEL"))
  -- ReputationDetailFrameMixin:Refresh (lua:756–792), registered by reference: only SetEmpty / SetPaneTitle /
  -- LayoutRows are reached by method lookup. RC.selected = nil | { name, description, standing, accountWide }
  function detail.Refresh(self)
    local f = RC.selected
    if not f then self:SetEmpty(G("REPUTATION_DETAIL_SELECT_PROMPT")); return end
    self.EmptyText:Hide()
    self:SetPaneTitle(f.name, f.standing)
    self.Description.text = f.description or ""
    self:ResetRows()
    if f.accountWide then self:AddWrappedRow(G("REPUTATION_TOOLTIP_ACCOUNT_WIDE_LABEL")) end
    self:LayoutRows()
  end
end

local function repRow(kind)
  local row = CreateFrame("Button")
  if kind == "header" then
    row.Name = Stub.fontString("")
    return row
  end
  local bar = CreateFrame("Frame")
  bar.Text = Stub.fontString("")
  bar.BonusIcon = CreateFrame("Frame")
  local icon = CreateFrame("Frame")
  row.Content = { Name = Stub.fontString(""), ReputationBar = bar, AccountWideIcon = icon }
  -- the entry's OnEnter shows the progress numbers, OnLeave the English standing again (lua:388–435)
  row:SetScript("OnEnter", function() if bar.progress then bar.Text.text = bar.progress end end)
  row:SetScript("OnLeave", function() if bar.standing then bar.Text.text = bar.standing end end)
  icon:SetScript("OnEnter", function(self)
    hoverTooltip(self, nil, { G("REPUTATION_TOOLTIP_ACCOUNT_WIDE_LABEL") })
  end)
  icon:SetScript("OnLeave", function() row.scripts.OnLeave(row) end) -- calls the entry's OnLeave (lua:319–322)
  return row
end

-- Replays the list's SetDataProvider: `list` = { { header = "Name" } | { name, standing, progress } }. → rows
function RC.setFactions(list)
  local box = _G.ReputationFrame.ScrollBox
  local used, out = { header = 0, entry = 0 }, {}
  for i, e in ipairs(list) do
    local kind = e.header and "header" or "entry"
    used[kind] = used[kind] + 1
    local row = RC.repPool[kind][used[kind]]
    if not row then row = repRow(kind); RC.repPool[kind][used[kind]] = row end
    box:initFrame(row, e, function(frame, data)
      if data.header then
        frame.Name.text = data.header -- ReputationHeaderMixin:Initialize
      else
        frame.Content.Name.text = data.name -- ReputationEntryMixin:Initialize
        local bar = frame.Content.ReputationBar
        bar.standing = data.standing
        bar.progress = data.progress and ("|cffffffff" .. data.progress .. "|r") or nil
        bar.Text.text = data.standing -- TryShowReputationStandingText
      end
    end)
    out[i] = row
  end
  return out
end

function RC.select(faction)
  RC.selected = faction
  _G.ReputationFrame.ReputationDetailFrame:Refresh() -- the EventRegistry path, not a method hook
end

function RC.hover(owner) if owner.scripts.OnEnter then owner.scripts.OnEnter(owner) end end
function RC.leave(owner) if owner.scripts.OnLeave then owner.scripts.OnLeave(owner) end end

function RC.install()
  installPaperDoll()
  installEquipmentManager()
  installReputation()
  -- the Classic Era panels are not loaded on camelot
  _G.PetPaperDollFrame_Update, _G.ReputationFrame_Update = nil, nil
end

return RC
