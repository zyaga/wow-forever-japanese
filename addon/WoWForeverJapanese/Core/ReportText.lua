-- Core/ReportText.lua: the report text, version 1, the one block the player copies into the issue form.
-- The grammar is docs/systems/fix-reports.md; pipeline/wfj/core/fix_report.py reads it, and vectors/report_vectors.lua
-- (make vectors) holds the cases both sides must produce byte for byte. Pure.
local _, WFJ = ...
local ReportText = {}
WFJ.ReportText = ReportText

ReportText.VERSION = 1

-- `\` → `\\`, newline → `\n`, carriage return → `\r`, `|` → `\x7c`: a WoW escape character never reaches the
-- copy box, and no raw CR a browser would turn into a line break (shipped lines hold CRs).
function ReportText.escape(s)
  s = s:gsub("\\", "\\\\")
  s = s:gsub("\n", "\\n")
  s = s:gsub("\r", "\\r")
  s = s:gsub("|", "\\x7c")
  return s
end

-- One short token of [0-9A-Za-z._@?+-] (the grammar's; the pipeline echoes it in the issue comment), at most 40
-- characters; "?" when unknown.
local function token(v)
  if v == nil or v == "" then return "?" end
  local s = tostring(v):gsub("[^%w%._@%?%+%-]", "_"):sub(1, 40)
  return s
end

-- → the report text, every line ending in a newline (the `end` line too)
function ReportText.serialize(addonVersion, build, fixes)
  local out = { "WFJ-REPORT " .. ReportText.VERSION, "addon " .. token(addonVersion) .. " client " .. token(build) }
  for _, f in ipairs(fixes) do
    out[#out + 1] = ("fix %s %s %s %s %s"):format(f.type, tostring(f.id), f.field, f.ja_hash, f.reason)
    if f.note ~= nil and f.note ~= "" then out[#out + 1] = "note " .. ReportText.escape(f.note) end
    if f.ja ~= nil and f.ja ~= "" then out[#out + 1] = "ja " .. ReportText.escape(f.ja) end
  end
  out[#out + 1] = "end " .. #fixes
  return table.concat(out, "\n") .. "\n"
end
