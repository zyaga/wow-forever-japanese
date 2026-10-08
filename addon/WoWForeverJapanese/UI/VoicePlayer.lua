-- UI/VoicePlayer.lua: plays the voice pack's line for a line the quest, gossip or book window just showed in
-- Japanese (ADR-061, ADR-062). Core/Voice decides which file; this file owns every sound and client-setting call.
--   * Start: State "lineShown" (fired by UI/Render after a client write, never on a refresh). One line at a time:
--     a new line stops the one playing; the same line shown again while it plays is not restarted (the gossip window
--     lays its first window out twice).
--   * Stop: the quest, gossip or book window hides (a book's next page is a new line), the reveal key goes down,
--     translation or a voice setting is switched off, the player logs out.
--   * Channel: "Master", so silencing the dialog channel never silences our own line. forever-vo ships the same MP3
--     shape and plays it with PlaySoundFile(path, channel) → willPlay, handle [unverified in the Forever client's own
--     files; the in-game check is in docs/testing/strategy.md].
--   * The button: a small play / pause icon at the right end of the stone band under the window's title (the band our
--     marker banner uses: y -36 on the quest window, -38 on the gossip window, UI/QuestFrame and UI/Gossip). Shown once
--     a line of that window has started, hidden when the window closes or its new line has no file. A pause icon
--     while the line plays (a click stops it), the play arrow once it stopped or ended (a click plays it from the
--     start). The client can only start and stop a sound file, so a stopped line cannot resume where it stopped. No
--     text on it; the voice.button setting hides it.
--   * The game's English voice: while a line plays, Sound_EnableDialog is turned off when it was on, and the fact is
--     kept in WFJ_DB.voiceDialogMuted, because the client saves the setting to Config.wtf: a reload or a crash in
--     between would otherwise leave the player's NPC voices off for good. It is put back when the line ends (the
--     pack's length plus a margin; PlaySoundFile reports no end), on stop, on logout and on the next load. A player
--     who had the dialog channel off keeps it off.
--   * The voice panel (UI/VoicePanel, trial): with Core/VoiceQueue's `opt.on`, a line that starts while one plays
--     waits its turn instead of stopping it, and with `opt.keepPlaying` a window closing no longer stops its line.
--     Every change of what plays fires State "voiceQueue"; the panel draws from VoicePlayer.state(). With the panel
--     off every path below behaves as before it existed.
local _, WFJ = ...
local VoicePlayer = {}
WFJ.VoicePlayer = VoicePlayer

local Compat = WFJ.Compat
local Q = WFJ.VoiceQueue
local CHANNEL = "Master"
local DIALOG = "Sound_EnableDialog"
local END_MARGIN = 0.5 -- seconds after the pack's length before the dialog channel comes back
local UNKNOWN_LENGTH = 30 -- a pack entry without a length: the longest scoped line is well under this
local BUTTON_SIZE = 28 -- the stopwatch textures have wide transparent margins: smaller reads as a dot
local BUTTON_X, BUTTON_Y = -8, -31 -- from the window's top right: centred in the band, below the close button
local BUTTON_LIFT = 10 -- above the window's own art, like the banner (Render.BANNER_LIFT)
-- The client's own stopwatch pair (blizzard_timemanager.xml:329–338, blizzard_timemanager.lua:549–565): pause while
-- it runs, the play arrow while it is stopped, so the icon always shows what a click does.
local ICON_PLAYING = "Interface\\TimeManager\\PauseButton"
local ICON_STOPPED = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up"
local ICON_HIGHLIGHT = "Interface\\Buttons\\UI-Common-MouseHilight"
local WINDOWS = { "QuestFrame", "GossipFrame", "ItemTextFrame" }
-- the NPC whose window shows the line: its creature id picks the voice of a line several creatures say
local SPEAKER_UNIT = { QuestFrame = "questnpc", GossipFrame = "npc" }

VoicePlayer.counts = { played = 0, refused = 0 }

