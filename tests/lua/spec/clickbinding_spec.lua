-- UI/ClickBinding.lua over a ClickBindingFrame replayed
-- from blizzard_clickbindingui/blizzard_clickbindingui.xml:147–312 and blizzard_clickbindingui.lua:160–259, 589–600,
-- 811–814. Spell and macro names and the tutorial's "Thrall" stay English; the surface waits for
-- Blizzard_ClickBindingUI in either load order and does nothing on a client without it.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/ClickBinding.lua"

local ADDON = "Blizzard_ClickBindingUI"

local UI = {
  CLICK_CAST_BINDINGS = { "Click Cast Bindings", "クリックキャスト設定" },
  CLICK_CAST_ABOUT_HEADER = { "About Click Cast Bindings", "クリックキャスト設定について" },
  SAVE = { "Save", "保存" }, ADD_BINDING = { "Add Binding", "バインドを追加" },
  RESET_TO_DEFAULT = { "Reset To Default", "初期設定に戻す" },
  ENABLE_MOUSEOVER_CAST = { "Mouseover Cast", "マウスオーバーキャスト" },
  MOUSEOVER_CAST_KEY = { "Mouseover Cast Key", "マウスオーバーキャストキー" },
  CLICK_CAST_TITLE = { "Bind spells and macros to mouse clicks", "呪文やマクロをマウスクリックに割り当てます" },
  CLICK_CAST_INFO = { "Cast bound spells and macros by clicking on the unit frame",
    "ユニットフレームをクリックして、割り当てた呪文やマクロを使用します" },
  CLICK_CAST_ALTERNATE = { "Alternate click bindings can be set using Shift, Ctrl, or Alt",
    "Shift、Ctrl、Altを使って別のクリックバインドを設定できます" },
  THRALL_NAME = { "Thrall", "スロール" }, -- shipped nowhere; here to prove the widget is refused even if it were
  CLICK_BINDINGS_DEFAULTS_HEADER = { "Default Mouse Bindings", "初期マウスバインド" },
  CLICK_BINDINGS_CUSTOMS_HEADER = { "Custom Mouse Bindings", "カスタムマウスバインド" },
  CLICK_BINDING_INTERACTION_TITLE = { "%s (Default)", "%s (初期設定)" },
  CLICK_BINDING_TARGET_UNIT = { "Target Unit Frame", "ユニットフレームをターゲット" },
  CLICK_BINDING_MACRO_TITLE = { "%s (Macro)", "%s (マクロ)" },
  LEFT_BUTTON_STRING = { "Left Button", "左ボタン" }, BUTTON_4_STRING = { "Button 4", "ボタン4" },
  -- the modifier + button composite and the colour-wrapped prompts
  CLICK_BINDINGS_BINDING_TEXT_FORMAT = { "%s-%s", "%s-%s" },
  CLICK_BINDINGS_NEW_EMPTY_PROMPT = { "Click on a spell or macro to get started", "呪文かマクロをクリックして始めます" },
  CLICK_BINDINGS_UNBOUND_TEXT = { "Unbound - Mouseover and click to set", "未設定 - マウスを合わせてクリックで設定" },
  OPTION_TOOLTIP_ENABLE_MOUSEOVER_CAST = { "Once enabled, mousing over a unit frame casts on it.", "有効にすると…" },
  MACROS = { "Macros", "マクロ" }, PLAYERSPELLS_BUTTON = { "Talents", "タレント" },
}

local function en(key) return _G[key] end
local function fs(text) return Stub.fontString(text or "") end

local function portraitFrame(name, label)
  local f = CreateFrame("Frame", name)
  f.name = label or name
  f.TitleContainer = { TitleText = fs() }
  function f.SetTitle(self, text) self.TitleContainer.TitleText.text = text end
  return f
end

local C = {}

local function loadClickBinding()
  local f = portraitFrame("ClickBindingFrame")
  f:SetTitle(en("CLICK_CAST_BINDINGS"))
  f.SaveButton = Stub.button(nil, en("SAVE"))
  f.AddBindingButton = Stub.button(nil, en("ADD_BINDING"))
  f.ResetButton = Stub.button(nil, en("RESET_TO_DEFAULT"))
  f.EnableMouseoverCastCheckbox = CreateFrame("CheckButton")
  f.EnableMouseoverCastCheckbox.Label = fs(en("ENABLE_MOUSEOVER_CAST"))
  f.MouseoverCastKeyDropdown = CreateFrame("DropdownButton")
  f.MouseoverCastKeyDropdown.Label = fs(en("MOUSEOVER_CAST_KEY"))
  f.PlayerSpellsPortrait, f.MacrosPortrait = CreateFrame("Button"), CreateFrame("Button")
  local t = portraitFrame(nil, "TutorialFrame")
  f.TutorialFrame = t
  t:SetTitle(en("CLICK_CAST_ABOUT_HEADER"))
  t.SummaryText, t.InfoText = fs(en("CLICK_CAST_TITLE")), fs(en("CLICK_CAST_INFO"))
  t.AlternateText, t.ThrallName = fs(en("CLICK_CAST_ALTERNATE")), fs(en("THRALL_NAME"))
  f.ScrollBox = Stub.scrollBox()
  C.rows = {}
  function C.row(i, data) -- ClickBindingLineMixin:Init / ClickBindingHeaderMixin:Init
    local row = C.rows[i]
    if not row then
      row = CreateFrame("Button")
      row.Name, row.BindingText = fs(), fs()
      C.rows[i] = row
    end
    f.ScrollBox:initFrame(row, data, function(r, d) r.Name.text, r.BindingText.text = d.name, d.binding or "" end)
    return row
  end
  Stub.loadedAddons[ADDON] = true
  return f
