-- Core/WordImport: marking a pasted word list, and the statuses as text.
local Env = require("tests.lua.spec.word_env")

local function known(WFJ)
  local out = {}
  for key, status in pairs(WFJ.WordStatus.entries("ja")) do
    if status == "known" then out[#out + 1] = (key:gsub("\t.*", "")) end
  end
  table.sort(out)
  return table.concat(out, " ")
end

describe("Core/WordImport", function()
  it("marks a messy paste: commas, tabs, furigana brackets, tags, other languages, forms and endings", function()
    local WFJ = Env.load()
    local r = WFJ.WordImport.apply("ja", "倒す, 食[た]べる\t<b>敵</b> hello 123\n倒して、倒しました。", "known")
    assert.are.equal("倒す 敵 食べる", known(WFJ))
    assert.are.same({ 3, 0, 0, 0 }, { r.marked, r.already, r.kept, #r.missing })
  end)

  it("marks a dictionary form in every reading the game has for it", function()
    local WFJ = Env.load()
    WFJ.WordImport.apply("ja", "開く", "known")
    assert.are.equal("known", WFJ.WordStatus.get("ja", "開く\tあく"))
    assert.are.equal("known", WFJ.WordStatus.get("ja", "開く\tひらく"))
  end)

  it("matches a kana word to the one word read that way, and leaves a reading of several unmatched", function()
    local WFJ = Env.load()
    local r = WFJ.WordImport.apply("ja", "あおい あく ぜったいない", "known")
    assert.are.equal("青い", known(WFJ))
    assert.are.same({ "あく", "ぜったいない" }, r.missing)
  end)

  it("never changes a word the player set by hand, and counts what it left", function()
    local WFJ = Env.load()
    local S = WFJ.WordStatus
    S.set("ja", "敵\tてき", "learning")
    S.set("ja", "谷\tたに", "ignored")
    S.set("ja", "倒す\tたおす", "known")
    S.set("ja", "増加\tぞうか", "known")
    S.set("ja", "増加する\tぞうかする", "unknown")
    local r = WFJ.WordImport.apply("ja", "敵 谷 倒す 増加する 青い", "known")
    assert.are.same({ 1, 1, 3 }, { r.marked, r.already, r.kept })
    assert.are.equal("learning", S.get("ja", "敵\tてき"))
    assert.are.equal("ignored", S.get("ja", "谷\tたに"))
    assert.are.equal("unknown", S.get("ja", "増加する\tぞうかする"))
  end)

  it("counts a word that is already what the import would make it", function()
    local WFJ = Env.load()
    WFJ.WordStatus.set("ja", "増加\tぞうか", "known")
    local r = WFJ.WordImport.apply("ja", "増加する だろう", "known")
    -- 増加する is known through its noun; だろう starts ignored and has no status of the player's, so it is marked
    assert.are.same({ 1, 1, 0 }, { r.marked, r.already, r.kept })
  end)

  it("marks its matches ignored when asked to", function()
    local WFJ = Env.load()
    local r = WFJ.WordImport.apply("ja", "敵、谷", "ignored")
    assert.are.equal(2, r.marked)
    assert.are.equal("ignored", WFJ.WordStatus.get("ja", "敵\tてき"))
    assert.are.same({ 0, 0, 0 }, { WFJ.WordImport.apply("ja", "敵", "learning").marked, 0, 0 })
  end)

  it("exports the statuses the player set, and an export pasted back restores them", function()
    local WFJ = Env.load()
    local S = WFJ.WordStatus
    S.set("ja", "敵\tてき", "known")
    S.set("ja", "開く\tあく", "learning")
    S.set("ja", "谷\tたに", "ignored")
    S.set("ja", "だろう\tだろう", "unknown")
    local text = WFJ.WordImport.export("ja")
    assert.are.equal("だろう\tだろう\tunknown\n敵\tてき\tknown\n谷\tたに\tignored\n開く\tあく\tlearning", text)
    local again = Env.load()
    local r = again.WordImport.apply("ja", text, "known")
    assert.are.same({ 4, 0 }, { r.marked, #r.missing })
    assert.are.same(S.entries("ja"), again.WordStatus.entries("ja"))
    assert.are.equal("unknown", again.WordStatus.get("ja", "開く\tひらく")) -- the other reading was never set
  end)

  it("imports and exports English words in the English list", function()
    local WFJ = Env.load()
    local r = WFJ.WordImport.apply("en", "Enemy, you're; Zebra 12 敵", "known")
    assert.are.same({ 2, 0, 0 }, { r.marked, r.already, r.kept })
    assert.are.same({ "Zebra" }, r.missing) -- as it was pasted
    assert.are.same({}, WFJ.WordStatus.entries("ja"))
    assert.are.equal("enemy\tknown\nyou\tknown", WFJ.WordImport.export("en"))
    local again = Env.load()
    again.WordImport.apply("en", "enemy\tignored\nyou\tknown", "known")
    assert.are.equal("ignored", again.WordStatus.get("en", "enemy"))
  end)

  it("keeps the last import's numbers, and announces a whole import once", function()
    local WFJ = Env.load()
    local fired = 0
    WFJ.State = { fire = function(event) if event == "wordStatus" then fired = fired + 1 end end }
    WFJ.WordImport.apply("ja", "敵 谷 倒す ぜったいない", "known")
    assert.are.equal(1, fired)
    assert.are.same({ marked = 3, already = 0, kept = 0, missing = 1 }, WFJ.WordStatus.lastImport("ja"))
  end)
end)
