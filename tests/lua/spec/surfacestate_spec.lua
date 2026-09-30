local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

describe("SurfaceState: the capture, apply and restore state machine", function()
  local WFJ, SS
  local JA = { path = "Interface\\AddOns\\WoWForeverJapanese\\Fonts\\ipagui.ttf", size = 13, flags = "" }

  before_each(function()
    WFJ = {}
    H.loadPure("Core/SurfaceState.lua", "WoWForeverJapanese", WFJ)
    SS = WFJ.SurfaceState
    Stub.fontSetFails = false
  end)

  local CASES = {
    { "ascii", "Kill 10 kobolds." },
    { "japanese", "コボルドを10体倒せ。" },
    { "colour codes", "|cffff0000Red|r text |cff00ff00green|r" },
    { "empty", "" },
    { "trailing whitespace", "Text with trailing  \n" },
  }

  for _, c in ipairs(CASES) do
    it("capture → apply → restore is byte-identical (" .. c[1] .. ")", function()
      local fs = Stub.fontString(c[2], "Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
      assert.is_truthy(SS.capture("quest", "description", fs, c[2]))
      assert.is_true((SS.apply("quest", "description", "日本語", JA)))
      assert.are.equal("日本語", fs:GetText())
      assert.are.same({ JA.path, 13, "" }, { fs:GetFont() })
      assert.is_true(SS.restore("quest", "description"))
      assert.are.equal(c[2], fs:GetText())
      assert.are.same({ "Fonts\\FRIZQT__.TTF", 14, "OUTLINE" }, { fs:GetFont() })
      assert.is_false(SS.restore("quest", "description")) -- nothing applied, nothing written
    end)
  end

  it("a refused SetFont records no applied font; the next apply tries again", function()
    local fs = Stub.fontString("English", "Fonts\\FRIZQT__.TTF", 14, "")
    SS.capture("quest", "k", fs, "English")
    Stub.fontSetFails = true
    local ok, fontOk = SS.apply("quest", "k", "日本語", JA)
    assert.is_true(ok); assert.is_false(fontOk)
    assert.is_nil(SS.get("quest", "k").appliedFont)
    Stub.fontSetFails = false
    local before = fs.calls.SetFont
    local _, retried = SS.apply("quest", "k", "日本語", JA)
    assert.is_true(retried)
    assert.are.equal(before + 1, fs.calls.SetFont)
    assert.are.same({ JA.path, 13, "" }, { fs:GetFont() })
    assert.is_true(SS.restore("quest", "k"))
    assert.are.same({ "Fonts\\FRIZQT__.TTF", 14, "" }, { fs:GetFont() })
  end)

  it("refuses a capture that echoes our own applied text and keeps the record", function()
    local fs = Stub.fontString("English")
    SS.capture("quest", "k", fs, "English")
    SS.apply("quest", "k", "日本語", JA)
    assert.is_nil(SS.capture("quest", "k", fs, "日本語"))
    local rec = SS.get("quest", "k")
    assert.are.equal("English", rec.en)
    assert.are.equal("日本語", rec.applied)
    assert.are.equal(1, SS.count("quest"))
  end)

  it("re-capturing a key with new English replaces the record and keeps the original font", function()
    local fs = Stub.fontString("Old", "F.ttf", 11, "")
    SS.capture("log", "description", fs, "Old")
    SS.apply("log", "description", "古い", JA)
    -- the client rewrote the text (another quest selected); our font is still on the widget
    fs.text = "New"
    assert.is_truthy(SS.capture("log", "description", fs, "New"))
    local rec = SS.get("log", "description")
    assert.are.equal("New", rec.en)
    assert.is_nil(rec.applied)
    assert.are.same({ path = "F.ttf", size = 11, flags = "" }, rec.font)
    SS.apply("log", "description", "新しい", JA)
    SS.restore("log", "description")
    assert.are.equal("New", fs:GetText())
    assert.are.same({ "F.ttf", 11, "" }, { fs:GetFont() })
  end)

  it("a different key on the same FontString (pool reuse) drops the older record silently", function()
    local fs = Stub.fontString("Option A", "F.ttf", 11, "")
    SS.capture("gossip", 1, fs, "Option A")
    SS.apply("gossip", 1, "選択肢A", JA)
    local before = { fs.calls.SetText, fs.calls.SetFont }
    fs.text = "Option B"
    assert.is_truthy(SS.capture("gossip", 2, fs, "Option B"))
    assert.are.same(before, { fs.calls.SetText, fs.calls.SetFont })
    assert.is_nil(SS.get("gossip", 1))
    assert.are.equal(1, SS.count("gossip"))
    -- the original font travelled with the widget
    assert.are.same({ path = "F.ttf", size = 11, flags = "" }, SS.get("gossip", 2).font)
  end)

  it("release restores only that surface's applied records and drops them all", function()
    local a1, a2, b1 = Stub.fontString("A1"), Stub.fontString("A2"), Stub.fontString("B1")
    SS.capture("A", 1, a1, "A1"); SS.apply("A", 1, "あ1", JA)
    SS.capture("A", 2, a2, "A2") -- captured, never applied
    SS.capture("B", 1, b1, "B1"); SS.apply("B", 1, "び1", JA)
    assert.are.equal(1, SS.release("A"))
    assert.are.equal("A1", a1:GetText())
    assert.are.equal("A2", a2:GetText())
    assert.are.equal("び1", b1:GetText())
    assert.are.equal(0, SS.count("A"))
    assert.are.equal(1, SS.count("B"))
    assert.are.equal(0, SS.release("nobody"))
  end)

  it("reapply re-writes the last applied text and font after a restore", function()
    local fs = Stub.fontString("En")
    SS.capture("q", "k", fs, "En")
    SS.apply("q", "k", "日", JA)
    SS.restore("q", "k")
    assert.is_true(SS.reapply("q", "k"))
    assert.are.equal("日", fs:GetText())
    assert.are.equal(JA.path, (fs:GetFont()))
    assert.is_false(SS.reapply("q", "k")) -- already applied
  end)

  it("apply without a font restores the original font; apply reports the SetFont result", function()
    local fs = Stub.fontString("En", "F.ttf", 11, "")
    SS.capture("q", "k", fs, "En")
    local ok, fontOk = SS.apply("q", "k", "日", JA)
    assert.is_true(ok); assert.is_true(fontOk)
    SS.apply("q", "k", "En ·", nil)
    assert.are.same({ "F.ttf", 11, "" }, { fs:GetFont() })
    assert.are.equal("En ·", fs:GetText())
    assert.is_false((SS.apply("q", "missing", "x")))
    Stub.fontSetFails = true
    SS.capture("q", "k2", Stub.fontString("x"), "x")
    ok, fontOk = SS.apply("q", "k2", "y", JA)
    assert.is_true(ok); assert.is_false(fontOk)
  end)

  it("records/surfaces expose live state", function()
    local fs = Stub.fontString("En")
    SS.capture("q", "k", fs, "En"); SS.apply("q", "k", "日", JA)
    assert.is_truthy(SS.records("q").k)
    assert.is_truthy(SS.surfaces().q)
    assert.are.same({}, SS.records("nobody"))
  end)

  -- The widget keeps our font across a re-capture; restore must put the original back even when
  -- nothing was applied to the NEW record (the untranslated-after-translated path).
  it("B1a: same key re-captured → restore puts the original font back with no apply in between", function()
    local fs = Stub.fontString("Quest A", "F.ttf", 14, "")
    SS.capture("log", "description", fs, "Quest A")
    SS.apply("log", "description", "クエストA", JA)
    fs.text = "Quest B" -- client selected an untranslated quest
    SS.capture("log", "description", fs, "Quest B")
    assert.is_true(SS.restore("log", "description"))
    assert.are.equal("Quest B", fs:GetText())
    assert.are.same({ "F.ttf", 14, "" }, { fs:GetFont() })
    assert.is_false(SS.restore("log", "description"))
  end)

  it("B1b: pool reuse under a new key → restore on the new key puts the original font back", function()
    local fs = Stub.fontString("Option A", "F.ttf", 11, "")
    SS.capture("gossip", 1, fs, "Option A"); SS.apply("gossip", 1, "選択肢A", JA)
    fs.text = "Option B"
    SS.capture("gossip", 2, fs, "Option B")
    assert.is_true(SS.restore("gossip", 2))
    assert.are.same({ "F.ttf", 11, "" }, { fs:GetFont() })
    assert.are.equal("Option B", fs:GetText())
  end)

  it("B1c: a widget reused ACROSS surfaces drops the other surface's record and carries the fonts", function()
    local fs = Stub.fontString("Use: heal", "F.ttf", 12, "")
    SS.capture("item", 1, fs, "Use: heal"); SS.apply("item", 1, "使用: 回復", JA)
    fs.text = "Instant cast"
    SS.capture("spell", 1, fs, "Instant cast")
    assert.are.equal(0, SS.count("item"))
    assert.are.same({ path = "F.ttf", size = 12, flags = "" }, SS.get("spell", 1).font)
    assert.are.equal(1, SS.release("spell"))
    assert.are.same({ "F.ttf", 12, "" }, { fs:GetFont() })
    assert.are.equal("Instant cast", fs:GetText())
    assert.are.equal(0, SS.release("item")) -- nothing left to write stored English with
    assert.are.equal("Instant cast", fs:GetText())
  end)

  it("B1d: the same key re-seated on another widget restores the old widget's font", function()
    local fs1 = Stub.fontString("Quest A", "F.ttf", 14, "")
    local fs2 = Stub.fontString("Quest A", "G.ttf", 10, "OUTLINE")
    SS.capture("log", "description", fs1, "Quest A"); SS.apply("log", "description", "クエストA", JA)
    SS.capture("log", "description", fs2, "Quest A")
    assert.are.same({ "F.ttf", 14, "" }, { fs1:GetFont() })
    assert.are.equal("クエストA", fs1:GetText()) -- text is the client's to rewrite on reuse
    assert.are.same({ path = "G.ttf", size = 10, flags = "OUTLINE" }, SS.get("log", "description").font)
    assert.is_nil(SS.get("log", "description").appliedFont)
  end)

  it("apply after a carried font is a no-op on SetFont", function()
    local fs = Stub.fontString("A", "F.ttf", 14, "")
    SS.capture("q", "k", fs, "A"); SS.apply("q", "k", "あ", JA)
    fs.text = "B"
    SS.capture("q", "k", fs, "B")
    local n = fs.calls.SetFont
    SS.apply("q", "k", "ぶ", JA)
    assert.are.equal(n, fs.calls.SetFont)
    assert.are.equal("ぶ", fs:GetText())
  end)
end)

describe("SurfaceState.drop / dropAll: forget without restoring over the client's new text", function()
  local WFJ, SS
  local JA = { path = "Interface\\AddOns\\WoWForeverJapanese\\Fonts\\ipagui.ttf", size = 13, flags = "" }

  before_each(function()
    WFJ = {}
    H.loadPure("Core/SurfaceState.lua", "WoWForeverJapanese", WFJ)
    SS = WFJ.SurfaceState
    Stub.fontSetFails = false
  end)

  it("client rewrote the widget → font reset only, the client's new text stays", function()
    local fs = Stub.fontString("Quest A", "F.ttf", 14, "")
    SS.capture("s", "title", fs, "Quest A", {})
    SS.apply("s", "title", "クエストA", JA)
    fs.text = "Quest B - (Failed)" -- the client wrote a new quest we did not capture
    local n = fs.calls.SetText
    assert.is_true(SS.drop("s", "title"))
    assert.are.equal("Quest B - (Failed)", fs:GetText())
    assert.are.equal(n, fs.calls.SetText)
    assert.are.same({ "F.ttf", 14, "" }, { fs:GetFont() })
    assert.is_nil(SS.get("s", "title"))
  end)

  it("client did not touch the widget (our text still applied) → the client's English is put back", function()
    local fs = Stub.fontString("Quest A", "F.ttf", 14, "")
    SS.capture("s", "description", fs, "Quest A", {})
    SS.apply("s", "description", "クエストA", JA)
    assert.is_true(SS.drop("s", "description"))
    assert.are.equal("Quest A", fs:GetText())
    assert.are.same({ "F.ttf", 14, "" }, { fs:GetFont() })
    assert.is_nil(SS.get("s", "description"))
  end)

  it("nothing applied → nothing written; unknown key → false", function()
    local fs = Stub.fontString("Quest A")
    SS.capture("s", "k", fs, "Quest A", {})
    local n, m = fs.calls.SetText, fs.calls.SetFont
    assert.is_false(SS.drop("s", "k"))
    assert.are.equal(n, fs.calls.SetText); assert.are.equal(m, fs.calls.SetFont)
    assert.is_false(SS.drop("s", "k"))
    assert.is_false(SS.drop("nobody", "k"))
  end)

  it("a carried font from a replaced record is reset by drop even with no text applied", function()
    local fs = Stub.fontString("Quest A", "F.ttf", 14, "")
    SS.capture("s", "title", fs, "Quest A", {})
    SS.apply("s", "title", "クエストA", JA)
    fs.text = "Quest B"
    SS.capture("s", "title", fs, "Quest B", {}) -- carries appliedFont, applied = nil
    assert.is_true(SS.drop("s", "title"))
    assert.are.equal("Quest B", fs:GetText())
    assert.are.same({ "F.ttf", 14, "" }, { fs:GetFont() })
  end)

  it("dropAll forgets one surface only and reports the records that wrote", function()
    local a, b, c = Stub.fontString("A"), Stub.fontString("B"), Stub.fontString("C")
    SS.capture("s", "1", a, "A", {}); SS.apply("s", "1", "あ", JA)
    SS.capture("s", "2", b, "B", {})
    SS.capture("t", "1", c, "C", {}); SS.apply("t", "1", "う", JA)
    assert.are.equal(1, SS.dropAll("s"))
    assert.are.equal(0, SS.count("s"))
    assert.are.equal("A", a:GetText())
    assert.are.equal("う", c:GetText())
    assert.are.equal(1, SS.count("t"))
    assert.are.equal(0, SS.dropAll("s"))
  end)
end)
