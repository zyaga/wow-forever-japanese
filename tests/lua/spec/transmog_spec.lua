-- The transmogrifier window on Forever: UI/Transmog.lua over a TransmogFrame replayed from
-- blizzard_transmog/blizzard_transmog.xml (:45–796) and .lua (:114, :821–822, :990, :1485–1491, :1747–1748,
-- :1817–1847, :1921–2025), with the shared TabSystem's UpdateTabText (tabsystemtemplates.lua:192–196),
-- load-on-demand in both load orders. Appearance and outfit names stay English.
local Stub = require("tests.lua.spec.wow_stub")
local C = require("tests.lua.spec.stub_commerce")

local UI = {
  TRANSMOGRIFY = { "Transmogrify", "トランスモグ" },
  TRANSMOG_SAVE_OUTFIT = { "Save Outfit", "衣装を保存" },
  TRANSMOG_SHEATHE_WEAPON = { "Sheathe Weapon", "武器をしまう" },
  TRANSMOG_SITUATIONS_DEFAULTS = { "Defaults", "初期設定" },
  SEARCH_LOADING_TEXT = { "Loading...", "読み込み中..." },
  TRANSMOG_TAB_ITEMS = { "Items", "アイテム" }, TRANSMOG_TAB_SETS = { "Sets", "セット" },
  SOURCES = { "Sources", "入手元" }, HEADSLOT = { "Head", "頭" }, WEAPON_ENCHANTMENT = { "Weapon Enchantment", "武器エンチャント" },
  TRANSMOG_SLOT_DISPLAY_TYPE_UNASSIGNED = { "Unassigned", "未割り当て" },
  TRANSMOG_SLOT_DISPLAY_TYPE_UNASSIGNED_TOOLTIP = { "The appearance of this slot will not be changed.",
    "このスロットの外見は変更されません。" },
  TRANSMOGRIFY_TOOLTIP_HIDDEN = { "Hidden", "非表示" },
  TRANSMOGRIFY_CLEAR_ALL_PENDING = { "Undo all pending changes", "保留中の変更をすべて取り消す" },
  -- the sheathe tooltip (binding form) and the situations' dropdown default text (wrapped form)
  TRANSMOG_SHEATHE_WEAPON_TOOLTIP = { "Sheathe/Unsheathe Weapon", "武器をしまう/抜く" },
  TRANSMOG_SITUATIONS_NO_VALID_OPTIONS = { "No valid options selected", "有効なオプションが選択されていません" },
}

local F = "TransmogFrame"
local function en(key) return _G[key] end

local function tabButton(text)
  local b = CreateFrame("Button")
  b.Text, b.tabText = Stub.fontString(""), text
  function b.UpdateTabText(self) self.Text.text = self.tabText end
  b:UpdateTabText()
  return b
end

