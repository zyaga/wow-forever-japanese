-- UI/QuestMap.lua: the Forever (camelot) quest log (area "quests"). camelot has no QuestLogFrame; it loads the
-- mainline quest map (QuestMapFrame inside the world map) and the objective tracker [verified: forever TOC
-- Blizzard_UIPanels_Game 96, 173–178; mainline/questmapframe.lua, .xml]. Surfaces (one Compat namespace, "questmap"):
--   questmap             the map's details pane: QuestInfo_Display(QUEST_TEMPLATE_MAP_DETAILS, …DetailsFrame
--                        .ScrollFrame.Contents) plus the pane's fixed words [verified: questmapframe.lua:1044–1110]
--   questmap.popup       the tracker's popup: QuestInfo_Display(QUEST_TEMPLATE_LOG, QuestLogPopupDetailFrame
--                        .ScrollFrame.ScrollChild) [verified: questmapframe.lua:2688–2689]
--   questmap.list        the quest list's title rows, after QuestLogQuests_Update [verified: :2104, rows :1808–1836]
--   questmap.listlabels  the list's fixed words (empty / no results / search / count)
--   questmap.tracker     the objective tracker's quest headers [verified: blizzard_questobjectivetracker.lua:289–307]
--   questmap.trackerlabels  the tracker's two fixed headers (TRACKER_ALL_OBJECTIVES, TRACKER_HEADER_QUESTS)
--   questmap.trackerobjectives  the tracker's objective lines [verified: blizzard_objectivetrackerblock.lua:79–209]
--   questmap.title       the world map's title (MAP_AND_QUEST_LOG / WORLD_MAP, written by WorldMapMixin:SetupTitle
--                        and SynchronizeDisplayState, blizzard_worldmap.lua:26–153). QUEST_LOG stays in the set so a
--                        build that titles the window "Quest Log" is still rendered.
-- Objective lines (list rows, the panes' QuestInfoObjectivesFrame, the tracker) match the objective's own server
-- text by its fingerprint first (Core/Objectives, ADR-031), else a client template ("3/10 Kobold Vermin slain", the
-- name kept as written). The count and a " (Complete)" tag stay where the client put them.
-- UI/QuestFrame owns the one QuestInfo_Display hook and hands every `template.questLog` call here. The quest window,
-- the map and the popup write the SAME global FontStrings (questinfo.lua:99–110), so showing on one first forgets
-- the other two and a release never restores one surface's English over another's text (ADR-029).
-- The English comes from the quest API (C_QuestLog.GetSelectedQuest, GetTitleForQuestID, GetQuestLogQuestText,
-- as the client's own QuestInfo reads it). A widget that does not show exactly that English is left alone (ADR-009).
-- List and tracker titles also accept camelot's "[<level>(+)] " prefix and the tracker's difficulty colour, both
-- kept verbatim; any other decoration leaves the row English. Rows are keyed by quest ID, never position.
-- Everything is used by type: a name bound to a table degrades to untouched English.
local _, WFJ = ...
local QuestMap = {}
WFJ.QuestMap = QuestMap

local SURFACE = "questmap" -- the details pane, and the Compat namespace of every name below
local POPUP = "questmap.popup"
-- Records on the shared QuestInfo widgets live on their own sub-surfaces, so the cross-surface forget drops only
-- them: a pane's own buttons (widgets no other surface writes) keep their Japanese while the quest window shows.
local INFO = "questmap.info"
local POPUP_INFO = "questmap.popup.info"
local LIST = "questmap.list"
local LIST_LABELS = "questmap.listlabels"
local TRACKER = "questmap.tracker"
local TRACKER_LABELS = "questmap.trackerlabels"
local TRACKER_OBJECTIVES = "questmap.trackerobjectives"
QuestMap.INFO, QuestMap.POPUP_INFO = INFO, POPUP_INFO
QuestMap.SURFACE, QuestMap.POPUP, QuestMap.LIST, QuestMap.LIST_LABELS, QuestMap.TRACKER, QuestMap.TRACKER_LABELS =
  SURFACE, POPUP, LIST, LIST_LABELS, TRACKER, TRACKER_LABELS
QuestMap.TRACKER_OBJECTIVES = TRACKER_OBJECTIVES
local MAP_TITLE = "questmap.title"
QuestMap.MAP_TITLE = MAP_TITLE
QuestMap.QUESTINFO = { INFO, POPUP_INFO } -- the surfaces on the shared QuestInfo widgets (UI/QuestFrame forgets them)

-- The quest list's search box is an EditBox: never ours (ADR-016). Its placeholder (.Instructions) is a label.
QuestMap.NEVER_TOUCH = { "QuestScrollFrame.SearchBox" }

local Compat = WFJ.Compat

local CANDIDATES = {
  -- QuestMapFrame.DetailsFrame is set in QuestMapFrame_OnLoad (:465); the XML path is tried first.
  mapFrame        = { "QuestMapFrame" },
  worldMap        = { "WorldMapFrame" },                           -- blizzard_worldmap.xml:67
  worldMapBorder  = { "WorldMapFrame.BorderFrame" },               -- the SetTitle host (:85)
  details         = { "QuestMapFrame.QuestsFrame.DetailsFrame", "QuestMapFrame.DetailsFrame" },
  detailsContents = { "QuestMapDetailsScrollFrame.Contents",
                      "QuestMapFrame.QuestsFrame.DetailsFrame.ScrollFrame.Contents" },
  detailsScroll   = { "QuestMapDetailsScrollFrame" },                                  -- .xml:788
  mapRewardsParent = { "QuestMapFrame.QuestsFrame.DetailsFrame.RewardsFrameContainer.RewardsFrame" }, -- .xml:743–749
  popup           = { "QuestLogPopupDetailFrame" },                                     -- .xml:308
  popupChild      = { "QuestLogPopupDetailFrameScrollFrame.ScrollChild",
                      "QuestLogPopupDetailFrame.ScrollFrame.ScrollChild" },
  popupScroll     = { "QuestLogPopupDetailFrameScrollFrame" },                          -- .xml:321
  listScroll      = { "QuestScrollFrame" },                                             -- .xml:490
  -- writers
  detailsButtons  = { "QuestMapFrame_UpdateQuestDetailsButtons" }, -- rewrites Track on both panes (:1138–1153)
  listUpdate      = { "QuestLogQuests_Update" },                   -- :2104, called by name
  -- the tracker's quest modules (Blizzard_ObjectiveTracker; the campaign module shares the mixin's UpdateSingle,
  -- blizzard_campaignquestobjectivetracker.lua:7) [verified: blizzard_questobjectivetracker.xml:26,
  -- blizzard_campaignquestobjectivetracker.xml:3]
  questTracker    = { "QuestObjectiveTracker" },
  campaignTracker = { "CampaignQuestObjectiveTracker" },
  -- the content-tracking module (blizzard_adventureobjectivetracker.xml:3, .lua:139–189)
  adventureTracker = { "AdventureObjectiveTracker" },
  trackerFrame    = { "ObjectiveTrackerFrame" },                   -- the container (blizzard_objectivetracker.xml:3)
  trackerAllHeader = { "ObjectiveTrackerFrame.Header.Text" },
  questsHeader    = { "QuestObjectiveTracker.Header.Text" },
  -- QuestMapLogTitleButton_OnEnter fires "QuestMapLogTitleButton.OnEnter" after GameTooltip:Show
  -- [verified: mainline/questmapframe.lua:2219–2302]
  eventRegistry   = { "EventRegistry" },
  -- readers
  selectedQuest   = { "C_QuestLog.GetSelectedQuest" },
  titleFor        = { "C_QuestLog.GetTitleForQuestID" },
  questText       = { "GetQuestLogQuestText" },
  -- the shared QuestInfo fields [verified: mainline/questinfo.xml:728, 734, 749]
  title           = { "QuestInfoTitleHeader" },
  objectives      = { "QuestInfoObjectivesText" },
  description     = { "QuestInfoDescriptionText" },
  -- the shared QuestInfo labels [verified: mainline/questinfo.xml:366, 399, 423–503, 743, 746]
  descriptionHeader = { "QuestInfoDescriptionHeader" },
  objectivesHeader  = { "QuestInfoObjectivesHeader" },
  objectivesFrame   = { "QuestInfoObjectivesFrame" }, -- .Objectives: the objective FontStrings (questinfo.lua:199)
  learnLabel        = { "QuestInfoSpellObjectiveLearnLabel" },
  requiredMoney     = { "QuestInfoRequiredMoneyText" },
  groupSize         = { "QuestInfoGroupSize" },
  rewardsFrame      = { "QuestInfoRewardsFrame" },     -- the popup's rewards (mapView nil, questinfo.lua:59–67)
  mapRewardsFrame   = { "MapQuestInfoRewardsFrame" },  -- the map's rewards (mapView true) [verified: questinfo.xml:612]
  -- the details pane's buttons and strip (parentKey only: dotted paths) [verified: mainline/questmapframe.xml:694,
  -- 777, 807, 818, 843]
  backButton      = { "QuestMapFrame.QuestsFrame.DetailsFrame.BackFrame.BackButton" },
  rewardsLabel    = { "QuestMapFrame.QuestsFrame.DetailsFrame.RewardsFrameContainer.RewardsFrame.Label" },
  abandonButton   = { "QuestMapFrame.QuestsFrame.DetailsFrame.AbandonButton" },
  shareButton     = { "QuestMapFrame.QuestsFrame.DetailsFrame.ShareButton" },
  trackButton     = { "QuestMapFrame.QuestsFrame.DetailsFrame.TrackButton" },
  -- the waypoint buttons: their tooltipText is QUEST_WAYPOINT_FINAL / _ROUTE, shown on OnEnter as SetOwner →
  -- GameTooltip_AddColoredLine → Show [verified: mainline/questmapframe.xml:39–75, 713–742]
  destinationButton = { "QuestMapFrame.QuestsFrame.DetailsFrame.DestinationMapButton" },
  waypointButton  = { "QuestMapFrame.QuestsFrame.DetailsFrame.WaypointMapButton" },
  -- the popup's buttons [verified: mainline/questmapframe.xml:337–404]
  popupAbandon    = { "QuestLogPopupDetailFrameAbandonButton", "QuestLogPopupDetailFrame.AbandonButton" },
  popupTrack      = { "QuestLogPopupDetailFrameTrackButton", "QuestLogPopupDetailFrame.TrackButton" },
  popupShare      = { "QuestLogPopupDetailFrameShareButton", "QuestLogPopupDetailFrame.ShareButton" },
  popupShowMap    = { "QuestLogPopupDetailFrame.ShowMapButton.Text" },
  -- the list's fixed words [verified: mainline/questmapframe.xml:509, 515, 602, 634; questmapframe.lua:1241;
  -- camelot/questmapframeutils.lua:14–16]
  noResults       = { "QuestScrollFrame.NoSearchResultsText" },
  emptyText       = { "QuestScrollFrame.EmptyText" },
  searchHint      = { "QuestScrollFrame.SearchBox.Instructions" },
  questCount      = { "QuestLogQuestCount" },
}

