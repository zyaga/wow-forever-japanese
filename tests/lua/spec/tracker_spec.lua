-- Surface "tracker": UI/Tracker.lua over an objective tracker replayed from the camelot load set of
-- blizzard_objectivetracker: module headers (blizzard_objectivetrackermodule.lua:47–52, 121–123; the bonus module's
-- relabel, blizzard_bonusobjectivetracker.lua:433–475; the scenario module's direct write,
-- blizzard_scenarioobjectivetracker.lua:254–266), auto-quest popups (blizzard_autoquestpopuptracker.lua:13–101), the
-- scenario stage block (:525–640), the rewards toast (blizzard_objectivetrackermanager.lua:110–123,
-- blizzard_objectivetrackershared.lua:233–234), the top banner (blizzard_bonusobjectivetracker.lua:718–725) and the
-- two help tooltips. Quest, scenario, stage and zone names stay English. Client writes go to `fs.text`.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/Tracker.lua"

-- Forever GlobalStrings (build 1.60.1.69913) → a test Japanese
local UI = {
  TRACKER_HEADER_SCENARIO = { "Scenario", "シナリオ" }, TRACKER_HEADER_DUNGEON = { "Dungeon", "ダンジョン" },
  TRACKER_HEADER_PROVINGGROUNDS = { "Proving Grounds", "試練の場" },
  TRACKER_HEADER_CAMPAIGN_QUESTS = { "Campaign", "キャンペーン" },
  ADVENTURE_TRACKING_MODULE_HEADER_TEXT = { "Collections", "コレクション" },
  TRACKER_HEADER_ACHIEVEMENTS = { "Achievements", "アチーブメント" },
  PROFESSIONS_TRACKER_HEADER_PROFESSION = { "Profession", "専門技術" },
  TRACKER_HEADER_BONUS_OBJECTIVES = { "Bonus Objectives", "ボーナス目標" },
  TRACKER_HEADER_OBJECTIVE = { "Objectives", "目標" },
  TRACKER_HEADER_WORLD_QUESTS = { "World Quests", "ワールドクエスト" },
  QUEST_WATCH_POPUP_CLICK_TO_COMPLETE = { "Click to complete quest", "クリックでクエスト完了" },
  QUEST_WATCH_POPUP_CLICK_TO_COMPLETE_TASK = { "Click to complete", "クリックで完了" },
  QUEST_WATCH_POPUP_QUEST_DISCOVERED = { "Quest Discovered!", "クエスト発見！" },
  QUEST_WATCH_POPUP_CLICK_TO_VIEW = { "Click to view quest", "クリックでクエストを見る" },
  SCENARIO_STAGE = { "Stage %d", "ステージ%d" }, SCENARIO_STAGE_FINAL = { "Final Stage", "最終ステージ" },
  SCENARIO_STAGE_STATUS = { "Stage %d of %d", "ステージ %d / %d" },
  STAGE_COMPLETE = { "Stage Complete", "ステージ完了" }, DUNGEON_COMPLETED = { "Dungeon Complete!", "ダンジョン完了！" },
  SCENARIO_COMPLETED_GENERIC = { "Completed!", "完了！" },
  PROVING_GROUNDS_WAVE = { "Wave:", "ウェーブ:" }, PROVING_GROUNDS_SCORE = { "Score:", "スコア:" },
  REWARDS = { "Rewards", "報酬" }, COLLECTED = { "Collected", "収集済み" },
  WORLD_QUEST_BANNER = { "World Quest", "ワールドクエスト" }, BONUS_OBJECTIVE_BANNER = { "Bonus Objective", "ボーナス目標" },
  RETRIEVING_DATA = { "Retrieving data", "データを取得中" },
  WORLD_QUEST_TOOLTIP_DESCRIPTION = { "Completing this world quest will reward you with:",
    "このワールドクエストを完了すると次の報酬を得られます:" },
  BONUS_OBJECTIVE_TOOLTIP_DESCRIPTION = { "Completing this bonus objective will reward you with:",
    "このボーナス目標を完了すると次の報酬を得られます:" },
  TOOLTIP_TRACKER_FIND_GROUP_BUTTON = { "Find Group", "グループを探す" },
  -- owned by UI/QuestMap (never shown by this surface), and a word a name can collide with
  TRACKER_HEADER_QUESTS = { "Quests", "クエスト" },
}
local function en(key) return UI[key][1] end
local function ja(key) return UI[key][2] end