local function build()
  local frame = C.window(F)
  frame:SetTitle(en("TRANSMOGRIFY")) -- OnLoad (lua:114), before any hook
  C.tree(frame, {
    ["OutfitCollection.SaveOutfitButton"] = { button = en("TRANSMOG_SAVE_OUTFIT") },
    ["CharacterPreview.ToggleOptions.SheatheWeaponToggle.Text"] = en("TRANSMOG_SHEATHE_WEAPON"),
    ["CharacterPreview.ClearAllPendingButton"] = { button = "" },
    ["WardrobeCollection.TabContent.ItemsFrame.ActiveSlotTitle"] = "",
    ["WardrobeCollection.TabContent.ItemsFrame.FilterButton.Text"] = "",
    ["WardrobeCollection.TabContent.ItemsFrame.DisplayTypes.DisplayTypeUnassignedButton"] = { button = "" },
    ["WardrobeCollection.TabContent.ItemsFrame.SearchBox.ProgressFrame.LoadingFrame.Text"] = en("SEARCH_LOADING_TEXT"),
    ["WardrobeCollection.TabContent.SituationsFrame.DefaultsButton"] = { button = en("TRANSMOG_SITUATIONS_DEFAULTS") },
    ["CharacterPreview.ToggleOptions.SheatheWeaponToggle.Checkbox"] = { button = "" },
  })
  -- the situations' pooled rows: Refresh writes each dropdown's default text, red-wrapped (lua:3104–3120)
  local situations = frame.WardrobeCollection.TabContent.SituationsFrame
  situations.SituationFramePool = C.pool(function()
    local row = CreateFrame("Frame")
    row.Dropdown = CreateFrame("Button")
    row.Dropdown.Text = Stub.fontString("")
    function row.Dropdown.UpdateText(self) self.Text.text = self.defaultText end
    return row
  end)
  function situations.Refresh(self)
    self.SituationFramePool:ReleaseAll()
    for _ = 1, 2 do
      local row = self.SituationFramePool:Acquire()
      row.Dropdown.defaultText = "|cffff2020" .. en("TRANSMOG_SITUATIONS_NO_VALID_OPTIONS") .. "|r"
      row.Dropdown:UpdateText()
    end
  end
  local items = frame.WardrobeCollection.TabContent.ItemsFrame
  items.slot = "HEADSLOT"
  function items.RefreshActiveSlotTitle(self) -- _G[slot name], or the "$slot ($option)" composite (lua:1823–1846)
    self.ActiveSlotTitle.text = self.composite or en(self.slot)
  end
  function items.RefreshDisplayTypeButtons(self)
    self.DisplayTypes.DisplayTypeUnassignedButton:SetText(en("TRANSMOG_SLOT_DISPLAY_TYPE_UNASSIGNED"))
  end
  function items.FilterButton.UpdateText() end
  function items.InitFilterButton(self) self.FilterButton.Text.text = en("SOURCES") end
  items:InitFilterButton()
  local wardrobe = frame.WardrobeCollection
  local tabs = { tabButton(en("TRANSMOG_TAB_ITEMS")), tabButton(en("TRANSMOG_TAB_SETS")) }
  wardrobe.TabHeaders = { GetTabButton = function(_, id) return tabs[id] end }
  wardrobe.itemsTabID, wardrobe.setsTabID = 1, 2
  local preview = frame.CharacterPreview
  preview.CharacterAppearanceSlotFramePool = C.pool(function() return CreateFrame("Button") end)
  preview.CharacterIllusionSlotFramePool = C.pool(function() return CreateFrame("Button") end)
  function preview.SetupSlots(self)
    self.CharacterAppearanceSlotFramePool:ReleaseAll()
    self.CharacterAppearanceSlotFramePool:Acquire()
    self.CharacterIllusionSlotFramePool:ReleaseAll()
    self.CharacterIllusionSlotFramePool:Acquire()
  end
  return frame
end

local function tabText(frame, id) return frame.WardrobeCollection.TabHeaders:GetTabButton(id).Text:GetText() end

