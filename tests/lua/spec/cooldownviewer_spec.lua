-- UI/CooldownViewer.lua over the camelot-shaped replay in
-- stub_cooldownviewer.lua. Blizzard_CooldownViewer is a login addon (its TOC allows camelot), so there is one load
-- order: the frames exist when the addon initialises. Spell, sound and layout names stay English; a HUD item is
-- never read. Client writes go to `fs.text`.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local CV = require("tests.lua.spec.stub_cooldownviewer")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/CooldownViewer.lua"

-- Forever GlobalStrings (build 1.60.1.69913) → a test Japanese
local UI = {
  COOLDOWN_VIEWER_SETTINGS_TITLE = { "Cooldown Settings", "クールダウン設定" },
  COOLDOWN_VIEWER_SETTINGS_SEARCH_INSTRUCTIONS = { "Enter search text", "検索テキストを入力" },
  COOLDOWN_VIEWER_SETTINGS_TAB_SPELLS = { "Spells", "呪文" },
  COOLDOWN_VIEWER_SETTINGS_TAB_GROUP_AURAS = { "Group Buffs", "グループバフ" },
  COOLDOWN_VIEWER_SETTINGS_TAB_GROUP_AURAS_DISABLED_TOOLTIP = {
    "This feature is not available for your current specialization.", "現在の専門化ではこの機能を利用できません。" },
  COOLDOWN_VIEWER_SETTINGS_BUTTON_REVERT_CHANGES = { "Revert", "元に戻す" }, -- iconAfter
  COOLDOWN_VIEWER_SETTINGS_BUTTON_REVERT_CHANGES_TOOLTIP = { "Revert all layout changes since the last save",
    "最後の保存以降のレイアウト変更をすべて元に戻す" },
  COOLDOWN_VIEWER_SETTINGS_CATEGORY_ESSENTIAL = { "Essential Cooldowns", "主要クールダウン" },
  COOLDOWN_VIEWER_SETTINGS_CATEGORY_EQUIP_ACTIVE = { "Items", "アイテム" },
  COOLDOWN_VIEWER_SETTINGS_CATEGORY_NOT_IN_BAR = { "Not Displayed", "非表示" },
  GROUP_BUFF_FILTER_SECTION_SHOWN = { "Group Frame Buffs", "グループフレームのバフ" },
  GROUP_BUFF_FILTER_SECTION_HIDDEN = { "Not Displayed", "非表示" },
  COOLDOWN_VIEWER_SETTINGS_EMPTY_SLOT_TOOLTIP = { "Empty Slot", "空きスロット" },
  COOLDOWN_VIEWER_TOOLTIP_POTION_HEALTH_TITLE = { "Health Potion", "回復ポーション" },
  COOLDOWN_VIEWER_TOOLTIP_POTION_HEALTH_DESCRIPTION = { "Displays the shared cooldown when a Healing potion is used.",
    "回復ポーション使用時の共有クールダウンを表示します。" },
  COOLDOWN_VIEWER_TRINKET_AURA_TOOLTIP_LABEL = { "Trinket Aura", "トリンケットのオーラ" },
  COOLDOWN_VIEWER_SETTINGS_ALERT_DIALOG_TITLE = { "New Alert", "新しいアラート" },
  COOLDOWN_VIEWER_SETTINGS_ALERT_DIALOG_LABEL_TYPE = { "Type", "種類" },
  COOLDOWN_VIEWER_SETTINGS_ALERT_DIALOG_LABEL_EVENT = { "When", "タイミング" },
  COOLDOWN_VIEWER_SETTINGS_ALERT_DIALOG_LABEL_SOUND_TYPE = { "Sound Alert", "サウンドアラート" },
  COOLDOWN_VIEWER_SETTINGS_ALERT_DIALOG_LABEL_VISUAL_TYPE = { "Visual Alert", "ビジュアルアラート" },
  COOLDOWN_VIEWER_SETTINGS_ALERT_MENU_BUTTON_ADD_ALERT = { "Add Alert", "アラートを追加" },
  COOLDOWN_VIEWER_SETTINGS_ALERT_MENU_BUTTON_EDIT_EXISTING_ALERT = { "Apply Changes", "変更を適用" },
  COOLDOWN_VIEWER_SETTINGS_ALERT_TYPE_SOUND = { "Sound", "サウンド" },
  COOLDOWN_VIEWER_SETTINGS_ALERT_TYPE_VISUAL = { "Visual", "ビジュアル" },
  COOLDOWN_VIEWER_SETTINGS_ALERT_WHEN_AVAILABLE = { "Available", "使用可能時" },
  COOLDOWN_VIEWER_SETTINGS_ALERT_WHEN_ON_COOLDOWN = { "On Cooldown", "クールダウン開始時" },
  COOLDOWN_VIEWER_SETTINGS_ALERT_LABEL_SOUND_TYPE_TEXT_TO_SPEECH = { "Text to Speech", "テキスト読み上げ" },
  GROUP_BUFF_FILTER_VISUAL_ALERT_DIALOG_LABEL_VISUAL_TYPE = { "Visual Type", "ビジュアルの種類" },
  CDMVIS_FLASH = { "Flash", "フラッシュ" }, CDMVIS_FLASH_BLUE = { "Flash (Blue)", "フラッシュ (青)" },
  HUD_EDIT_MODE_SYSTEM_ESSENTIAL_COOLDOWNS = { "Essential Cooldowns", "主要クールダウン" },
  HUD_EDIT_MODE_SYSTEM_TRACKED_BUFFS = { "Tracked Buffs", "追跡中のバフ" },
  -- dictionary words from other windows that are also a sound's name, a spell's name or another system's label here
  ERROR_CAPS = { "Error", "エラー" }, GOLD = { "Gold", "ゴールド" }, CLICK_TO_EDIT = { "Click to Edit", "クリックで編集" },
}
local function ja(key) return UI[key][2] end
local function en(key) return UI[key][1] end