local function get(key) return Compat.get(SURFACE, key) end

local function isText(w)
  return type(w) == "table" and type(w.GetText) == "function" and type(w.SetText) == "function"
end

local function hookScript(key, script, fn)
  local f = get(key)
  if type(f) == "table" and type(f.HookScript) == "function" then
    f:HookScript(script, fn)
    return true
  end
  return false
end

-- The details scroll frame's range callback lays out the rewards from QuestInfoFrame.rewardsFrame.numRows
-- (QuestLogQuestDetailsMixin:AdjustRewardsFrameContainer → QuestInfo_GetNumRewardRows, questinfo.lua:1065–1068,
-- questmapframe.lua:1015–1026), which is nil until QuestInfo_ShowRewards has run: a refit before then raised in
-- Blizzard's code. The client runs that layout itself once the rewards are shown, so the refit waits for them, and
-- an error in the client's callback is caught rather than shown.
local function rewardsReady()
  local info = Compat.resolve("QuestInfoFrame")
  local rewards = type(info) == "table" and info.rewardsFrame or nil
  return type(rewards) ~= "table" or type(rewards.numRows) == "number"
end

local function refitFor(scrollKey)
  return function()
    local scroll = get(scrollKey)
    if type(scroll) == "table" and type(scroll.UpdateScrollChildRect) == "function" and rewardsReady() then
      pcall(scroll.UpdateScrollChildRect, scroll)
    end
  end
end

-- ── labels ───────────────────────────────────────────────────────────────────────────────────────────────────────

local function named(key) return function() return get(key) end end
local function child(frameKey, field)
  return function()
    local f = get(frameKey)
    return type(f) == "table" and f[field] or nil
  end
end
local function xpReceive()
  local f = get("rewardsFrame")
  local xp = type(f) == "table" and f.XPFrame or nil
  return type(xp) == "table" and xp.ReceiveText or nil
end

-- Words both panes show through QuestInfo (the same widgets as the quest window, so the same record keys).
local QUESTINFO_LABELS = {
  { "ui.descriptionHeader", named("descriptionHeader") }, { "ui.objectivesHeader", named("objectivesHeader") },
  { "ui.learnLabel", named("learnLabel") }, { "ui.requiredMoney", named("requiredMoney") },
  { "ui.groupSize", named("groupSize") },
}
local MAP_LABELS = {
  -- "Back" is also INVTYPE_CLOAK's English (the cloak slot): the button takes BACK only, so it never shows the slot's
  -- Japanese.
  { "ui.back", named("backButton"), { only = { "BACK" } } }, { "ui.rewardsLabel", named("rewardsLabel") },
  { "ui.abandon", named("abandonButton") }, { "ui.share", named("shareButton") }, { "ui.track", named("trackButton") },
  { "ui.mapItemChoose", child("mapRewardsFrame", "ItemChooseText") },
  { "ui.mapItemReceive", child("mapRewardsFrame", "ItemReceiveText") },
  { "ui.mapPlayerTitle", child("mapRewardsFrame", "PlayerTitleText") },
}
-- The popup's rewards words are QuestInfoRewardsFrame's, the quest window's too (a shared widget).
local POPUP_INFO_LABELS = {
  { "ui.rewardsHeader", child("rewardsFrame", "Header") },
  { "ui.rewardsChoose", child("rewardsFrame", "ItemChooseText") },
  { "ui.rewardsReceive", child("rewardsFrame", "ItemReceiveText") },
  { "ui.rewardsTitle", child("rewardsFrame", "PlayerTitleText") }, { "ui.xpReceive", xpReceive },
}
local POPUP_LABELS = {
  { "ui.abandon", named("popupAbandon") }, { "ui.share", named("popupShare") }, { "ui.track", named("popupTrack") },
  { "ui.showMap", named("popupShowMap") },
}
local LIST_LABEL_ITEMS = {
  { "ui.noResults", named("noResults") }, { "ui.emptyText", named("emptyText") },
  { "ui.searchHint", named("searchHint") }, { "ui.questCount", named("questCount") },
}

