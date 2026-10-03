-- The Forever (camelot) client's Blizzard_PlayerSpells: PlayerSpellsFrame with its SpellBookFrame and
-- TalentsFrame children (parentKey only, no globals), plus EventRegistry, Menu.ModifyMenu and the camelot skills pane
-- (SkillsFrame.SkillDetailFrame), replaying the writes of the extracted 1.60.1 source:
--   blizzard_playerspells/blizzard_playerspellsframe.lua:155–171 (UpdateFrameTitle → SetTitle),
--   blizzard_sharedxml/portraitframe.lua:4–14 (SetTitle → TitleContainer.TitleText),
--   blizzard_pagedcontent/blizzard_pagingcontrols.lua:110–127, blizzard_pagedcontentframe.lua:494–575,
--   spellbook/blizzard_spellbookframe.lua:46, 91, 191–226, 608–614, spellbook/blizzard_spellbookitem.lua:27–109,
--   183–301, blizzard_menu/menu.lua:2700–2735, menutemplates.lua:341–354, mainline/menuvariants.lua:9–22,
--   blizzard_sharedxmlbase/callbackregistry.lua:112–215,
--   camelot/classtalents/blizzard_classtalentsframe.{lua,xml}, tabsystemtemplates.lua:167–207,
--   blizzard_sharedtalentui/blizzard_talentdisplay.lua:100–125,
--   blizzard_uipanels_game/camelot/skillsframe.lua:218–316, camelot/characterframe.lua:832–951.
-- A client write is stored as `fs.text = …` (not counted in fs.calls), so a spec can tell the addon's writes apart.
-- Requires wow_stub (Stub.install + Stub.installTooltipAPI first). Globals are set and read through _G.
local Stub = require("tests.lua.spec.wow_stub")

local PS = {}

local ENGLISH = {
  SPELLBOOK = "Spellbook", TALENTS = "Talents", SPECIALIZATION = "Specialization",
  TALENTS_INSPECT_FORMAT = "Talents - %s", PAGE_NUMBER = "Page %d", PAGE_NUMBER_WITH_MAX = "Page %d/%d",
  SPELL_PASSIVE = "Passive", SPELLBOOK_AVAILABLE_AT = "Level %d", SPELLBOOK_TRAINABLE = "See your trainer",
  BOOSTED_CHAR_SPELL_TEMPLOCK = "Temporarily Locked", SHOW_ALL_SPELL_RANKS = "Show all spell ranks",
  SPELLBOOK_FILTER_PASSIVES = "Hide Passives", SPELLBOOK_USE_FLYOUTS = "Group Similar Spells on Flyouts",
  TALENT_FRAME_APPLY_BUTTON_TEXT = "Apply Changes", TALENT_SPEC_ACTIVATE = "Activate", TALENT_SPEC_ACTIVE = "Active",
  UNSPENT_POINTS = "Unspent Talents", DUAL_SPEC_PRIMARY = "Primary", DUAL_SPEC_SECONDARY = "Secondary",
  TALENT_SPEC_LOCKED = "Locked", SPELLBOOK_SEARCH_INSTRUCTIONS = "Search",
  SPELLBOOK_SEARCH_HEADER_EXACT = "Exact Match", SPELLBOOK_SEARCH_HEADER_NAME = "Name Match",
  SPELLBOOK_SEARCH_HIDE_PASSIVES_DISABLED = "Unavailable while searching",
  TALENT_FRAME_DISCARD_CHANGES_BUTTON_TOOLTIP = "Undo Pending Changes",
  SKILL_DETAIL_SELECT_PROMPT = "Select a skill to view its details.",
  WEAPON_SKILL_DETAIL_SAME_LEVEL_HEADER = "|cFFFFFFFFEqual-Level Enemy|r",
  WEAPON_SKILL_DETAIL_BOSS_HEADER = "|cFFFFFFFFAgainst Raid Bosses|r",
  WEAPON_SKILL_DETAIL_SAME_LEVEL = "Chance to |cFFFFFFFFHit|r, and to avoid being |cFFFFFFFFDodged|r or"
    .. " |cFFFFFFFFParried|r: %s\n\nChance to |cFFFFFFFFCritically Hit|r: %s",
  WEAPON_SKILL_DETAIL_SAME_LEVEL_RANGED = "Chance to |cFFFFFFFFHit|r: %s\n\nChance to |cFFFFFFFFCritically Hit|r: %s",
  WEAPON_SKILL_DETAIL_BOSS = "Chance to |cFFFFFFFFHit|r, and to avoid being |cFFFFFFFFDodged|r or"
    .. " |cFFFFFFFFParried|r: %s\n\nChance to |cFFFFFFFFCritically Hit|r: %s\n\n|cFFFFFFFFGlancing Blows|r occur %s"
    .. " of the time and deal %s less damage",
  WEAPON_SKILL_DETAIL_BOSS_RANGED = "Chance to |cFFFFFFFFHit|r: %s\n\nChance to |cFFFFFFFFCritically Hit|r: %s",
}
local function G(key) return _G[key] or ENGLISH[key] end
PS.G = G

