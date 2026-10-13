-- Core/Intro + UI/IntroWindow: the window a first install shows once, at its first login, and never to a player who
-- already had the addon.
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

  it("a player who already had the addon never sees it after updating", function()
    start({ schema = 1, settings = {} })
    assert.is_true(_G.WFJ_DB.intro)
    Stub.fireAll("PLAYER_ENTERING_WORLD", true, false)
    assert.are.equal(0, opened)
  end)

  it("settings reset by a downgrade never count as a fresh install", function()
    start({ schema = 999, settings = {} })
    assert.is_true(_G.WFJ_DB.intro)
    Stub.fireAll("PLAYER_ENTERING_WORLD", true, false)
    assert.are.equal(0, opened)
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

  local function texts(f)
    local key = ("|cffffd200%s|r"):format(WFJ.Options.keyName()) -- the key's name in gold
    return {
      { f.lead, T["intro.lead"].ja, T["intro.lead"].en }, -- the opening line has no bullet
      { f.hold, "・" .. T["intro.hold"].ja:format(key), "• " .. T["intro.hold"].en:format(key) },
      { f.readings, "・" .. T["intro.readings"].ja, "• " .. T["intro.readings"].en },
      { f.minimap, "・" .. T["intro.minimap"].ja, "• " .. T["intro.minimap"].en },
    }
  end
  local function assertBoth(f)
    for _, row in ipairs(texts(f)) do
      assert.are.equal(row[2], row[1].ja:GetText())
      assert.are.equal(row[3], row[1].en:GetText())
      assert.is_true(row[1].ja:IsShown())
      assert.is_true(row[1].en:IsShown())
    end
  end

  it("shows every line in Japanese and English at once, the reveal key named", function()
    local f = IW.open()
    assert.is_true(f:IsShown())
    assert.are.equal("WoW Forever Japanese", f.title:GetText())
    assert.are.same({ "TOP", 0, -135 }, f.point) -- where the client's own popups open
    assertBoth(f)
    assert.is_truthy(f.hold.en:GetText():find("Alt", 1, true))
    assert.is_truthy(f.hold.ja:GetText():find("Alt", 1, true))
  end)

  it("keeps both languages while the reveal key is held and with translation off", function()
    local f = IW.open()
    Stub.keys.alt = true
    WFJ.Modifier.refresh()
    assertBoth(f)
    assert.are.equal("WoW Forever Japanese", f.title:GetText())
    Stub.keys.alt = false
    WFJ.Modifier.refresh()
    WFJ.State.setEnabled(false)
    assertBoth(f)
    WFJ.State.setEnabled(true)
  end)

  it("shows the voice line and its address while no voice pack has loaded, and neither with one", function()
    local f = IW.open()
    assert.is_true(f.voice.ja:IsShown())
    assert.is_true(f.voice.en:IsShown())
    assert.are.equal(T["intro.voice"].ja, f.voice.ja:GetText()) -- its own section: no bullet
    assert.are.equal(T["intro.voice"].en, f.voice.en:GetText())
    assert.is_true(f.voiceTitle:IsShown())
    assert.are.equal("日本語音声 / Japanese voice", f.voiceTitle:GetText())
    assert.is_true(f.box:IsShown())
    assert.are.equal(WFJ.Options.VOICE_URL, f.box:GetText())
    local tall = f.size[2]
    IW.close()
    WFJ.Voice.register({ format = 1, folder = "WoWForeverJapanese_Voice", lines = {} })
    IW.open()
    assert.is_false(f.voice.ja:IsShown())
    assert.is_false(f.voice.en:IsShown())
    assert.is_false(f.box:IsShown())
    assert.is_false(f.voiceTitle:IsShown())
    assert.is_true(f.size[2] < tall)
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
    function f.lead.ja.GetStringHeight() return 40 end -- the face that lands wraps the line to more rows
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

  it("one button labelled in both languages closes it, and Esc closes it", function()
    local f = IW.open()
    local caption = f.close.caption:GetText()
    assert.is_truthy(caption:find("閉じる", 1, true))
    assert.is_truthy(caption:find("Close", 1, true))
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
    for _, k in ipairs({ "intro.lead", "intro.hold", "intro.readings", "intro.minimap",
        "intro.voiceTitle", "intro.voice", "intro.close" }) do
      assert.is_string(T[k].en)
      assert.is_string(T[k].ja)
      assert.is_truthy(T[k].ja:find("[\227-\233]"))
      assert.is_falsy(T[k].en:find("\226\128\148", 1, true))
      assert.is_falsy(T[k].ja:find("\226\128\148", 1, true))
    end
  end)
end)
