-- Core/ChatPhrases.lua: the phrase book's phrases and the mark they travel with (docs/systems/chat-tools.md).
-- A phrase is typed as a middle dot and its English ("· Hello!"). To a player without the addon that reads as a
-- bullet and plain English. With the addon, a dot (· or ・) followed by exactly one of the book's phrases, in
-- either language, is that phrase: the dot is drawn as a gold 文 and the phrase is shown in the reader's language.
-- A dot before anything else, and a phrase with no dot, stay as typed. Pure: no globals, no frames. The message
-- filter and the reveal key are UI/ChatPhraseLines; the book is UI/PhraseBook.
--   ChatPhrases.list()                  → { { id, topic, en, ja } … } in id order
--   ChatPhrases.topics()                → { topic … } in the order the phrases first name them
--   ChatPhrases.typed(phrase)           → what a click types for it
--   ChatPhrases.translate(msg, "ja"|"en") → the message with each marked phrase in that language | nil when none
--   ChatPhrases.keep(shown, raw)        remembers a changed message with the message as it arrived
--   ChatPhrases.sent(text)              → raw, first, last: the kept message whose shown form `text` holds
-- Rows (generated, Data/Chat/ChatList.lua): [id] = "topic<TAB>English<TAB>Japanese".
local _, WFJ = ...
local ChatPhrases = {}
WFJ.ChatPhrases = ChatPhrases

local DOT, JA_DOT = "\194\183", "\227\131\187" -- U+00B7, U+30FB
ChatPhrases.MARK = "|cffffd200文|r "
ChatPhrases.KEPT = 200 -- changed messages remembered for the reveal key

local list, byText

local function build()
  list, byText = {}, {}
  local ids = {}
  for id in pairs(WFJ.Data.phrase) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local topic, en, ja = WFJ.Data.phrase[id]:match("^([^\t]+)\t([^\t]+)\t([^\t]+)$")
    if topic then
      local p = { id = id, topic = topic, en = en, ja = ja }
      list[#list + 1] = p
      byText[#byText + 1] = { text = en:lower(), phrase = p }
      byText[#byText + 1] = { text = ja, phrase = p }
    end
  end
  -- longest first, so a phrase that starts another never wins over it
  table.sort(byText, function(x, y)
    if #x.text ~= #y.text then return #x.text > #y.text end
    return x.text < y.text
  end)
end

function ChatPhrases.list()
  if not list then build() end
  return list
end

function ChatPhrases.topics()
  local out, seen = {}, {}
  for _, p in ipairs(ChatPhrases.list()) do
    if not seen[p.topic] then
      seen[p.topic] = true
      out[#out + 1] = p.topic
    end
  end
  return out
end

function ChatPhrases.typed(phrase)
  return DOT .. " " .. phrase.en
end

-- The phrase that starts at byte `i` of the lower-cased message (spaces after the dot skipped).
-- → phrase, its last byte
local function phraseAt(lower, i)
  while lower:byte(i) == 32 do i = i + 1 end
  for _, e in ipairs(byText) do
    if lower:sub(i, i + #e.text - 1) == e.text then return e.phrase, i + #e.text - 1 end
  end
  return nil
end

function ChatPhrases.translate(msg, direction)
  if type(msg) ~= "string" or msg == "" then return nil end
  if not list then build() end
  local lower = msg:lower() -- ASCII letters only; every other byte, and so every position, is unchanged
  local out, pos, changed = {}, 1, false
  while true do
    local a1, a2 = msg:find(DOT, pos, true)
    local b1, b2 = msg:find(JA_DOT, pos, true)
    local s, e
    if a1 and (not b1 or a1 < b1) then s, e = a1, a2 else s, e = b1, b2 end
    if not s then break end
    local p, last = phraseAt(lower, e + 1)
    if p then
      out[#out + 1] = msg:sub(pos, s - 1)
      out[#out + 1] = ChatPhrases.MARK .. (direction == "en" and p.en or p.ja)
      pos, changed = last + 1, true
    else
      out[#out + 1] = msg:sub(pos, e)
      pos = e + 1
    end
  end
  if not changed then return nil end
  out[#out + 1] = msg:sub(pos)
  return table.concat(out)
end

-- ── What was sent (for the reveal key) ───────────────────────────────────────
local kept, keptAt = {}, 0

function ChatPhrases.keep(shown, raw)
  if type(shown) ~= "string" or type(raw) ~= "string" or shown == raw then return end
  for _, k in ipairs(kept) do
    if k.shown == shown and k.raw == raw then return end
  end
  keptAt = keptAt % ChatPhrases.KEPT + 1
  kept[keptAt] = { shown = shown, raw = raw }
end

function ChatPhrases.sent(text)
  if type(text) ~= "string" then return nil end
  for _, k in ipairs(kept) do
    local first, last = text:find(k.shown, 1, true)
    if first then return k.raw, first, last end
  end
  return nil
end
