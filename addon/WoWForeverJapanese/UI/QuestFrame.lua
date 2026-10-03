-- UI/QuestFrame.lua: the quest accept / progress / turn-in windows (area "quests"), one surface per panel:
--   questframe.detail    QuestInfo_Display(QUEST_TEMPLATE_DETAIL, QuestDetailScrollChildFrame)
--                        → title, description, objectives
--   questframe.reward    QuestInfo_Display(QUEST_TEMPLATE_REWARD, QuestRewardScrollChildFrame)  → title, completion
--   questframe.progress  QuestFrameProgressPanel OnShow                                        → title, progress
-- Detail / reward post-hook the client's writer (hooksecurefunc on QuestInfo_Display, called by name from
-- QuestFrame*Panel_OnShow, so the global is resolved at call time). The progress writer is bound in XML as
-- <OnShow function="QuestFrameProgressPanel_OnShow"/> and reached only through panel:Show() [verified: classic_era
-- Vanilla/QuestFrame.xml:267, Classic/QuestFrame.lua:81–82]; [likely] the frame holds the function value, so it is
-- hooked as a frame script (HookScript), correct under either binding semantics, never as a global.
-- English is read from the quest API; a widget that does not show exactly that English is left untouched and any
-- stale record on it is dropped (ADR-009). Showing a panel forgets the other two. Release on QuestFrame's OnHide.
-- Every field's API English and the quest giver's name go to the Collector first.
-- Labels (area "ui"): each panel's fixed headers and buttons, after its fields, on the same surface (records
-- "ui.<widget>", exact dictionary words only: UI/Labels); the greeting panel (surface questframe.greeting,
-- QuestFrameGreetingPanel OnShow) shows its two headers and Goodbye
-- [verified: classic_era Vanilla/QuestFrame.xml:86–127, 272–357; Vanilla/QuestInfo.xml:207–291, 574–580].
-- Greeting prose (area "gossip"): GreetingText, written by QuestFrameGreetingPanel_OnShow from GetGreetingText()
-- and translated by its gossip key (ADR-005) on questframe.greeting. The client reaches the writer both through the
-- panel's OnShow (XML-bound, hooked with HookScript) and by name on QUEST_LOG_UPDATE (hooksecurefunc on the global)
-- [verified: classic_era Classic/QuestFrame.lua:59–60, 99–104, 305–317; Vanilla/QuestFrame.xml:333–360, 497]. The
-- greeting panel shares the quest window banner; showing it forgets the three quest panels, and a quest panel
-- forgets it.
-- Forever loads the mainline QuestInfo, whose QuestInfo_Display also writes the quest map's details
-- pane (QUEST_TEMPLATE_MAP_DETAILS / _MAP_REWARDS) and the tracker's popup (QUEST_TEMPLATE_LOG), with the SAME global
-- FontStrings as this window [verified: forever mainline/questmapframe.lua:1050–1051, 2688–2689; mainline/
-- questinfo.lua:28, 1134–1181]. This file keeps the one QuestInfo_Display hook and hands every `template.questLog`
-- call to UI/QuestMap (surfaces "questmap", "questmap.popup"). A detail / reward show forgets those surfaces first, and
-- they forget this window's panels, so a release never writes one surface's English over another's text (ADR-029).
-- Reward headers and the timer (area "ui"):
--   questframe.spellheaders  the rewards' spell-group headers. QuestInfo_ShowRewards writes each from a FontString
--     pool, rewardsFrame.spellHeaderPool, with QUEST_INFO_SPELL_REWARD_TO_HEADER[type] (REWARD_SPELL,
--     REWARD_ABILITY, …; mainline/questinfo.lua:471–483, 813–828), for the quest window's and the map's rewards
--     frames alike. Walked after every QuestInfo_Display, restricted to those keys, forgotten first (the pool was
--     released).
--   questframe.timer  QuestInfoTimerText, "Time Remaining: <SecondsToTime>" (the colonPrefix form, the live time
--     kept), rewritten by QuestInfo_ShowTimer and by the timer frame's XML-bound OnUpdate every frame
--     (questinfo.lua:5–10, 327–340; questinfo.xml:374–391): a QuestInfo_ShowTimer post-hook and a HookScript on
--     OnUpdate; while the text is still ours nothing is matched again.
-- Every client API and widget here is declared through Compat and used only by type: a name a client
-- moved into a namespace table resolves truthy and would raise "attempt to call a table" from inside the hook.
local _, WFJ = ...
local QuestFrame = {}
WFJ.QuestFrame = QuestFrame

