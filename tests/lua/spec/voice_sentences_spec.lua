-- The voice in sentences (ADR-090): packs in format 3 carry a line as one file per sentence and the time each part
-- of its Japanese is spoken; the player plays the files one after another, the panel follows the timing, and the
-- addon names packs that are out of date.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local JA = "よく来たな。話を聞いてくれ。"
local DATA = {
  ["quest.title"] = { [2] = { ja = "題", status = "." } },
  ["quest.description"] = { [2] = { ja = JA, status = "." }, [3] = { ja = "二つ目の依頼", status = "." } },
}
local FOLDER = "WoWForeverJapanese_VoiceLevels1to10"
local SENTENCES = { { "2-description-1.mp3", 1.0 }, { "2-description-2.mp3", 1.5 }, { "2-description-3.mp3", 0.5 } }
local TIMING = "2:10 4:20 2:100 6:20"

describe("Core/Voice: format 3 packs", function()
  local WFJ, V, settings

  before_each(function()
    WFJ = {}
    H.loadPure("Core/Hash.lua", nil, WFJ)
    H.loadPure("Core/Voice.lua", nil, WFJ)
    V = WFJ.Voice
    settings = { ["voice.enabled"] = true, ["voice.offer"] = true }
    V.init({
      lookup = function(kind, id) return DATA[kind] and DATA[kind][id] end,
      hash = WFJ.Hash.key,
      setting = function(id) return settings[id] end,
      revealed = function() return false end,
      enabled = function() return true end,
      meta = function(folder, field)
        return field == "Version" and (folder:match("Old") and "2026.10.11-aaaa" or "2026.11.14-bbbb")
      end,
    })
  end)

  local function line(ja) return { false, WFJ.Hash.key(ja), s = SENTENCES, m = TIMING } end

  it("a line in sentences gives the decision its files, their lengths and its timing", function()
    assert.are.same({ 1, 0 }, { V.register({ format = 3, folder = FOLDER, lines = { ["2-description"] = line(JA) } }) })
    local path, seconds, sentences = V.decide("questframe.detail", "description", "quest.description", 2, nil)
    local base = "Interface\\AddOns\\" .. FOLDER .. "\\Sound\\"
    assert.are.equal(base .. "2-description-1.mp3", path)
    assert.are.equal(3.0, seconds)
    assert.are.equal(3, #sentences)
    assert.are.same({ path = base .. "2-description-2.mp3", seconds = 1.5 }, sentences[2])
    assert.are.equal(TIMING, sentences.marks)
  end)

  it("where two packs carry a line, the one in the newer format keeps it, in either load order", function()
    for _, order in ipairs({ { 1, 2 }, { 2, 1 } }) do
      V.init({ lookup = function(kind, id) return DATA[kind] and DATA[kind][id] end, hash = WFJ.Hash.key,
        setting = function(id) return settings[id] end })
      local packs = {
        { format = 2, folder = "WoWForeverJapanese_VoiceOld",
          lines = { ["2-description"] = { "2-description.mp3", WFJ.Hash.key(JA), 3.0 } } },
        { format = 3, folder = FOLDER, lines = { ["2-description"] = line(JA) } },
      }
      for _, i in ipairs(order) do V.register(packs[i]) end
      local path, _, sentences = V.decide("questframe.detail", "description", "quest.description", 2, nil)
      assert.are.equal("Interface\\AddOns\\" .. FOLDER .. "\\Sound\\2-description-1.mp3", path)
      assert.are.equal(3, #sentences)
    end
  end)

  it("a whole-file line plays as one file with no sentences, and malformed sentences or timing are refused", function()
    V.register({ format = 2, folder = "WoWForeverJapanese_VoiceOld",
      lines = { ["2-description"] = { "2-description.mp3", WFJ.Hash.key(JA), 3.0 } } })
    local path, seconds, sentences = V.decide("questframe.detail", "description", "quest.description", 2, nil)
    assert.are.same({ "Interface\\AddOns\\WoWForeverJapanese_VoiceOld\\Sound\\2-description.mp3", 3.0 },
      { path, seconds })
    assert.is_nil(sentences)
    local _, bad = V.register({ format = 3, folder = FOLDER, lines = {
      ["3-description"] = { false, WFJ.Hash.key("二つ目の依頼"), s = { { "../x.mp3", 1 } } },
      ["3-progress"] = { false, WFJ.Hash.key("x"), s = SENTENCES, m = "two words" },
      ["3-completion"] = { false, WFJ.Hash.key("x") }, -- no file and no sentences
    } })
    assert.are.equal(3, bad)
  end)

  it("a line whose audio is older than its Japanese names its pack", function()
    V.register({ format = 3, folder = FOLDER, lines = { ["2-description"] = line("前の日本語") } })
    assert.are.same({ nil, "stale", FOLDER },
      { V.decide("questframe.detail", "description", "quest.description", 2, nil) })
  end)

  it("lists every pack with its version and format, and names the packs in an older format", function()
    V.register({ format = 3, folder = FOLDER, lines = { ["2-description"] = line(JA) } })
    V.register({ format = 2, folder = "WoWForeverJapanese_VoiceOld",
      lines = { ["3-description"] = { "3-description.mp3", WFJ.Hash.key("二つ目の依頼"), 1.0 } } })
    assert.are.same({ "Levels1to10 2026.11.14-bbbb (format 3, 1 lines)", "Old 2026.10.11-aaaa (format 2, 1 lines)" },
      V.packList())
    assert.are.same({ "Old 2026.10.11-aaaa" }, V.outdated())
  end)
end)

describe("UI/VoicePlayer: a line in sentences", function()
  local WFJ, S, db, sounds, stopped, timers, now, printed
  local FILES = { "Core/Const.lua", "Core/Compat.lua", "Core/State.lua", "Core/Settings.lua", "Core/Voice.lua",
    "Core/Modifier.lua", "Core/Translator.lua", "Core/SurfaceState.lua", "Core/Normalize.lua", "Core/Hash.lua",
    "Core/Collector.lua", "Core/UIStringKeys.lua", "Core/UIStrings.lua", "UI/Font.lua", "UI/Frames.lua",
    "UI/Render.lua", "Core/VoiceQueue.lua", "UI/VoicePlayer.lua", "UI/ButtonText.lua", "UI/Labels.lua",
    "UI/QuestFrame.lua" }

  local function fire(delay)
    for i, t in ipairs(timers) do
      if math.abs(t.delay - delay) < 1e-6 then
        table.remove(timers, i)
        return t.fn()
      end
    end
    error("no timer of " .. tostring(delay) .. " s")
  end

  local function setup(panel)
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI()
    sounds, stopped, timers, now, printed = {}, {}, {}, 100, {}
    _G.PlaySoundFile = function(path, channel)
      sounds[#sounds + 1] = { path = path, channel = channel }
      return true, #sounds
    end
    _G.StopSound = function(handle) stopped[#stopped + 1] = handle end
    _G.C_CVar = { GetCVar = function() return "1" end, SetCVar = function() end }
    _G.C_Timer = { After = function(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end }
    _G.GetTime = function() return now end
    _G.print = function(text) printed[#printed + 1] = text end
    WFJ = H.loadChunks(FILES)
    S = WFJ.Settings
    WFJ.Compat.init(function(name) return _G[name] end)
    db = S.load(nil, 1, {})
    WFJ.VoiceQueue.init(db)
    S.set("voice.panel.size", panel)
    WFJ.Render.init(WFJ.Translator.new({
      enabled = function() return WFJ.State.enabled end, areaEnabled = WFJ.State.areaEnabled,
      showsEnglish = WFJ.Modifier.english, lookup = function(kind, id) return DATA[kind] and DATA[kind][id] end,
      marker = function(n) return S.get("marker." .. n) end,
    }))
    WFJ.Voice.init({ lookup = function(kind, id) return DATA[kind] and DATA[kind][id] end, hash = WFJ.Hash.key,
      setting = S.get, revealed = WFJ.Modifier.isDown, enabled = function() return WFJ.State.enabled end,
      meta = function() return "2026.11.14-bbbb" end })
    assert.is_true(WFJ.QuestFrame.init())
    assert.is_true(WFJ.VoicePlayer.init(db))
    WFJ.Voice.register({ format = 3, folder = FOLDER, lines = {
      ["2-description"] = { false, WFJ.Hash.key(JA), s = SENTENCES, m = TIMING } } })
    Stub.quest = { id = 2, title = "T", description = "Talk.", objectives = "", progress = "", completion = "" }
  end

  after_each(function()
    _G.PlaySoundFile, _G.StopSound, _G.C_CVar, _G.C_Timer, _G.print = nil, nil, nil, nil, print
  end)

  local base = "Interface\\AddOns\\" .. FOLDER .. "\\Sound\\"

  it("plays the files one after another, each timed from the line's start, and ends after the last", function()
    setup("off")
    Stub.showDetail()
    assert.are.same({ base .. "2-description-1.mp3" }, { sounds[1].path })
    assert.are.equal(3.5, timers[1].delay) -- the line's length plus the margin
    now = 101.2 -- the timer fired late: the next one is shortened, so the chain never drifts
    fire(1.0)
    assert.are.equal(base .. "2-description-2.mp3", sounds[2].path)
    fire(1.3)
    assert.are.equal(base .. "2-description-3.mp3", sounds[3].path)
    assert.are.equal(3, #sounds)
  end)

  it("the panel's clock is the time into the line, from the start of the file playing", function()
    setup("off")
    Stub.showDetail()
    now = 100.5
    local t, marks = WFJ.VoicePlayer.timing()
    assert.are.equal(TIMING, marks)
    assert.is_true(math.abs(t - 0.5) < 1e-9)
    now = 101.0
    fire(1.0)
    now = 101.25
    t = WFJ.VoicePlayer.timing()
    assert.is_true(math.abs(t - 1.25) < 1e-9)
  end)

  it("a stop silences the file playing and the files not started never play", function()
    setup("off")
    Stub.showDetail()
    WFJ.VoicePlayer.stop()
    assert.are.same({ 1 }, stopped)
    fire(1.0)
    assert.are.equal(1, #sounds)
  end)

  it("pausing keeps the sentence playing and resuming starts there", function()
    setup("full")
    Stub.showDetail()
    fire(1.0)
    assert.are.equal(base .. "2-description-2.mp3", sounds[#sounds].path)
    assert.is_true(WFJ.VoicePlayer.pause())
    assert.is_true(WFJ.VoicePlayer.resume())
    assert.are.equal(base .. "2-description-2.mp3", sounds[#sounds].path)
    -- the line's clock counts the sentences before it
    local t = WFJ.VoicePlayer.timing()
    assert.is_true(math.abs(t - 1.0) < 1e-9)
  end)

  it("a line whose pack audio is older than its Japanese says so once, naming the pack", function()
    setup("off")
    WFJ.Voice.register({ format = 3, folder = FOLDER, lines = {
      ["2-description"] = { false, WFJ.Hash.key("前の日本語"), s = SENTENCES, m = TIMING } } })
    Stub.showDetail()
    Stub.showDetail()
    assert.are.equal(0, #sounds)
    assert.are.equal(1, #printed)
    assert.truthy(printed[1]:find("VoiceLevels1to10 2026.11.14-bbbb", 1, true)
      or printed[1]:find("Levels1to10 2026.11.14-bbbb", 1, true))
  end)

  it("at login, packs in an older format are named once and every pack goes to the log", function()
    setup("off")
    WFJ.Voice.register({ format = 2, folder = "WoWForeverJapanese_VoiceOther",
      lines = { ["3-description"] = { "3-description.mp3", WFJ.Hash.key("二つ目の依頼"), 1.0 } } })
    local logged = {}
    WFJ.Diag = { log = function(kind, msg) logged[#logged + 1] = kind .. ": " .. msg end }
    WFJ.VoicePlayer.announcePacks()
    WFJ.VoicePlayer.announcePacks()
    assert.are.equal(1, #printed)
    assert.truthy(printed[1]:find("out of date: Other 2026.11.14-bbbb", 1, true))
    assert.truthy(logged[1]:find("voicepacks: Levels1to10 2026.11.14-bbbb (format 3, 1 lines)", 1, true))
  end)

  it("at login, the packs the voice entry installs that did not load are named once", function()
    setup("off")
    WFJ.Voice.expect({ FOLDER, "WoWForeverJapanese_VoiceLevels1to10Part2", "NotAPack", 7,
      "WoWForeverJapanese_VoiceOther" })
    assert.are.same({ "Levels1to10Part2", "Other" }, WFJ.Voice.missing())
    WFJ.VoicePlayer.announcePacks()
    WFJ.VoicePlayer.announcePacks()
    assert.are.equal(1, #printed)
    assert.truthy(printed[1]:find("did not load: Levels1to10Part2, Other", 1, true))
  end)

  it("names no missing pack while the voice is off, or with no list from the entry", function()
    setup("off")
    WFJ.Voice.expect({ "WoWForeverJapanese_VoiceOther" })
    WFJ.Settings.set("voice.enabled", false)
    WFJ.VoicePlayer.announcePacks()
    assert.are.equal(0, #printed)
    WFJ.Settings.set("voice.enabled", true)
    WFJ.Voice.expect(nil)
    WFJ.VoicePlayer.announcePacks()
    assert.are.equal(0, #printed)
  end)

  it("plays a line by its key through the queue, for /wfj debug voice", function()
    setup("full")
    WFJ.Lookup = { get = function(kind, id) return DATA[kind] and DATA[kind][id] end }
    WFJ.Placeholders = { expand = function(text) return text, 0 end }
    local ok, what = WFJ.VoicePlayer.playKey("2-description")
    assert.is_true(ok)
    assert.are.equal("3 sentence files", what)
    assert.are.equal(base .. "2-description-1.mp3", sounds[1].path)
    assert.is_false((WFJ.VoicePlayer.playKey("nonsense")))
  end)
end)

describe("UI/VoicePanelText: following the timing", function()
  local T
  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    local WFJ = H.loadChunks({ "Core/Const.lua", "Core/Compat.lua", "Core/Data.lua", "Core/Readings.lua",
      "UI/Font.lua", "UI/VoicePanelText.lua" })
    T = WFJ.VoicePanelText
  end)

  local fill = function(piece) return (piece:gsub("{name}", "Reyn")) end

  it("finds every said part in the text as shown, with its time, closing marks left off", function()
    local parts = T.timedParts(JA, JA, TIMING, fill)
    assert.are.same({ 1, 6, 0.1 }, { parts[1].first, parts[1].last, parts[1].t })
    assert.are.equal("来たな", JA:sub(parts[2].first, parts[2].last))
    assert.are.equal(1.3, parts[3].t)
  end)

  it("finds a part holding the player's name filled in, and skips a part nobody says", function()
    local raw = "{name}よ、来い。\n<Kaltunkは笑った>"
    local shown = "Reynよ、来い。\n<Kaltunkは笑った>"
    local parts = T.timedParts(shown, raw, "6:10 3:30 2:- 14:-", fill)
    assert.are.equal("Reyn", shown:sub(parts[1].first, parts[1].last))
    assert.are.equal("よ、来", shown:sub(parts[2].first, parts[2].last))
    assert.are.equal(2, #parts)
  end)

  it("the part said last, and the word card's word as what to mark", function()
    local parts = T.timedParts(JA, JA, TIMING, fill)
    assert.is_nil(T.spokenAt(parts, 0.05))
    assert.are.equal(parts[2], T.spokenAt(parts, 0.5))
    local cards = { { first = parts[2].first, last = parts[2].first + 5 } } -- 来た
    assert.are.same({ parts[2].first, parts[2].last }, { T.unitOf(parts[2], cards) })
    assert.are.same({ parts[1].first, parts[1].last }, { T.unitOf(parts[1], cards) })
  end)

  it("leaves out a stage direction the voice skips, and keeps a line made only of directions", function()
    local pages = T.paginate("ふむ...\n<Kaltunkは笑った>\nきっとうまくゆくだろう。")
    assert.are.same({ "ふむ...きっとうまくゆくだろう。" }, pages)
    assert.are.same({ "<Sirraは手紙の翻訳を始めた……。>" }, (T.paginate("<Sirraは手紙の翻訳を始めた……。>")))
    assert.are.same({ "<lad/lass>よ、来い。" }, (T.paginate("<lad/lass>よ、来い。"))) -- a word pair, not a direction
  end)
end)
