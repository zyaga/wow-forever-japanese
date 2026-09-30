local H = require("tests.lua.spec.helpers")

describe("Hash.h32x2 (Lua twin of hash32x2)", function()
  local WFJ = {}
  setup(function()
    H.coreStub()
    H.loadChunk("Core/Normalize.lua", "WoWForeverJapanese", WFJ)
    H.loadChunk("Core/Hash.lua", "WoWForeverJapanese", WFJ)
  end)

  it("hashes the empty string to zero", function()
    local h1, h2 = WFJ.Hash.h32x2("")
    assert.are.equal(0, h1); assert.are.equal(0, h2)
    assert.are.equal("0000000000000000", WFJ.Hash.key(""))
  end)

  it("formats hex without string.format", function()
    assert.are.equal("00000001", WFJ.Hash.hex8(1))
    assert.are.equal("ffffffff", WFJ.Hash.hex8(4294967295))
  end)

  it("matches every shared vector (h1, h2, key) and keyOf(raw, player)", function()
    local V = H.vectors()
    for _, c in ipairs(V.cases) do
      local h1, h2 = WFJ.Hash.h32x2(c.norm)
      assert.are.equal(c.h1, h1, c.id .. " h1")
      assert.are.equal(c.h2, h2, c.id .. " h2")
      assert.are.equal(c.key, WFJ.Hash.key(c.norm), c.id .. " key")
      assert.are.equal(c.key, WFJ.Hash.keyOf(c.raw, c.player), c.id .. " keyOf")
    end
  end)

  it("keeps every intermediate below 2^45 on the 4 KB vector", function()
    local V = H.vectors()
    local big
    for _, c in ipairs(V.cases) do if c.id == "big-01" then big = c end end
    assert.is_not_nil(big)
    local dbg = {}
    WFJ.Hash.DEBUG_MAX_INTERMEDIATE = dbg
    WFJ.Hash.h32x2(big.norm)
    WFJ.Hash.DEBUG_MAX_INTERMEDIATE = nil
    assert.is_true(dbg.max < 2 ^ 45, tostring(dbg.max))
    assert.is_true(dbg.max > 2 ^ 32)
  end)

  it("uses no bit library", function()
    local f = io.open(H.ADDON_DIR .. "/Core/Hash.lua")
    local src = f:read("*a")
    f:close()
    assert.is_nil(src:find("bit%."))
  end)
end)
