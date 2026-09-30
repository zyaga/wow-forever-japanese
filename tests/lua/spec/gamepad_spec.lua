-- UI/Gamepad.lua over the gamepad-mode HUD replayed from camelot's Blizzard_GamepadSharedUtility /
-- Blizzard_Gamepad (inputprompts.lua:34–42, inputlegendpromptgroup.lua:94–121,
-- gamepadpersistentinputlegend.lua:133–168,
-- gamepadradial.lua:867–909 / 1076–1092 / 1164–1192, consoletemplates.lua:135–147, framereformutility.lua:138–171) and
-- UI/MenusUntagged's gamepad "More Actions" menu recognition (promptedbinding.lua:126–181).
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/Gamepad.lua"

-- Forever GlobalStrings (build 1.60.1.70009) → a test Japanese
local UI = {
  FRAME_ACTION_BACK = { "Back", "戻る" }, -- owns its Japanese (UIStrings.OWN): the slot below shares the English
  BACKSLOT = { "Back", "背中" },
  ACTION_LABEL_SELECT = { "Select", "選択" },
  OKAY = { "Okay", "OK" }, -- a footer label that is an ordinary key (StackSplit's okay binding)
  PROMPT_ZOOM_IN_CAMERA = { "Zoom In Camera", "カメラをズームイン" },
  PROMPT_FRIENDLY_TARGETING_ACTIONS = { "Friendly Targeting Actions", "味方ターゲットの操作" },
  FRAME_LABEL_MAIN_MENU = { "Main Menu", "メインメニュー" },
  RADIAL_LABEL_BAGS = { "Bags", "バッグ" },
  RADIAL_LABEL_TOGGLE_SIT = { "Sit/Stand", "座る/立つ" },
  SKIP = { "Skip", "スキップ" },
  TRAIN = { "Train", "訓練" }, -- the trainer's footer label
  RADIAL_LABEL_TRAIN = { "Train", "汽車" }, -- the radial's emote; owns its Japanese (UIStrings.OWN)
}

local function fontString(text) return Stub.fontString(text) end

-- An InputPromptMixin as the client defines it; RefreshInputPromptSize records the width it is asked to fit.
local function installPromptMixin()
  _G.InputPromptMixin = {
    SetPromptText = function(self, text)
      self.ControlDescText.FontString:SetText(text)
      self.ControlDescText:SetWidth(self.ControlDescText.FontString:GetWidth())
      self:RefreshInputPromptSize()
    end,
    RefreshInputPromptSize = function(self) self.refreshed = (self.refreshed or 0) + 1 end,
    SetPromptFont = function(self, fontObject) -- inputprompts.lua:44–49: SetFontObject puts the client's face back
      self.ControlDescText.FontString:SetFontObject(fontObject)
    end,
  }
end

-- A prompt frame made from the mixin as it is at this moment (Mixin copies the methods), under a legend.
local function promptFrame(legend)
  local fs = fontString("")
  function fs:GetWidth() return #self.text * 7 end
  local container = { GetParent = function() return legend end }
  local frame = { ControlDescText = { FontString = fs, SetWidth = function(self, w) self.width = w end } }
  for k, v in pairs(_G.InputPromptMixin) do frame[k] = v end
  frame.GetParent = function() return container end
  return frame
end

describe("the gamepad-mode HUD on Forever", function()
  local WFJ, frames

  local function setup(install)
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    frames = {}
    _G.EnumerateFrames = function(prev)
      local i = 0
      if prev then for j, f in ipairs(frames) do if f == prev then i = j end end end
      return frames[i + 1]
    end
    installPromptMixin()
    if install then install() end
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
  end

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    _G.InputPromptMixin, _G.GamepadRadial, _G.GamepadMode, _G.EnumerateFrames = nil, nil, nil, nil
    _G.GamepadMovieSkipButton = nil
  end)

  it("a footer prompt made after load shows Japanese, is re-fitted and its legend re-laid out; Alt shows English",
    function()
      setup()
      assert.is_truthy(WFJ.Gamepad.init())
      local legend = { laidOut = 0 }
      function legend:ApplyDefaultPromptPositioning() self.laidOut = self.laidOut + 1 end
      local prompt = promptFrame(legend) -- copies the hooked mixin, like a frame the client makes now
      prompt:SetPromptText("Back")
      local fs = prompt.ControlDescText.FontString
      assert.are.equal("戻る", fs:GetText())
      assert.are.equal(#"戻る" * 7, prompt.ControlDescText.width) -- sized to the Japanese, as the writer sizes
      assert.is_true(legend.laidOut >= 1)
      Stub.keys.alt = true
      WFJ.Modifier.refresh()
      assert.are.equal("Back", fs:GetText())
      assert.are.equal(#"Back" * 7, prompt.ControlDescText.width)
      Stub.keys.alt = false
      WFJ.Modifier.refresh()
      assert.are.equal("戻る", fs:GetText())
    end)

  it("a prompt made before load is hooked on its own and its current label is taken at init", function()
    setup()
    local legend = { ApplyDefaultPromptPositioning = function() end }
    local old = promptFrame(legend) -- holds the unhooked method
    frames[1] = old
    old:SetPromptText("Select")
    assert.are.equal("Select", old.ControlDescText.FontString:GetText())
    WFJ.Gamepad.init()
    assert.are.equal("選択", old.ControlDescText.FontString:GetText())
    old:SetPromptText("Back") -- a focus change rewrites it in English
    assert.are.equal("戻る", old.ControlDescText.FontString:GetText())
  end)

  it("any label that is exactly a dictionary English is taken; anything else stays as written", function()
    setup()
    WFJ.Gamepad.init()
    local prompt = promptFrame({})
    prompt:SetPromptText("Okay")
    assert.are.equal("OK", prompt.ControlDescText.FontString:GetText())
    prompt:SetPromptText("Issue Reporter") -- a literal the client writes (blizzard_ptrfeedback_gamepad.lua:156)
    assert.are.equal("Issue Reporter", prompt.ControlDescText.FontString:GetText())
  end)

  it("the persistent legend's colour-wrapped header keeps its colour around the Japanese", function()
    setup()
    WFJ.Gamepad.init()
    local entry = promptFrame({})
    entry:SetPromptText("|cffffffffFriendly Targeting Actions|r")
    assert.are.equal("|cffffffff味方ターゲットの操作|r", entry.ControlDescText.FontString:GetText())
    entry:SetPromptText("Zoom In Camera")
    assert.are.equal("カメラをズームイン", entry.ControlDescText.FontString:GetText())
  end)

  it("\"Train\" is the trainer's 訓練 on a footer and the emote 汽車 on the radial (the owned key stays on the radial)",
    function()
      setup(function()
        local seg = { IconLabel = fontString("") }
        _G.GamepadRadial = { HeaderText = fontString("Main Menu"), SegmentList = { seg } }
        _G.GamepadRadial.ActivateRadial = function() seg.IconLabel:SetText("Train") end
      end)
      WFJ.Gamepad.init()
      local prompt = promptFrame({})
      prompt:SetPromptText("Train")
      assert.are.equal("訓練", prompt.ControlDescText.FontString:GetText())
      _G.GamepadRadial:ActivateRadial()
      assert.are.equal("汽車", _G.GamepadRadial.SegmentList[1].IconLabel:GetText())
    end)

  it("a font object set after the label (the legend's header rows) gets the Japanese font back", function()
    setup()
    WFJ.Gamepad.init()
    local entry = promptFrame({})
    entry:SetPromptText("|cffffffffFriendly Targeting Actions|r")
    local fs = entry.ControlDescText.FontString
    assert.are.equal(WFJ.Font.PATH, (fs:GetFont()))
    entry:SetPromptFont({ font = { path = "Fonts\\FRIZQT__.TTF", size = 12, flags = "" } })
    assert.are.equal("|cffffffff味方ターゲットの操作|r", fs:GetText())
    assert.are.equal(WFJ.Font.PATH, (fs:GetFont()))
    Stub.keys.alt = true
    WFJ.Modifier.refresh()
    assert.are.equal("|cffffffffFriendly Targeting Actions|r", fs:GetText())
    Stub.keys.alt = false
    WFJ.Modifier.refresh()
  end)

  it("the radial menu's header, segments and D-pad indicators show Japanese on every ActivateRadial", function()
    setup(function()
      local seg = { IconLabel = fontString("") }
      local indicator = { Label = fontString("") }
      local selector = { indicators = { top = indicator } }
      selector.SetMenuOptions = function() indicator.Label:SetText("Sit/Stand") end
      _G.GamepadRadial = { HeaderText = fontString("Main Menu"), SegmentList = { seg },
        ContextActionSelector = selector }
      function _G.GamepadRadial:ActivateRadial()
        self.HeaderText:SetText("Main Menu")
        seg.IconLabel:SetText("Bags")
      end
    end)
    WFJ.Gamepad.init()
    local radial = _G.GamepadRadial
    radial:ActivateRadial(1)
    assert.are.equal("メインメニュー", radial.HeaderText:GetText())
    assert.are.equal("バッグ", radial.SegmentList[1].IconLabel:GetText())
    radial.ContextActionSelector:SetMenuOptions({})
    assert.are.equal("座る/立つ", radial.ContextActionSelector.indicators.top.Label:GetText())
  end)

  it("the skip button made later shows Japanese through its per-frame rewrite, the held countdown included", function()
    setup(function()
      _G.GamepadMode = {
        CreateHoldButtonWithTextFromTemplate = function(name, _, _, text)
          local button = CreateFrame("BUTTON", name)
          button.text = fontString(text)
          button.originalText = text
          button:SetScript("OnUpdate", function(self)
            self.text:SetText(self.buttonHeld and (self.originalText .. " 2") or self.originalText)
          end)
          _G[name] = button
          return button
        end,
      }
    end)
    WFJ.Gamepad.init()
    local button = _G.GamepadMode.CreateHoldButtonWithTextFromTemplate("GamepadMovieSkipButton", {}, nil, "Skip")
    button.scripts.OnUpdate(button)
    assert.are.equal("スキップ", button.text:GetText())
    button.buttonHeld = true
    button.scripts.OnUpdate(button)
    assert.are.equal("スキップ 2", button.text:GetText())
  end)

  it("without the gamepad HUD init returns false and raises nothing", function()
    setup()
    _G.InputPromptMixin = nil
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    assert.has_no.errors(function() assert.is_false(WFJ.Gamepad.init()) end)
  end)
end)

describe("the gamepad \"More Actions\" menu is the tagged MORE_CONTEXT_ACTIONS menu", function()
  it("UI/MenusTags appends UI/Gamepad's MENU_KEYS to that tag", function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    local files = {}
    for i, f in ipairs(H.UI_FILES) do files[i] = f end
    for _, f in ipairs({ "UI/MenusUnit.lua", "UI/Gamepad.lua", "UI/Menus.lua", "UI/MenusTags.lua" }) do
      files[#files + 1] = f
    end
    local WFJ = H.loadChunks(files)
    local keys = {}
    for _, k in ipairs(WFJ.Menus.TAGS.MORE_CONTEXT_ACTIONS.keys) do keys[k] = true end
    for _, k in ipairs(WFJ.Gamepad.MENU_KEYS) do assert.is_true(keys[k], k) end
    assert.is_true(keys.CONTEXT_ACTION_LABEL_SEE_IN_BAG) -- the tag's own keys stay
  end)
end)
