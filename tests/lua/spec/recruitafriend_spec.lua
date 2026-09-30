-- Recruit a friend: UI/RecruitAFriend.lua over RecruitAFriendFrame / RecruitAFriendRewardsFrame replayed
-- from camelot blizzard_recruitafriend/recruitafriendframe.lua (RewardClaiming :1645–1716, the claim buttons :933 +
-- :1015–1019, the rewards list :1093 + :1119–1187, recruit rows :778–805 + :692–702). Recruit names, reward names and
-- title names stay English.
local S = require("tests.lua.spec.stub_camelot_social")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = S.files("UI/TooltipLines.lua", "UI/RecruitAFriend.lua")

local UI = {
  RAF_RECRUITED_FRIENDS = { "Recruited Friends", "招待したフレンド" }, RAF_RECRUITMENT = { "Recruitment", "招待" },
  RAF_SPLASH_SCREEN_TITLE = { "Share Azeroth with Everyone!", "Azerothをみんなと分かち合おう!" }, OKAY = { "Okay", "OK" },
  RAF_YOU_HAVE_EARNED = { "You've Earned:", "獲得済み:" }, RAF_FIRST_REWARD = { "First Reward:", "最初の報酬:" },
  RAF_NEXT_REWARD_AFTER = { "Next Reward (%d of %d |4month:months;):", "次の報酬 (%d/%dか月):" },
  RAF_BENEFIT4 = { "30 days of free game time", "30日分の無料ゲーム時間" },
  RAF_REWARD_TITLE = { "New Title: %s", "新しい称号: %s" },
  RAF_FIRST_MONTH = { "Recruit friends to get started!", "フレンドを招待して始めよう!" },
  RAF_MONTHS_EARNED = { "%d |4Month:Months; Subscribed by Friends", "フレンドの購読 %dか月分" },
  CLAIM_REWARD = { "Claim Reward", "報酬を受け取る" }, RAF_VIEW_ALL_REWARDS = { "View All Rewards", "すべての報酬を見る" },
  RAF_CLAIM_MULTIPLE_REWARDS = { "Claim %d Rewards", "報酬を%d個受け取る" },
  RAF_REWARDS = { "Recruit A Friend Rewards", "フレンド招待の報酬" },
  RAF_REWARDS_DESC = { "A single monthly reward is earned every 30 days per recruit with active gametime.",
    "有効なゲーム時間を持つ招待フレンド1人につき、30日ごとに月間報酬を1つ獲得します。" },
  RAF_MONTHS = { "%d |4Month:Months;", "%dか月" }, RAF_REPEATABLE_MONTHS = { "Every %d months after", "以後%dか月ごと" },
  RAF_ACTIVE_RECRUIT = { "Active subscription", "購読中" }, RAF_PENDING_RECRUIT = { "Pending Recruit", "招待保留中" },
  RAF_RECRUIT_TOOLTIP_DESC = { "Each recruited friend can provide up to %d subscription months toward your rewards.",
    "招待したフレンド1人につき、最大%dか月分の購読が報酬の対象になります。" },
  RAF_NEXT_REWARD_HELP_TEXT = { "Recruit friends to begin earning rewards when your friends start a subscription.",
    "フレンドを招待すると、フレンドが購読を始めたときに報酬を獲得できます。" },
  BLIZZARD_STORE_PROCESSING = { "Processing...", "処理中..." },
  CLOSE = { "Close", "閉じる" },
  -- The no-recruits text (its link kept byte-identical) and an activity chest's tooltip lines
  RAF_NO_RECRUITS_DESC = { "|cffffd200Recruit friends to begin earning rewards.|r|n|nFor more info:|n"
    .. "|HurlIndex:49|h|cff82c5ffVisit our Recruit A Friend Website|r|h",
    "|cffffd200フレンドを招待して報酬を獲得しよう。|r|n|n詳しくは:|n|HurlIndex:49|h|cff82c5ffVisit our Recruit A Friend Website|r|h" },
  RAF_RECRUIT_ACTIVITY_DESCRIPTION = { "Use Party Sync and complete the following tasks with %s to receive a reward.",
    "パーティー同期を使って%sと次のタスクを達成すると報酬を獲得できます。" },
  CLICK_CHEST_TO_CLAIM_REWARD = { "Click chest to claim reward", "宝箱をクリックして報酬を受け取る" },
}
local NEEDS = { ARGS = { RAF_REWARD_TITLE = { [1] = "text" } } } -- Core/UIStrings: the title is a name, kept as written

