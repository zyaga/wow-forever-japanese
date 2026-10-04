-- UI/TextWatch: follows a FontString's text from the addon's own frame, never inside the code that writes it.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

describe("UI/TextWatch", function()
  local WFJ, TW

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    WFJ = H.loadChunks({ "Core/Const.lua", "Core/Compat.lua", "UI/TextWatch.lua" })
    WFJ.Compat.init(function(name) return _G[name] end)
    TW = WFJ.TextWatch
  end)

  it("runs the callback on the next tick after the text or the font changed, once per change", function()
    local fs = Stub.fontString("Say:")
    fs.shown = true
    local runs = 0
    assert.is_true(TW.add(fs, function() runs = runs + 1 end))
    assert.is_true(TW.watching(fs))
    TW.tick()
    assert.are.equal(1, runs) -- the first look counts as a change
    TW.tick()
    assert.are.equal(1, runs)
    fs:SetText("Yell:")
    TW.tick()
    assert.are.equal(2, runs)
    fs:SetFont("Fonts\\OTHER.TTF", 12, "")
    TW.tick()
    assert.are.equal(3, runs)
  end)

  it("what the callback itself writes is not seen as a change", function()
    local fs = Stub.fontString("Say:")
    fs.shown = true
    local runs = 0
    TW.add(fs, function() runs = runs + 1; fs:SetText("発言:") end)
    TW.tick()
    TW.tick()
    assert.are.equal(1, runs)
    assert.are.equal("発言:", fs:GetText())
  end)

  it("a hidden FontString is not read; a second add replaces the callback; bad input is refused", function()
    local fs = Stub.fontString("x")
    fs.shown = false
    local first, second = 0, 0
    TW.add(fs, function() first = first + 1 end)
    assert.is_false(TW.add(fs, function() second = second + 1 end))
    TW.tick()
    assert.are.same({ 0, 0 }, { first, second })
    fs.shown = true
    TW.tick()
    assert.are.same({ 0, 1 }, { first, second })
    assert.is_false(TW.add(nil, function() end))
    assert.is_false(TW.add(fs, "not a function"))
  end)

  it("a callback that errors does not stop the others", function()
    local a, b = Stub.fontString("a"), Stub.fontString("b")
    a.shown, b.shown = true, true
    local ran = false
    TW.add(a, function() error("boom") end)
    TW.add(b, function() ran = true end)
    assert.has_no.errors(function() TW.tick() end)
    assert.is_true(ran)
  end)
end)
