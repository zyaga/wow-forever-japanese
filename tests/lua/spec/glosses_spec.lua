-- The word popup (ADR-039): the read path, the card, the reading-only fallback, the setting and /wfj glosses.
-- Meanings are written by the model per sentence (no dictionary ships).
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local Loader = require("tests.lua.spec.loader")

local FILES = { "Core/Const.lua", "Core/Data.lua", "Core/Readings.lua", "Core/Glosses.lua", "Core/Placeholders.lua",
  "Core/State.lua",
  "Core/Settings.lua", "Core/Modifier.lua", "Core/Translator.lua", "Core/SurfaceState.lua", "Core/Compat.lua",
  "UI/Font.lua", "UI/ReadingPopup.lua", "UI/Readings.lua", "UI/Render.lua" }

local JA = "私は倒して少しの数を減らしてほしい。ここにいる。"
-- word=reading[=meaning number]: 少し carries none; いる is a kana word (listed for the card only)
local PACKED = "私=わたし=2 倒して=たおして=1 少し=すこし いる=いる=3"
local GLOSS = { [1] = "倒す\tたおす\tdefeat", [2] = "私\tわたし\tI", [3] = "いる\tいる\tto be (here)" }

local function isBoundary(text, i)
  if i == #text + 1 then return true end
  local c = text:byte(i)
  return c ~= nil and (c < 0x80 or c >= 0xC0)
end

local function spanFontString(text)
  local fs = Stub.fontString(text, "F.ttf", 14, "")
  function fs:CalculateScreenAreaFromCharacterSpan(a, b)
    if not isBoundary(self.text, a) or not isBoundary(self.text, b) or b <= a then error("CRASH") end
    return { { left = a, bottom = 0, width = b - a, height = 14 } }
  end
  function fs:GetParent() return self.parentFrame end
  return fs
end

-- The frame methods UI/Readings and UI/ReadingPopup use that the shared stub does not carry.
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
    function f:SetClampedToScreen(v) self.clamped = v end
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
      function fs.ClearAllPoints(x) x.point = nil end
      function fs.Show(x) x.shown = true end
      function fs.Hide(x) x.shown = false end
      return fs
    end
    return f
  end
end

