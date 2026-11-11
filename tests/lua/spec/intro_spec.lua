-- Core/Intro + UI/IntroWindow: the welcome window, shown once to a first install at its first login and once to a
-- player who already had the addon, the first time a version that asks its question loads.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local Loader = require("tests.lua.spec.loader")
local F = require("tests.lua.spec.stub_fixwindow")

-- The whole addon through ADDON_LOADED, with the tool window templates, from `saved` as WFJ_DB.
local function boot(saved)
  Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
  F.install()
  Stub.installQuestAPI(); Stub.installTooltipAPI(); Stub.installGossipAPI()
  _G.WFJ_DB = saved
  local WFJ = Loader.load("WoWForeverJapanese")
  Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese")
  return WFJ
end

describe("Core/Intro", function()
  local I
  setup(function()
    H.coreStub()
    local ns = H.loadChunks({ "Core/Const.lua" })
    H.loadPure("Core/Intro.lua", nil, ns)
    I = ns.Intro
  end)

  it("a fresh install owes the window; a table that never had the key counts as seen", function()
    local db = {}
    I.prepare(db, true)
    assert.is_false(db.intro)
    db = { settings = {} }
    I.prepare(db, false)
    assert.is_true(db.intro)
  end)

  it("leaves an owed or a seen window as it is on a later load", function()
    local db = { intro = false }
    I.prepare(db, false) -- a reload before the first login finished
    assert.is_false(db.intro)
    db = { intro = true }
    I.prepare(db, true)
    assert.is_true(db.intro)
  end)

  it("runs show once when owed and marks it seen", function()
    local db, shown = { intro = false }, 0
    local function show() shown = shown + 1 end
    assert.is_true(I.run(db, show))
    assert.is_true(db.intro)
    assert.is_false(I.run(db, show))
    assert.are.equal(1, shown)
  end)

  it("shows nothing when seen, never prepared, or with no table", function()
    local shown = 0
    local function show() shown = shown + 1 end
    assert.is_false(I.run({ intro = true }, show))
    assert.is_false(I.run({}, show))
    assert.is_false(I.run(nil, show))
    assert.is_nil(I.prepare(nil, true))
    assert.are.equal(0, shown)
  end)

  it("owes the question once to a player who already had the addon, and never again", function()
    local db, shown = { settings = {} }, 0
    local function show() shown = shown + 1 end
    I.prepare(db, false)
    assert.is_true(db.intro)
    assert.is_false(db.asked)
    assert.is_true(I.run(db, show))
    assert.is_true(db.asked)
    I.prepare(db, false) -- the next login
    assert.is_false(I.run(db, show))
    assert.are.equal(1, shown)
  end)

  it("asks a fresh install once, not twice, for the window and the question", function()
    local db, shown = {}, 0
    I.prepare(db, true)
    assert.is_true(I.run(db, function() shown = shown + 1 end))
    assert.is_true(db.intro)
    assert.is_true(db.asked)
    assert.is_false(I.run(db, function() shown = shown + 1 end))
    assert.are.equal(1, shown)
  end)

  it("marks it seen before showing, so a window that fails never comes back at every login", function()
    local db = { intro = false }
    local ok = pcall(I.run, db, function() error("broken window") end)
    assert.is_false(ok)
    assert.is_true(db.intro)
    assert.is_false(I.run(db, function() error("must not run") end))
  end)
end)

