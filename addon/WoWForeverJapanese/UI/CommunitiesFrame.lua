-- UI/CommunitiesFrame.lua: the Communities window's own chrome on Forever (surface "communities.frame", area "ui",
-- ADR-016): its title, side tabs, bottom buttons, the finder-posting countdown, the rename / posting
-- alerts, the calendar button, the chat frame's fixed words, the communities list's fixed entries and the two
-- invitation panels. The guild view is UI/Communities; ClubFinder, the guild benefits and the dialogs have
-- their own modules. Plumbing: UI/CommunitiesKit..
-- Every file:line below is the camelot extract 1.60.1.69913, interface/addons/blizzard_communities/.
-- Static labels (XML text= or an OnLoad write; each restricted to its own key):
--   the title (CommunitiesFrameMixin:OnLoad → SetTitle, communitiesframe.lua:103); CommunitiesControlFrame's
--   GuildControlButton / GuildRecruitmentButton (communitiesframe.xml:258, 267); GuildLogButton (xml:604);
--   InviteButton (CommunitiesInviteButtonTemplate, communitiesinvitationframe.xml:130); the chat's
--   JumpToUnreadButton (a global name, communitieschatframe.xml:29); AddToChatButton.Label
--   (communitiesstreams.xml:291); GuildNameAlertFrame.ClickText (guildnamechange.xml:17); the four report frames'
--   Error / GMText / RenameText / Button (guildnamechange.xml:109-219, their OnLoad writes); both invitation panels'
--   Accept / Decline buttons (communitiesinvitationframe.xml:6, 18).
-- Writers (post-hooks on the frame's own method, the client calls `self:…()`):
--   CommunitiesControlFrame:Update → CommunitiesSettingsButton (communitiesframe.lua:1757);
--   CommunitiesFrame:SetClubFinderPostingExpirationText → PostingExpirationText's ExpirationTimeText /
--     DaysUntilExpire / ExpiredText (lua:790-848);
--   CommunitiesFrame:ShowGuildNameAlertFrame → GuildNameAlertFrame.Alert (lua:906-908);
--   CommunitiesFrame:DisplayReportedAlerts → GuildNameChangeFrame.GMText (lua:929-933);
--   InvitationFrame:DisplayInvitation / TicketFrame:DisplayTicket → InvitationText, Type, Leader, MemberCount
--     (communitiesinvitationframe.lua:59-84, 150-163).
-- Help tooltips (owner → the keys its writer shows): the side tabs (RightSideTabMixin:OnEnter, blizzard_sharedxml/
--   shared/tabs/rightsidetab.lua:12-20: tooltip + tooltip2, communitiesframe.lua:1025); the disabled
--   buttons' GameTooltip_ShowDisabledTooltip (communitiesframe.xml:246-249, 280-283, 587-590; lua:1491-1521,
--   1762, 1787-1795); PostingExpirationText.InfoButton (xml:139-144, lua:811-822); the calendar button
--   (communitiescalendar.lua:22-50: the event titles and the MOTD are the club's own text).
-- The communities list (CommunitiesList.ScrollBox, CommunitiesListEntryMixin:Init, communitieslist.lua:402-667): the
--   finder / join / invitation entries write Name (the same FontString holds club names: each entry is restricted to
--   the one key its element data names: setGuildFinder / setFindCommunity / setJoinCommunity / an invitation); a
--   disabled entry's tooltip (lua:549-557, 765-767).
-- The chat tab's chat-disabled tooltip2: RESTRICT_CHAT_TOOLTIP_FORMAT ("%s\n%s") of the suppressed-message
--   sentence and the green-wrapped Shift-click instruction (communitiesframe.lua:1026–1028), both `entry` arguments;
--   the chat's MessageFrame (communitiesChat): its date / unread separators and the message-of-the-day line
--   (communitieschatframe.lua:354–397) through UI/ChatSystem's key-restricted entry point (AddMessage and
--   BackFillMessage); the club's broadcast inside the MOTD line is kept as written, members' messages never touched.
-- Never touched: club, community, leader, inviter and stream names, descriptions, the chat edit box, the rename box.
local _, WFJ = ...
local Kit = WFJ.CommunitiesKit
local CommunitiesFrame = {}
WFJ.CommunitiesFrame = CommunitiesFrame

local SURFACE = "communities.frame"
CommunitiesFrame.SURFACE = SURFACE

local CF = "CommunitiesFrame"
local CTRL = CF .. ".CommunitiesControlFrame"

