-- UI/VoiceErrors.lua: the character's own spoken error lines ("out of range", "not enough mana") in Japanese, from the
-- voice pack (ADR-062). Core/Voice says which file; this file owns the sound and client-setting calls.
--   * When: the error frame's TryDisplayMessage plays the game's line through C_Sound.PlayVocalErrorSound(voiceID)
--     [verified: forever 1.60.1.70170 blizzard_uierrorsframe/mainline/uierrorsframe.lua:146-157]. A hook after that
--     call notes the voice id; a hook after TryDisplayMessage then reads which message it showed
--     (GetGameMessageInfo, its global string name) and plays that message's recording, so the voice says the words
--     on screen; a call from anywhere else plays the voice id's line on the next frame. Both are only followed,
--     never replaced, so the error frame's own code runs as it always does.
--   * The player's setting: the error frame calls PlayVocalErrorSound whatever the client's error speech setting
--     (Sound_EnableErrorSpeech) says, and the client checks the setting inside that call. So a line plays here only
--     while that setting is on, and the setting is never written: on means the Japanese line, off means silence.
--   * The English line: while this is on and a pack carries lines for the character, the English recordings for
--     the character's race and sex (Data/ErrorSounds.lua, the client's own sound table) are muted with
--     MuteSoundFile, so the English line does not play under the Japanese one
--     [unverified: whether a muted file silences the call on Forever; in-game check in docs/testing/strategy.md].
--     A mute lasts until the client closes and is saved nowhere; it is taken off when the feature is switched off
--     and at logout. An earlier version turned the setting itself off and noted it in
--     WFJ_DB.voiceErrorSpeechMuted: that note is still honoured once, to give the setting back.
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
local displayHooked, subscribed = false, false -- each hook and listener once, however often init runs

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

-- The character's race (the client's file name, "Tauren"), sex (UnitSex: 2 male, 3 female) and race id
local function character()
  local unitRace, unitSex = Compat.resolve("UnitRace"), Compat.resolve("UnitSex")
  local race, raceID
  if type(unitRace) == "function" then race, raceID = select(2, unitRace("player")) end
  return race, type(unitSex) == "function" and unitSex("player") or nil, raceID
end

-- Whether the player has the client's error speech on. Unknown reads as on.
local function speechOn()
  local value = getCVar(SPEECH)
  return value == nil or tostring(value) ~= "0"
end

-- The English error recordings of the character's race and sex (file ids), or nil.
local function englishFiles()
  local _, sex, raceID = character()
  local all = WFJ.Data and WFJ.Data.errorSounds
  local byRace = type(all) == "table" and all[raceID] or nil
  return type(byRace) == "table" and byRace[sex == 3 and "f" or "m"] or nil
end

local mutedNow -- true once the files were muted this session, false once unmuted, nil before either

-- Mutes or unmutes the character's English recordings. → the number of files touched
local function setMuted(on)
  if mutedNow == on then return 0 end
  local fn = Compat.resolve(on and "MuteSoundFile" or "UnmuteSoundFile")
  local files = englishFiles()
  if type(fn) ~= "function" or type(files) ~= "table" then return 0 end
  for _, id in ipairs(files) do fn(id) end
  mutedNow = on
  VoiceErrors.muted = on and #files or 0
  return #files
end

local function wanted()
  if not (WFJ.State.enabled and WFJ.Settings.get("voice.enabled") and WFJ.Settings.get("voice.errors")) then
    return false
  end
  local race, sex = character()
  return WFJ.Voice.hasErrors(race, sex)
end

-- Gives the client's error speech setting back if an earlier version of this addon turned it off.
-- → true when it did
local function giveBack()
  if not (db and db.voiceErrorSpeechMuted) then return false end
  db.voiceErrorSpeechMuted = nil
  setCVar(SPEECH, "1")
  return true
end

-- Takes the mute off the English recordings, and gives the setting back as above. → true when it gave it back
function VoiceErrors.restore()
  setMuted(false)
  return giveBack()
end

-- Mutes the English recordings while Japanese lines can play, unmutes them otherwise.
function VoiceErrors.refresh()
  if not db then return end
  setMuted(wanted())
end

local pending -- the voice id the game just asked to speak, until its message is known

-- Plays the character's line for a voice id, as the message on screen when known. → true when a line started
function VoiceErrors.play(voiceID, message)
  local race, sex = character()
  if not speechOn() then
    VoiceErrors.last = { voiceID = voiceID, message = message, race = race, sex = sex, why = "setting" }
    return false
  end
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
  giveBack() -- the refresh below settles the mute: on when lines can play, off otherwise (a mute outlives a reload)
  local C = Compat.resolve("C_Sound")
  if not hooked and type(C) == "table" and type(C.PlayVocalErrorSound) == "function" then
    hooksecurefunc(C, "PlayVocalErrorSound", VoiceErrors.onVocalError)
    hooked = true
  end
  local frame = Compat.resolve("UIErrorsFrame")
  if not displayHooked and type(frame) == "table" and type(frame.TryDisplayMessage) == "function" then
    hooksecurefunc(frame, "TryDisplayMessage", VoiceErrors.onDisplay)
    displayHooked = true
  end
  if not subscribed then
    WFJ.State.on("voice", VoiceErrors.refresh)
    WFJ.State.on("enabled", VoiceErrors.refresh)
    subscribed = true
  end
  VoiceErrors.refresh()
  return hooked
end
