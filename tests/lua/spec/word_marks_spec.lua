-- Core/WordMarks: which word of a text takes an underline and which the highlight.
local Env = require("tests.lua.spec.word_env")

local TEXT = "敵を倒して谷へ行く。敵は青いだろう！食べる"
local function at(word, from)
  local first, last = TEXT:find(word, from or 1, true)
  return first, last
end

-- 敵 倒す 谷 | 敵 青い だろう | 食べる
local function words()
  local out = {}
  local function add(word, key, from)
    local first, last = at(word, from)
    out[#out + 1] = { first = first, last = last, lang = "ja", key = key }
  end
  add("敵", "敵\tてき")
  add("倒して", "倒す\tたおす")
  add("谷", "谷\tたに")
  add("敵", "敵\tてき", 20)
  add("青い", "青い\tあおい")
  add("だろう", "だろう\tだろう")
  add("食べる", "食べる\tたべる")
  out[#out + 1] = { first = 1, last = 3 } -- a name: no key
  return out
end

local function underlines(plan)
  local out = {}
  for i, m in ipairs(plan) do out[i] = m.underline or "-" end
  return table.concat(out, " ")
end

local function highlights(plan)
  local out = {}
  for i, m in ipairs(plan) do out[i] = m.highlight and "H" or "-" end
  return table.concat(out, " ")
end

describe("Core/WordMarks", function()
  it("cuts sentences after 。！？ and at line breaks, and English after a full stop", function()
    local Marks = Env.load().WordMarksPlan
    local s = Marks.sentences("あ。い！\nう", false)
    assert.are.same({ { 1, 6 }, { 7, 12 }, { 14, 16 } }, s)
    assert.are.same({ { 1, 6 }, { 7, 11 } }, Marks.sentences("Go on. Stop", true))
    assert.are.same({ { 1, 11 } }, Marks.sentences("Go on. Stop", false))
  end)

  it("underlines unknown and learning words, and nothing known, ignored or without a key", function()
    local WFJ = Env.load()
    local S, Marks = WFJ.WordStatus, WFJ.WordMarksPlan
    S.set("ja", "敵\tてき", "known")
    S.set("ja", "倒す\tたおす", "learning")
    S.set("ja", "谷\tたに", "ignored")
    local plan = Marks.plan(TEXT, words(), { underline = true, learning = true, highlight = "off" })
    assert.are.equal("- learning - - unknown - unknown -", underlines(plan))
    assert.are.equal("- - - - - - - -", highlights(plan))
    plan = Marks.plan(TEXT, words(), { underline = false, learning = false, highlight = "off" })
    assert.are.equal("- - - - - - - -", underlines(plan))
    -- each of the two underlines has its own switch
    plan = Marks.plan(TEXT, words(), { underline = true, learning = false, highlight = "off" })
    assert.are.equal("- - - - unknown - unknown -", underlines(plan))
    plan = Marks.plan(TEXT, words(), { underline = false, learning = true, highlight = "off" })
    assert.are.equal("- learning - - - - - -", underlines(plan))
  end)

  it("highlights the words to learn next in the common mode", function()
    local WFJ = Env.load()
    WFJ.WordStatus.LEARN_NEXT = 2 -- 倒す and 敵
    local plan = WFJ.WordMarksPlan.plan(TEXT, words(), { underline = true, highlight = "common" })
    assert.are.equal("H H - H - - - -", highlights(plan))
  end)

  it("highlights the one unknown word of a sentence in the only-new mode", function()
    local WFJ = Env.load()
    local S, Marks = WFJ.WordStatus, WFJ.WordMarksPlan
    -- sentence 1 has three unknown words, sentence 2 has 敵 and 青い (だろう is ignored), sentence 3 has one
    assert.are.equal("- - - - - - H -", highlights(Marks.plan(TEXT, words(), { highlight = "new" })))
    S.set("ja", "敵\tてき", "known")
    assert.are.equal("- - - - H - H -", highlights(Marks.plan(TEXT, words(), { highlight = "new" })))
    S.set("ja", "倒す\tたおす", "learning") -- a learning word is not a new one
    assert.are.equal("- - H - H - H -", highlights(Marks.plan(TEXT, words(), { highlight = "new" })))
  end)

  it("highlights a word that is both in the common-and-only-new mode", function()
    local WFJ = Env.load()
    local S, Marks = WFJ.WordStatus, WFJ.WordMarksPlan
    S.set("ja", "敵\tてき", "known")
    S.LEARN_NEXT = 2 -- 倒す and 谷, so 青い and 食べる are alone in their sentences but not common
    assert.are.equal("- - - - - - - -", highlights(Marks.plan(TEXT, words(), { highlight = "commonNew" })))
    S.LEARN_NEXT = 20
    S.set("ja", "倒す\tたおす", "unknown")
    assert.are.equal("- - - - H - H -", highlights(Marks.plan(TEXT, words(), { highlight = "commonNew" })))
  end)

  it("plans English words by the English list", function()
    local WFJ = Env.load()
    local text = "Defeat the enemy. Go to the valley."
    local list = {
      { first = 1, last = 6, lang = "en", key = "defeat" }, { first = 12, last = 16, lang = "en", key = "enemy" },
      { first = 29, last = 34, lang = "en", key = "valley" },
    }
    local plan = WFJ.WordMarksPlan.plan(text, list,
      { underline = true, learning = true, highlight = "new", english = true })
    assert.are.equal("unknown unknown unknown", underlines(plan))
    assert.are.equal("- - H", highlights(plan))
  end)
end)
