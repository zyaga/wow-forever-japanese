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
local _, WFJ = ...
local VoicePlayer = {}
WFJ.VoicePlayer = VoicePlayer

local Compat = WFJ.Compat
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
  local id = WFJ.Collector.creatureId(guid(unit))
  if not id then return nil end
  local sex = Compat.resolve("UnitSex")
  return { creature = id, sex = type(sex) == "function" and sex(unit) or nil }
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
  if not WFJ.Settings.get("voice.button") or not last[window] then
    b:Hide()
    return
  end
  b:SetNormalTexture(isPlaying and ICON_PLAYING or ICON_STOPPED)
  b.isPlaying = isPlaying
  b:Show()
end

function VoicePlayer.stop()
  if playing then
    local stopSound = Compat.resolve("StopSound")
    if type(stopSound) == "function" and playing.handle then stopSound(playing.handle) end
    local window = playing.window
    playing = nil
    showButton(window, false)
  end
  VoicePlayer.restoreDialog()
end

-- A window closed: its line stops and its button goes until the next line starts.
local function closed(window)
  if playing and playing.window == window then VoicePlayer.stop() end
  last[window] = nil
  if buttons[window] then buttons[window]:Hide() end
end

-- → the key playing, or nil
function VoicePlayer.current()
  return playing and playing.key or nil
end

local function play(path, seconds, key, window, again)
  if playing and playing.key == key and not again then return false end
  VoicePlayer.stop()
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
  playing = { handle = handle, key = key, token = token, window = window }
  last[window] = { path = path, seconds = seconds, key = key }
  showButton(window, true)
  VoicePlayer.counts.played = VoicePlayer.counts.played + 1
  local timer = Compat.resolve("C_Timer")
  if type(timer) == "table" and type(timer.After) == "function" then
    timer.After((seconds or UNKNOWN_LENGTH) + END_MARGIN, function()
      if playing and playing.token == token then
        playing = nil
        VoicePlayer.restoreDialog()
        showButton(window, false)
      end
    end)
  end
  return true
end

-- State "lineShown" listener. → true when a line started
function VoicePlayer.onShown(surface, recKey, kind, id)
  local window = windowOf(surface)
  local path, detail = WFJ.Voice.decide(surface, recKey, kind, id, speaker(window)) -- detail: length, or why not
  if not path then
    -- a voiced line of this window with no file to play: the button must not replay the previous line
    if detail == "missing" or detail == "stale" or detail == "notext" then
      if playing and playing.window == window then VoicePlayer.stop() end
      last[window] = nil
      showButton(window, false)
    end
    return false
  end
  local started = play(path, detail, WFJ.Voice.packKey(kind, id), window)
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
  local path, detail = WFJ.Voice.decide(s[1], s[2], s[3], s[4], speaker(window))
  if not path then return nil end
  return path, detail
end

-- The button's click: stop the line playing, or play the window's line again. Never while English is showing.
function VoicePlayer.toggle(window)
  if playing and playing.window == window then
    VoicePlayer.stop()
    return false
  end
  local line = last[window]
  if not line or not WFJ.State.enabled or WFJ.State.modifierHeld or not WFJ.Settings.get("voice.enabled") then
    return false
  end
  local path, seconds = replayable(window)
  if not path then return false end
  local shown = line.shown
  local started = play(path, seconds, line.key, window, true)
  if started then last[window].shown = shown end
  return started
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
  WFJ.State.on("modifier", function(held) if held then VoicePlayer.stop() end end)
  WFJ.State.on("enabled", stopUnless)
  WFJ.State.on("voice", function() -- any voice setting changed: the line playing may be one now off
    VoicePlayer.stop()
    for _, window in ipairs(WINDOWS) do
      if last[window] and not replayable(window) then last[window] = nil end -- its kind is off: no replay
      showButton(window, false)
    end
  end)
  for _, window in ipairs(WINDOWS) do
    local f = Compat.resolve(window)
    if type(f) == "table" and type(f.HookScript) == "function" then
      buttons[window] = createButton(window)
      f:HookScript("OnHide", function() closed(window) end)
    end
  end
  return true
end
