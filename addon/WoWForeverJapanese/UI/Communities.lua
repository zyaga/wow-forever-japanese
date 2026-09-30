-- UI/Communities.lua: the guild view of the Communities window on Forever (surfaces "communities" and
-- "communities.static", area "ui", ADR-016). `camelot` has no classic guild frame: GuildFrame lives in
-- [Family]\FriendsFrame.xml [AllowLoadGameType classic] (Blizzard_UIPanels_Game.toc:152), and ToggleGuildFrame is
-- blizzard_game/mainline/game.lua:1–25 → ToggleCommunitiesFrame(). The guild UI is Blizzard_Communities only. Its
-- camelot TOC has no LoadOnDemand line (retail's has one), so it is waited for through WFJ.LoadOnDemand.when, which
-- runs now if it is loaded and on its ADDON_LOADED otherwise.
-- Scope: the roster's column headers, the member count, the member detail pane, the guild info / news
-- labels. The rest of the window (ClubFinder, dialogs, benefits) is UI/CommunitiesFrame and its siblings; chat
-- streams, community settings, invitations and tickets are not touched.
-- Static labels (XML text=; each restricted to its own key):
--   CommunitiesFrame.GuildMemberDetailFrame: ZoneLabel / RankLabel / OnlineLabel / NoteLabel / OfficerNoteLabel,
--     RemoveButton, GroupInviteButton (guildroster.xml:19–98; the frame is parentKey GuildMemberDetailFrame,
--     communitiesframe.xml:613);
--   CommunitiesFrame.GuildDetailsFrame.Info (communitiesframe.xml:161–176, 542): TitleText GUILD_INFO_TITLE,
--     Header2Label GUILD_MOTD_LABEL, an unnamed GUILD_INFORMATION label, EditMOTDButton / EditDetailsButton
--     GUILD_EDIT_TEXT_LINK (guildinfo.xml:62, 147, 153, 210, 228);
--   CommunitiesFrame.GuildDetailsFrame.News: TitleText GUILD_NEWS_TITLE, an unnamed GUILD_NEWS label, NoNews,
--     SetFiltersButton (guildnews.xml:275–296);
--   CommunitiesGuildLogFrameTitle GUILD_EVENT_LOG (guildinfo.xml:388), CommunitiesGuildNewsFiltersFrame.Title
--     GUILD_NEWS_FILTERS (guildnews.xml:388).
-- Dynamic, each the frame's own method (mixins are copied onto the frame at load; every call is `self:…()`) or a
-- global called by name:
--   MemberList:UpdateMemberCount → MemberCount, COMMUNITIES_MEMBER_LIST_MEMBER_COUNT_FORMAT
--     (communitiesmemberlist.lua:395–405);
--   MemberList.ColumnDisplay:LayoutColumns → the pooled column header buttons (ColumnDisplayMixin, blizzard_sharedxml/
--     mainline/shareduipaneltemplates.lua; the titles are COMMUNITIES_ROSTER_COLUMN_TITLE_*, communitiesmemberlist
--     .lua:41–161). Headers are walked from the pool after each layout, keyed by widget;
--   GuildMemberDetailFrame:DisplayMember (guildroster.lua:91–175) → Level (FRIENDS_LEVEL_TEMPLATE, the class kept
--     verbatim), OnlineText (GUILD_ONLINE_LABEL or TimeUtil.GetRecentTimeDate's LASTONLINE_*, timeutil.lua:24–44),
--     the two note placeholders (GUILD_NOTE_EDITLABEL / GUILD_OFFICERNOTE_EDITLABEL; the same FontStrings hold the
--     members' own notes, hence `only`);
--   CommunitiesGuildInfoFrame_UpdateChallenges (global, guildinfo.lua:36, 78) → Info.Header1Label
--     (GUILD_FRAME_CHALLENGES, or GUILD_MOTD_LABEL when there are no challenges, lua:66–68).
--   the roster's pooled entries (MemberList.ScrollBox; CommunitiesMemberListEntryMixin, walked from the
--     ScrollBox's initialized-frame callback after its element initializer, communitiesmemberlist.lua:454–457):
--     a pending-invite header row writes COMMUNITIES_MEMBER_LIST_PENDING_INVITE_HEADER into NameFrame.Name (SetHeader,
--     lua:1041–1044, 1109–1110); the same FontString holds member names, so it is restricted to that key;
--     the entry's tooltip (OnEnter, lua:1162–1212) shows COMMUNITY_MEMBER_CHARACTER_INFO_FORMAT ("Level %d %s %s",
--     race and class kept as written); every other line is a name, a rank, a zone or a note, never matched;
--     CancelInvitationButton's tooltip COMMUNITY_MEMBER_CANCEL_INVITATION_TOOLTIP (communitiesmemberlist.xml:64–68).
--   The extra guild column CLUB_FINDER_APPLICANTS is a roster header (EXTRA_GUILD_COLUMNS, lua:168–171).
-- Never touched: member names, ranks, zones, notes, the MOTD and guild info text, guild names.
local _, WFJ = ...
local Communities = {}
WFJ.Communities = Communities

local SURFACE = "communities"
Communities.SURFACE = SURFACE
local STATIC = SURFACE .. ".static"
local Compat = WFJ.Compat
local ADDON = "Blizzard_Communities"

local DETAIL = "CommunitiesFrame.GuildMemberDetailFrame"
local INFO = "CommunitiesFrame.GuildDetailsFrame.Info"
local NEWS = "CommunitiesFrame.GuildDetailsFrame.News"

Communities.NEVER_TOUCH = { DETAIL .. ".Name", DETAIL .. ".ZoneText", DETAIL .. ".RankText",
  INFO .. ".MOTDScrollFrame.MOTD", "CommunitiesGuildTextEditFrame.Container.ScrollFrame.EditBox" }

-- Static labels: record key → { candidate, the one key it shows }.
local STATIC_LABELS = {
  zoneLabel = { DETAIL .. ".ZoneLabel", "ZONE_COLON" }, rankLabel = { DETAIL .. ".RankLabel", "RANK_COLON" },
  onlineLabel = { DETAIL .. ".OnlineLabel", "LAST_ONLINE_COLON" },
  noteLabel = { DETAIL .. ".NoteLabel", "NOTE_COLON" },
  officerNoteLabel = { DETAIL .. ".OfficerNoteLabel", "OFFICER_NOTE_COLON" },
  remove = { DETAIL .. ".RemoveButton", "REMOVE" }, groupInvite = { DETAIL .. ".GroupInviteButton", "GROUP_INVITE" },
  infoTitle = { INFO .. ".TitleText", "GUILD_INFO_TITLE" },
  motdHeader = { INFO .. ".Header2Label", "GUILD_MOTD_LABEL" },
  editMOTD = { INFO .. ".EditMOTDButton", "GUILD_EDIT_TEXT_LINK" },
  editDetails = { INFO .. ".EditDetailsButton", "GUILD_EDIT_TEXT_LINK" },
  newsTitle = { NEWS .. ".TitleText", "GUILD_NEWS_TITLE" }, noNews = { NEWS .. ".NoNews", "GUILD_NO_GUILD_NEWS" },
  setFilters = { NEWS .. ".SetFiltersButton", "GUILD_SET_FILTERS_LINK" },
  eventLog = { "CommunitiesGuildLogFrameTitle", "GUILD_EVENT_LOG" },
  newsFilters = { "CommunitiesGuildNewsFiltersFrame.Title", "GUILD_NEWS_FILTERS" },
}
local STATIC_ORDER = {}
for key in pairs(STATIC_LABELS) do STATIC_ORDER[#STATIC_ORDER + 1] = key end
table.sort(STATIC_ORDER)
-- Unnamed label regions: record key → { owner candidate, key }.
local REGIONS = { infoHeader = { INFO, "GUILD_INFORMATION" }, newsHeader = { NEWS, "GUILD_NEWS" } }

local TITLE = { only = { "COMMUNITIES_FRAME_TITLE" } }

local CANDIDATES = {
  frame = { "CommunitiesFrame" }, memberList = { "CommunitiesFrame.MemberList" },
  count = { "CommunitiesFrame.MemberList.MemberCount" }, columns = { "CommunitiesFrame.MemberList.ColumnDisplay" },
  detail = { DETAIL }, level = { DETAIL .. ".Level" }, online = { DETAIL .. ".OnlineText" },
  personalNote = { DETAIL .. ".NoteBackground.PersonalNoteText" },
  officerNote = { DETAIL .. ".OfficerNoteBackground.OfficerNoteText" },
  challengesHeader = { INFO .. ".Header1Label" }, updateChallenges = { "CommunitiesGuildInfoFrame_UpdateChallenges" },
  roster = { "CommunitiesFrame.MemberList.ScrollBox" }, scrollUtil = { "ScrollUtil" },
}

local COLUMN_KEYS = { "COMMUNITIES_ROSTER_COLUMN_TITLE_NAME", "COMMUNITIES_ROSTER_COLUMN_TITLE_RANK",
  "COMMUNITIES_ROSTER_COLUMN_TITLE_NOTE", "COMMUNITIES_ROSTER_COLUMN_TITLE_LEVEL",
  "COMMUNITIES_ROSTER_COLUMN_TITLE_CLASS", "COMMUNITIES_ROSTER_COLUMN_TITLE_ZONE",
  "COMMUNITIES_ROSTER_COLUMN_TITLE_ACHIEVEMENT", "COMMUNITIES_ROSTER_COLUMN_TITLE_PROFESSION",
  "CLUB_FINDER_APPLICANTS" }
local ONLINE_KEYS = { "GUILD_ONLINE_LABEL", "LASTONLINE_MINS", "LASTONLINE_HOURS", "LASTONLINE_DAYS",
  "LASTONLINE_MONTHS", "LASTONLINE_YEARS" }

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  for key, l in pairs(STATIC_LABELS) do Compat.declare(SURFACE, "static." .. key, { l[1] }) end
  for key, r in pairs(REGIONS) do Compat.declare(SURFACE, "region." .. key, { r[1] }) end
end

-- A stable record key per pooled header button (records follow the widget, not the index).
local headerKey = WFJ.Labels.keyer("column.") -- a pooled header's record key

local ENTRY_TOOLTIP = { only = { "COMMUNITY_MEMBER_CHARACTER_INFO_FORMAT" } }
local CANCEL_TOOLTIP = { only = { "COMMUNITY_MEMBER_CANCEL_INVITATION_TOOLTIP" } }
local INVITE_HEADER = { only = { "COMMUNITIES_MEMBER_LIST_PENDING_INVITE_HEADER" } }

-- One pooled roster entry after its initializer ran (ScrollUtil's initialized-frame callback: (owner, frame,
-- elementData) for a new entry, (frame, elementData) for the iterateExisting pass). Returns nothing: ForEachFrame stops
-- at the first truthy return (see UI/Raid.onRow).
function Communities.onRosterRow(a, b)
  local row = a
  if a == Communities then row = b end
  if type(row) ~= "table" then return end
  local name = type(row.NameFrame) == "table" and row.NameFrame.Name or nil
  if type(name) == "table" then WFJ.Labels.show(SURFACE, "invites." .. headerKey(name), name, nil, INVITE_HEADER) end
  WFJ.HelpTooltip.register(row, ENTRY_TOOLTIP)
  local cancel = row.CancelInvitationButton
  if type(cancel) == "table" then WFJ.HelpTooltip.register(cancel, CANCEL_TOOLTIP) end
end

-- The labels the client writes once at load. → the number of dictionary words found.
function Communities.showStatic()
  local items = {}
  for _, key in ipairs(STATIC_ORDER) do
    items[#items + 1] = { key, get("static." .. key), { only = { STATIC_LABELS[key][2] } } }
  end
  for _, key in ipairs({ "infoHeader", "newsHeader" }) do
    local k = REGIONS[key][2]
    items[#items + 1] = { key, WFJ.Labels.region(get("region." .. key), k), { only = { k } } }
  end
  return WFJ.Labels.showAll(STATIC, items)
end

-- hooksecurefunc target (MemberList:UpdateMemberCount). → 1 | 0
function Communities.onCount()
  return WFJ.Labels.show(SURFACE, "count", get("count"), nil,
    { only = { "COMMUNITIES_MEMBER_LIST_MEMBER_COUNT_FORMAT" } })
end

-- hooksecurefunc target (MemberList.ColumnDisplay:LayoutColumns). → the number of dictionary words found.
function Communities.onColumns()
  local columns = get("columns")
  local pool = type(columns) == "table" and columns.columnHeaders or nil
  if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then return 0 end
  local n = 0
  for header in pool:EnumerateActive() do
    if type(header) == "table" then
      n = n + WFJ.Labels.show(SURFACE, headerKey(header), header, nil, { only = COLUMN_KEYS })
    end
  end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- hooksecurefunc target (GuildMemberDetailFrame:DisplayMember). → the number of dictionary words found.
function Communities.onDetail()
  local show = WFJ.Labels.show
  local n = show(SURFACE, "detailLevel", get("level"), nil, { only = { "FRIENDS_LEVEL_TEMPLATE" } })
    + show(SURFACE, "detailOnline", get("online"), nil, { only = ONLINE_KEYS })
    + show(SURFACE, "personalNote", get("personalNote"), nil, { only = { "GUILD_NOTE_EDITLABEL" } })
    + show(SURFACE, "officerNote", get("officerNote"), nil, { only = { "GUILD_OFFICERNOTE_EDITLABEL" } })
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- hooksecurefunc target (CommunitiesGuildInfoFrame_UpdateChallenges). → 1 | 0
function Communities.onChallenges()
  return WFJ.Labels.show(SURFACE, "challengesHeader", get("challengesHeader"), nil,
    { only = { "GUILD_FRAME_CHALLENGES", "GUILD_MOTD_LABEL" } })
end

local hooked = false

-- Blizzard_Communities' part: runs once the addon is loaded (now, or on its ADDON_LOADED). → true when set up.
function Communities.setup()
  declare() -- its frames exist only now: forget what Compat memoized before
  if type(get("frame")) ~= "table" then return false end
  WFJ.Labels.forbidNames(Communities.NEVER_TOUCH) -- its widgets exist only now (Main's registration found none)
  Communities.showStatic()
  -- The window title, CommunitiesFrame:SetTitle(COMMUNITIES_FRAME_TITLE) at OnLoad
  -- (communitiesframe.lua:103). `only` keeps it to that one key, in case a later SetTitle writes a community's name.
  WFJ.Labels.title(SURFACE, get("frame"), TITLE)
  if hooked then return false end
  hooked = true
  local memberList = get("memberList")
  if type(memberList) == "table" and type(memberList.UpdateMemberCount) == "function" then
    hooksecurefunc(memberList, "UpdateMemberCount", Communities.onCount)
  end
  local columns = get("columns")
  if type(columns) == "table" and type(columns.LayoutColumns) == "function" then
    hooksecurefunc(columns, "LayoutColumns", Communities.onColumns)
  end
  local detail = get("detail")
  if type(detail) == "table" and type(detail.DisplayMember) == "function" then
    hooksecurefunc(detail, "DisplayMember", Communities.onDetail)
  end
  local roster, util = get("roster"), get("scrollUtil")
  if type(roster) == "table" and type(util) == "table" and type(util.AddInitializedFrameCallback) == "function" then
    util.AddInitializedFrameCallback(roster, Communities.onRosterRow, Communities, true)
  end
  if type(get("updateChallenges")) == "function" then
    hooksecurefunc("CommunitiesGuildInfoFrame_UpdateChallenges", Communities.onChallenges)
  end
  Communities.onColumns()
  Communities.onCount()
  Communities.onChallenges()
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init.
function Communities.init()
  declare()
  return WFJ.LoadOnDemand.when(ADDON, Communities.setup)
end
