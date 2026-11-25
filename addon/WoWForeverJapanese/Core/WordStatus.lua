-- Core/WordStatus.lua: what the player knows of each word (docs/systems/word-status.md). Pure: no globals, no
-- frames. A Japanese word is its dictionary form with that form's reading, so every inflection shares one status
-- on every line; an English word is its lower-cased form. Statuses: "unknown", "learning", "known", "ignored".
--   Status.keyOf(word)             → lang, key for a word-card word | nil (a name, a class or race word)
--   Status.englishKey(token)       → the key of an English word as a line writes it
--   Status.get(lang, key)          → the word's status
--   Status.set(lang, key, status)  → true when it was kept
--   Status.step(lang, key)         → the new status: unknown → learning → known → unknown; ignored → unknown
--   Status.ignore(lang, key)       → the new status: ignored, or unknown for a word that was ignored
--   Status.learnNext(lang, key)    → true for one of the most used words that are still unknown
--   Status.counts(lang)            → known, learning, ignored among the game's words
--   Status.sync(entries, cardOf)   the saved word list and its study cards move statuses up, never down
--   Status.batch(fn)               runs fn and announces its changes once
-- Every change fires the State event "wordStatus".
-- With no status set by the player a word is unknown, unless it is a grammar word (ignored) or a する verb whose
-- noun is known (known). A status the player set wins.
-- Saved (WFJ_Known, account-wide): { schema = 1, ja = { [key] = "k" | "l" | "i" | "u" }, en = { … },
-- lastImport = { ja = { … }, en = { … } } }. "u" is kept only where the word would otherwise not be unknown.
local _, WFJ = ...
local Status = {}
WFJ.WordStatus = Status

Status.LEARN_NEXT = 300 -- how many of the most used unknown words are the ones to learn next
Status.KNOWN_AT = 21 -- a study card this many days stable makes its word known

local SCHEMA = 1
local CODE = { unknown = "u", learning = "l", known = "k", ignored = "i" }
local NAME = { u = "unknown", l = "learning", k = "known", i = "ignored" }

local saved = { schema = SCHEMA, ja = {}, en = {} }
local frozen = false -- saved by a newer addon version: kept as it is, never written
local learnNext, counted = {}, {} -- per language, worked out again after any change

local version = 0 -- goes up with every change: what a caller keeps beside something it worked out
local quiet, pending = false, false

local function changed()
  if quiet then
    pending = true
    return
  end
  learnNext, counted = {}, {}
  version = version + 1
  if WFJ.State then WFJ.State.fire("wordStatus") end
end

function Status.version() return version end

-- Runs `fn` and announces every change it made once, at the end (an import sets thousands of words).
function Status.batch(fn)
  quiet, pending = true, false
  local ok, err = pcall(fn)
  quiet = false
  if pending then changed() end
  if not ok then error(err, 0) end
end

-- `t`: the account's own table, or nil before it exists. → the table to save
function Status.load(t)
  frozen = type(t) == "table" and type(t.schema) == "number" and t.schema > SCHEMA
  if frozen then
    saved = { schema = SCHEMA, ja = {}, en = {} }
    changed()
    return t
  end
  if type(t) ~= "table" then t = {} end
  t.schema = SCHEMA
  for _, lang in ipairs({ "ja", "en" }) do
    if type(t[lang]) ~= "table" then t[lang] = {} end
    for key, code in pairs(t[lang]) do
      if type(key) ~= "string" or not NAME[code] then t[lang][key] = nil end
    end
  end
  if type(t.lastImport) ~= "table" then t.lastImport = nil end
  saved = t
  changed()
  return t
end

function Status.readonly() return frozen end

-- ── Keys ─────────────────────────────────────────────────────────────────────

local tokens -- the class and race words the addon fills in: they are names of a kind, and take no status
local function tokenWord(word)
  if not tokens then
    tokens = {}
    local list = WFJ.Readings and WFJ.Readings.tokenWords and WFJ.Readings.tokenWords() or {}
    for _, t in ipairs(list) do tokens[t[1]] = true end
  end
  return tokens[word] == true
end

