-- UI/DialogueUIBook: the Dialogue UI addon's book window, when the player has that addon. The window is
-- tests/lua/spec/stub_dialogueui.lua, a stand-in written from that addon's behaviour.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local DUI = require("tests.lua.spec.stub_dialogueui")

local FILES = {}
for _, f in ipairs(H.UI_FILES) do FILES[#FILES + 1] = f end
for _, f in ipairs({ "Core/Voice.lua", "Core/VoiceQueue.lua", "UI/VoicePlayer.lua", "UI/QuestFrame.lua",
  "UI/QuestMap.lua", "UI/ItemText.lua", "UI/DialogueUI.lua", "UI/DialogueUIFrames.lua", "UI/DialogueUIBook.lua" }) do
  FILES[#FILES + 1] = f
end

local PLAYER = { name = "Reyn", class = "Hunter", race = "Night Elf" }

local PLAIN = "The first age was long.\n\nThe second age was short."
local PLAIN_JA = "最初の時代は長かった。\n\n二番目の時代は短かった。"
local HTML = "<HTML><BODY><H1>Of Kings</H1><P>The king slept.</P><P>The queen ruled.</P></BODY></HTML>"
local HTML_JA = "<HTML><BODY><H1>王について</H1><P>王は眠った。</P><P>女王が治めた。</P></BODY></HTML>"

describe("UI/DialogueUIBook: Dialogue UI's book window", function()
  local WFJ, data, book, logs, shown

  local function key(en) return WFJ.Collector.key(en, PLAYER) end

  local function ship(rows)
    data = {}
    for en, ja in pairs(rows) do data[key(en)] = { ja = ja, status = "." } end
  end

  local function load(opts)
    opts = opts or {}
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    DUI.installGameAPI()
    DUI.installItemTextAPI()
    if opts.present ~= false then
      book = DUI.installBookFrame({ without = opts.without })
      Stub.loadedAddons.DialogueUI = true
    end
    WFJ = H.loadChunks(FILES)
    WFJ.Compat.init(function(name) return _G[name] end)
    WFJ.Settings.load(nil, 1, {})
    WFJ.Collector.load(nil, H.collectorDeps())
    data = {}
    WFJ.Render.init(WFJ.Translator.new({
      enabled = function() return WFJ.State.enabled end,
      areaEnabled = WFJ.State.areaEnabled,
      showsEnglish = WFJ.Modifier.english,
      lookup = function(kind, id) if kind == "book" then return data[id] end end,
      marker = function(n) return WFJ.Settings.get("marker." .. n) end,
    }))
    WFJ.LoadOnDemand.init(function(name) return C_AddOns.IsAddOnLoaded(name) end)
    logs = {}
    WFJ.Diag.log = function(kind, msg) logs[#logs + 1] = kind .. " " .. msg end
    shown = {}
    WFJ.State.on("lineShown", function(surface, recKey) shown[#shown + 1] = surface .. " " .. recKey end)
    WFJ.DialogueUIBook.init({ key = key })
  end

  local function texts()
    local out = {}
    for _, e in ipairs(book.ScrollFrame.content) do out[#out + 1] = e.text end
    return out
  end

  local function measured()
    local out = {}
    for _, e in ipairs(book.ScrollFrame.content) do out[#out + 1] = e.measuredText end
    return out
  end

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
    DUI.flush()
  end

  it("does nothing without Dialogue UI's book window", function()
    load({ present = false })
    assert.is_false(WFJ.DialogueUIBook.installed())
  end)

  it("installs nothing and logs one line when a member it relies on is missing", function()
    for _, member in ipairs({ "ShowUI", "OnSettingsChanged", "Init" }) do
      load({ without = { member } })
      assert.is_false(WFJ.DialogueUIBook.installed(), member)
      assert.are.equal(1, #logs, member)
    end
  end)

  it("a plain-text page shows its Japanese, measured again by Dialogue UI in the bundled font", function()
    load()
    ship({ [PLAIN] = PLAIN_JA })
    DUI.openBook({ PLAIN })
    DUI.flush()
    assert.are.same({ "最初の時代は長かった。", "二番目の時代は短かった。" }, texts())
    assert.are.same(texts(), measured())
    assert.are.equal(WFJ.Font.PATH, book.ScrollFrame.content[1].measuredFont[1])
  end)

  it("Japanese with fewer paragraphs empties the page's extra blocks; more joins the rest into the last", function()
    load()
    ship({ [PLAIN] = "一つの段落だけ。" })
    DUI.openBook({ PLAIN })
    DUI.flush()
    assert.are.same({ "一つの段落だけ。", "" }, texts())
    load()
    ship({ [PLAIN] = "一。\n\n二。\n\n三。" })
    DUI.openBook({ PLAIN })
    DUI.flush()
    assert.are.same({ "一。", "二。\n\n三。" }, texts())
  end)

  it("an HTML page swaps its blocks one for one", function()
    load()
    ship({ [HTML] = HTML_JA })
    DUI.openBook({ HTML })
    DUI.flush()
    assert.are.same({ "王について", "王は眠った。", "女王が治めた。" }, texts())
  end)

  it("an HTML page whose blocks do not line up stays English and is logged", function()
    load()
    ship({ [HTML] = "<HTML><BODY><P>一つだけ。</P></BODY></HTML>" })
    DUI.openBook({ HTML })
    DUI.flush()
    assert.are.same({ "Of Kings", "The king slept.", "The queen ruled." }, texts())
    assert.are.equal(1, #logs)
  end)

  it("each page of a book is keyed on its own; an untranslated page carries the missing marker", function()
    load()
    ship({ [PLAIN] = PLAIN_JA })
    DUI.openBook({ PLAIN, "An untranslated page." })
    DUI.flush()
    local t = texts()
    assert.are.equal("最初の時代は長かった。", t[1])
    assert.truthy(t[3]:find(WFJ.MARKER.missing, 1, true))
    assert.truthy(t[3]:find("An untranslated page.", 1, true))
  end)

  it("a letter a player wrote is left as it is", function()
    load()
    ship({ [PLAIN] = PLAIN_JA })
    DUI.book.creator = "Reyn"
    DUI.openBook({ PLAIN })
    DUI.flush()
    assert.are.same({ "The first age was long.", "The second age was short." }, texts())
  end)

  it("the reveal key puts the English back and measures again; letting go brings the Japanese back", function()
    load()
    ship({ [PLAIN] = PLAIN_JA })
    DUI.openBook({ PLAIN })
    DUI.flush()
    local lines = #shown
    alt(true)
    assert.are.same({ "The first age was long.", "The second age was short." }, texts())
    assert.are.same(texts(), measured())
    assert.are_not.equal(WFJ.Font.PATH, book.ScrollFrame.content[1].measuredFont[1])
    alt(false)
    assert.are.same({ "最初の時代は長かった。", "二番目の時代は短かった。" }, texts())
    assert.are.equal(lines, #shown)
  end)

  it("every page is shown as its own line, page by page, for the voice", function()
    load()
    ship({ [PLAIN] = PLAIN_JA, ["Page two."] = "二ページ目。" })
    DUI.openBook({ PLAIN, "Page two." })
    DUI.flush()
    assert.are.same({ "dialogueui.book page1", "dialogueui.book page2" }, shown)
    assert.are.equal("DUIBookFrame", WFJ.VoicePlayer.windowOf("dialogueui.book"))
  end)

  it("a blank page does not move the pages after it", function()
    load()
    ship({ [PLAIN] = PLAIN_JA, ["Page three."] = "三ページ目。" })
    DUI.openBook({ PLAIN, " ", "Page three." })
    DUI.flush()
    assert.are.same({ "最初の時代は長かった。", "二番目の時代は短かった。", "三ページ目。" }, texts())
  end)

  it("with the voice queue off only the first page is a voice line", function()
    load()
    WFJ.Settings.set("voice.panel.size", "off")
    ship({ [PLAIN] = PLAIN_JA, ["Page two."] = "二ページ目。" })
    DUI.openBook({ PLAIN, "Page two." })
    DUI.flush()
    assert.are.same({ "dialogueui.book page1", "dialogueui.book text2" }, shown)
  end)

  it("a switch that changes nothing in the book does not measure it again", function()
    load()
    ship({ [PLAIN] = PLAIN_JA })
    DUI.openBook({ PLAIN })
    DUI.flush()
    local n = book.measures
    WFJ.State.setArea("quests", false)
    DUI.flush()
    assert.are.equal(n, book.measures)
  end)

  it("puts the bundled face back when Dialogue UI sets its own on a font size change", function()
    load()
    ship({ [PLAIN] = PLAIN_JA })
    DUI.openBook({ PLAIN })
    DUI.flush()
    _G.DUIFont_Book_Paragraph:SetFont("Interface\\AddOns\\DialogueUI\\Fonts\\frizqt__.ttf", 16, "")
    book:measure() -- Dialogue UI measures again after its font change
    DUI.flush()
    assert.are.equal(WFJ.Font.PATH, (_G.DUIFont_Book_Paragraph:GetFont()))
    assert.are.equal(WFJ.Font.PATH, book.ScrollFrame.content[1].measuredFont[1])
    book:Hide()
    assert.are.same({ "Interface\\AddOns\\DialogueUI\\Fonts\\frizqt__.ttf", 16, "" },
      { _G.DUIFont_Book_Paragraph:GetFont() })
  end)

  it("the book fonts get Dialogue UI's own face back when the book closes", function()
    load()
    local orig = { _G.DUIFont_Book_Paragraph:GetFont() }
    ship({ [PLAIN] = PLAIN_JA })
    DUI.openBook({ PLAIN })
    DUI.flush()
    assert.are.equal(WFJ.Font.PATH, (_G.DUIFont_Book_Paragraph:GetFont()))
    book:Hide()
    assert.are.same(orig, { _G.DUIFont_Book_Paragraph:GetFont() })
  end)

  it("plain-text page blocks get word cards for their share of the page's words", function()
    load()
    local attached = {}
    WFJ.ReadingView = { attach = function(rec) attached[#attached + 1] = rec; return true end, detach = function() end }
    WFJ.Readings = { lookup = function(kind, _, text)
      if kind ~= "book" then return nil end
      local at = text:find("時代", 1, true)
      return at and { { first = at, last = at + 5, word = "時代", reading = "じだい" } } or nil
    end }
    ship({ [PLAIN] = PLAIN_JA })
    DUI.openBook({ PLAIN })
    DUI.flush()
    book:layout()
    assert.is_true(#attached >= 1)
    local rec = attached[#attached]
    assert.are.equal("dialogueui.book", rec.surface)
    assert.are.equal("book", rec.meta.kind)
    assert.is_table(rec.spans)
  end)
end)
