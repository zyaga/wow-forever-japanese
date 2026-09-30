-- UI/Achievement.lua: the achievement window on Forever (surface "achievement", area "ui", ADR-016).
-- Blizzard_AchievementUI is load-on-demand and `camelot` loads its mainline files (blizzard_achievementui.toc:5–12).
-- camelot's micro menu does not place AchievementMicroButton (blizzard_micromenu/camelot/
-- micromenucontaineroverrides.lua:4–17) and bindings_camelot.xml has no TOGGLEACHIEVEMENT, but the window still has
-- entry points inside the camelot load set: the /achievements command (blizzard_chatframebase/shared/
-- slashcommands.lua:1310–1320), a click on an achievement toast (blizzard_framexml/mainline/alertframesystems.lua:
-- 400–417), a tracked achievement's header (blizzard_objectivetracker/blizzard_achievementobjectivetracker.lua:
-- 59–70), the unit menu's Compare Achievements (blizzard_unitpopup/mainline/unitpopupbuttons.lua:23) and the pet
-- journal's achievement status (blizzard_collections/shared/blizzard_petcollection.lua:1715). The alert system loads
-- the addon on ACHIEVEMENT_EARNED (blizzard_framexml/mainline/alertframes.lua:542–546), so it is waited for through
-- WFJ.LoadOnDemand.when. Whether the window really opens on Forever (the game rule AchievementsPanelDisabled,
-- blizzard_achievementui.lua:217; Blizzard_LegacySystem redefines several of its globals, blizzard_legacychallenges
-- .lua:302–344) is an in-game check.
-- Static labels (XML text=, blizzard_achievementui/mainline/blizzard_achievementui.xml; each restricted to its key):
--   AchievementFrameTab1 ACHIEVEMENTS (:2571), Tab2 ACHIEVEMENTS_GUILD_TAB (:2582), Tab3 STATISTICS (:2590);
--   AchievementFrameSummaryAchievementsEmptyText NO_COMPLETED_ACHIEVEMENTS (:2143),
--   AchievementFrameSummaryAchievementsHeaderTitle LATEST_UNLOCKED_ACHIEVEMENTS (:2166),
--   AchievementFrameSummaryCategoriesHeaderTitle ACHIEVEMENT_CATEGORY_PROGRESS (:2199),
--   AchievementFrameSummaryCategoriesStatusBarTitle ACHIEVEMENTS_COMPLETED (:2215),
--   AchievementFrame.SearchBox's progress text SEARCH_PROGRESS_BAR_TEXT (:1883) and the search box's placeholder
--   SEARCH (SearchBoxTemplate); the filter dropdown's own text (ACHIEVEMENTFRAME_FILTER_ALL / _COMPLETED /
--   _INCOMPLETE, lua:2006–2010) follows Labels.dropdown; its popup entries are UI/Menus'.
-- Writers (globals called by name, post-hooked):
--   AchievementFrame_RefreshView → AchievementFrame.Header.Title ACHIEVEMENT_TITLE / GUILD_ACHIEVEMENTS_TITLE
--     (lua:374–398);
--   AchievementFrameCategories_OnCategoryChanged and AchievementFrameAchievements_UpdateDataProvider →
--     AchievementFrameAchievementsFeatOfStrengthText FEAT_OF_STRENGTH_DESCRIPTION / GUILD_… (lua:852, 1035);
--   AchievementFrame_ShowSearchPreviewResults → the search preview's ShowAllSearchResults.Text
--     ENCOUNTER_JOURNAL_SHOW_SEARCH_RESULTS ("Show All %d Results", lua:3556, 3585–3589; xml:1816);
--   AchievementFrameSummary_UpdateAchievements creates the summary buttons AchievementFrameSummaryAchievement1–3 on
--     first use (lua:2529–2546); each is then a help-tooltip owner: an empty slot's tooltip is
--     SUMMARY_ACHIEVEMENT_INCOMPLETE / _TEXT (lua:2646–2647, AchievementFrameSummaryAchievement_OnEnter :2710–2717).
-- Pooled rows, walked from each ScrollBox's initialized-frame callback, keyed by widget:
--   AchievementFrameCategories.ScrollBox: Button.Label is ACHIEVEMENT_SUMMARY_CATEGORY for the summary row and a
--     category name from the client tables for every other (AchievementCategoryTemplateMixin:Init, lua:583–596):
--     restricted to that one key;
--   AchievementFrameAchievements.ScrollBox (AchievementTemplate, xml:746–1030): Tracked's unnamed label
--     TRACK_ACHIEVEMENT (xml:236), its tooltip TRACK_ / UNTRACK_ACHIEVEMENT_TOOLTIP (lua:1793–1798) and the Shield's
--     tooltip ACCOUNT_WIDE_ACHIEVEMENT[_COMPLETED] / CHARACTER_ACHIEVEMENT_DESCRIPTION (AchievementShield_OnEnter,
--     lua:3344–3366), which in the guild view goes on with AchievementFrameAchievements_CheckGuildMembersTooltip's
--     GUILD_ACHIEVEMENT_EARNED_BY / INCOMPLETE heading above guild members' names (lua:3372, 3386–3432): both are
--     help-tooltip owners restricted to those keys, so the names are never matched.
-- Writers with names inside (post-hooked; the names kept as `text` / `verbatim`):
--   AchievementFrameComparison_UpdateStatusBars → Summary.Player.StatusBar.Title ACHIEVEMENTS_COMPLETED_CATEGORY with
--     a category name (lua:881–892);
--   AchievementFrame_UpdateFullSearchResults → SearchResults.TitleText ENCOUNTER_JOURNAL_SEARCH_RESULTS with the
--     typed search text (lua:3787–3794);
--   AchievementButton_LocalizeMetaAchievement (mainline/localization.lua:13, the localizer every new pooled meta
--     criteria button goes through, lua:1862–1889) → the button owns its tooltip: ACHIEVEMENT_META_COMPLETED_DATE
--     with FormatShortDate's date, then the guild members' heading (AchievementMetaCriteriaMixin:OnEnter, :2772–2779).
-- The achievement text itself (ADR-042), from the client tables, each widget restricted to its families
-- (AchievementTitle / AchievementDescription / AchievementReward; AchievementCategory):
--   an achievement row's Label, Description and Reward (AchievementTemplateMixin:Init, lua:1352, 1373, 1764; the
--     HiddenDescription the client only measures is left as written);
--   a category row's Button.Label (lua:596; ACHIEVEMENT_SUMMARY_CATEGORY as before);
--   the Statistics rows (AchievementStatTemplateMixin:Init, lua:2339–2400): a header's Title (a category name) and a
--     statistic's own text (an achievement title, self:SetText), AchievementFrameStats.ScrollBox;
--   the comparison view: an achievement row's Player.Label / Player.Description (AchievementComparisonTemplateMixin:
--     Init, lua:2909–2911) and a statistic row's Title / Text (AchivementComparisonStatMixin:Init, lua:3102–3150);
--   the summary: the recent achievements' Label / Description (AchievementFrameSummary_UpdateAchievements,
--     lua:2578–2579, 2626–2627) and the category bars' Label (AchievementFrameSummary_UpdateSummaryProgressBars,
--     lua:2490–2495, AchievementFrameSummaryCategoriesCategory1–12);
--   a meta criteria button's Label (another achievement's title; AchievementObjectives_DisplayCriteria, lua:2124).
-- Never touched: criteria text, player names in the comparison view, the point totals, the search EditBox.
local _, WFJ = ...
local Achievement = {}
WFJ.Achievement = Achievement