C.suite(getfenv(1), {
  title = "the transmogrifier on Forever", module = "Transmog", file = "UI/Transmog.lua",
  addon = "Blizzard_Transmog", root = F, ui = UI, build = build, globals = { F },
  cases = {
    { "the title, static labels, tabs and the filter's own text are Japanese; Alt shows English; hide releases",
      function(frame, WFJ)
        frame:Show()
        assert.are.equal("トランスモグ", frame.TitleContainer.TitleText:GetText())
        frame:SetTitle(en("TRANSMOGRIFY"))
        assert.are.equal("トランスモグ", frame.TitleContainer.TitleText:GetText())
        assert.are.equal("衣装を保存", frame.OutfitCollection.SaveOutfitButton:GetText())
        assert.are.equal("武器をしまう", frame.CharacterPreview.ToggleOptions.SheatheWeaponToggle.Text:GetText())
        assert.are.equal("初期設定",
          frame.WardrobeCollection.TabContent.SituationsFrame.DefaultsButton:GetText())
        local items = frame.WardrobeCollection.TabContent.ItemsFrame
        assert.are.equal("読み込み中...", items.SearchBox.ProgressFrame.LoadingFrame.Text:GetText())
        assert.are.equal("入手元", items.FilterButton.Text:GetText())
        assert.are.equal("アイテム", tabText(frame, 1))
        frame.WardrobeCollection.TabHeaders:GetTabButton(2):UpdateTabText()
        assert.are.equal("セット", tabText(frame, 2))
        C.alt(WFJ, true)
        assert.are.equal("Transmogrify", frame.TitleContainer.TitleText:GetText())
        C.alt(WFJ, false)
        frame:Hide()
        assert.are.equal("Sheathe Weapon", frame.CharacterPreview.ToggleOptions.SheatheWeaponToggle.Text:GetText())
      end },
    { "the writers: the active slot title and the unassigned button follow their refresh methods", function(frame)
      frame:Show()
      local items = frame.WardrobeCollection.TabContent.ItemsFrame
      items:RefreshActiveSlotTitle()
      assert.are.equal("頭", items.ActiveSlotTitle:GetText())
      items.slot = "WEAPON_ENCHANTMENT"
      items:RefreshActiveSlotTitle()
      assert.are.equal("武器エンチャント", items.ActiveSlotTitle:GetText())
      items:RefreshDisplayTypeButtons()
      assert.are.equal("未割り当て", items.DisplayTypes.DisplayTypeUnassignedButton:GetText())
    end },
    { "tooltips: a slot button acquired by SetupSlots, the unassigned button and the clear-all button", function(frame)
      local preview = frame.CharacterPreview
      preview:SetupSlots()
      local slot = preview.CharacterAppearanceSlotFramePool:EnumerateActive()()
      C.tooltip(slot, { en("HEADSLOT"), "Helm of Valor", en("TRANSMOGRIFY_TOOLTIP_HIDDEN") })
      assert.are.equal("頭", _G.GameTooltipTextLeft1:GetText())
      assert.are.equal("Helm of Valor", _G.GameTooltipTextLeft2:GetText())
      assert.are.equal("非表示", _G.GameTooltipTextLeft3:GetText())
      local illusion = preview.CharacterIllusionSlotFramePool:EnumerateActive()()
      C.tooltip(illusion, { en("WEAPON_ENCHANTMENT") })
      assert.are.equal("武器エンチャント", _G.GameTooltipTextLeft1:GetText())
      local unassigned = frame.WardrobeCollection.TabContent.ItemsFrame.DisplayTypes.DisplayTypeUnassignedButton
      C.tooltip(unassigned, { en("TRANSMOG_SLOT_DISPLAY_TYPE_UNASSIGNED"),
        en("TRANSMOG_SLOT_DISPLAY_TYPE_UNASSIGNED_TOOLTIP") })
      assert.are.equal("このスロットの外見は変更されません。", _G.GameTooltipTextLeft2:GetText())
      C.tooltip(preview.ClearAllPendingButton, { en("TRANSMOGRIFY_CLEAR_ALL_PENDING") })
      assert.are.equal("保留中の変更をすべて取り消す", _G.GameTooltipTextLeft1:GetText())
    end },
    { "the sheathe toggle's binding tooltip and each situation's red default text", function(frame)
      frame:Show()
      local checkbox = frame.CharacterPreview.ToggleOptions.SheatheWeaponToggle.Checkbox
      C.tooltip(checkbox, { "Sheathe/Unsheathe Weapon |cffffd200(Z)|r" })
      assert.are.equal("武器をしまう/抜く |cffffd200(Z)|r", _G.GameTooltipTextLeft1:GetText())
      local situations = frame.WardrobeCollection.TabContent.SituationsFrame
      situations:Refresh()
      for row in situations.SituationFramePool:EnumerateActive() do
        assert.are.equal("|cffff2020有効なオプションが選択されていません|r", row.Dropdown.Text:GetText())
      end
      local row = situations.SituationFramePool:EnumerateActive()()
      row.Dropdown.defaultText = "Mounted" -- a selected option's name stays
      row.Dropdown:UpdateText()
      assert.are.equal("Mounted", row.Dropdown.Text:GetText())
    end },
  },
  name = function(frame, WFJ)
    -- an option set: "$slot ($option)" filled with an option name stays as written (lua:1842–1846)
    local items = frame.WardrobeCollection.TabContent.ItemsFrame
    items.composite = "Head (Sets)"
    items:RefreshActiveSlotTitle()
    assert.are.equal("Head (Sets)", items.ActiveSlotTitle:GetText())
    assert.is_true(C.unrecorded(WFJ, items.ActiveSlotTitle))
    assert.are.equal(0, WFJ.Labels.show("transmog", "x", items.SearchBox))
  end,
  wrong = function(frame)
    frame.WardrobeCollection.TabHeaders = "tabs"
    frame.CharacterPreview.CharacterAppearanceSlotFramePool = 5
    frame.OutfitCollection = true
    return function(f)
      assert.are.equal("武器をしまう", f.CharacterPreview.ToggleOptions.SheatheWeaponToggle.Text:GetText())
    end
  end,
})
