-- UI/ReadyCheck.lua: the ready check prompt on Forever (surface "readycheck", area "ui", ADR-016).
-- Blizzard_FrameXML loads mainline/readycheck.lua|xml on camelot: ReadyCheckFrame (READY_CHECK event, readycheck.lua:
-- 36, 44–57) shows ReadyCheckListenerFrame for everyone but the initiator (ShowReadyCheck, :23–33).
--   ReadyCheckListenerFrame.TitleContainer.TitleText   text="READY_CHECK" in XML (readycheck.xml:53); there is no
--                                                      SetTitle, so it is a static label shown on OnShow
--   ReadyCheckFrameYesButton / NoButton                READY / NOT_READY, set once in OnLoad (:40–41)
--   ReadyCheckListenerFrame.Text                       ReadyCheckListenerFrameMixin:Display (:89–110):
--                                                      READY_CHECK_MESSAGE "%s has initiated a ready check." (%s is
--                                                      the initiator, a player name, kept as written). Inside a
--                                                      toggle-difficulty instance the client appends
--                                                      "\n" .. RAID_DIFFICULTY .. ": " .. a difficulty name (:102–106):
--                                                      the readyCheckLine form: both lines matched by key (the
--                                                      initiator and the difficulty name kept as written).
-- Display is the frame's own mixin method (`ReadyCheckListenerFrame:Display(initiator)`, :30), post-hooked on the
-- frame.
local _, WFJ = ...
local ReadyCheck = {}
WFJ.ReadyCheck = ReadyCheck

local SURFACE = "readycheck"
ReadyCheck.SURFACE = SURFACE
local Compat = WFJ.Compat

ReadyCheck.NEVER_TOUCH = {}

local CANDIDATES = {
  listener = { "ReadyCheckListenerFrame", "ReadyCheckFrame.ReadyCheckListenerFrame" },
  title = { "ReadyCheckListenerFrame.TitleContainer.TitleText" },
  text = { "ReadyCheckListenerFrame.Text", "ReadyCheckFrameText" },
  yes = { "ReadyCheckFrameYesButton", "ReadyCheckListenerFrame.YesButton" },
  no = { "ReadyCheckFrameNoButton", "ReadyCheckListenerFrame.NoButton" },
}

local TITLE = { only = { "READY_CHECK" } }
local TEXT = { only = { "READY_CHECK_MESSAGE" } } -- the initiator's name is an argument, never a whole line
local YES = { only = { "READY" } }
local NO = { only = { "NOT_READY" } }
local DIFFICULTY = { "RAID_DIFFICULTY" }

local function get(key) return Compat.get(SURFACE, key) end

-- The readyCheckLine form: READY_CHECK_MESSAGE .. "\n" .. RAID_DIFFICULTY .. ": " .. <difficulty>
-- (readycheck.lua:100–108). → `seq` args | nil
function ReadyCheck.lineArgs(text)
  if type(text) ~= "string" then return nil end
  local message, label, name = text:match("^(.-)\n(.-): (.+)$")
  local first = message and WFJ.Labels.part(message, TEXT.only)
  local second = first and WFJ.Labels.part(label, DIFFICULTY)
  return second and { form = "seq", parts = { first, "\n", second, ": " .. name } } or nil
end

-- The message line: one line, or the two-line readyCheckLine. → 1 | 0
local function showText()
  local fs = get("text")
  if type(fs) ~= "table" or type(fs.GetText) ~= "function" then return 0 end
  local text = fs:GetText()
  if type(text) ~= "string" or not text:find("\n", 1, true) then
    return WFJ.Labels.show(SURFACE, "text", fs, nil, TEXT)
  end
  local rec = WFJ.SurfaceState.get(SURFACE, "text")
  if rec and rec.fs == fs and rec.applied == text then return 1 end -- still ours
  local args = ReadyCheck.lineArgs(text)
  return WFJ.Labels.showArgs(SURFACE, "text", fs, args and args.parts[1].key, args)
end

-- hooksecurefunc target (ReadyCheckListenerFrame:Display) and the OnShow hook. → the number of words found.
function ReadyCheck.onDisplay()
  return WFJ.Labels.showAll(SURFACE, { { "title", get("title"), TITLE }, { "yes", get("yes"), YES },
    { "no", get("no"), NO } }) + showText()
end

local hooked = false

-- Called by Main after Compat.init and ButtonText.init.
function ReadyCheck.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  if hooked then return false end
  local listener = get("listener")
  if type(listener) ~= "table" then return false end
  hooked = true
  if type(listener.Display) == "function" then hooksecurefunc(listener, "Display", ReadyCheck.onDisplay) end
  if type(listener.HookScript) == "function" then listener:HookScript("OnShow", ReadyCheck.onDisplay) end
  ReadyCheck.onDisplay()
  return true
end
