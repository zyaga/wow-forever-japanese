-- UI/GroupFinder.lua over LFGParentFrame replayed from camelot
-- blizzard_groupfinder_vanillastyle (blizzard_lfgvanilla_parentframe.lua:73–78, blizzard_lfgvanilla_listing.lua:
-- 613–652 + 1089–1097 + 822–838, blizzard_lfgvanilla_browse.lua:73–79 + 189 + 305 + 410–419 + 654–659, the Menu
-- dropdown's UpdateText). A leader's name never changes; a dungeon's, raid's or zone's name shows its Japanese
-- only while Japanese names are on; both load orders.
local S = require("tests.lua.spec.stub_camelot_social")
local Stub = require("tests.lua.spec.wow_stub")
local M = require("tests.lua.spec.menu_stub")

local FILES = S.files("UI/GroupFinder.lua")
local ADDON = "Blizzard_GroupFinder_VanillaStyle"

local UI = {
  LFG_TITLE = { "Looking For Group", "グループ検索" },
  LFG_LIST_TAB_1 = { "Create Listing", "募集を作成" }, LFG_LIST_EDIT = { "Edit Listing", "募集を編集" },
  LFG_LIST_TAB_2 = { "Group Browser", "グループ一覧" }, LFG_LIST_TAB_3 = { "Who List", "Whoリスト" },
  LFG_LIST_UNLIST = { "Delist", "募集を取り下げ" },
  BACK = { "Back", "戻る" }, INVTYPE_CLOAK = { "Back", "背中" },
  GROUP_FINDER_PLAYSTYLE_REQUIRED = { "Select Playstyle (required)", "プレイスタイルを選択 (必須)" },
  LFG_POST_GROUP_SOLO = { "List Self", "自分を登録" }, LFG_POST_GROUP_PARTY = { "List Group", "グループを登録" },
  LFG_POST_GROUP_UPDATE = { "Update", "更新" }, ROLE_POLL = { "Role Check", "ロールチェック" },
  LFG_LIST_ONLY_LEADER_CREATE = { "Only the group leader can create a listing for your group.",
    "募集を作成できるのはグループリーダーのみです。" },
  LFG_LIST_ONLY_LEADER_UPDATE = { "Only the group leader can modify your group's listing.",
    "募集を変更できるのはグループリーダーのみです。" },
  LFG_LIST_MY_ACTIVITY_LIST_HEADER = { "Your group is currently listed for:", "現在の募集内容:" },
  DESCRIPTION_OF_YOUR_GROUP = { "More details about your group (optional)", "グループの詳細 (任意)" },
  LFG_LIST_NO_RESULTS_FOUND = { "No groups found.", "グループが見つかりません。" },
  LFG_LIST_SEARCH_FAILED = { "Search Failed. Please wait a moment and try again.", "検索に失敗しました。" },
  SEARCHING = { "Searching...", "検索中..." }, SEND_MESSAGE = { "Send Message", "メッセージを送る" },
  GROUP_INVITE = { "Group Invite", "グループに招待" },
  LFG_LIST_ENTRY_DELISTED = { "This group has been delisted.", "この募集は取り下げられました。" },
  LFG_LIST_TOOLTIP_MEMBERS = { "Members: |cffffffff%d (%d/%d/%d)|r", "メンバー: |cffffffff%d (%d/%d/%d)|r" },
  LFG_LIST_TOOLTIP_MEMBERS_SIMPLE = { "Members: |cffffffff%d|r", "メンバー: |cffffffff%d|r" },
  LFG_SELF_LISTING = { "Your Listing", "自分の募集" },
  LFGBROWSE_ACTIVITY_COUNT = { "%d |4activity:activities;", "アクティビティ %d件" },
  LFG_TOOLTIP_ROLES = { "Roles:", "ロール:" },
  LFG_LIST_CATEGORY_GROUPS = { "Groups", "グループ" }, LFG_LIST_CATEGORY_SOLO_PLAYERS = { "Players", "プレイヤー" },
  GROUP_FINDER_GENERAL_PLAYSTYLE1 = { "Learning", "練習" }, GROUP_FINDER_GENERAL_PLAYSTYLE2 = { "Relaxed", "気楽に" },
  GROUP_FINDER_GENERAL_PLAYSTYLE3 = { "Competitive", "本気で" },
  GROUP_FINDER_GENERAL_PLAYSTYLE4 = { "Carry Offered", "キャリー可" },
  CATEGORY = { "Category", "カテゴリ" }, LFG_TYPE_NONE = { "None", "なし" },
  LFGBROWSE_ACTIVITY_HEADER_DEFAULT = { "Filter by activity", "アクティビティで絞り込む" },
  TANK = { "Tank", "タンク" }, HEALER = { "Healer", "ヒーラー" },
  SELECT_YOUR_ROLE = { "Select Your Role", "ロールを選択" },
  ROLE_DESCRIPTION_TANK = { "Indicates that you are willing to protect allies.", "味方を守る意思があることを示します。" },
  CLASS_ROLE_NOT_RECOMMENDED = { "This role is not recommended for your current character's class.",
    "このロールは現在のクラスには推奨されません。" },
  LFG_LIST_SEARCH_AGAIN = { "Search Again", "再検索" },
  CLOSE = { "Close", "閉じる" }, -- a word a leader or an activity may happen to be called
  BOSSES_KILLED = { "%d/%d Bosses Defeated", "ボス撃破 %d/%d" }, -- an activity row's lockout warning
  -- the listing's client-table words
  ["LfgCategory:2"] = { "Dungeons", "ダンジョン" }, ["LfgActivityGroup:12"] = { "World PvP", "ワールドPvP" },
  ["LfgActivity:285"] = { "Custom", "カスタム" }, ["LfgActivityGroup:285"] = { "Dungeons", "ダンジョン" },
  -- the listing's voice chat row and a result tooltip's voice line (listing.xml:554, 631; listing.lua:48–69;
  -- browse.lua:674–682)
  VOICE_CHAT = { "Voice Chat", "ボイスチャット" },
  -- the level-range checkbox's label (mainline/blizzard_lfgvanilla_listing.xml:564–589)
  LFG_LIST_IGNORE_SUGGESTED_LEVEL = { "Show All Level Ranges", "すべてのレベル帯を表示" },
  VOICE_CHAT_MODE_NONE = { "None", "なし" }, VOICE_CHAT_MODE_LEGACY = { "In-Game Voice (Legacy)", "ゲーム内ボイス(レガシー)" },
  VOICE_CHAT_MODE_FORMAT = { "Voice Chat: |cnHIGHLIGHT_FONT_COLOR:%s|r", "ボイスチャット: |cnHIGHLIGHT_FONT_COLOR:%s|r" },
}

local C = {} -- replayed client state

local function loadGroupFinder(o)
  o = o or {}
  local en = S.en
  local parent = S.frame("LFGParentFrame")
  for i, key in ipairs({ "LFG_LIST_TAB_1", "LFG_LIST_TAB_2", "LFG_LIST_TAB_3" }) do
    parent["Tab" .. i] = S.button(nil, en(key))
  end
  parent.ListingTab, parent.BrowsingTab, parent.WhoListingTab = S.frame(), S.frame(), S.frame()
  function parent.UpdateTabs(self) S.write(self.Tab1, en(C.listed and "LFG_LIST_EDIT" or "LFG_LIST_TAB_1")) end
  if not o.noWhoList then
    local who = S.frame("LFGWhoListFrame")
    S.put(who, "TitleContainer.TitleText", S.fs(en("LFG_TITLE"))) -- LFGWhoListMixin:OnLoad, wholist.lua:201–203
  end

  local listing = S.frame("LFGListingFrame")
  S.put(listing, "TitleContainer.TitleText", S.fs(en("LFG_TITLE")))
  listing.BackButton, listing.PostButton = S.button(nil, "Back"), S.button(nil, "")
  S.put(listing, "GroupRoleButtons.RolePollButton", S.button(nil, en("ROLE_POLL")))
  listing.GroupRoleButtons.RoleDropdown = S.dropdown("RoleDropdown")
  listing.GroupRoleButtons.RoleIcon = S.frame()
  S.put(listing, "SoloRoleButtons.Tank", S.frame())
  listing.SoloRoleButtons.Healer, listing.SoloRoleButtons.DPS = S.frame(), S.frame()
  listing.NewPlayerFriendlyButton = S.frame()
  S.put(listing, "LockedView.ErrorText", S.fs(en("LFG_LIST_ONLY_LEADER_CREATE")))
  listing.LockedView.ActivityText = S.fs(en("LFG_LIST_MY_ACTIVITY_LIST_HEADER"))
  -- LFGListingLockedViewActivityTemplate: a frame sized to its Text (listing.xml:227–250, listing.lua:1322–1326)
  listing.LockedView.framePool = S.pool(function()
    local frame = CreateFrame("Frame")
    frame.Text = S.fs("")
    function frame.Text.GetWidth(self) return #self.text * 7 end
    function frame.Text.GetHeight() return 14 end
    return frame
  end)
  listing.ActivityView = S.frame(nil, "ActivityView")
  listing.ActivityView.PlayStyleDropdown = S.dropdown("PlayStyleDropdown")
  listing.ActivityView.VoiceChatLabel = S.fs(en("VOICE_CHAT"))
  listing.ActivityView.LevelRangesCheckbox = S.frame()
  listing.ActivityView.LevelRangesCheckbox.Text = S.fs(en("LFG_LIST_IGNORE_SUGGESTED_LEVEL"))
  listing.ActivityView.VoiceChatDropdown = S.dropdown("VoiceChatDropdown")
  local comment = S.frame("LFGListingComment")
  comment.EditBox = CreateFrame("EditBox")
  comment.EditBox.Instructions = S.fs("")
  listing.ActivityView:SetScript("OnShow", function() -- LFGListingActivityView_OnShow, bound by reference
    comment.EditBox.Instructions.text = en("DESCRIPTION_OF_YOUR_GROUP")
  end)
  _G.LFGListingPostButton_UpdateText = function(self)
    S.write(self, en(C.listed and "LFG_POST_GROUP_UPDATE" or (C.grouped and "LFG_POST_GROUP_PARTY"
      or "LFG_POST_GROUP_SOLO")))
  end
  _G.LFGListingBackButton_UpdateText = function(self) S.write(self, C.listed and en("LFG_LIST_UNLIST") or "Back") end
  _G.LFGListingLockedView_RefreshContent = function(self)
    self.ErrorText.text = en(C.listed and "LFG_LIST_ONLY_LEADER_UPDATE" or "LFG_LIST_ONLY_LEADER_CREATE")
    self.framePool:ReleaseAll()
    for _, line in ipairs(C.lockedLines or {}) do -- LFGListingLockedView_SetLineContent
      local frame = self.framePool:Acquire()
      -- a collapsed group's line carries its hover: { text, tooltip } (listing.lua:1294–1300, 1325)
      local grouped = type(line) == "table"
      frame.Text.text, frame.tooltip = grouped and line[1] or line, grouped and line[2] or nil
      frame:SetSize(frame.Text:GetWidth(), frame.Text:GetHeight())
    end
  end
  _G.LFGListingPostButton_UpdateText(listing.PostButton) -- its OnLoad

  local browse = S.frame("LFGBrowseFrame")
  S.put(browse, "TitleContainer.TitleText", S.fs(en("LFG_TITLE")))
  browse.NoResultsFound = S.fs(en("LFG_LIST_NO_RESULTS_FOUND"))
  S.put(browse, "SearchingSpinner.Label", S.fs(en("SEARCHING")))
  browse.SendMessageButton = S.button(nil, en("SEND_MESSAGE"))
  browse.GroupInviteButton = S.button(nil, en("GROUP_INVITE"))
  browse.RefreshButton = S.frame()
  browse.CategoryDropdown, browse.ActivityDropdown = S.dropdown("CategoryDropdown"), S.dropdown("ActivityDropdown")
  browse.CategoryDropdown:SetDefaultText(en("CATEGORY"))
  browse.ActivityDropdown:SetDefaultText(en("LFGBROWSE_ACTIVITY_HEADER_DEFAULT"))
  browse.ScrollBox = Stub.scrollBox()
  function browse.UpdateResults(self)
    self.NoResultsFound.text = en(C.failed and "LFG_LIST_SEARCH_FAILED" or "LFG_LIST_NO_RESULTS_FOUND")
  end
  function browse.UpdateButtonState(self) S.write(self.GroupInviteButton, en("GROUP_INVITE")) end
  _G.LFGBrowseSearchEntry_Update = function(row)
    local d = row.elementData
    row.Name.text = d.leader
    row.ActivityName.text = d.own and en("LFG_SELF_LISTING")
      or (d.count and ("%d activities"):format(d.count) or d.activity)
    if d.playstyle then row.PlaystyleLabel.text = en(d.playstyle) end -- blizzard_lfgvanilla_browse.lua:477–478
  end
  function C.entry(row, data)
    if not row then
      row = CreateFrame("Button")
      row.Name, row.ActivityName, row.PlaystyleLabel = S.fs(), S.fs(), S.fs()
      row.DataDisplay = { Solo = { RolesText = S.fs(en("LFG_TOOLTIP_ROLES")) }, DelistButton = S.frame() }
    end
    browse.ScrollBox:initFrame(row, data, function(r) _G.LFGBrowseSearchEntry_Update(r) end)
    return row
  end
  function C.divider(solo)
    local row = CreateFrame("Button")
    row.CategoryLabel = S.fs()
    browse.ScrollBox:initFrame(row, {}, function(r)
      r.CategoryLabel.text = en(solo and "LFG_LIST_CATEGORY_SOLO_PLAYERS" or "LFG_LIST_CATEGORY_GROUPS")
    end)
    return row
  end

  local tip = S.frame("LFGBrowseSearchEntryTooltip")
  tip.Delisted = S.fs(en("LFG_LIST_ENTRY_DELISTED"))
  tip.NewPlayerFriendlyText, tip.CompletedEncounterHeader, tip.MemberCount, tip.Comment = S.fs(), S.fs(), S.fs(), S.fs()
  tip.Leader = { Name = S.fs() }
  tip.VoiceChat = S.fs()
  -- the tooltip's pooled lines (browse.lua:564–565): one line, held between the tooltip's edges
  local function tipLine()
    local fs = S.fs("")
    fs.GetParent = function() return tip end
    function fs.GetUnboundedStringWidth(self) return #self.text * 7 end
    return fs
  end
  tip.activityPool, tip.completedEncounterPool = S.pool(tipLine), S.pool(tipLine)
  -- an activity row's init (listing.lua:989–1029): its lockout warning icon owns a BOSSES_KILLED tooltip
  _G.LFGListingActivityView_InitActivityButton = function(button, data)
    if button.InstanceLockWarningIcon then button.InstanceLockWarningIcon.encountersCompleted = data.done end
    if data.name then -- the row's name, the name button sized to it (listing.lua:1000–1001)
      button.NameButton.Name.text = data.name
      button.NameButton:SetWidth(button.NameButton.Name:GetWidth())
    end
  end
  -- an activity group row (listing.lua:946–988) and a category button (listing.lua:702–718)
  _G.LFGListingActivityView_InitActivityGroupButton = function(button, data)
    button.NameButton.Name.text = data.name
    button.NameButton:SetWidth(button.NameButton.Name:GetWidth())
  end
  _G.LFGListingCategorySelection_AddButton = function(self, index, categoryID)
    self.CategoryButtons[index] = self.CategoryButtons[index] or S.button(nil, "")
    S.write(self.CategoryButtons[index], C.categoryNames[categoryID])
  end
  _G.LFGBrowseSearchEntryTooltip_UpdateAndShow = function(self, n, roles, voice)
    self.Leader.Name.text = "Close"
    if voice then self.VoiceChat.text = ("Voice Chat: |cnHIGHLIGHT_FONT_COLOR:%s|r"):format(voice) end
    self.MemberCount.text = roles and ("Members: |cffffffff%d (%d/%d/%d)|r"):format(n, unpack(roles))
      or ("Members: |cffffffff%d|r"):format(n)
    self.activityPool:ReleaseAll() -- browse.lua:711–806
    for _, line in ipairs(C.tipActivities or {}) do self.activityPool:Acquire().text = line end
    self.completedEncounterPool:ReleaseAll() -- browse.lua:813–833
    for _, boss in ipairs(C.tipBosses or {}) do self.completedEncounterPool:Acquire().text = boss end
  end
  Stub.loadedAddons[ADDON] = true
end

local GLOBALS = { "LFGParentFrame", "LFGWhoListFrame", "LFGListingFrame", "LFGListingComment", "LFGBrowseFrame",
  "LFGBrowseSearchEntryTooltip", "LFGListingPostButton_UpdateText", "LFGListingBackButton_UpdateText",
  "LFGListingLockedView_RefreshContent", "LFGBrowseSearchEntry_Update", "LFGBrowseSearchEntryTooltip_UpdateAndShow",
  "LFGListingActivityView_InitActivityButton", "LFGListingActivityView_InitActivityGroupButton",
  "LFGListingCategorySelection_AddButton", "EventRegistry" }

-- a listing row whose NameButton.Name is a FontString with a width that follows its text
local function nameRow()
  local name = S.fs("")
  function name.GetWidth(self) return (self.width == 0 or self.width == nil) and #self.text * 7 or self.width end
  local nb = CreateFrame("Button")
  nb.Name = name
  return { NameButton = nb }
end

describe("the group finder on Forever", function()
  local WFJ

  local function setup(loadedFirst)
    WFJ = S.load(FILES, UI)
    C.listed, C.grouped, C.failed = false, false, false
    C.lockedLines, C.tipActivities, C.tipBosses = nil, nil, nil
    if loadedFirst then
      loadGroupFinder()
      assert.is_true(WFJ.GroupFinder.init())
    else
      assert.is_false(WFJ.GroupFinder.init()) -- waits for the addon
      loadGroupFinder()
      assert.are.equal(1, WFJ.LoadOnDemand.loaded(ADDON))
    end
  end

  after_each(function() S.teardown(GLOBALS) end)

  for _, order in ipairs({ { true, "loaded at login" }, { false, "loaded on demand" } }) do
    describe(ADDON .. " " .. order[2], function()
      before_each(function() setup(order[1]) end)

      it("titles, tabs, buttons and static labels are Japanese; Alt shows English", function()
        local listing, browse = _G.LFGListingFrame, _G.LFGBrowseFrame
        assert.are.equal("グループ検索", listing.TitleContainer.TitleText:GetText())
        assert.are.equal("グループ検索", browse.TitleContainer.TitleText:GetText())
        assert.are.equal("グループ検索", _G.LFGWhoListFrame.TitleContainer.TitleText:GetText())
        assert.are.equal("募集を作成", _G.LFGParentFrame.Tab1:GetText())
        assert.are.equal("自分を登録", listing.PostButton:GetText())
        assert.are.equal("ロールチェック", listing.GroupRoleButtons.RolePollButton:GetText())
        assert.are.equal("現在の募集内容:", listing.LockedView.ActivityText:GetText())
        assert.are.equal("検索中...", browse.SearchingSpinner.Label:GetText())
        assert.are.equal("メッセージを送る", browse.SendMessageButton:GetText())
        assert.are.equal("この募集は取り下げられました。", _G.LFGBrowseSearchEntryTooltip.Delisted:GetText())
        assert.are.equal("戻る", listing.BackButton:GetText()) -- asked for by key: "Back" is also a cloak's slot
        S.alt(WFJ, true)
        assert.are.equal("Looking For Group", listing.TitleContainer.TitleText:GetText())
        assert.are.equal("List Self", listing.PostButton:GetText())
        S.alt(WFJ, false)
        assert.are.equal("自分を登録", listing.PostButton:GetText())
      end)

      it("the writers' texts follow the listing state", function()
        local listing, browse = _G.LFGListingFrame, _G.LFGBrowseFrame
        C.listed = true
        _G.LFGParentFrame:UpdateTabs()
        _G.LFGListingPostButton_UpdateText(listing.PostButton)
        _G.LFGListingBackButton_UpdateText(listing.BackButton)
        _G.LFGListingLockedView_RefreshContent(listing.LockedView)
        assert.are.equal("募集を編集", _G.LFGParentFrame.Tab1:GetText())
        assert.are.equal("更新", listing.PostButton:GetText())
        assert.are.equal("募集を取り下げ", listing.BackButton:GetText())
        assert.are.equal("募集を変更できるのはグループリーダーのみです。", listing.LockedView.ErrorText:GetText())
        listing.ActivityView:Show()
        assert.are.equal("グループの詳細 (任意)", _G.LFGListingComment.EditBox.Instructions:GetText())
        C.failed = true
        browse:UpdateResults()
        assert.are.equal("検索に失敗しました。", browse.NoResultsFound:GetText())
        browse:UpdateButtonState()
        assert.are.equal("グループに招待", browse.GroupInviteButton:GetText())
      end)

      it("result rows: counts and the own listing translate; a leader and an activity name never do", function()
        local row = C.entry(nil, { leader = "Close", count = 3 })
        assert.are.equal("アクティビティ 3件", row.ActivityName:GetText())
        assert.are.equal("ロール:", row.DataDisplay.Solo.RolesText:GetText())
        assert.are.equal("Close", row.Name:GetText())
        C.entry(row, { leader = "Close", activity = "Close" }) -- the pooled row reused: an activity called "Close"
        assert.are.equal("Close", row.ActivityName:GetText())
        assert.is_true(S.unrecorded(WFJ, row.Name))
        assert.is_true(S.unrecorded(WFJ, row.ActivityName))
        row.elementData = { leader = "Thrall", own = true }
        _G.LFGBrowseSearchEntry_Update(row) -- the row's own event refresh
        assert.are.equal("自分の募集", row.ActivityName:GetText())
        assert.are.equal("グループ", C.divider(false).CategoryLabel:GetText())
        assert.are.equal("プレイヤー", C.divider(true).CategoryLabel:GetText())
      end)

      it("the result tooltip's member count translates; the leader's name does not", function()
        local tip = _G.LFGBrowseSearchEntryTooltip
        _G.LFGBrowseSearchEntryTooltip_UpdateAndShow(tip, 4, { 1, 1, 2 })
        assert.are.equal("メンバー: |cffffffff4 (1/1/2)|r", tip.MemberCount:GetText())
        _G.LFGBrowseSearchEntryTooltip_UpdateAndShow(tip, 1)
        assert.are.equal("メンバー: |cffffffff1|r", tip.MemberCount:GetText())
        assert.are.equal("Close", tip.Leader.Name:GetText())
        assert.is_true(S.unrecorded(WFJ, tip.Leader.Name))
      end)

      it("the level-range checkbox's label translates; Alt shows English", function()
        local text = _G.LFGListingFrame.ActivityView.LevelRangesCheckbox.Text
        assert.are.equal("すべてのレベル帯を表示", text:GetText())
        Stub.keys.alt = true; WFJ.Modifier.refresh()
        assert.are.equal("Show All Level Ranges", text:GetText())
        Stub.keys.alt = false; WFJ.Modifier.refresh()
        assert.are.equal("すべてのレベル帯を表示", text:GetText())
      end)

      it("the voice chat label, dropdown and tooltip line translate; Alt shows English; another mode stays", function()
        local view, tip = _G.LFGListingFrame.ActivityView, _G.LFGBrowseSearchEntryTooltip
        assert.are.equal("ボイスチャット", view.VoiceChatLabel:GetText())
        view.VoiceChatDropdown:SetSelectionText("In-Game Voice (Legacy)")
        assert.are.equal("ゲーム内ボイス(レガシー)", view.VoiceChatDropdown.Text:GetText())
        _G.LFGBrowseSearchEntryTooltip_UpdateAndShow(tip, 1, nil, "In-Game Voice (Legacy)")
        assert.are.equal("ボイスチャット: |cnHIGHLIGHT_FONT_COLOR:ゲーム内ボイス(レガシー)|r", tip.VoiceChat:GetText())
        Stub.keys.alt = true; WFJ.Modifier.refresh()
        assert.are.equal("Voice Chat: |cnHIGHLIGHT_FONT_COLOR:In-Game Voice (Legacy)|r", tip.VoiceChat:GetText())
        assert.are.equal("Voice Chat", view.VoiceChatLabel:GetText())
        Stub.keys.alt = false; WFJ.Modifier.refresh()
        _G.LFGBrowseSearchEntryTooltip_UpdateAndShow(tip, 1, nil, "Other") -- not an entry here
        assert.are.equal("Voice Chat: |cnHIGHLIGHT_FONT_COLOR:Other|r", tip.VoiceChat:GetText())
      end)

      it("a Japanese voice line wider than the tooltip widens it; a narrower one leaves the width", function()
        local tip = _G.LFGBrowseSearchEntryTooltip
        local width = 100
        tip.GetWidth = function() return width end
        tip.SetWidth = function(_, w) width = w end
        tip.VoiceChat.GetParent = function() return tip end
        tip.VoiceChat.GetStringWidth = function() return 300 end
        _G.LFGBrowseSearchEntryTooltip_UpdateAndShow(tip, 1, nil, "In-Game Voice (Legacy)")
        assert.are.equal(322, width)
        tip.VoiceChat.GetStringWidth = function() return 50 end
        _G.LFGBrowseSearchEntryTooltip_UpdateAndShow(tip, 1, nil, "In-Game Voice (Legacy)")
        assert.are.equal(322, width)
      end)

      it("dropdown buttons: default and fixed selections translate; a category name does not", function()
        local browse, roles = _G.LFGBrowseFrame, _G.LFGListingFrame.GroupRoleButtons.RoleDropdown
        assert.are.equal("カテゴリ", browse.CategoryDropdown.Text:GetText())
        assert.are.equal("アクティビティで絞り込む", browse.ActivityDropdown.Text:GetText())
        browse.CategoryDropdown:SetSelectionText("None")
        assert.are.equal("なし", browse.CategoryDropdown.Text:GetText())
        browse.CategoryDropdown:SetSelectionText("Close") -- a category's name: client-table text
        assert.are.equal("Close", browse.CategoryDropdown.Text:GetText())
        roles:SetSelectionText("Healer")
        assert.are.equal("ヒーラー", roles.Text:GetText())
        local playstyle = _G.LFGListingFrame.ActivityView.PlayStyleDropdown
        playstyle:SetSelectionText("Relaxed")
        assert.are.equal("気楽に", playstyle.Text:GetText())
        -- with none chosen the client shows the prompt inside a colour code (listing.lua:921–923)
        playstyle.text = nil
        playstyle:SetDefaultText("|cff808080Select Playstyle (required)|r")
        assert.are.equal("|cff808080プレイスタイルを選択 (必須)|r", playstyle.Text:GetText())
      end)

      it("a result's playstyle line translates; the leader's name next to it does not", function()
        local row = C.entry(nil, { leader = "Learning", activity = "Custom",
          playstyle = "GROUP_FINDER_GENERAL_PLAYSTYLE4" })
        assert.are.equal("キャリー可", row.PlaystyleLabel:GetText())
        assert.are.equal("Learning", row.Name:GetText())
      end)

      it("help tooltips: each owner shows only its own keys", function()
        local listing = _G.LFGListingFrame
        assert.are.same({ "味方を守る意思があることを示します。", "このロールは現在のクラスには推奨されません。" },
          S.tooltip(listing.SoloRoleButtons.Tank,
            { S.en("ROLE_DESCRIPTION_TANK"), S.en("CLASS_ROLE_NOT_RECOMMENDED") }))
        assert.are.same({ "ロールを選択" }, S.tooltip(listing.GroupRoleButtons.RoleDropdown, { "Select Your Role" }))
        assert.are.same({ "募集を作成" }, S.tooltip(_G.LFGParentFrame.ListingTab, { "Create Listing" }))
        assert.are.same({ "再検索" }, S.tooltip(_G.LFGBrowseFrame.RefreshButton, { "Search Again" }))
        assert.are.same({ "Close" }, S.tooltip(_G.LFGBrowseFrame.RefreshButton, { "Close" }))
      end)

      it("category, activity group and activity names from the client tables; a dungeon stays; Alt",
        function()
          C.categoryNames = { [2] = "Dungeons", [4] = "Raids" }
          local selection = { CategoryButtons = {} }
          _G.LFGListingCategorySelection_AddButton(selection, 1, 2)
          _G.LFGListingCategorySelection_AddButton(selection, 2, 4) -- a category with no row
          assert.are.equal("ダンジョン", selection.CategoryButtons[1]:GetText())
          assert.are.equal("Raids", selection.CategoryButtons[2]:GetText())
          local group = nameRow()
          _G.LFGListingActivityView_InitActivityGroupButton(group, { name = "World PvP" })
          assert.are.equal("ワールドPvP", group.NameButton.Name:GetText())
          assert.are.equal(#"ワールドPvP" * 7, group.NameButton.size[1]) -- re-sized to the Japanese
          local custom, dungeon = nameRow(), nameRow()
          _G.LFGListingActivityView_InitActivityButton(custom, { name = "Custom" })
          _G.LFGListingActivityView_InitActivityButton(dungeon, { name = "Deadmines" })
          assert.are.equal("カスタム", custom.NameButton.Name:GetText())
          assert.are.equal(#"カスタム" * 7, custom.NameButton.size[1])
          assert.are.equal("Deadmines", dungeon.NameButton.Name:GetText())
          assert.are.equal(#"Deadmines" * 7, dungeon.NameButton.size[1])
          assert.is_true(S.unrecorded(WFJ, dungeon.NameButton.Name))
          _G.LFGListingActivityView_InitActivityButton(custom, { name = "Custom Group" }) -- the pooled row reused
          assert.are.equal("Custom Group", custom.NameButton.Name:GetText())
          -- a browse row's single activity name
          local row = C.entry(nil, { leader = "Close", activity = "Custom" })
          assert.are.equal("カスタム", row.ActivityName:GetText())
          S.alt(WFJ, true)
          assert.are.equal("Dungeons", selection.CategoryButtons[1]:GetText())
          assert.are.equal("World PvP", group.NameButton.Name:GetText())
          assert.are.equal(#"World PvP" * 7, group.NameButton.size[1]) -- the record's refit: sized to the English
          assert.are.equal("Custom", row.ActivityName:GetText())
          S.alt(WFJ, false)
          assert.are.equal("ワールドPvP", group.NameButton.Name:GetText())
          assert.is_nil(WFJ.UIIndex:match("World PvP")) -- the families only where a widget names them
        end)

      it("an activity row's lockout icon: BOSSES_KILLED with its counts kept; Alt English", function()
        local row = { InstanceLockWarningIcon = CreateFrame("Frame") }
        _G.LFGListingActivityView_InitActivityButton(row, { done = 2 })
        assert.are.same({ "ボス撃破 2/4" }, S.tooltip(row.InstanceLockWarningIcon, { "2/4 Bosses Defeated" }))
        assert.are.same({ "Close" }, S.tooltip(row.InstanceLockWarningIcon, { "Close" }))
        S.tooltip(row.InstanceLockWarningIcon, { "2/4 Bosses Defeated" })
        S.alt(WFJ, true)
        assert.are.equal("2/4 Bosses Defeated", _G.GameTooltipTextLeft1:GetText())
        S.alt(WFJ, false)
      end)
    end)
  end

  -- Japanese names (the names setting): every activity that is no table word is a dungeon, a raid, a battleground
  -- or a zone, and a group with no table word is a continent.
  describe("with the names list loaded", function()
    local registry
    local FILES_MENUS = S.files("UI/SettingsKeys.lua", "UI/Menus.lua", "UI/MenusUntagged.lua", "UI/GroupFinder.lua")
    local NORTH, GATE = "ダイア・モール（ノース）", "ストラトホルム（メイン・ゲート）"

    local function names(on)
      WFJ.State.setNames(on)
    end

    before_each(function()
      WFJ = S.load(FILES_MENUS, UI)
      WFJ.State.setNames(false) -- the setting's own default: names are English until the player chooses
      registry = M.registry()
      C.listed, C.grouped, C.failed = false, false, false
      C.lockedLines, C.tipActivities, C.tipBosses = nil, nil, nil
      WFJ.Data.add("name", {
        [WFJ.Names.key("Deadmines")] = "デッドマインズ\tでっどまいんず",
        [WFJ.Names.key("Dire Maul (North)")] = NORTH .. "\tだいあ・もーるのーす",
        [WFJ.Names.key("Stratholme (Main Gate)")] = GATE .. "\tすとらとほるむめいん・げーと",
        [WFJ.Names.key("Kalimdor")] = "カリムドア\tかりむどあ",
        [WFJ.Names.key("Baron Rivendare")] = "バロン・リーヴェンデア\tばろん・りーゔぇんであ",
      })
      WFJ.UIStrings.name = function(text) return WFJ.State.names and WFJ.Names.value(text) or nil end -- as Main does
      loadGroupFinder()
      assert.is_true(WFJ.GroupFinder.init())
      assert.is_true(WFJ.Menus.init())
    end)

    after_each(function()
      WFJ.UIStrings.name = nil
      WFJ.State.setNames(false)
    end)

    local function open(tag, build)
      local root = M.element("root")
      root.tag = tag
      build(root)
      local frames, menus = M.open(registry, tag, root)
      local texts = {}
      for i, e in ipairs(root.children) do texts[i] = frames[e].fontString end
      return texts, menus
    end

    it("a listing row: a dungeon in Japanese while names are, the button sized to it; off, Alt, no line", function()
      local dungeon, unknown, zone, group = nameRow(), nameRow(), nameRow(), nameRow()
      local function fill()
        _G.LFGListingActivityView_InitActivityButton(dungeon, { name = "Dire Maul (North)" })
        _G.LFGListingActivityView_InitActivityButton(unknown, { name = "Blackmaw Hold" })
        _G.LFGListingActivityView_InitActivityGroupButton(zone, { name = "Kalimdor" })
        _G.LFGListingActivityView_InitActivityGroupButton(group, { name = "Dungeons" })
      end
      fill()
      assert.are.equal("Dire Maul (North)", dungeon.NameButton.Name:GetText()) -- names are English
      assert.is_true(S.unrecorded(WFJ, dungeon.NameButton.Name))
      assert.are.equal("Kalimdor", zone.NameButton.Name:GetText())
      assert.are.equal("ダンジョン", group.NameButton.Name:GetText()) -- a table word, whatever the names choice
      names(true)
      fill()
      assert.are.equal(NORTH, dungeon.NameButton.Name:GetText())
      assert.are.equal(#NORTH * 7, dungeon.NameButton.size[1])
      assert.are.equal("カリムドア", zone.NameButton.Name:GetText()) -- a group that is a continent
      assert.are.equal("ダンジョン", group.NameButton.Name:GetText())
      assert.are.equal("Blackmaw Hold", unknown.NameButton.Name:GetText()) -- no line in the name list
      assert.is_true(S.unrecorded(WFJ, unknown.NameButton.Name))
      S.alt(WFJ, true)
      assert.are.equal("Dire Maul (North)", dungeon.NameButton.Name:GetText())
      assert.are.equal(#"Dire Maul (North)" * 7, dungeon.NameButton.size[1])
      S.alt(WFJ, false)
      assert.are.equal(NORTH, dungeon.NameButton.Name:GetText())
      -- the pooled row reused for the table's own activity, then for a dungeon again
      _G.LFGListingActivityView_InitActivityButton(dungeon, { name = "Custom" })
      assert.are.equal("カスタム", dungeon.NameButton.Name:GetText())
      _G.LFGListingActivityView_InitActivityButton(dungeon, { name = "Deadmines" })
      assert.are.equal("デッドマインズ", dungeon.NameButton.Name:GetText())
      names(false)
      fill()
      assert.are.equal("Dire Maul (North)", dungeon.NameButton.Name:GetText())
    end)

    it("the category dropdown shows the chosen category's word; the filter shows the one activity chosen", function()
      local browse = _G.LFGBrowseFrame
      browse.CategoryDropdown:SetSelectionText("Dungeons")
      assert.are.equal("ダンジョン", browse.CategoryDropdown.Text:GetText()) -- names are English: a table word
      browse.CategoryDropdown:SetSelectionText("Deadmines") -- never a name there
      assert.are.equal("Deadmines", browse.CategoryDropdown.Text:GetText())
      browse.ActivityDropdown:OverrideText("Stratholme (Main Gate)")
      assert.are.equal("Stratholme (Main Gate)", browse.ActivityDropdown.Text:GetText())
      names(true)
      browse.CategoryDropdown:SetSelectionText("Deadmines")
      assert.are.equal("Deadmines", browse.CategoryDropdown.Text:GetText())
      browse.ActivityDropdown:OverrideText("Stratholme (Main Gate)")
      assert.are.equal(GATE, browse.ActivityDropdown.Text:GetText())
      browse.ActivityDropdown:OverrideText("Custom")
      assert.are.equal("カスタム", browse.ActivityDropdown.Text:GetText())
      browse.ActivityDropdown:OverrideText("Blackmaw Hold")
      assert.are.equal("Blackmaw Hold", browse.ActivityDropdown.Text:GetText())
      browse.ActivityDropdown:OverrideText("Stratholme (Main Gate)")
      S.alt(WFJ, true)
      assert.are.equal("Stratholme (Main Gate)", browse.ActivityDropdown.Text:GetText())
      assert.are.equal("Category", browse.CategoryDropdown.defaultText)
      S.alt(WFJ, false)
      assert.are.equal(GATE, browse.ActivityDropdown.Text:GetText())
    end)

    it("the category menu and the filter menu: the header's word, each activity under its indent; Alt", function()
      local cats, catMenus = open("MENU_LFG_BROWSE_CATEGORY", function(r)
        r:CreateButton("None"); r:CreateButton("Dungeons"); r:CreateButton("Deadmines")
      end)
      assert.are.equal("なし", cats[1]:GetText())
      assert.are.equal("ダンジョン", cats[2]:GetText())
      assert.are.equal("Deadmines", cats[3]:GetText()) -- no category: never read as a name
      M.close(registry, catMenus)
      local function filter()
        return open("MENU_LFG_BROWSE_ACTIVITY", function(r) -- one group: its activities indented under it
          r:CreateButton("Dungeons"); r:CreateButton("  Deadmines"); r:CreateButton("  Dire Maul (North)")
          r:CreateButton("  Blackmaw Hold"); r:CreateButton("  Custom")
        end)
      end
      local e, menus = filter()
      assert.are.equal("ダンジョン", e[1]:GetText())
      assert.are.equal("  Deadmines", e[2]:GetText()) -- names are English
      M.close(registry, menus)
      names(true)
      e, menus = filter()
      assert.are.equal("ダンジョン", e[1]:GetText())
      assert.are.equal("  デッドマインズ", e[2]:GetText())
      assert.are.equal("  " .. NORTH, e[3]:GetText())
      assert.are.equal("  Blackmaw Hold", e[4]:GetText()) -- no line in the name list
      S.alt(WFJ, true)
      assert.are.equal("Dungeons", e[1]:GetText())
      assert.are.equal("  Deadmines", e[2]:GetText())
      S.alt(WFJ, false)
      assert.are.equal("  デッドマインズ", e[2]:GetText())
      M.close(registry, menus)
      -- several groups: each group's activities in its submenu, not indented
      local root = M.element("root")
      local group = root:CreateButton("Kalimdor")
      group:CreateButton("Deadmines")
      local frames, subMenus = M.open(registry, "MENU_LFG_BROWSE_ACTIVITY", root)
      assert.are.equal("カリムドア", frames[group].fontString:GetText())
      assert.are.equal("デッドマインズ", frames[group.children[1]].fontString:GetText())
      M.close(registry, subMenus)
    end)

    it("a result row: the activity in Japanese, the leader's name never; names off, Alt, no line", function()
      local row = C.entry(nil, { leader = "Deadmines", activity = "Dire Maul (North)" })
      assert.are.equal("Dire Maul (North)", row.ActivityName:GetText()) -- names are English
      assert.is_true(S.unrecorded(WFJ, row.ActivityName))
      names(true)
      C.entry(row, { leader = "Deadmines", activity = "Dire Maul (North)" })
      assert.are.equal(NORTH, row.ActivityName:GetText())
      assert.are.equal("Deadmines", row.Name:GetText()) -- a player called like a dungeon
      assert.is_true(S.unrecorded(WFJ, row.Name))
      S.alt(WFJ, true)
      assert.are.equal("Dire Maul (North)", row.ActivityName:GetText())
      S.alt(WFJ, false)
      assert.are.equal(NORTH, row.ActivityName:GetText())
      C.entry(row, { leader = "Thrall", count = 3 }) -- the pooled row reused: the count keeps its own line
      assert.are.equal("アクティビティ 3件", row.ActivityName:GetText())
      C.entry(row, { leader = "Thrall", activity = "Blackmaw Hold" })
      assert.are.equal("Blackmaw Hold", row.ActivityName:GetText())
      assert.is_true(S.unrecorded(WFJ, row.ActivityName))
      names(false)
      C.entry(row, { leader = "Thrall", activity = "Dire Maul (North)" })
      assert.are.equal("Dire Maul (North)", row.ActivityName:GetText())
    end)

    it("the result tooltip's activity and boss lines; a wider Japanese line widens the tooltip", function()
      local tip = _G.LFGBrowseSearchEntryTooltip
      local width = 100
      tip.GetWidth = function() return width end
      tip.SetWidth = function(_, w) width = w end
      C.tipActivities = { "Dungeons", "  Dire Maul (North)", "  Blackmaw Hold" }
      C.tipBosses = { "Baron Rivendare" }
      local function lines(pool)
        local out = {}
        for fs in pool:EnumerateActive() do out[#out + 1] = fs:GetText() end
        return out
      end
      _G.LFGBrowseSearchEntryTooltip_UpdateAndShow(tip, 2)
      assert.are.same({ "ダンジョン", "  Dire Maul (North)", "  Blackmaw Hold" }, lines(tip.activityPool))
      assert.are.same({ "Baron Rivendare" }, lines(tip.completedEncounterPool))
      names(true)
      _G.LFGBrowseSearchEntryTooltip_UpdateAndShow(tip, 2)
      assert.are.same({ "ダンジョン", "  " .. NORTH, "  Blackmaw Hold" }, lines(tip.activityPool))
      assert.are.same({ "バロン・リーヴェンデア" }, lines(tip.completedEncounterPool))
      assert.are.equal(#("  " .. NORTH) * 7 + 22, width)
      assert.are.equal("Close", tip.Leader.Name:GetText())
      S.alt(WFJ, true)
      assert.are.same({ "Dungeons", "  Dire Maul (North)", "  Blackmaw Hold" }, lines(tip.activityPool))
      S.alt(WFJ, false)
    end)

    it("the locked view's lines: activities, a group and its count; each frame sized to the text shown", function()
      local view = _G.LFGListingFrame.LockedView
      C.listed = true
      C.lockedLines = { "Deadmines", "Dungeons |cffffffff(3 activities)|r", "  Dire Maul (North)",
        "Kalimdor |cffffffff(3 activities)|r" }
      local function frames()
        local out = {}
        for frame in view.framePool:EnumerateActive() do out[#out + 1] = frame end
        return out
      end
      _G.LFGListingLockedView_RefreshContent(view)
      local f = frames()
      assert.are.equal("Deadmines", f[1].Text:GetText()) -- names are English
      assert.are.equal("ダンジョン |cffffffff(アクティビティ 3件)|r", f[2].Text:GetText())
      assert.are.equal("  Dire Maul (North)", f[3].Text:GetText())
      assert.are.equal("Kalimdor |cffffffff(アクティビティ 3件)|r", f[4].Text:GetText()) -- a continent: a name
      names(true)
      _G.LFGListingLockedView_RefreshContent(view)
      f = frames()
      assert.are.equal("カリムドア |cffffffff(アクティビティ 3件)|r", f[4].Text:GetText())
      assert.are.equal("デッドマインズ", f[1].Text:GetText())
      assert.are.equal(#"デッドマインズ" * 7, f[1].size[1])
      assert.are.equal("  " .. NORTH, f[3].Text:GetText())
      S.alt(WFJ, true)
      assert.are.equal("Deadmines", f[1].Text:GetText())
      assert.are.equal(#"Deadmines" * 7, f[1].size[1])
      assert.are.equal("Dungeons |cffffffff(3 activities)|r", f[2].Text:GetText())
      S.alt(WFJ, false)
      assert.are.equal("デッドマインズ", f[1].Text:GetText())
    end)
  end)

  -- The hover of a collapsed locked line: the pooled frame's OnEnter (listing.xml:240–245).
  describe("the hover of a collapsed listed-for line", function()
    local DUNGEONS = "Dungeons |cffffffff(2 activities)|r"

    before_each(function()
      WFJ = S.load(FILES, UI)
      WFJ.State.setNames(false)
      C.listed, C.grouped, C.failed = true, false, false
      C.tipActivities, C.tipBosses = nil, nil
      WFJ.Data.add("name", {
        [WFJ.Names.key("Deadmines")] = "デッドマインズ\tでっどまいんず",
        [WFJ.Names.key("Wailing Caverns")] = "ウェイリング・キャヴァーンズ\tうぇいりんぐ・きゃゔぁーんず",
        [WFJ.Names.key("Kalimdor")] = "カリムドア\tかりむどあ",
        [WFJ.Names.key("Ashenvale")] = "アッシェンヴェイル\tあっしぇんゔぇいる",
      })
      WFJ.UIStrings.name = function(text) return WFJ.State.names and WFJ.Names.value(text) or nil end -- as Main does
      loadGroupFinder()
      assert.is_true(WFJ.GroupFinder.init())
    end)

    after_each(function()
      _G.GameTooltip:Hide()
      WFJ.UIStrings.name = nil
      WFJ.State.setNames(false)
    end)

    -- → the tooltip's one line after the frame's OnEnter
    local function hover(lines, i)
      local view = _G.LFGListingFrame.LockedView
      C.lockedLines = lines
      _G.LFGListingLockedView_RefreshContent(view)
      local n = 0
      for frame in view.framePool:EnumerateActive() do
        n = n + 1
        if n == (i or 1) then
          _G.GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
          _G.GameTooltip:SetText(frame.tooltip)
        end
      end
      return _G.GameTooltipTextLeft1:GetText()
    end

    it("names English: the group's table word in Japanese, the dungeons as the client wrote them", function()
      assert.are.equal("ダンジョン\n  Deadmines\n  Wailing Caverns",
        hover({ { DUNGEONS, "Dungeons\n  Deadmines\n  Wailing Caverns" } }))
    end)

    it("names Japanese: every line, the line breaks and indents kept; the choice and Alt are followed", function()
      WFJ.State.setNames(true)
      local en = "Dungeons\n  Deadmines\n  Wailing Caverns\n  Custom"
      assert.are.equal("ダンジョン\n  デッドマインズ\n  ウェイリング・キャヴァーンズ\n  カスタム", hover({ { DUNGEONS, en } }))
      S.alt(WFJ, true)
      assert.are.equal(en, _G.GameTooltipTextLeft1:GetText())
      S.alt(WFJ, false)
      assert.are.equal("ダンジョン\n  デッドマインズ\n  ウェイリング・キャヴァーンズ\n  カスタム", _G.GameTooltipTextLeft1:GetText())
      WFJ.State.setNames(false)
      assert.are.equal("ダンジョン\n  Deadmines\n  Wailing Caverns\n  カスタム", _G.GameTooltipTextLeft1:GetText())
    end)

    it("a dungeon with no line: every name of the hover stays English, the table word still Japanese", function()
      WFJ.State.setNames(true)
      assert.are.equal("ダンジョン\n  Deadmines\n  Gnomeregan",
        hover({ { DUNGEONS, "Dungeons\n  Deadmines\n  Gnomeregan" } }))
    end)

    it("a continent and its zones: Japanese together while names are, English together otherwise", function()
      local line, en = "Kalimdor |cffffffff(1 activities)|r", "Kalimdor\n  Ashenvale"
      assert.are.equal(en, hover({ { line, en } }))
      WFJ.State.setNames(true)
      assert.are.equal("カリムドア\n  アッシェンヴェイル", hover({ { line, en } }))
      S.alt(WFJ, true)
      assert.are.equal(en, _G.GameTooltipTextLeft1:GetText())
      S.alt(WFJ, false)
      WFJ.State.setNames(false)
      assert.are.equal(en, _G.GameTooltipTextLeft1:GetText())
      WFJ.State.setNames(true)
      assert.are.equal("Kalimdor\n  Felwood", hover({ { line, "Kalimdor\n  Felwood" } }))
    end)

    it("translation off writes nothing; another owner's tooltip is not read as a listing", function()
      local en = "Dungeons\n  Deadmines"
      WFJ.State.setEnabled(false)
      assert.are.equal(en, hover({ { DUNGEONS, en } }))
      assert.are.equal(0, _G.GameTooltipTextLeft1.calls.addonSetText)
      WFJ.State.setEnabled(true)
      hover({ { DUNGEONS, en } })
      _G.GameTooltip:SetOwner(CreateFrame("Frame"))
      _G.GameTooltip:SetText(en)
      assert.are.equal(en, _G.GameTooltipTextLeft1:GetText())
    end)
  end)

  it("hooks install once", function()
    setup(true)
    assert.is_false(WFJ.GroupFinder.setup())
    assert.are.equal(1, #Stub.hooks["LFGParentFrame:UpdateTabs"])
    assert.are.equal(1, #Stub.hooks["LFGBrowseSearchEntry_Update"])
    assert.are.equal(1, #Stub.hooks["CategoryDropdown:UpdateText"])
    assert.are.equal(1, #Stub.hooks["LFGListingActivityView_InitActivityGroupButton"])
    assert.are.equal(1, #Stub.hooks["LFGListingCategorySelection_AddButton"])
  end)

  it("a client name bound to the wrong type degrades to English with no error", function()
    WFJ = S.load(FILES, UI)
    loadGroupFinder()
    _G.LFGBrowseSearchEntry_Update = "not a function"
    _G.LFGBrowseFrame.CategoryDropdown = 7
    _G.LFGBrowseFrame.UpdateResults = true
    _G.LFGListingFrame.PostButton = "?"
    assert.has_no.errors(function() WFJ.GroupFinder.init() end)
    assert.are.equal("グループ検索", _G.LFGListingFrame.TitleContainer.TitleText:GetText())
    assert.is_nil(Stub.hooks["LFGBrowseSearchEntry_Update"])
  end)

  it("without the camelot frames nothing is set up", function()
    WFJ = S.load(FILES, UI)
    assert.is_false(WFJ.GroupFinder.init()) -- the addon is not loaded
    assert.is_false(WFJ.GroupFinder.setup()) -- no LFGParentFrame
    loadGroupFinder({ noWhoList = true }) -- a client whose finder has no who list (not camelot)
    assert.is_false(WFJ.GroupFinder.setup())
    assert.are.equal("Looking For Group", _G.LFGListingFrame.TitleContainer.TitleText:GetText())
    assert.is_nil(Stub.hooks["LFGParentFrame:UpdateTabs"])
  end)
end)
