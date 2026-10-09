-- UI/Legacy.lua: the Legacy window on Forever (surface "legacy", area "ui", ADR-016). A Forever-only system:
-- Blizzard_LegacySystem is load-on-demand (blizzard_legacysystem.toc) and opens from the Legacy micro button
-- (LegacyMicroButtonMixin:OnClick → ToggleLegacySystemUI, blizzard_micromenu/mainline/mainmenubarmicrobuttons.lua:
-- 1043–1046; camelot places the button, camelot/micromenucontaineroverrides.lua:8) and from the TOGGLELEGACYSYSTEM
-- binding (blizzard_framexml/bindings_camelot.xml:1218). ToggleLegacySystemUI loads the addon on first use
-- (blizzard_legacysystem_bootstrap.lua:7–16), so everything here waits through WFJ.LoadOnDemand.when.
-- LegacySystemFrame (blizzard_legacysystem.xml:4, PortraitFrameTemplate) has three pages, each a parentKey child:
--   RewardTrackPage, ChallengesPage, TreePage (xml:40–42). Every widget is parentKey-only (dotted Compat names).
-- Title: each page's OnShow calls LegacySystemFrame:SetTitle: LEGACY_TRACK_FRAME_TITLE (blizzard_legacyrewardtrack
--   .lua:24), LEGACY_CHALLENGE_FRAME_TITLE (blizzard_legacychallenges.lua:42), LEGACY_TREE_FRAME_TITLE
--   (blizzard_legacytree.lua:25), through Labels.title, restricted to those three keys.
-- Static labels (XML text=, never rewritten; each restricted to its own key):
--   RewardTrackPage.PointsLabel LEGACY_REWARD_TRACK_POINTS (blizzard_legacyrewardtrack.xml:99);
--   ChallengesPage.CategoryList.NoResultsText LEGACY_NO_CHALLENGES (blizzard_legacychallengecategorylist.xml:8);
--   ChallengesPage.CategoryList.SearchBox.Instructions and TreePage.LegacyTreeTraitPanel.SearchBox.Instructions SEARCH
--     (SearchBoxTemplate; the EditBoxes themselves are never touched);
--   ChallengesPage.CategoryList.FilterDropdown's own text FILTER (WowStyle1FilterDropdownTemplate,
--     blizzard_menu/mainline/menutemplates.xml:69; its popup entries are UI/Menus');
--   TreePage.LegacyTreeTraitPanel.ApplyButton TALENT_FRAME_APPLY_BUTTON_TEXT (blizzard_legacytree.xml:132).
-- Writers, each the frame's own method called as `self:…()` (mixins are copied onto the frame at load), post-hooked
-- on the instance:
--   LegacyTreeTraitPanel:SelectTree → SelectedTreeIcon.SelectedTreeLabel, the tree's label LEGACY_TREE_PROFESSIONS /
--     _ADVENTURE / _PROGRESSION (blizzard_legacytree.lua:68–81; LegacyTreeData, blizzard_legacysystemconstants.lua:
--     1–17). The three are GlobalStrings category words, not game-data names;
--   LegacyTreePointSummary:RefreshText → AvailablePointsLabel LEGACY_POINTS_AVAILABLE (blizzard_legacytree.lua:
--     310–318; the number is LEGACY_POINTS_AMOUNT "%d");
--   ChallengesPage.LegacyChallengePointSummary.PointsBar:Update → Text LEGACY_POINTS_CURR_MAX
--     (blizzard_legacychallenges.lua:309–316);
--   the challenge cards (ChallengesPage.DetailPane.ScrollBox, pooled LegacyChallengeTemplate): Tracked.Text
--     TRACK_ACHIEVEMENT (blizzard_legacysystemtemplates.xml:75, 279), walked from the ScrollBox's initialized-frame
--     callback, keyed by widget. ADR-042: a card is an achievement row (LegacyChallengeTemplate inherits
--     AchievementTemplateMixin:Init, blizzard_legacychallengebutton.lua:202; blizzard_achievementui.lua:1352, 1373):
--     its Label and Description are the Achievement table's text, restricted to the achievement families
--     (UI/Achievement.TEXT_FIELDS, textOnly); its Shield owns the reward tooltip, one line added by
--     AchievementShield_OnEnter (blizzard_legacyachievementoverrides.lua:39–48): the AchievementReward family only.
--     Its text criteria are the CriteriaText family (CriteriaTree.Description_lang, GetAchievementCriteriaInfo):
--     AchievementTemplateMixin:DisplayObjectives hands the one shared LegacyChallengeObjectives frame to the card
--     (blizzard_legacychallengebutton.lua:256-279), whose Display acquires a pooled criterion per row and calls
--     LegacyChallengeCriteriaMixin:Init → Name:SetText(text) (:102-111, :158-175). Display is post-hooked on that
--     frame and walks criteriaPool:EnumerateActive(), each Name restricted to the CriteriaText family. A counted
--     criterion shows a progress bar and its count instead (showingProgress, Name hidden): left as written. A
--     criterion with no shipped row (a name) has no key and stays as the client wrote it.
--   the reward track (RewardTrackPage.LegacyRewardProgressFrame, RewardProgressFrameTemplate, pooled
--     LegacyRewardCardTemplate cards with RenownLevelMixin, blizzard_legacyrewardtrack.xml:4, 59, 119-124):
--     LegacyRewardTrackPageMixin:SetupRewardTrack fills each level's rewardInfo from
--     C_MajorFactions.GetRenownRewardsForLevel and calls progressFrame:Init (blizzard_legacyrewardtrack.lua:35-49);
--     RewardTrackFrameMixin:Init acquires the cards into self.Elements (blizzard_framexml/rewardtracktemplates.lua:
--     38-63), post-hooked on the instance. Each card's SetRewardName (:493-495, called from TryInit :367-386 after
--     SetInfo resets it) is post-hooked on the card: RewardName restricted to the RenownRewardName family. A name
--     that is no reward row's text (an item's, a mount's or a spell's own name, blizzard_framexmlutil/
--     renownrewardutil.lua:3-70) has no key and stays English. Each card owns its tooltip
--     (RenownLevelMixin:RefreshTooltip, :517-549): a single reward's name as title and its description, else the
--     milestone title and "- %s" name lines, or the capstone lines: the RenownRewardName and
--     RenownRewardDescription families and the four fixed renown keys only, so a "- %s" line (a name inside) is
--     never matched.
--   the category list (LIST.ScrollBox, pooled LegacyChallengeCategory rows): LegacyChallengeCategoryMixin:Init
--     writes the category name with SetHeaderText → GetTitleRegion():SetText (blizzard_legacychallengecategorylist
--     .lua:184–188; blizzard_sharedxml/listtemplates.lua:58–61), the AchievementCategory family only.
-- Tooltips (GameTooltip with the widget as owner, then Show: help-tooltip owners restricted to their keys):
--   the three side tabs' tooltipText LEGACY_REWARD_TRACK_TAB_TOOLTIP / LEGACY_CHALLENGE_TAB_TOOLTIP /
--     LEGACY_TREE_TAB_TOOLTIP (blizzard_legacysystem.xml:9, 18, 27; SidePanelTabButtonMixin:OnEnter,
--     blizzard_sharedxml/mainline/shareduipaneltemplates.lua:406–416);
--   the tree selection buttons' one line, the tree label (LegacyTreeButtonMixin:SetupLegacyTreeButton,
--     blizzard_legacytree.lua:246–252; RingedFrameWithTooltipMixin:ShowTooltip, blizzard_sharedxml/shared/
--     frametemplate/ringedframetemplate.lua:50–71), registered after each RefreshTreeButtons (pooled, :210–223);
--   LegacyTreePointSummary's LEGACY_POINTS_SEASONAL_CAP (blizzard_legacytree.lua:299–304, 315);
--   UndoButton's TALENT_FRAME_DISCARD_CHANGES_BUTTON_TOOLTIP (blizzard_legacytree.xml:212; UIButtonMixin:OnEnter).
-- Not here: the tree's search preview and search icons (UI/SpellSearch.lua); talent node tooltips
--   ("TalentDisplay.TooltipCreated", UI/Talents.lua); the filter menu's entries (UI/Menus); the gamepad footers
--   (GamepadSharedUtility prompts); the paragon reward's tooltip (paragon info, not a renown reward row).
-- Never touched: the two search EditBoxes, the point counters, the reward cards' level numbers.
local _, WFJ = ...
local Legacy = {}
WFJ.Legacy = Legacy

