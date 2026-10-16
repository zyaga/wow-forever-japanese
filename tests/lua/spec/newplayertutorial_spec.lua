local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

-- Camelot's new player experience. Stubs of:
--   blizzard_newplayerexperience/camelot/blizzard_tutorialkeyboardmouseframe.xml:5–121: the keyboard and mouse window
--     (static Text, the Okay and Skip Tutorial buttons, the Skip button's prompt and its OnShow anchor, xml:56–61)
--     and the walk prompt (static ContainerFrame.Text; TutorialWalkMixin:_SetContent only writes key bindings,
--     blizzard_tutorialkeyboardmouseframe.lua:127–132). Both exist once Blizzard_NewPlayerExperience loads.
--   blizzard_tutorialmanager/blizzard_tutorialmainframe.lua:88–140 (TutorialMainFrame_Frame:_SetContent) and
--     :245–262 (TutorialSingleKey_Frame:_SetContent, its key text and the key box's width, :234–243). The tutorial
--     manager is loaded at login.
local FILES = {}
for _, f in ipairs(H.UI_FILES) do FILES[#FILES + 1] = f end
FILES[#FILES + 1] = "UI/NewPlayerTutorial.lua"

local ADDON = "Blizzard_NewPlayerExperience"

local UI = {
  NPEV2_INTRO_TO_MOUSE_AND_KEYBOARD = { "Position your hands and click |cFFFFD200Okay|r",
    "手を置いて|cFFFFD200決定|rをクリックしましょう" },
  OKAY = { "Okay", "決定" },
  NPEV2_SKIP_TUTORIAL_BUTTON = { "Skip Tutorial", "チュートリアルを飛ばす" },
  NPEV2_SKIP_TUTORIAL_PROMPT = { "Played World of Warcraft before?", "World of Warcraftを遊んだことがありますか？" },
  NPEV2_INTRO_MOVE_ALLIANCE = { "|cFFFFD200Walk around|r", "|cFFFFD200歩き回りましょう|r" },
  NPEV2_INTRO_CAMERA_LOOK = { "|cFFFFD200Look around|r", "|cFFFFD200周りを見回しましょう|r" },
  NPEV2_INTRO_QUESTGIVER_INTERACT_HUMAN = { "|cFFFFD200Talk|r to Deputy Willem",
    "Deputy Willemに|cFFFFD200話しかけましょう|r" },
  NPEV2_LOOT_CORPSE = { "|cFFFFD200Loot|r the corpse", "死体から|cFFFFD200戦利品を取りましょう|r" },
  NPEV2_PLACE_ABILITY_BACK_ON_ACTION_BAR = { "Place %s back on your Action Bar to use it again.",
    "%sをアクションバーに戻すと、また使えます。" },
  NPEV2_FINDCORPSE = { "|cFFFFD200Open your map|r to find your corpse", "|cFFFFD200地図を開いて|r死体を探しましょう" },
  NPE_UNBOUND_KEYBIND = { "[Unbound]", "[未設定]" },
  RAID = { "Raid", "レイド" }, -- a dictionary word that is no tutorial key
}

local KEY_BIND_PADDING = 31 -- blizzard_tutorialmainframe.lua:16

-- the width of a line as drawn: colour codes take no room, a kana or kanji twice an ASCII letter
local function stringWidth(fs)
  local w = 0
  for ch in (fs.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    w = w + (#ch == 1 and 6 or 13)
  end
  return w
end

local function measured(text)
  local fs = Stub.fontString(text or "")
  fs.GetStringWidth = stringWidth
  fs.GetStringHeight = function(f) return Stub.textHeight(f.text, f.font, 100000) end
  fs.SetHeight = function(f, h) f.height = h end
  return fs
end

local function layoutFrame(name, parent)
  local f = CreateFrame("Frame", name, parent)
  f.dirty = 0
  function f:MarkDirty() self.dirty = self.dirty + 1 end
  function f:GetParent() return self.parent end
  function f:ClearAllPoints() self.point = nil end
  return f
end

-- TutorialMainFrame_Frame (mainframe.xml:5–58) and its writer, mainframe.lua:88–100, 138
local function buildMain()
  local frame = layoutFrame("TutorialMainFrame_Frame")
  local container = layoutFrame(nil, frame)
  container.Text = measured("")
  frame.ContainerFrame = container
  function frame:_SetContent(content)
    content = content or self.DesiredContent
    self.DesiredContent = nil
    local text = self.ContainerFrame.Text
    if content.text then
      text:SetSize(0, 0)
      text:SetText(content.text)
      text:SetWidth(text:GetStringWidth())
      text:SetHeight(text:GetStringHeight())
    end
    self.ContainerFrame:MarkDirty()
  end
  return frame
end

-- TutorialSingleKey_Frame (mainframe.xml:60–95) and its writer, mainframe.lua:234–262
local function buildSingleKey()
  local frame = layoutFrame("TutorialSingleKey_Frame")
  local container = layoutFrame(nil, frame)
  container.Text = measured("")
  container.KeyBind = CreateFrame("Frame", nil, container)
  container.KeyBind.KeyBind = measured("")
  frame.ContainerFrame = container
  function frame:_SetContent(content)
    content = content or self.DesiredContent
    self.DesiredContent = nil
    local box = self.ContainerFrame.KeyBind
    if content.keyText and content.keyText ~= "" then
      box.KeyBind:SetText(content.keyText)
      box:SetWidth(box.KeyBind:GetStringWidth() + KEY_BIND_PADDING)
    end
    local text = self.ContainerFrame.Text
    if content.text then
      text:SetSize(0, 0)
      text:SetText(content.text)
      text:SetWidth(text:GetStringWidth())
      text:SetHeight(text:GetStringHeight())
    end
    self.ContainerFrame:MarkDirty()
  end
  return frame
end

-- TutorialKeyboardMouseFrame_Frame and TutorialWalk_Frame (camelot xml:5–121), created when the addon loads
local function buildKeyboardMouse()
  local frame = layoutFrame("TutorialKeyboardMouseFrame_Frame")
  frame.Text = measured(_G.NPEV2_INTRO_TO_MOUSE_AND_KEYBOARD)
  local okay = Stub.button("KeyboardMouseConfirmButton", _G.OKAY)
  okay.parent = frame
  frame.ConfirmButton = okay
  local skip = Stub.button("SkipTutorialButton", _G.NPEV2_SKIP_TUTORIAL_BUTTON)
  skip.parent = frame
  function skip:GetParent() return self.parent end
  function skip:ClearAllPoints() self.point = nil end
  skip.SkipTutorialPrompt = measured(_G.NPEV2_SKIP_TUTORIAL_PROMPT)
  skip:SetScript("OnShow", function(self) -- xml:56–61
    local textWidth = self.SkipTutorialPrompt:GetStringWidth()
    self:ClearAllPoints()
    self:SetPoint("TOP", self:GetParent().ConfirmButton, "BOTTOM", (textWidth + 20) / 2, -30)
  end)
  frame.SkipTutorialButton = skip
  function frame:ShowTutorial() self:Show(); self.SkipTutorialButton:Show() end
  return frame
end

local function buildWalk()
  local frame = layoutFrame("TutorialWalk_Frame")
  local container = layoutFrame(nil, frame)
  container.Text = measured(_G.NPEV2_INTRO_MOVE_ALLIANCE)
  frame.ContainerFrame = container
  function frame:_SetContent() -- lua:127–132: key bindings only
    self:MarkDirty()
    self.ContainerFrame:MarkDirty()
  end
  return frame
end

local GLOBALS = { "TutorialMainFrame_Frame", "TutorialSingleKey_Frame", "TutorialKeyboardMouseFrame_Frame",
  "TutorialWalk_Frame", "KeyboardMouseConfirmButton", "SkipTutorialButton" }

describe("UI/NewPlayerTutorial: camelot's new player experience", function()
  local WFJ, main, single, kbm, walk

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  local function loadNPE()
    kbm, walk = buildKeyboardMouse(), buildWalk()
    Stub.loadedAddons[ADDON] = true
    return WFJ.LoadOnDemand.loaded(ADDON)
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    main, single = buildMain(), buildSingleKey()
  end)

  after_each(function()
    H.uiTeardown()
    for _, name in ipairs(GLOBALS) do _G[name] = nil end
  end)

  describe("the keyboard and mouse window", function()
    local function skipAnchor()
      local p = kbm.SkipTutorialButton.point
      assert.are.equal("TOP", p[1])
      assert.are.equal(kbm.ConfirmButton, p[2])
      assert.are.equal("BOTTOM", p[3])
      assert.are.equal(-30, p[5])
      return p[4]
    end

    it("waits for the addon, then shows all four texts in Japanese, redoes the Skip anchor and relays out",
      function()
        assert.is_false(WFJ.NewPlayerTutorial.init()) -- the addon loads on demand
        assert.are.equal(1, loadNPE())
        assert.are.equal(UI.NPEV2_INTRO_TO_MOUSE_AND_KEYBOARD[2], kbm.Text:GetText())
        assert.are.equal(WFJ.Font.PATH, (kbm.Text:GetFont()))
        assert.are.equal("決定", kbm.ConfirmButton:GetText())
        assert.are.equal(UI.NPEV2_SKIP_TUTORIAL_BUTTON[2], kbm.SkipTutorialButton:GetText())
        local prompt = kbm.SkipTutorialButton.SkipTutorialPrompt
        assert.are.equal(UI.NPEV2_SKIP_TUTORIAL_PROMPT[2], prompt:GetText())
        assert.are.equal((prompt:GetStringWidth() + 20) / 2, skipAnchor())
        assert.is_true(kbm.dirty > 0)
      end)

    it("on show the client's own anchor measures the Japanese prompt", function()
      WFJ.NewPlayerTutorial.init()
      loadNPE()
      kbm:ShowTutorial()
      local prompt = kbm.SkipTutorialButton.SkipTutorialPrompt
      assert.are.equal(UI.NPEV2_SKIP_TUTORIAL_PROMPT[2], prompt:GetText())
      assert.are.equal((stringWidth(prompt) + 20) / 2, skipAnchor())
    end)

    it("the reveal key shows the client's English, re-anchored and relaid for it; release brings the Japanese back",
      function()
        WFJ.NewPlayerTutorial.init()
        loadNPE()
        kbm:ShowTutorial()
        local prompt = kbm.SkipTutorialButton.SkipTutorialPrompt
        local before = kbm.dirty
        alt(true)
        assert.are.equal(UI.NPEV2_INTRO_TO_MOUSE_AND_KEYBOARD[1], kbm.Text:GetText())
        assert.are.equal("Okay", kbm.ConfirmButton:GetText())
        assert.are.equal("Skip Tutorial", kbm.SkipTutorialButton:GetText())
        assert.are.equal(UI.NPEV2_SKIP_TUTORIAL_PROMPT[1], prompt:GetText())
        assert.are.equal((stringWidth(prompt) + 20) / 2, skipAnchor())
        assert.is_true(kbm.dirty > before)
        alt(false)
        assert.are.equal(UI.NPEV2_SKIP_TUTORIAL_PROMPT[2], prompt:GetText())
        assert.are.equal((stringWidth(prompt) + 20) / 2, skipAnchor())
        assert.are.equal("決定", kbm.ConfirmButton:GetText())
      end)

    it("already loaded at init: shown at once", function()
      kbm, walk = buildKeyboardMouse(), buildWalk()
      Stub.loadedAddons[ADDON] = true
      assert.is_true(WFJ.NewPlayerTutorial.init())
      assert.are.equal(UI.NPEV2_INTRO_TO_MOUSE_AND_KEYBOARD[2], kbm.Text:GetText())
      assert.are.equal(UI.NPEV2_INTRO_MOVE_ALLIANCE[2], walk.ContainerFrame.Text:GetText())
    end)

    it("translation off leaves the client's English and the client's anchor", function()
      WFJ.State.setEnabled(false)
      WFJ.NewPlayerTutorial.init()
      loadNPE()
      kbm:ShowTutorial()
      assert.are.equal(UI.NPEV2_INTRO_TO_MOUSE_AND_KEYBOARD[1], kbm.Text:GetText())
      assert.are.equal("Okay", kbm.ConfirmButton:GetText())
      assert.are.equal(UI.NPEV2_SKIP_TUTORIAL_PROMPT[1], kbm.SkipTutorialButton.SkipTutorialPrompt:GetText())
      assert.are.equal(0, kbm.Text.calls.addonSetText)
      assert.are.equal((stringWidth(kbm.SkipTutorialButton.SkipTutorialPrompt) + 20) / 2, skipAnchor())
      WFJ.State.setEnabled(true) -- switched on later: Japanese, re-anchored
      assert.are.equal(UI.NPEV2_SKIP_TUTORIAL_PROMPT[2], kbm.SkipTutorialButton.SkipTutorialPrompt:GetText())
      assert.are.equal((stringWidth(kbm.SkipTutorialButton.SkipTutorialPrompt) + 20) / 2, skipAnchor())
    end)
  end)

  describe("the screen prompt (TutorialMainFrame_Frame)", function()
    local function sizedFor(text)
      assert.are.equal(stringWidth(text), text.width)
      assert.are.equal(text:GetStringHeight(), text.height)
    end

    it("a prompt is Japanese and the text box is measured for it; the container relays out", function()
      WFJ.NewPlayerTutorial.init()
      local text = main.ContainerFrame.Text
      main:_SetContent({ text = _G.NPEV2_INTRO_CAMERA_LOOK })
      assert.are.equal(UI.NPEV2_INTRO_CAMERA_LOOK[2], text:GetText())
      assert.are.equal(WFJ.Font.PATH, (text:GetFont()))
      sizedFor(text)
      assert.are.equal(2, main.ContainerFrame.dirty) -- the client's, then the refit's
    end)

    it("the reveal key shows the English measured for the English; translation off too", function()
      WFJ.NewPlayerTutorial.init()
      local text = main.ContainerFrame.Text
      main:_SetContent({ text = _G.NPEV2_INTRO_QUESTGIVER_INTERACT_HUMAN })
      assert.are.equal(UI.NPEV2_INTRO_QUESTGIVER_INTERACT_HUMAN[2], text:GetText())
      alt(true)
      assert.are.equal(UI.NPEV2_INTRO_QUESTGIVER_INTERACT_HUMAN[1], text:GetText())
      sizedFor(text)
      alt(false)
      assert.are.equal(UI.NPEV2_INTRO_QUESTGIVER_INTERACT_HUMAN[2], text:GetText())
      sizedFor(text)
      WFJ.State.setEnabled(false)
      assert.are.equal(UI.NPEV2_INTRO_QUESTGIVER_INTERACT_HUMAN[1], text:GetText())
      sizedFor(text)
    end)

    it("a later write with no content (the fade-out's finish) is read off the text, not the argument", function()
      WFJ.NewPlayerTutorial.init()
      main:_SetContent({ text = _G.NPEV2_INTRO_CAMERA_LOOK })
      main.DesiredContent = { text = _G.NPEV2_LOOT_CORPSE }
      main:_SetContent() -- _AnimateOut's Finish (mainframe.lua:210–216)
      assert.are.equal(UI.NPEV2_LOOT_CORPSE[2], main.ContainerFrame.Text:GetText())
      sizedFor(main.ContainerFrame.Text)
    end)

    it("a prompt naming a spell keeps the spell's name as the client wrote it", function()
      WFJ.NewPlayerTutorial.init()
      local live = _G.NPEV2_PLACE_ABILITY_BACK_ON_ACTION_BAR:format("|cFF00FFFFHeroic Strike|r")
      main:_SetContent({ text = live })
      assert.are.equal("|cFF00FFFFHeroic Strike|rをアクションバーに戻すと、また使えます。",
        main.ContainerFrame.Text:GetText())
      alt(true)
      assert.are.equal(live, main.ContainerFrame.Text:GetText())
    end)

    it("a text outside the prompt keys stays the client's; the earlier prompt's record goes", function()
      WFJ.NewPlayerTutorial.init()
      main:_SetContent({ text = _G.NPEV2_INTRO_CAMERA_LOOK })
      main:_SetContent({ text = _G.RAID })
      assert.are.equal("Raid", main.ContainerFrame.Text:GetText())
      alt(true); alt(false)
      assert.are.equal("Raid", main.ContainerFrame.Text:GetText())
    end)
  end)

  describe("the single-key prompt (TutorialSingleKey_Frame)", function()
    it("the prompt and an unbound key are Japanese; the key box is widened for the Japanese", function()
      WFJ.NewPlayerTutorial.init()
      single:_SetContent({ text = _G.NPEV2_FINDCORPSE, keyText = _G.NPE_UNBOUND_KEYBIND })
      local box, text = single.ContainerFrame.KeyBind, single.ContainerFrame.Text
      assert.are.equal(UI.NPEV2_FINDCORPSE[2], text:GetText())
      assert.are.equal("[未設定]", box.KeyBind:GetText())
      assert.are.equal(stringWidth(box.KeyBind) + KEY_BIND_PADDING, box.size[1])
      assert.are.equal(stringWidth(text), text.width)
      alt(true)
      assert.are.equal("[Unbound]", box.KeyBind:GetText())
      assert.are.equal(stringWidth(box.KeyBind) + KEY_BIND_PADDING, box.size[1])
      assert.are.equal(UI.NPEV2_FINDCORPSE[1], text:GetText())
      assert.are.equal(stringWidth(text), text.width)
    end)

    it("a bound key is a key name and stays as written", function()
      WFJ.NewPlayerTutorial.init()
      single:_SetContent({ text = _G.NPEV2_FINDCORPSE, keyText = "M" })
      assert.are.equal("M", single.ContainerFrame.KeyBind.KeyBind:GetText())
      assert.are.equal(UI.NPEV2_FINDCORPSE[2], single.ContainerFrame.Text:GetText())
    end)
  end)

  describe("the walk prompt (TutorialWalk_Frame)", function()
    it("its static text is Japanese at load and after the client's _SetContent; the reveal key shows the English",
      function()
        WFJ.NewPlayerTutorial.init()
        loadNPE()
        local text = walk.ContainerFrame.Text
        assert.are.equal(UI.NPEV2_INTRO_MOVE_ALLIANCE[2], text:GetText())
        assert.is_true(walk.ContainerFrame.dirty > 0)
        walk:_SetContent()
        assert.are.equal(UI.NPEV2_INTRO_MOVE_ALLIANCE[2], text:GetText())
        alt(true)
        assert.are.equal(UI.NPEV2_INTRO_MOVE_ALLIANCE[1], text:GetText())
        alt(false)
        assert.are.equal(UI.NPEV2_INTRO_MOVE_ALLIANCE[2], text:GetText())
      end)
  end)

  it("hooks once: a second init and a second load add no hook", function()
    WFJ.NewPlayerTutorial.init()
    loadNPE()
    WFJ.NewPlayerTutorial.init()
    WFJ.NewPlayerTutorial.setup()
    assert.are.equal(1, #Stub.hooks["TutorialMainFrame_Frame:_SetContent"])
    assert.are.equal(1, #Stub.hooks["TutorialSingleKey_Frame:_SetContent"])
    assert.are.equal(1, #Stub.hooks["TutorialWalk_Frame:_SetContent"])
  end)

  it("no tutorial frames (a client without them): init and setup return false, no error", function()
    _G.TutorialMainFrame_Frame, _G.TutorialSingleKey_Frame = nil, nil
    local W = H.loadChunks(FILES)
    H.uiSetup(W, UI)
    assert.is_false(W.NewPlayerTutorial.init())
    Stub.loadedAddons[ADDON] = true
    assert.are.equal(1, W.LoadOnDemand.loaded(ADDON))
    assert.is_false(W.NewPlayerTutorial.setup())
  end)
end)
