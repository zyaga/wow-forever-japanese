-- The word status marks on a word-card cover (UI/WordMarks): the underline and the highlight drawn under the
-- words, where the underline sits, the score tag, the status clicks, the card's status line, and the switches.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = { "Core/Const.lua", "Core/Data.lua", "Core/Readings.lua", "Core/Glosses.lua", "Core/State.lua",
  "Core/Settings.lua", "Core/Modifier.lua", "Core/Translator.lua", "Core/SurfaceState.lua", "Core/Compat.lua",
  "Core/Words.lua", "Core/WordFrequency.lua", "Core/WordStatus.lua", "Core/WordScore.lua", "Core/WordMarks.lua",
  "UI/Font.lua", "UI/ReadingPopup.lua", "UI/Readings.lua", "UI/WordSave.lua", "UI/WordMarks.lua",
  "UI/Render.lua", "UI/OptionsText.lua", "UI/OptionsWidgets.lua" }

local JA = "少しの生き物たちを狩り、数を減らしてほしい。"
local PACKED = "少し=すこし 生き物=いきもの=7 狩り=かり=8 数=かず"
local RED, BLUE, GREEN = { 0.95, 0.25, 0.25, 0.9 }, { 0.1, 0.4, 1, 1 }, { 0.2, 0.9, 0.3, 0.2 }

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

local function extendFrames()
  local create = _G.CreateFrame
  _G.CreateFrame = function(...)
    local f = create(...)
    function f:SetAllPoints(target) self.allPoints = target or true end
    function f:GetParent() return self.parent end
    function f:SetParent(p) self.parent = p end
    function f:IsMouseOver() return self.mouseOver == true end
    function f.SetMouseMotionEnabled() end
    function f.SetPropagateMouseMotion() end
    function f.SetMouseClickEnabled() end
    function f.SetPropagateMouseClicks() end
    function f.SetFrameStrata() end
    function f.SetClampedToScreen() end
    function f:ClearAllPoints() self.point = nil end
    function f:SetShown(v) if v then self:Show() else self:Hide() end end
    function f.GetLeft() return 100 end
    function f.GetBottom() return 200 end
    function f.GetEffectiveScale() return 1 end
    local createFontString = f.CreateFontString
    function f:CreateFontString(...)
      local fs = createFontString(self, ...)
      function fs.GetStringWidth() return 40 end
      function fs.GetStringHeight() return 12 end
      function fs.SetWidth() end
      function fs.SetJustifyH() end
      function fs.SetTextColor(text, r, g, b) text.color = { r, g, b } end
      return fs
    end
    return f
  end
end

local function same(a, b)
  for i = 1, 4 do if math.abs((a[i] or -1) - b[i]) > 1e-6 then return false end end
  return true
end

