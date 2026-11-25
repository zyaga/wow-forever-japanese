-- Core/WordFrequency.lua: how often each word of the game's text is used (docs/systems/word-status.md), the read
-- path over WFJ.Data.freqJa, freqEn and grammar. Pure: no globals, no frames.
--   Frequency.count(lang)        → how many words the list holds
--   Frequency.rank(lang, key)    → the word's place, most used first (1 = the most used) | nil
--   Frequency.at(lang, rank)     → the word key at that place | nil
--   Frequency.uses(lang, key)    → { n, … } per kind of text, in Frequency.KINDS order | nil
--   Frequency.grammar(key)       → true for a Japanese grammar word (it starts as Ignored)
--   Frequency.forms(word)        → the keys of a Japanese dictionary form, one per reading | nil
--   Frequency.read(reading)      → the keys of the Japanese words read that way | nil
-- `lang` is "ja" or "en". A Japanese key is "dictionary form<TAB>its reading"; an English key is the lower-cased
-- word. Rows (generated, Data/Freq/): [key] = "q,g,b,u,i,s", one count per kind of text. The order is worked out
-- here, once per language: most used first, equal totals by key, so a new word changes one data file.
local _, WFJ = ...
local Frequency = {}
WFJ.WordFrequency = Frequency

Frequency.KINDS = { "quest", "gossip", "book", "ui", "item", "spell" }

local TYPE = { ja = "freqJa", en = "freqEn" }
local lists = {} -- lang → { order, rankOf, usesOf, forms, read }

local function build(lang)
  local list = lists[lang]
  if list then return list end
  list = { order = {}, rankOf = {}, usesOf = {}, forms = {}, read = {} }
  local totals = {}
  for key, row in pairs(WFJ.Data[TYPE[lang]] or {}) do
    local uses, total = {}, 0
    for digits in row:gmatch("%d+") do
      local n = tonumber(digits)
      uses[#uses + 1] = n
      total = total + n
    end
    list.order[#list.order + 1] = key
    list.usesOf[key], totals[key] = uses, total
    if lang == "ja" then
      local word, reading = key:match("^([^\t]+)\t([^\t]+)$")
      if word then
        local forms = list.forms[word]
        if not forms then forms = {}; list.forms[word] = forms end
        forms[#forms + 1] = key
        local read = list.read[reading]
        if not read then read = {}; list.read[reading] = read end
        read[#read + 1] = key
      end
    end
  end
  table.sort(list.order, function(a, b)
    if totals[a] ~= totals[b] then return totals[a] > totals[b] end
    return a < b
  end)
  for rank, key in ipairs(list.order) do list.rankOf[key] = rank end
  lists[lang] = list
  return list
end

function Frequency.count(lang) return #build(lang).order end
function Frequency.rank(lang, key) return build(lang).rankOf[key] end
function Frequency.at(lang, rank) return build(lang).order[rank] end
function Frequency.uses(lang, key) return build(lang).usesOf[key] end
function Frequency.grammar(key) return WFJ.Data.grammar[key] ~= nil end
function Frequency.forms(word) return build("ja").forms[word] end
function Frequency.read(reading) return build("ja").read[reading] end
