-- A camelot-shaped Blizzard_CooldownViewer: CooldownViewerSettings, its two alert editors and the four HUD
-- viewers, replaying the client's writers (Forever build 1.60.1.69913; paths relative to Interface/AddOns):
--   blizzard_cooldownviewer/cooldownviewersettings.lua: OnLoad SetTitle :824, RefreshLayout :1513–1529 (release and
--     re-acquire the pooled categories, Init → Header:SetHeaderText :676–680, the category's items :722–745), the empty
--     slot tooltip :219–226;
--   cooldownviewersettingsalerts.lua :1–6, :74–173 and cooldownviewereditalertbase.lua :38–45 (the alert editor);
--   groupbufffilter.lua :178–208, :286–298 (the group-buff editor and the two sections);
--   blizzard_editmode/shared/editmodesystemtemplates.lua :3316–3345 (a viewer's Selection label and tooltip).
-- Client writes go to `fs.text` / the stub tooltip's own writers, never through the addon.
local Stub = require("tests.lua.spec.wow_stub")
local CV = {}

local function en(key) return _G[key] end

-- A frame pool the way CreateFramePool / CreateFramePoolCollection enumerate: objects are reused, never indexed.
local function pool(create)
  local p = { active = {}, inactive = {} }
  function p.Acquire(self)
    local obj = table.remove(self.inactive) or create()
    self.active[#self.active + 1] = obj
    return obj
  end
  function p.ReleaseAll(self)
    for _, o in ipairs(self.active) do self.inactive[#self.inactive + 1] = o end
    self.active = {}
  end
  function p.EnumerateActive(self)
    local i = 0
    return function()
      i = i + 1
      return self.active[i]
    end
  end
  return p
end
CV.pool = pool

-- A Menu-system dropdown button: UpdateText writes the selection text function's result into .Text.
local function dropdown(name)
  local d = { name = name, Text = Stub.fontString("") }
  function d.SetSelectionText(self, fn) self.selectionText = fn; self:UpdateText() end
  function d.UpdateText(self) self.Text.text = self.selectionText and self.selectionText() or "" end
  return d
end

-- A settings item (CooldownViewerSettingsItemTemplate). `info`: { empty, categoryTitle, tracked, dynamic, spell }.
local function settingsItem()
  local item = CreateFrame("Frame")
  item.info = {}
  function item.IsEmptyCategory(self) return self.info.empty == true end
  function item.UsesDynamicAppearance(self) return self.info.dynamic == true end
  function item.GetSpellCategoryTooltipTitle(self) return self.info.categoryTitle end
  function item.GetEquipSlotTooltipTypes(self)
    if self.info.tracked then return true, 13, _G.Enum.CooldownViewerCategory.EquipSlotTracked end
    return false
  end
  item:SetScript("OnEnter", function(self) -- CooldownViewerItemDataMixin:OnEnter → RefreshTooltip
    _G.GameTooltip:SetOwner(self)
    local i = self.info
    if i.empty then
      _G.GameTooltip:SetText(en("COOLDOWN_VIEWER_SETTINGS_EMPTY_SLOT_TOOLTIP"))
    elseif i.categoryTitle then
      _G.GameTooltip:SetText(i.categoryTitle)
      _G.GameTooltip:AddLine(i.categoryDescription)
    elseif i.tracked then
      _G.GameTooltip:SetText(i.itemName)
      _G.GameTooltip:AddLine(i.spell)
      _G.GameTooltip:AddLine(en("COOLDOWN_VIEWER_TRINKET_AURA_TOOLTIP_LABEL"))
    else
      _G.GameTooltip:SetText(i.spell) -- SetSpellByID: the spell's own lines
    end
    _G.GameTooltip:Show()
  end)
  return item
end

local function header()
  local h = Stub.button(nil, "")
  h.Name = Stub.fontString("")
  function h.SetHeaderText(self, text) self.Name.text = text end
  return h
end

local function category()
  local c = CreateFrame("Frame")
  c.Header = header()
  c.itemPool = pool(settingsItem)
  return c
end

-- CV.categories: the list RefreshLayout lays out, { { title = <English>, items = { info, … } }, … }.
local function installSettings()
  local f = CreateFrame("Frame", "CooldownViewerSettings")
  f.TitleContainer = { TitleText = Stub.fontString("") }
  function f.SetTitle(self, text) self.TitleContainer.TitleText.text = text end
  f.SearchBox = CreateFrame("EditBox")
  f.SearchBox.Instructions = Stub.fontString(en("COOLDOWN_VIEWER_SETTINGS_SEARCH_INSTRUCTIONS"))
  for _, tab in ipairs({ { "SpellsTab", "COOLDOWN_VIEWER_SETTINGS_TAB_SPELLS" },
    { "AurasTab", "COOLDOWN_VIEWER_SETTINGS_TAB_BUFFS" },
    { "GroupBuffsTab", "COOLDOWN_VIEWER_SETTINGS_TAB_GROUP_AURAS" } }) do
    local t = CreateFrame("Frame")
    t.tooltipText = en(tab[2])
    f[tab[1]] = t
  end
  f.UndoButton = Stub.button(nil, "Revert |A:common-icon-undo:0:0|a")
  f.LayoutDropdown = dropdown("LayoutDropdown")
  f.categoryPool = pool(category)
  f.GroupBuffFilter = { shownSection = { Header = header() }, hiddenSection = { Header = header() } }
  f.GroupBuffFilter.shownSection.Header:SetHeaderText(en("GROUP_BUFF_FILTER_SECTION_SHOWN"))
  f.GroupBuffFilter.hiddenSection.Header:SetHeaderText(en("GROUP_BUFF_FILTER_SECTION_HIDDEN"))
  function f.RefreshLayout(self)
    if type(self.categoryPool) ~= "table" then return end -- a spec rebinds it to a wrong type: the replay stops here
    self.categoryPool:ReleaseAll()
    for _, spec in ipairs(CV.categories or {}) do
      local c = self.categoryPool:Acquire()
      c.Header:SetHeaderText(spec.title)
      c.itemPool:ReleaseAll()
      for _, info in ipairs(spec.items or {}) do c.itemPool:Acquire().info = info end
    end
  end
  f:SetScript("OnShow", function(self) self:RefreshLayout() end)
  f:SetTitle(en("COOLDOWN_VIEWER_SETTINGS_TITLE")) -- OnLoad
  return f
end

local function alertBase(name)
  local a = CreateFrame("Frame", name)
  a.Title = Stub.fontString(en("COOLDOWN_VIEWER_SETTINGS_ALERT_DIALOG_TITLE"))
  a.Name = Stub.fontString("")
  a.PrimaryLabel = Stub.fontString("")
  a.AddButton = Stub.button(nil, "")
  function a.Display(self, isNewAlert)
    if type(self.AddButton) == "table" then -- a spec rebinds it to a wrong type
      self.AddButton.fontString.text = isNewAlert and en("COOLDOWN_VIEWER_SETTINGS_ALERT_MENU_BUTTON_ADD_ALERT")
        or en("COOLDOWN_VIEWER_SETTINGS_ALERT_MENU_BUTTON_EDIT_EXISTING_ALERT")
    end
    self:Show()
  end
  return a
end

-- CV.alert = { type = "sound" | "visual", event = <English>, payload = <English> }: the working copy's texts.
local function installAlerts()
  local a = alertBase("CooldownViewerSettingsEditAlert")
  a.PrimaryLabel.text = en("COOLDOWN_VIEWER_SETTINGS_ALERT_DIALOG_LABEL_TYPE")
  a.EventLabel = Stub.fontString(en("COOLDOWN_VIEWER_SETTINGS_ALERT_DIALOG_LABEL_EVENT"))
  a.PayloadLabel = Stub.fontString(en("COOLDOWN_VIEWER_SETTINGS_ALERT_DIALOG_LABEL_SOUND_TYPE"))
  a.TypeDropdown, a.EventDropdown, a.PayloadDropdown = dropdown("Type"), dropdown("Event"), dropdown("Payload")
  function a.SetupDropdowns(self)
    local visual = CV.alert.type == "visual"
    -- a spec rebinds some of these to a wrong type: the replay writes only the dropdowns that are still frames
    local function select(dd, fn)
      if type(dd) == "table" and type(dd.SetSelectionText) == "function" then dd:SetSelectionText(fn) end
    end
    select(self.TypeDropdown, function()
      return en(visual and "COOLDOWN_VIEWER_SETTINGS_ALERT_TYPE_VISUAL" or "COOLDOWN_VIEWER_SETTINGS_ALERT_TYPE_SOUND")
    end)
    select(self.EventDropdown, function() return CV.alert.event end)
    select(self.PayloadDropdown, function() return CV.alert.payload end)
    self.PayloadLabel.text = en(visual and "COOLDOWN_VIEWER_SETTINGS_ALERT_DIALOG_LABEL_VISUAL_TYPE"
      or "COOLDOWN_VIEWER_SETTINGS_ALERT_DIALOG_LABEL_SOUND_TYPE")
  end
  function a.DisplayForAlert(self, spellName, isNewAlert)
    self.Name.text = spellName
    self:SetupDropdowns()
    self:Display(isNewAlert)
  end

  local g = alertBase("GroupBuffFilterEditVisualAlert")
  g.PrimaryLabel.text = en("GROUP_BUFF_FILTER_VISUAL_ALERT_DIALOG_LABEL_VISUAL_TYPE")
  g.VisualDropdown = dropdown("Visual")
  function g.SetupDropdown(self) self.VisualDropdown:SetSelectionText(function() return CV.groupVisual end) end
  function g.DisplayForGroupBuffItem(self, buffName, isNewAlert)
    self.Name.text = buffName
    self:SetupDropdown()
    self:Display(isNewAlert)
  end
end

CV.VIEWERS = { EssentialCooldownViewer = "HUD_EDIT_MODE_SYSTEM_ESSENTIAL_COOLDOWNS",
  UtilityCooldownViewer = "HUD_EDIT_MODE_SYSTEM_UTILITY_COOLDOWNS",
  BuffIconCooldownViewer = "HUD_EDIT_MODE_SYSTEM_TRACKED_BUFFS",
  BuffBarCooldownViewer = "HUD_EDIT_MODE_SYSTEM_TRACKED_BUFF_BARS" }

local function installViewers()
  for name, key in pairs(CV.VIEWERS) do
    local viewer = CreateFrame("Frame", name)
    viewer.systemNameString = en(key)
    local selection = CreateFrame("Frame")
    selection.Label = Stub.fontString("")
    selection.isSelected = false
    function selection.UpdateLabelVisibility(self)
      if type(self.Label) ~= "table" then return end -- a spec rebinds it to a wrong type
      self.Label.text = self.isSelected and viewer.systemNameString or "Click to Edit"
    end
    function selection.CheckShowInstructionalTooltip(self)
      _G.GameTooltip:SetOwner(self)
      _G.GameTooltip:SetText(viewer.systemNameString)
      _G.GameTooltip:Show()
    end
    viewer.Selection = selection
  end
end

function CV.install()
  _G.Enum = _G.Enum or {}
  _G.Enum.CooldownViewerCategory = { EquipSlotTracked = 6 }
  CV.categories, CV.alert, CV.groupVisual = {}, { type = "sound", event = "", payload = "" }, ""
  installSettings()
  installAlerts()
  installViewers()
end

function CV.uninstall()
  for _, name in ipairs({ "CooldownViewerSettings", "CooldownViewerSettingsEditAlert", "GroupBuffFilterEditVisualAlert",
    "issecretvalue" }) do
    _G[name] = nil
  end
  for name in pairs(CV.VIEWERS) do _G[name] = nil end
  if _G.Enum then _G.Enum.CooldownViewerCategory = nil end
end

return CV
