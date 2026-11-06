-- UI/StudyWindow.lua: placeholder until the window step lands (keeps the TOC loadable).
local _, WFJ = ...
local StudyWindow = {}
WFJ.StudyWindow = StudyWindow

local function now() return WFJ.Compat.call("time") or 0 end
local function today() return WFJ.Compat.call("date", "%Y-%m-%d") or "" end
local function cap() return tonumber(WFJ.Settings.get("study.newPerDay")) or 20 end

function StudyWindow.counts()
  return WFJ.Study.counts(WFJ.Words.entries(), now(), today(), cap())
end
function StudyWindow.open() end
function StudyWindow.refresh() end
function StudyWindow.command(words, say) say("study: " .. tostring(words[1])) end
function WFJ_StudyToggle() StudyWindow.open() end
