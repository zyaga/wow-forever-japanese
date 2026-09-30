-- UI/ChatConfig.lua over a ChatConfigFrame replayed from camelot
-- blizzard_chatframe/mainline/chatconfigframe.lua (ChatConfig_CreateCheckboxes :819–892, _UpdateCheckboxes
-- :1018–1098, _CreateTieredCheckboxes :894–975, _CreateColorSwatches :977–1016, ChatConfigCategoryFrame_Refresh
-- :2182–2224, ChatTabManager:UpdateTabDisplay :2391–2427) and chatconfigframe.xml. Channel names, chat window names
-- and a combat log filter's name stay English. Client writes go to `fs.text`.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/ChatConfig.lua"

-- Forever GlobalStrings (build 1.60.1.69913) → a test Japanese
local RESTRICT = "|cnRED_FONT_COLOR:You can't edit chat settings while chat is disabled.|r\r\n"
  .. "|cnGREEN_FONT_COLOR:<Shift Click to View Options>|r"
local UI = {
  -- the chat-left check buttons' tooltip while chat is disabled (chatconfigframe.lua:2342–2352); its
  -- named-colour markup is part of the English and kept in the Japanese
  RESTRICT_CHAT_CONFIG_TOOLTIP = { RESTRICT, "|cnRED_FONT_COLOR:チャットが無効の間はチャット設定を編集できません。|r\r\n"
    .. "|cnGREEN_FONT_COLOR:<Shiftクリックでオプションを表示>|r" },
  CHAT = { "Chat", "チャット" }, COMBAT = { "Combat", "戦闘" }, GLOBAL_CHANNELS = { "Channels", "チャンネル" },
  OTHER = { "Other", "その他" }, SETTINGS = { "Settings", "設定" }, COLOR = { "Color", "色" },
  PLAYER_MESSAGES = { "Player Messages", "プレイヤーメッセージ" }, SAY = { "Say", "発言" },
  PARTY_LEADER = { "Party Leader", "パーティーリーダー" }, GUILD_CHAT = { "Guild Chat", "ギルドチャット" },
  CHAT_CONFIG_CHANNEL_SETTINGS_TITLE_WITH_DRAG_INSTRUCTIONS = { "Channels |cff808080(Drag to Reorder)|r",
    "チャンネル |cff808080(ドラッグで並べ替え)|r" },
  DONE_BY = { "Done By:", "実行者:" }, COMBATLOG_FILTER_STRING_ME = { "Me", "自分" },
  COMBATLOG_FILTER_STRING_CUSTOM_UNIT = { "Custom Unit", "カスタムユニット" },
  -- one English, two senses: the combat log's unit filter owns 味方 (UIStrings.OWN); the friends list is フレンド
  COMBATLOG_FILTER_STRING_FRIENDLY_UNITS = { "Friends", "味方" }, FRIENDS = { "Friends", "フレンド" },
  MELEE = { "Melee", "近接" }, DAMAGE = { "Damage", "ダメージ" }, MISSES = { "Misses", "ミス" },
  MELEE_COMBATLOG_TOOLTIP = { "Shows natural melee swings.", "通常の近接攻撃を表示します。" },
  SWING_MISSED_COMBATLOG_TOOLTIP = { "Show melee swings that do not deal damage.",
    "ダメージを与えなかった近接攻撃を表示します。" },
  UNIT_COLORS = { "Unit Colors:", "ユニットの色:" }, MESSAGE_SOURCES = { "Message Sources", "メッセージの発信元" },
  DELETE = { "Delete", "削除" }, MISCELLANEOUS = { "Miscellaneous", "その他" }, FILTER_NAME = { "Filter Name", "フィルター名" },
  SHOW_TIMESTAMP = { "Show Timestamp", "タイムスタンプを表示" },
  TIMESTAMP_COMBATLOG_TOOLTIP = { "Display the timestamp for combat log messages.",
    "戦闘ログのメッセージに時刻を表示します。" },
  MOVE_FILTER_UP = { "Move Filter Up", "フィルターを上へ" },
  CHARACTER_SPECIFIC_SETTINGS = { "Character Specific Settings", "キャラクター別の設定" },
  CHATCONFIG_HEADER = { "%s Config", "%sの設定" }, TEXT_TO_SPEECH_CONFIG = { "Text To Speech Config", "読み上げの設定" },
  TEXT_TO_SPEECH = { "Text To Speech", "読み上げ" }, OKAY = { "Okay", "OK" },
  GENERAL = { "General", "一般" }, -- a word a channel or a chat window may be called
}

