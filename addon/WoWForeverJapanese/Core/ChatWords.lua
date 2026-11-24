-- Core/ChatWords.lua: TRIAL. The words a chat line can show a card for, and where they sit in the line.
-- Three layers, looked up in this order: the player's own words (saved variable WFJ_ChatWords), the chat list
-- written for this trial (Data/Chat/ChatSlang.lua), and the general lists built from the shipped readings
-- (Data/Chat/ChatJa_*.lua, ChatEn_*.lua). Pure: no frames.
--   ChatWords.japaneseAt(text, i) → { first, last, word, reading, gloss } | nil   (gloss: a card table)
--   ChatWords.englishAt(text, i)  → { first, last, word, reading, card } | nil
--   ChatWords.plain(text)         → the line without escape sequences (a link keeps its label)
-- `i` is a byte of `text` as FontString:FindCharacterIndexAtCoordinate returns it; the text is a chat line as the
-- chat frame holds it, escape sequences included. A link's label (a player, an item) never takes a card.
local _, WFJ = ...
local ChatWords = {}
WFJ.ChatWords = ChatWords
WFJ.ChatData = { ja = {}, en = {}, slangJa = {}, slangEn = {}, phrases = {} }

local MAX_CHARS = 12 -- the longest Japanese word tried, in characters

-- ── The player's own words ────────────────────────────────────────────────────
local own = { ja = {}, en = {} }

function ChatWords.load(saved)
  if type(saved) ~= "table" then saved = {} end
  if type(saved.ja) ~= "table" then saved.ja = {} end
  if type(saved.en) ~= "table" then saved.en = {} end
  own = saved
  return saved
end

-- Japanese: word, reading, meaning. English: word, Japanese, reading of the Japanese.
function ChatWords.add(lang, word, a, b)
  if type(word) ~= "string" or word == "" or type(a) ~= "string" or a == "" then return false end
  if lang == "en" then
    own.en[word:lower()] = { ja = a, reading = (b and b ~= "") and b or a }
  else
    own.ja[word] = { reading = a, meaning = b or "" }
  end
  return true
end

function ChatWords.remove(word)
  local had = own.ja[word] ~= nil or own.en[word:lower()] ~= nil
  own.ja[word], own.en[word:lower()] = nil, nil
  return had
end

function ChatWords.own() return own end

-- ── Where a card may sit ───────────────────────────────────────────────────────

-- The stretches of `text` that are drawn as typed: outside every escape sequence and every link label.
-- → { { first, last }, … }
local runsOf = setmetatable({}, { __mode = "k" })
local cached, cachedCount = {}, 0
local function runs(text)
  local hit = cached[text]
  if hit then return hit end
  local out, i, n, start = {}, 1, #text, nil
  local function close(at)
    if start and at >= start then out[#out + 1] = { first = start, last = at } end
    start = nil
  end
  while i <= n do
    if text:byte(i) == 124 then -- "|"
      close(i - 1)
      local c = text:sub(i + 1, i + 1)
      if c == "c" then
        if text:sub(i + 2, i + 2) == "n" then
          local e = text:find(":", i + 3, true)
          i = (e or n) + 1
        else
          i = i + 10
        end
      elseif c == "H" then
        local dataEnd = text:find("|h", i + 2, true)
        local labelEnd = dataEnd and text:find("|h", dataEnd + 2, true)
        i = (labelEnd and labelEnd + 2) or (dataEnd and dataEnd + 2) or (n + 1)
      elseif c == "T" or c == "A" or c == "K" then
        local e = text:find("|" .. c:lower(), i + 2, true)
        i = (e and e + 2) or (n + 1)
      else
        i = i + 2
      end
    else
      start = start or i
      i = i + 1
    end
  end
  close(n)
  if cachedCount > 300 then cached, cachedCount = {}, 0 end
  cached[text], cachedCount = out, cachedCount + 1
  return out
end
ChatWords.runs = runs
runsOf = nil

local function runAt(text, i)
  for _, r in ipairs(runs(text)) do
    if i >= r.first and i <= r.last then return r end
  end
  return nil
end

function ChatWords.plain(text)
  if type(text) ~= "string" then return "" end
  local s = text
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:]*:", ""):gsub("|r", "")
  s = s:gsub("|H.-|h(.-)|h", "%1")
  s = s:gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|K.-|k", "")
  s = s:gsub("|n", "\n"):gsub("||", "|")
  return s
end

-- ── Japanese ─────────────────────────────────────────────────────────────────

local function glossCard(word, reading, n)
  local g = n and WFJ.Glosses and WFJ.Glosses.get(tonumber(n))
  if g then return g end
  return { lemma = word, lemmaReading = reading, meaning = "" }