describe("the intro at ADDON_LOADED and PLAYER_ENTERING_WORLD", function()
  after_each(function() F.clear() end)

  local opened
  local function start(saved)
    local WFJ = boot(saved)
    opened = 0
    local open = WFJ.IntroWindow.open
    WFJ.IntroWindow.open = function() opened = opened + 1; return open() end
    return WFJ
  end

  it("a fresh install shows it at the first login, not on a zone change, and never again", function()
    local WFJ = start(nil)
    assert.is_false(_G.WFJ_DB.intro)
    Stub.fireAll("PLAYER_ENTERING_WORLD", false, false) -- a zone change
    assert.are.equal(0, opened)
    Stub.fireAll("PLAYER_ENTERING_WORLD", true, false) -- login
    assert.are.equal(1, opened)
    assert.is_true(WFJ.IntroWindow.frame:IsShown())
    assert.is_true(_G.WFJ_DB.intro)
    assert.are.same({}, WFJ.initErrors)
    Stub.fireAll("PLAYER_ENTERING_WORLD", false, true) -- a reload
    assert.are.equal(1, opened)
    local saved = _G.WFJ_DB
    F.clear()
    start(saved) -- the next session
    Stub.fireAll("PLAYER_ENTERING_WORLD", true, false)
    assert.are.equal(0, opened)
  end)

  it("a fresh install that reloads first shows it at that reload", function()
    start(nil)
    Stub.fireAll("PLAYER_ENTERING_WORLD", false, true)
    assert.are.equal(1, opened)
  end)

  it("a player who already had the addon is asked once after updating, with every setting kept", function()
    start({ schema = 1, settings = { ["readings.enabled"] = false, modifier = "ctrl" } })
    assert.is_true(_G.WFJ_DB.intro)
    assert.is_false(_G.WFJ_DB.asked)
    Stub.fireAll("PLAYER_ENTERING_WORLD", true, false)
    assert.are.equal(1, opened)
    assert.is_true(_G.WFJ_DB.asked)
    assert.is_false(_G.WFJ_DB.settings["readings.enabled"]) -- showing the question changes nothing
    assert.are.equal("ctrl", _G.WFJ_DB.settings.modifier)
    local saved = _G.WFJ_DB
    F.clear()
    start(saved) -- the next session
    Stub.fireAll("PLAYER_ENTERING_WORLD", true, false)
    assert.are.equal(0, opened)
  end)

  it("settings reset by a downgrade are asked once, like any table that was never asked", function()
    start({ schema = 999, settings = {} })
    assert.is_true(_G.WFJ_DB.intro)
    Stub.fireAll("PLAYER_ENTERING_WORLD", true, false)
    assert.are.equal(1, opened)
  end)

  it("a window that fails to open is caught, marked seen, and the reminder still runs", function()
    local WFJ = start(nil)
    WFJ.IntroWindow.open = function() error("broken window") end
    local reminded = 0
    WFJ.CollectorRemind.run = function() reminded = reminded + 1 end
    Stub.fireAll("PLAYER_ENTERING_WORLD", true, false)
    assert.are.equal(1, reminded)
    assert.is_true(_G.WFJ_DB.intro)
    local surfaces = {}
    for _, e in ipairs(WFJ.initErrors) do surfaces[#surfaces + 1] = e.surface end
    assert.are.same({ "intro" }, surfaces)
  end)
end)

describe("UI/IntroWindow, the window", function()
  after_each(function() F.clear() end)
  local WFJ, IW, T

  before_each(function()
    WFJ = boot({ schema = 1, settings = {} })
    IW, T = WFJ.IntroWindow, WFJ.OptionsText.T
  end)

  -- the second page's points for a choice, as { line, Japanese, English }
  local function points(f, english)
    local key = ("|cffffd200%s|r"):format(WFJ.Options.keyName()) -- the key's name in gold
    local lead, hold, readings = "intro.lead", "intro.hold", "intro.readings"
    if english then lead, hold, readings = "intro.lead.en", "intro.hold.en", "intro.readings.en" end
    return {
      { f.lead, T[lead].ja, T[lead].en },
      { f.hold, T[hold].ja:format(key), T[hold].en:format(key) },
      { f.readings, T[readings].ja, T[readings].en },
      { f.minimap, T["intro.minimap"].ja, T["intro.minimap"].en },
    }
  end
  local function assertBoth(f, english)
    for _, row in ipairs(points(f, english)) do
      assert.is_table(row[1].ja.point, row[2]) -- placed by the layout, so it is drawn
      assert.is_table(row[1].en.point, row[3])
      assert.are.equal(row[2], row[1].ja:GetText())
      assert.are.equal(row[3], row[1].en:GetText())
      assert.is_true(row[1].ja:IsShown())
      assert.is_true(row[1].en:IsShown())
    end
  end
  local function settings()
    local S = WFJ.Settings
    return { S.get("direction"), S.get("readings.enabled"), S.get("study.tab") }
  end

  it("opens on the question: three cards in both languages, the one the settings match lit and described",
  function()
    local f = IW.open()
    assert.is_true(f:IsShown())
    assert.are.equal("WoW Forever Japanese", f.title:GetText())
    assert.are.same({ "TOP", 0, -135 }, f.point) -- where the client's own popups open
    assert.is_true(f.pickPage:IsShown())
    assert.is_false(f.infoPage:IsShown())
    assert.are.same({ T["intro.ask"].ja, T["intro.ask"].en }, { f.ask.ja:GetText(), f.ask.en:GetText() })
    for _, purpose in ipairs({ "ja", "en", "play" }) do
      local c = f.cards[purpose]
      assert.are.same({ T["intro.pick." .. purpose].en, T["intro.pick." .. purpose].ja },
        { c.en:GetText(), c.ja:GetText() })
      assert.is_string(c.icon.texture)
    end
    assert.are.equal("ja", IW.selected) -- a fresh table's settings are the Japanese learner's
    assert.is_true(f.cards.ja.picked)
    assert.is_falsy(f.cards.en.picked)
    assert.is_truthy(f.about.ja:GetText():find("・", 1, true)) -- a list, one point per line
    assert.are.equal(2, select(2, f.about.en:GetText():gsub("\n", "")))
  end)

  it("a click on a card only selects and describes it; nothing is written until Confirm", function()
    local f = IW.open()
    local before = settings()
    f.cards.en.scripts.OnClick(f.cards.en)
    assert.are.equal("en", IW.selected)
    assert.is_true(f.cards.en.picked)
    assert.is_false(f.cards.ja.picked)
    assert.is_truthy(f.about.en:GetText():find("stays in English", 1, true))
    assert.are.same(before, settings())
    assert.is_true(f.pickPage:IsShown())
  end)

  it("Confirm writes exactly the choice's settings and moves to the second page, worded for it", function()
    local f = IW.open()
    WFJ.Settings.set("modifier", "ctrl")
    WFJ.Settings.set("marker.missing", false)
    f.cards.en.scripts.OnClick(f.cards.en)
    f.confirm.scripts.OnClick(f.confirm)
    assert.are.same({ "en", true, true }, settings())
    assert.is_true(f.infoPage:IsShown())
    assert.is_false(f.pickPage:IsShown())
    assertBoth(f, true)
    assert.is_truthy(f.hold.en:GetText():find("Ctrl", 1, true))
    -- nothing else moved
    assert.are.same({ "ctrl", false }, { WFJ.Settings.get("modifier"), WFJ.Settings.get("marker.missing") })
    -- Back returns to the cards; playing only turns the cards and the study tab off and drops the card point
    f.back.scripts.OnClick(f.back)
    assert.is_true(f.pickPage:IsShown())
    f.cards.play.scripts.OnClick(f.cards.play)
    f.confirm.scripts.OnClick(f.confirm)
    assert.are.same({ "ja", false, false }, settings())
    assert.is_false(f.readings.ja:IsShown())
    assert.is_false(f.readings.en:IsShown())
    f.back.scripts.OnClick(f.back)
    f.cards.ja.scripts.OnClick(f.cards.ja)
    f.confirm.scripts.OnClick(f.confirm)
    assert.are.same({ "ja", true, true }, settings())
    assertBoth(f, false)
  end)

  it("confirming the choice the settings already match keeps a study tab the player hid", function()
    WFJ.Settings.set("study.tab", false)
    local f = IW.open()
    assert.are.equal("ja", IW.selected)
    f.confirm.scripts.OnClick(f.confirm)
    assert.are.same({ "ja", true, false }, settings())
    -- a real change of choice writes the tab with the rest
    f.back.scripts.OnClick(f.back)
    f.cards.en.scripts.OnClick(f.cards.en)
    f.confirm.scripts.OnClick(f.confirm)
    assert.are.same({ "en", true, true }, settings())
  end)

  it("closing without Confirm changes nothing, and it opens again on the cards with the settings' choice lit",
  function()
    WFJ.Settings.set("readings.enabled", false)
    local f = IW.open()
    assert.are.equal("play", IW.selected)
    f.cards.en.scripts.OnClick(f.cards.en)
    IW.close()
    assert.are.same({ "ja", false, true }, settings())
    IW.open()
    assert.are.equal("play", IW.selected)
    assert.is_true(f.pickPage:IsShown())
  end)

  it("the one time it asks, it starts on studying Japanese whatever the settings; by hand, on what they match",
  function()
    WFJ.Settings.set("readings.enabled", false)
    IW.request() -- the stub has no timer: it opens at once
    assert.are.equal("ja", IW.selected)
    assert.are.same({ "ja", false, true }, settings()) -- shown, not written
    IW.close()
    IW.open()
    assert.are.equal("play", IW.selected)
  end)

  it("the second page keeps both languages while the reveal key is held and with translation off", function()
    local f = IW.open()
    f.confirm.scripts.OnClick(f.confirm)
    Stub.keys.alt = true
    WFJ.Modifier.refresh()
    assertBoth(f, false)
    assert.are.equal("WoW Forever Japanese", f.title:GetText())
    Stub.keys.alt = false
    WFJ.Modifier.refresh()
    WFJ.State.setEnabled(false)
    assertBoth(f, false)
    WFJ.State.setEnabled(true)
  end)

  it("the second page shows the voice section while no voice pack has loaded, and not with one", function()
    local f = IW.open()
    f.confirm.scripts.OnClick(f.confirm)
    assert.is_true(f.voice.ja:IsShown())
    assert.is_true(f.voice.en:IsShown())
    assert.are.equal(T["intro.voice"].ja, f.voice.ja:GetText())
    assert.are.equal(T["intro.voice"].en, f.voice.en:GetText())
    assert.is_true(f.voiceTitle:IsShown())
    assert.are.equal("日本語音声 / Japanese voice", f.voiceTitle:GetText())
    assert.is_true(f.box:IsShown())
    assert.are.equal(WFJ.Options.VOICE_URL, f.box:GetText())
    local tall = f.size[2]
    IW.close()
    WFJ.Voice.register({ format = 1, folder = "WoWForeverJapanese_Voice", lines = {} })
    IW.open()
    f.confirm.scripts.OnClick(f.confirm)
    assert.is_false(f.voice.ja:IsShown())
    assert.is_false(f.voice.en:IsShown())
    assert.is_false(f.box:IsShown())
    assert.is_false(f.voiceTitle:IsShown())
    assert.is_true(f.size[2] < tall)
  end)

  it("/wfj intro opens it again for anyone, any number of times, and never touches the asked flag", function()
    local asked = _G.WFJ_DB.asked
    WFJ.Slash.handle("intro")
    assert.is_true(IW.frame:IsShown())
    IW.close()
    WFJ.Slash.handle("intro")
    assert.is_true(IW.frame:IsShown())
    assert.are.equal(asked, _G.WFJ_DB.asked)
  end)

  it("on a fresh launch, lays the lines out again once the bundled face is applied", function()
    local ticks = {}
    _G.C_Timer = { NewTicker = function(_, fn)
      local t = { cancelled = false }
      function t.Cancel() t.cancelled = true end
      ticks[#ticks + 1] = { fn = fn, t = t }
      return t
    end }
    Stub.fontSetFails = true -- the client refuses the bundled face until its file loads
    local f = IW.open()
    assert.are.equal(1, #ticks)
    local before = f.size[2]
    function f.ask.ja.GetStringHeight() return 40 end -- the face that lands wraps the line to more rows
    ticks[1].fn(ticks[1].t)
    assert.are.equal(before, f.size[2]) -- still refused: nothing measured again yet
    assert.is_false(ticks[1].t.cancelled)
    Stub.fontSetFails = false
    WFJ.Font.retryPending()
    ticks[1].fn(ticks[1].t)
    assert.is_true(f.size[2] > before)
    assert.is_true(ticks[1].t.cancelled)
    IW.open() -- nothing refused now: no second ticker
    assert.are.equal(1, #ticks)
    _G.C_Timer = nil
  end)

  -- C_Timer.After queued instead of run, and InCinematic() as the test sets it
  local function timers()
    local q = {}
    _G.C_Timer = { After = function(_, fn) q[#q + 1] = fn end }
    local function run() local now = q; q = {}; for _, fn in ipairs(now) do fn() end end
    return run, function() return #q end
  end
  local cinematic = false
  before_each(function() cinematic = false; _G.InCinematic = function() return cinematic end end)
  after_each(function() _G.C_Timer, _G.InCinematic = nil, nil end)

  it("opens a moment after it is asked for, never in the same event", function()
    local run = timers()
    IW.request()
    assert.is_falsy(IW.frame and IW.frame:IsShown())
    run()
    assert.is_true(IW.frame:IsShown())
  end)

  it("waits out a cinematic that is playing, and opens after it", function()
    local run = timers()
    cinematic = true
    IW.request()
    run()
    assert.is_falsy(IW.frame and IW.frame:IsShown())
    cinematic = false
    Stub.fireAll("CINEMATIC_STOP")
    run()
    assert.is_true(IW.frame:IsShown())
  end)

  it("comes back after a cinematic hid it, but stays closed once the player closed it", function()
    local run = timers()
    IW.request()
    run()
    local f = IW.frame
    cinematic = true -- a race intro starts: the client closes the special windows
    Stub.fireAll("CINEMATIC_START")
    f:Hide()
    run()
    cinematic = false
    Stub.fireAll("CINEMATIC_STOP")
    run()
    assert.is_true(f:IsShown())
    f.close.scripts.OnClick(f.close, "LeftButton")
    run()
    assert.is_false(f:IsShown())
    cinematic = true
    Stub.fireAll("CINEMATIC_START")
    cinematic = false
    Stub.fireAll("CINEMATIC_STOP")
    run()
    assert.is_false(f:IsShown())
  end)

  it("a sweep that hides it before the cinematic's start is heard still brings it back", function()
    local run = timers()
    IW.request()
    run()
    local f = IW.frame
    cinematic = true
    f:Hide() -- the client's sweep runs first
    Stub.fireAll("CINEMATIC_START") -- then the event reaches this addon
    run()
    cinematic = false
    Stub.fireAll("CINEMATIC_STOP")
    run()
    assert.is_true(f:IsShown())
  end)

  it("a cinematic the player skips within a second still brings it back", function()
    local run = timers()
    IW.request()
    run()
    local f = IW.frame
    cinematic = true
    f:Hide()
    Stub.fireAll("CINEMATIC_START")
    cinematic = false
    Stub.fireAll("CINEMATIC_STOP") -- skipped before the hide's check ran
    run() -- the hide's check and the reopen
    run()
    assert.is_true(f:IsShown())
  end)

  it("a window that fails to open a moment later is still recorded as the intro step", function()
    local run = timers()
    WFJ.initErrors = {}
    IW.open = function() error("broken window") end
    IW.request()
    run()
    local surfaces = {}
    for _, e in ipairs(WFJ.initErrors) do surfaces[#surfaces + 1] = e.surface end
    assert.are.same({ "intro" }, surfaces)
  end)

  it("a hide outside a cinematic is the player's: Esc keeps it closed too", function()
    local run = timers()
    IW.request()
    run()
    IW.frame:Hide() -- Esc closes the special windows
    run()
    Stub.fireAll("CINEMATIC_STOP")
    run()
    assert.is_false(IW.frame:IsShown())
  end)

  it("/wfj debug intro opens it, and novoice draws the voice line even with a pack loaded", function()
    WFJ.Voice.register({ format = 1, folder = "WoWForeverJapanese_Voice", lines = {} })
    SlashCmdList.WFJ("debug intro")
    assert.is_true(IW.frame:IsShown())
    assert.is_false(IW.frame.voice.ja:IsShown())
    SlashCmdList.WFJ("debug intro novoice")
    assert.is_true(IW.frame.voice.ja:IsShown())
    assert.is_true(IW.frame.box:IsShown())
  end)

  it("the Start button, labelled in both languages, closes it, and Esc closes it", function()
    local f = IW.open()
    local caption = f.close.caption:GetText()
    assert.is_truthy(caption:find("始める", 1, true))
    assert.is_truthy(caption:find("Start", 1, true))
    Stub.keys.alt = true
    WFJ.Modifier.refresh()
    assert.are.equal(caption, f.close.caption:GetText())
    Stub.keys.alt = false
    WFJ.Modifier.refresh()
    f.close.scripts.OnClick(f.close, "LeftButton")
    assert.is_false(f:IsShown())
    local special = false
    for _, name in ipairs(_G.UISpecialFrames) do if name == "WFJIntro" then special = true end end
    assert.is_true(special)
  end)

end)

describe("UI/OptionsText, the intro window's copy", function()
  local T
  setup(function() T = H.loadChunks({ "UI/OptionsText.lua" }).OptionsText.T end)

  it("every line is the addon's own copy in both languages, with no em dash", function()
    for _, k in ipairs({ "intro.lead", "intro.hold", "intro.readings", "intro.words", "intro.minimap",
        "intro.voiceTitle", "intro.voice", "intro.close" }) do
      assert.is_string(T[k].en)
      assert.is_string(T[k].ja)
      assert.is_truthy(T[k].ja:find("[\227-\233]"))
      assert.is_falsy(T[k].en:find("\226\128\148", 1, true))
      assert.is_falsy(T[k].ja:find("\226\128\148", 1, true))
    end
  end)
end)
