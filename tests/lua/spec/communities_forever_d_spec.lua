-- The rest of the Forever Communities window: UI/CommunitiesFrame, UI/CommunitiesGuild,
-- UI/ClubFinder, UI/ClubFinderApplicants and UI/CommunitiesDialogs over a CommunitiesFrame replayed from the camelot
-- blizzard_communities extract (the file:line of every writer is in each module's header). Per window: the static
-- labels and the writer-hooked texts render Japanese, names stay English, a name bound to the wrong type degrades
-- to English with no error, and the surfaces wait for Blizzard_Communities in either load order.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local MODULES = { "CommunitiesFrame", "CommunitiesGuild", "ClubFinder", "ClubFinderApplicants", "CommunitiesDialogs" }
local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/CommunitiesKit.lua"
for _, m in ipairs(MODULES) do FILES[#FILES + 1] = "UI/" .. m .. ".lua" end
FILES[#FILES + 1] = "UI/ChatSystem.lua" -- the chat MessageFrame's key-restricted entry point

local ADDON = "Blizzard_Communities"

-- { English, Japanese }: the window's own keys and the older keys it reuses
local UI = {
  COMMUNITIES_FRAME_TITLE = { "Guild & Communities", "ギルド&コミュニティ" },
  GUILD_CONTROL_BUTTON_TEXT = { "Guild Settings", "ギルド設定" }, GUILD_RECRUITMENT = { "Recruitment", "募集" },
  GUILD_VIEW_LOG = { "View Log", "ログを表示" }, COMMUNITIES_INVITE_MEMBERS = { "Invite Member", "メンバーの勧誘" },
  COMMUNITIES_FRAME_JUMP_TO_UNREAD = { "Unread", "未読" },
  COMMUNITIES_ADD_TO_CHAT = { "Add to Chat Window", "チャットウィンドウに追加" },
  COMMUNITIES_SETTINGS_BUTTON_LABEL = { "Group Settings", "グループ設定" },
  COMMUNITIES_SETTINGS_BUTTON_CHARACTER_LABEL = { "Community Settings", "コミュニティ設定" },
  COMMUNITIES_CHAT_TAB_TOOLTIP = { "Chat", "チャット" },
  ERR_PARENTAL_CONTROLS_CHAT_MUTED = { "Chat is disabled due to your Battle.net Account parental controls or privacy "
    .. "settings", "Battle.netアカウントの保護者による制限またはプライバシー設定により、チャットは無効になっています" },
  CLUB_INVITER_FAIL_GUILD_CAPACITY = { "You cannot invite new members, your guild is full.",
    "ギルドが満員のため、新しいメンバーを招待できません。" },
  GUILD_FINDER_POSTING_GOING_TO_EXPIRE = { "Guild Finder posting expires in:", "ギルド検索の募集掲載の期限まで:" },
  CLUB_FINDER_DAYS_UNTIL_EXPIRE = { "%d Days", "%d日" },
  GUILD_NAME_ALERT = { "Guild Name Change Alert", "ギルド名の変更に関する警告" },
  CLICK_HERE_FOR_MORE_INFO = { "Click here for more info", "クリックして詳細を表示" },
  GUILD_NAME_ALERT_WARNING = { "Your guild has been flagged for a rename.", "あなたのギルドは名前の変更が必要です。" },
  GUILD_NAME_ALERT_GM_HELP = { "You must pick a new name within the guidelines of our naming policy.",
    "命名規約に沿った新しい名前を選択してください。" },
  GUILD_NAME_ALERT_MEMBER_HELP = { "Your guildmaster must pick a new name within the guidelines of our naming policy.",
    "ギルドマスターが命名規約に沿った新しい名前を選択する必要があります。" },
  RENAME_GUILD_LABEL = { "Enter new guild name:", "新しいギルド名を入力:" }, ACCEPT = { "Accept", "承諾" },
  DECLINE = { "Decline", "辞退" }, CANCEL = { "Cancel", "キャンセル" }, DELETE = { "Delete", "削除" },
  CLOSE = { "Close", "閉じる" }, GUILD = { "Guild", "ギルド" }, SEARCH = { "Search", "検索" },
  FILTER = { "Filter", "フィルター" }, NONE = { "None", "なし" }, INVITE = { "Invite", "招待" },
  COMMUNITIES_CALENDAR_TOOLTIP_TITLE = { "Bulletin", "掲示板" },
  COMMUNITIES_CALENDAR_EVENT_FORMAT = { "%s at %s", "%sの%s" }, COMMUNITIES_CALENDAR_TODAY = { "Today", "今日" },
  WEEKDAY_MONDAY = { "Monday", "月曜日" },
  COMMUNITY_FINDER_FIND_COMMUNITY = { "Find a Community", "コミュニティを探す" },
  COMMUNITIES_GUILD_FINDER = { "Guild Finder", "ギルド検索" },
  COMMUNITIES_LIST_INVITATION_DISPLAY = { "Invited to %s", "%sへの招待" },
  COMMUNITY_TYPE_UNAVAILABLE = { "Currently Unavailable", "現在利用できません" },
  COMMUNITY_INVITATION_FRAME_INVITATION_TEXT = { "%s invited you to join", "%sから参加の招待が届きました" },
  COMMUNITIES_INVITATION_FRAME_TYPE_CHARACTER = { "World of Warcraft Community", "World of Warcraftコミュニティ" },
  COMMUNITIES_INVIVATION_FRAME_LEADER_FORMAT = { "Leader: |cffffffff%s|r", "リーダー: |cffffffff%s|r" },
  COMMUNITIES_INVITATION_FRAME_MEMBER_COUNT = { "Members: |cffffffff%d|r", "メンバー: |cffffffff%d|r" },
  -- guild benefits / preferred play
  GUILD_PERKS_TITLE = { "Guild Perks", "ギルド特典" }, GUILD_REWARDS_TITLE = { "Guild Rewards", "ギルド報酬" },
  GUILD_REPUTATION_COLON = { "Guild Reputation:", "ギルドの評判:" }, GUILD_REPUTATION = { "Guild Reputation", "ギルドの評判" },
  GUILD_EXPERIENCE_CURRENT = { "Current: %s/%s (%s%%)", "現在: %s/%s (%s%%)" },
  REQUIRES_GUILD_FACTION = { "Requires: |cffff0000%s|r", "必要: |cffff0000%s|r" },
  REQUIRES_GUILD_ACHIEVEMENT = { "Requires guild achievement", "ギルド実績が必要" },
  INSPECT_REQUIREMENTS = { "<Ctrl-Click to view requirements>", "<Ctrl+クリックで条件を表示>" },
  FACTION_STANDING_LABEL6 = { "Honored", "尊敬" },
  PREFERRED_PLAY_SETTINGS = { "Preferred Play Settings", "プレイの希望設定" },
  PREFERRED_LOCALE_LABEL = { "Preferred Online Language", "希望するオンライン言語" },
  PREFERRED_GUILD_DATACENTER_LOCALITY_LABEL = { "Preferred Guild Location", "ギルドの希望地域" },
  GUILD_PREFERRED_PLAY_SETTINGS_NO_PERMISSION = { "Only the guild master can change these settings.",
    "この設定を変更できるのはギルドマスターだけです。" },
  APPLY = { "Apply", "決定" }, CLUB_FINDER_APPLY = { "Apply", "決定" },
  -- ClubFinder
  CLUB_FINDER_PENDING_CLUBS_LIST = { "Pending List", "保留中のリスト" },
  CLUB_FINDER_GUILD_SIZE = { "Guild Size", "ギルドの規模" }, CLUB_FINDER_SORT_BY = { "Sort By", "並べ替え" },
  COMMUNITIES_GUILD_FINDER_DESCRIPTION2 = { "Use this tool to find a guild.", "このツールでギルドを探しましょう。" },
  BROWSE_SEARCH_TEXT = { 'Choose search criteria and press "Search"', "検索条件を選んで「検索」を押してください" },
  CLUB_FINDER_SEARCH_NOTHING_FOUND = { "No results found. Try adjusting your search criteria.",
    "結果が見つかりません。検索条件を変えてみてください。" },
  CLUB_FINDER_ANY_FLAG = { "Any", "指定なし" }, SMALL = { "Small", "小" },
  CLUB_FINDER_REQUEST_TO_JOIN = { "Request to Join", "参加をリクエスト" },
  CLUB_FINDER_PENDING = { "Pending", "保留中" }, CLUB_FINDER_DECLINED = { "Declined", "辞退" },
  CLUB_FINDER_FOCUS_STRING = { "Focus: %s", "フォーカス: %s" }, GUILD_INTEREST_RAID = { "Raids", "レイド" },
  CLUB_FINDER_LEADER = { "Leader: |cffffffff%s|r", "リーダー: |cffffffff%s|r" },
  CLUB_FINDER_ACTIVE_MEMBERS = { "Active Members: |cffffffff%d|r", "アクティブなメンバー: |cffffffff%d|r" },
  CLUB_FINDER_ROLE_TOOLTIP = { "Select role to search for %s seeking your role specification",
    "あなたのロールを募集している%sを検索するには、ロールを選択してください" },
  CLUB_FINDER_GUILDS = { "Guilds", "ギルド" },
  CLUB_FINDER_RECRUITING_ONE_SPEC = { "This guild is looking for %s %s. Which specializations do you play?",
    "このギルドは%sの%sを募集しています。あなたはどの専門化をプレイしますか？" },
  CLUB_FINDER_TYPE_GUILD = { "Guild", "ギルド" },
  CLUB_FINDER_ACCEPT_GUILD_STANDARD_WARNING = { "You may only join one guild.", "参加できるギルドは1つだけです。" },
  CLUB_FINDER_LIST_GUILD = { "List My Guild in Guild Finder", "自分のギルドをギルド検索に掲載" },
  CLUB_FINDER_MULTIPLE_ROLES = { "Multiple Classes/Roles", "複数のクラス/ロール" },
  -- applicants
  COMMUNITIES_ROSTER_COLUMN_TITLE_NAME = { "Name", "名前" }, CLUB_FINDER_SPEC = { "Spec", "専門化" },
  ITEM_LEVEL_ABBR = { "iLvl", "アイテムLv" }, CLUB_FINDER_APPROVED = { "Approved", "承認済み" },
  UNIT_TYPE_LEVEL_TEMPLATE = { "Level %d %s", "レベル %d %s" },
  CLUB_FINDER_MAX_MEMBER_COUNT_HIT = { "Max member count reached.", "メンバー数が上限に達しました。" },
  -- dialogs
  COMMUNITIES_SETTINGS_LABEL = { "Group Settings", "グループ設定" },
  COMMUNITIES_SETTINGS_CHARACTER_LABEL = { "Community Settings", "コミュニティ設定" },
  COMMUNITIES_SETTINGS_NAME_LABEL = { "Name", "名前" },
  COMMUNITIES_CREATE_DIALOG_DESCRIPTION_INSTRUCTIONS = { "Optional description of your community",
    "コミュニティの説明 (任意)" },
  CLUB_FINDER_BANNED_POSTING_WARNING = { "Your %s has been banned from posting in the Finder",
    "あなたの%sは検索への掲載を禁止されています" },
  CLUB_FINDER_COMMUNITY_TYPE = { "Community", "コミュニティ" },
  COMMUNITIES_CREATE_DIALOG_NAME_ERROR = { "Name|n%s", "名前|n%s" },
  COMMUNITIES_CREATE_CHANNEL = { "Create Channel", "チャンネルを作成" },
  COMMUNITIES_EDIT_CHANNEL = { "Edit Channel", "チャンネルを編集" },
  COMMUNITIES_CHANNEL_NAME_LABEL = { "Channel Name", "チャンネル名" },
  COMMUNITIES_NOTIFICATION_SETTINGS_DIALOG_QUICK_JOIN_LABEL = { "Quick Join Toasts", "クイック参加の通知" },
  COMMUNITIES_INVITE_MANAGER_LABEL = { "Invite to %s", "%sに招待" },
  COMMUNITIES_INVITE_MANAGER_LINK_TO_CHAT = { "Link to Chat", "チャットにリンク" },
  COMMUNITIES_INVITE_MANAGER_EXPIRES_NEVER = { "Never", "無期限" },
  COMMUNITIES_INVITE_MANAGER_USES_UNLIMITED = { "Unlimited", "無制限" },
  COMMUNITIES_INVITE_MANAGER_COLUMN_TITLE_CREATOR = { "Creator", "作成者" },
  COMMUNITIES_INVITE_MANAGER_COPY_LINK_BUTTON = { "Copy Link", "リンクをコピー" },
  COMMUNITIES_CREATE_DIALOG_AVATAR_PICKER_INSTRUCTIONS = { "Select an Icon", "アイコンを選択" },
  -- the two-part name check (communitiessettings.lua:350–366), the chat-disabled tab line
  -- (communitiesframe.lua:1026–1028) and the chat's client-written lines (communitieschatframe.lua:357–397)
  COMMUNITIES_CREATE_DIALOG_SHORT_NAME_ERROR = { "Short Name|n%s", "短縮名|n%s" },
  COMMUNITIES_CREATE_DIALOG_NAME_AND_SHORT_NAME_ERROR = { "Name|n%s|n|nShort Name|n%s", "名前|n%s|n|n短縮名|n%s" },
  RESTRICT_CHAT_TOOLTIP_FORMAT = { "%s\n%s", "%s\n%s" },
  RESTRICT_CHAT_MESSAGE_SUPPRESSED = { "You can't send or receive messages while chat is disabled.",
    "チャットが無効の間はメッセージを送受信できません。" },
  RESTRICT_CHAT_COMMUNITIES_TOOLTIP_INSTRUCTION = { "<Shift Click to View Chat Options>",
    "<Shiftクリックでチャット設定を表示>" },
  COMMUNITIES_CHAT_FRAME_YESTERDAY_NOTIFICATION = { "Yesterday", "昨日" },
  CLUB_FINDER_RECRUITING_ALL_SPECS = { "All Specs", "すべての専門化" }, -- communitiesutil.lua:342
}

local function en(key) return _G[key] end
local function fs(text) return Stub.fontString(text or "") end
local function btn(text) return Stub.button(nil, text or "") end
local function frame(name) local f = CreateFrame("Frame"); f.name = name; return f end

-- A WowStyle1Dropdown: its selection text is written by UpdateText (Labels.dropdown's writer).
local function dropdown(label)
  local d = frame("Dropdown")
  d.Text, d.Label = fs(), fs(label and en(label) or "")
  function d.UpdateText(self) self.Text.text = self.selection end
  return d
end

-- A ColumnDisplay whose pooled headers were laid out in the list's OnLoad, before this addon.
local function columns(keys)
  local d = frame("ColumnDisplay")
  local active = {}
  d.columnHeaders = { EnumerateActive = function()
    local i = 0
    return function() i = i + 1; return active[i] end
  end }
  function d.LayoutColumns(_, list)
    for i, key in ipairs(list) do active[i] = active[i] or btn(); active[i]:SetText(en(key)) end
    for i = #list + 1, #active do active[i] = nil end
  end
  d:LayoutColumns(keys)
  return d, active
end

local C = {} -- replayed client state

-- The GameTooltip writes an OnEnter makes (GameTooltip_AddColoredLine / GameTooltip_ShowDisabledTooltip end in Show).
local function hover(owner, lines)
  local tt = _G.GameTooltip
  tt:SetOwner(owner)
  tt:SetText(lines[1])
  for i = 2, #lines do tt:AddLine(lines[i]) end
  tt:Show()
end

local function loadWindow()
  local CF = CreateFrame("Frame", "CommunitiesFrame")
  C.CF = CF
  CF.TitleContainer = { TitleText = fs(en("COMMUNITIES_FRAME_TITLE")) }
  local ctrl = frame("CommunitiesControlFrame")
  CF.CommunitiesControlFrame = ctrl
  ctrl.CommunitiesSettingsButton = btn(en("COMMUNITIES_SETTINGS_BUTTON_LABEL"))
  ctrl.GuildControlButton = btn(en("GUILD_CONTROL_BUTTON_TEXT"))
  ctrl.GuildRecruitmentButton = btn(en("GUILD_RECRUITMENT"))
  function ctrl.Update(self) -- communitiesframe.lua:1757
    self.CommunitiesSettingsButton:SetText(C.battleNet and en("COMMUNITIES_SETTINGS_BUTTON_LABEL")
      or en("COMMUNITIES_SETTINGS_BUTTON_CHARACTER_LABEL"))
  end
  CF.GuildLogButton, CF.InviteButton = btn(en("GUILD_VIEW_LOG")), btn(en("COMMUNITIES_INVITE_MEMBERS"))
  Stub.button("JumpToUnreadButton", en("COMMUNITIES_FRAME_JUMP_TO_UNREAD"))
  CF.AddToChatButton = { Label = fs(en("COMMUNITIES_ADD_TO_CHAT")) }
  CF.ChatTab = CreateFrame("CheckButton")
  CF.ChatTab.tooltip = en("COMMUNITIES_CHAT_TAB_TOOLTIP")
  -- the chat's ScrollingMessageFrame (communitieschatframe.xml:6): its history, rewritten by TransformMessages
  local messages = { history = {} }
  function messages.AddMessage(self, text) self.history[#self.history + 1] = text end
  function messages.BackFillMessage(self, text) table.insert(self.history, 1, text) end
  function messages.TransformMessages(self, pick, change)
    for i, text in ipairs(self.history) do
      if pick(text) then self.history[i] = (change(text)) end
    end
  end
  CF.Chat = { MessageFrame = messages }
  CF.PostingExpirationText = { ExpirationTimeText = fs(), DaysUntilExpire = fs(), ExpiredText = fs(),
    InfoButton = CreateFrame("Button") }
  function CF.SetClubFinderPostingExpirationText(self, days) -- lua:829–833
    self.PostingExpirationText.ExpirationTimeText:SetText(en("GUILD_FINDER_POSTING_GOING_TO_EXPIRE"))
    self.PostingExpirationText.DaysUntilExpire:SetText(en("CLUB_FINDER_DAYS_UNTIL_EXPIRE"):format(days))
  end
  CF.GuildNameAlertFrame = { Alert = fs(en("GUILD_NAME_ALERT")), ClickText = fs(en("CLICK_HERE_FOR_MORE_INFO")) }
  CF.GuildNameChangeFrame = { Error = fs(en("GUILD_NAME_ALERT_WARNING")), GMText = fs(en("GUILD_NAME_ALERT_GM_HELP")),
    RenameText = fs(en("RENAME_GUILD_LABEL")), Button = btn(en("ACCEPT")), EditBox = CreateFrame("EditBox") }
  function CF.ShowGuildNameAlertFrame(self, text) self.GuildNameAlertFrame.Alert:SetText(text) end
  function CF.DisplayReportedAlerts(self)
    self.GuildNameChangeFrame.GMText:SetText(C.leader and en("GUILD_NAME_ALERT_GM_HELP")
      or en("GUILD_NAME_ALERT_MEMBER_HELP"))
    self:ShowGuildNameAlertFrame(en("GUILD_NAME_ALERT"))
  end
  CF.CommunitiesCalendarButton = CreateFrame("Button")
  -- communities list (communitieslist.lua:402–667)
  CF.CommunitiesList = { ScrollBox = Stub.scrollBox() }
  C.listRows = {}
  function C.listEntry(i, data)
    local row = C.listRows[i]
    if not row then row = CreateFrame("Button"); row.Name = fs(); C.listRows[i] = row end
    CF.CommunitiesList.ScrollBox:initFrame(row, data, function(r, d) -- Init (lua:402–531)
      if d.setFindCommunity then r.Name:SetText(en("COMMUNITY_FINDER_FIND_COMMUNITY"))
      elseif d.setGuildFinder then r.Name:SetText(en("COMMUNITIES_GUILD_FINDER"))
      elseif d.clubInfo.isInvitation then
        r.Name:SetText(en("COMMUNITIES_LIST_INVITATION_DISPLAY"):format(d.clubInfo.name))
      else r.Name:SetText(d.clubInfo.name) end
    end)
    return row
  end
  -- the invitation panel (communitiesinvitationframe.lua:36–86)
  local inv = CreateFrame("Frame")
  inv.name = "InvitationFrame"
  CF.InvitationFrame = inv
  inv.InvitationText, inv.Type, inv.Name = fs(), fs(), fs()
  inv.Leader, inv.MemberCount, inv.Description = fs(), fs(), fs()
  inv.AcceptButton, inv.DeclineButton = btn(en("ACCEPT")), btn(en("DECLINE"))
  function inv.DisplayInvitation(self, info)
    self.InvitationText:SetText(en("COMMUNITY_INVITATION_FRAME_INVITATION_TEXT"):format(info.inviter))
    self.Type:SetText(en("COMMUNITIES_INVITATION_FRAME_TYPE_CHARACTER"))
    self.Name:SetText(info.club)
    self.Leader:SetText(en("COMMUNITIES_INVIVATION_FRAME_LEADER_FORMAT"):format(info.leader))
    self.MemberCount:SetText(en("COMMUNITIES_INVITATION_FRAME_MEMBER_COUNT"):format(info.members))
  end
  -- guild benefits (communitiesframe.xml:4–60; guildrewards.lua / .xml; guildperks.xml)
  local ben = frame("GuildBenefitsFrame")
  CF.GuildBenefitsFrame = ben
  ben.Perks = { TitleText = fs(en("GUILD_PERKS_TITLE")) }
  ben.Rewards = { TitleText = fs(en("GUILD_REWARDS_TITLE")), ScrollBox = Stub.scrollBox() }
  ben.FactionFrame = { Label = fs(en("GUILD_REPUTATION_COLON")), Bar = CreateFrame("Frame") }
  _G.CommunitiesGuildRewardsButton_OnEnter = function(self) -- guildrewards.lua:102–129 (an item tooltip)
    local tt = _G.GameTooltip
    tt:SetOwner(self)
    tt:SetText(self.Name:GetText())
    tt.item = { name = self.Name:GetText(), link = "item:1" }
    tt:AddLine(" ")
    tt:AddLine(en("REQUIRES_GUILD_ACHIEVEMENT"))
    tt:AddLine("Guild Level 5") -- the achievement's name
    tt:AddLine(" ")
    tt:AddLine(en("INSPECT_REQUIREMENTS"))
    tt:Show()
  end
  C.rewardRows = {}
  function C.reward(i, data)
    local row = C.rewardRows[i]
    if not row then
      row = CreateFrame("Button"); row.Name, row.SubText = fs(), fs(); C.rewardRows[i] = row
      row.scripts.OnEnter = _G.CommunitiesGuildRewardsButton_OnEnter -- bound in XML with function= (xml:202)
    end
    ben.Rewards.ScrollBox:initFrame(row, data, function(r, d)
      r.Name:SetText(d.item)
      r.SubText:SetText(en("REQUIRES_GUILD_FACTION"):format(en("FACTION_STANDING_LABEL6")))
    end)
    return row
  end
  local play = frame("GuildPreferredPlaySettingsFrame")
  CF.GuildPreferredPlaySettingsFrame = play
  play.Title, play.LocaleLabel = fs(en("PREFERRED_PLAY_SETTINGS")), fs(en("PREFERRED_LOCALE_LABEL"))
  play.DatacenterLabel = fs(en("PREFERRED_GUILD_DATACENTER_LOCALITY_LABEL"))
  play.NotGuildMasterNotice = fs()
  play.LocaleApplyButton, play.DatacenterApplyButton = btn(en("APPLY")), btn(en("APPLY"))
  function play.RefreshState(self)
    self.NotGuildMasterNotice:SetText(en("GUILD_PREFERRED_PLAY_SETTINGS_NO_PERMISSION"))
  end
  C.loadFinder(CF)
  C.loadDialogs(CF)
  Stub.loadedAddons[ADDON] = true
  return CF
end

-- clubfinder.lua / .xml: one finder panel, the finder invitation panel, the recruitment dialog, the applicant list
function C.loadFinder(CF)
  local function card()
    local c = CreateFrame("Button")
    c.Name, c.Description, c.MemberCount, c.RequestStatus, c.Focus = fs(), fs(), fs(), fs(), fs()
    c.RequestJoin = btn(en("CLUB_FINDER_REQUEST_TO_JOIN"))
    function c.UpdateCard(self) -- lua:1234–1290
      self.Name:SetText(self.cardInfo.name)
      self.Focus:SetText(en("CLUB_FINDER_FOCUS_STRING"):format(self.cardInfo.focus))
      self.RequestStatus:SetText(self.cardInfo.status and en(self.cardInfo.status) or "")
    end
    return c
  end
  local p = CreateFrame("Frame", "ClubFinderGuildFinderFrame")
  CF.GuildFinderFrame = p
  p.isGuildType = true
  p.OptionsList = { PendingTextFrame = { Text = fs(en("CLUB_FINDER_PENDING_CLUBS_LIST")) },
    ClubFilterDropdown = dropdown("FILTER"), ClubSizeDropdown = dropdown("CLUB_FINDER_GUILD_SIZE"),
    SortByDropdown = dropdown("CLUB_FINDER_SORT_BY"), Search = btn(en("SEARCH")),
    SearchBox = CreateFrame("EditBox"), TankRoleFrame = { Checkbox = CreateFrame("CheckButton") } }
  p.OptionsList.SearchBox.Instructions = fs(en("SEARCH"))
  p.InsetFrame = CreateFrame("Frame")
  p.InsetFrame.GuildDescription, p.InsetFrame.ErrorDescription = fs(en("COMMUNITIES_GUILD_FINDER_DESCRIPTION2")), fs()
  p.GuildCards = frame("GuildCards")
  p.GuildCards.Cards = { card(), card(), card() }
  function p.GuildCards.BuildCardList(self) self:GetParent().InsetFrame.GuildDescription:SetText(
    en("CLUB_FINDER_SEARCH_NOTHING_FOUND")) end
  function p.GuildCards.GetParent() return p end
  function p.UpdateType(self) self.InsetFrame.GuildDescription:SetText(en("BROWSE_SEARCH_TEXT")) end
  local rtj = frame("RequestToJoinFrame")
  p.RequestToJoinFrame = rtj
  rtj.DialogLabel, rtj.ClubName, rtj.RecruitingSpecDescriptions = fs(en("CLUB_FINDER_REQUEST_TO_JOIN")), fs(), fs()
  rtj.Apply = btn(en("CLUB_FINDER_APPLY"))
  function rtj.Initialize(self) -- lua:444–451
    self.ClubName:SetText(self.card.cardInfo.name)
    self.RecruitingSpecDescriptions:SetText(en("CLUB_FINDER_RECRUITING_ONE_SPEC"):format("Holy", "Priest"))
  end
  local ci = frame("ClubFinderInvitationFrame")
  CF.ClubFinderInvitationFrame = ci
  ci.Type, ci.Name, ci.Leader, ci.MemberCount, ci.InvitationText = fs(), fs(), fs(), fs(), fs()
  ci.ApplyButton = btn(en("CLUB_FINDER_APPLY"))
  ci.WarningDialog = CreateFrame("Frame")
  ci.WarningDialog.DialogLabel = fs()
  ci.WarningDialog:SetScript("OnShow", function(self) -- lua:2167–2175, XML-bound
    self.DialogLabel:SetText(en("CLUB_FINDER_ACCEPT_GUILD_STANDARD_WARNING"))
  end)
  function ci.DisplayInvitation(self, info)
    self.Type:SetText(en("CLUB_FINDER_TYPE_GUILD"))
    self.Name:SetText(info.name)
    self.Leader:SetText(en("COMMUNITIES_INVIVATION_FRAME_LEADER_FORMAT"):format(info.leader))
    self.InvitationText:SetText(en("COMMUNITY_INVITATION_FRAME_INVITATION_TEXT"):format(info.leader))
  end
  CF.RecruitmentDialog = { ShouldListClub = { Label = fs(en("CLUB_FINDER_LIST_GUILD")) },
    LookingForDropdown = dropdown("CLUB_FINDER_LOOKING_FOR") }
  local al = frame("ApplicantList")
  CF.ApplicantList = al
  al.ColumnDisplay, C.applicantHeaders = columns({ "COMMUNITIES_ROSTER_COLUMN_TITLE_NAME", "CLUB_FINDER_SPEC",
    "ITEM_LEVEL_ABBR" })
  al.ScrollBox = Stub.scrollBox()
  C.applicants = {}
  function C.applicant(i, info)
    local row = C.applicants[i]
    if not row then
      row = CreateFrame("Button")
      row.Name, row.Level, row.RequestStatus, row.AllSpec = fs(), fs(), fs(), fs()
      row.InviteButton = CreateFrame("Button")
      row.InviteButton.Text = fs(en("INVITE"))
      C.applicants[i] = row
    end
    al.ScrollBox:initFrame(row, info, function(r, d) -- UpdateMemberInfo (clubfinderapplicantlist.lua:86–190)
      r.Name:SetText(d.name)
      r.Level:SetText(d.level)
      r.RequestStatus:SetText(en(d.status))
      r.AllSpec:SetText(en("NONE"))
    end)
    return row
  end
end

-- communitiessettings / communitiesstreams / communitiesticketmanagerdialog / communitiesavatarpickerdialog
function C.loadDialogs(CF)
  local sd = CreateFrame("Frame", "CommunitiesSettingsDialog")
  sd.DialogLabel, sd.NameLabel = fs(en("COMMUNITIES_SETTINGS_LABEL")), fs(en("COMMUNITIES_SETTINGS_NAME_LABEL"))
  sd.NameEdit = CreateFrame("EditBox")
  sd.Description = { EditBox = CreateFrame("EditBox") }
  sd.Description.EditBox.Instructions = fs()
  sd.ClubFinderPostingBannedError = fs()
  sd.Accept = btn(en("ACCEPT"))
  sd:SetScript("OnShow", function(self) self.DialogLabel:SetText(en("COMMUNITIES_SETTINGS_CHARACTER_LABEL")) end)
  function sd.SetClubId(self, club)
    self.NameEdit:SetText(club)
    self.Description.EditBox.Instructions:SetText(en("COMMUNITIES_CREATE_DIALOG_DESCRIPTION_INSTRUCTIONS"))
  end
  function sd.HideOrShowCommunityFinderOptions(self)
    self.ClubFinderPostingBannedError:SetText(en("CLUB_FINDER_BANNED_POSTING_WARNING"):format(
      en("CLUB_FINDER_COMMUNITY_TYPE")))
  end
  local es = frame("EditStreamDialog")
  CF.EditStreamDialog = es
  es.TitleLabel, es.NameLabel, es.NameEdit = fs(), fs(en("COMMUNITIES_CHANNEL_NAME_LABEL")), CreateFrame("EditBox")
  function es.ShowCreateDialog(self) self.TitleLabel:SetText(en("COMMUNITIES_CREATE_CHANNEL")) end
  function es.ShowEditDialog(self, _, stream)
    self.TitleLabel:SetText(en("COMMUNITIES_EDIT_CHANNEL"))
    self.NameEdit:SetText(stream)
  end
  CF.NotificationSettingsDialog = { ScrollFrame = { Child = { QuickJoinButton = { Text = fs(
    en("COMMUNITIES_NOTIFICATION_SETTINGS_DIALOG_QUICK_JOIN_LABEL")) } } } }
  local tm = CreateFrame("Frame", "CommunitiesTicketManagerDialog")
  tm.DialogLabel = fs(en("COMMUNITIES_INVITE_MANAGER_LABEL"))
  tm.LinkToChat = btn(en("COMMUNITIES_INVITE_MANAGER_LINK_TO_CHAT"))
  tm.UsesText, tm.ExpiresText, tm.LinkIDText = fs("50"), fs("00:06:41"), fs("awd6sdw9")
  tm.ExpiresDropdown = dropdown()
  tm:SetScript("OnShow", function(self)
    self.DialogLabel:SetText(en("COMMUNITIES_INVITE_MANAGER_LABEL"):format(C.club))
  end)
  function tm.RefreshLink(self)
    self.UsesText:SetText(en("COMMUNITIES_INVITE_MANAGER_USES_UNLIMITED"))
    self.ExpiresText:SetText(en("COMMUNITIES_INVITE_MANAGER_EXPIRES_NEVER"))
  end
  tm.InviteManager = { ScrollBox = Stub.scrollBox() }
  tm.InviteManager.ColumnDisplay = columns({ "COMMUNITIES_INVITE_MANAGER_COLUMN_TITLE_CREATOR" })
  C.tickets = {}
  function C.ticket(i, info)
    local row = C.tickets[i]
    if not row then
      row = CreateFrame("Button")
      row.Creator, row.Link, row.Uses, row.Expires = fs(), fs(), fs(), fs()
      row.CopyLinkButton = btn(en("COMMUNITIES_INVITE_MANAGER_COPY_LINK_BUTTON"))
      function row.SetTicket(self, t)
        self.Creator:SetText(t.creator)
        self.Uses:SetText(en("COMMUNITIES_INVITE_MANAGER_USES_UNLIMITED"))
        self.Expires:SetText(en("COMMUNITIES_INVITE_MANAGER_EXPIRES_NEVER"))
      end
      C.tickets[i] = row
    end
    tm.InviteManager.ScrollBox:initFrame(row, info, function(r, d) r:SetTicket(d) end)
    return row
  end
  local picker = CreateFrame("Frame", "CommunitiesAvatarPickerDialog")
  picker:addRegion(fs(en("COMMUNITIES_CREATE_DIALOG_AVATAR_PICKER_INSTRUCTIONS")))
end

describe("the rest of the Communities window on Forever", function()
  local WFJ

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  local function setup(loadedFirst)
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    C.battleNet, C.leader, C.club = false, false, "Night Watch"
    if loadedFirst then
      loadWindow()
      for _, m in ipairs(MODULES) do assert.is_true(WFJ[m].init(), m) end
    else
      for _, m in ipairs(MODULES) do assert.is_false(WFJ[m].init(), m) end -- each waits for the addon
      loadWindow()
      assert.are.equal(#MODULES, WFJ.LoadOnDemand.loaded(ADDON))
    end
  end

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    for _, g in ipairs({ "CommunitiesFrame", "ClubFinderGuildFinderFrame", "CommunitiesSettingsDialog",
      "CommunitiesTicketManagerDialog", "CommunitiesAvatarPickerDialog", "JumpToUnreadButton",
      "CommunitiesGuildRewardsButton_OnEnter" }) do _G[g] = nil end
  end)

  for _, order in ipairs({ { true, "loaded at login" }, { false, "loaded on demand" } }) do
    describe("Blizzard_Communities " .. order[2], function()
      before_each(function() setup(order[1]) end)

      it("the frame's chrome: title, buttons, chat word, control button, posting countdown, rename alert", function()
        local CF = _G.CommunitiesFrame
        assert.are.equal("ギルド&コミュニティ", CF.TitleContainer.TitleText:GetText())
        assert.are.equal("ギルド設定", CF.CommunitiesControlFrame.GuildControlButton:GetText())
        assert.are.equal("ログを表示", CF.GuildLogButton:GetText())
        assert.are.equal("未読", _G.JumpToUnreadButton:GetText())
        assert.are.equal("チャットウィンドウに追加", CF.AddToChatButton.Label:GetText())
        CF.CommunitiesControlFrame:Update()
        assert.are.equal("コミュニティ設定", CF.CommunitiesControlFrame.CommunitiesSettingsButton:GetText())
        CF:SetClubFinderPostingExpirationText(12)
        assert.are.equal("ギルド検索の募集掲載の期限まで:", CF.PostingExpirationText.ExpirationTimeText:GetText())
        assert.are.equal("12日", CF.PostingExpirationText.DaysUntilExpire:GetText())
        CF:DisplayReportedAlerts()
        assert.are.equal("ギルド名の変更に関する警告", CF.GuildNameAlertFrame.Alert:GetText())
        assert.are.equal("ギルドマスターが命名規約に沿った新しい名前を選択する必要があります。",
          CF.GuildNameChangeFrame.GMText:GetText())
        assert.are.equal("新しいギルド名を入力:", CF.GuildNameChangeFrame.RenameText:GetText())
        alt(true)
        assert.are.equal("Guild & Communities", CF.TitleContainer.TitleText:GetText())
        alt(false)
        hover(CF.ChatTab, { en("COMMUNITIES_CHAT_TAB_TOOLTIP") })
        assert.are.equal("チャット", _G.GameTooltipTextLeft1:GetText())
        hover(CF.InviteButton, { en("CLUB_INVITER_FAIL_GUILD_CAPACITY") })
        assert.are.equal("ギルドが満員のため、新しいメンバーを招待できません。", _G.GameTooltipTextLeft1:GetText())
      end)

      it("the calendar tooltip: title and event line Japanese, the event title stays English", function()
        hover(_G.CommunitiesFrame.CommunitiesCalendarButton, { en("COMMUNITIES_CALENDAR_TOOLTIP_TITLE"), "Search",
          en("COMMUNITIES_CALENDAR_EVENT_FORMAT"):format("Monday", "8:00 PM") })
        assert.are.equal("掲示板", _G.GameTooltipTextLeft1:GetText())
        assert.are.equal("Search", _G.GameTooltipTextLeft2:GetText()) -- an event called like a UI word
        assert.are.equal("月曜日の8:00 PM", _G.GameTooltipTextLeft3:GetText())
      end)

      it("the communities list: the finder entries Japanese, a club called like one stays English", function()
        local finder = C.listEntry(1, { setFindCommunity = true })
        local guild = C.listEntry(2, { setGuildFinder = true })
        local invite = C.listEntry(3, { clubInfo = { isInvitation = true, name = "Night Watch" } })
        assert.are.equal("コミュニティを探す", finder.Name:GetText())
        assert.are.equal("ギルド検索", guild.Name:GetText())
        assert.are.equal("Night Watchへの招待", invite.Name:GetText())
        C.listEntry(1, { clubInfo = { name = "Guild Finder" } }) -- the reused row: a club named like a UI word
        assert.are.equal("Guild Finder", finder.Name:GetText())
        alt(true); alt(false)
        assert.are.equal("Guild Finder", finder.Name:GetText())
      end)

      it("the invitation panel: fixed words Japanese, the community, inviter and leader names English", function()
        local inv = _G.CommunitiesFrame.InvitationFrame
        inv:DisplayInvitation({ inviter = "Thrall", club = "Invite", leader = "Jaina, Thrall", members = 12 })
        assert.are.equal("Thrallから参加の招待が届きました", inv.InvitationText:GetText())
        assert.are.equal("World of Warcraftコミュニティ", inv.Type:GetText())
        assert.are.equal("リーダー: |cffffffffJaina, Thrall|r", inv.Leader:GetText())
        assert.are.equal("メンバー: |cffffffff12|r", inv.MemberCount:GetText())
        assert.are.equal("Invite", inv.Name:GetText())
        assert.are.equal("承諾", inv.AcceptButton:GetText())
      end)

      it("guild rewards and perks: titles, a reward's requirement, its tooltip lines; the item name stays", function()
        local ben = _G.CommunitiesFrame.GuildBenefitsFrame
        assert.are.equal("ギルド特典", ben.Perks.TitleText:GetText())
        assert.are.equal("ギルド報酬", ben.Rewards.TitleText:GetText())
        assert.are.equal("ギルドの評判:", ben.FactionFrame.Label:GetText())
        local row = C.reward(1, { item = "Search" }) -- an item called like a UI word
        assert.are.equal("必要: |cffff0000尊敬|r", row.SubText:GetText())
        assert.are.equal("Search", row.Name:GetText())
        row.scripts.OnEnter(row)
        assert.are.equal("Search", _G.GameTooltipTextLeft1:GetText())
        assert.are.equal("ギルド実績が必要", _G.GameTooltipTextLeft3:GetText())
        assert.are.equal("Guild Level 5", _G.GameTooltipTextLeft4:GetText())
        assert.are.equal("<Ctrl+クリックで条件を表示>", _G.GameTooltipTextLeft6:GetText())
        _G.GameTooltip:Hide()
        hover(ben.FactionFrame.Bar, { en("GUILD_REPUTATION"), "Guild description.",
          en("GUILD_EXPERIENCE_CURRENT"):format("1,200", "3,000", 40) })
        assert.are.equal("ギルドの評判", _G.GameTooltipTextLeft1:GetText())
        assert.are.equal("現在: 1,200/3,000 (40%)", _G.GameTooltipTextLeft3:GetText())
      end)

      it("preferred play settings: labels, apply buttons and the guild-master notice", function()
        local play = _G.CommunitiesFrame.GuildPreferredPlaySettingsFrame
        assert.are.equal("プレイの希望設定", play.Title:GetText())
        assert.are.equal("決定", play.LocaleApplyButton:GetText())
        play:RefreshState()
        assert.are.equal("この設定を変更できるのはギルドマスターだけです。", play.NotGuildMasterNotice:GetText())
      end)

      it("ClubFinder search and options: labels, description, dropdown selection; a spec selection stays", function()
        local p = _G.CommunitiesFrame.GuildFinderFrame
        assert.are.equal("保留中のリスト", p.OptionsList.PendingTextFrame.Text:GetText())
        assert.are.equal("ギルドの規模", p.OptionsList.ClubSizeDropdown.Label:GetText())
        assert.are.equal("検索", p.OptionsList.Search:GetText())
        assert.are.equal("このツールでギルドを探しましょう。", p.InsetFrame.GuildDescription:GetText())
        p:UpdateType()
        assert.are.equal("検索条件を選んで「検索」を押してください", p.InsetFrame.GuildDescription:GetText())
        p.GuildCards:BuildCardList()
        assert.are.equal("結果が見つかりません。検索条件を変えてみてください。", p.InsetFrame.GuildDescription:GetText())
        local size = p.OptionsList.ClubSizeDropdown
        size.selection = en("SMALL"); size:UpdateText()
        assert.are.equal("小", size.Text:GetText())
        local looking = _G.CommunitiesFrame.RecruitmentDialog.LookingForDropdown
        looking.selection = "Holy Priest"; looking:UpdateText()
        assert.are.equal("Holy Priest", looking.Text:GetText())
        looking.selection = en("CLUB_FINDER_MULTIPLE_ROLES"); looking:UpdateText()
        assert.are.equal("複数のクラス/ロール", looking.Text:GetText())
        hover(p.OptionsList.TankRoleFrame.Checkbox, { en("CLUB_FINDER_ROLE_TOOLTIP"):format(en("CLUB_FINDER_GUILDS")) })
        assert.are.equal("あなたのロールを募集しているギルドを検索するには、ロールを選択してください",
          _G.GameTooltipTextLeft1:GetText())
      end)

      it("ClubFinder cards and request to join: status, focus and tooltip Japanese; club names English", function()
        local p = _G.CommunitiesFrame.GuildFinderFrame
        local card = p.GuildCards.Cards[1]
        card.cardInfo = { name = "Pending", focus = en("GUILD_INTEREST_RAID"), status = "CLUB_FINDER_DECLINED" }
        card:UpdateCard()
        assert.are.equal("辞退", card.RequestStatus:GetText())
        assert.are.equal("フォーカス: レイド", card.Focus:GetText())
        assert.are.equal("Pending", card.Name:GetText()) -- a guild called like a status word
        assert.are.equal("参加をリクエスト", card.RequestJoin:GetText())
        hover(p.GuildCards, { "Pending", en("CLUB_FINDER_ACTIVE_MEMBERS"):format(30),
          en("CLUB_FINDER_LEADER"):format("Thrall") })
        assert.are.equal("Pending", _G.GameTooltipTextLeft1:GetText())
        assert.are.equal("アクティブなメンバー: |cffffffff30|r", _G.GameTooltipTextLeft2:GetText())
        assert.are.equal("リーダー: |cffffffffThrall|r", _G.GameTooltipTextLeft3:GetText())
        hover(p.GuildCards, { "Pending", en("CLUB_FINDER_RECRUITING_ALL_SPECS") }) -- AddLookingForLines
        assert.are.equal("すべての専門化", _G.GameTooltipTextLeft2:GetText())
        p.RequestToJoinFrame.card = card
        p.RequestToJoinFrame:Initialize()
        assert.are.equal("このギルドはHolyのPriestを募集しています。あなたはどの専門化をプレイしますか？",
          p.RequestToJoinFrame.RecruitingSpecDescriptions:GetText())
        assert.are.equal("Pending", p.RequestToJoinFrame.ClubName:GetText())
        assert.are.equal("決定", p.RequestToJoinFrame.Apply:GetText())
      end)

      it("the finder invitation panel and its join warning", function()
        local ci = _G.CommunitiesFrame.ClubFinderInvitationFrame
        ci:DisplayInvitation({ name = "Guild", leader = "Thrall" })
        assert.are.equal("ギルド", ci.Type:GetText())
        assert.are.equal("Guild", ci.Name:GetText()) -- a guild named "Guild"
        assert.are.equal("Thrallから参加の招待が届きました", ci.InvitationText:GetText())
        ci.WarningDialog:Show()
        assert.are.equal("参加できるギルドは1つだけです。", ci.WarningDialog.DialogLabel:GetText())
      end)

      it("the applicant list: headers, status, the no-spec word and tooltip; the applicant stays English", function()
        local h = {}
        for i, header in ipairs(C.applicantHeaders) do h[i] = header:GetText() end
        assert.are.same({ "名前", "専門化", "アイテムLv" }, h)
        local row = C.applicant(1, { name = "Approved", level = 60, status = "CLUB_FINDER_APPROVED" })
        assert.are.equal("承認済み", row.RequestStatus:GetText())
        assert.are.equal("なし", row.AllSpec:GetText())
        assert.are.equal("招待", row.InviteButton.Text:GetText())
        assert.are.equal("Approved", row.Name:GetText())
        hover(row, { "Approved", en("UNIT_TYPE_LEVEL_TEMPLATE"):format(60, "Priest") })
        assert.are.equal("Approved", _G.GameTooltipTextLeft1:GetText())
        assert.are.equal("レベル 60 Priest", _G.GameTooltipTextLeft2:GetText())
        hover(row.InviteButton, { en("CLUB_FINDER_MAX_MEMBER_COUNT_HIT") })
        assert.are.equal("メンバー数が上限に達しました。", _G.GameTooltipTextLeft1:GetText())
      end)

      it("community settings: title, placeholder, banned notice, name error tooltip; the name box untouched", function()
        local sd = _G.CommunitiesSettingsDialog
        sd:SetClubId("Name")
        sd:Show()
        sd:HideOrShowCommunityFinderOptions()
        assert.are.equal("コミュニティ設定", sd.DialogLabel:GetText())
        assert.are.equal("名前", sd.NameLabel:GetText())
        assert.are.equal("コミュニティの説明 (任意)", sd.Description.EditBox.Instructions:GetText())
        assert.are.equal("あなたのコミュニティは検索への掲載を禁止されています", sd.ClubFinderPostingBannedError:GetText())
        assert.are.equal("Name", sd.NameEdit:GetText())
        hover(sd.Accept, { en("COMMUNITIES_CREATE_DIALOG_NAME_ERROR"):format("|cffff2020Too short|r") })
        assert.are.equal("名前|n|cffff2020Too short|r", _G.GameTooltipTextLeft1:GetText())
      end)

      it("a name-check error ending in a period, and the two-part one, keep the client's sentence",
        function()
          local sd = _G.CommunitiesSettingsDialog
          local err = "|cffff2020Names can't contain the word \"Blizzard\".|r"
          hover(sd.Accept, { en("COMMUNITIES_CREATE_DIALOG_NAME_ERROR"):format(err) })
          assert.are.equal("名前|n" .. err, _G.GameTooltipTextLeft1:GetText())
          local short = "|cffff2020Too long.|r"
          hover(sd.Accept, { en("COMMUNITIES_CREATE_DIALOG_NAME_AND_SHORT_NAME_ERROR"):format(err, short) })
          assert.are.equal("名前|n" .. err .. "|n|n短縮名|n" .. short, _G.GameTooltipTextLeft1:GetText())
          alt(true)
          assert.are.equal("Name|n" .. err .. "|n|nShort Name|n" .. short, _G.GameTooltipTextLeft1:GetText())
          alt(false)
          hover(CreateFrame("Button"), { "Name|nwhatever." }) -- not a registered owner: never matched
          assert.are.equal("Name|nwhatever.", _G.GameTooltipTextLeft1:GetText())
        end)

      it("the chat tab's chat-disabled line: both sentences in Japanese, the green instruction's colour kept",
        function()
          local CF = _G.CommunitiesFrame
          local line = en("RESTRICT_CHAT_MESSAGE_SUPPRESSED") .. "\n|cff20ff20<Shift Click to View Chat Options>|r"
          hover(CF.ChatTab, { en("COMMUNITIES_CHAT_TAB_TOOLTIP"), line })
          assert.are.equal("チャット", _G.GameTooltipTextLeft1:GetText())
          assert.are.equal("チャットが無効の間はメッセージを送受信できません。\n|cff20ff20<Shiftクリックでチャット設定を表示>|r",
            _G.GameTooltipTextLeft2:GetText())
          alt(true)
          assert.are.equal(line, _G.GameTooltipTextLeft2:GetText())
          alt(false)
        end)

      it("the chat's date separator arrives in Japanese; a member's message is untouched", function()
        local m = _G.CommunitiesFrame.Chat.MessageFrame
        m:AddMessage("Yesterday")
        m:BackFillMessage("Yesterday")
        m:AddMessage("[Thrall]: Yesterday was fun.")
        assert.are.same({ "昨日", "昨日", "[Thrall]: Yesterday was fun." }, m.history)
      end)

      it("the streams dialogs: create / edit title and labels; the channel name untouched", function()
        local es = _G.CommunitiesFrame.EditStreamDialog
        es:ShowCreateDialog(1)
        assert.are.equal("チャンネルを作成", es.TitleLabel:GetText())
        es:ShowEditDialog(1, "Chat")
        assert.are.equal("チャンネルを編集", es.TitleLabel:GetText())
        assert.are.equal("チャンネル名", es.NameLabel:GetText())
        assert.are.equal("Chat", es.NameEdit:GetText())
        assert.are.equal("クイック参加の通知",
          _G.CommunitiesFrame.NotificationSettingsDialog.ScrollFrame.Child.QuickJoinButton.Text:GetText())
      end)

      it("the ticket manager: label with the community name, link values, rows, headers; creators untouched",
        function()
          local tm = _G.CommunitiesTicketManagerDialog
          tm:Show()
          assert.are.equal("Night Watchに招待", tm.DialogLabel:GetText())
          tm:RefreshLink()
          assert.are.equal("無制限", tm.UsesText:GetText())
          assert.are.equal("無期限", tm.ExpiresText:GetText())
          assert.are.equal("チャットにリンク", tm.LinkToChat:GetText())
          local row = C.ticket(1, { creator = "Never" })
          assert.are.equal("無期限", row.Expires:GetText())
          assert.are.equal("リンクをコピー", row.CopyLinkButton:GetText())
          assert.are.equal("Never", row.Creator:GetText()) -- a player called like the expiry word
          row:SetTicket({ creator = "Never" })
          assert.are.equal("Never", row.Creator:GetText())
          assert.are.equal("アイコンを選択", (_G.CommunitiesAvatarPickerDialog:GetRegions()):GetText())
        end)
    end)
  end

  it("a name bound to the wrong type degrades to English with no error", function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    local CF = loadWindow()
    -- camelot-shaped names bound to the wrong types: a number, a string, a frame with no text
    CF.TitleContainer = 7
    CF.GuildFinderFrame.OptionsList = "options"
    CF.CommunitiesControlFrame.GuildControlButton = CreateFrame("Frame")
    CF.GuildBenefitsFrame.Perks = true
    _G.CommunitiesSettingsDialog.NameLabel = 42
    CF.ApplicantList.ColumnDisplay = 3
    _G.CommunitiesTicketManagerDialog.InviteManager = false
    for _, m in ipairs(MODULES) do assert.is_true(WFJ[m].init(), m) end
    assert.are.equal("ギルド報酬", CF.GuildBenefitsFrame.Rewards.TitleText:GetText()) -- its sibling Perks is broken
    assert.are.equal("ログを表示", CF.GuildLogButton:GetText()) -- the rest still renders
    CF.CommunitiesControlFrame:Update()
    assert.are.equal("コミュニティ設定", CF.CommunitiesControlFrame.CommunitiesSettingsButton:GetText())
  end)

  it("hooks install once", function()
    setup(true)
    for _, m in ipairs(MODULES) do assert.is_false(WFJ[m].setup(), m) end
    assert.are.equal(1, #Stub.hooks["CommunitiesControlFrame:Update"])
    assert.are.equal(1, #Stub.hooks["InvitationFrame:DisplayInvitation"])
    assert.are.equal(1, #Stub.hooks["RequestToJoinFrame:Initialize"])
    assert.are.equal(1, #Stub.hooks["EditStreamDialog:ShowCreateDialog"])
  end)
end)
