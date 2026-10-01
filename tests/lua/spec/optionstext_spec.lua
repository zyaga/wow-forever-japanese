local H = require("tests.lua.spec.helpers")

describe("UI/OptionsText: every page string in both languages", function()
  local Text
  setup(function() Text = H.loadChunks({ "UI/OptionsText.lua" }).OptionsText end)

  local function placeholders(s)
    local _, n = s:gsub("%%s", "")
    return n
  end

  it("has non-empty English and Japanese with the same number of %s for every key", function()
    local n = 0
    for key, t in pairs(Text.T) do
      n = n + 1
      assert.is_true(type(t.en) == "string" and #t.en > 0, key .. " en")
      assert.is_true(type(t.ja) == "string" and #t.ja > 0, key .. " ja")
      assert.are.equal(placeholders(t.en), placeholders(t.ja), key)
      assert.is_truthy(t.ja:find("[\128-\255]"), key .. ": the Japanese has no Japanese in it")
    end
    assert.is_true(n > 30)
  end)

  it("no English line carries Japanese (it would switch the English to the Japanese face and wrap)", function()
    -- the About page's marker line held "[要更新 …" in its English and ran into the next row
    -- page.main is the addon's name, written the same in both languages (and so in the same face) on a wide header
    for key, t in pairs(Text.T) do
      if key ~= "page.main" then assert.is_nil(t.en:find("[\227-\233\239]"), key) end
    end
  end)

  it("formats both languages and refuses a missing key", function()
    local en, ja = Text.get("warn.takeover", "Q", "Action Button 5", "Q")
    assert.are.equal('Q is used for "Action Button 5". While this addon is loaded, Q shows English instead.', en)
    assert.is_truthy(ja:find("「Action Button 5」", 1, true))
    assert.has_error(function() Text.get("no.such.key") end)
  end)
end)

describe("UI/OptionsText.SLASH names every command", function()
  it("lists every top-level verb and every debug sub-verb", function()
    local Text = H.loadChunks({ "UI/OptionsText.lua" }).OptionsText
    local all = table.concat(Text.SLASH, "\n")
    for _, verb in ipairs({ "on", "off", "toggle", "config", "debug", "glosses", "readings", "togglekey", "collector",
        "version", "modifier", "area", "marker", "fix" }) do
      assert.is_truthy(all:find("/wfj " .. verb, 1, true) or all:find("| " .. verb, 1, true), verb)
    end
    local debug = {}
    for list in all:gmatch("/wfj debug %[(.-)%]\n") do debug[#debug + 1] = list end
    for list in all:gmatch("/wfj debug %[(.-)%]$") do debug[#debug + 1] = list end
    local subs = table.concat(debug, " | ")
    for _, sub in ipairs({ "hash", "quest", "item", "spell", "gossip", "book", "objective", "fonts", "ui", "scan" }) do
      assert.is_truthy(subs:find(sub, 1, true), sub)
    end
  end)
end)
