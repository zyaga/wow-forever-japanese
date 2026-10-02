-- UI/Achievement.lua over an AchievementFrame replayed from
-- blizzard_achievementui/mainline/blizzard_achievementui.xml:1700–2590 and blizzard_achievementui.lua:374–398,
-- 583–596, 852, 1035, 1793–1798, 3344–3366. Achievement and category names stay English; the surface waits for
-- Blizzard_AchievementUI in either load order and does nothing on a client without it.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/Achievement.lua"

local ADDON = "Blizzard_AchievementUI"

local UI = {
  ACHIEVEMENTS = { "Achievements", "アチーブメント" }, ACHIEVEMENTS_GUILD_TAB = { "Guild", "ギルド" },
  STATISTICS = { "Statistics", "統計" },
  NO_COMPLETED_ACHIEVEMENTS = { "You have not earned any achievements recently", "最近獲得したアチーブメントはありません" },
  LATEST_UNLOCKED_ACHIEVEMENTS = { "Recent Achievements", "最近のアチーブメント" },
  ACHIEVEMENT_CATEGORY_PROGRESS = { "Progress Overview", "進行状況の概要" },
  ACHIEVEMENTS_COMPLETED = { "Achievements Earned", "獲得したアチーブメント" },
  SEARCH_PROGRESS_BAR_TEXT = { "Searching", "検索中" }, SEARCH = { "Search", "検索" },
  ACHIEVEMENTFRAME_FILTER_ALL = { "All", "すべて" }, ACHIEVEMENTFRAME_FILTER_INCOMPLETE = { "Incomplete", "未達成" },
  ACHIEVEMENT_TITLE = { "Account Achievement Points", "アカウントのアチーブメントポイント" },
  GUILD_ACHIEVEMENTS_TITLE = { "Guild Achievements", "ギルドアチーブメント" },
  FEAT_OF_STRENGTH_DESCRIPTION = { "Feats of Strength are very difficult to earn.", "偉業は獲得が非常に困難です。" },
  ACHIEVEMENT_SUMMARY_CATEGORY = { "Summary", "概要" }, TRACK_ACHIEVEMENT = { "Track", "追跡" },
  TRACK_ACHIEVEMENT_TOOLTIP = { "Check to track this achievement.", "チェックするとこのアチーブメントを追跡します。" },
  ACCOUNT_WIDE_ACHIEVEMENT_COMPLETED = { "Earned by your Account.", "アカウントで獲得済み。" },
  GUILD_ACHIEVEMENT_EARNED_BY = { "Earned by:", "獲得者:" },
  ENCOUNTER_JOURNAL_SHOW_SEARCH_RESULTS = { "Show All %d Results", "全%d件の結果を表示" },
  SUMMARY_ACHIEVEMENT_INCOMPLETE = { "Achievement Incomplete", "未達成のアチーブメント" },
  CLOSE = { "Close", "閉じる" }, -- a word an achievement or a category may happen to be called
  -- the comparison bar's title, the full search results' title, a meta criteria's completed date
  ACHIEVEMENTS_COMPLETED_CATEGORY = { "%s Achievements Earned", "%sの獲得アチーブメント" },
  ENCOUNTER_JOURNAL_SEARCH_RESULTS = { 'Search Results for "%s"(%d)', "「%s」の検索結果(%d)" },
  ACHIEVEMENT_META_COMPLETED_DATE = { "Completed %s", "%sに達成" },
}

local function en(key) return _G[key] end
local function fs(text) return Stub.fontString(text or "") end

local C = {}
local NAMES = { "AchievementFrame", "AchievementFrameTab1", "AchievementFrameTab2", "AchievementFrameTab3",
  "AchievementFrameSummaryAchievementsEmptyText", "AchievementFrameSummaryAchievementsHeaderTitle",
  "AchievementFrameSummaryCategoriesHeaderTitle", "AchievementFrameSummaryCategoriesStatusBarTitle",
  "AchievementFrameAchievementsFeatOfStrengthText", "AchievementFrameCategories", "AchievementFrameAchievements",
  "AchievementFrame_RefreshView", "AchievementFrameCategories_OnCategoryChanged",
  "AchievementFrameAchievements_UpdateDataProvider", "AchievementFrame_ShowSearchPreviewResults",
  "AchievementFrameSummary_UpdateAchievements", "AchievementFrameSummaryAchievement1",
  "AchievementFrameSummaryAchievement2", "AchievementFrameSummaryAchievement3", "AchievementFrameComparison",
  "AchievementFrameComparison_UpdateStatusBars", "AchievementFrame_UpdateFullSearchResults",
  "AchievementButton_LocalizeMetaAchievement",
  "AchievementFrameStats", "AchievementFrameSummary_UpdateSummaryProgressBars", "AchievementObjectives_DisplayCriteria",
  "AchievementFrameSummaryCategoriesCategory1", "AchievementFrameSummaryCategoriesCategory2" }

