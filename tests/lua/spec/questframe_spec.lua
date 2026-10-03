local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = { "Core/Const.lua", "Core/Compat.lua", "Core/State.lua", "Core/Settings.lua", "Core/Modifier.lua",
  "Core/Translator.lua", "Core/SurfaceState.lua", "Core/Normalize.lua", "Core/Hash.lua",
  "Core/Collector.lua", "Core/UIStringKeys.lua",
  "Core/UIStrings.lua", "UI/Font.lua", "UI/Render.lua", "UI/ButtonText.lua", "UI/Labels.lua",
  "UI/QuestFrame.lua" }

-- The six widgets a quest surface may write. Everything else the stub creates is a decoy.
local ALLOWED = {
  QuestInfoTitleHeader = true, QuestInfoDescriptionText = true, QuestInfoObjectivesText = true,
  QuestInfoRewardText = true, QuestProgressTitleText = true, QuestProgressText = true,
}

-- lookup fixture keyed like the shipped data: "quest.<field>" → id → { ja, status }
local DATA = {
  ["quest.title"] = { [2] = { ja = "Sharptalonの鉤爪", status = "." } },
  ["quest.description"] = { [2] = { ja = "Silverwind Refugeの説明文", status = "." } },
  ["quest.objectives"] = { [2] = { ja = "Sharptalonを倒せ", status = "s" } },
  ["quest.completion"] = { [2] = { ja = "よくやった", status = "." } },
  ["quest.progress"] = { [2] = { ja = "まだか？", status = "." } },
}

local DETAIL, PROGRESS, REWARD = "questframe.detail", "questframe.progress", "questframe.reward"
local MORPHEUS, FRIZ = { "Fonts\\MORPHEUS.TTF", 18, "" }, { "Fonts\\FRIZQT__.TTF", 13, "" }

