local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local QStub = require("tests.lua.spec.stub_questmap")

-- UI/QuestFrame.lua and UI/QuestMap.lua: every client name these surfaces use is
-- declared through Compat and used only by type. Binding each name to a TABLE (the moved-into-a-namespace case, which
-- a truthiness guard lets through) must leave the quest text the client wrote untouched, with no error.
local FILES = {}
for _, f in ipairs(H.UI_FILES) do FILES[#FILES + 1] = f end
FILES[#FILES + 1] = "UI/QuestFrame.lua"
FILES[#FILES + 1] = "UI/QuestMap.lua"

local DATA = {
  ["quest.title"] = { [2] = { ja = "Sharptalonの鉤爪", status = "." }, [5] = { ja = "狼の毛皮", status = "." } },
  ["quest.description"] = { [2] = { ja = "説明文", status = "." }, [5] = { ja = "森の狼", status = "." } },
}
local GREETING = "Well met, traveller."

-- The widgets a quest surface could write, with the client's English on them.
local function snapshot()
  local out = {}
  for _, name in ipairs({ "QuestInfoTitleHeader", "QuestInfoDescriptionText", "QuestInfoObjectivesText",
    "QuestInfoRewardText", "QuestProgressTitleText", "QuestProgressText", "GreetingText" }) do
    local w = _G[name]
    out[name] = type(w) == "table" and type(w.GetText) == "function" and w:GetText() or w
  end
  return out
end

local function load(bind)
  Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
  Stub.installQuestAPI(); Stub.installTooltipAPI()
  local Q = QStub.install()
  Q.quests[5] = { title = "Wolf Pelts", description = "The wolves grow bold.", objectives = "Collect 8.", level = 10 }
  Q.log, Q.watched = { 5 }, { [5] = true }
  Stub.quest = { id = 2, title = "Sharptalon's Claw", description = "Kill Sharptalon.", objectives = "Bring it.",
    progress = "Did you get it?", completion = "Well done." }
  Stub.units.questnpc = { name = "Senani", guid = "Creature-0-1-1-1-3695-0" }
  -- the client writes its English first (as its own writers would), then the names move
  _G.QuestInfoTitleHeader.text, _G.QuestInfoDescriptionText.text = Stub.quest.title, Stub.quest.description
  _G.QuestInfoObjectivesText.text, _G.QuestInfoRewardText.text = Stub.quest.objectives, Stub.quest.completion
  _G.QuestProgressTitleText.text, _G.QuestProgressText.text = Stub.quest.title, Stub.quest.progress
  _G.GreetingText.text = GREETING
  local WFJ = H.loadChunks(FILES)
  H.uiSetup(WFJ, {}, { lookup = function(kind, id) return DATA[kind] and DATA[kind][id] end })
  for _, name in ipairs(bind) do
    local head, rest = name:match("^([^.]+)%.?(.*)$")
    if rest == "" then _G[head] = {} else _G[head] = _G[head] or {}; _G[head][rest] = {} end
  end
  return WFJ, Q
end

describe("UI/QuestFrame's client names bound to a table degrade to untouched English", function()
  -- the readers and the unit functions (the hook still runs: the writer is intact)
  local READERS = { "GetTitleText", "GetQuestText", "GetObjectiveText", "GetRewardText", "GetProgressText",
    "GetQuestID", "UnitGUID", "UnitName", "GetGreetingText" }

  it("every reader bound to a table: no error, no record, the client's English stays", function()
    local WFJ = load(READERS)
    local before = snapshot()
    assert.has_no.errors(function()
      assert.is_true(WFJ.QuestFrame.init({ key = function() return "k" end }))
      WFJ.QuestFrame.onDisplay(QUEST_TEMPLATE_DETAIL, QuestDetailScrollChildFrame)
      WFJ.QuestFrame.onDisplay(QUEST_TEMPLATE_REWARD, QuestRewardScrollChildFrame)
      WFJ.QuestFrame.onProgress()
      WFJ.QuestFrame.onGreeting()
      WFJ.QuestFrame.release()
    end)
    assert.are.same(before, snapshot())
    for _, s in ipairs({ "questframe.detail", "questframe.reward", "questframe.progress", "questframe.greeting" }) do
      for key in pairs(WFJ.SurfaceState.records(s)) do
        assert.is_truthy(key:find("^ui%."), s .. " holds a quest record: " .. key) -- labels are not client API
      end
    end
  end)

  it("the writers and frames bound to a table: init installs nothing and raises nothing", function()
    local WFJ = load({ "QuestInfo_Display", "QuestFrameGreetingPanel_OnShow", "QuestFrame", "QuestFrameProgressPanel",
      "QuestFrameGreetingPanel", "QuestDetailScrollFrame" })
    assert.has_no.errors(function() assert.is_true(WFJ.QuestFrame.init()) end)
    assert.is_nil(Stub.hooks.QuestInfo_Display)
    assert.is_nil(Stub.hooks.QuestFrameGreetingPanel_OnShow)
    assert.is_nil(WFJ.QuestFrame.banner)
  end)

  it("the field and greeting widgets bound to a table: the panel shows nothing and raises nothing", function()
    local WFJ = load({ "QuestInfoTitleHeader", "QuestInfoDescriptionText", "QuestInfoObjectivesText",
      "QuestInfoRewardText", "QuestProgressTitleText", "QuestProgressText", "GreetingText",
      "QuestInfoRewardsFrame" })
    assert.has_no.errors(function()
      WFJ.QuestFrame.init({ key = function() return "k" end })
      assert.are.equal(0, WFJ.QuestFrame.onDisplay(QUEST_TEMPLATE_DETAIL, QuestDetailScrollChildFrame))
      assert.are.equal(0, WFJ.QuestFrame.onProgress())
      WFJ.QuestFrame.onGreeting()
    end)
    assert.are.equal(0, WFJ.SurfaceState.count("questframe.greeting"))
  end)

  it("with nothing moved, the same calls translate (the bindings above are what stopped them)", function()
    local WFJ = load({})
    WFJ.QuestFrame.init()
    assert.are.equal(3, WFJ.QuestFrame.onDisplay(QUEST_TEMPLATE_DETAIL, QuestDetailScrollChildFrame))
    assert.are.equal("Sharptalonの鉤爪", _G.QuestInfoTitleHeader:GetText())
  end)
end)

describe("UI/QuestMap's client names bound to a table degrade to untouched English", function()
  it("the readers bound to a table: details, popup, list and tracker stay English", function()
    local ns, Q = load({})
    Q.showDetails(5) -- the client writes the pane in English (nothing of ours is hooked yet)
    _G.C_QuestLog.GetSelectedQuest, _G.C_QuestLog.GetTitleForQuestID, _G.GetQuestLogQuestText = {}, {}, {}
    local list = _G.QuestScrollFrame.titleFramePool
    local row = select(1, list:Acquire())
    row.questID, row.Text.text = 5, "[10] Wolf Pelts"
    local block = _G.QuestObjectiveTracker:GetBlock(5)
    block.HeaderText.text = "Wolf Pelts"
    local quest = { GetID = function() return 5 end }
    assert.has_no.errors(function()
      assert.are.equal(0, ns.QuestMap.showPane("map"))
      assert.are.equal(0, ns.QuestMap.showPane("popup"))
      assert.are.equal(0, ns.QuestMap.onListUpdate())
      assert.are.equal(0, ns.QuestMap.onTrackerUpdate(_G.QuestObjectiveTracker, quest))
    end)
    assert.are.equal("Wolf Pelts", _G.QuestInfoTitleHeader:GetText())
    assert.are.equal("[10] Wolf Pelts", row.Text:GetText())
    assert.are.equal("Wolf Pelts", block.HeaderText:GetText())
  end)

  it("the writers, frames and widgets bound to a table: init and every hook target raise nothing", function()
    local WFJ = load({ "QuestMapFrame_UpdateQuestDetailsButtons", "QuestLogQuests_Update", "QuestMapFrame",
      "QuestLogPopupDetailFrame", "QuestScrollFrame", "QuestObjectiveTracker", "CampaignQuestObjectiveTracker",
      "ObjectiveTrackerFrame",
      "QuestInfoTitleHeader", "QuestInfoObjectivesText", "QuestInfoDescriptionText", "QuestLogQuestCount",
      "MapQuestInfoRewardsFrame", "QuestMapDetailsScrollFrame", "QuestLogPopupDetailFrameScrollFrame" })
    assert.has_no.errors(function()
      assert.is_true(WFJ.QuestMap.init())
      WFJ.QuestMap.onDisplay(QUEST_TEMPLATE_LOG, {})
      WFJ.QuestMap.showPane("map")
      WFJ.QuestMap.showPane("popup")
      WFJ.QuestMap.onButtons()
      WFJ.QuestMap.showTrackerLabels()
      WFJ.QuestMap.onListUpdate()
      WFJ.QuestMap.onTrackerUpdate({}, { GetID = {} })
      WFJ.QuestMap.onTrackerUpdate({ GetExistingBlock = {} }, { GetID = function() return 5 end })
    end)
    assert.is_nil(Stub.hooks.QuestMapFrame_UpdateQuestDetailsButtons)
    assert.is_nil(Stub.hooks.QuestLogQuests_Update)
    assert.is_nil(Stub.hooks["QuestObjectiveTracker:UpdateSingle"])
    assert.are.equal(0, WFJ.SurfaceState.count("questmap"))
  end)
end)
