-- Core/UIStrings for the Forever windows: the `signed` argument kind (a "+25" honor or rating
-- change, copied verbatim) and matchOnly's per-list set cache and bounded miss memo.
local H = require("tests.lua.spec.helpers")

describe("Core/UIStrings additions", function()
  local UIS, index, rows

  local function h1(text)
    local n = 0
    for i = 1, #text do n = (n * 31 + text:byte(i)) % 4294967296 end
    return n
  end

  local UI = {
    COMBAT_TEXT_HONOR_GAINED = { "Honor %s", "名誉 %s" },
    PVP_RATING_CHANGE = { "%s Rating", "レーティング %s" },
    PVP_HONOR_CHANGE = { "%s Honor", "名誉 %s" },
    HONOR = { "Honor", "名誉" },
    ACCEPT = { "Accept", "受注" },
  }

  before_each(function()
    local ns = {}
    H.loadPure("Core/UIStringKeys.lua", "WoWForeverJapanese", ns)
    H.loadPure("Core/UIStrings.lua", "WoWForeverJapanese", ns)
    UIS = ns.UIStrings
    rows = {}
    local english = {}
    for key, pair in pairs(UI) do
      rows[key] = { pair[2], h1(pair[1]), "." }
      english[key] = pair[1]
    end
    index = UIS.build({ rows = rows, hash = h1, english = function(key) return english[key] end })
  end)

  it("a `signed` argument takes a +/- count and is filled back verbatim; an unsigned number is not one", function()
    assert.are.same({ [1] = "signed" }, UIS.ARGS.COMBAT_TEXT_HONOR_GAINED)
    local key, args = index:match("Honor +25")
    assert.are.equal("COMBAT_TEXT_HONOR_GAINED", key)
    assert.are.equal("名誉 +25", index:fill(rows[key][1], args))
    key, args = index:match("-12 Rating")
    assert.are.equal("PVP_RATING_CHANGE", key)
    assert.are.equal("レーティング -12", index:fill(rows[key][1], args))
    key, args = index:match("+1,250 Honor")
    assert.are.equal("PVP_HONOR_CHANGE", key)
    assert.are.equal("名誉 +1,250", index:fill(rows[key][1], args))
    assert.is_nil(index:match("25 Rating")) -- no sign: not a change the client prints this way
    assert.is_nil(index:match("Honor Thrall")) -- a word is never a signed count
  end)

  it("matchOnly: a list and the equivalent set give the same answers, again from its caches", function()
    local list = { "HONOR", "ACCEPT" }
    local set = { HONOR = true, ACCEPT = true }
    for _ = 1, 3 do
      assert.are.equal("HONOR", (index:matchOnly("Honor", list)))
      assert.are.equal("HONOR", (index:matchOnly("Honor", set)))
      assert.is_nil(index:matchOnly("Honor +25", list)) -- a key outside the list: refused, and the refusal cached
      assert.is_nil(index:matchOnly("12:34", list)) -- a line no key matches (a clock time)
    end
    assert.are.equal("COMBAT_TEXT_HONOR_GAINED", (index:matchOnly("Honor +25", { "COMBAT_TEXT_HONOR_GAINED" })))
  end)

  it("matchOnly's miss memo is per list and bounded: past its limit it starts over and still answers right", function()
    local list = { "ACCEPT" }
    for i = 1, 1200 do assert.is_nil(index:matchOnly("line " .. i, list)) end
    assert.are.equal("ACCEPT", (index:matchOnly("Accept", list)))
    assert.is_nil(index:matchOnly("n", list)) -- a one-letter line never collides with the memo's own bookkeeping
    assert.are.equal("ACCEPT", (index:matchOnly("Accept", list)))
  end)

  it("a rebuilt index starts with an empty memo", function()
    local list = { "ACCEPT" }
    assert.is_nil(index:matchOnly("Accept!", list))
    local rebuilt = UIS.build({ rows = rows, hash = h1, english = function(key) return UI[key] and UI[key][1] end })
    assert.is_nil(rebuilt.onlyMisses)
    assert.are.equal("ACCEPT", (rebuilt:matchOnly("Accept", list)))
  end)
end)
