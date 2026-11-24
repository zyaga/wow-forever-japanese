-- Core/ChatWords.lua: the words a chat line can show a card for, and where they sit in the line
-- (docs/systems/chat-tools.md). Three layers, looked up in this order: the player's own words (the saved table
-- given to load), the chat list written for chat (Data chatword / chatwordEn), and the general lists generated
-- from the shipped readings (Data chatja / chaten). Pure: no globals, no frames. The display is UI/ChatCards.
--   ChatWords.japaneseAt(text, i) → { first, last, word, reading, gloss } | nil   (gloss: a card table)
--   ChatWords.englishAt(text, i)  → { first, last, word, reading, card } | nil
--   ChatWords.plain(text)         → the line without escape sequences (a link keeps its label)
--   ChatWords.typedPart(text)     → what a player typed, out of a typed chat line | nil
--   ChatWords.runs(text)          → { { first, last }, … }: the stretches drawn as typed
-- `i` is a byte of `text` as FontString:FindCharacterIndexAtCoordinate gives it; the text is a chat line as the
-- chat frame holds it, escape sequences included. A link's label (a player, an item) never takes a card.
local _, WFJ = ...
local ChatWords = {}
WFJ.ChatWords = ChatWords

local MAX_CHARS = 12 -- the longest Japanese word tried, in characters

-- ── The player's own words ────────────────────────────────────────────────────
local own = { ja = {}, en = {} }

-- `saved`: the account's own table, or nil before it exists. → the table now in use (to be saved)
function ChatWords.load(saved)
  if type(saved) ~= "table" then saved = {} end
  if type(saved.ja) ~= "table" then saved.ja = {} end
  if type(saved.en) ~= "table" then saved.en = {} end
  own = saved
  return saved
end

-- Japanese: word, reading, meaning. English: word, its Japanese, that Japanese's reading. → true when kept
function ChatWords.add(lang, word, a, b)
  if type(word) ~= "string" or word == "" or type(a) ~= "string" or a == "" then return false end
  if lang == "en" then
    own.en[word:lower()] = { ja = a, reading = (type(b) == "string" and b ~= "") and b or a }
  else
    own.ja[word] = { reading = a, meaning = type(b) == "string" and b or "" }
  end
  return true
end

-- → true when the word was one of the player's
function ChatWords.remove(word)
  if type(word) ~= "string" then return false end
  local lower = word:lower()
  local had = own.ja[word] ~= nil or own.en[lower] ~= nil
  own.ja[word], own.en[lower] = nil, nil
  return had
end

function ChatWords.own() return own end

-- ── Where a card may sit ───────────────────────────────────────────────────────

-- The stretches of `text` drawn as typed: outside every escape sequence and every link's label. Kept for the
-- lines last asked about: the mouse rests on one line for many looks.
local KEPT = 300
local cached, cachedCount = {}, 0
function ChatWords.runs(text)
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
        if text:sub(i + 2, i + 2) == "n" then -- |cn<colour name>:
          local e = text:find(":", i + 3, true)
          i = (e or n) + 1
        else
          i = i + 10 -- |cAARRGGBB
        end
      elseif c == "H" then -- |H<data>|h<label>|h: the label is skipped too
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
  if cachedCount >= KEPT then cached, cachedCount = {}, 0 end
  cached[text], cachedCount = out, cachedCount + 1
  return out
end

local function runAt(text, i)
  for _, r in ipairs(ChatWords.runs(text)) do
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

-- What a player typed, out of a typed line: everything after the sender's link and the ": " that closes the line's
-- opening words ("[Name] says: ", "[ギルド] [Name]: "). The opening words after the name are short and hold no link
-- of their own. → that text, or nil when the line is not shaped so (it is then copied whole)
local OPENING = 40
function ChatWords.typedPart(text)
  if type(text) ~= "string" then return nil end
  local _, linkEnd = text:find("|HBNplayer:.-|h.-|h")
  if not linkEnd then _, linkEnd = text:find("|Hplayer:.-|h.-|h") end
  if not linkEnd then return nil end
  local colon = text:find(": ", linkEnd + 1, true)
  if not colon or colon - linkEnd > OPENING or text:sub(linkEnd + 1, colon):find("|H", 1, true) then return nil end
  local rest = text:sub(colon + 2)
  return rest ~= "" and rest or nil
end

-- ── Japanese ─────────────────────────────────────────────────────────────────

local function meaningCard(word, reading, n)
  local g = n and WFJ.Glosses and WFJ.Glosses.get(n)
  if g then return g end
  return { lemma = word, lemmaReading = reading, meaning = "" }