CommunitiesFrame.NEVER_TOUCH = { CF .. ".ChatEditBox", CF .. ".GuildNameChangeFrame.EditBox",
  CF .. ".InvitationFrame.Name", CF .. ".InvitationFrame.Description", CF .. ".TicketFrame.Name",
  CF .. ".TicketFrame.Description" }

local k = Kit.new(SURFACE, {
  title = { CF .. ".TitleContainer.TitleText", "CommunitiesFrameTitleText" }, control = { CTRL },
  settingsButton = { CTRL .. ".CommunitiesSettingsButton" }, guildControl = { CTRL .. ".GuildControlButton" },
  recruitment = { CTRL .. ".GuildRecruitmentButton" }, guildLog = { CF .. ".GuildLogButton" },
  invite = { CF .. ".InviteButton" }, jumpToUnread = { "JumpToUnreadButton" },
  addToChat = { CF .. ".AddToChatButton.Label" }, posting = { CF .. ".PostingExpirationText" },
  nameAlert = { CF .. ".GuildNameAlertFrame" }, guildRename = { CF .. ".GuildNameChangeFrame" },
  communityRename = { CF .. ".CommunityNameChangeFrame" }, guildPosting = { CF .. ".GuildPostingChangeFrame" },
  communityPosting = { CF .. ".CommunityPostingChangeFrame" }, calendar = { CF .. ".CommunitiesCalendarButton" },
  list = { CF .. ".CommunitiesList.ScrollBox" }, invitation = { CF .. ".InvitationFrame" },
  ticket = { CF .. ".TicketFrame" }, messages = { CF .. ".Chat.MessageFrame" },
  chatTab = { CF .. ".ChatTab" }, rosterTab = { CF .. ".RosterTab" }, benefitsTab = { CF .. ".GuildBenefitsTab" },
  infoTab = { CF .. ".GuildInfoTab" }, playTab = { CF .. ".GuildPreferredPlaySettingsTab" },
})

local ALERTS = { "GUILD_NAME_ALERT", "CLUB_FINDER_COMMUNITY_NAME_CHANGE_ALERT", "CLUB_FINDER_GUILD_POSTING_ALERT",
  "CLUB_FINDER_COMMUNITY_POSTING_ALERT" }
-- A list entry's one fixed label, chosen by what its element data says it is (CommunitiesListEntryMixin:Init,
-- communitieslist.lua:405-531); a club's own entry has none (its Name is the club's name).
local function entryKeys(data)
  if type(data) ~= "table" then return nil end
  if data.setGuildFinder then return { "COMMUNITIES_GUILD_FINDER" } end
  if data.setFindCommunity then return { "COMMUNITY_FINDER_FIND_COMMUNITY" } end
  if data.setJoinCommunity then return { "COMMUNITIES_JOIN_COMMUNITY" } end
  local club = type(data.clubInfo) == "table" and data.clubInfo or nil
  if club and (club.isInvitation or club.isClubFinderInvitation) then
    return { "COMMUNITIES_LIST_INVITATION_DISPLAY" }
  end
  return nil
end
local DISABLED = { "COMMUNITY_FEATURE_UNAVAILABLE_MUTED", "COMMUNITY_FEATURE_UNAVAILABLE_SILENCED",
  "CLUB_FINDER_DISABLE_REASON_VETERAN_TRIAL", "COMMUNITY_TYPE_UNAVAILABLE" }