local C = {}

local function install(o)
  o = o or {}
  local en = S.en
  local friends = S.frame("FriendsFrame")
  if not o.untitled then function friends.SetTitle() end end
  local raf = S.frame("RecruitAFriendFrame")
  S.put(raf, "RecruitList.Header.RecruitedFriends", S.fs(en("RAF_RECRUITED_FRIENDS")))
  raf.RecruitList.Header.Count = S.fs("(1/10)")
  raf.RecruitList.ScrollBox = Stub.scrollBox()
  -- The no-recruits SimpleHTML (xml:699; SetText, GetFont / SetFont per text type, no GetText), written by
  -- SetNoRecruitsText(RAF_NO_RECRUITS_DESC) at OnLoad (lua:55, 82–84)
  local html = CreateFrame("Frame")
  html.fonts = { P = { "Fonts\\FRIZQT__.TTF", 12, "" } }
  function html.SetText(self, text) self.shown = text end
  function html.GetFont(self, tag) local f = self.fonts[tag or "P"]; return f[1], f[2], f[3] end
  function html.SetFont(self, tag, path, size, flags) self.fonts[tag] = { path, size, flags } end
  raf.RecruitList.NoRecruitsDesc = html
  function raf.SetNoRecruitsText(self, text) self.RecruitList.NoRecruitsDesc:SetText(text) end
  raf:SetNoRecruitsText(en("RAF_NO_RECRUITS_DESC"))
  -- an activity chest (RecruitActivityButtonMixin, lua:493–556) and its EmbeddedItemTooltip
  Stub.tooltipFrame("EmbeddedItemTooltip")
  _G.RecruitActivityButtonMixin = { OnEnter = function(self)
    local tt = _G.EmbeddedItemTooltip
    tt:SetOwner(self)
    tt:SetText(self.questName)
    tt:AddLine(en("RAF_RECRUIT_ACTIVITY_DESCRIPTION"):format(self.recruitName))
    tt:AddLine("Reach level 10")
    if self.complete then tt:AddLine(en("CLICK_CHEST_TO_CLAIM_REWARD")) end
    tt:Show()
  end }
  function C.activity(questName, recruitName, complete)
    local b = CreateFrame("Button")
    b.OnEnter = _G.RecruitActivityButtonMixin.OnEnter -- the mixin copied onto the button at load
    b.questName, b.recruitName, b.complete = questName, recruitName, complete
    return b
  end
  raf.RecruitmentButton = S.button(nil, en("RAF_RECRUITMENT"))
  S.put(raf, "SplashFrame.Title", S.fs(en("RAF_SPLASH_SCREEN_TITLE")))
  raf.SplashFrame.OKButton = S.button(nil, en("OKAY"))
  local claiming = S.frame(nil, "RewardClaiming")
  raf.RewardClaiming = claiming
  claiming.EarnInfo = S.fs("")
  claiming.NextRewardName, claiming.MonthCount = { Text = S.fs("") }, { Text = S.fs("") }
  claiming.NextRewardInfoButton = S.frame()
  claiming.ClaimOrViewRewardButton = S.button(nil, en("RAF_VIEW_ALL_REWARDS"))
  claiming.ClaimOrViewRewardButton.name = "ClaimOrViewRewardButton"
  function claiming.ClaimOrViewRewardButton.Update(self, canClaim)
    S.write(self, en(canClaim and "CLAIM_REWARD" or "RAF_VIEW_ALL_REWARDS"))
  end
  function claiming.UpdateNextReward(self, reward)
    self.EarnInfo.text = reward.earned and en("RAF_YOU_HAVE_EARNED")
      or (reward.of and "Next Reward (" .. reward.at .. " of " .. reward.of .. " months):" or en("RAF_FIRST_REWARD"))
    self.NextRewardName.Text.text = reward.title and en("RAF_REWARD_TITLE"):format(reward.title)
      or (reward.item or en("RAF_BENEFIT4"))
  end
  function claiming.UpdateRAFInfo(self, months)
    self.MonthCount.Text.text = months == 0 and en("RAF_FIRST_MONTH") or (months .. " Months Subscribed by Friends")
  end
  local rewards = S.frame("RecruitAFriendRewardsFrame")
  rewards.Title, rewards.Description = { Text = S.fs(en("RAF_REWARDS")) }, { Text = S.fs("") }
  rewards.VersionInfoButton = S.frame()
  rewards.ClaimLegacyRewardsButton = S.button(nil, en("CLAIM_REWARD"))
  rewards.ClaimLegacyRewardsButton.name = "ClaimLegacyRewardsButton"
  function rewards.ClaimLegacyRewardsButton.Update(self, n)
    S.write(self, n == 1 and en("CLAIM_REWARD") or en("RAF_CLAIM_MULTIPLE_REWARDS"):format(n))
  end
  rewards.rewardPool = S.pool(function() return { Months = { Text = S.fs("") } } end)
  function rewards.UpdateDescription(self) self.Description.Text.text = en("RAF_REWARDS_DESC") end
  function rewards.UpdateRewards(self, list)
    self.rewardPool:ReleaseAll()
    for _, months in ipairs(list) do
      self.rewardPool:Acquire().Months.Text.text = months < 0 and ("Every %d months after"):format(-months)
        or (months .. (months == 1 and " Month" or " Months"))
    end
  end
  function C.recruit(row, info)
    if not row then
      row = CreateFrame("Button")
      row.Name, row.InfoText = S.fs(""), S.fs("")
      function row.SetupRecruit(self, i)
        self.Name.text = i.name or en("RAF_PENDING_RECRUIT")
        self.InfoText.text = i.active and en("RAF_ACTIVE_RECRUIT") or "Close"
      end
    end
    raf.RecruitList.ScrollBox:initFrame(row, info, function(r, d) r:SetupRecruit(d) end)
    return row
  end
