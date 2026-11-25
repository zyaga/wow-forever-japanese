-- UI/ChatMarks.lua: the word status marks on chat lines (docs/systems/word-status.md, docs/systems/chat-tools.md).
-- With the chat place on, every word Core/ChatWords finds on a visible, readable chat line takes the marks
-- UI/WordMarks draws on a cover: an underline by status, the highlight the setting picks. Nothing is hooked and no
-- chat line is changed: a timer looks at the visible lines, and each line that shows new text gets an overlay of
-- its own with the marks on it. A line that has faded out, a line whose text the client keeps secret, a link's
-- label and an escape sequence take none.
local _, WFJ = ...
local ChatMarks = {}
WFJ.ChatMarks = ChatMarks

local Compat = WFJ.Compat

ChatMarks.EVERY = 0.25 -- seconds between looks

local overlays = setmetatable({}, { __mode = "k" }) -- chat line → its overlay frame
local drawnAt = -1 -- the status version the overlays were last drawn for

local function on()
  local S = WFJ.State
  -- only while the direction's own language shows, as the chat cards
  local own = S.showsEnglish() == (S.direction == "en")
  return S.enabled and own and WFJ.ReadingView.enabled and WFJ.Settings.get("marks.chat") == true
end

-- Every word of a chat line: → { { first, last, word, reading, card }, … } in the line's own bytes.
function ChatMarks.words(text, english)
  local Words = WFJ.ChatWords
  local find = english and Words.englishAt or Words.japaneseAt
  local out = {}
  for _, run in ipairs(Words.runs(text)) do
    local i = run.first
    while i <= run.last do
      local w = find(text, i)
      if w and w.last >= i then
        out[#out + 1] = w
        i = w.last + 1
      else
        local c = text:byte(i)
        i = i + ((c >= 0xF0 and 4) or (c >= 0xE0 and 3) or (c >= 0xC0 and 2) or 1)
      end
    end
  end
  return out
end

local function clear(overlay)
  for _, t in ipairs(overlay.markTex or {}) do t:Hide() end
  overlay.text = nil
  overlay:Hide()
end

local function draw(line, text)
  local overlay = overlays[line]
  if not overlay then
    overlay = CreateFrame("Frame", nil, Compat.resolve("UIParent"))
    overlay:SetFrameStrata("MEDIUM")
    overlays[line] = overlay
  end
  overlay:ClearAllPoints()
  overlay:SetAllPoints(line)
  overlay.text = text
  local english = WFJ.State.direction == "en"
  local words, list = {}, {}
  for _, w in ipairs(ChatMarks.words(text, english)) do
    -- the one guarded call for a word's place on screen (a span that splits a character makes the client exit)
    local areas = WFJ.ReadingView.chatSpanAreas(line, text, w.first, w.last)
    if type(areas) == "table" and not WFJ.ChatLines.secret(areas) and areas[1] then
      local rects = {}
      for i, a in ipairs(areas) do
        rects[i] = { left = a.left, bottom = a.bottom, width = a.width, height = a.height }
      end
      local lang, key = WFJ.WordStatus.keyOf(w)
      words[#words + 1] = { rects = rects }
      list[#list + 1] = { first = w.first, last = w.last, lang = lang, key = key }
    end
  end
  local plan = WFJ.WordMarksPlan.plan(text, list, { underline = WFJ.Settings.get("marks.underline"),
    highlight = WFJ.Settings.get("marks.highlight"), english = english })
  overlay:Show()
  return WFJ.WordMarks.paint(overlay, words, plan)
end

-- One look at the chat frames: each visible, readable line shows the marks for the text it holds now.
function ChatMarks.look()
  if not on() then
    for _, overlay in pairs(overlays) do if overlay.text then clear(overlay) end end
    return 0
  end
  local version = WFJ.WordStatus.version()
  local redraw = version ~= drawnAt
  drawnAt = version
  local names = Compat.resolve("CHAT_FRAMES")
  local live, drawn = {}, 0
  for _, name in ipairs(type(names) == "table" and names or {}) do
    local f = Compat.resolve(name)
    if type(f) == "table" and type(f.visibleLines) == "table" and f:IsVisible() then
      for _, line in ipairs(f.visibleLines) do
        local text = line:IsVisible() and line:GetAlpha() > WFJ.ChatLines.FADED and line:GetText() or nil
        if type(text) == "string" and text ~= "" and not WFJ.ChatLines.secret(text) then
          live[line] = true
          local overlay = overlays[line]
          if redraw or not overlay or overlay.text ~= text then
            draw(line, text)
            drawn = drawn + 1
          end
        end
      end
    end
  end
  for line, overlay in pairs(overlays) do
    if overlay.text and not live[line] then clear(overlay) end
  end
  return drawn
end

local function follow()
  drawnAt = -1 -- a setting moved: every line is drawn again
  local want = WFJ.State.enabled and WFJ.Settings.get("marks.chat") == true
  if ChatMarks.driver then
    if want then ChatMarks.driver:Show() else ChatMarks.driver:Hide() end
  end
  if not want then ChatMarks.look() end -- takes the overlays down
end

function ChatMarks.init()
  if ChatMarks.driver then return false end
  ChatMarks.driver = CreateFrame("Frame")
  local since = 0
  ChatMarks.driver:SetScript("OnUpdate", function(_, elapsed) -- a hidden frame gets no updates
    since = since + elapsed
    if since < ChatMarks.EVERY then return end
    since = 0
    ChatMarks.look()
  end)
  WFJ.State.on("wordMarks", follow)
  WFJ.State.on("enabled", follow)
  follow()
  return true
end
