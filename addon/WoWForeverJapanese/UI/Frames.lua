-- UI/Frames.lua: a frame's regions and children as lists, bounded. Every walk of a frame's parts goes through here.
-- GetRegions / GetChildren return each part as a separate value, all pushed onto the Lua stack by one call; past the
-- stack's limit (about 8,000 values) the client raises "stack overflow" inside the call, and the whole surface walking
-- it fails. A frame with more than MAX_PARTS of either is a drawing (grid lines, pooled textures), never a frame of
-- labels, so it lists as empty without the call [verified: GetNumRegions / GetNumChildren on Forever,
-- blizzard_apidocumentationgenerated/simpleframeapidocumentation.lua:509, 523]. The call itself is guarded too, for a
-- client or frame without the count.
local _, WFJ = ...
local Frames = {}
WFJ.Frames = Frames

Frames.MAX_PARTS = 1000

local function parts(frame, count, list)
  if type(frame) ~= "table" or type(frame[list]) ~= "function" then return {} end
  if type(frame[count]) == "function" then
    local ok, n = pcall(frame[count], frame)
    if not ok or (type(n) == "number" and n > Frames.MAX_PARTS) then return {} end
  end
  local ok, out = pcall(function() return { frame[list](frame) } end)
  return ok and out or {}
end

-- → the frame's regions in the client's order, or {} (no method, too many, or the call raised).
function Frames.regions(frame) return parts(frame, "GetNumRegions", "GetRegions") end

-- → the frame's children in the client's order, or {} (no method, too many, or the call raised).
function Frames.children(frame) return parts(frame, "GetNumChildren", "GetChildren") end
