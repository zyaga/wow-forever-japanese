-- UI/ChatCards.lua: word cards on chat lines (docs/systems/chat-tools.md). UI/ChatLines says which chat line the
-- mouse is on; this asks that line's own FontString which character is under the mouse
-- (FindCharacterIndexAtCoordinate, as the client's own text selection does [verified: forever
-- blizzard_sharedxml/scrollingmessageframe.lua:552–570, GetScaledCursorPosition :572–576]), Core/ChatWords finds
-- the word there, and UI/Readings draws it as on every word-card surface: the gold tint, the card or the reading
-- box (following the meanings setting), and the save click. Japanese first: Japanese words. English first: English
-- words. Never while the reveal key is held, or with translation, word cards or `chat.cards` off. The chat line
-- itself is never changed. A word is saved with what the player typed as its sentence.
--   ChatCards.shown()  → the word showing now, or nil
--   ChatCards.clear()  takes the card down (the mouse is still on the word: the next look shows it again)
local _, WFJ = ...
local Cards = {}
WFJ.ChatCards = Cards

local Compat = WFJ.Compat
local SURFACE = "chat.cards"
local CANDIDATES = { cursor = { "GetCursorPosition" } }

-- The cover UI/Readings draws on and UI/WordSave saves from: one frame, laid over the line the word is on.
local cover
local at -- where the shown word is: { line, text, first, last } in the chat line's own bytes

local function ensureCover()
  if cover then return cover end
  cover = CreateFrame("Frame", nil, Compat.resolve("UIParent"))
  cover:SetFrameStrata("MEDIUM")
  cover.tints = {}
  cover.kind, cover.id, cover.surface = "chat", "chat", "chat" -- what a saved word is kept under
  cover:Hide()
  return cover
end

function Cards.clear()
  if cover and at then
    WFJ.ReadingView.clearHover(cover)
    cover.words, cover.pressWord = nil, nil
    cover:Hide()
  end
  at = nil
end
local clear = Cards.clear

-- The sentence a chat word is saved with: the stretch of the line it sits in, from where the player's own text
-- starts when the line is a typed one (the sender and the line's opening words are no part of it).
-- → sentence, the word's first and last byte in it | nil
function Cards.sentence(line, text, first, last)
  for _, r in ipairs(WFJ.ChatWords.runs(text)) do
    if first >= r.first and last <= r.last then
      local from = r.first
      local typed = WFJ.ChatLines.typedPart(line, text)
      if typed then from = math.max(from, #text - #typed + 1) end
      if first < from then return nil end
      return text:sub(from, r.last), first - from + 1, last - from + 1
    end
  end
  return nil
end

local function show(line, text, w)
  -- the one guarded call for a word's place on screen (a span that splits a character makes the client exit)
  local areas = WFJ.ReadingView.chatSpanAreas(line, text, w.first, w.last)
  if type(areas) ~= "table" or WFJ.ChatLines.secret(areas) or not areas[1] then return false end
  clear()
  local c = ensureCover()
  c:ClearAllPoints()
  c:SetAllPoints(line)
  c:Show()
  local rects = {}
  for i, a in ipairs(areas) do rects[i] = { left = a.left, bottom = a.bottom, width = a.width, height = a.height } end
  -- the word as UI/Readings shows it and UI/WordSave saves it: its place is counted in the sentence it is saved with
  local sentence, first, last = Cards.sentence(line, text, w.first, w.last)
  local word = { word = w.word, reading = w.reading, card = w.card, rects = rects,
    first = first or w.first, last = last or w.last, name = sentence == nil } -- no sentence: shown, never saved
  c.fs, c.text, c.words = line, sentence or text, { word }
  c.wasDown = WFJ.ReadingView.buttonDown() -- a press that started before the word showed is not a click on it
  WFJ.ReadingView.showHover(c, word)
  at = { line = line, text = text, first = w.first, last = w.last }
  return true
end

local function cardsOn()
  local S = WFJ.State
  -- only while the direction's own language shows: the reveal key puts the other one on screen, and a chat line
  -- is not rewritten for it
  local own = S.showsEnglish() == (S.direction == "en")
  return S.enabled and own and WFJ.ReadingView.enabled and WFJ.Settings.get("chat.cards") == true
end

local function wordAt(text, i)
  if WFJ.State.direction == "en" then return WFJ.ChatWords.englishAt(text, i) end
  return WFJ.ChatWords.japaneseAt(text, i)
end

-- UI/ChatLines' listener.
function Cards.follow(frame, line, text)
  if not line or not cardsOn() then return clear() end
  local cursor = Compat.get(SURFACE, "cursor")
  if type(cursor) ~= "function" then return clear() end
  local cx, cy = cursor()
  local scale = frame:GetEffectiveScale()
  local ok, i, inside = pcall(line.FindCharacterIndexAtCoordinate, line, cx / scale, cy / scale)
  if not (ok and inside and type(i) == "number") or WFJ.ChatLines.secret(i) then return clear() end
  -- still on the word that is showing: nothing to find again
  if at and at.line == line and at.text == text and i >= at.first and i <= at.last then
    return WFJ.ReadingView.poll(cover)
  end
  local w = wordAt(text, i)
  if not (w and show(line, text, w)) then return clear() end
end

function Cards.shown() return at end

function Cards.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  WFJ.ChatLines.onLine(Cards.follow)
  -- a change of the player's own words may change the card of the word showing
  WFJ.ChatWords.onChange = clear
  return true
end

WFJ.State.on("chat", clear)
WFJ.State.on("glosses", clear) -- meanings on or off: the next look shows the card or the reading box
WFJ.State.on("direction", clear) -- the other language's words take the cards now