local Compat = WFJ.Compat
local DECLARE = "questframe" -- Compat namespace for every client name this file resolves

-- The marker banner: one FontString of ours on QuestFrame, in the stone band between the NPC name and the
-- parchment. QuestNpcNameFrame sits at TOP y=-23 (14 px tall) and the panels' scroll frames start at y=-81
-- [verified: classic_era Vanilla/QuestFrame.xml:59–62, Vanilla/QuestFrameTemplates.xml:195–199]; nothing of
-- the client's is anchored in between. Shared by the three panels (only one is ever shown). The FontString
-- sits on a small frame of ours raised above the panels: the panels are child frames of QuestFrame and their
-- background art (QuestFramePanelTemplate) would otherwise paint over a string drawn on QuestFrame itself, and
-- the banner would vanish once the panel texture finished loading.
local BANNER_Y = -52
local BANNER_WIDTH = 300
-- Forever loads the mainline QuestFrame, a ButtonFrameTemplate whose parchment starts at y=-62 and its scroll frames
-- at -65 [verified: forever-ui mainline/questframetemplates.xml:12, :165], so -52 would lay the banner over the
-- parchment's top edge. There the band is the stone strip between the title bar and the parchment, with the portrait
-- on the left: the gossip window's band, so the gossip banner's place (UI/Gossip.lua BANNER_X/Y/WIDTH). The
-- template's TopTileStreaks key tells the layouts apart (mainline questframe.xml:68 anchors to it; the vanilla
-- QuestFrame does not inherit the template). y -36 centres the banner in that strip; two markers wrap to a second
-- line that reaches the parchment's top edge.
local MODERN_BANNER_X, MODERN_BANNER_Y, MODERN_BANNER_WIDTH = 20, -36, 230

local CANDIDATES = {
  frame         = { "QuestFrame" },
  display       = { "QuestInfo_Display" },
  progressPanel = { "QuestFrameProgressPanel" },
  detailChild   = { "QuestDetailScrollChildFrame" },
  rewardChild   = { "QuestRewardScrollChildFrame" },
  detailScroll  = { "QuestDetailScrollFrame" },
  rewardScroll  = { "QuestRewardScrollFrame" },
  progressScroll = { "QuestProgressScrollFrame" },
  -- field widgets
  title         = { "QuestInfoTitleHeader" },
  description   = { "QuestInfoDescriptionText" },
  objectives    = { "QuestInfoObjectivesText" },
  completion    = { "QuestInfoRewardText" },
  progressTitle = { "QuestProgressTitleText" },
  progress      = { "QuestProgressText" },
  -- labels and buttons
  greetingPanel = { "QuestFrameGreetingPanel" },
  rewardsFrame  = { "QuestInfoRewardsFrame" },
  descriptionHeader = { "QuestInfoDescriptionHeader" },
  objectivesHeader  = { "QuestInfoObjectivesHeader" },
  learnLabel        = { "QuestInfoSpellObjectiveLearnLabel" },
  requiredMoney     = { "QuestInfoRequiredMoneyText" },
  groupSize         = { "QuestInfoGroupSize" },
  progressItems     = { "QuestProgressRequiredItemsText" },
  progressMoney     = { "QuestProgressRequiredMoneyText" },
  currentQuests     = { "CurrentQuestsText" },
  availableQuests   = { "AvailableQuestsText" },
  acceptButton      = { "QuestFrameAcceptButton" },
  declineButton     = { "QuestFrameDeclineButton" },
  continueButton    = { "QuestFrameCompleteButton" },
  goodbyeButton     = { "QuestFrameGoodbyeButton" },
  completeButton    = { "QuestFrameCompleteQuestButton" },
  greetingGoodbye   = { "QuestFrameGreetingGoodbyeButton" },
  -- greeting prose
  greetingText      = { "GreetingText" },
  greetingScroll    = { "QuestGreetingScrollFrame" },
  greetingWriter    = { "QuestFrameGreetingPanel_OnShow" },
  greetingGetter    = { "GetGreetingText" },
  -- the quest window's readers: the client's C API, present on both clients
  getTitle          = { "GetTitleText" },
  getDescription    = { "GetQuestText" },
  getObjectives     = { "GetObjectiveText" },
  getCompletion     = { "GetRewardText" },
  getProgress       = { "GetProgressText" },
  getQuestID        = { "GetQuestID" },
  unitGUID          = { "UnitGUID" },
  unitName          = { "UnitName" },
  -- reward headers and the timer
  mapRewardsFrame   = { "MapQuestInfoRewardsFrame" },
  timerFrame        = { "QuestInfoTimerFrame" },
  timerText         = { "QuestInfoTimerText" },
  showTimer         = { "QuestInfo_ShowTimer" },
  showRewards       = { "QuestInfo_ShowRewards" },
}

