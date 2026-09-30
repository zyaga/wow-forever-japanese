-- Core/Placeholders.lua: the player tokens the human quest corpus carries, expanded when the Japanese is applied.
-- Pure: the player arrives as a table (Main.lua reads the client). Tokens stay literal in data/.
--   {name}  → player.name (the client's own spelling of the character name)
--   {class} → the corpus's katakana class word, by classFile (UnitClass 2nd return); else the localized className
--   {race}  → the katakana race word, by raceFile (UnitRace 2nd return); else the localized raceName
--   <a/b>   → b for a female character (UnitSex 3), else a; ASCII word pairs only (English gender words the
--             translators left in; an emote such as <Sirraは…> is not a pair)
--   any other {word} → left literal and recorded once in Placeholders.unknown (distinct tokens; /wfj debug)
-- A token whose value is unavailable (no name yet, an unlisted class with no localized name) stays literal.
-- The katakana forms are the Classic plugin's (male and female identical there); class and race are prose words in
-- this corpus (katakana 380× vs Latin 94× in shipped quest lines), not proper names, which stay English.
local _, WFJ = ...
local Placeholders = {}
WFJ.Placeholders = Placeholders

Placeholders.KNOWN = { "name", "class", "race" }

Placeholders.CLASS = {
  WARRIOR = "ウォリアー", PALADIN = "パラディン", HUNTER = "ハンター", ROGUE = "ローグ", PRIEST = "プリースト",
  SHAMAN = "シャーマン", MAGE = "メイジ", WARLOCK = "ウォーロック", DRUID = "ドルイド",
}

Placeholders.RACE = {
  Human = "人間", Orc = "オーク", Dwarf = "ドワーフ", NightElf = "ナイトエルフ", Scourge = "アンデッド",
  Tauren = "トーレン", Gnome = "ノーム", Troll = "トロール",
}

Placeholders.unknown = {} -- set of distinct unknown {word} tokens met this session

local FEMALE = 3 -- UnitSex: 1 unknown · 2 male · 3 female
local known = {}
for _, word in ipairs(Placeholders.KNOWN) do known[word] = true end

local function nonEmpty(s)
  if type(s) == "string" and s ~= "" then return s end
  return nil
end

-- True when `text` could hold a token; lets a caller skip reading the client for token-free text.
function Placeholders.mayHaveTokens(text)
  return type(text) == "string" and (text:find("{", 1, true) ~= nil or text:find("<", 1, true) ~= nil)
end

-- Distinct unknown tokens met this session, sorted: → count, { "{foo}", … }.
function Placeholders.unknownTokens()
  local list = {}
  for token in pairs(Placeholders.unknown) do list[#list + 1] = token end
  table.sort(list)
  return #list, list
end

-- → expanded text, number of unknown {word} tokens left literal in this text
-- ASCII classes, not %a: %a follows the C locale in PUC Lua and could take high bytes of UTF-8 text.
function Placeholders.expand(text, player)
  if not Placeholders.mayHaveTokens(text) then
    return text, 0
  end
  player = player or {}
  local values = {
    name = nonEmpty(player.name),
    class = Placeholders.CLASS[player.classFile] or nonEmpty(player.className),
    race = Placeholders.RACE[player.raceFile] or nonEmpty(player.raceName),
  }
  local unknown = 0
  local out = text:gsub("{([A-Za-z]+)}", function(word)
    if not known[word] then
      unknown = unknown + 1
      Placeholders.unknown["{" .. word .. "}"] = true
      return nil -- keep the token literal
    end
    return values[word] -- nil keeps a known token literal when its value is unavailable
  end)
  out = out:gsub("<([A-Za-z]+)/([A-Za-z]+)>", function(male, female)
    if player.sex == FEMALE then return female end
    return male
  end)
  return out, unknown
end
