-- UI/Communities.lua over a CommunitiesFrame replayed from camelot
-- blizzard_communities (communitiesframe.xml:303–613, communitiesmemberlist.lua:395–405 + 591–612, the shared
-- ColumnDisplayMixin:LayoutColumns, guildroster.lua:91–175, guildinfo.{xml,lua}, guildnews.xml). Member names, ranks,
-- zones and notes stay English; the surface waits for Blizzard_Communities in either load order.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/Communities.lua"

local ADDON = "Blizzard_Communities"

local UI = {
  COMMUNITIES_ROSTER_COLUMN_TITLE_NAME = { "Name", "名前" }, COMMUNITIES_ROSTER_COLUMN_TITLE_RANK = { "Rank", "ランク" },
  COMMUNITIES_ROSTER_COLUMN_TITLE_NOTE = { "Note", "メモ" }, COMMUNITIES_ROSTER_COLUMN_TITLE_LEVEL = { "Lvl", "Lv" },
  COMMUNITIES_ROSTER_COLUMN_TITLE_CLASS = { "Class", "クラス" }, COMMUNITIES_ROSTER_COLUMN_TITLE_ZONE = { "Zone", "ゾーン" },
  COMMUNITIES_MEMBER_LIST_MEMBER_COUNT_FORMAT = { "%s/%s Online", "オンライン %s/%s" },
  ZONE_COLON = { "Zone:", "ゾーン:" }, RANK_COLON = { "Rank:", "ランク:" },
  LAST_ONLINE_COLON = { "Last Online:", "最終オンライン:" },
  NOTE_COLON = { "Note:", "メモ:" }, OFFICER_NOTE_COLON = { "Officer's Note", "オフィサーメモ" },
  REMOVE = { "Remove", "削除" }, GROUP_INVITE = { "Group Invite", "グループに招待" },
  FRIENDS_LEVEL_TEMPLATE = { "Level %d %s", "レベル %d %s" }, GUILD_ONLINE_LABEL = { "Online", "オンライン" },
  LASTONLINE_DAYS = { "%d |4day:days;", "%d日" },
  GUILD_NOTE_EDITLABEL = { "Click here to set a Public Note.", "ここをクリックして公開メモを設定します。" },
  GUILD_OFFICERNOTE_EDITLABEL = { "Click here to set an Officer's Note.", "ここをクリックしてオフィサーメモを設定します。" },
  GUILD_INFO_TITLE = { "Guild Info", "ギルド情報" }, GUILD_MOTD_LABEL = { "Guild Message Of The Day", "今日のギルドメッセージ" },
  GUILD_FRAME_CHALLENGES = { "Guild Challenges", "ギルドチャレンジ" }, GUILD_INFORMATION = { "Guild Information", "ギルド情報" },
  GUILD_EDIT_TEXT_LINK = { "Click here to edit", "ここをクリックして編集" }, GUILD_NEWS_TITLE = { "Guild News", "ギルドニュース" },
  GUILD_NEWS = { "Guild News", "ギルドニュース" }, GUILD_NO_GUILD_NEWS = { "No guild news", "ギルドニュースはありません" },
  GUILD_SET_FILTERS_LINK = { "Set Filters", "フィルター設定" }, GUILD_EVENT_LOG = { "Guild Event Log", "ギルドイベントログ" },
  GUILD_NEWS_FILTERS = { "Guild News Filters", "ギルドニュースフィルター" },
  CLOSE = { "Close", "閉じる" }, -- a word a member's name or note may happen to be
  CLUB_FINDER_APPLICANTS = { "Applicants", "応募者" },
  COMMUNITIES_MEMBER_LIST_PENDING_INVITE_HEADER = { "Pending Invites (%d)", "保留中の招待 (%d)" },
  COMMUNITY_MEMBER_CHARACTER_INFO_FORMAT = { "Level %d %s %s", "レベル %d %s %s" },
  COMMUNITY_MEMBER_CANCEL_INVITATION_TOOLTIP = { "Click to cancel invitation", "クリックで招待を取り消します" },
  COMMUNITIES_FRAME_TITLE = { "Guild & Communities", "ギルド&コミュニティ" },
}