local SURFACE = "legacy"
Legacy.SURFACE = SURFACE
local Compat = WFJ.Compat
local ADDON = "Blizzard_LegacySystem"

local FRAME = "LegacySystemFrame"
local LIST = FRAME .. ".ChallengesPage.CategoryList"
local PANEL = FRAME .. ".TreePage.LegacyTreeTraitPanel"
local SUMMARY = FRAME .. ".TreePage.LegacyTreePointSummary"

Legacy.NEVER_TOUCH = { LIST .. ".SearchBox", PANEL .. ".SearchBox", FRAME .. ".RewardTrackPage.Points",
  SUMMARY .. ".Shield.Points", FRAME .. ".ChallengesPage.LegacyChallengePointSummary.Shield.Points",
  PANEL .. ".SpentPointsFrame.Text" }

local TITLE = { only = { "LEGACY_TRACK_FRAME_TITLE", "LEGACY_CHALLENGE_FRAME_TITLE", "LEGACY_TREE_FRAME_TITLE" } }
local TREE_KEYS = { "LEGACY_TREE_PROFESSIONS", "LEGACY_TREE_ADVENTURE", "LEGACY_TREE_PROGRESSION" }
local TREE = { only = TREE_KEYS }
local AVAILABLE = { only = { "LEGACY_POINTS_AVAILABLE" } }
local POINTS_BAR = { only = { "LEGACY_POINTS_CURR_MAX" } }
local TRACKED = { only = { "TRACK_ACHIEVEMENT" } }
-- the fixed lines of a reward card's tooltip besides a reward's own name and description
local RENOWN_TOOLTIP_KEYS = { "RENOWN_REWARD_CAPSTONE_TOOLTIP_TITLE", "RENOWN_REWARD_CAPSTONE_TOOLTIP_DESC",
  "RENOWN_REWARD_CAPSTONE_TOOLTIP_DESC2", "RENOWN_REWARD_MILESTONE_TOOLTIP_TITLE" }

