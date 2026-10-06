-- UI/VoiceErrors.lua: the character's own spoken error lines ("out of range", "not enough mana") in Japanese, from the
-- voice pack (ADR-062). Core/Voice says which file; this file owns the sound and client-setting calls.
--   * When: the error frame's TryDisplayMessage plays the game's line through C_Sound.PlayVocalErrorSound(voiceID)
--     [verified: forever 1.60.1.70170 blizzard_uierrorsframe/mainline/uierrorsframe.lua:146-157]. A hook after that
--     call notes the voice id; a hook after TryDisplayMessage then reads which message it showed
--     (GetGameMessageInfo, its global string name) and plays that message's recording, so the voice says the words
--     on screen; a call from anywhere else plays the voice id's line on the next frame. Both are only followed,
--     never replaced, so the error frame's own code runs as it always does.
--   * The English line: while this is on and a pack carries lines for the character, the client's error speech
--     setting (Sound_EnableErrorSpeech) is turned off, so the English line does not play under the Japanese one
--     [unverified: whether the setting silences the call on Forever; in-game check in docs/testing/strategy.md].
--     The client saves the setting, so the change is kept in WFJ_DB.voiceErrorSpeechMuted and undone when the
--     feature is switched off, at logout and on the next load. A player who had it off keeps it off.
--   * Repeats: the same line is not started again within REPEAT seconds (an ability spammed out of range).
local _, WFJ = ...
local VoiceErrors = {}
WFJ.VoiceErrors = VoiceErrors

local Compat = WFJ.Compat
local SPEECH = "Sound_EnableErrorSpeech"
local CHANNEL = "Master"
local REPEAT = 2

-- every step, for /wfj debug: the game asked (calls), the message was known (shown), played, a repeat skipped,
-- the client refused; and why the last line that did not play stayed silent, with its voice id and message
VoiceErrors.counts = { calls = 0, shown = 0, played = 0, skipped = 0, refused = 0 }
VoiceErrors.last = {}

local db
local lastKey, lastAt = nil, 0
local hooked = false

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

-- The character's race (the client's file name, "Tauren") and sex (UnitSex: 2 male, 3 female)
local function character()
  local unitRace, unitSex = Compat.resolve("UnitRace"), Compat.resolve("UnitSex")
  local race = type(unitRace) == "function" and select(2, unitRace("player")) or nil
  return race, type(unitSex) == "function" and unitSex("player") or nil
end

local function wanted()
  if not (WFJ.State.enabled and WFJ.Settings.get("voice.enabled") and WFJ.Settings.get("voice.errors")) then
    return false
  end
  local race, sex = character()
  return WFJ.Voice.hasErrors(race, sex)
end

-- Puts the client's error speech back if this addon turned it off. → true when it did
function VoiceErrors.restore()
  if not (db and db.voiceErrorSpeechMuted) then return false end
  db.voiceErrorSpeechMuted = nil
  setCVar(SPEECH, "1")
  return true
end

-- Turns the English error speech off while Japanese lines can play, back on otherwise.
function VoiceErrors.refresh()
  if not db then return end
  if wanted() then
    if not db.voiceErrorSpeechMuted and tostring(getCVar(SPEECH)) == "1" then
      db.voiceErrorSpeechMuted = true
      setCVar(SPEECH, "0")
    end
  else
    VoiceErrors.restore()
  end
end

local pending -- the voice id the game just asked to speak, until its message is known

-- Plays the character's line for a voice id, as the message on screen when known. → true when a line started
function VoiceErrors.play(voiceID, message)
  local race, sex = character()
  local path, seconds = WFJ.Voice.errorFile(voiceID, race, sex, message)
  VoiceErrors.last = { voiceID = voiceID, message = message, race = race, sex = sex, why = seconds }
  if not path then return false end
  local now = (Compat.resolve("GetTime") or function() return 0 end)()
  if path == lastKey and now - lastAt < REPEAT then
    VoiceErrors.counts.skipped = VoiceErrors.counts.skipped + 1
    VoiceErrors.last.why = "repeat"
    return false
  end
  local playSoundFile = Compat.resolve("PlaySoundFile")
  if type(playSoundFile) ~= "function" or not playSoundFile(path, CHANNEL) then
    VoiceErrors.counts.refused = VoiceErrors.counts.refused + 1
    VoiceErrors.last.why = "refused"
    return false
  end
  VoiceErrors.last.why = "played"
  lastKey, lastAt = path, now
  VoiceErrors.counts.played = VoiceErrors.counts.played + 1
  return true, seconds
end

-- The hook after C_Sound.PlayVocalErrorSound: the line waits for its message, or plays on the next frame.
function VoiceErrors.onVocalError(voiceID)
  VoiceErrors.counts.calls = VoiceErrors.counts.calls + 1
  pending = voiceID
  local timer = Compat.resolve("C_Timer")
  if type(timer) == "table" and type(timer.After) == "function" then
    timer.After(0, function()
      if pending == voiceID then
        pending = nil
        VoiceErrors.play(voiceID)
      end
    end)
  end
end

-- The hook after the error frame's TryDisplayMessage: the message it showed names the recording.
function VoiceErrors.onDisplay(_, messageType)
  if pending == nil then return end
  local voiceID = pending
  pending = nil
  VoiceErrors.counts.shown = VoiceErrors.counts.shown + 1
  local info = Compat.resolve("GetGameMessageInfo")
  local message = type(info) == "function" and info(messageType) or nil
  VoiceErrors.play(voiceID, type(message) == "string" and message or nil)
end

-- Called by Main after Voice and Settings. `savedDb` is WFJ_DB. Safe without a pack: nothing changes.
function VoiceErrors.init(savedDb)
  db = savedDb
  VoiceErrors.restore() -- a crash or a removed pack must never leave the player's error speech off
  local C = Compat.resolve("C_Sound")
  if not hooked and type(C) == "table" and type(C.PlayVocalErrorSound) == "function" then
    hooksecurefunc(C, "PlayVocalErrorSound", VoiceErrors.onVocalError)
    hooked = true
  end
  local frame = Compat.resolve("UIErrorsFrame")
  if type(frame) == "table" and type(frame.TryDisplayMessage) == "function" then
    hooksecurefunc(frame, "TryDisplayMessage", VoiceErrors.onDisplay)
  end
  WFJ.State.on("voice", VoiceErrors.refresh)
  WFJ.State.on("enabled", VoiceErrors.refresh)
  VoiceErrors.refresh()
  return hooked
end
