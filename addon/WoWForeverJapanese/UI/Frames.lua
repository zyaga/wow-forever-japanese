-- UI/Frames.lua: a frame's regions and children as lists, bounded. Every walk of a frame's parts goes through here.
-- GetRegions / GetChildren return each part as a separate value, all pushed onto the Lua stack by one call; past the
-- stack's limit (about 8,000 values) the client raises "stack overflow" inside the call, and the whole surface walking
-- it fails. In the client's windows a frame with more than MAX_PARTS of either is a drawing (grid lines, pooled
-- textures), not a frame of labels, so it lists as empty without the call [verified: GetNumRegions / GetNumChildren
-- on Forever, blizzard_apidocumentationgenerated/simpleframeapidocumentation.lua:509, 523]. The call itself is
-- guarded too, for a client or frame without the count.
local _, WFJ = ...
local Frames = {}
WFJ.Frames = Frames

local MAX_PARTS = 1000
Frames.MAX_PARTS = MAX_PARTS

-- Run under pcall: the count, then the list built inside the protected call so an overflow is caught too.
local function list(frame, count, method)
  local getCount = frame[count]
  if type(getCount) == "function" then
    local n = getCount(frame)
    if type(n) == "number" and n > MAX_PARTS then return nil end
  end
  return { frame[method](frame) }
end

local function parts(frame, count, method)
  if type(frame) ~= "table" or type(frame[method]) ~= "function" then return {} end
  local ok, out = pcall(list, frame, count, method)
  return ok and out or {}
end

-- → the frame's regions in the client's order, or {} (no method, too many, or the call raised).
function Frames.regions(frame) return parts(frame, "GetNumRegions", "GetRegions") end

-- → the frame's children in the client's order, or {} (no method, too many, or the call raised).
function Frames.children(frame) return parts(frame, "GetNumChildren", "GetChildren") end
