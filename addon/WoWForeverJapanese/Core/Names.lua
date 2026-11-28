-- Core/Names.lua: the Japanese of a name, the read path over WFJ.Data.name (ADR-078, ADR-082). Pure: no globals,
-- no frames. A name's Japanese is stored under the hash of its English, so the English the client shows is the key.
--   Names.key(english)        → the 16-hex key the pipeline stores the name under (names.name_id)
--   Names.of(english)         → ja, reading | nil
--   Names.item(english)       → ja, reading | nil: the whole name, else an item name and its suffix
--                                ("Bandit Cloak of the Owl": the two names joined as the words of one name are)
--   Names.joined(english)     → ja, reading, first, second | nil: two names the client joined with ": " ("Call to
--                                Arms: Warsong Gulch"), each in its Japanese with the separator kept; only for a
--                                caller whose widget holds such a title
--   Names.inText(ja[, html])  → text, spans: a shown Japanese line with each English name inside it written in
--                                its Japanese; spans = { { first, last, ja, english, reading }, … } are byte positions
--                                in `text`. Markup, a count after a name and a run with no name stay as written;
--                                with `html` the tags of an HTML page stay too.
--   Names.value(text)         → a value the client filled into a line, in Japanese: the name's Japanese when
--                                `text` is a name, a link with only its bracketed label changed when the label
--                                is one, nil for anything else
-- Names.inText is the twin of wfj.core.names.replace_runs (LATIN_RUN, trim_run and the markup it steps over);
-- vectors/name_vectors.lua holds the two together and must stay byte-identical.
local _, WFJ = ...
local Names = {}
WFJ.Names = Names

local JOIN = "・" -- between the words of one name
local APOSTROPHE = "’"

-- English → { ja, reading } | false. Dropped whole when it grows past what a session's game names need: a filled-in
-- value can be any text (a player's name), and those would pile up for as long as the session lasts.
local CACHE_MAX = 8192
local cache, cached = {}, 0

function Names.key(english)
  return WFJ.Hash.key(WFJ.Normalize.v1(english))
end

function Names.of(english)
  if type(english) ~= "string" or english == "" then return nil end
  -- The key is of the normalized text, which has no markup: a coloured name or one beside an icon would be found
  -- and written without its colour or icon. Those go through the callers that keep what is around the name.
  if english:find("[|$]") then return nil end
  local hit = cache[english]
  if hit == nil then
    local row = WFJ.Data.name[Names.key(english)]
    local ja, reading
    if type(row) == "string" then ja, reading = row:match("^([^\t]*)\t(.*)$") end
    hit = ja and ja ~= "" and { ja, reading } or false
    if cached >= CACHE_MAX then cache, cached = {}, 0 end
    cache[english] = hit
    cached = cached + 1
  end
  if not hit then return nil end
  return hit[1], hit[2]
end

-- An item with a suffix ("Bandit Cloak of the Owl") whose whole name has no row: the item's name and the
-- suffix's, joined. → ja, reading | nil
local function suffixed(english)
  -- a suffix is written last, so the split nearest the end is tried first
  local at = #english
  while true do
    local first = english:sub(1, at + 3):match("^.*() of ")
    if not first then return nil end
    local itemJa, itemReading = Names.of(english:sub(1, first - 1))
    local suffixJa, suffixReading = Names.of(english:sub(first + 1))
    if itemJa and suffixJa then
      return itemJa .. JOIN .. suffixJa, itemReading .. JOIN .. suffixReading
    end
    at = first - 1
  end
end

-- A widget's text is asked for twice in one pass (a guard, then the policy layer) and again on every refresh, and
-- a text that is no name is the common answer: the suffix search's answers are kept like the whole names'.
local joined, joinedCount = {}, 0

function Names.item(english)
  local ja, reading = Names.of(english)
  if ja then return ja, reading end
  if type(english) ~= "string" then return nil end
  -- a class or a race the name list has no line for ("Human", "Night Elf"): the word prose uses for it
  local word = WFJ.Placeholders and WFJ.Placeholders.wordFor(english)
  if word then return word, word end
  local hit = joined[english]
  if hit == nil then
    local j, r = suffixed(english)
    hit = j and { j, r } or false
    if joinedCount >= CACHE_MAX then joined, joinedCount = {}, 0 end
    joined[english] = hit
    joinedCount = joinedCount + 1
  end
  if not hit then return nil end
  return hit[1], hit[2]
end

-- A line that is a list of names, each one maybe with a count after it ("Linen Cloth (2), Coarse Thread": a
-- recipe's ingredients): each name in its Japanese, every count as written. A list with a part that is no known
-- name is no list of game names (another addon's line of character names) and stays whole.
-- → the list, its reading | nil
function Names.list(english)
  if type(english) ~= "string" or not english:find(", ", 1, true) then return nil end
  local out, readings = {}, {}
  for part in (english .. ", "):gmatch("(.-), ") do
    local name, count = part:match("^(.-)( %(%d+%))$")
    name, count = name or part, count or ""
    local ja, reading = Names.item(name)
    if not ja then return nil end
    out[#out + 1] = ja .. count
    readings[#readings + 1] = (reading or ja) .. count
  end
  return table.concat(out, ", "), table.concat(readings, ", ")
end

-- What a widget holding only names shows: one name (an item's may carry a suffix), or a list of them.
function Names.shown(english)
  local ja, reading = Names.item(english)
  if ja then return ja, reading end
  return Names.list(english)
end

-- A title the client makes of two names and ": " between them ("Call to Arms: Warsong Gulch", a holiday on the
-- calendar). The name list holds each half and not the pair, so the pair is read as its halves. Both must be whole
-- names of the list: a text with one unknown half is some other text with a colon in it and stays as written. The
-- split nearest the start is tried first.
-- → ja, reading, the first name, the second name | nil
local SEPARATOR = ": "

function Names.joined(english)
  if type(english) ~= "string" then return nil end
  local from = 1
  while true do
    local at = english:find(SEPARATOR, from, true)
    if not at then return nil end
    local first, second = english:sub(1, at - 1), english:sub(at + #SEPARATOR)
    local firstJa, firstReading = Names.of(first)
    local secondJa, secondReading
    if firstJa then secondJa, secondReading = Names.of(second) end
    if secondJa then
      return firstJa .. SEPARATOR .. secondJa, (firstReading or firstJa) .. SEPARATOR .. (secondReading or secondJa),
        first, second
    end
    from = at + 1
  end
end

function Names.value(text)
  if type(text) ~= "string" then return nil end
  -- links: each one's payload and colour stay byte for byte, its label is the name. A label in brackets (an item
  -- link) or bare (a recipe's required tool: LinkUtil.FormatLink writes none), and a line may hold several ("Anvil,
  -- Forge", an unmet one inside a colour code). A label with no Japanese keeps the client's text.
  if text:find("|H", 1, true) then
    local changed = 0
    local out = text:gsub("(|H[^|]*|h%[?)([^|%[%]]+)(%]?|h)", function(open, label, close)
      local ja = Names.item(label)
      if not ja then return nil end
      changed = changed + 1
      return open .. ja .. close
    end)
    return changed > 0 and out or nil
  end
  return (Names.item(text))
end

-- The markup a shown line can hold, in the order the pipeline's pattern tries it. Each is anchored at the scan
-- position; only these four bytes can begin one.
local MARKUP_START = "[{$|%%]"
local MARKUP = {
  "^{[a-z]+}", "^%$%?[^%[]*", "^%$[0-9]*[A-Za-z][0-9]*", "^|[cC]%x%x%x%x%x%x%x%x", "^|cn[A-Z0-9_]+:", "^|[rR]",
  "^|H[^|]*|h", "^|h", "^|T[^|]*|t", "^|n", "^%%[0-9$]*[sd]", "^%%[A-Z][0-9]+",
  -- an interface line's own: an atlas icon, a Battle.net name code, a plural code
  "^|A[^|]*|a", "^|K[^|]*|k", "^|4[^;]*;",
}

-- → the position after the markup that begins at `i`, or nil
local function markupEnd(text, i, html)
  if html and text:byte(i) == 60 then -- "<"
    local _, last = text:find("^<[^>]*>", i)
    return last and last + 1 or nil
  end
  for n = 1, #MARKUP do
    local _, last = text:find(MARKUP[n], i)
    if last then return last + 1 end
  end
  return nil
end

-- The length of the run's word characters at `i`: letters, digits and the punctuation a name carries.
local function wordEnd(text, i)
  while true do
    local b = text:byte(i)
    if b == nil then return i end
    if (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122)
      or b == 39 or b == 46 or b == 38 or b == 45 then
      i = i + 1
    elseif text:sub(i, i + 2) == APOSTROPHE then
      i = i + 3
    else
      return i
    end
  end
end

local function isLetter(b)
  return b ~= nil and ((b >= 65 and b <= 90) or (b >= 97 and b <= 122))
end

local function isAlnum(b)
  return isLetter(b) or (b ~= nil and b >= 48 and b <= 57)
end

-- → first, afterLast of the next run of Latin words at or after `i` (words joined by single spaces), or nil
local function nextRun(text, i, stop)
  local first = i
  while first < stop and not isLetter(text:byte(first)) do first = first + 1 end
  if first >= stop then return nil end
  local e = wordEnd(text, first + 1)
  while text:byte(e) == 32 and isAlnum(text:byte(e + 1)) do e = wordEnd(text, e + 2) end
  if e > stop then e = stop end
  return first, e
end

local function endsWithApostrophe(s, last)
  return last >= 3 and s:sub(last - 2, last) == APOSTROPHE
end

-- The name in a run: a count after it and edge punctuation left out (names.trim_run).
local function trimRun(raw)
  local run, n = raw, 1
  while n > 0 do run, n = run:gsub(" [0-9][0-9.,]*$", "") end
  while true do
    local b = run:byte(#run)
    if b == 46 or b == 39 or b == 45 or b == 38 then
      run = run:sub(1, -2)
    elseif endsWithApostrophe(run, #run) then
      run = run:sub(1, -4)
    else
      break
    end
  end
  run = run:gsub("%s+$", "")
  -- a count written onto the name ("cloth60"): the digits from the first one that follows a lower-case letter,
  -- an apostrophe or a full stop
  local block = #run + 1
  while block > 1 and run:sub(block - 1, block - 1):find("^[0-9.,]") do block = block - 1 end
  for p = block, #run do
    local b = run:byte(p)
    if b >= 48 and b <= 57 and p > 1 then
      local before = run:byte(p - 1)
      if (before >= 97 and before <= 122) or before == 39 or before == 46 or endsWithApostrophe(run, p - 1) then
        return run:sub(1, p - 1)
      end
    end
  end
  return run
end

local function replace(ja, html)
  local out, spans, len = {}, {}, 0
  local function put(s)
    if s ~= "" then
      out[#out + 1] = s
      len = len + #s
    end
  end
  -- the plain text from `i` up to `stop`
  local function plain(i, stop)
    while i < stop do
      local first, e = nextRun(ja, i, stop)
      if not first then break end
      put(ja:sub(i, first - 1))
      local raw = ja:sub(first, e - 1)
      local run = trimRun(raw)
      local name, reading
      if run ~= "" and run:find("[A-Za-z]") then
        name, reading = Names.of(run)
        if not name then name, reading = suffixed(run) end
      end
      if name then
        spans[#spans + 1] = { first = len + 1, last = len + #name, ja = name, english = run, reading = reading }
        put(name)
        put(raw:sub(#run + 1))
      else
        put(raw)
      end
      i = e
    end
    put(ja:sub(i, stop - 1))
  end

  local n, at, i = #ja, 1, 1
  local start = html and "[{$|%%<]" or MARKUP_START
  while true do
    local m = ja:find(start, i)
    if not m then break end
    local after = markupEnd(ja, m, html)
    if after then
      plain(at, m)
      put(ja:sub(m, after - 1))
      at, i = after, after
    else
      i = m + 1
    end
  end
  plain(at, n + 1)
  return table.concat(out), spans
end

-- A line's answer is the same for the whole session, and the policy layer asks again for the same line on every
-- refresh of its window: the last answers are kept. The spans are shared, never changed by a reader.
local TEXT_MAX = 512
local texts, textCount = { [false] = {}, [true] = {} }, 0

function Names.inText(ja, html)
  if type(ja) ~= "string" or not ja:find("[A-Za-z]") then return ja, {} end -- no Latin letter: no name to find
  html = html == true
  local hit = texts[html][ja]
  if not hit then
    if textCount >= TEXT_MAX then texts, textCount = { [false] = {}, [true] = {} }, 0 end
    hit = { replace(ja, html) }
    texts[html][ja] = hit
    textCount = textCount + 1
  end
  return hit[1], hit[2]
end
