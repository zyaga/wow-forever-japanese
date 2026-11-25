-- Core/ChatWords: where a word sits in a chat line and the card it takes. Pure: loaded with no WoW globals.
local H = require("tests.lua.spec.helpers")

local GUILD = "|Hchannel:GUILD|h[ギルド]|h |Hplayer:Taro:12:GUILD|h[Taro]|h: 今日はダンジョンに行きませんか"
local SAY = "|Hplayer:Bob:3:SAY|h[Bob]|h says: LFM deadmines need healer"

local function load()
  local WFJ = {}
  H.loadPure("Core/Data.lua", "WoWForeverJapanese", WFJ)
  H.loadPure("Core/Glosses.lua", "WoWForeverJapanese", WFJ)
  H.loadPure("Core/Readings.lua", "WoWForeverJapanese", WFJ)
  H.loadPure("Core/ChatWords.lua", "WoWForeverJapanese", WFJ)
  WFJ.Data.add("gloss", { [1] = "今日\tきょう\ttoday", [2] = "ダンジョン\tダンジョン\tdungeon",
    [3] = "行く\tいく\tto go", [4] = "必要\tひつよう\tneed" })
  WFJ.Data.add("chatja", { ["今日"] = "きょう=1", ["ダンジョン"] = "ダンジョン=2", ["行き"] = "いき=3",
    ["せん"] = "せん=1" })
  WFJ.Data.add("chaten", { need = "必要=ひつよう=4" })
  WFJ.Data.add("chatword", { ["よろ"] = "よろ\tshort for よろしく" })
  WFJ.Data.add("chatwordEn", { lfm = "メンバー募集中", healer = "ヒーラー（回復役）" })
  WFJ.Data.add("pron", { need = "niːd" })
  WFJ.ChatWords.load(nil)
  return WFJ
end

-- every distinct word the line gives, by walking each byte: { word = span }
local function wordsOf(find, text)
  local out = {}
  for i = 1, #text do
    local w = find(text, i)
    if w then
      assert.is_true(i >= w.first and i <= w.last)
      out[text:sub(w.first, w.last)] = w
    end
  end
  return out
end

describe("Core/ChatWords", function()
  it("finds a Japanese word at any of its bytes, and none in a link or an escape sequence", function()
    local W = load().ChatWords
    local found = wordsOf(W.japaneseAt, GUILD)
    assert.is_table(found["今日"])
    assert.equals("きょう", found["今日"].reading)
    assert.equals("today", found["今日"].card.meaning)
    assert.is_table(found["ダンジョン"])
    assert.is_nil(found["ギルド"]) -- a link's label
    local labelFirst = GUILD:find("ギルド", 1, true)
    for i = 1, GUILD:find("今日", 1, true) - 1 do
      assert.is_nil(W.japaneseAt(GUILD, i), "byte " .. i .. (i >= labelFirst and " (label)" or ""))
    end
  end)

  it("joins a verb's endings to the word before them, with that word's card", function()
    local W = load().ChatWords
    local first = GUILD:find("行き", 1, true)
    local last = first + #"行きませんか" - 1
    for i = first, last do
      local w = W.japaneseAt(GUILD, i)
      assert.is_table(w, "byte " .. i)
      assert.equals(first, w.first)
      assert.equals(last, w.last)
      assert.equals("行きませんか", w.word)
      assert.equals("行く", w.card.lemma)
    end
  end)

  it("joins no ending to a word that ends in a kanji", function()
    local WFJ = load()
    WFJ.Data.add("chatja", { ["私"] = "わたし=1" })
    local w = WFJ.ChatWords.japaneseAt("私たち", 1)
    assert.equals("私", w.word)
  end)

  it("finds an English word with its Japanese and how it is said, and none in a link", function()
    local W = load().ChatWords
    local found = wordsOf(W.englishAt, SAY)
    assert.equals("メンバー募集中", found["LFM"].card.ja)
    assert.equals("必要", found["need"].card.ja)
    assert.equals("ひつよう", found["need"].card.jaReading)
    assert.equals("niːd", found["need"].card.ipa)
    assert.is_true(found["need"].card.english)
    assert.is_table(found["healer"])
    assert.is_nil(found["Bob"])
    assert.is_nil(found["deadmines"])
  end)

  it("gives a contraction its first word's card, and a negative none", function()
    local WFJ = load()
    WFJ.Data.add("chaten", { you = "あなた=あなた=1", can = "できる=できる=3" })
    assert.equals("あなた", WFJ.ChatWords.englishAt("you're late", 2).card.ja)
    assert.is_nil(WFJ.ChatWords.englishAt("can't go", 2))
  end)

  it("says when the player's own words change", function()
    local W = load().ChatWords
    local n = 0
    W.onChange = function() n = n + 1 end
    W.add("ja", "ぬるぽ", "ぬるぽ", "a joke")
    W.remove("ぬるぽ")
    W.remove("ぬるぽ") -- no longer there: nothing changed
    assert.equals(2, n)
  end)

  it("takes an own word before the chat list, and the chat list before the generated list", function()
    local WFJ = load()
    local W = WFJ.ChatWords
    WFJ.Data.add("chatja", { ["よろ"] = "よろ=2" })
    assert.equals("short for よろしく", W.japaneseAt("よろ", 1).card.meaning)
    assert.is_true(W.add("ja", "よろ", "よろ", "mine"))
    assert.equals("mine", W.japaneseAt("よろ", 1).card.meaning)
    assert.is_true(W.remove("よろ"))
    assert.equals("short for よろしく", W.japaneseAt("よろ", 1).card.meaning)

    assert.equals("必要", W.englishAt("need", 1).card.ja)
    WFJ.Data.add("chatwordEn", { need = "いる" })
    assert.equals("いる", W.englishAt("need", 1).card.ja)
    assert.is_true(W.add("en", "Need", "ほしい"))
    assert.equals("ほしい", W.englishAt("need", 1).card.ja)
  end)

  it("keeps the saved own words in the table it was given", function()
    local W = load().ChatWords
    local saved = W.load({ ja = { ["ぬるぽ"] = { reading = "ぬるぽ", meaning = "a joke" } } })
    assert.equals("a joke", W.japaneseAt("ぬるぽ", 1).card.meaning)
    W.add("en", "pog", "すごい")
    assert.equals("すごい", saved.en.pog.ja)
  end)

  it("gives the line without its escape sequences, a link keeping its label", function()
    local W = load().ChatWords
    assert.equals("[Guild] [Hana]: おつ  ok",
      W.plain("|cff40ff40[Guild] |Hplayer:Hana|h[Hana]|h: おつ|r |TInterface\\x:0|t ok"))
  end)

  it("gives what a player typed out of a typed line, or nothing when the line is not shaped so", function()
    local W = load().ChatWords
    assert.equals("今日はダンジョンに行きませんか", W.typedPart(GUILD))
    assert.equals("help: now", W.typedPart("|Hplayer:Bob|h[Bob]|h yells: help: now"))
    assert.equals("hello there", W.typedPart("To |Hplayer:Hana|h[Hana]|h: hello there"))
    assert.is_nil(W.typedPart("|Hplayer:Bob|h[Bob]|h has come online."))
    assert.is_nil(W.typedPart("You receive loot: |Hitem:1|h[Thing]|h."))
  end)
end)