local SURFACE = "achievement"
Achievement.SURFACE = SURFACE
local Compat = WFJ.Compat
local ADDON = "Blizzard_AchievementUI"

local FILTERS = "AchievementFrame.HeaderDetails.Filters"
Achievement.NEVER_TOUCH = { FILTERS .. ".SearchBox", "AchievementFrame.Header.Points",
  "AchievementFrameComparisonHeaderName" }

-- Static labels: record key → { candidate, the one key it shows }.
local STATIC_LABELS = {
  tab1 = { "AchievementFrameTab1", "ACHIEVEMENTS" }, tab2 = { "AchievementFrameTab2", "ACHIEVEMENTS_GUILD_TAB" },
  tab3 = { "AchievementFrameTab3", "STATISTICS" },
  emptyText = { "AchievementFrameSummaryAchievementsEmptyText", "NO_COMPLETED_ACHIEVEMENTS" },
  recentTitle = { "AchievementFrameSummaryAchievementsHeaderTitle", "LATEST_UNLOCKED_ACHIEVEMENTS" },
  progressTitle = { "AchievementFrameSummaryCategoriesHeaderTitle", "ACHIEVEMENT_CATEGORY_PROGRESS" },
  earnedTitle = { "AchievementFrameSummaryCategoriesStatusBarTitle", "ACHIEVEMENTS_COMPLETED" },
  searching = { FILTERS .. ".SearchBox.SearchProgressBar.Text", "SEARCH_PROGRESS_BAR_TEXT" },
  searchInstructions = { FILTERS .. ".SearchBox.Instructions", "SEARCH" },
}
local STATIC_ORDER = {}
for key in pairs(STATIC_LABELS) do STATIC_ORDER[#STATIC_ORDER + 1] = key end
table.sort(STATIC_ORDER)

local CANDIDATES = {
  frame = { "AchievementFrame" }, headerTitle = { "AchievementFrame.Header.Title" },
  featText = { "AchievementFrameAchievementsFeatOfStrengthText" }, filter = { FILTERS .. ".FilterDropdown" },
  categories = { "AchievementFrameCategories.ScrollBox" }, achievements = { "AchievementFrameAchievements.ScrollBox" },
  scrollUtil = { "ScrollUtil" }, refreshView = { "AchievementFrame_RefreshView" },
  categoryChanged = { "AchievementFrameCategories_OnCategoryChanged" },
  updateProvider = { "AchievementFrameAchievements_UpdateDataProvider" },
  showAll = { FILTERS .. ".SearchBox.SearchPreviewContainer.ShowAllSearchResults.Text" },
  showPreview = { "AchievementFrame_ShowSearchPreviewResults" },
  updateSummary = { "AchievementFrameSummary_UpdateAchievements" },
  comparisonTitle = { "AchievementFrameComparison.Summary.Player.StatusBar.Title" },
  comparisonBars = { "AchievementFrameComparison_UpdateStatusBars" },
  searchTitle = { "AchievementFrame.SearchResults.TitleText" },
  fullSearch = { "AchievementFrame_UpdateFullSearchResults" },
  localizeMeta = { "AchievementButton_LocalizeMetaAchievement" },
  stats = { "AchievementFrameStats.ScrollBox" },
  comparisonAchievements = { "AchievementFrameComparison.AchievementContainer.ScrollBox" },
  comparisonStats = { "AchievementFrameComparison.StatContainer.ScrollBox" },
  summaryBars = { "AchievementFrameSummary_UpdateSummaryProgressBars" },
  displayCriteria = { "AchievementObjectives_DisplayCriteria" },
}

local COMPARISON = { only = { "ACHIEVEMENTS_COMPLETED_CATEGORY" } }
local SEARCH_TITLE = { only = { "ENCOUNTER_JOURNAL_SEARCH_RESULTS" } }
local META_TOOLTIP = { only = { "ACHIEVEMENT_META_COMPLETED_DATE", "GUILD_ACHIEVEMENT_EARNED_BY", "INCOMPLETE" } }
local SUMMARY_BUTTONS = 3 -- ACHIEVEMENTUI_MAX_SUMMARY_ACHIEVEMENTS (lua:19)
local SUMMARY_BARS = 12 -- AchievementFrameSummary_UpdateSummaryProgressBars (lua:2491)

local HEADER = { only = { "ACHIEVEMENT_TITLE", "GUILD_ACHIEVEMENTS_TITLE" } }
local FEAT = { only = { "FEAT_OF_STRENGTH_DESCRIPTION", "GUILD_FEAT_OF_STRENGTH_DESCRIPTION" } }
local CATEGORY_KEYS = { "ACHIEVEMENT_SUMMARY_CATEGORY" }
-- The `only` of an achievement's own text, and of a category name (the families' shipped keys).
local function textOnly()
  return WFJ.Labels.families("AchievementTitle", "AchievementDescription", "AchievementReward")