end

local GLOBALS = { "FriendsFrame", "RecruitAFriendFrame", "RecruitAFriendRewardsFrame", "EmbeddedItemTooltip",
  "RecruitActivityButtonMixin" }

describe("the recruit-a-friend panel on Forever", function()
  local WFJ
  before_each(function() WFJ = S.load(FILES, UI, NEEDS) end)
  after_each(function() S.teardown(GLOBALS) end)

  it("static labels are Japanese; the recruit count is never taken; Alt shows English", function()
    install()
    assert.is_true(WFJ.RecruitAFriend.init())
    local raf = _G.RecruitAFriendFrame
    assert.are.equal("招待したフレンド", raf.RecruitList.Header.RecruitedFriends:GetText())
    assert.are.equal("招待", raf.RecruitmentButton:GetText())
    assert.are.equal("Azerothをみんなと分かち合おう!", raf.SplashFrame.Title:GetText())
    assert.are.equal("OK", raf.SplashFrame.OKButton:GetText())
    assert.are.equal("すべての報酬を見る", raf.RewardClaiming.ClaimOrViewRewardButton:GetText())
    assert.are.equal("フレンド招待の報酬", _G.RecruitAFriendRewardsFrame.Title.Text:GetText())
    assert.are.equal("(1/10)", raf.RecruitList.Header.Count:GetText())
    S.alt(WFJ, true)
    assert.are.equal("Recruitment", raf.RecruitmentButton:GetText())
    S.alt(WFJ, false)
  end)

  it("the reward writers: fixed texts translate, a title is kept, an item reward's name is never matched", function()
    install()
    WFJ.RecruitAFriend.init()
    local claiming, rewards = _G.RecruitAFriendFrame.RewardClaiming, _G.RecruitAFriendRewardsFrame
    claiming:UpdateNextReward({ at = 2, of = 3, title = "the Close" })
    assert.are.equal("次の報酬 (2/3か月):", claiming.EarnInfo:GetText())
    assert.are.equal("新しい称号: the Close", claiming.NextRewardName.Text:GetText())
    claiming:UpdateNextReward({ earned = true, item = "Close" })
    assert.are.equal("獲得済み:", claiming.EarnInfo:GetText())
    assert.are.equal("Close", claiming.NextRewardName.Text:GetText())
    claiming:UpdateNextReward({})
    assert.are.equal("30日分の無料ゲーム時間", claiming.NextRewardName.Text:GetText())
    claiming:UpdateRAFInfo(0)
    assert.are.equal("フレンドを招待して始めよう!", claiming.MonthCount.Text:GetText())
    claiming:UpdateRAFInfo(4)
    assert.are.equal("フレンドの購読 4か月分", claiming.MonthCount.Text:GetText())
    claiming.ClaimOrViewRewardButton:Update(true)
    assert.are.equal("報酬を受け取る", claiming.ClaimOrViewRewardButton:GetText())
    rewards:UpdateDescription()
    assert.are.equal("有効なゲーム時間を持つ招待フレンド1人につき、30日ごとに月間報酬を1つ獲得します。",
      rewards.Description.Text:GetText())
    rewards.ClaimLegacyRewardsButton:Update(3)
    assert.are.equal("報酬を3個受け取る", rewards.ClaimLegacyRewardsButton:GetText())
    rewards:UpdateRewards({ 1, 6, -3 })
    local months = {}
    for reward in rewards.rewardPool:EnumerateActive() do months[#months + 1] = reward.Months.Text:GetText() end
    assert.are.same({ "1か月", "6か月", "以後3か月ごと" }, months)
    rewards:UpdateRewards({ 2 }) -- the pooled frame reused
    assert.are.equal("2か月", rewards.rewardPool.active[1].Months.Text:GetText())
  end)

  it("recruit rows: the state and the placeholder translate; a recruit's name and last-online text do not", function()
    install()
    WFJ.RecruitAFriend.init()
    local row = C.recruit(nil, { active = true })
    assert.are.equal("招待保留中", row.Name:GetText())
    assert.are.equal("購読中", row.InfoText:GetText())
    row:SetupRecruit({ name = "Close" }) -- the row's own refresh: a recruit called like a UI word
    assert.are.equal("Close", row.Name:GetText())
    assert.are.equal("Close", row.InfoText:GetText())
    assert.is_true(S.unrecorded(WFJ, row.Name))
    C.recruit(row, { name = "Thrall", active = true })
    assert.are.equal(1, #Stub.hooks["?:SetupRecruit"]) -- hooked once per row
    assert.are.same({ "Close", "招待したフレンド1人につき、最大3か月分の購読が報酬の対象になります。" },
      S.tooltip(row, { "Close", S.en("RAF_RECRUIT_TOOLTIP_DESC"):format(3) }))
    assert.are.same({ "フレンドを招待すると、フレンドが購読を始めたときに報酬を獲得できます。" },
      S.tooltip(_G.RecruitAFriendFrame.RewardClaiming.NextRewardInfoButton, { S.en("RAF_NEXT_REWARD_HELP_TEXT") }))
    assert.are.same({ "処理中..." },
      S.tooltip(_G.RecruitAFriendFrame.RewardClaiming.ClaimOrViewRewardButton, { "Processing..." }))
  end)

  it("the no-recruits text: Japanese around the link, the link byte-identical; Alt the client's English",
    function()
      install()
      assert.is_true(WFJ.RecruitAFriend.init())
      local html = _G.RecruitAFriendFrame.RecruitList.NoRecruitsDesc
      local link = "|HurlIndex:49|h|cff82c5ffVisit our Recruit A Friend Website|r|h"
      assert.are.equal("|cffffd200フレンドを招待して報酬を獲得しよう。|r|n|n詳しくは:|n" .. link, html.shown)
      assert.are.equal(WFJ.Font.PATH, (html:GetFont("P")))
      S.alt(WFJ, true)
      assert.are.equal(S.en("RAF_NO_RECRUITS_DESC"), html.shown)
      S.alt(WFJ, false)
      _G.RecruitAFriendFrame:SetNoRecruitsText("Something else")
      assert.are.equal("Something else", html.shown)
    end)

  it("an activity chest's EmbeddedItemTooltip: the description (recruit's name kept) and the claim line; the "
    .. "quest title and requirements stay; another owner's tooltip is not walked", function()
      install()
      assert.is_true(WFJ.RecruitAFriend.init())
      local chest = C.activity("Close", "Jaina", true)
      chest:OnEnter()
      assert.are.equal("Close", _G.EmbeddedItemTooltipTextLeft1:GetText()) -- a quest named like a UI word
      assert.are.equal("パーティー同期を使ってJainaと次のタスクを達成すると報酬を獲得できます。",
        _G.EmbeddedItemTooltipTextLeft2:GetText())
      assert.are.equal("Reach level 10", _G.EmbeddedItemTooltipTextLeft3:GetText())
      assert.are.equal("宝箱をクリックして報酬を受け取る", _G.EmbeddedItemTooltipTextLeft4:GetText())
      S.alt(WFJ, true)
      assert.are.equal("Click chest to claim reward", _G.EmbeddedItemTooltipTextLeft4:GetText())
      S.alt(WFJ, false)
      _G.EmbeddedItemTooltip:Hide()
      local tt = _G.EmbeddedItemTooltip -- a world quest's tooltip on the same frame
      tt:SetOwner(CreateFrame("Frame"))
      tt:SetText("Click chest to claim reward")
      tt:Show()
      assert.are.equal("Click chest to claim reward", _G.EmbeddedItemTooltipTextLeft1:GetText())
    end)

  it("a client name bound to the wrong type degrades to English with no error", function()
    install()
    local raf = _G.RecruitAFriendFrame
    raf.RewardClaiming.UpdateNextReward = 1
    raf.RewardClaiming.ClaimOrViewRewardButton = "?"
    raf.RecruitList.ScrollBox = true
    _G.RecruitAFriendRewardsFrame.rewardPool = "?"
    _G.RecruitAFriendRewardsFrame.Description = 0
    assert.has_no.errors(function() assert.is_true(WFJ.RecruitAFriend.init()) end)
    assert.are.equal("招待", raf.RecruitmentButton:GetText())
    assert.has_no.errors(function() assert.are.equal(0, WFJ.RecruitAFriend.onRewards()) end)
  end)

  it("hooks install once; without the mainline social window init returns false and touches nothing", function()
    assert.is_false(WFJ.RecruitAFriend.init())
    install({ untitled = true })
    assert.is_false(WFJ.RecruitAFriend.init())
    assert.are.equal("Recruitment", _G.RecruitAFriendFrame.RecruitmentButton:GetText())
    install()
    assert.is_true(WFJ.RecruitAFriend.init())
    assert.is_false(WFJ.RecruitAFriend.init())
    assert.are.equal(1, #Stub.hooks["RewardClaiming:UpdateNextReward"])
  end)
end)
