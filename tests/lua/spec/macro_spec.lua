-- UI/Macro.lua over a MacroFrame replayed from blizzard_macroui/
-- blizzard_macroui.xml:40–234, blizzard_macroui.lua:233–246 and the icon selector popup (blizzard_sharedxml/mainline/
-- shareduipaneltemplates.lua:1844, 1969–1972). The macro body, macro names and the popup's name box are never
-- touched; the surface waits for Blizzard_MacroUI in either load order.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/Macro.lua"

local ADDON = "Blizzard_MacroUI"

local UI = {
  CREATE_MACROS = { "Create Macros", "マクロ作成" }, ENTER_MACRO_LABEL = { "Enter Macro Commands:", "マクロコマンドを入力:" },
  CHANGE_MACRO_NAME_ICON = { "Change Name/Icon", "名前/アイコン変更" }, CANCEL = { "Cancel", "キャンセル" },
  SAVE = { "Save", "保存" }, DELETE = { "Delete", "削除" }, NEW = { "New", "新規" }, EXIT = { "Exit", "閉じる" },
  GENERAL_MACROS = { "General Macros", "共通マクロ" },
  CHARACTER_SPECIFIC_MACROS = { "%s Specific Macros", "%s専用マクロ" },
  MACROFRAME_CHAR_LIMIT = { "%d/255 Characters Used", "%d/255文字使用" },
  MACRO_POPUP_TEXT = { "Enter Macro Name (Max 16 Characters):", "マクロ名を入力 (最大16文字):" }, OKAY = { "Okay", "OK" },
  ICON_SELECTION_TITLE_CURRENT = { "Current Icon", "現在のアイコン" },
  ICON_SELECTION_CLICK = { "Click to view in the list", "クリックで一覧に表示" },
  ICON_SELECTION_NOTINLIST = { "Not in the list", "一覧にありません" },
  CLICK_BINDING_BUTTON_DISABLED = { "Not available while in Click Cast Bindings", "クリックキャスト設定中は使用できません" },
}

local function en(key) return _G[key] end
local function fs(text) return Stub.fontString(text or "") end