describe("UI/QuestFrame: accept / progress / turn-in windows", function()
  local WFJ, S, SS, QF, lookups

  local function setQuest(id)
    Stub.quest = { id = id, title = "Sharptalon's Claw", description = "Kill Sharptalon at Silverwind Refuge.",
      objectives = "Bring Sharptalon's Claw to Senani Thunderheart.", progress = "Did you get it?",
      completion = "Well done." }
  end

  -- Snapshot the client's own SetText counts so a spec can assert the addon added none.
  local function counts()
    local c = {}
    for _, fs in ipairs(Stub.fontStrings) do c[fs] = { fs.calls.SetText, fs.calls.SetFont } end
    return c
  end

  local function total()
    return SS.count(DETAIL) + SS.count(PROGRESS) + SS.count(REWARD)
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    S, SS, QF = WFJ.Settings, WFJ.SurfaceState, WFJ.QuestFrame
    WFJ.Compat.init(function(name) return _G[name] end)
    S.load(nil, 1, {})
    lookups = {}
    WFJ.Render.init(WFJ.Translator.new({
      enabled = function() return WFJ.State.enabled end,
      areaEnabled = WFJ.State.areaEnabled,
      modifierHeld = WFJ.Modifier.isDown,
      lookup = function(kind, id)
        lookups[#lookups + 1] = { kind, id }
        return DATA[kind] and DATA[kind][id]
      end,
      marker = function(n) return S.get("marker." .. n) end,
    }))
    assert.is_true(QF.init())
    setQuest(2)
  end)

  after_each(function()
    -- no FontString outside the six ever received a SetText from the addon. The client replay writes only
    -- the six too, so any decoy with a write is ours.
    for _, fs in ipairs(Stub.fontStrings) do
      if fs.name and not ALLOWED[fs.name] then
        assert.are.equal(0, fs.calls.SetText, "addon wrote to " .. fs.name)
        assert.are.equal(0, fs.calls.SetFont, "addon set a font on " .. fs.name)
      end
    end
  end)

  it("a conditional description (this character's wording) is its keyed text, not the quest's own", function()
    DATA.gossip = { k1 = { ja = "条件付きの説明文", status = "." } }
    WFJ.ShippedGossipKey = function(text) if text == Stub.quest.description then return "k1" end end
    Stub.showDetail()
    assert.are.equal("条件付きの説明文", QuestInfoDescriptionText:GetText())
    assert.are.equal("gossip", SS.get(DETAIL, "description").meta.kind)
    assert.are.equal("Sharptalonの鉤爪", QuestInfoTitleHeader:GetText()) -- the other fields by the quest id
    WFJ.ShippedGossipKey, DATA.gossip = nil, nil
  end)

  it("a repeated quest's progress with no Japanese of its own takes the text keyed by its English", function()
    DATA.gossip = { kp = { ja = "良い焚き火は、あらゆる良いキャンプの土台です。", status = "." } }
    local recorded = {}
    local record = WFJ.Collector.record
    WFJ.Collector.record = function(kind, id, field, en) recorded[#recorded + 1] = { kind, id, field, en } end
    WFJ.ShippedGossipKey = function(text) if text == "A good campfire is the foundation to any good camp." then
      return "kp" end end
    WFJ.IsQuestFieldEnglish = function(id) return id == 2 end -- quest 2 has its own translation
    setQuest(9)
    Stub.quest.progress = "A good campfire is the foundation to any good camp."
    Stub.showProgress()
    assert.are.equal("良い焚き火は、あらゆる良いキャンプの土台です。", QuestProgressText:GetText())
    assert.are.same({ "quest", 9, "progress", "A good campfire is the foundation to any good camp." }, recorded[2])
    -- the quest's own translation wins where it has one
    setQuest(2)
    Stub.quest.progress = "Did you get it?"
    WFJ.ShippedGossipKey = function() return "kp" end
    Stub.showProgress()
    assert.are.equal("まだか？", QuestProgressText:GetText())
    WFJ.ShippedGossipKey, WFJ.IsQuestFieldEnglish, DATA.gossip = nil, nil, nil
    WFJ.Collector.record = record
  end)

  it("detail window translates title / description / objectives by field with the API id; refit runs",
  function()
    Stub.showDetail()
    assert.are.equal("Sharptalonの鉤爪", QuestInfoTitleHeader:GetText())
    assert.are.equal("Silverwind Refugeの説明文", QuestInfoDescriptionText:GetText())
    assert.are.equal("Sharptalonを倒せ", QuestInfoObjectivesText:GetText()) -- no inline marker: the banner has it
    assert.are.equal(WFJ.MARKER.stale, QF.banner:GetText())
    assert.is_true(QF.banner:IsShown())
    assert.are.same({ WFJ.Font.PATH, 18, "" }, { QuestInfoTitleHeader:GetFont() })
    assert.are.same({ WFJ.Font.PATH, 13, "" }, { QuestInfoDescriptionText:GetFont() })
    for _, key in ipairs({ "title", "description", "objectives" }) do
      local rec = SS.get(DETAIL, key)
      assert.is_table(rec, key)
      assert.are.equal("quest." .. key, rec.meta.kind)
      assert.are.equal(2, rec.meta.id)
    end
    assert.are.equal(0, SS.count(REWARD) + SS.count(PROGRESS))
    assert.is_true(QuestDetailScrollFrame.calls.UpdateScrollChildRect >= 1)
    assert.are.equal(0, QuestRewardScrollFrame.calls.UpdateScrollChildRect)
    assert.are.same({ "quest.title", 2 }, lookups[1])
  end)

  it("a reward redraw (item data arriving on a first open) keeps the Japanese prose and the banner", function()
    Stub.showDetail()
    QF.onShowRewards()
    assert.are.equal("Sharptalonの鉤爪", QuestInfoTitleHeader:GetText())
    assert.are.equal("Silverwind Refugeの説明文", QuestInfoDescriptionText:GetText())
    assert.are.equal("Sharptalonを倒せ", QuestInfoObjectivesText:GetText())
    assert.are.equal(3, SS.count(DETAIL))
    assert.are.equal(WFJ.MARKER.stale, QF.banner:GetText())
    -- the records still release to the client's English
    QuestFrame:Hide()
    assert.are.equal("Sharptalon's Claw", QuestInfoTitleHeader:GetText())

    Stub.showReward()
    QF.onShowRewards()
    assert.are.equal("Sharptalonの鉤爪", QuestInfoTitleHeader:GetText())
    assert.are.equal("よくやった", QuestInfoRewardText:GetText())
  end)

  it("a redraw after the client wrote another quest on the same widgets translates the new quest", function()
    Stub.showDetail()
    setQuest(3)
    Stub.quest.title = "Another Quest"
    QuestInfoTitleHeader:SetText("Another Quest") -- the client's writer, without our hook
    QF.onShowRewards()
    assert.are.equal("Another Quest", QuestInfoTitleHeader:GetText())
    assert.are.equal(3, SS.get(DETAIL, "title").meta.id) -- the new quest's record, not the old one kept
  end)

  it("progress (through the panel's OnShow) then reward: five fields on two surfaces", function()
    Stub.showProgress()
    assert.are.equal("Sharptalonの鉤爪", QuestProgressTitleText:GetText())
    assert.are.equal("まだか？", QuestProgressText:GetText())
    assert.are.equal(WFJ.Font.PATH, (QuestProgressTitleText:GetFont()))
    assert.are.equal(2, SS.count(PROGRESS))
    assert.is_true(QuestProgressScrollFrame.calls.UpdateScrollChildRect >= 1)
    assert.is_nil(Stub.hooks.QuestFrameProgressPanel_OnShow) -- never hooked as a global (XML-bound)

    Stub.showReward()
    assert.are.equal("Sharptalonの鉤爪", QuestInfoTitleHeader:GetText())
    assert.are.equal("よくやった", QuestInfoRewardText:GetText())
    assert.are.equal(WFJ.Font.PATH, (QuestInfoTitleHeader:GetFont()))
    assert.are.equal(2, SS.count(REWARD))
    assert.is_true(QuestRewardScrollFrame.calls.UpdateScrollChildRect >= 1)
  end)

  -- ADR-019: every quest field record carries the API English as ctx.live for the live check.
  it("detail, progress and reward records carry the API English as ctx.live", function()
    Stub.showDetail()
    assert.are.equal("Sharptalon's Claw", SS.get(DETAIL, "title").meta.ctx.live)
    assert.are.equal(Stub.quest.description, SS.get(DETAIL, "description").meta.ctx.live)
    assert.are.equal(Stub.quest.objectives, SS.get(DETAIL, "objectives").meta.ctx.live)
    Stub.showProgress()
    assert.are.equal("Did you get it?", SS.get(PROGRESS, "progress").meta.ctx.live)
    Stub.showReward()
    assert.are.equal("Well done.", SS.get(REWARD, "completion").meta.ctx.live)
  end)

  it("the reward window's stale banner follows the live check (match → none, mismatch → shown)", function()
    WFJ.Settings.set("marker.missing", false) -- on by default; this test reads the text, not the marker
    local function h1(t) return (WFJ.Hash.h32x2(WFJ.Normalize.v1(t))) end
    local entry = { ja = "よくやった", status = ".", h1 = h1("Well done.") }
    WFJ.Render.init(WFJ.Translator.new({
      enabled = function() return WFJ.State.enabled end,
      areaEnabled = WFJ.State.areaEnabled,
      modifierHeld = WFJ.Modifier.isDown,
      lookup = function(kind, id) return kind == "quest.completion" and id == 2 and entry or nil end,
      marker = function(n) return S.get("marker." .. n) end,
      fingerprints = function(t) return { h1(t) } end,
    }))
    Stub.showReward()
    assert.are.equal("よくやった", QuestInfoRewardText:GetText())
    assert.is_false(QF.banner:IsShown())
    Stub.quest.completion = "Well done, hero."
    Stub.showReward()
    assert.are.equal("よくやった", QuestInfoRewardText:GetText())
    assert.are.equal(WFJ.MARKER.stale, QF.banner:GetText())
    assert.is_true(QF.banner:IsShown())
  end)

  it("showing a panel forgets the previous one: its widgets return to the client's text and font",
  function()
    Stub.showProgress()
    Stub.showReward()
    assert.are.equal(0, SS.count(PROGRESS))
    assert.are.equal("Sharptalon's Claw", QuestProgressTitleText:GetText()) -- our Japanese was still there: put back
    assert.are.equal("Did you get it?", QuestProgressText:GetText())
    assert.are.same(MORPHEUS, { QuestProgressTitleText:GetFont() })
    assert.are.same(FRIZ, { QuestProgressText:GetFont() })
    -- the modifier now touches only the reward panel
    local before = counts()
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal(before[QuestProgressTitleText][1], QuestProgressTitleText.calls.SetText)
    assert.are.equal("Sharptalon's Claw", QuestInfoTitleHeader:GetText())
    Stub.keys.alt = false; WFJ.Modifier.refresh()

    QuestFrame:Hide()
    for _, fs in ipairs({ QuestInfoTitleHeader, QuestInfoRewardText, QuestProgressTitleText, QuestProgressText }) do
      assert.are.equal(FRIZ[1] == select(1, fs:GetFont()) or MORPHEUS[1] == select(1, fs:GetFont()), true, fs.name)
    end
    assert.are.equal("Sharptalon's Claw", QuestInfoTitleHeader:GetText())
    assert.are.equal("Well done.", QuestInfoRewardText:GetText())
    assert.are.equal(0, total())
  end)

  it("modifier and toggles restore / reapply; nothing written while held", function()
    Stub.showDetail()
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal("Sharptalon's Claw", QuestInfoTitleHeader:GetText())
    assert.are.equal("Kill Sharptalon at Silverwind Refuge.", QuestInfoDescriptionText:GetText())
    assert.are.equal("Bring Sharptalon's Claw to Senani Thunderheart.", QuestInfoObjectivesText:GetText())
    assert.are.same(MORPHEUS, { QuestInfoTitleHeader:GetFont() })
    assert.are.same(FRIZ, { QuestInfoDescriptionText:GetFont() })

    -- re-running the client's write for the same quest while held: the client writes, we add nothing
    local before = counts()
    Stub.showDetail()
    for _, fs in ipairs({ QuestInfoTitleHeader, QuestInfoDescriptionText, QuestInfoObjectivesText }) do
      assert.are.equal(before[fs][1] + 1, fs.calls.SetText, fs.name) -- exactly the client's own SetText
      assert.are.equal(before[fs][2], fs.calls.SetFont, fs.name)
    end

    Stub.keys.alt = false; WFJ.Modifier.refresh()
    assert.are.equal("Sharptalonの鉤爪", QuestInfoTitleHeader:GetText())
    S.set("area.quests", false)
    assert.are.equal("Sharptalon's Claw", QuestInfoTitleHeader:GetText())
    assert.are.equal("Kill Sharptalon at Silverwind Refuge.", QuestInfoDescriptionText:GetText())
    S.set("area.quests", true)
    assert.are.equal("Silverwind Refugeの説明文", QuestInfoDescriptionText:GetText())
    S.set("enabled", false)
    assert.are.equal("Kill Sharptalon at Silverwind Refuge.", QuestInfoDescriptionText:GetText())
    S.set("enabled", true)
    assert.are.equal("Silverwind Refugeの説明文", QuestInfoDescriptionText:GetText())
  end)

  it("QuestFrame:Hide() releases: every widget byte-identical to the client's text and font", function()
    Stub.showDetail()
    QuestFrame:Hide()
    assert.are.equal(0, total())
    assert.are.equal("Sharptalon's Claw", QuestInfoTitleHeader:GetText())
    assert.are.equal("Kill Sharptalon at Silverwind Refuge.", QuestInfoDescriptionText:GetText())
    assert.are.equal("Bring Sharptalon's Claw to Senani Thunderheart.", QuestInfoObjectivesText:GetText())
    assert.are.same(MORPHEUS, { QuestInfoTitleHeader:GetFont() })
    assert.are.same(FRIZ, { QuestInfoDescriptionText:GetFont() })
    assert.are.same(FRIZ, { QuestInfoObjectivesText:GetFont() })
    -- after release the modifier does nothing to these widgets
    local before = counts()
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal(before[QuestInfoTitleHeader][1], QuestInfoTitleHeader.calls.SetText)
  end)

  it("the banner sits in the band of the layout the client loaded (Forever: the modern QuestFrame)", function()
    -- the vanilla QuestFrame: the band between the NPC name and the parchment, verified in game
    assert.are.same({ "TOP", QuestFrame, "TOP", 0, -52 }, QF.bannerFrame.point)
    assert.are.equal(300, QF.banner.width)
    -- the mainline ButtonFrameTemplate (Forever): its parchment starts at -62, so the banner takes the stone strip
    -- right of the portrait, where the gossip window's banner sits
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI()
    rawset(_G.QuestFrame, "TopTileStreaks", {})
    local W = H.loadChunks(FILES)
    W.Compat.init(function(name) return _G[name] end)
    W.Settings.load(nil, 1, {})
    W.Render.init(W.Translator.new({
      enabled = function() return true end, areaEnabled = function() return true end,
      modifierHeld = function() return false end, lookup = function() return nil end,
      marker = function() return false end,
    }))
    assert.is_true(W.QuestFrame.init())
    assert.are.same({ "TOP", _G.QuestFrame, "TOP", 20, -36 }, W.QuestFrame.bannerFrame.point)
    assert.are.equal(230, W.QuestFrame.banner.width)
  end)

  it("an untranslated quest is left untouched; the missing marker rides the live English", function()
    WFJ.Settings.set("marker.missing", false) -- on by default; this test reads the text, not the marker
    setQuest(999)
    local before = counts()
    Stub.showDetail()
    for _, fs in ipairs({ QuestInfoTitleHeader, QuestInfoDescriptionText, QuestInfoObjectivesText }) do
      assert.are.equal(before[fs][1] + 1, fs.calls.SetText, fs.name) -- the client's write only
      assert.are.equal(before[fs][2], fs.calls.SetFont, fs.name)
    end
    assert.are.equal("Sharptalon's Claw", QuestInfoTitleHeader:GetText())
    assert.are.equal(3, SS.count(DETAIL)) -- captured, never written

    assert.is_false(QF.banner:IsShown()) -- marker off: nothing on screen
    S.set("marker.missing", true)
    assert.are.equal("Sharptalon's Claw", QuestInfoTitleHeader:GetText()) -- the English is never touched …
    assert.are.same(MORPHEUS, { QuestInfoTitleHeader:GetFont() }) -- … nor its font
    assert.are.equal(WFJ.MARKER.missing, QF.banner:GetText()) -- the message sits in the band under the NPC name
    assert.is_true(QF.banner:IsShown())
    assert.are.same({ WFJ.Font.PATH, 18 - 4, "" }, { QF.banner:GetFont() })
    assert.are.equal(QuestFrame, QF.bannerFrame.parent) -- on our own frame …
    assert.is_true(QF.bannerFrame:GetFrameLevel() > QuestFrame:GetFrameLevel() + 1) -- … raised above the panels
    S.set("marker.missing", false)
    assert.is_false(QF.banner:IsShown())
    S.set("marker.missing", true)
    QF.release()
    assert.is_false(QF.banner:IsShown()) -- closing the window clears it
    S.set("marker.missing", false)
  end)

  it("a translated quest followed by an untranslated one on the same widgets → English, original font",
  function()
    Stub.showDetail()
    assert.are.equal(WFJ.Font.PATH, (QuestInfoDescriptionText:GetFont()))
    setQuest(999)
    Stub.quest.description = "A different quest."
    Stub.showDetail()
    assert.are.equal("A different quest.", QuestInfoDescriptionText:GetText())
    assert.are.same(FRIZ, { QuestInfoDescriptionText:GetFont() })
    assert.are.same(MORPHEUS, { QuestInfoTitleHeader:GetFont() })
  end)

  it("GetQuestID of 0 or nil creates no records and drops the previous quest's", function()
    setQuest(0)
    Stub.showDetail()
    assert.are.equal(0, total())
    Stub.quest.id = nil
    Stub.showDetail()
    assert.are.equal(0, total())

    -- translated detail, then the client shows a detail whose id is 0: the old records must not survive
    setQuest(2)
    Stub.showDetail()
    assert.are.equal("Sharptalonの鉤爪", QuestInfoTitleHeader:GetText())
    setQuest(0)
    Stub.quest.title = "Unknown quest"
    Stub.showDetail()
    assert.are.equal(0, total())
    assert.are.equal("Unknown quest", QuestInfoTitleHeader:GetText())
    assert.are.same(MORPHEUS, { QuestInfoTitleHeader:GetFont() }) -- carried font reset
    local n = QuestInfoTitleHeader.calls.SetText
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    assert.are.equal(n, QuestInfoTitleHeader.calls.SetText) -- nothing restored over the client's text
    assert.are.equal("Unknown quest", QuestInfoTitleHeader:GetText())
  end)

  it("a decorated widget is skipped and its stale record dropped; the other fields translate",
  function()
    Stub.showDetail()
    -- the client's writer runs again: description / objectives get their English back as usual, but the header
    -- comes out decorated (as the log does for a failed quest)
    local header, desc, obj = QuestInfoTitleHeader, QuestInfoDescriptionText, QuestInfoObjectivesText
    header:SetText("Sharptalon's Claw (decorated)")
    desc:SetText(Stub.quest.description)
    obj:SetText(Stub.quest.objectives)
    QF.onDisplay(QUEST_TEMPLATE_DETAIL, QuestDetailScrollChildFrame) -- our hook, on the decorated state
    assert.are.equal("Sharptalon's Claw (decorated)", header:GetText())
    assert.is_nil(SS.get(DETAIL, "title"))
    assert.are.same(MORPHEUS, { header:GetFont() }) -- our font came off with the dropped record
    assert.is_table(SS.get(DETAIL, "description"))
    assert.are.equal("Silverwind Refugeの説明文", QuestInfoDescriptionText:GetText())
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal("Sharptalon's Claw (decorated)", header:GetText()) -- never restored over the client's text
    assert.are.equal("Kill Sharptalon at Silverwind Refuge.", QuestInfoDescriptionText:GetText())
  end)

  it("empty API English is skipped (no record, no write, no missing marker)", function()
    S.set("marker.missing", true)
    Stub.quest.progress = ""
    Stub.showProgress()
    assert.is_nil(SS.get(PROGRESS, "progress"))
    assert.are.equal("", QuestProgressText:GetText())
    assert.are.equal(1, QuestProgressText.calls.SetText) -- the client's own
    assert.are.equal("Sharptalonの鉤爪", QuestProgressTitleText:GetText())
  end)

  it("log / map templates and unknown parents are not ours", function()
    assert.are.equal(0, QF.onDisplay(QUEST_TEMPLATE_LOG, QuestDetailScrollChildFrame))
    assert.are.equal(0, QF.onDisplay(QUEST_TEMPLATE_DETAIL, {}))
    assert.are.equal(0, QF.onDisplay(nil, nil))
    assert.are.equal(0, total())
  end)

  it("init is idempotent and degrades when the progress panel is missing (reported by Compat.unresolved)",
  function()
    assert.is_false(QF.init()) -- already hooked
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI()
    _G.QuestFrameProgressPanel = nil
    local ns = H.loadChunks(FILES)
    ns.Compat.init(function(name) return _G[name] end)
    assert.has_no.errors(function() ns.QuestFrame.init() end)
    assert.is_truthy(table.concat(ns.Compat.unresolved(), ","):find("questframe.progressPanel", 1, true))
    assert.are.equal(1, #Stub.hooks.QuestInfo_Display)
  end)

  describe("feeds the Collector", function()
    it("records every non-empty field's API English and the quest giver, whatever is shown", function()
      local db = WFJ.Collector.load(nil, H.collectorDeps())
      Stub.units.questnpc = { name = "Senani Thunderheart", guid = "Creature-0-4372-0-17-3100-0000A1B2C3" }
      S.set("enabled", false)
      Stub.showDetail()
      Stub.keys.alt = true
      WFJ.Modifier.refresh()
      Stub.showProgress()
      Stub.quest.completion = "" -- empty English is never recorded
      Stub.showReward()
      local want = {
        ["quest:2:title"] = "Sharptalon's Claw", ["quest:2:description"] = "Kill Sharptalon at Silverwind Refuge.",
        ["quest:2:objectives"] = "Bring Sharptalon's Claw to Senani Thunderheart.",
        ["quest:2:progress"] = "Did you get it?",
        ["npc:3100:name"] = "Senani Thunderheart",
      }
      local got = {}
      for key, e in pairs(db.entries) do got[key] = e.e end
      assert.are.same(want, got)
      QuestFrame:Hide()
    end)

    it("a quest id of 0 records nothing; an item-started quest has no giver to record", function()
      local db = WFJ.Collector.load(nil, H.collectorDeps())
      Stub.quest.id = 0
      Stub.showDetail()
      assert.is_nil(next(db.entries))
      setQuest(2)
      Stub.showDetail()
      assert.is_nil(db.entries["npc:3100:name"])
      assert.is_table(db.entries["quest:2:title"])
      QuestFrame:Hide()
    end)

    it("a failing collector never stops the window from rendering", function()
      WFJ.Collector.load(nil, H.collectorDeps({ lookup = function() error("collector boom") end }))
      Stub.showDetail()
      assert.are.equal("Sharptalonの鉤爪", QuestInfoTitleHeader:GetText())
      assert.are.equal(3, WFJ.Collector.status().errors)
      QuestFrame:Hide()
    end)
  end)
end)

describe("UI/QuestFrame: player tokens in the quest window", function()
  local WFJ, SS
  -- the main block's files plus Core/Placeholders (the surfaces feed Core/Collector)
  local FILES_P = { "Core/Const.lua", "Core/Compat.lua", "Core/State.lua", "Core/Settings.lua", "Core/Modifier.lua",
    "Core/Placeholders.lua", "Core/Translator.lua", "Core/SurfaceState.lua", "Core/Normalize.lua", "Core/Hash.lua",
    "Core/Collector.lua", "UI/Font.lua", "UI/Render.lua", "UI/ButtonText.lua", "UI/Labels.lua", "UI/QuestFrame.lua" }
  local TOKENS = {
    ["quest.title"] = { [7] = { ja = "{race}の{class}へ", status = "." } },
    ["quest.description"] = { [7] = { ja = "御機嫌よう、{name}。若き{class}よ、{race}の力を見せてくれ。", status = "." } },
  }

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES_P)
    SS = WFJ.SurfaceState
    WFJ.Compat.init(function(name) return _G[name] end)
    WFJ.Settings.load(nil, 1, {})
    WFJ.Render.init(WFJ.Translator.new({
      enabled = function() return WFJ.State.enabled end,
      areaEnabled = WFJ.State.areaEnabled,
      modifierHeld = WFJ.Modifier.isDown,
      lookup = function(kind, id) return TOKENS[kind] and TOKENS[kind][id] end,
      marker = function(n) return WFJ.Settings.get("marker." .. n) end,
      expand = function(ja) -- as Main.lua injects it, over the stub's UnitName / UnitClass / UnitRace / UnitSex
        local className, classFile = UnitClass("player")
        local raceName, raceFile = UnitRace("player")
        return (WFJ.Placeholders.expand(ja, { name = UnitName("player"), className = className, classFile = classFile,
          raceName = raceName, raceFile = raceFile, sex = UnitSex("player") }))
      end,
    }))
    assert.is_true(WFJ.QuestFrame.init())
    Stub.quest = { id = 7, title = "The Balance of Nature",
      description = "Greetings, Reyn. Young hunter, show the strength of the night elves.",
      objectives = "", progress = "", completion = "" }
  end)

  it("renders the player's name and katakana class / race; Alt restores the English; release re-applies", function()
    Stub.showDetail()
    assert.are.equal("ナイトエルフのハンターへ", QuestInfoTitleHeader:GetText())
    assert.are.equal("御機嫌よう、Reyn。若きハンターよ、ナイトエルフの力を見せてくれ。", QuestInfoDescriptionText:GetText())

    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal("The Balance of Nature", QuestInfoTitleHeader:GetText())
    assert.are.equal(Stub.quest.description, QuestInfoDescriptionText:GetText())

    Stub.keys.alt = false; WFJ.Modifier.refresh()
    assert.are.equal("御機嫌よう、Reyn。若きハンターよ、ナイトエルフの力を見せてくれ。", QuestInfoDescriptionText:GetText())

    local writes = QuestInfoDescriptionText.calls.SetText
    assert.are.equal(0, WFJ.Render.refresh()) -- the expansion is deterministic: nothing to rewrite
    assert.are.equal(writes, QuestInfoDescriptionText.calls.SetText)
    assert.is_table(SS.get("questframe.detail", "description"))
  end)
end)

