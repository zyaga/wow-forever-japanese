local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = { "Core/Const.lua", "Core/State.lua", "Core/Settings.lua", "Core/Modifier.lua",
  "Core/Translator.lua", "Core/SurfaceState.lua", "UI/Font.lua", "UI/Render.lua" }

describe("Render: refresh on state, per-FontString font", function()
  local WFJ, R, S
  local DATA = {
    quest = { [1] = { ja = "クエスト1", status = "." }, [2] = { ja = "クエスト2", status = "s" } },
    gossip = { g1 = { ja = "こんにちは", status = "." } },
  }

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    WFJ = H.loadChunks(FILES)
    R, S = WFJ.Render, WFJ.Settings
    S.load(nil, 1, {})
    R.init(WFJ.Translator.new({
      enabled = function() return WFJ.State.enabled end,
      areaEnabled = WFJ.State.areaEnabled,
      modifierHeld = WFJ.Modifier.isDown,
      lookup = function(kind, id) return DATA[kind] and DATA[kind][id] end,
      marker = function(n) return S.get("marker." .. n) end,
    }))
  end)

  local function showQuest(fs, id)
    return R.show("quest", "description", fs, fs:GetText(), "quests", "quest", id or 1)
  end

  it("modifier, master, and area changes restore / reapply the open records", function()
    local q = Stub.fontString("Quest text", "F.ttf", 14, "OUTLINE")
    local g = Stub.fontString("Hello", "F.ttf", 12, "")
    assert.is_true(showQuest(q))
    assert.is_true(R.show("gossip", 1, g, "Hello", "gossip", "gossip", "g1"))
    assert.are.equal("クエスト1", q:GetText())
    assert.are.same({ WFJ.Font.PATH, 14, "OUTLINE" }, { q:GetFont() })

    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal("Quest text", q:GetText())
    assert.are.same({ "F.ttf", 14, "OUTLINE" }, { q:GetFont() })
    assert.are.equal("Hello", g:GetText())

    Stub.keys.alt = false; WFJ.Modifier.refresh()
    assert.are.equal("クエスト1", q:GetText())
    assert.are.equal(WFJ.Font.PATH, (q:GetFont()))
    assert.are.equal("こんにちは", g:GetText())

    S.set("enabled", false)
    assert.are.equal("Quest text", q:GetText()); assert.are.equal("Hello", g:GetText())
    S.set("enabled", true)
    assert.are.equal("クエスト1", q:GetText())

    S.set("area.quests", false)
    assert.are.equal("Quest text", q:GetText())
    assert.are.equal("こんにちは", g:GetText())
  end)

  it("no flicker: with the modifier held, toggling the master writes nothing", function()
    local q = Stub.fontString("Quest text")
    showQuest(q)
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    local n = q.calls.SetText
    S.set("enabled", false)
    S.set("enabled", true)
    assert.are.equal(n, q.calls.SetText)
    -- and re-showing the same element while held is a no-op too
    assert.is_false(showQuest(q))
    assert.are.equal(n, q.calls.SetText)
  end)

  it("applies the bundled font at the element's own size and flags; counts SetFont failures", function()
    local q = Stub.fontString("Quest text", "F.ttf", 16, "THICKOUTLINE")
    showQuest(q)
    assert.are.same({ WFJ.Font.PATH, 16, "THICKOUTLINE" }, { q:GetFont() })
    assert.are.equal(0, R.fontFailures)
    Stub.fontSetFails = true
    local q2 = Stub.fontString("Other")
    R.show("quest", "objectives", q2, "Other", "quests", "quest", 1)
    assert.are.equal(1, R.fontFailures)
    -- where, for /wfj debug: per surface, the count and the first failing record's arguments
    assert.are.same({ quest = { n = 1, key = "objectives", size = 13, flags = "" } }, R.fontFailureSurfaces)
  end)

  it("a refused font is pending and retried until it applies; a retry is not counted again", function()
    Stub.fontSetFails = true
    local q = Stub.fontString("Quest text", "F.ttf", 16, "")
    showQuest(q)
    assert.are.equal("クエスト1", q:GetText())
    assert.are.equal(1, R.fontFailures)
    assert.are.equal(1, R.pendingFonts())
    assert.are.equal(1, R.retryFonts()) -- still refused: still pending, not counted twice
    assert.are.equal(1, R.fontFailures)
    Stub.fontSetFails = false
    assert.are.equal(0, R.retryFonts())
    assert.are.same({ WFJ.Font.PATH, 16, "" }, { q:GetFont() })
    assert.are.equal(0, R.pendingFonts())
    -- a record the client rewrote before the retry is dropped, never written over
    Stub.fontSetFails = true
    local q2 = Stub.fontString("Other", "F.ttf", 12, "")
    R.show("quest", "objectives", q2, "Other", "quests", "quest", 1)
    q2.text = "The client wrote this"
    Stub.fontSetFails = false
    assert.are.equal(0, R.retryFonts())
    assert.are.equal("The client wrote this", q2:GetText())
  end)

  it("Font.set remembers a refused font for the addon's own widgets; a later set replaces it", function()
    local fs = Stub.fontString("x", "F.ttf", 12, "")
    Stub.fontSetFails = true
    assert.is_false(WFJ.Font.set(fs, WFJ.Font.PATH, 14, ""))
    assert.are.equal(1, WFJ.Font.retryPending())
    Stub.fontSetFails = false
    assert.are.equal(0, WFJ.Font.retryPending())
    assert.are.same({ WFJ.Font.PATH, 14, "" }, { fs:GetFont() })
    Stub.fontSetFails = true
    WFJ.Font.set(fs, WFJ.Font.PATH, 14, "")
    Stub.fontSetFails = false
    WFJ.Font.set(fs, "F.ttf", 12, "") -- the widget went back to its own font: nothing left to retry
    assert.are.equal(0, WFJ.Font.retryPending())
    assert.are.same({ "F.ttf", 12, "" }, { fs:GetFont() })
  end)

  local function inl(name) return WFJ.MARKER_INLINE_COLOR .. WFJ.MARKER[name] .. "|r" end

  it("markers (no banner): stale message on its own line above a stale entry; missing message only when enabled",
  function()
    WFJ.Settings.set("marker.missing", false) -- on by default; this test reads the text, not the marker
    local q = Stub.fontString("Quest text")
    showQuest(q, 2)
    assert.are.equal(inl("stale") .. "\nクエスト2", q:GetText())
    S.set("marker.stale", false)
    assert.are.equal("クエスト2", q:GetText())

    local u = Stub.fontString("Untranslated", "F.ttf", 12, "")
    assert.is_false(R.show("quest", "progress", u, "Untranslated", "quests", "quest", 999))
    assert.are.equal("Untranslated", u:GetText())
    S.set("marker.missing", true)
    assert.are.equal(inl("missing") .. "\nUntranslated", u:GetText())
    assert.are.same({ WFJ.Font.PATH, 12, "" }, { u:GetFont() }) -- bundled font while the message shows (kanji legible)
    S.set("marker.missing", false)
    assert.are.equal("Untranslated", u:GetText())
    assert.are.same({ "F.ttf", 12, "" }, { u:GetFont() }) -- and the original font comes back with it
  end)

  it("re-entrant show (the hook echoing our text) is ignored", function()
    local q = Stub.fontString("Quest text")
    showQuest(q)
    local n = q.calls.SetText
    assert.is_false(showQuest(q)) -- fs now holds our Japanese: echo
    assert.are.equal(n, q.calls.SetText)
  end)

  it("calls ctx.refit after a write and release restores", function()
    local refits = 0
    local t = Stub.fontString("Use: heal")
    R.show("tooltip", 3, t, "Use: heal", "quests", "quest", 1, { refit = function() refits = refits + 1 end })
    assert.are.equal(1, refits)
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal(2, refits)
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    assert.are.equal(3, refits)
    assert.are.equal(1, R.release("tooltip"))
    assert.are.equal("Use: heal", t:GetText())
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal(3, refits) -- no records left
  end)

  it("translated quest, then an untranslated one on the same FontString → live English, original font",
  function()
    WFJ.Settings.set("marker.missing", false) -- on by default; this test reads the text, not the marker
    local q = Stub.fontString("Quest A", "F.ttf", 14, "OUTLINE")
    showQuest(q, 1)
    assert.are.equal("クエスト1", q:GetText())
    q.text = "Quest B" -- the client wrote the next quest's English (font still ours)
    R.show("quest", "description", q, "Quest B", "quests", "quest", 999)
    assert.are.equal("Quest B", q:GetText())
    assert.are.same({ "F.ttf", 14, "OUTLINE" }, { q:GetFont() })
    R.release("quest")
    assert.are.same({ "F.ttf", 14, "OUTLINE" }, { q:GetFont() })
  end)

  it("banner: a registered FontString carries the surface's marker messages; the text widgets stay clean", function()
    local b = Stub.fontString("")
    b:Hide()
    R.setBanner("quest", b)
    local q = Stub.fontString("Quest text")
    showQuest(q, 2) -- stale entry
    assert.are.equal("クエスト2", q:GetText())
    assert.are.equal(WFJ.MARKER.stale, b:GetText())
    assert.is_true(b:IsShown())

    local u = Stub.fontString("Untranslated", "F.ttf", 12, "")
    S.set("marker.missing", true)
    R.show("quest", "progress", u, "Untranslated", "quests", "quest", 999)
    assert.are.equal("Untranslated", u:GetText()) -- English untouched …
    assert.are.same({ "F.ttf", 12, "" }, { u:GetFont() }) -- … in its own font
    assert.are.equal(WFJ.MARKER.missing .. "  " .. WFJ.MARKER.stale, b:GetText()) -- both, missing first
    S.set("marker.missing", false)
    assert.are.equal(WFJ.MARKER.stale, b:GetText())
    S.set("marker.stale", false)
    assert.is_false(b:IsShown())
    S.set("marker.stale", true)
    assert.is_true(b:IsShown())
    R.release("quest")
    assert.is_false(b:IsShown())
    assert.are.equal("", b:GetText())
  end)

  it("a nil English with the missing marker on does not error", function()
    S.set("marker.missing", true)
    local u = Stub.fontString(nil)
    assert.has_no.errors(function() R.show("quest", "progress", u, nil, "quests", "quest", 999) end)
    assert.are.equal(inl("missing") .. "\n", u:GetText())
    S.set("marker.missing", false)
    assert.is_nil(u:GetText())
  end)

  it("refit runs once per surface per refresh, not once per record", function()
    local refits = 0
    local ctx = { refit = function() refits = refits + 1 end }
    for i = 1, 3 do
      R.show("tooltip", i, Stub.fontString("Line " .. i), "Line " .. i, "quests", "quest", 1, ctx)
    end
    assert.are.equal(3, refits) -- one per show
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal(4, refits) -- one per surface for the refresh
    assert.are.equal(0, R.release("tooltip")) -- already restored while held: nothing left to write
  end)

  it("a surface spanning two frames refits each frame once", function()
    local a, b = 0, 0
    local ctxA = { refit = function() a = a + 1 end }
    local ctxB = { refit = function() b = b + 1 end }
    R.show("items", 1, Stub.fontString("Use: x"), "Use: x", "quests", "quest", 1, ctxA)
    R.show("items", 2, Stub.fontString("Use: y"), "Use: y", "quests", "quest", 1, ctxA)
    R.show("items", 3, Stub.fontString("Equip: z"), "Equip: z", "quests", "quest", 1, ctxB)
    assert.are.same({ 2, 1 }, { a, b })
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.same({ 3, 2 }, { a, b })
  end)

  -- Main guards every init step, so a failed Render.init is survivable and every later surface still installs its
  -- hooks. Raising here would turn one load failure into an error on every hover, quest update and window open.
  -- Nothing to render against means nothing rendered, as Tooltip and Labels do for a missing WFJ.UIIndex.
  it("show before init renders nothing instead of raising", function()
    local ns = H.loadChunks(FILES)
    local ok, shown
    assert.has_no.errors(function()
      ok, shown = pcall(function()
        return ns.Render.show("q", "k", Stub.fontString("x"), "x", "quests", "quest", 1)
      end)
    end)
    assert.is_true(ok)
    assert.is_false(shown)
    assert.are.equal(0, ns.Render.refresh())
  end)