local POPUP, FIND_GROUP = "AutoQuestPopUpBlockTemplate", "QuestObjectiveFindGroupButtonTemplate"

-- An ObjectiveTrackerModuleTemplate frame: Header.Text, SetHeader, usedBlocks by template, right-edge frames.
local function module(name, headerText)
  local m = CreateFrame("Frame", name)
  m.Header = CreateFrame("Frame")
  m.Header.Text = Stub.fontString("")
  m.usedBlocks = {}
  function m.SetHeader(self, text) self.Header.Text.text = text end
  function m.GetBlock(self, id, template)
    template = template or "Block"
    self.usedBlocks[template] = self.usedBlocks[template] or {}
    local block = self.usedBlocks[template][id]
    if not block then
      block = CreateFrame("Frame")
      block.id, block.template = id, template
      self.usedBlocks[template][id] = block
    end
    return block
  end
  function m.GetExistingBlock(self, id, template)
    return self.usedBlocks[template or "Block"] and self.usedBlocks[template or "Block"][id] or nil
  end
  function m.GetRightEdgeFrame(self, settings, id)
    self.usedRightEdgeFrames = self.usedRightEdgeFrames or {}
    local key = settings.frameKey .. id
    local frame = self.usedRightEdgeFrames[key]
    if not frame then
      frame = CreateFrame("Button")
      frame.template = settings.template
      self.usedRightEdgeFrames[key] = frame
    end
    return frame
  end
  if headerText then m:SetHeader(headerText) end -- OnLoad (blizzard_objectivetrackermodule.lua:47–52)
  return m
end

local P = {} -- replayed client state: P.popups = { { id, type, title, task } }

local function questModule(name, headerText)
  local m = module(name, headerText)
  function m.AddAutoQuestObjectives(self)
    for _, p in ipairs(P.popups or {}) do
      local block = self:GetBlock(p.id .. p.type, POPUP)
      if not block.Contents then
        block.Contents = { TopText = Stub.fontString(""), BottomText = Stub.fontString(""),
          QuestName = Stub.fontString("") }
      end
      local c = block.Contents
      if p.type == "COMPLETE" then
        c.TopText.text = p.task and en("QUEST_WATCH_POPUP_CLICK_TO_COMPLETE_TASK")
          or en("QUEST_WATCH_POPUP_CLICK_TO_COMPLETE")
        c.BottomText.shown = false
      else
        c.TopText.text = en("QUEST_WATCH_POPUP_QUEST_DISCOVERED")
        c.BottomText.text = en("QUEST_WATCH_POPUP_CLICK_TO_VIEW")
      end
      c.QuestName.text = p.title
    end
  end
  return m
end

