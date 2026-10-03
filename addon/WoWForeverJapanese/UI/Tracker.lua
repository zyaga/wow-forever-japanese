-- UI/Tracker.lua: the objective tracker's other modules on Forever (surface "tracker", area "ui", ADR-016,
-- ADR-029). Blizzard_ObjectiveTracker loads at login on camelot (blizzard_objectivetracker.toc: no LoadOnDemand, every
-- line ungated but the camelot quest override). ObjectiveTrackerManager:Init puts ELEVEN modules in
-- ObjectiveTrackerFrame (blizzard_objectivetracker/blizzard_objectivetrackermanager.lua:192–215); a module's header
-- shows only while the module has content. UI/QuestMap.lua already owns ObjectiveTrackerFrame.Header.Text,
-- QuestObjectiveTracker.Header.Text and the quest titles of the quest and campaign modules' blocks; this module never
-- touches those widgets. It owns:
--   module headers: ObjectiveTrackerModuleMixin:SetHeader writes self.Header.Text
--     (blizzard_objectivetrackermodule.lua:121–123), called as self:SetHeader from OnLoad (:47–52) with the module's
--     headerText, and by the bonus module after every layout
--     (blizzard_bonusobjectivetracker.lua:433, 460, 475: TRACKER_HEADER_BONUS_OBJECTIVES or
--     TRACKER_HEADER_OBJECTIVE): post-hooked on each instance. The scenario module writes Header.Text directly in
--     LayoutContents (blizzard_scenarioobjectivetracker.lua:254–266: TRACKER_HEADER_PROVINGGROUNDS,
--     TRACKER_HEADER_DUNGEON, else the scenario's or the zone's NAME), called as self:LayoutContents
--     (blizzard_objectivetrackermodule.lua:147): post-hooked too. Every header is restricted to its module's own keys,
--     so a scenario or zone name that is also a dictionary word stays English. headerText per module: scenario :45,
--     campaign blizzard_campaignquestobjectivetracker.lua:2, adventure blizzard_adventureobjectivetracker.lua:9,
--     achievement blizzard_achievementobjectivetracker.lua:2, professions blizzard_professionsrecipetracker.lua:10,
--     bonus blizzard_bonusobjectivetracker.lua:3, world quest blizzard_worldquestobjectivetracker.lua:2.
--     Not here: UIWidgetObjectiveTracker's header is GetRealZoneText() (blizzard_objectivetrackeruiwidgetcontainer.lua:
--     10, 28): a zone name, NEVER_TOUCH; the monthly-activities and endeavors modules can get no content on camelot
--     (their keys are excluded with the evidence).
--   auto-quest popups: AutoQuestPopupBlockMixin:Update writes Contents.TopText / BottomText
--     (blizzard_autoquestpopuptracker.lua:72–101) on blocks of the template "AutoQuestPopUpBlockTemplate", which the
--     quest and campaign modules build in AddAutoQuestObjectives (:13–32, called as self:… from
--     blizzard_questobjectivetracker.lua:392): post-hooked on both instances, walking usedBlocks[template]
--     (blizzard_objectivetrackermodule.lua:254–272). Contents.QuestName (the quest title) is never shown to Labels.
--   the scenario stage block: ScenarioObjectiveTrackerStageMixin:UpdateStageBlock writes Stage (SCENARIO_STAGE_FINAL,
--     SCENARIO_STAGE, or the stage NAME when the scenario suppresses stage text) and Name (:525–560);
--     SetupStageTransition writes CompleteLabel (STAGE_COMPLETE, DUNGEON_COMPLETED, SCENARIO_COMPLETED_GENERIC,
--     :618–640). Both are called on ScenarioObjectiveTracker.StageBlock by method. Its OnEnter tooltip's title is
--     SCENARIO_STAGE_STATUS (:492): the block is a help-tooltip owner restricted to that key. The proving-grounds
--     block's WaveLabel / ScoreLabel are static XML text (blizzard_scenarioobjectivetracker.xml:525, 540).
--     ScenarioRewardsFrame.Header is static XML text REWARDS (xml:647), shown on the frame's OnShow.
--   the rewards toast: ObjectiveTrackerManager:ShowRewardsToast (blizzard_objectivetrackermanager.lua:110–123)
--     acquires a pooled toast whose ShowRewards writes Header (headerText or REWARDS; the adventure module passes
--     COLLECTED, blizzard_objectivetrackershared.lua:233–234, blizzard_adventureobjectivetracker.lua:272):
--     post-hooked on the manager table, walking rewardsToastPool:EnumerateActive(). Reward labels (item names) are
--     never shown to Labels.
--   the top banner: ObjectiveTrackerTopBannerMixin:PlayBanner writes Title (the quest title) and Subtitle
--     (WORLD_QUEST_BANNER | BONUS_OBJECTIVE_BANNER, blizzard_bonusobjectivetracker.lua:718–725), called by
--     TopBannerManager as frame:PlayBanner(): post-hooked on ObjectiveTrackerTopBannerFrame (xml:227).
--   help tooltips: a bonus / world-quest block's rewards tooltip (BonusObjectiveBlockMixin:TryShowRewardsTooltip,
--     blizzard_bonusobjectivetracker.lua:654–676: RETRIEVING_DATA, REWARDS, WORLD_QUEST_TOOLTIP_DESCRIPTION |
--     BONUS_OBJECTIVE_TOOLTIP_DESCRIPTION, then reward lines, then Show) has the block as owner: each block is
--     registered after the module's GetBlock, restricted to those keys. The find-group eye button's tooltip
--     (TOOLTIP_TRACKER_FIND_GROUP_BUTTON, blizzard_objectivetrackershared.lua:198–203; the scenario stage's own button,
--     blizzard_scenarioobjectivetracker.lua:1170–1175, :586–600) is registered after GetRightEdgeFrame
--     (blizzard_objectivetrackermodule.lua:591–606) by its template, and after UpdateFindGroupButton.
--   a tracked achievement's title (ADR-042): AchievementObjectiveTrackerMixin:AddAchievement writes it with
--     block:SetHeader(achievementName) → HeaderText (blizzard_achievementobjectivetracker.lua:121–123;
--     blizzard_objectivetrackerblock.lua:155–159), called as self:AddAchievement from LayoutContents (:113):
--     post-hooked on the instance, the block found with GetExistingBlock(id), the AchievementTitle family only.
--     Its criteria lines are block:AddObjective(criteriaIndex, criteriaString) → line.Text (:130-152;
--     blizzard_objectivetrackerblock.lua:79-98, 161-208), kept in block.usedLines: each line's Text restricted to
--     the CriteriaText family. A progress-bar criterion is "<count> <description>", a meta criterion another
--     achievement's title, the overflow line "...", and a criterion with no shipped row (a name) has no key: all of
--     those stay as the client wrote them.
-- Out of scope: objective / progress lines, the block right-click menus (the menu system's), the challenge-mode
-- block (no keystone UI on camelot). Without ObjectiveTrackerFrame init returns false and touches nothing.
local _, WFJ = ...
local Tracker = {}
WFJ.Tracker = Tracker

local SURFACE = "tracker"
Tracker.SURFACE = SURFACE
local Compat = WFJ.Compat

local POPUP_TEMPLATE = "AutoQuestPopUpBlockTemplate"
local FIND_GROUP_TEMPLATE = "QuestObjectiveFindGroupButtonTemplate"

-- Names and the widgets QuestMap owns (its own list forbids nothing here; these are the tracker's name widgets).
Tracker.NEVER_TOUCH = { "UIWidgetObjectiveTracker.Header.Text", "ObjectiveTrackerTopBannerFrame.Title",
  "ScenarioObjectiveTracker.StageBlock.Name" }

-- module key → { the module's global, the keys its header may show }
local MODULES = {
  scenario = { "ScenarioObjectiveTracker",
    { "TRACKER_HEADER_SCENARIO", "TRACKER_HEADER_DUNGEON", "TRACKER_HEADER_PROVINGGROUNDS" } },
  campaign = { "CampaignQuestObjectiveTracker", { "TRACKER_HEADER_CAMPAIGN_QUESTS" } },
  adventure = { "AdventureObjectiveTracker", { "ADVENTURE_TRACKING_MODULE_HEADER_TEXT" } },
  achievement = { "AchievementObjectiveTracker", { "TRACKER_HEADER_ACHIEVEMENTS" } },
  professions = { "ProfessionsRecipeTracker", { "PROFESSIONS_TRACKER_HEADER_PROFESSION" } },
  bonus = { "BonusObjectiveTracker", { "TRACKER_HEADER_BONUS_OBJECTIVES", "TRACKER_HEADER_OBJECTIVE" } },
  worldquest = { "WorldQuestObjectiveTracker", { "TRACKER_HEADER_WORLD_QUESTS" } },
}
Tracker.MODULES = MODULES

local CANDIDATES = {
  frame = { "ObjectiveTrackerFrame" }, manager = { "ObjectiveTrackerManager" },
  quest = { "QuestObjectiveTracker" }, -- hooked for its popups and find-group buttons only (UI/QuestMap owns the rest)
  banner = { "ObjectiveTrackerTopBannerFrame" }, bannerSubtitle = { "ObjectiveTrackerTopBannerFrame.Subtitle" },
  stageBlock = { "ScenarioObjectiveTracker.StageBlock" }, stage = { "ScenarioObjectiveTracker.StageBlock.Stage" },
  complete = { "ScenarioObjectiveTracker.StageBlock.CompleteLabel" },
  provingBlock = { "ScenarioObjectiveTracker.ProvingGroundsBlock" },
  waveLabel = { "ScenarioObjectiveTracker.ProvingGroundsBlock.WaveLabel" },
  scoreLabel = { "ScenarioObjectiveTracker.ProvingGroundsBlock.ScoreLabel" },
  scenarioRewards = { "ScenarioRewardsFrame" }, scenarioRewardsHeader = { "ScenarioRewardsFrame.Header" },
}
for key, m in pairs(MODULES) do
  CANDIDATES[key] = { m[1] }
  CANDIDATES[key .. ".header"] = { m[1] .. ".Header.Text" }
end

local POPUP_TOP = { only = { "QUEST_WATCH_POPUP_CLICK_TO_COMPLETE", "QUEST_WATCH_POPUP_CLICK_TO_COMPLETE_TASK",
  "QUEST_WATCH_POPUP_QUEST_DISCOVERED" } }
local POPUP_BOTTOM = { only = { "QUEST_WATCH_POPUP_CLICK_TO_VIEW" } }
local STAGE = { only = { "SCENARIO_STAGE", "SCENARIO_STAGE_FINAL" } } -- never a stage name
local COMPLETE = { only = { "STAGE_COMPLETE", "DUNGEON_COMPLETED", "SCENARIO_COMPLETED_GENERIC" } }
local STAGE_TOOLTIP = { only = { "SCENARIO_STAGE_STATUS" } }
local WAVE = { only = { "PROVING_GROUNDS_WAVE" } }
local SCORE = { only = { "PROVING_GROUNDS_SCORE" } }
local REWARDS_HEADER = { only = { "REWARDS" } }
local TOAST = { only = { "REWARDS", "COLLECTED" } }
local BANNER = { only = { "WORLD_QUEST_BANNER", "BONUS_OBJECTIVE_BANNER" } }
local REWARDS_TOOLTIP = { only = { "RETRIEVING_DATA", "REWARDS", "WORLD_QUEST_TOOLTIP_DESCRIPTION",
  "BONUS_OBJECTIVE_TOOLTIP_DESCRIPTION" } }
local FIND_GROUP_TOOLTIP = { only = { "TOOLTIP_TRACKER_FIND_GROUP_BUTTON" } }

local function get(key) return Compat.get(SURFACE, key) end

local popupKey = WFJ.Labels.keyer("popup.") -- a pooled popup FontString's record key
local achievementKey = WFJ.Labels.keyer("achievement.") -- a pooled achievement block's record key
local toastKey = WFJ.Labels.keyer("toast.") -- a pooled toast header's record key
local criterionKey = WFJ.Labels.keyer("criterion.") -- a pooled objective line's record key

-- One module's header as it is now. → 1 | 0
function Tracker.showHeader(key)
  local m = MODULES[key]
  if not m then return 0 end
  local n = WFJ.Labels.show(SURFACE, "header." .. key, get(key .. ".header"), nil, { only = m[2] })
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- hooksecurefunc target on AchievementObjectiveTracker:AddAchievement: the block's title and its criteria lines.
-- → words shown
function Tracker.onAchievement(module, achievementID)
  if type(module) ~= "table" or type(module.GetExistingBlock) ~= "function" then return 0 end
  local ok, block = pcall(module.GetExistingBlock, module, achievementID)
  if not ok or type(block) ~= "table" then return 0 end
  local n = WFJ.Labels.show(SURFACE, achievementKey(block), block.HeaderText, nil,
    WFJ.Labels.families("AchievementTitle"))
  if type(block.usedLines) == "table" then
    -- an achievement with no criteria of its own shows its description as the line (lua:183): AchievementDescription
    local only = WFJ.Labels.families("CriteriaText", "AchievementDescription")
    for _, line in pairs(block.usedLines) do
      local text = type(line) == "table" and line.Text or nil
      if type(text) == "table" then n = n + WFJ.Labels.show(SURFACE, criterionKey(text), text, nil, only) end
    end
  end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- hooksecurefunc target on a quest-type module's AddAutoQuestObjectives: every popup block it holds. → words found
function Tracker.onAutoQuestPopups(module)
  local used = type(module) == "table" and module.usedBlocks or nil
  local blocks = type(used) == "table" and used[POPUP_TEMPLATE] or nil
  if type(blocks) ~= "table" then return 0 end
  local n = 0
  for _, block in pairs(blocks) do
    local contents = type(block) == "table" and block.Contents or nil
    if type(contents) == "table" then
      if type(contents.TopText) == "table" then
        n = n + WFJ.Labels.show(SURFACE, popupKey(contents.TopText), contents.TopText, nil, POPUP_TOP)
      end
      if type(contents.BottomText) == "table" then
        n = n + WFJ.Labels.show(SURFACE, popupKey(contents.BottomText), contents.BottomText, nil, POPUP_BOTTOM)
      end
    end
  end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- hooksecurefunc target on StageBlock:UpdateStageBlock / :SetupStageTransition. → words found
function Tracker.onStage()
  local n = WFJ.Labels.show(SURFACE, "stage", get("stage"), nil, STAGE)
    + WFJ.Labels.show(SURFACE, "complete", get("complete"), nil, COMPLETE)
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- The proving-grounds block's two static labels (HookScript OnShow, and once at init). → words found
function Tracker.showProvingLabels()
  return WFJ.Labels.showAll(SURFACE, { { "wave", get("waveLabel"), WAVE }, { "score", get("scoreLabel"), SCORE } })
end

-- ScenarioRewardsFrame's static header (HookScript OnShow, and once at init). → 1 | 0
function Tracker.showScenarioRewards()
  return WFJ.Labels.showAll(SURFACE, { { "scenarioRewards", get("scenarioRewardsHeader"), REWARDS_HEADER } })
end

-- hooksecurefunc target on ObjectiveTrackerManager:ShowRewardsToast: every active toast's header. → words found
function Tracker.onRewardsToast(manager)
  local pool = type(manager) == "table" and manager.rewardsToastPool or nil
  if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then return 0 end
  local n = 0
  for toast in pool:EnumerateActive() do
    local header = type(toast) == "table" and toast.Header or nil
    if type(header) == "table" then n = n + WFJ.Labels.show(SURFACE, toastKey(header), header, nil, TOAST) end
  end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- hooksecurefunc target on ObjectiveTrackerTopBannerFrame:PlayBanner. → 1 | 0
function Tracker.onBanner()
  local n = WFJ.Labels.show(SURFACE, "banner", get("bannerSubtitle"), nil, BANNER)
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- hooksecurefunc target on a bonus / world-quest module's GetBlock(id, template): the block owns its rewards tooltip.
function Tracker.onTaskBlock(module, id, template)
  if type(module) ~= "table" or type(module.GetExistingBlock) ~= "function" then return false end
  local ok, block = pcall(module.GetExistingBlock, module, id, template)
  if not ok or type(block) ~= "table" then return false end
  WFJ.HelpTooltip.register(block, REWARDS_TOOLTIP)
  return true
end

-- hooksecurefunc target on a module's GetRightEdgeFrame: its find-group eye buttons own a one-line tooltip. Matched by
-- the template the frame was acquired with (ObjectiveTrackerManager:AcquireFrame stores it on the frame,
-- blizzard_objectivetrackermanager.lua:76–79); a quest item button is never registered. → the number registered now
function Tracker.onRightEdgeFrame(module)
  local frames = type(module) == "table" and module.usedRightEdgeFrames or nil
  if type(frames) ~= "table" then return 0 end
  local n = 0
  for _, frame in pairs(frames) do
    if type(frame) == "table" and frame.template == FIND_GROUP_TEMPLATE and not WFJ.HelpTooltip.registered(frame) then
      WFJ.HelpTooltip.register(frame, FIND_GROUP_TOOLTIP)
      n = n + 1
    end
  end
  return n
end

-- hooksecurefunc target on StageBlock:UpdateFindGroupButton (the button is created on first need).
function Tracker.onStageFindGroup(stageBlock)
  local button = type(stageBlock) == "table" and stageBlock.findGroupButton or nil
  if type(button) ~= "table" then return false end
  WFJ.HelpTooltip.register(button, FIND_GROUP_TOOLTIP)
  return true
end

local hooked = false
local methodsHooked = setmetatable({}, { __mode = "k" })

-- Post-hooks `method` on the table behind Compat key `key`, once. → true when hooked now
local function hookMethod(key, method, fn)
  local t = get(key)
  if type(t) ~= "table" or type(t[method]) ~= "function" then return false end
  local done = methodsHooked[t] or {}
  if done[method] then return false end
  done[method] = true
  methodsHooked[t] = done
  hooksecurefunc(t, method, fn)
  return true
end

local function hookScript(key, script, fn)
  local f = get(key)
  if type(f) == "table" and type(f.HookScript) == "function" then f:HookScript(script, fn) end
end

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init. → false when there is no tracker
function Tracker.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  if hooked or type(get("frame")) ~= "table" then return false end
  hooked = true
  WFJ.Labels.forbidNames(Tracker.NEVER_TOUCH)
  for key in pairs(MODULES) do
    hookMethod(key, "SetHeader", function() Tracker.showHeader(key) end)
    Tracker.showHeader(key) -- OnLoad wrote it before this addon loaded
  end
  hookMethod("scenario", "LayoutContents", function() Tracker.showHeader("scenario") end)
  hookMethod("achievement", "AddAchievement", Tracker.onAchievement)
  for _, key in ipairs({ "quest", "campaign" }) do
    hookMethod(key, "AddAutoQuestObjectives", Tracker.onAutoQuestPopups)
    Tracker.onAutoQuestPopups(get(key))
  end
  for _, key in ipairs({ "quest", "campaign", "bonus", "worldquest" }) do
    hookMethod(key, "GetRightEdgeFrame", Tracker.onRightEdgeFrame)
    Tracker.onRightEdgeFrame(get(key))
  end
  for _, key in ipairs({ "bonus", "worldquest" }) do hookMethod(key, "GetBlock", Tracker.onTaskBlock) end
  hookMethod("stageBlock", "UpdateStageBlock", Tracker.onStage)
  hookMethod("stageBlock", "SetupStageTransition", Tracker.onStage)
  hookMethod("stageBlock", "UpdateFindGroupButton", Tracker.onStageFindGroup)
  local stageBlock = get("stageBlock")
  if type(stageBlock) == "table" then
    WFJ.HelpTooltip.register(stageBlock, STAGE_TOOLTIP)
    Tracker.onStageFindGroup(stageBlock)
  end
  hookScript("provingBlock", "OnShow", Tracker.showProvingLabels)
  hookScript("scenarioRewards", "OnShow", Tracker.showScenarioRewards)
  hookMethod("manager", "ShowRewardsToast", Tracker.onRewardsToast)
  hookMethod("banner", "PlayBanner", Tracker.onBanner)
  Tracker.onStage()
  Tracker.showProvingLabels()
  Tracker.showScenarioRewards()
  return true
end