local function loadAchievementUI()
  local f = CreateFrame("Frame", "AchievementFrame")
  f.Header = { Title = fs(en("ACHIEVEMENT_TITLE")), Points = fs("1234") }
  local filters = CreateFrame("Frame")
  f.HeaderDetails = { Filters = filters }
  filters.FilterDropdown = CreateFrame("DropdownButton")
  filters.FilterDropdown.Text = fs(en("ACHIEVEMENTFRAME_FILTER_ALL"))
  function filters.FilterDropdown.UpdateText(self) self.Text.text = en(C.filter or "ACHIEVEMENTFRAME_FILTER_ALL") end
  filters.SearchBox = CreateFrame("EditBox")
  filters.SearchBox.Instructions = fs(en("SEARCH"))
  filters.SearchBox.SearchProgressBar = { Text = fs(en("SEARCH_PROGRESS_BAR_TEXT")) }
  filters.SearchBox.SearchPreviewContainer = { ShowAllSearchResults = { Text = fs("") } }
  _G.AchievementFrame_ShowSearchPreviewResults = function() -- lua:3585–3589
    filters.SearchBox.SearchPreviewContainer.ShowAllSearchResults.Text.text =
      string.format(en("ENCOUNTER_JOURNAL_SHOW_SEARCH_RESULTS"), 12)
  end
  _G.AchievementFrameSummary_UpdateAchievements = function() -- lua:2536–2546: the buttons on first use
    for i = 1, 3 do
      local name = "AchievementFrameSummaryAchievement" .. i
      if not _G[name] then CreateFrame("Button", name) end
    end
  end
  Stub.button("AchievementFrameTab1", en("ACHIEVEMENTS"))
  Stub.button("AchievementFrameTab2", en("ACHIEVEMENTS_GUILD_TAB"))
  Stub.button("AchievementFrameTab3", en("STATISTICS"))
  Stub.namedFontString("AchievementFrameSummaryAchievementsEmptyText", en("NO_COMPLETED_ACHIEVEMENTS"))
  Stub.namedFontString("AchievementFrameSummaryAchievementsHeaderTitle", en("LATEST_UNLOCKED_ACHIEVEMENTS"))
  Stub.namedFontString("AchievementFrameSummaryCategoriesHeaderTitle", en("ACHIEVEMENT_CATEGORY_PROGRESS"))
  Stub.namedFontString("AchievementFrameSummaryCategoriesStatusBarTitle", en("ACHIEVEMENTS_COMPLETED"))
  Stub.namedFontString("AchievementFrameAchievementsFeatOfStrengthText", en("FEAT_OF_STRENGTH_DESCRIPTION"))
  local categories = CreateFrame("Frame", "AchievementFrameCategories")
  categories.ScrollBox = Stub.scrollBox()
  local achievements = CreateFrame("Frame", "AchievementFrameAchievements")
  achievements.ScrollBox = Stub.scrollBox()
  C.categoryRows, C.rows, C.filter, C.guild = {}, {}, nil, false
  function C.category(i, data) -- AchievementCategoryTemplateMixin:Init
    local row = C.categoryRows[i]
    if not row then
      row = CreateFrame("Button")
      row.Button = { Label = fs() }
      C.categoryRows[i] = row
    end
    categories.ScrollBox:initFrame(row, data, function(r, d)
      r.Button.Label.text = d.id == "summary" and en("ACHIEVEMENT_SUMMARY_CATEGORY") or d.name
    end)
    return row
  end
  function C.row(i, data) -- AchievementTemplateMixin:Init
    local row = C.rows[i]
    if not row then
      row = CreateFrame("Button")
      row.Label, row.Description = fs(), fs()
      row.Tracked = CreateFrame("CheckButton")
      row.Tracked:addRegion(fs(en("TRACK_ACHIEVEMENT")))
      row.Shield = CreateFrame("Button")
      C.rows[i] = row
    end
    achievements.ScrollBox:initFrame(row, data, function(r, d) r.Label.text, r.Description.text = d.name, d.name end)
    return row
  end
  _G.AchievementFrame_RefreshView = function()
    f.Header.Title.text = en(C.guild and "GUILD_ACHIEVEMENTS_TITLE" or "ACHIEVEMENT_TITLE")
  end
  _G.AchievementFrameCategories_OnCategoryChanged = function()
    _G.AchievementFrameAchievementsFeatOfStrengthText.text = en("FEAT_OF_STRENGTH_DESCRIPTION")
  end
  _G.AchievementFrameAchievements_UpdateDataProvider = function() end
  -- the comparison, search and meta criteria writers (lua:881–892, 3787–3794; localization.lua:13)
  local comparison = CreateFrame("Frame", "AchievementFrameComparison")
  comparison.Summary = { Player = { StatusBar = { Title = fs() } } }
  _G.AchievementFrameComparison_UpdateStatusBars = function(name)
    comparison.Summary.Player.StatusBar.Title.text = string.format(en("ACHIEVEMENTS_COMPLETED_CATEGORY"), name)
  end
  f.SearchResults = { TitleText = fs() }
  _G.AchievementFrame_UpdateFullSearchResults = function()
    f.SearchResults.TitleText.text = string.format(en("ENCOUNTER_JOURNAL_SEARCH_RESULTS"), "Close.", 3)
  end
  _G.AchievementButton_LocalizeMetaAchievement = function() end
  Stub.loadedAddons[ADDON] = true
  return f