local function loadMacroUI()
  local f = CreateFrame("Frame", "MacroFrame")
  f:addRegion(fs(en("CREATE_MACROS")))
  Stub.namedFontString("MacroFrameEnterMacroText", en("ENTER_MACRO_LABEL"))
  Stub.namedFontString("MacroFrameCharLimitText", "")
  Stub.namedFontString("MacroFrameSelectedMacroName", "")
  Stub.button("MacroEditButton", en("CHANGE_MACRO_NAME_ICON"))
  Stub.button("MacroCancelButton", en("CANCEL"))
  Stub.button("MacroSaveButton", en("SAVE"))
  Stub.button("MacroDeleteButton", en("DELETE"))
  Stub.button("MacroNewButton", en("NEW"))
  Stub.button("MacroExitButton", en("EXIT"))
  Stub.button("MacroFrameTab1", en("GENERAL_MACROS"))
  Stub.button("MacroFrameTab2", string.format(en("CHARACTER_SPECIFIC_MACROS"), "Reyn")) -- xml:204–207
  local body = CreateFrame("EditBox", "MacroFrameText")
  body:SetScript("OnTextChanged", function(self) -- xml:126–136
    _G.MacroFrameCharLimitText.text = string.format(en("MACROFRAME_CHAR_LIMIT"), #(self.text or ""))
  end)
  function body.type(self, text) -- test-only: the player types
    self.text = text
    self.scripts.OnTextChanged(self)
  end
  local popup = CreateFrame("Frame", "MacroPopupFrame")
  popup.name = "MacroPopupFrame"
  local box = CreateFrame("Frame")
  popup.BorderBox = box
  box.EditBoxHeaderText = fs(en("MACRO_POPUP_TEXT"))
  box.OkayButton, box.CancelButton = Stub.button(nil, en("OKAY")), Stub.button(nil, en("CANCEL"))
  box.IconSelectorEditBox = CreateFrame("EditBox")
  box.SelectedIconArea = { SelectedIconText = { SelectedIconHeader = fs(en("ICON_SELECTION_TITLE_CURRENT")),
    SelectedIconDescription = fs() } }
  function popup.SetSelectedIconText(self, inList)
    self.BorderBox.SelectedIconArea.SelectedIconText.SelectedIconDescription.text =
      en(inList and "ICON_SELECTION_CLICK" or "ICON_SELECTION_NOTINLIST")
  end
  popup:SetSelectedIconText(true)
  body:type("")
  Stub.loadedAddons[ADDON] = true
  return f
end

local NAMES = { "MacroFrame", "MacroFrameEnterMacroText", "MacroFrameCharLimitText", "MacroFrameSelectedMacroName",
  "MacroEditButton", "MacroCancelButton", "MacroSaveButton", "MacroDeleteButton", "MacroNewButton", "MacroExitButton",
  "MacroFrameTab1", "MacroFrameTab2", "MacroFrameText", "MacroPopupFrame" }

describe("the macro window on Forever", function()
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
    -- the player's name is a `text` capture (Core/UIStrings ARGS; granted here until the shared table carries it)
    WFJ.UIStrings.ARGS.CHARACTER_SPECIFIC_MACROS = WFJ.UIStrings.ARGS.CHARACTER_SPECIFIC_MACROS or { [1] = "text" }
    H.uiSetup(WFJ, UI)
  end

  local function setup(loadedFirst)
    load()
    if loadedFirst then
      loadMacroUI()
      assert.is_true(WFJ.Macro.init())
    else
      assert.is_false(WFJ.Macro.init()) -- waits for the addon
      loadMacroUI()
      assert.are.equal(1, WFJ.LoadOnDemand.loaded(ADDON))
    end
  end

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    for _, name in ipairs(NAMES) do _G[name] = nil end
  end)

  for _, order in ipairs({ { true, "loaded before the addon" }, { false, "loaded on demand" } }) do
    describe("Blizzard_MacroUI " .. order[2], function()
      before_each(function() setup(order[1]) end)

      it("static labels, both tabs and the popup are Japanese; the player's name is kept", function()
        assert.are.equal("マクロ作成", (_G.MacroFrame:GetRegions()):GetText())
        assert.are.equal("マクロコマンドを入力:", _G.MacroFrameEnterMacroText:GetText())
        assert.are.equal("名前/アイコン変更", _G.MacroEditButton:GetText())
        assert.are.equal("新規", _G.MacroNewButton:GetText())
        assert.are.equal("共通マクロ", _G.MacroFrameTab1:GetText())
        assert.are.equal("Reyn専用マクロ", _G.MacroFrameTab2:GetText())
        local box = _G.MacroPopupFrame.BorderBox
        assert.are.equal("マクロ名を入力 (最大16文字):", box.EditBoxHeaderText:GetText())
        assert.are.equal("OK", box.OkayButton:GetText())
        assert.are.equal("現在のアイコン", box.SelectedIconArea.SelectedIconText.SelectedIconHeader:GetText())
        alt(true)
        assert.are.equal("Reyn Specific Macros", _G.MacroFrameTab2:GetText())
        assert.are.equal("Create Macros", (_G.MacroFrame:GetRegions()):GetText())
        alt(false)
        assert.are.equal("Reyn専用マクロ", _G.MacroFrameTab2:GetText())
      end)

      it("the character count follows typing; the macro body is never read into a record", function()
        assert.are.equal("0/255文字使用", _G.MacroFrameCharLimitText:GetText())
        _G.MacroFrameText:type("/cast Save")
        assert.are.equal("10/255文字使用", _G.MacroFrameCharLimitText:GetText())
        assert.are.equal("/cast Save", _G.MacroFrameText.text)
        assert.is_true(unrecorded(_G.MacroFrameText))
      end)

      it("a macro named like a UI word stays English", function()
        _G.MacroFrameSelectedMacroName.text = "Save"
        _G.MacroFrame:Show()
        alt(true); alt(false)
        assert.are.equal("Save", _G.MacroFrameSelectedMacroName:GetText())
        assert.is_true(unrecorded(_G.MacroFrameSelectedMacroName))
      end)

      it("the popup's icon description follows SetSelectedIconText", function()
        local text = _G.MacroPopupFrame.BorderBox.SelectedIconArea.SelectedIconText.SelectedIconDescription
        assert.are.equal("クリックで一覧に表示", text:GetText())
        _G.MacroPopupFrame:SetSelectedIconText(false)
        assert.are.equal("一覧にありません", text:GetText())
      end)

      it("the click-binding tooltip on a disabled button is Japanese", function()
        local tt = _G.GameTooltip
        tt:SetOwner(_G.MacroNewButton)
        tt:SetText(en("CLICK_BINDING_BUTTON_DISABLED"))
        assert.are.equal("クリックキャスト設定中は使用できません", _G.GameTooltipTextLeft1:GetText())
      end)
    end)
  end

  it("hooks install once", function()
    setup(true)
    assert.is_false(WFJ.Macro.setup())
    assert.are.equal(1, #Stub.hooks["MacroPopupFrame:SetSelectedIconText"])
  end)

  it("a client name bound to the wrong type degrades to untouched English with no error", function()
    load()
    loadMacroUI()
    _G.MacroFrameTab1 = "nope"
    _G.MacroFrameText = 42
    _G.MacroPopupFrame = true
    _G.MacroFrameCharLimitText = false
    assert.has_no.errors(function() assert.is_true(WFJ.Macro.init()) end)
    assert.are.equal("保存", _G.MacroSaveButton:GetText()) -- the rest still works
  end)

  it("without the window: init waits, setup returns false", function()
    load()
    assert.is_false(WFJ.Macro.init())
    Stub.loadedAddons[ADDON] = true
    assert.is_false(WFJ.Macro.setup())
  end)
end)
