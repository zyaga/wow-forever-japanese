local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = { "Core/Const.lua", "Core/Compat.lua", "Core/State.lua", "Core/Settings.lua", "Core/Voice.lua",
  "Core/Modifier.lua", "Core/Translator.lua", "Core/SurfaceState.lua", "Core/Normalize.lua", "Core/Hash.lua",
  "Core/Collector.lua", "Core/UIStringKeys.lua", "Core/UIStrings.lua", "UI/Font.lua", "UI/Render.lua",
  "UI/VoicePlayer.lua", "UI/ButtonText.lua", "UI/Labels.lua", "UI/QuestFrame.lua" }

local DATA = {
  ["quest.title"] = { [2] = { ja = "Sharptalonの鉤爪", status = "." }, [3] = { ja = "別のクエスト", status = "." } },
  ["quest.description"] = { [2] = { ja = "御機嫌よう、{name}。Silverwind Refugeへ行け。", status = "." },
    [3] = { ja = "二つ目の依頼", status = "." } },
  ["quest.objectives"] = { [2] = { ja = "Sharptalonを倒せ", status = "." } },
  ["quest.completion"] = { [2] = { ja = "よくやった", status = "." } },
  ["quest.progress"] = { [2] = { ja = "まだか？", status = "." } },
}

describe("Core/Voice: the pack registry and the decision", function()
  local WFJ, V
  local settings, revealed, enabled

  before_each(function()
    WFJ = {}
    H.loadPure("Core/Hash.lua", nil, WFJ)
    H.loadPure("Core/Voice.lua", nil, WFJ) -- pure: no frame, no sound API, no global
    V = WFJ.Voice
    settings = { ["voice.enabled"] = true, ["voice.offer"] = true, ["voice.progress"] = true,
      ["voice.turnin"] = true, ["voice.greeting"] = true }
    revealed, enabled = false, true
    V.init({
      lookup = function(kind, id) return DATA[kind] and DATA[kind][id] end,
      hash = WFJ.Hash.key,
      setting = function(id) return settings[id] end,
      revealed = function() return revealed end,
      enabled = function() return enabled end,
    })
  end)

  local function pack(lines)
    return { format = 1, folder = "WoWForeverJapanese_Voice", lines = lines }
  end

  local function entry(file, ja, seconds) return { file, WFJ.Hash.key(ja), seconds } end

  it("registers a valid table and drops malformed entries, counting them", function()
    local n, bad = V.register(pack({
      ["2-description"] = entry("2-description.mp3", DATA["quest.description"][2].ja, 4.2),
      ["2-progress"] = { "../../Other/evil.mp3", WFJ.Hash.key("x"), 1 }, -- outside the Sound folder
      ["2-completion"] = { "2-completion.mp3", "nothex", 1 },
      ["g-0123456789abcdef"] = { "g-0123456789abcdef.mp3", "0123456789ABCDEF" }, -- no length is fine
    }))
    assert.are.equal(2, n)
    assert.are.equal(2, bad)
    assert.is_true(V.hasPack())
    assert.are.same({ registered = 2, invalid = 2, matched = 0, missing = 0, stale = 0 }, V.counts)
  end)

  it("refuses a table of another format or folder as a whole", function()
    assert.are.same({ 0, 1 }, { V.register({ format = 3, folder = "WoWForeverJapanese_Voice", lines = {} }) })
    assert.are.same({ 0, 1 }, { V.register({ format = 2, folder = "WoWForeverJapanese_Voice/../X", lines = {} }) })
    assert.are.same({ 0, 1 }, { V.register(pack(nil)) })
    assert.are.same({ 0, 1 }, { V.register({ format = 1, folder = "SomeOtherAddon", lines = {} }) })
    assert.is_false(V.hasPack())
  end)

  it("keys a quest field by quest id and gossip by its key, nothing else", function()
    assert.are.equal("456-description", V.packKey("quest.description", 456))
    assert.are.equal("g-0a044ece3562b58d", V.packKey("gossip", "0a044ece3562b58d"))
    assert.are.equal("b-0a044ece3562b58d", V.packKey("book", "0a044ece3562b58d"))
    assert.is_nil(V.packKey("quest.description", "456"))
    assert.is_nil(V.packKey("item.description", 4))
    assert.is_nil(V.packKey("ui", "QUEST_LOG"))
  end)

  it("voices only the offer, progress, turn-in and greeting lines", function()
    V.register(pack({ ["2-description"] = entry("2-description.mp3", DATA["quest.description"][2].ja, 4.2) }))
    local path, seconds = V.decide("questframe.detail", "description", "quest.description", 2)
    assert.are.equal("Interface\\AddOns\\WoWForeverJapanese_Voice\\Sound\\2-description.mp3", path)
    assert.are.equal(4.2, seconds)
    assert.are.same({ nil, "kind" }, { V.decide("questframe.detail", "objectives", "quest.objectives", 2) })
    assert.are.same({ nil, "kind" }, { V.decide("questframe.detail", "title", "quest.title", 2) })
    assert.are.same({ nil, "kind" }, { V.decide("gossip", "option1", "gossip", "0123456789abcdef") })
    assert.are.same({ nil, "kind" }, { V.decide("tooltip", "description", "quest.description", 2) })
  end)

  it("stays silent when switched off, when English is showing, and without a pack", function()
    assert.are.same({ nil, "nopack" }, { V.decide("questframe.detail", "description", "quest.description", 2) })
    V.register(pack({ ["2-description"] = entry("2-description.mp3", DATA["quest.description"][2].ja, 4.2) }))
    settings["voice.offer"] = false
    assert.are.same({ nil, "off" }, { V.decide("questframe.detail", "description", "quest.description", 2) })
    settings["voice.offer"], settings["voice.enabled"] = true, false
    assert.are.same({ nil, "off" }, { V.decide("questframe.detail", "description", "quest.description", 2) })
    settings["voice.enabled"] = true
    revealed = true
    assert.are.same({ nil, "english" }, { V.decide("questframe.detail", "description", "quest.description", 2) })
    revealed, enabled = false, false
    assert.are.same({ nil, "english" }, { V.decide("questframe.detail", "description", "quest.description", 2) })
  end)

  it("a line with no file, or whose Japanese changed since the file was made, plays nothing", function()
    V.register(pack({ ["2-description"] = entry("2-description.mp3", "an older Japanese", 4.2) }))
    assert.are.same({ nil, "stale" }, { V.decide("questframe.detail", "description", "quest.description", 2) })
    assert.are.same({ nil, "missing" }, { V.decide("questframe.progress", "progress", "quest.progress", 2) })
    assert.are.equal(1, V.counts.stale)
    assert.are.equal(1, V.counts.missing)
    assert.are.equal(0, V.counts.matched)
  end)

  it("hashes the shipped Japanese with its tokens unfilled", function()
    -- the pipeline speaks {name} as 冒険者 but hashes the text as shipped, so the match never depends on the player
    V.register(pack({ ["2-description"] = entry("2-description.mp3", "御機嫌よう、{name}。Silverwind Refugeへ行け。") }))
    assert.is_string((V.decide("questframe.detail", "description", "quest.description", 2)))
  end)

  local desc = DATA["quest.description"][2].ja
  local PATH = "Interface\\AddOns\\%s\\Sound\\%s"

  it("packs merge, and a pack registering again replaces only its own lines", function()
    V.register({ format = 2, folder = "WoWForeverJapanese_Voice_1", lines = { ["2-description"] = entry("a.mp3", desc, 1) } })
    V.register({ format = 2, folder = "WoWForeverJapanese_Voice_2", lines = { ["3-description"] = entry("b.mp3", "x", 1),
      ["2-progress"] = entry("c.mp3", "y", 1) } })
    assert.are.same({ WoWForeverJapanese_Voice_1 = 1, WoWForeverJapanese_Voice_2 = 2 }, V.packs())
    assert.are.equal(3, V.counts.registered)
    V.register({ format = 2, folder = "WoWForeverJapanese_Voice_2", lines = { ["3-description"] = entry("b.mp3", "x", 1) } })
    assert.are.equal(2, V.counts.registered)
    assert.are.equal(PATH:format("WoWForeverJapanese_Voice_1", "a.mp3"),
      (V.decide("questframe.detail", "description", "quest.description", 2)))
  end)

  it("a line several creatures say plays the voice of the one on screen, else its main voice", function()
    V.register({ format = 2, folder = "WoWForeverJapanese_Voice", creatures = { [10] = "deep", [11] = { "deep", "soft" } },
      lines = { ["2-description"] = { "2-description.mp3", WFJ.Hash.key(desc), 3,
        v = { deep = { "2-description_deep.mp3", 2.5 }, soft = { "2-description_soft.mp3", 2 } } } } })
    local function play(who) return { V.decide("questframe.detail", "description", "quest.description", 2, who) } end
    local F = "WoWForeverJapanese_Voice"
    assert.are.same({ PATH:format(F, "2-description_deep.mp3"), 2.5 }, play({ creature = 10 }))
    assert.are.same({ PATH:format(F, "2-description_soft.mp3"), 2 }, play({ creature = 11, sex = 3 }))
    assert.are.same({ PATH:format(F, "2-description_deep.mp3"), 2.5 }, play({ creature = 11, sex = 2 }))
    assert.are.same({ PATH:format(F, "2-description.mp3"), 3 }, play({ creature = 99 }))
    assert.are.same({ PATH:format(F, "2-description.mp3"), 3 }, play(nil))
  end)

  it("a book page is voiced on the book window and switched off by its own setting", function()
    DATA.book = { ["0a044ece3562b58d"] = { ja = "ページ", status = "." } }
    settings["voice.books"] = true
    V.register(pack({ ["b-0a044ece3562b58d"] = entry("b-0a044ece3562b58d.mp3", "ページ", 2) }))
    assert.is_string((V.decide("itemtext", "page", "book", "0a044ece3562b58d")))
    settings["voice.books"] = false
    assert.are.same({ nil, "off" }, { V.decide("itemtext", "page", "book", "0a044ece3562b58d") })
    DATA.book = nil
  end)

  it("a sectioned or missing Japanese plays nothing", function()
    V.register(pack({ ["9-description"] = { "9-description.mp3", WFJ.Hash.key("x") } }))
    assert.are.same({ nil, "notext" }, { V.decide("questframe.detail", "description", "quest.description", 9) })
  end)
end)

