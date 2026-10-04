-- UI/SpellSearch.lua: the spell / talent search that Forever's spellbook, talent tree and Legacy tree share
-- (surface "spellsearch", area "ui", ADR-016). Blizzard_SpellSearch is a login addon of templates
-- (blizzard_spellsearchtemplates.xml: SpellSearchBoxTemplate, SpellSearchPreviewContainerTemplate);
-- Blizzard_SharedTalentUI adds the talent buttons' search icon. Their text reaches the screen inside three hosts,
-- each a parentKey child of a load-on-demand window, so each host is set up through WFJ.LoadOnDemand.when for its
-- addon:
--   Blizzard_PlayerSpells: PlayerSpellsFrame.TalentsFrame (camelot/classtalents/blizzard_classtalentsframe.xml:401,
--     416). The spellbook's own preview (PlayerSpellsFrame.SpellBookFrame, spellbook/blizzard_spellbookframe.xml:
--     103, 119) is left English: nothing of this addon runs inside the spellbook's passes (ADR-058);
--   Blizzard_LegacySystem: LegacySystemFrame.TreePage.LegacyTreeTraitPanel (blizzard_legacytree.xml:220, 241).
-- What is shown, per host:
--   SearchPreviewContainer:SetPreviewResults (blizzard_spellsearch/blizzard_spellsearchtemplates.lua:99–129) writes
--     OverflowCount.Text TALENT_FRAME_SEARCH_PREVIEW_OVERFLOW_FORMAT ("And %s more") and then calls
--     self:UpdateResultsDisplay (:131–183), which writes each pooled suggested-result button's Text from
--     AddSuggestedResult's text: TALENT_FRAME_SEARCH_NOT_ON_ACTIONBAR (blizzard_sharedtalentui/
--     blizzard_classtalentsearch.lua:1, 20–22). Both are the container's own methods called as `self:…()`: post-hooked
--     on the instance; suggested buttons are walked from the pool (suggestedResultButtonsPool, :67), keyed by widget.
--     A preview result row's Name is a spell / talent name (SpellSearchPreviewResultMixin:Init, :12): never matched;
--   the talent tree's SearchBox.Instructions SEARCH (SearchBoxTemplate; the spellbook's own placeholder
--     SPELLBOOK_SEARCH_INSTRUCTIONS is UI/SpellBook's, the Legacy tree's is UI/Legacy's);
--   the talent buttons' search icon tooltip: TalentButtonSearchIconMixin:OnEnter: GameTooltip:SetOwner(
--     self.Mouseover), GameTooltip_AddNormalLine(self.tooltipText), Show (blizzard_sharedtalentui/
--     blizzard_sharedtalentbuttontemplates.lua:28–37); tooltipText is one of TALENT_FRAME_SEARCH_TOOLTIP_*
--     (blizzard_sharedtalentutil.lua:608–637). Talent buttons are pooled, so each button's SearchIcon.Mouseover is
--     registered as a help-tooltip owner when the tree acquires it (the tree's own CallbackRegistry event
--     "TalentButtonAcquired" (blizzard_sharedtalentframe.lua:120–123, 624; Blizzard_LegacySystem listens the same
--     way, blizzard_legacysystem.lua:28–30), and once for the buttons that already exist
--     (TalentFrameBaseMixin:EnumerateAllTalentButtons, :934).
-- Never touched: the search EditBoxes (their text is read back by the search), result names.
local _, WFJ = ...
local SpellSearch = {}
WFJ.SpellSearch = SpellSearch

local SURFACE = "spellsearch"
SpellSearch.SURFACE = SURFACE
local Compat = WFJ.Compat

local TALENTS = "PlayerSpellsFrame.TalentsFrame"
local SPELLBOOK = "PlayerSpellsFrame.SpellBookFrame"
local LEGACY = "LegacySystemFrame.TreePage.LegacyTreeTraitPanel"

SpellSearch.NEVER_TOUCH = { TALENTS .. ".SearchBox", SPELLBOOK .. ".SearchBox", LEGACY .. ".SearchBox" }

-- host key → { addon, frame candidate, is a talent tree (search icons), owns the box's placeholder here }
local HOSTS = {
  talents = { "Blizzard_PlayerSpells", TALENTS, true, true },
  legacy = { "Blizzard_LegacySystem", LEGACY, true, false },
}
local HOST_ORDER = { "legacy", "talents" }

local OVERFLOW = { only = { "TALENT_FRAME_SEARCH_PREVIEW_OVERFLOW_FORMAT" } }
local SUGGESTED = { only = { "TALENT_FRAME_SEARCH_NOT_ON_ACTIONBAR" } }
local INSTRUCTIONS = { only = { "SEARCH" } }
local ICON = { only = { "TALENT_FRAME_SEARCH_TOOLTIP_RELATED_MATCH", "TALENT_FRAME_SEARCH_TOOLTIP_MATCH",
  "TALENT_FRAME_SEARCH_TOOLTIP_EXACT_MATCH", "TALENT_FRAME_SEARCH_TOOLTIP_NOT_ON_ACTIONBAR",
  "TALENT_FRAME_SEARCH_TOOLTIP_ON_INACTIVE_BONUSBAR", "TALENT_FRAME_SEARCH_TOOLTIP_ON_DISABLED_ACTIONBAR" } }

local function declare()
  for key, host in pairs(HOSTS) do Compat.declare(SURFACE, key, { host[2] }) end
end

local function container(hostKey)
  local frame = Compat.get(SURFACE, hostKey)
  local c = type(frame) == "table" and frame.SearchPreviewContainer or nil
  return type(c) == "table" and c or nil
end

-- A stable record key per pooled suggested-result button (records follow the widget, not the index).
local suggestedKey = WFJ.Labels.keyer("suggested.")

-- After SearchPreviewContainer:UpdateResultsDisplay. → the number of dictionary words found.
function SpellSearch.onDisplay(hostKey)
  local c = container(hostKey)
  local pool = c and c.suggestedResultButtonsPool or nil
  if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then return 0 end
  local n = 0
  for button in pool:EnumerateActive() do
    local text = type(button) == "table" and button.Text or nil
    if type(text) == "table" then
      n = n + WFJ.Labels.show(SURFACE, hostKey .. "." .. suggestedKey(text), text, nil, SUGGESTED)
    end
  end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- After SearchPreviewContainer:SetPreviewResults. → 1 | 0 for the overflow line.
function SpellSearch.onResults(hostKey)
  local c = container(hostKey)
  local overflow = c and c.OverflowCount or nil
  return WFJ.Labels.show(SURFACE, hostKey .. ".overflow", type(overflow) == "table" and overflow.Text or nil, nil,
    OVERFLOW)
end

-- One talent button: its search icon's mouse-over frame owns the match tooltip. → true when registered.
function SpellSearch.registerIcon(button)
  local icon = type(button) == "table" and button.SearchIcon or nil
  local owner = type(icon) == "table" and icon.Mouseover or nil
  if type(owner) ~= "table" then return false end
  WFJ.HelpTooltip.register(owner, ICON)
  return true
end

-- The tree's "TalentButtonAcquired" callback: (owner, button).
function SpellSearch.onButtonAcquired(_, button)
  SpellSearch.registerIcon(button)
end

local hooked = {}

-- One host, once its addon is loaded. → true when set up now.
function SpellSearch.setupHost(hostKey)
  declare() -- its frames exist only now: forget what Compat memoized before
  local host = HOSTS[hostKey]
  local frame = Compat.get(SURFACE, hostKey)
  if type(frame) ~= "table" then return false end
  WFJ.Labels.forbidNames(SpellSearch.NEVER_TOUCH)
  if host[4] and type(frame.SearchBox) == "table" then
    WFJ.Labels.show(SURFACE, hostKey .. ".instructions", frame.SearchBox.Instructions, nil, INSTRUCTIONS)
  end
  if hooked[hostKey] then return false end
  hooked[hostKey] = true
  local c = container(hostKey)
  if c and type(c.SetPreviewResults) == "function" then
    hooksecurefunc(c, "SetPreviewResults", function() SpellSearch.onResults(hostKey) end)
  end
  if c and type(c.UpdateResultsDisplay) == "function" then
    hooksecurefunc(c, "UpdateResultsDisplay", function() SpellSearch.onDisplay(hostKey) end)
  end
  if host[3] then
    if type(frame.RegisterCallback) == "function" then
      frame:RegisterCallback("TalentButtonAcquired", SpellSearch.onButtonAcquired, SpellSearch)
    end
    if type(frame.EnumerateAllTalentButtons) == "function" then
      for button in frame:EnumerateAllTalentButtons() do SpellSearch.registerIcon(button) end
    end
  end
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init. → true when at least
-- one host was set up now; false while neither addon is loaded.
function SpellSearch.init()
  declare()
  local done = false
  for _, hostKey in ipairs(HOST_ORDER) do
    WFJ.LoadOnDemand.when(HOSTS[hostKey][1], function()
      if SpellSearch.setupHost(hostKey) then done = true end
    end)
  end
  return done
end
