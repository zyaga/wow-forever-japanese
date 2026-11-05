-- Saving the highlighted word (ADR-069): the press / release poll on the word covers, the chat line, the flash, the
-- screenshot, the card's hint, and that the covers never start taking clicks.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = { "Core/Const.lua", "Core/Data.lua", "Core/Readings.lua", "Core/Glosses.lua", "Core/State.lua",
  "Core/Settings.lua", "Core/Modifier.lua", "Core/Translator.lua", "Core/SurfaceState.lua", "Core/Compat.lua",
  "Core/Words.lua", "UI/Font.lua", "UI/ReadingPopup.lua", "UI/Readings.lua", "UI/WordSave.lua",
  "UI/Render.lua", "UI/OptionsText.lua" }

local JA = "少しの生き物たちを狩り、数を減らしてほしい。"
local PACKED = "少し=すこし 生き物=いきもの=7 狩り=かり=8 数=かず"

local function isBoundary(text, i)
  if i == #text + 1 then return true end
  local c = text:byte(i)
  return c ~= nil and (c < 0x80 or c >= 0xC0)
end

local function spanFontString(text)
  local fs = Stub.fontString(text, "F.ttf", 14, "")
  function fs:CalculateScreenAreaFromCharacterSpan(a, b)
    assert(isBoundary(self.text, a) and isBoundary(self.text, b) and b > a, "split span")
    return { { left = a, bottom = 0, width = b - a, height = 14 } }
  end
  function fs:GetParent() return self.parentFrame end
  return fs
end

