local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

-- Dropdown and context-menu entries through Menu.ModifyMenu initializers. A stub of the Menu system: ModifyMenu
-- stores the callback per tag; a generated menu is a tree of element descriptions whose initializers run on pooled
-- frames holding .fontString [verified: blizzard_menu/menu.lua:418–455, 2751–2788; menuvariants.lua:9–22].
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

  after_each(function() H.uiTeardown(); _G.Menu = nil; _G.EventRegistry = nil end)

  -- EventRegistry: RegisterCallback(event, fn, owner) → fn(owner, ...) on TriggerEvent. → the registry
  local function installRegistry()
    local registry = { calls = {} }
    function registry:RegisterCallback(event, fn, owner)
      self.calls[event] = self.calls[event] or {}
      table.insert(self.calls[event], { fn, owner })
    end
    function registry:TriggerEvent(event, ...)
      for _, c in ipairs(self.calls[event] or {}) do c[1](c[2], ...) end
    end
    _G.EventRegistry = registry
    return registry
  end

  -- A menu the client has built with no initializer of ours: its frame holds one element frame per entry, each with
  -- the client's English. → the menu frame, { [text] = element frame }
  local function builtMenu(texts)
    local kids, byText = {}, {}
    for i, text in ipairs(texts) do
      local frame = CreateFrame("Button")
      frame.fontString = Stub.fontString(text)
      frame.fontString.SetFont = function() error("Use of function 'SetFont' is disallowed. (Index)") end
      kids[i], byText[text] = frame, frame
    end
    local menu = { shown = true }
    function menu:IsShown() return self.shown end
    menu.GetNumChildren = function() return #kids end
    menu.GetChildren = function() return unpack(kids) end
    return menu, byText
  end

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

  it("a menu refresh that puts the client's font back keeps the Japanese in the bundled face", function()
    WFJ.Menus.init()
    local root, frames = generate("MENU_CONTAINER_FRAME_COMBINED", function(r)
      r:CreateButton(UI.BAG_NAME_BAG_1[1])
    end)
    local e = root.children[1]
    local fs = frames[e].fontString
    assert.are.equal("バッグ1", fs:GetText())
    -- a checkbox click refreshes the menu: the compositor sets each FontString to its default font object and runs
    -- the initializers again, the text still ours (blizzard_menu/menu.lua ReinitializeFrame, compositor.lua:66-74)
    fs.font = { path = "Fonts\\FRIZQT__.TTF", size = 12, flags = "" }
    for _, fn in ipairs(e.inits) do fn(frames[e], e) end
    assert.are.equal("バッグ1", fs:GetText())
    assert.are.equal(WFJ.Font.PATH, fs.font.path)
    release(frames)
  end)

  it("a menu refresh that resets the font and writes the English again gets the bundled face back", function()
    -- Blizzard's refresh, step by step from its source: ReinitializeFrame clears the compositor, which sets every
    -- FontString to its defaults, SetFontObject("GameFontHighlight") (blizzard_menu/menu.lua ReinitializeFrame,
    -- compositor.lua:66-74); then the initializers run again in order: the title's own writes the English with
    -- SetTextToFit (menutemplates.lua:294-300), then ours
    WFJ.Menus.init()
    local root, frames = generate("MENU_CONTAINER_FRAME_COMBINED", function(r)
      r:CreateButton(UI.BAG_NAME_BAG_1[1])
    end)
    local e = root.children[1]
    local fs = frames[e].fontString
    assert.are.equal(WFJ.Font.PATH, fs.font.path)
    fs.font = { path = "Fonts\\FRIZQT__.TTF", size = 12, flags = "" } -- the compositor's default font object
    fs:SetText(UI.BAG_NAME_BAG_1[1]) -- the client's initializer, the English again
    for _, fn in ipairs(e.inits) do fn(frames[e], e) end -- ours
    assert.are.equal("バッグ1", fs:GetText())
    assert.are.equal(WFJ.Font.PATH, fs.font.path)
    release(frames)
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
  it("no unit right-click menu gets a callback: its entries stay as the client wrote them", function()
    -- a unit popup checks each entry's IsEnabled (CheckInteractDistance, protected in combat) in the same pass as the
    -- element initializers (menutemplates.lua:105-112, unitpopupsharedutils.lua:195-205), so an addon initializer
    -- there taints the check
    WFJ.Menus.init()
    for tag in pairs(callbacks) do assert.is_nil(tag:find("^MENU_UNIT_"), tag) end
    assert.is_function(callbacks["MENU_CHAT_FRAME_CHANNEL"]) -- the other menus keep theirs
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

  it("the chat tab menu: Font Size's radios keep their number", function()
    WFJ.Menus.init()
    local size
    local root, frames = generate("MENU_FCF_TAB", function(r)
      size = r:CreateButton(UI.FONT_SIZE[1])
      size:CreateButton("12 pt")
    end)
    assert.are.equal("文字サイズ", frames[root.children[1]].fontString:GetText())
    assert.are.equal("12ポイント", frames[size.children[1]].fontString:GetText())
  end)

  it("the chat menu gets no initializer: its entries are written once the client reports it open", function()
    local registry = installRegistry()
    assert.is_true(WFJ.Menus.init())
    -- an initializer on this menu makes its picks run tainted, and a language picked from it then blocks chat
    assert.is_nil(WFJ.Menus.TAGS.MENU_CHAT_SHORTCUTS)
    assert.is_nil(callbacks.MENU_CHAT_SHORTCUTS)
    assert.is_table(WFJ.Menus.AFTER_OPEN.MENU_CHAT_SHORTCUTS)

    local menu, entry = builtMenu({ UI.SAY_MESSAGE[1], "/s", "Common" })
    registry:TriggerEvent("MenuProxy.OnShow", menu)
    assert.are.equal(UI.SAY_MESSAGE[1], entry[UI.SAY_MESSAGE[1]].fontString:GetText()) -- nothing until it is open
    registry:TriggerEvent("Menu.OpenMenuTag", "MENU_CHAT_SHORTCUTS")
    assert.are.equal("発言", entry[UI.SAY_MESSAGE[1]].fontString:GetText())
    assert.are.equal("/s", entry["/s"].fontString:GetText()) -- the slash command beside an entry
    assert.are.equal("Common", entry["Common"].fontString:GetText()) -- a language name: never listed
  end)

  -- The addon's writes on a text widget so far (the stub counts them).
  local function writes(fs) return fs.calls.addonSetText + fs.calls.addonSetFont end

  it("a closed chat menu lets go of its text widgets: the next menu to take one is never written", function()
    local registry = installRegistry()
    WFJ.Menus.init()
    local menu, entry = builtMenu({ UI.SAY_MESSAGE[1] })
    local pooled = entry[UI.SAY_MESSAGE[1]].fontString
    registry:TriggerEvent("MenuProxy.OnShow", menu)
    registry:TriggerEvent("Menu.OpenMenuTag", "MENU_CHAT_SHORTCUTS")
    assert.are.equal("発言", pooled:GetText())

    registry:TriggerEvent("MenuProxy.OnHide", menu) -- before the client hands the widgets back to the shared pool
    assert.are.equal(UI.SAY_MESSAGE[1], pooled:GetText()) -- the client's text is back on it
    local widget = WFJ.Labels.menuText(pooled) -- the adapter a menu record sits on
    for _, rec in pairs(WFJ.SurfaceState.records(WFJ.Menus.SURFACE)) do assert.are_not.equal(widget, rec.fs) end

    -- another menu takes the widget; its entry may even show the same English (a unit menu is never translated)
    for _, text in ipairs({ "Trade", UI.SAY_MESSAGE[1] }) do
      pooled:SetText(text)
      local before = writes(pooled)
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      Stub.keys.alt = false; WFJ.Modifier.refresh()
      WFJ.Render.refresh(WFJ.Menus.SURFACE)
      assert.are.equal(text, pooled:GetText())
      assert.are.equal(before, writes(pooled), text)
    end
    -- hiding it again, or a menu the addon never wrote, does nothing
    assert.are.equal(0, WFJ.Menus.onMenuHidden(nil, menu))
    assert.are.equal(0, WFJ.Menus.onMenuHidden(nil, (builtMenu({ "Trade" }))))
  end)

  it("a rebuild of the open chat menu moves its widgets to other frames: they are still let go", function()
    local registry = installRegistry()
    WFJ.Menus.init()
    local menu, entry = builtMenu({ UI.SAY_MESSAGE[1], "/s" })
    local say, slash = entry[UI.SAY_MESSAGE[1]], entry["/s"]
    local pooled = say.fontString
    registry:TriggerEvent("MenuProxy.OnShow", menu)
    registry:TriggerEvent("Menu.OpenMenuTag", "MENU_CHAT_SHORTCUTS")
    assert.are.equal("発言", pooled:GetText())
    say.fontString, slash.fontString = slash.fontString, say.fontString -- the pool hands them back in another order
    registry:TriggerEvent("MenuProxy.OnHide", menu)
    local widget = WFJ.Labels.menuText(pooled)
    for _, rec in pairs(WFJ.SurfaceState.records(WFJ.Menus.SURFACE)) do assert.are_not.equal(widget, rec.fs) end
  end)

  it("an error while writing an opened menu is recorded once and never raised", function()
    local registry = installRegistry()
    WFJ.Menus.init()
    WFJ.initErrors = nil
    local menu = builtMenu({ UI.SAY_MESSAGE[1] })
    menu.IsShown = function() error("boom") end
    registry:TriggerEvent("MenuProxy.OnShow", menu)
    registry:TriggerEvent("Menu.OpenMenuTag", "MENU_CHAT_SHORTCUTS")
    registry:TriggerEvent("Menu.OpenMenuTag", "MENU_CHAT_SHORTCUTS")
    assert.are.equal(1, #WFJ.initErrors)
    assert.are.equal("menus.afteropen", WFJ.initErrors[1].surface)
  end)

  it("the after-open path leaves other tags and hidden menus alone", function()
    local registry = installRegistry()
    WFJ.Menus.init()
    local menu, entry = builtMenu({ UI.SAY_MESSAGE[1] })
    registry:TriggerEvent("MenuProxy.OnShow", menu)
    registry:TriggerEvent("Menu.OpenMenuTag", "MENU_FCF_TAB") -- a tag translated by its initializers
    registry:TriggerEvent("Menu.OpenMenuTag", "MENU_UNIT_SELF") -- a tag the addon never touches
    assert.are.equal(UI.SAY_MESSAGE[1], entry[UI.SAY_MESSAGE[1]].fontString:GetText())
    menu.shown = false -- a menu shown earlier and since closed
    registry:TriggerEvent("Menu.OpenMenuTag", "MENU_CHAT_SHORTCUTS")
    assert.are.equal(UI.SAY_MESSAGE[1], entry[UI.SAY_MESSAGE[1]].fontString:GetText())
  end)

  it("the registry callbacks are placed once however often init runs", function()
    local registry = installRegistry()
    assert.is_true(WFJ.Menus.init())
    assert.is_true(WFJ.Menus.init())
    assert.are.equal(1, #registry.calls["MenuProxy.OnShow"])
    assert.are.equal(1, #registry.calls["Menu.OpenMenuTag"])
    assert.are.equal(1, #registry.calls["MenuProxy.OnHide"])
  end)

  it("with no event registry the tagged menus are still registered", function()
    assert.is_nil(_G.EventRegistry)
    assert.is_true(WFJ.Menus.init())
    assert.is_function(callbacks.MENU_FCF_TAB)
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

  it("the world map filter in gamepad UI mode: the map and quest log titles and the objectives checkbox", function()
    WFJ.Menus.init()
    local root, frames = generate("MENU_WORLD_MAP_TRACKING", function(r)
      r:CreateButton(UI.WORLD_MAP_FILTER_TITLE_SHOW_MAP[1])
      r:CreateButton(UI.WORLD_MAP_FILTER_TITLE_SHOW_QUEST_LOG[1])
      r:CreateButton(UI.QUEST_LOG_SHOW_OBJECTIVES[1])
      r:CreateButton(UI.RAID[1])
    end)
    local e = root.children
    assert.are.equal("マップに表示：", frames[e[1]].fontString:GetText())
    assert.are.equal("クエストログに表示：", frames[e[2]].fontString:GetText())
    assert.are.equal("クエスト目標を表示", frames[e[3]].fontString:GetText())
    assert.are.equal("Raid", frames[e[4]].fontString:GetText())
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal("Show Quest Objectives", frames[e[3]].fontString:GetText())
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
        local root, frames = generate(c[1], function(r) for _, k in ipairs(c[2]) do r:CreateButton(UI[k][1]) end end)
        for i, k in ipairs(c[2]) do assert.are.equal(UI[k][2], frames[root.children[i]].fontString:GetText(), k) end
        Stub.keys.alt = true; WFJ.Modifier.refresh()
        for i, k in ipairs(c[2]) do assert.are.equal(UI[k][1], frames[root.children[i]].fontString:GetText(), k) end
        Stub.keys.alt = false; WFJ.Modifier.refresh()
        release(frames)
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

  it("the untagged Options dropdowns through their RegisterMenu; Edit Mode's dropdowns are never reached", function()
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
    assert.are.equal(1, WFJ.MenusUntagged.init())
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
    assert.are.equal(UI.HIGH[1], open(edit)[edit.children[1]].fontString:GetText()) -- ADR-069
    -- hooked once per dropdown, however often the client sets it up
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
    local onMe = { RegisterMenu = function(self, r) self.menuDescription = r end }
    settings.InitDropdown(onMe)
    local root = element(nil)
    root:CreateButton(UI.COMBAT_TEXT_SHOW_DODGE_PARRY_MISS_TEXT[1])
    onMe:RegisterMenu(root)
    local frames = open(root)
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
    local onTarget = { RegisterMenu = function(self, r) self.menuDescription = r end }
    settings.InitDropdown(onTarget)
    local target = element(nil)
    target:CreateButton(UI.SHOW_DAMAGE_TEXT[1])
    target:CreateButton(UI.SHOW_TARGET_EFFECTS[1])
    onTarget:RegisterMenu(target)
    local shown = open(target)
    assert.are.equal("ダメージ", shown[target.children[1]].fontString:GetText())
    assert.are.equal("効果", shown[target.children[2]].fontString:GetText())
    _G.Settings = nil
  end)
end)
