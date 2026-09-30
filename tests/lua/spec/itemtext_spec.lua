-- UI/ItemText: the book / letter / plaque window's page text on its SimpleHTML (itemtext_client.lua
-- replays Forever's mainline ItemTextFrameMixin:OnEvent, which writes ItemTextGetText() with no leading newline).
-- `html.writes` lists every text the page received, the client's and ours, in order. A plain-text page's
-- Japanese is drawn in the adapter's own FontString (`drawn()`), the SimpleHTML given "".
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local Client = require("tests.lua.spec.itemtext_client")

local FILES = { "Core/Const.lua", "Core/Compat.lua", "Core/Normalize.lua", "Core/Hash.lua", "Core/Data.lua",
  "Core/Lookup.lua", "Core/State.lua", "Core/Settings.lua", "Core/Modifier.lua", "Core/Translator.lua",
  "Core/SurfaceState.lua", "Core/Collector.lua", "UI/Font.lua", "UI/Render.lua", "UI/ItemText.lua" }

local PLAYER = { name = "Reyn", class = "Hunter", race = "Night Elf" }
-- a page as VMaNGOS stores it ($B tokens) and as the client shows it (line breaks)
local PAGE_DATA = "These demon plates were worn by the creature that first cursed our people.$B$B- Thrall"
local PAGE_LIVE = "These demon plates were worn by the creature that first cursed our people.\n\n- Thrall"
local PAGE_JA = "この悪魔の鎧は、我らの民に初めて血の渇きの呪いをかけた者が身に着けていた。\n\n- Thrall"
local PAGE2 = "The second page has no translation."
local HTML_LIVE = "<HTML>\n<BODY>\n<P>\nIn memory of my dear mentor.\n</P>\n</BODY>\n</HTML>"
local HTML_JA = "<HTML>\n<BODY>\n<P>\n親愛なる師を偲んで。\n</P>\n</BODY>\n</HTML>"

