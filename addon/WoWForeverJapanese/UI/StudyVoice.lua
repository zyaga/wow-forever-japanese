-- UI/StudyVoice.lua: a saved word's sentence in its NPC's recorded voice (ADR-092, docs/systems/study.md). The
-- sentence's files are found when the study card or the word list asks, from the entry's kind, id and sentence and
-- its line's sentence files and timing (Core/Voice format 3, ADR-090); nothing about audio is stored with a word, so
-- a word saved before this existed finds its audio the same way.
--   find(entry) → { clips = { { path, folder, file, seconds } }, stop = seconds | nil } | nil, why
--     why: "kind" (never voiced) · "nopack" · "missing" · "stale" (the pack's audio is older than the line's
--     Japanese) · "notfound" (the sentence is not in the line now) · "untimed" (one file, no timing, part of a line)
--   play(entry) · toggle(entry) · stop() · playing() · available(): the study card's sound. It plays alone on the
--     Master channel (no queue, no panel, no dialog mute), stops the voice line playing, and fires State
--     "studyVoice" when it starts and ends.
--   cell(entry) · copyLines(entries, mac): the word list's Anki export, file names only.
local _, WFJ = ...
local StudyVoice = {}
WFJ.StudyVoice = StudyVoice

local Compat = WFJ.Compat
local CHANNEL = "Master"
local PREFIX = "wfj-" -- the files' names in Anki's media folder, clear of other decks' media

