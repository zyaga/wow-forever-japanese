-- UI/ChatCards.lua: word cards on chat lines (docs/systems/chat-tools.md). Nothing is hooked and no chat line is
-- changed. While the mouse is over a chat frame, a timer asks the line's own FontString which character is under
-- it (FindCharacterIndexAtCoordinate, as the client's own text selection does [verified: forever
-- blizzard_sharedxml/scrollingmessageframe.lua:552–570, GetScaledCursorPosition :572–576]), Core/ChatWords finds
-- the word there, and the word card shows over it. Japanese first: Japanese words. English first: English words.
-- Never while the reveal key is held, with translation or word cards off, or on a line whose text the client keeps
-- secret (chat messaging lockdown). The save click saves the word with what the player typed as its sentence.
--   ChatCards.look()            one look at the mouse (the timer's step; specs call it)
--   ChatCards.onLine(fn)        fn(line, text) for the readable line under the mouse, fn(nil) when there is none
--   ChatCards.typedPart(line, text) → what a player typed in that line | nil (not a typed line, or not shaped so)
local _, WFJ = ...
local Cards = {}
WFJ.ChatCards = Cards

local Compat = WFJ.Compat
local SURFACE = "chat.cards"
local CANDIDATES = { frames = { "CHAT_FRAMES" }, typeInfo = { "ChatTypeInfo" }, isSecret = { "issecretvalue" },
  cursor = { "GetCursorPosition" }, buttonDown = { "IsMouseButtonDown" } }

Cards.EVERY = 0.04 -- seconds between looks
Cards.FADED = 0.2 -- a line fainter than this has faded out: no card on text the player cannot see
local TINT = { 1, 0.82, 0, 0.22 } -- the word under the mouse, as on every word-card surface

local anchor
local shown -- { line, text, first, last, word }
local wasDown, pressed = false, nil
local listeners = {}

local function secret(v)
  local f = Compat.get(SURFACE, "isSecret")
  return type(f) == "function" and f(v) and true or false
end

function Cards.onLine(fn) listeners[#listeners + 1] = fn end

local function tell(line, text)
  for _, fn in ipairs(listeners) do fn(line, text) end
end

-- ── Which lines a player typed ──────────────────────────────────────────────

-- The chat types a player types into. The table of chat types is read by name: walking it finds no entries on this
-- client.
Cards.TYPED = { "SAY", "YELL", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING", "GUILD", "OFFICER",
  "WHISPER", "WHISPER_INFORM", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER", "BN_WHISPER", "BN_WHISPER_INFORM",
  "COMMUNITIES_CHANNEL", "CHANNEL" }
Cards.CHANNELS = 20 -- CHANNEL1 … CHANNEL20 have a type of their own

local typedIds
local function typedLine(line)
  local info = line.messageInfo
  -- the chat type is the first value the chat frame stores with a line [verified: forever
  -- blizzard_chatframebase/mainline/chatframeoverrides.lua:416, AddMessage(text, r, g, b, info.id)]
  local id = type(info) == "table" and type(info.extraData) == "table" and info.extraData[1] or nil
  local types = Compat.get(SURFACE, "typeInfo")
  if id == nil or secret(id) or type(types) ~= "table" then return false end
  if not typedIds then
    typedIds = {}
    local names = {}
    for _, name in ipairs(Cards.TYPED) do names[#names + 1] = name end
    for i = 1, Cards.CHANNELS do names[#names + 1] = "CHANNEL" .. i end
    for _, name in ipairs(names) do
      local t = types[name]
      if type(t) == "table" and t.id ~= nil then typedIds[t.id] = true end
    end
  end
  return typedIds[id] == true
end

function Cards.typedPart(line, text)
  if type(line) ~= "table" or not typedLine(line) then return nil end
  return WFJ.ChatWords.typedPart(text)
end

-- ── The card ───────────────────────────────────────────────────────────────

local function ensureAnchor()
  if anchor then return anchor end
  anchor = CreateFrame("Frame", nil, Compat.resolve("UIParent"))
  anchor:SetFrameStrata("MEDIUM")
  anchor.tints = {}
  anchor:Hide()
  return anchor
end

local function clear()
  if anchor then
    for _, t in ipairs(anchor.tints) do t:Hide() end
    anchor:Hide()
    if WFJ.ReadingPopup then WFJ.ReadingPopup.hide(anchor) end
  end
  shown = nil
end
Cards.clear = clear

local function showWord(line, text, w)
  if shown and shown.line == line and shown.text == text and shown.first == w.first then return true end
  -- the one guarded call for a word's place on screen (a span that splits a character makes the client exit); a
  -- chat line's indices count its escape sequences
  local areas = WFJ.ReadingView.spanAreas(line, text, w.first, w.last, "chat", true)
  if type(areas) ~= "table" or secret(areas) or not areas[1] then return false end
  clear()
  local a = ensureAnchor()
  a:ClearAllPoints()
  a:SetAllPoints(line)
  a:Show()
  for i, r in ipairs(areas) do
    local t = a.tints[i]
    if not t then
      t = a:CreateTexture(nil, "BACKGROUND")
      a.tints[i] = t
    end
    t:SetColorTexture(TINT[1], TINT[2], TINT[3], TINT[4])
    t:ClearAllPoints()
    t:SetPoint("BOTTOMLEFT", a, "BOTTOMLEFT", r.left, r.bottom)
    t:SetSize(math.max(r.width, 1), math.max(r.height, 1))
    t:Show()
  end
  local _, size = line:GetFont()
  local r = areas[1]
  local hint = WFJ.ReadingView.hint and WFJ.ReadingView.hint() or nil
  WFJ.ReadingPopup.show(a, r.left + r.width / 2, r.bottom + r.height + 2, w, w.card or w.gloss, size, hint)
  shown = { line = line, text = text, first = w.first, last = w.last, word = w }
  return true
end

-- ── The save click ─────────────────────────────────────────────────────────

-- The sentence a chat word is saved with: the stretch of the line it sits in, from where the player's own text
-- starts when the line is a typed one (the sender and the line's opening words are no part of it).
-- → sentence, the word's first and last byte in it | nil
function Cards.sentence(line, text, first, last)
  for _, r in ipairs(WFJ.ChatWords.runs(text)) do
    if first >= r.first and last <= r.last then
      local from = r.first
      local typed = Cards.typedPart(line, text)
      if typed then from = math.max(from, #text - #typed + 1) end
      if first < from then return nil end
      return text:sub(from, r.last), first - from + 1, last - from + 1
    end
  end
  return nil
end

-- A press and a release on the same word, with the save click's modifiers held (UI/WordSave decides).
local function save()
  local s = shown
  if not s or not WFJ.WordSave then return nil end
  local sentence, first, last = Cards.sentence(s.line, s.text, s.first, s.last)
  if not sentence then return nil end
  local a, w = anchor, s.word
  -- the cover UI/WordSave expects: what the entry is saved under, and the tints it flashes
  a.kind, a.id, a.surface, a.fs, a.text = "chat", "chat", "chat", s.line, sentence
  return WFJ.WordSave.release(a, { word = w.word, reading = w.reading, first = first, last = last,
    card = w.card or w.gloss })
end

local function poll()
  local isDown = Compat.get(SURFACE, "buttonDown")
  local down = type(isDown) == "function" and isDown("LeftButton") == true
  if down and not wasDown then
    pressed = shown and shown.first or nil
  elseif not down and wasDown then
    if pressed and shown and shown.first == pressed then save() end
    pressed = nil
  end
  wasDown = down
end

-- ── The look ───────────────────────────────────────────────────────────────

local function wordAt(text, i)
  if WFJ.State.direction == "en" then return WFJ.ChatWords.englishAt(text, i) end
  return WFJ.ChatWords.japaneseAt(text, i)
end

local function cardsOn()
  local S = WFJ.State
  return S.enabled and not S.modifierHeld and WFJ.ReadingView.enabled and WFJ.Settings.get("chat.cards") == true
end

-- The readable chat line under the mouse. → frame, line, text | nil
local function lineUnderMouse()
  local names = Compat.get(SURFACE, "frames")
  if type(names) ~= "table" then return nil end
  for _, name in ipairs(names) do
    local f = Compat.resolve(name)
    if type(f) == "table" and type(f.visibleLines) == "table" and f:IsVisible() and f:IsMouseOver() then
      for _, line in ipairs(f.visibleLines) do
        if line:IsVisible() and line:GetAlpha() > Cards.FADED and line:IsMouseOver() then
          local text = line:GetText()
          if type(text) == "string" and not secret(text) and text ~= "" then return f, line, text end
        end
      end
    end
  end
  return nil
end

function Cards.look()
  local f, line, text = lineUnderMouse()
  tell(line, text)
  if not line or not cardsOn() then
    clear()
    return nil
  end
  local cursor = Compat.get(SURFACE, "cursor")
  if type(cursor) ~= "function" then return nil end
  local cx, cy = cursor()
  local scale = f:GetEffectiveScale()
  local ok, i, inside = pcall(line.FindCharacterIndexAtCoordinate, line, cx / scale, cy / scale)
  local w = ok and inside and type(i) == "number" and not secret(i) and wordAt(text, i) or nil
  if w and showWord(line, text, w) then
    poll()
    return w
  end
  clear()
  return nil
end

function Cards.shown() return shown end

function Cards.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  if Cards.driver then return false end
  Cards.driver = CreateFrame("Frame")
  local since = 0
  Cards.driver:SetScript("OnUpdate", function(_, elapsed)
    since = since + elapsed
    if since < Cards.EVERY then return end
    since = 0
    Cards.look()
  end)
  return true
end

WFJ.State.on("chat", clear)
