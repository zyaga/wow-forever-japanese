-- UI/CollectorReminder.lua: the popup that collected English is waiting to be sent (docs/systems/collector.md).
-- Core/CollectorRemind decides when (login or reload, 10 or more unsent lines, at most once a day) and calls
-- CollectorReminder.open(count). It shows the count only, never a line's text: Send opens the send window, Later
-- closes it, and the box turns the reminder off (collector.remind) without turning the collector off.
-- Labels are the addon's copy (UI/OptionsText) in one language, like the other tool windows.
local _, WFJ = ...
local CollectorReminder = {}
WFJ.CollectorReminder = CollectorReminder

local W, Text, S = WFJ.OptionsWidgets, WFJ.OptionsText, WFJ.Settings
local LEFT, MIN_WIDTH = 24, 360
-- ButtonFrameTemplate's inset panel leaves room for tabs above it and buttons below it (TOPLEFT 4,-60 /
-- BOTTOMRIGHT -6,26 [verified: Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml:711]); this window has
-- neither, so the panel is moved up under the title bar and down to the bottom edge
local INSET_TOP, INSET_BOTTOM = 24, 4
local TOP, BOTTOM, PAD = INSET_TOP + 4, INSET_BOTTOM + 4, 12
local GOLD = "|cffffd200%d|r"
local LINE = 6 -- between the sentences; each sentence is its own line and never wraps

CollectorReminder.frame = nil
CollectorReminder.count = 0

-- One sentence, centred, on one line (no width, so the client never wraps it).
local function sentence(p)
  local l = W.label(p, "", "", 0, 0)
  l.en:SetJustifyH("CENTER")
  l.en:ClearAllPoints()
  return l
end

local function build()
  local f = W.toolWindow("WFJCollectorReminder", MIN_WIDTH, 200)
  if f.Inset then
    f.Inset:ClearAllPoints()
    f.Inset:SetPoint("TOPLEFT", 4, -INSET_TOP)
    f.Inset:SetPoint("BOTTOMRIGHT", -6, INSET_BOTTOM)
  end
  local p = CreateFrame("Frame", nil, f)
  p:SetPoint("TOPLEFT", 0, -TOP)
  p:SetPoint("TOPRIGHT", 0, -TOP)
  p:SetHeight(1)
  f.page = p
  f.saved = sentence(p)
  f.saved.en:SetPoint("TOP", p, "TOP", 0, -PAD)
  f.ask = sentence(p)
  f.ask.en:SetPoint("TOP", f.saved.en, "BOTTOM", 0, -LINE)
  local en, ja = Text.get("reminder.send")
  f.send = W.button(p, en, ja, 170, function() CollectorReminder.send() end)
  f.send:SetPoint("TOPRIGHT", f.ask.en, "BOTTOM", -6, -16)
  en, ja = Text.get("reminder.later")
  f.later = W.button(p, en, ja, 170, function() CollectorReminder.close() end)
  f.later:SetPoint("TOPLEFT", f.ask.en, "BOTTOM", 6, -16)
  en, ja = Text.get("reminder.stop")
  f.stop = W.checkbox(p, en, ja, 0, 0, 300, function(checked) S.set("collector.remind", not checked) end)
  f.stop:ClearAllPoints()
  f.stop:SetPoint("TOPLEFT", f.send, "BOTTOMLEFT", 0, -10)
  f.stop.label.en:ClearAllPoints()
  f.stop.label.en:SetPoint("LEFT", f.stop, "RIGHT", 4, 0)
  CollectorReminder.frame = f
  return f
end

-- The window's width from its longest sentence in either language (measured on the label's spare font string), so
-- it keeps one size when the reveal key switches the language and no sentence wraps; its height from its rows.
local function fit()
  local f = CollectorReminder.frame
  local widest, height = MIN_WIDTH - 2 * LEFT, 0
  for _, l in ipairs({ f.saved, f.ask }) do
    l.en:SetWidth(0)
    for _, text in ipairs(l.pair or {}) do
      W.put(l.ja, text, 12)
      local w = l.ja.GetStringWidth and math.ceil(l.ja:GetStringWidth()) or 0
      if w > widest then widest = w end
    end
    l.ja:SetText("")
    height = height + (l.en.GetStringHeight and math.ceil(l.en:GetStringHeight()) or 14)
  end
  f:SetWidth(widest + 2 * LEFT)
  f:SetHeight(TOP + PAD + height + LINE + 16 + 22 + 10 + 24 + PAD + BOTTOM)
end

function CollectorReminder.retitle()
  local f = CollectorReminder.frame
  if not f then return end
  W.put(f.title, W.pick(Text.get("reminder.title")), 13)
  W.setPair(f.saved, Text.get("reminder.saved", GOLD:format(CollectorReminder.count)))
  W.setPair(f.ask, Text.get("reminder.ask"))
  fit()
end
local function retitleIfShown()
  if CollectorReminder.frame and CollectorReminder.frame:IsShown() then CollectorReminder.retitle() end
end
WFJ.State.on("modifier", retitleIfShown)
WFJ.State.on("enabled", retitleIfShown)

-- Shows the popup for `count` unsent lines. → the frame
function CollectorReminder.open(count)
  local f = CollectorReminder.frame or build()
  CollectorReminder.count = count
  CollectorReminder.retitle()
  f.stop:SetChecked(S.get("collector.remind") == false)
  f:Show()
  W.relabelIfStale()
  return f
end

function CollectorReminder.close()
  if CollectorReminder.frame then CollectorReminder.frame:Hide() end
end

-- Send: the send window takes over.
function CollectorReminder.send()
  CollectorReminder.close()
  if WFJ.CollectorSendWindow then WFJ.CollectorSendWindow.open(false) end
end
