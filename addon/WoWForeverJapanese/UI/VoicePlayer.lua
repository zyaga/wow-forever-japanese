-- UI/VoicePlayer.lua: plays the voice pack's line for a line the quest, gossip or book window just showed in
-- Japanese (ADR-061, ADR-062, ADR-063). Core/Voice decides which file; this file owns every sound and client-setting
-- call; Core/VoiceQueue holds the order; UI/VoicePanel draws what `state()` reports (State "voiceQueue" on change).
--   * Start: State "lineShown" (fired by UI/Render after a client write, never on a refresh). With the voice panel on,
--     a line that starts while one plays waits its turn (never twice for one key) and plays when that one ends; with
--     the panel Off, a new line stops the one playing. The same line shown again while it plays is not restarted (the
--     gossip window lays its first window out twice).
--   * Stop: translation or a voice setting switched off, a loading screen, logout. A window closing stops its line
--     only with the panel Off or "keep reading" off; the reveal key going down stops it only with the panel Off (with
--     the panel on the voice goes on and the panel shows the line's English).
--   * A line the player asks for (a window's or the quest log's play button, a row of the panel's waiting list)
--     replaces the line playing; the one it interrupts is dropped, never resumed after it.
--   * Channel: "Master", so silencing the dialog channel never silences our own line. PlaySoundFile(path, channel)
--     → willPlay, handle [unverified in the Forever client's own files; the in-game check is in
--     docs/testing/strategy.md].
--   * The window buttons: a small play / pause icon at the right end of the stone band under the window's title (the
--     band our marker banner uses: y -36 on the quest window, -38 on the gossip window, UI/QuestFrame and UI/Gossip);
--     the quest log details' one is UI/VoiceQuestLog's. Shown while the voice panel is not on screen and
--     the line has a file; the pause icon while it plays (a click pauses with the panel on, stops with it Off), the
--     play arrow otherwise (a click plays it from the start: the client can only start and stop a sound file). No
--     text; the voice.button setting hides them.
--   * The game's English voice: while a line plays, Sound_EnableDialog is turned off when it was on, and the fact is
--     kept in WFJ_DB.voiceDialogMuted, because the client saves the setting to Config.wtf: a reload or a crash in
--     between would otherwise leave the player's NPC voices off for good. It is put back when the line ends (the
--     pack's length plus a margin; PlaySoundFile reports no end), on stop, on logout and on the next load. A player
--     who had the dialog channel off keeps it off.
--   * Ahead of the line: the client starts the NPC's English greeting as the window opens, before the window's text is
--     written, so a mute taken only when our line starts cuts the greeting mid-word. The events that open an NPC
--     window turn the dialog channel off at once when that window's line will be read aloud (never for a line with
--     no file, a kind switched off or a line heard before), give it back as soon as the line turns out not to play,
--     and after AHEAD_SECONDS when no line started. The timing follows the Spoken addon's (github.com/rusty-key/
--     spoken-wow, MIT): its greeting mute is taken in the window's event, before the text is read.
--   The dialog-sound handling is adapted from forever-vo's ForeverVO/Core/Audio.lua (MIT License; see ATTRIBUTION.md).
local _, WFJ = ...
local VoicePlayer = {}
WFJ.VoicePlayer = VoicePlayer

local Compat = WFJ.Compat
local Q = WFJ.VoiceQueue
local CHANNEL = "Master"
local DIALOG = "Sound_EnableDialog"
local END_MARGIN = 0.5 -- seconds after the pack's length before the dialog channel comes back
local AHEAD_SECONDS = 1.5 -- a mute taken as a window opens is given back after this when no line started
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
local WINDOW_OF = {} -- surface → window, for windows another addon draws (VoicePlayer.addWindow)

VoicePlayer.counts = { played = 0, refused = 0 }

local db -- WFJ_DB
local playing -- { handle, key, token, window } while a line plays
local buttons = {} -- window name → our button
local last = {} -- window name → { path, seconds, key }: the line its button plays again
local tokens = 0 -- a stale end timer (a line stopped early) finds a newer token and does nothing
local lastItem -- the panel's last line once nothing is queued (its replay)

local function queueOn() return Q.opt.on and true or false end

