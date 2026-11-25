-- Core/AnkiExport.lua: the word list as the Anki add-on reads it (ADR-110, docs/systems/anki-add-on.md). Pure: no
-- globals, no frames. An addon cannot write a file of its own, and the add-on cannot work out a sentence's furigana
-- or its sound files without the shipped readings and the loaded voice packs, so at logout the whole list is
-- written ready-made into the saved variables, where the add-on finds it.
--   AnkiExport.build(entries, now, deps) → { schema, written, voice, rows }
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

-- the sentence's files as "<pack folder>/Sound/<file>", in play order: where they sit under the AddOns folder
local function files(found)
  local out = {}
  for _, c in ipairs(found and found.clips or {}) do
    out[#out + 1] = text(c.folder) .. "/Sound/" .. text(c.file)
  end
  return out
end

local function row(e, deps)
  local en = e.lang == "en"
  return {
    key = text(e.key), lang = text(e.lang), word = text(e.word), reading = text(e.reading), lemma = text(e.lemma),
    lemmaReading = text(e.lemmaReading), meaning = text(e.meaning), sentence = text(deps.bold(e)),
    wordFurigana = en and text(e.word) or text(deps.furigana(e.word, e.reading)),
    sentenceFurigana = text(deps.sentenceFurigana(e)), jaSentence = text(e.jaSentence), source = text(e.source),
    questId = e.questId, questTitle = text(e.questTitle), saved = type(e.saved) == "number" and e.saved or nil,
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
