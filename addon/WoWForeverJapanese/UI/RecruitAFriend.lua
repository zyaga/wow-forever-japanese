-- UI/RecruitAFriend.lua: the social window's Recruit A Friend panel and its rewards list on Forever (surface
-- "recruitafriend", area "ui", ADR-016). Blizzard_RecruitAFriend loads at login; RecruitAFriendFrame is a
-- child of FriendsFrame (recruitafriendframe.xml:680), shown by the contacts header's Recruit A Friend tab when
-- C_RecruitAFriend.IsSystemEnabled() (blizzard_friendsframe/camelot/friendsframe.lua:458, 624; the tab and the title
-- are UI/Friends.lua's). RecruitAFriendRewardsFrame opens from the panel's View All Rewards button
-- (recruitafriendframe.lua:1000–1003).
-- Static labels (XML text=): RecruitList.Header.RecruitedFriends (xml:726), RecruitmentButton (xml:761), the splash
--   screen's Title / Description / OKButton (xml:794–859), RecruitAFriendRewardsFrame.Title.Text (xml:110).
-- Dynamic, each the frame's own method (mixins are copied onto the frame at load; every call is `self:…()`):
--   RewardClaiming:UpdateNextReward → EarnInfo (You've Earned / Next Reward (%d of %d months) / First Reward / Next
--     Reward, lua:1677–1683) and NextRewardName.Text: RAF_BENEFIT4 game time, or "New Title: <title>" with the title
--     kept as written; an item, mount or pet reward is a name and is never matched (lua:1645–1704);
--   RewardClaiming:UpdateRAFInfo → MonthCount.Text (lua:1711–1716);
--   ClaimOrViewRewardButton:Update → Claim Reward / View All Rewards (lua:1015–1019);
--   RecruitAFriendRewardsFrame:UpdateDescription → Description.Text (lua:1093); :UpdateRewards → the pooled reward
--     frames' Months.Text, "%d Months" / "Every %d months after" (rewardPool, lua:1119–1135, 1185–1187), walked
--     from the pool, keyed by widget; ClaimLegacyRewardsButton:Update → Claim Reward / Claim %d Rewards (lua:933);
--   the recruit list's pooled rows (RecruitListButtonMixin:SetupRecruit, lua:778–805), from the ScrollBox's
--     initialized-frame callback and a once-per-row post-hook: InfoText's subscription state; Name only when it is
--     the RAF_PENDING_RECRUIT placeholder (lua:292–294), a recruit's name otherwise, so it is restricted to that key.
-- Help tooltips: a recruit row (RAF_RECRUIT_TOOLTIP_DESC / _MONTH_COUNT under the recruit's name, lua:692–702),
--   NextRewardInfoButton (lua:835), RecruitAFriendRewardsFrame.VersionInfoButton (lua:851–852), the claim buttons'
--   BLIZZARD_STORE_PROCESSING (lua:866).
-- Also (ADR-038):
--   the no-recruits text: RecruitList.NoRecruitsDesc, a SimpleHTML (xml:699, no GetText) written only by
--     SetNoRecruitsText(RAF_NO_RECRUITS_DESC) from OnLoad (lua:55, 82–84): shown at init from that English and after
--     any later SetNoRecruitsText (post-hook); its "|H…|h" link is inside the English and kept byte-identical;
--   an activity chest's tooltip (tooltipFrame): EmbeddedItemTooltip, built by RecruitActivityButtonMixin:OnEnter
--     (lua:510–556): RAF_RECRUIT_ACTIVITY_DESCRIPTION (the recruit's name kept) and CLICK_CHEST_TO_CLAIM_REWARD,
--     followed through UI/TooltipLines only while its owner is an activity button (the quest title, requirement and
--     reward lines are no key of that set).
-- Not here: RecruitAFriendRecruitmentFrame is shown with StaticPopupSpecial_Show (lua:1491; ADR-015 §5).
-- The panel is set up only where FriendsFrame carries SetTitle (the mainline social window, UI/Labels.title).
--
-- The Recruit A Friend tab of the newer social window is the same panel in another frame:
-- SocialUIFrame.RecruitAFriendFrame (RecruitAFriendFrameSocialViewTemplate, blizzard_socialui/mainline/socialui.lua:
-- 253–266; recruitafriendsocialview.xml:301–360), whose mixin is RecruitAFriendFrameMixin with the contacts frame's
-- widgets (recruitafriendsocialview.lua:114–239). Set up whenever that frame exists, with or without the panel:
--   static: Header RAF_RECRUITED_FRIENDS and ActionButton RAF_RECRUITMENT (InitializeRecruitHeader,
--     InitializeActionButton, :129–134, 157–160); the action button's disabled reason RECRUITING_FRIENDS_DISABLED
--     (:279–284);
--   RewardClaiming (RewardClaimingSocialTemplate, xml:47–219: EarnInfo, NextRewardName and MonthCount are frames
--     with a Text child, read through RewardClaimingMixin:GetString, recruitafriendframe.lua:1635–1638): the same
--     UpdateNextReward, UpdateRAFInfo and ClaimOrViewRewardButton:Update writers as the panel's, post-hooked on
--     this view's own instances;
--   the no-recruits text: NoRecruitsScrollBox.NoRecruitsDesc, a SimpleHTML written by the view's own
--     SetNoRecruitsText from OnLoad and on every show (:186–198, 250–254), post-hooked. The scroll box around
--     it keeps the height the client gave it: its update is the client's list code, which this addon never runs;
--   the recruit rows (RecruitListButtonSocialTemplate, xml:234–299): the same InfoText and tooltip keys; Name is
--     the RAF_PENDING_RECRUIT placeholder inside the colour UpdateCardTextColors wraps it in (:16–27), a recruit's
--     name otherwise; CharacterName is never touched.
-- The view's privacy notice (FriendsDisabledText, :323–344) is UI/SocialUI's.
local _, WFJ = ...
local RecruitAFriend = {}
WFJ.RecruitAFriend = RecruitAFriend

local SURFACE = "recruitafriend"
RecruitAFriend.SURFACE = SURFACE
local Compat = WFJ.Compat

local RAF, CLAIMING, REWARDS = "RecruitAFriendFrame", "RecruitAFriendFrame.RewardClaiming", "RecruitAFriendRewardsFrame"
local VIEW = "SocialUIFrame.RecruitAFriendFrame"
local VIEW_CLAIMING = VIEW .. ".RewardClaiming"

RecruitAFriend.NEVER_TOUCH = { "RecruitAFriendRecruitmentFrame.EditBox", RAF .. ".RecruitList.Header.Count",
  VIEW .. ".Count" }

local LABELS = {
  recruited = { RAF .. ".RecruitList.Header.RecruitedFriends", { "RAF_RECRUITED_FRIENDS" } },
  recruitment = { RAF .. ".RecruitmentButton", { "RAF_RECRUITMENT" } },
  splashTitle = { RAF .. ".SplashFrame.Title", { "RAF_SPLASH_SCREEN_TITLE" } },
  splashDescription = { RAF .. ".SplashFrame.Description", { "RAF_SPLASH_SCREEN_DESCRIPTION" } },
  splashOK = { RAF .. ".SplashFrame.OKButton", { "OKAY" } },
  earnInfo = { CLAIMING .. ".EarnInfo",
    { "RAF_YOU_HAVE_EARNED", "RAF_NEXT_REWARD_AFTER", "RAF_FIRST_REWARD", "RAF_NEXT_REWARD" } },
  nextName = { CLAIMING .. ".NextRewardName.Text", { "RAF_BENEFIT4", "RAF_REWARD_TITLE" } },
  monthCount = { CLAIMING .. ".MonthCount.Text", { "RAF_FIRST_MONTH", "RAF_MONTHS_EARNED" } },
  claimOrView = { CLAIMING .. ".ClaimOrViewRewardButton", { "CLAIM_REWARD", "RAF_VIEW_ALL_REWARDS" } },
  rewardsTitle = { REWARDS .. ".Title.Text", { "RAF_REWARDS" } },
  rewardsDescription = { REWARDS .. ".Description.Text", { "RAF_REWARDS_DESC", "RAF_LEGACY_REWARDS_DESC" } },
  claimLegacy = { REWARDS .. ".ClaimLegacyRewardsButton", { "CLAIM_REWARD", "RAF_CLAIM_MULTIPLE_REWARDS" } },
  -- the social window's view: the same strings on its own widgets
  viewRecruited = { VIEW .. ".Header", { "RAF_RECRUITED_FRIENDS" } },
  viewRecruitment = { VIEW .. ".ActionButton", { "RAF_RECRUITMENT" } },
  viewEarnInfo = { VIEW_CLAIMING .. ".EarnInfo.Text",
    { "RAF_YOU_HAVE_EARNED", "RAF_NEXT_REWARD_AFTER", "RAF_FIRST_REWARD", "RAF_NEXT_REWARD" } },
  viewNextName = { VIEW_CLAIMING .. ".NextRewardName.Text", { "RAF_BENEFIT4", "RAF_REWARD_TITLE" } },
  viewMonthCount = { VIEW_CLAIMING .. ".MonthCount.Text", { "RAF_FIRST_MONTH", "RAF_MONTHS_EARNED" } },
  viewClaimOrView = { VIEW_CLAIMING .. ".ClaimOrViewRewardButton", { "CLAIM_REWARD", "RAF_VIEW_ALL_REWARDS" } },
}
local ORDER = {}
for key in pairs(LABELS) do ORDER[#ORDER + 1] = key end
table.sort(ORDER)

local PROCESSING = { only = { "BLIZZARD_STORE_PROCESSING" } }
local TOOLTIPS = {
  { CLAIMING .. ".NextRewardInfoButton", { only = { "RAF_NEXT_REWARD_HELP_TEXT" } } },
  { REWARDS .. ".VersionInfoButton", { only = { "RAF_LATEST_REWARDS_HELP_TEXT", "RAF_LEGACY_REWARDS_HELP_TEXT" } } },
  { CLAIMING .. ".ClaimOrViewRewardButton", PROCESSING }, { REWARDS .. ".ClaimLegacyRewardsButton", PROCESSING },
  { VIEW_CLAIMING .. ".ClaimOrViewRewardButton", PROCESSING },
  { VIEW .. ".ActionButton", { only = { "RECRUITING_FRIENDS_DISABLED" } } },
}

local CANDIDATES = {
  friends = { "FriendsFrame" }, frame = { RAF }, claiming = { CLAIMING }, rewards = { REWARDS },
  claimOrViewButton = { CLAIMING .. ".ClaimOrViewRewardButton" },
  claimLegacyButton = { REWARDS .. ".ClaimLegacyRewardsButton" },
  recruits = { RAF .. ".RecruitList.ScrollBox" }, scrollUtil = { "ScrollUtil" },
  noRecruits = { RAF .. ".RecruitList.NoRecruitsDesc" }, noRecruitsEnglish = { "RAF_NO_RECRUITS_DESC" },
  embedded = { "EmbeddedItemTooltip" }, activityMixin = { "RecruitActivityButtonMixin" },
  view = { VIEW }, viewClaiming = { VIEW_CLAIMING },
  viewClaimOrViewButton = { VIEW_CLAIMING .. ".ClaimOrViewRewardButton" },
  viewRecruits = { VIEW .. ".ScrollBox" },
  viewNoRecruits = { VIEW .. ".NoRecruitsScrollBox.NoRecruitsDesc" },
}
local NO_RECRUITS = { only = { "RAF_NO_RECRUITS_DESC" } }
local ACTIVITY_TIP = { only = { "RAF_RECRUIT_ACTIVITY_DESCRIPTION", "CLICK_CHEST_TO_CLAIM_REWARD" } }

local ROW_INFO = { only = { "RAF_ACTIVE_RECRUIT", "RAF_TRIAL_RECRUIT", "RAF_INACTIVE_RECRUIT" } }
-- the placeholder arrives inside a colour on the social window's cards
local ROW_NAME = { wrapped = true, only = { "RAF_PENDING_RECRUIT" } }
local ROW_TIP = { only = { "RAF_RECRUIT_TOOLTIP_DESC", "RAF_RECRUIT_TOOLTIP_MONTH_COUNT" } }
local MONTHS = { only = { "RAF_MONTHS", "RAF_REPEATABLE_MONTHS" } }

local function get(key) return Compat.get(SURFACE, key) end

-- Shows the named labels (all of them when none is named). → the number of dictionary words found.
function RecruitAFriend.show(...)
  local keys = select("#", ...) > 0 and { ... } or ORDER
  local items = {}
  for _, key in ipairs(keys) do
    items[#items + 1] = { key, get("label." .. key), { only = LABELS[key][2] } }
  end
  return WFJ.Labels.showAll(SURFACE, items)
end

local rowKey = WFJ.Labels.keyer("row.") -- a pooled widget's record key (follows the widget, never an index)
local rowHooked = setmetatable({}, { __mode = "k" })

local function showRow(row)
  if type(row.InfoText) == "table" then WFJ.Labels.show(SURFACE, rowKey(row.InfoText), row.InfoText, nil, ROW_INFO) end
  if type(row.Name) == "table" then WFJ.Labels.show(SURFACE, rowKey(row.Name), row.Name, nil, ROW_NAME) end
  WFJ.Labels.forbid(row.CharacterName) -- a card's second line: the recruit's character
end

-- One pooled recruit row after its initializer ran: (owner, frame, elementData) for a new row, (frame, elementData)
-- for the iterateExisting pass. Returns nothing: ForEachFrame stops at the first truthy return.
function RecruitAFriend.onRow(a, b)
  local row = a
  if a == RecruitAFriend then row = b end
  if type(row) ~= "table" then return end
  if not rowHooked[row] and type(row.SetupRecruit) == "function" then
    rowHooked[row] = true
    hooksecurefunc(row, "SetupRecruit", showRow) -- the row refreshes itself on recruit updates too
  end
  WFJ.HelpTooltip.register(row, ROW_TIP)
  showRow(row)
end

-- hooksecurefunc target (RecruitAFriendRewardsFrame:UpdateRewards). → the number of dictionary words found.
function RecruitAFriend.onRewards()
  local rewards = get("rewards")
  local pool = type(rewards) == "table" and rewards.rewardPool or nil
  if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then return 0 end
  local n = 0
  for reward in pool:EnumerateActive() do
    local text = type(reward) == "table" and type(reward.Months) == "table" and reward.Months.Text or nil
    if type(text) == "table" then n = n + WFJ.Labels.show(SURFACE, rowKey(text), text, nil, MONTHS) end
  end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- hooksecurefunc targets: the panel's widget and the social window view's.
function RecruitAFriend.onNextReward()
  return RecruitAFriend.show("earnInfo", "nextName", "viewEarnInfo", "viewNextName")
end
function RecruitAFriend.onRAFInfo() return RecruitAFriend.show("monthCount", "viewMonthCount") end
function RecruitAFriend.onClaimOrView() return RecruitAFriend.show("claimOrView", "viewClaimOrView") end
function RecruitAFriend.onDescription() return RecruitAFriend.show("rewardsDescription") end
function RecruitAFriend.onClaimLegacy() return RecruitAFriend.show("claimLegacy") end

-- The no-recruits SimpleHTML seen as a FontString (UI/HtmlText).
local html = WFJ.HtmlText.new()
RecruitAFriend.noRecruitsHtml = html

-- The no-recruits text, `text` being what the client wrote (SetNoRecruitsText's argument). → 1 | 0
function RecruitAFriend.onNoRecruits(_, text)
  if html.writing or type(html.html) ~= "table" then return 0 end
  html.logical = type(text) == "string" and text or nil
  local n = WFJ.Labels.show(SURFACE, "noRecruits", html, nil, NO_RECRUITS)
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- The social window view's no-recruits SimpleHTML, inside a scroll box.
local viewHtml = WFJ.HtmlText.new()
RecruitAFriend.viewNoRecruitsHtml = viewHtml

-- The view's no-recruits text, `text` being what the client wrote (SetNoRecruitsText's argument). → 1 | 0
function RecruitAFriend.onViewNoRecruits(_, text)
  if viewHtml.writing or type(viewHtml.html) ~= "table" then return 0 end
  viewHtml.logical = type(text) == "string" and text or nil
  local n = WFJ.Labels.show(SURFACE, "viewNoRecruits", viewHtml, nil, NO_RECRUITS)
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- TooltipLines' `allow` for EmbeddedItemTooltip: its owner is an activity chest (the mixin's OnEnter is copied onto
-- each button at load). → bool
function RecruitAFriend.activityOwner()
  local tt, mixin = get("embedded"), get("activityMixin")
  local owner = type(tt) == "table" and type(tt.GetOwner) == "function" and tt:GetOwner() or nil
  return type(owner) == "table" and type(mixin) == "table" and owner.OnEnter ~= nil and owner.OnEnter == mixin.OnEnter
end

local hooked = false

local function hookMethod(frame, method, fn)
  if type(frame) == "table" and type(frame[method]) == "function" then hooksecurefunc(frame, method, fn) end
end

-- One recruit list's pooled rows.
local function followRows(rows)
  local util = get("scrollUtil")
  if type(rows) == "table" and type(util) == "table" and type(util.AddInitializedFrameCallback) == "function" then
    util.AddInitializedFrameCallback(rows, RecruitAFriend.onRow, RecruitAFriend, true)
  end
end

-- The older panel's writers.
local function hookPanel(frame)
  hookMethod(get("claiming"), "UpdateNextReward", RecruitAFriend.onNextReward)
  hookMethod(get("claiming"), "UpdateRAFInfo", RecruitAFriend.onRAFInfo)
  hookMethod(get("claimOrViewButton"), "Update", RecruitAFriend.onClaimOrView)
  followRows(get("recruits"))
  html.html = get("noRecruits")
  hookMethod(frame, "SetNoRecruitsText", RecruitAFriend.onNoRecruits)
  RecruitAFriend.onNoRecruits(frame, get("noRecruitsEnglish")) -- written once by OnLoad, before this module
end

-- The social window view's writers.
local function hookView(view)
  hookMethod(get("viewClaiming"), "UpdateNextReward", RecruitAFriend.onNextReward)
  hookMethod(get("viewClaiming"), "UpdateRAFInfo", RecruitAFriend.onRAFInfo)
  hookMethod(get("viewClaimOrViewButton"), "Update", RecruitAFriend.onClaimOrView)
  followRows(get("viewRecruits"))
  viewHtml.html = get("viewNoRecruits")
  hookMethod(view, "SetNoRecruitsText", RecruitAFriend.onViewNoRecruits)
  RecruitAFriend.onViewNoRecruits(view, get("noRecruitsEnglish")) -- written by OnLoad, before this module
end

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function RecruitAFriend.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  for key, l in pairs(LABELS) do Compat.declare(SURFACE, "label." .. key, { l[1] }) end
  for i, t in ipairs(TOOLTIPS) do Compat.declare(SURFACE, "tip." .. i, { t[1] }) end
  local friends, frame, view = get("friends"), get("frame"), get("view")
  -- the panel needs a social window with SetTitle; the newer window's view stands by itself
  local panel = type(frame) == "table" and type(friends) == "table" and type(friends.SetTitle) == "function"
  if hooked or not (panel or type(view) == "table") then return false end
  hooked = true
  for i, t in ipairs(TOOLTIPS) do
    local owner = get("tip." .. i)
    if type(owner) == "table" then WFJ.HelpTooltip.register(owner, t[2]) end
  end
  if panel then hookPanel(frame) end
  if type(view) == "table" then hookView(view) end
  hookMethod(get("rewards"), "UpdateDescription", RecruitAFriend.onDescription)
  hookMethod(get("rewards"), "UpdateRewards", RecruitAFriend.onRewards)
  hookMethod(get("claimLegacyButton"), "Update", RecruitAFriend.onClaimLegacy)
  if WFJ.TooltipLines then
    WFJ.TooltipLines.follow(SURFACE .. ".activity", get("embedded"), ACTIVITY_TIP, RecruitAFriend.activityOwner)
  end
  RecruitAFriend.show()
  RecruitAFriend.onRewards()
  return true
end