end)

describe("Render: companion records follow their primary", function()
  local WFJ, R, S, refits
  local DATA = { ["item.description"] = { [117] = { ja = "18秒間でhealthを61回復。", status = "u" } } }

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    WFJ = H.loadChunks(FILES)
    R, S = WFJ.Render, WFJ.Settings
    S.load(nil, 1, {})
    refits = 0
    R.init(WFJ.Translator.new({
      enabled = function() return WFJ.State.enabled end,
      areaEnabled = WFJ.State.areaEnabled,
      modifierHeld = WFJ.Modifier.isDown,
      lookup = function(kind, id) return DATA[kind] and DATA[kind][id] end,
      marker = function(n) return S.get("marker." .. n) end,
      align = function(ja, lines) return lines ~= nil and #lines == 2, ja end,
    }))
  end)

  local function run()
    local use = Stub.fontString("Use: Restores 61 health over 18 sec.", "F.ttf", 12, "")
    local quote = Stub.fontString('"Tough as leather."', "F.ttf", 12, "")
    local refit = function() refits = refits + 1 end
    R.show("tooltip.GameTooltip", "desc", use, use:GetText(), "items", "item.description", 117,
      { lines = { use:GetText(), quote:GetText() }, refit = refit })
    R.show("tooltip.GameTooltip", "desc.2", quote, quote:GetText(), "items", "item.description", 117,
      { follow = "desc", refit = refit })
    return use, quote
  end

  it("blanks the companion while the primary is applied and restores both together", function()
    local use, quote = run()
    assert.are.equal("18秒間でhealthを61回復。", use:GetText())
    assert.are.equal(R.BLANK, quote:GetText())
    assert.are.same({ "F.ttf", 12, "" }, { quote:GetFont() }) -- companion keeps its original font
    assert.are.equal(2, refits) -- one per show that wrote

    refits = 0
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal("Use: Restores 61 health over 18 sec.", use:GetText())
    assert.are.equal('"Tough as leather."', quote:GetText())
    assert.are.equal(1, refits) -- one refit per refresh, deduped across the surface's records

    Stub.keys.alt = false; WFJ.Modifier.refresh()
    assert.are.equal("18秒間でhealthを61回復。", use:GetText())
    assert.are.equal(R.BLANK, quote:GetText())

    S.set("area.itemTooltips", false)
    assert.are.equal('"Tough as leather."', quote:GetText())
    S.set("area.itemTooltips", true)
    assert.are.equal(R.BLANK, quote:GetText())
    S.set("enabled", false)
    assert.are.equal('"Tough as leather."', quote:GetText())
  end)

  it("never writes the companion when the primary never applies", function()
    WFJ.Settings.set("marker.missing", false) -- on by default; this test reads the text, not the marker
    DATA["item.description"][117].ja = ""
    local use, quote = run()
    assert.are.equal("Use: Restores 61 health over 18 sec.", use:GetText())
    assert.are.equal('"Tough as leather."', quote:GetText())
    assert.are.equal(0, quote.calls.SetText)
    assert.are.equal(0, refits)
    DATA["item.description"][117].ja = "18秒間でhealthを61回復。"
  end)

  it("releases both with the surface", function()
    local use, quote = run()
    R.release("tooltip.GameTooltip")
    assert.are.equal("Use: Restores 61 health over 18 sec.", use:GetText())
    assert.are.equal('"Tough as leather."', quote:GetText())
    assert.are.equal(0, WFJ.SurfaceState.count("tooltip.GameTooltip"))
  end)
