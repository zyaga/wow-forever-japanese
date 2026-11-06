-- UI/StudyWindow: the tab, the card's front and back, the grades, collapse / close / reopen, the saved spot, combat.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = { "Core/Const.lua", "Core/Compat.lua", "Core/Data.lua", "Core/Readings.lua", "Core/Glosses.lua",
  "Core/State.lua", "Core/Settings.lua", "Core/Modifier.lua", "Core/Words.lua", "Core/Fsrs.lua", "Core/Study.lua",
  "UI/Font.lua", "UI/OptionsText.lua", "UI/OptionsWidgets.lua", "UI/StudyWindow.lua" }

local JA = "少しの生き物たちを狩り、数を減らしてほしい。"
local PACKED = "少し=すこし 生き物=いきもの=7 狩り=かり=8 数=かず"
local DAY = 86400
local NOW = 1790000000 -- a fixed moment; TODAY is its UTC date
local TODAY = "2026-09-21"

-- Unknown frame methods are harmless no-ops (SetMovable, StartMoving, SetBackdrop …); the ones the specs read
-- are real.
local NOOP = function() end
local function relax(t)
  return setmetatable(t, { __index = function(_, k)
    if type(k) == "string" and k:match("^%u") then return NOOP end
  end })
end
local function extendFrames()
  local create = _G.CreateFrame
  _G.CreateFrame = function(kind, name, parent, template)
    local f = create(kind, name, parent, template)
    function f:SetShown(v) if v then self:Show() else self:Hide() end end
    function f:ClearAllPoints() self.point = nil end
    function f.GetPoint() return "BOTTOM", nil, "BOTTOM", 10, 20 end
    function f:SetFrameStrata(s) self.strata = s end
    local createTexture = f.CreateTexture
    function f:CreateTexture(...) return relax(createTexture(self, ...)) end
    local createFontString = f.CreateFontString
    function f:CreateFontString(...)
      local fs = createFontString(self, ...)
      function fs.GetStringWidth(x) return #(x.text or "") * 6 end
      function fs.GetStringHeight() return 14 end
      return relax(fs)
    end
    return relax(f)
  end
end

