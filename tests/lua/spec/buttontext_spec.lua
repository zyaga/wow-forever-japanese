-- UI/ButtonText.lua: only an object with a text region and its own GetText / SetText is a button. A
-- ScrollingFontTemplate frame has GetFontString and neither (scrolltemplates.lua:337–340).
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

describe("ButtonText: what counts as a button", function()
  local WFJ

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    WFJ = H.loadChunks(H.UI_FILES)
    H.uiSetup(WFJ, {})
  end)

  after_each(function() H.uiTeardown() end)

  it("a scrolling text frame is not one", function()
    local scrolling = CreateFrame("Frame")
    scrolling.GetText, scrolling.SetText = nil, nil
    local inner = Stub.fontString("Some text")
    function scrolling.GetFontString() return inner end
    assert.is_false(WFJ.ButtonText.is(scrolling))
    assert.is_nil(WFJ.ButtonText.of(scrolling))
    assert.is_false(WFJ.ButtonText.known(scrolling))
    assert.is_nil(WFJ.Labels.widget(scrolling))
  end)

  it("a button is one, with the same adapter on every call", function()
    local button = Stub.button(nil, "Okay")
    assert.is_true(WFJ.ButtonText.is(button))
    assert.is_false(WFJ.ButtonText.known(button)) -- asking the shape builds no adapter and installs no hook
    local a = WFJ.ButtonText.of(button)
    assert.is_table(a)
    assert.are.equal("Okay", a.GetText())
    assert.are.equal(a, WFJ.ButtonText.of(button))
    assert.is_true(WFJ.ButtonText.known(button))
  end)
end)
