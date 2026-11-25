-- Core/WordMarks.lua: which word of a text takes which mark (docs/systems/word-status.md). Pure: no globals, no
-- frames. The drawing is UI/WordMarks and UI/ChatMarks.
--   Marks.sentences(text, english) → { { first, last }, … }
--   Marks.plan(text, words, opts)  → { [i] = { underline = "unknown" | "learning" | nil, highlight = bool } }
-- `words`: { { first, last, lang, key }, … } in the text's byte positions; a word with no key takes no mark.
-- `opts`: { underline = bool (unknown words), learning = bool (learning words),
-- highlight = "off" | "common" | "commonNew" | "new", english = bool }.
-- The underline shows a word's status. The highlight picks out unknown words: the ones to learn next, the one
-- unknown word of a sentence that has no other, or the words that are both.
local _, WFJ = ...
local Marks = {}
WFJ.WordMarksPlan = Marks

local ENDS = { ["。"] = true, ["！"] = true, ["？"] = true, ["!"] = true, ["?"] = true, ["\n"] = true }

-- Sentences are cut after 。！？!? and at a line break; an English text after a full stop too.
function Marks.sentences(text, english)
  local out, s, i, n = {}, 1, 1, #text
  while i <= n do
    local c = text:byte(i)
    local j = i + ((c >= 0xF0 and 4) or (c >= 0xE0 and 3) or (c >= 0xC0 and 2) or 1) - 1
    local ch = text:sub(i, j)
    if ENDS[ch] or (english and ch == ".") then
      local e = ch == "\n" and i - 1 or j
      if e >= s then out[#out + 1] = { s, e } end
      s = j + 1
    end
    i = j + 1
  end
  if s <= n then out[#out + 1] = { s, n } end
  return out
end

-- → { [i] = true } for each word that is the one unknown word of its sentence
local function alone(text, words, statuses, english)
  local bounds, unknown, out = Marks.sentences(text, english), {}, {}
  for i, w in ipairs(words) do
    if statuses[i] == "unknown" then
      for at, b in ipairs(bounds) do
        if w.first >= b[1] and w.first <= b[2] then
          local u = unknown[at] or { n = 0 }
          unknown[at] = u
          u.n, u.word = u.n + 1, i
          break
        end
      end
    end
  end
  for _, u in pairs(unknown) do
    if u.n == 1 then out[u.word] = true end
  end
  return out
end

function Marks.plan(text, words, opts)
  local Status = WFJ.WordStatus
  local statuses, out = {}, {}
  for i, w in ipairs(words) do
    statuses[i] = w.key and Status.get(w.lang, w.key) or nil
  end
  local mode = opts.highlight
  local only = (mode == "new" or mode == "commonNew") and alone(text, words, statuses, opts.english) or nil
  for i, w in ipairs(words) do
    local status = statuses[i]
    local mark = {}
    if (status == "unknown" and opts.underline) or (status == "learning" and opts.learning) then
      mark.underline = status
    end
    if status == "unknown" then
      if mode == "common" then
        mark.highlight = Status.learnNext(w.lang, w.key)
      elseif mode == "commonNew" then
        mark.highlight = only[i] == true and Status.learnNext(w.lang, w.key)
      elseif mode == "new" then
        mark.highlight = only[i] == true
      end
    end
    mark.highlight = mark.highlight or false
    out[i] = mark
  end
  return out
end