local db -- WFJ_DB
local playing -- { handle, key, token, window } while a line plays
local buttons = {} -- window name → our button
local last = {} -- window name → { path, seconds, key }: the line its button plays again
local tokens = 0 -- a stale end timer (a line stopped early) finds a newer token and does nothing
local lastItem -- the panel's last line once nothing is queued (its replay)

local function queueOn() return Q.opt.on and true or false end

local function notify()
  pcall(WFJ.State.fire, "voiceQueue")
end

local function getCVar(name)
  local C = Compat.resolve("C_CVar")
  if type(C) == "table" and type(C.GetCVar) == "function" then return C.GetCVar(name) end
  local get = Compat.resolve("GetCVar")
  return type(get) == "function" and get(name) or nil
end

local function setCVar(name, value)
  local C = Compat.resolve("C_CVar")
  if type(C) == "table" and type(C.SetCVar) == "function" then return C.SetCVar(name, value) end
  local set = Compat.resolve("SetCVar")
  if type(set) == "function" then return set(name, value) end
  return nil
end

local function windowOf(surface)
  if surface == "gossip" then return "GossipFrame" end
  if surface == "itemtext" then return "ItemTextFrame" end
  return "QuestFrame"
end

-- The NPC on screen for a window → { creature, sex } or nil (a book has no speaker; a unit token the client does
-- not answer leaves the line's main voice). UnitGUID("questnpc") is the token the quest window names its giver by
-- [verified: classic_era Classic/QuestFrame.lua:118]; UnitSex on an NPC unit [unverified on Forever; in-game check
-- in docs/testing/strategy.md].
local function speaker(window)
  local unit = SPEAKER_UNIT[window]
  local guid = unit and Compat.resolve("UnitGUID")
  if type(guid) ~= "function" then return nil end
  local g = guid(unit)
  local id = WFJ.Collector.creatureId(g)
  if not id then return nil end
  local sex = Compat.resolve("UnitSex")
  return { creature = id, sex = type(sex) == "function" and sex(unit) or nil, unit = unit, guid = g }
end

-- The NPC's title as the client shows it under the name in its tooltip ("<Innkeeper>"), or nil. Live text, kept
-- with the queued line for the session only. [unverified on Forever: C_TooltipInfo.GetUnit is in the 70245 API
-- docs, tooltipinfodocumentation.lua:1181; line 2 being the title is the in-game check]
local function titleOf(unit)
  local T = Compat.resolve("C_TooltipInfo")
  if type(T) ~= "table" or type(T.GetUnit) ~= "function" then return nil end
  local ok, data = pcall(T.GetUnit, unit)
  local line = ok and type(data) == "table" and type(data.lines) == "table" and data.lines[2]
  local text = type(line) == "table" and line.leftText or nil
  if type(text) ~= "string" or text == "" or text:find("%d") then return nil end -- "Level 12 Humanoid"
  return text
end

-- What the panel shows for a line: who says it (name and title as the client shows them now) and its Japanese as
-- the window shows it (tokens filled in), without an inline marker line.
local function describe(window, surface, recKey, who)
  local rec = WFJ.SurfaceState and WFJ.SurfaceState.get(surface, recKey)
  local ja = rec and type(rec.applied) == "string" and rec.applied or nil
  -- the English the client wrote into the window for this line: shown on the panel while the reveal key is held,
  -- kept with the queued line in memory only, never saved
  local en = rec and type(rec.en) == "string" and rec.en or nil
  if ja then ja = ja:gsub("^|c%x%x%x%x%x%x%x%x.-|r[\n ]", "") end
  local name, title
  local unit = SPEAKER_UNIT[window]
  if unit then
    local unitName = Compat.resolve("UnitName")
    name = type(unitName) == "function" and unitName(unit) or nil
    title = who and titleOf(unit) or nil
  else
    local itemName = Compat.resolve("ItemTextGetItem") -- a book or letter: its own name
    name = type(itemName) == "function" and itemName() or nil
  end
  return ja, name, title, en
end

-- Puts the dialog channel back if this addon turned it off. → true when it did
function VoicePlayer.restoreDialog()
  if not (db and db.voiceDialogMuted) then return false end
  db.voiceDialogMuted = nil
  setCVar(DIALOG, "1")
  return true
end

local function muteDialog()
  if not WFJ.Settings.get("voice.muteDialog") or not db or db.voiceDialogMuted then return end
  if tostring(getCVar(DIALOG)) ~= "1" then return end -- off already: the player's choice, left alone
  db.voiceDialogMuted = true
  setCVar(DIALOG, "0")
end

local function showButton(window, isPlaying)
  local b = buttons[window]
  if not b then return end
  -- the voice panel carries pause, next and play again: the window's own button shows only while the panel is not
  -- on screen (switched off, or faded after the line)
  local panelUp = queueOn() and WFJ.VoicePanel ~= nil and WFJ.VoicePanel.visible()
  if not WFJ.Settings.get("voice.button") or not last[window] or panelUp then
    b:Hide()
    return
  end
  b:SetNormalTexture(isPlaying and ICON_PLAYING or ICON_STOPPED)
  b.isPlaying = isPlaying
  b:Show()
end

local function silence()
  if not playing then return end
  local stopSound = Compat.resolve("StopSound")
  if type(stopSound) == "function" and playing.handle then stopSound(playing.handle) end
  local window = playing.window
  playing = nil
  showButton(window, false)
end

-- Stops the line and empties the queue (the reveal key, translation or voice off, a loading screen, logout).
function VoicePlayer.stop()
  silence()
  local had = Q.size() > 0
  if had then lastItem = Q.current() end
  Q.clear()
  VoicePlayer.restoreDialog()
  if had then notify() end
end

-- A window closed: its line stops and its button goes until the next line starts.
local startHead -- defined below play
local function closed(window)
  if queueOn() then
    if not Q.opt.keepPlaying then
      local wasHead = Q.dropWindow(window)
      if wasHead then
        silence()
        if Q.current() and not Q.paused then startHead() else VoicePlayer.restoreDialog() end
      end
      notify()
    end
  elseif playing and playing.window == window then
    VoicePlayer.stop()
  end
  last[window] = nil
  if buttons[window] then buttons[window]:Hide() end
end

-- → the key playing, or nil
function VoicePlayer.current()
  return playing and playing.key or nil
end

local function finished(window)
  playing = nil
  if queueOn() and Q.current() then
    lastItem = Q.pop()
    if Q.current() and not Q.paused then
      startHead()
      notify()
      return
    end
  end
  VoicePlayer.restoreDialog()
  showButton(window, false)
  notify()
end

local function play(path, seconds, key, window, again)
  if playing and playing.key == key and not again then return false end
  if queueOn() then silence() else VoicePlayer.stop() end
  local playSoundFile = Compat.resolve("PlaySoundFile")
  if type(playSoundFile) ~= "function" then
    VoicePlayer.counts.refused = VoicePlayer.counts.refused + 1
    return false
  end
  muteDialog()
  local willPlay, handle = playSoundFile(path, CHANNEL)
  if not willPlay then
    VoicePlayer.counts.refused = VoicePlayer.counts.refused + 1
    VoicePlayer.restoreDialog()
    return false
  end
  tokens = tokens + 1
  local token = tokens
  local getTime = Compat.resolve("GetTime")
  playing = { handle = handle, key = key, token = token, window = window,
    startedAt = type(getTime) == "function" and getTime() or 0, seconds = seconds or UNKNOWN_LENGTH }
  last[window] = { path = path, seconds = seconds, key = key }
  showButton(window, true)
  VoicePlayer.counts.played = VoicePlayer.counts.played + 1
  local timer = Compat.resolve("C_Timer")
  if type(timer) == "table" and type(timer.After) == "function" then
    timer.After((seconds or UNKNOWN_LENGTH) + END_MARGIN, function()
      if playing and playing.token == token then finished(window) end
    end)
  end
  return true
end

-- Plays the queue's head. → true when it started
startHead = function()
  local item = Q.current()
  if not item then return false end
  Q.paused = false
  local started = play(item.path, item.seconds, item.key, item.window, true)
  if started and last[item.window] then last[item.window].shown = item.shown end
  if not started then -- the client refused the file: drop it and go on
    Q.pop()
    if Q.current() then return startHead() end
  end
  notify()
  return started
end

-- State "lineShown" listener. → true when a line started
function VoicePlayer.onShown(surface, recKey, kind, id)
  local window = windowOf(surface)
  local path, detail = WFJ.Voice.decide(surface, recKey, kind, id, speaker(window)) -- detail: length, or why not
  if not path then
    -- a new voiced line of this window that will not play (no file, its kind switched off, English showing): the
    -- button must not replay the previous line over it. An unvoiced line of the window ("kind": a title) leaves it.
    if detail == "missing" or detail == "stale" or detail == "notext" or detail == "off" or detail == "english" then
      -- with the queue the line playing goes on: it may be another NPC's, kept playing after its window closed
      if not queueOn() and playing and playing.window == window then VoicePlayer.stop() end
      last[window] = nil
      showButton(window, false)
    end
    return false
  end
  local key = WFJ.Voice.packKey(kind, id)
  if queueOn() then
    if (playing and playing.key == key) or Q.has(key) then return false end
    local who = speaker(window)
    local ja, name, title, en = describe(window, surface, recKey, who)
    local item = { key = key, path = path, seconds = detail, window = window, surface = surface, kind = kind, id = id,
      shown = { surface, recKey, kind, id }, ja = ja, en = en, name = name, title = title, speaker = who }
    if Q.paused then Q.pop() end -- a paused line gives way to the new one: the player has moved on
    Q.push(item)
    if Q.size() == 1 then return startHead() end
    notify()
    return false
  end
  local started = play(path, detail, key, window)
  if started then last[window].shown = { surface, recKey, kind, id } end -- re-asked before a replay
  return started
end

-- The window's last line again, as Voice.decide answers now (a setting may have switched its kind off since).
-- → path, seconds, or nil
local function replayable(window)
  local line = last[window]
  if not line then return nil end
  if not line.shown then return line.path, line.seconds end
  local s = line.shown
  local path, detail = WFJ.Voice.decide(s[1], s[2], s[3], s[4], speaker(window), true)
  if not path then return nil end
  return path, detail
end

-- The button's click: stop the line playing, or play the window's line again. Never while English is showing.
function VoicePlayer.toggle(window)
  if playing and playing.window == window then
    if queueOn() then VoicePlayer.skip() else VoicePlayer.stop() end
    return false
  end
  local line = last[window]
  if not line or not WFJ.State.enabled or WFJ.State.modifierHeld or not WFJ.Settings.get("voice.enabled") then
    return false
  end
  local path, seconds = replayable(window)
  if not path then return false end
  local shown = line.shown
  if queueOn() then
    local item
    for _, it in ipairs(Q.items) do if it.key == line.key then item = it end end
    if not item and lastItem and lastItem.key == line.key then item = lastItem end
    item = item or { key = line.key, window = window, shown = shown }
    item.path, item.seconds = path, seconds
    silence()
    Q.front(item)
    return startHead()
  end
  local started = play(path, seconds, line.key, window, true)
  if started then last[window].shown = shown end
  return started
end

-- ── The panel's controls (UI/VoicePanel, the key bindings) ────────────────

local function voiceAllowed()
  return WFJ.State.enabled and not WFJ.State.modifierHeld and WFJ.Settings.get("voice.enabled")
end

-- Stops the line and keeps it at the head; resume plays it again from the start (the client cannot resume a file).
function VoicePlayer.pause()
  if not Q.current() then return false end
  silence()
  Q.paused = true
  VoicePlayer.restoreDialog()
  notify()
  return true
end

function VoicePlayer.resume()
  if not Q.current() or not voiceAllowed() then return false end
  return startHead()
end

function VoicePlayer.togglePause()
  if Q.paused or (Q.current() and not playing) then return VoicePlayer.resume() end
  return VoicePlayer.pause()
end

-- Ends the line playing and plays the next one.
function VoicePlayer.skip()
  if not Q.current() then return false end
  silence()
  lastItem = Q.pop()
  if Q.current() and not Q.paused and voiceAllowed() then
    startHead()
  else
    VoicePlayer.restoreDialog()
  end
  notify()
  return true
end

-- The panel's line from the start: the head, or the last line once nothing is queued.
function VoicePlayer.replay()
  if not voiceAllowed() then return false end
  local item = Q.current() or lastItem
  if not item or not item.path then return false end
  silence()
  Q.front(item)
  return startHead()
end

-- Empties the queue (the panel's close button).
function VoicePlayer.clear()
  VoicePlayer.stop()
  lastItem = nil
  notify()
end

-- → { item, playing, paused, startedAt, seconds, waiting = { items }, last } for the panel
function VoicePlayer.state()
  local waiting = {}
  for i = 2, #Q.items do waiting[#waiting + 1] = Q.items[i] end
  return { item = Q.current(), playing = playing ~= nil, paused = Q.paused,
    startedAt = playing and playing.startedAt or nil, seconds = playing and playing.seconds or nil,
    waiting = waiting, last = lastItem }
end

local function createButton(window)
  local frame = Compat.resolve(window)
  local createFrame = Compat.resolve("CreateFrame")
  if type(frame) ~= "table" or type(createFrame) ~= "function" then return nil end
  local b = createFrame("Button", nil, frame)
  b:SetSize(BUTTON_SIZE, BUTTON_SIZE)
  b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", BUTTON_X, BUTTON_Y)
  b:SetFrameLevel(frame:GetFrameLevel() + BUTTON_LIFT)
  b:SetNormalTexture(ICON_STOPPED)
  b:SetHighlightTexture(ICON_HIGHLIGHT, "ADD")
  b:SetScript("OnClick", function() VoicePlayer.toggle(window) end)
  b:Hide()
  return b
end

-- The window buttons again, as the panel's visibility now says.
function VoicePlayer.refreshButtons()
  for _, window in ipairs(WINDOWS) do showButton(window, playing ~= nil and playing.window == window) end
end

-- ── The quest log's details pane (QuestMapFrame) ─────────────────────────
-- The pane shows a quest's text but plays nothing by itself (opening the log is browsing). A play / stop button at
-- the right end of the pane's top bar plays that quest's description as the pane shows it, voiced like its offer,
-- through the queue and the panel like any other line. [verified: forever 1.60.1.70245 mainline/questmapframe.xml
-- 701–720 (DetailsFrame.BackFrame, 307 × 52, BackButton at its left); questmapframe.lua:1044–1056
-- (QuestMapFrame_ShowQuestDetails)]
local LOG = "QuestMapFrame"
local LOG_SURFACE = "questmap.info" -- UI/QuestMap's records for the details pane's QuestInfo text
local logButton

-- → path, seconds, item for the pane's description, or nil
local function logLine()
  local rec = WFJ.SurfaceState and WFJ.SurfaceState.get(LOG_SURFACE, "description")
  local m = rec and rec.meta
  if not m or type(rec.applied) ~= "string" then return nil end
  local path, detail = WFJ.Voice.decide("questframe.detail", "description", m.kind, m.id, nil, true)
  if not path then return nil end
  local key = WFJ.Voice.packKey(m.kind, m.id)
  local title = WFJ.SurfaceState.get(LOG_SURFACE, "title")
  local name = title and type(title.applied) == "string" and title.applied or nil
  return path, detail, { key = key, path = path, seconds = detail, window = LOG, surface = "questframe.detail",
    kind = m.kind, id = m.id, shown = { "questframe.detail", "description", m.kind, m.id },
    ja = rec.applied:gsub("^|c%x%x%x%x%x%x%x%x.-|r[\n ]", ""), en = rec.en, name = name }
end

local function updateLogButton()
  if not logButton then return end
  local path, _, item = logLine()
  if not path or not WFJ.Settings.get("voice.button") then
    logButton:Hide()
    return
  end
  local on = playing ~= nil and playing.key == item.key
  logButton:SetNormalTexture(on and ICON_PLAYING or ICON_STOPPED)
  logButton:Show()
end

local function logClick()
  local path, seconds, item = logLine()
  if not path or not voiceAllowed() then return end
  if playing and playing.key == item.key then
    if queueOn() then VoicePlayer.skip() else VoicePlayer.stop() end
  elseif queueOn() then
    silence()
    Q.front(item)
    startHead()
  else
    play(path, seconds, item.key, LOG, true)
  end
  updateLogButton()
end

local function setupLog()
  local frame = Compat.resolve(LOG)
  local bar = type(frame) == "table" and frame.DetailsFrame and frame.DetailsFrame.BackFrame
  if type(bar) ~= "table" or logButton then return end
  local createFrame = Compat.resolve("CreateFrame")
  if type(createFrame) ~= "function" then return end
  logButton = createFrame("Button", nil, bar)
  logButton:SetSize(BUTTON_SIZE, BUTTON_SIZE)
  logButton:SetPoint("RIGHT", bar, "RIGHT", -8, 4)
  logButton:SetFrameLevel(bar:GetFrameLevel() + BUTTON_LIFT)
  logButton:SetNormalTexture(ICON_STOPPED)
  logButton:SetHighlightTexture(ICON_HIGHLIGHT, "ADD")
  logButton:SetScript("OnClick", logClick)
  logButton:Hide()
end

-- → the window's button, or nil (for /wfj debug and the specs)
function VoicePlayer.button(window)
  return buttons[window]
end

local function stopUnless(on)
  if not on then VoicePlayer.stop() end
end

-- Called by Main after Settings and Voice are loaded. `savedDb` is WFJ_DB. Safe without a pack: nothing ever plays.
function VoicePlayer.init(savedDb)
  db = savedDb
  VoicePlayer.restoreDialog() -- a reload or crash during a line left the dialog channel off
  WFJ.State.on("lineShown", VoicePlayer.onShown)
  -- With the voice panel the reveal key only switches the panel's text to English: the Japanese voice goes on, so a
  -- player can glance at the English without losing the line. Without the panel it stops the line, as before.
  WFJ.State.on("modifier", function(held)
    if queueOn() then notify() return end
    if held then VoicePlayer.stop() end
  end)
  WFJ.State.on("enabled", stopUnless)
  WFJ.State.on("voicePanel", function() -- the panel switched on or off: the window buttons follow
    for _, window in ipairs(WINDOWS) do showButton(window, playing ~= nil and playing.window == window) end
  end)
  WFJ.State.on("voice", function() -- any voice setting changed: the line playing may be one now off
    VoicePlayer.stop()
    for _, window in ipairs(WINDOWS) do
      if last[window] and not replayable(window) then last[window] = nil end -- its kind is off: no replay
      showButton(window, false)
    end
  end)
  local hook = Compat.resolve("hooksecurefunc")
  if type(hook) == "function" and type(Compat.resolve("QuestMapFrame_ShowQuestDetails")) == "function" then
    hook("QuestMapFrame_ShowQuestDetails", function() setupLog(); updateLogButton() end)
  end
  WFJ.State.on("voiceQueue", updateLogButton)
  local createFrame = Compat.resolve("CreateFrame")
  if type(createFrame) == "function" then -- a loading screen ends every line and the queue
    local ev = createFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function() if Q.size() > 0 or playing then VoicePlayer.stop() end end)
  end
  for _, window in ipairs(WINDOWS) do
    local f = Compat.resolve(window)
    if type(f) == "table" and type(f.HookScript) == "function" then
      buttons[window] = createButton(window)
      f:HookScript("OnHide", function() closed(window) end)
    end
  end
  return true
end