-- The frame methods UI/Readings and UI/ReadingPopup use that the shared stub does not carry; every mouse-flag call
-- on any frame is recorded, so a test can prove the covers never take clicks.
local function extendFrames(mouseCalls)
  local create = _G.CreateFrame
  _G.CreateFrame = function(...)
    local f = create(...)
    function f:SetAllPoints(target) self.allPoints = target or true end
    function f:GetParent() return self.parent end
    function f:SetParent(p) self.parent = p end
    function f:IsMouseOver() return self.mouseOver == true end
    function f:SetMouseMotionEnabled(v) self.motion = v end
    function f:SetPropagateMouseMotion(v) self.propagate = v end
    function f:SetMouseClickEnabled(...) mouseCalls[#mouseCalls + 1] = { self, "SetMouseClickEnabled", ... } end
    function f:SetPropagateMouseClicks(...) mouseCalls[#mouseCalls + 1] = { self, "SetPropagateMouseClicks", ... } end
    function f:EnableMouse(...) mouseCalls[#mouseCalls + 1] = { self, "EnableMouse", ... } end
    function f:SetFrameStrata(s) self.strata = s end
    function f.SetClampedToScreen() end
    function f:ClearAllPoints() self.point = nil end
    function f:SetShown(v) if v then self:Show() else self:Hide() end end
    function f.GetLeft(x) return x.left or 100 end
    function f.GetBottom(x) return x.bottom or 200 end
    function f.GetEffectiveScale() return 1 end
    local createTexture = f.CreateTexture
    function f:CreateTexture(...)
      local t = createTexture(self, ...)
      function t.SetAllPoints() end
      function t.ClearAllPoints(tx) tx.point = nil end
      function t.SetColorTexture(tx, r, g, b, a) tx.color = { r, g, b, a } end
      function t.Show(tx) tx.shown = true end
      function t.Hide(tx) tx.shown = false end
      return t
    end
    local createFontString = f.CreateFontString
    function f:CreateFontString(...)
      local fs = createFontString(self, ...)
      function fs.GetStringWidth() return 40 end
      function fs.GetStringHeight() return 12 end
      function fs.SetWidth() end
      function fs.SetJustifyH() end
      return fs
    end
    return f
  end
end

describe("Saving a word", function()
  local WFJ, R, S, fs, cover, mouseCalls, timers, shots

  local function coverOf(f)
    for _, fr in ipairs(Stub.frames) do if fr.allPoints == f then return fr end end
    return nil
  end

  -- the mouse over a word of the line (cover origin (100, 200), one area per byte span)
  local function pointAt(word)
    local s = fs:GetText():find(word, 1, true)
    Stub.cursor = { 100 + s + 1, 205 }
  end
  local function frame() cover.scripts.OnUpdate(cover, 0.01) end
  local function click(word, mods)
    mods = mods or {}
    Stub.keys.ctrl, Stub.keys.shift, Stub.meta = mods.ctrl == true, mods.shift == true, mods.meta == true
    pointAt(word); frame()
    Stub.mouse.LeftButton = true; frame()
    if mods.releaseOn then pointAt(mods.releaseOn) end
    Stub.mouse.LeftButton = false; frame()
    Stub.keys.ctrl, Stub.keys.shift, Stub.meta = false, false, false
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    mouseCalls, timers, shots = {}, {}, 0
    extendFrames(mouseCalls)
    _G.UIParent = CreateFrame("Frame", "UIParent")
    _G.GetCursorPosition = function() return Stub.cursor[1], Stub.cursor[2] end
    _G.IsMetaKeyDown = function() return Stub.meta == true end
    _G.IsMacClient = function() return true end
    _G.Screenshot = function() shots = shots + 1 end
    _G.GetCVar = function(name) return name == "screenshotFormat" and "png" or nil end
    _G.date = function(p, t) return os.date("!" .. p, t) end
    _G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
    Stub.cursor, Stub.meta = { 0, 0 }, false
    WFJ = H.loadChunks(FILES)
    WFJ.Compat.init(function(name) return _G[name] end)
    WFJ.Data.add("reading", { ["quest:456"] = { description = PACKED }, ["gossip:g1"] = { text = PACKED } })
    WFJ.Data.add("gloss", { [7] = "生き物\tいきもの\tliving thing", [8] = "狩る\tかる\tto hunt" })
    WFJ.Lookup = { get = function(kind, id)
      if kind == "quest.title" and id == 456 then return { ja = "生き物を減らせ" } end
    end }
    R, S = WFJ.Render, WFJ.Settings
    S.load(nil, 1, {})
    WFJ.Words.load(nil)
    local DATA = { ["quest.description"] = { [456] = { ja = JA, status = "." } },
      gossip = { g1 = { ja = JA, status = "." } } }
    R.init(WFJ.Translator.new({
      enabled = function() return WFJ.State.enabled end,
      areaEnabled = WFJ.State.areaEnabled,
      modifierHeld = WFJ.Modifier.isDown,
      lookup = function(kind, id) return DATA[kind] and DATA[kind][id] end,
      marker = function() return false end,
    }))
    fs = spanFontString("Reduce their number.")
    fs.parentFrame = CreateFrame("Frame")
    R.show("questframe.detail", "description", fs, fs:GetText(), "quests", "quest.description", 456)
    cover = coverOf(fs)
    cover.scripts.OnEnter(cover)
  end)

  after_each(function()
    _G.UIParent, _G.GetCursorPosition, _G.IsMetaKeyDown, _G.IsMacClient = nil, nil, nil, nil
    _G.Screenshot, _G.GetCVar, _G.date, _G.C_Timer = nil, nil, nil, nil
  end)

  it("Ctrl+click saves the highlighted word with its meaning, sentence, source and quest", function()
    click("生き物", { ctrl = true })
    assert.are.equal(1, WFJ.Words.count())
    local e = WFJ.Words.entries()[1]
    assert.are.equal("quest.description:456:生き物", e.key)
    assert.are.equal("いきもの", e.reading)
    assert.are.equal("living thing", e.meaning)
    assert.are.equal(JA, e.sentence)
    assert.are.equal("quest", e.source)
    assert.are.equal(456, e.questId)
    assert.are.equal("生き物を減らせ", e.questTitle)
    assert.is_truthy(Stub.prints[#Stub.prints]:find("生き物", 1, true))
    assert.is_truthy(Stub.prints[#Stub.prints]:find("1", 1, true))
  end)

  it("a word whose dictionary form differs keys on the dictionary form", function()
    click("狩り", { ctrl = true })
    local e = WFJ.Words.entries()[1]
    assert.are.equal("quest.description:456:狩る", e.key)
    assert.are.equal("狩る", e.lemma)
    assert.are.equal("かる", e.lemmaReading)
  end)

  it("each choice needs exactly its own modifier set", function()
    click("生き物", {}) -- plain click while the choice is Ctrl
    click("生き物", { ctrl = true, shift = true })
    click("生き物", { shift = true })
    assert.are.equal(0, WFJ.Words.count())
    S.set("words.saveClick", "shift"); click("生き物", { shift = true })
    assert.are.equal(1, WFJ.Words.count())
    S.set("words.saveClick", "meta"); click("狩り", { meta = true })
    assert.are.equal(2, WFJ.Words.count())
    S.set("words.saveClick", "click"); click("少し", {})
    assert.are.equal(3, WFJ.Words.count())
  end)

  it("off never polls the button; a drag, a release elsewhere or no word saves nothing; one press saves once",
  function()
    S.set("words.saveClick", "off")
    local polled = 0
    local real = _G.IsMouseButtonDown
    _G.IsMouseButtonDown = function(b) polled = polled + 1; return real(b) end
    click("生き物", {})
    assert.are.equal(0, polled)
    _G.IsMouseButtonDown = real
    S.set("words.saveClick", "ctrl")
    -- the button already down when the mouse arrives: the end of a drag
    Stub.keys.ctrl = true
    Stub.mouse.LeftButton = true
    cover.scripts.OnLeave(cover); cover.scripts.OnEnter(cover)
    pointAt("生き物"); frame()
    Stub.mouse.LeftButton = false; frame()
    Stub.keys.ctrl = false
    click("生き物", { ctrl = true, releaseOn = "少し" })
    Stub.cursor = { 100 + #fs:GetText() + 50, 205 } -- off every word
    Stub.keys.ctrl = true
    frame(); Stub.mouse.LeftButton = true; frame(); Stub.mouse.LeftButton = false; frame()
    Stub.keys.ctrl = false
    assert.are.equal(0, WFJ.Words.count())
    pointAt("生き物"); Stub.keys.ctrl = true
    frame(); Stub.mouse.LeftButton = true; frame(); frame(); frame(); Stub.mouse.LeftButton = false; frame(); frame()
    Stub.keys.ctrl = false
    assert.are.equal(1, WFJ.Words.count())
  end)

  it("a press that ends after the cover moved (a frame dragged by its text) saves nothing", function()
    Stub.keys.ctrl = true
    pointAt("生き物"); frame()
    Stub.mouse.LeftButton = true; frame()
    cover.left = 140 -- the voice panel dragged; the word stays under the cursor
    Stub.cursor = { Stub.cursor[1] + 40, Stub.cursor[2] }
    frame()
    Stub.mouse.LeftButton = false; frame()
    Stub.keys.ctrl = false
    assert.are.equal(0, WFJ.Words.count())
  end)

  it("a second save of the same word says so and adds nothing", function()
    click("生き物", { ctrl = true })
    click("生き物", { ctrl = true })
    assert.are.equal(1, WFJ.Words.count())
    assert.are.equal(2, #Stub.prints)
    assert.are_not.equal(Stub.prints[1], Stub.prints[2])
  end)

  it("the tint flashes on a save and settles back", function()
    click("生き物", { ctrl = true })
    local flashed
    for _, t in ipairs(cover.tints) do if t.shown and t.color and t.color[4] > 0.22 then flashed = t end end
    assert.is_table(flashed)
    assert.are.equal(1, #timers)
    timers[1]()
    assert.are.equal(0.22, flashed.color[4])
  end)

  it("the covers never take clicks, whatever the setting", function()
    for _, v in ipairs({ "ctrl", "click", "off", "shift" }) do
      S.set("words.saveClick", v)
      click("生き物", { ctrl = true })
    end
    assert.are.same({}, mouseCalls)
  end)

  it("a quest-window line keyed by its English is a quest source with no quest id", function()
    local fs2 = spanFontString("Reduce.")
    fs2.parentFrame = CreateFrame("Frame")
    R.show("questframe.progress", "progress", fs2, fs2:GetText(), "quests", "gossip", "g1")
    fs, cover = fs2, coverOf(fs2)
    cover.scripts.OnEnter(cover)
    click("数", { ctrl = true })
    local e = WFJ.Words.entries()[1]
    assert.are.equal("gossip:g1:数", e.key)
    assert.are.equal("quest", e.source)
    assert.is_nil(e.questId)
  end)

  describe("screenshot", function()
    it("off: no screenshot", function()
      click("生き物", { ctrl = true })
      assert.are.equal(0, shots)
      assert.is_nil(WFJ.Words.entries()[1].shot)
    end)

    it("on: the card hides, the tint stays, the shot is named on success and the line prints after", function()
      S.set("words.screenshot", true)
      click("生き物", { ctrl = true })
      assert.are.equal(1, shots)
      local card = WFJ.ReadingPopup.frame()
      assert.is_false(card:IsShown())
      local tinted = false
      for _, t in ipairs(cover.tints) do if t.shown then tinted = true end end
      assert.is_true(tinted)
      assert.are.equal(0, #Stub.prints)
      Stub.fireAll("SCREENSHOT_SUCCEEDED")
      assert.are.equal("WoWScrnShot_" .. os.date("!%m%d%y_%H%M%S", 1790000000) .. ".png",
        WFJ.Words.entries()[1].shot)
      assert.are.equal(1, #Stub.prints)
      assert.is_true(card:IsShown())
    end)

    it("the shot is named after the capture's time, not the event's", function()
      S.set("words.screenshot", true)
      local now = 1790000000
      _G.time = function() return now end
      click("生き物", { ctrl = true })
      now = now + 2
      Stub.fireAll("SCREENSHOT_SUCCEEDED")
      assert.are.equal("WoWScrnShot_" .. os.date("!%m%d%y_%H%M%S", 1790000000) .. ".png",
        WFJ.Words.entries()[1].shot)
    end)

    it("a save while a screenshot is pending takes none and prints at once; the first keeps its shot", function()
      S.set("words.screenshot", true)
      click("生き物", { ctrl = true })
      click("狩り", { ctrl = true })
      assert.are.equal(1, shots)
      assert.are.equal(1, #Stub.prints)
      Stub.fireAll("SCREENSHOT_SUCCEEDED")
      local e = WFJ.Words.entries()
      assert.is_string(e[1].shot)
      assert.is_nil(e[2].shot)
      assert.are.equal(2, #Stub.prints)
    end)

    it("a client without Screenshot saves and prints at once", function()
      S.set("words.screenshot", true)
      _G.Screenshot = nil
      click("生き物", { ctrl = true })
      assert.are.equal(1, #Stub.prints)
      assert.is_true(WFJ.ReadingPopup.frame():IsShown())
    end)

    it("no answer from the client within 5 seconds ends the wait: the card comes back and the line prints", function()
      S.set("words.screenshot", true)
      click("生き物", { ctrl = true })
      assert.are.equal(0, #Stub.prints)
      timers[#timers]() -- the wait's timer (the flash's came first)
      assert.are.equal(1, #Stub.prints)
      assert.is_true(WFJ.ReadingPopup.frame():IsShown())
      click("狩り", { ctrl = true })
      assert.are.equal(2, shots) -- the next save takes its screenshot again
    end)

    it("a failed screenshot leaves no name and still prints the line", function()
      S.set("words.screenshot", true)
      click("生き物", { ctrl = true })
      Stub.fireAll("SCREENSHOT_FAILED")
      assert.is_nil(WFJ.Words.entries()[1].shot)
      assert.are.equal(1, #Stub.prints)
    end)
  end)

  describe("the card's hint", function()
    local function hintShown()
      for _, c in ipairs(WFJ.ReadingPopup.frame().children) do
        if c.GetText and c:GetText() and c:GetText():find("単語を保存", 1, true) and c:IsShown() then return c end
      end
      return nil
    end

    it("shows the save click until the first save ever, and never while it is off", function()
      pointAt("生き物"); frame()
      local hint = hintShown()
      assert.is_table(hint)
      assert.is_truthy(hint:GetText():find("Ctrl+click", 1, true))
      click("生き物", { ctrl = true })
      WFJ.Words.clear()
      cover.scripts.OnLeave(cover); cover.scripts.OnEnter(cover)
      pointAt("狩り"); frame()
      assert.is_nil(hintShown())
      WFJ.Words.load(nil)
      S.set("words.saveClick", "off")
      cover.scripts.OnLeave(cover); cover.scripts.OnEnter(cover)
      pointAt("狩り"); frame()
      assert.is_nil(hintShown())
      S.set("words.saveClick", "shift")
      cover.scripts.OnLeave(cover); cover.scripts.OnEnter(cover)
      pointAt("生き物"); frame()
      assert.is_truthy(hintShown():GetText():find("Shift+click", 1, true))
    end)
  end)
end)
