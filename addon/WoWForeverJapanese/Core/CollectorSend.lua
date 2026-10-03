-- Core/CollectorSend.lua: packs the collected English a player has not sent yet into one string for one GitHub
-- issue (docs/systems/collector.md, ADR-056). Pure: the client's encoder is an injected dep (Main wires
-- C_EncodingUtil); no frame access (lint-core-gate).
--   CollectorSend.init(deps) · deps = { encode(payload) → string | nil, version() → string }
--   CollectorSend.pack(all) → { mode, count, shipped, text, url, sent }
--     mode: "empty" (nothing to send) · "readonly" (a file from a newer version) · "unavailable" (no encoder:
--           attach the file) · "link" (the string rides in the URL) · "paste" (the URL opens the form, the string is
--           pasted) · "file" (too long to paste: attach the file)
--     text: the string (link and paste modes) · url: what the player opens · sent: { { key, h }, … } for markSent
--     later: in file and unavailable modes, the lines recorded since the file was last saved (not in it yet)
--   CollectorSend.markSent(pack) → the number of entries marked sent
-- The string is PREFIX .. URL-safe Base64 of zlib-compressed JSON { v, a, b, e }: the format version, the addon
-- version, the builds the entries were recorded on, and the entries in the dump's own fields (b indexes this b).
local _, WFJ = ...
local CollectorSend = {}
WFJ.CollectorSend = CollectorSend

CollectorSend.PREFIX = "WFJC1:"
CollectorSend.FORMAT = 1
CollectorSend.ISSUE_URL = WFJ.Collector.ISSUE_URL
-- A longer new-issue link fails: logged out, about 7,000 characters gets a server error and 8,300 a 414
-- (measured against this repository's form); 6,000 leaves room for the browser and the login redirect.
CollectorSend.URL_BUDGET = 6000
-- The issue body holds 65,536 characters; the form's headings and the note take the rest.
CollectorSend.PASTE_BUDGET = 60000

local FIELDS = { "t", "i", "f", "h", "e", "n", "p" }

local deps

function CollectorSend.init(d)
  deps = d
end

-- Every character outside the URL-safe Base64 alphabet as %XX (the prefix's ":" and the padding "=").
function CollectorSend.percentEncode(s)
  return (s:gsub("[^%w%-_]", function(c) return ("%%%02X"):format(c:byte()) end))
end

-- The JSON table for a list from Collector.pending: builds renumbered to the ones these entries use.
function CollectorSend.payload(list, version)
  local builds, index, entries = {}, {}, {}
  for _, item in ipairs(list) do
    local src = item.entry
    local out = {}
    for _, k in ipairs(FIELDS) do out[k] = src[k] end
    local b = WFJ.Collector.buildName(src.b)
    if b then
      if not index[b] then
        builds[#builds + 1] = b
        index[b] = #builds
      end
      out.b = index[b]
    end
    entries[#entries + 1] = out
  end
  return { v = CollectorSend.FORMAT, a = version, b = builds, e = entries }
end

local function encode(payload)
  if not deps or type(deps.encode) ~= "function" then return nil end
  local ok, s = pcall(deps.encode, payload)
  if not ok or type(s) ~= "string" or s == "" then return nil end
  return CollectorSend.PREFIX .. s
end

function CollectorSend.pack(all)
  local list, shipped, shippedList = WFJ.Collector.pending(all)
  local result = { count = #list, shipped = shipped, url = CollectorSend.ISSUE_URL, sent = {}, later = 0 }
  if WFJ.Collector.isReadOnly() then
    result.mode = "readonly" -- a file from a newer version of the addon: this one neither reads nor sends it
    return result
  end
  for i, item in ipairs(list) do result.sent[i] = { key = item.key, h = item.entry.h } end
  -- a line that ships in Japanese now needs no sending: marking it keeps the unsent count honest
  for _, item in ipairs(shippedList) do result.sent[#result.sent + 1] = item end
  if #list == 0 then
    result.mode = "empty"
    return result
  end
  local version = deps and type(deps.version) == "function" and deps.version() or "?"
  local text = encode(CollectorSend.payload(list, tostring(version)))
  if not text then
    result.mode = "unavailable"
  elseif #text <= CollectorSend.URL_BUDGET then
    local link = CollectorSend.ISSUE_URL .. "&dump=" .. CollectorSend.percentEncode(text)
    if #link <= CollectorSend.URL_BUDGET then
      result.mode, result.text, result.url = "link", text, link
      return result
    end
  end
  if text and #text <= CollectorSend.PASTE_BUDGET then
    result.mode, result.text = "paste", text
    return result
  end
  -- "file" (too long to paste) or "unavailable" (no encoder): the player attaches the saved file. The client writes it
  -- only at logout or /reload, so I sent it marks only the lines it held when the addon loaded it; the rest go later.
  result.mode = result.mode or "file"
  local kept = {}
  for i, item in ipairs(result.sent) do
    if WFJ.Collector.onDisk(item.key, item.h) then
      kept[#kept + 1] = item
    elseif i <= #list then
      result.later = result.later + 1
    end
  end
  result.sent = kept
  return result
end

function CollectorSend.markSent(pack)
  if type(pack) ~= "table" or pack.mode == "empty" or pack.mode == "readonly" then return 0 end
  return WFJ.Collector.markSent(pack.sent)
end