-- Static labels: { recKey, candidate, child path or false, keys }.
local STATIC = {
  { "title", "title", false, { "COMMUNITIES_FRAME_TITLE" } },
  { "guildControl", "guildControl", false, { "GUILD_CONTROL_BUTTON_TEXT" } },
  { "recruitment", "recruitment", false, { "GUILD_RECRUITMENT" } },
  { "guildLog", "guildLog", false, { "GUILD_VIEW_LOG" } },
  { "invite", "invite", false, { "COMMUNITIES_INVITE_MEMBERS" } },
  { "jumpToUnread", "jumpToUnread", false, { "COMMUNITIES_FRAME_JUMP_TO_UNREAD" } },
  { "addToChat", "addToChat", false, { "COMMUNITIES_ADD_TO_CHAT" } },
  { "alertClick", "nameAlert", "ClickText", { "CLICK_HERE_FOR_MORE_INFO" } },
  { "guildRename.error", "guildRename", "Error", { "GUILD_NAME_ALERT_WARNING" } },
  { "guildRename.label", "guildRename", "RenameText", { "RENAME_GUILD_LABEL" } },
  { "guildRename.button", "guildRename", "Button", { "ACCEPT" } },
  { "communityRename.error", "communityRename", "Error", { "CLUB_FINDER_COMMUNITY_NAME_CHANGE_ALERT" } },
  { "communityRename.gm", "communityRename", "GMText", { "CLUB_FINDER_COMMUNITY_NAME_CHANGE_DESCRIPTION_BOTTOM" } },
  { "communityRename.button", "communityRename", "Button", { "CLUB_FINDER_COMMUNITY_RENAME_BUTTON" } },
  { "guildPosting.error", "guildPosting", "Error", { "CLUB_FINDER_GUILD_POSTING_ALERT_REMOVED" } },
  { "guildPosting.gm", "guildPosting", "GMText", { "CLUB_FINDER_GUILD_POSTING_ALERT_REMOVED_DESC" } },
  { "guildPosting.button", "guildPosting", "Button", { "CLUB_FINDER_REPORTED_GUILD_REPOST_MESSAGE" } },
  { "communityPosting.error", "communityPosting", "Error", { "CLUB_FINDER_COMMUNITY_POSTING_REMOVED_TEXT" } },
  { "communityPosting.gm", "communityPosting", "GMText", { "CLUB_FINDER_GUILD_POSTING_ALERT_REMOVED_DESC" } },
  { "communityPosting.button", "communityPosting", "Button", { "CLUB_FINDER_REPORTED_GUILD_REPOST_MESSAGE" } },
  { "invitation.accept", "invitation", "AcceptButton", { "ACCEPT" } },
  { "invitation.decline", "invitation", "DeclineButton", { "DECLINE" } },
  { "ticket.accept", "ticket", "AcceptButton", { "ACCEPT" } },
  { "ticket.decline", "ticket", "DeclineButton", { "DECLINE" } },
}

-- Help-tooltip owners: { candidate, child path or false, keys }.
local TOOLTIPS = {
  { "chatTab", false, { "COMMUNITIES_CHAT_TAB_TOOLTIP", "ERR_PARENTAL_CONTROLS_CHAT_MUTED",
    "RESTRICT_CHAT_TOOLTIP_FORMAT" } },
  { "rosterTab", false, { "COMMUNITIES_ROSTER_TAB_TOOLTIP" } },
  { "benefitsTab", false, { "COMMUNITIES_GUILD_BENEFITS_TAB_TOOLTIP" } },
  { "infoTab", false, { "COMMUNITIES_GUILD_INFO_TAB_TOOLTIP" } },
  { "playTab", false, { "PREFERRED_PLAY_SETTINGS" } },
  { "settingsButton", false, { "CLUB_FINDER_NO_RECRUITING_PERMISSIONS" } },
  { "recruitment", false, { "COMMUNITY_FEATURE_UNAVAILABLE_MUTED", "COMMUNITY_FEATURE_UNAVAILABLE_SILENCED",
    "CLUB_FINDER_DISABLE_REASON_VETERAN_TRIAL", "CLUB_FINDER_NO_RECRUITING_PERMISSIONS",
    "CLUB_FINDER_BANNED_POSTING_WARNING" } },
  { "invite", false, { "CLUB_INVITER_FAIL_GUILD_CAPACITY", "CLUB_INVITER_FAIL_COMMUNITY_CAPACITY",
    "ERR_CLUB_FINDER_ERROR_TYPE_NO_INVITE_PERMISSIONS" } },
  { "posting", "InfoButton", { "CLUB_FINDER_BANNED_POSTING_WARNING", "ERR_CLUB_FINDER_ERROR_TYPE_FLAGGED_RENAME",
    "CLUB_FINDER_GUILD_POSTING_ALERT_REMOVED_DESC" } },
  { "calendar", false, { "COMMUNITIES_CALENDAR_TOOLTIP_TITLE", "COMMUNITIES_CALENDAR_EVENT_FORMAT",
    "COMMUNITIES_CALENDAR_CLICK_TO_ADD_INSTRUCTIONS" } },
}

-- The chat MessageFrame's client-written lines (communitiesChat).
CommunitiesFrame.CHAT_KEYS = { "COMMUNITIES_CHAT_FRAME_TODAY_NOTIFICATION",
  "COMMUNITIES_CHAT_FRAME_YESTERDAY_NOTIFICATION", "COMMUNITIES_CHAT_FRAME_UNREAD_MESSAGES_NOTIFICATION",
  "COMMUNITIES_MESSAGE_OF_THE_DAY_FORMAT" }

local function under(key, path)
  local base = k.get(key)
  if not path then return base end
  return Kit.child(base, path)
end

function CommunitiesFrame.showStatic() return k.showUnder(STATIC) end