-- A declared client function, called only when it is one. → its returns | nil
local function call(key, ...)
  local fn = Compat.get(DECLARE, key)
  if type(fn) ~= "function" then return nil end
  return fn(...)
end

-- A widget we may read and write: a table with GetText and SetText functions.
local function isText(w)
  return type(w) == "table" and type(w.GetText) == "function" and type(w.SetText) == "function"
end

local function refitFor(scrollKey)
  return function()
    local scroll = Compat.get(DECLARE, scrollKey)
    if type(scroll) == "table" and type(scroll.UpdateScrollChildRect) == "function" then
      scroll:UpdateScrollChildRect()
    end
  end
end

-- Per panel: its surface id, its refit (one closure each, so Render.refresh dedupes it), and
-- { field, widget key, English getter } rows. Getters are called at hook time, never cached.
local function title() return call("getTitle") end
local PANELS = {
  detail   = { surface = "questframe.detail", refit = refitFor("detailScroll"),
               { "title", "title", title },
               { "description", "description", function() return call("getDescription") end },
               { "objectives", "objectives", function() return call("getObjectives") end } },
  reward   = { surface = "questframe.reward", refit = refitFor("rewardScroll"),
               { "title", "title", title },
               { "completion", "completion", function() return call("getCompletion") end } },
  progress = { surface = "questframe.progress", refit = refitFor("progressScroll"),
               { "title", "progressTitle", title },
               { "progress", "progress", function() return call("getProgress") end } },
}
QuestFrame.SURFACES = { PANELS.detail.surface, PANELS.progress.surface, PANELS.reward.surface }
QuestFrame.GREETING = "questframe.greeting"
local greetingRefit = refitFor("greetingScroll")
local deps = {} -- { key(text) → gossip key | nil } from Main

-- Label widgets per panel: { record key, widget getter }. Getters resolve at hook time.
local function named(key) return function() return Compat.get(DECLARE, key) end end
local function reward(field)
  return function()
    local f = Compat.get(DECLARE, "rewardsFrame")
    return type(f) == "table" and f[field] or nil
  end
end
local function xpReceive()
  local f = Compat.get(DECLARE, "rewardsFrame")
  local xp = type(f) == "table" and f.XPFrame or nil
  return type(xp) == "table" and xp.ReceiveText or nil
