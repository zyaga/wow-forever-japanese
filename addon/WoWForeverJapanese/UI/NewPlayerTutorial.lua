-- UI/NewPlayerTutorial.lua: camelot's new player experience on Forever (surface "npe", area "ui", ADR-016). It runs
-- below level 10 (blizzard_newplayerexperience/camelot/blizzard_tutorialdata.lua:16). Its pointer arrows go through
-- UI/HelpTips; this file owns its screen prompts:
--   the keyboard and mouse window, TutorialKeyboardMouseFrame_Frame (camelot/blizzard_tutorialkeyboardmouseframe.xml:
--     5–69): Text NPEV2_INTRO_TO_MOUSE_AND_KEYBOARD, the Okay button OKAY, the Skip Tutorial button
--     NPEV2_SKIP_TUTORIAL_BUTTON and its prompt NPEV2_SKIP_TUTORIAL_PROMPT, all written by the XML only. The Skip
--     button's OnShow anchors it below the Okay button by half the prompt's width (xml:56–61), so the refit redoes
--     that anchor for the text now shown, and marks the window's layout dirty (a ResizeLayoutFrame, xml:5);
--   the walk prompt, TutorialWalk_Frame (xml:71–121): ContainerFrame.Text NPEV2_INTRO_MOVE_ALLIANCE, static; its
--     _SetContent only writes the movement keys (blizzard_tutorialkeyboardmouseframe.lua:96–132), which stay;
--   the screen prompt, TutorialMainFrame_Frame (blizzard_tutorialmanager/blizzard_tutorialmainframe.xml:5–58):
--     _SetContent writes ContainerFrame.Text, sets its size to the text's own and marks the container dirty
--     (blizzard_tutorialmainframe.lua:88–140). The fade-out's finish calls it again with no content
--     (:210–216), so the hook reads the text off the FontString, never the argument;
--   the single-key prompt, TutorialSingleKey_Frame (mainframe.xml:60–95): _SetContent writes the key's box
--     (ContainerFrame.KeyBind, its width the key text's + 31) and then the text like the screen prompt
--     (mainframe.lua:16, 234–262). A bound key is a key name and stays; the unbound key's word is translated.
-- The keyboard and mouse window and the walk prompt exist once Blizzard_NewPlayerExperience loads (load on demand,
-- blizzard_newplayerexperience.toc:2); they are rewritten then and again on the window's show. The tutorial
-- manager's two frames are hooked at init and again when the new player experience loads (it requires the manager,
-- toc:3). The records stay across hides: the static texts never change and a hook re-shows a written prompt.
local _, WFJ = ...
local NewPlayerTutorial = {}
WFJ.NewPlayerTutorial = NewPlayerTutorial

local SURFACE = "npe"
NewPlayerTutorial.SURFACE = SURFACE
local Compat = WFJ.Compat

NewPlayerTutorial.NEVER_TOUCH = {}

local ADDON = "Blizzard_NewPlayerExperience"

-- the screen prompt's texts (blizzard_newplayerexperience/blizzard_tutorialtutorials.lua:127, 227, 3315, 3482, 3488;
-- the starting quest giver per race, camelot/blizzard_tutorialdata.lua:300–312)
local MAIN = { only = { "NPEV2_INTRO_CAMERA_LOOK", "NPEV2_INTRO_QUESTGIVER_INTERACT_HUMAN",
  "NPEV2_INTRO_QUESTGIVER_INTERACT_DWARF", "NPEV2_INTRO_QUESTGIVER_INTERACT_NIGHTELF",
  "NPEV2_INTRO_QUESTGIVER_INTERACT_SCOURGE", "NPEV2_INTRO_QUESTGIVER_INTERACT_ORC",
  "NPEV2_INTRO_QUESTGIVER_INTERACT_TAUREN", "NPEV2_INTRO_QUESTGIVER_INTERACT_SKYBORNE", "NPEV2_START_ATTACKING",
  "NPEV2_LOOT_CORPSE", "NPEV2_PLACE_ABILITY_BACK_ON_ACTION_BAR" } }
local SINGLE = { only = { "NPEV2_FINDCORPSE" } } -- tutorialtutorials.lua:3131
-- the key box when the binding is unset (tutorialhelper.lua:284–296)
local UNBOUND = { only = { "NPE_UNBOUND_KEYBIND" } }
local INTRO = { only = { "NPEV2_INTRO_TO_MOUSE_AND_KEYBOARD" } }
local OKAY = { only = { "OKAY" } }
local SKIP = { only = { "NPEV2_SKIP_TUTORIAL_BUTTON" } }
local PROMPT = { only = { "NPEV2_SKIP_TUTORIAL_PROMPT" } }
local WALK = { only = { "NPEV2_INTRO_MOVE_ALLIANCE" } }

local SKIP_GAP, SKIP_Y = 20, -30 -- camelot xml:57, 60
local KEY_BIND_PADDING = 31 -- mainframe.lua:16

local CANDIDATES = {
  main = { "TutorialMainFrame_Frame" },
  single = { "TutorialSingleKey_Frame" },
  kbm = { "TutorialKeyboardMouseFrame_Frame" },
  kbmText = { "TutorialKeyboardMouseFrame_Frame.Text" },
  okay = { "KeyboardMouseConfirmButton" },
  skip = { "SkipTutorialButton" },
  prompt = { "SkipTutorialButton.SkipTutorialPrompt" },
  walk = { "TutorialWalk_Frame" },
  walkText = { "TutorialWalk_Frame.ContainerFrame.Text" },
}

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
end

