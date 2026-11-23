-- Core/Align.lua: the runtime alignment gate for `unaligned` entries (ADR-007), the Lua twin of
-- pipeline/wfj/core/align.py. Pure: no globals, no frames; proven by vectors/align_vectors.lua (both suites).
--   Align.names(text, allowlist)          Latin names in reading order (multi-word joins, allowlist, ≥ 3 letters)
--   Align.checkNames(ja, scope, allowlist) → missing names (word-by-word fallback for multi-word names)
--   Align.numbers(text)                   digit runs after full-width folding, digits glued to Latin letters ignored
--   Align.numberWords(text)               English number words as digit strings ("twenty-five" → 25, 20)
--   Align.checkNumbers(ja, scope, extra)  → missing digit runs (multiset)
--   Align.values(scope, duration, loose)  the live line's number tokens in order (predecessor rule: commas stripped);
--                                         with `duration`, a worded duration ("until canceled") holds its place
--                                         as `false`; `loose` also reads the glued and signed shapes (see `glued`)
--   Align.durations(scope, duration)      the live line's durations in order, each already in Japanese; `worded[k]`
--                                         is set for one the client wrote as words
--   Align.fill(ja, values, durations, icons)  $N<k> → values[k], $D<k> → durations[k], $I<k> → icons[k]
--                                         nil when one has no value, or a worded duration stands where the
--                                         Japanese around its slot cannot take words
--   Align.grantedHead(ja, scope)          the Japanese up to its icon, when the live line ends after that icon,
--                                         and the count of the value slots before the icon
--   Align.textures(text)                  → text without its `|T…|t` icon escapes, { the escapes }
--   Align.fillValues(ja, scope, duration, count)  → text: $N/$D filled from `scope`, WITHOUT the names and
--                                         numbers gate: a trusted line's text was checked offline, and
--                                         only the values the server fills in come from the live line.
--                                         nil when a placeholder cannot be filled (fail closed); the
--                                         Japanese unchanged when it holds no placeholder at all.
--                                         `count` (optional): as for `check`
--   Align.splitTail(ja, scope)            a trailing `$T` (name-list tail) → head, { scope, text } | ja, nil
--                                         | nil (a misplaced `$T`, or a live text with fewer lines than the head)
--   Align.variantKey(scope, duration)     (ADR-064) the key of a live line's wording with its values masked,
--                                         the twin of align.variant_key; nil without Normalize / Hash
--   Align.checkVariants(variants, shapes, lines, nameScope, duration)  (ADR-043) → ok, text: the one
--                                         variant of a branch line that passes `check` (and, where the
--                                         variants' shapes differ, has the live line's shape; and, where the
--                                         slot carries `key`, whose key the live line has); false when none
--                                         or several do. The Translator's `alignVariants` dependency.
--   Align.gate(entry, lines, duration)  → ok, text: what the tooltip shows for a shipped item / spell entry
--                                         against live lines, by the Translator's status rules (UI/Tooltip set
--                                         bonus lines, the Collector's covered check through Main)
--   Align.check(ja, lines, nameScope, duration, count)  → ok, text: the Translator's `align` dependency;
--                                         `nameScope` (optional) is extra text names may come from (the tooltip's
--                                         name line), never numbers; `duration` (optional) is UIStrings' duration
--                                         renderer, a function or { render = function, words = { { en, ja }, … } }
--                                         (the phrases the client prints where a duration belongs), without
--                                         which a $D placeholder fails closed; `count` (optional) is how many
--                                         values the English the Japanese is numbered to prints: a live line
--                                         with more or fewer fails closed
-- Consumers: Main (the Translator's `align` dep; surfaces reach it only through Translator), align_spec.
local _, WFJ = ...
local Align = {}
WFJ.Align = Align

-- Twin of pipeline/allowlist.txt (parity-tested by tests/python/test_align_vectors.py). Lower-case.
Align.ALLOWLIST = {
  health = true, mana = true, stamina = true, spirit = true, intellect = true, agility = true, strength = true,
  armor = true, rage = true, energy = true, npc = true, pvp = true,
  azeroth = true, horde = true, alliance = true, forsaken = true, elune = true,
  neutral = true, friendly = true, honored = true, revered = true, exalted = true,
}
Align.MIN_LEN = 3

local RSQUO = "\226\128\153" -- ’ (U+2019), part of a name run like the ASCII apostrophe

local function isLetter(b) return b and ((b >= 65 and b <= 90) or (b >= 97 and b <= 122)) end
local function isDigit(b) return b and b >= 48 and b <= 57 end

-- Full-width digits ０-９ (EF BC 90..99) → ASCII.
function Align.foldDigits(text)
  return (text:gsub("\239\188([\144-\153])", function(c) return string.char(c:byte() - 144 + 48) end))
end

local function stripPlaceholders(text)
  return (text:gsub("{name}", " "):gsub("{class}", " "):gsub("{race}", " "))
end

-- Name runs: an ASCII letter then ≥ 2 more of letters / ' / ’ / -, counted in code points (’ is one).
-- Returns { {s = byteStart, e = byteEnd, text = run}, … }.
local function runs(text)
  local out, i, n = {}, 1, #text
  while i <= n do
    if isLetter(text:byte(i)) then
      local j, chars = i + 1, 1
      while j <= n do
        local b = text:byte(j)
        if isLetter(b) or b == 39 or b == 45 then
          j = j + 1; chars = chars + 1
        elseif text:sub(j, j + 2) == RSQUO then
          j = j + 3; chars = chars + 1
        else
          break
        end
      end
      if chars >= 3 then out[#out + 1] = { s = i, e = j - 1, text = text:sub(i, j - 1) } end
      i = j
    else
      i = i + 1
    end
  end
  return out
end

local function trimQuotes(s)
  local t = s
  while true do
    local u = t:gsub("^['%-]", ""):gsub("^" .. RSQUO, ""):gsub("['%-]$", ""):gsub(RSQUO .. "$", "")
    if u == t then return t end
    t = u
  end
end

local function nameLen(s)
  local _, extra = s:gsub(RSQUO, "")
  return #s - extra * 2 -- each ’ is 3 bytes, 1 char
end

function Align.names(text, allowlist)
  allowlist = allowlist or Align.ALLOWLIST
  text = stripPlaceholders(text)
  local toks = runs(text)
  local names, seen = {}, {}
  local i = 1
  while i <= #toks do
    local words, e = { toks[i].text }, toks[i].e
    local j = i + 1
    while j <= #toks and toks[j].s == e + 2 and text:sub(e + 1, e + 1) == " " and isLetter(toks[j].text:byte(1))
      and toks[j].text:sub(1, 1):upper() == toks[j].text:sub(1, 1) do
      words[#words + 1] = toks[j].text
      e = toks[j].e
      j = j + 1
    end
    local name = trimQuotes(table.concat(words, " "))
    if nameLen(name) >= Align.MIN_LEN and not allowlist[name:lower()] and not seen[name] then
      names[#names + 1] = name
      seen[name] = true
    end
    i = j
  end
  return names
end

local function present(name, scopeLower)
  return scopeLower:find(name:lower(), 1, true) ~= nil
end

function Align.checkNames(ja, scope, allowlist)
  allowlist = allowlist or Align.ALLOWLIST
  local scopeLower = scope:lower()
  local missing = {}
  for _, name in ipairs(Align.names(ja, allowlist)) do
    if not present(name, scopeLower) then
      local parts = {}
      for w in name:gmatch("%S+") do
        if nameLen(trimQuotes(w)) >= Align.MIN_LEN and not allowlist[w:lower()] then parts[#parts + 1] = w end
      end
      local gaps = {}
      for _, w in ipairs(parts) do
        if not present(w, scopeLower) then gaps[#gaps + 1] = w end
      end
      if #gaps > 0 then missing[#missing + 1] = (#parts == 1) and name or table.concat(gaps, " ") end
    end
  end
  return missing
end

-- Digit runs not glued to a Latin letter on either side (Mk2, N1 are not numbers). → { [run] = count }
function Align.numbers(text)
  text = Align.foldDigits(stripPlaceholders(text))
  local counts = {}
  local i, n = 1, #text
  while i <= n do
    if isDigit(text:byte(i)) then
      local j = i
      while j <= n and isDigit(text:byte(j)) do j = j + 1 end
      if not isLetter(text:byte(i - 1)) and not isLetter(text:byte(j)) then
        local run = text:sub(i, j - 1)
        counts[run] = (counts[run] or 0) + 1
      end
      i = j
    else
      i = i + 1
    end
  end
  return counts
end

local WORDS = {
  zero = 0, one = 1, two = 2, three = 3, four = 4, five = 5, six = 6, seven = 7, eight = 8, nine = 9, ten = 10,
  eleven = 11, twelve = 12, thirteen = 13, fourteen = 14, fifteen = 15, sixteen = 16, seventeen = 17,
  eighteen = 18, nineteen = 19, twenty = 20, thirty = 30, forty = 40, fifty = 50, sixty = 60, seventy = 70,
  eighty = 80, ninety = 90, hundred = 100, thousand = 1000, dozen = 12, single = 1,
}

-- Mirrors align.english_number_words: `\b(word)(?:[- ](word))?\b`, non-overlapping, case-insensitive.
function Align.numberWords(text)
  local out = {}
  local words = {}
  for s, w, e in text:gmatch("()(%a+)()") do
    -- Python's \b: a word glued to a digit ("one2") is not a number word
    if not isDigit(text:byte(s - 1)) and not isDigit(text:byte(e)) then
      words[#words + 1] = { s = s, e = e - 1, w = w:lower() }
    end
  end
  local i = 1
  while i <= #words do
    local a = WORDS[words[i].w]
    if a then
      local nxt = words[i + 1]
      local sep = nxt and text:sub(words[i].e + 1, nxt.s - 1)
      local b = nxt and (sep == "-" or sep == " ") and WORDS[nxt.w] or nil
      if b == nil then
        out[#out + 1] = tostring(a)
        i = i + 1
      else
        if b == 100 or b == 1000 then
          out[#out + 1] = tostring(a * b)
        else
          out[#out + 1] = tostring(a + b)
          out[#out + 1] = tostring(a)
        end
        i = i + 2
      end
    else
      i = i + 1
    end
  end
  return out
end

-- → missing digit runs of `ja` (multiset), against scope digit runs ∪ scope number words ∪ `extra` (a list).
function Align.checkNumbers(ja, scope, extra)
  local want, have = Align.numbers(ja), Align.numbers(scope)
  for _, w in ipairs(Align.numberWords(scope)) do have[w] = (have[w] or 0) + 1 end
  for _, v in ipairs(extra or {}) do
    -- a range ("1350～1650") vouches for each of its ends: the line itself reads "1,350 to 1,650", whose digit
    -- runs are 1, 350, 1 and 650
    -- a worded duration holds a place and vouches for no number; a signed range's ends are read without the sign
    if v then
      for part in (v .. "～"):gmatch("%-?(.-)～") do have[part] = (have[part] or 0) + 1 end
    end
  end
  local missing = {}
  for run, count in pairs(want) do
    for _ = 1, count - (have[run] or 0) do missing[#missing + 1] = run end
  end
  table.sort(missing, function(a, b) if #a ~= #b then return #a < #b end return a < b end)
  return missing
end

-- The live line's number tokens in reading order (the predecessor's rule): `[%d%.,]+`, commas stripped,
-- leading/trailing dots trimmed, empty tokens skipped; a token glued to a Latin letter (Mk2, 18sec) is not a
-- value. "1,200" → "1200", "18.5" → "18.5".
-- A value the client prints as a RANGE ("causes 14 to 22 Fire damage" for Fireball's `$s1`) is
-- one value, filled as "14～22": counted as two it shifted every later `$N`, and the pipeline's
-- `core/align.slots` counts "A to B" as one slot to match.
-- The duration renderer is UIStrings': a function (a number and its unit → Japanese), or a table
-- { render = that function, words = { { en = the client's phrase, ja = its Japanese }, … } }. The words are what
-- the client prints where a duration belongs when it has no number to print: a spell the character does not know
-- shows "Lasts until canceled." for "Lasts $d.".
local function rendererOf(duration)
  if type(duration) == "table" then return duration.render, duration.words end
  return duration, nil
end

-- Every worded duration of `scope` in reading order: { s, e, ja }. The phrase is the client's own string, matched
-- whole and never inside a longer word.
local function wordedSpans(scope, words)
  local out = {}
  if type(words) ~= "table" then return out end
  for _, w in ipairs(words) do
    if type(w.en) == "string" and w.en ~= "" and type(w.ja) == "string" and w.ja ~= "" then
      local at = 1
      while true do
        local s, e = scope:find(w.en, at, true)
        if not s then break end
        if not isLetter(scope:byte(s - 1)) and not isLetter(scope:byte(e + 1)) then
          out[#out + 1] = { s = s, e = e, ja = w.ja }
        end
        at = e + 1
      end
    end
  end
  table.sort(out, function(a, b) return a.s < b.s end)
  return out
end

-- A number glued to a letter is not a value: "Mk2", "Mace2H" and "247x128" are names. A few templates glue a
-- value to a word by mistake ("stun for1.5 sec", "Inflicts140 Nature damage", "79to 118") or write its unit as
-- one letter ("2x damage", "Every 2s"). The LOOSE reading takes those shapes and no other:
--   before the number, an ordinary word of three letters or more, lower-case after its first letter;
--   after it, "x" or "s" alone, or "to" before the second number of a range.
-- It is only ever tried on a line whose strict reading does not have the count its Japanese is numbered to, and
-- kept only when it has exactly that count (`valuesFor`), so a line that reads right today never changes.
local function glued(scope, s, e)
  local before, after = isLetter(scope:byte(s - 1)), isLetter(scope:byte(e))
  if before then
    local word = scope:sub(1, s - 1):match("%a+$")
    if #word < 3 or word:sub(2):find("%u") then return false end
  end
  if after then
    local word = scope:match("^%a+", e)
    local nxt = scope:byte(e + #word)
    if word == "x" or word == "s" then
      if isDigit(nxt) then return false end
    elseif not (word == "to" and scope:find("^ %-?%d", e + 2)) then
      return false
    end
  end
  return true
end

-- Every value token of `scope` in reading order: fn(start, end, token, value, isRange, signed), `isRange` when
-- the token continues the previous value as "A to B". One scanner for `values` and the variant key's mask.
-- `words`: the worded durations to report in their place, as fn(start, end, phrase, false).
-- `loose`: the glued shapes are read too, and a range whose two ends carry a minus sign ("-24 to -21") is one
-- value, reported `signed`.
local function eachValue(scope, fn, words, loose)
  local last, lastSigned = nil, false
  local spans = wordedSpans(scope, words)
  local nextSpan = 1
  local function worded(upTo)
    while spans[nextSpan] and spans[nextSpan].s < upTo do
      local w = spans[nextSpan]
      fn(w.s, w.e + 1, scope:sub(w.s, w.e), false, false)
      last, lastSigned = nil, false
      nextSpan = nextSpan + 1
    end
  end
  for s, tok, e in scope:gmatch("()([%d%.,]+)()") do
    local free = not isLetter(scope:byte(s - 1)) and not isLetter(scope:byte(e))
    if free or (loose and glued(scope, s, e)) then
      local v = tok:gsub(",", ""):gsub("^%.+", ""):gsub("%.+$", "")
      if v ~= "" then
        worded(s)
        local signed = loose and scope:sub(s - 1, s - 1) == "-" and not scope:sub(s - 2, s - 2):find("[%w%-]")
        local gap = last ~= nil and scope:sub(last, s - 1) or nil
        if gap == " to " then
          fn(s, e, tok, v, true, false)
        elseif gap == " to -" and lastSigned and signed then
          fn(s, e, tok, v, true, true)
        else
          fn(s, e, tok, v, false, false)
        end
        last, lastSigned = e, signed or false
      end
    end
  end
  worded(#scope + 1)
end

function Align.values(scope, duration, loose)
  local out = {}
  local _, words = rendererOf(duration)
  eachValue(scope, function(_, _, _, v, isRange, signed)
    if isRange and signed then
      out[#out] = "-" .. out[#out] .. "～-" .. v
    elseif isRange then
      out[#out] = out[#out] .. "～" .. v
    else
      out[#out + 1] = v
    end
  end, words, loose)
  return out
end

-- A duration in a tooltip line is the one value whose UNIT the client chooses: "$d" renders through
-- INT_SPELL_DURATION_SEC / _MIN / _HOURS / _DAYS (and the SPELL_DURATION_* float forms), so 18 may be seconds
-- on one item and minutes on another. `$N<k>` would give the bare number and the Japanese would have to name a
-- unit, which is a guess. So a duration uses `$D<k>` instead and the whole phrase is copied out of the live
-- line. `duration(text)` is UIStrings' renderer (`Index:duration`): it answers only for a real
-- DURATIONS entry and understands one or two of them ("1 hr 30 min"), so a number that is not a duration never
-- matches. Candidates are tried longest first, and a trailing sentence mark is not part of the phrase.
local DURATION_TRAIL = "[%.,;:!%?%)%]\"。、]+$" -- "(30 sec)" / "30 sec;": the mark is not part of the phrase
local DURATION_SHAPES = {
  "^([%d%.,]+%s*[^%s%d]+%s+[%d%.,]+%s*[^%s%d]+)", -- two entries: "1 hr 30 min"
  "^([%d%.,]+%s*[^%s%d]+)",                        -- one entry: "30 sec", "18秒"
}
-- The same in the client's plural code, which the spell API's text keeps ("for 1 |4hour:hrs;."). Its closing ";"
-- is part of the phrase, so these are not trimmed.
local PLURAL_SHAPES = {
  "^([%d%.,]+%s*|4[^;]*;%s+[%d%.,]+%s*|4[^;]*;)", -- "5 |4Hr:Hrs; 30 |4Min:Mins;"
  "^([%d%.,]+%s*|4[^;]*;)",                       -- "1 |4hour:hrs;"
}

-- Every duration phrase of `scope` in reading order: fn(start, length, ja, worded). Never overlapping: a phrase
-- that matched is skipped past, so "1 hr 30 min" is one duration and not also "30 min". A number glued to an
-- ordinary word before it ("stun for1.5 sec") is still a duration: only a real duration string matches, so a name
-- never does.
local function eachDuration(scope, duration, fn)
  local render, words = rendererOf(duration)
  if type(scope) ~= "string" or type(render) ~= "function" then return end
  local found = wordedSpans(scope, words)
  for _, w in ipairs(found) do w.len, w.worded = w.e - w.s + 1, true end
  local i, len = 1, #scope
  while i <= len do
    local s = scope:find("%d", i)
    if not s then break end
    -- a candidate starts only where a number starts, and a number that is not a duration is skipped whole:
    -- "1.5 sec" whose float form is not shipped must not come back as "5 sec"
    local _, numEnd = scope:find("^[%d%.,]+", s)
    local step = numEnd + 1
    if not isLetter(scope:byte(s - 1)) or glued(scope, s, s) then
      local ja, phrase
      for _, shape in ipairs(PLURAL_SHAPES) do
        phrase = scope:match(shape, s)
        ja = phrase and render(phrase) or nil
        if ja then break end
      end
      if not ja then
        for _, shape in ipairs(DURATION_SHAPES) do
          local cand = scope:match(shape, s)
          if cand then
            phrase = cand:gsub(DURATION_TRAIL, "")
            ja = phrase ~= "" and render(phrase) or nil
            if ja then break end
          end
        end
      end
      if ja then
        found[#found + 1] = { s = s, len = #phrase, ja = ja }
        step = s + #phrase
      end
    end
    i = step
  end
  if #found > 1 then table.sort(found, function(a, b) return a.s < b.s end) end
  for _, d in ipairs(found) do fn(d.s, d.len, d.ja, d.worded) end
end

-- → the live line's durations in reading order, each already in Japanese. `worded[k]` is set when the k-th is
-- the client's words and not a number with its unit.
function Align.durations(scope, duration)
  local out = {}
  eachDuration(scope, duration, function(_, _, ja, worded)
    out[#out + 1] = ja
    if worded then
      out.worded = out.worded or {}
      out.worded[#out] = true
    end
  end)
  return out
end

-- The live line's durations only when the Japanese asks for one: every gated tooltip and filled quest line would
-- otherwise run each number through the UI index.
local function durationsFor(ja, scope, duration)
  if not ja:find("%$D%d") then return {} end
  return Align.durations(scope, duration)
end

-- A `$D<k>` slot is written for a number and its unit ("10秒"): `$D1かけて`, `$D1ごとに`. A worded duration
-- ("until canceled") is an adverb, so it reads as Japanese only where the words after the slot allow it:
--   kept as written   `$D1の間`, `$D1持続`, `$D1続く`, `$D1です`, `$D1、`, `$D1スタン`
--   the particle goes `$D1かけて`, `$D1にわたって`, `$D1にわたり` ("over 10 sec" → "until canceled")
-- Any other slot (`$D1ごとに`, `$D1後`, `$D1以内`, `$D1短縮`) has no reading with words in it: nil, and the line
-- stays English. → `ja` with the particles after its worded slots taken out, or nil
local WORDED_KEEP = { "の間", "持続", "続", "です", "、", "スタン" }
local WORDED_DROP = { "かけて", "にわたって", "にわたり" }

local function startsWith(text, at, list)
  for _, p in ipairs(list) do
    if text:sub(at, at + #p - 1) == p then return #p end
  end
  return nil
end

local function wordedSlots(ja, worded)
  local out, at = {}, 1
  for k, e in ja:gmatch("%$D(%d+)()") do
    if worded[tonumber(k)] then
      local drop = startsWith(ja, e, WORDED_DROP)
      if drop then
        out[#out + 1] = ja:sub(at, e - 1)
        at = e + drop
      elseif not startsWith(ja, e, WORDED_KEEP) then
        return nil
      end
    end
  end
  out[#out + 1] = ja:sub(at)
  return table.concat(out)
end

-- $N<k> → values[k], $D<k> → durations[k], $I<k> → icons[k] (the k-th inline icon of the live line).
-- → text, used (the values substituted, in order); nil when any placeholder has no value (fail closed): none in
-- the line, a worded duration asked for as a number, or one in a slot that cannot take words. A bare "$N", "$D"
-- or "$I" is left alone.
function Align.fill(ja, values, durations, icons)
  local ok, used = true, {}
  durations = durations or {}
  icons = icons or {}
  if durations.worded then
    ja = wordedSlots(ja, durations.worded)
    if ja == nil then return nil end
  end
  local text = ja:gsub("%$([NDI])(%d+)", function(kind, k)
    local v = (kind == "N" and values or kind == "D" and durations or icons)[tonumber(k)]
    if not v then ok = false; return "$" .. kind .. k end
    used[#used + 1] = v
    return v
  end)
  if not ok then return nil end
  return text, used
end

-- An inline icon (ADR-043). A template's `$@spellicon<id>` prints the spell's icon as a texture escape
-- (`|T<path>:<size>|t`) in the line [likely, no source yet; the in-game check is in docs/testing/strategy.md].
-- Its path holds digits and Latin words ("inv_misc_food_15"), which are neither values nor names, so every
-- read of a live line takes the escapes out first; the Japanese carries `$I<k>` and gets the k-th escape
-- back, byte for byte. A line with no escape leaves `$I<k>` unfilled and fails closed.
local TEXTURE = "|T[^|]*|t"
local ESCAPED = "\1" -- stands in for an escaped pipe `||`, which prints a `|` and never opens an escape
function Align.textures(text)
  local icons = {}
  local plain = text:gsub("||", ESCAPED):gsub(TEXTURE, function(t) icons[#icons + 1] = t; return " " end)
  return (plain:gsub(ESCAPED, "||")), icons
end

-- A name-list tail (ADR-033, widened by ADR-064). A Japanese ending in `$T` translates only the head of a
-- description whose English ends in a chain of `$?<cond>[<break>$@spellname<id>][]` elements (Languages, Armor
-- Proficiency, the Riding skills, the class "you currently have access to" lists, with an icon before each
-- name): the client prints the head, then one line per spell the player knows, each that spell's NAME in
-- live English. The Japanese head keeps the English head's line breaks, so the live text is cut at the
-- break after as many breaks as the Japanese head has; the lines from there on are copied byte for byte
-- after the Japanese, and the head is checked and filled against the live text before that break only.
-- → ja, nil (no `$T`) · head, { scope = the live head, text = the live tail } · nil when `$T` is anywhere but the
-- end, appears twice, or the live text has fewer line breaks than the head (another layout: fail closed).
-- The guard counts the whole live text: should the client print the head with fewer breaks than the
-- template [unverified; the in-game check is in docs/testing/strategy.md], the list's own breaks could make
-- up the count and the first list line would be read as part of the head. Without English the addon cannot
-- tell the two apart; the lint keeps the Japanese head's breaks equal to the template's (`tail_breaks`).
local TAIL = "$T"
local BREAK = "\r?\n"

local function countBreaks(text)
  local n = 0
  for _ in text:gmatch(BREAK) do n = n + 1 end
  return n
end

-- the start of the k-th line break of `text`, or nil
local function nthBreak(text, k)
  local at, s = 0, nil
  for _ = 1, k do
    local e
    s, e = text:find(BREAK, at + 1)
    if not s then return nil end
    at = e
  end
  return s
end

function Align.splitTail(ja, scope)
  local at = ja:find(TAIL, 1, true)
  if at == nil then return ja, nil end
  if at ~= #ja - #TAIL + 1 then return nil end
  local head = ja:sub(1, at - 1)
  local n = countBreaks(head)
  if countBreaks(scope) < n then return nil end
  local brk = nthBreak(scope, n + 1)
  return head, { scope = brk and scope:sub(1, brk - 1) or scope, text = brk and scope:sub(brk) or "" }
end

-- A Japanese line's `$N<k>` are numbered to the values of the English it was written against. A client whose
-- template has gained or lost a number shows a line where every later value has moved, and the names and
-- numbers gate cannot tell: each number it would fill in is in the live line. So a line that ships the count
-- of its English is shown only while the live line holds exactly as many values. No count: no such check.
local function sameCount(values, count)
  return count == nil or #values == count
end

-- The live line's values for a Japanese numbered to `count` of them, or nil when the line does not hold that
-- many. The strict reading stands whenever it has the count (or there is none to hold it to). Only a line it
-- fails on is read loosely, and that reading is kept only when it has exactly the count. A worded duration
-- takes a value's place only when the Japanese asks for a duration. → values, whether they are the loose reading
local function valuesFor(ja, plain, duration, count)
  local words = ja:find("%$D%d") and duration or nil
  local values = Align.values(plain, words)
  if sameCount(values, count) then return values, false end
  values = Align.values(plain, words, true)
  if #values == count then return values, true end
  return nil
end

-- A GRANTED ABILITY the client left out. "Gain the Wyvern Strike ability:", a blank line, the ability's icon,
-- then the ability's own description: for a character who does not have the ability the client prints the
-- heading and the icon and stops. The Japanese is the heading, `$I1`, a line break and the ability's text.
-- When the live line ends after its one icon and the Japanese has that shape, only the Japanese up to and
-- including `$I1` is shown, checked against the live line like any line. A live line that goes on after the
-- icon is not this case and gets the whole check.
-- A heading may print values of its own ("Heals the target for 450 health over 12 sec and applies Temporal
-- Beacon for 60 sec.", then the beacon's icon). The English prints the heading before the ability's text, so
-- the heading's values are the first of the line and its `$N<k>` / `$D<k>` are numbered from 1 as in the whole
-- Japanese. The live heading must then hold exactly as many values as the heading has slots: one more or one
-- fewer and every slot after it would take another value.
-- → the Japanese head, the count of its value slots (nil when it has none) | nil (not this shape)
local GRANT_ICON = "$I1"
-- How many values a heading prints: its distinct slots, or its highest `$N<k>` when that is more (a number the
-- Japanese writes as a literal, "さらに1%", still takes its place among the line's values; durations are numbered
-- on their own, so only `$N` raises the count). → n | nil when the heading has no slot
local function slotCount(head)
  local seen, n, top = {}, 0, 0
  for slot in head:gmatch("%$[ND]%d+") do
    if not seen[slot] then seen[slot], n = true, n + 1 end
  end
  for k in head:gmatch("%$N(%d+)") do top = math.max(top, tonumber(k)) end
  n = math.max(n, top)
  return n > 0 and n or nil
end

function Align.grantedHead(ja, scope)
  local at = ja:find(GRANT_ICON, 1, true)
  if at == nil then return nil end
  local head, rest = ja:sub(1, at + #GRANT_ICON - 1), ja:sub(at + #GRANT_ICON)
  -- the ability's text starts on its own line, and no other icon comes before this one
  if not rest:find("^\r?\n%s*%S") or head:find("%$I%d") ~= at then return nil end
  local live = scope:gsub("||", ESCAPED .. ESCAPED)
  local s, e = live:find(TEXTURE)
  if s == nil or live:find("%S", e + 1) or not live:sub(1, s - 1):find("%S") then return nil end
  return head, slotCount(head)
end

-- $N<k> / $D<k> filled from the live text, with no gate. A quest line is `trusted`: its names and
-- numbers were checked offline against the English, so re-checking them here would reject a good translation
-- over a count the server fills in. Only the placeholders are resolved, and a placeholder that cannot be
-- filled fails closed to English, exactly as in `check`.
function Align.fillValues(ja, scope, duration, count)
  if type(ja) ~= "string" then return nil end
  if ja:find(TAIL, 1, true) then -- the head filled from the live head, the live tail appended
    if type(scope) ~= "string" then return nil end
    local head, tail = Align.splitTail(ja, scope)
    local text = head and Align.fillValues(head, tail.scope, duration, count)
    return text and (text .. tail.text) or nil
  end
  if not ja:find("%$[NDI]%d") then return ja end -- nothing to fill: never a failure
  if type(scope) ~= "string" or scope == "" then return nil end
  local plain, icons = Align.textures(scope)
  local values = valuesFor(ja, plain, duration, count)
  if values == nil then return nil end
  return (Align.fill(ja, values, durationsFor(ja, plain, duration), icons))
end

-- The Translator's `align` dep: → ok, text. Every name and number of the filled Japanese must occur in the
-- lines about to be replaced; a name may also come from `nameScope` (the tooltip's own name line: "Hearthstoneの
-- 場所に戻ります" names the item), which never supplies numbers or values. Any doubt → false: English stays.
function Align.check(ja, lines, nameScope, duration, count)
  if type(ja) ~= "string" or type(lines) ~= "table" or #lines == 0 then return false end
  local scope = table.concat(lines, "\n")
  local head, tail = Align.splitTail(ja, scope)
  if head == nil then return false end
  if tail ~= nil then -- the count is the head's: the tail prints names
    local ok, text = Align.check(head, { tail.scope }, nameScope, duration, count)
    if not ok then return false end
    return true, text .. tail.text
  end
  -- the count is the whole line's: the head of a granted ability is held to its own names, numbers and count
  local granted, grantedCount = Align.grantedHead(ja, scope)
  if granted ~= nil then return Align.check(granted, lines, nameScope, duration, grantedCount) end
  -- Icon escapes out of the live line before anything is read from it, and out of the filled Japanese
  -- before its names and numbers are checked (an icon path is neither)
  local plain, icons = Align.textures(scope)
  local values, loose = valuesFor(ja, plain, duration, count)
  if values == nil then return false end
  local text = Align.fill(ja, values, durationsFor(ja, plain, duration), icons)
  if text == nil then return false end
  local checked = Align.textures(text)
  local names = type(nameScope) == "string" and (plain .. "\n" .. nameScope) or plain
  if #Align.checkNames(checked, names) > 0 then return false end
  -- evidence = the line's digit runs ∪ number words ∪ its value tokens with separators stripped ("1,200" → 1200,
  -- so a corpus "1200" matches a rendered "1,200"); glued tokens are not values, so "Mk2" never vouches for a 2
  local evidence = values
  if loose then -- a glued value's digits are not among the line's digit runs, which skip a glued number
    evidence = {}
    for _, v in ipairs(values) do
      evidence[#evidence + 1] = v
      for run in (v or ""):gmatch("%d+") do evidence[#evidence + 1] = run end
    end
  end
  if #Align.checkNumbers(checked, plain, evidence) > 0 then return false end
  return true, text
end

-- A SECTIONED line: a heading paragraph, then optional paragraphs the client prints one per thing the player has
-- (the Camp Benefits aura: "Tent: …", "Mana Well: …"). It ships the heading's Japanese with the key of its English,
-- and per paragraph the byte length and key of the words it begins with, its Japanese and its shape. The live
-- text is split at its blank lines: the first paragraph must be the heading, and every other one is found by its
-- opening words and filled from its own values with `check`. A paragraph found by none, or one that does not fit,
-- leaves the whole line English. [verified: in game, the Camp Benefits aura with its Tent paragraph] → ok, text
local function paragraphsOf(text)
  local out = {}
  for p in (text:gsub("\r\n", "\n") .. "\n\n"):gmatch("(.-)\n%s*\n") do
    p = p:gsub("^%s+", ""):gsub("%s+$", "")
    if p ~= "" then out[#out + 1] = p end
  end
  return out
end

function Align.sections(sec, lines, nameScope, duration)
  if type(sec) ~= "table" or type(lines) ~= "table" or #lines == 0 then return false end
  local N, H = WFJ.Normalize, WFJ.Hash
  if not N or not H then return false end
  local paras = paragraphsOf(table.concat(lines, "\n"))
  if #paras == 0 or H.key(N.v1(paras[1])) ~= sec.hkey then return false end
  local out = { sec.head }
  for i = 2, #paras do
    local p, found = paras[i], nil
    for _, s in ipairs(sec) do
      if #p >= s.n and H.key(N.v1(p:sub(1, s.n))) == s.key then found = s; break end
    end
    if not found then return false end
    -- the paragraph shows exactly the values its Japanese is numbered for, no more
    local plain = Align.textures(p)
    if #Align.values(plain, duration) .. "/" .. #Align.durations(plain, duration) ~= found.shape then return false end
    local ok, text = Align.check(found.ja, { p }, nameScope, duration)
    if not ok then return false end
    out[#out + 1] = text
  end
  return true, table.concat(out, "\n\n")
end

-- A VARIANT KEY (ADR-064): the hash of a live line's wording with every value masked, the twin of
-- `align.variant_key` on the English template (parity-tested by the align vectors). Icon escapes out, each
-- duration phrase with its unit one `#` (so the unit the client chose does not matter), then each value token
-- one `#` (a range "14 to 22" is one, as `values` reads it), then normalize_v1 and the hash. A key, never
-- the English, is what a keyed branch line ships per variant.
local function maskDurations(text, duration)
  local out, at = {}, 1
  eachDuration(text, duration, function(s, len)
    out[#out + 1] = text:sub(at, s - 1) .. "#"
    at = s + len
  end)
  out[#out + 1] = text:sub(at)
  return table.concat(out)
end

local function maskValues(text)
  local out, at = {}, 1
  eachValue(text, function(s, e, tok, _, isRange)
    -- a sentence mark around the number is text, not value ("by 5." masks to "by #."); the second number
    -- of a range folds into the first "#" (" to 22" goes), its mark kept
    if isRange then
      out[#out + 1] = tok:match("[%.,]*$")
    else
      out[#out + 1] = text:sub(at, s - 1) .. tok:match("^[%.,]*") .. "#" .. tok:match("[%.,]*$")
    end
    at = e
  end)
  out[#out + 1] = text:sub(at)
  return table.concat(out)
end

-- the key of a live line already stripped of its icon escapes
local function keyOfPlain(plain, duration)
  local N, H = WFJ.Normalize, WFJ.Hash
  if not N or not H then return nil end
  return H.key(N.v1(maskValues(maskDurations(plain, duration))))
end

function Align.variantKey(scope, duration)
  if type(scope) ~= "string" then return nil end
  return keyOfPlain((Align.textures(scope)), duration)
end

-- A branch line (`$?<cond>[A][B]`, ADR-043) ships one Japanese per branch combination, each numbered to
-- its own reading order, with its shape "<values>/<durations>": what `values` / `durations` read off a live
-- line showing that combination. The client chose the branch; the addon reads which one from the live line and
-- never evaluates the condition. A variant is a candidate when it passes `check` and, where the variants'
-- shapes differ (that is what tells a line with an extra clause from one without), the live line has its
-- shape. A line whose variants differ only in their words carries a key per variant (`variants.key`,
-- ADR-064): then a variant is a candidate only when the live line's key (`variantKey`) is its own.
-- Exactly one candidate (identical texts count once) → true, its filled text; none or several → false,
-- and the tooltip keeps its English. The pipeline refuses to ship a line whose variants could both
-- pass on one of their lines (`align.indistinguishable`) and carry no keys.
function Align.checkVariants(variants, shapes, lines, nameScope, duration)
  if type(variants) ~= "table" or #variants == 0 or type(lines) ~= "table" or #lines == 0 then return false end
  local compare = false
  if type(shapes) == "table" then
    for i = 2, #variants do
      if shapes[i] ~= shapes[1] then compare = true; break end
    end
  end
  local keys = type(variants.key) == "table" and variants.key or nil
  local live, liveKey
  if compare or keys then
    local plain = Align.textures(table.concat(lines, "\n"))
    if compare then live = #Align.values(plain, duration) .. "/" .. #Align.durations(plain, duration) end
    if keys then liveKey = keyOfPlain(plain, duration) end
  end
  local found, count = nil, 0
  for i, ja in ipairs(variants) do
    if (not compare or shapes[i] == live) and (not keys or (liveKey ~= nil and keys[i] == liveKey)) then
      local ok, text = Align.check(ja, lines, nameScope, duration)
      if ok and text ~= found then
        found = text
        count = count + 1
      end
    end
  end
  if count ~= 1 then return false end
  return true, found
end

-- What the tooltip shows for a shipped item / spell entry against these live lines, by the Translator's rules for an
-- item or spell: a trusted line is shown ungated with its live values filled in; an unaligned or stale one through
-- the gate; a branch or sectioned line only when unaligned or stale; any other status shows nothing. The tooltip's
-- name line is not offered as a name scope (the callers have none). → ok, text
function Align.gate(entry, lines, duration)
  if type(entry) ~= "table" or type(lines) ~= "table" then return false end
  local status = entry.status
  local gated = status == "u" or status == "s"
  if entry.variants or entry.sections then
    if not gated then return false end
    if entry.variants then return Align.checkVariants(entry.variants, entry.shapes, lines, nil, duration) end
    return Align.sections(entry.sections, lines, nil, duration)
  end
  if type(entry.ja) ~= "string" or entry.ja == "" then return false end
  if status == "." then
    local text = Align.fillValues(entry.ja, table.concat(lines, "\n"), duration, entry.values)
    if text == nil then return false end
    return true, text
  end
  if not gated then return false end
  return Align.check(entry.ja, lines, nil, duration, entry.values)
end
