-- UI/ScriptErrors.lua: the Lua error window on Forever (surface "scripterrors", area "ui", ADR-016).
-- ScriptErrorsFrame is built at login (blizzard_scripterrorsframe/blizzard_scripterrorsframe.xml:4–90) and shown to
-- the player whenever a script error or warning is displayed and the "scriptErrors" setting allows it
-- (blizzard_scripterrorsframe.lua:130), so it is a player-visible window, not only a developer tool.
-- Static (XML text=): Reload RELOADUI (xml:46), CloseButton CLOSE (xml:75).
-- Dynamic: ScriptErrorsFrame:DisplayMessageInternal (the frame's own method, lua:88–93; every caller is
--   `self:DisplayMessageInternal(…)`, lua:44, 50, 85) → Title: LUA_ERROR or LUA_WARNING.
-- Never touched: the message itself (ScrollFrame.Text is an EditBox holding the error, its stack and locals:
-- text the player copies into a bug report, lua:192–209) and IndexLabel ("1 / 3", lua:238).
-- The frame's OnShow and error paths run inside the client's error handling, so every step here is type-checked and
-- nothing is called that could raise.
local _, WFJ = ...
local ScriptErrors = {}
WFJ.ScriptErrors = ScriptErrors

local SURFACE = "scripterrors"
ScriptErrors.SURFACE = SURFACE
local Compat = WFJ.Compat

ScriptErrors.NEVER_TOUCH = { "ScriptErrorsFrame.ScrollFrame.Text", "ScriptErrorsFrame.IndexLabel" }

local CANDIDATES = {
  frame = { "ScriptErrorsFrame" }, title = { "ScriptErrorsFrame.Title" },
  reload = { "ScriptErrorsFrame.Reload" }, close = { "ScriptErrorsFrame.CloseButton" },
}

local TITLE = { only = { "LUA_ERROR", "LUA_WARNING" } }
local RELOAD = { only = { "RELOADUI" } }
local CLOSE = { only = { "CLOSE" } }

local function get(key) return Compat.get(SURFACE, key) end

-- hooksecurefunc target (ScriptErrorsFrame:DisplayMessageInternal) and HookScript target (OnShow).
-- → the number of dictionary words found.
function ScriptErrors.onDisplay()
  local show = WFJ.Labels.show
  local n = show(SURFACE, "title", get("title"), nil, TITLE) + show(SURFACE, "reload", get("reload"), nil, RELOAD)
    + show(SURFACE, "close", get("close"), nil, CLOSE)
  WFJ.Render.updateBanner(SURFACE)
  return n
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function ScriptErrors.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  local frame = get("frame")
  if hooked or type(frame) ~= "table" then return false end
  hooked = true
  if type(frame.DisplayMessageInternal) == "function" then
    hooksecurefunc(frame, "DisplayMessageInternal", ScriptErrors.onDisplay)
  end
  if type(frame.HookScript) == "function" then frame:HookScript("OnShow", ScriptErrors.onDisplay) end
  ScriptErrors.onDisplay()
  return true
end
