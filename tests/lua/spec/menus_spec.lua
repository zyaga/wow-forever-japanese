local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local M = require("tests.lua.spec.menu_stub")

-- Dropdown and context-menu entries, written once the client has built and shown each menu (tests/lua/spec/
-- menu_stub.lua builds the menus as the client does and fires its registry events).
local FILES = {}
for _, f in ipairs(H.UI_FILES) do FILES[#FILES + 1] = f end
FILES[#FILES + 1] = "UI/SettingsKeys.lua"
FILES[#FILES + 1] = "UI/Menus.lua"
FILES[#FILES + 1] = "UI/MenusUntagged.lua"

local UI = {
  BAG_FILTER_TITLE_SORTING = { "Bag Settings", "バッグの設定" }, BAG_NAME_BAG_1 = { "Bag 1", "バッグ1" },
  BAG_FILTER_ASSIGN_TO = { "Assign To:", "割り当て先:" }, BAG_FILTER_CLEANUP = { "Ignore This Bag", "このバッグを無視" },
  BAG_FILTER_EQUIPMENT = { "Equipment", "装備品" },
  BAG_NAME_BAG_REAGENT = { "Reagent Bag", "素材バッグ" }, -- gamepad UI mode's combined bag (containerframe.lua:42)
  UNAVAILABLE = { "Unavailable", "習得不可" }, USED = { "Used", "習得済み" },
  CATEGORIZE = { "Categorize", "分類" },
  AVAILABLE = { "Available", "習得可能" }, -- owns its Japanese (FRIENDS_LIST_AVAILABLE shares "Available")
  GUILD_RANK_UNAVAILABLE = { "Rank Unavailable", "ランクは選択できません" },
  -- the Communities menus' colour-wrapped entries (a plain entry and a template)
  COMMUNITIES_CREATE_CHANNEL = { "Create Channel", "チャンネルを作成" },
  COMMUNITIES_NOTIFICATION_SETTINGS = { "Notification Settings", "通知設定" },
  CLUB_FINDER_REAPPLY = { "Reapply in %d Days", "%d日後に再申請可能" },
  -- a word that is also a key but not in the tag's list: never shown in a menu of another tag
  RAID = { "Raid", "レイド" },
  -- level-1 menus
  DUEL = { "Duel", "決闘" }, TRADE = { "Trade", "取引" }, SET_FOCUS = { "Set Focus", "フォーカスに設定" },
  RAID_TARGET_ICON = { "Target Marker Icon", "ターゲットマーカー" }, RAID_TARGET_1 = { "Star", "スター" },
  UNIT_FRAME_DROPDOWN_SUBSECTION_TITLE_OTHER = { "Other Options", "その他のオプション" },
  MOVE_TO_NEW_WINDOW = { "Move to New Window", "新しいウィンドウに移動" },
  MINIMAP_TRACKING_BANKER = { "Banker", "銀行員" }, UNCHECK_ALL = { "Uncheck All", "すべてのチェックを外す" },
  FONT_SIZE = { "Font Size", "文字サイズ" }, FONT_SIZE_TEMPLATE = { "%d pt", "%dポイント" },
  SAY_MESSAGE = { "Say", "発言" },
  WORLD_MAP_FILTER_LABEL_SHOW = { "Show:", "表示：" },
  -- gamepad UI mode's combined map and quest log menu (blizzard_worldmaptemplates.lua:234, 325–339)
  WORLD_MAP_FILTER_TITLE_SHOW_MAP = { "Show on Map:", "マップに表示：" },
  WORLD_MAP_FILTER_TITLE_SHOW_QUEST_LOG = { "Show in Quest Log:", "クエストログに表示：" },
  QUEST_LOG_SHOW_OBJECTIVES = { "Show Quest Objectives", "クエスト目標を表示" },
  SHOW_QUEST_LEVELS = { "Show Quest Levels", "クエストレベルを表示" },
  QUEST_LEVEL_FILTER_DESCRIPTION = { "Show recommended player level next to quests",
    "クエストの横に推奨プレイヤーレベルを表示する" },
  -- group entries, the sweep's menus, the untagged dropdowns
  TANK = { "Tank", "タンク" }, NO_ROLE = { "No Role", "役割なし" }, SET_ROLE = { "Set Role", "役割を設定" },
  YES = { "Yes", "はい" }, NO = { "No", "いいえ" }, OPT_OUT_LOOT_TITLE = { "Pass on Loot: %s", "戦利品をパス：%s" },
  LOOT_GROUP_LOOT = { "Loot: Group Loot", "戦利品：グループ" }, ITEM_QUALITY2_DESC = { "Uncommon", "アンコモン" },
  NEWBIE_TOOLTIP_UNIT_GROUP_LOOT = { "Under group loot rules, players take turns.", "グループルールでは、順番に取ります。" },
  FRIENDS_LIST_AVAILABLE = { "Available", "オンライン" },
  ADDON_LIST_RESET_TO_DEFAULT = { "Reset to Default", "初期設定に戻す" },
  HUD_EDIT_MODE_IMPORT_LAYOUT = { "Import", "インポート" }, UNLIST_ME = { "Unlist Me", "登録を取り消す" },
  TIMEMANAGER_AM = { "AM", "午前" }, ALL_SPECS = { "All Specs", "すべての専門" }, ALL = { "All", "すべて" },
  LFG_LIST_IGNORE_SUGGESTED_LEVEL = { "Ignore Suggested Level", "推奨レベルを無視" },
  ANTIALIASING_FXAA_LOW = { "FXAA Low", "FXAA 低" }, HIGH = { "High", "高" },
  -- the Options window's combat text menus (blizzard_settingsdefinitions_frame/mainline/combatoverrides.lua:73–88,
  -- 183–224): a "Text on Me" checkbox with its hover, and a "Text on Target" entry
  COMBAT_TEXT_SHOW_DODGE_PARRY_MISS_TEXT = { "Dodge/Parry/Miss", "回避/受け流し/ミス" },
  OPTION_TOOLTIP_COMBAT_TEXT_SHOW_DODGE_PARRY_MISS = { "Shows attacks against you that dodge, parry, or miss.",
    "自分への攻撃の回避、受け流し、ミスを表示します。" },
  SHOW_DAMAGE_TEXT = { "Damage", "ダメージ" },
  -- the Text on Target menu's owned "Effects" (UIStrings.OWN); "Effects" elsewhere is the volume slider's 効果音
  SHOW_TARGET_EFFECTS = { "Effects", "効果" }, FX_VOLUME = { "Effects", "効果音" },
  -- a quest's context menu in the quest log (mainline/questmapframe.lua:2367–2416) and the detail popup's options
  -- menu (:2642–2689)
  TRACK_QUEST = { "Track Quest", "追跡" }, UNTRACK_QUEST = { "Untrack Quest", "クエストの追跡を解除" },
  SUPER_TRACK_QUEST = { "Focus", "フォーカス" }, SHARE_QUEST = { "Share Quest", "クエスト共有" },
  ABANDON_QUEST = { "Abandon Quest", "クエスト放棄" }, SHOW_MAP = { "Show Map", "マップを表示" },
}

local element = M.element

describe("UI/Menus: menu entries", function()
  local WFJ, registry

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    registry = M.registry()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
  end)

  after_each(function()
    H.uiTeardown(); _G.Menu = nil; _G.EventRegistry = nil; _G.issecretvalue = nil; _G.UnitName = nil
  end)

  -- A menu the client has built and shown with `tag`. → root, { [element] = frame }, menu frames
  local function generate(tag, build, contextData)
    local root = element(nil)
    build(root)
    local frames, menus = M.open(registry, tag, root, contextData)
    return root, frames, menus
  end

  local function text(frames, e) return frames[e].fontString:GetText() end

  it("writes top-level and submenu entries once the menu is shown; Alt shows English; closing lets go", function()
    assert.is_true(WFJ.Menus.init())
    local sub
    local root, frames, menus = generate("MENU_CONTAINER_FRAME_COMBINED", function(r)
      r:CreateButton(UI.BAG_FILTER_TITLE_SORTING[1])
      sub = r:CreateButton(UI.BAG_NAME_BAG_1[1])
      sub:CreateButton(UI.BAG_FILTER_ASSIGN_TO[1])
      sub:CreateButton(UI.BAG_FILTER_EQUIPMENT[1])
    end)
    local e = root.children
    assert.are.equal("バッグの設定", text(frames, e[1]))
    assert.are.equal("バッグ1", text(frames, e[2]))
    -- the client's own SetFont, never the compositor's wrapped one
    assert.are.equal(WFJ.Font.PATH, frames[e[2]].fontString.font.path)
    assert.are.equal("割り当て先:", text(frames, sub.children[1]))
    assert.are.equal("装備品", text(frames, sub.children[2]))
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal("Bag 1", text(frames, e[2]))
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    M.close(registry, menus)
    assert.are.equal(0, WFJ.SurfaceState.count(WFJ.Menus.SURFACE))
    assert.is_false(WFJ.TextWatch.watching(frames[e[2]].fontString))
    assert.is_nil(WFJ.Menus.openTag())
  end)

  it("no menu description is touched: nothing adds an initializer or a resetter", function()
    WFJ.Menus.init()
    local root = element(nil)
    local b = root:CreateButton(UI.BAG_NAME_BAG_1[1])
    b.AddInitializer = function() error("an initializer") end
    b.AddResetter = function() error("a resetter") end
    root.AddInitializer, root.AddResetter = b.AddInitializer, b.AddResetter
    local frames = M.open(registry, "MENU_CONTAINER_FRAME_COMBINED", root)
    assert.are.equal("バッグ1", text(frames, b))
  end)

  it("a pick that keeps the menu open writes the English back: the text watch writes the Japanese again", function()
    -- a checkbox's Refresh response runs the client's own initializers again: the compositor sets each FontString
    -- to its default font object and the initializer writes the English (menu.lua:2353–2367, 1682–1700;
    -- compositor.lua:66–74; menutemplates.lua:298)
    WFJ.Menus.init()
    local root, frames = generate("MENU_CONTAINER_FRAME_COMBINED", function(r)
      r:CreateButton(UI.BAG_FILTER_EQUIPMENT[1])
    end)
    local fs = frames[root.children[1]].fontString
    assert.are.equal("装備品", fs:GetText())
    fs.font = { path = "Fonts\\FRIZQT__.TTF", size = 12, flags = "" }
    fs:SetText(UI.BAG_FILTER_EQUIPMENT[1])
    fs.width = M.width(UI.BAG_FILTER_EQUIPMENT[1])
    WFJ.TextWatch.tick() -- the watch's next frame, after the client's pass
    assert.are.equal("装備品", fs:GetText())
    assert.are.equal(WFJ.Font.PATH, fs.font.path)
    assert.are.equal(M.width(UI.BAG_FILTER_EQUIPMENT[1]), fs:GetWidth()) -- narrower Japanese keeps the width
  end)

  it("gamepad UI mode's reagent bag entry in the combined bag menu; Alt shows English", function()
    WFJ.Menus.init()
    local root, frames = generate("MENU_CONTAINER_FRAME_COMBINED", function(r)
      r:CreateButton(UI.BAG_NAME_BAG_REAGENT[1])
    end)
    local fs = frames[root.children[1]].fontString
    assert.are.equal("素材バッグ", fs:GetText())
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal("Reagent Bag", fs:GetText())
    Stub.keys.alt = false; WFJ.Modifier.refresh()
  end)

  it("a name in a menu, and a dictionary word outside the tag's list, stay as written", function()
    WFJ.Menus.init()
    local root, frames = generate("MENU_CONTAINER_FRAME_COMBINED", function(r)
      r:CreateButton("My Herb Bag") -- a bag the player named
      r:CreateButton(UI.RAID[1])
    end)
    assert.are.equal("My Herb Bag", text(frames, root.children[1]))
    assert.are.equal("Raid", text(frames, root.children[2]))
  end)

  it("a colour-wrapped entry keeps its colour (the trainer filter)", function()
    WFJ.Menus.init()
    local root, frames = generate("MENU_TRAINER_FILTER", function(r)
      r:CreateButton("|cffff2020" .. UI.UNAVAILABLE[1] .. "|r")
      r:CreateButton("|cff808080" .. UI.USED[1] .. "|r")
    end)
    assert.are.equal("|cffff2020習得不可|r", text(frames, root.children[1]))
    assert.are.equal("|cff808080習得済み|r", text(frames, root.children[2]))
  end)

  it("the trainer filter's Available owns its Japanese; the friends status keeps its own", function()
    WFJ.Menus.init()
    local root, frames = generate("MENU_TRAINER_FILTER", function(r)
      r:CreateButton("|cff00ff00" .. UI.AVAILABLE[1] .. "|r")
    end)
    assert.are.equal("|cff00ff00習得可能|r", text(frames, root.children[1]))
    assert.are.equal(0, WFJ.UIIndex.counts.ambiguous)
  end)

  it("the trainer filter's Categorize checkbox translates; Alt shows English", function()
    WFJ.Menus.init()
    local root, frames = generate("MENU_TRAINER_FILTER", function(r)
      r:CreateButton(UI.CATEGORIZE[1])
    end)
    local fs = frames[root.children[1]].fontString
    assert.are.equal("分類", fs:GetText())
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal("Categorize", fs:GetText())
    Stub.keys.alt = false; WFJ.Modifier.refresh()
  end)

  it("the Communities menus' colour-wrapped entries keep their colour; a channel name stays as written", function()
    WFJ.Menus.init()
    local root, frames, menus = generate("MENU_COMMUNITIES_STREAM", function(r)
      r:CreateButton("General") -- a channel name
      r:CreateButton("|cff19ff19" .. UI.COMMUNITIES_CREATE_CHANNEL[1] .. "|r")
      r:CreateButton(UI.COMMUNITIES_NOTIFICATION_SETTINGS[1])
    end)
    assert.are.equal("General", text(frames, root.children[1]))
    assert.are.equal("|cff19ff19チャンネルを作成|r", text(frames, root.children[2]))
    assert.are.equal("通知設定", text(frames, root.children[3]))
    M.close(registry, menus)
    local card, cardFrames = generate("MENU_CLUB_FINDER_CARD", function(r)
      -- RED_FONT_COLOR:WrapTextInColorCode(CLUB_FINDER_REAPPLY:format(3))
      r:CreateButton("|cffff2020Reapply in 3 Days|r")
    end)
    assert.are.equal("|cffff20203日後に再申請可能|r", text(cardFrames, card.children[1]))
  end)

  it("a disabled rank's reason is registered on its own element as a help-tooltip owner", function()
    WFJ.Menus.init()
    local root, frames = generate("MENU_GUILD_RANKS", function(r) r:CreateButton("Officer") end)
    local frame = frames[root.children[1]]
    assert.are.equal("Officer", frame.fontString:GetText()) -- the rank's name
    assert.is_true(WFJ.HelpTooltip.registered(frame))
  end)

  it("no event registry: init returns false and nothing is written", function()
    _G.EventRegistry = nil
    local W = H.loadChunks(FILES)
    H.uiSetup(W, UI)
    assert.is_false(W.Menus.init())
  end)

  it("an element whose frame has no text widget, or a malformed event, never errors", function()
    WFJ.Menus.init()
    assert.are.equal(0, WFJ.Menus.showElement("MENU_TRAINER_FILTER", {}))
    assert.are.equal(0, WFJ.Menus.showElement("MENU_TRAINER_FILTER", { fontString = "x" }))
    assert.are.equal(0, WFJ.Menus.onMenuShown(nil, nil))
    assert.are.equal(0, WFJ.Menus.onMenuOpened(nil, nil))
    assert.are.equal(0, WFJ.Menus.onMenuHidden(nil, "x"))
  end)

  it("a channel menu keeps its title (the channel's name) even when it is a dictionary word", function()
    WFJ.Menus.init()
    local root, frames = generate("MENU_CHAT_FRAME_CHANNEL", function(r)
      r:CreateButton("Trade") -- ChatFrameUtil.ResolveChannelName
      r:CreateButton(UI.MOVE_TO_NEW_WINDOW[1])
    end, { name = "Trade" })
    assert.are.equal("Trade", text(frames, root.children[1]))
    assert.are.equal("新しいウィンドウに移動", text(frames, root.children[2]))
  end)

  it("a menu's name the client keeps secret counts as no name and raises nothing", function()
    local SECRET = "Trade" -- stands for a secret string value
    _G.issecretvalue = function(v) return v == SECRET end
    WFJ.Compat.init(function(name) return _G[name] end)
    WFJ.Menus.init()
    WFJ.initErrors = nil
    local root, frames = generate("MENU_CHAT_FRAME_CHANNEL", function(r)
      r:CreateButton("General") -- the title
      r:CreateButton(UI.MOVE_TO_NEW_WINDOW[1])
    end, { name = SECRET })
    assert.are.equal("新しいウィンドウに移動", text(frames, root.children[2]))
    assert.is_nil(WFJ.initErrors)
    assert.is_nil(WFJ.Menus.nameOf(WFJ.Menus.TAGS.MENU_CHAT_FRAME_CHANNEL, { name = SECRET }))
    assert.are.equal("General", WFJ.Menus.nameOf(WFJ.Menus.TAGS.MENU_CHAT_FRAME_CHANNEL, { name = "General" }))
  end)

  it("the minimap tracking menu: townsfolk entries in Japanese, a tracking spell stays its name", function()
    WFJ.Menus.init()
    local root, frames = generate("MENU_MINIMAP_TRACKING", function(r)
      r:CreateButton(UI.UNCHECK_ALL[1])
      r:CreateButton(UI.MINIMAP_TRACKING_BANKER[1])
      r:CreateButton("Find Herbs")
    end)
    assert.are.equal("すべてのチェックを外す", text(frames, root.children[1]))
    assert.are.equal("銀行員", text(frames, root.children[2]))
    assert.are.equal("Find Herbs", text(frames, root.children[3]))
  end)

  it("the chat tab menu: Font Size's radios keep their number", function()
    WFJ.Menus.init()
    local size
    local root, frames = generate("MENU_FCF_TAB", function(r)
      size = r:CreateButton(UI.FONT_SIZE[1])
      size:CreateButton("12 pt")
    end)
    assert.are.equal("文字サイズ", text(frames, root.children[1]))
    assert.are.equal("12ポイント", text(frames, size.children[1]))
  end)

  it("the chat menu: entries in Japanese once open; slash commands and language names stay", function()
    WFJ.Menus.init()
    local root, frames = generate("MENU_CHAT_SHORTCUTS", function(r)
      r:CreateButton(UI.SAY_MESSAGE[1])
      r:CreateButton("/s")
      r:CreateButton("Common")
    end)
    assert.are.equal("発言", text(frames, root.children[1]))
    assert.are.equal("/s", text(frames, root.children[2])) -- the slash command beside an entry
    assert.are.equal("Common", text(frames, root.children[3])) -- a language name: never listed
  end)

  it("nothing is written before the client reports a tagged menu open", function()
    WFJ.Menus.init()
    local root = element(nil)
    root:CreateButton(UI.SAY_MESSAGE[1])
    local frames = {}
    local menu = M.menuFrame(root, frames)
    registry:TriggerEvent("MenuProxy.OnShow", menu)
    assert.are.equal(UI.SAY_MESSAGE[1], text(frames, root.children[1]))
    registry:TriggerEvent("Menu.OpenMenuTag", "MENU_CHAT_SHORTCUTS")
    assert.are.equal("発言", text(frames, root.children[1]))
  end)

  -- The addon's writes on a text widget so far (the stub counts them).
  local function writes(fs) return fs.calls.addonSetText + fs.calls.addonSetFont end

  it("a closed menu lets go of its text widgets: the next menu to take one is never written", function()
    WFJ.Menus.init()
    local root, frames, menus = generate("MENU_CHAT_SHORTCUTS", function(r) r:CreateButton(UI.SAY_MESSAGE[1]) end)
    local pooled = frames[root.children[1]].fontString
    assert.are.equal("発言", pooled:GetText())

    M.close(registry, menus) -- before the client hands the widgets back to the shared pool
    assert.are.equal(UI.SAY_MESSAGE[1], pooled:GetText()) -- the client's text is back on it
    local widget = WFJ.Labels.menuText(pooled) -- the adapter a menu record sits on
    for _, rec in pairs(WFJ.SurfaceState.records(WFJ.Menus.SURFACE)) do assert.are_not.equal(widget, rec.fs) end
    assert.is_false(WFJ.TextWatch.watching(pooled))

    -- another menu takes the widget, outside any translated menu; its entry may even show the same English
    for _, t in ipairs({ "Trade", UI.SAY_MESSAGE[1] }) do
      pooled:SetText(t)
      local before = writes(pooled)
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      Stub.keys.alt = false; WFJ.Modifier.refresh()
      WFJ.Render.refresh(WFJ.Menus.SURFACE)
      WFJ.TextWatch.tick()
      assert.are.equal(t, pooled:GetText())
      assert.are.equal(before, writes(pooled), t)
    end
    -- hiding it again does nothing
    assert.are.equal(0, WFJ.Menus.onMenuHidden(nil, menus[1]))
  end)

  it("a rebuild of the open menu moves its widgets to other frames: they are still let go", function()
    WFJ.Menus.init()
    local root, frames, menus = generate("MENU_CHAT_SHORTCUTS", function(r)
      r:CreateButton(UI.SAY_MESSAGE[1])
      r:CreateButton("/s")
    end)
    local say, slash = frames[root.children[1]], frames[root.children[2]]
    local pooled = say.fontString
    assert.are.equal("発言", pooled:GetText())
    say.fontString, slash.fontString = slash.fontString, say.fontString -- the pool hands them back in another order
    M.close(registry, menus)
    local widget = WFJ.Labels.menuText(pooled)
    for _, rec in pairs(WFJ.SurfaceState.records(WFJ.Menus.SURFACE)) do assert.are_not.equal(widget, rec.fs) end
  end)

  it("an error while writing an opened menu is recorded once and never raised", function()
    WFJ.Menus.init()
    WFJ.initErrors = nil
    local root = element(nil)
    root:CreateButton(UI.SAY_MESSAGE[1])
    local menu = M.menuFrame(root, {})
    menu.GetOwnerRegion = function() error("boom") end
    registry:TriggerEvent("MenuProxy.OnShow", menu)
    registry:TriggerEvent("MenuProxy.OnShow", menu)
    assert.are.equal(1, #WFJ.initErrors)
    assert.are.equal("menus.afteropen", WFJ.initErrors[1].surface)
  end)

  it("an unlisted tag, or a menu frame already hidden, is never written", function()
    WFJ.Menus.init()
    local root = element(nil)
    root:CreateButton(UI.SAY_MESSAGE[1])
    local frames = {}
    local menu = M.menuFrame(root, frames)
    registry:TriggerEvent("MenuProxy.OnShow", menu)
    registry:TriggerEvent("Menu.OpenMenuTag", "MENU_NOT_TRANSLATED")
    assert.are.equal(UI.SAY_MESSAGE[1], text(frames, root.children[1]))
    menu.shown = false -- a menu shown earlier and since closed
    registry:TriggerEvent("Menu.OpenMenuTag", "MENU_CHAT_SHORTCUTS")
    assert.are.equal(UI.SAY_MESSAGE[1], text(frames, root.children[1]))
  end)

  it("a menu frame shown after the translated menu closed is not written with its keys", function()
    WFJ.Menus.init()
    local _, _, menus = generate("MENU_CHAT_SHORTCUTS", function(r) r:CreateButton(UI.SAY_MESSAGE[1]) end)
    M.close(registry, menus)
    -- another menu with no tag of ours (a unit-less context menu nobody recorded) opens next
    local other = element(nil)
    other:CreateButton(UI.SAY_MESSAGE[1])
    local frames = M.open(registry, nil, other)
    assert.are.equal(UI.SAY_MESSAGE[1], text(frames, other.children[1]))
  end)

  it("the registry callbacks are placed once however often init runs", function()
    assert.is_true(WFJ.Menus.init())
    assert.is_true(WFJ.Menus.init())
    assert.are.equal(1, #registry.calls["MenuProxy.OnShow"])
    assert.are.equal(1, #registry.calls["Menu.OpenMenuTag"])
    assert.are.equal(1, #registry.calls["MenuProxy.OnHide"])
  end)

  it("a Japanese label wider than the English widens its widget, the entries and the menu frame", function()
    WFJ.Menus.init()
    -- "Ignore Suggested Level" is 22 characters, 推奨レベルを無視 8; "Tank" 4 → タンク 3: none wider
    local root, frames, menus = generate("MENU_LFG_LISTING_ROLE", function(r) r:CreateButton(UI.TANK[1]) end)
    assert.are.equal(M.INSET + M.width("Tank") + M.MARGIN, frames[root.children[1]]:GetWidth())
    M.close(registry, menus)
    -- 割り当て先: (6) against "Assign To:" (10): narrower; 装備品 (3) against "Equipment" (9): narrower. A label
    -- whose Japanese is longer: SET_ROLE "Set Role" (8) → 役割を設定 (5) is narrower too, so use a long one
    local LONG = { "Ok", "とても長い日本語の項目です" }
    UI.FX_LONG = LONG
    H.uiSetup(WFJ, UI)
    WFJ.Menus.TAGS.MENU_TEST_FIT = { keys = { "FX_LONG", "TANK" } }
    local root2, frames2, menus2 = generate("MENU_TEST_FIT", function(r)
      r:CreateButton(LONG[1])
      r:CreateButton(UI.TANK[1])
    end)
    local entryBefore = M.INSET + M.width("Tank") + M.MARGIN -- the widest English
    local over = M.INSET + M.width(LONG[2]) + M.MARGIN - entryBefore
    local fs = frames2[root2.children[1]].fontString
    assert.are.equal(LONG[2], fs:GetText())
    assert.are.equal(M.width(LONG[2]), fs:GetWidth())
    assert.are.equal(entryBefore + over, frames2[root2.children[1]]:GetWidth())
    assert.are.equal(entryBefore + over, frames2[root2.children[2]]:GetWidth())
    assert.are.equal(entryBefore + 2 * M.PAD + over, menus2[1]:GetWidth())
    -- a scrolling menu keeps its fixed size
    M.close(registry, menus2)
    local root3 = element(nil)
    root3:CreateButton(LONG[1])
    local frames3 = {}
    local scrolling = M.menuFrame(root3, frames3)
    scrolling.ScrollBox = { IsShown = function() return true end }
    local width = scrolling:GetWidth()
    registry:TriggerEvent("MenuProxy.OnShow", scrolling)
    registry:TriggerEvent("Menu.OpenMenuTag", "MENU_TEST_FIT")
    assert.are.equal(LONG[2], text(frames3, root3.children[1]))
    assert.are.equal(width, scrolling:GetWidth())
    WFJ.Menus.TAGS.MENU_TEST_FIT, UI.FX_LONG = nil, nil
  end)

  it("the world map filter: title and entries in Japanese; each entry owns its description tooltip", function()
    WFJ.Menus.init()
    local root, frames = generate("MENU_WORLD_MAP_TRACKING", function(r)
      r:CreateButton(UI.WORLD_MAP_FILTER_LABEL_SHOW[1])
      r:CreateButton(UI.SHOW_QUEST_LEVELS[1])
    end)
    assert.are.equal("表示：", text(frames, root.children[1]))
    local entry = frames[root.children[2]]
    assert.are.equal("クエストレベルを表示", entry.fontString:GetText())
    assert.is_true(WFJ.HelpTooltip.registered(entry))
    local tt = _G.GameTooltip
    tt:SetOwner(entry, "ANCHOR_PRESERVE")
    tt:SetText(UI.SHOW_QUEST_LEVELS[1])
    tt:AddLine(UI.QUEST_LEVEL_FILTER_DESCRIPTION[1])
    tt:Show()
    assert.are.equal("クエストレベルを表示", _G.GameTooltipTextLeft1:GetText())
    assert.are.equal("クエストの横に推奨プレイヤーレベルを表示する", _G.GameTooltipTextLeft2:GetText())
  end)

  it("the world map filter in gamepad UI mode: the map and quest log titles and the objectives checkbox", function()
    WFJ.Menus.init()
    local root, frames = generate("MENU_WORLD_MAP_TRACKING", function(r)
      r:CreateButton(UI.WORLD_MAP_FILTER_TITLE_SHOW_MAP[1])
      r:CreateButton(UI.WORLD_MAP_FILTER_TITLE_SHOW_QUEST_LOG[1])
      r:CreateButton(UI.QUEST_LOG_SHOW_OBJECTIVES[1])
      r:CreateButton(UI.RAID[1])
    end)
    local e = root.children
    assert.are.equal("マップに表示：", text(frames, e[1]))
    assert.are.equal("クエストログに表示：", text(frames, e[2]))
    assert.are.equal("クエスト目標を表示", text(frames, e[3]))
    assert.are.equal("Raid", text(frames, e[4]))
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal("Show Quest Objectives", text(frames, e[3]))
    Stub.keys.alt = false; WFJ.Modifier.refresh()
  end)

  it("a quest's menu in the quest log and the detail popup's options: every entry in Japanese; Alt shows English",
    function()
      WFJ.Menus.init()
      local cases = {
        { "MENU_QUEST_MAP_LOG_TITLE", { "TRACK_QUEST", "SUPER_TRACK_QUEST", "SHARE_QUEST", "ABANDON_QUEST" } },
        { "MENU_QUEST_MAP_LOG_TITLE", { "UNTRACK_QUEST" } },
        { "MENU_QUEST_LOG_POPUP_DETAIL_FRAME", { "TRACK_QUEST", "SUPER_TRACK_QUEST", "SHOW_MAP", "SHARE_QUEST",
          "ABANDON_QUEST" } },
      }
      for _, c in ipairs(cases) do
        local root, frames, menus = generate(c[1], function(r)
          for _, k in ipairs(c[2]) do r:CreateButton(UI[k][1]) end
        end)
        for i, k in ipairs(c[2]) do assert.are.equal(UI[k][2], text(frames, root.children[i]), k) end
        Stub.keys.alt = true; WFJ.Modifier.refresh()
        for i, k in ipairs(c[2]) do assert.are.equal(UI[k][1], text(frames, root.children[i]), k) end
        Stub.keys.alt = false; WFJ.Modifier.refresh()
        M.close(registry, menus)
      end
    end)

  it("one entry per sweep tag in Japanese; names beside them stay as written", function()
    WFJ.Menus.init()
    local cases = {
      { "MENU_QUEUE_STATUS_FRAME", { "Deadmines", UI.UNLIST_ME[1] }, { "Deadmines", "登録を取り消す" } },
      { "MENU_LFG_LISTING_ROLE", { UI.TANK[1] }, { "タンク" } },
      { "MENU_LFG_LISTING_SETTINGS", { UI.LFG_LIST_IGNORE_SUGGESTED_LEVEL[1] }, { "推奨レベルを無視" } },
      { "MENU_FRIENDS_STATUS", { "|TInterface\\FriendsFrame\\StatusIcon-Online.tga:16:16:0:0|t "
        .. UI.FRIENDS_LIST_AVAILABLE[1] }, { "|TInterface\\FriendsFrame\\StatusIcon-Online.tga:16:16:0:0|t オンライン" } },
      { "MENU_MERCHANT_FRAME", { "Arms", UI.ALL_SPECS[1], UI.ALL[1] }, { "Arms", "すべての専門", "すべて" } },
      { "MENU_TIME_MANAGER_AMPM", { UI.TIMEMANAGER_AM[1] }, { "午前" } },
      { "MENU_ADDON_LIST", { UI.ALL[1] }, { "すべて" } },
    }
    for _, c in ipairs(cases) do
      local root, frames, menus = generate(c[1], function(r) for _, t in ipairs(c[2]) do r:CreateButton(t) end end)
      for i, want in ipairs(c[3]) do assert.are.equal(want, text(frames, root.children[i]), c[1]) end
      M.close(registry, menus)
    end
  end)

  it("an AddOn entry's menu keeps its title (the addon's title) even when it is a dictionary word",
    function()
      WFJ.Menus.init()
      local root, frames = generate("MENU_ADDON_LIST_ENTRY", function(r)
        r:CreateButton(UI.ALL[1]) -- an addon titled "All"
        r:CreateButton(UI.ADDON_LIST_RESET_TO_DEFAULT[1])
      end, { name = UI.ALL[1] })
      assert.are.equal("All", text(frames, root.children[1]))
      assert.are.equal("初期設定に戻す", text(frames, root.children[2]))
    end)

  it("the untagged Options dropdowns, recognised by their owner; Edit Mode's dropdowns are never reached", function()
    local settings = { InitDropdown = function() end }
    _G.Settings = settings
    local editRow = { Dropdown = {} }
    _G.EditModeSettingDropdownMixin = { SetupSetting = function() end }
    WFJ.Compat.init(function(name) return _G[name] end)
    WFJ.Menus.init()
    assert.are.equal(1, WFJ.MenusUntagged.init())
    local options = {}
    settings.InitDropdown(options)
    _G.EditModeSettingDropdownMixin.SetupSetting(editRow)
    local root = element(nil)
    root:CreateButton(UI.ANTIALIASING_FXAA_LOW[1])
    root:CreateButton("Friz Quadrata TT") -- a font name: no key
    root:CreateButton(UI.RAID[1]) -- a dictionary word outside the window's keys
    local frames, menus = M.open(registry, nil, root, nil, options) -- a dropdown's menu fires no Menu.OpenMenuTag
    assert.are.equal("FXAA 低", text(frames, root.children[1]))
    assert.are.equal("Friz Quadrata TT", text(frames, root.children[2]))
    assert.are.equal("Raid", text(frames, root.children[3]))
    M.close(registry, menus)
    local edit = element(nil)
    edit:CreateButton(UI.HIGH[1])
    assert.are.equal(UI.HIGH[1], text(M.open(registry, nil, edit, nil, editRow.Dropdown), edit.children[1])) -- ADR-069
    -- recorded once per dropdown, however often the client sets it up
    assert.is_false(WFJ.MenusUntagged.hookDropdown(options, "SETTINGS_DROPDOWN"))
    _G.Settings, _G.EditModeSettingDropdownMixin = nil, nil
  end)

  it("the combat text dropdowns: a Text on Me checkbox and its hover (title = label, line = tooltip), a Text on"
    .. " Target entry", function()
    local settings = { InitDropdown = function() end }
    _G.Settings = settings
    WFJ.Compat.init(function(name) return _G[name] end)
    WFJ.Menus.init()
    WFJ.MenusUntagged.init()
    local onMe = {}
    settings.InitDropdown(onMe)
    local root = element(nil)
    root:CreateButton(UI.COMBAT_TEXT_SHOW_DODGE_PARRY_MISS_TEXT[1])
    local frames, menus = M.open(registry, nil, root, nil, onMe)
    local box = frames[root.children[1]]
    assert.are.equal("回避/受け流し/ミス", box.fontString:GetText())
    -- Settings.CreateDropdownCheckbox's SetTooltip (blizzard_settings_shared/blizzard_settings.lua:508–513)
    assert.is_true(WFJ.HelpTooltip.registered(box))
    local tt = _G.GameTooltip
    tt:SetOwner(box, "ANCHOR_RIGHT")
    tt:SetText(UI.COMBAT_TEXT_SHOW_DODGE_PARRY_MISS_TEXT[1])
    tt:AddLine(UI.OPTION_TOOLTIP_COMBAT_TEXT_SHOW_DODGE_PARRY_MISS[1])
    tt:Show()
    assert.are.equal("回避/受け流し/ミス", _G.GameTooltipTextLeft1:GetText())
    assert.are.equal("自分への攻撃の回避、受け流し、ミスを表示します。", _G.GameTooltipTextLeft2:GetText())
    -- an Options key that is no combat-text hover stays English on that hover
    tt:SetOwner(box, "ANCHOR_RIGHT")
    tt:SetText(UI.ANTIALIASING_FXAA_LOW[1])
    tt:Show()
    assert.are.equal("FXAA Low", _G.GameTooltipTextLeft1:GetText())
    M.close(registry, menus)
    local onTarget = {}
    settings.InitDropdown(onTarget)
    local target = element(nil)
    target:CreateButton(UI.SHOW_DAMAGE_TEXT[1])
    target:CreateButton(UI.SHOW_TARGET_EFFECTS[1])
    local shown = M.open(registry, nil, target, nil, onTarget)
    assert.are.equal("ダメージ", text(shown, target.children[1]))
    assert.are.equal("効果", text(shown, target.children[2]))
    _G.Settings = nil
  end)
end)
