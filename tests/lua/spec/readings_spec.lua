-- The word-reading box (ADR-036): the crash guard, word location, where it attaches and the setting.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = { "Core/Const.lua", "Core/Data.lua", "Core/Readings.lua", "Core/State.lua", "Core/Settings.lua",
  "Core/Modifier.lua", "Core/Translator.lua", "Core/SurfaceState.lua", "Core/Compat.lua", "UI/Font.lua",
  "UI/Readings.lua", "UI/Render.lua" }

local JA = "御機嫌よう、{name}。私はConservator Ilthalaine。少しの生き物たちを狩り、数を減らしてほしい。"
-- word, reading, meaning number (false when the word carries none)
local WORDS = { "御機嫌よう", "ごきげんよう", false, "私", "わたし", false, "少し", "すこし", false, "生き物", "いきもの", 7,
  "狩り", "かり", false, "数", "かず", false, "減らして", "へらして", false }
local PACKED = "御機嫌よう=ごきげんよう 私=わたし 少し=すこし 生き物=いきもの=7 狩り=かり 数=かず 減らして=へらして"

local function isBoundary(text, i)
  if i == #text + 1 then return true end
  local c = text:byte(i)
  return c ~= nil and (c < 0x80 or c >= 0xC0)
end

-- A FontString whose span call behaves like the client's: a split character or an escape sequence is fatal (the
-- client exits; here: error), anything else returns one area per call.
local function spanFontString(text)
  local fs = Stub.fontString(text, "F.ttf", 14, "")
  fs.spanCalls = 0
  function fs:CalculateScreenAreaFromCharacterSpan(a, b)
    self.spanCalls = self.spanCalls + 1
    local t = self.text
    if t:find("|", 1, true) then error("CRASH: escape sequence") end
    if not isBoundary(t, a) or not isBoundary(t, b) or b <= a then error(("CRASH: span %d..%d"):format(a, b)) end
    return { { left = a, bottom = 0, width = b - a, height = 14 } }
  end
  function fs:GetParent() return self.parentFrame end
  return fs
end

-- The frame methods UI/Readings uses that the shared stub does not carry.
local function extendFrames()
  local create = _G.CreateFrame
  _G.CreateFrame = function(...)
    local f = create(...)
    function f:SetAllPoints(target) self.allPoints = target or true end
    function f:GetParent() return self.parent end
    function f:SetParent(p) self.parent = p end
    function f:IsMouseOver() return self.mouseOver == true end
    function f:SetMouseMotionEnabled(v) self.motion = v end
    function f:SetPropagateMouseMotion(v) self.propagate = v end
    function f:SetFrameStrata(s) self.strata = s end
    function f:ClearAllPoints() self.point = nil end
    function f:SetShown(v) if v then self:Show() else self:Hide() end end
    function f.GetLeft() return 100 end
    function f.GetBottom() return 200 end
    function f.GetEffectiveScale() return 1 end
    local createTexture = f.CreateTexture
    function f:CreateTexture(...)
      local t = createTexture(self, ...)
      function t.SetAllPoints() end
      function t.ClearAllPoints(tx) tx.point = nil end
      function t.Show(tx) tx.shown = true end
      function t.Hide(tx) tx.shown = false end
      return t
    end
    local createFontString = f.CreateFontString
    function f:CreateFontString(...)
      local fs = createFontString(self, ...)
      function fs.GetStringWidth() return 40 end
      function fs.GetStringHeight() return 12 end
      return fs
    end
    return f
  end
end

