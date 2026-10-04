-- UI/ReportWindow.lua: the window that reports a bug or sends an idea (docs/systems/fix-reports.md, "Bug and idea
-- reports"). A radio choice at the top picks Bug or Idea. Bug: a link to the bug-report form with build, version and
-- the addon's unsent Lua errors filled in (Core/BugReport), the error text to paste when the link would be too long,
-- and I sent it, which marks those errors sent. Idea: a link to the idea form. A tool window the player opens; it
-- shows the addon's own errors, never game text. Labels are the addon's copy (UI/OptionsText) in one language.
-- Entry points call ReportWindow.open(): /wfj bug, the minimap menu and the About page's button.
local _, WFJ = ...
local ReportWindow = {}
WFJ.ReportWindow = ReportWindow

local W, Text = WFJ.OptionsWidgets, WFJ.OptionsText
local WIDTH, HEIGHT, LEFT = 560, 470, 16
local INNER = WIDTH - 2 * LEFT
ReportWindow.INNER = INNER

ReportWindow.frame = nil
ReportWindow.mode = "bug"
ReportWindow.pack = nil -- the bug report on screen: what I sent it marks

local function pair(key, ...)
  return Text.get(key, ...)
end

-- A radio button with its label, the label clickable too; a click always checks it. [verified:
-- UIRadialButtonTemplate Blizzard_SharedXML/Shared/Button/CheckButtonTemplates.xml:26, as UI/FixWindow uses it]
local function radio(parent, key, onPick)
  local b = CreateFrame("CheckButton", nil, parent, "UIRadialButtonTemplate")
  b.text = b.text or b:CreateFontString(nil, "BACKGROUND")
  b.key = key
  b:SetScript("OnClick", function(self) self:SetChecked(true); onPick() end)
  return b
end

local function build()
  local f = W.toolWindow("WFJReportWindow", WIDTH, HEIGHT)

  local p = CreateFrame("Frame", nil, f)
  p:SetPoint("TOPLEFT", 0, -32)
  p:SetSize(WIDTH, HEIGHT - 40)
  f.page = p
  f.bug = radio(p, "report.bug", function() ReportWindow.setMode("bug") end)
  f.bug:SetPoint("TOPLEFT", LEFT + 4, -4)
  f.idea = radio(p, "report.idea", function() ReportWindow.setMode("idea") end)
  f.idea:SetPoint("LEFT", f.bug.text, "RIGHT", 18, 0)
  f.summary = W.label(p, "", "", LEFT, -34, INNER)
  f.step1 = W.label(p, "", "", LEFT, -60, INNER)
  f.url = W.copyBox(p, LEFT, -82, INNER - 12, "")
  -- a link can be 6,000 characters: no letter or byte limit on the box
  if f.url.SetMaxLetters then f.url:SetMaxLetters(0) end
  if f.url.SetMaxBytes then f.url:SetMaxBytes(0) end
  f.step2 = W.label(p, "", "", LEFT, -110, INNER)
  f.text = W.scrollText(p, LEFT, -132, INNER, 150)
  f.step3 = W.label(p, "", "", LEFT, -290, INNER)
  f.step4 = W.label(p, "", "", LEFT, -320, 300)
  local en, ja = pair("send.sent")
  f.sent = W.button(p, en, ja, 160, function() ReportWindow.markSent() end)
  f.message = W.label(p, "", "", LEFT, -360, INNER)
  f.message.en:SetTextColor(W.GOLD[1], W.GOLD[2], W.GOLD[3])
  ReportWindow.frame = f
  return f
end

local setBox, show = W.setBox, W.setShown

local function showLabel(l, on, key, ...)
  if on then W.setPair(l, pair(key, ...)) else W.setPair(l, "", "") end
end

-- Each row sits under the one before it, so a label that wraps never runs into the next row.
local GAP = 8
function ReportWindow.layout()
  local f = ReportWindow.frame
  local function below(widget, anchor, x, gap)
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x or 0, -(gap or GAP))
  end
  below(f.step1.en, f.summary.en, 0, 12)
  below(f.url, f.step1.en, 6) -- InputBoxTemplate's left cap sits outside the frame
  below(f.step2.en, f.url, -6, 10)
  local last = f.step2.en
  if f.text.frame:IsShown() then
    below(f.text.frame, last)
    last = f.text.frame
  end
  below(f.step3.en, last, 0, 12)
  below(f.step4.en, f.step3.en, 0, 12)
  f.sent:ClearAllPoints()
  f.sent:SetPoint("LEFT", f.step4.en, "LEFT", 310, 0)
  below(f.message.en, f.step4.en, 0, 18)
