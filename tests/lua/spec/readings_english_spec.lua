-- English word cards: the read path over the generated English card rows (Core/Readings) and the card's lines.
local H = require("tests.lua.spec.helpers")

local PACKED = "少し=すこし 生き物=いきもの=7 狩り=かり=9 数=かず 減らして=へらして=11"
local EN = "Hunt a few creatures, and thin their numbers."

describe("Readings.englishLookup", function()
  local WFJ, R
  before_each(function()
    H.coreStub()
    WFJ = H.loadChunks({ "Core/Const.lua", "Core/Data.lua", "Core/Readings.lua" })
    R = WFJ.Readings
    WFJ.Data.add("reading", { ["quest:1"] = { description = PACKED } })
    -- word=n: n is the place of the Japanese word in the line's reading row
    WFJ.Data.add("english", { ["quest:1"] = { description = "creatures=2 hunt=3 numbers=4 thin=5" } })
    WFJ.Data.add("pron", { hunt = "hʌnt", creatures = "kríːtʃərz", few = "fjuː" })
    WFJ.Data.add("common", { few = "少し=すこし" })
  end)

  it("finds each English word the row lists, where it stands, with its Japanese word and reading", function()
    local spans = R.englishLookup("quest.description", 1, EN)
    local got = {}
    for _, s in ipairs(spans) do
      got[#got + 1] = { EN:sub(s.first, s.last), s.card.ja, s.card.jaReading, s.card.ipa }
    end
    assert.are.same({
      { "Hunt", "狩り", "かり", "hʌnt" }, { "few", "少し", "すこし", "fjuː" },
      { "creatures", "生き物", "いきもの", "kríːtʃərz" }, { "thin", "減らして", "へらして" },
      { "numbers", "数", "かず" },
    }, got)
  end)

  it("carries the Japanese word's meaning number, and marks the card as an English one", function()
    local spans = R.englishLookup("quest.description", 1, EN)
    assert.is_true(spans[1].card.english)
    assert.are.equal(9, spans[1].card.gloss)
    assert.is_nil(spans[5].card.gloss) -- 数 carries none
    assert.are.equal("Hunt", spans[1].word) -- the word as the line writes it
    assert.are.equal("狩り（かり）", spans[1].reading) -- what the reading-only box shows
  end)

  it("a common word the row does not list comes from the common list; a word in neither gets nothing", function()
    local spans = R.englishLookup("quest.description", 1, "A few more, and")
    assert.are.equal(1, #spans)
    assert.are.equal("few", spans[1].word)
    assert.is_nil(spans[1].card.gloss)
  end)

  it("a line with no English row still gets its common words, and nothing without text", function()
    assert.are.equal(1, #R.englishLookup("quest.description", 99, "a few"))
    assert.is_nil(R.englishLookup("quest.description", 1, nil))
    assert.is_nil(R.englishLookup("item", 1, "a few")) -- not a kind that takes cards
  end)

  it("keeps every span on character boundaries beside multi-byte text, and reads a contraction as one word", function()
    WFJ.Data.add("english", { ["gossip:k"] = { text = "don't=1 hunt=2" } })
    WFJ.Data.add("reading", { ["gossip:k"] = { text = "しない=しない 狩り=かり" } })
    local text = "“Hunt”・don't。"
    local spans = R.englishLookup("gossip", "k", text)
    local found = { text:sub(spans[1].first, spans[1].last), text:sub(spans[2].first, spans[2].last) }
    assert.are.same({ "Hunt", "don't" }, found)
    for _, s in ipairs(spans) do
      assert.is_true(text:byte(s.first) < 0x80 and text:byte(s.last) < 0x80)
    end
  end)

  it("a contraction with no card of its own takes its first word's, over the whole contraction", function()
    WFJ.Data.add("common", { you = "あなた=あなた", let = "させる=させる" })
    local text = "You're late; let's hunt. Isn't it?"
    local spans = R.englishLookup("quest.description", 1, text)
    local got = {}
    for _, s in ipairs(spans) do got[#got + 1] = text:sub(s.first, s.last) .. ">" .. s.card.ja end
    assert.are.same({ "You're>あなた", "let's>させる", "hunt>狩り" }, got)
  end)

  it("an index past the reading row's end is dropped, never read", function()
    WFJ.Data.add("english", { ["quest:2"] = { description = "hunt=9" } })
    WFJ.Data.add("reading", { ["quest:2"] = { description = "狩り=かり" } })
    assert.are.same({}, R.englishLookup("quest.description", 2, "Hunt"))
  end)
end)