describe("UI/VoicePlayer: playing the pack's line in the quest window", function()
  local WFJ, S, db, sounds, stopped, timers, cvars, willPlay

  local function setQuest(id)
    Stub.quest = { id = id, title = "Sharptalon's Claw", description = "Kill Sharptalon at Silverwind Refuge.",
      objectives = "Bring Sharptalon's Claw to Senani Thunderheart.", progress = "Did you get it?",
      completion = "Well done." }
  end

  local function packLines()
    local lines = {}
    for _, k in ipairs({ { 2, "description" }, { 2, "progress" }, { 2, "completion" }, { 3, "description" } }) do
      local ja = DATA["quest." .. k[2]][k[1]].ja
      lines[k[1] .. "-" .. k[2]] = { k[1] .. "-" .. k[2] .. ".mp3", WFJ.Hash.key(ja), 3.0 }
    end
    return lines
  end

  local function runTimers()
    local due = timers
    timers = {}
    for _, t in ipairs(due) do t.fn() end
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI()
    sounds, stopped, timers, cvars, willPlay = {}, {}, {}, { Sound_EnableDialog = "1" }, true
    _G.PlaySoundFile = function(path, channel)
      sounds[#sounds + 1] = { path = path, channel = channel }
      if not willPlay then return false end
      return true, #sounds
    end
    _G.StopSound = function(handle) stopped[#stopped + 1] = handle end
    _G.C_CVar = {
      GetCVar = function(name) return cvars[name] end,
      SetCVar = function(name, value) cvars[name] = tostring(value) end,
    }
    _G.C_Timer = { After = function(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end }
    WFJ = H.loadChunks(FILES)
    S = WFJ.Settings
    WFJ.Compat.init(function(name) return _G[name] end)
    db = S.load(nil, 1, {})
    WFJ.Render.init(WFJ.Translator.new({
      enabled = function() return WFJ.State.enabled end,
      areaEnabled = WFJ.State.areaEnabled,
      modifierHeld = WFJ.Modifier.isDown,
      lookup = function(kind, id) return DATA[kind] and DATA[kind][id] end,
      marker = function(n) return S.get("marker." .. n) end,
    }))
    WFJ.Voice.init({
      lookup = function(kind, id) return DATA[kind] and DATA[kind][id] end,
      hash = WFJ.Hash.key,
      setting = S.get,
      revealed = WFJ.Modifier.isDown,
      enabled = function() return WFJ.State.enabled end,
    })
    assert.is_true(WFJ.QuestFrame.init())
    assert.is_true(WFJ.VoicePlayer.init(db))
    WFJ.Voice.register({ format = 1, folder = "WoWForeverJapanese_Voice", lines = packLines() })
    setQuest(2)
  end)

  after_each(function()
    _G.PlaySoundFile, _G.StopSound, _G.C_CVar, _G.C_Timer = nil, nil, nil, nil
  end)

  it("plays the offer on the Master channel when the window shows its Japanese, and mutes the English voice", function()
    Stub.showDetail()
    assert.are.equal(1, #sounds)
    assert.are.equal("Interface\\AddOns\\WoWForeverJapanese_Voice\\Sound\\2-description.mp3", sounds[1].path)
    assert.are.equal("Master", sounds[1].channel)
    assert.are.equal("0", cvars.Sound_EnableDialog)
    assert.is_true(db.voiceDialogMuted)
    assert.are.equal("2-description", WFJ.VoicePlayer.current())
    assert.are.equal(3.5, timers[1].delay) -- the pack's length plus the margin
  end)

  it("puts the English voice back when the line ends", function()
    Stub.showDetail()
    runTimers()
    assert.are.equal("1", cvars.Sound_EnableDialog)
    assert.is_nil(db.voiceDialogMuted)
    assert.is_nil(WFJ.VoicePlayer.current())
  end)

  it("plays progress and turn-in on their panels", function()
    Stub.showProgress()
    assert.are.equal("Interface\\AddOns\\WoWForeverJapanese_Voice\\Sound\\2-progress.mp3", sounds[1].path)
    Stub.showReward()
    assert.are.equal("Interface\\AddOns\\WoWForeverJapanese_Voice\\Sound\\2-completion.mp3", sounds[2].path)
    assert.are.same({ 1 }, stopped) -- the turn-in stopped the progress line
  end)

  it("stops when the window closes", function()
    Stub.showDetail()
    QuestFrame:Hide()
    assert.are.same({ 1 }, stopped)
    assert.are.equal("1", cvars.Sound_EnableDialog)
    assert.is_nil(WFJ.VoicePlayer.current())
    runTimers() -- the old line's end timer finds nothing to do
    assert.are.equal("1", cvars.Sound_EnableDialog)
  end)

  it("stops when the reveal key goes down, and does not start again when it comes up", function()
    Stub.showDetail()
    Stub.keys.alt = true
    WFJ.Modifier.refresh()
    assert.are.same({ 1 }, stopped)
    Stub.keys.alt = false
    WFJ.Modifier.refresh() -- a refresh shows the Japanese again but never starts a line
    assert.are.equal(1, #sounds)
  end)

  it("never plays while the reveal key is held", function()
    Stub.keys.alt = true
    WFJ.Modifier.refresh()
    Stub.showDetail()
    assert.are.equal(0, #sounds)
    Stub.keys.alt = false
  end)

  it("stops when translation or voice is switched off", function()
    Stub.showDetail()
    S.set("enabled", false)
    assert.are.same({ 1 }, stopped)
    S.set("enabled", true)
    setQuest(3)
    Stub.showDetail()
    assert.are.equal(2, #sounds)
    S.set("voice.enabled", false)
    assert.are.same({ 1, 2 }, stopped)
    setQuest(2)
    Stub.showDetail()
    assert.are.equal(2, #sounds) -- off: nothing new
  end)

  it("a kind switched off is not voiced", function()
    S.set("voice.offer", false)
    Stub.showDetail()
    assert.are.equal(0, #sounds)
    Stub.showProgress()
    assert.are.equal(1, #sounds)
  end)

  it("a new quest's line replaces the one playing; the same line shown again is not restarted", function()
    Stub.showDetail()
    WFJ.VoicePlayer.onShown("questframe.detail", "description", "quest.description", 2)
    assert.are.equal(1, #sounds)
    setQuest(3)
    Stub.showDetail()
    assert.are.equal(2, #sounds)
    assert.are.same({ 1 }, stopped)
    assert.are.equal("3-description", WFJ.VoicePlayer.current())
  end)

  it("leaves the English voice alone when the player had it off, or when the setting says so", function()
    cvars.Sound_EnableDialog = "0"
    Stub.showDetail()
    assert.is_nil(db.voiceDialogMuted)
    QuestFrame:Hide()
    assert.are.equal("0", cvars.Sound_EnableDialog) -- never turned on by us
    cvars.Sound_EnableDialog = "1"
    S.set("voice.muteDialog", false)
    Stub.showDetail()
    assert.are.equal("1", cvars.Sound_EnableDialog)
    assert.is_nil(db.voiceDialogMuted)
  end)

  it("a line the client refuses to play puts the English voice back at once", function()
    willPlay = false
    Stub.showDetail()
    assert.are.equal(1, #sounds)
    assert.are.equal("1", cvars.Sound_EnableDialog)
    assert.are.equal(1, WFJ.VoicePlayer.counts.refused)
    assert.is_nil(WFJ.VoicePlayer.current())
  end)

  it("a reload or crash during a line: the next load puts the English voice back", function()
    db.voiceDialogMuted = true
    cvars.Sound_EnableDialog = "0"
    local P = WFJ.VoicePlayer
    P.init(db)
    assert.are.equal("1", cvars.Sound_EnableDialog)
    assert.is_nil(db.voiceDialogMuted)
  end)

  it("logout stops the line and puts the English voice back", function()
    Stub.showDetail()
    WFJ.VoicePlayer.stop() -- what Main runs on PLAYER_LOGOUT
    assert.are.equal("1", cvars.Sound_EnableDialog)
    assert.is_nil(db.voiceDialogMuted)
  end)

  it("the button shows pause while the line plays, the play arrow once it ends, gone once the window closes", function()
    local b = WFJ.VoicePlayer.button("QuestFrame")
    assert.is_false(b:IsShown()) -- nothing played yet
    assert.are.same({ "TOPRIGHT", QuestFrame, "TOPRIGHT", -8, -31 }, b.point)
    Stub.showDetail()
    assert.is_true(b:IsShown())
    assert.are.equal("Interface\\TimeManager\\PauseButton", b.textures.normal)
    runTimers()
    assert.is_true(b:IsShown())
    assert.are.equal("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up", b.textures.normal)
    QuestFrame:Hide()
    assert.is_false(b:IsShown())
  end)

  it("a click stops the line; a second click plays it again from the start", function()
    Stub.showDetail()
    local b = WFJ.VoicePlayer.button("QuestFrame")
    b.scripts.OnClick(b)
    assert.are.same({ 1 }, stopped)
    assert.are.equal("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up", b.textures.normal)
    assert.are.equal("1", cvars.Sound_EnableDialog)
    b.scripts.OnClick(b)
    assert.are.equal(2, #sounds)
    assert.are.equal(sounds[1].path, sounds[2].path)
    assert.are.equal("Interface\\TimeManager\\PauseButton", b.textures.normal)
    assert.are.equal("0", cvars.Sound_EnableDialog)
  end)

  it("a click never plays while English is showing or voice is off", function()
    Stub.showDetail()
    local b = WFJ.VoicePlayer.button("QuestFrame")
    b.scripts.OnClick(b) -- stop
    Stub.keys.alt = true
    WFJ.Modifier.refresh()
    b.scripts.OnClick(b)
    assert.are.equal(1, #sounds)
    Stub.keys.alt = false
    WFJ.Modifier.refresh()
    S.set("voice.enabled", false)
    b.scripts.OnClick(b)
    assert.are.equal(1, #sounds)
  end)

  it("a new line of the window with no file hides the button, so it never replays the previous line", function()
    Stub.showDetail()
    local b = WFJ.VoicePlayer.button("QuestFrame")
    WFJ.Voice.register({ format = 1, folder = "WoWForeverJapanese_Voice", lines = {} })
    Stub.showProgress()
    assert.is_false(b:IsShown())
    assert.is_nil(WFJ.VoicePlayer.current())
  end)

  it("the button setting hides it", function()
    S.set("voice.button", false)
    Stub.showDetail()
    assert.are.equal(1, #sounds)
    assert.is_false(WFJ.VoicePlayer.button("QuestFrame"):IsShown())
  end)

  it("passes the NPC on screen, so a line several creatures say plays that NPC's voice", function()
    Stub.units.questnpc = { name = "Tarindrella", guid = "Creature-0-1-0-1-1992-0000ABCD" }
    WFJ.Voice.register({ format = 2, folder = "WoWForeverJapanese_Voice", creatures = { [1992] = "soft" },
      lines = { ["2-description"] = { "2-description.mp3", WFJ.Hash.key(DATA["quest.description"][2].ja), 3,
        v = { soft = { "2-description_soft.mp3", 2 } } } } })
    Stub.showDetail()
    assert.are.equal("Interface\\AddOns\\WoWForeverJapanese_Voice\\Sound\\2-description_soft.mp3", sounds[1].path)
    Stub.units.questnpc = nil
  end)

  it("a stale file stays silent and is counted", function()
    WFJ.Voice.register({ format = 1, folder = "WoWForeverJapanese_Voice",
      lines = { ["2-description"] = { "2-description.mp3", WFJ.Hash.key("older"), 3 } } })
    Stub.showDetail()
    assert.are.equal(0, #sounds)
    assert.are.equal(1, WFJ.Voice.counts.stale)
  end)
end)

describe("voice settings: shown only with a pack", function()
  it("the voice settings are hidden from lists until a pack registers", function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    local WFJ = H.loadChunks({ "Core/Const.lua", "Core/Compat.lua", "Core/State.lua", "Core/Settings.lua",
      "Core/Voice.lua", "Core/Modifier.lua" })
    WFJ.Settings.load(nil, 1, {})
    local function hiddenVoice()
      local n = 0
      for _, d in ipairs(WFJ.Settings.list()) do
        if d.id:find("^voice%.") and WFJ.Settings.isHidden(d) then n = n + 1 end
      end
      return n
    end
    assert.are.equal(8, hiddenVoice())
    WFJ.Voice.register({ format = 1, folder = "WoWForeverJapanese_Voice", lines = {} })
    assert.are.equal(0, hiddenVoice())
    assert.is_true(WFJ.Settings.get("voice.enabled")) -- on by default
    assert.is_true(WFJ.Settings.get("voice.muteDialog"))
  end)
end)
