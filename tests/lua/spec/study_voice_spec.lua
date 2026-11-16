-- UI/StudyVoice: a saved word's sentence found in its line's sentence files (Core/Voice format 3), played alone on the
-- study card, and named for the Anki export.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = { "Core/Const.lua", "Core/Compat.lua", "Core/State.lua", "Core/Settings.lua", "Core/Modifier.lua",
  "Core/Hash.lua",
  "Core/Voice.lua", "Core/Placeholders.lua", "Core/Words.lua", "UI/VoicePanelText.lua", "UI/StudyVoice.lua" }

local FOLDER = "WoWForeverJapanese_VoiceLevels1to10"
local BASE = "Interface\\AddOns\\" .. FOLDER .. "\\Sound\\"

-- A real row of the Levels 1-10 pack (format 3): quest 1463's turn-in, three sentences, one file each.
local REAL_JA = "信頼の証に1つやろう。お前はもう一度自分を証明しとる。だが、これからはもっと気をつけるべきだと俺は思うぞ。"
local REAL_MARKS = "2:45 1:64 1:16 1:40 1:8 1:24 4:24 2:112 1:32 2:24 1:24 1:16 2:16 1:40 2:16 1:48 3:8 1:104 2:16 "
  .. "2:64 2:24 1:24 3:16 1:40 1:24 3:8 2:32 1:24 1:16 1:16 1:16 2:24 2:32"
local REAL_CLIPS = { { "1463-completion-1.mp3", 2.952 }, { "1463-completion-2.mp3", 3.288 },
  { "1463-completion-3.mp3", 4.296 } }

-- Three sentences in two files: the second file holds the second and third sentence (spoken at 1.1 s and 2.1 s).
local TWO_JA = "よく来たな。話を聞いてくれ。頼む。"
local TWO_MARKS = "6:10 8:100 3:100"
local TWO_CLIPS = { { "g-aaaa-1.mp3", 1.0 }, { "g-aaaa-2.mp3", 2.0 } }

-- One sentence whose files were cut at its comma: it takes both.
local SPLIT_JA = "長い文、とても長い文だ。"
local SPLIT_MARKS = "4:10 8:100"
local SPLIT_CLIPS = { { "b-bbbb-1.mp3", 1.0 }, { "b-bbbb-2.mp3", 1.0 } }

-- A line naming the player: the parts are found in it as the window filled it.
local NAME_JA = "{name}、よく来た。頼む。"
local NAME_MARKS = "7:10 5:30 3:100"
local NAME_CLIPS = { { "5-progress-1.mp3", 1.0 }, { "5-progress-2.mp3", 1.0 } }

local WHOLE_JA = "一つだけ。"

