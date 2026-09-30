local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

-- Dropdown and context-menu entries through Menu.ModifyMenu initializers. A stub of the Menu system: ModifyMenu
-- stores the callback per tag; a generated menu is a tree of element descriptions whose initializers run on pooled
-- frames holding .fontString [verified: blizzard_menu/menu.lua:418–455, 2708–2745; menuvariants.lua:9–22].
local FILES = {}
for _, f in ipairs(H.UI_FILES) do FILES[#FILES + 1] = f end
FILES[#FILES + 1] = "UI/SettingsKeys.lua"
FILES[#FILES + 1] = "UI/MenusUnit.lua"
FILES[#FILES + 1] = "UI/Menus.lua"
FILES[#FILES + 1] = "UI/MenusUntagged.lua"

local UI = {
  BAG_FILTER_TITLE_SORTING = { "Bag Settings", "バッグの設定" }, BAG_NAME_BAG_1 = { "Bag 1", "バッグ1" },
  BAG_FILTER_ASSIGN_TO = { "Assign To:", "割り当て先:" }, BAG_FILTER_CLEANUP = { "Ignore This Bag", "このバッグを無視" },
  BAG_FILTER_EQUIPMENT = { "Equipment", "装備品" },
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
}

local function element(text)
  local e = { text = text, children = {}, inits = {}, resets = {} }
  function e:CreateButton(t) local c = element(t); self.children[#self.children + 1] = c; return c end
  function e:EnumerateElementDescriptions() return ipairs(self.children) end
  function e:AddInitializer(fn) self.inits[#self.inits + 1] = fn end
  function e:AddResetter(fn) self.resets[#self.resets + 1] = fn end
  return e
end

-- The compositor: a frame per element, the client's text first, then every initializer in order; the resetter on
-- release. → { [element] = frame }
local function open(root)
  local frames = {}
  local function each(desc)
    for _, e in desc:EnumerateElementDescriptions() do
      local frame = CreateFrame("Button")
      frame.fontString = Stub.fontString(e.text)
      -- the compositor forbids SetFont on its FontStrings (blizzard_menu/compositor.lua:166–169, 254–256)
      frame.fontString.SetFont = function() error("Use of function 'SetFont' is disallowed. (Index)") end
      for _, fn in ipairs(e.inits) do fn(frame, e) end
      frames[e] = frame
      each(e)
    end
  end
  each(root)
  return frames
end

local function release(frames)
  for e, frame in pairs(frames) do
    for _, fn in ipairs(e.resets) do fn(frame, e) end
  end
end

describe("UI/Menus: menu entries", function()
  local WFJ, callbacks

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    callbacks = {}
    _G.Menu = { ModifyMenu = function(tag, fn) callbacks[tag] = fn end }
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
  end)

  after_each(function() H.uiTeardown(); _G.Menu = nil end)

  local function generate(tag, build, contextData)
    local root = element(nil)
    build(root)
    callbacks[tag](nil, root, contextData) -- Menu.PopulateDescription → SecureModifyMenu
    return root, open(root)
  end

  it("registers one callback per tag and translates top-level and submenu entries", function()
    assert.is_true(WFJ.Menus.init())
    for tag in pairs(WFJ.Menus.TAGS) do assert.is_function(callbacks[tag], tag) end
    local sub
    local root, frames = generate("MENU_CONTAINER_FRAME_COMBINED", function(r)
      r:CreateButton(UI.BAG_FILTER_TITLE_SORTING[1])
      sub = r:CreateButton(UI.BAG_NAME_BAG_1[1])
      sub:CreateButton(UI.BAG_FILTER_ASSIGN_TO[1])
      sub:CreateButton(UI.BAG_FILTER_EQUIPMENT[1])
    end)
    local e = root.children
    assert.are.equal("バッグの設定", frames[e[1]].fontString:GetText())
    assert.are.equal("バッグ1", frames[e[2]].fontString:GetText())
    -- the client's own SetFont, never the compositor's wrapped one
    assert.are.equal(WFJ.Font.PATH, frames[e[2]].fontString.font.path)
    assert.are.equal("割り当て先:", frames[sub.children[1]].fontString:GetText())
    assert.are.equal("装備品", frames[sub.children[2]].fontString:GetText())
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal("Bag 1", frames[e[2]].fontString:GetText())
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    release(frames)
    assert.are.equal(0, WFJ.SurfaceState.count(WFJ.Menus.SURFACE))
  end)

  it("a name in a menu, and a dictionary word outside the tag's list, stay as written", function()
    WFJ.Menus.init()
    local root, frames = generate("MENU_CONTAINER_FRAME_COMBINED", function(r)
      r:CreateButton("My Herb Bag") -- a bag the player named
      r:CreateButton(UI.RAID[1])
    end)
    assert.are.equal("My Herb Bag", frames[root.children[1]].fontString:GetText())
    assert.are.equal("Raid", frames[root.children[2]].fontString:GetText())
  end)

  it("a colour-wrapped entry keeps its colour (the trainer filter)", function()
    WFJ.Menus.init()
    local root, frames = generate("MENU_TRAINER_FILTER", function(r)
      r:CreateButton("|cffff2020" .. UI.UNAVAILABLE[1] .. "|r")
      r:CreateButton("|cff808080" .. UI.USED[1] .. "|r")
    end)
    assert.are.equal("|cffff2020習得不可|r", frames[root.children[1]].fontString:GetText())
    assert.are.equal("|cff808080習得済み|r", frames[root.children[2]].fontString:GetText())
  end)

  it("the trainer filter's Available owns its Japanese; the friends status keeps its own", function()
    WFJ.Menus.init()
    local root, frames = generate("MENU_TRAINER_FILTER", function(r)
      r:CreateButton("|cff00ff00" .. UI.AVAILABLE[1] .. "|r")
    end)
    assert.are.equal("|cff00ff00習得可能|r", frames[root.children[1]].fontString:GetText())
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
    local root, frames = generate("MENU_COMMUNITIES_STREAM", function(r)
      r:CreateButton("General") -- a channel name
      r:CreateButton("|cff19ff19" .. UI.COMMUNITIES_CREATE_CHANNEL[1] .. "|r")
      r:CreateButton(UI.COMMUNITIES_NOTIFICATION_SETTINGS[1])
    end)
    assert.are.equal("General", frames[root.children[1]].fontString:GetText())
    assert.are.equal("|cff19ff19チャンネルを作成|r", frames[root.children[2]].fontString:GetText())
    assert.are.equal("通知設定", frames[root.children[3]].fontString:GetText())
    local card, cardFrames = generate("MENU_CLUB_FINDER_CARD", function(r)
      -- RED_FONT_COLOR:WrapTextInColorCode(CLUB_FINDER_REAPPLY:format(3))
      r:CreateButton("|cffff2020Reapply in 3 Days|r")
    end)
    assert.are.equal("|cffff20203日後に再申請可能|r", cardFrames[card.children[1]].fontString:GetText())
  end)

  it("a disabled rank's reason is registered on its own element as a help-tooltip owner", function()
    WFJ.Menus.init()
    local root, frames = generate("MENU_GUILD_RANKS", function(r) r:CreateButton("Officer") end)
    local frame = frames[root.children[1]]
    assert.are.equal("Officer", frame.fontString:GetText()) -- the rank's name
    assert.is_true(WFJ.HelpTooltip.registered(frame))
  end)

  it("no Menu API: init returns false and hooks nothing", function()
    _G.Menu = nil
    local W = H.loadChunks(FILES)
    H.uiSetup(W, UI)
    assert.is_false(W.Menus.init())
  end)

  it("an element whose frame has no text widget, or a malformed description, never errors", function()
    WFJ.Menus.init()
    assert.are.equal(0, WFJ.Menus.showElement("MENU_TRAINER_FILTER", {}))
    assert.are.equal(0, WFJ.Menus.showElement("MENU_TRAINER_FILTER", { fontString = "x" }))
    assert.are.equal(0, WFJ.Menus.onMenu("MENU_TRAINER_FILTER", {}))
    assert.are.equal(0, WFJ.Menus.resetElement(nil))
  end)

  -- the level-1 menus
  it("a unit menu: entries and the raid-target submenu in Japanese; the title (the unit's name) never matched",
    function()
    WFJ.Menus.init()
    local markers
    local root, frames = generate("MENU_UNIT_PLAYER", function(r)
      r:CreateButton("Duel") -- the title: a player named Duel (unitpopupshared.lua:112–116)
      r:CreateButton(UI.DUEL[1])
      r:CreateButton(UI.TRADE[1])
      r:CreateButton(UI.SET_FOCUS[1])
      markers = r:CreateButton(UI.RAID_TARGET_ICON[1])
      markers:CreateButton(UI.RAID_TARGET_1[1])
      r:CreateButton(UI.UNIT_FRAME_DROPDOWN_SUBSECTION_TITLE_OTHER[1])
    end, { name = "Trade" })
    local e = root.children
    assert.are.equal("Duel", frames[e[1]].fontString:GetText())
    assert.are.equal("決闘", frames[e[2]].fontString:GetText())
    assert.are.equal("Trade", frames[e[3]].fontString:GetText()) -- contextData.name: never matched
    assert.are.equal("フォーカスに設定", frames[e[4]].fontString:GetText())
    assert.are.equal("ターゲットマーカー", frames[e[5]].fontString:GetText())
    assert.are.equal("スター", frames[markers.children[1]].fontString:GetText())
    assert.are.equal("その他のオプション", frames[e[6]].fontString:GetText())
    for _, which in ipairs({ "SELF", "TARGET", "PLAYER", "ENEMY_PLAYER", "PARTY", "PET", "FOCUS", "FRIEND" }) do
      assert.is_function(callbacks["MENU_UNIT_" .. which], which)
    end
  end)

  it("a target menu with only a unit: an entry equal to UnitName(unit) is never matched", function()
    WFJ.Menus.init()
    _G.UnitName = function(unit) return unit == "target" and "Trade" or nil end
    local root, frames = generate("MENU_UNIT_TARGET", function(r)
      r:CreateButton("Trade") -- the title
      r:CreateButton(UI.SET_FOCUS[1])
      r:CreateButton(UI.TRADE[1]) -- the same English as the unit's name: left alone
    end, { unit = "target" })
    assert.are.equal("Trade", frames[root.children[1]].fontString:GetText())
    assert.are.equal("フォーカスに設定", frames[root.children[2]].fontString:GetText())
    assert.are.equal("Trade", frames[root.children[3]].fontString:GetText())
    _G.UnitName = nil
  end)

  it("a channel menu keeps its title (the channel's name) even when it is a dictionary word", function()
    WFJ.Menus.init()
    local root, frames = generate("MENU_CHAT_FRAME_CHANNEL", function(r)
      r:CreateButton("Trade") -- ChatFrameUtil.ResolveChannelName
      r:CreateButton(UI.MOVE_TO_NEW_WINDOW[1])
    end)
    assert.are.equal("Trade", frames[root.children[1]].fontString:GetText())
    assert.are.equal("新しいウィンドウに移動", frames[root.children[2]].fontString:GetText())
  end)

  it("the minimap tracking menu: townsfolk entries in Japanese, a tracking spell stays its name", function()
    WFJ.Menus.init()
    local root, frames = generate("MENU_MINIMAP_TRACKING", function(r)
      r:CreateButton(UI.UNCHECK_ALL[1])
      r:CreateButton(UI.MINIMAP_TRACKING_BANKER[1])
      r:CreateButton("Find Herbs")
    end)
    assert.are.equal("すべてのチェックを外す", frames[root.children[1]].fontString:GetText())
    assert.are.equal("銀行員", frames[root.children[2]].fontString:GetText())
    assert.are.equal("Find Herbs", frames[root.children[3]].fontString:GetText())
  end)

  it("the chat tab menu: Font Size's radios keep their number; the shortcuts menu in Japanese", function()
    WFJ.Menus.init()
    local size
    local root, frames = generate("MENU_FCF_TAB", function(r)
      size = r:CreateButton(UI.FONT_SIZE[1])
      size:CreateButton("12 pt")
    end)
    assert.are.equal("文字サイズ", frames[root.children[1]].fontString:GetText())
    assert.are.equal("12ポイント", frames[size.children[1]].fontString:GetText())
    local lang
    local s, sf = generate("MENU_CHAT_SHORTCUTS", function(r)
      r:CreateButton(UI.SAY_MESSAGE[1])
      lang = r:CreateButton("Language")
      lang:CreateButton("Common") -- a language name (GetLanguageByIndex): never listed
    end)
    assert.are.equal("発言", sf[s.children[1]].fontString:GetText())
    assert.are.equal("Common", sf[lang.children[1]].fontString:GetText())
  end)

  it("the world map filter: title and entries in Japanese; each entry owns its description tooltip", function()
    WFJ.Menus.init()
    local root, frames = generate("MENU_WORLD_MAP_TRACKING", function(r)
      r:CreateButton(UI.WORLD_MAP_FILTER_LABEL_SHOW[1])
      r:CreateButton(UI.SHOW_QUEST_LEVELS[1])
    end)
    assert.are.equal("表示：", frames[root.children[1]].fontString:GetText())
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

  it("a role radio keeps its icon; the loot opt-out shows Yes / No in Japanese; hovers are registered",
    function()
      WFJ.Menus.init()
      local icon = "|A:groupfinder-icon-role-micro-tank:16:16:0:0|a"
      local role
      local root, frames = generate("MENU_UNIT_SELF", function(r)
        r:CreateButton("Me") -- the title: the player's name
        r:CreateButton(UI.LOOT_GROUP_LOOT[1])
        r:CreateButton(string.format(UI.OPT_OUT_LOOT_TITLE[1], UI.NO[1]))
        role = r:CreateButton(UI.SET_ROLE[1])
        role:CreateButton(icon .. " " .. UI.TANK[1])
        role:CreateButton(UI.NO_ROLE[1])
      end, { name = "Me" })
      local e = root.children
      assert.are.equal("Me", frames[e[1]].fontString:GetText())
      assert.are.equal("戦利品：グループ", frames[e[2]].fontString:GetText())
      assert.are.equal("戦利品をパス：いいえ", frames[e[3]].fontString:GetText())
      assert.are.equal("役割を設定", frames[e[4]].fontString:GetText())
      assert.are.equal(icon .. " タンク", frames[role.children[1]].fontString:GetText())
      assert.are.equal("役割なし", frames[role.children[2]].fontString:GetText())
      assert.is_true(WFJ.HelpTooltip.registered(frames[e[2]]))
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      assert.are.equal(icon .. " Tank", frames[role.children[1]].fontString:GetText())
      Stub.keys.alt = false; WFJ.Modifier.refresh()
    end)

  it("one entry per sweep tag in Japanese; names beside them stay as written", function()
    WFJ.Menus.init()
    local cases = {
      { "MENU_EDIT_MODE_MANAGER", { "Modern", UI.HUD_EDIT_MODE_IMPORT_LAYOUT[1] }, { "Modern", "インポート" } },
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
      local root, frames = generate(c[1], function(r) for _, t in ipairs(c[2]) do r:CreateButton(t) end end)
      for i, want in ipairs(c[3]) do assert.are.equal(want, frames[root.children[i]].fontString:GetText(), c[1]) end
    end
  end)

  it("an AddOn entry's menu keeps its title (the addon's title) even when it is a dictionary word",
    function()
      WFJ.Menus.init()
      local root, frames = generate("MENU_ADDON_LIST_ENTRY", function(r)
        r:CreateButton(UI.ALL[1]) -- an addon titled "All"
        r:CreateButton(UI.ADDON_LIST_RESET_TO_DEFAULT[1])
      end)
      assert.are.equal("All", frames[root.children[1]].fontString:GetText())
      assert.are.equal("初期設定に戻す", frames[root.children[2]].fontString:GetText())
    end)

  it("the untagged Options and Edit Mode dropdowns, through their RegisterMenu", function()
    local function dropdown()
      local d = {}
      function d:RegisterMenu(root) self.menuDescription = root end
      return d
    end
    local settings = { InitDropdown = function() end }
    _G.Settings = settings
    local editRow = { Dropdown = dropdown() }
    _G.EditModeSettingDropdownMixin = { SetupSetting = function() end }
    WFJ.Compat.init(function(name) return _G[name] end)
    WFJ.Menus.init()
    assert.are.equal(2, WFJ.MenusUntagged.init())
    local options = dropdown()
    settings.InitDropdown(options)
    _G.EditModeSettingDropdownMixin.SetupSetting(editRow)
    local root = element(nil)
    root:CreateButton(UI.ANTIALIASING_FXAA_LOW[1])
    root:CreateButton("Friz Quadrata TT") -- a font name: no key
    root:CreateButton(UI.RAID[1]) -- a dictionary word outside the window's keys
    options:RegisterMenu(root)
    local frames = open(root)
    assert.are.equal("FXAA 低", frames[root.children[1]].fontString:GetText())
    assert.are.equal("Friz Quadrata TT", frames[root.children[2]].fontString:GetText())
    assert.are.equal("Raid", frames[root.children[3]].fontString:GetText())
    local edit = element(nil)
    edit:CreateButton(UI.HIGH[1])
    editRow.Dropdown:RegisterMenu(edit)
    assert.are.equal("高", open(edit)[edit.children[1]].fontString:GetText())
    -- hooked once per dropdown, however often the client sets it up
    assert.is_false(WFJ.MenusUntagged.hookDropdown(options, "SETTINGS_DROPDOWN"))
    _G.Settings, _G.EditModeSettingDropdownMixin = nil, nil
  end)
end)
