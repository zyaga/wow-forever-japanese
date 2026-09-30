-- Core/Normalize.lua: normalize_v1, the Lua 5.1 twin of pipeline/wfj/core/normalize.py (ADR-005).
-- Steps 2..7 of the spec; step 1 (NFC) is repo-side only: the client cannot normalize, and WoW text is NFC.
-- No bitwise ops, no libraries. Must stay byte-identical to the Python side: vectors/hash_vectors.lua is the contract.
local _, WFJ = ...
local Normalize = {}
WFJ.Normalize = Normalize

local MIN_TOKEN_LEN = 3 -- code points, counted as UTF-8 lead bytes (matches Python len())

-- Full-width digits U+FF10..U+FF19 are the UTF-8 bytes EF BC 90..99.
local FW = {}
for i = 0, 9 do FW[string.char(0xEF, 0xBC, 0x90 + i)] = tostring(i) end

-- ASCII letters only (locale-independent; Python uses isascii() and isalpha()).
local function isLetter(ch)
  local b = ch:byte()
  return b ~= nil and ((b >= 65 and b <= 90) or (b >= 97 and b <= 122))
end

local function codePoints(s)
  local _, n = s:gsub("[^\128-\191]", "")
  return n
end

-- Whole-word, exact-case replacement; boundaries are ASCII letters. Tokens < 3 chars are never replaced.
function Normalize.replaceWord(text, token, placeholder)
  if codePoints(token) < MIN_TOKEN_LEN then return text end
  local out, i, n, t = {}, 1, #text, #token
  while i <= n do
    local j = text:find(token, i, true)
    if not j then out[#out + 1] = text:sub(i); break end
    local beforeOk = j == 1 or not isLetter(text:sub(j - 1, j - 1))
    local afterOk = j + t > n or not isLetter(text:sub(j + t, j + t))
    out[#out + 1] = text:sub(i, j - 1)
    out[#out + 1] = (beforeOk and afterOk) and placeholder or token
    i = j + t
  end
  return table.concat(out)
end

-- player: optional { name=, class=, race= }, client side only.
function Normalize.v1(raw, player)
  local s = raw
  s = s:gsub("|H[^|]*|h(.-)|h", "%1")
  s = s:gsub("|T[^|]*|t", "")
  s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
  s = s:gsub("|r", "")
  s = s:gsub("|n", "\n")
  s = s:gsub("%$[Bb]", "\n")
  s = s:gsub("\239\188[\144-\153]", FW)
  s = s:gsub("%$[Gg]([^:;]*):[^;]*;", "%1")
  s = s:gsub("%$[Nn]", "{name}"):gsub("%$[Cc]", "{class}"):gsub("%$[Rr]", "{race}")
  if player then
    if player.name and player.name ~= "" then s = Normalize.replaceWord(s, player.name, "{name}") end
    if player.class and player.class ~= "" then s = Normalize.replaceWord(s, player.class, "{class}") end
    if player.race and player.race ~= "" then s = Normalize.replaceWord(s, player.race, "{race}") end
  end
  s = s:gsub("[ \t\r\n\f\v]+", " ")
  s = s:gsub("^ ", ""):gsub(" $", "") -- ASCII space only, same as Python .strip(" ")
  return s
end
