-- UI/CollectorSendWindow.lua: the window that sends the collected English (docs/systems/collector.md, ADR-056).
-- It packs the lines not sent yet (Core/CollectorSend) and walks the player through one issue: open the link, paste
-- the string if the link could not carry it (or attach the file when even that is too long), submit, then click
-- I sent it. A tool window the player opens; it shows the encoded string, never English text. Every label is the
-- addon's own copy (UI/OptionsText) in one language, as on the settings pages (UI/OptionsWidgets).
-- Entry points call CollectorSendWindow.open(all): /wfj collector send [all] and the collector page's button.
local _, WFJ = ...
local SendWindow = {}
WFJ.CollectorSendWindow = SendWindow

local W, Text = WFJ.OptionsWidgets, WFJ.OptionsText
local WIDTH, HEIGHT, LEFT = 560, 490, 16
local INNER = WIDTH - 2 * LEFT

SendWindow.frame = nil
SendWindow.pack = nil -- the pack on screen: what I sent it marks

local function pair(key, ...)
  return Text.get(key, ...)
end

local function build()
  local f = W.toolWindow("WFJCollectorSendWindow", WIDTH, HEIGHT)

  local p = CreateFrame("Frame", nil, f)
  p:SetPoint("TOPLEFT", 0, -32)
  p:SetSize(WIDTH, HEIGHT - 40)
  f.page = p
  f.summary = W.label(p, "", "", LEFT, -4, INNER)
  f.step1 = W.label(p, "", "", LEFT, -46, INNER)
  f.url = W.copyBox(p, LEFT, -68, INNER - 12, "")
  -- a link can be 6,000 characters: no letter or byte limit on the box
  if f.url.SetMaxLetters then f.url:SetMaxLetters(0) end
  if f.url.SetMaxBytes then f.url:SetMaxBytes(0) end
  f.step2 = W.label(p, "", "", LEFT, -100, INNER)
  f.text = W.scrollText(p, LEFT, -122, INNER, 170)
  f.path = W.copyBox(p, LEFT, -122, INNER - 12, "")
  f.step3 = W.label(p, "", "", LEFT, -302, INNER)
  f.step4 = W.label(p, "", "", LEFT, -334, 300)
  local en, ja = pair("send.sent")
  f.sent = W.button(p, en, ja, 160, function() SendWindow.markSent() end)
  f.sent:SetPoint("TOPLEFT", LEFT + 310, -330)
  f.message = W.label(p, "", "", LEFT, -370, INNER)
  f.message.en:SetTextColor(W.GOLD[1], W.GOLD[2], W.GOLD[3])
  SendWindow.frame = f
  return f
end

local setBox, show = W.setBox, W.setShown

local function showLabel(l, on, key, ...)
  if on then W.setPair(l, pair(key, ...)) else W.setPair(l, "", "") end
end

-- Each row below step 2 sits under the one before it: a step's copy wraps to two lines in either language (the
-- paste step does at this width), so fixed heights put a box over its second line.
local GAP = 8
function SendWindow.layout()
  local f = SendWindow.frame
  local function below(widget, anchor, x, gap)
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x or 0, -(gap or GAP))
  end
  local last = f.step2.en
  if f.text.frame:IsShown() then
    below(f.text.frame, last)
    last = f.text.frame
  elseif f.path:IsShown() then
    below(f.path, last, 6) -- InputBoxTemplate's left cap sits outside the frame
    last = f.path
  end
  below(f.step3.en, last, last == f.path and -6 or 0, 12)
  below(f.step4.en, f.step3.en, 0, 12)
  f.sent:ClearAllPoints()
  f.sent:SetPoint("LEFT", f.step4.en, "LEFT", 310, 0)
  below(f.message.en, f.step4.en, 0, 18)
end

-- Fills the window from a pack (Core/CollectorSend.pack).
-- The summary line's copy per mode: link, paste and file share one.
local SUMMARY = { link = "send.summary", paste = "send.summary", file = "send.summary",
  unavailable = "send.summary.unavailable", empty = "send.summary.empty", readonly = "send.summary.readonly" }

local function fill(pk)
  local f = SendWindow.frame
  local mode = pk.mode
  local attach = mode == "file" or mode == "unavailable"
  local steps = mode == "link" or mode == "paste" or attach
  W.setPair(f.summary, pair(SUMMARY[mode], pk.count, pk.shipped))
  showLabel(f.step1, steps, "send.step1")
  show(f.url, steps)
  setBox(f.url, steps and pk.url or "")
  showLabel(f.step2, steps, "send.step2." .. (attach and "file" or mode))
  show(f.text, mode == "paste")
  f.text:setText(mode == "paste" and pk.text or "")
  show(f.path, attach)
  setBox(f.path, WFJ.Collector.path())
  showLabel(f.step3, steps, "send.step3")
  showLabel(f.step4, steps, "send.step4")
  show(f.sent, steps)
  SendWindow.layout()
  -- the saved file holds only what the client wrote at the last logout or /reload
  if attach and pk.later > 0 then W.setPair(f.message, pair("send.later", pk.later))
  else W.setPair(f.message, "", "") end
end

function SendWindow.retitle()
  local f = SendWindow.frame
  if f then W.put(f.title, W.pick(pair("send.title")), 13) end
end
local function retitleIfShown()
  if SendWindow.frame and SendWindow.frame:IsShown() then SendWindow.retitle() end
end
WFJ.State.on("modifier", retitleIfShown)
WFJ.State.on("enabled", retitleIfShown)

-- Packs and shows. all: every entry again (a send that was copied but never submitted).
function SendWindow.open(all)
  local f = SendWindow.frame or build()
  SendWindow.retitle()
  SendWindow.pack = WFJ.CollectorSend.pack(all == true)
  fill(SendWindow.pack)
  f:Show()
  W.relabelIfStale()
  if SendWindow.pack.mode == "link" then f.url:SetFocus() end
  return f
end

-- I sent it: the lines in the pack on screen count as sent. → the number marked
function SendWindow.markSent()
  local f = SendWindow.frame
  local pk = SendWindow.pack
  if not f or not pk then return 0 end
  WFJ.CollectorSend.markSent(pk)
  local n = pk.count - (pk.later or 0) -- the lines this send carried (not the ones left out as translated)
  SendWindow.pack = nil
  show(f.sent, false)
  if WFJ.Collector.status().capped then
    W.setPair(f.message, pair("send.markedFull", n))
  else
    W.setPair(f.message, pair("send.marked", n))
  end
  if WFJ.Options and WFJ.Options.refresh then pcall(WFJ.Options.refresh) end
  return n
end
