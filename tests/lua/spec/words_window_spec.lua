-- UI/WordsWindow: the word list as copyable text, the Copy button, the images box, Remove last and Clear all.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local F = require("tests.lua.spec.stub_fixwindow")

local FILES = { "Core/Const.lua", "Core/Compat.lua", "Core/State.lua", "Core/Settings.lua", "Core/Modifier.lua",
  "Core/Words.lua", "UI/Font.lua", "UI/OptionsText.lua", "UI/OptionsWidgets.lua", "UI/WordsWindow.lua" }

local function add(W, word, shot)
  local text = word .. "がある。"
  local _, e = W.add({ kind = "quest.description", id = 456, surface = "questframe.detail", text = text, first = 1,
    last = #word, word = word, reading = "よみ", lemma = word, lemmaReading = "よみ", meaning = "a meaning",
    questTitle = "題" }, 1790000000)
  if shot then W.setShot(e, shot) end
  return e
end

describe("the word list window", function()
  local WFJ, WW, copied

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    F.install()
    copied = {}
    _G.CopyToClipboard = function(text, removeMarkup)
      copied[#copied + 1] = { text = text, removeMarkup = removeMarkup }
      return #text
    end
    _G.date = function(p, t) return os.date("!" .. p, t) end
    WFJ = H.loadChunks(FILES)
    WFJ.Compat.init(function(name) return _G[name] end)
    WFJ.Settings.load(nil, 1, {})
    WFJ.Words.load(nil)
    WW = WFJ.WordsWindow
  end)
  after_each(function()
    F.clear()
    _G.CopyToClipboard, _G.date = nil, nil
  end)

  local function ja(key, ...) return select(2, WFJ.OptionsText.get(key, ...)) end
  local function jaClick(key) return select(2, WFJ.OptionsText.withSaveClick(key)) end
  local function shown(w) return (w.frame or w):IsShown() end

  it("opens with the whole list as the export text, selected, and the copy instructions", function()
    add(WFJ.Words, "生き物")
    add(WFJ.Words, "数")
    local f = WW.open()
    assert.is_true(f:IsShown())
    assert.are.equal(ja("words.title"), f.title:GetText())
    assert.are.equal(ja("words.summary", 2), f.summary.en:GetText())
    assert.is_truthy(jaClick("words.empty"):find("Ctrl+click", 1, true))
    assert.are.equal(WFJ.Words.export({}, _G.date), f.text.value)
    assert.is_true(f.text.box.focused)
    assert.are.equal(ja("words.copyHint"), f.copyHint.en:GetText())
    for _, name in ipairs(_G.UISpecialFrames) do if name == "WFJWordsWindow" then return end end
    error("the window does not close on Esc")
  end)

  it("Copy copies the text and says so only when the client reports text copied", function()
    add(WFJ.Words, "生き物")
    local f = WW.open()
    assert.is_true(shown(f.copy))
    f.copy.scripts.OnClick(f.copy, "LeftButton")
    assert.are.equal(f.text.value, copied[1].text)
    assert.is_false(copied[1].removeMarkup)
    assert.are.equal(ja("words.copied"), f.message.en:GetText())
    _G.CopyToClipboard = function() return nil end
    f.copy.scripts.OnClick(f.copy, "LeftButton")
    assert.are.equal("", f.message.en:GetText())
  end)

  it("hides Copy on a client without the call", function()
    _G.CopyToClipboard = nil
    WFJ.Compat.init(function(name) return _G[name] end)
    add(WFJ.Words, "生き物")
    local f = WW.open()
    assert.is_false(shown(f.copy))
  end)

  it("Include images adds the image column and shows where the screenshots are and where Anki wants them", function()
    add(WFJ.Words, "生き物", "WoWScrnShot_092126_165320.jpg")
    local f = WW.open()
    assert.is_false(shown(f.shotsPath))
    assert.is_false(shown(f.ankiMac))
    f.images:SetChecked(true)
    f.images.scripts.OnClick(f.images)
    assert.are.equal(WFJ.Words.export({ images = true }, _G.date), f.text.value)
    assert.is_truthy(f.text.value:find('<img src="WoWScrnShot_092126_165320.jpg">', 1, true))
    assert.is_true(shown(f.shotsPath))
    assert.is_truthy(f.shotsPath:GetText():find("Screenshots", 1, true))
    assert.is_truthy(f.ankiMac:GetText():find("collection.media", 1, true))
    assert.is_truthy(f.ankiWin:GetText():find("collection.media", 1, true))
  end)

  it("Remove last removes the newest word; Clear all needs a second click", function()
    add(WFJ.Words, "生き物")
    add(WFJ.Words, "数")
    local f = WW.open()
    f.removeLast.scripts.OnClick(f.removeLast, "LeftButton")
    assert.are.equal(1, WFJ.Words.count())
    assert.are.equal(ja("words.removed", "数"), f.message.en:GetText())
    assert.are.equal(ja("words.summary", 1), f.summary.en:GetText())
    f.clear.scripts.OnClick(f.clear, "LeftButton")
    assert.are.equal(1, WFJ.Words.count())
    assert.are.equal(ja("words.clearArm"), f.clear.caption:GetText())
    f.clear.scripts.OnClick(f.clear, "LeftButton")
    assert.are.equal(0, WFJ.Words.count())
    assert.are.equal(ja("words.cleared", 1), f.message.en:GetText())
    assert.are.equal(jaClick("words.empty"), f.summary.en:GetText())
  end)

  it("Clear all disarms after 5 seconds", function()
    add(WFJ.Words, "生き物")
    local f = WW.open()
    local now = 0
    _G.GetTime = function() return now end
    f.clear.scripts.OnClick(f.clear, "LeftButton")
    now = 6
    f.clear.scripts.OnClick(f.clear, "LeftButton")
    assert.are.equal(1, WFJ.Words.count())
  end)

  it("with no words it says how to save one", function()
    local f = WW.open()
    assert.are.equal(jaClick("words.empty"), f.summary.en:GetText())
  end)

  it("a list from a newer version can be copied but not changed", function()
    WFJ.Words.load({ schema = 99, entries = { { key = "k", word = "w" } } })
    local f = WW.open()
    f.removeLast.scripts.OnClick(f.removeLast, "LeftButton")
    assert.are.equal(ja("words.refused"), f.message.en:GetText())
    f.clear.scripts.OnClick(f.clear, "LeftButton")
    f.clear.scripts.OnClick(f.clear, "LeftButton")
    assert.are.equal(1, #WFJ.Words.entries())
  end)
end)
