-- The tooltip trace cuts a long value on a character boundary: text cut inside a Japanese character is not UTF-8, and
-- the trace window's edit box shows nothing at all for it.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

-- whether `s` is well-formed UTF-8 (Lua 5.1 has no utf8 library)
local function isUtf8(s)
  local i, n = 1, #s
  while i <= n do
    local c = s:byte(i)
    local len = c < 0x80 and 1 or (c >= 0xC2 and c < 0xE0) and 2 or (c >= 0xE0 and c < 0xF0) and 3
      or (c >= 0xF0 and c < 0xF5) and 4 or nil
    if not len or i + len - 1 > n then return false end
    for k = i + 1, i + len - 1 do
      local b = s:byte(k)
      if b < 0x80 or b >= 0xC0 then return false end
    end
    i = i + len
  end
  return true
end

describe("UI/Tooltip trace text", function()
  local WFJ
  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    local files = {}
    for i, f in ipairs(H.UI_FILES) do files[i] = f end
    files[#files + 1] = "UI/TimeLine.lua"
    files[#files + 1] = "UI/Tooltip.lua"
    WFJ = H.loadChunks(files)
    H.uiSetup(WFJ, {})
  end)
  after_each(function() H.uiTeardown() end)

  it("a long Japanese value is cut before a character, never inside one", function()
    local ja = string.rep("回復", 30) -- 60 characters, 180 bytes
    for shift = 0, 3 do
      local cut = WFJ.Tooltip.plain(string.rep("a", shift) .. ja)
      assert.is_true(isUtf8(cut), "shift " .. shift)
      assert.is_truthy(cut:find("%.%.%.$"))
      assert.is_true(#cut <= 73)
    end
    assert.are.equal("short", WFJ.Tooltip.plain("short"))
  end)
end)
