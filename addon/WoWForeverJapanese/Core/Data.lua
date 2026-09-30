-- Core/Data.lua: the one function generated files call, WFJ.Data.add(type, tbl).
-- Rows are keyed by game id (gossip: by key; book: by the hash of the page's English; ui: by global-string name;
-- objective: by QuestObjective id; area: by quest id; reading: by "<type>:<id>"; gloss: by meaning number) and
-- copied in. The same id from two shards is a generator bug and raises at load. Pure: no globals, no frames.
-- Layout: Core/Const.lua (WFJ.SLOTS), ADR-008.
local _, WFJ = ...
local Data = { quest = {}, item = {}, spell = {}, gossip = {}, book = {}, ui = {}, objective = {}, area = {},
  reading = {}, gloss = {},
  counts = { quest = 0, item = 0, spell = 0, gossip = 0, book = 0, ui = 0, objective = 0, area = 0, reading = 0,
    gloss = 0 } }
WFJ.Data = Data

function Data.add(type_, tbl)
  local t = Data[type_]
  if type(t) ~= "table" or Data.counts[type_] == nil then
    error("Data.add: unknown type " .. tostring(type_), 2)
  end
  local n = 0
  for id, row in pairs(tbl) do
    if t[id] ~= nil then error(("Data.add: duplicate %s id %s"):format(type_, tostring(id)), 2) end
    t[id] = row
    n = n + 1
  end
  Data.counts[type_] = Data.counts[type_] + n
end

function Data.count(type_)
  return Data.counts[type_] or 0
end
