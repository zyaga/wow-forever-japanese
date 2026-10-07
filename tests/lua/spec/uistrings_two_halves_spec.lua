-- Core/UIStrings: a template that is two free-text halves around one short word ("%s in %s", "%s by %s") answers
-- only a caller that asks for its key. Open, it would split any sentence without a period at that word and show
-- the halves in the Japanese order ("Cannot change equip status while in combat" → "combatのCannot change …").
local H = require("tests.lua.spec.helpers")

describe("Core/UIStrings: two-halves templates are key-only", function()
  local index, rows

  local function h1(text)
    local n = 0
    for i = 1, #text do n = (n * 31 + text:byte(i)) % 4294967296 end
    return n
  end

  local UI = {
    WARDROBE_TOOLTIP_ENCOUNTER_SOURCE = { "%s in %s", "%2$sの%1$s" },
    DEATH_RECAP_CAST_BY_TT = { "%s by %s", "%s（使用者: %s）" },
    ITEM_WRITTEN_BY = { "Written by %s", "著者: %s" }, -- a literal word of its own: open
  }

  setup(function()
    local ns = H.loadChunks({ "Core/UIStringKeys.lua", "Core/UIStrings.lua" })
    rows = {}
    local english = {}
    for key, pair in pairs(UI) do
      rows[key] = { pair[2], h1(pair[1]), "." }
      english[key] = pair[1]
    end
    index = ns.UIStrings.build({ rows = rows, hash = h1, english = function(key) return english[key] end })
  end)

  local function ja(text, only)
    local key, args
    if only then key, args = index:matchOnly(text, only) else key, args = index:match(text) end
    assert.is_not_nil(key, text)
    return index:fill(rows[key][1], args)
  end

  it("a tooltip sentence holding ' in ' or ' by ' stays as written on an unrestricted match", function()
    assert.is_nil(index:match("Cannot change equip status while in combat"))
    assert.is_nil(index:match("Dropped by Hogger in Elwynn Forest"))
  end)

  it("the wardrobe and the death recap still fill them by key", function()
    assert.are.equal("Elwynn ForestのHogger", ja("Hogger in Elwynn Forest", { "WARDROBE_TOOLTIP_ENCOUNTER_SOURCE" }))
    assert.are.equal("Shadow Bolt（使用者: Hogger）", ja("Shadow Bolt by Hogger", { "DEATH_RECAP_CAST_BY_TT" }))
  end)

  it("a template with a literal word of its own still answers an open match", function()
    assert.are.equal("著者: Hogger", ja("Written by Hogger"))
  end)
end)
