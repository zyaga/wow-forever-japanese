-- Core/CollectorSend: what one send packs, which mode it takes at each size, and that it carries nothing personal.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local Loader = require("tests.lua.spec.loader")

local PLAYER = { name = "Reyn", class = "Hunter", race = "Night Elf" }

local function loadSend()
  H.coreStub()
  local ns = H.loadChunks({ "Core/Const.lua", "Core/Normalize.lua", "Core/Hash.lua", "Core/State.lua",
    "Core/Settings.lua" })
  H.loadPure("Core/Collector.lua", nil, ns)
  H.loadPure("Core/CollectorSend.lua", nil, ns)
  return ns
end

describe("Core/CollectorSend", function()
  local WFJ, C, S, payloads, out

  -- an encoder whose output is `out` characters long (sizes are what the modes are about), keeping each payload
  local function encoder()
    return function(payload)
      payloads[#payloads + 1] = payload
      return string.rep("A", out)
    end
  end

  before_each(function()
    WFJ = loadSend()
    C, S = WFJ.Collector, WFJ.CollectorSend
    payloads, out = {}, 100
    C.load(nil, H.collectorDeps({ player = function() return PLAYER end }))
    S.init({ encode = encoder(), version = function() return "1.2.3" end })
  end)

  it("packs the unsent entries into the documented payload, builds renumbered", function()
    C.record("quest", 7, "title", "A Title")
    C.recordGossip("Well met, Reyn. A hunter needs rest too.", "Creature-0-1-0-1-6740-0000000001")
    local pk = S.pack()
    assert.are.equal("link", pk.mode)
    assert.are.equal(2, pk.count)
    assert.are.equal(0, pk.shipped)
    assert.are.equal(S.PREFIX .. string.rep("A", 100), pk.text)
    local p = payloads[1]
    assert.are.same({ "a", "b", "e", "v" }, (function()
      local k = {}
      for x in pairs(p) do k[#k + 1] = x end
      table.sort(k)
      return k
    end)())
    assert.are.equal(1, p.v)
    assert.are.equal("1.2.3", p.a)
    assert.are.same({ "1.15.9.69722" }, p.b)
    local shape = { t = 1, i = 1, f = 1, h = 1, e = 1, b = 1, n = 1, p = 1 }
    for _, e in ipairs(p.e) do
      for k in pairs(e) do assert.is_truthy(shape[k], k) end
      assert.are.equal(1, e.b)
    end
    assert.are.equal("gossip", p.e[1].t) -- sorted by key: gossip:… before quest:…
    assert.are.same({ 6740 }, p.e[1].n)
    assert.are.equal("Hunter|Night Elf", p.e[1].p)
    assert.are.same({ "gossip:" .. p.e[1].h .. ":text", "quest:7:title" }, { pk.sent[1].key, pk.sent[2].key })
  end)

  it("the link carries the percent-encoded string in the form's dump field", function()
    C.record("quest", 7, "title", "A Title")
    S.init({ encode = function() return "ab-_c=" end })
    local pk = S.pack()
    assert.are.equal(S.ISSUE_URL .. "&dump=WFJC1%3Aab-_c%3D", pk.url)
    assert.are.equal(C.ISSUE_URL, S.ISSUE_URL)
    assert.is_truthy(S.ISSUE_URL:find("template=collector-send.yml", 1, true))
  end)

  it("link up to 6,000 characters of URL, then paste up to 60,000 of string, then the file", function()
    C.record("quest", 7, "title", "A Title")
    local overhead = #(S.ISSUE_URL .. "&dump=WFJC1%3A")
    out = S.URL_BUDGET - overhead
    assert.are.equal("link", S.pack().mode)
    out = out + 1
    local pk = S.pack()
    assert.are.equal("paste", pk.mode)
    assert.are.equal(S.ISSUE_URL, pk.url) -- the form opens empty; the string is pasted
    out = S.PASTE_BUDGET - #S.PREFIX
    assert.are.equal("paste", S.pack().mode)
    out = out + 1
    pk = S.pack()
    assert.are.equal("file", pk.mode)
    assert.is_nil(pk.text)
    assert.are.equal(S.ISSUE_URL, pk.url)
    -- recorded this session: not in the saved file until a logout or /reload, so nothing to mark yet
    assert.are.equal(0, #pk.sent)
    assert.are.equal(1, pk.later)
  end)

  it("file mode marks only the lines the saved file held when it loaded", function()
    local saved = { version = 1, builds = { "1.15.9.69722" }, entries = {
      ["quest:2:title"] = { t = "quest", i = 2, f = "title", h = "0123456789abcdef", e = "Old Title", b = 1 } } }
    C.load(saved, H.collectorDeps({ player = function() return PLAYER end }))
    C.record("quest", 7, "title", "A Title") -- after the load: only in memory
    out = S.PASTE_BUDGET + 1
    local pk = S.pack()
    assert.are.equal("file", pk.mode)
    assert.are.equal(2, pk.count)
    assert.are.equal(1, pk.later)
    assert.are.same({ { key = "quest:2:title", h = "0123456789abcdef" } }, pk.sent)
    S.markSent(pk)
    local left = C.pending()
    assert.are.equal(1, #left)
    assert.are.equal("quest:7:title", left[1].key)
    -- a line replaced since the load is not the one the file holds
    C.record("quest", 2, "title", "New Title")
    pk = S.pack(true)
    assert.are.equal(0, #pk.sent)
  end)

  it("a translated line is marked with the send, so the unsent count reaches zero", function()
    local shipped = {}
    C.load(nil, H.collectorDeps({ player = function() return PLAYER end,
      lookup = function(kind, id) return shipped[kind] and shipped[kind][id] end }))
    C.record("quest", 2, "title", "Sharptalon's Claw")
    C.record("quest", 3, "title", "Still English")
    shipped["quest.title"] = { [2] = { ja = "x", status = ".",
      h1 = (WFJ.Hash.h32x2(WFJ.Normalize.v1("Sharptalon's Claw"))) } }
    assert.are.equal(1, C.status().unsent)
    local pk = S.pack()
    assert.are.equal(1, pk.count)
    assert.are.equal(1, pk.shipped)
    S.markSent(pk)
    assert.are.equal(0, C.status().unsent)
    assert.is_truthy(C.describe():find("(0 unsent)", 1, true))
  end)

  it("a file from a newer version is readonly and marks nothing", function()
    C.load({ version = 2, entries = {}, builds = {} }, H.collectorDeps())
    local pk = S.pack(true)
    assert.are.equal("readonly", pk.mode)
    assert.are.equal(0, S.markSent(pk))
  end)

  it("nothing unsent is empty; send all packs every entry again", function()
    C.record("quest", 7, "title", "A Title")
    local pk = S.pack()
    assert.are.equal(1, S.markSent(pk))
    pk = S.pack()
    assert.are.equal("empty", pk.mode)
    assert.are.equal(0, S.markSent(pk))
    assert.are.equal("link", S.pack(true).mode)
  end)

  it("a client without the encoder, or one that fails, is unavailable: the file goes instead", function()
    C.record("quest", 7, "title", "A Title")
    S.init({})
    local pk = S.pack()
    assert.are.equal("unavailable", pk.mode)
    assert.are.equal(1, pk.later) -- recorded this session: not in the file yet
    assert.are.equal(0, S.markSent(pk))
    S.init({ encode = function() error("no zlib") end })
    assert.are.equal("unavailable", S.pack().mode)
    S.init({ encode = function() return nil end })
    assert.are.equal("unavailable", S.pack().mode)
    assert.are.equal(1, C.status().unsent)
  end)

  it("percentEncode leaves the URL-safe Base64 alphabet alone", function()
    assert.are.equal("Az09-_", S.percentEncode("Az09-_"))
    assert.are.equal("%3A%3D%2B%2F", S.percentEncode(":=+/"))
  end)
end)

-- the client's encoder as Main wires it, in a whole stub session: what it is handed holds nothing personal
describe("CollectorSend through the loaded addon", function()
  it("Main hands C_EncodingUtil the payload with Zlib and the URL-safe alphabet; nothing personal in it", function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI(); Stub.installGossipAPI()
    local calls = {}
    _G.Enum = _G.Enum or {}
    _G.Enum.CompressionMethod = { Deflate = 0, Zlib = 1, Gzip = 2 }
    _G.Enum.Base64Variant = { Standard = 0, StandardUrlSafe = 1 }
    local payload
    _G.C_EncodingUtil = {
      SerializeJSON = function(v) payload = v; calls[#calls + 1] = "json"; return "{json}" end,
      CompressString = function(s, method) calls[#calls + 1] = "zlib:" .. method; return "z" .. s end,
      EncodeBase64 = function(s, variant) calls[#calls + 1] = "b64:" .. variant; return "B" .. s end,
    }
    local WFJ = Loader.load("WoWForeverJapanese")
    Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese")
    Stub.fireAll("PLAYER_ENTERING_WORLD")
    require("tests.lua.spec.collector_session").run()
    local pk = WFJ.CollectorSend.pack(true)
    _G.C_EncodingUtil = nil
    assert.are.equal("link", pk.mode)
    assert.are.same({ "json", "zlib:1", "b64:1" }, calls)
    assert.are.equal("WFJC1:Bz{json}", pk.text)
    assert.is_true(#payload.e >= 8)
    local function scan(v)
      if type(v) == "string" then
        assert.is_nil(v:find("Reyn", 1, true), v)
        assert.is_nil(v:find("Creature-", 1, true), v)
        assert.is_nil(v:find("Player-", 1, true), v)
        assert.is_nil(v:find(GetRealmName(), 1, true), v)
      elseif type(v) == "table" then
        for k, x in pairs(v) do scan(k); scan(x) end
      end
    end
    scan(payload)
  end)
end)
