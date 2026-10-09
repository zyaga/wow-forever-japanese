local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local M = require("tests.lua.spec.menu_stub")

-- The menu tags of every other Forever window (UI/MenusTags), the keys added to three shipped tags,
-- the element utility-button hovers, and the damage meter's session entries ("Combat 3 [01:23]").
local FILES = {}
for _, f in ipairs(H.UI_FILES) do FILES[#FILES + 1] = f end
for _, f in ipairs({ "UI/SettingsKeys.lua", "UI/MenusUnit.lua", "UI/Menus.lua", "UI/MenusTags.lua",
  "UI/MenusUntagged.lua", "UI/DamageMeter.lua" }) do FILES[#FILES + 1] = f end

local FAV, USABLE = "お気に入りに設定", "使用可能のみ"
local UI = {
  COOLDOWN_VIEWER_SETTINGS_SHOW_UNLEARNED = { "Show Unlearned", "未習得を表示" },
  COOLDOWN_VIEWER_SETTINGS_CLEAR_ALL_ALERTS = { "Clear all Alerts", "すべてのアラートを消去" },
  COOLDOWN_VIEWER_SETTINGS_RENAME_LAYOUT = { "Change Name", "名前を変更" },
  GROUP_BUFF_FILTER_MOVE_TO_HIDDEN = { "Move to Not Displayed", "非表示に移動" },
  ACHIEVEMENTFRAME_FILTER_COMPLETED = { "Earned", "獲得済み" },
  ACHIEVEMENT_FILTER_TITLE = { "Achievement Filter", "アチーブメントフィルター" },
  ACHIEVEMENT_FILTER_COMPLETE_EXPLANATION = { "Show achievements completed on your Account",
    "アカウントで達成したアチーブメントを表示" },
  OBJECTIVES_VIEW_ACHIEVEMENT = { "Open Achievement", "アチーブメントを開く" },
  CONTENT_TRACKING_OPEN_JOURNAL_OPTION = { "Open Collections", "コレクションを開く" },
  AUCTION_HOUSE_DROPDOWN_SET_FAVORITE = { "Set Favorite", FAV },
  AUCTION_HOUSE_FILTER_USABLE_ONLY = { "Usable Only", USABLE },
  LOCK_BATTLEFIELDMINIMAP = { "Lock Zone Map", "ゾーンマップを固定" },
  CALENDAR_COPY_EVENT = { "Copy", "コピー" },
  CALENDAR_INVITELIST_SETMODERATOR = { "Grant Moderator Status", "モデレーター権限を付与" },
  BLIZZARD_COMBAT_LOG_MENU_EVERYTHING = { "Show everything", "すべて表示" },
  DAMAGE_METER_COMBAT_NUMBER = { "Combat %d", "戦闘%d" },
  DAMAGE_METER_CURRENT_SESSION = { "Current Segment", "現在の区間" },
  DAMAGE_METER_LOCK_WINDOW = { "Lock Window", "ウィンドウを固定" },
  DAMAGE_METER_CATEGORY_HEALING = { "Healing", "回復" },
  EVENTTRACE_SHOW_TIMESTAMP = { "Show Event Timestamp", "イベントのタイムスタンプを表示" },
  REQUEST_ROLL = { "Request Roll", "ロールを要求" },
  PVP_REPORT_AFK_ALL = { "Report all of the above", "上記全員を報告" },
  GUILDCONTROL_RANK_PERMISSIONS = { "Rank Permissions", "ランクの権限" },
  NOT_COLLECTED = { "Not Collected", "未収集" },
  MOUNT_JOURNAL_FILTER_FLYING = { "Flying", "飛行" },
  BATTLE_PET_FAVORITE = { "Set Favorite", FAV },
  BATTLE_PET_UNFAVORITE = { "Remove Favorite", "お気に入りから外す" },
  PET_JOURNAL_FILTER_USABLE_ONLY = { "Usable Only", USABLE },
  TRADESKILL_FILTER_HAS_SKILL_UP = { "Has skill up", "スキルアップあり" },
  TRADESKILL_POST = { "Post in chat", "チャットに投稿" },
  PROFESSIONS_TRACKING_VIEW_RECIPE = { "View Recipe", "レシピを見る" },
  PROFESSIONS_LISTING_DURATION_TWO = { "24 Hours", "24時間" },
  WHISPER_MESSAGE = { "Whisper", "ささやき" },
  PROF_ORDER_CANT_WHISPER_OFFLINE = { "This player is offline.", "このプレイヤーはオフラインです。" },
  PLAYER_DIFFICULTY2 = { "Heroic", "ヒロイック" },
  TRANSMOG_EDIT_OUTFIT_SLOT = { "Change Name/Icon", "名前／アイコンを変更" },
  TRANSMOG_ARTIFACT_OPTIONS_HEADER = { "Legion Artifact Override", "Legionアーティファクトの上書き" },
  TRANSMOG_SET_OPEN_COLLECTION = { "Open Appearances", "外見を開く" },
  TRANSMOG_CUSTOM_SET_RENAME = { "Rename", "名前を変更する" },
  TRANSMOG_SET_PVP = { "PvP", "PvP" },
  TRANSMOG_ITEM_SET_FAVORITE = { "Set Favorite", FAV },
  SOCIAL_SHARE_TEXT = { "Share", "共有" },
  VOICE_CHAT_MODE_LEGACY = { "In-Game Voice (Legacy)", "ゲーム内ボイス(レガシー)" },
  -- the keys added to shipped tags
  LEAVE_ARENA = { "Leave Arena", "アリーナから退出" },
  SHOW_WORLD_QUESTS_ON_MAP_TEXT = { "World Quests", "ワールドクエスト" },
  WORLD_QUESTS_FILTER_DESCRIPTION = { "Open world activities that give varying rewards",
    "さまざまな報酬が得られるオープンワールドの活動" },
  -- the utility buttons' hovers
  HUD_EDIT_MODE_DELETE_LAYOUT = { "Delete Layout", "レイアウトを削除" },
  COOLDOWN_VIEWER_SETTINGS_DELETE_LAYOUT = { "Delete Layout", "レイアウトを削除" },
  HUD_EDIT_MODE_RENAME_OR_COPY_LAYOUT = { "Rename/Copy Layout", "レイアウトの名前変更／コピー" },
  COOLDOWN_VIEWER_SETTINGS_ALERT_MENU_PLAY_SAMPLE = { "Play Sample", "サンプルを再生" },
  -- a dictionary word no MenusTags tag lists
  RAID = { "Raid", "レイド" },
}

-- one entry per MenusTags tag: { tag, key }
local CASES = {
  { "COOLDOWN_VIEWER_SETTINGS_MENU", "COOLDOWN_VIEWER_SETTINGS_SHOW_UNLEARNED" },
  { "MENU_COOLDOWN_SETTINGS_ITEM", "COOLDOWN_VIEWER_SETTINGS_CLEAR_ALL_ALERTS" },
  { "MENU_COOLDOWN_SETTINGS_LAYOUTS", "COOLDOWN_VIEWER_SETTINGS_RENAME_LAYOUT" },
  { "MENU_GROUP_BUFF_FILTER_ITEM", "GROUP_BUFF_FILTER_MOVE_TO_HIDDEN" },
  { "MENU_ACHIEVEMENT_FILTER", "ACHIEVEMENTFRAME_FILTER_COMPLETED" },
  { "MENU_ACHIEVEMENT_TRACKER", "OBJECTIVES_VIEW_ACHIEVEMENT" },
  { "MENU_OBJECTIVE_TRACKER", "CONTENT_TRACKING_OPEN_JOURNAL_OPTION" },
  { "MENU_AUCTION_HOUSE_FAVORITE", "AUCTION_HOUSE_DROPDOWN_SET_FAVORITE" },
  { "MENU_AUCTION_HOUSE_SEARCH_FILTER", "AUCTION_HOUSE_FILTER_USABLE_ONLY" },
  { "MENU_BATTLEFIELD_MAP", "LOCK_BATTLEFIELDMINIMAP" },
  { "MENU_CALENDAR_DAY", "CALENDAR_COPY_EVENT" },
  { "MENU_CALENDAR_CREATE_INVITE", "CALENDAR_INVITELIST_SETMODERATOR" },
  { "MENU_COMBAT_LOG", "BLIZZARD_COMBAT_LOG_MENU_EVERYTHING" },
  { "MENU_DAMAGE_METER_SESSIONS", "DAMAGE_METER_CURRENT_SESSION" },
  { "MENU_DAMAGE_METER_WINDOW_SETTINGS", "DAMAGE_METER_LOCK_WINDOW" },
  { "MENU_DAMAGE_METER_WINDOW_TRACKED_TYPE", "DAMAGE_METER_CATEGORY_HEALING" },
  { "MENU_EVENT_TRACE_FILTER", "EVENTTRACE_SHOW_TIMESTAMP" },
  { "MENU_GROUP_LOOT", "REQUEST_ROLL" },
  { "MENU_GROUP_MEMBERS_PIN", "PVP_REPORT_AFK_ALL" },
  { "MENU_GUILD_PERMISSIONS", "GUILDCONTROL_RANK_PERMISSIONS" },
  { "MENU_HEIRLOOMS_FILTER", "NOT_COLLECTED" },
  { "MENU_MOUNT_COLLECTION_FILTER", "MOUNT_JOURNAL_FILTER_FLYING" },
  { "MENU_MOUNT_COLLECTION_MOUNT", "BATTLE_PET_FAVORITE" },
  { "MENU_PET_COLLECTION_FILTER", "NOT_COLLECTED" },
  { "MENU_PET_COLLECTION_PET", "BATTLE_PET_FAVORITE" },
  { "MENU_TOYBOX_FILTER", "PET_JOURNAL_FILTER_USABLE_ONLY" },
  { "MENU_TOYBOX_FAVORITE", "BATTLE_PET_UNFAVORITE" },
  { "MENU_WARBANDSCENE_FAVORITE", "BATTLE_PET_FAVORITE" },
  { "MENU_PROFESSIONS_FILTER", "TRADESKILL_FILTER_HAS_SKILL_UP" },
  { "MENU_PROFESSIONS_RECIPE_LIST_FAVORITE", "BATTLE_PET_FAVORITE" },
  { "MENU_PROFESSIONS_CRAFTING_PAGE", "TRADESKILL_POST" },
  { "MENU_PROFESSIONS_CRAFTER_ORDER", "BATTLE_PET_UNFAVORITE" },
  { "MENU_PROFESSIONS_RECIPE_TRACKER", "PROFESSIONS_TRACKING_VIEW_RECIPE" },
  { "MENU_PROFESSIONS_CUSTOMER_ORDER_BROWSE", "AUCTION_HOUSE_FILTER_USABLE_ONLY" },
  { "MENU_PROFESSIONS_CUSTOMER_ORDER_DURATION", "PROFESSIONS_LISTING_DURATION_TWO" },
  { "MENU_PROFESSIONS_CUSTOMER_ORDER_FORM", "WHISPER_MESSAGE" },
  { "MENU_RAID_FRAME_DIFFICULTY", "PLAYER_DIFFICULTY2" },
  { "MENU_TRANSMOG_OUTFIT_ENTRY", "TRANSMOG_EDIT_OUTFIT_SLOT" },
  { "MENU_TRANSMOG_OPTIONS", "TRANSMOG_ARTIFACT_OPTIONS_HEADER" },
  { "MENU_TRANSMOG_SETS_MODEL_FILTER", "TRANSMOG_SET_OPEN_COLLECTION" },
  { "MENU_TRANSMOG_CUSTOM_SETS_MODEL_FILTER", "TRANSMOG_CUSTOM_SET_RENAME" },
  { "MENU_TRANSMOG_SETS_FILTER", "TRANSMOG_SET_PVP" },
  { "MENU_WARDROBE_BASE_SETS_FILTER", "TRANSMOG_SET_PVP" },
  { "MENU_WARDROBE_SETS_SET", "TRANSMOG_ITEM_SET_FAVORITE" },
  { "MENU_WARDROBE_SETS_SET_DETAIL", "TRANSMOG_ITEM_SET_FAVORITE" },
  { "MENU_WARDROBE_ITEMS_MODEL_FILTER", "TRANSMOG_ITEM_SET_FAVORITE" },
  { "MORE_CONTEXT_ACTIONS", "SOCIAL_SHARE_TEXT" },
  { "MENU_LFG_LISTING_VOICE_CHAT", "VOICE_CHAT_MODE_LEGACY" },
  -- the keys added to shipped tags
  { "MENU_QUEUE_STATUS_FRAME", "LEAVE_ARENA" },
  { "MENU_WORLD_MAP_TRACKING", "SHOW_WORLD_QUESTS_ON_MAP_TEXT" },
}

describe("UI/MenusTags: every other Forever window's menus", function()
  local WFJ, callbacks

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    callbacks = {}
    _G.Menu = { ModifyMenu = function(tag, fn) callbacks[tag] = fn end }
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    assert.is_true(WFJ.Menus.init())
  end)

  after_each(function() H.uiTeardown(); _G.Menu = nil end)

  local function generate(tag, build, contextData)
    local root = M.element(nil)
    build(root)
    callbacks[tag](nil, root, contextData) -- Menu.PopulateDescription → SecureModifyMenu
    return root, M.open(root)
  end

  it("each new tag names its source file:line and is registered with Menu.ModifyMenu", function()
    local n = 0
    for tag, spec in pairs(WFJ.Menus.TAGS) do
      assert.is_string(spec.source, tag)
      assert.truthy(spec.source:match("%.lua:%d+"), tag)
      assert.is_function(callbacks[tag], tag)
      n = n + 1
    end
    assert.is_true(n >= 49 + 34) -- the Menus / MenusUnit tags (34 incl. the 8 level-1 unit menus) and MenusTags'
  end)

  it("one entry per new tag renders Japanese; a name and an unlisted word beside it stay byte-identical", function()
    for _, c in ipairs(CASES) do
      local tag, key = c[1], c[2]
      local root, frames = generate(tag, function(r)
        r:CreateButton("Thrall") -- a name (a player, a layout, an item)
        r:CreateButton(UI[key][1])
        r:CreateButton(UI.RAID[1])
      end)
      local e = root.children
      assert.are.equal("Thrall", frames[e[1]].fontString:GetText(), tag)
      assert.are.equal(UI[key][2], frames[e[2]].fontString:GetText(), tag)
      assert.are.equal("Raid", frames[e[3]].fontString:GetText(), tag)
      M.release(frames)
    end
    assert.are.equal(0, WFJ.SurfaceState.count(WFJ.Menus.SURFACE))
  end)

  it("a submenu entry renders Japanese; Alt shows the English", function()
    local layout
    local root, frames = generate("MENU_COOLDOWN_SETTINGS_LAYOUTS", function(r)
      layout = r:CreateButton("My Layout") -- a layout the player named
      layout:CreateButton(UI.COOLDOWN_VIEWER_SETTINGS_RENAME_LAYOUT[1])
    end)
    assert.are.equal("My Layout", frames[root.children[1]].fontString:GetText())
    local sub = frames[layout.children[1]]
    assert.are.equal("名前を変更", sub.fontString:GetText())
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal("Change Name", sub.fontString:GetText())
    Stub.keys.alt = false; WFJ.Modifier.refresh()
  end)

  it("a tracker block menu keeps its title (the achievement's name) even when it is a dictionary word", function()
    local root, frames = generate("MENU_ACHIEVEMENT_TRACKER", function(r)
      r:CreateButton(UI.OBJECTIVES_VIEW_ACHIEVEMENT[1]) -- an achievement named like the entry
      r:CreateButton(UI.OBJECTIVES_VIEW_ACHIEVEMENT[1])
    end)
    assert.are.equal("Open Achievement", frames[root.children[1]].fontString:GetText())
    assert.are.equal("アチーブメントを開く", frames[root.children[2]].fontString:GetText())
  end)

  it("element tooltips: the achievement filter's hover and a disabled crafting-order entry's reason", function()
    local root, frames = generate("MENU_ACHIEVEMENT_FILTER", function(r)
      r:CreateButton(UI.ACHIEVEMENTFRAME_FILTER_COMPLETED[1])
    end)
    local radio = frames[root.children[1]]
    assert.is_true(WFJ.HelpTooltip.registered(radio))
    assert.are.equal("アチーブメントフィルター",
      M.hover(radio, UI.ACHIEVEMENT_FILTER_TITLE[1], UI.ACHIEVEMENT_FILTER_COMPLETE_EXPLANATION[1]))
    assert.are.equal("アカウントで達成したアチーブメントを表示", _G.GameTooltipTextLeft2:GetText())
    local form, formFrames = generate("MENU_PROFESSIONS_CUSTOMER_ORDER_FORM", function(r)
      r:CreateButton(UI.WHISPER_MESSAGE[1])
    end)
    local whisper = formFrames[form.children[1]]
    M.hover(whisper, UI.PROF_ORDER_CANT_WHISPER_OFFLINE[1])
    assert.are.equal("このプレイヤーはオフラインです。", _G.GameTooltipTextLeft1:GetText())
    -- the world map's world-quest filter: its hover is its text + a description, as on the other menus
    local map, mapFrames = generate("MENU_WORLD_MAP_TRACKING", function(r)
      r:CreateButton(UI.SHOW_WORLD_QUESTS_ON_MAP_TEXT[1])
    end)
    M.hover(mapFrames[map.children[1]], UI.SHOW_WORLD_QUESTS_ON_MAP_TEXT[1], UI.WORLD_QUESTS_FILTER_DESCRIPTION[1])
    assert.are.equal("ワールドクエスト", _G.GameTooltipTextLeft1:GetText())
    assert.are.equal("さまざまな報酬が得られるオープンワールドの活動", _G.GameTooltipTextLeft2:GetText())
  end)

  -- MenuTemplates.SetUtilityButtonTooltipText hooks the button's OnEnter to GameTooltip_SetTitle with the button
  -- as owner (menutemplates.lua:645–649; menuutil.lua:114–130)
  it("an element's utility buttons show the tag's tooltip keys (Edit Mode's shipped keys, a cooldown layout)",
    function()
      local gear, cancel
      local attach = function(frame)
        gear, cancel = frame:AttachButton(), frame:AttachButton()
      end
      local root, frames = generate("MENU_EDIT_MODE_MANAGER", function(r) r:CreateButton("Modern", attach) end)
      assert.are.equal("Modern", frames[root.children[1]].fontString:GetText())
      assert.are.equal("レイアウトを削除", M.hover(cancel, UI.HUD_EDIT_MODE_DELETE_LAYOUT[1]))
      assert.are.equal("レイアウトの名前変更／コピー", M.hover(gear, UI.HUD_EDIT_MODE_RENAME_OR_COPY_LAYOUT[1]))
      generate("MENU_COOLDOWN_SETTINGS_LAYOUTS", function(r) r:CreateButton("My Layout", attach) end)
      assert.are.equal("レイアウトを削除", M.hover(cancel, UI.COOLDOWN_VIEWER_SETTINGS_DELETE_LAYOUT[1]))
      -- an alert entry's play-sample button (cooldownviewersettingsalerts.lua:193–205)
      generate("MENU_COOLDOWN_SETTINGS_ITEM", function(r) r:CreateButton("Bloodlust", attach) end)
      assert.are.equal("サンプルを再生", M.hover(gear, UI.COOLDOWN_VIEWER_SETTINGS_ALERT_MENU_PLAY_SAMPLE[1]))
      -- a word outside the tag's tooltip keys stays English on the same owner
      assert.are.equal("Raid", M.hover(gear, UI.RAID[1]))
    end)

  it("the damage meter's combat sessions: the name in Japanese, the duration kept; an encounter's name stays",
    function()
      local root, frames = generate("MENU_DAMAGE_METER_SESSIONS", function(r)
        r:CreateButton("Combat 3 [01:23]")
        r:CreateButton("Onyxia [04:12]")
        r:CreateButton("Combat 12")
        r:CreateButton(UI.DAMAGE_METER_CURRENT_SESSION[1])
      end)
      local e = root.children
      assert.are.equal("戦闘3 [01:23]", frames[e[1]].fontString:GetText())
      assert.are.equal("Onyxia [04:12]", frames[e[2]].fontString:GetText())
      assert.are.equal("戦闘12", frames[e[3]].fontString:GetText())
      assert.are.equal("現在の区間", frames[e[4]].fontString:GetText())
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      assert.are.equal("Combat 3 [01:23]", frames[e[1]].fontString:GetText())
      Stub.keys.alt = false; WFJ.Modifier.refresh()
      assert.are.equal("戦闘3 [01:23]", frames[e[1]].fontString:GetText())
      M.release(frames)
      assert.are.equal(0, WFJ.SurfaceState.count(WFJ.Menus.SURFACE))
    end)

  it("the added keys join the shipped tags without dropping theirs", function()
    local function has(list, key)
      for _, k in ipairs(list) do if k == key then return true end end
      return false
    end
    local tags = WFJ.Menus.TAGS
    assert.is_true(has(tags.MENU_QUEUE_STATUS_FRAME.keys, "LEAVE_ARENA"))
    assert.is_true(has(tags.MENU_QUEUE_STATUS_FRAME.keys, "UNLIST_ME"))
    assert.is_true(has(tags.MENU_EDIT_MODE_MANAGER.keys, "HUD_EDIT_MODE_CHARACTER_LAYOUTS_HEADER"))
    assert.is_true(has(tags.MENU_EDIT_MODE_MANAGER.tooltips, "HUD_EDIT_MODE_DELETE_LAYOUT"))
    assert.is_true(has(tags.MENU_WORLD_MAP_TRACKING.tooltips, "WORLD_QUESTS_FILTER_DESCRIPTION"))
    assert.is_true(has(tags.MENU_WORLD_MAP_TRACKING.keys, "SHOW_QUEST_LEVELS"))
  end)
end)