end

describe("the achievement window on Forever", function()
  local WFJ, SS

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  local function unrecorded(widget)
    for _, bucket in pairs(SS.surfaces()) do
      for _, rec in pairs(bucket) do
        if rec.fs == widget then return false end
      end
    end
    return true
  end

  local function load()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    SS = WFJ.SurfaceState
    H.uiSetup(WFJ, UI)
  end

  local function setup(loadedFirst)
    load()
    if loadedFirst then
      loadAchievementUI()
      assert.is_true(WFJ.Achievement.init())
    else
      assert.is_false(WFJ.Achievement.init()) -- waits for the addon
      loadAchievementUI()
      assert.are.equal(1, WFJ.LoadOnDemand.loaded(ADDON))
    end
  end

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    for _, name in ipairs(NAMES) do _G[name] = nil end
  end)

  for _, order in ipairs({ { true, "loaded before the addon" }, { false, "loaded on demand" } }) do
    describe("Blizzard_AchievementUI " .. order[2], function()
      before_each(function() setup(order[1]) end)

      it("tabs, summary labels, the search box and the filter button are Japanese", function()
        assert.are.equal("アチーブメント", _G.AchievementFrameTab1:GetText())
        assert.are.equal("ギルド", _G.AchievementFrameTab2:GetText())
        assert.are.equal("統計", _G.AchievementFrameTab3:GetText())
        assert.are.equal("最近のアチーブメント", _G.AchievementFrameSummaryAchievementsHeaderTitle:GetText())
        assert.are.equal("進行状況の概要", _G.AchievementFrameSummaryCategoriesHeaderTitle:GetText())
        assert.are.equal("獲得したアチーブメント", _G.AchievementFrameSummaryCategoriesStatusBarTitle:GetText())
        local filters = _G.AchievementFrame.HeaderDetails.Filters
        assert.are.equal("検索", filters.SearchBox.Instructions:GetText())
        assert.are.equal("検索中", filters.SearchBox.SearchProgressBar.Text:GetText())
        assert.are.equal("すべて", filters.FilterDropdown.Text:GetText())
        C.filter = "ACHIEVEMENTFRAME_FILTER_INCOMPLETE"
        filters.FilterDropdown:UpdateText()
        assert.are.equal("未達成", filters.FilterDropdown.Text:GetText())
        alt(true)
        assert.are.equal("Achievements", _G.AchievementFrameTab1:GetText())
        alt(false)
        assert.are.equal("1234", _G.AchievementFrame.Header.Points:GetText())
        assert.is_true(unrecorded(_G.AchievementFrame.Header.Points))
      end)

      it("the header title follows AchievementFrame_RefreshView; the feats note follows its writers", function()
        assert.are.equal("アカウントのアチーブメントポイント", _G.AchievementFrame.Header.Title:GetText())
        C.guild = true
        _G.AchievementFrame_RefreshView()
        assert.are.equal("ギルドアチーブメント", _G.AchievementFrame.Header.Title:GetText())
        assert.are.equal("偉業は獲得が非常に困難です。", _G.AchievementFrameAchievementsFeatOfStrengthText:GetText())
        _G.AchievementFrameCategories_OnCategoryChanged()
        assert.are.equal("偉業は獲得が非常に困難です。", _G.AchievementFrameAchievementsFeatOfStrengthText:GetText())
      end)

      it("the Summary category translates; a category or achievement name never does, even on a reused row",
        function()
          local row = C.category(1, { id = "summary" })
          assert.are.equal("概要", row.Button.Label:GetText())
          C.category(1, { id = 92, name = "Close" })
          alt(true); alt(false)
          assert.are.equal("Close", row.Button.Label:GetText())
          assert.is_true(unrecorded(row.Button.Label))
          local ach = C.row(1, { name = "Close" })
          assert.are.equal("Close", ach.Label:GetText())
          assert.is_true(unrecorded(ach.Label))
          assert.is_true(unrecorded(ach.Description))
          assert.are.equal("追跡", (ach.Tracked:GetRegions()):GetText())
        end)

      it("the Track check's and the shield's tooltips are Japanese", function()
        local ach, tt = C.row(1, { name = "Level 10" }), _G.GameTooltip
        tt:SetOwner(ach.Tracked)
        tt:SetText(en("TRACK_ACHIEVEMENT_TOOLTIP"))
        assert.are.equal("チェックするとこのアチーブメントを追跡します。", _G.GameTooltipTextLeft1:GetText())
        tt:SetOwner(ach.Shield)
        tt:ClearLines()
        tt:AddLine(en("ACCOUNT_WIDE_ACHIEVEMENT_COMPLETED"))
        tt:Show()
        assert.are.equal("アカウントで獲得済み。", _G.GameTooltipTextLeft1:GetText())
        tt:ClearLines() -- the guild view's member list (AchievementFrameAchievements_CheckGuildMembersTooltip)
        tt:AddLine(en("ACCOUNT_WIDE_ACHIEVEMENT_COMPLETED"))
        tt:AddLine(" ")
        tt:AddLine(en("GUILD_ACHIEVEMENT_EARNED_BY"))
        tt:AddDoubleLine("Close", "Reyn") -- guild members' names
        tt:Show()
        assert.are.equal("獲得者:", _G.GameTooltipTextLeft3:GetText())
        assert.are.equal("Close", _G.GameTooltipTextLeft4:GetText())
      end)
    end)
  end

  it("the search preview's Show All line and an empty summary slot's tooltip are Japanese", function()
    setup(true)
    _G.AchievementFrame_ShowSearchPreviewResults()
    local text = _G.AchievementFrame.HeaderDetails.Filters.SearchBox.SearchPreviewContainer.ShowAllSearchResults.Text
    assert.are.equal("全12件の結果を表示", text:GetText())
    assert.is_nil(_G.AchievementFrameSummaryAchievement1)
    _G.AchievementFrameSummary_UpdateAchievements()
    local tt = _G.GameTooltip
    tt:SetOwner(_G.AchievementFrameSummaryAchievement2)
    tt:SetText(en("SUMMARY_ACHIEVEMENT_INCOMPLETE"))
    assert.are.equal("未達成のアチーブメント", _G.GameTooltipTextLeft1:GetText())
  end)

  it("the comparison title, the search results title and a meta criteria's date tooltip; names kept",
    function()
      setup(true)
      _G.AchievementFrameComparison_UpdateStatusBars("Dungeons & Raids")
      local title = _G.AchievementFrameComparison.Summary.Player.StatusBar.Title
      assert.are.equal("Dungeons & Raidsの獲得アチーブメント", title:GetText())
      _G.AchievementFrame_UpdateFullSearchResults()
      assert.are.equal("「Close.」の検索結果(3)", _G.AchievementFrame.SearchResults.TitleText:GetText())
      local meta = CreateFrame("Button")
      _G.AchievementButton_LocalizeMetaAchievement(meta)
      local tt = _G.GameTooltip
      tt:SetOwner(meta)
      tt:AddLine("Completed 9/25/26")
      tt:Show()
      assert.are.equal("9/25/26に達成", _G.GameTooltipTextLeft1:GetText())
      alt(true)
      assert.are.equal("Dungeons & Raids Achievements Earned", title:GetText())
      alt(false)
    end)

  it("hooks install once", function()
    setup(true)
    assert.is_false(WFJ.Achievement.setup())
    assert.are.equal(1, #Stub.hooks["AchievementFrame_RefreshView"])
    assert.are.equal(1, #Stub.hooks["AchievementFrameCategories_OnCategoryChanged"])
    assert.are.equal(1, #_G.AchievementFrameAchievements.ScrollBox.initCallbacks)
  end)

  it("client names bound to the wrong type degrade to untouched English with no error", function()
    load()
    local f = loadAchievementUI()
    f.Header = "nope"
    f.HeaderDetails.Filters.FilterDropdown = 42
    _G.AchievementFrameTab1 = true
    _G.AchievementFrame_RefreshView = "nope"
    _G.AchievementFrameCategories.ScrollBox = false
    assert.has_no.errors(function() assert.is_true(WFJ.Achievement.init()) end)
    assert.are.equal("ギルド", _G.AchievementFrameTab2:GetText()) -- the rest still works
    assert.has_no.errors(function()
      WFJ.Achievement.onAchievement({ Tracked = 1, Shield = "x" })
      WFJ.Achievement.onCategory({ Button = 7 })
    end)
  end)

  it("a client without the window: init returns false and hooks nothing", function()
    load()
    local before = 0
    for _ in pairs(Stub.hooks) do before = before + 1 end
    assert.is_false(WFJ.Achievement.init())
    Stub.loadedAddons[ADDON] = true -- the addon name loaded, but no AchievementFrame
    assert.is_false(WFJ.Achievement.init())
    assert.is_false(WFJ.Achievement.setup())
    local after = 0
    for _ in pairs(Stub.hooks) do after = after + 1 end
    assert.are.equal(before, after)
  end)
end)

-- The achievement text itself (ADR-042), from the client tables, each widget restricted to its families:
-- an achievement row's Label / Description / Reward (AchievementTemplateMixin:Init, lua:1352, 1373, 1764), a category
-- row's Button.Label (AchievementCategory, or ACHIEVEMENT_SUMMARY_CATEGORY), the Statistics rows
-- (AchievementStatTemplateMixin:Init, lua:2339–2400), the comparison rows (lua:2909–2911), the summary category bars
-- (lua:2490–2495) and a meta criteria's Label (lua:2124). A name that is no row of the family stays English.
describe("the achievement window's client-table text on Forever", function()
  local WFJ, SS, frames

  local ROWS = {}
  for k, v in pairs(UI) do ROWS[k] = v end
  ROWS["AchievementTitle:6"] = { "Level 10", "レベル10" }
  ROWS["AchievementDescription:6"] = { "Reach level 10.", "レベル10に到達する。" }
  ROWS["AchievementReward:6"] = { "Reward: Tabard of the Explorer", "報酬: 探検家のタバード" }
  ROWS["AchievementTitle:60"] = { "Total deaths", "死亡回数" }
  ROWS["AchievementCategory:92"] = { "General", "一般" }
  ROWS["AchievementCategory:130"] = { "Character", "キャラクター" }
  ROWS["CriteriaText:121233"] = { "Explore Alterac Mountains", "アルターク山脈を探検する" }

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end
  local function unrecorded(widget)
    for _, bucket in pairs(SS.surfaces()) do
      for _, rec in pairs(bucket) do if rec.fs == widget then return false end end
    end
    return true
  end

  -- the client-table widgets the base replay does not build
  local function addClientTableFrames()
    local f = {}
    local stats = CreateFrame("Frame", "AchievementFrameStats")
    stats.ScrollBox = Stub.scrollBox()
    f.stats = stats.ScrollBox
    local comparison = _G.AchievementFrameComparison
    comparison.AchievementContainer = { ScrollBox = Stub.scrollBox() }
    comparison.StatContainer = { ScrollBox = Stub.scrollBox() }
    f.compareRows, f.compareStats = comparison.AchievementContainer.ScrollBox, comparison.StatContainer.ScrollBox
    for i = 1, 2 do
      local bar = CreateFrame("StatusBar", "AchievementFrameSummaryCategoriesCategory" .. i)
      bar.Label = fs("")
    end
    f.bars = { "General", "Quests" }
    _G.AchievementFrameSummary_UpdateSummaryProgressBars = function() -- lua:2490–2495
      for i, name in ipairs(f.bars) do _G["AchievementFrameSummaryCategoriesCategory" .. i].Label.text = name end
    end
    f.metas = {}
    -- lua:2124: the meta button's Label is another title; lua:2170-2214: each text criterion's Name is its text
    -- when completed, else "- " and its text, on the pooled frames in objectivesFrame.criterias
    _G.AchievementObjectives_DisplayCriteria = function(objectivesFrame)
      for button, title in pairs(f.metas) do button.Label.text = title end
      if objectivesFrame then
        objectivesFrame.criterias = objectivesFrame.criterias or {}
        for i, c in ipairs(f.criteria or {}) do
          local criterion = objectivesFrame.criterias[i] or { Name = fs("") }
          criterion.Name.text = c.completed and c.text or ("- " .. c.text)
          objectivesFrame.criterias[i] = criterion
        end
      end
    end
    return f
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    SS = WFJ.SurfaceState
    H.uiSetup(WFJ, ROWS)
    loadAchievementUI()
    frames = addClientTableFrames()
    assert.is_true(WFJ.Achievement.init())
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    for _, name in ipairs(NAMES) do _G[name] = nil end
  end)

  local function achievementRow(data)
    local row = CreateFrame("Button")
    row.Label, row.Description, row.Reward = fs(), fs(), fs()
    _G.AchievementFrameAchievements.ScrollBox:initFrame(row, data, function(r, d)
      r.Label.text, r.Description.text, r.Reward.text = d.name, d.description, d.reward or ""
    end)
    return row
  end

  it("an achievement row's title, description and reward are Japanese; Alt shows English; a name stays", function()
    local row = achievementRow({ name = "Level 10", description = "Reach level 10.",
      reward = "Reward: Tabard of the Explorer" })
    assert.are.equal("レベル10", row.Label:GetText())
    assert.are.equal("レベル10に到達する。", row.Description:GetText())
    assert.are.equal("報酬: 探検家のタバード", row.Reward:GetText())
    alt(true)
    assert.are.equal("Level 10", row.Label:GetText())
    assert.are.equal("Reach level 10.", row.Description:GetText())
    alt(false)
    assert.are.equal("レベル10", row.Label:GetText())
    -- reused for an achievement no row has, whose name is a dictionary word and a category's English
    _G.AchievementFrameAchievements.ScrollBox:initFrame(row, { name = "General", description = "Close" },
      function(r, d) r.Label.text, r.Description.text, r.Reward.text = d.name, d.description, "" end)
    assert.are.equal("General", row.Label:GetText())
    assert.are.equal("Close", row.Description:GetText())
    assert.is_true(unrecorded(row.Label))
    assert.is_true(unrecorded(row.Description))
  end)

  it("a category row: an AchievementCategory row and the Summary are Japanese; an achievement title is not",
    function()
      local general = C.category(1, { id = 92, name = "General" })
      local summary = C.category(2, { id = "summary" })
      local title = C.category(3, { id = 7, name = "Level 10" }) -- an AchievementTitle English: not a category
      assert.are.equal("一般", general.Button.Label:GetText())
      assert.are.equal("概要", summary.Button.Label:GetText())
      assert.are.equal("Level 10", title.Button.Label:GetText())
      alt(true)
      assert.are.equal("General", general.Button.Label:GetText())
      alt(false)
      assert.are.equal("一般", general.Button.Label:GetText())
    end)

  it("a statistics row: a header's Title is a category, a statistic's text a title; a pooled row switches kind",
    function()
      local header = CreateFrame("Button")
      header.isHeader, header.Title, header.Text = true, fs("Character"), fs("")
      frames.stats:initFrame(header, {})
      assert.are.equal("キャラクター", header.Title:GetText())
      local stat = CreateFrame("Button")
      stat.Title, stat.Text = fs(""), fs("Total deaths")
      frames.stats:initFrame(stat, {})
      assert.are.equal("死亡回数", stat.Text:GetText())
      local other = CreateFrame("Button")
      other.Title, other.Text = fs(""), fs("Character") -- a category's English as a statistic's name: not a title
      frames.stats:initFrame(other, {})
      assert.are.equal("Character", other.Text:GetText())
      alt(true)
      assert.are.equal("Total deaths", stat.Text:GetText())
      alt(false)
      -- the header row reused for a statistic: its title record is dropped, the text is matched as a title
      header.isHeader = false
      header.Text.text = "Total deaths"
      frames.stats:initFrame(header, {})
      assert.are.equal("死亡回数", header.Text:GetText())
      assert.is_true(unrecorded(header.Title))
      -- a statistic with no Text FontString: the button's own text (the comparison view's rows)
      local button = Stub.button(nil, "Total deaths")
      frames.compareStats:initFrame(button, {})
      assert.are.equal("死亡回数", button:GetText())
    end)

  it("a comparison row's player side: title and description are Japanese", function()
    local row = CreateFrame("Button")
    row.Player = { Label = fs("Level 10"), Description = fs("Reach level 10.") }
    frames.compareRows:initFrame(row, {})
    assert.are.equal("レベル10", row.Player.Label:GetText())
    assert.are.equal("レベル10に到達する。", row.Player.Description:GetText())
  end)

  it("the summary's category bars: an AchievementCategory row is Japanese, another name stays", function()
    _G.AchievementFrameSummary_UpdateSummaryProgressBars()
    assert.are.equal("一般", _G.AchievementFrameSummaryCategoriesCategory1.Label:GetText())
    assert.are.equal("Quests", _G.AchievementFrameSummaryCategoriesCategory2.Label:GetText())
    alt(true)
    assert.are.equal("General", _G.AchievementFrameSummaryCategoriesCategory1.Label:GetText())
    alt(false)
  end)

  it("a meta criteria button's Label is an achievement title after AchievementObjectives_DisplayCriteria",
    function()
      local meta, other = CreateFrame("Button"), CreateFrame("Button")
      meta.Label, other.Label = fs(""), fs("")
      _G.AchievementButton_LocalizeMetaAchievement(meta)
      _G.AchievementButton_LocalizeMetaAchievement(other)
      frames.metas[meta], frames.metas[other] = "Level 10", "General"
      _G.AchievementObjectives_DisplayCriteria()
      assert.are.equal("レベル10", meta.Label:GetText())
      assert.are.equal("General", other.Label:GetText()) -- a category's English: not a title
    end)

  it("a text criterion is a CriteriaText row's Japanese, open or completed; Alt shows English; others stay",
    function()
      local objectives = CreateFrame("Frame")
      frames.criteria = { { text = "Explore Alterac Mountains" },
        { text = "Explore Alterac Mountains", completed = true },
        { text = "Hogger" }, { text = "Level 10", completed = true }, { text = "General" } }
      _G.AchievementObjectives_DisplayCriteria(objectives, 6)
      local c = objectives.criterias
      assert.are.equal("- アルターク山脈を探検する", c[1].Name:GetText())
      assert.are.equal("アルターク山脈を探検する", c[2].Name:GetText())
      assert.are.equal("- Hogger", c[3].Name:GetText()) -- a name: no row
      assert.are.equal("Level 10", c[4].Name:GetText()) -- an AchievementTitle row: not a criterion's family
      assert.are.equal("- General", c[5].Name:GetText())
      assert.is_true(unrecorded(c[3].Name))
      alt(true)
      assert.are.equal("- Explore Alterac Mountains", c[1].Name:GetText())
      assert.are.equal("Explore Alterac Mountains", c[2].Name:GetText())
      alt(false)
      assert.are.equal("- アルターク山脈を探検する", c[1].Name:GetText())
      _G.AchievementObjectives_DisplayCriteria(objectives, 6) -- shown again: still ours
      assert.are.equal("- アルターク山脈を探検する", c[1].Name:GetText())
      frames.criteria = { { text = "Hogger" } } -- the pooled frame reused for a name
      _G.AchievementObjectives_DisplayCriteria(objectives, 7)
      assert.are.equal("- Hogger", c[1].Name:GetText())
    end)
end)
