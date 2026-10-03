-- UI/ChatInput.lua: the chat input box, its header and suffix always wear the bundled face.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local function widget(name)
  local w = { font = { "Fonts\\ARIALN.TTF", 14, "" }, scripts = {} }
  function w:GetFont() return self.font[1], self.font[2], self.font[3] end
  function w:SetFont(p, s, f) self.font = { p, s, f }; return true end
  function w.GetName() return name end
  function w:HookScript(n, fn) self.scripts[n] = fn end
  return w
end

describe("UI/ChatInput", function()
  local WFJ, box
  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    box = widget("ChatFrame1EditBox")
    _G.CHAT_FRAMES = { "ChatFrame1" }
    _G.ChatFrame1 = { editBox = box }
    _G.ChatFrame1EditBoxHeader, _G.ChatFrame1EditBoxHeaderSuffix = widget(), widget()
    WFJ = H.loadChunks({ "Core/Const.lua", "Core/Compat.lua", "UI/Font.lua", "UI/ChatInput.lua" })
    WFJ.Compat.init(function(name) return _G[name] end)
  end)
  after_each(function()
    _G.CHAT_FRAMES, _G.ChatFrame1, _G.ChatFrame1EditBoxHeader, _G.ChatFrame1EditBoxHeaderSuffix = nil, nil, nil, nil
  end)

  it("dresses the box, its header and suffix at their own size, and again when the box shows", function()
    assert.is_true(WFJ.ChatInput.init())
    for _, w in ipairs({ box, _G.ChatFrame1EditBoxHeader, _G.ChatFrame1EditBoxHeaderSuffix }) do
      assert.are.same({ WFJ.Font.PATH, 14, "" }, w.font)
    end
    box.font = { "Fonts\\ARIALN.TTF", 12, "" } -- the client set its font object again
    box.scripts.OnShow(box)
    assert.are.same({ WFJ.Font.PATH, 12, "" }, box.font)
    assert.are.equal(0, WFJ.ChatInput.hookAll()) -- hooked once
  end)
end)