-- Static labels: record key → { candidate, the one key it shows }.
local STATIC_LABELS = {
  pointsLabel = { FRAME .. ".RewardTrackPage.PointsLabel", "LEGACY_REWARD_TRACK_POINTS" },
  noResults = { LIST .. ".NoResultsText", "LEGACY_NO_CHALLENGES" },
  challengeSearch = { LIST .. ".SearchBox.Instructions", "SEARCH" },
  treeSearch = { PANEL .. ".SearchBox.Instructions", "SEARCH" },
  apply = { PANEL .. ".ApplyButton", "TALENT_FRAME_APPLY_BUTTON_TEXT" },
}
local STATIC_ORDER = {}
for key in pairs(STATIC_LABELS) do STATIC_ORDER[#STATIC_ORDER + 1] = key end
table.sort(STATIC_ORDER)

-- Help-tooltip owners: candidate key → the keys its tooltip shows.
local TOOLTIPS = {
  rewardTab = { FRAME .. ".LegacyRewardTrackTab", { "LEGACY_REWARD_TRACK_TAB_TOOLTIP" } },
  challengeTab = { FRAME .. ".LegacyChallengeTab", { "LEGACY_CHALLENGE_TAB_TOOLTIP" } },
  treeTab = { FRAME .. ".LegacyTreeTab", { "LEGACY_TREE_TAB_TOOLTIP" } },
  summary = { SUMMARY, { "LEGACY_POINTS_SEASONAL_CAP" } },
  undo = { PANEL .. ".UndoButton", { "TALENT_FRAME_DISCARD_CHANGES_BUTTON_TOOLTIP" } },
}

local CANDIDATES = {
  frame = { FRAME }, panel = { PANEL }, summary = { SUMMARY },
  treeLabel = { PANEL .. ".SelectedTreeIcon.SelectedTreeLabel" },
  available = { SUMMARY .. ".AvailablePointsLabel" },
  pointsBar = { FRAME .. ".ChallengesPage.LegacyChallengePointSummary.PointsBar" },
  filter = { LIST .. ".FilterDropdown" },
  selection = { FRAME .. ".TreePage.LegacyTreeSelectionPanel" },
  cards = { FRAME .. ".ChallengesPage.DetailPane.ScrollBox" }, scrollUtil = { "ScrollUtil" },
  categories = { LIST .. ".ScrollBox" },
  objectives = { "LegacyChallengeObjectives" }, -- the one criteria frame every card borrows (xml:155)
  track = { FRAME .. ".RewardTrackPage.LegacyRewardProgressFrame" },
  -- the label's writer: OnLoad registers RefreshText itself as a currency callback, so a hook on the frame's field
  -- never runs; UpdateCurrencyInfo fires it on every show and points change [verified: forever-ui-1.60.1.70170
  -- blizzard_legacysystem/blizzard_legacysystemutil.lua:55-73, blizzard_legacytree.lua:107, 291-293]
  system = { "LegacySystem" },
}

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  for key, l in pairs(STATIC_LABELS) do Compat.declare(SURFACE, "static." .. key, { l[1] }) end
  for key, t in pairs(TOOLTIPS) do Compat.declare(SURFACE, "tip." .. key, { t[1] }) end
end

-- A stable record key per pooled challenge card (records follow the widget, not the index).
local cardKey = WFJ.Labels.keyer("card.")
local categoryKey = WFJ.Labels.keyer("category.")
local criterionKey = WFJ.Labels.keyer("criterion.")
local rewardKey = WFJ.Labels.keyer("reward.")

-- The labels the client writes once at load, the filter button's own text and the window title.
-- → the number of dictionary words found.
function Legacy.showStatic()
  local items = {}
  for _, key in ipairs(STATIC_ORDER) do
    items[#items + 1] = { key, get("static." .. key), { only = { STATIC_LABELS[key][2] } } }
  end
  local n = WFJ.Labels.showAll(SURFACE, items)
  n = n + WFJ.Labels.dropdown(SURFACE, "filter", get("filter"))
  return n + WFJ.Labels.title(SURFACE, get("frame"), TITLE)
end

-- hooksecurefunc target (LegacyTreeTraitPanel:SelectTree). → 1 | 0
function Legacy.onTree()
  return WFJ.Labels.show(SURFACE, "treeLabel", get("treeLabel"), nil, TREE)
end

-- hooksecurefunc target (LegacyTreePointSummary:RefreshText, LegacySystem.UpdateCurrencyInfo). → 1 | 0
function Legacy.onAvailable()
  return WFJ.Labels.show(SURFACE, "available", get("available"), nil, AVAILABLE)
end

-- hooksecurefunc target (PointsBar:Update). → 1 | 0
function Legacy.onPointsBar()
  local bar = get("pointsBar")
  return WFJ.Labels.show(SURFACE, "pointsBar", type(bar) == "table" and bar.Text or nil, nil, POINTS_BAR)
end

-- One pooled challenge card after its initializer ran (ScrollUtil's initialized-frame callback: (owner, frame,
-- elementData) for a new card, (frame, elementData) for the iterateExisting pass). Returns nothing: ForEachFrame
-- stops at the first truthy return (see UI/Raid.onRow).
function Legacy.onCard(a, b)
  local card = a
  if a == Legacy then card = b end
  if type(card) ~= "table" then return end
  local text = type(card.Tracked) == "table" and card.Tracked.Text or nil
  if type(text) == "table" then WFJ.Labels.show(SURFACE, cardKey(text), text, nil, TRACKED) end
  local only = WFJ.Achievement.textOnly() -- the challenge's title and description
  for _, field in ipairs(WFJ.Achievement.TEXT_FIELDS) do
    if card[field] ~= nil then WFJ.Labels.show(SURFACE, cardKey(card) .. "." .. field, card[field], nil, only) end
  end
  if type(card.Shield) == "table" then
    WFJ.HelpTooltip.register(card.Shield, WFJ.Labels.families("AchievementReward"))
  end
  WFJ.Render.updateBanner(SURFACE)
end

-- One pooled category row: its header text is a category name. Returns nothing.
function Legacy.onCategory(a, b)
  local row = a
  if a == Legacy then row = b end
  if type(row) ~= "table" or type(row.GetTitleRegion) ~= "function" then return end
  local ok, title = pcall(row.GetTitleRegion, row)
  if ok and type(title) == "table" then
    WFJ.Labels.show(SURFACE, categoryKey(row), title, nil, WFJ.Achievement.categoryOnly())
  end
  WFJ.Render.updateBanner(SURFACE)
end

-- hooksecurefunc target (LegacyChallengeObjectives:Display): every pooled criterion it holds. → words shown
function Legacy.onObjectives(objectives)
  if type(objectives) ~= "table" then objectives = get("objectives") end
  local pool = type(objectives) == "table" and objectives.criteriaPool or nil
  if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then return 0 end
  local only, n = WFJ.Labels.families("CriteriaText"), 0
  for criterion in pool:EnumerateActive() do
    local name = type(criterion) == "table" and criterion.Name or nil
    if type(name) == "table" then
      if criterion.showingProgress then
        WFJ.SurfaceState.drop(SURFACE, criterionKey(name)) -- the count speaks; the hidden name stays as written
      else
        n = n + WFJ.Labels.show(SURFACE, criterionKey(name), name, nil, only)
      end
    end
  end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- hooksecurefunc target (a reward card's SetRewardName). → 1 | 0
function Legacy.onRewardName(card)
  if type(card) ~= "table" then return 0 end
  local n = WFJ.Labels.show(SURFACE, rewardKey(card), card.RewardName, nil, WFJ.Labels.families("RenownRewardName"))
  WFJ.Render.updateBanner(SURFACE)
  return n
end

local rewardCards = setmetatable({}, { __mode = "k" }) -- cards whose SetRewardName is hooked

-- hooksecurefunc target (LegacyRewardProgressFrame:Init): the cards it acquired. → the number of cards seen
function Legacy.onTrack(track)
  if type(track) ~= "table" then track = get("track") end
  local cards = type(track) == "table" and track.Elements or nil
  if type(cards) ~= "table" then return 0 end
  local tooltip = WFJ.Labels.familiesWith(RENOWN_TOOLTIP_KEYS, "RenownRewardName", "RenownRewardDescription")
  local n = 0
  for _, card in ipairs(cards) do
    if type(card) == "table" then
      WFJ.HelpTooltip.register(card, tooltip)
      if not rewardCards[card] and type(card.SetRewardName) == "function" then
        rewardCards[card] = true
        hooksecurefunc(card, "SetRewardName", Legacy.onRewardName)
      end
      Legacy.onRewardName(card)
      n = n + 1
    end
  end
  return n
end

-- hooksecurefunc target (LegacyTreeSelectionPanel:RefreshTreeButtons): the pooled tree buttons own a one-line tooltip.
-- → the number of buttons registered.
function Legacy.onTreeButtons()
  local selection = get("selection")
  local buttons = type(selection) == "table" and selection.treeButtons or nil
  if type(buttons) ~= "table" then return 0 end
  local n = 0
  for _, button in pairs(buttons) do
    if type(button) == "table" then
      WFJ.HelpTooltip.register(button, TREE)
      n = n + 1
    end
  end
  return n
end

local hooked = false

local function hook(owner, method, fn)
  if type(owner) == "table" and type(owner[method]) == "function" then hooksecurefunc(owner, method, fn) end
end

-- Blizzard_LegacySystem's part: runs once the addon is loaded (now, or on its ADDON_LOADED). → true when set up.
function Legacy.setup()
  declare() -- its frames exist only now: forget what Compat memoized before
  local frame = get("frame")
  if type(frame) ~= "table" then return false end
  WFJ.Labels.forbidNames(Legacy.NEVER_TOUCH) -- its widgets exist only now (Main's registration found none)
  Legacy.showStatic()
  if hooked then return false end
  hooked = true
  if type(frame.HookScript) == "function" then frame:HookScript("OnShow", Legacy.showStatic) end
  hook(get("panel"), "SelectTree", Legacy.onTree)
  hook(get("summary"), "RefreshText", Legacy.onAvailable)
  hook(get("system"), "UpdateCurrencyInfo", Legacy.onAvailable)
  hook(get("pointsBar"), "Update", Legacy.onPointsBar)
  hook(get("selection"), "RefreshTreeButtons", Legacy.onTreeButtons)
  hook(get("objectives"), "Display", Legacy.onObjectives)
  hook(get("track"), "Init", Legacy.onTrack)
  local cards, util = get("cards"), get("scrollUtil")
  if type(cards) == "table" and type(util) == "table" and type(util.AddInitializedFrameCallback) == "function" then
    util.AddInitializedFrameCallback(cards, Legacy.onCard, Legacy, true)
  end
  local categories = get("categories")
  if type(categories) == "table" and type(util) == "table" and type(util.AddInitializedFrameCallback) == "function" then
    util.AddInitializedFrameCallback(categories, Legacy.onCategory, Legacy, true)
  end
  for key, t in pairs(TOOLTIPS) do WFJ.HelpTooltip.register(get("tip." .. key), { only = t[2] }) end
  Legacy.onTreeButtons()
  Legacy.onObjectives()
  Legacy.onTrack()
  Legacy.onTree()
  Legacy.onAvailable()
  Legacy.onPointsBar()
  WFJ.Render.updateBanner(SURFACE)
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init. → true when the
-- window was set up now; false while Blizzard_LegacySystem is not loaded or has no frame.
function Legacy.init()
  declare()
  local done = false
  WFJ.LoadOnDemand.when(ADDON, function() done = Legacy.setup() end)
  return done
end
