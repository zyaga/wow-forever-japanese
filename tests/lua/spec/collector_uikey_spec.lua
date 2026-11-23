-- Core/Collector and Core/CollectorSend: the name of an interface string seen in chat, kept without any text.
local H = require("tests.lua.spec.helpers")

local function loadCollector()
  H.coreStub()
  local ns = H.loadChunks({ "Core/Const.lua", "Core/Normalize.lua", "Core/Hash.lua", "Core/State.lua",
    "Core/Settings.lua" })
  H.loadPure("Core/Collector.lua", nil, ns)
  H.loadPure("Core/CollectorSend.lua", nil, ns)
  return ns
end

describe("the collector's interface string names", function()
  local C, S, db, enabled, shipped, prints, payloads
  local NAME, KEY = "DRUNK_MESSAGE_OTHER1", "uikey:DRUNK_MESSAGE_OTHER1"

  local function deps()
    local d = H.collectorDeps({ enabled = function() return enabled end })
    d.uiKey = function(name) return shipped[name] == true end
    d.print = function(msg) prints[#prints + 1] = msg end
    return d
  end

  before_each(function()
    local WFJ = loadCollector()
    C, S = WFJ.Collector, WFJ.CollectorSend
    enabled, shipped, prints, payloads = true, {}, {}, {}
    db = C.load(nil, deps())
    S.init({ version = function() return "1.2.3" end, encode = function(payload)
      payloads[#payloads + 1] = payload
      return "AAAA"
    end })
  end)

  it("stores the kind, the name and the build, and nothing else", function()
    assert.are.equal("recorded", C.recordUiKey(NAME))
    assert.are.same({ t = "uikey", i = NAME, b = 1 }, db.entries[KEY])
    assert.are.same({ "1.15.9.69722" }, db.builds)
    assert.are.equal(C.size(KEY), db.bytes)
    assert.are.equal("seen", C.recordUiKey(NAME))
    assert.are.equal(1, C.status().entries)
    assert.are.equal(1, C.unsentCount()) -- a line to translate: it counts, unlike an NPC name
  end)

  it("off records nothing; a name that is no interface string's is refused", function()
    enabled = false
    assert.are.equal("off", C.recordUiKey(NAME))
    assert.is_nil(next(db.entries))
    enabled = true
    for _, bad in ipairs({ "", "lower_case", "Has Space", "Rex seems to be sobering up.", "9LIVES", "A-B", 12,
      ("A"):rep(C.UI_KEY_MAX + 1) }) do
      assert.are.same({ "refused", "bad_id" }, { C.recordUiKey(bad) }, tostring(bad))
    end
    assert.is_nil(next(db.entries))
    assert.are.equal(0, C.status().errors)
  end)

  it("a name the addon ships Japanese for is known, and a stored one goes once it is", function()
    shipped[NAME] = true
    assert.are.equal("known", C.recordUiKey(NAME))
    assert.is_nil(next(db.entries))
    shipped[NAME] = nil
    db = C.load(nil, deps()) -- a new session: the memo is empty
    assert.are.equal("recorded", C.recordUiKey(NAME))
    assert.are.equal(1, C.unsentCount())
    shipped[NAME] = true -- a newer addon translates it
    assert.are.equal(0, C.unsentCount())
    assert.are.equal(0, #(C.pending()))
    assert.are.equal(1, C.prune())
    assert.is_nil(next(db.entries))
    assert.are.equal(0, db.bytes)
  end)

  it("respects the cap, with the one print", function()
    db.bytes = C.CAP_BYTES - 10
    assert.are.equal("capped", C.recordUiKey(NAME))
    assert.are.equal("capped", C.recordUiKey("ANOTHER_NAME"))
    assert.is_true(db.capped)
    assert.are.equal(1, #prints)
    assert.is_nil(next(db.entries))
  end)

  it("a file's entry survives a load only in its own shape: never with text on it", function()
    local function saved(entry, key)
      return { version = 1, builds = { "1.15.9.69722" }, entries = { [key or KEY] = entry },
        sent = { [key or KEY] = NAME } }
    end
    db = C.load(saved({ t = "uikey", i = NAME, b = 1 }), deps())
    assert.are.same({ t = "uikey", i = NAME, b = 1 }, db.entries[KEY])
    assert.are.equal(NAME, db.sent[KEY]) -- sent before: the row holds the name, there being no hash
    assert.are.equal(0, C.unsentCount())
    assert.is_true(C.onDisk(KEY, NAME))
    for _, bad in ipairs({
      { t = "uikey", i = NAME, b = 1, e = "Rex seems to be sobering up." },
      { t = "uikey", i = NAME, b = 1, h = "0123456789abcdef" },
      { t = "uikey", i = NAME, b = 1, f = "text" },
      { t = "uikey", i = NAME, b = 1, p = "Rex|Human" },
      { t = "uikey", i = NAME, b = 1, n = { 5 } },
      { t = "uikey", i = "Rex seems to be sobering up.", b = 1 },
      { t = "uikey", i = NAME, b = 9 },
    }) do
      db = C.load(saved(bad), deps())
      assert.is_nil(next(db.entries))
      assert.is_nil(next(db.sent))
    end
    db = C.load(saved({ t = "uikey", i = NAME, b = 1 }, "uikey:OTHER_NAME"), deps())
    assert.is_nil(next(db.entries))
  end)

  it("the send carries the name and the build only, and I sent it marks it", function()
    C.record("quest", 7, "title", "A Title")
    C.recordUiKey(NAME)
    local pk = S.pack()
    assert.are.equal("link", pk.mode)
    assert.are.equal(2, pk.count)
    local p = payloads[#payloads]
    assert.are.equal(1, p.v)
    assert.are.same({ t = "uikey", i = NAME, b = 1 }, p.e[2]) -- sorted by key: quest:… before uikey:…
    assert.are.same({ key = KEY, h = NAME }, pk.sent[2])
    assert.are.equal(2, S.markSent(pk))
    assert.are.equal(NAME, db.sent[KEY])
    assert.are.equal(0, C.unsentCount())
    assert.are.equal("empty", S.pack().mode)
    assert.are.equal(2, S.pack(true).count) -- send all packs it again
    C.clear()
    assert.is_nil(next(db.sent))
    assert.are.equal("recorded", C.recordUiKey(NAME))
  end)

  it("a name alone is a reason to send", function()
    C.recordUiKey(NAME)
    local pk = S.pack()
    assert.are.equal("link", pk.mode)
    assert.are.equal(1, pk.count)
    assert.are.same({ { t = "uikey", i = NAME, b = 1 } }, payloads[#payloads].e)
  end)

  it("a file from a newer version is left alone", function()
    local file = { version = 2, entries = {} }
    db = C.load(file, deps())
    assert.are.same({ "refused", "read_only" }, { C.recordUiKey(NAME) })
    assert.is_nil(next(file.entries))
  end)
end)
