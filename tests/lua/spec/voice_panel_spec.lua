-- The voice panel (ADR-063): the queue and the player with the panel on, the panel itself, its text, the remembered
-- speaker and the quest log's button. The player with the panel Off is voice_spec.lua.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = { "Core/Const.lua", "Core/Compat.lua", "Core/Data.lua", "Core/State.lua", "Core/Settings.lua",
  "Core/Voice.lua", "Core/Modifier.lua", "Core/Translator.lua", "Core/SurfaceState.lua", "Core/Normalize.lua",
  "Core/Hash.lua", "Core/Collector.lua", "Core/UIStringKeys.lua", "Core/UIStrings.lua", "Core/Readings.lua",
  "Core/VoiceQueue.lua", "UI/Font.lua", "UI/Render.lua", "UI/VoicePlayer.lua", "UI/VoicePanelLooks.lua",
  "UI/VoicePanelHead.lua", "UI/VoicePanelText.lua", "UI/VoicePanel.lua", "UI/ButtonText.lua", "UI/Labels.lua",
  "UI/QuestFrame.lua" }

local DATA = {
  ["quest.title"] = { [2] = { ja = "Sharptalonの鉤爪", status = "." }, [3] = { ja = "別のクエスト", status = "." } },
  ["quest.description"] = { [2] = { ja = "御機嫌よう、{name}。Silverwind Refugeへ行け。", status = "." },
    [3] = { ja = "二つ目の依頼", status = "." } },
  ["quest.objectives"] = { [2] = { ja = "Sharptalonを倒せ", status = "." } },
  ["quest.completion"] = { [2] = { ja = "よくやった", status = "." } },
  ["quest.progress"] = { [2] = { ja = "まだか？", status = "." } },
}
local EN = "Kill Sharptalon at Silverwind Refuge."
local SOUND = "Interface\\AddOns\\WoWForeverJapanese_Voice\\Sound\\%s.mp3"

