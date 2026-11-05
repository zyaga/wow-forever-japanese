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

function Words.entries() return list and list.entries or {} end

function Words.key(kind, id, lemma, word)
  local head = (lemma ~= nil and lemma ~= "") and lemma or word
  return tostring(kind) .. ":" .. tostring(id) .. ":" .. tostring(head)
end

-- Where the line was shown, from the surface: a quest-window line keyed by its English (a conditional description,
-- a repeated quest's text) is still quest text. The voice panel shows lines of every kind.
function Words.source(surface, kind)
  if type(surface) == "string" and (surface:find("^questframe") or surface:find("^questmap")) then return "quest" end
  if surface == "gossip" then return "gossip" end
  if surface == "itemtext" then return "book" end
  if surface == "voicepanel" then
    if type(kind) == "string" and kind:find("^quest%.") then return "quest" end
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
  local isQuest = type(input.kind) == "string" and input.kind:find("^quest%.") ~= nil
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
  "Quest ID", "Quest", "Saved" }

local function bold(e)
  local s = e.sentence or ""
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
      type(e.saved) == "number" and fmt("%Y-%m-%d %H:%M", e.saved) or "" }
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

Words.CHOICES = { "ctrl", "shift", "meta", "click", "off" }
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
  return "click"
end