end

-- → reading, card for a Japanese word, or nil
local function japanese(word)
  local o = own.ja[word]
  if o then return o.reading, { lemma = word, lemmaReading = o.reading, meaning = o.meaning or "" } end
  local s = WFJ.ChatData.slangJa[word]
  if s then
    local reading, meaning = s:match("^([^=]*)=(.*)$")
    return reading, { lemma = word, lemmaReading = reading, meaning = meaning }
  end
  local row = WFJ.ChatData.ja[word]
  if row then
    local reading, n = row:match("^([^=]+)=?(%d*)$")
    if reading then return reading, glossCard(word, reading, n ~= "" and n or nil) end
  end
  return nil
end

-- The Japanese stretch of `text` around byte `i` (bytes 0x80 and up), cut into words: the longest listed word at
-- each place, else one character. → { { first, last, word, reading, gloss } … } (unlisted characters left out)
local function segment(text, first, last)
  local starts, i = {}, first
  while i <= last do
    local c = text:byte(i)
    starts[#starts + 1] = i
    i = i + ((c >= 0xF0 and 4) or (c >= 0xE0 and 3) or (c >= 0xC0 and 2) or 1)
  end
  starts[#starts + 1] = last + 1
  local out, k, count = {}, 1, #starts - 1
  while k <= count do
    local taken = 1
    for len = math.min(MAX_CHARS, count - k + 1), 1, -1 do
      local s, e = starts[k], starts[k + len] - 1
      if e <= last then
        local word = text:sub(s, e)
        local reading, card = japanese(word)
        if reading then
          out[#out + 1] = { first = s, last = e, word = word, reading = reading, gloss = card }
          taken = len
          break
        end
      end
    end
    k = k + taken
  end
  return out
end

function ChatWords.japaneseAt(text, i)
  if type(text) ~= "string" or type(i) ~= "number" then return nil end
  local b = text:byte(i)
  if not b or b < 0x80 then return nil end
  local r = runAt(text, i)
  if not r then return nil end
  local first, last = i, i
  while first > r.first and text:byte(first - 1) >= 0x80 do first = first - 1 end
  while last < r.last and text:byte(last + 1) >= 0x80 do last = last + 1 end
  -- never start or end inside a character
  while first <= last and text:byte(first) < 0xC0 do first = first + 1 end
  for _, w in ipairs(segment(text, first, last)) do
    if i >= w.first and i <= w.last then return w end
  end
  return nil
end

-- ── English ──────────────────────────────────────────────────────────────────

local function wordByte(b)
  return b and ((b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 39)
end

-- → ja, jaReading, gloss number for a lower-cased English word, or nil
local function english(lower)
  local o = own.en[lower]
  if o then return o.ja, o.reading, nil end
  local s = WFJ.ChatData.slangEn[lower]
  if s then return s, s, nil end
  local row = WFJ.ChatData.en[lower]
  if row then
    local ja, reading, n = row:match("^([^=]+)=([^=]+)=?(%d*)$")
    if ja then return ja, reading, tonumber(n) end
  end
  local common = WFJ.Data and WFJ.Data.common and WFJ.Data.common[lower]
  if type(common) == "string" then return common:match("^([^=]+)=([^=]+)$") end
  return nil
end

function ChatWords.englishAt(text, i)
  if type(text) ~= "string" or type(i) ~= "number" or not wordByte(text:byte(i)) then return nil end
  local r = runAt(text, i)
  if not r then return nil end
  local first, last = i, i
  while first > r.first and wordByte(text:byte(first - 1)) do first = first - 1 end
  while last < r.last and wordByte(text:byte(last + 1)) do last = last + 1 end
  while first < last and text:byte(first) == 39 do first = first + 1 end
  while last > first and text:byte(last) == 39 do last = last - 1 end
  local token = text:sub(first, last)
  local lower = token:lower()
  local ja, jaReading, gloss = english(lower)
  if not ja then
    -- a plural or a contraction takes its base word's card
    local base = lower:match("^(%a+)'%a+$") or lower:match("^(%a+)s$")
    if base then ja, jaReading, gloss = english(base) end
  end
  if not ja then return nil end
  local ipa = WFJ.Data and WFJ.Data.pron and WFJ.Data.pron[lower] or nil
  return { first = first, last = last, word = token,
    reading = ja == jaReading and ja or (ja .. "（" .. jaReading .. "）"),
    card = { english = true, ja = ja, jaReading = jaReading, gloss = gloss, ipa = ipa } }
end