describe("the study window", function()
  local WFJ, SW, S, db, attached, detached, timers, clock

  local function save(word, text, kind, id, surface)
    text = text or JA
    local first = text:find(word, 1, true)
    local _, e = WFJ.Words.add({ kind = kind or "quest.description", id = id or 456,
      surface = surface or "questframe.detail", text = text, first = first, last = first + #word - 1, word = word,
      reading = "いきもの", lemma = word, lemmaReading = "いきもの", meaning = "living thing", questTitle = "題" }, NOW)
    return e
  end
  local function loadStudy() WFJ.Study.load(nil, WFJ.Words.keys()) end
  local function runTimers()
    local due = timers
    timers = {}
    for _, t in ipairs(due) do t.fn() end
  end
  local function events()
    for _, f in ipairs(Stub.frames) do if f.events["PLAYER_REGEN_DISABLED"] then return f end end
  end
  local function ja(key, ...) return select(2, WFJ.OptionsText.get(key, ...)) end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    extendFrames()
    _G.WFJStudyTab, _G.WFJStudyCard = nil, nil -- the stub keeps named frames from an earlier test
    _G.UIParent = CreateFrame("Frame", "UIParent")
    clock = NOW
    _G.time = function() return clock end
    _G.date = function(p, t) return os.date("!" .. p, t or clock) end
    _G.InCombatLockdown = function() return false end
    timers = {}
    _G.C_Timer = { After = function(s, fn) timers[#timers + 1] = { s = s, fn = fn } end }
    attached, detached = {}, 0
    WFJ = H.loadChunks(FILES)
    WFJ.Compat.init(function(name) return _G[name] end)
    WFJ.Data.add("reading", { ["quest:456"] = { description = PACKED } })
    WFJ.Data.add("gloss", { [7] = "生き物\tいきもの\tliving thing", [8] = "狩る\tかる\tto hunt" })
    db = WFJ.Settings.load(nil, 1, {})
    WFJ.Words.load(nil)
    loadStudy()
    WFJ.ReadingView = {
      attach = function(r)
        local copy = {}
        for k, v in pairs(r) do copy[k] = v end
        attached[#attached + 1] = copy
        return true
      end,
      detach = function() detached = detached + 1 end,
    }
    S, SW = WFJ.Settings, WFJ.StudyWindow
    SW.init(db)
  end)
  after_each(function()
    _G.time, _G.date, _G.InCombatLockdown, _G.C_Timer = nil, nil, nil, nil
  end)

  local function tab() return _G.WFJStudyTab or { IsShown = function() return false end } end
  local function card() return _G.WFJStudyCard end

  it("the tab shows how many words wait, and nothing when none do or the setting is off", function()
    assert.is_false(tab():IsShown())
    save("生き物")
    save("数")
    loadStudy()
    SW.refresh()
    assert.is_true(tab():IsShown())
    assert.are.equal(ja("study.tab", 2), tab().text.text)
    S.set("study.tab", false)
    assert.is_false(tab():IsShown())
    S.set("study.tab", true)
    assert.is_true(tab():IsShown())
    WFJ.Study.answer("quest.description:456:生き物", WFJ.Study.GOOD, clock, TODAY)
    WFJ.Study.answer("quest.description:456:数", WFJ.Study.GOOD, clock, TODAY)
    SW.refresh()
    assert.is_false(tab():IsShown())
  end)

  it("clicking the tab opens the card: the word, its sentence with the word marked, the other words hoverable",
    function()
      local e = save("生き物")
      loadStudy()
      SW.refresh()
      tab().scripts.OnClick(tab())
      local f = card()
      assert.is_true(f:IsShown())
      assert.is_false(tab():IsShown())
      assert.are.equal("生き物", f.word.text)
      assert.are.equal(e.sentence, f.sentence.text)
      assert.is_true(f.show:IsShown())
      assert.is_false(f.again:IsShown())
      local r = attached[#attached]
      assert.are.equal("study", r.surface)
      assert.are.equal(f.sentence, r.fs)
      assert.are.equal(e.sentence, r.applied)
      assert.are.same({ kind = "quest.description", id = 456 }, r.meta)
      assert.are.same({ first = e.wf, last = e.wl }, r.mark)
      local words = {}
      for i, sp in ipairs(r.spans) do words[i] = sp.word end
      assert.are.same({ "少し", "狩り", "数" }, words) -- never the tested word
    end)

  it("Show answer reveals the reading, the dictionary form and the meaning, then Again and Good", function()
    local e = save("生き物たち")
    e.lemma, e.lemmaReading = "生き物", "いきもの"
    loadStudy()
    SW.open()
    local f = card()
    f.show.scripts.OnClick(f.show, "LeftButton")
    assert.is_false(f.show:IsShown())
    assert.is_true(f.again:IsShown())
    assert.is_true(f.good:IsShown())
    local text = f.answer.en.text
    assert.is_truthy(text:find("いきもの", 1, true))
    assert.is_truthy(text:find(ja("study.lemma", "生き物"), 1, true))
    assert.is_truthy(text:find("living thing", 1, true))
    assert.are.equal(1, #attached) -- the sentence's readings stay attached on the back
  end)

  it("Good schedules the word and shows the next; Again brings it back after ten minutes", function()
    save("生き物")
    save("数")
    loadStudy()
    SW.open()
    local f = card()
    assert.are.equal("生き物", f.word.text)
    SW.showAnswer()
    f.good.scripts.OnClick(f.good, "LeftButton")
    assert.are.equal(clock + 2 * DAY, WFJ.Study.card("quest.description:456:生き物").due)
    assert.are.equal("数", f.word.text)
    SW.showAnswer()
    f.again.scripts.OnClick(f.again, "LeftButton")
    assert.are.equal(clock + 600, WFJ.Study.card("quest.description:456:数").due)
    -- nothing due now: the done state says when the next word comes
    assert.is_true(f.message.en:IsShown())
    assert.is_false(f.sentence:IsShown())
    assert.is_truthy(f.message.en.text:find(ja("study.nextIn", 10), 1, true))
    clock = clock + 600
    SW.refresh()
    assert.are.equal("数", f.word.text)
    assert.is_true(f.show:IsShown())
  end)

  it("the done state says tomorrow when today's new words are used up, and to save words when there are none",
    function()
      SW.open()
      local f = card()
      assert.is_truthy(f.message.en.text:find(ja("study.empty"), 1, true))
      for _, w in ipairs({ "少し", "生き物", "狩り", "数", "減らして", "ほしい" }) do save(w) end
      loadStudy()
      S.set("study.newPerDay", "5")
      SW.refresh()
      for _ = 1, 5 do SW.showAnswer(); SW.grade(WFJ.Study.GOOD) end
      assert.is_truthy(f.message.en.text:find(ja("study.tomorrow"), 1, true))
      assert.is_false(tab():IsShown())
      -- the cap raised: the sixth word is asked; then every word waits two days, named by the day
      S.set("study.newPerDay", "50")
      assert.are.equal("ほしい", f.word.text)
      SW.showAnswer(); SW.grade(WFJ.Study.GOOD)
      assert.is_truthy(f.message.en.text:find(ja("study.nextOn", os.date("!%Y-%m-%d", clock + 2 * DAY)), 1, true))
    end)

  it("a word coming back later today, more than an hour away, is named by its time", function()
    save("生き物")
    loadStudy()
    SW.open()
    local f = card()
    SW.showAnswer(); SW.grade(WFJ.Study.AGAIN)
    clock = clock + 600
    SW.refresh()
    SW.showAnswer(); SW.grade(WFJ.Study.GOOD) -- a relearned word waits one whole day
    local due = WFJ.Study.card("quest.description:456:生き物").due
    assert.are.equal(clock + DAY, due)
    clock = due - 5600
    SW.refresh()
    assert.is_truthy(f.message.en.text:find(ja("study.nextAt", os.date("!%H:%M", due)), 1, true))
  end)

  it("collapse goes back to the tab; close hides both for the session; open and toggle bring the card back",
    function()
      save("生き物")
      loadStudy()
      SW.open()
      local f = card()
      f.collapse.scripts.OnClick(f.collapse, "LeftButton")
      assert.is_false(f:IsShown())
      assert.is_true(tab():IsShown())
      f.close.scripts.OnClick(f.close)
      assert.is_false(f:IsShown())
      assert.is_false(tab():IsShown())
      SW.refresh()
      assert.is_false(tab():IsShown()) -- closed stays closed this session
      S.set("study.tab", false)
      SW.open()
      assert.is_true(f:IsShown()) -- the setting never blocks an explicit open
      _G.WFJ_StudyToggle()
      assert.is_false(f:IsShown())
      _G.WFJ_StudyToggle()
      assert.is_true(f:IsShown())
      SW.close()
      SW.toggle()
      assert.is_true(f:IsShown())
    end)

  it("the card and the tab share the spot they were dragged to; /wfj study reset puts them back", function()
    save("生き物")
    loadStudy()
    SW.open()
    local f = card()
    assert.are.equal("RIGHT", f.point[1])
    f.scripts.OnDragStop(f)
    assert.are.same({ "BOTTOM", "BOTTOM", 10, 20 }, db.study.point)
    SW.collapse()
    assert.are.equal("BOTTOM", tab().point[1])
    local said = {}
    SW.command({ "reset" }, function(line) said[#said + 1] = line end)
    assert.is_nil(db.study.point)
    assert.are.equal("RIGHT", tab().point[1])
    assert.are.equal(1, #said)
    SW.command({ "elsewhere" }, function(line) said[#said + 1] = line end)
    assert.is_truthy(said[2]:find("/wfj study reset", 1, true))
  end)

  it("combat hides the tab and the card and brings back what was showing, unless the setting is off", function()
    save("生き物")
    loadStudy()
    SW.open()
    local f, ev = card(), events()
    ev:fire("PLAYER_REGEN_DISABLED")
    assert.is_false(f:IsShown())
    assert.is_false(tab():IsShown())
    ev:fire("PLAYER_REGEN_ENABLED")
    assert.is_true(f:IsShown())
    SW.collapse()
    ev:fire("PLAYER_REGEN_DISABLED")
    assert.is_false(tab():IsShown())
    ev:fire("PLAYER_REGEN_ENABLED")
    assert.is_true(tab():IsShown())
    S.set("study.combatHide", false)
    ev:fire("PLAYER_REGEN_DISABLED")
    assert.is_true(tab():IsShown())
    ev:fire("PLAYER_REGEN_ENABLED")
  end)

  it("a study table saved by a newer version refuses the grade with the word list's line", function()
    save("生き物")
    WFJ.Study.load({ schema = 99, cards = {} }, WFJ.Words.keys())
    SW.open()
    local f = card()
    assert.is_truthy(f.message.en:IsShown()) -- nothing is asked from a table it may not write
    assert.is_nil(SW.grade(WFJ.Study.GOOD))
    assert.are.same({}, Stub.prints)
  end)

  it("ticks every 15 seconds while in use, refreshing the tab, and stops once closed", function()
    assert.are.equal(1, #timers)
    assert.are.equal(SW.TICK, timers[1].s)
    save("生き物")
    loadStudy()
    runTimers()
    assert.is_true(tab():IsShown())
    assert.are.equal(1, #timers)
    SW.close()
    runTimers()
    assert.are.equal(0, #timers)
    SW.open()
    assert.are.equal(1, #timers)
  end)

  it("a word removed from the list leaves the card on the next refresh", function()
    save("生き物")
    save("数")
    loadStudy()
    SW.open()
    local f = card()
    assert.are.equal("生き物", f.word.text)
    WFJ.Words.removeLast() -- 数
    WFJ.Words.removeLast() -- 生き物
    WFJ.Study.prune(WFJ.Words.keys())
    SW.refresh()
    assert.is_true(f.message.en:IsShown())
  end)
end)
