-- Core/Readings.lua: whole-word readings (ADR-036), the read path over WFJ.Data.reading and where each word sits
-- in the text on screen. Pure: no globals, no frames. The display is UI/Readings.lua.
--   Readings.words(kind, id)        → { word, reading, gloss, … } | nil; gloss = meaning number or false
--                                      kind = "quest.<field>" | "gossip" | "ui" | "book" | "item.description" |
--                                      "spell.description" | "spell.aura"
--   Readings.locate(words, text[, guards])
--                                   → { { first, last, word, reading, gloss }, … }: byte positions, found in order;
--                                      a word the text lacks is skipped; a match on part of a guard span is passed over
--   Readings.lookup(kind, id, text) → locate(words(kind, id), text, tokenSpans(text)) | nil
--   Readings.tokenSpans(text)       → { { first, last }, … }: every class / race word standing alone in `text`
--   Readings.withNames(spans, text, names)
--                                   → `spans` plus a span for each name the addon wrote into `text` in Japanese
--                                      (names = { { ja, english, reading }, … } in text order, from the policy
--                                      layer's payload): its card gives the reading and the English name
--   Readings.englishLookup(kind, id, text)
--                                   → { { first, last, word, reading, card }, … }: the English words of `text` that
--                                      have a Japanese word, for the English word card (English first); nil for a
--                                      kind that takes no cards or without text
-- Rows (Data/Reading/*.lua): ["<type>:<id>"] = { <field> = "word=reading word=reading=n …" }; "=n" is the word's
-- meaning in Data/Gloss. The pipeline guarantees no " " or "=" inside a word or a reading.
local _, WFJ = ...
local Readings = {}
WFJ.Readings = Readings

local TOOLTIP_FIELDS = { item = { description = true }, spell = { description = true, aura = true } }

local function split(kind)
  if kind == "gossip" then return "gossip", "text" end
  if kind == "ui" then return "ui", "text" end -- ["ui:<KEY>"] (ADR-041)
  if kind == "book" then return "book", "text" end -- ["book:<English hash>"] (ADR-044)
  if type(kind) ~= "string" then return nil end
  local field = kind:match("^quest%.(%a+)$")
  if field then return "quest", field end
  -- tooltip text, shown with word cards on a frozen tooltip (UI/TooltipFreeze): ["item:<id>"], ["spell:<id>"]
  local type_, own = kind:match("^(%a+)%.(%a+)$")
  if TOOLTIP_FIELDS[type_] and TOOLTIP_FIELDS[type_][own] then return type_, own end
  return nil
end

-- A packed row is parsed once: a label the client rewrites every frame (map coordinates) looks it up on every change.
local parsed = setmetatable({}, { __mode = "v" })

function Readings.words(kind, id)
  local type_, field = split(kind)
  if not type_ or id == nil then return nil end
  local row = WFJ.Data.reading[type_ .. ":" .. tostring(id)]
  local packed = row and row[field]
  if type(packed) ~= "string" then return nil end
  if parsed[packed] then return parsed[packed] end
  local out = {}
  for item in packed:gmatch("[^ ]+") do
    local word, reading, n = item:match("^([^=]+)=([^=]+)=?(%d*)$")
    if word then
      out[#out + 1] = word
      out[#out + 1] = reading
      out[#out + 1] = tonumber(n) or false
    end
  end
  parsed[packed] = out
  return out
end

-- A listed word never anchors on part of a filled-in class / race word (エルフ inside ナイトエルフ). A match that
-- covers the whole span is kept: the word itself (ドルイド) or a word holding it (ウォリアーたち).
local function inside(guards, s, e)
  for _, g in ipairs(guards) do
    if s <= g.last and e >= g.first and not (s <= g.first and e >= g.last) then return true end
  end
  return false
end

function Readings.locate(words, text, guards)
  local out, cursor = {}, 1
  for i = 1, #words - 2, 3 do
    local s, e = text:find(words[i], cursor, true)
    while s and guards and inside(guards, s, e) do
      s, e = text:find(words[i], s + 1, true)
    end
    if s then
      out[#out + 1] = { first = s, last = e, word = words[i], reading = words[i + 1], gloss = words[i + 2] or nil }
      cursor = e + 1
    end
  end
  return out
end

function Readings.lookup(kind, id, text)
  local words = Readings.words(kind, id)
  if not words or type(text) ~= "string" then return nil end
  return Readings.locate(words, text, Readings.tokenSpans(text))
end

-- ── English word cards ─────────────────────────────────────────────────────
-- Rows (Data/English/*.lua): ["<type>:<id>"] = { <field> = "word=n word=n …" }: the line's English words that have a
-- Japanese word, lower-cased and sorted (never the sentence), n the place of that Japanese word in the same line's
-- reading row. Data.pron: word → how it is said. Data.common: word → "Japanese=reading", for the everyday words a
-- line's own row leaves out.

local englishRows = setmetatable({}, { __mode = "v" })
local function englishMap(packed)
  local map = englishRows[packed]
  if map then return map end
  map = {}
  for word, n in packed:gmatch("([^ =]+)=(%d+)") do map[word] = tonumber(n) end
  englishRows[packed] = map
  return map
end

-- → the lower-cased English words a line's row lists, in no order | nil (a line with no row)
function Readings.englishWords(kind, id)
  local type_, field = split(kind)
  local row = type_ and id ~= nil and WFJ.Data.english[type_ .. ":" .. tostring(id)]
  local packed = row and row[field]
  if type(packed) ~= "string" then return nil end
  local out = {}
  for word in pairs(englishMap(packed)) do out[#out + 1] = word end
  return out
end

local function englishCard(ja, jaReading, gloss, ipa)
  return { english = true, ja = ja, jaReading = jaReading, gloss = gloss or nil, ipa = ipa }
end
Readings.englishCard = englishCard -- Core/ChatWords builds a chat word's card the same way

-- A contraction with no card of its own takes its first word's (you're → you, let's → let); never a negative
-- (can't is not can). → that first word, or nil
function Readings.contractionHead(lower)
  if lower:find("n't$") then return nil end
  return lower:match("^(%a+)'")
end

-- A capitalised word inside a sentence is a name, and names take no card (the pipeline leaves them out of the rows
-- the same way): true when the word at `first` starts its sentence or its line.
local OPENERS = { [" "] = true, ['"'] = true, ["'"] = true, ["("] = true }
local ENDERS = { ["."] = true, ["!"] = true, ["?"] = true, [":"] = true, ["\n"] = true }
local function startsSentence(text, first)
  local i = first - 1
  while i >= 1 do
    local c = text:sub(i, i)
    if OPENERS[c] then
      i = i - 1
    elseif i >= 3 and (text:sub(i - 2, i) == "\226\128\156" or text:sub(i - 2, i) == "\226\128\152") then
      i = i - 3 -- a curly opening quote
    else
      return ENDERS[c] == true
    end
  end
  return true
end

-- A word is a run of ASCII letters and apostrophes, so both ends of a span are always character boundaries.
function Readings.englishLookup(kind, id, text)
  local type_, field = split(kind)
  if not type_ or type(text) ~= "string" then return nil end
  local row = id ~= nil and WFJ.Data.english[type_ .. ":" .. tostring(id)]
  local packed = row and row[field]
  local map = type(packed) == "string" and englishMap(packed) or nil
  local words = map and Readings.words(kind, id)
  local out = {}
  -- → ja, jaReading, gloss for one lower-cased word: from the line's own row, else the common list
  local function find(lower)
    local n = map and words and map[lower]
    if n then
      if words[3 * n - 2] then return words[3 * n - 2], words[3 * n - 1], words[3 * n] end
      return nil -- a place past the reading row's end: dropped, never read
    end
    local common = WFJ.Data.common[lower]
    if type(common) == "string" then return common:match("^([^=]+)=([^=]+)$") end
    return nil
  end
  for start, raw in text:gmatch("()([%a']+)") do
    -- a quote mark before the word ('Hello) is not part of it
    local token = raw:gsub("^'+", "")
    local first = start + #raw - #token
    local lower = token:lower()
    local isName = token:find("^%u") ~= nil and token ~= "I" and not startsSentence(text, first)
    local ja, jaReading, gloss, said
    if token ~= "" and not isName then
      ja, jaReading, gloss = find(lower)
      if not ja and lower:find("'$") then
        -- a closing quote mark after the word ('Hunt') is not part of it either; a word that ends in one of its
        -- own (givin') was found above
        token = token:gsub("'+$", "")
        lower = token:lower()
        ja, jaReading, gloss = find(lower)
      end
      said = WFJ.Data.pron[lower]
      -- a contraction with no card of its own takes its first word's (you're → you, let's → let); never a
      -- negative (can't is not can)
      local head = not ja and Readings.contractionHead(lower) or nil
      if head then
        ja, jaReading, gloss = find(head)
        said = said or WFJ.Data.pron[head]
      end
    end
    if ja then
      out[#out + 1] = { first = first, last = first + #token - 1, word = token,
        reading = ja == jaReading and ja or (ja .. "（" .. jaReading .. "）"),
        card = englishCard(ja, jaReading, gloss, said) }
    end
  end
  return out
end

-- The class and race words filled in for {class} / {race} are not in the stored Japanese, so no reading row lists
-- them; they get their own card wherever they stand alone. The meaning is the English name (names stay English).
-- Spellings come from Core/Placeholders at call time (it loads after this file).
-- 人間 (Human) is left out: in prose it is the common noun "person", and its own reading entry covers it.
local ENGLISH = {
  WARRIOR = "Warrior (a class)", PALADIN = "Paladin (a class)", HUNTER = "Hunter (a class)", ROGUE = "Rogue (a class)",
  PRIEST = "Priest (a class)", SHAMAN = "Shaman (a class)", MAGE = "Mage (a class)", WARLOCK = "Warlock (a class)",
  DRUID = "Druid (a class)", Orc = "Orc (a race)", Dwarf = "Dwarf (a race)", NightElf = "Night Elf (a race)",
  Scourge = "Undead (a race)", Tauren = "Tauren (a race)", Gnome = "Gnome (a race)", Troll = "Troll (a race)",
}

local tokenWords -- { { word, meaning }, … }, built on first use from Placeholders.CLASS / RACE
function Readings.tokenWords()
  if tokenWords then return tokenWords end
  local P = WFJ.Placeholders
  if not P then return {} end
  tokenWords = {}
  for _, tbl in ipairs({ P.CLASS, P.RACE }) do
    local keys = {}
    for k in pairs(tbl) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
      if ENGLISH[k] then tokenWords[#tokenWords + 1] = { tbl[k], ENGLISH[k] } end
    end
  end
  return tokenWords
end

local function overlaps(spans, s, e)
  for _, sp in ipairs(spans) do
    if s <= sp.last and e >= sp.first then return true end
  end
  return false
end

-- Katakana is E3 82 A1 – E3 83 BF in UTF-8. A token word touching katakana is part of a longer word (コントロール).
local function katakanaEndingAt(text, i)
  if i < 3 then return false end
  local a, b = text:byte(i - 2), text:byte(i - 1)
  local c = text:byte(i)
  return a == 0xE3 and (b == 0x82 and c >= 0xA1 or b == 0x83)
end

local function katakanaStartingAt(text, i)
  local a, b, c = text:byte(i, i + 2)
  return a == 0xE3 and c ~= nil and (b == 0x82 and c >= 0xA1 or b == 0x83)
end

-- `lookup` passes these to `locate` as guards; `withTokenWords` gives the same spots their card.
function Readings.tokenSpans(text)
  local out = {}
  if type(text) ~= "string" then return out end
  for _, t in ipairs(Readings.tokenWords()) do
    local word, from = t[1], 1
    while true do
      local s, e = text:find(word, from, true)
      if not s then break end
      if not katakanaEndingAt(text, s - 1) and not katakanaStartingAt(text, e + 1) then
        out[#out + 1] = { first = s, last = e }
      end
      from = e + 1
    end
  end
  return out
end

-- `spans` plus a span for every class / race word standing alone in `text`, in text order. `exclude`: a span
-- { first, last } that takes no word (the study card's tested word, whose card would give the answer away).
function Readings.withTokenWords(spans, text, exclude)
  local out = {}
  for i, sp in ipairs(spans or {}) do out[i] = sp end
  if type(text) ~= "string" then return out end
  local added = false
  for _, t in ipairs(Readings.tokenWords()) do
    local word, meaning = t[1], t[2]
    local from = 1
    while true do
      local s, e = text:find(word, from, true)
      if not s then break end
      local kept = exclude and s <= exclude.last and e >= exclude.first
      if not kept and not overlaps(out, s, e) and not katakanaEndingAt(text, s - 1)
          and not katakanaStartingAt(text, e + 1) then
        out[#out + 1] = { first = s, last = e, word = word, reading = word,
          card = { lemma = word, lemmaReading = word, meaning = meaning } }
        added = true
      end
      from = e + 1
    end
  end
  if added then table.sort(out, function(a, b) return a.first < b.first end) end
  return out
end

-- `spans` plus a span for every name in `names`, found in `text` in order (each one after the one before it, so a
-- name said twice gets two spans). A name's span carries `name = true` and the card of a name: its reading and its
-- English name. A listed word that touches a name's span is left out: a word never anchors inside a name. A name
-- the text no longer holds is skipped.
-- The words of a row's list as entries Readings.withNames lays over another line it is written into (a set bonus
-- line holding its spell's description, a duration holding 秒): { ja, reading, lemma, lemmaReading, english (the
-- meaning), word = true }, in the list's order. → list (empty when the row has no words)
function Readings.cards(kind, id)
  local out = {}
  local words = Readings.words(kind, id)
  for i = 1, #(words or {}), 3 do
    local gloss = words[i + 2] and WFJ.Glosses and WFJ.Glosses.get(words[i + 2])
    out[#out + 1] = { ja = words[i], reading = words[i + 1], word = true,
      lemma = gloss and gloss.lemma or nil, lemmaReading = gloss and gloss.lemmaReading or nil,
      english = gloss and gloss.meaning or nil }
  end
  return out
end

function Readings.withNames(spans, text, names)
  local out = {}
  for i, sp in ipairs(spans or {}) do out[i] = sp end
  if type(text) ~= "string" or type(names) ~= "table" or names[1] == nil then return out end
  local found, from = {}, 1
  local function place(n, s, e)
    local reading = type(n.reading) == "string" and n.reading ~= "" and n.reading or n.ja
    -- `word`: a word of another line's list written into this one (Readings.cards), saved like any word; a name's
    -- card is not
    found[#found + 1] = { first = s, last = e, word = n.ja, reading = reading, name = not n.word or nil,
      card = { lemma = n.lemma or n.ja, lemmaReading = n.lemmaReading or reading, meaning = n.english } }
  end
  for _, n in ipairs(names) do
    if type(n) == "table" and type(n.ja) == "string" and n.ja ~= "" then
      if n.afterNumber then
        -- a unit the line's values brought in (秒, 分) stands right after each number it was written with: every such
        -- place takes its card, however many durations the line holds, and none inside another word (自分), which
        -- follows no digit
        local at = 1
        while true do
          local s, e = text:find(n.ja, at, true)
          if not s then break end
          if s > 1 and text:sub(s - 1, s - 1):find("%d") and not overlaps(found, s, e) then place(n, s, e) end
          at = e + 1
        end
      else
        local s, e = text:find(n.ja, from, true)
        if not s then
          -- a card the line's values brought in is listed after the line's own names, wherever it stands: looked
          -- for from the start, never over a card already placed
          s, e = text:find(n.ja, 1, true)
          if s and overlaps(found, s, e) then s = nil end
        end
        if s then
          place(n, s, e)
          if e + 1 > from then from = e + 1 end
        end
      end
    end
  end
  if found[1] == nil then return out end
  local kept = {}
  for _, sp in ipairs(out) do
    if not overlaps(found, sp.first, sp.last) then kept[#kept + 1] = sp end
  end
  for _, sp in ipairs(found) do kept[#kept + 1] = sp end
  table.sort(kept, function(a, b) return a.first < b.first end)
  return kept
end
