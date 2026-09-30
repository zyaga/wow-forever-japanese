-- Core/Hash.lua: Hash32x2, the Lua 5.1 twin of pipeline/wfj/core/hashing.py (ADR-005).
--   h1 = (h1*131  + b) % 4294967291   h2 = (h2*8161 + b) % 4294967279   key = "%08x%08x"
-- Every intermediate < 2^45, exact in doubles; no `bit` library (lint forbids it).
-- Consumers of Hash.lua and Normalize.lua (check each before changing either): UI/Slash (debug hash),
-- Core/Collector (fingerprints), UI/Gossip, pipeline check/generate. A change must stay byte-identical to Python.
local _, WFJ = ...
local Hash = {}
WFJ.Hash = Hash

local M1, P1 = 131, 4294967291
local M2, P2 = 8161, 4294967279
local HEX = "0123456789abcdef"

-- Test hook: when set to a table, records the largest intermediate seen.
Hash.DEBUG_MAX_INTERMEDIATE = nil

function Hash.h32x2(norm)
  local h1, h2 = 0, 0
  local dbg = Hash.DEBUG_MAX_INTERMEDIATE
  for i = 1, #norm do
    local b = norm:byte(i)
    local t1, t2 = h1 * M1 + b, h2 * M2 + b
    if dbg then
      if t1 > (dbg.max or 0) then dbg.max = t1 end
      if t2 > (dbg.max or 0) then dbg.max = t2 end
    end
    h1, h2 = t1 % P1, t2 % P2
  end
  return h1, h2
end

-- 8 lowercase hex digits without string.format("%x") (its cast to C long is not portable across clients).
function Hash.hex8(n)
  local out = {}
  for i = 8, 1, -1 do
    local d = n % 16
    out[i] = HEX:sub(d + 1, d + 1)
    n = (n - d) / 16
  end
  return table.concat(out)
end

function Hash.key(norm)
  local h1, h2 = Hash.h32x2(norm)
  return Hash.hex8(h1) .. Hash.hex8(h2)
end

function Hash.keyOf(raw, player)
  return Hash.key(WFJ.Normalize.v1(raw, player))
end