end

local function summaryKey(pk)
  if not pk.ours then return "report.summary.other" end
  return pk.count > 0 and "report.summary.errors" or "report.summary.none"
end

local function fill()
  local f = ReportWindow.frame
  local bug = ReportWindow.mode == "bug"
  f.bug:SetChecked(bug)
  f.idea:SetChecked(not bug)
  W.setPair(f.message, "", "")
  W.setPair(f.step1, pair("send.step1"))
  if not bug then
    ReportWindow.pack = nil
    W.setPair(f.summary, pair("report.summary.idea"))
    setBox(f.url, WFJ.BugReport.IDEA_URL)
    W.setPair(f.step2, pair("report.idea.step2"))
    show(f.text, false)
    f.text:setText("")
    showLabel(f.step3, false)
    showLabel(f.step4, false)
    show(f.sent, false)
    ReportWindow.layout()
    return
  end
  local pk = ReportWindow.pack
  local paste = pk.mode == "paste"
  W.setPair(f.summary, pair(summaryKey(pk), pk.count))
  setBox(f.url, pk.url)
  showLabel(f.step2, true, paste and "report.step2.paste" or "report.step2.link")
  show(f.text, paste)
  f.text:setText(paste and pk.text or "")
  showLabel(f.step3, true, "report.step3")
  local errors = pk.count > 0
  showLabel(f.step4, errors, "send.step4")
  show(f.sent, errors)
  ReportWindow.layout()
end

-- The build string the login screen shows (1.60.1.70170).
local function clientBuild()
  local info = WFJ.Compat.resolve("GetBuildInfo")
  if type(info) ~= "function" then return "?" end
  local version, number = info()
  return tostring(version) .. "." .. tostring(number)
end

-- A fresh bug report from the unsent errors.
local function packBug()
  return WFJ.BugReport.pack({ build = clientBuild(), version = WFJ.VERSION, errors = WFJ.ErrorLog.unsent(),
    ours = WFJ.ErrorLog.ours() })
end

function ReportWindow.retitle()
  local f = ReportWindow.frame
  if not f then return end
  W.put(f.title, W.pick(pair("report.title")), 13)
  for _, b in ipairs({ f.bug, f.idea }) do
    W.put(b.text, W.pick(pair(b.key)), 12)
    -- the clickable area is the circle plus its own label
    local w = b.text.GetStringWidth and b.text:GetStringWidth() or 0
    if b.SetHitRectInsets then b:SetHitRectInsets(0, -(w + 8), -3, -3) end
  end
end
local function retitleIfShown()
  if ReportWindow.frame and ReportWindow.frame:IsShown() then ReportWindow.retitle() end
end
WFJ.State.on("modifier", retitleIfShown)
WFJ.State.on("enabled", retitleIfShown)

-- Switches between Bug and Idea and redraws.
function ReportWindow.setMode(mode)
  ReportWindow.mode = mode == "idea" and "idea" or "bug"
  if ReportWindow.mode == "bug" then ReportWindow.pack = packBug() end
  if ReportWindow.frame then fill() end
end

-- Opens on Bug with the errors not sent yet.
function ReportWindow.open()
  local f = ReportWindow.frame or build()
  ReportWindow.retitle()
  ReportWindow.setMode("bug")
  f:Show()
  W.relabelIfStale()
  f.url:SetFocus()
  return f
end

-- I sent it: the errors in the report on screen count as sent. → the number marked
function ReportWindow.markSent()
  local f = ReportWindow.frame
  local pk = ReportWindow.pack
  if not f or not pk then return 0 end
  local n = WFJ.ErrorLog.markSent(pk.sent)
  ReportWindow.pack = nil
  show(f.sent, false)
  W.setPair(f.message, pair("report.marked", n))
  return n
end
