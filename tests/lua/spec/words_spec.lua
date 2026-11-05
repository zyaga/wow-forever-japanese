-- The saved word list (ADR-069): keys, sentences, the saved table, the export text and the save-click choices.
local H = require("tests.lua.spec.helpers")

local function load()
  local ns = {}
  H.loadPure("Core/Words.lua", nil, ns)
  return ns.Words
end

-- date() as the client has it (os.date), fixed to UTC so the expected text does not depend on the machine.
local function fmt(pattern, t) return os.date("!" .. pattern, t) end

local T = 1790000000 -- a fixed moment, printed in UTC by fmt

local function input(o)
  local text = o.text or "少しの生き物たちを狩り、数を減らしてほしい。私は元気だ。"
  local word = o.word or "生き物"
  local first = o.first or text:find(word, 1, true)
  local i = {
    kind = "quest.description", id = 456, surface = "questframe.detail", text = text, first = first,
    last = first + #word - 1, word = word, reading = "いきもの", lemma = "生き物", lemmaReading = "いきもの",
    meaning = "living thing", questTitle = "生き物を減らせ",
  }
  for k, v in pairs(o) do i[k] = v end
  return i
end

describe("Words", function()
  local W

  before_each(function()
    W = load()
    W.load(nil)
  end)

  describe("key and source", function()
    it("is the source key and the dictionary form, or the word when there is no dictionary form", function()
      assert.are.equal("quest.description:456:生き物", W.key("quest.description", 456, "生き物", "生き物たち"))
      assert.are.equal("gossip:0123456789abcdef:狩る", W.key("gossip", "0123456789abcdef", "狩る", "狩り"))
      assert.are.equal("ui:QUEST_REWARDS:報酬", W.key("ui", "QUEST_REWARDS", nil, "報酬"))
      assert.are.equal("book:bk1:悪魔", W.key("book", "bk1", "", "悪魔"))
    end)

    it("comes from the surface, so a quest-window line keyed by its English is still a quest", function()
      assert.are.equal("quest", W.source("questframe.detail", "quest.description"))
      assert.are.equal("quest", W.source("questframe.progress", "gossip"))
      assert.are.equal("quest", W.source("questmap.info", "quest.description"))
      assert.are.equal("gossip", W.source("gossip", "gossip"))
      assert.are.equal("book", W.source("itemtext", "book"))
      assert.are.equal("window", W.source("character", "ui"))
      assert.are.equal("quest", W.source("voicepanel", "quest.progress"))
      assert.are.equal("gossip", W.source("voicepanel", "gossip"))
      assert.are.equal("book", W.source("voicepanel", "book"))
    end)
  end)

  describe("sentence", function()
    it("cuts at 。！？!? and line breaks, and returns the word's place inside it", function()
      local text = "前の文。少しの生き物たちを狩り、数を減らしてほしい！次の文"
      local f = text:find("生き物", 1, true)
      local s, wf, wl = W.sentence(text, f, f + #"生き物" - 1)
      assert.are.equal("少しの生き物たちを狩り、数を減らしてほしい！", s)
      assert.are.equal("生き物", s:sub(wf, wl))
      local text2 = "一行目\n二行目の生き物?三"
      local f2 = text2:find("生き物", 1, true)
      assert.are.equal("二行目の生き物?", (W.sentence(text2, f2, f2 + #"生き物" - 1)))
    end)

    it("caps a long sentence at 200 bytes around the word without splitting a character", function()
      local text = ("あ"):rep(150) .. "生き物" .. ("い"):rep(150)
      local f = text:find("生き物", 1, true)
      local s, wf, wl = W.sentence(text, f, f + #"生き物" - 1)
      assert.is_true(#s <= 200)
      assert.are.equal("生き物", s:sub(wf, wl))
      -- every byte run is whole characters: re-reading it as UTF-8 leaves no stray continuation byte at either end
      local c1, cn = s:byte(1), s:byte(#s - 2)
      assert.is_true(c1 >= 0xC0)
      assert.is_true(cn >= 0xC0)
    end)
  end)

  describe("add", function()
    it("adds one entry with every field, and a second save of the same key adds nothing", function()
      local status, e = W.add(input({}), T)
      assert.are.equal("added", status)
      assert.are.equal(1, W.count())
      assert.are.equal("quest.description:456:生き物", e.key)
      assert.are.equal("生き物", e.word)
      assert.are.equal("いきもの", e.reading)
      assert.are.equal("生き物", e.lemma)
      assert.are.equal("living thing", e.meaning)
      assert.are.equal("少しの生き物たちを狩り、数を減らしてほしい。", e.sentence)
      assert.are.equal("生き物", e.sentence:sub(e.wf, e.wl))
      assert.are.equal("quest", e.source)
      assert.are.equal(456, e.questId)
      assert.are.equal("生き物を減らせ", e.questTitle)
      assert.are.equal(T, e.saved)
      local again = W.add(input({ word = "生き物" }), T + 5)
      assert.are.equal("exists", again)
      assert.are.equal(1, W.count())
    end)

    it("a quest-window line keyed by its English has no quest id or title", function()
      local _, e = W.add(input({ kind = "gossip", id = "0123456789abcdef", surface = "questframe.progress" }), T)
      assert.are.equal("quest", e.source)
      assert.is_nil(e.questId)
      assert.is_nil(e.questTitle)
    end)

    it("turns tabs and line breaks inside fields into spaces", function()
      local _, e = W.add(input({ meaning = "a\tb\nc", reading = "い\rき" }), T)
      assert.are.equal("a b c", e.meaning)
      assert.are.equal("い き", e.reading)
    end)

    it("a word without a meaning keys on the word and keeps an empty meaning", function()
      local i = input({ word = "数", reading = "かず" })
      i.lemma, i.lemmaReading, i.meaning = nil, nil, nil
      local _, e = W.add(i, T)
      assert.are.equal("quest.description:456:数", e.key)
      assert.are.equal("", e.meaning)
      assert.are.equal("", e.lemma)
    end)

    it("refuses a malformed input", function()
      assert.are.equal("refused", (W.add({ kind = "quest.description" }, T)))
      assert.are.equal(0, W.count())
    end)
  end)

  describe("the saved table", function()
    it("starts a fresh list from nothing or a garbled value", function()
      for _, v in ipairs({ false, "x", 3, { entries = "no" } }) do
        local t = W.load(v)
        assert.are.equal(W.SCHEMA, t.schema)
        assert.are.equal(0, W.count())
      end
    end)

    it("keeps what was saved, rebuilds the key index, and never writes the index to disk", function()
      local saved = W.load({ schema = 1, entries = { { key = "quest.description:456:生き物", word = "生き物" }, "junk",
        { word = "no key" }, { key = "k2", word = "b" } }, everSaved = true })
      assert.are.equal(2, W.count())
      assert.is_nil(saved.keys)
      assert.is_true(W.everSaved())
      assert.are.equal("exists", (W.add(input({}), T)))
      assert.are.equal(2, W.count())
    end)

    it("a list from a newer version is kept untouched and refuses save, Remove last and Clear all", function()
      local newer = { schema = W.SCHEMA + 1, entries = { { key = "k", word = "w" } }, future = true }
      local t = W.load(newer)
      assert.are.equal(newer, t)
      assert.is_true(W.readonly())
      assert.are.equal("refused", (W.add(input({}), T)))
      assert.is_nil(W.removeLast())
      assert.is_nil(W.clear())
      assert.are.equal(1, #newer.entries)
    end)

    it("Remove last and Clear all update the index; everSaved survives Clear all", function()
      W.add(input({}), T)
      W.add(input({ word = "数", lemma = "数" }), T)
      assert.are.equal("数", W.removeLast().word)
      assert.are.equal(1, W.count())
      assert.are.equal("added", (W.add(input({ word = "数", lemma = "数" }), T)))
      assert.are.equal(2, W.clear())
      assert.are.equal(0, W.count())
      assert.is_true(W.everSaved())
      assert.are.equal("added", (W.add(input({}), T)))
    end)
  end)

  describe("export", function()
    it("writes Anki's header lines, then one line per entry with the word in bold by its place", function()
      local text = "生き物と生き物。"
      local second = text:find("生き物", 4, true)
      W.add(input({ text = text, first = second }), T)
      W.add(input({ kind = "gossip", id = "g1", surface = "gossip", word = "数", reading = "かず", lemma = "数",
        lemmaReading = "かず", meaning = "number", text = "数が多い。" }), T)
      local out = W.export({}, fmt)
      local lines = {}
      for l in (out .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = l end
      assert.are.equal("#separator:Tab", lines[1])
      assert.are.equal("#html:true", lines[2])
      assert.is_truthy(lines[3]:find("^#columns:Key\tWord\tReading"))
      local row = {}
      for c in (lines[4] .. "\t"):gmatch("([^\t]*)\t") do row[#row + 1] = c end
      assert.are.same({ "quest.description:456:生き物", "生き物", "いきもの", "生き物", "いきもの", "living thing",
        "生き物と<b>生き物</b>。", "quest", "456", "生き物を減らせ", fmt("%Y-%m-%d %H:%M", T) }, row)
      assert.is_truthy(lines[5]:find("^gossip:g1:数\t数\tかず"))
      assert.is_truthy(lines[5]:find("\tgossip\t\t\t", 1, true))
      assert.are.equal(5, #lines)
    end)

    it("adds the image column only when asked, empty for an entry without a screenshot", function()
      local _, e = W.add(input({}), T)
      W.setShot(e, "WoWScrnShot_092126_165320.jpg")
      W.add(input({ word = "数", lemma = "数" }), T)
      local out = W.export({ images = true }, fmt)
      assert.is_truthy(out:find("\tImage\n", 1, true))
      assert.is_truthy(out:find('\t<img src="WoWScrnShot_092126_165320.jpg">\n', 1, true))
      assert.is_truthy(out:find("\t$"))
      assert.is_nil(W.export({}, fmt):find("<img", 1, true))
    end)

    it("names a screenshot the way the client does, with the format's extension", function()
      assert.are.equal("WoWScrnShot_" .. fmt("%m%d%y_%H%M%S", T) .. ".jpg", W.shotName(T, "jpeg", fmt))
      assert.are.equal("WoWScrnShot_" .. fmt("%m%d%y_%H%M%S", T) .. ".png", W.shotName(T, "png", fmt))
      assert.are.equal("WoWScrnShot_" .. fmt("%m%d%y_%H%M%S", T) .. ".tga", W.shotName(T, "tga", fmt))
      assert.are.equal("WoWScrnShot_" .. fmt("%m%d%y_%H%M%S", T) .. ".jpg", W.shotName(T, nil, fmt))
    end)
  end)

  describe("the save click", function()
    it("matches only the chosen modifier set", function()
      assert.is_true(W.matches("ctrl", true, false, false))
      assert.is_false(W.matches("ctrl", true, true, false))
      assert.is_false(W.matches("ctrl", false, false, false))
      assert.is_true(W.matches("shift", false, true, false))
      assert.is_true(W.matches("meta", false, false, true))
      assert.is_false(W.matches("meta", true, false, true))
      assert.is_true(W.matches("click", false, false, false))
      assert.is_false(W.matches("click", true, false, false))
      assert.is_false(W.matches("off", false, false, false))
      assert.is_false(W.matches("off", true, false, false))
    end)

    it("hides the reveal key's modifier and Cmd off a Mac", function()
      assert.is_true(W.hidden("ctrl", "lctrl", true))
      assert.is_true(W.hidden("shift", "shift", true))
      assert.is_false(W.hidden("ctrl", "alt", true))
      assert.is_false(W.hidden("ctrl", "Q", true))
      assert.is_true(W.hidden("meta", "alt", false))
      assert.is_false(W.hidden("meta", "alt", true))
      assert.is_false(W.hidden("click", "ctrl", false))
      assert.is_false(W.hidden("off", "ctrl", false))
    end)

    it("moves a hidden choice to the next free one", function()
      assert.are.equal("shift", W.nextFree("ctrl", "rctrl", false))
      assert.are.equal("ctrl", W.nextFree("shift", "shift", true))
      assert.are.equal("ctrl", W.nextFree("meta", "alt", false))
      assert.are.equal("shift", W.nextFree("meta", "ctrl", false))
      assert.are.equal("click", W.nextFree("click", "ctrl", false))
      assert.are.equal("ctrl", W.nextFree("ctrl", "alt", true))
    end)
  end)
end)