end
local REWARD_LABELS = {
  { "ui.rewardsHeader", reward("Header") }, { "ui.rewardsChoose", reward("ItemChooseText") },
  { "ui.rewardsReceive", reward("ItemReceiveText") }, { "ui.xpReceive", xpReceive },
}
local LABELS = {
  detail = { { "ui.descriptionHeader", named("descriptionHeader") },
    { "ui.objectivesHeader", named("objectivesHeader") },
    { "ui.learnLabel", named("learnLabel") }, { "ui.requiredMoney", named("requiredMoney") },
    { "ui.groupSize", named("groupSize") },
    { "ui.accept", named("acceptButton") }, { "ui.decline", named("declineButton") } },
  progress = { { "ui.progressItems", named("progressItems") }, { "ui.progressMoney", named("progressMoney") },
    { "ui.continue", named("continueButton") }, { "ui.goodbye", named("goodbyeButton") } },
  -- the reward panel has no Cancel button: QuestFrameRewardPanel holds only QuestFrameCompleteQuestButton and the
  -- scroll frame [verified: forever mainline/questframe.xml:71–91]
  reward = { { "ui.complete", named("completeButton") } },
  greeting = { { "ui.currentQuests", named("currentQuests") }, { "ui.availableQuests", named("availableQuests") },
    { "ui.goodbye", named("greetingGoodbye") } },
}
for _, l in ipairs(REWARD_LABELS) do
  table.insert(LABELS.detail, l)
  table.insert(LABELS.reward, l)
end

local function showLabels(surface, list, refit)
  local items = {}
  for i, l in ipairs(list) do items[i] = { l[1], l[2]() } end
  return WFJ.Labels.showAll(surface, items, refit)
end

-- Hands every field of one panel to Render. The other panels' records are forgotten first (their widgets are
-- hidden and may be rewritten by the client before we see them again). Returns the number of records shown.
function QuestFrame.showPanel(panelName)
  local panel = PANELS[panelName]
  for _, other in pairs(PANELS) do
    if other ~= panel then WFJ.Render.forget(other.surface) end
  end
  WFJ.Render.forget(QuestFrame.GREETING) -- the client hid the greeting panel (it shares the banner)
  local id = call("getQuestID")
  if type(id) ~= "number" or id == 0 then
    WFJ.Render.forget(panel.surface)
    return 0
  end
  local n = 0
  for _, spec in ipairs(panel) do
    local field, widgetKey, getter = spec[1], spec[2], spec[3]
    local fs = Compat.get(DECLARE, widgetKey)
    local en = getter()
    -- a conditional description (another wording of the quest for this character), keyed by its English: only
    -- when the line is not the quest's own description
    local variant = field == "description" and type(WFJ.ShippedGossipKey) == "function"
      and not (type(WFJ.IsQuestFieldEnglish) == "function" and WFJ.IsQuestFieldEnglish(id, field, en))
      and WFJ.ShippedGossipKey(en)
    -- The API English is the truth even when the widget is decorated: record before the equality guard. A variant
    -- is never recorded as the quest's description: other characters see the quest's own wording.
    if not variant then WFJ.Collector.record("quest", id, field, en) end
    -- The widget must show exactly the API English; anything else (empty, decoration, a moved widget) is left
    -- alone, and a record from an earlier quest on that widget is dropped, never restored over the new text.
    if isText(fs) and en ~= nil and en ~= "" and fs:GetText() == en and variant then
      WFJ.Render.show(panel.surface, field, fs, en, "quests", "gossip", variant, { refit = panel.refit })
      n = n + 1
    elseif isText(fs) and en ~= nil and en ~= "" and fs:GetText() == en then
      -- live: the API English, for the stale marker's live check (ADR-019)
      WFJ.Render.show(panel.surface, field, fs, en, "quests", "quest." .. field, id, { refit = panel.refit, live = en })
      n = n + 1
    else
      WFJ.SurfaceState.drop(panel.surface, field)
    end
  end
  showLabels(panel.surface, LABELS[panelName], panel.refit) -- headers and buttons
  WFJ.Render.updateBanner(panel.surface) -- dropped fields no longer count
  -- The quest giver, as the window names it: UnitName("questnpc") [verified: classic_era Classic/QuestFrame.lua:118];
  -- UnitGUID accepts the same token [likely].
  WFJ.Collector.recordNpc(call("unitGUID", "questnpc"), call("unitName", "questnpc"))
  return n
