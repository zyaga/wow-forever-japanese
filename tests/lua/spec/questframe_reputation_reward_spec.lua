-- UI/QuestFrame: the quest window's reputation reward row (QuestInfoReputationRewardButtonMixin, mainline/
-- questinfo.lua:1365–1395): its "<faction> Reputation" name and its hover, the faction's name kept as written.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/QuestFrame.lua"

local UI = {
  QUEST_REPUTATION_REWARD_TITLE = { "%s Reputation", "%sの評価" },
  QUEST_REPUTATION_REWARD_TOOLTIP = { "Awards %d reputation with the %s", "%2$sの評価が%1$d上がります" },
  REPUTATION_TOOLTIP_ACCOUNT_WIDE_LABEL = { "Account-Wide", "アカウント共通" },
}

describe("UI/QuestFrame's reputation reward row", function()
  local WFJ

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI()
    -- the client's mixin, as questinfo.lua defines it before any addon loads
    _G.QuestInfoReputationRewardButtonMixin = {}
    function _G.QuestInfoReputationRewardButtonMixin:SetUpMajorFactionReputationReward(info)
      self.factionName, self.rewardAmount = info.name, info.rewardAmount
      self.Name:SetText(string.format(_G.QUEST_REPUTATION_REWARD_TITLE, self.factionName))
    end
    function _G.QuestInfoReputationRewardButtonMixin:OnEnter()
      local tt = _G.GameTooltip
      tt:SetOwner(self, "ANCHOR_RIGHT")
      tt:SetText(string.format(_G.QUEST_REPUTATION_REWARD_TITLE, self.factionName))
      tt:AddLine(_G.REPUTATION_TOOLTIP_ACCOUNT_WIDE_LABEL)
      tt:AddLine(string.format(_G.QUEST_REPUTATION_REWARD_TOOLTIP, self.rewardAmount, self.factionName))
      tt:Show()
    end
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    assert.is_true(WFJ.QuestFrame.init())
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    _G.QuestInfoReputationRewardButtonMixin = nil
  end)

  it("the row's name and its hover are Japanese around the faction's name; Alt shows English", function()
    local row = { Name = Stub.fontString("") }
    for k, v in pairs(_G.QuestInfoReputationRewardButtonMixin) do row[k] = v end
    _G.QuestInfoReputationRewardButtonMixin.SetUpMajorFactionReputationReward(row,
      { name = "Argent Dawn", rewardAmount = 250 })
    assert.are.equal("Argent Dawnの評価", row.Name:GetText())
    -- the window's display pass runs after the rows are built and forgets its own records, never the row's
    WFJ.Render.forget(WFJ.QuestFrame.SPELL_HEADERS)
    assert.are.equal("Argent Dawnの評価", row.Name:GetText())
    row:OnEnter()
    assert.are.equal("Argent Dawnの評価", _G.GameTooltipTextLeft1:GetText())
    assert.are.equal("アカウント共通", _G.GameTooltipTextLeft2:GetText())
    assert.are.equal("Argent Dawnの評価が250上がります", _G.GameTooltipTextLeft3:GetText())
    alt(true)
    assert.are.equal("Argent Dawn Reputation", row.Name:GetText())
    alt(false)
    assert.are.equal("Argent Dawnの評価", row.Name:GetText())
    -- a reward whose name is not a faction ("Reputation" alone) is never this template
    row.Name:SetText("Reputation")
    assert.are.equal(0,
      WFJ.Labels.show("questframe", "x", row.Name, nil, { only = { "QUEST_REPUTATION_REWARD_TITLE" } }))
  end)
end)