describe("Word status marks on a cover", function()
  local WFJ, R, S, Status, Marks, fs, cover, timers

  -- A cover is a table that holds its frame (the frame carries no field): the tests read both through one view,
  -- the cover's state first, then its frame.
  local function coverOf(f)
    for _, fr in ipairs(Stub.frames) do
      if fr.allPoints == f then
        local state = WFJ.ReadingView.coverAt(f)
        return setmetatable({ frame = fr }, { __index = function(_, k)
          local v = state and state[k]
          if v ~= nil then return v end
          return fr[k]
        end, __newindex = function(_, k, v)
          if state then state[k] = v else fr[k] = v end
        end })
      end
    end
    return nil
  end
  local function settle()
    local run = timers
    timers = {}
    for _, fn in ipairs(run) do fn() end
  end
  -- the marks now shown on the cover, by colour
  local function shown(color)
    local out = {}
    for _, t in ipairs(cover.markTex or {}) do
      if t.shown ~= false and same(t.color, color) then out[#out + 1] = t end
    end
    return out
  end
  local function tag()
    local fsTag = cover.scoreFs
    return fsTag and fsTag.shown ~= false and fsTag:GetText() or nil
  end
  local function pointAt(word)
    local s = fs:GetText():find(word, 1, true)
    Stub.cursor = { 100 + s + 1, 205 }
  end
  local function frame() cover.scripts.OnUpdate(cover, 0.01) end
  local function click(word, button, mods)
    mods = mods or { shift = true }
    Stub.keys.ctrl, Stub.keys.shift = mods.ctrl == true, mods.shift == true
    pointAt(word); frame()
    Stub.mouse[button] = true; frame()
    Stub.mouse[button] = false; frame()
    Stub.keys.ctrl, Stub.keys.shift = false, false
  end
  local function card()
    pointAt("生き物"); frame()
    return WFJ.ReadingPopup.frame().children
  end
  local function hintText()
    card()
    for _, child in ipairs(WFJ.ReadingPopup.frame().children) do
      local text = child.GetText and child:GetText()
      if type(text) == "string" and text:find("#", 1, true) then return text end
    end
    return nil
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    timers = {}
    extendFrames()
    _G.UIParent = CreateFrame("Frame", "UIParent")
    _G.GetCursorPosition = function() return Stub.cursor[1], Stub.cursor[2] end
    _G.IsMetaKeyDown = function() return false end
    _G.IsMacClient = function() return true end
    _G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
    Stub.cursor = { 0, 0 }
    WFJ = H.loadChunks(FILES)
    WFJ.Compat.init(function(name) return _G[name] end)
    WFJ.Placeholders = { CLASS = {}, RACE = {} }
    WFJ.Data.add("reading", { ["quest:456"] = { description = PACKED, progress = "数=かず 生き物=いきもの=7" },
      ["quest:9"] = { description = "数=かず" } })
    WFJ.Data.add("gloss", { [7] = "生き物\tいきもの\tliving thing", [8] = "狩る\tかる\tto hunt" })
    WFJ.Data.add("freqJa", { ["生き物\tいきもの"] = "9,0,0,0,0,0", ["狩る\tかる"] = "5,0,0,0,0,0",
      ["少し\tすこし"] = "3,0,0,0,0,0", ["数\tかず"] = "2,0,0,0,0,0" })
    WFJ.Data.add("freqEn", { reduce = "4,0,0,0,0,0", number = "2,0,0,0,0,0" })
    WFJ.Data.add("english", { ["quest:456"] = { description = "number=4 reduce=3" } })
    WFJ.Lookup = { get = function() return nil end }
    R, S, Status, Marks = WFJ.Render, WFJ.Settings, WFJ.WordStatus, WFJ.WordMarks
    S.load(nil, 1, {})
    WFJ.Words.load(nil)
    Status.load(nil)
    Status.LEARN_NEXT = 1 -- 生き物, the most used
    local DATA = { ["quest.description"] = { [456] = { ja = JA, status = "." }, [9] = { ja = "数", status = "." } } }
    R.init(WFJ.Translator.new({
      enabled = function() return WFJ.State.enabled end,
      areaEnabled = WFJ.State.areaEnabled,
      showsEnglish = WFJ.Modifier.english,
      lookup = function(kind, id) return DATA[kind] and DATA[kind][id] end,
      marker = function() return false end,
    }))
    fs = spanFontString("Reduce their number.")
    fs.parentFrame = CreateFrame("Frame")
    R.show("questframe.detail", "description", fs, fs:GetText(), "quests", "quest.description", 456)
    cover = coverOf(fs)
    settle()
  end)

  after_each(function()
    _G.UIParent, _G.GetCursorPosition, _G.IsMetaKeyDown, _G.IsMacClient, _G.C_Timer = nil, nil, nil, nil, nil
  end)

  it("underlines every unknown word in red and highlights the one to learn next", function()
    assert.are.equal(4, #shown(RED))
    assert.are.equal(0, #shown(BLUE))
    local green = shown(GREEN)
    assert.are.equal(1, #green)
    local first = JA:find("生き物", 1, true)
    assert.are.equal(first, green[1].point[4]) -- behind 生き物
  end)

  it("draws a learning word blue and a known or ignored word with nothing", function()
    Status.set("ja", "生き物\tいきもの", "learning")
    Status.set("ja", "狩る\tかる", "known")
    Status.set("ja", "数\tかず", "ignored")
    settle()
    assert.are.equal(1, #shown(RED)) -- 少し
    assert.are.equal(1, #shown(BLUE))
    assert.are.equal(1, #shown(GREEN)) -- 少し is now the most used unknown word
  end)

  it("puts the underline in the middle of the gap between text lines, never over the line below", function()
    local function words(gap)
      return { { rects = { { left = 0, bottom = 20 + gap, width = 10, height = 14 } } },
        { rects = { { left = 0, bottom = 6, width = 10, height = 14 } } } }
    end
    for _, gap in ipairs({ 1, 2, 3, 4, 6, 10 }) do
      assert.are.equal(gap, Marks.gap(words(gap)))
      local drop, thick = Marks.line(gap)
      assert.is_true(drop <= gap, "over the line below at gap " .. gap)
      assert.is_true(drop - thick >= 0, "inside the word's own box at gap " .. gap)
      assert.are.equal(gap >= 4 and 1.5 or 1, thick)
    end
    -- a single line has nothing below it to measure against: the roomy default
    assert.are.equal(4, Marks.gap({ { rects = { { left = 0, bottom = 6, width = 10, height = 14 } } } }))
    -- lines that touch leave no gap: the line sits straight under the box
    assert.are.same({ 1, 1 }, { Marks.line(0) })
  end)

  it("draws the highlight by the mode the setting picks", function()
    S.set("marks.highlight", "off"); settle()
    assert.are.equal(0, #shown(GREEN))
    assert.are.equal(4, #shown(RED))
    S.set("marks.highlight", "new"); settle()
    assert.are.equal(0, #shown(GREEN)) -- four unknown words in the one sentence
    Status.set("ja", "少し\tすこし", "known")
    Status.set("ja", "狩る\tかる", "known")
    Status.set("ja", "数\tかず", "known")
    settle()
    assert.are.equal(1, #shown(GREEN))
    S.set("marks.highlight", "commonNew"); settle()
    assert.are.equal(1, #shown(GREEN))
  end)

  it("draws no underline with the underline setting off, and nothing at all with the place off", function()
    S.set("marks.underline", false); settle()
    assert.are.equal(0, #shown(RED))
    assert.are.equal(1, #shown(GREEN))
    S.set("marks.underline", true)
    S.set("marks.quest", false); settle()
    assert.are.equal(0, #shown(RED))
    assert.are.equal(0, #shown(GREEN))
    assert.is_nil(tag())
    assert.is_nil(Marks.statusLine(cover, { word = "数", reading = "かず" }))
    cover.scripts.OnEnter(cover)
    if cover.scripts.OnUpdate then click("生き物", "LeftButton") end
    assert.are.equal("unknown", Status.get("ja", "生き物\tいきもの"))
  end)

  it("draws nothing with word cards off or while English shows, and draws again when they come back", function()
    S.set("readings.enabled", false); settle()
    assert.are.equal(0, #shown(RED))
    S.set("readings.enabled", true); settle()
    assert.are.equal(4, #shown(RED))
    Stub.keys.alt = true -- the reveal key goes down: the client's English is back on screen
    WFJ.Modifier.refresh()
    settle()
    assert.are.equal("Reduce their number.", fs:GetText())
    assert.are.equal(0, #shown(RED))
    Stub.keys.alt = false
    WFJ.Modifier.refresh()
    settle()
    assert.are.equal(4, #shown(RED))
  end)

  it("shows nothing for a player who only plays (word cards off), and everything for one who studies", function()
    -- what the welcome window's Just play writes, then what either study choice writes
    S.set("readings.enabled", false); settle()
    assert.are.equal(0, #shown(RED) + #shown(GREEN))
    assert.is_nil(tag())
    S.set("readings.enabled", true); settle()
    assert.are.equal(4, #shown(RED))
    assert.are.equal("理解度 0%", tag())
  end)

  it("Shift+click steps the word's status and Shift+right-click ignores it or takes that back", function()
    local key = "生き物\tいきもの"
    cover.scripts.OnEnter(cover)
    click("生き物", "LeftButton")
    assert.are.equal("learning", Status.get("ja", key))
    assert.is_truthy(Stub.prints[#Stub.prints]:find("生き物", 1, true))
    click("生き物", "LeftButton")
    assert.are.equal("known", Status.get("ja", key))
    click("生き物", "LeftButton")
    assert.are.equal("unknown", Status.get("ja", key))
    click("生き物", "RightButton")
    assert.are.equal("ignored", Status.get("ja", key))
    click("生き物", "RightButton")
    assert.are.equal("unknown", Status.get("ja", key))
    assert.are.equal(0, WFJ.Words.count()) -- none of these saved the word
  end)

  it("leaves an unmodified click and the save click as they were", function()
    cover.scripts.OnEnter(cover)
    click("生き物", "LeftButton", {})
    click("生き物", "RightButton", {})
    assert.are.equal("unknown", Status.get("ja", "生き物\tいきもの"))
    assert.are.equal(0, WFJ.Words.count())
    click("生き物", "LeftButton", { ctrl = true })
    assert.are.equal(1, WFJ.Words.count())
    assert.are.equal("unknown", Status.get("ja", "生き物\tいきもの"))
  end)

  it("lets Shift+click save, and says so on the card, while the save click is Shift+click", function()
    S.set("words.saveClick", "shift")
    cover.scripts.OnEnter(cover)
    click("生き物", "LeftButton")
    assert.are.equal(1, WFJ.Words.count())
    assert.are.equal("unknown", Status.get("ja", "生き物\tいきもの"))
    local en = WFJ.OptionsText.get("marks.clickOff")
    local _, ja = WFJ.OptionsText.get("marks.clickOff")
    local line = Marks.statusLine(cover, { word = "生き物", reading = "いきもの", gloss = 7 })
    assert.is_truthy(line:find(ja, 1, true) or line:find(en, 1, true))
  end)

  it("shows the status, the rank and the common mark on the word card, in the language now showing", function()
    local line = Marks.statusLine(cover, { word = "生き物", reading = "いきもの", gloss = 7 })
    assert.is_truthy(line:find("未知", 1, true))
    assert.is_truthy(line:find("#1", 1, true))
    assert.is_truthy(line:find("頻出", 1, true))
    assert.is_nil(line:find("Unknown", 1, true))
    Status.set("ja", "生き物\tいきもの", "known")
    line = Marks.statusLine(cover, { word = "生き物", reading = "いきもの", gloss = 7 })
    assert.is_truthy(line:find("既知", 1, true))
    assert.is_nil(line:find("頻出", 1, true))
    assert.is_nil(Marks.statusLine(cover, { word = "ストームウィンド", reading = "ストームウィンド", name = true }))
    cover.scripts.OnEnter(cover)
    assert.is_truthy(hintText():find("既知", 1, true)) -- and it is on the card that shows
  end)

  it("tags the text with the share of the quest's words the player knows", function()
    -- description 少し 生き物 狩る 数, progress 数 生き物: six counted words
    assert.are.equal("理解度 0%", tag())
    Status.set("ja", "生き物\tいきもの", "known")
    settle()
    assert.are.equal("理解度 33%", tag())
    S.set("marks.score", false); settle()
    assert.is_nil(tag())
  end)

  it("tags no text of fewer than five counted words", function()
    local short = spanFontString("Count.")
    short.parentFrame = CreateFrame("Frame")
    R.show("questframe.detail", "short", short, short:GetText(), "quests", "quest.description", 9)
    settle()
    local c = coverOf(short)
    assert.is_truthy(c)
    assert.is_true(c.scoreFs == nil or c.scoreFs.shown == false)
  end)

  it("marks prose only: never a window's own label, a name widget or a quest title on the same surface", function()
    WFJ.Data.add("reading", { ["ui:REWARDS"] = { text = "報酬=ほうしゅう" }, ["quest:456x"] = {} })
    local function shownOn(kind, id, key, text)
      local label = spanFontString(text)
      label.parentFrame = CreateFrame("Frame")
      R.show("questframe.detail", key, label, text, "quests", kind, id)
      settle()
      local c = coverOf(label)
      local n = 0
      for _, t in ipairs(c and c.markTex or {}) do if t.shown ~= false then n = n + 1 end end
      return c, n
    end
    local c = coverOf(fs)
    assert.are.equal("quest", c.marksPlace)
    -- the cover of a line of another kind on the same surface has no place, so no mark, click or status line
    for _, kind in ipairs({ "ui", "name", "quest.title" }) do
      local cover2 = { surface = "questframe.detail" }
      Marks.laid(cover2, { surface = "questframe.detail", key = "x", meta = { kind = kind, id = 1 } }, false)
      assert.is_nil(cover2.marksPlace, kind)
      assert.is_nil(Marks.active(cover2), kind)
    end
    assert.is_function(shownOn) -- (the label path itself is laid by UI/Labels; its kind is what decides)
  end)

  it("has a place for books, the voice panel and the frozen tooltip, each with its own switch", function()
    local places = { itemtext = "marks.book", ["dialogueui.book"] = "marks.book", voicepanel = "marks.voicepanel",
      ["tooltip.frozen"] = "marks.tooltip", gossip = "marks.quest", ["dialogueui.gossip"] = "marks.quest" }
    for surface, id in pairs(places) do
      local c = { surface = surface }
      Marks.laid(c, { surface = surface, key = "text", meta = { kind = "gossip", id = "g" } }, false)
      assert.is_truthy(Marks.active(c), surface)
      S.set(id, false)
      assert.is_nil(Marks.active(c), surface)
      S.set(id, true)
    end
    -- a surface that is no reading place has none
    local c = { surface = "tracker" }
    Marks.laid(c, { surface = "tracker", key = "x", meta = { kind = "gossip", id = "g" } }, false)
    assert.is_nil(c.marksPlace)
  end)

  it("switches the whole feature off with one setting: no mark, tag, status line or status click", function()
    S.set("marks.enabled", false); settle()
    assert.are.equal(0, #shown(RED) + #shown(GREEN))
    assert.is_nil(tag())
    assert.is_nil(Marks.statusLine(cover, { word = "生き物", reading = "いきもの", gloss = 7 }))
    cover.scripts.OnEnter(cover)
    if cover.scripts.OnUpdate then click("生き物", "LeftButton") end
    assert.are.equal("unknown", Status.get("ja", "生き物\tいきもの"))
    S.set("marks.enabled", true); settle()
    assert.are.equal(4, #shown(RED))
  end)

  it("hides the learning underline alone with its own setting", function()
    Status.set("ja", "生き物\tいきもの", "learning"); settle()
    assert.are.equal(1, #shown(BLUE))
    S.set("marks.learning", false); settle()
    assert.are.equal(0, #shown(BLUE))
    assert.are.equal(3, #shown(RED))
  end)

  it("draws nothing with translation off", function()
    WFJ.State.setEnabled(false)
    settle()
    assert.are.equal(0, #shown(RED) + #shown(GREEN))
    assert.is_nil(tag())
    WFJ.State.setEnabled(true)
    settle()
    assert.are.equal(4, #shown(RED))
  end)

  it("tags the text itself and its first paragraph only, never the voice panel's copy of it", function()
    cover.marksPlace, cover.recKey = "voicepanel", "text"
    S.set("marks.voicepanel", true)
    Marks.redraw(); settle()
    assert.is_nil(tag())
    cover.marksPlace, cover.recKey = "quest", "description.2"
    Marks.redraw(); settle()
    assert.is_nil(tag())
    cover.recKey = "description.1"
    Marks.redraw(); settle()
    assert.are.equal("理解度 0%", tag())
  end)

  it("offers no status click while the reveal key is Shift, and still shows the status", function()
    S.set("modifier", "shift")
    local line = Marks.statusLine(cover, { word = "生き物", reading = "いきもの", gloss = 7 })
    assert.is_truthy(line:find("#1", 1, true))
    assert.is_nil(line:find("Shift", 1, true))
    assert.is_false(Marks.click(cover, { word = "生き物", reading = "いきもの", gloss = 7 }, "LeftButton"))
  end)

  it("still ignores a word with Shift+right-click while Shift+click is the save click", function()
    S.set("words.saveClick", "shift")
    cover.scripts.OnEnter(cover)
    click("生き物", "RightButton")
    assert.are.equal("ignored", Status.get("ja", "生き物\tいきもの"))
    assert.are.equal(0, WFJ.Words.count())
  end)

  it("marks the client's English words in English first", function()
    S.set("direction", "en")
    settle()
    assert.are.equal("Reduce their number.", fs:GetText())
    assert.are.equal(2, #shown(RED)) -- reduce and number
    cover.scripts.OnEnter(cover)
    local s = fs:GetText():find("Reduce", 1, true)
    Stub.cursor = { 100 + s + 1, 205 }
    frame()
    Stub.keys.shift = true
    Stub.mouse.LeftButton = true; frame()
    Stub.mouse.LeftButton = false; frame()
    Stub.keys.shift = false
    assert.are.equal("learning", Status.get("en", "reduce"))
    assert.are.same({}, Status.entries("ja"))
  end)
end)
