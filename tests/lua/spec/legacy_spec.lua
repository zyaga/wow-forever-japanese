-- UI/Legacy.lua over a LegacySystemFrame replayed from camelot
-- blizzard_legacysystem (stub_legacy.lua). The window title follows each page's SetTitle; challenge names, point
-- counters and the search boxes stay as the client wrote them; the surface waits for Blizzard_LegacySystem in either
-- load order and does nothing on a client without it.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local L = require("tests.lua.spec.stub_legacy")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/Achievement.lua" -- a challenge card uses Achievement.TEXT_FIELDS and textOnly
FILES[#FILES + 1] = "UI/Legacy.lua"

local UI = {
  LEGACY_TRACK_FRAME_TITLE = { "Progress Track", "進行トラック" },
  LEGACY_CHALLENGE_FRAME_TITLE = { "Legacy Challenges", "レガシーチャレンジ" },
  LEGACY_TREE_FRAME_TITLE = { "Legacy Tree", "レガシーツリー" },
  LEGACY_REWARD_TRACK_TAB_TOOLTIP = { "Legacy Rewards", "レガシー報酬" },
  LEGACY_CHALLENGE_TAB_TOOLTIP = { "Legacy Challenges", "レガシーチャレンジ" },
  LEGACY_TREE_TAB_TOOLTIP = { "Legacy Trees", "レガシーツリー" },
  LEGACY_REWARD_TRACK_POINTS = { "Legacy Points", "レガシーポイント" },
  LEGACY_NO_CHALLENGES = { "There are no results with your current filters.", "現在のフィルターに一致する結果はありません。" },
  LEGACY_POINTS_AMOUNT = { "%d", "%d" },
  LEGACY_POINTS_AVAILABLE = { "Available points: %s", "使用可能ポイント: %s" },
  LEGACY_POINTS_CURR_MAX = { "Legacy Points %d / %d", "レガシーポイント %d / %d" },
  LEGACY_POINTS_SEASONAL_CAP = { "You can spend up to your current seasonal cap of %d Legacy Points in total.",
    "現在のシーズン上限である合計%dレガシーポイントまで使用できます。" },
  LEGACY_TREE_PROFESSIONS = { "Professions", "専門技能" }, LEGACY_TREE_ADVENTURE = { "Adventure", "冒険" },
  LEGACY_TREE_PROGRESSION = { "Resourcefulness", "機知" },
  TRACK_ACHIEVEMENT = { "Track", "追跡" }, SEARCH = { "Search", "検索" }, FILTER = { "Filter", "フィルター" },
  TALENT_FRAME_APPLY_BUTTON_TEXT = { "Apply Changes", "変更を適用" },
  TALENT_FRAME_DISCARD_CHANGES_BUTTON_TOOLTIP = { "Undo Pending Changes", "保留中の変更を元に戻す" },
  CLOSE = { "Close", "閉じる" }, -- a word a challenge's name may happen to be
}

local STATE = { points = 11, max = 40, available = 3, cap = 25 }

describe("the Legacy window on Forever", function()
  local WFJ, SS

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  local function unrecorded(widget)
    for _, bucket in pairs(SS.surfaces()) do
      for _, rec in pairs(bucket) do
        if rec.fs == widget or (type(rec.fs) == "table" and rec.fs.button == widget) then return false end
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
      L.load(STATE)
      assert.is_true(WFJ.Legacy.init())
    else
      assert.is_false(WFJ.Legacy.init()) -- waits for the addon
      L.load(STATE)
      assert.are.equal(1, WFJ.LoadOnDemand.loaded(L.ADDON))
    end
  end

  local function title() return _G.LegacySystemFrame.TitleContainer.TitleText:GetText() end

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    L.unload()
  end)

  for _, order in ipairs({ { true, "loaded before the addon" }, { false, "loaded on demand" } }) do
    describe("Blizzard_LegacySystem " .. order[2], function()
      before_each(function() setup(order[1]) end)

      it("the title is Japanese, follows each page's SetTitle, and keeps it after a second SetTitle", function()
        local f = _G.LegacySystemFrame
        assert.are.equal("進行トラック", title())
        f.ChallengesPage:Show()
        assert.are.equal("レガシーチャレンジ", title())
        f.TreePage:Show()
        assert.are.equal("レガシーツリー", title())
        f:SetTitle(_G.LEGACY_TREE_FRAME_TITLE)
        assert.are.equal("レガシーツリー", title())
        alt(true)
        assert.are.equal("Legacy Tree", title())
        alt(false)
        assert.are.equal("レガシーツリー", title())
        f:SetTitle("Close") -- not one of the three titles: left alone
        assert.are.equal("Close", title())
      end)

      it("static labels, the filter button and the search placeholders are Japanese", function()
        local f = _G.LegacySystemFrame
        local list, panel = f.ChallengesPage.CategoryList, f.TreePage.LegacyTreeTraitPanel
        assert.are.equal("レガシーポイント", f.RewardTrackPage.PointsLabel:GetText())
        assert.are.equal("現在のフィルターに一致する結果はありません。", list.NoResultsText:GetText())
        assert.are.equal("検索", list.SearchBox.Instructions:GetText())
        assert.are.equal("検索", panel.SearchBox.Instructions:GetText())
        assert.are.equal("フィルター", list.FilterDropdown.Text:GetText())
        list.FilterDropdown:UpdateText()
        assert.are.equal("フィルター", list.FilterDropdown.Text:GetText())
        assert.are.equal("変更を適用", panel.ApplyButton:GetText())
        alt(true)
        assert.are.equal("Legacy Points", f.RewardTrackPage.PointsLabel:GetText())
        assert.are.equal("Apply Changes", panel.ApplyButton:GetText())
        alt(false)
      end)

      it("the writer-hooked texts follow their writers; the point counters are left alone", function()
        local f = _G.LegacySystemFrame
        local panel, points = f.TreePage.LegacyTreeTraitPanel, f.TreePage.LegacyTreePointSummary
        local bar = f.ChallengesPage.LegacyChallengePointSummary.PointsBar
        assert.are.equal("専門技能", panel.SelectedTreeIcon.SelectedTreeLabel:GetText())
        panel:SelectTree(3)
        assert.are.equal("機知", panel.SelectedTreeIcon.SelectedTreeLabel:GetText())
        assert.are.equal("使用可能ポイント: 3", points.AvailablePointsLabel:GetText())
        -- the client refreshes the label through LegacySystem.UpdateCurrencyInfo, never through the frame's field
        L.currency = { points = 11, max = 40, available = 7, cap = 25 }
        _G.LegacySystem.UpdateCurrencyInfo()
        assert.are.equal("使用可能ポイント: 7", points.AvailablePointsLabel:GetText())
        assert.are.equal("レガシーポイント 11 / 40", bar.Text:GetText())
        bar:Update({ points = 12, max = 40 })
        assert.are.equal("レガシーポイント 12 / 40", bar.Text:GetText())
        assert.are.equal("11", f.RewardTrackPage.Points:GetText())
        assert.is_true(unrecorded(f.RewardTrackPage.Points))
        assert.is_true(unrecorded(panel.SpentPointsFrame.Text))
      end)

      it("a challenge card's Track label translates; its name and description never do, even on a reused card",
        function()
          local card = L.card(1, { name = "Close", description = "Close" })
          assert.are.equal("追跡", card.Tracked.Text:GetText())
          assert.are.equal("Close", card.Label:GetText())
          assert.are.equal("Close", card.Description:GetText())
          L.card(1, { name = "Track", description = "Track" })
          alt(true); alt(false)
          assert.are.equal("Track", card.Label:GetText())
          assert.is_true(unrecorded(card.Label))
          assert.is_true(unrecorded(card.Description))
        end)

      it("tab, tree button, point summary and undo tooltips are Japanese", function()
        local f = _G.LegacySystemFrame
        f.LegacyChallengeTab:OnEnter()
        assert.are.equal("レガシーチャレンジ", _G.GameTooltipTextLeft1:GetText())
        f.LegacyRewardTrackTab:OnEnter()
        assert.are.equal("レガシー報酬", _G.GameTooltipTextLeft1:GetText())
        f.TreePage.LegacyTreeSelectionPanel.treeButtons[2]:ShowTooltip()
        assert.are.equal("冒険", _G.GameTooltipTextLeft1:GetText())
        f.TreePage.LegacyTreePointSummary:OnEnter()
        assert.are.equal("現在のシーズン上限である合計25レガシーポイントまで使用できます。", _G.GameTooltipTextLeft1:GetText())
        f.TreePage.LegacyTreeTraitPanel.UndoButton:OnEnter()
        assert.are.equal("保留中の変更を元に戻す", _G.GameTooltipTextLeft1:GetText())
      end)

      it("tree buttons rebuilt by RefreshTreeButtons are registered again", function()
        local selection = _G.LegacySystemFrame.TreePage.LegacyTreeSelectionPanel
        selection:RefreshTreeButtons()
        selection.treeButtons[1]:ShowTooltip()
        assert.are.equal("専門技能", _G.GameTooltipTextLeft1:GetText())
      end)
    end)
  end

  it("hooks install once", function()
    setup(true)
    assert.is_false(WFJ.Legacy.setup())
    assert.are.equal(1, #Stub.hooks["LegacyTreeTraitPanel:SelectTree"])
    assert.are.equal(1, #Stub.hooks["LegacyTreePointSummary:RefreshText"])
    assert.are.equal(1, #Stub.hooks["LegacySystem:UpdateCurrencyInfo"])
    assert.are.equal(1, #Stub.hooks["PointsBar:Update"])
    assert.are.equal(1, #Stub.hooks["LegacySystemFrame:SetTitle"])
  end)

  it("a client name bound to the wrong type degrades to untouched English with no error", function()
    load()
    local f = L.load(STATE)
    f.TreePage.LegacyTreeTraitPanel.SelectTree = "not a function"
    f.TreePage.LegacyTreePointSummary = 42
    f.ChallengesPage.CategoryList.FilterDropdown = true
    f.ChallengesPage.DetailPane.ScrollBox = "nope"
    f.LegacyTreeTab = false
    f.TitleContainer = "nope"
    assert.has_no.errors(function() assert.is_true(WFJ.Legacy.init()) end)
    assert.are.equal("レガシーポイント", f.RewardTrackPage.PointsLabel:GetText()) -- the rest still works
    assert.is_nil(Stub.hooks["LegacyTreeTraitPanel:SelectTree"])
  end)

  it("a client without the Legacy window: init returns false and touches nothing", function()
    load()
    local before = 0
    for _ in pairs(Stub.hooks) do before = before + 1 end
    assert.is_false(WFJ.Legacy.init())
    Stub.loadedAddons[L.ADDON] = true -- the addon name loaded, but no LegacySystemFrame
    assert.is_false(WFJ.Legacy.init())
    assert.is_false(WFJ.Legacy.setup())
    local after = 0
    for _ in pairs(Stub.hooks) do after = after + 1 end
    assert.are.equal(before, after) -- nothing hooked
  end)
end)

-- A challenge card is an achievement row (ADR-042) (LegacyChallengeTemplate inherits AchievementTemplateMixin:
-- Init): its Label / Description are the achievement families' text, its Shield's reward line the AchievementReward
-- family; the category list's rows write the category name through GetTitleRegion (listtemplates.lua:58–61), the
-- AchievementCategory family only.
describe("the Legacy window's client-table text", function()
  local WFJ, list

  local ROWS = {}
  for k, v in pairs(UI) do ROWS[k] = v end
  ROWS["AchievementTitle:9001"] = { "Slay Ragnaros", "ラグナロスを倒す" }
  ROWS["AchievementDescription:9001"] = { "Defeat Ragnaros in Molten Core.", "モルテンコアでラグナロスを倒す。" }
  ROWS["AchievementReward:9001"] = { "Reward: 10 Legacy Points", "報酬: レガシーポイント10" }
  ROWS["AchievementCategory:15300"] = { "Dungeons", "ダンジョン" }

  local function alt(down) Stub.keys.alt = down; WFJ.Modifier.refresh() end
  local function fs(text) return Stub.fontString(text or "") end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, ROWS)
    local f = L.load(STATE)
    list = f.ChallengesPage.CategoryList
    list.ScrollBox = Stub.scrollBox() -- LegacyChallengeCategoryList's ScrollBox
    assert.is_true(WFJ.Legacy.init())
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    L.unload()
  end)

  local function card(data)
    local c = CreateFrame("Button")
    c.Label, c.Description = fs(), fs()
    c.Tracked = CreateFrame("CheckButton")
    c.Tracked.Text = fs(_G.TRACK_ACHIEVEMENT)
    c.Shield = CreateFrame("Button")
    _G.LegacySystemFrame.ChallengesPage.DetailPane.ScrollBox:initFrame(c, data, function(x, d)
      x.Label.text, x.Description.text = d.name, d.description
    end)
    return c
  end

  it("a challenge card's title and description are Japanese; Alt shows English; a name no row has stays", function()
    local c = card({ name = "Slay Ragnaros", description = "Defeat Ragnaros in Molten Core." })
    assert.are.equal("ラグナロスを倒す", c.Label:GetText())
    assert.are.equal("モルテンコアでラグナロスを倒す。", c.Description:GetText())
    assert.are.equal("追跡", c.Tracked.Text:GetText())
    alt(true)
    assert.are.equal("Slay Ragnaros", c.Label:GetText())
    alt(false)
    assert.are.equal("ラグナロスを倒す", c.Label:GetText())
    local other = card({ name = "Dungeons", description = "Close" }) -- a category and a dictionary word: not text
    assert.are.equal("Dungeons", other.Label:GetText())
    assert.are.equal("Close", other.Description:GetText())
  end)

  it("a card's shield tooltip shows the reward line in Japanese", function()
    local c = card({ name = "Slay Ragnaros", description = "" })
    local tt = _G.GameTooltip
    tt:SetOwner(c.Shield)
    tt:SetText("Slay Ragnaros")
    tt:AddLine("Reward: 10 Legacy Points")
    tt:Show()
    assert.are.equal("Slay Ragnaros", _G.GameTooltipTextLeft1:GetText()) -- only the reward family on this owner
    assert.are.equal("報酬: レガシーポイント10", _G.GameTooltipTextLeft2:GetText())
  end)

  it("a category row's title region is an AchievementCategory row's Japanese; another name stays", function()
    local function category(name)
      local row = CreateFrame("Button")
      row.title = fs("")
      function row.GetTitleRegion(self) return self.title end
      list.ScrollBox:initFrame(row, { name = name }, function(r, d) r.title.text = d.name end) -- SetHeaderText
      return row
    end
    local dungeons, title = category("Dungeons"), category("Slay Ragnaros")
    assert.are.equal("ダンジョン", dungeons.title:GetText())
    assert.are.equal("Slay Ragnaros", title.title:GetText())
    alt(true)
    assert.are.equal("Dungeons", dungeons.title:GetText())
    alt(false)
    assert.has_no.errors(function()
      WFJ.Legacy.onCategory(WFJ.Legacy, { GetTitleRegion = function() error("moved") end })
      WFJ.Legacy.onCategory("x")
    end)
  end)
end)

-- The challenge cards' criteria and the reward track. LegacyChallengeObjectives (blizzard_legacysystemtemplates.xml:
-- 155) is the one frame every card borrows: its Display acquires a pooled criterion per row and calls Init, which
-- writes Name (blizzard_legacychallengebutton.lua:102-111, 158-175), the CriteriaText family only; a counted criterion
-- shows a progress bar instead (showingProgress). The reward track's Init acquires the cards into Elements
-- (rewardtracktemplates.lua:38-63); TryInit calls each card's SetRewardName (:367-386, 493-495), the
-- RenownRewardName family; each card's tooltip (:517-549) the RenownRewardName / RenownRewardDescription families.
describe("the Legacy window's criteria and reward track", function()
  local WFJ, SS, objectives, track

  local ROWS = {}
  for k, v in pairs(UI) do ROWS[k] = v end
  ROWS["CriteriaText:121233"] = { "Explore Alterac Mountains", "アルターク山脈を探検する" }
  ROWS["AchievementTitle:9001"] = { "Slay Ragnaros", "ラグナロスを倒す" }
  ROWS["RenownRewardName:1832"] = { "Rank 1 Rewards", "ランク1の報酬" }
  ROWS["RenownRewardDescription:1832"] = { "Faction Tabard", "陣営タバード" }
  ROWS["RenownRewardToast:1832"] = { "Faction Tabard Unlocked", "陣営タバード解放" }
  ROWS["RENOWN_REWARD_MILESTONE_TOOLTIP_TITLE"] = { "Renown %d Rewards", "名声 %d の報酬" }

  local function alt(down) Stub.keys.alt = down; WFJ.Modifier.refresh() end
  local function fs(text) return Stub.fontString(text or "") end
  local function unrecorded(widget)
    for _, bucket in pairs(SS.surfaces()) do
      for _, rec in pairs(bucket) do if rec.fs == widget then return false end end
    end
    return true
  end

  -- LegacyChallengeObjectivesMixin:Display: rows are { text, showProgress }
  local function installObjectives()
    local o = CreateFrame("Frame", "LegacyChallengeObjectives")
    o.criteriaPool = L.pool(function() return { Name = fs(""), ProgressBar = { Text = fs("") } } end)
    function o.Display(self, rows)
      self.criteriaPool:ReleaseAll()
      for _, r in ipairs(rows) do
        local c = self.criteriaPool:Acquire()
        c.showingProgress = r[2] == true
        c.Name.text = r[1]
        if c.showingProgress then c.ProgressBar.Text.text = "3 / 10" end
      end
    end
    return o
  end

  -- RewardTrackFrameMixin:Init + RenownLevelMixin (SetInfo, TryInit → SetRewardName, RefreshTooltip)
  local function installTrack(f)
    local t = CreateFrame("Frame")
    t.pool = L.pool(function()
      local card = CreateFrame("Frame")
      card.RewardName, card.Level = fs(""), fs("")
      function card.SetInfo(c, info) c.info, c.init = info, false end
      function card.SetRewardName(c) c.RewardName.text = c.info.name end
      function card.TryInit(c)
        if c.init then return end
        c.init = true
        c.Level.text = tostring(c.info.level)
        c:SetRewardName()
      end
      function card.OnEnter(c)
        local tt = _G.GameTooltip
        tt:SetOwner(c)
        if c.info.count == 1 then
          tt:SetText(c.info.name)
          tt:AddLine(c.info.description)
        else
          tt:SetText(("Renown %d Rewards"):format(c.info.level))
          tt:AddLine("- " .. c.info.name)
        end
        tt:Show()
      end
      return card
    end)
    function t.Init(self, list)
      self.pool:ReleaseAll()
      self.Elements = {}
      for i, info in ipairs(list) do
        local card = self.pool:Acquire()
        card.index = i
        self.Elements[i] = card
        card:SetInfo(info)
      end
    end
    f.RewardTrackPage.LegacyRewardProgressFrame = t
    return t
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    SS = WFJ.SurfaceState
    H.uiSetup(WFJ, ROWS)
    local f = L.load(STATE)
    objectives = installObjectives()
    track = installTrack(f)
    assert.is_true(WFJ.Legacy.init())
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    _G.LegacyChallengeObjectives = nil
    L.unload()
  end)

  local function names()
    local out = {}
    for c in objectives.criteriaPool:EnumerateActive() do out[#out + 1] = c.Name:GetText() end
    return out
  end

  it("a criterion is a CriteriaText row's Japanese; Alt shows English; a name, a count and another family stay",
    function()
      objectives:Display({ { "Explore Alterac Mountains" }, { "Hogger" }, { "Explore Alterac Mountains", true },
        { "Slay Ragnaros" }, { "Track" } })
      assert.are.same({ "アルターク山脈を探検する", "Hogger", "Explore Alterac Mountains", "Slay Ragnaros", "Track" },
        names())
      local counted
      for c in objectives.criteriaPool:EnumerateActive() do if c.showingProgress then counted = c end end
      assert.is_true(unrecorded(counted.Name))
      assert.are.equal("3 / 10", counted.ProgressBar.Text:GetText())
      alt(true)
      assert.are.equal("Explore Alterac Mountains", names()[1])
      alt(false)
      assert.are.equal("アルターク山脈を探検する", names()[1])
      objectives:Display({ { "Hogger" } }) -- the pooled criterion reused for a name
      assert.are.same({ "Hogger" }, names())
    end)

  it("a reward card's name is a RenownRewardName row's Japanese; Alt shows English; other names stay", function()
    track:Init({ { level = 1, name = "Rank 1 Rewards", description = "Faction Tabard", count = 1 },
      { level = 2, name = "Gryphon Rider's Lance", description = "Faction Tabard", count = 1 },
      { level = 3, name = "Faction Tabard Unlocked", description = "x", count = 1 } })
    for _, card in ipairs(track.Elements) do card:TryInit() end
    local cards = track.Elements
    assert.are.equal("ランク1の報酬", cards[1].RewardName:GetText())
    assert.are.equal("Gryphon Rider's Lance", cards[2].RewardName:GetText()) -- an item's name: no row
    assert.are.equal("Faction Tabard Unlocked", cards[3].RewardName:GetText()) -- a RenownRewardToast row
    assert.are.equal("1", cards[1].Level:GetText())
    alt(true)
    assert.are.equal("Rank 1 Rewards", cards[1].RewardName:GetText())
    alt(false)
    assert.are.equal("ランク1の報酬", cards[1].RewardName:GetText())
    -- the track built again: the reused card gets new info and SetRewardName again
    track:Init({ { level = 1, name = "Gryphon Rider's Lance", description = "x", count = 1 } })
    track.Elements[1]:TryInit()
    assert.are.equal("Gryphon Rider's Lance", track.Elements[1].RewardName:GetText())
  end)

  it("a reward card's tooltip shows its name and description rows in Japanese; a name line stays", function()
    track:Init({ { level = 1, name = "Rank 1 Rewards", description = "Faction Tabard", count = 1 },
      { level = 4, name = "Gryphon Rider's Lance", count = 2 } })
    track.Elements[1]:OnEnter()
    assert.are.equal("ランク1の報酬", _G.GameTooltipTextLeft1:GetText())
    assert.are.equal("陣営タバード", _G.GameTooltipTextLeft2:GetText())
    track.Elements[2]:OnEnter()
    assert.are.equal("名声 4 の報酬", _G.GameTooltipTextLeft1:GetText())
    assert.are.equal("- Gryphon Rider's Lance", _G.GameTooltipTextLeft2:GetText())
  end)

  it("wrong shapes raise nothing", function()
    assert.has_no.errors(function()
      assert.are.equal(0, WFJ.Legacy.onObjectives({ criteriaPool = 1 }))
      assert.are.equal(0, WFJ.Legacy.onTrack({ Elements = "x" }))
      assert.are.equal(0, WFJ.Legacy.onRewardName("x"))
      WFJ.Legacy.onTrack({ Elements = { 1, { RewardName = 2 } } })
    end)
  end)
end)