-- The kinds of saved word whose line a pack may voice (Core/Voice.KINDS): quest offer, progress and turn-in, NPC
-- greetings and gossip (a quest window's greeting is gossip too), book and letter pages.
local VOICED = { ["quest.description"] = true, ["quest.progress"] = true, ["quest.completion"] = true,
  gossip = true, book = true }

-- ── Finding ──────────────────────────────────────────────────────────────

-- the line as the window shows it to this character (its player tokens filled in)
local function shown(ja)
  return type(WFJ.expandTokens) == "function" and WFJ.expandTokens(ja) or ja
end

-- the Japanese sentence a word was saved in; an English word's is the one its card's back shows
local function sentenceOf(e)
  local s = e.lang == "en" and e.jaSentence or e.sentence
  return type(s) == "string" and s ~= "" and s or nil
end

local function trim(s) return (s:match("^%s*(.-)%s*$")) end

-- the file holding the line's moment t: the last one that starts at or before it
local function clipAt(at, t)
  local i = 1
  while at[i + 1] and at[i + 1] <= t do i = i + 1 end
  return i
end

-- The files from the one where the sentence's first spoken part is to the one where its last is, and where to stop
-- when the next part is spoken in that last file too (the client can start a file only at its start, so a sentence
-- that starts inside a file plays that file from its start). → first, last, stop | nil
local function timedRange(rec, text, raw, s0, e0)
  local parts = WFJ.VoicePanelText.timedParts(text, raw, rec.marks, shown)
  local tFirst, tLast, tNext
  for _, p in ipairs(parts or {}) do
    if p.first > e0 then
      tNext = p.t
      break
    end
    if p.first >= s0 then
      tFirst = tFirst or p.t
      tLast = p.t
    end
  end
  if not tFirst then return nil end
  local at, t = {}, 0
  for i, c in ipairs(rec.clips) do
    at[i] = t
    t = t + (c[2] or 0)
  end
  local first, last = clipAt(at, tFirst), clipAt(at, tLast)
  local stop = tNext and clipAt(at, tNext) == last and tNext - at[first] or nil
  return first, last, stop
end

function StudyVoice.find(e)
  if type(e) ~= "table" or not VOICED[e.kind] then return nil, "kind" end
  local Voice = WFJ.Voice
  local key = Voice.packKey(e.kind, e.id)
  if not key then return nil, "kind" end
  if not Voice.hasPack() then return nil, "nopack" end
  local rec = Voice.record(key)
  local line = WFJ.Lookup and WFJ.Lookup.get(e.kind, e.id)
  if not rec or type(line) ~= "table" or type(line.ja) ~= "string" then return nil, "missing" end
  if WFJ.Hash.key(line.ja) ~= rec.jaHash then return nil, "stale" end
  local sentence, text = sentenceOf(e), shown(line.ja)
  local s0 = sentence and text:find(sentence, 1, true)
  if not s0 then return nil, "notfound" end
  local first, last, stop
  if rec.marks then
    first, last, stop = timedRange(rec, text, line.ja, s0, s0 + #sentence - 1)
  elseif trim(sentence) == trim(text) then
    first, last = 1, #rec.clips
  end
  if not first then return nil, "untimed" end
  local clips = {}
  for i = first, last do
    local c = rec.clips[i]
    clips[#clips + 1] = { path = Voice.soundPath(rec.folder, c[1]), folder = rec.folder, file = c[1],
      seconds = c[2] or 0 }
  end
  return { clips = clips, stop = stop }
end

-- ── Playing ──────────────────────────────────────────────────────────────

local current -- the sentence playing: { key, token, handle }
local tokens = 0

local function changed() WFJ.State.fire("studyVoice") end

-- A pack loaded, the voice and translation on: the card shows its button.
function StudyVoice.available()
  return WFJ.Voice.hasPack() and WFJ.Settings.get("voice.enabled") == true and WFJ.State.enabled == true
end

-- → the key of the entry playing, or nil
function StudyVoice.playing()
  return current and current.key or nil
end

function StudyVoice.stop()
  if not current then return end
  local stopSound = Compat.resolve("StopSound")
  if type(stopSound) == "function" and current.handle then stopSound(current.handle) end
  current = nil
  changed()
end

-- The files one after another, each started when the one before ends (the client reports no end, so by the pack's
-- lengths, as the voice player does), the last cut where the next sentence starts when it holds it too.
-- → true, or false and why
function StudyVoice.play(e)
  StudyVoice.stop()
  if not WFJ.Voice.hasPack() then return false, "nopack" end
  if not StudyVoice.available() then return false, "off" end
  local r, why = StudyVoice.find(e)
  if not r then return false, why end
  local playSoundFile = Compat.resolve("PlaySoundFile")
  if type(playSoundFile) ~= "function" then return false, "refused" end
  local VP = WFJ.VoicePlayer
  if VP and VP.playing() then VP.stop() end
  local ok, handle = playSoundFile(r.clips[1].path, CHANNEL)
  if not ok then return false, "refused" end
  tokens = tokens + 1
  local token = tokens
  current = { key = e.key, token = token, handle = handle }
  changed()
  local after = Compat.resolve("C_Timer.After")
  if type(after) ~= "function" then return true end
  local function mine() return current and current.token == token end
  local t = r.clips[1].seconds
  for i = 2, #r.clips do
    local c = r.clips[i]
    after(t, function()
      if not mine() then return end
      local started, h = playSoundFile(c.path, CHANNEL)
      if started then current.handle = h end
    end)
    t = t + c.seconds
  end
  after(r.stop or t, function()
    if not mine() then return end
    if r.stop then return StudyVoice.stop() end
    current = nil
    changed()
  end)
  return true
end

-- The card's button: stops the sentence playing, else plays this one. → true when it started
function StudyVoice.toggle(e)
  if current and type(e) == "table" and current.key == e.key then
    StudyVoice.stop()
    return false
  end
  return (StudyVoice.play(e))
end

-- Translation or the voice switched off stops it, as it stops the voice player.
WFJ.State.on("enabled", function(on) if not on then StudyVoice.stop() end end)
WFJ.State.on("voice", function()
  if WFJ.Settings.get("voice.enabled") ~= true then StudyVoice.stop() end
end)

-- ── The Anki export ──────────────────────────────────────────────────────

-- → "[sound:wfj-<file>]" for each of the sentence's files, or "" when it has none
function StudyVoice.cell(e)
  local r = StudyVoice.find(e)
  if not r then return "" end
  local out = {}
  for _, c in ipairs(r.clips) do out[#out + 1] = "[sound:" .. PREFIX .. c.file .. "]" end
  return table.concat(out)
end

local MAC = 'cp "Interface/AddOns/%s/Sound/%s" ~/"Library/Application Support/Anki2/User 1/collection.media/%s"'
local WINDOWS = 'copy /Y "Interface\\AddOns\\%s\\Sound\\%s" "%%APPDATA%%\\Anki2\\User 1\\collection.media\\%s"'

-- The lines that copy every entry's files into Anki's media folder, each file once, in list order: pasted in a
-- terminal opened in the client's _forever_ folder (an addon cannot copy files). `mac`: the Mac's cp, else
-- Windows' copy.
function StudyVoice.copyLines(entries, mac)
  local out, seen = {}, {}
  for _, e in ipairs(entries or {}) do
    local r = StudyVoice.find(e)
    for _, c in ipairs(r and r.clips or {}) do
      local id = c.folder .. "/" .. c.file
      if not seen[id] then
        seen[id] = true
        out[#out + 1] = (mac and MAC or WINDOWS):format(c.folder, c.file, PREFIX .. c.file)
      end
    end
  end
  return out
end
