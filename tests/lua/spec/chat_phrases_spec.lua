-- Core/ChatPhrases: the phrase mark. A dot followed by exactly one of the book's phrases is that phrase, shown in
-- the reader's language; anything else stays as typed. Pure: loaded with no WoW globals.
local H = require("tests.lua.spec.helpers")

local DOT, JA_DOT = "\194\183", "\227\131\187"

local function load()
  local WFJ = {}
  H.loadPure("Core/Data.lua", "WoWForeverJapanese", WFJ)
  H.loadPure("Core/ChatPhrases.lua", "WoWForeverJapanese", WFJ)
  WFJ.Data.add("phrase", {
    [1] = "greetings\tHello!\tこんにちは！",
    [2] = "greetings\tThank you very much!\tありがとうございます！",
    [3] = "combat\tI'm out of mana.\tマナがありません。",
    [4] = "group\tI'm ready.\t準備できました。",
  })
  return WFJ.ChatPhrases
end

describe("Core/ChatPhrases", function()
  it("shows a marked phrase in the reader's language, whichever language it was sent in", function()
    local P = load()
    assert.equals(P.MARK .. "こんにちは！", P.translate(DOT .. " Hello!", "ja"))
    assert.equals(P.MARK .. "こんにちは！", P.translate(JA_DOT .. "こんにちは！", "ja"))
    assert.equals(P.MARK .. "Hello!", P.translate(JA_DOT .. "こんにちは！", "en"))
    assert.equals(P.MARK .. "Hello!", P.translate(DOT .. " hello!", "en"))
  end)

  it("changes each marked phrase of a message and keeps what else was typed", function()
    local P = load()
    assert.equals(P.MARK .. "こんにちは！" .. P.MARK .. "ありがとうございます！",
      P.translate(DOT .. " Hello!" .. DOT .. " Thank you very much!", "ja"))
    assert.equals(P.MARK .. "マナがありません。 need a sec", P.translate(DOT .. " I'm out of mana. need a sec", "ja"))
  end)

  it("leaves a dot before anything else, a dot inside a name and a phrase with no dot", function()
    local P = load()
    assert.is_nil(P.translate(JA_DOT .. "今日はダンジョン行く？", "ja"))
    assert.is_nil(P.translate("ジョン" .. JA_DOT .. "スミス", "ja"))
    assert.is_nil(P.translate("Hello!", "ja"))
    assert.is_nil(P.translate("こんにちは！", "en"))
    assert.is_nil(P.translate("", "ja"))
  end)

  it("gives what is typed for a phrase: the dot, a space and its English", function()
    local P = load()
    assert.equals(DOT .. " Hello!", P.typed(P.list()[1]))
  end)

  it("lists the phrases in order with their topic, and the topics in first-seen order", function()
    local P = load()
    local list = P.list()
    assert.equals(4, #list)
    assert.same({ id = 3, topic = "combat", en = "I'm out of mana.", ja = "マナがありません。" }, list[3])
    assert.same({ "greetings", "combat", "group" }, P.topics())
  end)

  it("keeps the last sent messages with what they were shown as, and forgets the oldest", function()
    local P = load()
    P.keep("shown one", "raw one")
    assert.equals("raw one", P.sent("a line holding shown one here"))
    assert.is_nil(P.sent("a line holding nothing"))
    for i = 1, P.KEPT do P.keep("shown " .. i .. ".", "raw " .. i) end
    assert.is_nil(P.sent("shown one"))
    local raw, first, last = P.sent("x shown 5. y")
    assert.equals("raw 5", raw)
    assert.equals("shown 5.", ("x shown 5. y"):sub(first, last))
  end)
end)