-- Frame, texture and FontString methods the panel uses that the shared stub does not carry: the ones a spec reads
-- are recorded, every other one is accepted and does nothing (what the client draws is the in-game checklist's).
local NOOP = function() end
local function relax(t) return setmetatable(t, { __index = function() return NOOP end }) end
local function extendFrames()
  local create = _G.CreateFrame
  _G.CreateFrame = function(kind, name, parent, template)
    local f = create(kind, name, parent, template)
    function f:SetShown(v) if v then self:Show() else self:Hide() end end
    function f:IsMouseOver() return Stub.mouseOn == self end
    function f:ClearAllPoints() self.point = nil end
    function f:GetPoint() return "BOTTOM", nil, "BOTTOM", 10, 20 end
    if kind == "PlayerModel" then
      function f:SetUnit(u) self.unit, self.creature = u, nil end
      function f:SetCreature(id) self.creature, self.unit = id, nil end
      function f:ClearModel() self.unit, self.creature = nil, nil end
      function f:GetModelFileID() return (self.unit or self.creature) and Stub.modelFile or 0 end
    end
    local createTexture = f.CreateTexture
    function f:CreateTexture(...)
      local t = createTexture(self, ...)
      function t.SetShown(tx, v) tx.shown = v and true or false end
      return relax(t)
    end
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

local WFJ, S, db, sounds, stopped, timers, newTimers, cvars, clock

local function pack(lines)
  WFJ.Voice.register({ format = 1, folder = "WoWForeverJapanese_Voice", lines = lines })
end

local function packLines()
  local lines = {}
  for _, k in ipairs({ { 2, "description" }, { 2, "progress" }, { 2, "completion" }, { 3, "description" } }) do
    local ja = DATA["quest." .. k[2]][k[1]].ja
    lines[k[1] .. "-" .. k[2]] = { k[1] .. "-" .. k[2] .. ".mp3", WFJ.Hash.key(ja), 3.0 }
  end
  return lines
end

local function setQuest(id)
  Stub.quest = { id = id, title = "Sharptalon's Claw", description = EN,
    objectives = "Bring Sharptalon's Claw to Senani Thunderheart.", progress = "Did you get it?",
    completion = "Well done." }
end

local function runTimers()
  local due = timers
  timers = {}
  for _, t in ipairs(due) do t.fn() end
end

local function settle()
  local due = newTimers
  newTimers = {}
  for _, t in ipairs(due) do if not t.cancelled then t.fn() end end
end

local function panel() return _G.WFJVoicePanel end
local function tick(f, at)
  clock = at or clock
  f.scripts.OnUpdate(f, 0.2)
end
local function frameWith(event, parent)
  for _, fr in ipairs(Stub.frames) do
    if fr.events[event] and (parent == nil or fr.parent == parent) then return fr end
  end
end

local function setup(withPack)
  Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
  extendFrames()
  Stub.installQuestAPI(); Stub.installTooltipAPI()
  _G.UIParent = CreateFrame("Frame", "UIParent")
  sounds, stopped, timers, newTimers, cvars, clock = {}, {}, {}, {}, { Sound_EnableDialog = "1" }, 0
  Stub.mouseOn, Stub.modelFile = nil, 118355
  _G.PlaySoundFile = function(path, channel)
    sounds[#sounds + 1] = { path = path, channel = channel }
    return true, #sounds
  end
  _G.StopSound = function(handle) stopped[#stopped + 1] = handle end
  _G.C_CVar = {
    GetCVar = function(name) return cvars[name] end,
    SetCVar = function(name, value) cvars[name] = tostring(value) end,
  }
  _G.C_Timer = {
    After = function(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end,
    NewTimer = function(delay, fn)
      local t = { delay = delay, fn = fn }
      function t.Cancel(self) self.cancelled = true end
      newTimers[#newTimers + 1] = t
      return t
    end,
  }
  _G.GetTime = function() return clock end
  _G.UnitFactionGroup = function() return "Alliance" end
  _G.C_Texture = {
    GetAtlasExists = function() return true end,
    GetAtlasInfo = function() return { file = "kit", leftTexCoord = 0, rightTexCoord = 1, topTexCoord = 0,
      bottomTexCoord = 1 } end,
  }
  _G.C_TooltipInfo = { GetUnit = function() return { lines = { { leftText = "Senani" }, { leftText = "Trainer" } } } end }
  -- the quest log's details pane, for its button (VoicePlayer hooks QuestMapFrame_ShowQuestDetails at init)
  _G.QuestMapFrame = CreateFrame("Frame", "QuestMapFrame")
  QuestMapFrame.DetailsFrame = CreateFrame("Frame", nil, QuestMapFrame)
  QuestMapFrame.DetailsFrame.BackFrame = CreateFrame("Frame", nil, QuestMapFrame.DetailsFrame)
  _G.QuestMapFrame_ShowQuestDetails = function(id) QuestMapFrame.DetailsFrame.questID = id end
  WFJ = H.loadChunks(FILES)
  S = WFJ.Settings
  WFJ.Compat.init(function(name) return _G[name] end)
  db = S.load(nil, 1, {})
  WFJ.VoiceQueue.init(db)
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
  assert.is_true(WFJ.VoicePanel.init())
  if withPack then pack(packLines()) end
  setQuest(2)
end

local function teardown()
  _G.PlaySoundFile, _G.StopSound, _G.C_CVar, _G.C_Timer, _G.C_Texture, _G.C_TooltipInfo = nil, nil, nil, nil, nil, nil
  _G.UnitFactionGroup, _G.QuestMapFrame, _G.QuestMapFrame_ShowQuestDetails, _G.WFJVoicePanel = nil, nil, nil, nil
  _G.WFJVoicePanelText, _G.C_QuestLog, _G.QuestMapFrame_OpenToQuestDetails = nil, nil, nil
  Stub.units.questnpc = nil
end

describe("the voice panel without a voice pack", function()
  before_each(function() setup(false) end)
  after_each(teardown)

  it("builds no frame and lists no panel setting", function()
    Stub.showDetail()
    assert.is_nil(panel())
    for _, d in ipairs(S.list()) do
      if d.id:find("^voice%.panel") then assert.is_true(S.isHidden(d), d.id) end
    end
  end)
end)

describe("the voice player with the voice panel on", function()
  local P
  before_each(function()
    setup(true)
    P = WFJ.VoicePlayer
  end)
  after_each(teardown)

  it("a voiced line builds and shows the panel with its Japanese", function()
    assert.is_nil(panel())
    Stub.showDetail()
    local f = panel()
    assert.is_true(f:IsShown())
    assert.are.equal("御機嫌よう、Reyn。Silverwind Refugeへ行け。", f.text:GetText()) -- one page: a short first sentence
    assert.are.equal(SOUND:format("2-description"), sounds[1].path)
  end)

  it("a line shown while one plays waits its turn, once, and plays when that one ends", function()
    Stub.showDetail()
    Stub.showDetail() -- the same line again: not queued twice
    setQuest(3)
    Stub.showDetail()
    assert.are.equal(1, #sounds)
    assert.are.equal(1, #P.state().waiting)
    assert.is_true(panel().box:IsShown())
    assert.are.equal("3-description", panel().box.rows[1].key)
    runTimers()
    assert.are.equal(SOUND:format("3-description"), sounds[2].path)
    assert.are.equal(0, #P.state().waiting)
    assert.is_false(panel().box:IsShown())
  end)

  it("a click on a waiting line plays it now and drops the line it interrupts", function()
    Stub.showDetail()
    setQuest(3)
    Stub.showDetail()
    local row = panel().box.rows[1]
    row.scripts.OnClick(row)
    assert.are.equal(SOUND:format("3-description"), sounds[2].path)
    assert.are.same({ 1 }, stopped)
    assert.are.equal("3-description", P.current())
    assert.are.equal("2-description", P.state().last.key)
    runTimers()
    assert.are.equal(2, #sounds) -- the interrupted line does not come back
  end)

  it("holding the reveal key keeps the voice and shows the line's English; letting go shows the Japanese", function()
    Stub.showDetail()
    local f = panel()
    Stub.keys.alt = true
    WFJ.Modifier.refresh()
    tick(f, 0.5)
    assert.are.same({}, stopped)
    assert.are.equal("2-description", P.current())
    assert.are.equal(EN, f.text:GetText())
    Stub.keys.alt = false
    WFJ.Modifier.refresh()
    tick(f, 0.7)
    assert.are.equal("御機嫌よう、Reyn。Silverwind Refugeへ行け。", f.text:GetText())
  end)

  it("keeps reading after the window closes; with the setting off the window's line stops", function()
    Stub.showDetail()
    QuestFrame:Hide()
    assert.are.same({}, stopped)
    assert.are.equal("2-description", P.current())
    S.set("voice.panel.keep", false)
    Stub.showProgress()
    runTimers() -- the description ends; the progress line plays next
    QuestFrame:Hide()
    assert.is_nil(P.current())
  end)

  it("a loading screen ends the line and empties the queue", function()
    Stub.showDetail()
    setQuest(3)
    Stub.showDetail()
    local ev = frameWith("PLAYER_ENTERING_WORLD")
    ev:fire("PLAYER_ENTERING_WORLD")
    assert.is_nil(P.current())
    assert.are.equal(0, #P.state().waiting)
    assert.is_false(panel():IsShown())
  end)

  it("pause, resume, play again and close", function()
    Stub.showDetail()
    local f = panel()
    f.pause.scripts.OnClick(f.pause)
    assert.are.same({ 1 }, stopped)
    assert.is_true(P.state().paused)
    assert.are.equal("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up", f.pause.textures.normal)
    f.pause.scripts.OnClick(f.pause)
    assert.are.equal(2, #sounds) -- from the start: the client cannot resume a file
    f.replay.scripts.OnClick(f.replay)
    assert.are.equal(3, #sounds)
    f.close.scripts.OnClick(f.close)
    assert.is_nil(P.current())
    assert.is_false(f:IsShown())
  end)

  it("translation off or Panel size Off stops the line and hides the panel", function()
    Stub.showDetail()
    S.set("voice.panel.size", "off")
    assert.is_nil(P.current())
    assert.is_false(panel():IsShown())
    S.set("voice.panel.size", "full")
    Stub.showDetail()
    S.set("enabled", false)
    assert.is_nil(P.current())
    assert.is_false(panel():IsShown())
  end)

  it("the window's own button is hidden while the panel shows, and back once it fades", function()
    Stub.showDetail()
    local b = P.button("QuestFrame")
    assert.is_false(b:IsShown())
    runTimers() -- the line ends
    local f = panel()
    tick(f, 3.1)
    tick(f, 3.8) -- faded and hidden
    assert.is_false(f:IsShown())
    assert.is_true(b:IsShown())
  end)

  it("fades after the last line unless the mouse is on it; a fade on a paused line stays away", function()
    Stub.showDetail()
    runTimers()
    local f = panel()
    Stub.mouseOn = f
    tick(f, 5)
    tick(f, 9)
    assert.is_true(f:IsShown()) -- held while the mouse is on it
    Stub.mouseOn = nil
    tick(f, 12.1)
    tick(f, 12.8)
    assert.is_false(f:IsShown())
    -- a paused line: it fades, and a refresh does not bring it back
    Stub.showDetail()
    f.pause.scripts.OnClick(f.pause)
    tick(f, 16)
    tick(f, 17)
    assert.is_false(f:IsShown())
    WFJ.Modifier.refresh()
    WFJ.State.fire("voice")
    assert.is_false(f:IsShown())
  end)

  it("controls show only with the mouse on the panel, unless that setting is off; combat dims the panel", function()
    Stub.showDetail()
    local f = panel()
    tick(f, 0.2)
    assert.are.equal(0, f.pause.alpha)
    Stub.mouseOn = f
    tick(f, 0.4)
    assert.are.equal(1, f.pause.alpha)
    Stub.mouseOn = nil
    S.set("voice.panel.hoverButtons", false)
    tick(f, 0.6)
    assert.are.equal(1, f.pause.alpha)
    frameWith("PLAYER_REGEN_DISABLED", f):fire("PLAYER_REGEN_DISABLED")
    assert.are.equal(0.4, f.alpha)
    frameWith("PLAYER_REGEN_DISABLED", f):fire("PLAYER_REGEN_ENABLED")
    assert.are.equal(1, f.alpha)
  end)

  it("the head comes from the NPC on screen; the window's NPC is remembered for each quest line", function()
    Stub.units.questnpc = { name = "Senani Thunderheart", guid = "Creature-0-1-0-1-1992-0000ABCD" }
    Stub.showDetail()
    settle()
    assert.are.equal("questnpc", panel().head.model.unit)
    assert.are.same({ c = 1992, s = 2, n = "Senani Thunderheart", t = "Trainer" }, db.voiceSpeakers["2-description"])
    assert.are.equal("Senani Thunderheart", panel().name:GetText())
    assert.are.equal("<Trainer>", panel().title:GetText())
    S.set("enabled", false) -- remembered with translation off too
    Stub.showProgress()
    assert.are.equal(1992, db.voiceSpeakers["2-progress"].c)
  end)

  it("a quest offered by a player is not remembered", function()
    Stub.units.questnpc = { name = "Reyn", guid = "Player-4372-0ABCDEF1" }
    Stub.showDetail()
    assert.is_nil(db.voiceSpeakers)
  end)

  it("the quest log's button plays the quest's offer with the NPC who offered it, then pauses and resumes",
    function()
    -- the details pane shows quest 2 (UI/QuestMap's records)
    local fs = Stub.fontString(EN)
    WFJ.Render.show("questmap.info", "description", fs, EN, "quests", "quest.description", 2, { live = EN })
    local title = Stub.fontString("Sharptalon's Claw")
    WFJ.Render.show("questmap.info", "title", title, "Sharptalon's Claw", "quests", "quest.title", 2)
    db.voiceSpeakers = { ["2-description"] = { c = 1992, s = 2, n = "Senani Thunderheart", t = "Trainer" } }
    QuestMapFrame_ShowQuestDetails(2)
    local b
    for _, fr in ipairs(Stub.frames) do
      if fr.parent == QuestMapFrame.DetailsFrame.BackFrame and fr.kind == "Button" then b = fr end
    end
    assert.is_true(b:IsShown())
    b.scripts.OnClick(b)
    assert.are.equal(SOUND:format("2-description"), sounds[1].path)
    assert.are.equal(1992, panel().head.model.creature) -- no NPC on screen: by creature id
    assert.are.equal("Senani Thunderheart", panel().name:GetText())
    b.scripts.OnClick(b)
    assert.is_true(P.state().paused)
    b.scripts.OnClick(b)
    assert.are.equal(2, #sounds)
    -- nothing remembered: the quest's title and no head
    db.voiceSpeakers = nil
    P.clear()
    b.scripts.OnClick(b)
    assert.are.equal("Sharptalonの鉤爪", panel().name:GetText())
    assert.is_nil(panel().head.model.creature)
  end)

  it("the whole-text button opens the quest in the log when it is there, else a window, and prints nothing",
    function()
    local opened
    _G.C_QuestLog = { GetLogIndexForQuestID = function(id) return id == 2 and 1 or nil end }
    _G.QuestMapFrame_OpenToQuestDetails = function(id) opened = id end
    Stub.showDetail()
    local f = panel()
    f.textButton.scripts.OnClick(f.textButton)
    assert.are.equal(2, opened)
    assert.is_nil(_G.WFJVoicePanelText)
    S.set("voice.panel.questLog", false)
    f.textButton.scripts.OnClick(f.textButton)
    assert.is_true(_G.WFJVoicePanelText:IsShown())
    assert.are.equal("御機嫌よう、Reyn。Silverwind Refugeへ行け。", _G.WFJVoicePanelText.text:GetText())
    f.textButton.scripts.OnClick(f.textButton) -- a second press closes it
    assert.is_false(_G.WFJVoicePanelText:IsShown())
    assert.are.same({}, Stub.prints)
  end)

  it("/wfj panel reset puts it back at the bottom centre; nothing else is a panel command", function()
    local said = {}
    local function say(fmt, ...) said[#said + 1] = fmt:format(...) end
    WFJ.VoiceQueue.opt.point = { "TOP", "TOP", 0, -50 }
    WFJ.VoicePanel.command({ "reset" }, say)
    assert.is_nil(WFJ.VoiceQueue.opt.point)
    WFJ.VoicePanel.command({ "look", "2" }, say)
    assert.are.equal("panel: /wfj panel reset puts the voice panel back at the bottom centre", said[#said])
  end)
end)

describe("Core/VoiceQueue", function()
  local Q
  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    WFJ = H.loadChunks({ "Core/Const.lua", "Core/State.lua", "Core/Settings.lua", "Core/VoiceQueue.lua" })
    S, Q = WFJ.Settings, WFJ.VoiceQueue
  end)

  it("keeps order, never holds a key twice, puts a line in front, drops a window's lines", function()
    S.load(nil, 1, {})
    Q.init({})
    assert.is_true(Q.push({ key = "a", window = "QuestFrame" }))
    assert.is_false(Q.push({ key = "a", window = "QuestFrame" }))
    Q.push({ key = "b", window = "GossipFrame" })
    Q.push({ key = "c", window = "QuestFrame" })
    Q.front({ key = "c", window = "QuestFrame" })
    assert.are.same({ "c", "a", "b" }, { Q.items[1].key, Q.items[2].key, Q.items[3].key })
    assert.is_true(Q.dropWindow("QuestFrame"))
    assert.are.same({ "b" }, { Q.items[1].key })
    Q.clear()
    assert.are.equal(0, Q.size())
  end)

  it("maps Panel size and style to the four looks, and Off to the panel off with its size remembered", function()
    local saved = S.load(nil, 1, {})
    Q.init(saved)
    assert.are.equal(4, Q.opt.look) -- Full, Parchment by default
    S.set("voice.panel.size", "strip")
    assert.are.equal(5, Q.opt.look)
    S.set("voice.panel.style", "dark")
    assert.are.equal(3, Q.opt.look)
    S.set("voice.panel.size", "full")
    assert.are.equal(1, Q.opt.look)
    S.set("voice.panel.size", "strip")
    Q.opt.on = false
    assert.are.equal("off", S.get("voice.panel.size"))
    Q.opt.on = true
    assert.are.equal("strip", S.get("voice.panel.size"))
  end)

  it("an earlier build's switches carry into the dropdowns once and are dropped with the retired values", function()
    local saved = S.load({ schema = 1, settings = { ["voice.panel.strip"] = true, ["voice.panel.parchment"] = false,
      ["voice.panel.queueBox"] = true, ["voice.panel.ruby"] = true } }, 1, {})
    saved.voicePanel = { zoom = 1.2, queue = "box", point = { "TOP", "TOP", 0, -40 } }
    Q.init(saved)
    assert.are.equal("strip", S.get("voice.panel.size"))
    assert.are.equal("dark", S.get("voice.panel.style"))
    for _, id in ipairs({ "voice.panel.strip", "voice.panel.parchment", "voice.panel.queueBox", "voice.panel.ruby" }) do
      assert.is_nil(saved.settings[id], id)
    end
    assert.is_nil(saved.voicePanel.zoom)
    assert.is_nil(saved.voicePanel.queue)
    assert.are.same({ "TOP", "TOP", 0, -40 }, Q.opt.point)
  end)
end)

describe("UI/VoicePanelText: pages and their words", function()
  local T
  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    WFJ = H.loadChunks({ "Core/Const.lua", "Core/Compat.lua", "Core/Data.lua", "Core/Readings.lua", "UI/Font.lua",
      "UI/VoicePanelText.lua" })
    T = WFJ.VoicePanelText
  end)

  it("splits after 。！？ and line breaks, joins a short sentence to the next, and gives each page its share", function()
    local ja = "これは最初のとても長い文です。短い。これは三つ目の文で、少し長いです！"
    local pages, starts, offsets = T.paginate(ja)
    assert.are.same({ "これは最初のとても長い文です。", "短い。これは三つ目の文で、少し長いです！" }, pages)
    assert.are.equal(0, starts[1])
    assert.is_true(starts[2] > 0.3 and starts[2] < 0.6)
    assert.are.equal(1, offsets[1])
    assert.are.equal(#pages[1] + 1, offsets[2])
    assert.are.same({ "" }, (T.paginate("")))
  end)

  it("a page's words are found in the whole line: an earlier sentence's word never steals the cursor", function()
    WFJ.Data.add("reading", { ["gossip:k"] = { text = "光=ひかり=1 あなた=あなた=2 共=とも=3 あります=あります=4 "
      .. "ように=ように=5 今日=きょう=6 何か=なにか=7 お手伝い=おてつだい=8 できる=できる=9 こと=こと=10 "
      .. "あります=あります=11" } })
    local item = { kind = "gossip", id = "k",
      ja = "光があなたと共にありますように、Padinnann。今日は何かお手伝いできることはありますか？" }
    local pages, _, offsets = T.paginate(item.ja)
    local words = {}
    for _, sp in ipairs(T.pageSpans(item, offsets[2], pages[2])) do words[#words + 1] = sp.word end
    assert.are.same({ "今日", "何か", "お手伝い", "できる", "こと", "あります" }, words)
    assert.are.equal(1, #WFJ.Readings.lookup("gossip", "k", pages[2])) -- on its own: one word
  end)
end)