describe("Glosses", function()
  local WFJ, R, S

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    extendFrames()
    _G.UIParent = CreateFrame("Frame", "UIParent")
    _G.GetCursorPosition = function() return Stub.cursor[1], Stub.cursor[2] end
    Stub.cursor = { 0, 0 }
    WFJ = H.loadChunks(FILES)
    WFJ.Compat.init(function(name) return _G[name] end)
    WFJ.Data.add("reading", { ["quest:456"] = { description = PACKED } })
    WFJ.Data.add("gloss", GLOSS)
    R, S = WFJ.Render, WFJ.Settings
    S.load(nil, 1, {})
    local DATA = { ["quest.description"] = { [456] = { ja = JA, status = "." },
      [999] = { ja = "若きドルイドよ", status = "." } } }
    R.init(WFJ.Translator.new({
      enabled = function() return WFJ.State.enabled end,
      areaEnabled = WFJ.State.areaEnabled,
      modifierHeld = WFJ.Modifier.isDown,
      lookup = function(kind, id) return DATA[kind] and DATA[kind][id] end,
      marker = function() return false end,
    }))
  end)

  after_each(function() _G.UIParent, _G.GetCursorPosition = nil, nil end)

  local function hover(word)
    local fs = spanFontString("Greetings.")
    fs.parentFrame = CreateFrame("Frame")
    R.show("questframe.detail", "description", fs, fs:GetText(), "quests", "quest.description", 456)
    local cover
    for _, f in ipairs(Stub.frames) do if f.allPoints == fs then cover = f end end
    local s = JA:find(word, 1, true)
    Stub.cursor = { 100 + s + 1, 205 }
    cover.scripts.OnEnter(cover)
    cover.scripts.OnUpdate(cover, 0.01)
    return cover, s
  end

  -- the TOOLTIP-strata frame that is showing: the card (WIDTH wide) or the reading-only box
  local function shown()
    local card, box
    for _, f in ipairs(Stub.frames) do
      if f.strata == "TOOLTIP" and f:IsShown() then
        if f.clamped then card = f else box = f end
      end
    end
    return card, box
  end

  local function texts(frame)
    local out = {}
    for _, c in ipairs(frame.children) do
      if c.GetText and c.shown ~= false then out[#out + 1] = c:GetText() end
    end
    return out
  end

  -- ── the read path ──────────────────────────────────────────────

  it("get parses a meaning row into dictionary form, its reading and the meaning; nil otherwise", function()
    assert.are.same({ lemma = "倒す", lemmaReading = "たおす", meaning = "defeat" }, WFJ.Glosses.get(1))
    assert.is_nil(WFJ.Glosses.get(99))
    assert.is_nil(WFJ.Glosses.get(false))
    assert.is_nil(WFJ.Glosses.get("1"))
  end)

  it("Readings.locate spans carry the word and its meaning number (the fields before are unchanged)", function()
    local spans = WFJ.Readings.lookup("quest.description", 456, JA)
    assert.are.equal("倒して", spans[2].word)
    assert.are.equal("たおして", spans[2].reading)
    assert.are.equal(1, spans[2].gloss)
    assert.is_nil(spans[3].gloss) -- 少し carries no meaning
    local s, e = JA:find("倒して", 1, true)
    assert.are.same({ s, e }, { spans[2].first, spans[2].last })
  end)

  -- ── the card ──────────────────────────────────────────────────

  it("an inflected word shows word + reading, its dictionary form, then its meaning here", function()
    local cover, s = hover("倒して")
    local card, box = shown()
    assert.is_table(card)
    assert.is_nil(box)
    local t = texts(card)
    assert.are.equal("倒して", t[1])
    assert.are.equal("たおして", t[2])
    -- laid out like the head line (word, then reading) in its own colours
    assert.are.equal("|cffbfd4f2倒す|r　|cffc9a65aたおす|r", t[3])
    assert.are.equal("defeat", t[4])
    assert.are.equal(WFJ.ReadingPopup.WIDTH, card.size[1])
    assert.are.equal(280, WFJ.ReadingPopup.WIDTH)
    assert.is_true(card.clamped)
    -- anchored like the reading box: bottom-centre above the word's first rectangle
    local e = s + #"倒して" - 1
    assert.are.same({ "BOTTOM", cover, "BOTTOMLEFT", s + (e + 1 - s) / 2, 14 + 2 }, card.point)
    cover.scripts.OnLeave(cover)
    assert.is_nil((shown()))
  end)

  it("a word already in dictionary form gets no dictionary-form line", function()
    local _, _, lemma, meaning = WFJ.ReadingPopup.lines({ word = "私", reading = "わたし" }, WFJ.Glosses.get(2))
    assert.is_nil(lemma)
    assert.are.equal("I", meaning)
  end)

  it("a kana word with a meaning shows the card", function()
    hover("いる")
    local card = shown()
    assert.are.same({ "いる", "", "to be (here)" }, texts(card)) -- a kana word is shown once
  end)

  it("a kana word's card shows the word once (it is its own reading)", function()
    local head, reading = WFJ.ReadingPopup.lines({ word = "いる", reading = "いる" }, WFJ.Glosses.get(3))
    assert.are.same({ "いる", "" }, { head, reading })
  end)

  it("class and race words the addon fills in get a card with the English name", function()
    local text = "若きドルイドよ、ナイトエルフの町へ。私は倒して。"
    local spans = WFJ.Readings.withTokenWords(WFJ.Readings.lookup("quest.description", 456, text) or {}, text)
    local byWord = {}
    for _, sp in ipairs(spans) do byWord[sp.word] = sp end
    assert.are.same({ lemma = "ドルイド", lemmaReading = "ドルイド", meaning = "Druid (a class)" }, byWord["ドルイド"].card)
    assert.are.equal("Night Elf (a race)", byWord["ナイトエルフ"].card.meaning)
    for i = 2, #spans do assert.is_true(spans[i - 1].first < spans[i].first) end -- text order
    -- a listed word that covers the spot wins: no second span over it
    local over = WFJ.Readings.withTokenWords({ { first = 1, last = #"ドルイドたち", word = "ドルイドたち" } }, "ドルイドたち")
    assert.are.equal(1, #over)
    assert.are.same({}, WFJ.Readings.withTokenWords({}, "森"))
  end)

  it("a class or race word inside a longer katakana word gets no card", function()
    for _, text in ipairs({ "コントロールする", "パトロール隊", "オークションへ", "プロローグ", "ドルイドー" }) do
      assert.are.same({}, WFJ.Readings.withTokenWords({}, text), text)
    end
    assert.are.equal(1, #WFJ.Readings.withTokenWords({}, "トロールの村")) -- a kanji or kana particle next to it is fine
    assert.are.same({}, WFJ.Readings.withTokenWords({}, "人間の町")) -- 人間 is the common noun "person" in prose
  end)

  it("a listed word never anchors inside a filled-in class or race word", function()
    -- gossip fde1d7c619c766f6: 「…失われた、{race}。エルフの師匠たち…」 with {race} = ナイトエルフ
    local text = "それらは失われた、ナイトエルフ。エルフの師匠たち"
    local words = { "失われた", "うしなわれた", false, "エルフ", "エルフ", false, "師匠たち", "ししょうたち", false }
    local guards = WFJ.Readings.tokenSpans(text)
    assert.are.equal(1, #guards)
    local spans = WFJ.Readings.locate(words, text, guards)
    assert.are.equal(3, #spans)
    local s = text:find("。エルフ", 1, true) + #"。"
    assert.are.same({ s, s + #"エルフ" - 1 }, { spans[2].first, spans[2].last }) -- the prose エルフ, not the race word
    -- without guards the first match wins
    assert.are.equal(text:find("エルフ", 1, true), WFJ.Readings.locate(words, text)[2].first)
    -- a listed word equal to the filled word is kept where it stands
    local own = WFJ.Readings.locate({ "ナイトエルフ", "ナイトエルフ", false }, "ナイトエルフの町", WFJ.Readings.tokenSpans("ナイトエルフの町"))
    assert.are.same({ 1, #"ナイトエルフ" }, { own[1].first, own[1].last })
    -- a word running across the filled word's edge is passed over too
    local forest = "ナイトエルフの森、エルフの町"
    local across = WFJ.Readings.locate({ "エルフの", "エルフの", false }, forest, WFJ.Readings.tokenSpans(forest))
    assert.are.equal(forest:find("、エルフの", 1, true) + #"、", across[1].first)
    -- a word holding the class word whole (ウォリアーたち) is kept
    local held = "ウォリアーたちの霊"
    local kept = WFJ.Readings.locate({ "ウォリアーたち", "ウォリアーたち", false }, held, WFJ.Readings.tokenSpans(held))
    assert.are.equal(1, kept[1].first)
    -- a line with no class or race word: no guard, the same spans as without guards
    assert.are.same({}, WFJ.Readings.tokenSpans(JA))
    assert.are.same(WFJ.Readings.locate(WFJ.Readings.words("quest.description", 456), JA),
      WFJ.Readings.lookup("quest.description", 456, JA))
  end)

  it("a head line wider than the card widens it", function()
    local cover = hover("倒して")
    local card = shown()
    assert.are.equal(280, card.size[1]) -- the stub measures every string at 40 px: fits
    cover.scripts.OnLeave(cover)
    -- a long head: the word FontString (the card's first) now measures 400 px → 10 + 400 + 8 + 40 + 10 (10 px
    -- inside the tooltip border)
    for _, c in ipairs(card.children) do
      if c.GetText and c:GetText() == "倒して" then c.GetStringWidth = function() return 400 end end
    end
    hover("倒して")
    assert.are.equal(468, shown().size[1])
  end)

  it("a line with no reading row still gets a card on its class word", function()
    local fs = spanFontString("Greetings.")
    fs.parentFrame = CreateFrame("Frame")
    R.show("questframe.detail", "description", fs, fs:GetText(), "quests", "quest.description", 999)
    local cover
    for _, f in ipairs(Stub.frames) do if f.allPoints == fs then cover = f end end
    assert.is_table(cover)
    local s = ("若きドルイドよ"):find("ドルイド", 1, true)
    Stub.cursor = { 100 + s + 1, 205 }
    cover.scripts.OnEnter(cover)
    cover.scripts.OnUpdate(cover, 0.01)
    local card = shown()
    assert.are.same({ "ドルイド", "", "Druid (a class)" }, texts(card))
  end)

  it("a kana word is no hover target once meanings are off", function()
    S.set("readings.glosses", false)
    hover("いる")
    local card, box = shown()
    assert.is_nil(card)
    assert.is_nil(box)
  end)

  -- ── the fallback ──────────────────────────────────────────────

  it("a word with no gloss shows exactly the reading-only box", function()
    hover("少し")
    local card, box = shown()
    assert.is_nil(card)
    assert.is_table(box)
    assert.are.same({ "すこし" }, texts(box))
  end)

  it("with readings.glosses off a glossed word shows the reading-only box; on again, the card", function()
    assert.is_true(S.get("readings.glosses")) -- default on
    S.set("readings.glosses", false)
    local cover = hover("倒して")
    local card, box = shown()
    assert.is_nil(card)
    assert.are.same({ "たおして" }, texts(box))
    cover.scripts.OnLeave(cover)
    S.set("readings.glosses", true)
    hover("倒して")
    card = shown()
    assert.is_table(card)
  end)

  it("turning meanings off while the mouse rests on the text drops kana words at once", function()
    local cover = hover("倒して")
    local s = JA:find("いる", 1, true)
    S.set("readings.glosses", false)
    Stub.cursor = { 100 + s + 1, 205 }
    cover.scripts.OnUpdate(cover, 0.01) -- no new OnEnter: the mouse never left
    local card, box = shown()
    assert.is_nil(card)
    assert.is_nil(box) -- いる is no hover target now, not a box holding いる
  end)

  it("turning glosses off closes a card that is open", function()
    hover("倒して")
    assert.is_table((shown()))
    S.set("readings.glosses", false)
    assert.is_nil((shown()))
  end)

  it("readings.enabled off still hides everything", function()
    S.set("readings.enabled", false)
    local fs = spanFontString("Greetings.")
    fs.parentFrame = CreateFrame("Frame")
    R.show("questframe.detail", "description", fs, fs:GetText(), "quests", "quest.description", 456)
    for _, f in ipairs(Stub.frames) do
      if f.allPoints == fs then assert.is_false(f:IsShown()) end
    end
  end)
end)

describe("/wfj glosses", function()
  local WFJ, S
  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI(); Stub.installGossipAPI()
    WFJ = Loader.load("WoWForeverJapanese")
    Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese")
    S = WFJ.Settings
    Stub.prints = {}
  end)

  it("sets readings.glosses and prints the state with how many words have a meaning", function()
    SlashCmdList.WFJ("glosses off")
    assert.is_false(S.get("readings.glosses"))
    assert.is_truthy(Stub.prints[#Stub.prints]:find("glosses off · %d+ meanings loaded"))
    SlashCmdList.WFJ("glosses on")
    assert.is_true(S.get("readings.glosses"))
    SlashCmdList.WFJ("glosses")
    local line = Stub.prints[#Stub.prints]
    assert.is_truthy(line:find("glosses on", 1, true))
    local n = tonumber(line:match("(%d+) meanings"))
    assert.is_true(n > 0 and n == WFJ.Data.count("gloss")) -- the shipped Data/Gloss files loaded in TOC order
    SlashCmdList.WFJ("glosses maybe")
    assert.is_truthy(Stub.prints[#Stub.prints]:find("expected on|off", 1, true))
    assert.is_true(S.get("readings.glosses"))
  end)
end)
