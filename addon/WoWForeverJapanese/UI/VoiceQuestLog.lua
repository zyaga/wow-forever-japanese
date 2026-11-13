-- UI/VoiceQuestLog.lua: the quest log's play / pause button and the remembered speaker (ADR-063).
--   * The quest log (the world map's quest pane) shows a quest's text but plays nothing by itself (opening the log is
--     browsing). A play / pause button at the right end of the details' top bar plays that quest's offer as the pane
--     shows it, through UI/VoicePlayer like any line a player asks for. [verified: forever 1.60.1.70685
--     mainline/questmapframe.xml 691–725 (DetailsFrame.BackFrame, 307 × 52, BackButton at its left);
--     questmapframe.lua:1044–1056 (QuestMapFrame_ShowQuestDetails)]. Like the windows' buttons it shows only while the
--     voice panel is not on screen, and only for a line with a file.
--   * Who showed each quest line, remembered when the quest window shows it (State "questShown", fired by
--     UI/QuestFrame whether or not the line is translated), while a voice pack is installed:
--     WFJ_DB.voiceSpeakers["<quest id>-<field>"] = { c = creature id, s = UnitSex, n = name, t = title }, as the client
--     showed them; seeing the NPC again refreshes it. At most one entry per quest line the game has, so it is bounded
--     by the game's quests. The quest log's replays take their head (by creature id), name, title and voice variant
--     from it. A quest taken before this existed, or from a player, an item or an object, has none: the quest's title
--     stands in, with no head.
--   * The display id of every NPC whose head the panel drew from the unit on screen (State "speakerDisplay", from
--     UI/VoicePanelHead), while a voice pack is installed: WFJ_DB.voiceDisplays[creature id] = display id, refreshed
--     every time. `displayFor` answers it, else the shipped one, for every head drawn without the NPC on screen, so
--     none needs the creature cache every client build empties (ADR-089). Bounded by the NPCs the player has met.
-- The button follows forever-vo's ForeverVO/UI/QuestLog.lua (MIT License; see ATTRIBUTION.md).
local _, WFJ = ...
local QuestLog = {}
WFJ.VoiceQuestLog = QuestLog

local Compat = WFJ.Compat

local LOG = "QuestMapFrame"
local LOG_SURFACE = "questmap.info" -- UI/QuestMap's records for the details pane's QuestInfo text
local FIELD_OF = { detail = "description", progress = "progress", reward = "completion" }
local BUTTON_SIZE, BUTTON_LIFT = 28, 10 -- the windows' buttons' size and lift (UI/VoicePlayer)
local ICON_PLAYING = "Interface\\TimeManager\\PauseButton"
local ICON_STOPPED = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up"
local ICON_HIGHLIGHT = "Interface\\Buttons\\UI-Common-MouseHilight"

local db -- WFJ_DB
local button

local function rememberSpeaker(questID, panelName)
  local field = FIELD_OF[panelName]
  -- only with a voice pack: without one nothing is ever replayed, so nothing is kept
  if not field or type(questID) ~= "number" or type(db) ~= "table" or not WFJ.Voice.hasPack() then return end
  local P = WFJ.VoicePlayer
  local who = P.speaker("QuestFrame")
  if not who then return end
  local unitName = Compat.resolve("UnitName")
  if type(db.voiceSpeakers) ~= "table" then db.voiceSpeakers = {} end
  db.voiceSpeakers[questID .. "-" .. field] = { c = who.creature, s = who.sex,
    n = type(unitName) == "function" and unitName("questnpc") or nil, t = P.titleOf("questnpc") }
end

local function rememberDisplay(creature, display)
  if type(creature) ~= "number" or type(display) ~= "number" or type(db) ~= "table" or not WFJ.Voice.hasPack() then
    return
  end
  if type(db.voiceDisplays) ~= "table" then db.voiceDisplays = {} end
  db.voiceDisplays[creature] = display
end

-- → the display id to draw a creature with and where it came from ("saved": this player's client drew it,
-- "shipped": WFJ.Data.displays), or nil
function QuestLog.displayFor(creature)
  local saved = type(db) == "table" and db.voiceDisplays
  local d = type(saved) == "table" and saved[creature] or nil
  if d then return d, "saved" end
  local shipped = WFJ.Data and WFJ.Data.displays
  d = type(shipped) == "table" and shipped[creature] or nil
  if d then return d, "shipped" end
  return nil
end

-- → the remembered speaker of a quest line, or nil
function QuestLog.rememberedSpeaker(questID, field)
  local all = type(db) == "table" and db.voiceSpeakers
  return type(all) == "table" and type(questID) == "number" and all[questID .. "-" .. field] or nil
end

-- → path, seconds and the queue item for the pane's description, or nil
local function logLine()
  local rec = WFJ.SurfaceState and WFJ.SurfaceState.get(LOG_SURFACE, "description")
  local m = rec and rec.meta
  if not m or type(rec.applied) ~= "string" then return nil end
  -- the pane's quest: its own id, also for a description keyed by its English (m.id is then that key)
  local frame = Compat.resolve(LOG)
  local qid = type(frame) == "table" and frame.DetailsFrame and frame.DetailsFrame.questID
  if type(qid) ~= "number" then qid = type(m.id) == "number" and m.id or nil end
  local saw = QuestLog.rememberedSpeaker(qid, "description")
  local who = saw and { creature = saw.c, sex = saw.s } or nil
  local path, detail = WFJ.Voice.decide("questframe.detail", "description", m.kind, m.id, who, true)
  if not path then return nil end
  local questTitle = WFJ.SurfaceState.get(LOG_SURFACE, "title")
  -- nobody remembered: the quest's title as the pane shows it (its Japanese, or the client's English it was left as)
  local shownTitle = questTitle and (questTitle.applied or questTitle.en)
  local name = saw and saw.n or (type(shownTitle) == "string" and shownTitle or nil)
  return path, detail, { key = WFJ.Voice.packKey(m.kind, m.id), path = path, seconds = detail, window = LOG,
    surface = "questframe.detail", kind = m.kind, id = m.id,
    shown = { "questframe.detail", "description", m.kind, m.id },
    ja = (rec.applied:gsub("^|c%x%x%x%x%x%x%x%x.-|r[\n ]", "")), en = rec.en, name = name,
    title = saw and saw.t or nil, speaker = who }
