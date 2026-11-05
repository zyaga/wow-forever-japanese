-- UI/WordsWindow.lua: the player's saved words as text to copy (docs/systems/word-list.md, ADR-069). An addon can only
-- write its SavedVariables, so the export is text on screen: tab-separated with Anki's file headers (Core/Words), for a
-- text file, a spreadsheet or Anki. A tool window the player opens; it shows the saved Japanese, never game English.
-- Entry points call WordsWindow.open(): /wfj words, the Words settings page and the minimap button's menu.
local _, WFJ = ...
local WordsWindow = {}
WFJ.WordsWindow = WordsWindow

local W, Text = WFJ.OptionsWidgets, WFJ.OptionsText
local WIDTH, HEIGHT, LEFT = 620, 520, 16
local INNER = WIDTH - 2 * LEFT
local ARM_SECONDS = 5 -- Clear all needs a second click within this long, as the collector's Clear does

WordsWindow.SCREENSHOTS = "World of Warcraft/_forever_/Screenshots"
WordsWindow.ANKI_MAC = "~/Library/Application Support/Anki2/User 1/collection.media"
WordsWindow.ANKI_WIN = "%APPDATA%\\Anki2\\User 1\\collection.media"

WordsWindow.frame = nil

local show = W.setShown

local function date() return WFJ.Compat.resolve("date") end

local function copyCall()
  local f = WFJ.Compat.resolve("CopyToClipboard")
  return type(f) == "function" and f or nil
end

local function say(key, ...)
  local f = WordsWindow.frame
  if key then W.setPair(f.message, Text.get(key, ...)) else W.setPair(f.message, "", "") end
end

local function fill()
  local f = WordsWindow.frame
  local n = WFJ.Words.count()
  if n == 0 then W.setPair(f.summary, Text.get("words.empty"))
  else W.setPair(f.summary, Text.get("words.summary", n)) end
  local images = f.images:GetChecked() and true or false
  f.text:setText(WFJ.Words.export({ images = images }, date()))
  show(f.shotsLabel.en, images); show(f.shotsLabel.ja, images); show(f.shotsPath, images)
  show(f.ankiLabel.en, images); show(f.ankiLabel.ja, images); show(f.ankiMac, images); show(f.ankiWin, images)
  show(f.copy, copyCall() ~= nil)
end

local function copy()
  local fn = copyCall()
  if not fn then return end
  local n = fn(WordsWindow.frame.text.value, false)
  if type(n) == "number" and n > 0 then say("words.copied") else say(nil) end
end

local function removeLast()
  if WFJ.Words.readonly() then return say("words.refused") end
  local e = WFJ.Words.removeLast()
  fill()
  if e then say("words.removed", e.word) else say(nil) end
end

local armedAt
local function clear(button)
  if WFJ.Words.readonly() then return say("words.refused") end
  local now = WFJ.Compat.resolve("GetTime")()
  if armedAt and now - armedAt <= ARM_SECONDS then
    armedAt = nil
    local n = WFJ.Words.clear() or 0
    button:setLabel(Text.get("words.clear"))
    fill()
    say("words.cleared", n)
  else
    armedAt = now
    button:setLabel(Text.get("words.clearArm"))
  end
end

local function build()
  local f = W.toolWindow("WFJWordsWindow", WIDTH, HEIGHT)
  local p = CreateFrame("Frame", nil, f)
  p:SetPoint("TOPLEFT", 0, -32)
  p:SetSize(WIDTH, HEIGHT - 40)
  f.page = p
  f.summary = W.label(p, "", "", LEFT, -4, INNER)
  f.text = W.scrollText(p, LEFT, -40, INNER, 220)
  f.copyHint = W.label(p, "", "", LEFT, -270, INNER)
  W.setPair(f.copyHint, Text.get("words.copyHint"))
  local en, ja = Text.get("words.copy")
  f.copy = W.button(p, en, ja, 120, copy)
  f.copy:SetPoint("TOPLEFT", LEFT, -312)
  en, ja = Text.get("words.removeLast")
  f.removeLast = W.button(p, en, ja, 140, removeLast)
  f.removeLast:SetPoint("TOPLEFT", LEFT + 140, -312)
  en, ja = Text.get("words.clear")
  f.clear = W.button(p, en, ja, 140, function(self) clear(self) end)
  f.clear:SetPoint("TOPLEFT", LEFT + 300, -312)
  en, ja = Text.get("words.images")
  f.images = W.checkbox(p, en, ja, LEFT, -346, INNER, function() fill() end)
  f.shotsLabel = W.label(p, "", "", LEFT, -378, INNER)
  W.setPair(f.shotsLabel, Text.get("words.shotsPath"))
  f.shotsPath = W.copyBox(p, LEFT, -396, INNER - 12, WordsWindow.SCREENSHOTS)
  f.ankiLabel = W.label(p, "", "", LEFT, -420, INNER)
  W.setPair(f.ankiLabel, Text.get("words.ankiPath"))
  f.ankiMac = W.copyBox(p, LEFT, -438, INNER - 12, WordsWindow.ANKI_MAC)
  f.ankiWin = W.copyBox(p, LEFT, -460, INNER - 12, WordsWindow.ANKI_WIN)
  f.message = W.label(p, "", "", LEFT + 460, -316, INNER - 460)
  f.message.en:SetTextColor(W.GOLD[1], W.GOLD[2], W.GOLD[3])
  WordsWindow.frame = f
  return f
end

function WordsWindow.retitle()
  local f = WordsWindow.frame
  if f then W.put(f.title, W.pick(Text.get("words.title")), 13) end
end
local function retitleIfShown()
  if WordsWindow.frame and WordsWindow.frame:IsShown() then WordsWindow.retitle() end
end
WFJ.State.on("modifier", retitleIfShown)
WFJ.State.on("enabled", retitleIfShown)

function WordsWindow.open()
  local f = WordsWindow.frame or build()
  WordsWindow.retitle()
  armedAt = nil
  f.clear:setLabel(Text.get("words.clear"))
  say(nil)
  fill()
  f:Show()
  W.relabelIfStale()
  f.text.focusAll()
  return f
end

-- Kept current while it is open: a word saved with the window up shows in the text at once.
function WordsWindow.refresh()
  if WordsWindow.frame and WordsWindow.frame:IsShown() then fill() end
end