local made = {}
local function en(key) return _G[key] end
local function named(name, value)
  _G[name] = value
  made[#made + 1] = name
  return value
end
local function frame(kind, name)
  local f = CreateFrame(kind, name)
  if name then made[#made + 1] = name end
  return f
end
local function text(name, s)
  made[#made + 1] = name
  return Stub.namedFontString(name, s or "")
end
local function button(name, s)
  made[#made + 1] = name
  return Stub.button(name, s)
end

local C = {} -- replayed client state

local function pool()
  local p = { active = {}, inactive = {} }
  function p.Acquire(self)
    local f = table.remove(self.inactive) or Stub.button(nil, "")
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

local function rowText(value)
  local t = value.text
  if type(t) == "function" then t = t() end
  return t or en(value.type)
end

local function installChatConfig()
  local config = frame("Frame", "ChatConfigFrame")
  config.Header = { Text = Stub.fontString("") }
  local manager = CreateFrame("Frame")
  manager.name = "ChatTabManager"
  config.ChatTabManager = manager
  manager.tabPool = pool()
  function manager.UpdateTabDisplay(self) -- lua:2391–2427, SetChatWindowIndex :2363–2370
    self.tabPool:ReleaseAll()
    for _, name in ipairs(C.windows) do self.tabPool:Acquire():SetText(name) end
  end
  for _, n in ipairs({ "ChatConfigChatSettingsLeft", "ChatConfigChannelSettingsLeft",
    "CombatConfigMessageSourcesDoneBy", "CombatConfigMessageTypesLeft", "CombatConfigColorsUnitColors" }) do
    frame("Frame", n)
    text(n .. "Title")
  end
  text("ChatConfigChatSettingsLeftColorHeader", en("COLOR"))
  button("ChatConfigCategoryFrameButton1", en("CHAT"))
  button("ChatConfigCategoryFrameButton2", en("COMBAT"))
  button("ChatConfigCategoryFrameButton3", en("GLOBAL_CHANNELS"))
  button("ChatConfigCombatSettingsFiltersDeleteButton", en("DELETE"))
  button("CombatConfigTab1", en("MESSAGE_SOURCES"))
  button("ChatConfigFrameOkayButton", en("OKAY"))
  frame("Frame", "CombatConfigMessageTypesMisc"):addRegion(Stub.fontString(en("MISCELLANEOUS")))
  local edit = frame("EditBox", "CombatConfigSettingsNameEditBox")
  edit:addRegion(Stub.fontString(en("FILTER_NAME")))
  edit.text = "General" -- a filter the player named like a dictionary word
  text("CombatConfigFormattingShowTimeStampText", en("SHOW_TIMESTAMP"))
  frame("CheckButton", "CombatConfigFormattingShowTimeStamp")
  frame("Button", "ChatConfigMoveFilterUpButton")
  text("CombatConfigColorsExampleString1", "General")
  local specific = frame("CheckButton", "TextToSpeechCharacterSpecificButton")
  specific.Text = Stub.fontString("|cffffffff" .. en("CHARACTER_SPECIFIC_SETTINGS") .. "|r")

  named("ChatConfig_CreateCheckboxes", function(f, tbl, _, title)
    local stem = f:GetName() .. "Checkbox"
    f.checkBoxTable = tbl
    if title then _G[f:GetName() .. "Title"].text = title end
    for i, value in ipairs(tbl) do
      if not _G[stem .. i] then
        frame("Frame", stem .. i)
        frame("CheckButton", stem .. i .. "Check")
        text(stem .. i .. "CheckText")
      end
      _G[stem .. i .. "CheckText"].text = rowText(value)
    end
  end)
  named("ChatConfig_UpdateCheckboxes", function(f)
    local stem = f:GetName() .. "Checkbox"
    for i, value in ipairs(f.checkBoxTable) do
      if type(value.text) == "function" then _G[stem .. i .. "CheckText"].text = value.text() end
    end
  end)
  named("ChatConfig_CreateTieredCheckboxes", function(f, tbl)
    local stem = f:GetName() .. "Checkbox"
    for i, value in ipairs(tbl) do
      frame("CheckButton", stem .. i)
      text(stem .. i .. "Text", rowText(value))
      for k, sub in ipairs(value.subTypes or {}) do
        frame("CheckButton", stem .. i .. "_" .. k)
        text(stem .. i .. "_" .. k .. "Text", rowText(sub))
      end
    end
  end)
  named("ChatConfig_CreateColorSwatches", function(f, tbl, _, title)
    local stem = f:GetName() .. "Swatch"
    if title then _G[f:GetName() .. "Title"].text = title end
    for i, value in ipairs(tbl) do
      frame("Frame", stem .. i)
      text(stem .. i .. "Text", rowText(value))
    end
  end)
  named("ChatConfigCategoryFrame_Refresh", function()
    config.Header.Text.text = C.tts and en("TEXT_TO_SPEECH_CONFIG") or string.format(en("CHATCONFIG_HEADER"), C.window)
  end)
  return config
end

local CHAT_LEFT = { { type = "SAY" }, { text = "Guild Chat", type = "GUILD" }, { type = "PARTY_LEADER" } }
local CHANNELS = { { text = "1.General" }, { text = "General" } }
local TIERED = { { text = "Melee", subTypes = { { text = "Damage" }, { text = "Misses" } } } }

describe("the chat configuration window on Forever", function()
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

  local function load()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    SS = WFJ.SurfaceState
    -- the Core/UIStrings grants this surface needs: a chat window's name is a verbatim argument, the
    -- character-specific label arrives inside a colour
    WFJ.UIStrings.ARGS.CHATCONFIG_HEADER = { [1] = "text" }
    WFJ.UIStrings.LABELS.CHARACTER_SPECIFIC_SETTINGS = "wrapped"
    H.uiSetup(WFJ, UI)
    C.windows, C.window, C.tts, C.custom = { "General", "Combat Log", "Text To Speech" }, "General", false, false
  end

  -- createdFirst: the client built its rows (PLAYER_ENTERING_WORLD) before the module's init, or after it.
  local function setup(createdFirst)
    load()
    installChatConfig()
    local function create()
      _G.ChatConfig_CreateCheckboxes(_G.ChatConfigChatSettingsLeft, CHAT_LEFT, nil, en("PLAYER_MESSAGES"))
      _G.ChatConfig_CreateCheckboxes(_G.ChatConfigChannelSettingsLeft, CHANNELS, nil,
        en("CHAT_CONFIG_CHANNEL_SETTINGS_TITLE_WITH_DRAG_INSTRUCTIONS"))
      _G.ChatConfig_CreateCheckboxes(_G.CombatConfigMessageSourcesDoneBy, { { text = function()
        return C.custom and en("COMBATLOG_FILTER_STRING_CUSTOM_UNIT") or en("COMBATLOG_FILTER_STRING_ME")
      end }, { text = en("COMBATLOG_FILTER_STRING_FRIENDLY_UNITS") } }, nil, en("DONE_BY"))
      _G.ChatConfig_CreateTieredCheckboxes(_G.CombatConfigMessageTypesLeft, TIERED)
      _G.ChatConfig_CreateColorSwatches(_G.CombatConfigColorsUnitColors, { { text = "Me" }, { text = "Friends" } }, nil,
        en("UNIT_COLORS"))
    end
    if createdFirst then create() end
    WFJ.Labels.forbidNames(WFJ.ChatConfig.NEVER_TOUCH)
    assert.is_true(WFJ.ChatConfig.init())
    if not createdFirst then create() end
  end

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    for _, name in ipairs(made) do _G[name] = nil end
    made = {}
  end)

  for _, order in ipairs({ { true, "rows built before init" }, { false, "rows built after init" } }) do
    describe(order[2], function()
      before_each(function() setup(order[1]) end)

      it("titles, rows, tiered rows and swatches are Japanese; Alt shows the client's English", function()
        if order[1] then _G.ChatConfigFrame:Show() end
        assert.are.equal("プレイヤーメッセージ", _G.ChatConfigChatSettingsLeftTitle:GetText())
        assert.are.equal("発言", _G.ChatConfigChatSettingsLeftCheckbox1CheckText:GetText())
        assert.are.equal("ギルドチャット", _G.ChatConfigChatSettingsLeftCheckbox2CheckText:GetText())
        assert.are.equal("パーティーリーダー", _G.ChatConfigChatSettingsLeftCheckbox3CheckText:GetText())
        assert.are.equal("実行者:", _G.CombatConfigMessageSourcesDoneByTitle:GetText())
        assert.are.equal("近接", _G.CombatConfigMessageTypesLeftCheckbox1Text:GetText())
        assert.are.equal("ミス", _G.CombatConfigMessageTypesLeftCheckbox1_2Text:GetText())
        assert.are.equal("ユニットの色:", _G.CombatConfigColorsUnitColorsTitle:GetText())
        assert.are.equal("自分", _G.CombatConfigColorsUnitColorsSwatch1Text:GetText())
        alt(true)
        assert.are.equal("Say", _G.ChatConfigChatSettingsLeftCheckbox1CheckText:GetText())
        assert.are.equal("Misses", _G.CombatConfigMessageTypesLeftCheckbox1_2Text:GetText())
        alt(false)
        assert.are.equal("発言", _G.ChatConfigChatSettingsLeftCheckbox1CheckText:GetText())
      end)

      it("a channel frame shows its title only: channel names are never touched", function()
        if order[1] then _G.ChatConfigFrame:Show() end
        assert.are.equal("チャンネル |cff808080(ドラッグで並べ替え)|r", _G.ChatConfigChannelSettingsLeftTitle:GetText())
        assert.are.equal("1.General", _G.ChatConfigChannelSettingsLeftCheckbox1CheckText:GetText())
        assert.are.equal("General", _G.ChatConfigChannelSettingsLeftCheckbox2CheckText:GetText())
        assert.is_true(unrecorded(_G.ChatConfigChannelSettingsLeftCheckbox2CheckText))
        assert.is_false(WFJ.HelpTooltip.registered(_G.ChatConfigChannelSettingsLeftCheckbox2Check))
      end)

      it("the combat log's unit rows show friendly units as 味方; Friends elsewhere is the friends list", function()
        if order[1] then _G.ChatConfigFrame:Show() end
        assert.are.equal("味方", _G.CombatConfigMessageSourcesDoneByCheckbox2CheckText:GetText())
        assert.are.equal("味方", _G.CombatConfigColorsUnitColorsSwatch2Text:GetText())
        assert.are.equal("FRIENDS", (WFJ.UIIndex:match("Friends")))
        alt(true)
        assert.are.equal("Friends", _G.CombatConfigMessageSourcesDoneByCheckbox2CheckText:GetText())
        alt(false)
      end)

      it("a row whose text is a function follows ChatConfig_UpdateCheckboxes", function()
        if order[1] then _G.ChatConfigFrame:Show() end
        assert.are.equal("自分", _G.CombatConfigMessageSourcesDoneByCheckbox1CheckText:GetText())
        C.custom = true
        _G.ChatConfig_UpdateCheckboxes(_G.CombatConfigMessageSourcesDoneBy)
        assert.are.equal("カスタムユニット", _G.CombatConfigMessageSourcesDoneByCheckbox1CheckText:GetText())
      end)
    end)
  end

  it("static labels, the unnamed labels and the colour-wrapped label are Japanese on show", function()
    setup(true)
    _G.ChatConfigFrame:Show()
    assert.are.equal("チャット", _G.ChatConfigCategoryFrameButton1:GetText())
    assert.are.equal("戦闘", _G.ChatConfigCategoryFrameButton2:GetText())
    assert.are.equal("チャンネル", _G.ChatConfigCategoryFrameButton3:GetText())
    assert.are.equal("色", _G.ChatConfigChatSettingsLeftColorHeader:GetText())
    assert.are.equal("削除", _G.ChatConfigCombatSettingsFiltersDeleteButton:GetText())
    assert.are.equal("メッセージの発信元", _G.CombatConfigTab1:GetText())
    assert.are.equal("タイムスタンプを表示", _G.CombatConfigFormattingShowTimeStampText:GetText())
    assert.are.equal("その他", (_G.CombatConfigMessageTypesMisc:GetRegions()):GetText())
    assert.are.equal("フィルター名", (_G.CombatConfigSettingsNameEditBox:GetRegions()):GetText())
    assert.are.equal("|cffffffffキャラクター別の設定|r", _G.TextToSpeechCharacterSpecificButton.Text:GetText())
    assert.are.equal("OK", _G.ChatConfigFrameOkayButton:GetText())
  end)

  it("never touched: the filter name EditBox and the example combat line, even holding a dictionary word", function()
    setup(true)
    _G.ChatConfigFrame:Show()
    assert.are.equal("General", _G.CombatConfigSettingsNameEditBox:GetText())
    assert.are.equal("General", _G.CombatConfigColorsExampleString1:GetText())
    assert.is_true(unrecorded(_G.CombatConfigColorsExampleString1))
    assert.are.equal(0, WFJ.Labels.show("chatconfig", "x", _G.CombatConfigColorsExampleString1))
  end)

  it("the header keeps the chat window's name; the window tabs translate only the text-to-speech tab", function()
    setup(true)
    _G.ChatConfigCategoryFrame_Refresh()
    assert.are.equal("Generalの設定", _G.ChatConfigFrame.Header.Text:GetText())
    C.tts = true
    _G.ChatConfigCategoryFrame_Refresh()
    assert.are.equal("読み上げの設定", _G.ChatConfigFrame.Header.Text:GetText())
    _G.ChatConfigFrame.ChatTabManager:UpdateTabDisplay()
    local tabs = {}
    for tab in _G.ChatConfigFrame.ChatTabManager.tabPool:EnumerateActive() do tabs[#tabs + 1] = tab:GetText() end
    assert.are.same({ "General", "Combat Log", "読み上げ" }, tabs) -- "General" is a dictionary word: a window's name
    C.windows = { "Text To Speech", "General" } -- the pool hands the widgets out again in another order
    _G.ChatConfigFrame.ChatTabManager:UpdateTabDisplay()
    tabs = {}
    for tab in _G.ChatConfigFrame.ChatTabManager.tabPool:EnumerateActive() do tabs[#tabs + 1] = tab:GetText() end
    table.sort(tabs)
    assert.are.same({ "General", "読み上げ" }, tabs)
  end)

  it("a check button's tooltip and the move-filter tooltip are Japanese", function()
    setup(true)
    _G.ChatConfigFrame:Show()
    local tt = _G.GameTooltip
    tt:SetOwner(_G.CombatConfigMessageTypesLeftCheckbox1)
    tt:SetText(en("MELEE_COMBATLOG_TOOLTIP"))
    assert.are.equal("通常の近接攻撃を表示します。", _G.GameTooltipTextLeft1:GetText())
    tt:SetOwner(_G.CombatConfigMessageTypesLeftCheckbox1_2)
    tt:SetText(en("SWING_MISSED_COMBATLOG_TOOLTIP"))
    assert.are.equal("ダメージを与えなかった近接攻撃を表示します。", _G.GameTooltipTextLeft1:GetText())
    tt:SetOwner(_G.CombatConfigFormattingShowTimeStamp)
    tt:SetText(en("TIMESTAMP_COMBATLOG_TOOLTIP"))
    assert.are.equal("戦闘ログのメッセージに時刻を表示します。", _G.GameTooltipTextLeft1:GetText())
    tt:SetOwner(_G.ChatConfigMoveFilterUpButton)
    tt:SetText(en("MOVE_FILTER_UP"))
    assert.are.equal("フィルターを上へ", _G.GameTooltipTextLeft1:GetText())
    -- a chat-left check button while chat is disabled
    tt:SetOwner(_G.ChatConfigChatSettingsLeftCheckbox1Check)
    tt:SetText(RESTRICT)
    assert.are.equal("|cnRED_FONT_COLOR:チャットが無効の間はチャット設定を編集できません。|r\r\n"
      .. "|cnGREEN_FONT_COLOR:<Shiftクリックでオプションを表示>|r", _G.GameTooltipTextLeft1:GetText())
  end)

  it("hooks install once", function()
    setup(true)
    assert.is_false(WFJ.ChatConfig.init())
    assert.are.equal(1, #Stub.hooks["ChatConfig_CreateCheckboxes"])
    assert.are.equal(1, #Stub.hooks["ChatTabManager:UpdateTabDisplay"])
  end)

  it("client names bound to the wrong type degrade to untouched English with no error", function()
    load()
    installChatConfig()
    _G.ChatConfig_CreateCheckboxes(_G.ChatConfigChatSettingsLeft, CHAT_LEFT, nil, en("PLAYER_MESSAGES"))
    _G.ChatConfig_UpdateCheckboxes = "not a function"
    _G.ChatConfigFrame.ChatTabManager = 7
    _G.ChatConfigFrame.Header = "header"
    _G.ChatConfigCategoryFrameButton1 = 42
    _G.ChatConfigChatSettingsLeftTitle = true
    assert.has_no.errors(function() assert.is_true(WFJ.ChatConfig.init()) end)
    assert.has_no.errors(function()
      WFJ.ChatConfig.onFamily(nil); WFJ.ChatConfig.onFamily({})
      WFJ.ChatConfig.onFamily({ GetName = function() return 5 end })
      WFJ.ChatConfig.onHeader(); WFJ.ChatConfig.onWindowTabs(); WFJ.ChatConfig.onShow()
    end)
    assert.are.equal("発言", _G.ChatConfigChatSettingsLeftCheckbox1CheckText:GetText()) -- the rest still works
    assert.is_nil(Stub.hooks["ChatConfig_UpdateCheckboxes"])
  end)

  it("no ChatConfigFrame → init is false and nothing is touched", function()
    load()
    assert.has_no.errors(function() assert.is_false(WFJ.ChatConfig.init()) end)
  end)
end)