describe("the Cooldown Settings window on Forever", function()
  local WFJ, SS

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

  local function settings() return _G.CooldownViewerSettings end
  local function title() return settings().TitleContainer.TitleText:GetText() end
  local function headers()
    local out = {}
    for c in settings().categoryPool:EnumerateActive() do out[#out + 1] = c.Header.Name:GetText() end
    return out
  end
  local function items(categoryIndex)
    local out, i = {}, 0
    for c in settings().categoryPool:EnumerateActive() do
      i = i + 1
      if i == categoryIndex then
        for item in c.itemPool:EnumerateActive() do out[#out + 1] = item end
      end
    end
    return out
  end
  local function tipLine(i) return _G["GameTooltipTextLeft" .. i]:GetText() end
  local function hover(item) item.scripts.OnEnter(item) end

  local function load()
    local ns = H.loadChunks(FILES)
    H.uiSetup(ns, UI)
    return ns
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    CV.install()
    WFJ = load()
    SS = WFJ.SurfaceState
    -- H.uiSetup sets the English globals, which the replayed OnLoad reads: install again now that they exist
    CV.uninstall()
    CV.install()
    CV.categories = {
      { title = en("COOLDOWN_VIEWER_SETTINGS_CATEGORY_ESSENTIAL"), items = { { spell = "Items" }, { empty = true } } },
      { title = en("COOLDOWN_VIEWER_SETTINGS_CATEGORY_EQUIP_ACTIVE"), items = {} },
      { title = en("COOLDOWN_VIEWER_SETTINGS_CATEGORY_NOT_IN_BAR"), items = {} },
    }
    WFJ.Labels.forbidNames(WFJ.CooldownViewer.NEVER_TOUCH)
    assert.is_true(WFJ.CooldownViewer.init())
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    CV.uninstall()
  end)

  it("the title renders after SetTitle and again after a second SetTitle; the search placeholder and the group-buff "
    .. "sections render; Alt shows the client's English", function()
    assert.are.equal(ja("COOLDOWN_VIEWER_SETTINGS_TITLE"), title())
    settings():SetTitle(en("COOLDOWN_VIEWER_SETTINGS_TITLE"))
    assert.are.equal(ja("COOLDOWN_VIEWER_SETTINGS_TITLE"), title())
    assert.are.equal(1, #Stub.hooks["CooldownViewerSettings:SetTitle"])
    assert.are.equal(ja("COOLDOWN_VIEWER_SETTINGS_SEARCH_INSTRUCTIONS"), settings().SearchBox.Instructions:GetText())
    local filter = settings().GroupBuffFilter
    assert.are.equal(ja("GROUP_BUFF_FILTER_SECTION_SHOWN"), filter.shownSection.Header.Name:GetText())
    assert.are.equal(ja("GROUP_BUFF_FILTER_SECTION_HIDDEN"), filter.hiddenSection.Header.Name:GetText())
    alt(true)
    assert.are.equal(en("COOLDOWN_VIEWER_SETTINGS_TITLE"), title())
    alt(false)
    -- the undo button's "Revert |A…|a" shows the word in Japanese, the atlas kept (iconAfter); the layout
    -- dropdown holds a layout's name
    local undo = settings().UndoButton
    assert.are.equal("元に戻す |A:common-icon-undo:0:0|a", undo:GetText())
    alt(true)
    assert.are.equal("Revert |A:common-icon-undo:0:0|a", undo:GetText())
    alt(false)
    -- the client's formatter runs again (a disable: OnDisable → RunCustomTextFormatter), the other atlas
    undo:SetText("Revert |A:common-icon-undo-disable:0:0|a")
    WFJ.CooldownViewer.onUndoText()
    assert.are.equal("元に戻す |A:common-icon-undo-disable:0:0|a", undo:GetText())
    assert.is_true(WFJ.Labels.forbidden(settings().LayoutDropdown.Text))
    assert.is_true(WFJ.Labels.forbidden(settings().SearchBox))
  end)

  it("RefreshLayout: the pooled category headers render, keyed by widget, and follow a reshuffled pool", function()
    settings():Show()
    assert.are.same({ ja("COOLDOWN_VIEWER_SETTINGS_CATEGORY_ESSENTIAL"),
      ja("COOLDOWN_VIEWER_SETTINGS_CATEGORY_EQUIP_ACTIVE"), ja("COOLDOWN_VIEWER_SETTINGS_CATEGORY_NOT_IN_BAR") },
      headers())
    CV.categories = { { title = en("COOLDOWN_VIEWER_SETTINGS_CATEGORY_NOT_IN_BAR") }, { title = "Gold" } }
    settings():RefreshLayout()
    assert.are.same({ ja("COOLDOWN_VIEWER_SETTINGS_CATEGORY_NOT_IN_BAR"), "Gold" }, headers()) -- not a category key
    alt(true)
    assert.are.same({ en("COOLDOWN_VIEWER_SETTINGS_CATEGORY_NOT_IN_BAR"), "Gold" }, headers())
    alt(false)
    assert.are.equal(1, #Stub.hooks["CooldownViewerSettings:RefreshLayout"])
  end)

  it("help tooltips: a tab's title, the disabled group tab's reason and the undo button's tooltip render", function()
    local tab = settings().SpellsTab
    _G.GameTooltip:SetOwner(tab)
    _G.GameTooltip:SetText(tab.tooltipText)
    _G.GameTooltip:Show()
    assert.are.equal(ja("COOLDOWN_VIEWER_SETTINGS_TAB_SPELLS"), tipLine(1))
    _G.GameTooltip:Hide()
    _G.GameTooltip:SetOwner(settings().GroupBuffsTab)
    _G.GameTooltip:SetText(en("COOLDOWN_VIEWER_SETTINGS_TAB_GROUP_AURAS"))
    _G.GameTooltip:AddLine(en("COOLDOWN_VIEWER_SETTINGS_TAB_GROUP_AURAS_DISABLED_TOOLTIP"))
    _G.GameTooltip:Show()
    assert.are.equal(ja("COOLDOWN_VIEWER_SETTINGS_TAB_GROUP_AURAS"), tipLine(1))
    assert.are.equal(ja("COOLDOWN_VIEWER_SETTINGS_TAB_GROUP_AURAS_DISABLED_TOOLTIP"), tipLine(2))
    _G.GameTooltip:Hide()
    _G.GameTooltip:SetOwner(settings().UndoButton)
    _G.GameTooltip:SetText(en("COOLDOWN_VIEWER_SETTINGS_BUTTON_REVERT_CHANGES_TOOLTIP"))
    _G.GameTooltip:Show()
    assert.are.equal(ja("COOLDOWN_VIEWER_SETTINGS_BUTTON_REVERT_CHANGES_TOOLTIP"), tipLine(1))
  end)

  it("item tooltips: an empty slot, a potion category and a tracked trinket's label render; a spell tooltip, an aura "
    .. "tooltip and a secret title are never walked", function()
    settings():Show()
    local list = items(1)
    hover(list[2]) -- the empty slot
    assert.are.equal(ja("COOLDOWN_VIEWER_SETTINGS_EMPTY_SLOT_TOOLTIP"), tipLine(1))
    _G.GameTooltip:Hide()
    hover(list[1]) -- a spell whose name is a dictionary word of this window
    assert.are.equal("Items", tipLine(1))
    _G.GameTooltip:Hide()
    CV.categories = { { title = "x", items = {
      { categoryTitle = en("COOLDOWN_VIEWER_TOOLTIP_POTION_HEALTH_TITLE"),
        categoryDescription = en("COOLDOWN_VIEWER_TOOLTIP_POTION_HEALTH_DESCRIPTION") },
      { tracked = true, itemName = "Empty Slot", spell = "Flash" },
      { empty = true, dynamic = true },
    } } }
    settings():RefreshLayout()
    list = items(1)
    hover(list[1])
    assert.are.equal(ja("COOLDOWN_VIEWER_TOOLTIP_POTION_HEALTH_TITLE"), tipLine(1))
    assert.are.equal(ja("COOLDOWN_VIEWER_TOOLTIP_POTION_HEALTH_DESCRIPTION"), tipLine(2))
    _G.GameTooltip:Hide()
    hover(list[2]) -- the item's and the spell's names are dictionary words elsewhere: only the label is taken
    assert.are.equal("Empty Slot", tipLine(1))
    assert.are.equal("Flash", tipLine(2))
    assert.are.equal(ja("COOLDOWN_VIEWER_TRINKET_AURA_TOOLTIP_LABEL"), tipLine(3))
    _G.GameTooltip:Hide()
    hover(list[3]) -- a dynamic (aura) appearance: never walked
    assert.are.equal(en("COOLDOWN_VIEWER_SETTINGS_EMPTY_SLOT_TOOLTIP"), tipLine(1))
    _G.GameTooltip:Hide()
    _G.issecretvalue = function() return true end -- the first line is a secret value
    local secret = load()
    CV.uninstall()
    CV.install()
    _G.issecretvalue = function() return true end
    CV.categories = { { title = "x", items = { { empty = true } } } }
    assert.is_true(secret.CooldownViewer.init())
    settings():Show()
    hover(items(1)[1])
    assert.are.equal(en("COOLDOWN_VIEWER_SETTINGS_EMPTY_SLOT_TOOLTIP"), tipLine(1))
  end)

  it("the alert editor: labels, the add button and the dropdown texts render and follow a type change; the spell's "
    .. "name and a sound's name stay English", function()
    local a = _G.CooldownViewerSettingsEditAlert
    CV.alert = { type = "sound", event = en("COOLDOWN_VIEWER_SETTINGS_ALERT_WHEN_AVAILABLE"), payload = "Error" }
    a:DisplayForAlert("Flash", true)
    assert.are.equal(ja("COOLDOWN_VIEWER_SETTINGS_ALERT_DIALOG_TITLE"), a.Title:GetText())
    assert.are.equal(ja("COOLDOWN_VIEWER_SETTINGS_ALERT_DIALOG_LABEL_TYPE"), a.PrimaryLabel:GetText())
    assert.are.equal(ja("COOLDOWN_VIEWER_SETTINGS_ALERT_DIALOG_LABEL_EVENT"), a.EventLabel:GetText())
    assert.are.equal(ja("COOLDOWN_VIEWER_SETTINGS_ALERT_DIALOG_LABEL_SOUND_TYPE"), a.PayloadLabel:GetText())
    assert.are.equal(ja("COOLDOWN_VIEWER_SETTINGS_ALERT_MENU_BUTTON_ADD_ALERT"), a.AddButton:GetText())
    assert.are.equal(ja("COOLDOWN_VIEWER_SETTINGS_ALERT_TYPE_SOUND"), a.TypeDropdown.Text:GetText())
    assert.are.equal(ja("COOLDOWN_VIEWER_SETTINGS_ALERT_WHEN_AVAILABLE"), a.EventDropdown.Text:GetText())
    assert.are.equal("Error", a.PayloadDropdown.Text:GetText()) -- a sound's name, a dictionary word elsewhere
    assert.are.equal("Flash", a.Name:GetText()) -- a spell's name that is also a visual alert's label
    assert.is_true(unrecorded(a.Name))
    assert.is_true(WFJ.Labels.forbidden(a.Name))
    -- the player picks Visual, then an event: the client reruns SetupDropdowns / UpdateText
    CV.alert = { type = "visual", event = en("COOLDOWN_VIEWER_SETTINGS_ALERT_WHEN_ON_COOLDOWN"),
      payload = en("CDMVIS_FLASH_BLUE") }
    a:SetupDropdowns()
    assert.are.equal(ja("COOLDOWN_VIEWER_SETTINGS_ALERT_DIALOG_LABEL_VISUAL_TYPE"), a.PayloadLabel:GetText())
    assert.are.equal(ja("COOLDOWN_VIEWER_SETTINGS_ALERT_TYPE_VISUAL"), a.TypeDropdown.Text:GetText())
    assert.are.equal(ja("COOLDOWN_VIEWER_SETTINGS_ALERT_WHEN_ON_COOLDOWN"), a.EventDropdown.Text:GetText())
    assert.are.equal(ja("CDMVIS_FLASH_BLUE"), a.PayloadDropdown.Text:GetText())
    CV.alert.payload = en("COOLDOWN_VIEWER_SETTINGS_ALERT_LABEL_SOUND_TYPE_TEXT_TO_SPEECH")
    a.PayloadDropdown:UpdateText()
    assert.are.equal(ja("COOLDOWN_VIEWER_SETTINGS_ALERT_LABEL_SOUND_TYPE_TEXT_TO_SPEECH"),
      a.PayloadDropdown.Text:GetText())
    a:Display(false)
    assert.are.equal(ja("COOLDOWN_VIEWER_SETTINGS_ALERT_MENU_BUTTON_EDIT_EXISTING_ALERT"), a.AddButton:GetText())
    alt(true)
    assert.are.equal(en("COOLDOWN_VIEWER_SETTINGS_ALERT_DIALOG_LABEL_VISUAL_TYPE"), a.PayloadLabel:GetText())
    alt(false)
  end)

  it("the group-buff visual alert editor renders its label and its visual type; the buff's name stays English",
    function()
    local g = _G.GroupBuffFilterEditVisualAlert
    CV.groupVisual = en("CDMVIS_FLASH")
    g:DisplayForGroupBuffItem("Gold", true)
    assert.are.equal(ja("GROUP_BUFF_FILTER_VISUAL_ALERT_DIALOG_LABEL_VISUAL_TYPE"), g.PrimaryLabel:GetText())
    assert.are.equal(ja("CDMVIS_FLASH"), g.VisualDropdown.Text:GetText())
    assert.are.equal(ja("COOLDOWN_VIEWER_SETTINGS_ALERT_MENU_BUTTON_ADD_ALERT"), g.AddButton:GetText())
    assert.are.equal("Gold", g.Name:GetText())
    assert.is_true(unrecorded(g.Name))
  end)

  it("edit mode: a HUD viewer's selection label and tooltip render its system name and nothing else", function()
    local selection = _G.EssentialCooldownViewer.Selection
    selection:UpdateLabelVisibility()
    assert.are.equal("Click to Edit", selection.Label:GetText()) -- edit mode's own word: not this surface's
    selection.isSelected = true
    selection:UpdateLabelVisibility()
    assert.are.equal(ja("HUD_EDIT_MODE_SYSTEM_ESSENTIAL_COOLDOWNS"), selection.Label:GetText())
    _G.BuffIconCooldownViewer.Selection:CheckShowInstructionalTooltip()
    assert.are.equal(ja("HUD_EDIT_MODE_SYSTEM_TRACKED_BUFFS"), tipLine(1))
  end)

  it("client names bound to the wrong type degrade to untouched English with no error", function()
    CV.uninstall()
    CV.install()
    local f = settings()
    f.SearchBox, f.SpellsTab, f.UndoButton, f.categoryPool = "moved", 7, true, 5
    f.GroupBuffFilter = "gone"
    f.TitleContainer = { TitleText = "moved" }
    local a = _G.CooldownViewerSettingsEditAlert
    a.Title, a.TypeDropdown, a.PayloadDropdown, a.AddButton = 3, true, { Text = "x" }, "button"
    _G.GroupBuffFilterEditVisualAlert = "not a frame"
    _G.EssentialCooldownViewer.Selection = 7
    _G.UtilityCooldownViewer = "moved"
    _G.BuffBarCooldownViewer.Selection.Label = false
    _G.issecretvalue = "not a function"
    local ns = load()
    assert.has_no.errors(function() assert.is_true(ns.CooldownViewer.init()) end)
    assert.has_no.errors(function()
      f:Show()
      CV.alert = { type = "sound", event = en("COOLDOWN_VIEWER_SETTINGS_ALERT_WHEN_AVAILABLE"), payload = "Error" }
      a:DisplayForAlert("Flash", true)
      _G.BuffBarCooldownViewer.Selection:UpdateLabelVisibility()
    end)
    assert.are.equal(ja("COOLDOWN_VIEWER_SETTINGS_ALERT_DIALOG_LABEL_EVENT"), a.EventLabel:GetText()) -- what resolves
    assert.are.equal(ja("COOLDOWN_VIEWER_SETTINGS_ALERT_WHEN_AVAILABLE"), a.EventDropdown.Text:GetText())
  end)

  it("hooks install once; a client without the window is skipped without error", function()
    assert.is_false(WFJ.CooldownViewer.init())
    assert.are.equal(1, #Stub.hooks["CooldownViewerSettings:RefreshLayout"])
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    CV.uninstall()
    local bare = load()
    assert.has_no.errors(function() assert.is_false(bare.CooldownViewer.init()) end)
  end)
end)
