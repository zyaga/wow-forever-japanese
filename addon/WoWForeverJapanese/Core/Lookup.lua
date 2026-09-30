-- Core/Lookup.lua: the only read path over WFJ.Data. Consumers: Main (Translator's `lookup` dep,
-- through which every surface reads), UI/Slash (`/wfj debug quest|item|spell|gossip`), UI/Options (header counts
-- via Data.meta). Pure: no globals, no frames.
--   Lookup.get(kind, id)  → { ja, status, h1[, h1f] } | { variants, shapes, status, h1 } | nil
--                            kind = "<type>.<field>" (a one-field type may be bare: "ui")
--                                                        | a keyed type (id = the key → Lookup.keyed)
--                                         h1f: quest only, the h1 of the English's female variant (ADR-024)
--                                         variants / shapes (ADR-043): a branch line's slot is a table
--                                         { "<variant 1>", …, shape = { "<values>/<durations>", … } } (item /
--                                         spell only); `ja` is nil and the Translator picks with
--                                         Align.checkVariants
--   Lookup.keyed(type_, key) → { ja, status } | nil
--                                         type_ = "gossip" | "book"
--   Lookup.gossip(key)    → Lookup.keyed("gossip", key)
-- Consumers of Lookup.get: Main (Translator + Collector `lookup` deps), UI/Slash (debug verbs),
-- UI/Tooltip (nil and status checks only).
-- `status` is the one-char code Translator reads ("." trusted · "s" stale · "u" unaligned); an unshipped slot
-- ("m") is nil: a missing translation leaves the live English untouched.
local _, WFJ = ...
local Lookup = {}
WFJ.Lookup = Lookup

-- Keyed by a 16-hex English hash, rows { ja, status } (ADR-005; book: the page's English, ADR-022).
local KEYED = { gossip = true, book = true }

local function slotOf(kind)
  if type(kind) ~= "string" then return nil end
  local type_, field = kind:match("^(%a+)%.(%a+)$")
  if not type_ then type_ = kind end
  local slots = WFJ.SLOTS[type_]
  if not slots then return nil end
  if field == nil then
    if #slots.fields ~= 1 then return nil end
    return type_, slots, 1
  end
  local i = slots.index[field]
  if not i then return nil end
  return type_, slots, i
end

function Lookup.get(kind, id)
  if KEYED[kind] then return Lookup.keyed(kind, id) end -- keyed by fingerprint, no slot map (ADR-005)
  local type_, slots, i = slotOf(kind)
  if not type_ then return nil end
  local row = WFJ.Data[type_][id]
  if not row then return nil end
  local ja = row[i]
  if ja == nil then return nil end
  local entry = { status = row[slots.status]:sub(i, i), h1 = row[i + slots.hash],
    h1f = slots.female and row[i + slots.female] or nil }
  if type(ja) == "table" then
    entry.variants, entry.shapes = ja, ja.shape
  else
    entry.ja = ja
  end
  return entry
end

function Lookup.keyed(type_, key)
  if not KEYED[type_] or key == nil then return nil end
  local row = WFJ.Data[type_][key]
  if not row then return nil end
  return { ja = row[1], status = row[2] }
end

function Lookup.gossip(key)
  return Lookup.keyed("gossip", key)
end
