-- Core/Reports.lua: the player's pending fixes (docs/systems/fix-reports.md), kept in WFJ_DB.reports so
-- they survive /reload and logout until the player copies the report out and clears them.
-- A fix: { type, id, field, ja_hash, reason, note?, ja? }: the line's store address and the hash of the Japanese
-- the player saw (from Core/RecentLines), one of REASONS, an optional one-line note, and the player's own Japanese
-- when they wrote one. Never any English, never a time, and never the player's name: a report is pasted into a
-- public issue. At most CAP fixes; one per address: a second fix for a line replaces the first only when the
-- caller says so (the window asks the player first).
-- Pure: the caller passes the player's name. Fed by UI/FixWindow; serialized by Core/ReportText.
local _, WFJ = ...
local Reports = {}
WFJ.Reports = Reports

Reports.CAP = 25
Reports.REASONS = { "wrong", "awkward", "typo", "name", "other" }
Reports.NOTE_MAX = 200 -- bytes, before escaping (the report grammar's limits)
Reports.JA_MAX = 8000 -- the longest shipped line is 6,416 bytes

local REASON = {}
for _, r in ipairs(Reports.REASONS) do REASON[r] = true end

local db -- the live WFJ_DB table

local function valid(f)
  return type(f) == "table" and type(f.type) == "string" and f.id ~= nil and type(f.field) == "string"
    and type(f.ja_hash) == "string" and f.ja_hash:match("^%x+$") and #f.ja_hash == 16 and REASON[f.reason]
end

-- Takes the loaded WFJ_DB table (Core/Settings.load's result). A save without `reports` (an older version, or a
-- player who never saved a fix) reads as empty and gains the key only with the first fix; an entry a hand edit broke
-- is dropped rather than reaching a report.
function Reports.load(saved)
  if type(saved) ~= "table" then db = nil; return nil end -- no saved table: nothing can be saved (Save says so)
  db = saved
  if saved.reports == nil then return {} end
  local kept = {}
  if type(saved.reports) == "table" then
    for _, f in ipairs(saved.reports) do
      if valid(f) then
        f.t = nil -- a file saved by a version that stored the time of each fix
        kept[#kept + 1] = f
      end
    end
  end
  saved.reports = kept
  return kept
end

local EMPTY = {}
local function list()
  return db and db.reports or EMPTY
end

function Reports.list()
  return list()
end

function Reports.count()
  return #list()
end

-- → the index of the pending fix for this address, or nil
function Reports.find(type_, id, field)
  for i, f in ipairs(list()) do
    if f.type == type_ and f.id == id and f.field == field then return i end
  end
  return nil
end

local function oneLine(s)
  return type(s) == "string" and not s:find("[\r\n]")
end

local function isLetter(b)
  return b ~= nil and ((b >= 65 and b <= 90) or (b >= 97 and b <= 122))
end

-- Whether `text` holds the player's name as a whole word, in any ASCII letter case.
function Reports.mentions(text, name)
  return Reports.withoutName(text, name) ~= text
end

-- `text` with each whole-word occurrence of the player's name, in any ASCII letter case, written as the {name}
-- placeholder the shipped lines use. Word edges are ASCII letters, so a name inside a longer word stays. The
-- caller passes no name when the line itself carries that word as a game name (a creature called like the
-- player), so a game name is never turned into the placeholder.
function Reports.withoutName(text, name)
  if type(text) ~= "string" or type(name) ~= "string" or name == "" then return text end
  local low, token, out, i = text:lower(), name:lower(), {}, 1
  while true do
    local j = low:find(token, i, true)
    if not j then break end
    local k = j + #token
    local whole = not isLetter(low:byte(j - 1)) and not isLetter(low:byte(k))
    out[#out + 1] = text:sub(i, j - 1) .. (whole and "{name}" or text:sub(j, k - 1))
    i = k
  end
  out[#out + 1] = text:sub(i)
  return table.concat(out)
end

-- Saves a fix. `replace`: the player agreed to overwrite this line's earlier fix. `name`: the player's own
-- name, taken out of the note and the Japanese before they are checked and stored.
-- → true | false, why ("unavailable" · "address" · "reason" · "note" · "ja" · "exists" · "full")
function Reports.save(fix, replace, name)
  if not db then return false, "unavailable" end
  if type(fix) ~= "table" or not (type(fix.type) == "string" and fix.id ~= nil and type(fix.field) == "string"
      and type(fix.ja_hash) == "string") then
    return false, "address"
  end
  if not REASON[fix.reason] then return false, "reason" end
  local note = Reports.withoutName(fix.note, name)
  if note == "" then note = nil end
  if note ~= nil and not (oneLine(note) and #note <= Reports.NOTE_MAX) then return false, "note" end
  local ja = Reports.withoutName(fix.ja, name)
  if ja == "" then ja = nil end
  if ja ~= nil and not (type(ja) == "string" and #ja <= Reports.JA_MAX) then return false, "ja" end
  local entry = { type = fix.type, id = fix.id, field = fix.field, ja_hash = fix.ja_hash, reason = fix.reason,
    note = note, ja = ja }
  if db.reports == nil then db.reports = {} end
  local i = Reports.find(fix.type, fix.id, fix.field)
  if i then
    if not replace then return false, "exists" end
    db.reports[i] = entry
    return true
  end
  if #db.reports >= Reports.CAP then return false, "full" end
  db.reports[#db.reports + 1] = entry
  return true
end

function Reports.delete(i)
  if not (db and db.reports and db.reports[i]) then return false end
  table.remove(db.reports, i)
  return true
end

-- Removes the fixes at these addresses ({ type, id, field }, e.g. the ones a copied report held) and keeps any
-- saved since. → how many were removed
function Reports.clearOnly(addresses)
  if not (db and db.reports) or type(addresses) ~= "table" then return 0 end
  local drop = {}
  for _, a in ipairs(addresses) do drop[a.type .. "\0" .. tostring(a.id) .. "\0" .. a.field] = true end
  local kept, n = {}, 0
  for _, f in ipairs(db.reports) do
    if drop[f.type .. "\0" .. tostring(f.id) .. "\0" .. f.field] then n = n + 1 else kept[#kept + 1] = f end
  end
  db.reports = kept
  return n
end

-- → how many fixes were cleared
function Reports.clear()
  if not (db and db.reports) then return 0 end
  local n = #db.reports
  db.reports = {}
  return n
end
