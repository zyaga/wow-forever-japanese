-- Core/AnkiExport.lua: the word list as the Anki add-on reads it (ADR-110, docs/systems/anki-add-on.md). Pure: no
-- globals, no frames. An addon cannot write a file of its own, and the add-on cannot work out a sentence's furigana
-- or its sound files without the shipped readings and the loaded voice packs, so at logout the whole list is
-- written ready-made into the saved variables, where the add-on finds it.
--   AnkiExport.build(entries, now, deps) → { schema, written, voice, rows }: a row's text values are HTML, ready for
--     an Anki field (the saved word in <b>, readings as `word[reading]`); key, shot and audio are plain
--   AnkiExport.save(current, entries, now, deps, onError) → the table to keep in WFJ_Anki
-- deps: furigana(word, reading), sentenceFurigana(entry), bold(entry) (Core/Words); audio(entry) → what
-- StudyVoice.find returns, or nil; voice: a voice pack is loaded.
-- The rows are rebuilt from the whole list each time, so a word saved before a field existed gets it too. Nothing
-- reads the table in game.
local _, WFJ = ...
local AnkiExport = {}
WFJ.AnkiExport = AnkiExport

AnkiExport.SCHEMA = 1

local function text(v)
  if v == nil then return "" end
  return tostring(v)
end

-- A row's values go into Anki's fields, which hold HTML: a stage direction in angle brackets would be read as a tag
-- and vanish, and text another player typed could carry markup of its own. Square brackets are escaped too: Anki's
-- furigana filter reads `[...]` as a reading, and a link's label ("[Loot]") is not one.
local ESCAPES = { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ["["] = "&#91;", ["]"] = "&#93;" }
local function esc(v)
  return (text(v):gsub("[&<>%[%]]", ESCAPES))
end

-- the sentence's files as "<pack folder>/Sound/<file>", in play order: where they sit under the AddOns folder
local function files(found)
  local out = {}
  for _, c in ipairs(found and found.clips or {}) do
    out[#out + 1] = text(c.folder) .. "/Sound/" .. text(c.file)
  end
  return out
end

-- The entry with its texts escaped and the word's place moved to match, so the tags and readings the word list's
-- own functions add (the word in bold, `word[reading]`) are the only markup in what they return.
local function escaped(e)
  local s = type(e.sentence) == "string" and e.sentence or ""
  local wf, wl = e.wf, e.wl
  local copy = {}
  for k, v in pairs(e) do copy[k] = v end
  copy.word, copy.reading = esc(e.word), esc(e.reading)
  if type(wf) == "number" and type(wl) == "number" and wf >= 1 and wl <= #s and wl >= wf then
    local before, word = esc(s:sub(1, wf - 1)), esc(s:sub(wf, wl))
    copy.sentence = before .. word .. esc(s:sub(wl + 1))
    copy.wf, copy.wl = #before + 1, #before + #word
  else
    copy.sentence = esc(s)
  end
  return copy
end

local function row(e, deps)
  local en = e.lang == "en"
  local safe = escaped(e)
  return {
    key = text(e.key), lang = text(e.lang), word = safe.word, reading = safe.reading, lemma = esc(e.lemma),
    lemmaReading = esc(e.lemmaReading), meaning = esc(e.meaning), sentence = text(deps.bold(safe)),
    wordFurigana = en and safe.word or text(deps.furigana(safe.word, safe.reading)),
    sentenceFurigana = text(deps.sentenceFurigana(safe)), jaSentence = esc(e.jaSentence), source = esc(e.source),
    questId = e.questId, questTitle = esc(e.questTitle), saved = type(e.saved) == "number" and e.saved or nil,
    shot = text(e.shot), audio = files(deps.audio(e)),
  }
end

function AnkiExport.build(entries, now, deps)
  local rows = {}
  for _, e in ipairs(entries or {}) do
    if type(e) == "table" then rows[#rows + 1] = row(e, deps) end
  end
  return { schema = AnkiExport.SCHEMA, written = now, voice = deps.voice == true, rows = rows }
end

-- A fault while building keeps the table that was loaded: the client writes whatever the global holds, and an
-- older copy of the list is better than none.
function AnkiExport.save(current, entries, now, deps, onError)
  local ok, result = pcall(AnkiExport.build, entries, now, deps)
  if ok then return result end
  if onError then onError(result) end
  return current
end
