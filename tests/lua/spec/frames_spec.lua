-- UI/Frames.lua: a frame's regions and children as bounded lists. GetRegions / GetChildren return every part as a
-- separate value; past the Lua stack's limit the client raises "stack overflow" inside the call.
local H = require("tests.lua.spec.helpers")

-- A frame with `n` parts behind `list`, its count behind `count` (nil: no count method). `limit`: the call raises
-- "stack overflow" past this many, as the client does.
local function frameWith(list, count, n, limit)
  local f, calls = {}, { list = 0 }
  local parts = {}
  for i = 1, math.min(n, 50) do parts[i] = { id = i } end
  f[list] = function()
    calls.list = calls.list + 1
    if limit and n > limit then error("stack overflow") end
    return unpack(parts)
  end
  if count then f[count] = function() return n end end
  return f, calls, parts
end

describe("Frames: bounded region and child lists", function()
  local Frames

  before_each(function()
    local WFJ = {}
    H.loadPure("UI/Frames.lua", "WoWForeverJapanese", WFJ)
    Frames = WFJ.Frames
  end)

  local KINDS = { { "regions", "GetRegions", "GetNumRegions" }, { "children", "GetChildren", "GetNumChildren" } }
  for _, kind in ipairs(KINDS) do
    local name, list, count = kind[1], kind[2], kind[3]

    it(name .. ": every part in the client's order", function()
      local f, _, parts = frameWith(list, count, 3)
      assert.are.same(parts, Frames[name](f))
    end)

    it(name .. ": a frame without the count method is still listed (older client, a stub)", function()
      local f, _, parts = frameWith(list, nil, 2)
      assert.are.same(parts, Frames[name](f))
    end)

    it(name .. ": more parts than the bound gives an empty list without the call that would overflow", function()
      local f, calls = frameWith(list, count, 9000, 7999)
      assert.are.same({}, Frames[name](f))
      assert.are.equal(0, calls.list)
      local atBound = frameWith(list, count, Frames.MAX_PARTS)
      assert.are.equal(50, #Frames[name](atBound)) -- the bound itself is still listed (the stub holds 50)
    end)

    it(name .. ": a call that raises gives an empty list", function()
      local f = frameWith(list, nil, 9000, 7999)
      assert.are.same({}, Frames[name](f))
    end)

    it(name .. ": nothing to list on a non-table or a table without the method", function()
      assert.are.same({}, Frames[name](nil))
      assert.are.same({}, Frames[name]("frame"))
      assert.are.same({}, Frames[name]({}))
    end)
  end
end)