end

-- → reading, card for a Japanese word, or nil
local function japanese(word)
  local o = own.ja[word]
  if o then return o.reading, { lemma = word, lemmaReading = o.reading, meaning = o.meaning or "" } end
  local listed = WFJ.Data.chatword[word]
  if type(listed) == "string" then
    local reading, meaning = listed:match("^([^\t]*)\t(.*)$")
    if reading then return reading, { lemma = word, lemmaReading = reading, meaning = meaning } end
  end
  local row = WFJ.Data.chatja[word]
  if type(row) == "string" then
    local reading, n = row:match("^([^=]+)=?(%d*)$")
    if reading then return reading, meaningCard(word, reading, tonumber(n)) end
  end
  return nil
end

-- The endings a verb or an adjective takes in chat, longest first. A run of them right after a listed word that
-- ends in hiragana (a stem: 行き, 食べ, 倒し) is part of that word: 行きませんか is one word with 行き's card. A word
-- that ends in a kanji or katakana takes none (私たち stays 私 and たち).
local ENDINGS = { "ませんでした", "ましょうか", "ませんか", "ましょう", "ている", "ていた", "てます", "ました",
  "ません", "なかった", "たかった", "ください", "ます", "たい", "ない", "てる", "て", "た", "か", "よ", "ね" }

local function isHiragana(text, charStart)
  local a, b, c = text:byte(charStart, charStart + 2)
  if a ~= 0xE3 or not b or not c then return false end
  return (b == 0x81 and c >= 0x81) or (b == 0x82 and c <= 0x9F)
end

-- the byte after the endings that follow a word ending at `last` (the word's last character starts at `lastChar`)
local function withEndings(text, lastChar, last, limit)
  if not isHiragana(text, lastChar) then return last end
  local joined = true
  while joined do
    joined = false
    for _, ending in ipairs(ENDINGS) do
      if last + #ending <= limit and text:sub(last + 1, last + #ending) == ending then
        last, joined = last + #ending, true
        break
      end
    end
  end
  return last
end

-- The Japanese stretch first..last of `text` cut into words: the longest listed word at each place (with its
-- endings), else one character. → { { first, last, word, reading, gloss } … }, unlisted characters left out
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
      local reading, card = japanese(text:sub(s, e))
      if reading then
        local wordEnd = withEndings(text, starts[k + len - 1], e, last)
        out[#out + 1] = { first = s, last = wordEnd, word = text:sub(s, wordEnd), reading = reading, gloss = card }
        taken = len
        while k + taken <= count and starts[k + taken] <= wordEnd do taken = taken + 1 end
        break
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
  -- never start inside a character
  while first <= last and text:byte(first) < 0xC0 do first = first + 1 end
  for _, w in ipairs(segment(text, first, last)) do
    if i >= w.first and i <= w.last then return w end
  end
  return nil
end

-- ── English ──────────────────────────────────────────────────────────────────

local function wordByte(b)
  return b ~= nil and ((b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 39)
end

-- → ja, jaReading, meaning number for a lower-cased English word, or nil
local function english(lower)
  local o = own.en[lower]
  if o then return o.ja, o.reading, nil end
  local listed = WFJ.Data.chatwordEn[lower]
  if type(listed) == "string" then return listed, listed, nil end
  local row = WFJ.Data.chaten[lower]
  if type(row) == "string" then
    local ja, reading, n = row:match("^([^=]+)=([^=]+)=?(%d*)$")
    if ja then return ja, reading, tonumber(n) end
  end
  local common = WFJ.Data.common[lower]
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
  -- a quote mark around the word is not part of it
  while first < last and text:byte(first) == 39 do first = first + 1 end
  while last > first and text:byte(last) == 39 do last = last - 1 end
  if i < first or i > last then return nil end
  local token = text:sub(first, last)
  local lower = token:lower()
  local ja, jaReading, gloss = english(lower)
  if not ja then
    -- a plural or a contraction takes its base word's card (heals → heal, you're → you)
    local base = lower:match("^(%a+)'%a+$") or lower:match("^(%a+)s$")
    if base then ja, jaReading, gloss = english(base) end
  end
  if not ja then return nil end
  return { first = first, last = last, word = token,
    reading = ja == jaReading and ja or (ja .. "（" .. jaReading .. "）"),
    card = { english = true, ja = ja, jaReading = jaReading, gloss = gloss, ipa = WFJ.Data.pron[lower] } }
end
