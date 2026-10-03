-- Core/Align.lua: the runtime alignment gate for `unaligned` entries (ADR-007), the Lua twin of
-- pipeline/wfj/core/align.py. Pure: no globals, no frames; proven by vectors/align_vectors.lua (both suites).
--   Align.names(text, allowlist)          Latin names in reading order (multi-word joins, allowlist, ≥ 3 letters)
--   Align.checkNames(ja, scope, allowlist) → missing names (word-by-word fallback for multi-word names)
--   Align.numbers(text)                   digit runs after full-width folding, digits glued to Latin letters ignored
--   Align.numberWords(text)               English number words as digit strings ("twenty-five" → 25, 20)
--   Align.checkNumbers(ja, scope, extra)  → missing digit runs (multiset)
--   Align.values(scope)                   the live line's number tokens in order (predecessor rule: commas stripped)
--   Align.durations(scope, duration)      the live line's durations in order, each already in Japanese
--   Align.fill(ja, values, durations, icons)  $N<k> → values[k], $D<k> → durations[k], $I<k> → icons[k]
--                                         nil when one has no value
--   Align.textures(text)                  → text without its `|T…|t` icon escapes, { the escapes }
--   Align.fillValues(ja, scope, duration)  → text: $N/$D filled from `scope`, WITHOUT the names and
--                                         numbers gate: a trusted line's text was checked offline, and
--                                         only the values the server fills in come from the live line.
--                                         nil when a placeholder cannot be filled (fail closed); the
--                                         Japanese unchanged when it holds no placeholder at all.
--   Align.splitTail(ja, scope)            a trailing `$T` (name-list tail) → head, { scope, text } | ja, nil
--                                         | nil (a misplaced `$T`)
--   Align.checkVariants(variants, shapes, lines, nameScope, duration)  (ADR-043) → ok, text: the one
--                                         variant of a branch line that passes `check` (and, where the
--                                         variants' shapes differ, has the live line's shape); false when none
--                                         or several do. The Translator's `alignVariants` dependency.
--   Align.check(ja, lines, nameScope, duration)  → ok, text: the Translator's `align` dependency; `nameScope`
--                                         (optional) is extra text names may come from (the tooltip's name line),
--                                         never numbers; `duration` (optional) is UIStrings' duration renderer,
--                                         without which a $D placeholder fails closed
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
  for _, v in ipairs(extra or {}) do have[v] = (have[v] or 0) + 1 end
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
function Align.values(scope)
  local out, last = {}, nil
  for s, tok, e in scope:gmatch("()([%d%.,]+)()") do
    if not isLetter(scope:byte(s - 1)) and not isLetter(scope:byte(e)) then
      local v = tok:gsub(",", ""):gsub("^%.+", ""):gsub("%.+$", "")
      if v ~= "" then
        if last and scope:sub(last.e, s - 1) == " to " then
          out[#out] = out[#out] .. "～" .. v
        else
          out[#out + 1] = v
        end
        last = { e = e }
      end
    end
  end
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

-- → the live line's durations in reading order, each already in Japanese. Never overlapping: a phrase that
-- matched is skipped past, so "1 hr 30 min" is one duration and not also "30 min".
function Align.durations(scope, duration)
  local out = {}
  if type(scope) ~= "string" or type(duration) ~= "function" then return out end
  local i, len = 1, #scope
  while i <= len do
    local s = scope:find("%d", i)
    if not s then break end
    -- a candidate starts only where a number starts, and a number that is not a duration is skipped whole:
    -- "1.5 sec" whose float form is not shipped must not come back as "5 sec"
    local _, numEnd = scope:find("^[%d%.,]+", s)
    local step = numEnd + 1
    if not isLetter(scope:byte(s - 1)) then
      for _, shape in ipairs(DURATION_SHAPES) do
        local cand = scope:match(shape, s)
        if cand then
          local trimmed = cand:gsub(DURATION_TRAIL, "")
          local ja = trimmed ~= "" and duration(trimmed) or nil
          if ja then
            out[#out + 1] = ja
            step = s + #trimmed
            break
          end
        end
      end
    end
    i = step
  end
  return out
end

-- The live line's durations only when the Japanese asks for one: every gated tooltip and filled quest line would
-- otherwise run each number through the UI index.
local function durationsFor(ja, scope, duration)
  if not ja:find("%$D%d") then return {} end
  return Align.durations(scope, duration)
end

-- $N<k> → values[k], $D<k> → durations[k], $I<k> → icons[k] (the k-th inline icon of the live line).
-- → text, used (the values substituted, in order); nil when any placeholder has no value (fail closed). A bare
-- "$N", "$D" or "$I" is left alone.
function Align.fill(ja, values, durations, icons)
  local ok, used = true, {}
  durations = durations or {}
  icons = icons or {}
  local text = ja:gsub("%$([NDI])(%d+)", function(kind, k)
    local v = (kind == "N" and values or kind == "D" and durations or icons)[tonumber(k)]
    if v == nil then ok = false; return "$" .. kind .. k end
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

-- A name-list tail (ADR-033). A Japanese ending in `$T` translates only the head of a description whose
-- English ends in a `$?s<id>[<break>$@spellname<id>][]` chain (Languages, Armor Proficiency): the client prints the
-- head, then one line per spell the player knows, each that spell's NAME in live English. The live lines
-- from the first line break on are copied byte for byte after the Japanese; the head is checked and filled
-- against the live text before that break only.
-- → ja, nil (no `$T`) · head, { scope = the live head, text = the live tail } · nil when `$T` is anywhere but the
-- end, or appears twice (fail closed).
local TAIL = "$T"
function Align.splitTail(ja, scope)
  local at = ja:find(TAIL, 1, true)
  if at == nil then return ja, nil end
  if at ~= #ja - #TAIL + 1 then return nil end
  local brk = scope:find("\r?\n")
  return ja:sub(1, at - 1), { scope = brk and scope:sub(1, brk - 1) or scope, text = brk and scope:sub(brk) or "" }
end

-- $N<k> / $D<k> filled from the live text, with no gate. A quest line is `trusted`: its names and
-- numbers were checked offline against the English, so re-checking them here would reject a good translation
-- over a count the server fills in. Only the placeholders are resolved, and a placeholder that cannot be
-- filled fails closed to English, exactly as in `check`.
function Align.fillValues(ja, scope, duration)
  if type(ja) ~= "string" then return nil end
  if ja:find(TAIL, 1, true) then -- the head filled from the live head, the live tail appended
    if type(scope) ~= "string" then return nil end
    local head, tail = Align.splitTail(ja, scope)
    local text = head and Align.fillValues(head, tail.scope, duration)
    return text and (text .. tail.text) or nil
  end
  if not ja:find("%$[NDI]%d") then return ja end -- nothing to fill: never a failure
  if type(scope) ~= "string" or scope == "" then return nil end
  local plain, icons = Align.textures(scope)
  return (Align.fill(ja, Align.values(plain), durationsFor(ja, plain, duration), icons))
end

-- The Translator's `align` dep: → ok, text. Every name and number of the filled Japanese must occur in the
-- lines about to be replaced; a name may also come from `nameScope` (the tooltip's own name line: "Hearthstoneの
-- 場所に戻ります" names the item), which never supplies numbers or values. Any doubt → false: English stays.
function Align.check(ja, lines, nameScope, duration)
  if type(ja) ~= "string" or type(lines) ~= "table" or #lines == 0 then return false end
  local scope = table.concat(lines, "\n")
  local head, tail = Align.splitTail(ja, scope)
  if head == nil then return false end
  if tail ~= nil then
    local ok, text = Align.check(head, { tail.scope }, nameScope, duration)
    if not ok then return false end
    return true, text .. tail.text
  end
  -- Icon escapes out of the live line before anything is read from it, and out of the filled Japanese
  -- before its names and numbers are checked (an icon path is neither)
  local plain, icons = Align.textures(scope)
  local values = Align.values(plain)
  local text = Align.fill(ja, values, durationsFor(ja, plain, duration), icons)
  if text == nil then return false end
  local checked = Align.textures(text)
  local names = type(nameScope) == "string" and (plain .. "\n" .. nameScope) or plain
  if #Align.checkNames(checked, names) > 0 then return false end
  -- evidence = the line's digit runs ∪ number words ∪ its value tokens with separators stripped ("1,200" → 1200,
  -- so a corpus "1200" matches a rendered "1,200"); glued tokens are not values, so "Mk2" never vouches for a 2
  if #Align.checkNumbers(checked, plain, values) > 0 then return false end
  return true, text
end

-- A SECTIONED line: a heading paragraph, then optional paragraphs the client prints one per thing the player has
-- (the Camp Benefits aura: "Tent: …", "Mana Well: …"). It ships the heading's Japanese with the key of its English,
-- and per paragraph the byte length and key of the words it begins with, its Japanese and its shape. The live
-- text is split at its blank lines: the first paragraph must be the heading, and every other one is found by its
-- opening words and filled from its own values with `check`. A paragraph found by none, or one that does not fit,
-- leaves the whole line English. → ok, text
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
    if #Align.values(plain) .. "/" .. #Align.durations(plain, duration) ~= found.shape then return false end
    local ok, text = Align.check(found.ja, { p }, nameScope, duration)
    if not ok then return false end
    out[#out + 1] = text
  end
  return true, table.concat(out, "\n\n")
end

-- A branch line (`$?<cond>[A][B]`, ADR-043) ships one Japanese per branch combination, each numbered to
-- its own reading order, with its shape "<values>/<durations>": what `values` / `durations` read off a live
-- line showing that combination. The client chose the branch; the addon reads which one from the live line and
-- never evaluates the condition. A variant is a candidate when it passes `check` and, where the variants'
-- shapes differ (that is what tells a line with an extra clause from one without), the live line has its
-- shape. Exactly one candidate (identical texts count once) → true, its filled text; none or several → false,
-- and the tooltip keeps its English. The pipeline refuses to ship a line whose variants could both
-- pass on one of their lines (`align.indistinguishable`).
function Align.checkVariants(variants, shapes, lines, nameScope, duration)
  if type(variants) ~= "table" or #variants == 0 or type(lines) ~= "table" or #lines == 0 then return false end
  local compare = false
  if type(shapes) == "table" then
    for i = 2, #variants do
      if shapes[i] ~= shapes[1] then compare = true; break end
    end
  end
  local live
  if compare then
    local plain = Align.textures(table.concat(lines, "\n"))
    live = #Align.values(plain) .. "/" .. #Align.durations(plain, duration)
  end
  local found, count = nil, 0
  for i, ja in ipairs(variants) do
    if not compare or shapes[i] == live then
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
