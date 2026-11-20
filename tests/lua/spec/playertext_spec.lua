-- UI/PlayerText.lua: a typing box always wears the bundled face; shown text wears it only while it holds Japanese.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local CLIENT = "Fonts\\FRIZQT__.TTF"

local function box(size)
  local b = Stub.fontString("", CLIENT, size or 12, "OUTLINE")
  b.scripts, b.hooks = {}, 0
  function b:HookScript(name, fn)
    self.hooks = self.hooks + 1
    self.scripts[name] = fn
  end
  return b
end

-- A SimpleHTML: no GetText, fonts per text type, its paragraphs from GetTextData.
local function html(text)
  local h = { fonts = { P = { CLIENT, 11, "" } }, text = text }
  function h:SetText(t) self.text = t end
  function h:GetFont(textType) local f = self.fonts[textType]; return f[1], f[2], f[3] end
  function h:SetFont(textType, path, size, flags) self.fonts[textType] = { path, size, flags } end
  function h:GetTextData() return self.text and { { text = self.text, type = "P" } } or {} end
  return h
end

describe("UI/PlayerText", function()
  local WFJ, P
  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    WFJ = H.loadChunks({ "Core/Const.lua", "Core/Compat.lua", "UI/Font.lua", "UI/HtmlText.lua", "UI/PlayerText.lua" })
    WFJ.Compat.init(function(name) return _G[name] end)
    P = WFJ.PlayerText
  end)
  after_each(function() _G.issecretvalue, _G.WfjTestDialog = nil, nil end)

  it("a typing box wears the bundled face at its own size and flags, again when it shows, hooked once", function()
    local b = box(14)
    assert.is_true(P.box(b))
    assert.are.same({ path = WFJ.Font.PATH, size = 14, flags = "OUTLINE" }, b.font)
    b.font = { path = CLIENT, size = 16, flags = "" } -- the client put its font object back
    b.scripts.OnShow(b)
    assert.are.same({ path = WFJ.Font.PATH, size = 16, flags = "" }, b.font)
    assert.is_true(P.box(b))
    assert.are.equal(1, b.hooks)
    assert.are.equal("", b:GetText()) -- nothing is written into it
  end)

  it("a box whose reported size is not above 0 gets the default size; a non-widget is refused", function()
    for _, size in ipairs({ -1566.5, 0, 0 / 0 }) do
      local b = box()
      b.font.size = size
      assert.is_true(P.box(b))
      assert.are.equal(WFJ.Font.DEFAULT_SIZE, b.font.size)
    end
    assert.is_false(P.box(nil))
    assert.is_false(P.box({}))
  end)

  it("shown text wears the bundled face while it holds Japanese and its own font otherwise", function()
    local fs = Stub.fontString("今夜はレイドです", CLIENT, 10, "THICK")
    assert.is_true(P.shown(fs))
    assert.are.same({ path = WFJ.Font.PATH, size = 10, flags = "THICK" }, fs.font)
    assert.are.equal("今夜はレイドです", fs:GetText())
    for _, text in ipairs({ "Raid tonight", "" }) do
      fs.text = text
      assert.is_false(P.shown(fs))
      assert.are.same({ path = CLIENT, size = 10, flags = "THICK" }, fs.font)
      fs.text = "カタカナ"
      P.shown(fs)
    end
    assert.is_false(P.shown(fs, "given text wins over the widget's"))
    assert.are.equal(CLIENT, fs.font.path)
  end)

  it("a widget that was never dressed is not touched by text without Japanese", function()
    local fs = Stub.fontString("Hello", CLIENT, 10, "")
    P.shown(fs)
    assert.are.equal(0, fs.calls.SetFont)
    assert.is_false(P.shown({}, "日本語")) -- no SetFont: not a text widget
  end)

  it("a secret value changes nothing either way", function()
    local hidden = {}
    _G.issecretvalue = function(v) return v == hidden end
    local fs = Stub.fontString("メモ", CLIENT, 10, "")
    P.shown(fs)
    local calls = fs.calls.SetFont
    assert.is_false(P.shown(fs, hidden))
    assert.are.equal(calls, fs.calls.SetFont)
    assert.are.equal(WFJ.Font.PATH, fs.font.path)
    assert.is_false(P.hasJapanese(hidden))
  end)

  it("a refused font leaves the widget as it was and is tried again on the next write", function()
    local fs = Stub.fontString("メモ", CLIENT, 10, "")
    Stub.fontSetFails = true
    assert.is_false(P.shown(fs))
    assert.are.equal(CLIENT, fs.font.path)
    Stub.fontSetFails = nil
    assert.is_true(P.shown(fs))
  end)

  it("a followed FontString is looked at now and on every SetText, and hooked once", function()
    local fs = Stub.fontString("ようこそ", CLIENT, 12, "")
    assert.is_true(P.follow(fs))
    assert.are.equal(WFJ.Font.PATH, fs.font.path)
    fs:SetText("Welcome")
    assert.are.equal(CLIENT, fs.font.path)
    fs:SetText("ギルド")
    assert.are.equal(WFJ.Font.PATH, fs.font.path)
    assert.are.equal("ギルド", fs:GetText())
    assert.is_false(P.follow(fs))
    assert.is_false(P.follow({}))
  end)

  it("a followed SimpleHTML has its paragraph font set and given back", function()
    local h = html("今日のメッセージ")
    assert.is_true(P.follow(h))
    assert.are.same({ WFJ.Font.PATH, 11, "" }, h.fonts.P)
    h:SetText("Message of the day", true)
    assert.are.same({ CLIENT, 11, "" }, h.fonts.P)
    h:SetText("日本語のメッセージ", true)
    assert.are.same({ WFJ.Font.PATH, 11, "" }, h.fonts.P)
    assert.are.equal("日本語のメッセージ", h.text)
    local empty = html(nil)
    assert.is_true(P.follow(empty))
    assert.are.equal(CLIENT, empty.fonts.P[1])
  end)

  it("each() finds widgets by path and passes over the ones this client lacks", function()
    local name = box()
    _G.WfjTestDialog = { NameEdit = name, Description = {} }
    local n = P.each(P.box, { "WfjTestDialog.NameEdit", "WfjTestDialog.Description.EditBox", "NoSuchDialog.NameEdit" })
    assert.are.equal(1, n)
    assert.are.equal(WFJ.Font.PATH, name.font.path)
  end)
end)
