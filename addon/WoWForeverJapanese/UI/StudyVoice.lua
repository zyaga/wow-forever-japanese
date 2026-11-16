-- UI/StudyVoice.lua: a saved word's sentence in its NPC's recorded voice (ADR-092, docs/systems/study.md). The
-- sentence's files are found when the study card or the word list asks, from the entry's kind, id and sentence and
-- its line's sentence files and timing (Core/Voice format 3, ADR-090); nothing about audio is stored with a word, so
-- a word saved before this existed finds its audio the same way.
--   find(entry) → { clips = { { path, folder, file, seconds } }, stop = seconds | nil } | nil, why
--     why: "kind" (never voiced) · "nopack" · "missing" · "stale" (the pack's audio is older than the line's
--     Japanese) · "notfound" (the sentence is not in the line now) · "untimed" (one file, no timing, part of a line)
--   play(entry, found) · toggle(entry, found) · stop() · playing() · available(): the study card's sound (`found`:
--     what find returned, when the caller has it). It plays alone on the Master channel (no queue, no panel, no
--     dialog mute), needs only a voice pack, stops the voice line playing, and fires State "studyVoice" when it
--     starts and ends.
--   findAll(entries) · cell(found) · fileList(entries, found): the word list's Anki export, file names only.
local _, WFJ = ...
local StudyVoice = {}
WFJ.StudyVoice = StudyVoice

local Compat = WFJ.Compat
local CHANNEL = "Master"
local UNKNOWN_LENGTH = 30 -- a file a pack gives no length: the voice player's guess, so its end is not missed

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

-- a sentence starts the line, or follows a sentence end, a line break or a space
local STARTS = { ["。"] = true, ["！"] = true, ["？"] = true, ["!"] = true, ["?"] = true, ["」"] = true }
local function startsSentence(text, i)
  if i == 1 or text:sub(i - 1, i - 1):match("%s") then return true end
  for mark in pairs(STARTS) do
    if i > #mark and text:sub(i - #mark, i - 1) == mark then return true end
  end
  return false
end

-- Where the saved sentence is in the line: the first place it starts a sentence (a short one, 「行け！」, also sits
-- inside an earlier 「早く行け！」), else the first place at all.
local function locate(text, sentence)
  local first = text:find(sentence, 1, true)
  local i = first
  while i do
    if startsSentence(text, i) then return i end
    i = text:find(sentence, i + 1, true)
  end
  return first
end

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
  if type(e) ~= "table" then return nil, "kind" end
  local rec, ja = WFJ.Voice.line(e.kind, e.id)
  if not rec then return nil, ja end
  local sentence, text = sentenceOf(e), shown(ja)
  local s0 = sentence and locate(text, sentence)
  if not s0 then return nil, "notfound" end
  local first, last, stop
  if rec.marks then
    first, last, stop = timedRange(rec, text, ja, s0, s0 + #sentence - 1)
  elseif trim(sentence) == trim(text) then
    first, last = 1, #rec.clips
  end
  if not first then return nil, "untimed" end
  local clips = {}
  for i = first, last do
    local c = rec.clips[i]
    clips[#clips + 1] = { path = WFJ.Voice.soundPath(rec.folder, c[1]), folder = rec.folder, file = c[1],
      seconds = (c[2] or 0) > 0 and c[2] or UNKNOWN_LENGTH }
  end
  return { clips = clips, stop = stop }
end

-- ── Playing ──────────────────────────────────────────────────────────────

local current -- the sentence playing: { key, handle }; a timer of an older one finds it replaced and does nothing

local function changed() WFJ.State.fire("studyVoice") end

-- A pack loaded: the card shows its button. Nothing else: it is a study tool, so it plays whatever translation, the
-- voice switch (NPCs reading aloud in the world), the reveal key or the direction say.
function StudyVoice.available()
  return WFJ.Voice.hasPack()
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
-- lengths, as the voice player does), the last cut where the next sentence starts when it holds it too. Only the
-- next step waits on a timer. `found`: what find returned for this entry, when the caller has it.
-- → true, or false and why
function StudyVoice.play(e, found)
  StudyVoice.stop()
  if not StudyVoice.available() then return false, "nopack" end
  local r, why = found, nil
  if not r then r, why = StudyVoice.find(e) end
  if not r then return false, why end
  local playSoundFile = Compat.resolve("PlaySoundFile")
  if type(playSoundFile) ~= "function" then return false, "refused" end
  local ok, handle = playSoundFile(r.clips[1].path, CHANNEL)
  if not ok then return false, "refused" end
  -- one voice at a time: the voice player's line, and the lines waiting their turn, give way once this one started
  local VP = WFJ.VoicePlayer
  if VP and VP.playing() then VP.stop() end
  local me = { key = e.key, handle = handle }
  current = me
  changed()
  local after = Compat.resolve("C_Timer.After")
  if type(after) ~= "function" then return true end
  local at, total = {}, 0 -- each file's start, from the first file's
  for i, c in ipairs(r.clips) do
    at[i] = total
    total = total + c.seconds
  end
  local finish = r.stop or total
  -- after file i - 1 started: start file i, or end the sentence
  local function step(i)
    after((at[i] or finish) - at[i - 1], function()
      if current ~= me then return end
      if not r.clips[i] then
        if r.stop then return StudyVoice.stop() end
        current = nil
        return changed()
      end
      local started, h = playSoundFile(r.clips[i].path, CHANNEL)
      if started then me.handle = h end
      step(i + 1)
    end)
  end
  step(2)
  return true
end

-- The card's button: stops the sentence playing, else plays this one. → true when it started
function StudyVoice.toggle(e, found)
  if current and type(e) == "table" and current.key == e.key then
    StudyVoice.stop()
    return false
  end
  return (StudyVoice.play(e, found))
end

-- ── The Anki export ──────────────────────────────────────────────────────

-- → each entry's files as find returns them, by entry (none for an entry without audio): one search per word for
-- both the export's cells and the file list
function StudyVoice.findAll(entries)
  local found = {}
  for _, e in ipairs(entries or {}) do found[e] = StudyVoice.find(e) end
  return found
end

-- → "[sound:<file>]" for each file of what find returned, or "" for nothing: the files keep the packs' names, which
-- is how a player copying them by hand finds them in Anki's media folder
function StudyVoice.cell(r)
  local out = {}
  for _, c in ipairs(r and r.clips or {}) do out[#out + 1] = "[sound:" .. c.file .. "]" end
  return table.concat(out)
end

-- The files the player copies into Anki's media folder, each once, under the pack folder it is in (both in list
-- order): "<folder>/Sound:" then "  <file>" lines. An addon cannot copy files, and cannot know where the game is
-- installed, so the window names the folders from the World of Warcraft folder the player knows.
function StudyVoice.fileList(entries, found)
  local order, files, seen = {}, {}, {}
  for _, e in ipairs(entries or {}) do
    local r = found[e]
    for _, c in ipairs(r and r.clips or {}) do
      if not files[c.folder] then
        files[c.folder] = {}
        order[#order + 1] = c.folder
      end
      local id = c.folder .. "/" .. c.file
      if not seen[id] then
        seen[id] = true
        local list = files[c.folder]
        list[#list + 1] = "  " .. c.file
      end
    end
  end
  local out = {}
  for _, folder in ipairs(order) do
    out[#out + 1] = folder .. "/Sound:"
    for _, line in ipairs(files[folder]) do out[#out + 1] = line end
  end
  return out
end
