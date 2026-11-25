-- Core/WordFrequency: the order of the game's words and what each row says. Pure: loaded with no WoW globals.
local H = require("tests.lua.spec.helpers")

local function load()
  local WFJ = {}
  H.loadPure("Core/Data.lua", "WoWForeverJapanese", WFJ)
  H.loadPure("Core/WordFrequency.lua", "WoWForeverJapanese", WFJ)
  WFJ.Data.add("freqJa", { ["倒す\tたおす"] = "5,1,0,0,0,0", ["敵\tてき"] = "3,0,0,0,0,9", ["開く\tあく"] = "1,0,0,0,0,0",
    ["開く\tひらく"] = "1,0,0,0,0,0", ["悪\tあく"] = "0,2,0,0,0,0", ["だろう\tだろう"] = "4,0,0,0,0,0" })
  WFJ.Data.add("freqEn", { enemy = "7,0,0,0,0,0", defeat = "2,0,0,0,0,0", hello = "0,0,0,0,0,0" })
  WFJ.Data.add("grammar", { ["だろう\tだろう"] = "1" })
  return WFJ.WordFrequency
end

describe("Core/WordFrequency", function()
  it("ranks the words most used first, equal totals by key", function()
    local F = load()
    assert.are.equal(6, F.count("ja"))
    assert.are.equal("敵\tてき", F.at("ja", 1))
    assert.are.equal(2, F.rank("ja", "倒す\tたおす"))
    assert.are.equal(3, F.rank("ja", "だろう\tだろう"))
    assert.are.equal("悪\tあく", F.at("ja", 4))
    assert.are.equal(5, F.rank("ja", "開く\tあく")) -- before 開く ひらく: the same total, the smaller key
    assert.is_nil(F.rank("ja", "無い\tない"))
    assert.are.equal("enemy", F.at("en", 1))
    assert.are.equal(3, F.rank("en", "hello"))
  end)

  it("gives a word's uses per kind of text", function()
    local F = load()
    assert.are.same({ 3, 0, 0, 0, 0, 9 }, F.uses("ja", "敵\tてき"))
    assert.are.equal(6, #F.KINDS)
  end)

  it("knows the grammar words, a dictionary form's readings and the words read one way", function()
    local F = load()
    assert.is_true(F.grammar("だろう\tだろう"))
    assert.is_false(F.grammar("敵\tてき"))
    local forms = F.forms("開く")
    table.sort(forms)
    assert.are.same({ "開く\tあく", "開く\tひらく" }, forms)
    local read = F.read("あく")
    table.sort(read)
    assert.are.same({ "悪\tあく", "開く\tあく" }, read)
    assert.is_nil(F.read("ない"))
  end)
end)
