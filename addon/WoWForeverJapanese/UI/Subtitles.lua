-- UI/Subtitles.lua: the subtitle lines shown over a cinematic (records on surface "cinematic.subtitles", area "ui",
-- ADR-016). Blizzard_Subtitles is a login addon (blizzard_subtitles.toc has no LoadOnDemand), so SubtitlesFrame
-- normally exists at login; the setup still waits through WFJ.LoadOnDemand.when.
-- Writer: SubtitlesFrameMixin:OnEvent takes SHOW_SUBTITLE (message, sender) and calls self:AddSubtitle(body), body the
-- message alone or format(SUBTITLE_FORMAT, sender, message) (blizzard_subtitles.lua:85–97). AddSubtitle writes the
-- first hidden FontString of self.Subtitles, or scrolls every line up one (each takes the next line's GetText) and
-- writes the last (lua:37–54). The message is a BroadcastText row's English, matched only in that family; the
-- sender is a name and stays as written, around it SUBTITLE_FORMAT's own words. Any other line stays English.
-- AddSubtitle is post-hooked on the instance. Before matching, a line that took our Japanese from the line below it
-- in the scroll gets that line's live English back, so Alt keeps showing English on every line. HideSubtitles
-- (lua:72–79) empties the lines; the records are then forgotten, never restored over the emptied lines.
-- [unverified in game: no subtitle line shows on the Forever intro cinematics with subtitles on]
local _, WFJ = ...
local Subtitles = {}
WFJ.Subtitles = Subtitles

local SURFACE = "cinematic.subtitles"
Subtitles.SURFACE = SURFACE
local Compat = WFJ.Compat
local ADDON = "Blizzard_Subtitles"

Subtitles.NEVER_TOUCH = {}

local function frame() return Compat.get(SURFACE, "frame") end

local lineKey = WFJ.Labels.keyer("line.") -- one record per subtitle FontString

-- A line written with SUBTITLE_FORMAT: → the text before the message (the format's words around the speaker's name),
-- the message, the text after it | nil when the line or the format is no plain "<words>%s<words>%s<words>".
local function splitSender(text)
  local fmt = Compat.resolve("SUBTITLE_FORMAT")
  if type(fmt) ~= "string" then return nil end
  local a, b, c = fmt:match("^(.-)%%s(.-)%%s(.*)$")
  if not a or (a .. b .. c):find("%", 1, true) then return nil end
  local function esc(t) return (t:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end
  local head, message = text:match("^(" .. esc(a) .. ".-" .. esc(b) .. ")(.*)$")
  if not head or message:sub(#message - #c + 1) ~= c then return nil end
  return head, message:sub(1, #message - #c), c
end

-- One line: the message alone or inside SUBTITLE_FORMAT, the message a BroadcastText row. → 1 | 0
local function showLine(fs)
  local recKey = lineKey(fs)
  local index = WFJ.UIIndex
  local text = type(fs.GetText) == "function" and fs:GetText() or nil
  local key, args
  if index and type(text) == "string" and text ~= "" then
    local only = WFJ.Labels.families("BroadcastText").only
    key = index:matchOnly(text, only)
    local head, message, tail
    if not key then head, message, tail = splitSender(text) end
    if message and message ~= "" then
      key = index:matchOnly(message, only)
      args = key and { form = "affix", before = head, after = tail } or nil
    end
  end
  return WFJ.Labels.showArgs(SURFACE, recKey, fs, key, args)
end

-- hooksecurefunc target (SubtitlesFrame:AddSubtitle). → the number of lines in Japanese
function Subtitles.onAdd()
  local f = frame()
  local lines = type(f) == "table" and f.Subtitles or nil
  if type(lines) ~= "table" then return 0 end
  -- our Japanese → its English, from every line's record as it stood before this scroll
  local english = {}
  for _, fs in ipairs(lines) do
    local rec = type(fs) == "table" and WFJ.SurfaceState.get(SURFACE, lineKey(fs)) or nil
    if rec and type(rec.applied) == "string" and type(rec.en) == "string" then english[rec.applied] = rec.en end
  end
  local n = 0
  for _, fs in ipairs(lines) do
    if type(fs) == "table" and type(fs.GetText) == "function" and type(fs.SetText) == "function" then
      local text = fs:GetText()
      local rec = WFJ.SurfaceState.get(SURFACE, lineKey(fs))
      local own = rec and rec.fs == fs and rec.applied == text
      if not own and type(text) == "string" and english[text] then fs:SetText(english[text]) end
      n = n + showLine(fs)
    end
  end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

function Subtitles.forget()
  return WFJ.Render.forget(SURFACE)
end

local hooked = false

-- Blizzard_Subtitles' part, once it is loaded. → true when hooked now
function Subtitles.setup()
  Compat.declare(SURFACE, "frame", { "SubtitlesFrame" })
  local f = frame()
  if hooked or type(f) ~= "table" or type(f.AddSubtitle) ~= "function" then return false end
  hooked = true
  hooksecurefunc(f, "AddSubtitle", Subtitles.onAdd)
  if type(f.HideSubtitles) == "function" then hooksecurefunc(f, "HideSubtitles", Subtitles.forget) end
  return true
end

-- Called by Main after Compat.init and LoadOnDemand.init. → true when the frame was hooked now
function Subtitles.init()
  Compat.declare(SURFACE, "frame", { "SubtitlesFrame" })
  local done = false
  WFJ.LoadOnDemand.when(ADDON, function() done = Subtitles.setup() end)
  return done
end