function Status.englishKey(token)
  local F = WFJ.WordFrequency
  local lower = token:lower()
  if F.rank("en", lower) then return lower end
  -- a contraction is its first word (you're: you), a plural with no row of its own its singular (golds: gold),
  -- as on an English word card
  local head = WFJ.Readings and WFJ.Readings.contractionHead and WFJ.Readings.contractionHead(lower)
  if head and F.rank("en", head) then return head end
  local singular = lower:match("^(%a%a%a+[^s])s$")
  if singular and F.rank("en", singular) then return singular end
  return lower
end

function Status.keyOf(word)
  if type(word) ~= "table" or word.name or type(word.word) ~= "string" then return nil end
  local card = word.card
  if card and card.english then return "en", Status.englishKey(word.word) end
  if tokenWord(word.word) then return nil end
  local g = card or (WFJ.Glosses and WFJ.Glosses.get(word.gloss))
  if g and type(g.lemma) == "string" and type(g.lemmaReading) == "string" then
    return "ja", g.lemma .. "\t" .. g.lemmaReading
  end
  if type(word.reading) == "string" then return "ja", word.word .. "\t" .. word.reading end
  return nil
end

-- ── Status ───────────────────────────────────────────────────────────────────

function Status.get(lang, key)
  local code = saved[lang][key]
  if code then return NAME[code] end
  if lang == "ja" then
    if WFJ.WordFrequency.grammar(key) then return "ignored" end
    local noun, reading = key:match("^(.+)する\t(.+)する$")
    if noun and saved.ja[noun .. "\t" .. reading] == "k" then return "known" end
  end
  return "unknown"
end

-- → the status the player set, or nil
function Status.own(lang, key)
  return NAME[saved[lang][key]]
end

-- → { [key] = status } for every word the player set a status on
function Status.entries(lang)
  local out = {}
  for key, code in pairs(saved[lang]) do out[key] = NAME[code] end
  return out
end

function Status.set(lang, key, status)
  if frozen or not CODE[status] or type(key) ~= "string" or not saved[lang] then return false end
  saved[lang][key] = nil
  -- an unknown word that would be unknown anyway keeps no entry
  if not (status == "unknown" and Status.get(lang, key) == "unknown") then saved[lang][key] = CODE[status] end
  changed()
  return true
end

local NEXT = { unknown = "learning", learning = "known", known = "unknown", ignored = "unknown" }
function Status.step(lang, key)
  local to = NEXT[Status.get(lang, key)]
  return Status.set(lang, key, to) and to or nil
end

function Status.ignore(lang, key)
  local to = Status.get(lang, key) == "ignored" and "unknown" or "ignored"
  return Status.set(lang, key, to) and to or nil
end

function Status.learnNext(lang, key)
  local set = learnNext[lang]
  if not set then
    set = {}
    local F, found = WFJ.WordFrequency, 0
    for rank = 1, F.count(lang) do
      local k = F.at(lang, rank)
      if Status.get(lang, k) == "unknown" then
        set[k] = true
        found = found + 1
        if found >= Status.LEARN_NEXT then break end
      end
    end
    learnNext[lang] = set
  end
  return set[key] == true
end

function Status.counts(lang)
  local c = counted[lang]
  if not c then
    c = { known = 0, learning = 0, ignored = 0, unknown = 0 }
    local F = WFJ.WordFrequency
    for rank = 1, F.count(lang) do
      local status = Status.get(lang, F.at(lang, rank))
      c[status] = c[status] + 1
    end
    counted[lang] = c
  end
  return c.known, c.learning, c.ignored
end

-- ── The last import's numbers (Core/WordImport) ─────────────────────────────

function Status.noteImport(lang, numbers)
  if frozen then return end
  saved.lastImport = saved.lastImport or {}
  saved.lastImport[lang] = numbers
end

function Status.lastImport(lang)
  local last = saved.lastImport and saved.lastImport[lang]
  return type(last) == "table" and last or nil
end

-- ── The word list and its study cards ───────────────────────────────────────

local function entryKey(e)
  if type(e) ~= "table" or type(e.word) ~= "string" then return nil end
  if e.lang == "en" then return "en", Status.englishKey(e.word) end
  if tokenWord(e.word) then return nil end
  if type(e.lemma) == "string" and e.lemma ~= "" and type(e.lemmaReading) == "string" and e.lemmaReading ~= "" then
    return "ja", e.lemma .. "\t" .. e.lemmaReading
  end
  if type(e.reading) == "string" and e.reading ~= "" then return "ja", e.word .. "\t" .. e.reading end
  return nil
end

-- `entries`: the saved words (Core/Words); `cardOf(entryKey)`: a word's study card, or nil. A saved word with no
-- status becomes learning; a word whose card is stable for KNOWN_AT days becomes known unless it is ignored.
-- Nothing is ever moved down.
function Status.sync(entries, cardOf)
  if frozen then return end
  local moved = false
  for _, e in ipairs(entries or {}) do
    local lang, key = entryKey(e)
    if lang then
      local now = Status.get(lang, key)
      local card = cardOf and cardOf(e.key)
      if card and type(card.s) == "number" and card.s >= Status.KNOWN_AT then
        if now ~= "known" and now ~= "ignored" then
          saved[lang][key] = CODE.known
          moved = true
        end
      elseif now == "unknown" and saved[lang][key] == nil then
        saved[lang][key] = CODE.learning
        moved = true
      end
    end
  end
  if moved then changed() end
end
