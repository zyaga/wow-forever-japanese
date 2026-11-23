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
--     RemoveButton, GroupInviteButton (guildroster.xml:26–111; the frame is parentKey GuildMemberDetailFrame,
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
--   GuildMemberDetailFrame:DisplayMember (guildroster.lua:117–207) → Level (FRIENDS_LEVEL_TEMPLATE, the class kept
--     verbatim), OnlineText (GUILD_ONLINE_LABEL or TimeUtil.GetRecentTimeDate's LASTONLINE_*, timeutil.lua:24–44),
--     the two note placeholders (GUILD_NOTE_EDITLABEL / GUILD_OFFICERNOTE_EDITLABEL; the same FontStrings hold the
--     members' own notes, hence `only`);
--   CommunitiesGuildInfoFrame_UpdateChallenges (global, guildinfo.lua:36, 78) → Info.Header1Label
--     (GUILD_FRAME_CHALLENGES, or GUILD_MOTD_LABEL when there are no challenges, lua:66–68).
--   the roster's pooled entries (MemberList.ScrollBox; CommunitiesMemberListEntryMixin, walked from the
--     ScrollBox's initialized-frame callback after its element initializer, communitiesmemberlist.lua:454–457):
--     a pending-invite header row writes COMMUNITIES_MEMBER_LIST_PENDING_INVITE_HEADER into NameFrame.Name (SetHeader,
--     lua:1048–1051, 1116–1117); the same FontString holds member names, so it is restricted to that key;
--     the entry's tooltip (OnEnter, lua:1169–1219) shows COMMUNITY_MEMBER_CHARACTER_INFO_FORMAT ("Level %d %s %s",
--     raceInfo.raceName and classInfo.className, lua:1197–1201); every other line is a name, a rank, a zone or a
--     note, never matched as a dictionary line (the zone is a name, below);
--     CancelInvitationButton's tooltip COMMUNITY_MEMBER_CANCEL_INVITATION_TOOLTIP (communitiesmemberlist.xml:67–71).
--   The extra guild column CLUB_FINDER_APPLICANTS is a roster header (EXTRA_GUILD_COLUMNS, lua:168–171).
-- Names: a member's zone is a place the game names. While names are on it shows its Japanese on the roster row's
--   Zone column (memberInfo.zone, communitiesmemberlist.lua:1301–1302) and on the member detail's ZoneText
--   (guildroster.lua:147), and the class in the detail's level line (classInfo.className, guildroster.lua:141–144)
--   shows the word prose uses for it. So do the race and the class in a roster row's tooltip, filled when the line
--   is drawn (the key's `spec` and `class` values, Core/UIStringKeys); a race with no such word shows the name
--   list's spelling, and one with neither stays as written. The tooltip's zone line (memberInfo.zone again,
--   lua:1206–1207) shows the zone's Japanese too: it is found after the row's OnEnter script (xml:237) by the
--   zone the row holds, never by its place among the lines, and is the last line with that text, so a rank a
--   guild named like a zone stays as written. A roster row is a plain button whose click opens the member's
--   detail or menu, and nothing measures these labels.
-- Never touched: member names, notes, the MOTD and guild info text, guild names, and a rank's name: a guild's
--   leader names its ranks (memberInfo.guildRank, lua:1313), the first rank included.
-- Their font only (UI/PlayerText): the MOTD, the guild info text, a member's two notes and rank, and a roster
--   row's note and rank wear the bundled face while they hold Japanese; the box the MOTD and the info text are
--   edited in always does.
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
  -- the roster's check box label, written by its OnLoad (communitiesmemberlist.xml:284–290)
  showOffline = { "CommunitiesFrame.MemberList.ShowOfflineButton.Text", "COMMUNITIES_MEMBER_LIST_SHOW_OFFLINE" },
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
  detail = { DETAIL }, level = { DETAIL .. ".Level" }, zoneText = { DETAIL .. ".ZoneText" },
  online = { DETAIL .. ".OnlineText" },
  personalNote = { DETAIL .. ".NoteBackground.PersonalNoteText" },
  officerNote = { DETAIL .. ".OfficerNoteBackground.OfficerNoteText" },
  challengesHeader = { INFO .. ".Header1Label" }, updateChallenges = { "CommunitiesGuildInfoFrame_UpdateChallenges" },
  roster = { "CommunitiesFrame.MemberList.ScrollBox" }, scrollUtil = { "ScrollUtil" },
}

local COLUMN_KEYS = { "COMMUNITIES_ROSTER_COLUMN_TITLE_NAME", "COMMUNITIES_ROSTER_COLUMN_TITLE_RANK",
  "COMMUNITIES_ROSTER_COLUMN_TITLE_NOTE", "COMMUNITIES_ROSTER_COLUMN_TITLE_LEVEL",
  "COMMUNITIES_ROSTER_COLUMN_TITLE_CLASS", "COMMUNITIES_ROSTER_COLUMN_TITLE_ZONE",
  "COMMUNITIES_ROSTER_COLUMN_TITLE_ACHIEVEMENT", "COMMUNITIES_ROSTER_COLUMN_TITLE_PROFESSION",
  "CLUB_FINDER_APPLICANTS", "CLUB_FINDER_APPLICANT_HISTORY", "DUNGEON_SCORE" }
local ONLINE_KEYS = { "GUILD_ONLINE_LABEL", "LASTONLINE_MINS", "LASTONLINE_HOURS", "LASTONLINE_DAYS",
  "LASTONLINE_MONTHS", "LASTONLINE_YEARS" }

-- A roster row's Zone column holds a place (a name), or for a member who is not online the client's own line:
-- "Offline" or how long ago they were (communitiesmemberlist.lua:1293–1303, TimeUtil.GetRecentTimeDate).
local ROW_PRESENCE = { only = { "COMMUNITIES_PRESENCE_OFFLINE", "LASTONLINE_SECS", "LASTONLINE_MINS",
  "LASTONLINE_HOURS", "LASTONLINE_DAYS", "LASTONLINE_MONTHS", "LASTONLINE_YEARS" } }
-- The channel dropdown shows the selected channel's name. A guild's own two channels are named by the game
-- ("Guild", "Officer"); every other channel is named by a player and left as written.
local STREAM = { only = { "GUILD", "OFFICER" } }

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  for key, l in pairs(STATIC_LABELS) do Compat.declare(SURFACE, "static." .. key, { l[1] }) end
  for key, r in pairs(REGIONS) do Compat.declare(SURFACE, "region." .. key, { r[1] }) end
end

-- A stable record key per pooled header button (records follow the widget, not the index).
local headerKey = WFJ.Labels.keyer("column.") -- a pooled header's record key
local zoneKey = WFJ.Labels.keyer("zone.") -- a pooled roster row's Zone column
local placeKey = WFJ.Labels.keyer("place.") -- the same column while it holds a place

local ENTRY_TOOLTIP = { only = { "COMMUNITY_MEMBER_CHARACTER_INFO_FORMAT",
  -- a cross-faction member's lines (communitiesmemberlist.lua:1216, 1789–1790), the faction word kept
  "COMMUNITY_MEMBER_LIST_CROSS_FACTION", "COMMUNITIES_CROSS_FACTION_BUTTON_TOOLTIP_TITLE",
  "CROSS_FACTION_INVITE_TOOLTIP" } }
local CANCEL_TOOLTIP = { only = { "COMMUNITY_MEMBER_CANCEL_INVITATION_TOOLTIP" } }
local INVITE_HEADER = { only = { "COMMUNITIES_MEMBER_LIST_PENDING_INVITE_HEADER" } }

local zoneHooked = setmetatable({}, { __mode = "k" })
local function showZone(row)
  if type(row.Zone) ~= "table" then return end
  WFJ.Labels.show(SURFACE, zoneKey(row.Zone), row.Zone, nil, ROW_PRESENCE)
  -- a place under a record of its own: a text that is no presence line drops the record above
  WFJ.NameLabels.show(SURFACE, placeKey(row.Zone), row.Zone)
end

-- After a roster row's OnEnter script built its tooltip (CommunitiesMemberListEntryMixin:OnEnter, lua:1169–1219):
-- the line that holds the member's zone shows the zone's Japanese while names are on. The lines before it are the
-- member's name, the rank (a guild's own word, which may be spelled like a place) and the level line; the note
-- after it starts with an icon and the cross-faction lines are the client's own. So of the lines from the second
-- on that hold exactly the zone, the last one is the zone's. A member on the mobile app has no zone line
-- (lua:1204–1205): a rank spelled like the zone would be the only match, so nothing is looked for. The record is
-- on the help surface under the walk's own key, so the tooltip's refit and release are UI/HelpTooltip's. → 1 | 0
function Communities.onRowTooltip(row)
  if not WFJ.State.names or type(row) ~= "table" or type(row.GetMemberInfo) ~= "function" then return 0 end
  local help, secret = WFJ.HelpTooltip, WFJ.SurfaceState.secret
  local tt = Compat.get(help.SURFACE, "tooltip")
  if type(tt) ~= "table" or type(tt.GetOwner) ~= "function" or tt:GetOwner() ~= row
      or type(tt.NumLines) ~= "function" or type(tt.GetName) ~= "function" then return 0 end
  local info = row:GetMemberInfo()
  local zone = type(info) == "table" and info.zone or nil
  local mobile = Compat.resolve("Enum.ClubMemberPresence.OnlineMobile")
  if secret(zone) or type(zone) ~= "string" or zone == "" or mobile == nil or secret(info.presence)
      or info.presence == mobile then
    return 0
  end
  local name, at = tt:GetName(), nil
  for i = 2, tt:NumLines() or 0 do
    local fs = Compat.resolve(name .. "TextLeft" .. i)
    local text = type(fs) == "table" and type(fs.GetText) == "function" and fs:GetText() or nil
    if not secret(text) then
      -- a line a record already holds is ours: it stands for the English it was written from
      local rec = WFJ.SurfaceState.get(help.SURFACE, "L" .. i)
      if rec and rec.fs == fs and rec.applied ~= nil and rec.applied == text then text = rec.en end
      if text == zone then at = i end
    end
  end
  return at and help.nameAt(tt, at) or 0
end

local tooltipHooked = setmetatable({}, { __mode = "k" })

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
  if not tooltipHooked[row] and type(row.HookScript) == "function" then
    tooltipHooked[row] = true
    row:HookScript("OnEnter", Communities.onRowTooltip)
  end
  local cancel = row.CancelInvitationButton
  if type(cancel) == "table" then WFJ.HelpTooltip.register(cancel, CANCEL_TOOLTIP) end
  -- the client rewrites the columns without initializing the row again (RefreshExpandedColumns, lua:1242, from
  -- SetExpanded and the member events), so the Zone line is shown after each rewrite as well
  if not zoneHooked[row] and type(row.RefreshExpandedColumns) == "function" then
    zoneHooked[row] = true
    hooksecurefunc(row, "RefreshExpandedColumns", showZone)
  end
  showZone(row)
  WFJ.PlayerText.follow(row.Note) -- the member's note (communitiesmemberlist.lua:1320)
  WFJ.PlayerText.follow(row.Rank) -- the rank's name, written by the guild master (lua:1313)
end

-- The news pane holds two labels with one English, "Guild News": its TitleText (GUILD_NEWS_TITLE) and the unnamed
-- header under it (GUILD_NEWS, guildnews.xml:275–286). A search by text alone finds the TitleText first, so the
-- header is the region with that text that is not the TitleText. Found once, while both still hold their English.
local newsHeaderRegion = setmetatable({}, { __mode = "k" }) -- the news frame → its unnamed header
local function newsHeader()
  local news = get("region.newsHeader")
  if type(news) ~= "table" then return nil end
  if newsHeaderRegion[news] then return newsHeaderRegion[news] end
  local en = Compat.resolve(REGIONS.newsHeader[2])
  if type(en) ~= "string" or en == "" then return nil end
  for _, region in ipairs(WFJ.Frames.regions(news)) do
    if type(region) == "table" and region ~= news.TitleText and region.GetObjectType
        and region:GetObjectType() == "FontString" and region:GetText() == en then
      newsHeaderRegion[news] = region
      return region
    end
  end
  return nil
end

-- The labels the client writes once at load. → the number of dictionary words found.
function Communities.showStatic()
  local items = {}
  local header = newsHeader() -- before the TitleText is shown: both are found by their English
  for _, key in ipairs(STATIC_ORDER) do
    items[#items + 1] = { key, get("static." .. key), { only = { STATIC_LABELS[key][2] } } }
  end
  local infoKey = REGIONS.infoHeader[2]
  items[#items + 1] = { "infoHeader", WFJ.Labels.region(get("region.infoHeader"), infoKey), { only = { infoKey } } }
  items[#items + 1] = { "newsHeader", header, { only = { REGIONS.newsHeader[2] } } }
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

-- A note widget holds the client's placeholder (a dictionary line) or the member's own note. The font a note in
-- Japanese was given comes off first, so the placeholder's record holds the widget's own font; a note that is not
-- the placeholder then gets the bundled face when it holds Japanese. → 1 | 0
local function showNote(recKey, key, placeholder)
  local fs = get(key)
  WFJ.Font.restore(fs)
  local n = WFJ.Labels.show(SURFACE, recKey, fs, nil, { only = { placeholder } })
  if n == 0 then WFJ.PlayerText.shown(fs) end
  return n
end

-- The detail's level line, "Level %d %s" with the member's class. The template is compiled once for every key
-- with that English and reads its second slot as a creature's type; here the slot is a class, so the line is
-- filled under the key that declares one and the class follows the names choice when the line is drawn. → 1 | 0
local LEVEL = { "FRIENDS_LEVEL_TEMPLATE" }
local LEVEL_WITH_CLASS = "SOCIAL_UI_RECENT_ALLIES_TOOLTIP_LEVEL_CLASS_FORMAT"
local function showLevel()
  local widget = get("level")
  local fs, index = WFJ.Labels.widget(widget), WFJ.UIIndex
  local text = fs and fs:GetText()
  local key, args
  if index and type(text) == "string" and text ~= "" then key, args = index:matchOnly(text, LEVEL) end
  if key and type(args) == "table" and args.form == nil and type(args[2]) == "string" then
    local withClass = {}
    for k, v in pairs(args) do withClass[k] = v end
    withClass.key = LEVEL_WITH_CLASS
    args = withClass
  end
  return WFJ.Labels.showArgs(SURFACE, "detailLevel", widget, key, args)
end

-- hooksecurefunc target (GuildMemberDetailFrame:DisplayMember). → the number of dictionary words found.
function Communities.onDetail()
  local show = WFJ.Labels.show
  local n = showLevel()
    + show(SURFACE, "detailOnline", get("online"), nil, { only = ONLINE_KEYS })
    + showNote("personalNote", "personalNote", "GUILD_NOTE_EDITLABEL")
    + showNote("officerNote", "officerNote", "GUILD_OFFICERNOTE_EDITLABEL")
    + WFJ.NameLabels.show(SURFACE, "detailZone", get("zoneText"))
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- The guild info tab's player-written text: the MOTD (a SimpleHTML, guildinfo.xml:176), the guild information (the
-- details scroll frame's child has no key of its own, xml:251–265) and the box both are edited in (xml:328).
local function playerText()
  local P = WFJ.PlayerText
  P.each(P.follow, { INFO .. ".MOTDScrollFrame.MOTD", DETAIL .. ".RankText" }) -- RankText: guildroster.lua:148
  P.each(function(scroll)
    local child = type(scroll.GetScrollChild) == "function" and scroll:GetScrollChild() or nil
    if type(child) == "table" then P.follow(child.Details) end
  end, { INFO .. ".DetailsFrame" })
  P.each(P.box, { "CommunitiesGuildTextEditFrame.Container.ScrollFrame.EditBox" })
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
  playerText()
  WFJ.Labels.dropdown(SURFACE, "stream", Compat.resolve("CommunitiesFrame.StreamDropdown"), STREAM)
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
