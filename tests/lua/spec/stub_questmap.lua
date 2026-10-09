-- The camelot (Forever) quest log as the mainline UI builds it: QuestMapFrame's details pane and quest list,
-- the tracker's popup (QuestLogPopupDetailFrame) and the objective tracker's quest module, replaying the writes of
-- forever Blizzard_UIPanels_Game/mainline/questmapframe.{lua,xml}, mainline/questinfo.lua,
-- Blizzard_FrameXMLUtil/camelot/questutilsoverrides.lua and
-- Blizzard_ObjectiveTracker/blizzard_questobjectivetracker.lua with its camelot override. A client write
-- is a plain fs:SetText outside the addon (not counted as ours). Requires Stub.install and Stub.installQuestAPI first
-- (the QuestInfo widgets are the quest window's), and must run before the addon hooks QuestInfo_Display.
--   Q.quests[id] = { title, description, objectives, level, elite, tag, failed, decorated }
--     tag: the quest tag's word key ("ELITE", "CALENDAR_TYPE_DUNGEON", "CALENDAR_TYPE_PVP", "RAID"); an elite quest
--     with no tag set is tagged ELITE
--   Q.log = { id, … } (list order) · Q.watched = { [id] = true } · Q.party = { [id] = n } (party-count prefix)
--   Q.trackerLevel (the tracker's level prefix, always on on camelot; off lets a spec read a bare title)
--   · Q.trackerColor (showQuestDifficultyColor CVar)
-- Drivers: Q.showDetails(id), Q.closeDetails(), Q.showPopup(id), Q.hidePopup(), Q.updateList(), Q.hideMap(),
-- Q.updateTracker(), Q.setWatched(id, bool).
local Stub = require("tests.lua.spec.wow_stub")
local Q = {}

-- The client's English for the global strings the replayed writers use (a spec's ui table sets the same globals).
local EN = {
  BACK = "Back", REWARDS = "Rewards", ABANDON_QUEST_ABBREV = "Abandon", SHARE_QUEST_ABBREV = "Share",
  TRACK_QUEST_ABBREV = "Track", UNTRACK_QUEST_ABBREV = "Untrack", SHOW_MAP = "Show Map",
  QUEST_LOG_NO_QUESTS = "No quests available|n|nAccept quests by talking to characters with a "
    .. "|TInterface\\GossipFrame\\AvailableQuestIcon:16:16|t above their head.",
  QUEST_LOG_NO_RESULTS = "No results found", SEARCH_QUEST_LOG = "Search Quest Log",
  QUEST_LOG_COUNT_TEMPLATE = "Quests: %s%d|r|cffffffff/%d|r", QUEST_TITLE_FORMAT_FAILED = "%s - |cffff2020(Failed)|r",
  REWARD_CHOICES = "You will be able to choose one of these rewards:", REWARD_ITEMS_ONLY = "You will receive:",
  REWARD_TITLE = "You shall be granted the title:", TRACKER_HEADER_QUESTS = "Quests",
  TRACKER_ALL_OBJECTIVES = "All Objectives", INVTYPE_CLOAK = "Back", COMPLETE = "Complete",
  QUEST_WAYPOINT_FINAL = "Show Final Destination", QUEST_WAYPOINT_ROUTE = "Show Travel Route",
  PARENS_TEMPLATE = "(%s)", ELITE = "Elite", CALENDAR_TYPE_DUNGEON = "Dungeon", CALENDAR_TYPE_PVP = "PvP",
  RAID = "Raid",
}
Q.EN = EN
local function S(key) return _G[key] or EN[key] end

-- QuestUtilsOverrides.GetQuestTagText (blizzard_framexmlutil/camelot/questutilsoverrides.lua:20–35). → text | nil
local function tagText(q)
  local word = q.tag or (q.elite and "ELITE") or nil
  return word and S("PARENS_TEMPLATE"):format(S(word)) or nil
end

local function fs(text) return Stub.fontString(text or "") end

function Q.install()
  Q.quests, Q.log, Q.watched, Q.party, Q.selected = {}, {}, {}, {}, 0
  Q.trackerLevel, Q.trackerColor = false, false
  -- QuestInfoObjectivesFrame.Objectives (mainline/questinfo.lua:199), filled by the map templates
  Q.objectiveStrings = {}
  _G.QuestInfoObjectivesFrame = CreateFrame("Frame", "QuestInfoObjectivesFrame")
  _G.QuestInfoObjectivesFrame.Objectives = Q.objectiveStrings

  -- C_QuestLog as the mainline QuestInfo reads it [verified: mainline/questinfo.lua:124–126, 137–146]
  _G.C_QuestLog = {
    GetSelectedQuest = function() return Q.selected end,
    SetSelectedQuest = function(id) Q.selected = id end,
    GetTitleForQuestID = function(id) return Q.quests[id] and Q.quests[id].title or nil end,
    IsEliteQuest = function(id) return Q.quests[id] and Q.quests[id].elite or false end,
    GetQuestDifficultyLevel = function(id) return Q.quests[id] and Q.quests[id].level or 1 end,
  }
  -- GetQuestLogQuestText() with no argument: the selected quest (questinfo.lua:185, 391)
  _G.GetQuestLogQuestText = function()
    local q = Q.quests[Q.selected]
    if not q then return nil, nil end
    return q.description, q.objectives
  end

  -- the rewards frames (mainline/questinfo.xml:423–503, 612–640); the quest window's already exists
  _G.QuestInfoRewardsFrame.PlayerTitleText = fs("")
  local mapRewards = CreateFrame("Frame", "MapQuestInfoRewardsFrame")
  mapRewards.ItemChooseText = fs(S("REWARD_CHOICES"))
  mapRewards.ItemReceiveText = fs("")
  mapRewards.PlayerTitleText = fs(S("REWARD_TITLE"))
  mapRewards.Header = CreateFrame("Frame") -- an anchor frame, no text (questinfo.xml:635)

  -- QuestMapFrame (mainline/questmapframe.xml:423–860)
  local map = CreateFrame("Frame", "QuestMapFrame")
  map.QuestsFrame = CreateFrame("Frame")
  local list = CreateFrame("ScrollFrame", "QuestScrollFrame")
  map.QuestsFrame.ScrollFrame = list
  list.NoSearchResultsText = fs(S("QUEST_LOG_NO_RESULTS"))
  list.EmptyText = fs(S("QUEST_LOG_NO_QUESTS"))
  list.SearchBox = CreateFrame("EditBox")
  list.SearchBox.Instructions = fs(S("SEARCH_QUEST_LOG")) -- QuestLogScrollFrameMixin:OnLoad (:1241)
  Stub.namedFontString("QuestLogQuestCount", "")
  list.Contents = CreateFrame("Frame")
  list.Contents.layouts = 0
  function list.Contents.Layout(self) self.layouts = self.layouts + 1 end -- (:2162)
  -- titleFramePool (:1228): Acquire reuses the most recently released row first, so a row changes quest between updates
  local pool = { active = {}, free = {}, made = 0 }
  function pool:Acquire()
    local b = table.remove(self.free)
    if not b then
      self.made = self.made + 1
      b = CreateFrame("Button")
      b.Text = fs("")
      b.Text.width = 200
      b.TagText = fs("") -- camelot's quest tag (camelot/questutilsoverrides.lua:20–35; questmapframe.lua:1833–1836)
      function b.SetHeight(row, h) row.h = h end
      function b.GetHeight(row) return row.h end
      b.rowIndex = self.made
    end
    self.active[b] = true
    b.shown = true
    return b
  end
  function pool:ReleaseAll()
    for b in pairs(self.active) do
      b.shown = false
      b.info, b.questID = nil, nil
      self.free[#self.free + 1] = b
    end
    self.active = {}
  end
  function pool:EnumerateActive() return pairs(self.active) end
  list.titleFramePool = pool
  -- objectiveFramePool (:1233, QuestLogObjectiveTemplate): a row holds .Text and .questID only
  local opool = { active = {}, free = {} }
  function opool:Acquire()
    local o = table.remove(self.free)
    if not o then
      o = CreateFrame("Frame")
      o.Text = fs("")
      o.Text.width = 200
      function o.Text.GetStringHeight(t) return t:GetHeight() end
      function o.SetHeight(row, h) row.h = h end
      function o.GetHeight(row) return row.h end
    end
    self.active[o] = true
    return o
  end
  function opool:ReleaseAll()
    for o in pairs(self.active) do o.questID = nil; self.free[#self.free + 1] = o end
    self.active = {}
  end
  function opool:EnumerateActive() return pairs(self.active) end
  list.objectiveFramePool = opool

  local details = CreateFrame("Frame")
  map.QuestsFrame.DetailsFrame = details
  map.DetailsFrame = details -- QuestMapFrame_OnLoad (:465)
  details.ScrollFrame = CreateFrame("ScrollFrame", "QuestMapDetailsScrollFrame")
  details.ScrollFrame.Contents = CreateFrame("Frame")
  details.BackFrame = { BackButton = Stub.button(nil, S("BACK")) }
  details.RewardsFrameContainer = { RewardsFrame = CreateFrame("Frame") }
  details.RewardsFrameContainer.RewardsFrame.Label = fs(S("REWARDS"))
  details.AbandonButton = Stub.button(nil, S("ABANDON_QUEST_ABBREV"))
  details.ShareButton = Stub.button(nil, S("SHARE_QUEST_ABBREV"))
  details.TrackButton = Stub.button(nil, S("TRACK_QUEST_ABBREV"))
  -- QuestLogPathButtonTemplate's OnEnter (xml:70–74): SetOwner, GameTooltip_AddColoredLine(tooltipText), Show
  local function pathButton(key)
    local b = CreateFrame("Button")
    b.tooltipKey = key
    b:SetScript("OnEnter", function(self)
      _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      _G.GameTooltip:AddLine(S(self.tooltipKey))
      _G.GameTooltip:Show()
    end)
    return b
  end
  details.DestinationMapButton = pathButton("QUEST_WAYPOINT_FINAL")
  details.WaypointMapButton = pathButton("QUEST_WAYPOINT_ROUTE")
  -- a hover after the previous button's OnLeave (GameTooltip_Hide: the tooltip hides and its lines clear)
  function Q.hoverPath(button)
    _G.GameTooltip:Hide()
    _G.GameTooltip:ClearLines()
    button.scripts.OnEnter(button)
  end

  -- QuestLogPopupDetailFrame (:308–404)
  local popup = CreateFrame("Frame", "QuestLogPopupDetailFrame")
  popup.ScrollFrame = CreateFrame("ScrollFrame", "QuestLogPopupDetailFrameScrollFrame")
  popup.ScrollFrame.ScrollChild = CreateFrame("Frame")
  popup.AbandonButton = Stub.button("QuestLogPopupDetailFrameAbandonButton", S("ABANDON_QUEST_ABBREV"))
  popup.TrackButton = Stub.button("QuestLogPopupDetailFrameTrackButton", S("TRACK_QUEST_ABBREV"))
  popup.ShareButton = Stub.button("QuestLogPopupDetailFrameShareButton", S("SHARE_QUEST_ABBREV"))
  popup.ShowMapButton = { Text = fs(S("SHOW_MAP")) }

  -- the mainline QuestInfo_Display for the quest-log templates; the quest window's templates keep the replay
  -- installQuestAPI wrote (the same widgets). [verified: mainline/questinfo.lua:1134–1181]
  _G.QUEST_TEMPLATE_MAP_DETAILS = { questLog = true, contentWidth = 289 }
  _G.QUEST_TEMPLATE_MAP_REWARDS = { questLog = true, contentWidth = 289 }
  local windowDisplay = _G.QuestInfo_Display
  _G.QuestInfo_Display = function(template, parentFrame, acceptButton, material, mapView)
    if not template.questLog then return windowDisplay(template, parentFrame, acceptButton, material, mapView) end
    local q = Q.quests[Q.selected] or {}
    if template == _G.QUEST_TEMPLATE_MAP_REWARDS then
      _G.MapQuestInfoRewardsFrame.ItemReceiveText.text = S("REWARD_ITEMS_ONLY")
      return
    end
    -- QuestInfo_ShowTitle: decorated, or the failed format (questinfo.lua:137–161)
    local title = _G.C_QuestLog.GetTitleForQuestID(_G.C_QuestLog.GetSelectedQuest()) or ""
    if q.decorated then title = "|A:questlog-questtypeicon-dungeon:16:16|a" .. title end
    if q.failed then title = S("QUEST_TITLE_FORMAT_FAILED"):format(title) end
    _G.QuestInfoTitleHeader.text = title
    local description, objectives = _G.GetQuestLogQuestText()
    _G.QuestInfoObjectivesText.text = objectives or ""
    _G.QuestInfoDescriptionText.text = description or ""
    -- QuestInfo_ShowObjectives (questinfo.lua:194–250): one FontString per leaderboard line, " (Complete)" when done
    local shown = 0
    for i, line in ipairs(q.leaderboard or {}) do
      local o = Q.objectiveStrings[i]
      if not o then
        o = fs("")
        Q.objectiveStrings[i] = o
      end
      o.text = line.done and (line.text .. " (" .. S("COMPLETE") .. ")") or line.text
      o.shown = true
      shown = i
    end
    for i = shown + 1, #Q.objectiveStrings do Q.objectiveStrings[i].shown = false end
    if template == _G.QUEST_TEMPLATE_LOG then
      _G.QuestInfoRewardsFrame.ItemReceiveText.text = "You will also receive:"
    end
  end

  -- QuestMapFrame_UpdateQuestDetailsButtons (:1138–1153): Track / Untrack on both panes
  _G.QuestMapFrame_UpdateQuestDetailsButtons = function()
    local key = Q.watched[_G.C_QuestLog.GetSelectedQuest()] and "UNTRACK_QUEST_ABBREV" or "TRACK_QUEST_ABBREV"
    details.TrackButton.fontString.text = S(key)
    popup.TrackButton.fontString.text = S(key)
  end

  -- QuestMapFrame_ShowQuestDetails (:1044–1110)
  _G.QuestMapFrame_ShowQuestDetails = function(id)
    _G.C_QuestLog.SetSelectedQuest(id)
    details.questID = id
    _G.QuestInfo_Display(_G.QUEST_TEMPLATE_MAP_DETAILS, details.ScrollFrame.Contents)
    _G.QuestInfo_Display(_G.QUEST_TEMPLATE_MAP_REWARDS, details.RewardsFrameContainer.RewardsFrame, nil, nil, true)
    map:Show()
    details:Show()
    _G.QuestMapFrame_UpdateQuestDetailsButtons()
  end
  function Q.showDetails(id) _G.QuestMapFrame_ShowQuestDetails(id) end
  function Q.closeDetails() details:Hide(); details.questID = nil end -- QuestMapFrame_CloseQuestDetails (:1112)
  function Q.hideMap() details:Hide(); map:Hide() end                   -- QuestMapFrame_OnHide (:630–633)

  -- QuestLogPopupDetailMixin:ShowQuest (:2600–2615) → Update (:2688–2689)
  function Q.showPopup(id)
    popup.questID = id
    _G.C_QuestLog.SetSelectedQuest(id)
    _G.QuestMapFrame_UpdateQuestDetailsButtons()
    _G.QuestInfo_Display(_G.QUEST_TEMPLATE_LOG, popup.ScrollFrame.ScrollChild)
    popup:Show()
  end
  function Q.hidePopup() popup:Hide() end

  function Q.setWatched(id, on)
    Q.watched[id] = on or nil
    _G.QuestMapFrame_UpdateQuestDetailsButtons() -- QUEST_WATCH_LIST_CHANGED (:587–589)
  end

  -- QuestLogQuests_Update (:2104) with QuestLogQuests_AddQuestButton (:1808–1836) and camelot's title prefix
  -- (:1631, blizzard_framexmlutil/camelot/questutilsoverrides.lua:6–9), the party count (:1639) and the count
  -- (camelot/questmapframeutils.lua)
  _G.QuestLogQuests_Update = function()
    pool:ReleaseAll()
    opool:ReleaseAll()
    for _, id in ipairs(Q.log) do
      local q = Q.quests[id]
      local b = pool:Acquire()
      b.questID = id
      b.info = { questID = id, title = q.title, difficultyLevel = q.level }
      local title = "[" .. q.level .. (q.elite and "+" or "") .. "] " .. q.title
      if Q.party[id] then title = "[" .. Q.party[id] .. "] " .. title end
      if q.decorated then title = "|A:questlog-questtypeicon-dungeon:16:16|a" .. title end
      b.Text.text = title
      b.TagText.text = tagText(q) or ""
      local total = 8 + b.Text:GetHeight() -- the button's height: the sum of its English heights (:1885–1961)
      for _, line in ipairs(q.leaderboard or {}) do -- unfinished leaderboard lines (:1904–1926)
        if not line.done then
          local o = opool:Acquire()
          o.questID = id
          o.Text.text = line.text
          o:SetHeight(o.Text:GetStringHeight())
          total = total + o:GetHeight() + 3
        end
      end
      b:SetHeight(total + 6)
    end
    list.EmptyText.shown = #Q.log == 0
    _G.QuestLogQuestCount.text = S("QUEST_LOG_COUNT_TEMPLATE"):format("|cffffffff", #Q.log, 20)
  end
  function Q.updateList() _G.QuestLogQuests_Update() end
  function Q.rows()
    local out = {}
    for b in pool:EnumerateActive() do out[b.questID] = b end
    return out
  end

  -- the objective tracker's quest module (blizzard_questobjectivetracker.lua:197–204, 291–307 with
  -- camelot/blizzard_questobjectivetrackeroverride.lua:5–7; blizzard_objectivetrackermodule.lua:254–300;
  -- difficultyutil.lua:84–99 through camelot/questutilsoverrides.lua:6–18)
  local tracker = CreateFrame("Frame", "QuestObjectiveTracker")
  tracker.name = "QuestObjectiveTracker"
  tracker.usedBlocks = {}
  -- A block (ObjectiveTrackerBlockMixin): SetHeader writes the header and stores its measured height as block.height
  -- (blizzard_objectivetrackerblock.lua:134–158); each objective line adds OBJECTIVE_HEIGHT; SetHeight is the layout's
  -- (LayoutBlock, module.lua:349–354), recorded as block.laidOut.
  Q.OBJECTIVE_HEIGHT = 10
  local function newBlock(id)
    local block = { id = id, HeaderText = fs("") }
    block.HeaderText.width = 120
    function block:SetHeader(text)
      self.HeaderText.text = text
      self.height = self.HeaderText:GetHeight()
    end
    function block:SetHeight(h) self.laidOut = h end
    -- AddObjective (blizzard_objectivetrackerblock.lua:79–103, 161–209): the line is usedLines[objectiveKey], sized
    -- to its text, its height added to block.height
    block.usedLines = {}
    function block:AddObjective(objectiveKey, text)
      local line = self.usedLines[objectiveKey]
      if not line then
        line = { Text = fs("") }
        line.Text.width = 120
        function line.SetHeight(l, h) l.h = h end
        function line.GetHeight(l) return l.h end
        self.usedLines[objectiveKey] = line
      end
      line.parentBlock, line.used, line.objectiveKey = self, true, objectiveKey -- GetLine (:97–101)
      line.Text.text = text
      local h = line.Text:GetHeight()
      line:SetHeight(h)
      self.height = self.height + h
      return line
    end
    return block
  end
  function tracker:GetBlock(id)
    local block = self.usedBlocks[id]
    if not block then
      block = newBlock(id)
      self.usedBlocks[id] = block
    end
    return block, true
  end
  function tracker:GetExistingBlock(id) return self.usedBlocks[id] end
  -- the module header (ObjectiveTrackerModuleMixin:OnLoad → SetHeader(headerText), module.lua:47–52, 121–122) and the
  -- container's (ObjectiveTrackerContainerMixin:Init, container.lua:47–50; ObjectiveTrackerFrame, xml:3–13)
  tracker.Header = { Text = fs("") }
  function tracker:SetHeader(text) self.Header.Text.text = text end
  tracker:SetHeader(S("TRACKER_HEADER_QUESTS"))
  local container = CreateFrame("Frame", "ObjectiveTrackerFrame")
  container.Header = { Text = fs("") }
  function container:Init() self.Header.Text.text = S("TRACKER_ALL_OBJECTIVES") end
  function Q.initTrackerContainer() container:Init() end
  function tracker:UpdateSingle(quest)
    local id = quest:GetID()
    local block = self:GetBlock(id)
    local title = quest.title
    local tag = Q.quests[id] and tagText(Q.quests[id])
    if tag then title = title .. " " .. tag end
    if Q.trackerLevel then
      title = "[" .. _G.C_QuestLog.GetQuestDifficultyLevel(id) .. (_G.C_QuestLog.IsEliteQuest(id) and "+" or "")
        .. "] " .. title
    end
    if Q.trackerColor then title = "|cffffff00" .. title .. "|r" end
    block:SetHeader(title)
    local board = Q.quests[id] and Q.quests[id].leaderboard
    if board then -- DoQuestObjectives (blizzard_questobjectivetracker.lua:207–258)
      for i, line in ipairs(board) do block:AddObjective(i, line.text) end
    else
      block.height = block.height + Q.OBJECTIVE_HEIGHT -- one objective line (AddObjective)
    end
    self:LayoutBlock(block)
    return true
  end
  function tracker.LayoutBlock(_, block) block:SetHeight(block.height) end -- module.lua:349–354
  function Q.updateTracker()
    for _, id in ipairs(Q.log) do
      if Q.watched[id] then
        local quest = { id = id, title = Q.quests[id].title }
        function quest.GetID(self) return self.id end
        tracker.UpdateSingle(tracker, quest) -- EnumQuestWatchData: func(self, quest), func read at call time
      end
    end
    tracker:UpdateHeight()
  end
  -- UpdateHeight (module.lua:223–231): the module frame from its contentsHeight, the sum of its blocks' height fields
  -- (InternalAddBlock, :417); the frame height is recorded as tracker.frameHeight
  function tracker:UpdateHeight()
    local sum = 0
    for _, block in pairs(self.usedBlocks) do sum = sum + (block.height or 0) end
    self.contentsHeight = sum
    self.frameHeight = sum
  end
  function tracker.SetHeight(t, h) t.frameHeight = h end
  function tracker.GetHeight(t) return t.frameHeight end
  Stub.loadedAddons.Blizzard_ObjectiveTracker = true
  return Q
end

return Q
