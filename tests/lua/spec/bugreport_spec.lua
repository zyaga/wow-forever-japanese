-- Core/BugReport: the bug link fills the form's fields through the URL; too long, it falls back to a paste.
local H = require("tests.lua.spec.helpers")

local function load()
  local ns = {}
  H.loadPure("Core/BugReport.lua", "WoWForeverJapanese", ns)
  -- the two things it borrows from the collector send: the encoder and the link limit
  ns.CollectorSend = { URL_BUDGET = 6000, percentEncode = function(s)
    return (s:gsub("[^%w%-_]", function(c) return ("%%%02X"):format(c:byte()) end))
  end }
  return ns.BugReport
end

-- The query parameters of a link, decoded.
local function params(url)
  local out = {}
  for k, v in url:gmatch("[?&]([^=&]+)=([^&]*)") do
    out[k] = v:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
  end
  return out
end

local ERR = { msg = "Interface/AddOns/WoWForeverJapanese/UI/A.lua:1: x", stack = "line 1\nline 2", n = 3,
  first = "2026-10-03 14:40:00", last = "2026-10-03 14:45:00" }

describe("Core/BugReport", function()
  it("opens the bug form with build, version and the errors as readable text", function()
    local B = load()
    local pk = B.pack({ build = "1.60.1.70170", version = "0.1.0-alpha.6", errors = { ERR }, ours = true })
    assert.are.equal("link", pk.mode)
    assert.are.equal(1, pk.count)
    assert.is_true(pk.ours)
    assert.are.equal(1, pk.url:find(B.URL, 1, true))
    local p = params(pk.url)
    assert.are.equal("bug-report.yml", p.template)
    assert.are.equal("1.60.1.70170", p["client-build"])
    assert.are.equal("0.1.0-alpha.6", p["addon-version"])
    assert.are.equal("1) 3 times, first 2026-10-03 14:40:00, last 2026-10-03 14:45:00\n" .. ERR.msg
      .. "\nline 1\nline 2", p.errors)
    assert.are.equal(p.errors, pk.text)
    assert.are.same({ { msg = ERR.msg, last = ERR.last, n = 3 } }, pk.sent)
  end)

  it("leaves the errors field out when there is nothing new", function()
    local B = load()
    local pk = B.pack({ build = "1.60.1.70170", version = "1", errors = {} })
    assert.are.equal("link", pk.mode)
    assert.are.equal(0, pk.count)
    assert.is_nil(params(pk.url).errors)
    assert.are.same({}, pk.sent)
  end)

  it("over 6,000 characters the link fills build and version and the text is pasted", function()
    local B = load()
    local errors = {}
    for i = 1, 8 do
      errors[i] = { msg = ERR.msg .. i, stack = string.rep("x", 900), n = 1, first = "a", last = "b" }
    end
    local pk = B.pack({ build = "1.60.1.70170", version = "1", errors = errors, ours = true })
    assert.are.equal("paste", pk.mode)
    assert.is_nil(params(pk.url).errors)
    assert.are.equal("1.60.1.70170", params(pk.url)["client-build"])
    assert.is_truthy(pk.text:find("8) 1 time", 1, true))
    assert.are.equal(8, #pk.sent)
    assert.is_true(#pk.url <= 6000)
  end)

  it("writes ? for a time the clock could not read", function()
    local B = load()
    local text = B.text({ { msg = "m", stack = "s", n = 1, first = "", last = "" } })
    assert.are.equal("1) 1 time, first ?, last ?\nm\ns", text)
  end)

  it("reports whether the errors reached the log, and links the idea form", function()
    local B = load()
    assert.is_false(B.pack({ errors = {}, ours = false }).ours)
    assert.are.equal("https://github.com/zyaga/wow-forever-japanese/issues/new?template=idea.yml", B.IDEA_URL)
  end)
end)