-- a line may start: translation and voice on, and Japanese showing (no voice starts while English shows)
local function voiceAllowed()
  return WFJ.State.enabled and not WFJ.State.showsEnglish() and WFJ.Settings.get("voice.enabled") and true or false
end

local function notify()
  pcall(WFJ.State.fire, "voiceQueue")
end

-- The voice timing trace in the problem log: each line's start, its recorded length, and what ended it, with the
-- time since it started. Read it with /wfj log after a line ends early.
local function trace(what, p, fields)
  if not (WFJ.Diag and p) then return end
  local getTime = Compat.resolve("GetTime")
  local t = type(getTime) == "function" and getTime() or 0
  fields = fields or {}
  fields.seconds, fields.elapsed = p.seconds, p.startedAt and (t - p.startedAt) or nil
  local stack = Compat.resolve("debugstack")
  if what ~= "start" and type(stack) == "function" then fields.from = stack(3, 2, 0) end
  pcall(WFJ.Diag.log, "voicetime", ("%s %s #%d"):format(what, tostring(p.key), p.token or 0), fields)
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
  if WINDOW_OF[surface] then return WINDOW_OF[surface] end
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
  -- the level line ("Level 12 Humanoid", "Level ?? Elite") is no title
  if type(text) ~= "string" or text == "" or text:find("%d") or text:find("%?%?") then return nil end
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

-- → the window name a surface's lines belong to (for /wfj debug and the specs)
function VoicePlayer.windowOf(surface) return windowOf(surface) end

local ahead -- the token of a mute taken as a window opened, while its line has not started
local aheadTokens = 0
local aheadWindow -- the window that mute was taken for: only its own line not playing gives it back

-- Puts the dialog channel back if this addon turned it off. → true when it did
function VoicePlayer.restoreDialog()
  ahead = nil
  if not (db and db.voiceDialogMuted) then return false end
  db.voiceDialogMuted = nil
  setCVar(DIALOG, "1")
  return true
end

-- → true when the dialog channel is off by this addon's hand
local function muteDialog()
  if not WFJ.Settings.get("voice.muteDialog") or not db then return false end
  if db.voiceDialogMuted then return true end
  if tostring(getCVar(DIALOG)) ~= "1" then return false end -- off already: the player's choice, left alone
  db.voiceDialogMuted = true
  setCVar(DIALOG, "0")
  return true
end

-- The mute taken ahead goes back, unless a line is playing (that line holds it until it ends).
local function giveBack()
  if not ahead then return end
  ahead, aheadWindow = nil, nil
  if not playing then VoicePlayer.restoreDialog() end
end

local function showButton(window, isPlaying)
  local b = buttons[window]
  if not b then return end
  -- the voice panel carries pause, play again and the whole text: the window's own button shows only while the panel
  -- is not on screen (switched off, or faded after the line)
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
  trace("silence", playing)
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
        Q.paused = false -- a paused head that was dropped takes its pause with it
        if Q.current() and voiceAllowed() then startHead() else VoicePlayer.restoreDialog() end
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
  trace("end", playing)
  playing = nil
  if queueOn() and Q.current() then
    lastItem = Q.pop()
    -- the next line waits unstarted while English shows; letting go of the reveal key starts it (init)
    if Q.current() and not Q.paused and voiceAllowed() then
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
  ahead = nil -- the line holds the mute now
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
  trace("start", playing, { path = path })
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
  if started and item.shown then WFJ.Voice.markHeard(unpack(item.shown)) end
  if not started then -- the client refused the file: drop it and go on
    Q.pop()
    if Q.current() then return startHead() end
  end
  notify()
  return started
end

