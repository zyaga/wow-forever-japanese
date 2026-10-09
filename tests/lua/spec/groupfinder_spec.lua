-- UI/GroupFinder.lua over LFGParentFrame replayed from camelot
-- blizzard_groupfinder_vanillastyle (blizzard_lfgvanilla_parentframe.lua:87–92, blizzard_lfgvanilla_listing.lua:
-- 610–649 + 1089–1097 + 822–838, blizzard_lfgvanilla_browse.lua:73–79 + 189 + 305 + 410–419 + 648–653, the Menu
-- dropdown's UpdateText). Leader names, activity and category names stay English; both load orders.
local S = require("tests.lua.spec.stub_camelot_social")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = S.files("UI/GroupFinder.lua")
local ADDON = "Blizzard_GroupFinder_VanillaStyle"

local UI = {
  LFG_TITLE = { "Looking For Group", "グループ検索" },
  LFG_LIST_TAB_1 = { "Create Listing", "募集を作成" }, LFG_LIST_EDIT = { "Edit Listing", "募集を編集" },
  LFG_LIST_TAB_2 = { "Group Browser", "グループ一覧" }, LFG_LIST_TAB_3 = { "Who List", "Whoリスト" },
  LFG_LIST_UNLIST = { "Delist", "募集を取り下げ" },
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
  ["LfgActivity:285"] = { "Custom", "カスタム" },
  -- the listing's voice chat row and a result tooltip's voice line (listing.xml:554, 631; listing.lua:48–69;
  -- browse.lua:674–682)
  VOICE_CHAT = { "Voice Chat", "ボイスチャット" },
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
  if not o.noWhoList then S.frame("LFGWhoListFrame") end

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
  listing.ActivityView = S.frame(nil, "ActivityView")
  listing.ActivityView.PlayStyleDropdown = S.dropdown("PlayStyleDropdown")
  listing.ActivityView.VoiceChatLabel = S.fs(en("VOICE_CHAT"))
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
    if d.playstyle then row.PlaystyleLabel.text = en(d.playstyle) end -- blizzard_lfgvanilla_browse.lua:465–466
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
  end
  Stub.loadedAddons[ADDON] = true
end

local GLOBALS = { "LFGParentFrame", "LFGWhoListFrame", "LFGListingFrame", "LFGListingComment", "LFGBrowseFrame",
  "LFGBrowseSearchEntryTooltip", "LFGListingPostButton_UpdateText", "LFGListingBackButton_UpdateText",
  "LFGListingLockedView_RefreshContent", "LFGBrowseSearchEntry_Update", "LFGBrowseSearchEntryTooltip_UpdateAndShow",
  "LFGListingActivityView_InitActivityButton", "LFGListingActivityView_InitActivityGroupButton",
  "LFGListingCategorySelection_AddButton" }

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
        assert.are.equal("募集を作成", _G.LFGParentFrame.Tab1:GetText())
        assert.are.equal("自分を登録", listing.PostButton:GetText())
        assert.are.equal("ロールチェック", listing.GroupRoleButtons.RolePollButton:GetText())
        assert.are.equal("現在の募集内容:", listing.LockedView.ActivityText:GetText())
        assert.are.equal("検索中...", browse.SearchingSpinner.Label:GetText())
        assert.are.equal("メッセージを送る", browse.SendMessageButton:GetText())
        assert.are.equal("この募集は取り下げられました。", _G.LFGBrowseSearchEntryTooltip.Delisted:GetText())
        assert.are.equal("Back", listing.BackButton:GetText()) -- "Back" belongs to INVTYPE_CLOAK: left English
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
