-- UI/Cinematic.lua: the "cancel this cinematic?" dialogs on Forever (surface "cinematic", area "ui", ADR-016).
-- Blizzard_FrameXML loads movieframe.xml|lua and shared/cinematicframe.xml|lua at login on `camelot`. Pressing Escape
-- during a pre-rendered movie or an in-engine cinematic shows a close dialog (MovieFrameMixin:ShowCloseDialog,
-- movieframe.lua:100–106; the cinematic frame's closeDialog, shared/cinematicframe.xml:35–70). Their words are XML
-- text= labels, never rewritten: an OnShow pass (HookScript on each dialog) shows them.
--   MovieFrame.CloseDialog: Title CONFIRM_CLOSE_CINEMATIC (movieframe.xml:34), Buttons.ConfirmButton YES (:59),
--     Buttons.ResumeButton NO (:65).
--   CinematicFrameCloseDialog: CinematicFrameCloseDialogText CONFIRM_CLOSE_CINEMATIC (cinematicframe.xml:42),
--     CinematicFrameCloseDialogConfirmButton YES (:52), CinematicFrameCloseDialogResumeButton NO (:62).
-- Never touched: MovieFrame.CloseDialog.Summary (the cinematic's own summary, GetCurrentCinematicSummary(),
-- lua:101–104).
-- These are real frames, not StaticPopups: YES / NO here are button labels this surface owns.
local _, WFJ = ...
local Cinematic = {}
WFJ.Cinematic = Cinematic

local SURFACE = "cinematic"
Cinematic.SURFACE = SURFACE
local Compat = WFJ.Compat

Cinematic.NEVER_TOUCH = { "MovieFrame.CloseDialog.Summary" }

local QUESTION = { only = { "CONFIRM_CLOSE_CINEMATIC" } }
local YES = { only = { "YES" } }
local NO = { only = { "NO" } }

-- dialog key → its label list { recKey, candidate, opts }
local DIALOGS = {
  movie = { "MovieFrame.CloseDialog", {
    { "movie.title", "MovieFrame.CloseDialog.Title", QUESTION },
    { "movie.confirm", "MovieFrame.CloseDialog.Buttons.ConfirmButton", YES },
    { "movie.resume", "MovieFrame.CloseDialog.Buttons.ResumeButton", NO } } },
  cinematic = { "CinematicFrameCloseDialog", {
    { "cinematic.text", "CinematicFrameCloseDialogText", QUESTION },
    { "cinematic.confirm", "CinematicFrameCloseDialogConfirmButton", YES },
    { "cinematic.resume", "CinematicFrameCloseDialogResumeButton", NO } } },
}

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  for key, d in pairs(DIALOGS) do
    Compat.declare(SURFACE, key, { d[1] })
    for _, l in ipairs(d[2]) do Compat.declare(SURFACE, l[1], { l[2] }) end
  end
end

-- One dialog's labels (its OnShow). → the number of dictionary words found.
function Cinematic.show(key)
  local d = DIALOGS[key]
  if not d then return 0 end
  local list = {}
  for i, l in ipairs(d[2]) do list[i] = { l[1], get(l[1]), l[3] } end
  return WFJ.Labels.showAll(SURFACE, list)
end

local hooked = false

-- Called by Main after Compat.init. → true when at least one dialog was hooked now; false on a second
-- call.
function Cinematic.init()
  declare()
  if hooked then return false end
  local any = false
  for key in pairs(DIALOGS) do
    local dialog = get(key)
    if type(dialog) == "table" and type(dialog.HookScript) == "function" then
      dialog:HookScript("OnShow", function() Cinematic.show(key) end)
      Cinematic.show(key)
      any = true
    end
  end
  hooked = any
  return any
end
