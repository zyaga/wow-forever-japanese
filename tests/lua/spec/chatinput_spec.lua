-- UI/ChatInput.lua: the chat input box wears the bundled face only while it holds Japanese.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local function editBox()
  local box = { text = "", font = { "Fonts\\FRIZQT__.TTF", 14, "" }, scripts = {} }
  function box:GetText() return self.text end
  function box:GetFont() return self.font[1], self.font[2], self.font[3] end
  function box:SetFont(p, s, f) self.font = { p, s, f }; return true end
  function box.GetFontObject() return { GetFont = function() return "Fonts\\FRIZQT__.TTF", 14, "" end } end
  function box:HookScript(name, fn) self.scripts[name] = fn end
  function box:type(t) self.text = t; self.scripts.OnTextChanged(self) end
  return box
end

describe("UI/ChatInput", function()
  local WFJ, box
  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    box = editBox()
    _G.CHAT_FRAMES = { "ChatFrame1" }
    _G.ChatFrame1 = { editBox = box }
    WFJ = H.loadChunks({ "Core/Const.lua", "Core/Compat.lua", "UI/Font.lua", "UI/ChatInput.lua" })
    WFJ.Compat.init(function(name) return _G[name] end)
  end)
  after_each(function() _G.CHAT_FRAMES, _G.ChatFrame1 = nil, nil end)

  it("switches to the bundled face for Japanese and back for English, at the box's size", function()
    assert.is_true(WFJ.ChatInput.init())
    box:type("hello")
    assert.are.equal("Fonts\\FRIZQT__.TTF", box.font[1])
    box:type("こんにちは")
    assert.are.equal(WFJ.Font.PATH, box.font[1])
    assert.are.equal(14, box.font[2])
    box:type("ｗ") -- a full-width letter
    assert.are.equal(WFJ.Font.PATH, box.font[1])
    box:type("")
    assert.are.equal("Fonts\\FRIZQT__.TTF", box.font[1])
  end)

  it("hooks each box once", function()
    WFJ.ChatInput.init()
    assert.are.equal(0, WFJ.ChatInput.hookAll())
  end)
end)
