-- UI/ChatWordsWindow.lua: the player's own chat words (docs/systems/chat-tools.md). A tool window the player opens
-- (the Words settings page, /wfj chatwords): add a Japanese word with its reading and meaning, or an English word
-- with its Japanese; the list of what was added; Remove for the row picked. The words live in the account's own
-- WFJ_ChatWords (Core/ChatWords), are looked up before every shipped list, and are never shipped.
local _, WFJ = ...
local Window = {}
WFJ.ChatWordsWindow = Window

local W, Text = WFJ.OptionsWidgets, WFJ.OptionsText

local WIDTH, HEIGHT, LEFT = 600, 470, 16
local INNER = WIDTH - 2 * LEFT
local ROW_H, ROWS, LEFT_COL = 20, 10, 170
local frame
local picked -- the list row picked for Remove: { word, lang }

local function pick(key, ...) return W.pick(Text.get(key, ...)) end

-- The player's words as list rows, Japanese words first, each group by word.
function Window.items()
  local own = WFJ.ChatWords.own()
  local items = {}
  local function add(lang, words, text)
    local keys = {}
    for word in pairs(words) do keys[#keys + 1] = word end
    table.sort(keys)
    for _, word in ipairs(keys) do
      items[#items + 1] = { left = word, text = text(words[word]), word = word, lang = lang, index = #items + 1 }
    end
  end
  add("ja", own.ja, function(e)
    return e.reading .. ((e.meaning or "") ~= "" and ("　" .. e.meaning) or "")
  end)
  add("en", own.en, function(e)
    return e.ja .. (e.reading ~= e.ja and ("（" .. e.reading .. "）") or "")
  end)
  return items
end

function Window.refresh()
  if not frame then return end
  local items = Window.items()
  frame.list:setItems(items)
  frame.empty:SetText(#items == 0 and pick("chat.words.empty") or "")
  WFJ.Font.set(frame.empty, WFJ.Font.PATH, 12, "")
  if picked and not (WFJ.ChatWords.own()[picked.lang] or {})[picked.word] then picked = nil end
  frame.remove:setLabel(picked and pick("chat.words.removeOne", picked.word) or pick("chat.words.remove"))
  frame.remove:SetEnabled(picked ~= nil)
end

-- → true when the word was kept
function Window.add(lang, word, a, b)
  local ok = WFJ.ChatWords.add(lang, word, a, b)
  if ok and WFJ.ChatCards then WFJ.ChatCards.clear() end
  Window.refresh()
  return ok
end

function Window.remove(word)
  local had = WFJ.ChatWords.remove(word)
  picked = nil
  Window.refresh()
  return had
end

local function input(parent, x, y, width)
  local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  box:SetSize(width, 20)
  box:SetPoint("TOPLEFT", x, y)
  box:SetAutoFocus(false)
  box:SetFont(WFJ.Font.PATH, 12, "")
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  return box
end

local function text(box)
  return ((box:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function caption(parent, key, x, y)
  local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  fs:SetPoint("TOPLEFT", x, y)
  fs.key = key
  return fs
end

local function relabel()
  if not frame then return end
  frame.title:SetText(pick("chat.words.title"))
  WFJ.Font.set(frame.title, WFJ.Font.PATH, 13, "")
  W.setPair(frame.explain, Text.get("chat.words.explain"))
  for _, fs in ipairs(frame.captions) do
    fs:SetText(pick(fs.key))
    WFJ.Font.set(fs, WFJ.Font.PATH, 11, "")
  end
  frame.addJa:setLabel(pick("chat.words.add"))
  frame.addEn:setLabel(pick("chat.words.add"))
  Window.refresh()
end

local function build()
  local f = W.toolWindow("WFJChatWordsWindow", WIDTH, HEIGHT)
  frame = f
  f.explain = W.label(f, "", "", LEFT, -70, INNER)
  f.captions = {}
  local function cap(key, x, y)
    local fs = caption(f, key, x, y)
    f.captions[#f.captions + 1] = fs
    return fs
  end
  -- a Japanese word: the word, how it is read, what it means
  cap("chat.words.ja", LEFT, -118)
  cap("chat.words.word", LEFT + 6, -136)
  cap("chat.words.reading", LEFT + 146, -136)
  cap("chat.words.meaning", LEFT + 286, -136)
  f.jaWord = input(f, LEFT + 6, -150, 130)
  f.jaReading = input(f, LEFT + 146, -150, 130)
  f.jaMeaning = input(f, LEFT + 286, -150, 190)
  f.addJa = W.button(f, "", nil, 80, function()
    if Window.add("ja", text(f.jaWord), text(f.jaReading), text(f.jaMeaning)) then
      f.jaWord:SetText(""); f.jaReading:SetText(""); f.jaMeaning:SetText("")
    end
  end)
  f.addJa:SetPoint("TOPLEFT", LEFT + 486, -149)
  -- an English word: the word and its Japanese
  cap("chat.words.en", LEFT, -184)
  cap("chat.words.word", LEFT + 6, -202)
  cap("chat.words.japanese", LEFT + 146, -202)
  f.enWord = input(f, LEFT + 6, -216, 130)
  f.enJa = input(f, LEFT + 146, -216, 330)
  f.addEn = W.button(f, "", nil, 80, function()
    if Window.add("en", text(f.enWord), text(f.enJa)) then
      f.enWord:SetText(""); f.enJa:SetText("")
    end
  end)
  f.addEn:SetPoint("TOPLEFT", LEFT + 486, -215)
  f.list = W.scrollList(f, LEFT, -250, INNER, ROWS * ROW_H, ROW_H, LEFT_COL, function(item)
    picked = { word = item.word, lang = item.lang }
    Window.refresh()
  end)
  f.empty = f:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  f.empty:SetPoint("TOPLEFT", LEFT + 6, -256)
  f.remove = W.button(f, "", nil, 140, function()
    if picked then Window.remove(picked.word) end
  end)
  f.remove:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", LEFT, 4)
  return f
end

function Window.open()
  if not frame then build() end
  picked = nil
  relabel()
  frame:Show()
  return frame
end

function Window.frame() return frame end

WFJ.State.on("language", function() if frame and frame:IsShown() then pcall(relabel) end end)