end

-- The button as things stand: hidden while the panel is on screen, the setting is off or the line has no file.
function QuestLog.refresh()
  if not button then return end
  local path, _, item = logLine()
  if not path or not WFJ.VoicePlayer.buttonsAllowed() then
    button:Hide()
    return
  end
  button:SetNormalTexture(WFJ.VoicePlayer.playing() == item.key and ICON_PLAYING or ICON_STOPPED)
  button:Show()
end

local function click()
  local P = WFJ.VoicePlayer
  local path, _, item = logLine()
  if not path or not P.allowed() then return end
  local head = WFJ.VoiceQueue.current()
  if P.playing() == item.key then
    if P.queueOn() then P.pause() else P.stop() end -- the icon is a pause: it pauses
  elseif P.queueOn() and WFJ.VoiceQueue.paused and head and head.key == item.key then
    P.resume()
  else
    P.playNow(item, LOG)
  end
  QuestLog.refresh()
end

local function setup()
  local frame = Compat.resolve(LOG)
  local bar = type(frame) == "table" and frame.DetailsFrame and frame.DetailsFrame.BackFrame
  if type(bar) ~= "table" or button then return end
  local createFrame = Compat.resolve("CreateFrame")
  if type(createFrame) ~= "function" then return end
  button = createFrame("Button", nil, bar)
  button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
  button:SetPoint("RIGHT", bar, "RIGHT", -8, 4)
  button:SetFrameLevel(bar:GetFrameLevel() + BUTTON_LIFT)
  button:SetNormalTexture(ICON_STOPPED)
  button:SetHighlightTexture(ICON_HIGHLIGHT, "ADD")
  button:SetScript("OnClick", click)
  button:Hide()
end

-- → the button, or nil (for the specs)
function QuestLog.button()
  return button
end

-- Called by Main after VoicePlayer. `savedDb` is WFJ_DB.
function QuestLog.init(savedDb)
  db = savedDb
  local hook = Compat.resolve("hooksecurefunc")
  if type(hook) == "function" and type(Compat.resolve("QuestMapFrame_ShowQuestDetails")) == "function" then
    hook("QuestMapFrame_ShowQuestDetails", function() setup(); QuestLog.refresh() end)
  end
  for _, event in ipairs({ "voiceQueue", "voiceButtons", "voice", "enabled", "voicePanel" }) do
    WFJ.State.on(event, function() pcall(QuestLog.refresh) end)
  end
  WFJ.State.on("questShown", function(questID, panelName) pcall(rememberSpeaker, questID, panelName) end)
  WFJ.State.on("speakerDisplay", function(creature, display) pcall(rememberDisplay, creature, display) end)
  return true
end