end)

describe("Render: a companion never blanks when the primary shows English + missing marker", function()
  local WFJ, R, S
  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    WFJ = H.loadChunks(FILES)
    R, S = WFJ.Render, WFJ.Settings
    S.load(nil, 1, {})
    S.set("marker.missing", true)
    R.init(WFJ.Translator.new({
      enabled = function() return WFJ.State.enabled end,
      areaEnabled = WFJ.State.areaEnabled,
      modifierHeld = WFJ.Modifier.isDown,
      lookup = function() return { ja = "18秒間でhealthを61回復。", status = "u" } end,
      marker = function(n) return S.get("marker." .. n) end,
      align = function() return false end, -- the gate fails
    }))
  end)

  it("marks the primary with the inline missing message and leaves every companion line untouched", function()
    local use = Stub.fontString("Use: Restores 70 health over 18 sec.", "F.ttf", 12, "")
    local quote = Stub.fontString('"Tough as leather."', "F.ttf", 12, "")
    R.show("tooltip.GameTooltip", "desc", use, use:GetText(), "items", "item.description", 117,
      { lines = { use:GetText() } })
    R.show("tooltip.GameTooltip", "desc.2", quote, quote:GetText(), "items", "item.description", 117,
      { follow = "desc" })
    -- tooltips have no banner: the message goes inline, on its own line above the English
    local msg = WFJ.MARKER_INLINE_COLOR .. WFJ.MARKER.missing .. "|r\n"
    assert.are.equal(msg .. "Use: Restores 70 health over 18 sec.", use:GetText())
    assert.are.equal('"Tough as leather."', quote:GetText())
    assert.are.equal(0, quote.calls.SetText)
  end)
end)
