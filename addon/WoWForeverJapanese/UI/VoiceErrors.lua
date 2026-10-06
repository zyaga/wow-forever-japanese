-- UI/VoiceErrors.lua: the character's own spoken error lines ("out of range", "not enough mana") in Japanese, from the
-- voice pack (ADR-062). Core/Voice says which file; this file owns the sound and client-setting calls.
--   * When: the error frame plays the game's line through C_Sound.PlayVocalErrorSound(voiceID)
--     [verified: forever 1.60.1.70170 blizzard_uierrorsframe/mainline/uierrorsframe.lua:150-152]. A hook after it
--     plays the Japanese line for that voice id in the voice of the character's race and sex. The call is only
--     followed, never replaced, so the error frame's own code runs as it always does.
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

VoiceErrors.counts = { played = 0, skipped = 0 }

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

-- The hook after C_Sound.PlayVocalErrorSound. → true when a line started
function VoiceErrors.onVocalError(voiceID)
  local race, sex = character()
  local path, seconds = WFJ.Voice.errorFile(voiceID, race, sex)
  if not path then return false end
  local now = (Compat.resolve("GetTime") or function() return 0 end)()
  if path == lastKey and now - lastAt < REPEAT then
    VoiceErrors.counts.skipped = VoiceErrors.counts.skipped + 1
    return false
  end
  local playSoundFile = Compat.resolve("PlaySoundFile")
  if type(playSoundFile) ~= "function" or not playSoundFile(path, CHANNEL) then return false end
  lastKey, lastAt = path, now
  VoiceErrors.counts.played = VoiceErrors.counts.played + 1
  return true, seconds
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
  WFJ.State.on("voice", VoiceErrors.refresh)
  WFJ.State.on("enabled", VoiceErrors.refresh)
  VoiceErrors.refresh()
  return hooked
end
