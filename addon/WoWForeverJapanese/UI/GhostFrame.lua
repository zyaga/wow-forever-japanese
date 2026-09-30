-- UI/GhostFrame.lua: the "Return to Graveyard" button a ghost sees on Forever (surface "ghostframe", area "ui",
-- ADR-016). Blizzard_FrameXML loads ghostframe.lua|xml on camelot: GhostFrame is a button under UIParent,
-- shown by SetGhostFrameShown (ghostframe.lua:3–5) from the death / resurrect handlers
-- (blizzard_game/camelot/eventimplementation.lua:54 `SetGhostFrameShown(CanPortGraveyard() and UnitIsGhost(…))`).
-- Its one label is static XML text: GhostFrameContentsFrameText text="RETURN_TO_GRAVEYARD" (ghostframe.xml:13), never
-- rewritten in Lua, so it is shown on OnShow and once at init. Nothing else on the button is text.
local _, WFJ = ...
local GhostFrame = {}
WFJ.GhostFrame = GhostFrame

local SURFACE = "ghostframe"
GhostFrame.SURFACE = SURFACE
local Compat = WFJ.Compat

GhostFrame.NEVER_TOUCH = {}

local CANDIDATES = { frame = { "GhostFrame" }, text = { "GhostFrameContentsFrameText" } }
local TEXT = { only = { "RETURN_TO_GRAVEYARD" } }

-- HookScript target (GhostFrame OnShow). → 1 | 0
function GhostFrame.onShow()
  return WFJ.Labels.showAll(SURFACE, { { "text", Compat.get(SURFACE, "text"), TEXT } })
end

local hooked = false

-- Called by Main after Compat.init.
function GhostFrame.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  if hooked then return false end
  local frame = Compat.get(SURFACE, "frame")
  if type(frame) ~= "table" or type(Compat.get(SURFACE, "text")) ~= "table" then return false end
  hooked = true
  if type(frame.HookScript) == "function" then frame:HookScript("OnShow", GhostFrame.onShow) end
  GhostFrame.onShow()
  return true
end
