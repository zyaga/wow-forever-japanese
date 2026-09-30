-- Core/Readings.lua: whole-word readings (ADR-036), the read path over WFJ.Data.reading and where each word sits
-- in the text on screen. Pure: no globals, no frames. The display is UI/Readings.lua.
--   Readings.words(kind, id)        → { word, reading, gloss, … } | nil; gloss = meaning number or false
--                                      kind = "quest.<field>" | "gossip" | "ui" | "book"
--   Readings.locate(words, text[, guards])
--                                   → { { first, last, word, reading, gloss }, … }: byte positions, found in order;
--                                      a word the text lacks is skipped; a match on part of a guard span is passed over
--   Readings.lookup(kind, id, text) → locate(words(kind, id), text, tokenSpans(text)) | nil
--   Readings.tokenSpans(text)       → { { first, last }, … }: every class / race word standing alone in `text`
-- Rows (Data/Reading/*.lua): ["<type>:<id>"] = { <field> = "word=reading word=reading=n …" }; "=n" is the word's
-- meaning in Data/Gloss. The pipeline guarantees no " " or "=" inside a word or a reading.
local _, WFJ = ...
local Readings = {}
WFJ.Readings = Readings

local function split(kind)
  if kind == "gossip" then return "gossip", "text" end
  if kind == "ui" then return "ui", "text" end -- ["ui:<KEY>"] (ADR-041)
  if kind == "book" then return "book", "text" end -- ["book:<English hash>"] (ADR-044)
  if type(kind) ~= "string" then return nil end
  local field = kind:match("^quest%.(%a+)$")
  if field then return "quest", field end
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

-- `spans` plus a span for every class / race word standing alone in `text`, in text order.
function Readings.withTokenWords(spans, text)
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
      if not overlaps(out, s, e) and not katakanaEndingAt(text, s - 1) and not katakanaStartingAt(text, e + 1) then
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
