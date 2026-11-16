-- UI/WordsWindow.lua: the player's saved words as text to copy (docs/systems/word-list.md, ADR-069). An addon can only
-- write its SavedVariables, so the export is text on screen: tab-separated with Anki's file headers (Core/Words), for a
-- text file, a spreadsheet or Anki. A tool window the player opens; it shows the saved Japanese, never game English.
-- Entry points call WordsWindow.open(): /wfj words, the Words settings page and the minimap button's menu.
-- With a voice pack, Include audio adds each sentence's recording to the export (UI/StudyVoice, ADR-092) and lists
-- those files and where they go, for the player to copy into Anki's media folder: an addon cannot copy files itself.
local _, WFJ = ...
local WordsWindow = {}
WFJ.WordsWindow = WordsWindow

local W, Text = WFJ.OptionsWidgets, WFJ.OptionsText
local WIDTH, HEIGHT, LEFT = 620, 520, 16
local HEIGHT_IMAGES = 570 -- with Include images ticked: room for the two folder paths below the checkbox
local ROW = 28 -- a checkbox row
local AUDIO_LINES = 96 -- the file list's box
local BOTTOM = 40 -- the frame below the page's last row: the page starts 32 down, and a margin
local INNER = WIDTH - 2 * LEFT
local ARM_SECONDS = 5 -- Clear all needs a second click within this long, as the collector's Clear does

WordsWindow.SCREENSHOTS = "World of Warcraft/_forever_/Screenshots"
WordsWindow.ANKI_MAC = "~/Library/Application Support/Anki2/User 1/collection.media"
WordsWindow.ANKI_WIN = "%APPDATA%\\Anki2\\User 1\\collection.media"

WordsWindow.frame = nil

local show = W.setShown

local function date() return WFJ.Compat.resolve("date") end

local function say(key, ...)
  local f = WordsWindow.frame
  if key then W.setPair(f.message, Text.get(key, ...)) else W.setPair(f.message, "", "") end
end

local SV = WFJ.StudyVoice

local function at(frame, y, x)
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", x or LEFT, y)
end

-- Include audio sits under the images rows when they show; ticked, its hint, Anki's folder and the file list
-- under it. `found`: the entries' files (StudyVoice.findAll), when Include audio is ticked. → the frame's height
local function layAudio(images, offered, found)
  local f = WordsWindow.frame
  local base = images and HEIGHT_IMAGES or HEIGHT
  for _, w in ipairs({ f.audio, f.audio.label.en, f.audio.label.ja }) do show(w, offered) end
  for _, w in ipairs(f.audioRows) do show(w, found ~= nil) end
  if not offered then return base end
  local y = images and -490 or -374
  at(f.audio, y + 5)
  at(f.audio.label.en, y, LEFT + 30)
  if not found then return base end
  at(f.audioHint.en, y - ROW - 4)
  at(f.ankiFolder, y - ROW - 70, LEFT + 6) -- InputBoxTemplate's left cap sits outside the frame
  at(f.audioLines.frame, y - ROW - 98)
  W.setBox(f.ankiFolder, WFJ.Compat.call("IsMacClient") == true and WordsWindow.ANKI_MAC or WordsWindow.ANKI_WIN)
  local lines = SV.fileList(WFJ.Words.entries(), found)
  f.audioLines:setText(#lines > 0 and table.concat(lines, "\n") or W.pick(Text.get("words.audioNone")))
  return math.max(base, -(y - ROW - 98 - AUDIO_LINES) + BOTTOM)
end

local function fill()
  local f = WordsWindow.frame
  local n = WFJ.Words.count()
  if n == 0 then W.setPair(f.summary, Text.withSaveClick("words.empty"))
  else W.setPair(f.summary, Text.get("words.summary", n)) end
  local images = f.images:GetChecked() and true or false
  local offered = WFJ.Voice.hasPack()
  local found = offered and f.audio:GetChecked() and SV.findAll(WFJ.Words.entries()) or nil
  local audio = found and function(e) return SV.cell(found[e]) end or nil
  f.text:setText(WFJ.Words.export({ images = images, audio = audio }, date()))
  for _, w in ipairs(f.imageRows) do show(w, images) end
  f:SetHeight(layAudio(images, offered, found))
  -- new text drops the selection; the box keeps its focus, so select it again for Cmd+C
  local box = f.text.box
  if box.HasFocus and box:HasFocus() then box:HighlightText() end
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
  local now = WFJ.Compat.call("GetTime") or 0
  if armedAt and now - armedAt <= ARM_SECONDS then
    armedAt = nil
    local n = WFJ.Words.clear() or 0
    button:setLabel(Text.get("words.clear"))
    fill()
    say("words.cleared", n)
  else
    armedAt = now
    button:setLabel(Text.get("words.clearArm"))
    -- the armed label goes back when the second click did not come in time
    local after = WFJ.Compat.resolve("C_Timer.After")
    if type(after) == "function" then
      after(ARM_SECONDS, function()
        if armedAt == now then armedAt = nil; button:setLabel(Text.get("words.clear")) end
      end)
    end
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
  -- no Copy button: the client blocks CopyToClipboard for addons (ADDON_ACTION_FORBIDDEN), so the selected text and
  -- Cmd+C / Ctrl+C are the way to copy
  local en, ja = Text.get("words.removeLast")
  f.removeLast = W.button(p, en, ja, 140, removeLast)
  f.removeLast:SetPoint("TOPLEFT", LEFT, -312)
  en, ja = Text.get("words.clear")
  f.clear = W.button(p, en, ja, 140, function(self) clear(self) end)
  f.clear:SetPoint("TOPLEFT", LEFT + 160, -312)
  en, ja = Text.get("words.images")
  f.images = W.checkbox(p, en, ja, LEFT, -346, INNER, function() fill() end)
  f.shotsLabel = W.label(p, "", "", LEFT, -378, INNER)
  W.setPair(f.shotsLabel, Text.get("words.shotsPath"))
  f.shotsPath = W.copyBox(p, LEFT, -396, INNER - 12, WordsWindow.SCREENSHOTS)
  f.ankiLabel = W.label(p, "", "", LEFT, -420, INNER)
  W.setPair(f.ankiLabel, Text.get("words.ankiPath"))
  f.ankiMac = W.copyBox(p, LEFT, -438, INNER - 12, WordsWindow.ANKI_MAC)
  f.ankiWin = W.copyBox(p, LEFT, -460, INNER - 12, WordsWindow.ANKI_WIN)
  -- shown only with Include images ticked
  f.imageRows = { f.shotsLabel.en, f.shotsLabel.ja, f.shotsPath, f.ankiLabel.en, f.ankiLabel.ja, f.ankiMac, f.ankiWin }
  en, ja = Text.get("words.audio")
  -- the audio rows are placed by layAudio, under whatever shows above them
  f.audio = W.checkbox(p, en, ja, LEFT, 0, INNER, function() fill() end)
  f.audioHint = W.label(p, "", "", LEFT, 0, INNER)
  W.setPair(f.audioHint, Text.get("words.audioHint"))
  f.ankiFolder = W.copyBox(p, LEFT, 0, INNER - 12, WordsWindow.ANKI_MAC)
  f.audioLines = W.scrollText(p, LEFT, 0, INNER, AUDIO_LINES)
  -- shown only with Include audio ticked
  f.audioRows = { f.audioHint.en, f.audioHint.ja, f.ankiFolder, f.audioLines }
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
WFJ.State.on("language", retitleIfShown)
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
WFJ.State.on("words", function() WordsWindow.refresh() end)