-- CreateAtlasMarkup output (camelot/…/blizzard_classtalentsframe.lua:18–19)
PS.CHECKMARK = "|A:Talents-Checkmark-c60:15:20|a"
PS.LOCK = "|A:Talents-lock-c60:14:10|a"

-- ───────────────────────────── EventRegistry (CallbackRegistryMixin, Function callbacks) ─────────────────────────────
local function installEventRegistry()
  local reg = { callbacks = {} }
  function reg.RegisterCallback(self, event, fn, owner)
    assert(type(event) == "string" and type(fn) == "function")
    self.callbacks[event] = self.callbacks[event] or {}
    self.callbacks[event][owner or fn] = fn
    return owner
  end
  function reg.TriggerEvent(self, event, ...)
    for owner, fn in pairs(self.callbacks[event] or {}) do fn(owner, ...) end
  end
  _G.EventRegistry = reg
end

-- ───────────────────────────────────── Menu (ModifyMenu and a generated menu) ─────────────────────────────────────
-- PS.openMenu(tag, labels): the client generates the root description (one checkbox per label, its initializer
-- closing over the English), runs every ModifyMenu callback for the tag, then initialises pooled buttons in order.
local function installMenu()
  PS.menuMods = {}
  PS.menuButtons = {}
  _G.Menu = { ModifyMenu = function(tag, cb)
    assert(type(tag) == "string")
    PS.menuMods[tag] = PS.menuMods[tag] or {}
    table.insert(PS.menuMods[tag], cb)
  end }
end

