-- The ready-made copy of the word list the Anki add-on reads (ADR-110): one row per saved word, with what the
-- export window works out when it opens (furigana, the sentence's sound files), built at logout.
local H = require("tests.lua.spec.helpers")

local function load()
  local ns = {}
  H.loadPure("Core/Words.lua", nil, ns)
  H.loadPure("Core/AnkiExport.lua", nil, ns)
  return ns.AnkiExport, ns.Words
end

local function fmt(pattern, t) return os.date("!" .. pattern, t) end

local T = 1790000000

local TEXT = "少しの生き物たちを狩り、数を減らしてほしい。私は元気だ。"

local function save(W, o)
  o = o or {}
  local text = o.text or TEXT
  local word = o.word or "生き物"
  local first = text:find(word, 1, true)
  local i = {
    kind = "quest.description", id = 456, surface = "questframe.detail", text = text, first = first,
    last = first + #word - 1, word = word, reading = "いきもの", lemma = "生き物", lemmaReading = "いきもの",
    meaning = "living thing", questTitle = "生き物を減らせ",
  }
  for k, v in pairs(o) do i[k] = v end
  local _, e = W.add(i, T)
  return e
end

local function deps(W, o)
  o = o or {}
  return {
    furigana = W.furigana, sentenceFurigana = W.sentenceFurigana, bold = W.bold,
    audio = o.audio or function() return nil end, voice = o.voice == true,
  }
end

-- the export text's cell under a column, for the entry on line `n` (1 = the first entry)
local function cell(W, n, column)
  local out = W.export({}, fmt)
  local lines = {}
  for line in (out .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
  local names, at = {}, nil
  for name in (lines[3]:gsub("^#columns:", "") .. "\t"):gmatch("(.-)\t") do names[#names + 1] = name end
  for i, name in ipairs(names) do if name == column then at = i end end
  local cells = {}
  for c in (lines[3 + n] .. "\t"):gmatch("(.-)\t") do cells[#cells + 1] = c end
  return cells[at]
end

describe("AnkiExport", function()
  local A, W

  before_each(function()
    A, W = load()
    W.load(nil)
  end)

  it("is one row per saved word, in saved order, under the schema, the time and whether a pack is loaded", function()
    save(W)
    save(W, { word = "数", reading = "かず", lemma = "数", lemmaReading = "かず", meaning = "number" })
    local t = A.build(W.entries(), T, deps(W, { voice = true }))
    assert.are.equal(1, t.schema)
    assert.are.equal(T, t.written)
    assert.is_true(t.voice)
    assert.are.equal(2, #t.rows)
    assert.are.equal("quest.description:456:生き物", t.rows[1].key)
    assert.are.equal("quest.description:456:数", t.rows[2].key)
  end)

  it("holds the entry's fields and the furigana the export window gives", function()
    local e = save(W)
    W.setShot(e, "WoWScrnShot_112526_101500.jpg")
    local row = A.build(W.entries(), T, deps(W)).rows[1]
    assert.are.equal("生き物", row.word)
    assert.are.equal("いきもの", row.reading)
    assert.are.equal("生き物", row.lemma)
    assert.are.equal("いきもの", row.lemmaReading)
    assert.are.equal("living thing", row.meaning)
    assert.are.equal("quest", row.source)
    assert.are.equal(456, row.questId)
    assert.are.equal("生き物を減らせ", row.questTitle)
    assert.are.equal(T, row.saved)
    assert.are.equal("WoWScrnShot_112526_101500.jpg", row.shot)
    assert.are.equal("", row.lang)
    assert.are.equal("", row.jaSentence)
    assert.are.equal(cell(W, 1, "Sentence"), row.sentence)
    assert.are.equal(cell(W, 1, "Word (furigana)"), row.wordFurigana)
    assert.are.equal(cell(W, 1, "Sentence (furigana)"), row.sentenceFurigana)
    assert.is_truthy(row.sentence:find("<b>生き物</b>", 1, true))
  end)

  it("names the sentence's sound files in play order, as pack folder, Sound and file", function()
    save(W)
    local t = A.build(W.entries(), T, deps(W, { voice = true, audio = function(e)
      assert.are.equal("quest.description:456:生き物", e.key)
      return { clips = { { folder = "WoWForeverJapanese_VoiceA", file = "q456-d-1.mp3" },
        { folder = "WoWForeverJapanese_VoiceA", file = "q456-d-2.mp3" } } }
    end }))
    assert.are.same({ "WoWForeverJapanese_VoiceA/Sound/q456-d-1.mp3", "WoWForeverJapanese_VoiceA/Sound/q456-d-2.mp3" },
      t.rows[1].audio)
  end)

  it("has no sound file for a word without audio, and none at all with no pack loaded", function()
    save(W)
    local t = A.build(W.entries(), T, deps(W))
    assert.is_false(t.voice)
    assert.are.same({}, t.rows[1].audio)
  end)

  it("gives a word saved by an older version its furigana and audio, from the fields it has", function()
    -- the saved shape before any later field: no shot, no lang
    W.load({ schema = 1, entries = { { key = "quest.description:456:生き物", word = "生き物", reading = "いきもの",
      lemma = "生き物", lemmaReading = "いきもの", meaning = "living thing", sentence = "少しの生き物たちを狩り、数を減らしてほしい。",
      wf = 10, wl = 18, kind = "quest.description", id = 456, source = "quest", saved = T } } })
    local row = A.build(W.entries(), T, deps(W, { voice = true, audio = function()
      return { clips = { { folder = "P", file = "a.mp3" } } }
    end })).rows[1]
    assert.are.equal("少しの<b>生[い]き 物[もの]</b>たちを狩り、数を減らしてほしい。", row.sentenceFurigana)
    assert.are.same({ "P/Sound/a.mp3" }, row.audio)
    assert.are.equal("", row.shot)
    assert.are.equal("", row.questTitle)
  end)

  it("exports an English word with its Japanese sentence and no furigana brackets", function()
    local text = "Hunt a few creatures. I am well."
    save(W, { text = text, word = "creatures", reading = "KREE-churz", meaning = "生き物 (いきもの)",
      english = { jaSentence = "少しの生き物たちを狩ってほしい。" } })
    local row = A.build(W.entries(), T, deps(W)).rows[1]
    assert.are.equal("en", row.lang)
    assert.are.equal("creatures", row.wordFurigana)
    assert.are.equal("Hunt a few <b>creatures</b>.", row.sentenceFurigana)
    assert.are.equal("少しの生き物たちを狩ってほしい。", row.jaSentence)
    assert.are.equal("", row.lemma)
  end)

  it("exports a list saved by a newer version, as the export window does", function()
    W.load({ schema = 99, entries = { { key = "k", word = "数", reading = "かず", sentence = "数を減らせ。", wf = 1, wl = 3,
      kind = "quest.description", id = 1, extra = { 1 } } } })
    assert.is_true(W.readonly())
    local t = A.build(W.entries(), T, deps(W))
    assert.are.equal(1, #t.rows)
    assert.are.equal("k", t.rows[1].key)
    assert.are.equal("", t.rows[1].meaning)
  end)

  describe("save", function()
    it("gives the new table to keep", function()
      save(W)
      local old = { schema = 1, written = 5, voice = false, rows = {} }
      local t = A.save(old, W.entries(), T, deps(W))
      assert.are.equal(T, t.written)
      assert.are.equal(1, #t.rows)
    end)

    it("keeps the table that was loaded when building fails, and reports the fault", function()
      save(W)
      local old = { schema = 1, written = 5, voice = false, rows = { { key = "kept" } } }
      local d = deps(W, { audio = function() error("boom") end })
      local reported
      local t = A.save(old, W.entries(), T, d, function(err) reported = err end)
      assert.are.equal(old, t)
      assert.is_truthy(tostring(reported):find("boom", 1, true))
    end)
  end)

  it("builds a thousand words quickly enough for a logout", function()
    local entries = {}
    for i = 1, 1000 do
      entries[i] = { key = "quest.description:" .. i .. ":生き物", word = "生き物", reading = "いきもの", lemma = "生き物",
        lemmaReading = "いきもの", meaning = "living thing", sentence = "少しの生き物たちを狩り、数を減らしてほしい。", wf = 10, wl = 18,
        kind = "quest.description", id = i, source = "quest", saved = T }
    end
    local t0 = os.clock()
    local t = A.build(entries, T, deps(W))
    assert.are.equal(1000, #t.rows)
    assert.is_true(os.clock() - t0 < 0.5)
  end)
end)
