local H = require("tests.lua.spec.helpers")

describe("Normalize.v1 (Lua twin of normalize_v1)", function()
  local WFJ = {}
  setup(function()
    H.coreStub()
    H.loadChunk("Core/Normalize.lua", "WoWForeverJapanese", WFJ)
  end)

  it("matches every shared vector", function()
    local V = H.vectors()
    assert.are.equal("v1", V.norm)
    assert.is_true(#V.cases >= 40)
    for _, c in ipairs(V.cases) do
      assert.are.equal(c.norm, WFJ.Normalize.v1(c.raw, c.player), c.id)
    end
  end)

  it("never replaces tokens shorter than 3 chars", function()
    assert.are.equal("Al is. Alliance.", WFJ.Normalize.replaceWord("Al is. Alliance.", "Al", "{name}"))
  end)

  it("respects ASCII-letter word boundaries", function()
    assert.are.equal("Marketplace, {name}'s.", WFJ.Normalize.replaceWord("Marketplace, Mark's.", "Mark", "{name}"))
  end)
end)