-- hooksecurefunc target (CommunitiesControlFrame:Update). → 1 | 0
function CommunitiesFrame.onControl()
  local n = k.show("settingsButton", k.get("settingsButton"),
    { "COMMUNITIES_SETTINGS_BUTTON_LABEL", "COMMUNITIES_SETTINGS_BUTTON_CHARACTER_LABEL" })
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- hooksecurefunc target (CommunitiesFrame:SetClubFinderPostingExpirationText). → n shown
function CommunitiesFrame.onPosting()
  return k.showList({
    { "posting.time", under("posting", "ExpirationTimeText"),
      { "GUILD_FINDER_POSTING_GOING_TO_EXPIRE", "COMMUNITY_FINDER_POSTING_EXPIRE_SOON" } },
    { "posting.days", under("posting", "DaysUntilExpire"), { "CLUB_FINDER_DAYS_UNTIL_EXPIRE" } },
    { "posting.expired", under("posting", "ExpiredText"), { "CLUB_FINDER_GUILD_POSTING_REMOVED_TEXT_SRRS",
      "CLUB_FINDER_COMMUNITY_POSTING_REMOVED_TEXT_SRRS", "GUILD_FINDER_POSTING_EXPIRED",
      "COMMUNITY_FINDER_POSTING_EXPIRED" } },
  })
end

-- hooksecurefunc target (ShowGuildNameAlertFrame and DisplayReportedAlerts). → n shown
function CommunitiesFrame.onAlerts()
  return k.showList({
    { "alert", under("nameAlert", "Alert"), ALERTS },
    { "guildRename.gm", under("guildRename", "GMText"),
      { "GUILD_NAME_ALERT_GM_HELP", "GUILD_NAME_ALERT_MEMBER_HELP" } },
  })
end

-- hooksecurefunc target (InvitationFrame:DisplayInvitation / TicketFrame:DisplayTicket); `frame` is the panel.
function CommunitiesFrame.onInvitation(frame)
  if type(frame) ~= "table" then return 0 end
  local p = frame == k.get("ticket") and "ticket." or "invitation."
  return k.showList({
    { p .. "text", frame.InvitationText, { "COMMUNITY_INVITATION_FRAME_INVITATION_TEXT" } },
    { p .. "type", frame.Type, { "COMMUNITIES_INVITATION_FRAME_TYPE", "COMMUNITIES_INVITATION_FRAME_TYPE_CHARACTER" } },
    { p .. "leader", frame.Leader, { "COMMUNITIES_INVIVATION_FRAME_LEADER_FORMAT" } },
    { p .. "members", frame.MemberCount, { "COMMUNITIES_INVITATION_FRAME_MEMBER_COUNT" } },
  })
end

local entryKey = WFJ.Labels.keyer("list.") -- a pooled list entry's record key (never a position)

-- One communities-list entry after CommunitiesListEntryMixin:Init (a club's entry drops any record the reused row had).
function CommunitiesFrame.onListEntry(row, data)
  if type(row.Name) == "table" then
    local keys = entryKeys(data)
    if keys then k.show(entryKey(row.Name), row.Name, keys) else WFJ.SurfaceState.drop(SURFACE, entryKey(row.Name)) end
  end
  k.tooltip(row, DISABLED)
  WFJ.Render.updateBanner(SURFACE)
end

local hooked = false

function CommunitiesFrame.setup()
  if not Kit.ready(k, CommunitiesFrame.NEVER_TOUCH) then return false end
  CommunitiesFrame.showStatic()
  for _, t in ipairs(TOOLTIPS) do k.tooltip(under(t[1], t[2]), t[3]) end
  if hooked then return false end
  hooked = true
  local frame = k.get("frame")
  k.after(k.get("control"), "Update", CommunitiesFrame.onControl)
  k.after(frame, "SetClubFinderPostingExpirationText", CommunitiesFrame.onPosting)
  k.after(frame, "ShowGuildNameAlertFrame", CommunitiesFrame.onAlerts)
  k.after(frame, "DisplayReportedAlerts", CommunitiesFrame.onAlerts)
  k.after(k.get("invitation"), "DisplayInvitation", CommunitiesFrame.onInvitation)
  k.after(k.get("ticket"), "DisplayTicket", CommunitiesFrame.onInvitation)
  k.rows(k.get("list"), CommunitiesFrame.onListEntry)
  if WFJ.ChatSystem then WFJ.ChatSystem.hookKeyed(k.get("messages"), CommunitiesFrame.CHAT_KEYS) end
  CommunitiesFrame.onControl()
  CommunitiesFrame.onAlerts()
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init.
function CommunitiesFrame.init() return Kit.init(k, CommunitiesFrame.setup) end