describe("UI/QuestFrame: the greeting panel's NPC text is gossip", function()
  local WFJ, SS, QF, data, db
  local FILES_G = { "Core/Const.lua", "Core/Compat.lua", "Core/State.lua", "Core/Settings.lua", "Core/Modifier.lua",
    "Core/Translator.lua", "Core/SurfaceState.lua", "Core/Normalize.lua", "Core/Hash.lua", "Core/Collector.lua",
    "UI/Font.lua", "UI/Render.lua", "UI/ButtonText.lua", "UI/Labels.lua", "UI/QuestFrame.lua" }
  local PLAYER = { name = "Reyn", class = "Hunter", race = "Night Elf" }
  local GREETING = "Hail, Reyn. I have work for a hunter like you."

  local function key(en) return WFJ.Collector.key(en, PLAYER) end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES_G)
    SS, QF = WFJ.SurfaceState, WFJ.QuestFrame
    WFJ.Compat.init(function(name) return _G[name] end)
    WFJ.Settings.load(nil, 1, {})
    data = { gossip = {}, ["quest.title"] = { [2] = { ja = "Sharptalonの鉤爪", status = "." } } }
    db = WFJ.Collector.load(nil, H.collectorDeps({
      lookup = function(kind, id) return data[kind] and data[kind][id] end,
    }))
    WFJ.Render.init(WFJ.Translator.new({
      enabled = function() return WFJ.State.enabled end,
      areaEnabled = WFJ.State.areaEnabled,
      modifierHeld = WFJ.Modifier.isDown,
      lookup = function(kind, id) return data[kind] and data[kind][id] end,
      marker = function(n) return WFJ.Settings.get("marker." .. n) end,
    }))
    assert.is_true(QF.init({ key = key }))
    Stub.greeting = GREETING
    Stub.units.questnpc = { name = "Marshal Dughan", guid = "Creature-0-4372-0-17-240-0000A1B2C3" }
    data.gossip[key(GREETING)] = { ja = "ようこそ、{name}。仕事がある。", status = "s" }
  end)

  it("translates GreetingText by its gossip key through OnShow; the stale marker goes to the banner", function()
    Stub.showGreeting()
    assert.are.equal("ようこそ、{name}。仕事がある。", GreetingText:GetText())
    assert.are.equal(WFJ.Font.PATH, (GreetingText:GetFont()))
    local rec = SS.get(QF.GREETING, "greeting")
    assert.are.equal("gossip", rec.meta.kind)
    assert.are.equal(key(GREETING), rec.meta.id)
    assert.is_true(QuestGreetingScrollFrame.calls.UpdateScrollChildRect >= 1)
    assert.are.equal(WFJ.MARKER.stale, QF.banner:GetText())
    assert.is_true(QF.banner:IsShown())
    -- the handler reached a second time with no client write in between: no second write
    local writes = GreetingText.calls.addonSetText
    QF.onGreeting()
    assert.are.equal(writes, GreetingText.calls.addonSetText)
    assert.are.equal("ようこそ、{name}。仕事がある。", GreetingText:GetText())
  end)

  it("the by-name writer call on QUEST_LOG_UPDATE is translated again", function()
    Stub.showGreeting()
    Stub.questLogUpdate() -- the client rewrites the English by calling the global
    assert.are.equal("ようこそ、{name}。仕事がある。", GreetingText:GetText())
    assert.are.equal(1, #Stub.hooks.QuestFrameGreetingPanel_OnShow)
  end)

  it("a quest panel forgets the greeting and the greeting panel forgets the quest panels", function()
    Stub.showGreeting()
    Stub.quest = { id = 2, title = "Sharptalon's Claw", description = "D", objectives = "O", progress = "",
      completion = "" }
    Stub.showDetail()
    assert.are.equal(0, SS.count(QF.GREETING))
    assert.are.equal(GREETING, GreetingText:GetText())
    assert.are.same({ "Fonts\\FRIZQT__.TTF", 13, "" }, { GreetingText:GetFont() })
    assert.is_nil(QF.banner:GetText():find(WFJ.MARKER.stale, 1, true)) -- the hidden greeting no longer counts
    assert.are.equal("Sharptalonの鉤爪", QuestInfoTitleHeader:GetText())
    Stub.showGreeting()
    assert.are.equal(0, SS.count("questframe.detail"))
    assert.are.equal("Sharptalon's Claw", QuestInfoTitleHeader:GetText())
  end)

  it("records the greeting as gossip with the quest giver's creature id, and leaves a mismatch untouched", function()
    data.gossip = {}
    Stub.showGreeting()
    assert.are.equal(GREETING, GreetingText:GetText())
    assert.are.equal(0, GreetingText.calls.addonSetText)
    local e = db.entries["gossip:" .. key(GREETING) .. ":text"]
    assert.are.equal("Hail, $N. I have work for a $C like you.", e.e)
    assert.are.same({ 240 }, e.n)
    data.gossip[key(GREETING)] = { ja = "ようこそ。", status = "." }
    rawset(GreetingText, "text", "Something the client decorated") -- the widget no longer shows the API English
    QF.onGreeting()
    assert.are.equal(0, GreetingText.calls.addonSetText)
    assert.is_nil(SS.get(QF.GREETING, "greeting"))
  end)
end)
