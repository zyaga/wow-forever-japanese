-- Core/Objectives.lua: a quest objective's own server text on its live line (ADR-031). Pure: every dependency
-- is injected, no global is read.
-- The shipped rows (WFJ.Data.objective: QuestObjective id → { ja, h1, status }) are keyed by game id, but the
-- client gives no objective id where the line is written: the tracker, the quest list and the map details see a quest
-- id, a position and the text ("0/1 Archive Burned"). So the row is found the way UIStrings finds an item subclass,
-- by the fingerprint of the English: the live line's count is set aside, the rest is hashed, and the row whose h1
-- equals it is the objective. Two objectives with one English and different Japanese are ambiguous and never shown
-- (validate refuses shipping them). The count is put back where the client wrote it, verbatim.
-- A quest's area text (WFJ.Data.area: quest id → the same row shape) is an objective line too, so the index
-- is built from several sources: an entry is its type and id (the two types' ids may be equal), and one fingerprint
-- with different Japanese across the sources is ambiguous the same way.
--   Objectives.build{ sources = { { type, rows }, … }, hash(text) → h1 } → index
--   Objectives.build{ rows, hash }   one source of type "objective"
--   index:match(text) → id, { form = "affix", before, after }, type | nil     (UIStrings' `affix` fill form)
--   index.counts      { shipped, indexed, ambiguous, byType = { <type> = shipped } }
local _, WFJ = ...
local Objectives = {}
WFJ.Objectives = Objectives

local Index = {}
Index.__index = Index

-- The count the client writes around an objective's text: "3/10 " before it (Forever's QUEST_*_KILLED order) or
-- ": 3/10" after it (the older order, still handled). A count with thousands separators ("0/1,200 …",
-- the 1,200-ticket turn-ins) is split the same way and kept as written. → before, text, after
local function split(text)
  local count, rest = text:match("^(%d[%d,]*/%d[%d,]* )(.+)$")
  if count then return count, rest, "" end
  local head, tail = text:match("^(.-)(: %d[%d,]*/%d[%d,]*)$")
  if head and head ~= "" then return "", head, tail end
  return "", text, ""
end
Objectives.split = split

function Index:match(text)
  if type(text) ~= "string" or text == "" then return nil end
  local before, core, after = split(text)
  local e = self.byH1[self.hash(core)]
  if not e then return nil end
  return e.id, { form = "affix", before = before, after = after }, e.type
end

-- One source's ids, sorted (deterministic: the first row seen for a fingerprint is the one indexed).
local function sortedIds(rows)
  local ids = {}
  for id in pairs(rows or {}) do ids[#ids + 1] = id end
  table.sort(ids)
  return ids
end

function Objectives.build(deps)
  local index = setmetatable({ byH1 = {}, hash = deps.hash,
    counts = { shipped = 0, indexed = 0, ambiguous = 0, byType = {} } }, Index)
  local sources = deps.sources or { { type = "objective", rows = deps.rows } }
  local seen, conflict = {}, {}
  for _, source in ipairs(sources) do
    local type_ = source.type
    index.counts.byType[type_] = index.counts.byType[type_] or 0
    for _, id in ipairs(sortedIds(source.rows)) do
      local row = source.rows[id]
      local ja, h1 = row[1], row[2]
      if type(ja) == "string" and ja ~= "" and type(h1) == "number" then
        index.counts.shipped = index.counts.shipped + 1
        index.counts.byType[type_] = index.counts.byType[type_] + 1
        local e = seen[h1]
        if not e then
          seen[h1] = { id = id, type = type_, ja = ja, n = 1 }
        else
          e.n = e.n + 1
          if e.ja ~= ja then conflict[h1] = true end
        end
      end
    end
  end
  for h1, e in pairs(seen) do
    if conflict[h1] then
      index.counts.ambiguous = index.counts.ambiguous + e.n
    else
      index.byH1[h1] = { id = e.id, type = e.type }
      index.counts.indexed = index.counts.indexed + e.n
    end
  end
  return index
end
