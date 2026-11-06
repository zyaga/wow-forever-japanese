-- Core/Words.lua: the player's saved word list (ADR-069, docs/systems/word-list.md). Pure: no globals, no frames.
-- UI/Readings saves the highlighted word here, UI/WordsWindow shows the export text.
--   Words.load(saved) → the table to keep in WFJ_Words
--   Words.add(input, now) → "added" | "exists" | "refused", entry
--   Words.export(opts, fmt) → tab-separated text with Anki's file headers; fmt(pattern, t) is the client's date()
--   Words.matches / hidden / nextFree: the save-click choices
-- An entry is keyed by its source (the reading row's kind and id) and the word's dictionary form, never by its text,
-- so a reworded translation never adds the same word twice. The key index is rebuilt on load and never saved.
local _, WFJ = ...
local Words = {}
WFJ.Words = Words

Words.SCHEMA = 1
Words.SENTENCE_MAX = 200 -- bytes: a quest paragraph with no full stop stays a readable card

local list -- the saved table
local index = {} -- key → entry
local frozen = false -- saved by a newer version: kept as it is, never written

local function clean(s)
  if s == nil then return "" end
  return (tostring(s):gsub("[\t\r\n]", " "))
end

function Words.load(saved)
  index, frozen = {}, false
  if type(saved) == "table" and type(saved.schema) == "number" and saved.schema > Words.SCHEMA then
    list, frozen = saved, true
    return saved
  end
  local t = { schema = Words.SCHEMA, entries = {} }
  if type(saved) == "table" then
    t.everSaved = saved.everSaved == true or nil
    if type(saved.entries) == "table" then
      for _, e in ipairs(saved.entries) do
        if type(e) == "table" and type(e.key) == "string" and not index[e.key] then
          t.entries[#t.entries + 1] = e
          index[e.key] = e
        end
      end
    end
  end
  list = t
  return t
end

function Words.readonly() return frozen end

function Words.count()
  return list and type(list.entries) == "table" and #list.entries or 0
end

function Words.everSaved() return list ~= nil and list.everSaved == true end

function Words.entries()
  return list and type(list.entries) == "table" and list.entries or {}
end

-- every saved key in order (Core/Study keeps only cards for these)
function Words.keys()
  local out = {}
  for i, e in ipairs(Words.entries()) do out[i] = e.key end
  return out
end

function Words.key(kind, id, lemma, word)
  local head = (lemma ~= nil and lemma ~= "") and lemma or word
  return tostring(kind) .. ":" .. tostring(id) .. ":" .. tostring(head)
end

function Words.isQuestKind(kind)
  return type(kind) == "string" and kind:find("^quest%.") ~= nil
end

-- Where the line was shown, from the surface: a quest-window line keyed by its English (a conditional description,
-- a repeated quest's text) is still quest text. The voice panel and the study card show lines of every kind.
function Words.source(surface, kind)
  if type(surface) == "string" and (surface:find("^questframe") or surface:find("^questmap")) then return "quest" end
  if surface == "gossip" then return "gossip" end
  if surface == "itemtext" then return "book" end
  if surface == "voicepanel" or surface == "study" then
    if Words.isQuestKind(kind) then return "quest" end
    if kind == "book" then return "book" end
    return "gossip"
  end
  return "window"
end

local function lead(text, i) -- i is a character's first byte
  local c = text:byte(i)
  return c == nil or c < 0x80 or c >= 0xC0
end

-- The end of the character that starts at byte i.
local function charEnd(text, i)
  local j = i + 1
  while j <= #text and not lead(text, j) do j = j + 1 end
  return j - 1
end

local ENDS = { ["。"] = true, ["！"] = true, ["？"] = true, ["!"] = true, ["?"] = true }

-- The sentence holding bytes first..last of text, and the word's place inside it. → sentence, wordFirst, wordLast
function Words.sentence(text, first, last)
  local s, e = 1, #text
  local i = 1
  while i <= #text do
    local j = charEnd(text, i)
    local ch = text:sub(i, j)
    if j < first and (ENDS[ch] or ch == "\n") then s = j + 1 end
    if i > last and (ENDS[ch] or ch == "\n") then
      e = ch == "\n" and i - 1 or j
      break
    end
    i = j + 1
  end
  -- too long: keep whole characters around the word, at most SENTENCE_MAX bytes
  while e - s + 1 > Words.SENTENCE_MAX do
    if first - s > e - last then
      s = charEnd(text, s) + 1
    else
      local k = e
      while k > s and not lead(text, k) do k = k - 1 end
      e = k - 1
    end
  end
  return text:sub(s, e), first - s + 1, last - s + 1
end

-- input: { kind, id, surface, text, first, last, word, reading, lemma, lemmaReading, meaning, questTitle }
function Words.add(input, now)
  if frozen or not list then return "refused" end
  if type(input) ~= "table" or type(input.text) ~= "string" or type(input.word) ~= "string"
      or type(input.first) ~= "number" or type(input.last) ~= "number" or input.kind == nil or input.id == nil then
    return "refused"
  end
  local key = Words.key(input.kind, input.id, input.lemma, input.word)
  if index[key] then return "exists", index[key] end
  local sentence, wf, wl = Words.sentence(input.text, input.first, input.last)
  local isQuest = Words.isQuestKind(input.kind)
  local e = {
    key = clean(key), word = clean(input.word), reading = clean(input.reading), lemma = clean(input.lemma),
    lemmaReading = clean(input.lemmaReading), meaning = clean(input.meaning), sentence = clean(sentence),
    wf = wf, wl = wl, kind = input.kind, id = input.id, source = Words.source(input.surface, input.kind),
    questId = isQuest and input.id or nil, questTitle = isQuest and input.questTitle and clean(input.questTitle) or nil,
    saved = now,
  }
  list.entries[#list.entries + 1] = e
  list.everSaved = true
  index[key] = e
  return "added", e
end

function Words.setShot(entry, name)
  if type(entry) == "table" and not frozen then entry.shot = name end
end

-- → the removed entry, or nil
function Words.removeLast()
  if frozen or not list or #list.entries == 0 then return nil end
  local e = table.remove(list.entries)
  index[e.key] = nil
  return e
end

-- → the number cleared, or nil when the list cannot be written
function Words.clear()
  if frozen or not list then return nil end
  local n = #list.entries
  list.entries, index = {}, {}
  return n
end

-- ── Export ──────────────────────────────────────────────────────────────────

local COLUMNS = { "Key", "Word", "Reading", "Dictionary form", "Its reading", "Meaning", "Sentence", "Source",
  "Quest ID", "Quest", "Saved", "Word (furigana)", "Sentence (furigana)" }

-- ── Furigana in Anki's format ───────────────────────────────────────────────
-- Anki draws a reading over the text between the last space (or tag) and `[`: `用心[ようじん]しろ`, and a space
-- before a kanji run that follows other text, which Anki's furigana filter hides. A word's reading is whole, so it is
-- split around the kana the word itself is written with: those appear unchanged in the reading.

-- a hiragana or katakana character (U+3040 to U+30FF: UTF-8 E3 81..83 xx)
local function isKana(text, i)
  local b1, b2 = text:byte(i, i + 1)
  return b1 == 0xE3 and b2 ~= nil and b2 >= 0x81 and b2 <= 0x83
end

-- the word as runs { text, kana = bool }
local function runs(word)
  local out, i = {}, 1
  while i <= #word do
    local j = charEnd(word, i)
    local kana = isKana(word, i)
    local last = out[#out]
    if last and last.kana == kana then last.text = last.text .. word:sub(i, j)
    else out[#out + 1] = { text = word:sub(i, j), kana = kana } end
    i = j + 1
  end
  return out
end

-- Every way the runs fit the reading, up to two (two means it could go more than one way). A kana run must appear
-- as written; a kanji run takes one character or more.
local function fit(rs, reading, r, pos, taken, found)
  if #found >= 2 then return end
  if r > #rs then
    if pos == #reading + 1 then
      local copy = {} -- `taken` has holes at the kana runs, so it is copied by key
      for k, v in pairs(taken) do copy[k] = v end
      found[#found + 1] = copy
    end
    return
  end
  local run = rs[r]
  if run.kana then
    if reading:sub(pos, pos + #run.text - 1) == run.text then fit(rs, reading, r + 1, pos + #run.text, taken, found) end
    return
  end
  local e = pos
  while e <= #reading do
    e = charEnd(reading, e)
    taken[r] = reading:sub(pos, e)
    fit(rs, reading, r + 1, e + 1, taken, found)
    taken[r] = nil
    e = e + 1
  end
end

-- `word` with its reading in Anki's furigana format; kana stays outside the brackets. One bracket over the whole
-- word when the kana cannot be placed, or could be placed two ways.
function Words.furigana(word, reading)
  if type(word) ~= "string" or word == "" then return "" end
  local rs = runs(word)
  local anyKanji = false
  for _, run in ipairs(rs) do if not run.kana then anyKanji = true end end
  if not anyKanji or type(reading) ~= "string" or reading == "" or reading == word then return word end
  local found = {}
  fit(rs, reading, 1, 1, {}, found)
  if #found ~= 1 then return word .. "[" .. reading .. "]" end
  local out = ""
  for r, run in ipairs(rs) do
    if run.kana then
      out = out .. run.text
    else
      out = out .. (out ~= "" and " " or "") .. run.text .. "[" .. found[1][r] .. "]"
    end
  end
  return out
end

-- The entry's sentence with a reading on every word the line's reading list holds (looked up again by the entry's
-- source, so a word saved before this column existed gets it too), and the saved word in bold.
function Words.sentenceFurigana(e)
  local s = type(e.sentence) == "string" and e.sentence or ""
  local spans = {}
  local R = WFJ.Readings
  local lineWords = R and e.kind ~= nil and e.id ~= nil and R.words(e.kind, e.id)
  local wf, wl = e.wf, e.wl
  local own = type(wf) == "number" and type(wl) == "number" and wf >= 1 and wl <= #s and wl >= wf
  if lineWords then
    for _, sp in ipairs(R.locate(lineWords, s)) do
      if not (own and sp.first <= wl and sp.last >= wf) then spans[#spans + 1] = sp end
    end
  end
  if own then spans[#spans + 1] = { first = wf, last = wl, word = s:sub(wf, wl), reading = e.reading, own = true } end
  table.sort(spans, function(a, b) return a.first < b.first end)
  local out, pos = "", 1
  for _, sp in ipairs(spans) do
    if sp.first >= pos then
      out = out .. s:sub(pos, sp.first - 1)
      local f = Words.furigana(sp.word, sp.reading)
      if sp.own then
        f = "<b>" .. f .. "</b>" -- the tag ends the text before it, as a space would
      elseif f:find("[", 1, true) and out ~= "" and not out:find("[ >]$") then
        f = " " .. f
      end
      out = out .. f
      pos = sp.last + 1
    end
  end
  return out .. s:sub(pos)
end

local function bold(e)
  local s = type(e.sentence) == "string" and e.sentence or ""
  local wf, wl = e.wf, e.wl
  if type(wf) ~= "number" or type(wl) ~= "number" or wf < 1 or wl > #s or wl < wf then return s end
  return s:sub(1, wf - 1) .. "<b>" .. s:sub(wf, wl) .. "</b>" .. s:sub(wl + 1)
end

-- opts.images: add the image column. fmt(pattern, t): the client's date().
function Words.export(opts, fmt)
  opts = opts or {}
  local cols = { unpack(COLUMNS) }
  if opts.images then cols[#cols + 1] = "Image" end
  local out = { "#separator:Tab", "#html:true", "#columns:" .. table.concat(cols, "\t") }
  for _, e in ipairs(Words.entries()) do
    -- every field through clean(): a list a newer version wrote may lack any of them
    local row = { clean(e.key), clean(e.word), clean(e.reading), clean(e.lemma), clean(e.lemmaReading),
      clean(e.meaning), clean(bold(e)), clean(e.source), clean(e.questId), clean(e.questTitle),
      type(e.saved) == "number" and fmt("%Y-%m-%d %H:%M", e.saved) or "",
      clean(Words.furigana(e.word, e.reading)), clean(Words.sentenceFurigana(e)) }
    if opts.images then row[#row + 1] = type(e.shot) == "string" and clean('<img src="' .. e.shot .. '">') or "" end
    out[#out + 1] = table.concat(row, "\t")
  end
  return table.concat(out, "\n")
end

local EXT = { jpeg = "jpg", jpg = "jpg", png = "png", tga = "tga" }

-- The client names a screenshot after the local time it was taken; ext is its screenshot format setting.
function Words.shotName(t, ext, fmt)
  local e = EXT[type(ext) == "string" and ext:lower() or ""] or "jpg"
  return fmt("WoWScrnShot_%m%d%y_%H%M%S", t) .. "." .. e
end

-- ── The save click ──────────────────────────────────────────────────────────

local MOVE = { "ctrl", "shift", "meta", "click" }
local FAMILY = { ctrl = "ctrl", lctrl = "ctrl", rctrl = "ctrl", shift = "shift", lshift = "shift", rshift = "shift" }

function Words.matches(choice, ctrl, shift, meta)
  ctrl, shift, meta = ctrl == true, shift == true, meta == true
  if choice == "ctrl" then return ctrl and not shift and not meta end
  if choice == "shift" then return shift and not ctrl and not meta end
  if choice == "meta" then return meta and not ctrl and not shift end
  if choice == "click" then return not ctrl and not shift and not meta end
  return false
end

-- A choice the player is not offered: the reveal key's own modifier (holding it shows English, so no word is
-- highlighted to save), and Cmd off a Mac.
function Words.hidden(choice, revealKey, isMac)
  if choice == "meta" and not isMac then return true end
  return FAMILY[revealKey] ~= nil and FAMILY[revealKey] == choice
end

function Words.nextFree(choice, revealKey, isMac)
  if not Words.hidden(choice, revealKey, isMac) then return choice end
  for _, c in ipairs(MOVE) do
    if not Words.hidden(c, revealKey, isMac) then return c end
  end
  return "click" -- not reached: a plain click is never hidden
end
