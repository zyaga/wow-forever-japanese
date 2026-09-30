-- Core/RecentLines.lua: the lines the addon last wrote on screen (docs/systems/fix-reports.md), what the
-- fix window lists, so a player picks the exact line to report. Memory only, never SavedVariables; at most CAP
-- lines, newest first; a line written again moves to the front instead of repeating.
-- An entry is the line's store address (`type`, `id`, `field` as the pipeline keys it; gossip / book: the English
-- hash the addon keys the line by), plus `ja_hash`, the addon hash of the Japanese as stored (the hash a reading's
-- `ja_hash` uses; never the text after player tokens are filled in), the Japanese itself and the surface's name.
-- Only what the translation store holds as one line is recorded: a branch line (item / spell `$?` variants,
-- ADR-043) has no single stored Japanese and records nothing. Never any English: the addon stores none.
-- `shown` is the text the player saw (a template with its values filled, player tokens expanded), without the inline
-- marker message and colour codes: what the list displays. The report still carries `ja_hash` of the stored line.
-- Lines are grouped (story: quest / NPC / book / objectives; tooltips: item / spell; windows: UI text), and each
-- group keeps its own CAP, so reopening a window full of labels never pushes a quest line out.
-- Order: lines one surface writes within BURST seconds of each other are one burst (a quest window writes its title,
-- then its text, then its objectives). list() gives the newest burst first and each burst in the order it was
-- written: the order the player reads them on screen.
-- Fed by UI/Render (one call after each applied write); read by UI/FixWindow. Pure: reads WFJ.Lookup / WFJ.Hash.
local _, WFJ = ...
local RecentLines = {}
WFJ.RecentLines = RecentLines

RecentLines.CAP = 100

-- Keyed types: one field, looked up by key (Core/Lookup's KEYED).
local KEYED = { gossip = true, book = true }

local lines = {} -- newest first
-- The hash of each stored Japanese, computed once: hashing the full text in Lua on every write is too slow.
-- Bounded: emptied when it passes MEMO_MAX entries.
local memo, memoN = {}, 0
RecentLines.MEMO_MAX = 600
local function hashOf(ja)
  local h = memo[ja]
  if h == nil then
    if memoN >= RecentLines.MEMO_MAX then memo, memoN = {}, 0 end
    h = WFJ.Hash.key(ja)
    memo[ja], memoN = h, memoN + 1
  end
  return h
end
-- One listener, called after every recorded line (UI/FixWindow: redraws an open list). Set by the UI; nil in tests.
RecentLines.onChange = nil
RecentLines.BURST = 1 -- seconds
local seq, burst = 0, 0
local last -- { surface, at } of the previous note

RecentLines.GROUPS = { "story", "tooltips", "windows" }
local GROUP = { quest = "story", gossip = "story", book = "story", objective = "story", area = "story",
  item = "tooltips", spell = "tooltips", ui = "windows" }
function RecentLines.group(type_)
  return GROUP[type_] or "windows"
end

-- The written text as the player read it: the inline marker message (a coloured run ending in |r, then a space or
-- a newline) and every colour code removed.
function RecentLines.clean(text)
  if type(text) ~= "string" then return nil end
  text = text:gsub("^|c%x%x%x%x%x%x%x%x[^|]*|r[ \n]", "")
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  return text
end

-- A Lookup kind ("quest.title", "ui", "gossip", …) → type, field | nil (the same reading as Lookup's slotOf).
function RecentLines.address(kind)
  if type(kind) ~= "string" then return nil end
  if KEYED[kind] then return kind, "text" end
  local type_, field = kind:match("^(%a+)%.(%a+)$")
  if not type_ then type_ = kind end
  local slots = WFJ.SLOTS[type_]
  if not slots then return nil end
  if field == nil then
    if #slots.fields ~= 1 then return nil end
    return type_, slots.fields[1]
  end
  if not slots.index[field] then return nil end
  return type_, field
end

local function same(a, type_, id, field)
  return a.type == type_ and a.id == id and a.field == field
end

-- Records one written line. → the entry, or nil when the line is not one stored translation.
function RecentLines.note(kind, id, surface, shown, at)
  local type_, field = RecentLines.address(kind)
  if not type_ or id == nil then return nil end
  local entry = WFJ.Lookup.get(kind, id)
  if entry == nil or type(entry.ja) ~= "string" or entry.ja == "" then return nil end
  local rec = { type = type_, id = id, field = field, ja_hash = hashOf(entry.ja), ja = entry.ja,
    surface = type(surface) == "string" and surface or nil, shown = RecentLines.clean(shown),
    group = GROUP[type_] or "windows" }
  if not (last and last.surface == surface and at ~= nil and last.at ~= nil and at - last.at <= RecentLines.BURST)
  then burst = burst + 1 end
  last = { surface = surface, at = at }
  seq = seq + 1
  rec.burst, rec.seq = burst, seq
  for i = #lines, 1, -1 do
    if same(lines[i], type_, id, field) then table.remove(lines, i) end
  end
  table.insert(lines, 1, rec)
  local n = 0
  for i = 1, #lines do
    if lines[i] and lines[i].group == rec.group then
      n = n + 1
      if n > RecentLines.CAP then lines[i] = false end
    end
  end
  for i = #lines, 1, -1 do
    if lines[i] == false then table.remove(lines, i) end
  end
  if RecentLines.onChange then RecentLines.onChange() end
  return rec
end

-- → a copy of the list, newest first; `group` ("story" / "tooltips" / "windows") keeps only that group
function RecentLines.list(group)
  local out = {}
  for _, rec in ipairs(lines) do
    if group == nil or group == "all" or rec.group == group then out[#out + 1] = rec end
  end
  table.sort(out, function(a, b)
    if a.burst ~= b.burst then return a.burst > b.burst end
    return a.seq < b.seq
  end)
  return out
end

function RecentLines.clear()
  lines, last = {}, nil
end