describe("UI/ItemText: the book window", function()
  local WFJ, S, SS, IT, html

  local function keys(en) return WFJ.Collector.keys(en, PLAYER) end
  local function keyOf(en)
    for _, k in ipairs(keys(en)) do if WFJ.Lookup.keyed("book", k) then return k end end
    return keys(en)[1]
  end

  -- rows by stored English: { [en] = ja }
  local function ship(rows)
    local t = {}
    for en, ja in pairs(rows) do t[WFJ.Hash.key(WFJ.Normalize.v1(en))] = { ja, "." } end
    WFJ.Data.add("book", t)
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    local _
    _, html = Stub.installItemTextAPI()
    WFJ = H.loadChunks(FILES)
    S, SS, IT = WFJ.Settings, WFJ.SurfaceState, WFJ.ItemText
    WFJ.Compat.init(function(name) return _G[name] end)
    S.load(nil, 1, {})
    WFJ.Render.init(WFJ.Translator.new({
      enabled = function() return WFJ.State.enabled end,
      areaEnabled = WFJ.State.areaEnabled,
      modifierHeld = WFJ.Modifier.isDown,
      lookup = WFJ.Lookup.get,
      marker = function(n) return S.get("marker." .. n) end,
    }))
    assert.is_true(IT.init({ key = keyOf, keys = keys }))
  end)

  after_each(function() Client.stickyObjects = false; Stub.fontSetFails = false end)

  local function tag(t) return html.tags[t] end
  -- the text our FontString shows ("" / nil when it is hidden)
  local function drawn() local fs = IT.page.fs; return fs and fs.shown and fs.text or nil end

  -- the client's styling for a material (nil → "Parchment", the default font table, the text colour on every type)
  local function assertClientStyle(material)
    local fonts = Client.FONTS[material] or Client.FONTS.default
    for _, t in ipairs(Client.TAGS) do
      local c = (material == "ParchmentLarge" and t ~= "P") and Client.TITLE or Client.PARCHMENT
      assert.are.equal(fonts[t].path, (html:GetFont(t)), t)
      assert.are.equal(fonts[t], tag(t).object, t)
      assert.are.same({ c[1], c[2], c[3], 1 }, tag(t).color, t)
    end
  end

  it("hooks once: the page's SetText, the frame's OnEvent and OnHide", function()
    assert.is_false(IT.init({ key = keyOf, keys = keys }))
    assert.are.equal(1, #Stub.hooks["ItemTextPageText:SetText"])
  end)

  it("a shipped page shows its Japanese, written as Forever writes a page (no leading newline), in the "
    .. "bundled font on every text type with the client's colours", function()
    ship({ [PAGE_DATA] = PAGE_JA })
    Stub.openItemText({ PAGE_LIVE })
    assert.are.equal(PAGE_JA, drawn())
    for _, t in ipairs(Client.TAGS) do
      assert.are.equal(WFJ.Font.PATH, (html:GetFont(t)), t)
      assert.are.same({ Client.PARCHMENT[1], Client.PARCHMENT[2], Client.PARCHMENT[3], 1 }, tag(t).color, t)
    end
    assert.are.same({ PAGE_LIVE, "" }, html.writes) -- the client's write, then ours (emptied)
    -- our FontString, where the SimpleHTML's text starts, as wide, in the P font and colour
    local fs = IT.page.fs
    assert.are.equal(WFJ.Font.PATH, (fs:GetFont()))
    assert.are.same({ Client.PARCHMENT[1], Client.PARCHMENT[2], Client.PARCHMENT[3], 1 }, fs.color)
    assert.are.equal(270, fs.width)
    assert.are.same({ "TOPLEFT", html, "TOPLEFT", 0, 0 }, fs.point)
  end)

  it("an HTML page's Japanese is written as HTML (never in our FontString)", function()
    ship({ [HTML_LIVE] = HTML_JA })
    Stub.openItemText({ HTML_LIVE })
    assert.are.equal(HTML_JA, html.text)
    assert.is_nil(drawn())
  end)

  it("a letter a player wrote (a creator) is untouched, even under a matching key and with the missing marker",
    function()
      ship({ [PAGE_DATA] = PAGE_JA })
      S.set("marker.missing", true)
      Stub.openItemText({ PAGE_LIVE }, "Somebody")
      assert.are.same({ PAGE_LIVE .. "\n\nFrom\nSomebody\n" }, html.writes) -- the client's write only
      assertClientStyle()
      assert.is_nil(SS.get(IT.SURFACE, "page"))
    end)

  it("an unshipped page is exactly what the client wrote; the missing marker goes above it", function()
    WFJ.Settings.set("marker.missing", false) -- on by default; this test reads the text, not the marker
    Stub.openItemText({ PAGE2 })
    assert.are.same({ PAGE2 }, html.writes) -- the client's write only
    assert.are.equal(0, html.calls.SetFont)
    assertClientStyle()
    S.set("marker.missing", true)
    WFJ.Render.refresh(IT.SURFACE)
    -- the client's English under the marker stays in the SimpleHTML, never in our FontString
    assert.are.equal(WFJ.MARKER_INLINE_COLOR .. WFJ.MARKER.missing .. "|r\n" .. PAGE2, html.text)
    assert.is_nil(drawn())
    S.set("marker.missing", false)
    WFJ.Render.refresh(IT.SURFACE)
    assert.are.equal(PAGE2, html.text)
    assert.is_nil(drawn())
    assertClientStyle()
  end)

  it("on an HTML page the missing marker is a paragraph inside the body", function()
    S.set("marker.missing", true)
    Stub.openItemText({ HTML_LIVE })
    assert.are.equal("<HTML>\n<BODY>\n<P>" .. WFJ.MARKER_INLINE_COLOR .. WFJ.MARKER.missing .. "|r</P>\n<P>\n"
      .. "In memory of my dear mentor.\n</P>\n</BODY>\n</HTML>", html.text)
  end)

  it("the reveal key, the master switch and area.books put back the client's text, font objects and colours",
    function()
      ship({ [PAGE_DATA] = PAGE_JA })
      Stub.openItemText({ PAGE_LIVE })
      local flips = {
        { function() Stub.keys.alt = true; WFJ.Modifier.refresh() end,
          function() Stub.keys.alt = false; WFJ.Modifier.refresh() end },
        { function() S.set("enabled", false) end, function() S.set("enabled", true) end },
        { function() S.set("area.books", false) end, function() S.set("area.books", true) end },
      }
      for _, f in ipairs(flips) do
        f[1]()
        assert.are.equal(PAGE_LIVE, html.text)
        assertClientStyle()
        assert.is_nil(drawn())
        f[2]()
        assert.are.equal(PAGE_JA, drawn())
        assert.are.equal("", html.text)
        assert.are.equal(WFJ.Font.PATH, (html:GetFont("H1")))
      end
    end)

  it("the English font comes back even when the engine ignores re-assigning the same font object", function()
    Client.stickyObjects = true
    ship({ [PAGE_DATA] = PAGE_JA })
    Stub.openItemText({ PAGE_LIVE })
    assert.are.equal(WFJ.Font.PATH, (html:GetFont("P")))
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal(PAGE_LIVE, html.text)
    assertClientStyle()
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    assert.are.equal(WFJ.Font.PATH, (html:GetFont("H2")))
  end)

  it("a refused font is read back (SimpleHTML SetFont returns nothing), counted, kept English-styled and retried",
    function()
      ship({ [PAGE_DATA] = PAGE_JA })
      Stub.fontSetFails = true
      Stub.openItemText({ PAGE_LIVE })
      assert.are.equal(PAGE_JA, drawn())
      assert.are.equal(1, WFJ.Render.pendingFonts())
      assert.are.equal(1, WFJ.Render.fontFailures)
      assertClientStyle()
      Stub.fontSetFails = false
      assert.are.equal(0, WFJ.Render.retryFonts())
      for _, t in ipairs(Client.TAGS) do assert.are.equal(WFJ.Font.PATH, (html:GetFont(t)), t) end
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      assertClientStyle()
      Stub.keys.alt = false; WFJ.Modifier.refresh()
    end)

  it("turning pages shows each page's own text, never the previous page's", function()
    WFJ.Settings.set("marker.missing", false) -- on by default; this test reads the text, not the marker
    ship({ [PAGE_DATA] = PAGE_JA })
    Stub.openItemText({ PAGE_LIVE, PAGE2 })
    assert.are.equal(PAGE_JA, drawn())
    Stub.itemTextPage(2)
    assert.are.equal(PAGE2, html.text)
    assert.is_nil(drawn()) -- the client's write takes the page back from our FontString
    assertClientStyle()
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    assert.are.equal(PAGE2, html.text)
    Stub.itemTextPage(1)
    assert.are.equal(PAGE_JA, drawn())
    assert.are.equal(1, SS.count(IT.SURFACE))
  end)

  it("another item opened while the window is shown starts from the client's styling", function()
    ship({ [PAGE_DATA] = PAGE_JA })
    Stub.openItemText({ PAGE_LIVE })
    Stub.openItemText({ PAGE_LIVE })
    assert.are.equal(PAGE_JA, drawn())
    assert.are.equal(WFJ.Font.PATH, (html:GetFont("P")))
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assertClientStyle()
    Stub.keys.alt = false; WFJ.Modifier.refresh()
  end)

  it("a page whose SimpleHTML does not hold the text the getters build is left alone", function()
    ship({ [PAGE_DATA] = PAGE_JA })
    Stub.itemText.pages = { PAGE_LIVE }
    _G.ItemTextFrame:fire("ITEM_TEXT_BEGIN")
    html:SetText("something else") -- another writer got there
    assert.are.equal(0, IT.onReady())
    assert.are.equal("something else", html.text)
    assert.is_nil(SS.get(IT.SURFACE, "page"))
  end)

  it("the page is shown only when the SimpleHTML received exactly ItemTextGetText() (Forever adds no newline)",
    function()
      ship({ [PAGE_DATA] = PAGE_JA })
      Stub.itemText.pages = { PAGE_LIVE }
      _G.ItemTextFrame:fire("ITEM_TEXT_BEGIN")
      html:SetText(PAGE_LIVE) -- exactly what Forever writes (itemtextframe.lua:124)
      assert.are.equal(1, IT.onReady())
      assert.are.equal(PAGE_JA, drawn())
      for _, other in ipairs({ "\n" .. PAGE_LIVE, PAGE_LIVE .. "\n", "something else" }) do
        IT.release()
        _G.ItemTextFrame:fire("ITEM_TEXT_BEGIN")
        html:SetText(other) -- the Era shape, a trailing newline, another writer
        assert.are.equal(0, IT.onReady(), other)
        assert.are.equal(other, html.text)
        assert.is_nil(drawn())
        assert.is_nil(SS.get(IT.SURFACE, "page"))
      end
    end)

  it("a ParchmentLarge book keeps its headings' sizes relative to the prose, and its title colours on reveal",
    function()
      ship({ [PAGE_DATA] = PAGE_JA })
      Stub.openItemText({ PAGE_LIVE }, nil, "ParchmentLarge")
      assert.are.equal(PAGE_JA, drawn())
      local _, pSize = html:GetFont("P")
      local _, h1Size = html:GetFont("H1")
      assert.are.equal(WFJ.Font.PATH, (html:GetFont("H1")))
      assert.are.equal(pSize * 48 / Client.CLIENT_FONT.size, h1Size)
      assert.are.same({ Client.TITLE[1], Client.TITLE[2], Client.TITLE[3], 1 }, tag("H2").color)
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      assert.are.equal(PAGE_LIVE, html.text)
      assertClientStyle("ParchmentLarge")
      Stub.keys.alt = false; WFJ.Modifier.refresh()
    end)

  it("every write re-measures the scroll child (our FontString's page by its own height)", function()
    ship({ [PAGE_DATA] = PAGE_JA })
    Stub.itemText.range = 120
    Stub.openItemText({ PAGE_LIVE })
    local child = _G.ItemTextScrollFrame:GetScrollChild()
    local rects = _G.ItemTextScrollFrame.calls.UpdateScrollChildRect
    assert.are.equal(2, rects) -- the client's, then ours
    -- the Japanese fits the frame (15 + its height < 355): no scrolling, whatever the English needed
    assert.are.same({ 1, 355 + 120 + 30, 1 }, child.heights)
    Stub.itemText.range = 0
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal(3, _G.ItemTextScrollFrame.calls.UpdateScrollChildRect)
    assert.are.equal(1, child.height)
    Stub.keys.alt = false; WFJ.Modifier.refresh()
  end)

  it("a Japanese page taller than the frame makes the scroll child tall enough to hold it", function()
    ship({ [PAGE_DATA] = PAGE_JA })
    Stub.openItemText({ PAGE_LIVE })
    local fs, child = IT.page.fs, _G.ItemTextScrollFrame:GetScrollChild()
    function fs.GetStringHeight() return 600 end
    IT.refit()
    assert.are.equal(15 + 600 + 30, child.height)
  end)

  it("Japanese that ends with the page's English is still drawn in our FontString", function()
    local en = "Tirion"
    ship({ [en] = "この書を記した者：Tirion" })
    Stub.openItemText({ en })
    assert.are.equal("この書を記した者：Tirion", drawn())
    assert.are.equal("", html.text)
  end)

  it("a font that takes late (retryFonts) re-sizes the scroll child for the drawn page", function()
    ship({ [PAGE_DATA] = PAGE_JA })
    Stub.fontSetFails = true
    Stub.openItemText({ PAGE_LIVE })
    local fs, child = IT.page.fs, _G.ItemTextScrollFrame:GetScrollChild()
    function fs.GetStringHeight() return 600 end
    Stub.fontSetFails = false
    assert.are.equal(0, WFJ.Render.retryFonts())
    assert.are.equal(15 + 600 + 30, child.height)
  end)

  it("closing the window releases the surface", function()
    ship({ [PAGE_DATA] = PAGE_JA })
    Stub.openItemText({ PAGE_LIVE })
    Stub.closeItemText()
    assert.are.equal(0, SS.count(IT.SURFACE))
    assert.are.equal(PAGE_LIVE, html.text)
    assert.is_nil(drawn())
    assertClientStyle()
  end)

  it("inspect reports the open page's keys and the shipped one", function()
    assert.is_false(IT.inspect().open)
    ship({ [PAGE_DATA] = PAGE_JA })
    Stub.openItemText({ PAGE_LIVE })
    local info = IT.inspect()
    assert.is_true(info.open)
    assert.are.same(keys(PAGE_LIVE), info.keys)
    assert.are.equal(WFJ.Hash.key(WFJ.Normalize.v1(PAGE_DATA)), info.shipped)
    assert.is_table(info.record)
  end)
end)