describe("UI/StudyVoice", function()
  local WFJ, SV, shipped, played, stopped, timers, voiceStops, handles

  local function entry(kind, id, sentence, extra)
    local e = { key = kind .. ":" .. tostring(id) .. ":w", kind = kind, id = id, sentence = sentence, word = "w" }
    for k, v in pairs(extra or {}) do e[k] = v end
    return e
  end
  local function line(ja, clips, marks)
    return { false, WFJ.Hash.key(ja), s = clips, m = marks }
  end
  local function register()
    WFJ.Voice.register({ format = 3, folder = FOLDER, lines = {
      ["1463-completion"] = line(REAL_JA, REAL_CLIPS, REAL_MARKS),
      ["g-aaaa"] = line(TWO_JA, TWO_CLIPS, TWO_MARKS),
      ["b-bbbb"] = line(SPLIT_JA, SPLIT_CLIPS, SPLIT_MARKS),
      ["5-progress"] = line(NAME_JA, NAME_CLIPS, NAME_MARKS),
      ["9-description"] = line("古い訳。", { { "9-description-1.mp3", 1.0 } }, "4:10"),
    } })
    WFJ.Voice.register({ format = 2, folder = "WoWForeverJapanese_VoiceOther", lines = {
      ["g-cccc"] = { "g-cccc.mp3", WFJ.Hash.key(WHOLE_JA), 2.5 },
    } })
  end
  local function runTimers()
    local due = timers
    timers = {}
    table.sort(due, function(a, b) return a.s < b.s end)
    for _, t in ipairs(due) do t.fn() end
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    played, stopped, timers, voiceStops, handles = {}, {}, {}, 0, 0
    _G.PlaySoundFile = function(path, channel)
      handles = handles + 1
      played[#played + 1] = { path = path, channel = channel, handle = handles }
      return true, handles
    end
    _G.StopSound = function(h) stopped[#stopped + 1] = h end
    _G.C_Timer = { After = function(s, fn) timers[#timers + 1] = { s = s, fn = fn } end }
    WFJ = H.loadChunks(FILES)
    WFJ.Compat.init(function(name) return _G[name] end)
    WFJ.Settings.load(nil, 1, {})
    shipped = {
      ["quest.completion"] = { [1463] = { ja = REAL_JA } },
      ["quest.progress"] = { [5] = { ja = NAME_JA } },
      ["quest.description"] = { [9] = { ja = "新しい訳。" }, [10] = { variants = {} } },
      gossip = { aaaa = { ja = TWO_JA }, cccc = { ja = WHOLE_JA } },
      book = { bbbb = { ja = SPLIT_JA } },
      ui = { [3] = { ja = "閉じる" } },
    }
    WFJ.Voice.init({ lookup = function(kind, id) return shipped[kind] and shipped[kind][id] end,
      hash = WFJ.Hash.key })
    WFJ.expandTokens = function(ja) return (WFJ.Placeholders.expand(ja, { name = "Reyn" })) end
    WFJ.VoicePlayer = { playing = function() return "g-zzzz" end, stop = function() voiceStops = voiceStops + 1 end }
    SV = WFJ.StudyVoice
  end)
  after_each(function()
    _G.PlaySoundFile, _G.StopSound, _G.C_Timer = nil, nil, nil
  end)

  describe("find", function()
    it("a sentence alone in its file: that file, no stop time (a real pack row)", function()
      register()
      local r = SV.find(entry("quest.completion", 1463, "お前はもう一度自分を証明しとる。"))
      assert.are.equal(1, #r.clips)
      assert.are.equal(BASE .. "1463-completion-2.mp3", r.clips[1].path)
      assert.are.equal(3.288, r.clips[1].seconds)
      assert.is_nil(r.stop)
      assert.are.equal(BASE .. "1463-completion-1.mp3", SV.find(entry("quest.completion", 1463,
        "信頼の証に1つやろう。")).clips[1].path)
      assert.are.equal(BASE .. "1463-completion-3.mp3", SV.find(entry("quest.completion", 1463,
        "だが、これからはもっと気をつけるべきだと俺は思うぞ。")).clips[1].path)
    end)

    it("a sentence that shares its file with the next one stops where the next one starts", function()
      register()
      local r = SV.find(entry("gossip", "aaaa", "話を聞いてくれ。"))
      assert.are.equal(1, #r.clips)
      assert.are.equal(BASE .. "g-aaaa-2.mp3", r.clips[1].path)
      assert.is_near(1.1, r.stop, 1e-9)
      assert.is_nil(SV.find(entry("gossip", "aaaa", "よく来たな。")).stop) -- the next sentence is in the next file
    end)

    it("a sentence that starts inside a file after another sentence plays that file from its start", function()
      register()
      local r = SV.find(entry("gossip", "aaaa", "頼む。"))
      assert.are.equal(1, #r.clips)
      assert.are.equal(BASE .. "g-aaaa-2.mp3", r.clips[1].path)
      assert.is_nil(r.stop)
    end)

    it("a sentence cut across files takes each of them, in order", function()
      register()
      local r = SV.find(entry("book", "bbbb", SPLIT_JA))
      assert.are.same({ BASE .. "b-bbbb-1.mp3", BASE .. "b-bbbb-2.mp3" }, { r.clips[1].path, r.clips[2].path })
      assert.are.same({ FOLDER, "b-bbbb-2.mp3" }, { r.clips[2].folder, r.clips[2].file })
    end)

    it("a line naming the player is searched as this character's window shows it", function()
      register()
      assert.are.equal(BASE .. "5-progress-2.mp3", SV.find(entry("quest.progress", 5, "頼む。")).clips[1].path)
      assert.are.equal(BASE .. "5-progress-1.mp3", SV.find(entry("quest.progress", 5, "Reyn、よく来た。")).clips[1].path)
      -- saved by another character: its name is not in this one's line
      assert.are.same({ nil, "notfound" }, { SV.find(entry("quest.progress", 5, "Bob、よく来た。")) })
    end)

    it("a line in one file with no timing plays only when the sentence is the whole line", function()
      register()
      local r = SV.find(entry("gossip", "cccc", WHOLE_JA))
      assert.are.same({ "Interface\\AddOns\\WoWForeverJapanese_VoiceOther\\Sound\\g-cccc.mp3" }, { r.clips[1].path })
      assert.is_nil(r.stop)
      shipped.gossip.cccc = { ja = "一つだけ。二つ目。" }
      WFJ.Voice.register({ format = 2, folder = "WoWForeverJapanese_VoiceOther", lines = {
        ["g-cccc"] = { "g-cccc.mp3", WFJ.Hash.key("一つだけ。二つ目。"), 2.5 } } })
      assert.are.same({ nil, "untimed" }, { SV.find(entry("gossip", "cccc", WHOLE_JA)) })
    end)

    it("a short sentence is found where it starts a sentence, not inside an earlier one", function()
      register()
      -- 「頼む。」 is the third sentence; the first place it starts a sentence is that one
      shipped.gossip.aaaa = { ja = TWO_JA }
      assert.are.equal(BASE .. "g-aaaa-2.mp3", SV.find(entry("gossip", "aaaa", "頼む。")).clips[1].path)
      local text = "早く行け！行け！"
      shipped.gossip.eeee = { ja = text }
      WFJ.Voice.register({ format = 3, folder = "WoWForeverJapanese_VoiceOther", lines = {
        ["g-eeee"] = { false, WFJ.Hash.key(text), s = { { "g-eeee-1.mp3", 1.0 }, { "g-eeee-2.mp3", 1.0 } },
          m = "5:10 3:100" } } })
      assert.are.equal("Interface\\AddOns\\WoWForeverJapanese_VoiceOther\\Sound\\g-eeee-2.mp3",
        SV.find(entry("gossip", "eeee", "行け！")).clips[1].path)
    end)

    it("a file the pack gives no length is timed as the voice player guesses, so its end is not missed", function()
      register()
      shipped.gossip.ffff = { ja = WHOLE_JA }
      WFJ.Voice.register({ format = 2, folder = "WoWForeverJapanese_VoiceOld", lines = {
        ["g-ffff"] = { "g-ffff.mp3", WFJ.Hash.key(WHOLE_JA) } } })
      assert.are.equal(30, SV.find(entry("gossip", "ffff", WHOLE_JA)).clips[1].seconds)
    end)

    it("an English word plays its Japanese sentence, never its English one", function()
      register()
      local e = entry("gossip", "aaaa", "Listen to me.", { lang = "en", jaSentence = "話を聞いてくれ。" })
      assert.are.equal(BASE .. "g-aaaa-2.mp3", SV.find(e).clips[1].path)
      e.jaSentence = ""
      assert.are.same({ nil, "notfound" }, { SV.find(e) })
    end)

    it("says why a sentence cannot play", function()
      assert.are.same({ nil, "kind" }, { SV.find(entry("ui", 3, "閉じる")) })
      assert.are.same({ nil, "kind" }, { SV.find(entry("quest.title", 1463, "題")) })
      assert.are.same({ nil, "nopack" }, { SV.find(entry("gossip", "aaaa", "頼む。")) })
      register()
      assert.are.same({ nil, "missing" }, { SV.find(entry("gossip", "dddd", "頼む。")) })
      assert.are.same({ nil, "missing" }, { SV.find(entry("quest.description", 10, "頼む。")) })
      assert.are.same({ nil, "stale" }, { SV.find(entry("quest.description", 9, "新しい訳。")) })
      assert.are.same({ nil, "notfound" }, { SV.find(entry("gossip", "aaaa", "もう言わない。")) })
      assert.are.same({ nil, "notfound" }, { SV.find(entry("gossip", "aaaa", nil)) })
    end)

    it("a word as Words.add saves it finds its sentence; the saved list keeps its shape", function()
      register()
      WFJ.Words.load(nil)
      local text = WFJ.expandTokens(NAME_JA)
      local first = text:find("頼", 1, true)
      local status, e = WFJ.Words.add({ kind = "quest.progress", id = 5, surface = "questframe.progress", text = text,
        first = first, last = first + 5, word = "頼む", reading = "たのむ" }, 1)
      assert.are.equal("added", status)
      assert.are.equal(1, WFJ.Words.SCHEMA)
      local keys = {}
      for k in pairs(e) do keys[#keys + 1] = k end
      table.sort(keys)
      assert.are.same({ "id", "key", "kind", "lemma", "lemmaReading", "meaning", "questId", "reading", "saved",
        "sentence", "source", "wf", "wl", "word" }, keys)
      assert.are.equal(BASE .. "5-progress-2.mp3", SV.find(e).clips[1].path)
    end)
  end)

  describe("the export", function()
    it("an entry's Anki sound cell names its files as the pack names them, empty without audio", function()
      register()
      local book, label = entry("book", "bbbb", SPLIT_JA), entry("ui", 3, "閉じる")
      local found = SV.findAll({ book, label })
      assert.are.equal("[sound:b-bbbb-1.mp3][sound:b-bbbb-2.mp3]", SV.cell(found[book]))
      assert.is_nil(found[label])
      assert.are.equal("", SV.cell(found[label]))
    end)

    it("lists the files to copy once each, under the pack folder each is in, in list order", function()
      register()
      local list = { entry("book", "bbbb", SPLIT_JA), entry("gossip", "aaaa", "話を聞いてくれ。"),
        entry("gossip", "aaaa", "頼む。"), entry("ui", 3, "閉じる"), entry("gossip", "cccc", WHOLE_JA) }
      assert.are.same({
        FOLDER .. "/Sound:", "  b-bbbb-1.mp3", "  b-bbbb-2.mp3", "  g-aaaa-2.mp3",
        "WoWForeverJapanese_VoiceOther/Sound:", "  g-cccc.mp3",
      }, SV.fileList(list, SV.findAll(list)))
      assert.are.same({}, SV.fileList({ entry("ui", 3, "閉じる") }, {}))
    end)
  end)

  describe("playing", function()
    local function voiceOn() WFJ.Settings.set("voice.enabled", true) end

    it("plays the files one after another on Master, stopping the voice line playing first", function()
      register()
      voiceOn()
      local e = entry("book", "bbbb", SPLIT_JA)
      assert.is_true(SV.play(e))
      assert.are.equal(1, voiceStops)
      assert.are.same({ path = BASE .. "b-bbbb-1.mp3", channel = "Master", handle = 1 }, played[1])
      assert.are.equal(e.key, SV.playing())
      runTimers() -- the second file at the first one's end
      assert.are.equal(BASE .. "b-bbbb-2.mp3", played[2].path)
      runTimers() -- the end
      assert.is_nil(SV.playing())
      assert.are.equal(2, #played)
    end)

    it("stops the shared file where the next sentence starts", function()
      register()
      voiceOn()
      SV.play(entry("gossip", "aaaa", "話を聞いてくれ。"))
      local stopAt
      for _, t in ipairs(timers) do if math.abs(t.s - 1.1) < 1e-9 then stopAt = t end end
      assert.is_not_nil(stopAt)
      stopAt.fn()
      assert.are.same({ 1 }, stopped)
      assert.is_nil(SV.playing())
    end)

    it("a second play while it plays stops it; stop() and the timers after it do nothing more", function()
      register()
      voiceOn()
      local e = entry("book", "bbbb", SPLIT_JA)
      SV.play(e)
      assert.is_false(SV.toggle(e))
      assert.are.same({ 1 }, stopped)
      assert.is_nil(SV.playing())
      runTimers()
      assert.are.equal(1, #played) -- the old chain's timer started nothing
      assert.is_true(SV.toggle(e))
      assert.are.equal(2, #played)
    end)

    it("a file the client refuses leaves the voice line playing", function()
      register()
      _G.PlaySoundFile = function() return false end
      assert.are.same({ false, "refused" }, { SV.play(entry("book", "bbbb", SPLIT_JA)) })
      assert.are.equal(0, voiceStops)
      assert.is_nil(SV.playing())
    end)

    it("plays whatever translation, the voice switch, the reveal key or the direction say; refuses only with no pack "
      .. "or no audio", function()
      local e = entry("book", "bbbb", SPLIT_JA)
      assert.are.same({ false, "nopack" }, { SV.play(e) })
      assert.are.equal(0, #played)
      register()
      WFJ.Settings.set("voice.enabled", false)
      WFJ.State.setEnabled(false)
      WFJ.State.direction = "en"
      WFJ.State.modifierHeld = true
      assert.is_true(SV.play(e))
      assert.are.equal(1, #played)
      assert.are.same({ false, "stale" }, { SV.play(entry("quest.description", 9, "新しい訳。")) })
    end)

    it("keeps playing when translation or the voice switch goes off", function()
      register()
      SV.play(entry("book", "bbbb", SPLIT_JA))
      WFJ.State.setEnabled(false)
      WFJ.Settings.set("voice.enabled", false)
      assert.are.same({}, stopped)
      assert.is_not_nil(SV.playing())
    end)

    it("tells the card when it starts and ends", function()
      register()
      voiceOn()
      local seen = 0
      WFJ.State.on("studyVoice", function() seen = seen + 1 end)
      SV.play(entry("gossip", "aaaa", "よく来たな。"))
      assert.are.equal(1, seen)
      runTimers()
      assert.are.equal(2, seen)
    end)

    it("available: a pack loaded, nothing else", function()
      assert.is_false(SV.available())
      register()
      assert.is_true(SV.available())
      WFJ.Settings.set("voice.enabled", false)
      WFJ.State.setEnabled(false)
      assert.is_true(SV.available())
    end)
  end)
end)
