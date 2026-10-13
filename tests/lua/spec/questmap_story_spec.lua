-- UI/QuestMap: the quest log's story header (QuestScrollFrame.Contents.StoryHeader, mainline/questmapframe.lua:
-- 2142, written by QuestLogQuests_Update) and the story tooltip (StoryHeaderMixin:ShowTooltip on that header,
-- :2710–2768): the progress words in Japanese, the story's name and the counts kept.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local Q = require("tests.lua.spec.stub_questmap")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
for _, f in ipairs({ "UI/QuestFrame.lua", "UI/QuestMap.lua" }) do FILES[#FILES + 1] = f end

local UI = {
  QUEST_STORY_STATUS = { "|cffffd200Story Progress:|r %d/%d Chapters", "|cffffd200ストーリー進行:|r %d/%d章" },
  STORY_PROGRESS = { "Story Progress", "ストーリー進行" },
  STORY_CHAPTERS = { "%d/%d Chapters", "%d/%d章" },
  EVENT_SCHEDULER_FRAME_LABEL = { "Events", "イベント" },
}

describe("UI/QuestMap's story header, story tooltip and events tab", function()
  local WFJ, list

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI()
    for key, pair in pairs(UI) do _G[key] = pair[1] end
    Q.install()
    list = _G.QuestScrollFrame
    -- the header carries StoryHeaderMixin's ShowTooltip (applied in XML): it fills the story tooltip
    list.Contents.StoryHeader = { Text = Stub.fontString("The Barrens"), Progress = Stub.fontString("") }
    list.StoryTooltip = { Title = Stub.fontString("The Barrens"), ProgressLabel = Stub.fontString(_G.STORY_PROGRESS),
      ProgressCount = Stub.fontString("") }
    function list.Contents.StoryHeader.ShowTooltip()
      list.StoryTooltip.ProgressCount:SetText(string.format(_G.STORY_CHAPTERS, 2, 5))
    end
    local tab = CreateFrame("Button")
    tab.tooltipText = _G.EVENT_SCHEDULER_FRAME_LABEL
    _G.QuestMapFrame.EventsTab = tab
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    WFJ.QuestFrame.init()
    assert.is_true(WFJ.QuestMap.init())
  end)

  after_each(function()
    H.uiTeardown()
  end)

  it("the story header's progress is Japanese after the list update; the story's name stays", function()
    local header = list.Contents.StoryHeader
    header.Progress:SetText(string.format(_G.QUEST_STORY_STATUS, 2, 5))
    Q.updateList()
    assert.are.equal("|cffffd200ストーリー進行:|r 2/5章", header.Progress:GetText())
    assert.are.equal("The Barrens", header.Text:GetText())
  end)

  it("the story tooltip's label and count are Japanese after the client shows it, through a list update", function()
    list.Contents.StoryHeader:ShowTooltip()
    assert.are.equal("ストーリー進行", list.StoryTooltip.ProgressLabel:GetText())
    assert.are.equal("2/5章", list.StoryTooltip.ProgressCount:GetText())
    -- the list updates while the tooltip is open: its words stay Japanese
    Q.updateList()
    assert.are.equal("ストーリー進行", list.StoryTooltip.ProgressLabel:GetText())
    assert.are.equal("The Barrens", list.StoryTooltip.Title:GetText())
  end)

  it("the events tab's hover is Japanese", function()
    local tt = _G.GameTooltip
    tt:SetOwner(_G.QuestMapFrame.EventsTab)
    tt:SetText(_G.EVENT_SCHEDULER_FRAME_LABEL)
    tt:Show()
    assert.are.equal("イベント", _G.GameTooltipTextLeft1:GetText())
  end)
end)
