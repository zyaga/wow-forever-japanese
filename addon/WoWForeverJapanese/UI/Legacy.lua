-- UI/Legacy.lua: the Legacy window on Forever (surface "legacy", area "ui", ADR-016). A Forever-only system:
-- Blizzard_LegacySystem is load-on-demand (blizzard_legacysystem.toc) and opens from the Legacy micro button
-- (LegacyMicroButtonMixin:OnClick → ToggleLegacySystemUI, blizzard_micromenu/mainline/mainmenubarmicrobuttons.lua:
-- 1043–1046; camelot places the button, camelot/micromenucontaineroverrides.lua:8) and from the TOGGLELEGACYSYSTEM
-- binding (blizzard_framexml/bindings_camelot.xml:1214). ToggleLegacySystemUI loads the addon on first use
-- (blizzard_legacysystem_bootstrap.lua:7–16), so everything here waits through WFJ.LoadOnDemand.when.
-- LegacySystemFrame (blizzard_legacysystem.xml:4, PortraitFrameTemplate) has three pages, each a parentKey child:
--   RewardTrackPage, ChallengesPage, TreePage (xml:40–42). Every widget is parentKey-only (dotted Compat names).
-- Title: each page's OnShow calls LegacySystemFrame:SetTitle: LEGACY_TRACK_FRAME_TITLE (blizzard_legacyrewardtrack
--   .lua:24), LEGACY_CHALLENGE_FRAME_TITLE (blizzard_legacychallenges.lua:54), LEGACY_TREE_FRAME_TITLE
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
--     (blizzard_legacychallenges.lua:359–366);
--   the challenge cards (ChallengesPage.DetailPane.ScrollBox, pooled LegacyChallengeTemplate): Tracked.Text
--     TRACK_ACHIEVEMENT (blizzard_legacysystemtemplates.xml:76, 281), walked from the ScrollBox's initialized-frame
--     callback and from each card's own Init (post-hooked once: a click and a progress update re-init a card
--     directly), keyed by widget. The Tracked check owns its tooltip: LegacyChallengeTrackedTemplate inherits
--     AchievementCheckButtonBaseTemplate (blizzard_legacysystemtemplates.xml:69), whose AchievementButtonCheckMixin:
--     OnEnter writes TRACK_ / UNTRACK_ACHIEVEMENT_TOOLTIP with SetText [verified: forever-ui-1.60.1.71037
--     blizzard_achievementui/mainline/blizzard_achievementui.xml:220-225, blizzard_achievementui.lua:1792-1798]: a
--     help-tooltip owner restricted to those two keys, registered as each card is shown. ADR-042: a card is an
--     achievement row (LegacyChallengeTemplate inherits AchievementTemplateMixin:Init,
--     blizzard_legacychallengebutton.lua:202; blizzard_achievementui.lua:1352, 1373): its Label, Description and
--     HiddenDescription (shown instead of Description while the card is expanded) are the Achievement table's text,
--     restricted to the achievement families (UI/Achievement.TEXT_FIELDS, textOnly); its Shield owns the reward
--     tooltip, one line added by AchievementShield_OnEnter (blizzard_legacyachievementoverrides.lua:39–48): the
--     AchievementReward family only.
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
--     SetInfo resets it) is post-hooked on the card: RewardName restricted to the RenownRewardName family and the
--     four labelled forms the client builds around a mount's, a title's, a companion's or an illusion's name
--     ("Mount: %s", RENOWN_REWARD_*_NAME_FORMAT, blizzard_framexmlutil/renownrewardutil.lua:18-26, 44-52, 65-72): the
--     label in Japanese and, while names are on, the name in its Japanese. A name that is neither is an item's or a
--     spell's own name (renownrewardutil.lua:3-70): never a dictionary word; while names are on it shows the name's
--     Japanese (UI/NameLabels). Nothing reads or measures RewardName: the client writes it, colours it and fades it
--     [verified: forever-ui-1.60.1.71037 blizzard_framexml/rewardtracktemplates.lua:472-506]. Each card owns its
--     tooltip (RenownLevelMixin:RefreshTooltip, :533-565): a single reward's name as title and its description,
--     else the milestone title and "- %s" name lines (RENOWN_REWARD_TOOLTIP_REWARD_LINE, :556-561), or the capstone
--     lines: the RenownRewardName and RenownRewardDescription families, the four labelled forms and the four fixed
--     renown keys. A title that is none of them is the reward's own name, shown as a name too. A "- %s" line is no
--     dictionary line: after each card's RefreshTooltip (post-hooked on the card) the lines under the title that
--     start with the dash show the dash and what follows it, a reward row, a labelled form or a name (surface
--     "help.legacy", released on GameTooltip's OnHide).
--   the category list (LIST.ScrollBox, pooled LegacyChallengeCategory rows): LegacyChallengeCategoryMixin:Init
--     writes the category name with SetHeaderText → GetTitleRegion():SetText (blizzard_legacychallengecategorylist
--     .lua:184–188; blizzard_sharedxml/listtemplates.lua:58–61), the AchievementCategory family only. A
--     category that is no row of that family and is a game name (a class's challenges are filed under the
--     class's name) shows the name's Japanese while names are on (UI/NameLabels). The title is measured only for
--     the row's own truncation tooltip (listtemplates.lua:63–65); the window holds no protected action.
-- Tooltips (GameTooltip with the widget as owner, then Show: help-tooltip owners restricted to their keys):
--   the three side tabs' tooltipText LEGACY_REWARD_TRACK_TAB_TOOLTIP / LEGACY_CHALLENGE_TAB_TOOLTIP /
--     LEGACY_TREE_TAB_TOOLTIP (blizzard_legacysystem.xml:9, 18, 27; SidePanelTabButtonMixin:OnEnter,
--     blizzard_sharedxml/mainline/shareduipaneltemplates.lua:408–418);
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
local TRACKED_TOOLTIP = { only = { "TRACK_ACHIEVEMENT_TOOLTIP", "UNTRACK_ACHIEVEMENT_TOOLTIP" } }
-- a reward's name behind its kind ("Mount: %s", blizzard_framexmlutil/renownrewardutil.lua:18-26, 44-52)
local REWARD_NAME_FORMATS = { "RENOWN_REWARD_MOUNT_NAME_FORMAT", "RENOWN_REWARD_TITLE_NAME_FORMAT",
  "RENOWN_REWARD_FOLLOWER_NAME_FORMAT", "RENOWN_REWARD_ILLUSION_NAME_FORMAT" }
-- the fixed lines of a reward card's tooltip besides a reward's own name and description, and the title of a
-- single reward in a labelled form
local RENOWN_TOOLTIP_KEYS = { "RENOWN_REWARD_CAPSTONE_TOOLTIP_TITLE", "RENOWN_REWARD_CAPSTONE_TOOLTIP_DESC",
  "RENOWN_REWARD_CAPSTONE_TOOLTIP_DESC2", "RENOWN_REWARD_MILESTONE_TOOLTIP_TITLE", unpack(REWARD_NAME_FORMATS) }
-- RENOWN_REWARD_TOOLTIP_REWARD_LINE is "- %s": the dash the client writes before each reward of a milestone
local DASH = "- "
-- under the help surface: tooltip lines, never a window's labels
local TIP = "help.legacy"

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
  -- never runs; UpdateCurrencyInfo fires it on every show and points change [verified: forever-ui-1.60.1.70425
  -- blizzard_legacysystem/blizzard_legacysystemutil.lua:62-80, blizzard_legacytree.lua:107, 291-293]
  system = { "LegacySystem" }, tooltip = { "GameTooltip" },
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

-- A challenge card's Track label and tooltip, title, description and reward tooltip. Returns nothing.
local function showCard(card)
  local text = type(card.Tracked) == "table" and card.Tracked.Text or nil
  if type(text) == "table" then WFJ.Labels.show(SURFACE, cardKey(text), text, nil, TRACKED) end
  if type(card.Tracked) == "table" then WFJ.HelpTooltip.register(card.Tracked, TRACKED_TOOLTIP) end
  local only = WFJ.Achievement.textOnly() -- the challenge's title and description
  for _, field in ipairs(WFJ.Achievement.TEXT_FIELDS) do
    if card[field] ~= nil then WFJ.Labels.show(SURFACE, cardKey(card) .. "." .. field, card[field], nil, only) end
  end
  if type(card.Shield) == "table" then
    WFJ.HelpTooltip.register(card.Shield, WFJ.Labels.families("AchievementReward"))
  end
  WFJ.Render.updateBanner(SURFACE)
end

-- The board also calls a card's own Init directly, with no ScrollBox callback: selecting or deselecting it
-- (AchievementTemplateMixin:SetSelected, blizzard_achievementui/mainline/blizzard_achievementui.lua:1225–1226,
-- through the selection behavior AchievementFrameAchievements_OnLoad gives the detail pane,
-- blizzard_legacychallengedetailpane.lua:6) and on a progress update (UpdateChallenge, :66–70). Init rewrites the
-- English, so the first time a card is seen its own Init is post-hooked too (once per pooled card).
local cardHooked = setmetatable({}, { __mode = "k" })

-- Runs inside the client's own Init (a click, a progress update): a failure here must not break the list, so it
-- is caught and recorded instead of reaching the caller.
local function showCardAfterInit(card)
  local ok, err = pcall(showCard, card)
  if not ok and WFJ.ErrorLog then WFJ.ErrorLog.recordCaught(err) end
end

-- One pooled challenge card after its initializer ran (ScrollUtil's initialized-frame callback: (owner, frame,
-- elementData) for a new card, (frame, elementData) for the iterateExisting pass). Returns nothing: ForEachFrame
-- stops at the first truthy return (see UI/Raid.onRow).
function Legacy.onCard(a, b)
  local card = a
  if a == Legacy then card = b end
  if type(card) ~= "table" then return end
  if not cardHooked[card] and type(card.Init) == "function" then
    cardHooked[card] = true
    hooksecurefunc(card, "Init", showCardAfterInit)
  end
  showCard(card)
end

-- One pooled category row: its header text is a category name. Returns nothing.
function Legacy.onCategory(a, b)
  local row = a
  if a == Legacy then row = b end
  if type(row) ~= "table" or type(row.GetTitleRegion) ~= "function" then return end
  local ok, title = pcall(row.GetTitleRegion, row)
  if ok and type(title) == "table" then
    local key = categoryKey(row)
    if WFJ.Labels.show(SURFACE, key, title, nil, WFJ.Achievement.categoryOnly()) == 0 then
      WFJ.NameLabels.show(SURFACE, key, title) -- a class's category: a game name
    end
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

-- A reward's name as the client writes it: a reward row's text or one of the labelled forms. → { only = set }
local function rewardNames()
  return WFJ.Labels.familiesWith(REWARD_NAME_FORMATS, "RenownRewardName")
end

-- hooksecurefunc target (a reward card's SetRewardName). → 1 | 0
function Legacy.onRewardName(card)
  if type(card) ~= "table" then return 0 end
  local key = rewardKey(card)
  local n = WFJ.Labels.show(SURFACE, key, card.RewardName, nil, rewardNames())
  if n == 0 then n = WFJ.NameLabels.show(SURFACE, key, card.RewardName) end -- an item's or a spell's own name
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- hooksecurefunc target (a reward card's RefreshTooltip): the "- <reward>" lines of a card with several rewards,
-- which the tooltip's own pass leaves as written. Line 1 is the milestone title. → the number of lines shown
function Legacy.onRewardTooltip(card)
  local tt = get("tooltip")
  if type(card) ~= "table" or type(tt) ~= "table" or type(tt.GetOwner) ~= "function" or tt:GetOwner() ~= card
      or type(tt.NumLines) ~= "function" or type(tt.GetName) ~= "function" then return 0 end
  local name, n, refit = tt:GetName(), 0, WFJ.HelpTooltip.refit
  if type(name) ~= "string" then return 0 end
  for i = 2, tt:NumLines() or 0 do
    local fs = Compat.resolve(name .. "TextLeft" .. i)
    local text = type(fs) == "table" and type(fs.GetText) == "function" and fs:GetText() or nil
    local rec = WFJ.SurfaceState.get(TIP, "L" .. i)
    local reward = type(text) == "string" and text:match("^" .. DASH:gsub("%-", "%%-") .. "(.+)$")
    if rec and rec.fs == fs and rec.applied ~= nil and text == rec.applied then
      n = n + 1 -- still ours
    elseif reward then
      local part = WFJ.Labels.part(reward, rewardNames().only)
      if part then
        n = n + WFJ.Labels.showArgs(TIP, "L" .. i, fs, part.key, { form = "seq", parts = { DASH, part } }, refit)
      else
        n = n + WFJ.NameLabels.after(TIP, "L" .. i, fs, DASH, nil, refit)
      end
    else
      WFJ.SurfaceState.drop(TIP, "L" .. i)
    end
  end
  if n > 0 then refit() end -- one layout for the new widths
  return n
end

local rewardCards = setmetatable({}, { __mode = "k" }) -- cards whose SetRewardName is hooked

-- hooksecurefunc target (LegacyRewardProgressFrame:Init): the cards it acquired. → the number of cards seen
function Legacy.onTrack(track)
  if type(track) ~= "table" then track = get("track") end
  local cards = type(track) == "table" and track.Elements or nil
  if type(cards) ~= "table" then return 0 end
  -- line 1 of a single reward's tooltip is the reward's name: a row of the family, else a game name
  local tooltip = { nameLine = "ui",
    only = WFJ.Labels.familiesWith(RENOWN_TOOLTIP_KEYS, "RenownRewardName", "RenownRewardDescription").only }
  local n = 0
  for _, card in ipairs(cards) do
    if type(card) == "table" then
      WFJ.HelpTooltip.register(card, tooltip)
      if not rewardCards[card] and type(card.SetRewardName) == "function" then
        rewardCards[card] = true
        hooksecurefunc(card, "SetRewardName", Legacy.onRewardName)
        if type(card.RefreshTooltip) == "function" then
          hooksecurefunc(card, "RefreshTooltip", Legacy.onRewardTooltip)
        end
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
  local tt = get("tooltip")
  if type(tt) == "table" and type(tt.HookScript) == "function" then
    tt:HookScript("OnHide", function() WFJ.Render.release(TIP) end)
  end
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