end

-- The quest map's QuestInfo surfaces, read at call time: UI/QuestMap loads after this file, and a client or
-- spec without it has nothing to forget.
local function forgetQuestMap()
  local QM = WFJ.QuestMap
  if type(QM) ~= "table" or type(QM.QUESTINFO) ~= "table" then return end
  for _, surface in ipairs(QM.QUESTINFO) do WFJ.Render.forget(surface) end
end

-- The records the detail and reward panels hold on the SHARED QuestInfo widgets (the fields and the QuestInfo /
-- QuestInfoRewardsFrame words), dropped by UI/QuestMap before it shows on those widgets. The window's own
-- buttons (Accept, Decline, Complete Quest, …) are nobody else's widgets and keep their records; the progress panel and
-- the greeting write widgets of their own and are left alone.
local SHARED_KEYS = { "title", "description", "objectives", "completion", "ui.descriptionHeader",
  "ui.objectivesHeader", "ui.learnLabel", "ui.requiredMoney", "ui.groupSize" }
for _, l in ipairs(REWARD_LABELS) do SHARED_KEYS[#SHARED_KEYS + 1] = l[1] end
function QuestFrame.forgetQuestInfo()
  for _, surface in ipairs({ PANELS.detail.surface, PANELS.reward.surface }) do
    for _, key in ipairs(SHARED_KEYS) do WFJ.SurfaceState.drop(surface, key) end
    WFJ.Render.updateBanner(surface)
  end
end

-- The spell-group headers of both rewards frames (see the file header).
local SPELL_HEADERS = "questframe.spellheaders"
QuestFrame.SPELL_HEADERS = SPELL_HEADERS
local SPELL_HEADER_ONLY = { only = { "REWARD_FOLLOWER", "REWARD_COMPANION", "REWARD_TRADESKILL_SPELL",
  "REWARD_ABILITY", "REWARD_AURA", "REWARD_SPELL", "REWARD_UNLOCK", "REWARD_QUESTLINE_UNLOCK",
  "REWARD_QUESTLINE_REWARD", "REWARD_QUESTLINE_UNLOCK_PART", "REWARD_POSSIBLE_QUEST_REWARD" } }
local spellHeaderKey = WFJ.Labels.keyer("header.")
function QuestFrame.showSpellHeaders()
  WFJ.Render.forget(SPELL_HEADERS)
  local n = 0
  for _, key in ipairs({ "rewardsFrame", "mapRewardsFrame" }) do
    local f = Compat.get(DECLARE, key)
    local pool = type(f) == "table" and f.spellHeaderPool or nil
    if type(pool) == "table" and type(pool.EnumerateActive) == "function" then
      for header in pool:EnumerateActive() do
        if type(header) == "table" then
          n = n + WFJ.Labels.show(SPELL_HEADERS, spellHeaderKey(header), header, nil, SPELL_HEADER_ONLY)
        end
      end
    end
  end
  WFJ.Render.updateBanner(SPELL_HEADERS)
  return n
end

-- The quest timer line (see the file header). → 1 | 0
local TIMER = "questframe.timer"
QuestFrame.TIMER = TIMER
local TIMER_ONLY = { only = { "TIME_REMAINING" } }
function QuestFrame.showTimer()
  return WFJ.Labels.show(TIMER, "timer", Compat.get(DECLARE, "timerText"), nil, TIMER_ONLY)
end

-- hooksecurefunc target: runs after QuestInfo_Display wrote the panel. A quest-log template (the camelot quest map
-- details and the tracker popup) is UI/QuestMap's.
function QuestFrame.onDisplay(template, parentFrame)
  if type(template) ~= "table" then return 0 end
  QuestFrame.showSpellHeaders()
  if template.questLog then
    local QM = WFJ.QuestMap
    if type(QM) == "table" and type(QM.onDisplay) == "function" then return QM.onDisplay(template, parentFrame) end
    return 0
  end
  if parentFrame == nil then return 0 end
  if parentFrame == Compat.get(DECLARE, "detailChild") then
    forgetQuestMap()
    return QuestFrame.showPanel("detail")
  end
  if parentFrame == Compat.get(DECLARE, "rewardChild") then
    forgetQuestMap()
    return QuestFrame.showPanel("reward")
  end
  return 0
end

-- hooksecurefunc target (QuestInfo_ShowRewards): the client redraws the rewards on its own when a reward item's data
-- arrives (QUEST_ITEM_UPDATE, mainline/questframe.lua:75–84) or a spell is learned (:92–96), writing the English
-- reward headings again (questinfo.lua:765) after the panel was shown. The open panel is shown again.
function QuestFrame.onShowRewards()
  local function visible(key)
    local f = Compat.get(DECLARE, key)
    return type(f) == "table" and type(f.IsVisible) == "function" and f:IsVisible()
  end
  if visible("detailChild") then return QuestFrame.showPanel("detail") end
  if visible("rewardChild") then return QuestFrame.showPanel("reward") end
  return 0
end

-- HookScript target on QuestFrameProgressPanel's OnShow: runs after the client's writer.
function QuestFrame.onProgress()
  return QuestFrame.showPanel("progress")
end

-- The greeting prose: recorded as gossip, then shown by its gossip key when the widget shows exactly the API
-- English. A widget still showing our text for the same English (the handler reached twice after one client write)
-- is left as it is. → 1 when shown or already ours, else 0
local function showGreetingText()
  local fs, getter = Compat.get(DECLARE, "greetingText"), Compat.get(DECLARE, "greetingGetter")
  -- a client without it: the labels still show (unresolved in /wfj debug)
  if type(getter) ~= "function" then return 0 end
  local en = getter()
  WFJ.Collector.recordGossip(en, call("unitGUID", "questnpc"))
  local surface = QuestFrame.GREETING
  if not isText(fs) then
    WFJ.SurfaceState.drop(surface, "greeting")
    return 0
  end
  local rec = WFJ.SurfaceState.get(surface, "greeting")
  if rec and rec.fs == fs and rec.applied ~= nil and rec.en == en and fs:GetText() == rec.applied then
    return 1
  end
  local key = type(en) == "string" and en ~= "" and type(deps.key) == "function" and deps.key(en) or nil
  if key and fs:GetText() == en then
    WFJ.Render.show(surface, "greeting", fs, en, "gossip", "gossip", key, { refit = greetingRefit })
    return 1
  end
  WFJ.SurfaceState.drop(surface, "greeting")
  return 0
end

-- The greeting panel's quest buttons: each shows its quest's Japanese title, as the quest log does, through
-- UI/QuestMap's title helper. The client acquires them from titleButtonPool, numbering active quests 1.. and offered
-- ones 1.. again (`isActive` 1 / 0) [verified: forever-ui blizzard_uipanels_game/mainline/questframe.lua,
-- QuestFrameGreetingPanel_OnShow]. → titles shown
local function showGreetingTitles()
  local panel = Compat.get(DECLARE, "greetingPanel")
  local pool = type(panel) == "table" and panel.titleButtonPool or nil
  if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then return 0 end
  local activeId, activeTitle = Compat.resolve("GetActiveQuestID"), Compat.resolve("GetActiveTitle")
  local offeredInfo, offeredTitle = Compat.resolve("GetAvailableQuestInfo"), Compat.resolve("GetAvailableTitle")
  local n = 0
  for button in pool:EnumerateActive() do
    local i = type(button.GetID) == "function" and button:GetID() or nil
    local fs = type(button.GetFontString) == "function" and button:GetFontString() or nil
    local questID, en
    if type(i) == "number" and button.isActive == 1 and type(activeId) == "function" and type(activeTitle) == "function"
    then
      questID, en = activeId(i), activeTitle(i)
    elseif type(i) == "number" and type(offeredInfo) == "function" and type(offeredTitle) == "function" then
      questID, en = select(5, offeredInfo(i)), offeredTitle(i)
    end
    if fs and questID then
      local function refit()
        local icon = button.Icon
        button:SetHeight(math.max(button:GetTextHeight() + 2, icon and icon:GetHeight() or 0))
      end
      n = n + WFJ.QuestMap.showTitle(QuestFrame.GREETING, questID, fs, refit, en)
    end
  end
  return n
end

-- HookScript target on QuestFrameGreetingPanel's OnShow, and hooksecurefunc target on QuestFrameGreetingPanel_OnShow:
-- the greeting prose, its quest titles, then the panel's headers and Goodbye button. → the number of labels found
function QuestFrame.onGreeting()
  for _, panel in pairs(PANELS) do WFJ.Render.forget(panel.surface) end
  showGreetingText()
  pcall(showGreetingTitles)
  local n = showLabels(QuestFrame.GREETING, LABELS.greeting)
  WFJ.Render.updateBanner(QuestFrame.GREETING)
  return n
end

function QuestFrame.release()
  local n = 0
  for _, surface in ipairs(QuestFrame.SURFACES) do n = n + WFJ.Render.release(surface) end
  return n + WFJ.Render.release(QuestFrame.GREETING)
end

local hooked = false

-- Called by Main after Compat.init. Declares the candidates, hooks the writers that resolve, hooks OnHide.
-- d = { key(text) → gossip key | nil }; without it the greeting prose is left English.
function QuestFrame.init(d)
  deps = d or deps
  for key, names in pairs(CANDIDATES) do Compat.declare(DECLARE, key, names) end
  if hooked then return false end
  hooked = true
  -- by type, not truthiness: a writer bound to a table is not hooked, and a frame without HookScript is skipped
  if type(Compat.get(DECLARE, "display")) == "function" then
    hooksecurefunc("QuestInfo_Display", QuestFrame.onDisplay)
  end
  local function hookScript(key, script, fn)
    local f = Compat.get(DECLARE, key)
    if type(f) == "table" and type(f.HookScript) == "function" then f:HookScript(script, fn) end
  end
  hookScript("progressPanel", "OnShow", QuestFrame.onProgress)
  hookScript("greetingPanel", "OnShow", QuestFrame.onGreeting)
  -- the by-name call on QUEST_LOG_UPDATE; the OnShow path above covers the XML-bound value
  if type(Compat.get(DECLARE, "greetingWriter")) == "function" then
    hooksecurefunc("QuestFrameGreetingPanel_OnShow", QuestFrame.onGreeting)
  end
  hookScript("frame", "OnHide", QuestFrame.release)
  hookScript("timerFrame", "OnUpdate", QuestFrame.showTimer)
  if type(Compat.get(DECLARE, "showRewards")) == "function" then
    hooksecurefunc("QuestInfo_ShowRewards", QuestFrame.onShowRewards)
  end
  if type(Compat.get(DECLARE, "showTimer")) == "function" then
    hooksecurefunc("QuestInfo_ShowTimer", QuestFrame.showTimer)
  end
  local frame = Compat.get(DECLARE, "frame")
  if type(frame) == "table" and type(frame.CreateFontString) == "function" and type(frame.GetFrameLevel) == "function"
      and not QuestFrame.banner then
    local modern = frame.TopTileStreaks ~= nil
    local fs, holder
    if modern then
      fs, holder = WFJ.Render.createBanner(frame, MODERN_BANNER_X, MODERN_BANNER_Y, MODERN_BANNER_WIDTH)
    else
      fs, holder = WFJ.Render.createBanner(frame, 0, BANNER_Y, BANNER_WIDTH)
    end
    QuestFrame.banner = fs
    QuestFrame.bannerFrame = holder
    for _, surface in ipairs(QuestFrame.SURFACES) do WFJ.Render.setBanner(surface, fs) end
    WFJ.Render.setBanner(QuestFrame.GREETING, fs) -- the greeting prose's markers
  end
  return true
end