local C = {} -- replayed client state

local function en(key) return _G[key] end
local function fs(text) return Stub.fontString(text or "") end

-- A CreateFramePool-like pool (ColumnDisplayMixin:OnLoad, shareduipaneltemplates.lua:825–827).
local function pool(create)
  local p = { active = {}, inactive = {} }
  function p.Acquire(self)
    local f = table.remove(self.inactive) or create()
    self.active[#self.active + 1] = f
    return f
  end
  function p.ReleaseAll(self)
    for _, f in ipairs(self.active) do self.inactive[#self.inactive + 1] = f end
    self.active = {}
  end
  function p.EnumerateActive(self)
    local i = 0
    return function()
      i = i + 1
      if self.active[i] then return self.active[i], true end
    end
  end
  return p
end

local function loadCommunities()
  local frame = CreateFrame("Frame", "CommunitiesFrame")
  -- the PortraitFrame title (blizzard_sharedxml/portraitframe.lua:11–13), set at OnLoad (communitiesframe.lua:103)
  frame.TitleContainer = { TitleText = fs(en("COMMUNITIES_FRAME_TITLE")) }
  function frame.SetTitle(self, text) self.TitleContainer.TitleText.text = text end
  -- member list
  local list = CreateFrame("Frame")
  list.name = "MemberList"
  frame.MemberList = list
  list.MemberCount = fs()
  list.ColumnDisplay = CreateFrame("Frame")
  list.ColumnDisplay.name = "ColumnDisplay"
  list.ColumnDisplay.columnHeaders = pool(function() return Stub.button(nil, "") end)
  function list.ColumnDisplay.LayoutColumns(self, columns)
    self.columnHeaders:ReleaseAll()
    for _, key in ipairs(columns) do self.columnHeaders:Acquire():SetText(en(key)) end
  end
  -- the roster ScrollBox (communitiesmemberlist.lua:454–457): pooled entries, CommunitiesMemberListEntryMixin:Init
  list.ScrollBox = Stub.scrollBox()
  C.rows = {}
  function C.initEntry(row, data) -- lua:1107–1115 (SetHeader / SetMember)
    if data.invitationHeaderCount then
      row.NameFrame.Name.text = string.format(en("COMMUNITIES_MEMBER_LIST_PENDING_INVITE_HEADER"),
        data.invitationHeaderCount)
    else
      row.NameFrame.Name.text = data.name
      row.member = data
    end
  end
  function C.entry(i, data)
    local row = C.rows[i]
    if not row then
      row = CreateFrame("Button")
      row.NameFrame = { Name = fs() }
      row.CancelInvitationButton = CreateFrame("Button")
      C.rows[i] = row
    end
    list.ScrollBox:initFrame(row, data, C.initEntry)
    return row
  end
  function list.UpdateMemberCount(self)
    self.MemberCount.text = string.format(en("COMMUNITIES_MEMBER_LIST_MEMBER_COUNT_FORMAT"), C.online, C.total)
  end
  -- member detail (guildroster.xml:4–98)
  local d = CreateFrame("Frame")
  d.name = "GuildMemberDetailFrame"
  frame.GuildMemberDetailFrame = d
  d.Name, d.Level, d.ZoneText, d.RankText, d.OnlineText = fs(), fs(), fs(), fs(), fs()
  d.ZoneLabel, d.RankLabel = fs(en("ZONE_COLON")), fs(en("RANK_COLON"))
  d.OnlineLabel, d.NoteLabel = fs(en("LAST_ONLINE_COLON")), fs(en("NOTE_COLON"))
  d.OfficerNoteLabel = fs(en("OFFICER_NOTE_COLON"))
  d.RemoveButton = Stub.button(nil, en("REMOVE"))
  d.GroupInviteButton = Stub.button(nil, en("GROUP_INVITE"))
  d.NoteBackground = { PersonalNoteText = fs() }
  d.OfficerNoteBackground = { OfficerNoteText = fs() }
  function d.DisplayMember(self, _, m)
    self.Name.text = m.name
    self.Level.text = string.format(en("FRIENDS_LEVEL_TEMPLATE"), m.level, m.class)
    self.ZoneText.text = m.zone
    self.RankText.text = m.rank
    self.OnlineText.text = m.lastOnlineDays and string.format(en("LASTONLINE_DAYS"), m.lastOnlineDays)
      or en("GUILD_ONLINE_LABEL")
    self.NoteBackground.PersonalNoteText.text = (m.note == nil or m.note == "") and en("GUILD_NOTE_EDITLABEL") or m.note
    self.OfficerNoteBackground.OfficerNoteText.text = (m.officerNote == nil or m.officerNote == "")
      and en("GUILD_OFFICERNOTE_EDITLABEL") or m.officerNote
  end
  -- guild details: info + news (communitiesframe.xml:161–176; guildinfo.xml:59–246; guildnews.xml:254–296)
  local details = CreateFrame("Frame", "CommunitiesFrameGuildDetailsFrame")
  frame.GuildDetailsFrame = details
  local info = CreateFrame("Frame")
  details.Info = info
  info.TitleText = fs(en("GUILD_INFO_TITLE"))
  info.Header1Label = fs(en("GUILD_FRAME_CHALLENGES"))
  info.Header2Label = fs(en("GUILD_MOTD_LABEL"))
  info:addRegion(fs(en("GUILD_INFORMATION")))
  info.EditMOTDButton = Stub.button(nil, en("GUILD_EDIT_TEXT_LINK"))
  info.EditDetailsButton = Stub.button(nil, en("GUILD_EDIT_TEXT_LINK"))
  info.MOTDScrollFrame = { MOTD = fs() }
  local news = CreateFrame("Frame")
  details.News = news
  news.TitleText = fs(en("GUILD_NEWS_TITLE"))
  news:addRegion(fs(en("GUILD_NEWS")))
  news.NoNews = fs(en("GUILD_NO_GUILD_NEWS"))
  news.SetFiltersButton = Stub.button(nil, en("GUILD_SET_FILTERS_LINK"))
  Stub.namedFontString("CommunitiesGuildLogFrameTitle", en("GUILD_EVENT_LOG"))
  local filters = CreateFrame("Frame", "CommunitiesGuildNewsFiltersFrame")
  filters.Title = fs(en("GUILD_NEWS_FILTERS"))
  -- guildinfo.lua:78–106: no challenges → HideChallenges rewrites Header1Label
  _G.CommunitiesGuildInfoFrame_UpdateChallenges = function(self)
    if not C.challenges then self.Header1Label.text = en("GUILD_MOTD_LABEL") end
  end
  Stub.loadedAddons[ADDON] = true
  return frame
end

local GUILD_COLUMNS = { "COMMUNITIES_ROSTER_COLUMN_TITLE_LEVEL", "COMMUNITIES_ROSTER_COLUMN_TITLE_CLASS",
  "COMMUNITIES_ROSTER_COLUMN_TITLE_NAME", "COMMUNITIES_ROSTER_COLUMN_TITLE_ZONE",
  "COMMUNITIES_ROSTER_COLUMN_TITLE_RANK", "COMMUNITIES_ROSTER_COLUMN_TITLE_NOTE" }

describe("the Communities guild view on Forever", function()
  local WFJ, SS

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  local function unrecorded(widget)
    for _, bucket in pairs(SS.surfaces()) do
      for _, rec in pairs(bucket) do
        if rec.fs == widget or (type(rec.fs) == "table" and rec.fs.button == widget) then return false end
      end
    end
    return true
  end

  local function headers()
    local out = {}
    for h in _G.CommunitiesFrame.MemberList.ColumnDisplay.columnHeaders:EnumerateActive() do
      out[#out + 1] = h:GetText()
    end
    return out
  end

  local function setup(loadedFirst)
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    SS = WFJ.SurfaceState
    H.uiSetup(WFJ, UI)
    C.online, C.total, C.challenges = 3, 12, false
    if loadedFirst then
      loadCommunities()
      assert.is_true(WFJ.Communities.init())
    else
      assert.is_false(WFJ.Communities.init()) -- waits for the addon
      loadCommunities()
      assert.are.equal(1, WFJ.LoadOnDemand.loaded(ADDON))
    end
  end

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    _G.CommunitiesFrame, _G.CommunitiesGuildInfoFrame_UpdateChallenges = nil, nil
  end)

  for _, order in ipairs({ { true, "loaded at login" }, { false, "loaded on demand" } }) do
    describe("Blizzard_Communities " .. order[2], function()
      before_each(function() setup(order[1]) end)

      it("column headers, the member count and the static labels are Japanese", function()
        _G.CommunitiesFrame.MemberList.ColumnDisplay:LayoutColumns(GUILD_COLUMNS)
        assert.are.same({ "Lv", "クラス", "名前", "ゾーン", "ランク", "メモ" }, headers())
        _G.CommunitiesFrame.MemberList:UpdateMemberCount()
        assert.are.equal("オンライン 3/12", _G.CommunitiesFrame.MemberList.MemberCount:GetText())
        local d = _G.CommunitiesFrame.GuildMemberDetailFrame
        assert.are.equal("ゾーン:", d.ZoneLabel:GetText())
        assert.are.equal("オフィサーメモ", d.OfficerNoteLabel:GetText())
        assert.are.equal("グループに招待", d.GroupInviteButton:GetText())
        local info = _G.CommunitiesFrame.GuildDetailsFrame.Info
        assert.are.equal("ギルド情報", info.TitleText:GetText())
        assert.are.equal("今日のギルドメッセージ", info.Header2Label:GetText())
        assert.are.equal("ギルド情報", (info:GetRegions()):GetText())
        assert.are.equal("ここをクリックして編集", info.EditMOTDButton:GetText())
        local news = _G.CommunitiesFrame.GuildDetailsFrame.News
        assert.are.equal("ギルドニュース", news.TitleText:GetText())
        assert.are.equal("ギルドニュース", (news:GetRegions()):GetText())
        assert.are.equal("ギルドニュースはありません", news.NoNews:GetText())
        assert.are.equal("フィルター設定", news.SetFiltersButton:GetText())
        assert.are.equal("ギルドイベントログ", _G.CommunitiesGuildLogFrameTitle:GetText())
        assert.are.equal("ギルドニュースフィルター", _G.CommunitiesGuildNewsFiltersFrame.Title:GetText())
        alt(true)
        assert.are.same({ "Lvl", "Class", "Name", "Zone", "Rank", "Note" }, headers())
        assert.are.equal("3/12 Online", _G.CommunitiesFrame.MemberList.MemberCount:GetText())
        alt(false)
        assert.are.same({ "Lv", "クラス", "名前", "ゾーン", "ランク", "メモ" }, headers())
      end)

      it("the window title is Japanese, again after a SetTitle, and a community name is left English",
        function()
          local title = _G.CommunitiesFrame.TitleContainer.TitleText
          assert.are.equal("ギルド&コミュニティ", title:GetText())
          _G.CommunitiesFrame:SetTitle(en("COMMUNITIES_FRAME_TITLE"))
          assert.are.equal("ギルド&コミュニティ", title:GetText())
          alt(true)
          assert.are.equal("Guild & Communities", title:GetText())
          alt(false)
          _G.CommunitiesFrame:SetTitle("Guild Info") -- a community could be named after a dictionary word
          assert.are.equal("Guild Info", title:GetText())
        end)

      it("a relayout with fewer columns reuses pooled headers: each shows its new title", function()
        local display = _G.CommunitiesFrame.MemberList.ColumnDisplay
        display:LayoutColumns(GUILD_COLUMNS)
        display:LayoutColumns({ "COMMUNITIES_ROSTER_COLUMN_TITLE_NAME", "COMMUNITIES_ROSTER_COLUMN_TITLE_RANK",
          "COMMUNITIES_ROSTER_COLUMN_TITLE_NOTE" })
        assert.are.same({ "名前", "ランク", "メモ" }, headers())
      end)

      it("member detail: level, online and the note placeholders translate; name, zone, rank and notes do not",
        function()
          local d = _G.CommunitiesFrame.GuildMemberDetailFrame
          d:DisplayMember(1, { name = "Close", level = 42, class = "Warrior", zone = "Close", rank = "Close" })
          assert.are.equal("レベル 42 Warrior", d.Level:GetText())
          assert.are.equal("オンライン", d.OnlineText:GetText())
          assert.are.equal("ここをクリックして公開メモを設定します。", d.NoteBackground.PersonalNoteText:GetText())
          assert.are.equal("ここをクリックしてオフィサーメモを設定します。",
            d.OfficerNoteBackground.OfficerNoteText:GetText())
          assert.are.equal("Close", d.Name:GetText())
          assert.are.equal("Close", d.ZoneText:GetText())
          assert.are.equal("Close", d.RankText:GetText())
          for _, w in ipairs({ d.Name, d.ZoneText, d.RankText }) do assert.is_true(unrecorded(w)) end
          d:DisplayMember(1, { name = "Thrall", level = 60, class = "Shaman", zone = "Orgrimmar", rank = "Warchief",
            lastOnlineDays = 3, note = "Close", officerNote = "Close" })
          assert.are.equal("3日", d.OnlineText:GetText())
          assert.are.equal("Close", d.NoteBackground.PersonalNoteText:GetText()) -- a member's own note
          assert.are.equal("Close", d.OfficerNoteBackground.OfficerNoteText:GetText())
        end)

      it("the applicants column header translates", function()
        _G.CommunitiesFrame.MemberList.ColumnDisplay:LayoutColumns({ "CLUB_FINDER_APPLICANTS",
          "COMMUNITIES_ROSTER_COLUMN_TITLE_NAME" })
        assert.are.same({ "応募者", "名前" }, headers())
      end)

      it("the pending-invite header row translates; a reused row shows a member's name as written", function()
        local row = C.entry(1, { invitationHeaderCount = 2 })
        assert.are.equal("保留中の招待 (2)", row.NameFrame.Name:GetText())
        C.entry(1, { name = "Close" })
        assert.are.equal("Close", row.NameFrame.Name:GetText())
        alt(true); alt(false)
        assert.are.equal("Close", row.NameFrame.Name:GetText())
        assert.is_true(unrecorded(row.NameFrame.Name))
      end)

      it("the entry tooltip's level line translates with race and class kept; names, rank and zone do not",
        function()
          local row = C.entry(1, { name = "Thrall" })
          local tt = _G.GameTooltip
          tt:SetOwner(row)
          tt:AddLine("Close") -- the name (a member called like a UI word)
          tt:AddLine("Close") -- the guild rank
          tt:AddLine(string.format(en("COMMUNITY_MEMBER_CHARACTER_INFO_FORMAT"), 60, "Orc", "Shaman"))
          tt:AddLine("Close") -- the zone
          tt:Show()
          assert.are.equal("Close", _G.GameTooltipTextLeft1:GetText())
          assert.are.equal("Close", _G.GameTooltipTextLeft2:GetText())
          assert.are.equal("レベル 60 Orc Shaman", _G.GameTooltipTextLeft3:GetText())
          assert.are.equal("Close", _G.GameTooltipTextLeft4:GetText())
          tt:SetOwner(row.CancelInvitationButton)
          tt:SetText(en("COMMUNITY_MEMBER_CANCEL_INVITATION_TOOLTIP"))
          assert.are.equal("クリックで招待を取り消します", _G.GameTooltipTextLeft1:GetText())
        end)

      it("the info header follows CommunitiesGuildInfoFrame_UpdateChallenges", function()
        local info = _G.CommunitiesFrame.GuildDetailsFrame.Info
        assert.are.equal("ギルドチャレンジ", info.Header1Label:GetText())
        _G.CommunitiesGuildInfoFrame_UpdateChallenges(info)
        assert.are.equal("今日のギルドメッセージ", info.Header1Label:GetText())
      end)
    end)
  end

  it("hooks install once", function()
    setup(true)
    assert.is_false(WFJ.Communities.setup())
    assert.are.equal(1, #Stub.hooks["MemberList:UpdateMemberCount"])
    assert.are.equal(1, #Stub.hooks["ColumnDisplay:LayoutColumns"])
    assert.are.equal(1, #Stub.hooks["GuildMemberDetailFrame:DisplayMember"])
  end)
end)
