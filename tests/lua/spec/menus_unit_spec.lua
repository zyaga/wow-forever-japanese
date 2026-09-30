local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local M = require("tests.lua.spec.menu_stub")

-- the unit right-click menus outside level 1 (UI/MenusUnit WHICH): each `which` renders its listed
-- entries in Japanese; its title (a player's, a Battle.net friend's or a club's name; unitpopupshared.lua:110–116;
-- communitieslist.lua:790–805) is never touched; the raid menu's entries beside protected actions are only
-- text-written (the frame's scripts are never replaced).
local FILES = {}
for _, f in ipairs(H.UI_FILES) do FILES[#FILES + 1] = f end
for _, f in ipairs({ "UI/SettingsKeys.lua", "UI/MenusUnit.lua", "UI/Menus.lua", "UI/MenusTags.lua",
  "UI/MenusUntagged.lua" }) do FILES[#FILES + 1] = f end

local UI = {
  VIEW_FRIENDS_OF_FRIENDS = { "View Friends", "フレンドを表示" },
  SOCIAL_UI_BATTLE_NET_FRIEND_TAGS_LABEL = { "Add Tags [%d]", "タグを追加 [%d]" },
  SET_RAID_LEADER = { "Promote to Raid Leader", "レイドリーダーに昇格" },
  SET_MAIN_TANK = { "Promote to Main Tank", "メインタンクに昇格" },
  SET_FOCUS = { "Set Focus", "フォーカスに設定" },
  DEMOTE = { "Demote", "降格" },
  COMMUNITY_MEMBER_LIST_DROP_DOWN_ROLES = { "Roles", "役割" },
  GUILD_PROMOTE = { "Promote to Guildmaster", "ギルドマスターに昇格" },
  COMMUNITY_MEMBER_LIST_DROP_DOWN_BATTLETAG_FRIEND = { "Add BattleTag Friend", "バトルタグフレンドを追加" },
  COMMUNITIES_LIST_DROP_DOWN_FAVORITE = { "Set Favorite", "お気に入りに設定" },
  COMMUNITIES_LIST_DROP_DOWN_INVITE = { "Invite Member", "メンバーを招待" },
  MAKE_MODERATOR = { "Make Moderator", "モデレーターにする" },
  RECENT_ALLIES_MENU_BUTTON_LABEL_PIN = { "Pin", "ピン留め" },
  DISCORD_CHAT_MESSAGE_CLICK_DELETE = { "Delete", "削除" },
  VOTE_TO_ABANDON = { "Vote to Abandon", "放棄を投票" },
  PET_ABANDON = { "Release", "解放" }, RELEASE_PET_BUTTON_LABEL = { "Release", "解放" },
  WHISPER = { "Whisper", "ささやく" },
  AGE_RESTRICTED_CHAT_MINOR_TOOLTIP = { "Chat and other social features are unavailable on accounts belonging to "
    .. "minors.", "未成年者のアカウントでは、チャットやその他のソーシャル機能を利用できません。" },
  TRADE = { "Trade", "取引" }, -- a level-1 entry the club menus never show
}

-- which → { an entry key it lists }
local CASES = {
  { "BN_FRIEND", "VIEW_FRIENDS_OF_FRIENDS" }, { "BN_FRIEND_OFFLINE", "VIEW_FRIENDS_OF_FRIENDS" },
  { "RAID_PLAYER", "SET_RAID_LEADER" }, { "RAID", "SET_MAIN_TANK" },
  { "COMMUNITIES_WOW_MEMBER", "COMMUNITY_MEMBER_LIST_DROP_DOWN_ROLES" },
  { "COMMUNITIES_GUILD_MEMBER", "GUILD_PROMOTE" },
  { "COMMUNITIES_MEMBER", "COMMUNITY_MEMBER_LIST_DROP_DOWN_BATTLETAG_FRIEND" },
  { "COMMUNITIES_COMMUNITY", "COMMUNITIES_LIST_DROP_DOWN_FAVORITE" },
  { "GUILDS_GUILD", "COMMUNITIES_LIST_DROP_DOWN_INVITE" },
  { "CHAT_ROSTER", "MAKE_MODERATOR" }, { "RECENT_ALLY", "RECENT_ALLIES_MENU_BUTTON_LABEL_PIN" },
  { "RECENT_ALLY_OFFLINE", "RECENT_ALLIES_MENU_BUTTON_LABEL_PIN" },
  { "DISCORD_USER_SELF", "DISCORD_CHAT_MESSAGE_CLICK_DELETE" },
}

describe("UI/MenusUnit: the unit menus outside level 1", function()
  local WFJ, callbacks

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    callbacks = {}
    _G.Menu = { ModifyMenu = function(tag, fn) callbacks[tag] = fn end }
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    WFJ.Menus.init()
  end)

  after_each(function() H.uiTeardown(); _G.Menu = nil end)

  -- UnitPopupManager: SetTag("MENU_UNIT_"..which, contextData), then the title, then the entries
  local function generate(which, title, entries, contextData)
    local root = M.element(nil)
    root:CreateButton(title)
    for _, text in ipairs(entries) do root:CreateButton(text) end
    callbacks["MENU_UNIT_" .. which](nil, root, contextData)
    return root, M.open(root)
  end

  it("registers the 13 new whichs, each with its own key list and titleIsName", function()
    assert.are.equal(13, (function() local n = 0; for _ in pairs(WFJ.MenusUnit.WHICH) do n = n + 1 end; return n end)())
    for which, keys in pairs(WFJ.MenusUnit.WHICH) do
      local spec = WFJ.Menus.TAGS["MENU_UNIT_" .. which]
      assert.are.equal(keys, spec.keys, which)
      assert.is_true(spec.titleIsName, which)
      assert.is_function(callbacks["MENU_UNIT_" .. which], which)
    end
  end)

  it("each new which renders its listed entry in Japanese; the title (a name) stays as written", function()
    for _, c in ipairs(CASES) do
      local which, key = c[1], c[2]
      -- the title is a name that is also the entry's English (a player called "Pin", a club called "Set Favorite")
      local root, frames = generate(which, UI[key][1], { UI[key][1] }, { name = UI[key][1] .. "!" })
      assert.are.equal(UI[key][1], frames[root.children[1]].fontString:GetText(), which)
      assert.are.equal(UI[key][2], frames[root.children[2]].fontString:GetText(), which)
    end
  end)

  it("a club menu: an entry equal to the club's name (contextData.name) is never matched", function()
    local root, frames = generate("COMMUNITIES_COMMUNITY", "Invite Member",
      { UI.COMMUNITIES_LIST_DROP_DOWN_FAVORITE[1], "Invite Member" }, { name = "Invite Member" })
    assert.are.equal("Invite Member", frames[root.children[1]].fontString:GetText())
    assert.are.equal("お気に入りに設定", frames[root.children[2]].fontString:GetText())
    assert.are.equal("Invite Member", frames[root.children[3]].fontString:GetText())
  end)

  it("a which shows only its own keys: a level-1 word outside a club menu's list stays English", function()
    local root, frames = generate("GUILDS_GUILD", "My Guild", { UI.TRADE[1], UI.WHISPER[1] }, { name = "My Guild" })
    assert.are.equal("Trade", frames[root.children[2]].fontString:GetText())
    assert.are.equal("Whisper", frames[root.children[3]].fontString:GetText())
  end)

  it("the raid menu beside protected actions: text-only writes, the entry's scripts untouched", function()
    local root = M.element(nil)
    root:CreateButton("Jaina")
    root:CreateButton(UI.SET_FOCUS[1])
    root:CreateButton(UI.SET_MAIN_TANK[1])
    root:CreateButton(UI.DEMOTE[1])
    callbacks.MENU_UNIT_RAID(nil, root, { name = "Jaina" })
    local frames = M.open(root)
    for i, want in ipairs({ "Jaina", "フォーカスに設定", "メインタンクに昇格", "降格" }) do
      local frame = frames[root.children[i]]
      assert.are.equal(want, frame.fontString:GetText())
      assert.are.same({}, frame.scripts) -- no SetScript: the secure click path stays the client's
    end
  end)

  it("the level-1 menus gain the abandon vote and the pet's release (same English as the shipped key)", function()
    local root, frames = generate("SELF", "Me", { UI.VOTE_TO_ABANDON[1] }, { name = "Me" })
    assert.are.equal("放棄を投票", frames[root.children[2]].fontString:GetText())
    local pet, petFrames = generate("PET", "Wolf", { UI.PET_ABANDON[1] }, { name = "Wolf" })
    assert.are.equal("解放", petFrames[pet.children[2]].fontString:GetText())
  end)

  it("the whisper entry's age-restriction hover translates (level-1 and a friend menu); Alt shows English",
    function()
      local warning = "Chat and other social features are unavailable on accounts belonging to minors."
      for _, which in ipairs({ "PLAYER", "BN_FRIEND" }) do
        local root, frames = generate(which, "Jaina", { UI.WHISPER[1] }, { name = "Jaina" })
        local element = frames[root.children[2]]
        assert.are.equal("ささやく", M.hover(element, UI.WHISPER[1], warning), which)
        assert.are.equal("未成年者のアカウントでは、チャットやその他のソーシャル機能を利用できません。",
          _G.GameTooltipTextLeft2:GetText(), which)
        Stub.keys.alt = true; WFJ.Modifier.refresh()
        assert.are.equal(warning, _G.GameTooltipTextLeft2:GetText(), which)
        Stub.keys.alt = false; WFJ.Modifier.refresh()
        _G.GameTooltip:Hide()
      end
    end)

  it("a friend's tag count keeps its number", function()
    local root, frames = generate("BN_FRIEND", "Friend#1234", { "Add Tags [3]" }, { name = "Friend#1234" })
    assert.are.equal("タグを追加 [3]", frames[root.children[2]].fontString:GetText())
  end)
end)
