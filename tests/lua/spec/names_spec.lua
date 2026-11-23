local H = require("tests.lua.spec.helpers")

describe("Core/Names (the Lua twin of wfj.core.names for names on screen)", function()
  local WFJ, V
  before_each(function()
    WFJ = {}
    H.coreStub()
    H.loadChunk("Core/Normalize.lua", "WoWForeverJapanese", WFJ)
    H.loadChunk("Core/Hash.lua", "WoWForeverJapanese", WFJ)
    H.loadChunk("Core/Data.lua", "WoWForeverJapanese", WFJ)
    H.loadChunk("Core/Names.lua", "WoWForeverJapanese", WFJ)
    V = dofile(H.ROOT .. "/vectors/name_vectors.lua")
  end)

  it("takes generated name rows", function()
    WFJ.Data.add("name", { ["0000004100000041"] = "ア\tあ" })
    assert.are.equal(1, WFJ.Data.count("name"))
  end)

  it("keys every vector name as the pipeline does", function()
    assert.is_true(#V.hashes >= 200)
    for _, c in ipairs(V.hashes) do
      assert.are.equal(c.key, WFJ.Names.key(c.en), c.en)
    end
  end)

  it("gives a known name's Japanese and reading, and nil for anything else", function()
    WFJ.Data.add("name", { [WFJ.Names.key("Thrall")] = "スロール\tすろーる" })
    local ja, reading = WFJ.Names.of("Thrall")
    assert.are.equal("スロール", ja)
    assert.are.equal("すろーる", reading)
    assert.is_nil(WFJ.Names.of("Nobody Known"))
    assert.is_nil(WFJ.Names.of(""))
    assert.is_nil(WFJ.Names.of(nil))
    assert.is_nil(WFJ.Names.of(12))
  end)

  it("answers the same name again without hashing it twice", function()
    WFJ.Data.add("name", { [WFJ.Names.key("Thrall")] = "スロール\tすろーる" })
    local calls, key = 0, WFJ.Hash.key
    WFJ.Hash.key = function(...) calls = calls + 1; return key(...) end
    WFJ.Names.of("Thrall"); WFJ.Names.of("Thrall"); WFJ.Names.of("Nobody Known"); WFJ.Names.of("Nobody Known")
    assert.are.equal(2, calls)
  end)

  it("gives a filled-in value its Japanese: a name as written, or a link with only its label changed", function()
    WFJ.Data.add("name", {
      [WFJ.Names.key("Linen Cloth")] = "リネン・クロス\tりねん・くろす",
      [WFJ.Names.key("Horde")] = "ホード\tほーど",
    })
    assert.are.equal("ホード", WFJ.Names.value("Horde"))
    assert.are.equal("|cffffffff|Hitem:2589::::::::1:::::|h[リネン・クロス]|h|r",
      WFJ.Names.value("|cffffffff|Hitem:2589::::::::1:::::|h[Linen Cloth]|h|r"))
    assert.are.equal("|Hitem:2589|h[リネン・クロス]|hx2", WFJ.Names.value("|Hitem:2589|h[Linen Cloth]|hx2"))
    assert.is_nil(WFJ.Names.value("|Hitem:1|h[Unknown Thing]|h"))
    assert.is_nil(WFJ.Names.value("Reyn"))
    assert.is_nil(WFJ.Names.value(nil))
  end)

  it("writes every vector line with its names in Japanese, as the pipeline does", function()
    WFJ.Data.add("name", V.names)
    assert.is_true(#V.lines >= 300)
    local html = 0
    for _, c in ipairs(V.lines) do
      if c.html then html = html + 1 end
      assert.are.equal(c.out, (WFJ.Names.inText(c.ja, c.html)), c.id)
    end
    assert.is_true(html > 0)
  end)

  it("reports where each name it wrote stands, with its English and reading", function()
    WFJ.Data.add("name", {
      [WFJ.Names.key("Stormwind")] = "ストームウィンド\tすとーむうぃんど",
      [WFJ.Names.key("Kobold Vermin")] = "コボルド・バーミン\tこぼるど・ばーみん",
    })
    local text, spans = WFJ.Names.inText("|cffffd100Stormwind|rでKobold Vermin 10匹とUnknown Placeを。")
    assert.are.equal("|cffffd100ストームウィンド|rでコボルド・バーミン 10匹とUnknown Placeを。", text)
    assert.are.equal(2, #spans)
    assert.are.equal("ストームウィンド", text:sub(spans[1].first, spans[1].last))
    assert.are.equal("Stormwind", spans[1].english)
    assert.are.equal("すとーむうぃんど", spans[1].reading)
    assert.are.equal("コボルド・バーミン", text:sub(spans[2].first, spans[2].last))
    assert.are.equal("Kobold Vermin", spans[2].english)
  end)

  it("leaves an icon, a Battle.net name code and a plural code as written, and still finds the names", function()
    WFJ.Data.add("name", {
      [WFJ.Names.key("Fishing")] = "フィッシング\tふぃっしんぐ",
      [WFJ.Names.key("a")] = "ア\tあ", [WFJ.Names.key("guide")] = "ガイド\tがいど",
    })
    local line = "|A:newplayerchat-chaticon-guide:0:0:0:0|a|Kq1|kとFishingを %d |4guide:guides;"
    assert.are.equal("|A:newplayerchat-chaticon-guide:0:0:0:0|a|Kq1|kとフィッシングを %d |4guide:guides;",
      (WFJ.Names.inText(line)))
  end)

  it("joins a suffixed item's two names inside a line too, when the whole name has no row", function()
    WFJ.Data.add("name", {
      [WFJ.Names.key("Bandit Cloak")] = "バンディット・クローク\tばんでぃっと・くろーく",
      [WFJ.Names.key("of the Owl")] = "オブ・ジ・アウル\tおぶ・じ・あうる",
    })
    local text, spans = WFJ.Names.inText("売却: Bandit Cloak of the Owl")
    assert.are.equal("売却: バンディット・クローク・オブ・ジ・アウル", text)
    assert.are.equal("Bandit Cloak of the Owl", spans[1].english)
    assert.are.equal("ばんでぃっと・くろーく・おぶ・じ・あうる", spans[1].reading)
  end)

  it("a text with markup in it is never looked up as a whole name: its colour or icon would be lost", function()
    WFJ.Data.add("name", { [WFJ.Names.key("Thunderfury")] = "サンダーフューリー\tさんだーふゅーりー" })
    assert.are.equal("サンダーフューリー", (WFJ.Names.of("Thunderfury")))
    assert.is_nil(WFJ.Names.of("|cffa335eeThunderfury|r"))
    assert.is_nil(WFJ.Names.item("|TInterface\\Icons\\x:0|t Thunderfury"))
    assert.is_nil(WFJ.Names.shown("$N1 Thunderfury"))
  end)

  it("a list shows only when every one of its names is known", function()
    WFJ.Data.add("name", {
      [WFJ.Names.key("Linen Cloth")] = "リネン・クロス\tりねん・くろす",
      [WFJ.Names.key("Coarse Thread")] = "コース・スレッド\tこーす・すれっど",
    })
    assert.are.equal("リネン・クロス (2), コース・スレッド", (WFJ.Names.list("Linen Cloth (2), Coarse Thread")))
    assert.is_nil(WFJ.Names.list("Linen Cloth (2), Somebody Else"))
  end)

  it("returns a line with no name in it untouched, with no spans", function()
    local text, spans = WFJ.Names.inText("名前のない行。")
    assert.are.equal("名前のない行。", text)
    assert.are.equal(0, #spans)
  end)

  it("joins a suffixed item's two names when the whole name has no line", function()
    WFJ.Data.add("name", {
      [WFJ.Names.key("Bandit Cloak")] = "バンディット・クローク\tばんでぃっと・くろーく",
      [WFJ.Names.key("of the Owl")] = "オブ・ザ・アウル\tおぶ・ざ・あうる",
      [WFJ.Names.key("Staff of Jordan")] = "スタッフ・オブ・ジョーダン\tすたっふ・おぶ・じょーだん",
    })
    local ja, reading = WFJ.Names.item("Bandit Cloak of the Owl")
    assert.are.equal("バンディット・クローク・オブ・ザ・アウル", ja)
    assert.are.equal("ばんでぃっと・くろーく・おぶ・ざ・あうる", reading)
    assert.are.equal("スタッフ・オブ・ジョーダン", (WFJ.Names.item("Staff of Jordan")))
    assert.is_nil(WFJ.Names.item("Bandit Cloak of the Unknown"))
    assert.is_nil(WFJ.Names.item("Unknown Cloak of the Owl"))
    assert.is_nil(WFJ.Names.item("of the Owl of the Owl of"))
  end)
end)