-- A line the player asked for (a window's or the quest log's play button) replaces the line playing: the one it
-- interrupts is dropped, never resumed after it (it becomes the panel's last line). Lines waiting stay waiting.
local function takeOver(item)
  silence()
  local head = Q.current()
  if head and head.key ~= item.key then lastItem = Q.pop() end
  Q.front(item)
  return startHead()
end

-- State "lineShown" listener. → true when a line started
function VoicePlayer.onShown(surface, recKey, kind, id)
  local window = windowOf(surface)
  local path, detail = WFJ.Voice.decide(surface, recKey, kind, id, speaker(window)) -- detail: length, or why not
  if not path and detail == "heard" then
    -- heard before (first time only): it stays quiet, and the window's button reads this line on a click. The same
    -- line laid out again while it plays (the gossip window lays its first window out twice) goes on.
    local key = WFJ.Voice.packKey(kind, id)
    if playing and playing.key == key then return false end
    if ahead and window == aheadWindow then giveBack() end
    if not queueOn() and playing and playing.window == window then VoicePlayer.stop() end
    last[window] = { key = key, shown = { surface, recKey, kind, id } }
    showButton(window, false)
    return false
  end
  -- the window's voiced line will not play; another translated line (a tooltip, the window's title) changes nothing
  if not path and ahead and detail ~= "kind" and window == aheadWindow then giveBack() end
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
    -- a paused line gives way to the new one: the player has moved on; lines waiting stay waiting
    if Q.paused then return takeOver(item) end
    Q.push(item)
    if Q.size() == 1 then
      if voiceAllowed() then return startHead() end
      notify()
      return false
    end
    notify()
    return false
  end
  local started = play(path, detail, key, window)
  if started then
    last[window].shown = { surface, recKey, kind, id } -- re-asked before a replay
    WFJ.Voice.markHeard(surface, recKey, kind, id)
  end
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
    -- the icon is a pause: it pauses (a line started while the panel was off is not queued: it stops)
    if queueOn() and Q.current() then VoicePlayer.pause() else VoicePlayer.stop() end
    return false
  end
  local head = Q.current()
  if queueOn() and Q.paused and head and head.window == window then return VoicePlayer.resume() end
  local line = last[window]
  if not line or not WFJ.State.enabled or WFJ.State.showsEnglish() or not WFJ.Settings.get("voice.enabled") then
    return false
  end
  local path, seconds = replayable(window)
  if not path then return false end
  local shown = line.shown
  if queueOn() then
    local item
    for _, it in ipairs(Q.items) do if it.key == line.key then item = it end end
    if not item and lastItem and lastItem.key == line.key then item = lastItem end
    if not item and shown then -- a line played while the panel was off: describe it as the window shows it now
      local who = speaker(window)
      local ja, name, title, en = describe(window, shown[1], shown[2], who)
      item = { key = line.key, window = window, shown = shown, surface = shown[1], kind = shown[3], id = shown[4],
        ja = ja, en = en, name = name, title = title, speaker = who }
    end
    item = item or { key = line.key, window = window, shown = shown }
    item.path, item.seconds = path, seconds
    return takeOver(item)
  end
  local started = play(path, seconds, line.key, window, true)
  if started then last[window].shown = shown end
  return started
end

-- ── The panel's controls (UI/VoicePanel, the key bindings) ────────────────

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
  if not queueOn() or not Q.current() or not voiceAllowed() then return false end
  return startHead()
end

function VoicePlayer.togglePause()
  if not queueOn() then return false end
  if Q.paused or (Q.current() and not playing) then return VoicePlayer.resume() end
  return VoicePlayer.pause()
end

