-- A font size the client reports that is not a number above 0 (seen as -1566.5 on a mail row's expiry text): the
-- client refuses SetFont with such a height by raising, so the addon never passes one on. The Japanese goes out at
-- the bundled default size, and putting the client's face back uses the size that was applied.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local BAD = { -1566.511841, 0 }
local CLIENT = "Fonts\\FRIZQT__.TTF"

describe("the stub's SetFont refuses a height that is not above 0, as the client does", function()
  it("raises for 0, a negative size and NaN; accepts a positive size", function()
    local fs = Stub.fontString("x", CLIENT, 12, "")
    for _, s in ipairs({ 0, -1, 0 / 0 }) do
      assert.has_error(function() fs:SetFont(CLIENT, s, "") end)
    end
    assert.is_true(fs:SetFont(CLIENT, 9.5, ""))
    assert.are.same({ CLIENT, 9.5, "" }, { fs:GetFont() })
  end)
end)

describe("SurfaceState with a widget whose reported size is not above 0", function()
  local WFJ, SS
  local JA = { path = "Interface\\AddOns\\WoWForeverJapanese\\Fonts\\ipagui.ttf", size = 12, flags = "OUTLINE" }

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
    assert.are.same({ JA.path, 12, "OUTLINE" }, { fs:GetFont() })
    return fs
  end

  for _, size in ipairs(BAD) do
    it("size " .. size .. ": restore puts the client's face back at the applied size", function()
      local fs = applied(size)
      assert.is_true(SS.restore("mail", "expire"))
      assert.are.equal("29 Days", fs:GetText())
      assert.are.same({ CLIENT, 12, "OUTLINE" }, { fs:GetFont() })
    end)

    it("size " .. size .. ": apply without a font, drop, discard and release put the face back", function()
      local fs = applied(size)
      assert.is_true((SS.apply("mail", "expire", "29 Days")))
      assert.are.same({ CLIENT, 12, "OUTLINE" }, { fs:GetFont() })

      fs = applied(size)
      assert.is_true(SS.drop("mail", "expire"))
      assert.are.same({ CLIENT, 12, "OUTLINE" }, { fs:GetFont() })

      fs = applied(size)
      assert.are.equal(1, SS.discard("mail"))
      assert.are.same({ CLIENT, 12, "OUTLINE" }, { fs:GetFont() })

      fs = applied(size)
      assert.are.equal(1, SS.release("mail"))
      assert.are.same({ CLIENT, 12, "OUTLINE" }, { fs:GetFont() })
    end)

    it("size " .. size .. ": the key seated on another widget puts the old widget's face back", function()
      local fs = applied(size)
      local other = Stub.fontString("29 Days", CLIENT, 14, "")
      assert.is_truthy(SS.capture("mail", "expire", other, "29 Days"))
      assert.are.same({ CLIENT, 12, "OUTLINE" }, { fs:GetFont() })
    end)
  end

  it("a positive size is kept as reported", function()
    local fs = Stub.fontString("29 Days", CLIENT, 10, "")
    SS.capture("mail", "expire", fs, "29 Days")
    assert.are.equal(10, SS.get("mail", "expire").font.size)
  end)
end)

describe("Font.bundled and the label path with a reported size that is not above 0", function()
  local WFJ

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    WFJ = H.loadChunks(H.UI_FILES)
    H.uiSetup(WFJ, { TEST_DAYS_LEFT = { "Days Left", "残り日数" } })
  end)

  after_each(function() H.uiTeardown() end)

  it("the default size for nil, 0, a negative size and NaN; a positive size unchanged", function()
    local Font = WFJ.Font
    for _, s in ipairs({ 0, -1566.511841, 0 / 0 }) do
      assert.are.same({ path = Font.PATH, size = Font.DEFAULT_SIZE, flags = "OUTLINE" },
        Font.bundled({ path = CLIENT, size = s, flags = "OUTLINE" }))
    end
    assert.are.same({ path = Font.PATH, size = Font.DEFAULT_SIZE, flags = "" }, Font.bundled({ path = CLIENT }))
    assert.are.same({ path = Font.PATH, size = Font.DEFAULT_SIZE, flags = "" }, Font.bundled(nil))
    for _, s in ipairs({ 13, 9.5 }) do
      assert.are.same({ path = Font.PATH, size = s, flags = "" }, Font.bundled({ path = CLIENT, size = s, flags = "" }))
    end
  end)

  for _, size in ipairs(BAD) do
    it("a button reporting size " .. size .. " shows its Japanese at the default size, then its English", function()
      local button = Stub.button("MailItem6ExpireTime", "Days Left")
      button.fontString.font.size = size
      assert.are.equal(1, WFJ.Labels.show("mail", "expire6", button))
      assert.are.equal("残り日数", button:GetText())
      assert.are.same({ WFJ.Font.PATH, WFJ.Font.DEFAULT_SIZE, "" }, { button.fontString:GetFont() })
      WFJ.Render.release("mail")
      assert.are.equal("Days Left", button:GetText())
      assert.are.same({ CLIENT, WFJ.Font.DEFAULT_SIZE, "" }, { button.fontString:GetFont() })
    end)
  end
end)