end
local function categoryOnly() return WFJ.Labels.familiesWith(CATEGORY_KEYS, "AchievementCategory") end
Achievement.textOnly, Achievement.categoryOnly = textOnly, categoryOnly
local TRACK_KEY = "TRACK_ACHIEVEMENT"
local TRACKED = { only = { TRACK_KEY } }
local TRACKED_TOOLTIP = { only = { "TRACK_ACHIEVEMENT_TOOLTIP", "UNTRACK_ACHIEVEMENT_TOOLTIP" } }
local SHIELD_TOOLTIP = { only = { "ACCOUNT_WIDE_ACHIEVEMENT", "ACCOUNT_WIDE_ACHIEVEMENT_COMPLETED",
  "CHARACTER_ACHIEVEMENT_DESCRIPTION", "GUILD_ACHIEVEMENT_EARNED_BY", "INCOMPLETE" } }

local SHOW_ALL = { only = { "ENCOUNTER_JOURNAL_SHOW_SEARCH_RESULTS" } }
local SUMMARY_TOOLTIP = { only = { "SUMMARY_ACHIEVEMENT_INCOMPLETE", "SUMMARY_ACHIEVEMENT_INCOMPLETE_TEXT" } }

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  for key, l in pairs(STATIC_LABELS) do Compat.declare(SURFACE, "static." .. key, { l[1] }) end
  for i = 1, SUMMARY_BUTTONS do
    Compat.declare(SURFACE, "summary" .. i, { "AchievementFrameSummaryAchievement" .. i })
  end
  for i = 1, SUMMARY_BARS do
    Compat.declare(SURFACE, "summaryBar" .. i, { "AchievementFrameSummaryCategoriesCategory" .. i .. ".Label" })
  end