local function markDirty(frame)
  if type(frame) == "table" and type(frame.MarkDirty) == "function" then frame:MarkDirty() end
end

-- the client's own measure of a prompt's text (mainframe.lua:96–99)
local function fitText(text)
  if type(text) ~= "table" or type(text.GetStringWidth) ~= "function" or type(text.GetStringHeight) ~= "function"
      or type(text.SetSize) ~= "function" then
    return
  end
  text:SetSize(0, 0)
  text:SetWidth(text:GetStringWidth())
  text:SetHeight(text:GetStringHeight())
end

-- The keyboard and mouse window's refit: the Skip button's anchor as its OnShow sets it, for the prompt shown now.
function NewPlayerTutorial.refitKeyboardMouse()
  local skip, prompt, okay = get("skip"), get("prompt"), get("okay")
  if type(skip) == "table" and type(prompt) == "table" and type(prompt.GetStringWidth) == "function"
      and type(skip.ClearAllPoints) == "function" and type(skip.SetPoint) == "function" then
    skip:ClearAllPoints()
    skip:SetPoint("TOP", okay, "BOTTOM", (prompt:GetStringWidth() + SKIP_GAP) / 2, SKIP_Y)
  end
  markDirty(get("kbm"))
end

-- The keyboard and mouse window's four texts. → the number of dictionary words found.
function NewPlayerTutorial.showKeyboardMouse()
  local refit = NewPlayerTutorial.refitKeyboardMouse
  local n = WFJ.Labels.show(SURFACE, "kbm.text", get("kbmText"), refit, INTRO)
    + WFJ.Labels.show(SURFACE, "kbm.prompt", get("prompt"), refit, PROMPT)
  n = n + WFJ.Labels.showAll(SURFACE, { { "kbm.okay", get("okay"), OKAY }, { "kbm.skip", get("skip"), SKIP } })
  return n
end

local function walkRefit()
  local walk = get("walk")
  markDirty(type(walk) == "table" and walk.ContainerFrame or nil)
end

-- The walk prompt's text (the TutorialWalk_Frame:_SetContent post-hook too). → 1 | 0
function NewPlayerTutorial.showWalk()
  return WFJ.Labels.show(SURFACE, "walk", get("walkText"), walkRefit, WALK)
end

-- A screen prompt's refit (one function per frame): the text measured for what it shows, the single-key prompt's
-- key box sized to its key text, then the layout marked dirty.
local refits = setmetatable({}, { __mode = "k" })
local function refitOf(frame)
  local fn = refits[frame]
  if not fn then
    fn = function()
      local container = frame.ContainerFrame
      if type(container) ~= "table" then return end
      fitText(container.Text)
      local box = container.KeyBind
      local key = type(box) == "table" and box.KeyBind or nil
      if type(key) == "table" and type(key.GetStringWidth) == "function" and type(box.SetWidth) == "function" then
        box:SetWidth(key:GetStringWidth() + KEY_BIND_PADDING)
      end
      markDirty(container)
    end
    refits[frame] = fn
  end
  return fn
end

-- The TutorialMainFrame_Frame:_SetContent post-hook. → 1 | 0
function NewPlayerTutorial.onMain(frame)
  if type(frame) ~= "table" or type(frame.ContainerFrame) ~= "table" then return 0 end
  return WFJ.Labels.show(SURFACE, "main", frame.ContainerFrame.Text, refitOf(frame), MAIN)
end

-- The TutorialSingleKey_Frame:_SetContent post-hook. → the number of dictionary words found.
function NewPlayerTutorial.onSingleKey(frame)
  if type(frame) ~= "table" or type(frame.ContainerFrame) ~= "table" then return 0 end
  local container = frame.ContainerFrame
  local box = container.KeyBind
  local n = WFJ.Labels.show(SURFACE, "single", container.Text, refitOf(frame), SINGLE)
  if type(box) == "table" then n = n + WFJ.Labels.show(SURFACE, "single.key", box.KeyBind, refitOf(frame), UNBOUND) end
  return n
end

local hooked = setmetatable({}, { __mode = "k" })
local function hookContent(frame, fn)
  if type(frame) ~= "table" or type(frame._SetContent) ~= "function" or hooked[frame] then return end
  hooked[frame] = true
  hooksecurefunc(frame, "_SetContent", fn)
end

local function hookManager()
  hookContent(get("main"), NewPlayerTutorial.onMain)
  hookContent(get("single"), NewPlayerTutorial.onSingleKey)
end

local shownHooked = setmetatable({}, { __mode = "k" })

-- The new player experience's part: runs once it is loaded (now, or on its ADDON_LOADED).
-- → true when the keyboard and mouse window was found.
function NewPlayerTutorial.setup()
  declare() -- its frames exist only now: forget what Compat memoized before
  hookManager()
  hookContent(get("walk"), NewPlayerTutorial.showWalk)
  NewPlayerTutorial.showWalk()
  local kbm = get("kbm")
  if type(kbm) ~= "table" then return false end
  if not shownHooked[kbm] and type(kbm.HookScript) == "function" then
    shownHooked[kbm] = true
    kbm:HookScript("OnShow", NewPlayerTutorial.showKeyboardMouse)
  end
  NewPlayerTutorial.showKeyboardMouse()
  return true
end

-- Called by Main after Compat.init, ButtonText.init and LoadOnDemand.init.
-- → true when the new player experience was already loaded.
function NewPlayerTutorial.init()
  declare()
  hookManager()
  return WFJ.LoadOnDemand.when(ADDON, NewPlayerTutorial.setup)
end
