-- Core/WordScore.lua: how much of a text the player knows (docs/systems/word-status.md). Pure: no globals, no
-- frames. A score is known words over counted words: an ignored word is in neither, a learning word counts as not
-- known, and a name or a word with no key is not a word here.
--   Score.line(lang, kind, id)  → known, counted for one line's own words
--   Score.text(lang, kind, id)  → known, counted for the text a line belongs to: a quest's whole text, else the line
--   Score.game(lang)            → { known, counted, kinds = { [kind] = { known, counted } } }: every word weighted by
--                                 how often the game uses it
--   Score.percent(known, counted) → a whole percent, or nil for a text with nothing counted
local _, WFJ = ...
local Score = {}
WFJ.WordScore = Score

local function add(lang, key, known, counted)
  local status = WFJ.WordStatus.get(lang, key)
  if status == "ignored" then return known, counted end
  return known + (status == "known" and 1 or 0), counted + 1
end

function Score.line(lang, kind, id, known, counted)
  known, counted = known or 0, counted or 0
  local R = WFJ.Readings
  if lang == "en" then
    for _, word in ipairs(R.englishWords(kind, id) or {}) do known, counted = add("en", word, known, counted) end
    return known, counted
  end
  local words = R.words(kind, id) or {}
  for i = 1, #words, 3 do
    local wordLang, key = WFJ.WordStatus.keyOf({ word = words[i], reading = words[i + 1], gloss = words[i + 2] or nil })
    if wordLang then known, counted = add(wordLang, key, known, counted) end
  end
  return known, counted
end

-- a quest is read as one text: its description, objectives, progress and turn-in text together
local QUEST_FIELDS = { "description", "objectives", "progress", "completion" }
function Score.text(lang, kind, id)
  if type(kind) == "string" and kind:find("^quest%.") then
    local known, counted = 0, 0
    for _, field in ipairs(QUEST_FIELDS) do
      known, counted = Score.line(lang, "quest." .. field, id, known, counted)
    end
    return known, counted
  end
  return Score.line(lang, kind, id)
end

local games = {} -- lang → { version, score }
function Score.game(lang)
  local Status, F = WFJ.WordStatus, WFJ.WordFrequency
  local kept = games[lang]
  if kept and kept.version == Status.version() then return kept.score end
  local score = { known = 0, counted = 0, kinds = {} }
  for _, kind in ipairs(F.KINDS) do score.kinds[kind] = { known = 0, counted = 0 } end
  for rank = 1, F.count(lang) do
    local key = F.at(lang, rank)
    local status = Status.get(lang, key)
    if status ~= "ignored" then
      local uses = F.uses(lang, key)
      for at, kind in ipairs(F.KINDS) do
        local n, k = uses[at] or 0, score.kinds[kind]
        k.counted, score.counted = k.counted + n, score.counted + n
        if status == "known" then k.known, score.known = k.known + n, score.known + n end
      end
    end
  end
  games[lang] = { version = Status.version(), score = score }
  return score
end

function Score.percent(known, counted)
  if not counted or counted <= 0 then return nil end
  -- rounded down: a text with a word still unknown never reads as 100
  return math.floor(100 * known / counted)
end
