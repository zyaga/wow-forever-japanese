-- Lua side: Core/ReportText writes the report text v1 (docs/systems/fix-reports.md) byte for byte as
-- the shared vectors say; pipeline/wfj/core/fix_report.py reads the same vectors (tests/python).
local H = require("tests.lua.spec.helpers")

local function pure() -- the module loaded fresh, under the plain Lua environment (no WoW global)
  local ns = {}
  H.loadPure("Core/ReportText.lua", "WoWForeverJapanese", ns)
  return ns.ReportText
end

describe("Core/ReportText", function()
  local R
  setup(function() R = pure() end)

  it("escapes \\ first, then newlines and |; the report never holds a | or a raw newline in a field", function()
    assert.are.equal("a\\\\b\\nc\\x7cd", R.escape("a\\b\nc|d"))
    assert.are.equal("\\\\x7c", R.escape("\\x7c")) -- a literal \x7c stays distinguishable from an escaped |
    assert.is_nil(R.escape("|||\n"):find("|", 1, true))
  end)

  it("writes the header, one block per fix in order, and the end count; unknown versions read ?", function()
    local text = R.serialize(nil, "1 2", {
      { type = "quest", id = 7, field = "title", ja_hash = "0011223344556677", reason = "typo" },
      { type = "ui", id = "OKAY", field = "text", ja_hash = "8899aabbccddeeff", reason = "other", note = "",
        ja = "了解" },
    })
    assert.are.equal("WFJ-REPORT 1\naddon ? client 1_2\nfix quest 7 title 0011223344556677 typo\n"
      .. "fix ui OKAY text 8899aabbccddeeff other\nja 了解\nend 2\n", text)
  end)

  it("matches every shared vector byte for byte (vectors/report_vectors.lua, make vectors)", function()
    local V = dofile(H.ROOT .. "/vectors/report_vectors.lua")
    local n = 0
    for _, c in ipairs(V.cases) do
      if c.fixes then
        n = n + 1
        assert.are.equal(c.text, R.serialize(c.addon, c.client, c.fixes), c.id)
      end
    end
    assert.is_true(n >= 5)
  end)
end)