local function installTracker()
  CreateFrame("Frame", "ObjectiveTrackerFrame")
  questModule("QuestObjectiveTracker", en("TRACKER_HEADER_QUESTS"))
  questModule("CampaignQuestObjectiveTracker", en("TRACKER_HEADER_CAMPAIGN_QUESTS"))
  module("AdventureObjectiveTracker", en("ADVENTURE_TRACKING_MODULE_HEADER_TEXT"))
  module("AchievementObjectiveTracker", en("TRACKER_HEADER_ACHIEVEMENTS"))
  module("ProfessionsRecipeTracker", en("PROFESSIONS_TRACKER_HEADER_PROFESSION"))
  module("WorldQuestObjectiveTracker", en("TRACKER_HEADER_WORLD_QUESTS"))
  module("UIWidgetObjectiveTracker", "Dungeon") -- GetRealZoneText(): here a zone whose name is a dictionary word
  local bonus = module("BonusObjectiveTracker", en("TRACKER_HEADER_BONUS_OBJECTIVES"))
  function bonus.LayoutContents(self, asObjective)
    self:SetHeader(en(asObjective and "TRACKER_HEADER_OBJECTIVE" or "TRACKER_HEADER_BONUS_OBJECTIVES"))
  end

  local scenario = module("ScenarioObjectiveTracker", en("TRACKER_HEADER_SCENARIO"))
  function scenario.LayoutContents(self, kind, scenarioName)
    if kind == "proving" then self.Header.Text.text = en("TRACKER_HEADER_PROVINGGROUNDS")
    elseif kind == "dungeon" then self.Header.Text.text = en("TRACKER_HEADER_DUNGEON")
    else self.Header.Text.text = scenarioName end
  end
  local stage = CreateFrame("Frame")
  scenario.StageBlock = stage
  stage.Stage, stage.Name, stage.CompleteLabel = Stub.fontString(""), Stub.fontString(""),
    Stub.fontString(en("STAGE_COMPLETE"))
  function stage.UpdateStageBlock(self, suppress, current, stageName, numStages)
    if suppress then
      self.Stage.text, self.Name.text = stageName, ""
    else
      self.Stage.text = current == numStages and en("SCENARIO_STAGE_FINAL") or en("SCENARIO_STAGE"):format(current)
      self.Name.text = stageName
    end
  end
  function stage.SetupStageTransition(self, completed, dungeon)
    if completed then
      self.CompleteLabel.text = dungeon and en("DUNGEON_COMPLETED") or en("SCENARIO_COMPLETED_GENERIC")
    else
      self.CompleteLabel.text = en("STAGE_COMPLETE")
    end
  end
  function stage.UpdateFindGroupButton(self, has)
    if has and not self.findGroupButton then self.findGroupButton = CreateFrame("Button") end
  end
  local proving = CreateFrame("Frame")
  scenario.ProvingGroundsBlock = proving
  proving.WaveLabel, proving.ScoreLabel = Stub.fontString(en("PROVING_GROUNDS_WAVE")),
    Stub.fontString(en("PROVING_GROUNDS_SCORE"))
  proving.Wave = Stub.fontString("0")

  local rewards = CreateFrame("Frame", "ScenarioRewardsFrame")
  rewards.Header = Stub.fontString(en("REWARDS"))

  local banner = CreateFrame("Frame", "ObjectiveTrackerTopBannerFrame")
  banner.Title, banner.Subtitle = Stub.fontString(""), Stub.fontString("")
  function banner.PlayBanner(self, title, world)
    self.Title.text = title
    self.Subtitle.text = world and en("WORLD_QUEST_BANNER") or en("BONUS_OBJECTIVE_BANNER")
  end

  local toasts = {}
  _G.ObjectiveTrackerManager = { name = "ObjectiveTrackerManager", rewardsToastPool = {
    EnumerateActive = function()
      local i = 0
      return function() i = i + 1; return toasts[i] end
    end } }
  function _G.ObjectiveTrackerManager.ShowRewardsToast(_, headerText, label)
    toasts[#toasts + 1] = { Header = Stub.fontString(headerText or en("REWARDS")), Label = Stub.fontString(label) }
  end
  return toasts
end

local GLOBALS = { "ObjectiveTrackerFrame", "QuestObjectiveTracker", "CampaignQuestObjectiveTracker",
  "AdventureObjectiveTracker", "AchievementObjectiveTracker", "ProfessionsRecipeTracker", "WorldQuestObjectiveTracker",
  "UIWidgetObjectiveTracker", "BonusObjectiveTracker", "ScenarioObjectiveTracker", "ScenarioRewardsFrame",
  "ObjectiveTrackerTopBannerFrame", "ObjectiveTrackerManager" }

describe("the objective tracker's other modules on Forever (surface tracker)", function()
  local WFJ, SS, toasts

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end
  local function header(name) return _G[name].Header.Text end
  local function unrecorded(widget)
    for _, bucket in pairs(SS.surfaces()) do
      for _, rec in pairs(bucket) do if rec.fs == widget then return false end end
    end
    return true
  end
  local function left(i) return _G["GameTooltipTextLeft" .. i] end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    SS = WFJ.SurfaceState
    H.uiSetup(WFJ, UI)
    P.popups = {}
    toasts = installTracker()
    assert.is_true(WFJ.Tracker.init())
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    for _, name in ipairs(GLOBALS) do _G[name] = nil end
  end)

  it("module headers written before the addon loaded translate; QuestMap's header and a zone name do not", function()
    assert.are.equal(ja("TRACKER_HEADER_CAMPAIGN_QUESTS"), header("CampaignQuestObjectiveTracker"):GetText())
    assert.are.equal(ja("ADVENTURE_TRACKING_MODULE_HEADER_TEXT"), header("AdventureObjectiveTracker"):GetText())
    assert.are.equal(ja("TRACKER_HEADER_ACHIEVEMENTS"), header("AchievementObjectiveTracker"):GetText())
    assert.are.equal(ja("PROFESSIONS_TRACKER_HEADER_PROFESSION"), header("ProfessionsRecipeTracker"):GetText())
    assert.are.equal(ja("TRACKER_HEADER_WORLD_QUESTS"), header("WorldQuestObjectiveTracker"):GetText())
    assert.are.equal(ja("TRACKER_HEADER_BONUS_OBJECTIVES"), header("BonusObjectiveTracker"):GetText())
    assert.are.equal(ja("TRACKER_HEADER_SCENARIO"), header("ScenarioObjectiveTracker"):GetText())
    -- UI/QuestMap owns the quest module's header: this surface leaves it alone
    assert.are.equal("Quests", header("QuestObjectiveTracker"):GetText())
    assert.is_true(unrecorded(header("QuestObjectiveTracker")))
    -- the widget module's header is a zone name, here one that is also a dictionary word
    assert.are.equal("Dungeon", header("UIWidgetObjectiveTracker"):GetText())
    assert.is_true(unrecorded(header("UIWidgetObjectiveTracker")))
    alt(true)
    assert.are.equal("Campaign", header("CampaignQuestObjectiveTracker"):GetText())
    alt(false)
    assert.are.equal(ja("TRACKER_HEADER_CAMPAIGN_QUESTS"), header("CampaignQuestObjectiveTracker"):GetText())
  end)

  it("the bonus module's relabel and the scenario module's direct write are followed; a scenario name stays English",
    function()
      _G.BonusObjectiveTracker:LayoutContents(true)
      assert.are.equal(ja("TRACKER_HEADER_OBJECTIVE"), header("BonusObjectiveTracker"):GetText())
      _G.BonusObjectiveTracker:LayoutContents(false)
      assert.are.equal(ja("TRACKER_HEADER_BONUS_OBJECTIVES"), header("BonusObjectiveTracker"):GetText())
      _G.ScenarioObjectiveTracker:LayoutContents("dungeon")
      assert.are.equal(ja("TRACKER_HEADER_DUNGEON"), header("ScenarioObjectiveTracker"):GetText())
      _G.ScenarioObjectiveTracker:LayoutContents("proving")
      assert.are.equal(ja("TRACKER_HEADER_PROVINGGROUNDS"), header("ScenarioObjectiveTracker"):GetText())
      -- a scenario's name, here one that is another module's dictionary word
      _G.ScenarioObjectiveTracker:LayoutContents("named", "Achievements")
      assert.are.equal("Achievements", header("ScenarioObjectiveTracker"):GetText())
      assert.is_true(unrecorded(header("ScenarioObjectiveTracker")))
    end)

  it("auto-quest popups: the two fixed lines translate, the quest title never; a reused block follows its new text",
    function()
      P.popups = { { id = 101, type = "OFFER", title = "Rewards" } } -- a quest whose title is a dictionary word
      _G.QuestObjectiveTracker:AddAutoQuestObjectives()
      local c = _G.QuestObjectiveTracker.usedBlocks[POPUP]["101OFFER"].Contents
      assert.are.equal(ja("QUEST_WATCH_POPUP_QUEST_DISCOVERED"), c.TopText:GetText())
      assert.are.equal(ja("QUEST_WATCH_POPUP_CLICK_TO_VIEW"), c.BottomText:GetText())
      assert.are.equal("Rewards", c.QuestName:GetText())
      assert.is_true(unrecorded(c.QuestName))
      -- the campaign module shares the mixin
      P.popups = { { id = 7, type = "COMPLETE", title = "The Missing Diplomat", task = true } }
      _G.CampaignQuestObjectiveTracker:AddAutoQuestObjectives()
      local cc = _G.CampaignQuestObjectiveTracker.usedBlocks[POPUP]["7COMPLETE"].Contents
      assert.are.equal(ja("QUEST_WATCH_POPUP_CLICK_TO_COMPLETE_TASK"), cc.TopText:GetText())
      assert.are.equal("The Missing Diplomat", cc.QuestName:GetText())
      -- the client rewrites the same widget
      cc.TopText.text = en("QUEST_WATCH_POPUP_CLICK_TO_COMPLETE")
      WFJ.Tracker.onAutoQuestPopups(_G.CampaignQuestObjectiveTracker)
      assert.are.equal(ja("QUEST_WATCH_POPUP_CLICK_TO_COMPLETE"), cc.TopText:GetText())
    end)

  it("the scenario stage block: stage number and completion labels translate; stage names stay English", function()
    local stage = _G.ScenarioObjectiveTracker.StageBlock
    stage:UpdateStageBlock(false, 2, "Rewards", 3)
    assert.are.equal("ステージ2", stage.Stage:GetText())
    assert.are.equal("Rewards", stage.Name:GetText()) -- the stage's name, a dictionary word here
    assert.is_true(unrecorded(stage.Name))
    stage:UpdateStageBlock(false, 3, "The End", 3)
    assert.are.equal(ja("SCENARIO_STAGE_FINAL"), stage.Stage:GetText())
    stage:UpdateStageBlock(true, 1, "Rewards", 3) -- stage text suppressed: Stage holds the stage's name
    assert.are.equal("Rewards", stage.Stage:GetText())
    assert.is_true(unrecorded(stage.Stage))
    assert.are.equal(ja("STAGE_COMPLETE"), stage.CompleteLabel:GetText())
    stage:SetupStageTransition(true, true)
    assert.are.equal(ja("DUNGEON_COMPLETED"), stage.CompleteLabel:GetText())
    stage:SetupStageTransition(true, false)
    assert.are.equal(ja("SCENARIO_COMPLETED_GENERIC"), stage.CompleteLabel:GetText())
    local proving = _G.ScenarioObjectiveTracker.ProvingGroundsBlock
    assert.are.equal(ja("PROVING_GROUNDS_WAVE"), proving.WaveLabel:GetText())
    assert.are.equal(ja("PROVING_GROUNDS_SCORE"), proving.ScoreLabel:GetText())
    assert.are.equal("0", proving.Wave:GetText())
    assert.are.equal(ja("REWARDS"), _G.ScenarioRewardsFrame.Header:GetText())
  end)

  it("the rewards toast header and the top banner's subtitle translate; item and quest names do not", function()
    _G.ObjectiveTrackerManager:ShowRewardsToast(nil, "Collected") -- the reward label is an item name
    _G.ObjectiveTrackerManager:ShowRewardsToast(en("COLLECTED"), "Swift Brown Steed")
    _G.ObjectiveTrackerManager:ShowRewardsToast("Dungeon", "x") -- a caller's own header that is not a toast word
    assert.are.equal(ja("REWARDS"), toasts[1].Header:GetText())
    assert.are.equal("Collected", toasts[1].Label:GetText())
    assert.is_true(unrecorded(toasts[1].Label))
    assert.are.equal(ja("COLLECTED"), toasts[2].Header:GetText())
    assert.are.equal("Dungeon", toasts[3].Header:GetText())
    local banner = _G.ObjectiveTrackerTopBannerFrame
    banner:PlayBanner("World Quest", true) -- a quest titled like the subtitle word
    assert.are.equal(ja("WORLD_QUEST_BANNER"), banner.Subtitle:GetText())
    assert.are.equal("World Quest", banner.Title:GetText())
    assert.is_true(unrecorded(banner.Title))
    banner:PlayBanner("Clear the Camp", false)
    assert.are.equal(ja("BONUS_OBJECTIVE_BANNER"), banner.Subtitle:GetText())
  end)

  it("help tooltips: a task block's rewards tooltip and the find-group buttons, each restricted to its keys", function()
    local tt = _G.GameTooltip
    local block = _G.BonusObjectiveTracker:GetBlock(55)
    assert.is_true(WFJ.HelpTooltip.registered(block))
    tt:SetOwner(block)
    tt:SetText(en("REWARDS"))
    tt:AddLine(en("BONUS_OBJECTIVE_TOOLTIP_DESCRIPTION"))
    tt:AddLine("Achievements") -- a reward's name that is a dictionary word elsewhere
    tt:Show()
    assert.are.equal(ja("REWARDS"), left(1):GetText())
    assert.are.equal(ja("BONUS_OBJECTIVE_TOOLTIP_DESCRIPTION"), left(2):GetText())
    assert.are.equal("Achievements", left(3):GetText())
    tt:Hide()

    local eye = _G.QuestObjectiveTracker:GetRightEdgeFrame({ frameKey = "FindGroup", template = FIND_GROUP }, 9)
    local item = _G.QuestObjectiveTracker:GetRightEdgeFrame(
      { frameKey = "Item", template = "QuestObjectiveItemButtonTemplate" }, 9)
    assert.is_true(WFJ.HelpTooltip.registered(eye))
    assert.is_false(WFJ.HelpTooltip.registered(item))
    tt:SetOwner(eye)
    tt:ClearLines() -- the client's SetOwner clears the tooltip
    tt:AddLine(en("TOOLTIP_TRACKER_FIND_GROUP_BUTTON"))
    tt:Show()
    assert.are.equal(ja("TOOLTIP_TRACKER_FIND_GROUP_BUTTON"), left(1):GetText())
    tt:Hide()

    local stage = _G.ScenarioObjectiveTracker.StageBlock
    stage:UpdateFindGroupButton(true)
    assert.is_true(WFJ.HelpTooltip.registered(stage.findGroupButton))
    tt:SetOwner(stage)
    tt:SetText(en("SCENARIO_STAGE_STATUS"):format(1, 3))
    tt:AddLine("Rewards") -- the stage's name
    tt:Show()
    assert.are.equal("ステージ 1 / 3", left(1):GetText())
    assert.are.equal("Rewards", left(2):GetText())
  end)

  it("hooks install once", function()
    assert.is_false(WFJ.Tracker.init())
    assert.are.equal(1, #Stub.hooks["BonusObjectiveTracker:SetHeader"])
    assert.are.equal(1, #Stub.hooks["ObjectiveTrackerManager:ShowRewardsToast"])
  end)
end)

describe("the tracker surface degrades", function()
  after_each(function()
    H.uiTeardown()
    for _, name in ipairs(GLOBALS) do _G[name] = nil end
  end)

  local function fresh()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    local WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    return WFJ
  end

  it("no ObjectiveTrackerFrame: init returns false and hooks nothing", function()
    local WFJ = fresh()
    local before = {}
    for label, list in pairs(Stub.hooks) do before[label] = #list end
    assert.has_no.errors(function() assert.is_false(WFJ.Tracker.init()) end)
    for label, list in pairs(Stub.hooks) do assert.are.equal(before[label], #list, label) end
  end)

  it("client names bound to the wrong type leave the English and raise nothing", function()
    local WFJ = fresh()
    installTracker()
    _G.CampaignQuestObjectiveTracker = "not a frame"
    _G.AchievementObjectiveTracker.Header = 7
    _G.AdventureObjectiveTracker.Header.Text = function() end
    _G.BonusObjectiveTracker.SetHeader = "nope"
    _G.ScenarioObjectiveTracker.StageBlock = true
    _G.ObjectiveTrackerManager = 12
    _G.ObjectiveTrackerTopBannerFrame.Subtitle = "x"
    _G.QuestObjectiveTracker.usedBlocks = { [POPUP] = { a = 1, b = { Contents = "c" },
      c = { Contents = { TopText = 3 } } } }
    _G.WorldQuestObjectiveTracker.usedRightEdgeFrames = { x = 5, y = { template = 4 } }
    assert.has_no.errors(function() assert.is_true(WFJ.Tracker.init()) end)
    assert.has_no.errors(function()
      WFJ.Tracker.onBanner()
      _G.QuestObjectiveTracker:AddAutoQuestObjectives()
      _G.WorldQuestObjectiveTracker:GetRightEdgeFrame({ frameKey = "k", template = FIND_GROUP }, 1)
      WFJ.Tracker.onRewardsToast(12)
      WFJ.Tracker.onTaskBlock({ GetExistingBlock = function() error("boom") end }, 1)
      WFJ.Tracker.onStageFindGroup(true)
    end)
    assert.are.equal("Achievements", UI.TRACKER_HEADER_ACHIEVEMENTS[1])
    -- the modules that still resolve are served
    assert.are.equal(ja("TRACKER_HEADER_WORLD_QUESTS"), _G.WorldQuestObjectiveTracker.Header.Text:GetText())
    assert.are.equal(ja("PROFESSIONS_TRACKER_HEADER_PROFESSION"), _G.ProfessionsRecipeTracker.Header.Text:GetText())
  end)
end)

-- ADR-042: a tracked achievement's title. AchievementObjectiveTrackerMixin:AddAchievement writes it with
-- block:SetHeader(achievementName) → HeaderText (blizzard_achievementobjectivetracker.lua:121–123); post-hooked on the
-- instance, the block found with GetExistingBlock(id), the AchievementTitle family only.
describe("the tracker's achievement titles", function()
  local WFJ

  local ROWS = {}
  for k, v in pairs(UI) do ROWS[k] = v end
  ROWS["AchievementTitle:6"] = { "Level 10", "レベル10" }
  ROWS["AchievementCategory:92"] = { "General", "一般" }

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, ROWS)
    installTracker()
    function _G.AchievementObjectiveTracker.AddAchievement(self, id, name) -- lua:115–123
      local block = self:GetBlock(id)
      block.HeaderText = block.HeaderText or Stub.fontString("")
      block.HeaderText.text = name
      return true
    end
    assert.is_true(WFJ.Tracker.init())
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    for _, name in ipairs(GLOBALS) do _G[name] = nil end
  end)

  it("an AchievementTitle row's title is Japanese; Alt shows English; the hook is placed once", function()
    assert.are.equal(1, #Stub.hooks["AchievementObjectiveTracker:AddAchievement"])
    local m = _G.AchievementObjectiveTracker
    m:AddAchievement(6, "Level 10")
    local block = m:GetExistingBlock(6)
    assert.are.equal("レベル10", block.HeaderText:GetText())
    alt(true)
    assert.are.equal("Level 10", block.HeaderText:GetText())
    alt(false)
    assert.are.equal("レベル10", block.HeaderText:GetText())
    m:AddAchievement(6, "Level 10") -- laid out again: still ours
    assert.are.equal("レベル10", block.HeaderText:GetText())
  end)

  it("a title no row has, a category's English and a dictionary word stay English", function()
    local m = _G.AchievementObjectiveTracker
    m:AddAchievement(7, "Explore Elwynn Forest")
    m:AddAchievement(92, "General")
    m:AddAchievement(8, "Achievements")
    assert.are.equal("Explore Elwynn Forest", m:GetExistingBlock(7).HeaderText:GetText())
    assert.are.equal("General", m:GetExistingBlock(92).HeaderText:GetText())
    assert.are.equal("Achievements", m:GetExistingBlock(8).HeaderText:GetText())
  end)

  it("a missing block or a module of the wrong shape raises nothing", function()
    assert.are.equal(0, WFJ.Tracker.onAchievement(_G.AchievementObjectiveTracker, 404))
    assert.are.equal(0, WFJ.Tracker.onAchievement({ GetExistingBlock = function() error("boom") end }, 1))
    assert.are.equal(0, WFJ.Tracker.onAchievement("x", 1))
  end)
end)

-- A tracked achievement's criteria lines: AddAchievement writes each with block:AddObjective(criteriaIndex,
-- criteriaString) → line.Text, kept in block.usedLines (blizzard_achievementobjectivetracker.lua:130-152;
-- blizzard_objectivetrackerblock.lua:79-98, 161-208). The CriteriaText family only.
describe("the tracker's achievement criteria", function()
  local WFJ

  local ROWS = {}
  for k, v in pairs(UI) do ROWS[k] = v end
  ROWS["AchievementTitle:6"] = { "Level 10", "レベル10" }
  ROWS["CriteriaText:121233"] = { "Explore Alterac Mountains", "アルターク山脈を探検する" }

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, ROWS)
    installTracker()
    -- lua:121-152: the title, then one objective line per shown criterion
    function _G.AchievementObjectiveTracker.AddAchievement(self, id, name, criteria)
      local block = self:GetBlock(id)
      block.HeaderText = block.HeaderText or Stub.fontString("")
      block.HeaderText.text = name
      block.usedLines = block.usedLines or {}
      for i, text in ipairs(criteria or {}) do
        local line = block.usedLines[i] or { Text = Stub.fontString("") }
        line.Text.text = text
        block.usedLines[i] = line
      end
      return true
    end
    assert.is_true(WFJ.Tracker.init())
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    for _, name in ipairs(GLOBALS) do _G[name] = nil end
  end)

  it("a CriteriaText row's line is Japanese; Alt shows English; a name, a count and another family stay", function()
    local m = _G.AchievementObjectiveTracker
    m:AddAchievement(6, "Level 10", { "Explore Alterac Mountains", "Hogger", "3/10 Explore Alterac Mountains",
      "Level 10", "Achievements" })
    local lines = m:GetExistingBlock(6).usedLines
    assert.are.equal("アルターク山脈を探検する", lines[1].Text:GetText())
    assert.are.equal("Hogger", lines[2].Text:GetText()) -- a name: no row
    assert.are.equal("3/10 Explore Alterac Mountains", lines[3].Text:GetText()) -- a progress-bar criterion
    assert.are.equal("Level 10", lines[4].Text:GetText()) -- an AchievementTitle row: not this widget's family
    assert.are.equal("Achievements", lines[5].Text:GetText()) -- a dictionary word
    assert.are.equal("レベル10", m:GetExistingBlock(6).HeaderText:GetText())
    alt(true)
    assert.are.equal("Explore Alterac Mountains", lines[1].Text:GetText())
    alt(false)
    assert.are.equal("アルターク山脈を探検する", lines[1].Text:GetText())
    m:AddAchievement(6, "Level 10", { "Hogger" }) -- the line reused for a name: back to the client's text
    assert.are.equal("Hogger", lines[1].Text:GetText())
  end)
end)