local function showLabels(surface, lists, refit)
  local items = {}
  for _, list in ipairs(lists) do
    for _, l in ipairs(list) do items[#items + 1] = { l[1], l[2](), l[3] } end
  end
  return WFJ.Labels.showAll(surface, items, refit)
end

-- ── the two QuestInfo panes ──────────────────────────────────────────────────────────────────────────────────────

local PANES = {
  map   = { surface = SURFACE, info = INFO, refit = refitFor("detailsScroll"), infoLabels = { QUESTINFO_LABELS },
            labels = { MAP_LABELS }, track = "trackButton" },
  popup = { surface = POPUP, info = POPUP_INFO, refit = refitFor("popupScroll"),
            infoLabels = { QUESTINFO_LABELS, POPUP_INFO_LABELS }, labels = { POPUP_LABELS }, track = "popupTrack" },
}

-- Before a pane shows on the shared QuestInfo widgets: forget the other pane's shared records and the quest window's
-- (their records may still sit on these widgets, and their release would restore their English over ours). Only the
-- shared records: the panes' own buttons are untouched.
local function forgetOthers(info)
  for _, s in ipairs(QuestMap.QUESTINFO) do
    if s ~= info then WFJ.Render.forget(s) end
  end
  local QF = WFJ.QuestFrame
  if type(QF) == "table" and type(QF.forgetQuestInfo) == "function" then QF.forgetQuestInfo() end
end

local function showField(pane, field, en, id)
  local fs = get(field)
  local variant = field == "description" and type(WFJ.ShippedGossipKey) == "function"
    and not (type(WFJ.IsQuestFieldEnglish) == "function" and WFJ.IsQuestFieldEnglish(id, field, en))
      and WFJ.ShippedGossipKey(en)
  if variant and isText(fs) and fs:GetText() == en then
    -- a conditional description (another wording for this character), keyed by its English
    WFJ.Render.show(pane.info, field, fs, en, "quests", "gossip", variant, { refit = pane.refit, compact = true })
    return 1
  end
  if isText(fs) and type(en) == "string" and en ~= "" and fs:GetText() == en then
    -- live: the API English, for the stale marker's live check (ADR-019); compact below the title, so a quest
    -- gets one missing marker, on its title
    WFJ.Render.show(pane.info, field, fs, en, "quests", "quest." .. field, id,
      { refit = pane.refit, live = en, compact = field ~= "title" })
    return 1
  end
  WFJ.SurfaceState.drop(pane.info, field)
  return 0
end

-- The pane's objective lines: QuestInfo_ShowObjectives writes QuestInfoObjectivesFrame.Objectives[1..n] and
-- shows only the first n (mainline/questinfo.lua:194–250). Shared QuestInfo widgets, so on the pane's info surface.
local detailObjectiveKey = WFJ.Labels.keyer("objective.")
function QuestMap.showDetailObjectives(pane)
  local frame = get("objectivesFrame")
  local list = type(frame) == "table" and frame.Objectives or nil
  if type(list) ~= "table" then return 0 end
  local n = 0
  for _, fs in ipairs(list) do
    if type(fs) == "table" and (type(fs.IsShown) ~= "function" or fs:IsShown()) then
      n = n + QuestMap.showObjective(pane.info, detailObjectiveKey(fs), fs, pane.refit)
    end
  end
  return n
end

-- The selected quest on one pane: its three fields, then the pane's fixed words. → the number of fields shown
function QuestMap.showPane(paneName)
  local pane = PANES[paneName]
  forgetOthers(pane.info)
  local selected, titleFor, questText = get("selectedQuest"), get("titleFor"), get("questText")
  local id = type(selected) == "function" and type(titleFor) == "function" and type(questText) == "function"
    and selected() or nil
  if type(id) ~= "number" or id == 0 then
    WFJ.Render.forget(pane.info)
    WFJ.Render.forget(pane.surface)
    return 0
  end
  local title = titleFor(id)
  local description, objectives = questText()
  WFJ.Collector.record("quest", id, "title", title)
  WFJ.Collector.record("quest", id, "objectives", objectives)
  WFJ.Collector.record("quest", id, "description", description)
  local n = showField(pane, "title", title, id) + showField(pane, "objectives", objectives, id)
    + showField(pane, "description", description, id)
  QuestMap.showDetailObjectives(pane)
  showLabels(pane.info, pane.infoLabels, pane.refit)
  showLabels(pane.surface, pane.labels, pane.refit)
  return n
end

-- Called by UI/QuestFrame's QuestInfo_Display hook for every quest-log template. The map's rewards call
-- (QUEST_TEMPLATE_MAP_REWARDS into the rewards strip, :1051) writes only the rewards frame: its words are shown on the
-- details surface, nothing forgotten. Any other parent is not ours. → the number of fields (or labels) shown
function QuestMap.onDisplay(_, parentFrame)
  if parentFrame == nil then return 0 end
  if parentFrame == get("detailsContents") then return QuestMap.showPane("map") end
  if parentFrame == get("popupChild") then return QuestMap.showPane("popup") end
  if parentFrame == get("mapRewardsParent") then
    if WFJ.SurfaceState.count(SURFACE) == 0 then return 0 end -- the details write came first and found nothing
    return showLabels(SURFACE, { MAP_LABELS }, PANES.map.refit)
  end
  return 0
end

-- hooksecurefunc target on QuestMapFrame_UpdateQuestDetailsButtons: it rewrites both Track buttons
-- (TRACK_QUEST_ABBREV / UNTRACK_QUEST_ABBREV) after every details show and on watch-list changes (:1147–1153,
-- 538, 588, 594, 1101, 2612). Only a pane that is live (holds records) is re-shown. → the number of words shown
function QuestMap.onButtons()
  local n = 0
  for _, pane in pairs(PANES) do
    if WFJ.SurfaceState.count(pane.surface) > 0 then
      n = n + WFJ.Labels.show(pane.surface, "ui.track", get(pane.track), pane.refit)
      WFJ.Render.updateBanner(pane.surface)
    end
  end
  return n
end

-- ── objective lines ─────────────────────────────────────────────────────────────────────────────────────────────

-- The templates an objective line may be (Forever GlobalStrings): only these, so "3/10 …" is never read as another key.
QuestMap.OBJECTIVE_KEYS = { "QUEST_MONSTERS_KILLED", "QUEST_PLAYERS_KILLED", "QUEST_PLAYERS_KILLED_NOPROGRESS",
  "QUEST_FACTION_NEEDED", "QUEST_FACTION_NEEDED_NOPROGRESS",
  -- a finished quest's tracker line (blizzard_questobjectivetracker.lua:321-343)
  "QUEST_WATCH_QUEST_READY", "QUEST_WATCH_QUEST_COMPLETE", "QUEST_WATCH_CLICK_TO_COMPLETE" }

-- " (Complete)", which the details pane appends to a finished objective (mainline/questinfo.lua:238): its Japanese
-- through PARENS_TEMPLATE / COMPLETE, and the objective before it. → text before the tag, the tag's Japanese (with its
-- leading space) | text, ""
local function completeTag(en)
  local ui = WFJ.UIIndex
  local paren = en:match(" (%(.-%))$")
  if not paren or not ui then return en, "" end
  local key, args = ui:matchOnly(paren, { "PARENS_TEMPLATE" })
  local ja = key and ui:fill(ui.rows[key][1], args)
  if not ja then return en, "" end
  return en:sub(1, #en - #paren - 1), " " .. ja
end

-- A quest's completion log line ("Speak with Deathguard Billmuth at Tyr's Watch."), the line the tracker and the
-- quest log show once the quest is ready: quest-cache text keyed like NPC dialogue. → key | nil
local function completionLogKey(core)
  return type(WFJ.ShippedGossipKey) == "function" and WFJ.ShippedGossipKey(core) or nil
end

-- One objective line's Japanese without a record (a tooltip the client rebuilds every frame), by the same lookups as
-- showObjective. → Japanese | nil
function QuestMap.objectiveJapanese(en, surface)
  if type(en) ~= "string" or en == "" then return nil end
  local core, tag = completeTag(en)
  local ui, objectives = WFJ.UIIndex, WFJ.ObjectiveIndex
  local id, args, kind
  if objectives then id, args, kind = objectives:match(core) end
  if id then
    args.after = args.after .. tag
    return WFJ.Render.preview(surface, en, nil, "quests", kind, id, { args = args, compact = true })
  end
  local keyed = completionLogKey(core)
  if keyed then
    return WFJ.Render.preview(surface, en, nil, "quests", "gossip", keyed,
      { args = { form = "affix", before = "", after = tag }, compact = true })
  end
  local key
  if ui then key, args = ui:matchOnly(core, QuestMap.OBJECTIVE_KEYS) end
  if key then
    return WFJ.Render.preview(surface, en, nil, "quests", "ui", key,
      { args = { form = "affix", before = "", after = tag, inner = args }, compact = true })
  end
  return nil
end

-- One objective line on `fs` as record `recKey`. `refit` (optional) lays the line's owner out again after a write.
-- → 1 when shown (or still ours), else 0 and the record is dropped
function QuestMap.showObjective(surface, recKey, fs, refit)
  if not isText(fs) then
    WFJ.SurfaceState.drop(surface, recKey)
    return 0
  end
  local en = fs:GetText()
  local rec = WFJ.SurfaceState.get(surface, recKey)
  if rec and rec.fs == fs and rec.applied ~= nil and en == rec.applied then return 1 end
  if type(en) ~= "string" or en == "" then
    WFJ.SurfaceState.drop(surface, recKey)
    return 0
  end
  local core, tag = completeTag(en)
  local ui, objectives = WFJ.UIIndex, WFJ.ObjectiveIndex
  -- the objective's own text first: a server text that starts with a dictionary word ("Learn cooking from Tomas")
  -- must never be read as a client template. The index holds objective and area rows; `kind` names which.
  local id, args, kind
  if objectives then id, args, kind = objectives:match(core) end
  if id then
    args.after = args.after .. tag
    WFJ.Render.show(surface, recKey, fs, en, "quests", kind, id, { refit = refit, args = args, compact = true })
    return 1
  end
  local keyed = completionLogKey(core)
  if keyed then
    WFJ.Render.show(surface, recKey, fs, en, "quests", "gossip", keyed,
      { refit = refit, args = { form = "affix", before = "", after = tag }, compact = true })
    return 1
  end
  local key
  if ui then key, args = ui:matchOnly(core, QuestMap.OBJECTIVE_KEYS) end
  if key then
    WFJ.Render.show(surface, recKey, fs, en, "quests", "ui", key,
      { refit = refit, args = { form = "affix", before = "", after = tag, inner = args }, compact = true })
    return 1
  end
  WFJ.SurfaceState.drop(surface, recKey)
  return 0
end

-- ── titles in the list and the tracker ───────────────────────────────────────────────────────────────────────────

-- A title widget seen through its verbatim decoration: GetText returns the text between `prefix` and `suffix`,
-- SetText writes them back around it, GetFont / SetFont go to the widget. One adapter per widget (weak-keyed), so a
-- record keeps its widget identity across pooled reuse (SurfaceState: one record per widget); the decoration is set on
-- every show.
-- A decoration with words of its own ("%s (low level)") has a Japanese suffix too: written around a Japanese title,
-- the English one around the English title (the modifier held), and either is stripped when reading.
local adapters = setmetatable({}, { __mode = "k" })
local function decorated(fs, prefix, suffix, jaSuffix, en)
  local a = adapters[fs]
  if not a then
    a = { prefix = "", suffix = "" }
    function a.GetText()
      local text, p = fs:GetText(), a.prefix
      if type(text) ~= "string" or text:sub(1, #p) ~= p then return text end
      for _, x in ipairs({ a.suffix, a.jaSuffix }) do
        if (p ~= "" or x ~= "") and #text >= #p + #x and (x == "" or text:sub(-#x) == x) then
          return text:sub(#p + 1, #text - #x)
        end
      end
      return text
    end
    function a.SetText(_, text)
      local x = (a.jaSuffix and text ~= a.en) and a.jaSuffix or a.suffix
      fs:SetText(a.prefix .. (text or "") .. x)
    end
    function a.GetFont() return fs:GetFont() end
    function a.SetFont(_, path, size, flags) return fs:SetFont(path, size, flags) end
    adapters[fs] = a
  end
  a.prefix, a.suffix, a.jaSuffix, a.en = prefix, suffix, jaSuffix, en
  return a
end

-- camelot's level prefix: "[" .. level .. ("+" for elite) .. "] " (list) or "[" .. level .. "] " (tracker). → the
-- prefix and the rest, or nil
local function splitPrefix(text)
  if type(text) ~= "string" then return nil end
  local p = text:match("^%[%d+%+?%] ")
  if not p then return nil end
  return p, text:sub(#p + 1)
end
QuestMap.splitPrefix = splitPrefix

-- The decorations a title may carry around its API English, kept verbatim: camelot's level prefix, and the tracker's
-- difficulty colour wrap "|cAARRGGBB" .. title .. "|r" around it (SetQuestTitleLevelAndDifficultyColor with
-- showQuestDifficultyColor on: difficultyutil.lua:84–96). → prefix, suffix | nil (any other decoration)
-- The quest-row wrappers with words of their own (the talk and quest windows, gossipframeshared.lua:27–39,
-- questframe.lua): split around their "%s", with the dictionary's Japanese suffix. → prefix, suffix, jaSuffix | nil
local WRAPPERS = { "TRIVIAL_QUEST_DISPLAY", "IGNORED_QUEST_DISPLAY" }
local function wrapper(text, en)
  for _, key in ipairs(WRAPPERS) do
    local template = Compat.resolve(key)
    local head, tail
    if type(template) == "string" then head, tail = template:match("^(.-)%%s(.*)$") end
    if head and text == head .. en .. tail then
      local entry = WFJ.Lookup.get("ui", key)
      local jaHead, jaTail
      if type(entry) == "table" and type(entry.ja) == "string" then jaHead, jaTail = entry.ja:match("^(.-)%%s(.*)$") end
      return head, tail, (jaHead == head and jaTail) or nil
    end
  end
  return nil
end

local function decoration(text, en)
  if type(text) ~= "string" or type(en) ~= "string" then return nil end
  if text == en then return "", "" end
  local wp, ws, wj = wrapper(text, en)
  if wp then return wp, ws, wj end
  local color, inner = text:match("^(|c%x%x%x%x%x%x%x%x)(.*)|r$")
  local head, suffix = color or "", color and "|r" or ""
  inner = inner or text
  if color and inner == en then return head, suffix end
  local p, rest = splitPrefix(inner)
  if p and rest == en then return head .. p, suffix end
  return nil
end
QuestMap.decoration = decoration

-- Drops `key` and any other record on this widget's adapter: a reused block or row that no longer shows its old quest
-- must not keep that quest's record (and its font) for the rest of the session.
local function dropWidget(surface, key, fs)
  if key then WFJ.SurfaceState.drop(surface, key) end
  local a = type(fs) == "table" and adapters[fs] or nil
  if not a then return end
  for k, rec in pairs(WFJ.SurfaceState.records(surface)) do
    if rec.fs == a then WFJ.SurfaceState.drop(surface, k) end
  end
end

-- One quest title on a list row or a tracker header. `refit` (optional) lays the widget's owner out again after a
-- write. → 1 when shown, else 0 (and that quest's record, and any other on the widget, is dropped)
QuestMap.dropWidget = dropWidget

local function showTitle(surface, questID, fs, refit, given, row)
  local key = "title." .. tostring(questID)
  local titleFor = get("titleFor")
  local canRead = type(fs) == "table" and type(fs.GetText) == "function" and type(fs.SetText) == "function"
    and type(fs.GetFont) == "function" and type(fs.SetFont) == "function"
  if type(questID) ~= "number" or questID == 0 or type(titleFor) ~= "function" or not canRead then
    dropWidget(surface, key, fs)
    return 0
  end
  -- `given`: the title the caller's API returned (an offered quest is not in the log, so titleFor has none)
  local en = given or titleFor(questID)
  if type(en) ~= "string" or en == "" then
    dropWidget(surface, key, fs)
    return 0
  end
  WFJ.Collector.record("quest", questID, "title", en)
  local prefix, suffix, jaSuffix = decoration(fs:GetText(), en)
  -- the adapter may already carry this widget's record (our Japanese inside the decoration): same record
  local a = adapters[fs]
  local rec = WFJ.SurfaceState.get(surface, key)
  if not prefix and a and rec and rec.fs == a and rec.applied ~= nil and a.GetText() == rec.applied then return 1 end
  if not prefix then
    dropWidget(surface, key, fs)
    return 0
  end
  WFJ.Render.show(surface, key, decorated(fs, prefix, suffix, jaSuffix, en), en, "quests", "quest.title", questID,
    { live = en, refit = refit, compact = true, row = row })
  return 1
end
QuestMap.showTitle = showTitle

-- A list objective row: keyed by the row frame (pooled, so never a position); its height follows a line that wraps
-- differently in Japanese. The client sized the quest's title button to the sum of its English heights
-- (questmapframe.lua:1885, 1899–1925, 1959–1961), so the height change goes into the title button too and the list
-- is laid out again (Contents:Layout(), as QuestLogQuests_Update does at :2162): once per list update, or at once for
-- a later rewrite (the modifier).
local listObjectiveKey = WFJ.Labels.keyer("objective.")
local listTagKey = WFJ.Labels.keyer("tag.")
local listHeaderKey = WFJ.Labels.keyer("header.")
local listRefits = setmetatable({}, { __mode = "k" })
local titleButtons = {} -- questID → the list's title button, rebuilt on every list update
local listBatch -- true while onListUpdate walks the rows: one Layout at its end
local listMoved = false

local function relayoutList()
  if listBatch then listMoved = true; return end
  local scroll = get("listScroll")
  local contents = type(scroll) == "table" and scroll.Contents or nil
  if type(contents) == "table" and type(contents.Layout) == "function" then contents:Layout() end
end

-- Moves the title button of `questID` by `delta` (a row or its title changed height).
local function growTitle(questID, delta)
  local button = titleButtons[questID]
  if delta == 0 or type(button) ~= "table" or type(button.GetHeight) ~= "function"
      or type(button.SetHeight) ~= "function" then return end
  local h = button:GetHeight()
  if type(h) ~= "number" then return end
  button:SetHeight(h + delta)
  relayoutList()
end

local function listObjectiveRefit(row)
  local fn = listRefits[row]
  if fn then return fn end
  fn = function()
    local fs = row.Text
    if type(fs) ~= "table" or type(fs.GetStringHeight) ~= "function" then return end
    if type(row.SetHeight) ~= "function" then return end
    local h = fs:GetStringHeight()
    if type(h) == "number" and h > 0 then
      local old = type(row.GetHeight) == "function" and row:GetHeight() or nil
      row:SetHeight(h)
      if type(old) == "number" then growTitle(row.questID, h - old) end
    end
  end
  listRefits[row] = fn
  return fn
end

-- A title's own wrap: the button grows by the title's height change.
local titleHeights = setmetatable({}, { __mode = "k" }) -- title FontString → the height the button was sized on
local titleRefits = setmetatable({}, { __mode = "k" })
local function listTitleRefit(button)
  local fn = titleRefits[button]
  if fn then return fn end
  fn = function()
    local fs = button.Text
    if type(fs) ~= "table" or type(fs.GetHeight) ~= "function" then return end
    local h, old = fs:GetHeight(), titleHeights[fs]
    if type(h) ~= "number" then return end
    titleHeights[fs] = h
    if type(old) == "number" and titleButtons[button.questID] == button then growTitle(button.questID, h - old) end
  end
  titleRefits[button] = fn
  return fn
end

-- camelot's elite tag: button.TagText holds PARENS_TEMPLATE:format(ELITE), its own FontString
-- (camelot/questmapframeoverrides.lua:19–21; mainline/questmapframe.lua:1833–1836). Only that template.
local TAG_ONLY = { only = { "PARENS_TEMPLATE" } }

-- hooksecurefunc target on QuestLogQuests_Update: the client released every row and wrote the active ones; our
-- records from before are forgotten (their widgets are rewritten or hidden), then every active row is walked
-- [verified: mainline/questmapframe.lua:2105, 1228; pools: blizzard_sharedxmlbase/pools.lua:166–168]. The list's
-- fixed words follow. → the number of titles shown
function QuestMap.onListUpdate()
  WFJ.Render.forget(LIST)
  titleButtons = {}
  listBatch, listMoved = true, false
  local n = 0
  local scroll = get("listScroll")
  local pool = type(scroll) == "table" and scroll.titleFramePool or nil
  local ok, err = pcall(function()
    if type(pool) == "table" and type(pool.EnumerateActive) == "function" then
      for button in pool:EnumerateActive() do
        if type(button) == "table" then
          if type(button.questID) == "number" then titleButtons[button.questID] = button end
          local fs = button.Text
          if type(fs) == "table" and type(fs.GetHeight) == "function" then titleHeights[fs] = fs:GetHeight() end
          n = n + showTitle(LIST, button.questID, fs, listTitleRefit(button))
          if type(button.TagText) == "table" then
            WFJ.Labels.show(LIST, listTagKey(button.TagText), button.TagText, nil, TAG_ONLY)
          end
        end
      end
    end
    -- the category headers (ADR-042) (QuestLogQuests_AddStandardHeaderButton → button:SetText(info.title),
    -- mainline/questmapframe.lua:2044–2048; ListHeaderVisualTemplate's title region). A header is a zone name or a
    -- QuestSort word ("Seasonal", "Epic"); only the QuestSort family is matched, so a zone name is never changed.
    local headers = type(scroll) == "table" and scroll.headerFramePool or nil
    if type(headers) == "table" and type(headers.EnumerateActive) == "function" then
      for header in headers:EnumerateActive() do
        if type(header) == "table" then
          local fs = header
          if type(header.GetTitleRegion) == "function" then
            local okT, title = pcall(header.GetTitleRegion, header)
            if okT and type(title) == "table" then fs = title end
          end
          WFJ.Labels.show(LIST, listHeaderKey(header), fs, nil, WFJ.Labels.families("QuestSort"))
        end
      end
    end
    -- the rows' objective lines; a complete quest's row is its completion text (GetQuestLogCompletionText), which
    -- for a quest with no counted objectives is the quest's whole objective text, shown as the tracker shows it
    -- [verified: blizzard_uipanels_game/mainline/questmapframe.lua:1891–1896, row.questID :1893]
    local objectives = type(scroll) == "table" and scroll.objectiveFramePool or nil
    if type(objectives) == "table" and type(objectives.EnumerateActive) == "function" then
      for row in objectives:EnumerateActive() do
        if type(row) == "table" then
          local key, refit = listObjectiveKey(row), listObjectiveRefit(row)
          if QuestMap.showObjective(LIST, key, row.Text, refit) == 0 then
            QuestMap.showQuestText(LIST, key, row.Text, row.questID, refit)
          end
        end
      end
    end
  end)
  listBatch = false
  if listMoved then relayoutList() end
  if not ok then error(err, 0) end
  WFJ.Render.updateBanner(LIST)
  QuestMap.showListLabels()
  return n
end

function QuestMap.showListLabels()
  return showLabels(LIST_LABELS, { LIST_LABEL_ITEMS })
end

-- The tracker's fixed headers. "Quests" and "All Objectives" are short words another key may share, so each header
-- takes only its own key. Always-visible chrome: never released (the modifier and toggles still refresh it).
local TRACKER_LABEL_ITEMS = {
  { "ui.trackerAll", named("trackerAllHeader"), { only = { "TRACKER_ALL_OBJECTIVES" } } },
  { "ui.trackerQuests", named("questsHeader"), { only = { "TRACKER_HEADER_QUESTS" } } },
}
function QuestMap.showTrackerLabels()
  return showLabels(TRACKER_LABELS, { TRACKER_LABEL_ITEMS })
end

-- The window title: only the three words the map can be titled with (a title is never matched as free text).
local MAP_TITLE_ONLY = { only = { "MAP_AND_QUEST_LOG", "WORLD_MAP", "QUEST_LOG" } }
QuestMap.MAP_TITLE_KEYS = MAP_TITLE_ONLY.only

-- The map's title: at init, after every BorderFrame:SetTitle (Labels.title's hook) and on WorldMapFrame's OnShow.
-- → 1 | 0
function QuestMap.showMapTitle()
  local n = WFJ.Labels.title(MAP_TITLE, get("worldMapBorder"), MAP_TITLE_ONLY)
  WFJ.Render.updateBanner(MAP_TITLE)
  return n
end

-- ── tracker headers ──────────────────────────────────────────────────────────────────────────────────────────────
-- ObjectiveTrackerBlockMixin:SetHeader writes the English, measures HeaderText:GetHeight() and stores it as
-- block.height; AddObjective then adds each line's height and LayoutBlock sizes the block from block.height, the next
-- block anchored to its BOTTOM [verified: blizzard_objectivetrackerblock.lua:134–158, 161–205;
-- blizzard_objectivetrackermodule.lua:254–282, 341–354, 422–446]. block.height is never written here: the module adds
-- it into its contentsHeight (module.lua:417), which the container and Edit Mode's layout pass read, so a value this
-- addon wrote there taints that whole pass (in game: the action bars' protected SetPoint blocked, the scenario
-- tracker's aura read refused). The height the Japanese adds or removes is kept in `extra` instead and put on the
-- block's frame only: after LayoutBlock (a post-hook on the module), and at once when a refit runs after the layout
-- (the modifier, a toggle). The module's frame is sized the same way: UpdateHeight sets it from contentsHeight
-- (module.lua:223–231) and the container anchors the next module and the background to its bottom (container.lua:
-- 100–118), so a post-hook on UpdateHeight adds its blocks' extra to the frame, never to contentsHeight. contentsHeight
-- stays the English one, so a tracker near its height limit may cut a block a line early or late [in-game check: a
-- long title with the tracker near its height limit].
local headerBase = setmetatable({}, { __mode = "k" }) -- block → its header's height in the English, at SetHeader
local extra = setmetatable({}, { __mode = "k" }) -- block → { header = px, lines = { [line] = px } }
local blockRefits = setmetatable({}, { __mode = "k" })
local blocksHooked = setmetatable({}, { __mode = "k" })
local blockModule = setmetatable({}, { __mode = "k" }) -- block → the module that last laid it out
local moduleBase = setmetatable({}, { __mode = "k" }) -- module → the frame height its own UpdateHeight gave it

local function extraOf(block)
  local e = extra[block]
  if not e then return 0 end
  local total = e.header or 0
  -- a line counts only while the block holds it: Reset clears `used` to nil and FreeLine leaves parentBlock set
  -- [verified: blizzard_objectivetrackerblock.lua:39–40, 98–101]
  local held = type(block.usedLines) == "table" and block.usedLines or {}
  for line, px in pairs(e.lines) do
    if line.used and held[line.objectiveKey] == line then total = total + px end
  end
  return total
end

-- The module's frame at the client's height plus its laid-out blocks' extra.
function QuestMap.sizeModule(module)
  local base = moduleBase[module]
  if type(base) ~= "number" or type(module.SetHeight) ~= "function" then return end
  local px = 0
  for block, m in pairs(blockModule) do
    if m == module and block.used ~= false then px = px + extraOf(block) end
  end
  module:SetHeight(base + px)
end
-- post-hook on a tracker module's UpdateHeight
local function onModuleHeight(module)
  if type(module) ~= "table" or type(module.GetHeight) ~= "function" then return end
  moduleBase[module] = module:GetHeight()
  QuestMap.sizeModule(module)
end

-- The block's frame at the client's height plus ours, and its module's frame with it.
function QuestMap.sizeBlock(block)
  if type(block) ~= "table" or type(block.height) ~= "number" or type(block.SetHeight) ~= "function" then return end
  if not extra[block] then return end
  local want = block.height + extraOf(block)
  if type(block.GetHeight) == "function" and math.abs(block:GetHeight() - want) <= 0.5 then return end
  block:SetHeight(want)
  if blockModule[block] then QuestMap.sizeModule(blockModule[block]) end
end
-- post-hook on a tracker module's LayoutBlock(block)
local function onLayoutBlock(module, block)
  if type(block) == "table" then blockModule[block] = module end
  QuestMap.sizeBlock(block)
end

local function blockRefit(block)
  local fn = blockRefits[block]
  if fn then return fn end
  fn = function()
    local fs = block.HeaderText
    if type(fs) ~= "table" or type(fs.GetHeight) ~= "function" then return end
    local h, base = fs:GetHeight(), headerBase[block]
    if type(h) ~= "number" or type(base) ~= "number" then return end
    local e = extra[block] or { lines = {} }
    extra[block] = e
    if e.header == h - base then return end
    e.header = h - base
    QuestMap.sizeBlock(block)
  end
  blockRefits[block] = fn
  return fn
end

-- hooksecurefunc target on a block's SetHeader (and the late path below): a new layout of the block starts, so the
-- height ours added is measured again. → 1 | 0
function QuestMap.onBlockHeader(block)
  if type(block) ~= "table" then return 0 end
  local fs = block.HeaderText
  if type(fs) == "table" and type(fs.GetHeight) == "function" then headerBase[block] = fs:GetHeight() end
  extra[block] = { header = 0, lines = {} }
  local n = showTitle(TRACKER, block.id, fs, blockRefit(block))
  WFJ.Render.updateBanner(TRACKER)
  return n
end

-- ── tracker objective lines ─────────────────────────────────────────────────────────────────────────────────────
-- AddObjective sets the line's text, sizes the line to the text's height and adds that height to block.height; the
-- layout then sizes the block from block.height (blizzard_objectivetrackerblock.lua:161–209). A post-hook on the
-- BLOCK's AddObjective translates the line before the layout; its refit sizes the line to the Japanese and keeps the
-- difference in the block's `extra` (block.height is never written, above), only while the line is still sized to
-- its text (an overrideHeight line is left as the client sized it).
local lineHeights = setmetatable({}, { __mode = "k" }) -- line → its text height in the English, at AddObjective
local lineSizes = setmetatable({}, { __mode = "k" }) -- line → the height this addon last gave it
local lineRefits = setmetatable({}, { __mode = "k" })
local trackerObjectiveKey = WFJ.Labels.keyer("line.")

local function lineRefit(block, line)
  local fn = lineRefits[line]
  if fn and fn.block == block then return fn.run end
  fn = { block = block }
  fn.run = function()
    local fs = line.Text
    if type(fs) ~= "table" or type(fs.GetHeight) ~= "function" or type(line.GetHeight) ~= "function" then return end
    local h, base = fs:GetHeight(), lineHeights[line]
    if type(h) ~= "number" or type(base) ~= "number" then return end
    local sized = lineSizes[line] or base
    if math.abs(line:GetHeight() - sized) > 0.5 then return end
    -- a freed line keeps its text and our record, but it is no longer this block's
    if line.parentBlock ~= block or not line.used then return end
    if h == sized then return end
    line:SetHeight(h)
    lineSizes[line] = h
    local e = extra[block] or { lines = {} }
    extra[block] = e
    e.lines[line] = h - base
    QuestMap.sizeBlock(block)
  end
  lineRefits[line] = fn
  return fn.run
end

-- hooksecurefunc target on a block's AddObjective(objectiveKey, text, …). → 1 | 0
function QuestMap.onAddObjective(block, objectiveKey)
  local lines = type(block) == "table" and block.usedLines or nil
  local line = type(lines) == "table" and lines[objectiveKey] or nil
  if type(line) ~= "table" or type(line.Text) ~= "table" then return 0 end
  local fs = line.Text
  if type(fs.GetHeight) == "function" then lineHeights[line], lineSizes[line] = fs:GetHeight(), nil end
  if extra[block] then extra[block].lines[line] = nil end -- re-added: measured again from the English
  local recKey, refit = trackerObjectiveKey(line), lineRefit(block, line)
  local n = QuestMap.showObjective(TRACKER_OBJECTIVES, recKey, fs, refit)
  if n == 0 then n = QuestMap.showQuestText(TRACKER_OBJECTIVES, recKey, fs, block.id, refit) end
  WFJ.Render.updateBanner(TRACKER_OBJECTIVES)
  return n
end

-- A quest with no counted objectives shows its whole objective text as one tracker line
-- (GetQuestLogCompletionText falls back to it; blizzard_questobjectivetracker.lua:326-336): the line is that quest's
-- own text when its hash is the quest's objectives hash. → 1 | 0
function QuestMap.showQuestText(surface, recKey, fs, questID, refit)
  if type(questID) ~= "number" or not isText(fs) then return 0 end
  local en = fs:GetText()
  if type(en) ~= "string" or en == "" then return 0 end
  -- the quest's objectives English, read as the live check reads it (player words, the female variant)
  if type(WFJ.IsQuestFieldEnglish) ~= "function" or not WFJ.IsQuestFieldEnglish(questID, "objectives", en) then
    return 0
  end
  -- a list or tracker row: compact (never the missing marker inline), checked against the live English
  return WFJ.Render.show(surface, recKey, fs, en, "quests", "quest.objectives", questID,
    { refit = refit, compact = true, live = en }) and 1 or 0
end

-- ── content-tracking lines ──────────────────────────────────────────────────────────────────────────────────────
-- AdventureObjectiveTrackerMixin:ProcessTrackingEntry writes a tracked appearance / encounter / vendor block: its
-- header is the tracked thing's name (C_ContentTracking.GetTitle, never touched: no SetHeader hook here), line 1 the
-- server's objective text or CONTENT_TRACKING_RETRIEVING_INFO, line 2 CONTENT_TRACKING_LOCATION_UNAVAILABLE /
-- _ROUTE_UNAVAILABLE or OPTIONAL_QUEST_OBJECTIVE_DESCRIPTION:format(waypointText) (the waypoint text kept)
-- [verified: blizzard_adventureobjectivetracker.lua:139–180]. Each line is matched only against these four keys,
-- from the block's AddObjective post-hook (before LayoutBlock), with the quest lines' height refit. The module's
-- blocks come from its own pool (ObjectiveTrackerManager:AcquireFrame keys pools by parent, manager.lua:61–74).
QuestMap.CONTENT_TRACKING_KEYS = { "CONTENT_TRACKING_RETRIEVING_INFO", "CONTENT_TRACKING_LOCATION_UNAVAILABLE",
  "CONTENT_TRACKING_ROUTE_UNAVAILABLE", "OPTIONAL_QUEST_OBJECTIVE_DESCRIPTION" }
local CONTENT_ONLY = { only = QuestMap.CONTENT_TRACKING_KEYS }
local contentBlocksHooked = setmetatable({}, { __mode = "k" })

-- hooksecurefunc target on a content-tracking block's AddObjective(objectiveKey, text, …). → 1 | 0
function QuestMap.onContentObjective(block, objectiveKey)
  local lines = type(block) == "table" and block.usedLines or nil
  local line = type(lines) == "table" and lines[objectiveKey] or nil
  if type(line) ~= "table" or type(line.Text) ~= "table" then return 0 end
  local fs = line.Text
  if type(fs.GetHeight) == "function" then lineHeights[line], lineSizes[line] = fs:GetHeight(), nil end
  if extra[block] then extra[block].lines[line] = nil end -- re-added: measured again from the English
  local n = WFJ.Labels.show(TRACKER_OBJECTIVES, trackerObjectiveKey(line), fs, lineRefit(block, line), CONTENT_ONLY)
  WFJ.Render.updateBanner(TRACKER_OBJECTIVES)
  return n
end

-- hooksecurefunc target on the content-tracking module's GetBlock(id, template).
function QuestMap.onContentBlock(module, id, template)
  if type(module) ~= "table" or type(module.GetExistingBlock) ~= "function" then return end
  local block = module:GetExistingBlock(id, template)
  -- GetBlock resets the block for a new layout and a content block has no SetHeader hook: its extra starts over here
  if type(block) == "table" then extra[block] = nil end
  if type(block) ~= "table" or contentBlocksHooked[block] or type(block.AddObjective) ~= "function" then return end
  contentBlocksHooked[block] = true
  hooksecurefunc(block, "AddObjective", QuestMap.onContentObjective)
end

-- → true when the block was hooked now
local function hookBlock(block)
  if type(block) ~= "table" or blocksHooked[block] or type(block.SetHeader) ~= "function" then return false end
  blocksHooked[block] = true
  hooksecurefunc(block, "SetHeader", QuestMap.onBlockHeader)
  if type(block.AddObjective) == "function" then hooksecurefunc(block, "AddObjective", QuestMap.onAddObjective) end
  return true
end

-- hooksecurefunc target on a module's GetBlock(id, template): the block is in usedBlocks now and its SetHeader has not
-- run yet (UpdateSingle: GetBlock, then SetHeader; blizzard_questobjectivetracker.lua:297–307).
function QuestMap.onGetBlock(module, id, template)
  if type(module) ~= "table" or type(module.GetExistingBlock) ~= "function" then return end
  hookBlock(module:GetExistingBlock(id, template))
end

-- hooksecurefunc target on a quest tracker module's UpdateSingle(quest): the tracker's fixed headers, and a block not
-- hooked yet (built before we loaded, so its header was written without us) is hooked now and translated after the
-- layout; the refit corrects its height. → 1 | 0
function QuestMap.onTrackerUpdate(module, quest)
  QuestMap.showTrackerLabels() -- a cheap no-op while they are still ours
  if type(module) ~= "table" or type(quest) ~= "table" or type(quest.GetID) ~= "function" then return 0 end
  local questID = quest:GetID()
  if type(questID) ~= "number" or type(module.GetExistingBlock) ~= "function" then return 0 end
  local block = module:GetExistingBlock(questID)
  if type(block) ~= "table" or block.id ~= questID then return 0 end
  if hookBlock(block) then
    -- built before we loaded: its lines were written without us too. The header first: it starts the block's
    -- extra over, which would otherwise drop the lines' just recorded
    local n = QuestMap.onBlockHeader(block)
    if type(block.usedLines) == "table" then
      for objectiveKey in pairs(block.usedLines) do QuestMap.onAddObjective(block, objectiveKey) end
    end
    return n
  end
  return 0
end

-- ── the list title's tooltip ────────────────────────────────────────────────────────────────────────────────────
-- The title button's GameTooltip: the title, its objective lines (the client's templates), "<Click to view Quest
-- Details>" (CLICK_QUEST_DETAILS, a whole line of its own, questmapframe.lua:2290) and party lines. Walked once
-- through UI/HelpTooltip with only these keys, so the quest title and the party members' names are never read.
-- In gamepad mode the click line is "<input icon>Toggle Focus on Quest" and "<input icon>More" instead
-- (GameTooltip_AddLineWithInputIcon, questmapframe.lua:2292–2294; UIStrings `icon` form)
QuestMap.TITLE_TOOLTIP_KEYS = { "CLICK_QUEST_DETAILS", "MAP_PIN_TOGGLE_QUEST_FOCUS",
  "CONTEXT_ACTION_LABEL_MORE_ACTIONS",
  -- the gamepad line between them and the party line after them (questmapframe.lua:2293, 2299)
  "OBJECTIVES_VIEW_IN_QUESTLOG", "PARTY_QUEST_STATUS_ON" }
for _, k in ipairs(QuestMap.OBJECTIVE_KEYS) do QuestMap.TITLE_TOOLTIP_KEYS[#QuestMap.TITLE_TOOLTIP_KEYS + 1] = k end

-- Each leaderboard line is written as QUEST_DASH .. text (questmapframe.lua:2270): the dash is kept and
-- the rest goes through the objective lookup (showObjective: the objective's own text, then OBJECTIVE_KEYS), recorded
-- on the help surface under the line's own key so the tooltip's refit and release are HelpTooltip's. The money line
-- (:2281) matches nothing and stays.
local dashAdapters = setmetatable({}, { __mode = "k" })
local function dashed(fs, dash)
  local a = dashAdapters[fs]
  if not a then
    a = {}
    function a.GetText()
      local text = fs:GetText()
      if type(text) == "string" and text:sub(1, #dash) == dash then return text:sub(#dash + 1) end
      return text
    end
    function a.SetText(_, text) fs:SetText(dash .. (text or "")) end
    function a.GetFont() return fs:GetFont() end
    function a.SetFont(_, path, size, flags) return fs:SetFont(path, size, flags) end
    dashAdapters[fs] = a
  end
  return a
end

-- The EventRegistry callback (owner, button, questID). → the number of dictionary lines
function QuestMap.onTitleTooltip()
  local help = WFJ.HelpTooltip
  local n = help.walkAs(nil, { only = QuestMap.TITLE_TOOLTIP_KEYS })
  local tt = Compat.get(help.SURFACE, "tooltip")
  local dash = Compat.resolve("QUEST_DASH")
  if type(tt) ~= "table" or type(tt.NumLines) ~= "function" or type(tt.GetName) ~= "function"
      or type(dash) ~= "string" or dash == "" then return n end
  local name = tt:GetName()
  for i = 2, tt:NumLines() or 0 do -- line 1 is the quest's title
    local fs = Compat.resolve(name .. "TextLeft" .. i)
    local text = type(fs) == "table" and type(fs.GetText) == "function" and fs:GetText() or nil
    if type(text) == "string" and #text > #dash and text:sub(1, #dash) == dash then
      n = n + QuestMap.showObjective(help.SURFACE, "L" .. i, dashed(fs, dash), help.refit)
    end
  end
  return n
end

-- ── release / init ───────────────────────────────────────────────────────────────────────────────────────────────

function QuestMap.releaseDetails() return WFJ.Render.release(INFO) + WFJ.Render.release(SURFACE) end
function QuestMap.releasePopup() return WFJ.Render.release(POPUP_INFO) + WFJ.Render.release(POPUP) end
function QuestMap.releaseList() return WFJ.Render.release(LIST) + WFJ.Render.release(LIST_LABELS) end
function QuestMap.releaseMapTitle() return WFJ.Render.release(MAP_TITLE) end

local trackersHooked = setmetatable({}, { __mode = "k" })

-- The tracker modules live in Blizzard_ObjectiveTracker; they are hooked once that addon is present. → the number
-- hooked now
function QuestMap.hookTrackers()
  local n = 0
  for _, key in ipairs({ "questTracker", "campaignTracker", "adventureTracker", "trackerFrame", "trackerAllHeader",
    "questsHeader" }) do
    Compat.declare(SURFACE, key, CANDIDATES[key]) -- re-resolve: the addon may have loaded after the first lookup
  end
  local function hookMethod(key, method, fn)
    local t = get(key)
    local done = type(t) == "table" and trackersHooked[t] or nil
    if type(t) ~= "table" or type(t[method]) ~= "function" or (done and done[method]) then return end
    done = done or {}
    done[method] = true
    trackersHooked[t] = done
    hooksecurefunc(t, method, fn)
    n = n + 1
  end
  hookMethod("questTracker", "GetBlock", QuestMap.onGetBlock)
  hookMethod("campaignTracker", "GetBlock", QuestMap.onGetBlock)
  hookMethod("questTracker", "UpdateSingle", QuestMap.onTrackerUpdate)
  hookMethod("campaignTracker", "UpdateSingle", QuestMap.onTrackerUpdate)
  hookMethod("adventureTracker", "GetBlock", QuestMap.onContentBlock)
  for _, key in ipairs({ "questTracker", "campaignTracker", "adventureTracker" }) do
    hookMethod(key, "LayoutBlock", onLayoutBlock) -- the block's frame takes the height the Japanese adds
    hookMethod(key, "UpdateHeight", onModuleHeight) -- and so does the module's frame
  end
  -- the headers' writers, called by method on the instance (a later Init / SetHeader); both already ran once for a
  -- tracker loaded before us, so the headers are shown now too
  hookMethod("trackerFrame", "Init", QuestMap.showTrackerLabels)
  hookMethod("questTracker", "SetHeader", QuestMap.showTrackerLabels)
  QuestMap.showTrackerLabels()
  return n
end

local hooked = false

-- The details pane's markers go on one line right of its back button, the one free spot at the top: inline, the
-- message pushed the description down and read as part of it. The popup pane has no back button and keeps them
-- inline. → true when the banner was made
QuestMap.BANNER_GAP, QuestMap.BANNER_WIDTH = 8, 200
function QuestMap.makeBanner()
  local back = get("backButton")
  if QuestMap.banner or type(back) ~= "table" or type(back.GetParent) ~= "function"
      or type(back:GetParent()) ~= "table" then
    return false
  end
  QuestMap.banner, QuestMap.bannerFrame =
    WFJ.Render.createBannerBeside(back, QuestMap.BANNER_GAP, QuestMap.BANNER_WIDTH)
  WFJ.Render.setBanner(SURFACE, QuestMap.banner)
  WFJ.Render.setBanner(INFO, QuestMap.banner)
  return true
end

-- Called by Main after Compat.init. Declares the candidates and hooks the writers that resolve.
function QuestMap.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  if hooked then return false end
  hooked = true
  WFJ.Labels.forbidNames(QuestMap.NEVER_TOUCH)
  -- The waypoint buttons' one-line tooltips go through UI/HelpTooltip, each owner taking only its own key.
  local help = WFJ.HelpTooltip
  if type(help) == "table" and type(help.register) == "function" then
    help.register(get("destinationButton"), { only = { "QUEST_WAYPOINT_FINAL" } })
    help.register(get("waypointButton"), { only = { "QUEST_WAYPOINT_ROUTE" } })
  end
  if type(get("detailsButtons")) == "function" then
    hooksecurefunc("QuestMapFrame_UpdateQuestDetailsButtons", QuestMap.onButtons)
  end
  if type(get("listUpdate")) == "function" then hooksecurefunc("QuestLogQuests_Update", QuestMap.onListUpdate) end
  local registry = get("eventRegistry")
  if type(get("listUpdate")) == "function" and type(registry) == "table"
      and type(registry.RegisterCallback) == "function" then
    registry:RegisterCallback("QuestMapLogTitleButton.OnEnter", QuestMap.onTitleTooltip, QuestMap)
  end
  QuestMap.makeBanner()
  hookScript("details", "OnHide", QuestMap.releaseDetails)
  hookScript("popup", "OnHide", QuestMap.releasePopup)
  hookScript("mapFrame", "OnHide", QuestMap.releaseList)
  -- the window title: Blizzard_WorldMap loads at login, so there is no load-on-demand wait
  hookScript("worldMap", "OnShow", QuestMap.showMapTitle)
  hookScript("worldMap", "OnHide", QuestMap.releaseMapTitle)
  QuestMap.showMapTitle()
  local LOD = WFJ.LoadOnDemand
  if type(LOD) == "table" and type(LOD.when) == "function" then
    LOD.when("Blizzard_ObjectiveTracker", QuestMap.hookTrackers)
  else
    QuestMap.hookTrackers()
  end
  return true
end