-- A waiting line, played now (a row of the panel's waiting list): it replaces the line playing. → true when it started
function VoicePlayer.playWaiting(key)
  if not voiceAllowed() then return false end
  for i = 2, #Q.items do
    if Q.items[i].key == key then return takeOver(Q.items[i]) end
  end
  return false
end

-- Whether `item` would still play as Voice.decide answers now (its kind may have been switched off since).
local function stillVoiced(item)
  local s = item and item.shown
  if not s then return item ~= nil end
  return WFJ.Voice.decide(s[1], s[2], s[3], s[4], item.speaker, true) ~= nil
end

-- The panel's line from the start: the head, or the last line once nothing is queued.
function VoicePlayer.replay()
  if not queueOn() or not voiceAllowed() then return false end
  local item = Q.current() or lastItem
  if not item or not item.path or not stillVoiced(item) then return false end
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
  pcall(WFJ.State.fire, "voiceButtons") -- UI/VoiceQuestLog's button follows too
end

-- For UI/VoiceQuestLog: whether the window buttons may show now (the panel is not on screen).
function VoicePlayer.buttonsAllowed()
  return WFJ.Settings.get("voice.button") and not (queueOn() and WFJ.VoicePanel ~= nil and WFJ.VoicePanel.visible())
end

-- For UI/VoiceQuestLog: the key playing, whether the queue is on, and a line asked for. → true when it started
function VoicePlayer.playing() return playing and playing.key or nil end
function VoicePlayer.queueOn() return queueOn() end
function VoicePlayer.allowed() return voiceAllowed() end
function VoicePlayer.speaker(window) return speaker(window) end
function VoicePlayer.titleOf(unit) return titleOf(unit) end
function VoicePlayer.playNow(item, window)
  if queueOn() then return takeOver(item) end
  return play(item.path, item.seconds, item.key, window, true)
end

-- → the window's button, or nil (for /wfj debug and the specs)
function VoicePlayer.button(window)
  return buttons[window]
end

local function stopUnless(on)
  if not on then VoicePlayer.stop() end
end

local ready = false -- init ran: the queue and the settings it reads are there

-- A window another addon draws in place of the client's (UI/DialogueUI): its lines (`surfaces`) belong to it, `unit`
-- names its NPC (nil for a book), and it gets the replay control. Its close is heard through a child frame of ours,
-- because that addon sets its window's own OnHide script again after load, which drops a hook made with HookScript.
-- → true when added
function VoicePlayer.addWindow(window, surfaces, unit)
  local frame = Compat.resolve(window)
  local createFrame = Compat.resolve("CreateFrame")
  if buttons[window] or type(frame) ~= "table" or type(createFrame) ~= "function" then return false end
  WINDOWS[#WINDOWS + 1] = window
  SPEAKER_UNIT[window] = unit
  for _, s in ipairs(surfaces) do WINDOW_OF[s] = window end
  buttons[window] = createButton(window)
  local watcher = createFrame("Frame", nil, frame)
  watcher:SetScript("OnHide", function() if ready then closed(window) end end)
  watcher:Show()
  return true
end

-- The quest windows' events: their surface, record key and the client getter of their English.
local QUEST_EVENTS = {
  QUEST_DETAIL = { "questframe.detail", "description", "GetQuestText" },
  QUEST_PROGRESS = { "questframe.progress", "progress", "GetProgressText" },
  QUEST_COMPLETE = { "questframe.reward", "completion", "GetRewardText" },
}

local function readable(v)
  local isSecret = Compat.resolve("issecretvalue")
  return type(v) == "string" and v ~= "" and not (type(isSecret) == "function" and isSecret(v))
end

-- The line the window an event opens will show → surface, record key, kind, id and its area; or nil and why not
local function opening(event)
  if event == "GOSSIP_SHOW" or event == "QUEST_GREETING" then
    local text
    if event == "GOSSIP_SHOW" then
      local api = Compat.resolve("C_GossipInfo")
      text = type(api) == "table" and type(api.GetText) == "function" and api.GetText() or nil
    else
      local get = Compat.resolve("GetGreetingText")
      text = type(get) == "function" and get() or nil
    end
    if not readable(text) then return nil, "no text yet" end -- a first talk: the text may arrive after the event
    local key = type(WFJ.ShippedGossipKey) == "function" and WFJ.ShippedGossipKey(text) or nil
    if not key then return nil, "no Japanese" end
    return event == "GOSSIP_SHOW" and "gossip" or "questframe.greeting", "greeting", "gossip", key, "gossip"
  end
  local q = QUEST_EVENTS[event]
  if not q then return nil, "not a window" end
  local getID, getText = Compat.resolve("GetQuestID"), Compat.resolve(q[3])
  local id = type(getID) == "function" and getID() or nil
  if type(id) ~= "number" or id == 0 then return nil, "no quest" end
  local en = type(getText) == "function" and getText() or nil
  local kind, keyId = "quest." .. q[2], id
  if readable(en) and WFJ.QuestFrame and type(WFJ.QuestFrame.fieldSource) == "function" then
    kind, keyId = WFJ.QuestFrame.fieldSource(id, q[2], en)
  end
  return q[1], q[2], kind, keyId, "quests"
end

-- An NPC window is opening: the English greeting has just started. When the window's line will be read aloud, the
-- dialog channel goes off now and comes back when the line ends, when it turns out not to play, or after
-- AHEAD_SECONDS when no line started.
-- Each window event leaves one "window" line in the log saying what the mute decided and why, so a greeting heard in
-- English can be traced to its cause (a first talk whose text came after the event, a line with no file, …).
local function noteWindow(event, why, key)
  trace("window", { key = key or "-", token = 0 }, { event = event, why = why })
  return false
end

function VoicePlayer.onWindowEvent(event)
  if not ready then return false end
  if playing then return noteWindow(event, "a line is playing", playing.key) end
  local surface, recKey, kind, id, area = opening(event)
  if not surface then return noteWindow(event, recKey) end
  local key = WFJ.Voice.packKey(kind, id)
  if not WFJ.State.areaEnabled(area) then return noteWindow(event, "area off", key) end -- renders no Japanese
  local path, detail = WFJ.Voice.decide(surface, recKey, kind, id, speaker(windowOf(surface)), "ahead")
  if not path then return noteWindow(event, detail, key) end
  if not muteDialog() then return noteWindow(event, "dialog left as it is", key) end
  aheadTokens = aheadTokens + 1
  local token = aheadTokens
  ahead, aheadWindow = token, windowOf(surface)
  trace("ahead", { key = WFJ.Voice.packKey(kind, id), token = token }, { event = event })
  local timer = Compat.resolve("C_Timer")
  if type(timer) == "table" and type(timer.After) == "function" then
    timer.After(AHEAD_SECONDS, function() if ahead == token then giveBack() end end)
  end
  return true
end

-- Called by Main after Settings and Voice are loaded. `savedDb` is WFJ_DB. Safe without a pack: nothing ever plays.
function VoicePlayer.init(savedDb)
  db = savedDb
  ready = true
  VoicePlayer.restoreDialog() -- a reload or crash during a line left the dialog channel off
  WFJ.State.on("lineShown", VoicePlayer.onShown)
  -- With the voice panel the reveal key only switches the panel's text to English: the Japanese voice goes on, so a
  -- player can glance at the English without losing the line. Without the panel it stops the line, as before.
  WFJ.State.on("language", function(english)
    if not queueOn() then
      if english then VoicePlayer.stop() end
      return
    end
    -- back to Japanese: a line that came up while English showed starts now
    if not english and Q.current() and not playing and not Q.paused and voiceAllowed() then return startHead() end
    notify()
  end)
  WFJ.State.on("enabled", stopUnless)
  WFJ.State.on("voicePanel", function() -- the panel switched on or off: the window buttons follow
    if not queueOn() then lastItem = nil end -- no panel replay of an old line with the panel off
    VoicePlayer.refreshButtons()
  end)
  WFJ.State.on("voice", function() -- any voice setting changed: the line playing may be one now off
    VoicePlayer.stop()
    if lastItem and not stillVoiced(lastItem) then lastItem = nil; notify() end -- no replay of a line now off
    for _, window in ipairs(WINDOWS) do
      if last[window] and not replayable(window) then last[window] = nil end -- its kind is off: no replay
      showButton(window, false)
    end
  end)
  local createFrame = Compat.resolve("CreateFrame")
  if type(createFrame) == "function" then -- a loading screen ends every line and the queue
    local ev = createFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    for _, e in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE" }) do
      ev:RegisterEvent(e)
    end
    ev:SetScript("OnEvent", WFJ.Perf.wrap("idle.voiceplayer.event", function(_, event)
      if event ~= "PLAYER_ENTERING_WORLD" then return VoicePlayer.onWindowEvent(event) end
      -- like the panel's close: the line, the queue and the panel's last line all go
      -- with the panel only: with it off a line goes on through a loading screen, as it always did
      if queueOn() and (Q.size() > 0 or playing or lastItem) then VoicePlayer.clear() end
    end))
  end
  for _, window in ipairs(WINDOWS) do
    local f = Compat.resolve(window)
    if not buttons[window] and type(f) == "table" and type(f.HookScript) == "function" then -- not an added window
      buttons[window] = createButton(window)
      f:HookScript("OnHide", function() closed(window) end)
    end
  end
  return true
end