end

-- The fields of an achievement row that hold its own text (UI/Legacy's challenge cards are the same template)
Achievement.TEXT_FIELDS = { "Label", "Description", "Reward" }

-- An achievement's title, description and reward on one row (`prefix` its record key). → words shown
local function showText(prefix, row)
  if type(row) ~= "table" then return 0 end
  local only, n = textOnly(), 0
  for _, field in ipairs(Achievement.TEXT_FIELDS) do
    if row[field] ~= nil then n = n + WFJ.Labels.show(SURFACE, prefix .. "." .. field, row[field], nil, only) end
  end
  return n
end

-- hooksecurefunc target (AchievementFrame_ShowSearchPreviewResults). → 1 | 0
function Achievement.onSearchPreview()
  return WFJ.Labels.show(SURFACE, "showAll", get("showAll"), nil, SHOW_ALL)
end

-- hooksecurefunc target (AchievementFrameSummary_UpdateAchievements): the summary buttons exist from its first run.
-- → the number of buttons registered.
function Achievement.onSummary()
  declare() -- the buttons may be new: forget what Compat memoized before
  local n = 0
  for i = 1, SUMMARY_BUTTONS do
    local button = get("summary" .. i)
    if type(button) == "table" then
      WFJ.HelpTooltip.register(button, SUMMARY_TOOLTIP)
      showText("summary" .. i, button) -- the recent achievement's title and description
      n = n + 1
    end
  end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- hooksecurefunc target (AchievementFrameSummary_UpdateSummaryProgressBars): the category bars' names.
-- → the number of category names shown
function Achievement.onSummaryBars()
  local n = 0
  for i = 1, SUMMARY_BARS do
    n = n + WFJ.Labels.show(SURFACE, "summaryBar" .. i, get("summaryBar" .. i), nil, categoryOnly())
  end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- hooksecurefunc targets: the comparison status bar's title, the full search results' title, and a new meta
-- criteria button (it owns its completed-date tooltip). → 1 | 0
function Achievement.onComparison()
  return WFJ.Labels.show(SURFACE, "comparisonTitle", get("comparisonTitle"), nil, COMPARISON)
end
function Achievement.onSearchTitle()
  return WFJ.Labels.show(SURFACE, "searchTitle", get("searchTitle"), nil, SEARCH_TITLE)
end
local metas = setmetatable({}, { __mode = "k" }) -- meta criteria buttons seen (their Label is a title)
local metaKey = WFJ.Labels.keyer("meta.")
function Achievement.onMeta(frame)
  if type(frame) ~= "table" then return 0 end
  WFJ.HelpTooltip.register(frame, META_TOOLTIP)
  metas[frame] = true
  return 1
end

-- hooksecurefunc target (AchievementObjectives_DisplayCriteria): every meta criteria button's title.
-- → the number shown
function Achievement.onCriteria()
  local n = 0
  for frame in pairs(metas) do
    if frame.Label ~= nil then n = n + WFJ.Labels.show(SURFACE, metaKey(frame), frame.Label, nil, textOnly()) end
  end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

local categoryKey = WFJ.Labels.keyer("category.") -- pooled rows' record keys (they follow the widget)
local trackedKey = WFJ.Labels.keyer("tracked.")
local rowKey = WFJ.Labels.keyer("row.")
local statKey = WFJ.Labels.keyer("stat.")

-- hooksecurefunc target (AchievementFrame_RefreshView). → 1 | 0
function Achievement.onHeader()
  return WFJ.Labels.show(SURFACE, "headerTitle", get("headerTitle"), nil, HEADER)
end

-- hooksecurefunc target (the two writers of the Feats of Strength note). → 1 | 0
function Achievement.onFeat()
  return WFJ.Labels.show(SURFACE, "featText", get("featText"), nil, FEAT)
end

-- The labels the client writes once at load, the filter button's own text and the two written headers.
-- HookScript target (AchievementFrame OnShow). → the number of dictionary words found.
function Achievement.showStatic()
  local items = {}
  for _, key in ipairs(STATIC_ORDER) do
    items[#items + 1] = { key, get("static." .. key), { only = { STATIC_LABELS[key][2] } } }
  end
  local n = WFJ.Labels.showAll(SURFACE, items)
  return n + WFJ.Labels.dropdown(SURFACE, "filter", get("filter")) + Achievement.onHeader() + Achievement.onFeat()
end

-- The row a ScrollUtil initialized-frame callback hands over: (owner, frame, elementData) for a new row,
-- (frame, elementData) for the iterateExisting pass.
local function rowOf(a, b)
  local row = a
  if a == Achievement then row = b end
  return type(row) == "table" and row or nil
end

-- One pooled category row. Returns nothing: ForEachFrame stops at the first truthy return (see UI/Raid.onRow).
function Achievement.onCategory(a, b)
  local row = rowOf(a, b)
  local label = row and type(row.Button) == "table" and row.Button.Label or nil
  if type(label) == "table" then WFJ.Labels.show(SURFACE, categoryKey(label), label, nil, categoryOnly()) end
  WFJ.Render.updateBanner(SURFACE)
end

-- One pooled statistic row (the Statistics tab and the comparison view's): a header's Title is a category name, a
-- statistic's text an achievement title (its Text FontString, or the button's own). Returns nothing.
function Achievement.onStat(a, b)
  local row = rowOf(a, b)
  if not row then return end
  local key = statKey(row)
  if row.isHeader then
    WFJ.SurfaceState.drop(SURFACE, key .. ".text")
    WFJ.Labels.show(SURFACE, key .. ".title", row.Title, nil, categoryOnly())
  else
    WFJ.SurfaceState.drop(SURFACE, key .. ".title")
    WFJ.Labels.show(SURFACE, key .. ".text", row.Text ~= nil and row.Text or row, nil, textOnly())
  end
  WFJ.Render.updateBanner(SURFACE)
end

-- One pooled comparison row: the player side's title and description. Returns nothing.
function Achievement.onComparisonRow(a, b)
  local row = rowOf(a, b)
  if row then showText(rowKey(row), row.Player) end
  WFJ.Render.updateBanner(SURFACE)
end

-- One pooled achievement row. Returns nothing.
function Achievement.onAchievement(a, b)
  local row = rowOf(a, b)
  if not row then return end
  local tracked = row.Tracked
  if type(tracked) == "table" then
    local label = WFJ.Labels.region(tracked, TRACK_KEY)
    if label then WFJ.Labels.show(SURFACE, trackedKey(label), label, nil, TRACKED) end
    WFJ.HelpTooltip.register(tracked, TRACKED_TOOLTIP)
  end
  if type(row.Shield) == "table" then WFJ.HelpTooltip.register(row.Shield, SHIELD_TOOLTIP) end
  showText(rowKey(row), row)
  WFJ.Render.updateBanner(SURFACE)
end

local hooked = false

-- Blizzard_AchievementUI's part: runs once the addon is loaded (now, or on its ADDON_LOADED). → true when set up.
function Achievement.setup()
  declare() -- its frames exist only now: forget what Compat memoized before
  local frame = get("frame")
  if type(frame) ~= "table" then return false end
  WFJ.Labels.forbidNames(Achievement.NEVER_TOUCH) -- its widgets exist only now (Main's registration found none)
  Achievement.showStatic()
  if hooked then return false end
  hooked = true
  if type(frame.HookScript) == "function" then frame:HookScript("OnShow", Achievement.showStatic) end
  if type(get("refreshView")) == "function" then
    hooksecurefunc("AchievementFrame_RefreshView", Achievement.onHeader)
  end
  if type(get("categoryChanged")) == "function" then
    hooksecurefunc("AchievementFrameCategories_OnCategoryChanged", Achievement.onFeat)
  end
  if type(get("updateProvider")) == "function" then
    hooksecurefunc("AchievementFrameAchievements_UpdateDataProvider", Achievement.onFeat)
  end
  if type(get("showPreview")) == "function" then
    hooksecurefunc("AchievementFrame_ShowSearchPreviewResults", Achievement.onSearchPreview)
  end
  if type(get("updateSummary")) == "function" then
    hooksecurefunc("AchievementFrameSummary_UpdateAchievements", Achievement.onSummary)
  end
  for _, h in ipairs({ { "comparisonBars", "AchievementFrameComparison_UpdateStatusBars", Achievement.onComparison },
    { "fullSearch", "AchievementFrame_UpdateFullSearchResults", Achievement.onSearchTitle },
    { "localizeMeta", "AchievementButton_LocalizeMetaAchievement", Achievement.onMeta },
    { "summaryBars", "AchievementFrameSummary_UpdateSummaryProgressBars", Achievement.onSummaryBars },
    { "displayCriteria", "AchievementObjectives_DisplayCriteria", Achievement.onCriteria } }) do
    if type(get(h[1])) == "function" then hooksecurefunc(h[2], h[3]) end
  end
  Achievement.onSummary()
  local util = get("scrollUtil")
  if type(util) == "table" and type(util.AddInitializedFrameCallback) == "function" then
    local categories, achievements = get("categories"), get("achievements")
    if type(categories) == "table" then
      util.AddInitializedFrameCallback(categories, Achievement.onCategory, Achievement, true)
    end
    if type(achievements) == "table" then
      util.AddInitializedFrameCallback(achievements, Achievement.onAchievement, Achievement, true)
    end
    for _, b in ipairs({ { "stats", Achievement.onStat }, { "comparisonStats", Achievement.onStat },
      { "comparisonAchievements", Achievement.onComparisonRow } }) do
      local box = get(b[1])
      if type(box) == "table" then util.AddInitializedFrameCallback(box, b[2], Achievement, true) end
    end
  end
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init. → true when the window
-- was set up now; false while Blizzard_AchievementUI is not loaded or has no frame.
function Achievement.init()
  declare()
  local done = false
  WFJ.LoadOnDemand.when(ADDON, function() done = Achievement.setup() end)
  return done
end