function PS.openMenu(tag, labels)
  local root = { elements = {} }
  function root.EnumerateElementDescriptions(self) return ipairs(self.elements) end
  for _, text in ipairs(labels) do
    local desc = { text = text, initializers = {}, resetters = {} }
    function desc.AddInitializer(self, fn) self.initializers[#self.initializers + 1] = fn end
    function desc.AddResetter(self, fn) self.resetters[#self.resetters + 1] = fn end
    desc:AddInitializer(function(button) -- MenuVariants.CreateCheckbox: fontString:SetTextToFit(text)
      button.fontString = button.fontString or Stub.fontString("")
      button.fontString.text = text
    end)
    root.elements[#root.elements + 1] = desc
  end
  for _, cb in ipairs(PS.menuMods[tag] or {}) do cb({}, root, nil) end
  local shown = {}
  for i, desc in ipairs(root.elements) do
    local button = PS.menuButtons[i] or {}
    PS.menuButtons[i] = button
    for _, init in ipairs(desc.initializers) do init(button, desc, {}) end
    button.desc = desc
    shown[i] = button
  end
  PS.openButtons = shown
  return shown
end

-- MenuMixin:DiscardChildFrames (menu.lua:1667–1697): every element frame's resetters, then the compositor detaches
-- and the frame returns to the pool; on reuse the compositor resets the fontString with SetFontObject
-- (compositor.lua:66–74, 388), modelled here as the menu font written straight into the widget.
function PS.closeMenu()
  for _, button in ipairs(PS.openButtons or {}) do
    for _, reset in ipairs(button.desc.resetters) do reset(button) end
    if button.fontString then button.fontString.font = { path = "Fonts\\FRIZQT__.TTF", size = 12, flags = "" } end
  end
  PS.openButtons = {}
end

-- ───────────────────────────────────────── PlayerSpellsFrame ─────────────────────────────────────────
-- PS.spells[slot] = { name, subtext, passive, cached, level (unlearned: "Level %d"), trainable }
-- PS.book = { slot, … } in display order; PS.perPage items per page.
-- SpellBookItemMixin: the XML mixin copies these methods onto each item when the pool creates it
local mixin = {}
local function newItem()
  local item = CreateFrame("Frame")
  item.Name = Stub.fontString("")
  item.SubName = Stub.fontString("")
  item.RequiredLevel = Stub.fontString("")
  for k, v in pairs(_G.SpellBookItemMixin or {}) do item[k] = v end
  return item
end
PS.newItem = newItem
do
  local item = mixin
  function item.HasValidData(self) return self.elementData ~= nil and self.spellBookItemInfo ~= nil end
  function item.UpdateSubName(self, text) -- spellbookitem.lua:295–301
    if text == "" and self.spellBookItemInfo.isPassive then text = G("SPELL_PASSIVE") end
    self.SubName.text = text
  end
  function item.UpdateVisuals(self) -- spellbookitem.lua:183–252 (the text writes)
    local info = self.spellBookItemInfo
    self.Name.text = info.name
    self.SubName.text = ""
    local spell = PS.spells[self.slotIndex]
    if spell.cached then
      self:UpdateSubName(spell.subtext or "")
    else
      PS.pending[self.slotIndex] = function() self:UpdateSubName(spell.subtext or "") end
    end
    local sub = ""
    if spell.level then sub = string.format(G("SPELLBOOK_AVAILABLE_AT"), spell.level)
    elseif spell.trainable then sub = G("SPELLBOOK_TRAINABLE") end
    self.RequiredLevel.text = sub
  end
  function item.UpdateSpellData(self) -- :81–109
    PS.pending[self.slotIndex or -1] = nil -- ClearSpellData cancels the load callback
    local spell = PS.spells[self.elementData.slotIndex]
    self.slotIndex, self.spellBank = self.elementData.slotIndex, self.elementData.spellBank
    -- a flyout entry (Portal, Summon Demon) is typed Flyout (spellbookitem.lua:203)
    self.spellBookItemInfo = { name = spell.name, isPassive = spell.passive,
      itemType = spell.flyout and _G.Enum.SpellBookItemType.Flyout or _G.Enum.SpellBookItemType.Spell }
    self:UpdateVisuals()
  end
  function item.Init(self, elementData) self.elementData = elementData; self:UpdateSpellData() end
end

local function installPlayerSpellsFrame()
  _G.Enum.SpellBookItemType = _G.Enum.SpellBookItemType or { Spell = 1, Flyout = 4 }
  PS.spells, PS.book, PS.pending, PS.perPage = {}, {}, {}, 3
  PS.calls = { UpdateFrameTitle = 0, UpdateControls = 0 }
  local host = CreateFrame("Frame", "PlayerSpellsFrame")
  host.TitleContainer = { TitleText = Stub.fontString("") }
  host.tab, host.inspectUnit = "spellbook", nil
  function host.SetTitle(self, title) self.TitleContainer.TitleText.text = title end
  function host.UpdateFrameTitle(self)
    PS.calls.UpdateFrameTitle = PS.calls.UpdateFrameTitle + 1
    if self.inspectUnit then
      self:SetTitle(G("TALENTS_INSPECT_FORMAT"):format(self.inspectUnit))
    elseif self.linked then -- a linked build (:162), GetSpecName / GetClassName
      self:SetTitle(G("TALENTS_LINK_FORMAT"):format(self.linked[1], self.linked[2]))
    elseif self.tab == "talents" then
      self:SetTitle(G("TALENTS"))
    elseif self.tab == "specialization" then -- the specialization tab's title
      self:SetTitle(G("SPECIALIZATION"))
    else
      self:SetTitle(G("SPELLBOOK"))
    end
  end
  function host.SetTab(self, tab) -- :173–200: the tab's frame shows, then the title
    self.tab = tab
    if tab == "talents" then self.SpellBookFrame:Hide(); self.TalentsFrame:Show()
    else self.TalentsFrame:Hide(); self.SpellBookFrame:Show() end
    self:UpdateFrameTitle()
  end

  local book = CreateFrame("Frame", nil, host)
  host.SpellBookFrame = book
  local paging = { PageText = Stub.fontString(""), currentPage = 1, maxPages = 1, name = "PagingControls" }
  function paging.UpdateControls(self)
    PS.calls.UpdateControls = PS.calls.UpdateControls + 1
    self.PageText.text = string.format(G("PAGE_NUMBER_WITH_MAX"), self.currentPage, self.maxPages)
  end
  book.PagedSpellsFrame = { PagingControls = paging, frames = {} }
  function book.PagedSpellsFrame.EnumerateFrames(self) return ipairs(self.frames) end
  -- SearchBoxTemplate_OnLoad wrote the placeholder (inputboxtemplates.lua:175–178)
  book.SearchBox = CreateFrame("EditBox", nil, book)
  book.SearchBox.Instructions = Stub.fontString(G("SPELLBOOK_SEARCH_INSTRUCTIONS"))
  book.pool, book.headerPool = {}, {}
  function book.ForEachDisplayedSpell(self, fn)
    for _, frame in ipairs(self.PagedSpellsFrame.frames) do
      if frame.HasValidData and frame:HasValidData() then fn(frame) end
    end
  end
  -- DisplayViewsForCurrentPage (pagedcontentframe.lua:494–575): release all, acquire (the pool hands frames back in
  -- reverse), Init each, then OnUpdate → OnPagedSpellsUpdate → the EventRegistry event (spellbookframe.lua:91)
  function book.DisplayPage(self, page)
    paging.currentPage = page
    paging.maxPages = math.max(1, math.ceil(#PS.book / PS.perPage))
    local free, freeHeaders = {}, {}
    for i = #self.pool, 1, -1 do free[#free + 1] = self.pool[i] end
    for i = #self.headerPool, 1, -1 do freeHeaders[#freeHeaders + 1] = self.headerPool[i] end
    self.PagedSpellsFrame.frames = {}
    for i = 1, PS.perPage do
      local slot = PS.book[(page - 1) * PS.perPage + i]
      if type(slot) == "string" then -- a HEADER element: SpellBookHeaderMixin:Init (spellbooktemplates.lua:3–7)
        local header = table.remove(freeHeaders, 1)
        if not header then
          header = CreateFrame("Frame")
          header.Text = Stub.fontString("")
          self.headerPool[#self.headerPool + 1] = header
        end
        table.insert(self.PagedSpellsFrame.frames, header)
        header.Text.text = slot
      elseif slot then
        local item = table.remove(free, 1)
        if not item then item = newItem(); self.pool[#self.pool + 1] = item end
        table.insert(self.PagedSpellsFrame.frames, item)
        item:Init({ slotIndex = slot, spellBank = 0 })
      end
    end
    paging:UpdateControls()
    _G.EventRegistry:TriggerEvent("PlayerSpellsFrame.SpellBookFrame.DisplayedSpellsChanged")
  end
  -- UpdateAllSpellData (spellbookframe.lua:487–549): each displayed item's data again, no event
  function book.RefreshSpellData(self)
    for _, item in ipairs(self.PagedSpellsFrame.frames) do item:UpdateSpellData() end
  end
  book:SetScript("OnShow", function(self) self:DisplayPage(paging.currentPage) end)

  -- TalentsFrame (camelot/classtalents/blizzard_classtalentsframe.xml:4–36, 102, 111, 342, 382, 388, 438)
  local talents = CreateFrame("Frame", nil, host)
  host.TalentsFrame = talents
  talents.ApplyButton = Stub.button(nil, G("TALENT_FRAME_APPLY_BUTTON_TEXT"))
  talents.ActiveSpec = { ActivateButton = Stub.button(nil, G("TALENT_SPEC_ACTIVATE")),
    ActiveLabel = Stub.fontString(G("TALENT_SPEC_ACTIVE")) }
  talents.ClassCurrencyDisplay = { UnspentLabel = Stub.fontString(G("UNSPENT_POINTS")),
    CurrentAmountContainer = { CurrencyAmount = Stub.fontString("") } }
  talents.UndoButton = CreateFrame("Button")
  talents.UndoButton.tooltipText = G("TALENT_FRAME_DISCARD_CHANGES_BUTTON_TOOLTIP")
  talents.UndoButton:SetScript("OnEnter", function(self) -- UIButtonMixin:OnEnter (uibuttontemplate.lua:20–45)
    _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    _G.GameTooltip:ClearLines()
    _G.GameTooltip:AddLine(self.tooltipText)
    _G.GameTooltip:Show()
  end)
  talents.TabSystem = { tabs = {} }
  function talents.TabSystem.GetTabButton(self, id) return self.tabs[id] end
  local function newTab(id, text)
    local tab = CreateFrame("Button")
    tab.Text = Stub.fontString(text)
    tab.tabID, tab.tabText, tab.isActive, tab.forceDisabled = id, text, false, false
    function tab.GetTabText(self) -- camelot :39–49
      if self.isActive then return self.tabText .. " " .. PS.CHECKMARK end
      if self.forceDisabled then return self.tabText .. " " .. PS.LOCK end
      return self.tabText
    end
    function tab.UpdateTabText(self) -- tabsystemtemplates.lua:192–196
      local t = self:GetTabText()
      self.Text.text = self.forceDisabled and ("|cff808080" .. t .. "|r") or t
    end
    function tab.SetIsActive(self, v) self.isActive = v; self:UpdateTabText() end
    function tab.SetTabEnabled(self, v, reason)
      self.forceDisabled = not v
      self:UpdateTabText()
      self.errorReason = reason
    end
    tab:SetScript("OnEnter", function(self) -- TabSystemButtonMixin:OnEnter (tabsystemtemplates.lua:126–136)
      if not self.forceDisabled or not self.errorReason then return end
      _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      _G.GameTooltip:ClearLines()
      _G.GameTooltip:AddLine(self.errorReason)
      _G.GameTooltip:Show()
    end)
    talents.TabSystem.tabs[id] = tab
    return tab
  end
  talents.primarySpecTabID, talents.secondarySpecTabID = 1, 2
  newTab(1, G("DUAL_SPEC_PRIMARY")); newTab(2, G("DUAL_SPEC_SECONDARY"))
  -- UpdateTabs (camelot :150–157)
  function talents.UpdateTabs(self)
    self.TabSystem:GetTabButton(2):SetTabEnabled(PS.specGroups > 1, G("TALENT_SPEC_LOCKED"))
    local active = PS.activeGroup == 1 and 1 or 2
    for id = 1, 2 do self.TabSystem:GetTabButton(id):SetIsActive(id == active) end
  end
  PS.specGroups, PS.activeGroup = 1, 1
  talents:UpdateTabs() -- InitializeTabSystem at OnLoad (:124–134), before any addon runs
end

-- What UIParentLoadAddOn("Blizzard_PlayerSpells") creates. The spec then forwards ADDON_LOADED the way Main does.
function PS.loadPlayerSpells()
  _G.SpellBookItemMixin = {} -- a fresh copy per load: a hook on it never leaks into the next test
  for k, v in pairs(mixin) do _G.SpellBookItemMixin[k] = v end
  installPlayerSpellsFrame()
  Stub.loadedAddons["Blizzard_PlayerSpells"] = true
  return _G.PlayerSpellsFrame
end

function PS.openSpellBook()
  local host = _G.PlayerSpellsFrame
  host:Show()
  host:SetTab("spellbook")
end

function PS.openTalents()
  local host = _G.PlayerSpellsFrame
  host:Show()
  host:SetTab("talents")
end

-- MenuUtil.ShowTooltipEx (menuutil.lua:98–106): the entry's tooltip on GameTooltip with the menu button as owner
function PS.hoverMenuButton(button, lines)
  local tt = _G.GameTooltip
  tt:SetOwner(button, "ANCHOR_RIGHT")
  tt:ClearLines()
  for _, l in ipairs(lines) do tt:AddLine(l) end
  tt:Show()
end

function PS.loadSpell(slot)
  PS.spells[slot].cached = true
  local fn = PS.pending[slot]
  PS.pending[slot] = nil
  if fn then fn() end
end

-- TalentDisplayMixin:SetTooltipInternal (talentdisplay.lua:100–125): owner, title (the talent's name), the lines,
-- Show, then the EventRegistry event with (display, tooltip).
function PS.hoverTalent(display, lines)
  local tt = _G.GameTooltip
  tt:SetOwner(display, "ANCHOR_RIGHT")
  tt:writeLines(lines)
  tt:Show()
  _G.EventRegistry:TriggerEvent("TalentDisplay.TooltipCreated", display, tt)
end

-- ───────────────────────────────────── Skills (camelot SkillsFrame) ─────────────────────────────────────
-- PS.skill = nil (no selection → SetEmpty) | { name, description, weapon = { ranged = bool, values = { … } } }
local function newRow(template)
  local row = CreateFrame("Frame")
  row.template = template
  row.Label = Stub.fontString("")
  row.Label.width = 200
  function row.Label.GetStringHeight(fs) return fs:GetHeight() end
  row.height = template == "category" and 20 or 1
  function row.GetHeight(self) return self.height end
  function row.SetHeight(self, h) self.height = h end
  return row
end

local function installSkills()
  PS.skill = nil
  PS.layouts = 0
  local frame = CreateFrame("Frame", "SkillsFrame")
  local detail = CreateFrame("Frame", nil, frame)
  frame.SkillDetailFrame = detail
  detail.EmptyText = Stub.fontString("")
  detail.Title, detail.Description = Stub.fontString(""), Stub.fontString("")
  detail.Content = { Layout = function() PS.layouts = PS.layouts + 1 end }
  local pools = { free = { category = {}, wrapped = {} }, active = {} }
  function pools.EnumerateActive(self)
    local i = 0
    return function() i = i + 1; return self.active[i] end
  end
  function pools.ReleaseAll(self)
    for _, row in ipairs(self.active) do table.insert(self.free[row.template], row); row:Hide() end
    self.active = {}
  end
  function pools.Acquire(self, template)
    local row = table.remove(self.free[template]) or newRow(template)
    self.active[#self.active + 1] = row
    row:Show()
    return row
  end
  detail.rowPools = pools
  PS.rowPools = pools
  function detail.LayoutRows(self) self.Content:Layout() end -- characterframe.lua:939–941
  function detail.SetEmpty(self, text) -- :942–951
    self.rowPools:ReleaseAll()
    self:LayoutRows()
    self.Title.text = ""
    self.EmptyText.text = text or ""
    self.EmptyText:Show()
  end
  function detail.AddCategory(self, text) self.rowPools:Acquire("category").Label.text = text end
  function detail.AddWrappedRow(self, text)
    local row = self.rowPools:Acquire("wrapped")
    row.Label.text = text
    row:SetHeight(math.max(1, row.Label:GetStringHeight()))
  end
  -- SkillDetailFrameMixin:Refresh (skillsframe.lua:255–316), registered by reference: only SetEmpty / LayoutRows are
  -- reached by method lookup
  function detail.Refresh(self)
    local s = PS.skill
    if not s then self:SetEmpty(G("SKILL_DETAIL_SELECT_PROMPT")); return end
    self.EmptyText:Hide()
    self.Title.text = s.name
    self.Description.text = s.description or ""
    self.rowPools:ReleaseAll()
    if s.weapon then
      local v = s.weapon.values
      self:AddCategory(G("WEAPON_SKILL_DETAIL_SAME_LEVEL_HEADER"))
      local fmt = s.weapon.ranged and G("WEAPON_SKILL_DETAIL_SAME_LEVEL_RANGED") or G("WEAPON_SKILL_DETAIL_SAME_LEVEL")
      self:AddWrappedRow(fmt:format(v[1], v[2]))
      self:AddCategory(G("WEAPON_SKILL_DETAIL_BOSS_HEADER"))
      if s.weapon.ranged then
        self:AddWrappedRow(G("WEAPON_SKILL_DETAIL_BOSS_RANGED"):format(v[3], v[4]))
      else
        self:AddWrappedRow(G("WEAPON_SKILL_DETAIL_BOSS"):format(v[3], v[4], v[5], v[6]))
      end
    end
    self:LayoutRows()
  end
  frame:SetScript("OnShow", function() detail:Refresh() end)
end

function PS.selectSkill(skill)
  PS.skill = skill
  _G.SkillsFrame.SkillDetailFrame:Refresh() -- the EventRegistry path, not a method hook
end

function PS.install()
  _G.SpellBookItemMixin = nil
  installEventRegistry()
  installMenu()
  installSkills()
  _G.PlayerSpellsFrame = nil
end

return PS