describe("Readings", function()
  local WFJ, R, S, V

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    extendFrames()
    _G.UIParent = CreateFrame("Frame", "UIParent")
    _G.GetCursorPosition = function() return Stub.cursor[1], Stub.cursor[2] end
    Stub.cursor = { 0, 0 }
    WFJ = H.loadChunks(FILES)
    WFJ.Compat.init(function(name) return _G[name] end)
    WFJ.Data.add("reading", { ["quest:456"] = { description = PACKED }, ["gossip:g1"] = { text = "私=わたし" },
      ["ui:QUEST_REWARDS"] = { text = "報酬=ほうしゅう" }, ["book:bk1"] = { text = "悪魔=あくま 鎧=よろい" } })
    R, S, V = WFJ.Render, WFJ.Settings, WFJ.ReadingView
    S.load(nil, 1, {})
    local DATA = { ["quest.description"] = { [456] = { ja = JA:gsub("{name}", "Reyn"), status = "." } },
      gossip = { g1 = { ja = "私は元気だ。", status = "." } }, ["quest.title"] = { [456] = { ja = "題", status = "." } },
      ui = { QUEST_REWARDS = { ja = "報酬", status = "." }, CLASS_LABEL = { ja = "ドルイドの道", status = "." } },
      book = { bk1 = { ja = "この悪魔の鎧は古い。", status = "." },
        bk2 = { ja = "<HTML><BODY><P>悪魔の鎧</P></BODY></HTML>", status = "." } } }
    R.init(WFJ.Translator.new({
      enabled = function() return WFJ.State.enabled end,
      areaEnabled = WFJ.State.areaEnabled,
      modifierHeld = WFJ.Modifier.isDown,
      lookup = function(kind, id) return DATA[kind] and DATA[kind][id] end,
      marker = function() return false end,
    }))
  end)

  after_each(function() _G.UIParent, _G.GetCursorPosition = nil, nil end)

  local function questFs()
    local fs = spanFontString("Greetings, Reyn.")
    fs.parentFrame = CreateFrame("Frame")
    return fs
  end

  local function coverOf(fs)
    for _, f in ipairs(Stub.frames) do if f.allPoints == fs then return f end end
    return nil
  end

  -- ── word location ────────────────────────────────────────────────

  describe("Core/Readings (pure)", function()
    it("finds the words in order in the text on screen, with the name substituted", function()
      local ns = { Data = { reading = { ["quest:456"] = { description = PACKED } } } }
      H.loadPure("Core/Readings.lua", nil, ns)
      local text = JA:gsub("{name}", "Reyn")
      local spans = ns.Readings.lookup("quest.description", 456, text)
      assert.are.equal(7, #spans)
      for i, sp in ipairs(spans) do assert.are.equal(WORDS[3 * i - 2], text:sub(sp.first, sp.last)) end
      assert.are.equal("すこし", spans[3].reading)
    end)

    it("a word the text does not hold is skipped; the rest are still found", function()
      local ns = { Data = { reading = { ["quest:456"] = { description = PACKED } } } }
      H.loadPure("Core/Readings.lua", nil, ns)
      local text = JA:gsub("{name}", "Reyn"):gsub("少し", "たくさん")
      local spans = ns.Readings.lookup("quest.description", 456, text)
      assert.are.equal(6, #spans)
      assert.are.equal("生き物", text:sub(spans[3].first, spans[3].last))
    end)

    it("the packed row parses back to the word list", function()
      local ns = { Data = { reading = { ["quest:456"] = { description = PACKED } } } }
      H.loadPure("Core/Readings.lua", nil, ns)
      assert.are.same(WORDS, ns.Readings.words("quest.description", 456))
    end)

    it("no row, another field, or an unknown kind → nil", function()
      local ns = { Data = { reading = { ["quest:456"] = { description = PACKED } } } }
      H.loadPure("Core/Readings.lua", nil, ns)
      assert.is_nil(ns.Readings.lookup("quest.title", 456, "x"))
      assert.is_nil(ns.Readings.lookup("quest.description", 457, "x"))
      assert.is_nil(ns.Readings.lookup("item.description", 456, "x"))
      assert.is_nil(ns.Readings.words("gossip", nil))
    end)
  end)

  -- ── the crash guard ──────────────────────────────────────────────

  describe("the crash guard", function()
    it("never calls the client with a split character, a bad range or an escape sequence", function()
      local text = "自然界のバランス"
      local fs = spanFontString(text)
      local cases = {
        { 2, 3 }, -- inside 自 (3 bytes)
        { 1, 1 }, -- right end 2 would split 自
        { 4, 2 }, -- right before left
        { 0, 3 }, -- left out of range
        { 1, #text + 1 }, -- right past the end
      }
      for _, c in ipairs(cases) do
        assert.has_no.errors(function() assert.is_nil((V.spanAreas(fs, text, c[1], c[2]))) end)
      end
      assert.are.equal(0, fs.spanCalls)
      assert.are.equal(#cases, V.refused)
      assert.is_string(V.refusedAt)
      local esc = "|cffffd100自然|r界"
      fs.text = esc
      assert.has_no.errors(function() assert.is_nil((V.spanAreas(fs, esc, 11, 16))) end)
      assert.are.equal(0, fs.spanCalls)
    end)

    it("calls the client for every whole word of a line (bytes, right end exclusive)", function()
      local text = JA:gsub("{name}", "Reyn")
      local fs = spanFontString(text)
      local spans = WFJ.Readings.lookup("quest.description", 456, text)
      for _, sp in ipairs(spans) do
        local areas
        assert.has_no.errors(function() areas = V.spanAreas(fs, text, sp.first, sp.last) end)
        assert.are.equal(sp.first, areas[1].left)
        assert.are.equal(sp.last + 1 - sp.first, areas[1].width)
      end
      assert.are.equal(#spans, fs.spanCalls)
    end)
  end)

  -- ── where it attaches ────────────────────────────────────────────

  describe("attach / detach through Render", function()
    it("attaches after an apply on a quest prose surface and shows the whole reading under the mouse", function()
      local fs = questFs()
      R.show("questframe.detail", "description", fs, fs:GetText(), "quests", "quest.description", 456)
      local cover = coverOf(fs)
      assert.is_table(cover)
      assert.is_true(cover:IsShown())
      assert.is_true(cover.motion)
      -- the mouse over 少し: cover origin (100, 200); areas are x = first byte .. right, y = 0..14
      local text = fs:GetText()
      local s, e = text:find("少し", 1, true)
      Stub.cursor = { 100 + s + 1, 205 }
      cover.scripts.OnEnter(cover)
      assert.is_function(cover.scripts.OnUpdate)
      cover.scripts.OnUpdate(cover, 0.01)
      local box
      for _, f in ipairs(Stub.frames) do if f.strata == "TOOLTIP" then box = f end end
      assert.is_true(box:IsShown())
      local label
      for _, c in ipairs(box.children) do if c.GetText then label = c end end
      assert.are.equal("すこし", label:GetText())
      -- BOTTOM of the box at the middle of the word's top edge, 2 px up, relative to the cover's BOTTOMLEFT
      assert.are.same({ "BOTTOM", cover, "BOTTOMLEFT", s + (e + 1 - s) / 2, 0 + 14 + 2 }, box.point)
      -- off every word: hidden
      Stub.cursor = { 100 + #text + 50, 205 }
      cover.scripts.OnUpdate(cover, 0.01)
      assert.is_false(box:IsShown())
      cover.scripts.OnLeave(cover)
      assert.is_nil(cover.scripts.OnUpdate)
    end)

    it("in combat a line with no cover yet gets none (the propagate call is protected); out of combat it does",
    function()
      local fs = questFs()
      Stub.combat = true
      R.show("questframe.detail", "description", fs, fs:GetText(), "quests", "quest.description", 456)
      assert.is_nil(coverOf(fs))
      Stub.combat = false
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      Stub.keys.alt = false; WFJ.Modifier.refresh()
      assert.is_true(coverOf(fs).propagate)
    end)

    it("the modifier (English) detaches; letting go attaches again", function()
      local fs = questFs()
      R.show("questframe.detail", "description", fs, fs:GetText(), "quests", "quest.description", 456)
      local cover = coverOf(fs)
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      assert.are.equal("Greetings, Reyn.", fs:GetText())
      assert.is_false(cover:IsShown())
      Stub.keys.alt = false; WFJ.Modifier.refresh()
      assert.is_true(cover:IsShown())
    end)

    it("release and forget detach", function()
      local fs = questFs()
      R.show("questframe.detail", "description", fs, fs:GetText(), "quests", "quest.description", 456)
      R.release("questframe.detail")
      assert.is_false(coverOf(fs):IsShown())
      R.show("questframe.detail", "description", fs, fs:GetText(), "quests", "quest.description", 456)
      assert.is_true(coverOf(fs):IsShown())
      R.forget("questframe.detail")
      assert.is_false(coverOf(fs):IsShown())
    end)

    it("a tooltip, a list row, a gossip option or a widget without the span call gets no cover", function()
      local fs = questFs()
      R.show("tooltip.item", "desc", fs, fs:GetText(), "quests", "quest.description", 456)
      R.show("tracker", "title", questFs(), "x", "quests", "quest.description", 456)
      local opt = spanFontString("Hello")
      opt.parentFrame = CreateFrame("Frame")
      R.show("gossip", "option.1", opt, "Hello", "gossip", "gossip", "g1")
      local plain = Stub.fontString("Greetings, Reyn.")
      R.show("questframe.detail", "description", plain, "Greetings, Reyn.", "quests", "quest.description", 456)
      assert.is_nil(coverOf(fs)); assert.is_nil(coverOf(opt)); assert.is_nil(coverOf(plain))
      assert.are.equal(0, V.attached)
    end)

    -- ── ADR-044: book / letter pages, drawn in UI/ItemText's own FontString ──────────────────────
    -- A page adapter as UI/ItemText's: plain text goes to its FontString (spanRegion), HTML stays in the SimpleHTML.
    local function pageAdapter(en)
      local fs = spanFontString("")
      fs.parentFrame = CreateFrame("Frame")
      local page = { logical = en, html = en, fs = fs }
      function page:GetText() return self.logical end
      function page:SetText(t)
        self.logical = t
        if t ~= en and not t:find("<HTML", 1, true) then
          fs:SetText(t); self.html = ""
        else
          fs:SetText(""); self.html = t
        end
      end
      function page.GetFont() return fs:GetFont() end
      function page.SetFont(_, ...) return fs:SetFont(...) end
      function page:spanRegion() return self.fs end
      return page, fs
    end

    it("a plain-text Japanese book page takes a cover on the adapter's FontString; English detaches it",
      function()
        local page, fs = pageAdapter("These demon plates are old.")
        R.show("itemtext", "page", page, page:GetText(), "books", "book", "bk1")
        assert.are.equal("この悪魔の鎧は古い。", fs:GetText())
        local cover = coverOf(fs)
        assert.is_table(cover)
        assert.is_true(cover:IsShown())
        assert.are.equal(2, #cover.spans)
        assert.are.equal("あくま", cover.spans[1].reading)
        Stub.keys.alt = true; WFJ.Modifier.refresh()
        assert.are.equal("These demon plates are old.", page.html)
        assert.is_false(cover:IsShown())
        Stub.keys.alt = false; WFJ.Modifier.refresh()
        assert.is_true(cover:IsShown())
      end)

    it("an HTML book page, a page without words and the setting off take no cover", function()
      local page, fs = pageAdapter("<HTML><BODY><P>Demon plates</P></BODY></HTML>")
      R.show("itemtext", "page", page, page:GetText(), "books", "book", "bk2")
      assert.is_nil(coverOf(fs))
      local page3, fs3 = pageAdapter("No words here.")
      R.show("itemtext", "page3", page3, page3:GetText(), "books", "book", "bk3")
      assert.is_nil(coverOf(fs3))
      assert.are.equal(0, V.attached)
      S.set("readings.enabled", false)
      local page4, fs4 = pageAdapter("These demon plates are old.")
      R.show("itemtext", "page4", page4, page4:GetText(), "books", "book", "bk1")
      local cover = coverOf(fs4)
      assert.is_true(cover == nil or not cover:IsShown())
    end)

    -- ── ADR-041: plain-text labels in every window ──────────────────────────────────────────────
    local function labelFs(parent)
      local fs = spanFontString("Rewards")
      fs.parentFrame = parent or CreateFrame("Frame")
      return fs
    end

    it("a plain-text window label takes readings on any window surface", function()
      for _, surface in ipairs({ "questframe.reward", "character", "mail", "spellbook.static" }) do
        local fs = labelFs()
        R.show(surface, "ui.rewardsHeader", fs, "Rewards", "ui", "ui", "QUEST_REWARDS")
        assert.are.equal("報酬", fs:GetText(), surface)
        assert.is_table(coverOf(fs), surface)
        assert.is_true(coverOf(fs):IsShown(), surface)
      end
    end)

    it("a label in a button, a tooltip, a protected frame or on a non-window surface gets none", function()
      local button = CreateFrame("Frame")
      function button.IsObjectType(_, t) return t == "Button" end
      local secure = CreateFrame("Frame")
      function secure.IsProtected() return true, true end
      local refused = {
        { "character", labelFs(button) }, { "character", labelFs(secure) }, { "help", labelFs() },
        { "tracker", labelFs() }, { "hudlabels", labelFs() }, { "alerts.loot", labelFs() },
        { "friends.tooltip", labelFs() }, { "tooltip.unit", labelFs() },
        -- GameTooltip lines under names without "tooltip", and the tracker's headers
        { "deathrecap.tip", labelFs() }, { "quickjoin.tip", labelFs() },
        { "communities.benefits.rewardtip", labelFs() },
        { "auctionhouse.token", labelFs() }, { "questmap.trackerlabels", labelFs() }, { "gamepad", labelFs() },
      }
      for i, r in ipairs(refused) do
        R.show(r[1], "ui." .. i, r[2], "Rewards", "ui", "ui", "QUEST_REWARDS")
        assert.are.equal("報酬", r[2]:GetText(), r[1]) -- the label is still translated
        assert.is_nil(coverOf(r[2]), r[1] .. " " .. i)
      end
      -- a Button's text reaches Render as an adapter without the span call
      local adapter = Stub.fontString("Rewards")
      R.show("character", "ui.button", adapter, "Rewards", "ui", "ui", "QUEST_REWARDS")
      assert.is_nil(coverOf(adapter))
      assert.are.equal(0, V.attached)
    end)

    it("a label holding only a class word, with no word list of its own, gets no cover", function()
      WFJ.Placeholders = { CLASS = { DRUID = "ドルイド" }, RACE = {} }
      assert.are.equal(1, #WFJ.Readings.withTokenWords({}, "ドルイドの道")) -- prose would get the class card
      local fs = spanFontString("Path of the Druid")
      fs.parentFrame = CreateFrame("Frame")
      R.show("character", "ui.class", fs, "Path of the Druid", "ui", "ui", "CLASS_LABEL")
      assert.are.equal("ドルイドの道", fs:GetText())
      assert.is_nil(coverOf(fs))
      -- with a word list of its own the label takes a cover, and still only its own words
      WFJ.Data.reading["ui:CLASS_LABEL"] = { text = "道=みち" }
      local fs2 = spanFontString("Path of the Druid")
      fs2.parentFrame = CreateFrame("Frame")
      R.show("character", "ui.class2", fs2, "Path of the Druid", "ui", "ui", "CLASS_LABEL")
      local cover = coverOf(fs2)
      assert.is_table(cover)
      assert.are.equal(1, #cover.spans)
      assert.are.equal("道", cover.spans[1].word)
      WFJ.Placeholders = nil
    end)

    it("a label with no word list gets no cover; prose surfaces are unchanged", function()
      WFJ.Data.reading["ui:QUEST_REWARDS"] = nil
      local fs = labelFs()
      R.show("character", "ui.x", fs, "Rewards", "ui", "ui", "QUEST_REWARDS")
      assert.is_nil(coverOf(fs))
      local q = questFs()
      R.show("questframe.detail", "description", q, q:GetText(), "quests", "quest.description", 456)
      assert.is_true(coverOf(q):IsShown())
    end)

    it("nonWindow matches a listed surface and every surface under it, and any tooltip", function()
      assert.is_true(V.nonWindow("tracker")); assert.is_true(V.nonWindow("alerts.achievement"))
      assert.is_true(V.nonWindow("questmap.trackerobjectives")); assert.is_true(V.nonWindow("settingspanel.tooltip"))
      assert.is_false(V.nonWindow("questmap.list")); assert.is_false(V.nonWindow("questframe.reward"))
      assert.is_false(V.nonWindow("character.static")); assert.is_true(V.nonWindow(nil))
      assert.is_true(V.nonWindow("help.xpbar")); assert.is_false(V.nonWindow("helpframe"))
      V.tooltipSurface("recruitafriend.activity")
      assert.is_true(V.nonWindow("recruitafriend.activity")); assert.is_false(V.nonWindow("recruitafriend"))
    end)

    it("the gossip greeting row takes readings; a line with no readings gets no cover", function()
      local g = spanFontString("Hello")
      g.parentFrame = CreateFrame("Frame")
      R.show("gossip", "greeting", g, "Hello", "gossip", "gossip", "g1")
      assert.is_true(coverOf(g):IsShown())
      local t = questFs()
      R.show("questframe.detail", "title", t, t:GetText(), "quests", "quest.title", 456)
      assert.is_nil(coverOf(t))
    end)

    it("a cover on a widget the client rewrote behind Render does nothing on enter, and hides", function()
      local fs = questFs()
      R.show("questframe.detail", "description", fs, fs:GetText(), "quests", "quest.description", 456)
      local cover = coverOf(fs)
      fs.text = "Some other quest's text"
      cover.scripts.OnEnter(cover)
      assert.is_nil(cover.scripts.OnUpdate)
      assert.are.equal(0, fs.spanCalls)
      assert.is_false(cover:IsShown()) -- a stale cover takes no more mouse motion
    end)

    it("the cover follows its FontString to a new parent (QuestInfo moves them between panes)", function()
      local fs = questFs()
      local detail = fs.parentFrame
      R.show("questframe.detail", "description", fs, fs:GetText(), "quests", "quest.description", 456)
      local cover = coverOf(fs)
      assert.are.equal(detail, cover:GetParent())
      R.release("questframe.detail")
      local map = CreateFrame("Frame")
      fs.parentFrame = map
      R.show("questmap.info", "description", fs, fs:GetText(), "quests", "quest.description", 456)
      assert.are.equal(map, cover:GetParent())
      assert.are.equal(fs, cover.allPoints)
      assert.is_true(cover:IsShown())
    end)

    it("a re-attach under a resting mouse starts hovering again without a new OnEnter", function()
      local fs = questFs()
      R.show("questframe.detail", "description", fs, fs:GetText(), "quests", "quest.description", 456)
      local cover = coverOf(fs)
      cover.mouseOver = true
      R.forget("questframe.detail")
      R.show("questframe.detail", "description", fs, fs:GetText(), "quests", "quest.description", 456)
      assert.is_function(cover.scripts.OnUpdate)
    end)

    it("an error in the reading box is counted and never stops a surface from rendering", function()
      V.attach = function() error("boom") end
      local fs = questFs()
      assert.has_no.errors(function()
        R.show("questframe.detail", "description", fs, fs:GetText(), "quests", "quest.description", 456)
      end)
      assert.are.equal("Reyn", fs:GetText():match("Reyn"))
      assert.are.equal(1, R.readingErrors)
    end)

    it("a refused font waits: the words attach once the font is applied", function()
      Stub.fontSetFails = true
      local fs = questFs()
      R.show("questframe.detail", "description", fs, fs:GetText(), "quests", "quest.description", 456)
      assert.is_nil(coverOf(fs))
      Stub.fontSetFails = false
      R.retryFonts()
      assert.is_true(coverOf(fs):IsShown())
    end)
  end)

  -- ── the setting ──────────────────────────────────────────────────

  describe("the setting", function()
    it("defaults on; off hides every cover at once, on shows them again", function()
      assert.is_true(S.get("readings.enabled"))
      local fs = questFs()
      R.show("questframe.detail", "description", fs, fs:GetText(), "quests", "quest.description", 456)
      S.set("readings.enabled", false)
      assert.is_false(coverOf(fs):IsShown())
      coverOf(fs).scripts.OnEnter(coverOf(fs))
      assert.is_nil(coverOf(fs).scripts.OnUpdate)
      S.set("readings.enabled", true)
      assert.is_true(coverOf(fs):IsShown())
    end)

    it("a saved WFJ_DB from before the setting existed loads with it on", function()
      local saved = { schema = 1, settings = { enabled = true, ["marker.stale"] = false } }
      local db = S.load(saved, 1, {})
      assert.is_true(S.get("readings.enabled"))
      assert.is_false(S.get("marker.stale"))
      assert.is_nil(db.backup)
    end)
  end)

  -- ── the crash guard over the shipped sample ───────────────────────────────────────

  describe("the shipped sample through the crash guard", function()
    it("every generated reading row finds all its words in its line on screen, and no span is refused", function()
      local Loader = require("tests.lua.spec.loader")
      local ns = H.loadChunks({ "Core/Const.lua", "Core/Compat.lua", "Core/Data.lua", "Core/Lookup.lua",
        "Core/Readings.lua", "Core/State.lua", "UI/Font.lua", "UI/Readings.lua" })
      local rows = 0
      for _, f in ipairs(Loader.tocFiles(H.ADDON_DIR .. "/WoWForeverJapanese.toc")) do
        local wanted = f:find("^Data/Reading/") or f:find("^Data/Quest/") or f:find("^Data/Gossip/")
          or f:find("^Data/UI/") or f == "Data/Meta.lua" -- UI rows
          or f:find("^Data/Book/") -- book pages, keyed by their English hash
        if wanted then H.loadChunk(f, nil, ns) end
      end
      local fs = spanFontString("")
      for key, fields in pairs(ns.Data.reading) do
        local type_, id = key:match("^(%a+):(.+)$")
        if type_ == "quest" then id = tonumber(id) end
        for field in pairs(fields) do
          local kind = (type_ == "gossip" or type_ == "ui" or type_ == "book") and type_ or ("quest." .. field)
          local row
          if type_ == "book" then
            row = ns.Lookup.keyed("book", id)
          elseif type_ == "ui" then -- the UI dictionary row { ja, h1, status }; Lookup has no ui slot map
            local r = ns.Data.ui and ns.Data.ui[id]
            row = r and { ja = r[1] } or nil
          else
            row = ns.Lookup.get(kind, id)
          end
          assert.is_table(row, key .. " " .. field)
          -- the line as a player sees it: the addon's tokens filled in
          local text = row.ja:gsub("{name}", "Reyn"):gsub("{class}", "ドルイド"):gsub("{race}", "ナイトエルフ")
          fs.text = text
          local words = ns.Readings.words(kind, id)
          local spans = ns.Readings.locate(words, text)
          assert.are.equal(#words / 3, #spans, key .. " " .. field) -- word, reading, meaning number
          for _, sp in ipairs(spans) do
            local RV = ns.ReadingView
            assert.has_no.errors(function() assert.is_table((RV.spanAreas(fs, text, sp.first, sp.last))) end)
          end
          rows = rows + 1
        end
      end
      -- every shipped reading line, the whole corpus
      assert.are.equal(ns.Data.meta.counts.reading, rows)
      assert.is_true(rows > 27000)
      assert.are.equal(0, ns.ReadingView.refused)
    end)
  end)
end)
