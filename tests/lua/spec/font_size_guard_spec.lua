-- A font size the client reports that is not a number above 0 (seen as -1566.5 on a mail row's expiry text): the
-- client refuses SetFont with such a height by raising, so the addon never passes one on. The Japanese goes out at
-- the bundled default size, and putting the client's face back uses the size that was applied.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local BAD = { -1566.511841, 0, 0 / 0 }
local CLIENT = "Fonts\\FRIZQT__.TTF"

describe("the stub's SetFont refuses a height that is not above 0, as the client does", function()
  it("raises for every bad size; accepts a positive size", function()
    local fs = Stub.fontString("x", CLIENT, 12, "")
    for _, s in ipairs(BAD) do
      assert.has_error(function() fs:SetFont(CLIENT, s, "") end)
    end
    assert.is_true(fs:SetFont(CLIENT, 9.5, ""))
    assert.are.same({ CLIENT, 9.5, "" }, { fs:GetFont() })
  end)
end)

describe("SurfaceState with a widget whose reported size is not above 0", function()
  local WFJ, SS
  local JA = { path = "Interface\\AddOns\\WoWForeverJapanese\\Fonts\\ipagui.ttf", size = 12, flags = "OUTLINE" }
  local PUT_BACK = { CLIENT, JA.size, "OUTLINE" } -- the client's face and flags at the applied size

  before_each(function()
    WFJ = {}
    H.loadPure("Core/SurfaceState.lua", "WoWForeverJapanese", WFJ)
    SS = WFJ.SurfaceState
    Stub.fontSetFails = false
  end)

  local function applied(size)
    local fs = Stub.fontString("29 Days", CLIENT, size, "OUTLINE")
    assert.is_truthy(SS.capture("mail", "expire", fs, "29 Days"))
    assert.is_nil(SS.get("mail", "expire").font.size) -- no size on record, the face and flags are kept
    assert.are.equal(CLIENT, SS.get("mail", "expire").font.path)
    assert.is_true((SS.apply("mail", "expire", "29日", JA)))
    assert.are.equal("29日", fs:GetText())
    assert.are.same({ JA.path, JA.size, "OUTLINE" }, { fs:GetFont() })
    return fs
  end

  local PUT_BACKS = {
    { "restore", function() SS.restore("mail", "expire") end },
    { "apply without a font", function() SS.apply("mail", "expire", "29 Days") end },
    { "drop", function() SS.drop("mail", "expire") end },
    { "discard", function() SS.discard("mail") end },
    { "release", function() SS.release("mail") end },
    { "the key seated on another widget", function()
      SS.capture("mail", "expire", Stub.fontString("29 Days", CLIENT, 14, ""), "29 Days")
    end },
  }

  for _, size in ipairs(BAD) do
    for _, case in ipairs(PUT_BACKS) do
      it("size " .. tostring(size) .. ": " .. case[1] .. " puts the client's face back at the applied size", function()
        local fs = applied(size)
        case[2]()
        assert.are.same(PUT_BACK, { fs:GetFont() })
      end)
    end
  end

  it("a positive size is kept as reported", function()
    local fs = Stub.fontString("29 Days", CLIENT, 10, "")
    SS.capture("mail", "expire", fs, "29 Days")
    assert.are.equal(10, SS.get("mail", "expire").font.size)
  end)
end)

describe("UI/Font and the label path with a reported size that is not above 0", function()
  local WFJ, Font

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    WFJ = H.loadChunks(H.UI_FILES)
    H.uiSetup(WFJ, { TEST_DAYS_LEFT = { "Days Left", "残り日数" } })
    Font = WFJ.Font
  end)

  after_each(function() H.uiTeardown() end)

  -- a font object whose GetFont reports `size`
  local function fontObject(path, size)
    return { GetFont = function() return path, size, "" end }
  end

  it("Font.size keeps a number above 0 and gives nil for anything else", function()
    for _, s in ipairs(BAD) do assert.is_nil(Font.size(s)) end
    assert.is_nil(Font.size(nil))
    assert.is_nil(Font.size("12"))
    assert.are.equal(9.5, Font.size(9.5))
  end)

  it("Font.bundled: the default size for a bad or missing size, a positive size unchanged", function()
    for _, s in ipairs(BAD) do
      assert.are.same({ path = Font.PATH, size = Font.DEFAULT_SIZE, flags = "OUTLINE" },
        Font.bundled({ path = CLIENT, size = s, flags = "OUTLINE" }))
    end
    assert.are.same({ path = Font.PATH, size = Font.DEFAULT_SIZE, flags = "" }, Font.bundled({ path = CLIENT }))
    assert.are.same({ path = Font.PATH, size = Font.DEFAULT_SIZE, flags = "" }, Font.bundled(nil))
    assert.are.same({ path = Font.PATH, size = 13, flags = "" }, Font.bundled({ path = CLIENT, size = 13, flags = "" }))
  end)

  for _, size in ipairs(BAD) do
    it("Font.bundle / restore / follow with size " .. tostring(size) .. " never pass it on", function()
      -- the row's own size is bad: the default; the owner's size is bad: the row's own
      local row = Stub.fontString("x", CLIENT, size, "")
      assert.are.equal(Font.DEFAULT_SIZE, Font.bundle(row))
      local other = Stub.fontString("x", CLIENT, 14, "")
      assert.are.equal(14, Font.bundle(other, fontObject(CLIENT, size)))
      -- the owner's font back, at the size the bundled face was set at
      assert.is_true(Font.restore(other, fontObject("Fonts\\ARIALN.TTF", size)))
      assert.are.same({ "Fonts\\ARIALN.TTF", 14, "" }, { other:GetFont() })
      -- following a font object whose size is bad sets nothing
      assert.is_false(Font.follow(other, fontObject("Fonts\\MORPHEUS.TTF", size)))
      assert.are.same({ "Fonts\\ARIALN.TTF", 14, "" }, { other:GetFont() })
    end)

    it("a button reporting size " .. tostring(size) .. " shows its Japanese at the default size, then its English",
      function()
        local button = Stub.button("MailItem6ExpireTime", "Days Left")
        button.fontString.font.size = size
        assert.are.equal(1, WFJ.Labels.show("mail", "expire6", button))
        assert.are.equal("残り日数", button:GetText())
        assert.are.same({ Font.PATH, Font.DEFAULT_SIZE, "" }, { button.fontString:GetFont() })
        WFJ.Render.release("mail")
        assert.are.equal("Days Left", button:GetText())
        assert.are.same({ CLIENT, Font.DEFAULT_SIZE, "" }, { button.fontString:GetFont() })
      end)
  end
end)

describe("OptionsWidgets.setText with a FontString reporting a size not above 0", function()
  it("shows Japanese in the bundled face at the default size and puts the own face back at it", function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    local WFJ = H.loadChunks({ "Core/Const.lua", "Core/Compat.lua", "Core/State.lua", "Core/Settings.lua",
      "Core/Modifier.lua", "UI/Font.lua", "UI/OptionsText.lua", "UI/OptionsWidgets.lua" })
    for _, size in ipairs(BAD) do
      local fs = Stub.fontString("", CLIENT, size, "")
      WFJ.OptionsWidgets.setText(fs, "未設定")
      assert.are.same({ WFJ.Font.PATH, WFJ.Font.DEFAULT_SIZE, "" }, { fs:GetFont() })
      WFJ.OptionsWidgets.setText(fs, "CTRL-J")
      assert.are.same({ CLIENT, WFJ.Font.DEFAULT_SIZE, "" }, { fs:GetFont() })
    end
  end)
end)
