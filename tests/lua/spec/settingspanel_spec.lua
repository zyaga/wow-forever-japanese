-- The Options window on Forever: UI/SettingsPanel.lua over a SettingsPanel replayed from
-- blizzard_settings_shared (blizzard_settingspanel.lua:48–78, 875–971, 979–1024; blizzard_settingcontrols.lua:311–356;
-- blizzard_keybindings.lua:385–394; blizzard_categorylist.lua:94–97). Rows are pooled ScrollBox frames walked after
-- their initializer; addon pages, key names, unit names and the search box stay as the client wrote them.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local S = require("tests.lua.spec.stub_settings")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
for _, f in ipairs({ "UI/LabelTree.lua", "UI/TooltipLines.lua", "UI/SettingsKeys.lua", "UI/SettingsPanel.lua" }) do
  FILES[#FILES + 1] = f
end

-- Forever GlobalStrings (build 1.60.1.69913) → a test Japanese
local UI = {
  SETTINGS_TITLE = { "Options", "オプション" }, SETTINGS_CLOSE = { "Close", "閉じる" },
  SETTINGS_APPLY = { "Apply", "適用" }, SETTINGS_DEFAULTS = { "Defaults", "デフォルト" },
  SETTINGS_TAB_GAME = { "Game", "ゲーム" }, SETTINGS_TAB_ADDONS = { "AddOns", "アドオン" },
  SETTINGS_SEARCH_RESULTS = { "Results:", "検索結果:" }, KEY_BOUND = { "Key Bound Successfully", "キーを割り当てました" },
  GRAPHICS_LABEL = { "Graphics", "グラフィック" }, CONTROLS_LABEL = { "Controls", "操作" },
  SETTING_GROUP_SYSTEM = { "System", "システム" }, GRAPHICS_QUALITY = { "Graphics Quality", "グラフィック品質" },
  SHADOW_QUALITY = { "Shadow Quality", "影の品質" }, VIDEO_OPTIONS_LOW = { "Low", "低" },
  VIDEO_OPTIONS_HIGH = { "High", "高" },
  OPTION_TOOLTIP_SHADOW_QUALITY = { "Controls both the method and quality of shadows.", "影の描画方式と品質を設定します。" },
  VIDEO_OPTIONS_NEED_CLIENTRESTART = { "Changing this option requires a client restart",
    "この設定の変更にはクライアントの再起動が必要です" },
  -- the audio assist resource option around the player's power word (a dictionary word)
  CAA_SAY_PLAYER_RESOURCE_LABEL = { "Say Your %s", "自分の%sの読み上げ" }, MANA = { "Mana", "マナ" },
  BINDING_NAME_MOVEFORWARD = { "Move Forward", "前進" }, BINDING_HEADER_MOVEMENT = { "Movement Keys", "移動キー" },
  -- in the dictionary, and never shown here: not one of this window's keys / a key name / a player's name
  RAID = { "Raid", "レイド" }, KEY_SPACE = { "Space", "スペース" }, PREVIEW = { "Preview", "プレビュー" },
  -- an option's tooltip, shown inside the "<label>: <tooltip>" line
  VIDEO_OPTIONS_SHADOW_QUALITY_LOW = { "Blob shadows.", "簡易的な影。" },
  -- the muted-account paragraph (social.lua:21–29) and the recommended-value line (blizzard_settings.lua:468)
  OPTION_TOOLTIP_DISABLE_CHAT = { "Disables chat. You will not be able to send or receive messages.",
    "チャットを無効にします。メッセージの送受信ができなくなります。" },
  OPTION_TOOLTIP_DISABLE_CHAT_ACCOUNT_MUTE = { "To change this, first unmute your account.",
    "変更するには、まずアカウントのミュートを解除してください。" },
  VIDEO_OPTIONS_RECOMMENDED = { "Recommended", "推奨" },
  -- the combat audio alert's power-word labels and a graphics adapter's suffix (the adapter's name kept)
  -- (the label and MANA are above)
  CAA_SAY_PLAYER_RESOURCE_TOOLTIP = { "Says your %s when it crosses certain percentages. This setting is saved per "
    .. "talent specialization.", "%sが一定の割合を超えると読み上げます。この設定は専門化ごとに保存されます。" },
  GX_ADAPTER_EXTERNAL = { "%s (External)", "%s(外部)" },
  -- new on 1.60.1.70009: the Gamepad page (gamepad.lua:214, 275–280), a binding (bindings_camelot.xml:1226)
  -- and the chat option's age-restriction paragraph (social.lua:24–27)
  TARGETING_HEADER = { "Targeting", "ターゲティング" },
  GAMEPAD_SWAP_TARGET_MODIFIERS = { "Swap Target Modifier Sides", "ターゲット修飾キーの左右を入れ替え" },
  GAMEPAD_SWAP_TARGET_MODIFIERS_TOOLTIP = { "Switch sides of the two targeting modifiers, putting friendly targeting "
    .. "on the right side, and hostile targeting on the left side.",
    "2つのターゲット修飾キーの左右を入れ替え、友好ターゲットを右側、敵対ターゲットを左側にします。" },
  -- an Edit Mode checkbox now (editmodesettingdisplayinfo.lua:1522): never an Options key
  GAMEPAD_TOGGLE_COMPACT_ACTION_BAR = { "Use Compact Action Bar", "コンパクトなアクションバーを使用" },
  -- the Voice page's service dropdown and Discord settings checkbox (audio.lua:258–283)
  NEW_CAPS = { "NEW", "新規" }, -- the new-setting tag on the voice rows (camelot/newdefinitions.lua:1–4)
  VOICE_CHAT_SERVICE = { "Preferred Voice Chat Service", "優先するボイスチャットサービス" },
  VOICE_CHAT_SERVICE_LEGACY = { "Legacy", "レガシー" },
  VOICE_CHAT_USE_DISCORD_SETTINGS = { "Use Your Discord Settings", "Discordの設定を使用" },
  OPTION_TOOLTIP_VOICE_CHAT_USE_DISCORD_SETTINGS = { "Uses settings from your Discord account to control volume.",
    "Discordアカウントの設定で音量を調整します。" },
  BINDING_NAME_TOGGLECOOLDOWNVIEWERSETTINGS = { "Toggle Cooldown Settings", "クールダウン設定の切り替え" },
  OPTION_TOOLTIP_DISABLE_CHAT_AGE_RESTRICTED_MINOR = { "Chat and other social features are unavailable on accounts "
    .. "belonging to minors", "未成年者のアカウントでは、チャットやその他のソーシャル機能を利用できません" },
}

describe("the Options window on Forever", function()
  local WFJ, SS, panel, list, categories

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  local function unrecorded(widget)
    for _, bucket in pairs(SS.surfaces()) do
      for _, rec in pairs(bucket) do
        if rec.fs == widget then return false end
      end
    end
    return true
  end

  local function load()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    SS = WFJ.SurfaceState
    H.uiSetup(WFJ, UI)
  end

  before_each(function()
    load()
    panel = S.installSettingsPanel()
    list, categories = panel.Container.SettingsList.ScrollBox, panel.CategoryList.ScrollBox
    WFJ.Labels.forbidNames(WFJ.SettingsPanel.NEVER_TOUCH)
    assert.is_true(WFJ.SettingsPanel.init())
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    S.removeSettingsPanel()
  end)

  it("the title, the buttons and the two tabs translate at load and again after the panel re-shows", function()
    assert.are.equal("オプション", panel.NineSlice.Text:GetText())
    assert.are.equal("閉じる", panel.CloseButton:GetText())
    assert.are.equal("適用", panel.ApplyButton:GetText())
    assert.are.equal("デフォルト", panel.Container.SettingsList.Header.DefaultsButton:GetText())
    assert.are.equal("ゲーム", panel.GameTab.Text:GetText())
    assert.are.equal("アドオン", panel.AddOnsTab.Text:GetText())
    panel:Show() -- OnShow writes the title again (blizzard_settingspanel.lua:186)
    assert.are.equal("オプション", panel.NineSlice.Text:GetText())
    alt(true)
    assert.are.equal("Options", panel.NineSlice.Text:GetText())
    alt(false)
  end)

  it("rows are walked after their initializer: labels, section headers, dropdown values; pooled rows follow their text",
    function()
      local header, row = S.headerRow("Graphics Quality"), S.dropdownRow("Shadow Quality", "Low")
      list:initFrame(header, {})
      list:initFrame(row, {})
      assert.are.equal("グラフィック品質", header.Title:GetText())
      assert.are.equal("影の品質", row.Text:GetText())
      assert.are.equal("低", row.Control.Dropdown.Text:GetText())
      row.Control.Dropdown:select("High") -- the Menu system rewrites the text on a selection
      assert.are.equal("高", row.Control.Dropdown.Text:GetText())
      assert.are.equal(1, #Stub.hooks["?:UpdateText"])
      -- the pool reuses the row for another option, one that is not in the dictionary
      list:initFrame(row, {}, function(f) f.Text.text = "Some New Option"; f.Control.Dropdown:select("Ultra") end)
      assert.are.equal("Some New Option", row.Text:GetText())
      assert.are.equal("Ultra", row.Control.Dropdown.Text:GetText())
      assert.is_true(unrecorded(row.Text))
      assert.are.equal(1, #Stub.hooks["?:UpdateText"]) -- the dropdown is followed once, however often it is reused
    end)

  it("the resource option shows the power word in Japanese; another word in its place stays", function()
    local row = S.dropdownRow("Say Your Mana", "Low")
    list:initFrame(row, {})
    assert.are.equal("自分のマナの読み上げ", row.Text:GetText())
    list:initFrame(row, {}, function(f) f.Text.text = "Say Your Frostbolt" end) -- not a dictionary word
    assert.are.equal("Say Your Frostbolt", row.Text:GetText())
  end)

  it("a binding row: the binding's name and its section translate; the key buttons are key names and stay", function()
    local section, row = S.sectionRow("Movement Keys"), S.bindingRow("Move Forward", "Space", "W")
    list:initFrame(section, {})
    list:initFrame(row, {})
    assert.are.equal("移動キー", section.Button.Text:GetText())
    assert.are.equal("前進", row.Label:GetText())
    assert.are.equal("Space", row.Button1:GetText())
    assert.is_true(unrecorded(row.Button1.fontString))
  end)

  it("names stay: a slider's value, a preview's unit name, a word outside this window's keys, the search box",
    function()
    local slider, preview, other = S.sliderRow("Shadow Quality", "Low"), S.previewRow("Graphics"), S.checkboxRow("Raid")
    for _, row in ipairs({ slider, preview, other }) do list:initFrame(row, {}) end
    assert.are.equal("影の品質", slider.Text:GetText())
    assert.are.equal("Low", slider.SliderWithSteppers.RightText:GetText())
    assert.are.equal("Graphics", preview.RaidFrame.name:GetText()) -- a player called "Graphics"
    assert.are.equal("Raid", other.Text:GetText()) -- RAID is a dictionary word, not an Options key
    panel.SearchBox.Instructions.text = "Graphics"
    panel:Show()
    assert.are.equal("Graphics", panel.SearchBox.Instructions:GetText())
  end)

  it("search results: rows under a game category's header translate; rows under an addon's header stay", function()
    -- the result list the search builds (blizzard_settingspanel.lua:612–680): a header per category, then its rows
    local header = function(category)
      return { frameTemplate = "SettingsListSearchCategoryTemplate", data = { category = category } }
    end
    local gameRowData, addonRowData = { data = {} }, { data = {} }
    local elements = { header(S.category("Graphics", S.GAME)), gameRowData,
      header(S.category("MyAddon", S.ADDONS)), addonRowData }
    local provider = {}
    function provider.Find(_, i) return elements[i] end
    function provider.FindIndex(_, e) for i, x in ipairs(elements) do if x == e then return i end end end
    function list.GetDataProvider() return provider end
    panel.SearchBox.text = "shadow"
    local game, addon = S.dropdownRow("Shadow Quality", "Low"), S.dropdownRow("Shadow Quality", "Low")
    list:initFrame(game, gameRowData)
    list:initFrame(addon, addonRowData) -- another addon's option labelled like a Blizzard one
    assert.are.equal("影の品質", game.Text:GetText())
    assert.are.equal("Shadow Quality", addon.Text:GetText())
    assert.is_true(unrecorded(addon.Text))
    local stray = S.checkboxRow("Shadow Quality") -- a row the list's data does not hold: left as written
    list:initFrame(stray, { data = {} })
    assert.are.equal("Shadow Quality", stray.Text:GetText())
  end)

  it("the category list translates game categories and groups; an addon's category is its name", function()
    local group, game, addon = S.categoryRow("System"), S.categoryRow("Graphics"), S.categoryRow("Controls")
    categories:initFrame(group, { data = { label = "System" } })
    categories:initFrame(game, { data = { category = S.category("Graphics", S.GAME) } })
    categories:initFrame(addon, { data = { category = S.category("Controls", S.ADDONS) } }) -- an addon named "Controls"
    assert.are.equal("システム", group.Label:GetText())
    assert.are.equal("グラフィック", game.Label:GetText())
    assert.are.equal("Controls", addon.Label:GetText())
    assert.is_true(unrecorded(addon.Label))
  end)

  it("the list header follows DisplayLayout; an addon's page is left alone, header, rows and tooltip", function()
    panel:DisplayCategory(S.category("Graphics"))
    local title = panel.Container.SettingsList.Header.Title
    assert.are.equal("グラフィック", title:GetText())
    title.text = "Results:" -- the search writes the header, then DisplayLayout (blizzard_settingspanel.lua:730–732)
    panel:DisplayLayout()
    assert.are.equal("検索結果:", title:GetText())
    panel:DisplayCategory(S.category("Controls", S.ADDONS))
    assert.are.equal("Controls", title:GetText())
    local row = S.checkboxRow("Shadow Quality")
    list:initFrame(row, {})
    assert.are.equal("Shadow Quality", row.Text:GetText())
    S.optionTooltip(row.Tooltip, { "Shadow Quality" })
    assert.are.equal("Shadow Quality", _G.SettingsTooltipTextLeft1:GetText())
  end)

  it("the key-binding messages follow SetOutputText", function()
    panel:SetOutputText("Key Bound Successfully")
    assert.are.equal("キーを割り当てました", panel.OutputText:GetText())
    panel:SetOutputText(nil)
    assert.is_nil(panel.OutputText:GetText())
  end)

  it("SettingsTooltip: name, body and the restart notice translate; a composite option line stays; hide releases",
    function()
      local row = S.dropdownRow("Shadow Quality", "Low")
      S.optionTooltip(row.Tooltip, { "Shadow Quality", "Controls both the method and quality of shadows.", " ",
        "|cffffffffLow|r: |cffffd200Fast shadows|r", "Changing this option requires a client restart" })
      assert.are.equal("影の品質", _G.SettingsTooltipTextLeft1:GetText())
      assert.are.equal("影の描画方式と品質を設定します。", _G.SettingsTooltipTextLeft2:GetText())
      assert.are.equal("|cffffffffLow|r: |cffffd200Fast shadows|r", _G.SettingsTooltipTextLeft4:GetText())
      assert.are.equal("この設定の変更にはクライアントの再起動が必要です", _G.SettingsTooltipTextLeft5:GetText())
      assert.are.equal(2, _G.SettingsTooltip.calls.Show) -- the client's Show and one refit
      alt(true)
      assert.are.equal("Shadow Quality", _G.SettingsTooltipTextLeft1:GetText())
      alt(false)
      _G.SettingsTooltip:Hide()
      assert.are.equal(0, SS.count("settingspanel.tooltip"))
    end)

  it("an option's \"<label>: <tooltip>\" line shows both halves in Japanese, each colour kept", function()
    local row = S.dropdownRow("Shadow Quality", "Low")
    S.optionTooltip(row.Tooltip, { "Shadow Quality", " ", "|cffffffffLow|r: |cffffd200Blob shadows.|r",
      "|cff808080High|r:", "|cffffffffLow|r: |cffffd200Fast shadows|r" })
    assert.are.equal("|cffffffff低|r: |cffffd200簡易的な影。|r", _G.SettingsTooltipTextLeft3:GetText())
    assert.are.equal("|cff808080高|r:", _G.SettingsTooltipTextLeft4:GetText()) -- an option with no tooltip
    -- a tooltip half that is no dictionary entry leaves the whole line English
    assert.are.equal("|cffffffffLow|r: |cffffd200Fast shadows|r", _G.SettingsTooltipTextLeft5:GetText())
    alt(true)
    assert.are.equal("|cffffffffLow|r: |cffffd200Blob shadows.|r", _G.SettingsTooltipTextLeft3:GetText())
    alt(false)
  end)

  it("the red-wrapped muted-account paragraph and the recommended-value line translate, colour and value kept",
    function()
      local row = S.dropdownRow("Shadow Quality", "Low")
      local muted = "Disables chat. You will not be able to send or receive messages.\n\n"
        .. "|cffff2020To change this, first unmute your account.|r"
      S.optionTooltip(row.Tooltip, { "Shadow Quality", muted, "Recommended: |cffffffffHigh|r" })
      assert.are.equal("チャットを無効にします。メッセージの送受信ができなくなります。\n\n"
        .. "|cffff2020変更するには、まずアカウントのミュートを解除してください。|r", _G.SettingsTooltipTextLeft2:GetText())
      assert.are.equal("推奨: |cffffffffHigh|r", _G.SettingsTooltipTextLeft3:GetText())
      alt(true)
      assert.are.equal(muted, _G.SettingsTooltipTextLeft2:GetText())
      assert.are.equal("Recommended: |cffffffffHigh|r", _G.SettingsTooltipTextLeft3:GetText())
      alt(false)
    end)

  it("a power-word option and its tooltip, and an adapter name with its suffix (the name kept)", function()
    local row = S.checkboxRow("Say Your Mana")
    list:initFrame(row, {})
    assert.are.equal("自分のマナの読み上げ", row.Text:GetText())
    S.optionTooltip(row.Tooltip, { "Say Your Mana", "Says your Mana when it crosses certain percentages. This setting "
      .. "is saved per talent specialization." })
    assert.are.equal("マナが一定の割合を超えると読み上げます。この設定は専門化ごとに保存されます。",
      _G.SettingsTooltipTextLeft2:GetText())
    local gpu = S.dropdownRow("Shadow Quality", "NVIDIA GeForce RTX 4070 (External)")
    list:initFrame(gpu, {})
    assert.are.equal("NVIDIA GeForce RTX 4070(外部)", gpu.Control.Dropdown.Text:GetText())
    alt(true)
    assert.are.equal("Say Your Mana", row.Text:GetText())
    assert.are.equal("NVIDIA GeForce RTX 4070 (External)", gpu.Control.Dropdown.Text:GetText())
    alt(false)
  end)

  it("the Gamepad page's Targeting section, its options and tooltip, and the cooldown settings binding",
    function()
      local header = S.headerRow("Targeting")
      local swap, compact = S.checkboxRow("Swap Target Modifier Sides"), S.checkboxRow("Use Compact Action Bar")
      local binding = S.bindingRow("Toggle Cooldown Settings", "Space", "W")
      for _, row in ipairs({ header, swap, compact, binding }) do list:initFrame(row, {}) end
      assert.are.equal("ターゲティング", header.Title:GetText())
      assert.are.equal("ターゲット修飾キーの左右を入れ替え", swap.Text:GetText())
      assert.are.equal("Use Compact Action Bar", compact.Text:GetText()) -- Edit Mode's word, not this window's
      assert.are.equal("クールダウン設定の切り替え", binding.Label:GetText())
      S.optionTooltip(swap.Tooltip, { "Swap Target Modifier Sides", "Switch sides of the two targeting modifiers, "
        .. "putting friendly targeting on the right side, and hostile targeting on the left side." })
      assert.are.equal("2つのターゲット修飾キーの左右を入れ替え、友好ターゲットを右側、敵対ターゲットを左側にします。",
        _G.SettingsTooltipTextLeft2:GetText())
      alt(true)
      assert.are.equal("Swap Target Modifier Sides", swap.Text:GetText())
      assert.are.equal("Toggle Cooldown Settings", binding.Label:GetText())
      assert.are.equal("Switch sides of the two targeting modifiers, putting friendly targeting on the right side, "
        .. "and hostile targeting on the left side.", _G.SettingsTooltipTextLeft2:GetText())
      alt(false)
    end)

  it("the Voice page's service dropdown, its Discord settings checkbox and tooltip; Alt shows English", function()
    local service = S.dropdownRow("Preferred Voice Chat Service", "Legacy")
    local discord = S.checkboxRow("Use Your Discord Settings")
    local other = S.dropdownRow("Preferred Voice Chat Service", "Some Other Service")
    local tag = S.node("Frame", nil, service, "NewFeature") -- NewFeatureLabelTemplate: Label and BGLabel
    S.label(tag, "Label", "NEW")
    for _, row in ipairs({ service, discord, other }) do list:initFrame(row, {}) end
    assert.are.equal("新規", tag.Label:GetText())
    assert.are.equal("優先するボイスチャットサービス", service.Text:GetText())
    assert.are.equal("レガシー", service.Control.Dropdown.Text:GetText())
    assert.are.equal("Discordの設定を使用", discord.Text:GetText())
    assert.are.equal("Some Other Service", other.Control.Dropdown.Text:GetText())
    S.optionTooltip(discord.Tooltip, { "Use Your Discord Settings",
      "Uses settings from your Discord account to control volume." })
    assert.are.equal("Discordアカウントの設定で音量を調整します。", _G.SettingsTooltipTextLeft2:GetText())
    alt(true)
    assert.are.equal("Preferred Voice Chat Service", service.Text:GetText())
    assert.are.equal("Legacy", service.Control.Dropdown.Text:GetText())
    assert.are.equal("Uses settings from your Discord account to control volume.",
      _G.SettingsTooltipTextLeft2:GetText())
    alt(false)
  end)

  it("the chat option's red-wrapped age-restriction paragraph translates, colour kept", function()
    local row = S.checkboxRow("Shadow Quality")
    local minor = "Disables chat. You will not be able to send or receive messages.\n\n"
      .. "|cffff2020Chat and other social features are unavailable on accounts belonging to minors|r"
    S.optionTooltip(row.Tooltip, { "Shadow Quality", minor })
    assert.are.equal("チャットを無効にします。メッセージの送受信ができなくなります。\n\n"
      .. "|cffff2020未成年者のアカウントでは、チャットやその他のソーシャル機能を利用できません|r",
      _G.SettingsTooltipTextLeft2:GetText())
    alt(true)
    assert.are.equal(minor, _G.SettingsTooltipTextLeft2:GetText())
    alt(false)
  end)

  it("client names bound to the wrong type degrade to untouched English with no error", function()
    assert.has_no.errors(function()
      for _, bad in ipairs({ 42, "text", true }) do
        local row = S.dropdownRow("Shadow Quality", "Low")
        row.Text, row.Control.Dropdown.Text, row.Tooltip = bad, bad, bad
        row.GetChildren = function() return bad, row.Control end
        list:initFrame(row, bad)
        WFJ.SettingsPanel.onCategoryRow(WFJ.SettingsPanel, bad, bad)
        categories:initFrame(S.categoryRow("Graphics"), bad)
        WFJ.SettingsPanel.onRow(bad)
        panel.GetCurrentCategory = function() return bad end
        _G.Settings.CategorySet = bad
        panel:DisplayLayout()
      end
    end)
    load()
    S.removeSettingsPanel()
    local odd = S.installSettingsPanel()
    odd.Container.SettingsList.ScrollBox = 7
    assert.has_no.errors(function() assert.is_false(WFJ.SettingsPanel.init()) end)
    assert.are.equal("Options", odd.NineSlice.Text:GetText())
  end)

  it("hooks install once; a client without the panel is skipped without error", function()
    assert.is_false(WFJ.SettingsPanel.init())
    assert.are.equal(1, #Stub.hooks["SettingsPanel:DisplayLayout"])
    load()
    S.removeSettingsPanel()
    assert.has_no.errors(function() assert.is_false(WFJ.SettingsPanel.init()) end)
  end)
end)
