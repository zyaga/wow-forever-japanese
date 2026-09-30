-- UI/Scan.lua: `/wfj debug ui scan` lists the English still showing on the open windows, so a coverage gap
-- is found by one command instead of a screenshot per button. Read-only: walks every visible frame's FontString regions
-- (EnumerateFrames / GetRegions), keeps text with ASCII letters and no multibyte characters that no record of ours has
-- applied, and says for each whether the UI dictionary already knows it (a hook is missing) or not (a key is missing).
-- Names and prose show up too; the list is a triage aid, not an error report.
local _, WFJ = ...
local Scan = {}
WFJ.Scan = Scan

local Compat = WFJ.Compat
local DECLARE = "scan"
Scan.LIMIT = 25

local function ours()
  local set = {}
  for _, bucket in pairs(WFJ.SurfaceState.surfaces()) do
    for _, rec in pairs(bucket) do
      if rec.applied ~= nil then set[rec.fs] = true end
    end
  end
  return set
end

local function english(text)
  return type(text) == "string" and text:find("%a") ~= nil and not text:find("[\128-\255]")
end

-- → { { text, frame name, known } … } sorted by text, and the total number of distinct texts.
function Scan.collect()
  local enumerate = Compat.get(DECLARE, "enumerate")
  if type(enumerate) ~= "function" then return {}, 0 end
  local applied, seen, out = ours(), {}, {}
  local index = WFJ.UIIndex
  local function regionsOf(f) -- a forbidden or odd frame may refuse; the scan skips it
    local ok, list = pcall(function() return { f:GetRegions() } end)
    return ok and list or {}
  end
  local frame = enumerate()
  while frame do
    local forbidden = frame.IsForbidden and frame:IsForbidden() -- any other method on a forbidden frame raises
    if not forbidden and frame.IsVisible and frame:IsVisible() and frame.GetRegions then
      for _, region in ipairs(regionsOf(frame)) do
        if region.GetObjectType and region:GetObjectType() == "FontString" and region:IsVisible()
            and not applied[region] then
          local text = region:GetText()
          if english(text) and not seen[text] then
            seen[text] = true
            local known = index ~= nil and index:match(text) ~= nil
            out[#out + 1] = { text, frame.GetName and frame:GetName() or "?", known }
          end
        end
      end
    end
    frame = enumerate(frame)
  end
  table.sort(out, function(a, b) return a[1] < b[1] end)
  return out, #out
end

function Scan.run(print_)
  local list, n = Scan.collect()
  print_(("WFJ: ui scan: %d English texts on visible frames%s"):format(n, n > Scan.LIMIT and
    (" (first %d)"):format(Scan.LIMIT) or ""))
  for i = 1, math.min(n, Scan.LIMIT) do
    local e = list[i]
    local text = #e[1] > 60 and (e[1]:sub(1, 57) .. "...") or e[1]
    print_(("  %s %q  [%s]"):format(e[3] and "hook?" or "key? ", text, e[2]))
  end
  return n
end

function Scan.init()
  Compat.declare(DECLARE, "enumerate", { "EnumerateFrames" })
end
