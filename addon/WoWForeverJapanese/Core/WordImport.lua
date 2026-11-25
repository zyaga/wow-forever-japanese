-- Core/WordImport.lua: marking a pasted list of words, and the player's statuses as text (docs/systems/
-- word-status.md). Pure: no globals, no frames. The window is UI/KnownWordsWindow.
--   Import.match(lang, piece)        → the word keys a pasted piece stands for | nil
--   Import.apply(lang, text, status) → { marked, already, kept, missing = { piece, … } }
--   Import.export(lang)              → one line per word the player set a status on
-- A pasted text is words in any mix of commas, spaces, tabs, new lines and Japanese punctuation. Furigana brackets
-- and HTML tags are dropped, and so is everything not of the language. A Japanese piece is matched as a dictionary
-- form (in every reading the game has for it), then as a form the game's text uses, then with a polite or past
-- ending removed, then, when it is all kana, as the reading of exactly one dictionary form. A line that is
-- "word<TAB>reading" of one game word (an exported line, a two-column list) is that word exactly, and a third
-- column naming a status sets that status. A word the player set by hand keeps its status.
local _, WFJ = ...
local Import = {}
WFJ.WordImport = Import

local STATUSES = { known = true, learning = true, ignored = true, unknown = true }
-- the endings a pasted verb or adjective may carry beyond a form the game's text uses, longest first
local ENDINGS = { "ませんでした", "ましょう", "ました", "ません", "なかった", "たかった", "ます", "たい", "ない",
  "て", "た" }
local SEPARATORS = { "、", "。", "・", "　", "「", "」", "（", "）", "，", "；", "：", "／", "〜" }

-- the keys of the dictionary form behind a form the game's text uses
local function fromForm(piece)
  local F = WFJ.WordFrequency
  local row = WFJ.Data.chatja[piece]
  if type(row) ~= "string" then return nil end
  local reading, n = row:match("^([^=]+)=?(%d*)$")
  local g = WFJ.Glosses and WFJ.Glosses.get(tonumber(n))
  if g then return F.forms(g.lemma) or { g.lemma .. "\t" .. g.lemmaReading } end
  local key = reading and (piece .. "\t" .. reading)
  return key and F.rank("ja", key) and { key } or nil
end

local function kana(piece)
  return piece:find("^[\227][\129-\131]") ~= nil and not piece:find("[\228-\233]")
end

function Import.match(lang, piece)
  local F = WFJ.WordFrequency
  if lang == "en" then
    local key = WFJ.WordStatus.englishKey(piece)
    return F.rank("en", key) and { key } or nil
  end
  local keys = F.forms(piece) or fromForm(piece)
  if keys then return keys end
  for _, ending in ipairs(ENDINGS) do
    if #piece > #ending and piece:sub(-#ending) == ending then
      keys = fromForm(piece:sub(1, #piece - #ending))
      if keys then return keys end
    end
  end
  if kana(piece) then
    local read = F.read(piece)
    if read and #read == 1 then return read end
  end
  return nil
end

-- a line's pieces: runs of the language's own characters
local function pieces(lang, line)
  if lang == "en" then
    local s = line:gsub("[^%a']+", " ")
    return s:gmatch("%S+")
  end
  local s = line:gsub("[%z\1-\127]+", " ")
  for _, sep in ipairs(SEPARATORS) do s = s:gsub(sep, " ") end
  return s:gmatch("%S+")
end

-- A line that names one word exactly: "word<TAB>reading[<TAB>status]" (English: "word[<TAB>status]" with a status).
-- → key, status | nil
local function exact(lang, line)
  local a, b, c = line:match("^%s*([^\t]+)\t([^\t]*)\t?([^\t]*)")
  if not a then return nil end
  if lang == "en" then
    local key = a:lower()
    if STATUSES[b] and WFJ.WordFrequency.rank("en", key) then return key, b end
    return nil
  end
  local key = a .. "\t" .. b
  if WFJ.WordFrequency.rank("ja", key) then return key, STATUSES[c] and c or nil end
  return nil
end

function Import.apply(lang, text, status)
  local Status = WFJ.WordStatus
  local out = { marked = 0, already = 0, kept = 0, missing = {} }
  if type(text) ~= "string" or (status ~= "known" and status ~= "ignored") or Status.readonly() then return out end
  local seenPiece, seenKey = {}, {}
  local function mark(key, to)
    if seenKey[key] then return end
    seenKey[key] = true
    local own = Status.own(lang, key)
    if own == to or (own == nil and Status.get(lang, key) == to) then
      out.already = out.already + 1
    elseif own ~= nil then
      out.kept = out.kept + 1 -- set by hand to something else
    else
      Status.set(lang, key, to)
      out.marked = out.marked + 1
    end
  end
  Status.batch(function()
    for raw in (text .. "\n"):gmatch("([^\r\n]*)[\r\n]") do
      local line = raw:gsub("%b[]", ""):gsub("%b<>", " ")
      local key, lineStatus = exact(lang, line)
      if key then
        mark(key, lineStatus or status)
      else
        for piece in pieces(lang, line) do
          if not seenPiece[piece] then
            seenPiece[piece] = true
            local keys = Import.match(lang, piece)
            if keys then
              for _, k in ipairs(keys) do mark(k, status) end
            else
              out.missing[#out.missing + 1] = piece
            end
          end
        end
      end
    end
  end)
  Status.noteImport(lang, { marked = out.marked, already = out.already, kept = out.kept, missing = #out.missing })
  return out
end

-- One line per word the player set a status on: "word<TAB>reading<TAB>status" (English: "word<TAB>status"),
-- sorted. Pasted into the import, each line sets that word to that status.
function Import.export(lang)
  local lines = {}
  for key, status in pairs(WFJ.WordStatus.entries(lang)) do lines[#lines + 1] = key .. "\t" .. status end
  table.sort(lines)
  return table.concat(lines, "\n")
end