end

describe("the Click Cast Bindings window on Forever", function()
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

  local function load()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    SS = WFJ.SurfaceState
    -- "%s (Default)" wraps a dictionary entry (Core/UIStrings ARGS; granted here until the shared table carries it)
    WFJ.UIStrings.ARGS.CLICK_BINDING_INTERACTION_TITLE = WFJ.UIStrings.ARGS.CLICK_BINDING_INTERACTION_TITLE
      or { [1] = "entry" }
    H.uiSetup(WFJ, UI)
  end

  local function setup(loadedFirst)
    load()
    if loadedFirst then
      loadClickBinding()
      assert.is_true(WFJ.ClickBinding.init())
    else
      assert.is_false(WFJ.ClickBinding.init()) -- waits for the addon
      loadClickBinding()
      assert.are.equal(1, WFJ.LoadOnDemand.loaded(ADDON))
    end
  end

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    _G.ClickBindingFrame = nil
  end)

  for _, order in ipairs({ { true, "loaded before the addon" }, { false, "loaded on demand" } }) do
    describe("Blizzard_ClickBindingUI " .. order[2], function()
      before_each(function() setup(order[1]) end)

      it("both titles are Japanese and stay Japanese after a second SetTitle", function()
        local f = _G.ClickBindingFrame
        assert.are.equal("クリックキャスト設定", f.TitleContainer.TitleText:GetText())
        assert.are.equal("クリックキャスト設定について", f.TutorialFrame.TitleContainer.TitleText:GetText())
        f:SetTitle(en("CLICK_CAST_BINDINGS"))
        f.TutorialFrame:SetTitle(en("CLICK_CAST_ABOUT_HEADER"))
        assert.are.equal("クリックキャスト設定", f.TitleContainer.TitleText:GetText())
        assert.are.equal("クリックキャスト設定について", f.TutorialFrame.TitleContainer.TitleText:GetText())
        alt(true)
        assert.are.equal("Click Cast Bindings", f.TitleContainer.TitleText:GetText())
        alt(false)
      end)

      it("static labels are Japanese; the tutorial's Thrall is a name and stays English", function()
        local f = _G.ClickBindingFrame
        assert.are.equal("保存", f.SaveButton:GetText())
        assert.are.equal("バインドを追加", f.AddBindingButton:GetText())
        assert.are.equal("初期設定に戻す", f.ResetButton:GetText())
        assert.are.equal("マウスオーバーキャスト", f.EnableMouseoverCastCheckbox.Label:GetText())
        assert.are.equal("マウスオーバーキャストキー", f.MouseoverCastKeyDropdown.Label:GetText())
        assert.are.equal("呪文やマクロをマウスクリックに割り当てます", f.TutorialFrame.SummaryText:GetText())
        assert.are.equal("Thrall", f.TutorialFrame.ThrallName:GetText())
        assert.is_true(unrecorded(f.TutorialFrame.ThrallName))
        assert.is_true(WFJ.Labels.forbidden(f.TutorialFrame.ThrallName))
      end)

      it("list rows: headers, default interactions, macro titles and mouse buttons translate; spell and macro names "
        .. "do not",
        function()
          local header = C.row(1, { name = en("CLICK_BINDINGS_DEFAULTS_HEADER") })
          assert.are.equal("初期マウスバインド", header.Name:GetText())
          local target = C.row(2, { name = string.format(en("CLICK_BINDING_INTERACTION_TITLE"),
            en("CLICK_BINDING_TARGET_UNIT")), binding = en("LEFT_BUTTON_STRING") })
          assert.are.equal("ユニットフレームをターゲット (初期設定)", target.Name:GetText())
          assert.are.equal("左ボタン", target.BindingText:GetText())
          -- the same pooled row reused for a spell called like a UI word, then a macro
          C.row(2, { name = "Save", binding = en("BUTTON_4_STRING") })
          assert.are.equal("Save", target.Name:GetText())
          assert.are.equal("ボタン4", target.BindingText:GetText())
          -- a macro's title (the name kept); "<modifiers>-<button>"
          C.row(2, { name = string.format(en("CLICK_BINDING_MACRO_TITLE"), "Macros"), binding = "SHIFT-Left Button" })
          alt(true); alt(false)
          assert.are.equal("Macros (マクロ)", target.Name:GetText())
          -- the modifier key names stay as written, the button word is Japanese
          assert.are.equal("SHIFT-左ボタン", target.BindingText:GetText())
          C.row(2, { name = "|cff808080Macros (Macro)|r", binding = "SHIFT-CTRL-Button 4" })
          assert.are.equal("|cff808080Macros (マクロ)|r", target.Name:GetText())
          assert.are.equal("SHIFT-CTRL-ボタン4", target.BindingText:GetText())
          alt(true)
          assert.are.equal("SHIFT-CTRL-Button 4", target.BindingText:GetText())
          alt(false)
          C.row(2, { name = "Fireball", binding = "SHIFT-Something" }) -- a spell's name; no button word: as written
          assert.are.equal("SHIFT-Something", target.BindingText:GetText())
          assert.is_true(unrecorded(target.Name))
          C.row(2, { name = "Save", binding = "SHIFT-ALT-Button 4" })
          assert.are.equal("SHIFT-ALT-ボタン4", target.BindingText:GetText())
          C.row(2, { name = "Save", binding = "SHIFT-Frostbolt" }) -- not a button word: stays as written
          assert.are.equal("SHIFT-Frostbolt", target.BindingText:GetText())
        end)

      it("a row the window re-inits directly (after a binding is set) is translated again",
        function()
          local row = C.row(4, { name = "Save", binding = en("LEFT_BUTTON_STRING") })
          assert.are.equal("左ボタン", row.BindingText:GetText())
          -- a direct Init, no ScrollBox callback
          function row.Init(self) self.BindingText.text = "SHIFT-Left Button" end
          WFJ.ClickBinding.onRow(row) -- first sight hooks the row's own Init
          row:Init()
          assert.are.equal("SHIFT-左ボタン", row.BindingText:GetText())
        end)

      it("the colour-wrapped prompts are Japanese inside their colour", function()
        local row = C.row(3, { name = "", binding = "|cff19ff19" .. en("CLICK_BINDINGS_NEW_EMPTY_PROMPT") .. "|r" })
        assert.are.equal("|cff19ff19呪文かマクロをクリックして始めます|r", row.BindingText:GetText())
        C.row(3, { name = "Save", binding = "|cffff2020" .. en("CLICK_BINDINGS_UNBOUND_TEXT") .. "|r" })
        assert.are.equal("|cffff2020未設定 - マウスを合わせてクリックで設定|r", row.BindingText:GetText())
        alt(true)
        assert.are.equal("|cffff2020Unbound - Mouseover and click to set|r", row.BindingText:GetText())
        alt(false)
      end)

      it("the checkbox and portrait tooltips are Japanese", function()
        local f, tt = _G.ClickBindingFrame, _G.GameTooltip
        tt:SetOwner(f.EnableMouseoverCastCheckbox)
        tt:SetText(en("OPTION_TOOLTIP_ENABLE_MOUSEOVER_CAST"))
        assert.are.equal("有効にすると…", _G.GameTooltipTextLeft1:GetText())
        tt:SetOwner(f.MacrosPortrait)
        tt:SetText(en("MACROS"))
        assert.are.equal("マクロ", _G.GameTooltipTextLeft1:GetText())
      end)
    end)
  end

  it("hooks install once", function()
    setup(true)
    assert.is_false(WFJ.ClickBinding.setup())
    assert.are.equal(1, #Stub.hooks["ClickBindingFrame:SetTitle"])
    assert.are.equal(1, #Stub.hooks["TutorialFrame:SetTitle"])
    assert.are.equal(1, #_G.ClickBindingFrame.ScrollBox.initCallbacks)
  end)

  it("client names bound to the wrong type degrade to untouched English with no error", function()
    load()
    local f = loadClickBinding()
    f.TutorialFrame = "nope"
    f.ScrollBox = 42
    f.SaveButton = true
    f.EnableMouseoverCastCheckbox = false
    assert.has_no.errors(function() assert.is_true(WFJ.ClickBinding.init()) end)
    assert.are.equal("バインドを追加", f.AddBindingButton:GetText()) -- the rest still works
    assert.has_no.errors(function() WFJ.ClickBinding.onRow("x") end)
  end)

  it("a client without the window: init returns false and hooks nothing", function()
    load()
    local before = 0
    for _ in pairs(Stub.hooks) do before = before + 1 end
    assert.is_false(WFJ.ClickBinding.init())
    Stub.loadedAddons[ADDON] = true -- the addon name loaded, but no ClickBindingFrame
    assert.is_false(WFJ.ClickBinding.init())
    assert.is_false(WFJ.ClickBinding.setup())
    local after = 0
    for _ in pairs(Stub.hooks) do after = after + 1 end
    assert.are.equal(before, after)
  end)
end)
