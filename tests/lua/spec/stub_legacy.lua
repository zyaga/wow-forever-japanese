-- A camelot-shaped Legacy window, replayed from blizzard_legacysystem: LegacySystemFrame
-- (blizzard_legacysystem.xml:4–47, PortraitFrameTemplate), its three pages and their writers
-- (blizzard_legacyrewardtrack.lua:27–36, blizzard_legacychallenges.lua:31–37, 250–258, blizzard_legacytree.lua:
-- 24–26, 68–81, 210–223, 299–318), the challenge cards (blizzard_legacysystemtemplates.xml:157–283) and the tree's
-- spell search (blizzard_spellsearch/blizzard_spellsearchtemplates.lua:94–183; blizzard_sharedtalentui/
-- blizzard_sharedtalentbuttontemplates.lua:10–37). A client write is stored as `fs.text = …`.
local Stub = require("tests.lua.spec.wow_stub")

local L = {}
L.ADDON = "Blizzard_LegacySystem"

local function G(key) return _G[key] end
local function fs(text) return Stub.fontString(text or "") end

local function frame(name, label)
  local f = CreateFrame("Frame", name)
  f.name = label or name
  return f
end

-- CreateFramePool-like pool.
function L.pool(create)
  local p = { active = {}, inactive = {} }
  function p.Acquire(self)
    local f = table.remove(self.inactive) or create()
    self.active[#self.active + 1] = f
    return f
  end
  function p.ReleaseAll(self)
    for _, f in ipairs(self.active) do self.inactive[#self.inactive + 1] = f end
    self.active = {}
  end
  function p.EnumerateActive(self)
    local i = 0
    return function()
      i = i + 1
      if self.active[i] then return self.active[i], true end
    end
  end
  return p
end

-- SpellSearchPreviewContainerTemplate: SetPreviewResults writes the overflow line and calls self:UpdateResultsDisplay,
-- which fills the pooled suggested-result buttons when there are no results.
function L.previewContainer(maximumEntries)
  local c = frame(nil, "SearchPreviewContainer")
  c.maximumEntries = maximumEntries or 2
  c.OverflowCount = { Text = fs() }
  c.suggestedResultInfos = {}
  c.rows = {}
  c.suggestedResultButtonsPool = L.pool(function()
    local b = CreateFrame("Button")
    b.Text = fs()
    return b
  end)
  function c.AddSuggestedResult(self, text)
    self.suggestedResultInfos[#self.suggestedResultInfos + 1] = { text = text }
  end
  function c.SetPreviewResults(self, results)
    self.rows = {}
    self.OverflowCount.Text.text = ""
    for i, info in ipairs(results or {}) do
      if i <= self.maximumEntries then self.rows[i] = { Name = fs(info.name) } end
    end
    local overflow = #(results or {}) - self.maximumEntries
    if overflow > 0 then
      self.OverflowCount.Text.text = string.format(G("TALENT_FRAME_SEARCH_PREVIEW_OVERFLOW_FORMAT"), overflow)
    end
    self:UpdateResultsDisplay()
  end
  function c.UpdateResultsDisplay(self)
    self.suggestedResultButtonsPool:ReleaseAll()
    if #self.rows > 0 then return end
    for _, info in ipairs(self.suggestedResultInfos) do
      self.suggestedResultButtonsPool:Acquire().Text.text = info.text
    end
  end
  return c
end

-- A talent tree (TalentFrameBaseMixin): pooled buttons with a SearchIcon, and the "TalentButtonAcquired" event.
function L.talentTree(f)
  f.buttons, f.callbacks = {}, {}
  function f.RegisterCallback(self, event, fn, owner) self.callbacks[#self.callbacks + 1] = { event, fn, owner } end
  function f.EnumerateAllTalentButtons(self)
    local i = 0
    return function()
      i = i + 1
      return self.buttons[i]
    end
  end
  function f.acquireButton(self) -- test-only: AcquireTalentButton → TriggerEvent(TalentButtonAcquired, button)
    local b = CreateFrame("Button")
    b.SearchIcon = CreateFrame("Frame")
    b.SearchIcon.Mouseover = CreateFrame("Frame")
    function b.SearchIcon.SetMatchType(icon, key) icon.tooltipText = key and G(key) or nil end
    function b.SearchIcon.OnEnter(icon) -- sharedtalentbuttontemplates.lua:28–37
      if not icon.tooltipText then return end
      _G.GameTooltip:SetOwner(icon.Mouseover)
      _G.GameTooltip:ClearLines() -- SetOwner clears the tooltip
      _G.GameTooltip:AddLine(icon.tooltipText)
      _G.GameTooltip:Show()
    end
    self.buttons[#self.buttons + 1] = b
    for _, c in ipairs(self.callbacks) do
      if c[1] == "TalentButtonAcquired" then c[2](c[3], b) end
    end
    return b
  end
  f.SearchBox = CreateFrame("EditBox")
  f.SearchBox.Instructions = fs(G("SEARCH"))
  f.SearchPreviewContainer = L.previewContainer()
  return f
end

local function sideTab(key)
  local tab = frame(nil, key)
  tab.tooltipText = G(key)
  function tab.OnEnter(self) -- SidePanelTabButtonMixin:OnEnter
    _G.GameTooltip:SetOwner(self)
    _G.GameTooltip:SetText(self.tooltipText)
  end
  return tab
end

-- `state`: { points, max, available, cap }, what Legacy.UpdateCurrencyInfo would carry.
function L.load(state)
  local f = frame("LegacySystemFrame")
  f.TitleContainer = frame(nil, "TitleContainer")
  f.TitleContainer.TitleText = fs()
  function f.SetTitle(self, text) self.TitleContainer.TitleText.text = text end
  f.LegacyRewardTrackTab = sideTab("LEGACY_REWARD_TRACK_TAB_TOOLTIP")
  f.LegacyChallengeTab = sideTab("LEGACY_CHALLENGE_TAB_TOOLTIP")
  f.LegacyTreeTab = sideTab("LEGACY_TREE_TAB_TOOLTIP")

  -- reward track page
  local track = frame(nil, "RewardTrackPage")
  f.RewardTrackPage = track
  track.Points = fs(tostring(state.points))
  track.PointsLabel = fs(G("LEGACY_REWARD_TRACK_POINTS"))
  track:SetScript("OnShow", function() f:SetTitle(G("LEGACY_TRACK_FRAME_TITLE")) end)

  -- challenges page
  local page = frame(nil, "ChallengesPage")
  f.ChallengesPage = page
  page:SetScript("OnShow", function() f:SetTitle(G("LEGACY_CHALLENGE_FRAME_TITLE")) end)
  local list = frame(nil, "CategoryList")
  page.CategoryList = list
  list.NoResultsText = fs(G("LEGACY_NO_CHALLENGES"))
  list.SearchBox = CreateFrame("EditBox")
  list.SearchBox.Instructions = fs(G("SEARCH"))
  list.FilterDropdown = frame(nil, "FilterDropdown")
  list.FilterDropdown.Text = fs(G("FILTER"))
  function list.FilterDropdown.UpdateText(self) self.Text.text = G("FILTER") end
  page.DetailPane = frame(nil, "DetailPane")
  page.DetailPane.ScrollBox = Stub.scrollBox()
  L.cards = {}
  function L.card(i, data) -- LegacyChallengeTemplate through the ScrollBox's element initializer
    local card = L.cards[i]
    if not card then
      card = CreateFrame("Button")
      card.Label, card.Description = fs(), fs()
      card.Tracked = CreateFrame("CheckButton")
      card.Tracked.Text = fs(G("TRACK_ACHIEVEMENT"))
      L.cards[i] = card
    end
    page.DetailPane.ScrollBox:initFrame(card, data, function(c, d)
      c.Label.text, c.Description.text = d.name, d.description
    end)
    return card
  end
  local summary = frame(nil, "LegacyChallengePointSummary")
  page.LegacyChallengePointSummary = summary
  summary.Shield = { Points = fs(tostring(state.points)) }
  summary.PointsBar = frame(nil, "PointsBar")
  summary.PointsBar.Text = fs()
  function summary.PointsBar.Update(self, info)
    self.Text.text = string.format(G("LEGACY_POINTS_CURR_MAX"), info.points, info.max)
  end
  summary.PointsBar:Update(state)

  -- tree page
  local tree = frame(nil, "TreePage")
  f.TreePage = tree
  tree:SetScript("OnShow", function() f:SetTitle(G("LEGACY_TREE_FRAME_TITLE")) end)
  local panel = L.talentTree(frame(nil, "LegacyTreeTraitPanel"))
  tree.LegacyTreeTraitPanel = panel
  panel.SelectedTreeIcon = { SelectedTreeLabel = fs() }
  panel.SpentPointsFrame = { Text = fs("2") }
  panel.ApplyButton = Stub.button(nil, G("TALENT_FRAME_APPLY_BUTTON_TEXT"))
  panel.UndoButton = frame(nil, "UndoButton")
  function panel.UndoButton.OnEnter(self) -- UIButtonMixin:OnEnter
    _G.GameTooltip:SetOwner(self)
    _G.GameTooltip:SetText(G("TALENT_FRAME_DISCARD_CHANGES_BUTTON_TOOLTIP"))
  end
  L.TREES = { "LEGACY_TREE_PROFESSIONS", "LEGACY_TREE_ADVENTURE", "LEGACY_TREE_PROGRESSION" }
  function panel.SelectTree(self, index) self.SelectedTreeIcon.SelectedTreeLabel.text = G(L.TREES[index]) end
  local selection = frame(nil, "LegacyTreeSelectionPanel")
  tree.LegacyTreeSelectionPanel = selection
  function selection.RefreshTreeButtons(self)
    self.treeButtons = {}
    for i, key in ipairs(L.TREES) do
      local b = CreateFrame("CheckButton")
      b.line = G(key)
      function b.ShowTooltip(button) -- RingedFrameWithTooltipMixin:ShowTooltip
        _G.GameTooltip:SetOwner(button)
        _G.GameTooltip:ClearLines() -- SetOwner clears the tooltip
        _G.GameTooltip:AddLine(button.line)
        _G.GameTooltip:Show()
      end
      self.treeButtons[i] = b
    end
  end
  selection:RefreshTreeButtons()
  local points = frame(nil, "LegacyTreePointSummary")
  tree.LegacyTreePointSummary = points
  points.AvailablePointsLabel = fs()
  points.Shield = { Points = fs(tostring(state.points)) }
  function points.RefreshText(self, info)
    self.AvailablePointsLabel.text = string.format(G("LEGACY_POINTS_AVAILABLE"),
      string.format(G("LEGACY_POINTS_AMOUNT"), info.available))
    self.tooltipText = string.format(G("LEGACY_POINTS_SEASONAL_CAP"), info.cap)
  end
  function points.OnEnter(self)
    _G.GameTooltip:SetOwner(self)
    _G.GameTooltip:SetText(self.tooltipText)
  end
  points:RefreshText(state)
  panel:SelectTree(1)

  track:Show() -- LegacySystemFrameMixin:OnLoad → SelectPage(1)
  Stub.loadedAddons[L.ADDON] = true
  return f
end

function L.unload()
  _G.LegacySystemFrame = nil
  L.cards = nil
end

return L
