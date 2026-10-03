-- UI/Gamepad.lua: the gamepad-mode HUD on Forever (surface "gamepad", area "ui"): the button prompts along the
-- bottom of every window, the persistent controller legend, the radial main menu, the gamepad "More Actions" menus
-- and the cinematic skip button. Blizzard_Gamepad / _GamepadSharedUtility / _GamepadTargeting load at login on
-- camelot (their .toc AllowLoadGameType / AllowLoad lines); all of it shows only in gamepad input mode
-- (InputUtil.IsGamepadUIEnabled, blizzard_sharedxml/mainline/inpututil.lua:7–13).
-- Writers [verified: Forever 1.60.1.70009 source]:
--   prompts  InputPromptMixin:SetPromptText (blizzard_gamepadsharedutility/inputprompts/inputprompts.lua:34–42) sets
--            ControlDescText.FontString, sizes ControlDescText to the text's width and calls RefreshInputPromptSize.
--            Two callers: a window footer's legend (InputPromptLegendMixin:RefreshWithPromptedBindings,
--            inputlegendpromptgroup.lua:94–121, which lays the prompts out afterwards with
--            ApplyDefaultPromptPositioning), re-run on every focus change, and the persistent legend
--            (gamepadpersistentinputlegend.lua:133–168, fixed anchors; four labels arrive colour-wrapped, the
--            `wrapped` form). Prompt frames copy the mixin when made (Mixin / mixin="…", inputprompts.xml:31, 104):
--            the mixin is post-hooked for every frame made later, and each frame that already exists is hooked on
--            its own (found once with EnumerateFrames; they are unnamed and live in no list we can reach). Never both:
--            a frame made before the mixin hook still holds the method the mixin had then (the HudLabels rule).
--            After a label changes, the prompt is re-sized exactly as the writer does and its legend re-laid out.
--   radial   GamepadRadial (gamepadradial.xml:119, made at load): ActivateRadial writes HeaderText and, through
--            FillSegmentData → GamepadRadialSegmentMixin:SetHandler, each segment's IconLabel (lua:867–909,
--            1076–1092); the context selector's SetMenuOptions writes each D-pad indicator's Label (lua:1164–1192,
--            BasicContextOptionHandler:Attach :352–360). Both are post-hooked on the instances.
--   skip     GamepadMode.CreateHoldButtonWithTextFromTemplate (framereformutility.lua:138–171) makes the cinematic /
--            movie skip button (cinematicmovie.lua:21–28); its OnUpdate rewrites the text every frame, SKIP or
--            SKIP .. " " .. n while held (consoletemplates.lua:135–147), so the button's OnUpdate is post-hooked
--            (HookScript) and the `number` form carries the countdown.
-- Elsewhere: the red radial errors (RADIAL_ERROR_*, ERROR_NO_FRAME_TO_FOCUS) are UIErrorsFrame lines UI/Errors
-- matches exactly; the "More Actions" context menus are tagged MORE_CONTEXT_ACTIONS (promptedbinding.lua:140), so
-- UI/MenusTags takes MENU_KEYS into that tag's list.
-- Never touched: the narration strings the client only speaks (NARRATION_CONTEXT_GAME_MENU, C_VoiceChat.SpeakText).
local _, WFJ = ...
local Gamepad = {}
WFJ.Gamepad = Gamepad

local SURFACE = "gamepad"
Gamepad.SURFACE = SURFACE
local Compat = WFJ.Compat

Gamepad.NEVER_TOUCH = {}

-- Every key the gamepad HUD writers show (pipeline/ui_keys.txt, the gamepad block).
Gamepad.KEYS = {
  -- window footers (the prompted-binding legends)
  "ACTION_LABEL_ADJUST_BRIGHTNESS", "ACTION_LABEL_ADJUST_COLOR", "ACTION_LABEL_ROTATE", "ACTION_LABEL_SELECT",
  "ACTION_LABEL_CHAT_CHANNELS",
  "ACTION_LABEL_SEND", "ACTION_LABEL_TAB_SETTINGS", "ACTION_LABEL_RESET_VIEW", "ACTION_LABEL_ZOOM_SLASH_ROTATE",
  "CONTEXT_ACTION_LABEL_APPLY", "CONTEXT_ACTION_LABEL_BIND_TO_GAMEPAD_ACTION_BAR", "CONTEXT_ACTION_LABEL_BUY",
  "CONTEXT_ACTION_LABEL_CAST", "CONTEXT_ACTION_LABEL_CHARACTER_VIEWER", "CONTEXT_ACTION_LABEL_CHOOSE_REWARD",
  "CONTEXT_ACTION_LABEL_CREATE_ALL", "CONTEXT_ACTION_LABEL_DETAILS", "CONTEXT_ACTION_LABEL_EQUIP",
  "CONTEXT_ACTION_LABEL_FOCUS", "CONTEXT_ACTION_LABEL_INSPECT", "CONTEXT_ACTION_LABEL_MANAGE_BAG",
  "CONTEXT_ACTION_LABEL_MORE_ACTIONS", "CONTEXT_ACTION_LABEL_MULTI_BUY", "CONTEXT_ACTION_LABEL_OPEN",
  "CONTEXT_ACTION_LABEL_OPTIONS", "CONTEXT_ACTION_LABEL_PLACE", "CONTEXT_ACTION_LABEL_READ",
  "CONTEXT_ACTION_LABEL_REPAIR", "CONTEXT_ACTION_LABEL_SELL", "CONTEXT_ACTION_LABEL_USE",
  "FRAME_ACTION_ACCEPT", "FRAME_ACTION_AMOUNT", "FRAME_ACTION_BACK", "FRAME_ACTION_CHANGE_MAP", "FRAME_ACTION_CLOSE",
  "FRAME_ACTION_COMPLETE", "FRAME_ACTION_CONFIRM", "FRAME_ACTION_CONTINUE", "FRAME_ACTION_EDIT_ACTION_BAR",
  "FRAME_ACTION_EXIT", "FRAME_ACTION_HOLD_TO_UNLEARN", "FRAME_ACTION_LOOT", "FRAME_ACTION_LOOT_ALL",
  "FRAME_ACTION_MAP_MARKER", "FRAME_ACTION_NAVIGATE", "FRAME_ACTION_OPEN_FULLMAP", "FRAME_ACTION_OPEN_MAP",
  "FRAME_ACTION_PAN", "FRAME_ACTION_ZOOM", "GAMEPAD_TALENT_ADD_POINT", "GAMEPAD_TALENT_APPLY",
  "GAMEPAD_TALENT_REMOVE_POINT", "GROUP_TARGETING_CLOSE", "NARRATION_OBJECT_CLEAR_BUTTON", "PROMPT_TOGGLE_CATEGORY",
  "PROMPT_TOGGLE_TOOLTIPS", "PURCHASE", "TRAIN",
  -- the persistent controller legend
  "BINDING_NAME_ASSISTTARGET", "BINDING_NAME_TARGETLASTHOSTILE", "PROMPT_APPLY_TARGET_MARKER", "PROMPT_AUTO_RUN",
  "PROMPT_CENTER_CAMERA", "PROMPT_CLEAR_TARGET_MARKER", "PROMPT_EXIT", "PROMPT_FLIP_CAMERA", "PROMPT_FOCUS_UI",
  "PROMPT_FRIENDLY_TARGETING", "PROMPT_FRIENDLY_TARGETING_ACTIONS", "PROMPT_HOSTILE_TARGETING",
  "PROMPT_HOSTILE_TARGETING_ACTIONS", "PROMPT_INSPECT_HUD", "PROMPT_NEXT_ACTION_PAGE", "PROMPT_NEXT_FRAME",
  "PROMPT_OPEN_BAGS", "PROMPT_PING", "PROMPT_PREVIOUS_ACTION_PAGE", "PROMPT_PREVIOUS_FRAME", "PROMPT_SHORTCUTS",
  "PROMPT_SHORTCUT_ACTIONS", "PROMPT_TARGET_GROUP_DOWN", "PROMPT_TARGET_GROUP_LEFT", "PROMPT_TARGET_GROUP_RIGHT",
  "PROMPT_TARGET_GROUP_UP", "PROMPT_TARGET_PET", "PROMPT_TARGET_SELF", "PROMPT_VIEW_BUFFS", "PROMPT_VIEW_CHAT",
  "PROMPT_VIEW_QUEST_TRACKER", "PROMPT_ZOOM_IN_CAMERA", "PROMPT_ZOOM_OUT_CAMERA",
  -- the radial main menu
  "FRAME_LABEL_MAIN_MENU", "RADIAL_LABEL_ANGRY", "RADIAL_LABEL_BAGS", "RADIAL_LABEL_BUFFS", "RADIAL_LABEL_CALENDAR",
  "RADIAL_LABEL_CHARACTER", "RADIAL_LABEL_CHAT", "RADIAL_LABEL_CHEER", "RADIAL_LABEL_CHICKEN", "RADIAL_LABEL_CLOCK",
  "RADIAL_LABEL_COLLECTIONS", "RADIAL_LABEL_DANCE", "RADIAL_LABEL_GAME_MENU", "RADIAL_LABEL_GROUP_FINDER",
  "RADIAL_LABEL_GUILD", "RADIAL_LABEL_KNEEL", "RADIAL_LABEL_LEGACY", "RADIAL_LABEL_LFD_CONTEXT_MENU",
  "RADIAL_LABEL_POINT", "RADIAL_LABEL_PROFESSIONS", "RADIAL_LABEL_PVP", "RADIAL_LABEL_QUEST_MAPS",
  "RADIAL_LABEL_SHOP", "RADIAL_LABEL_SOCIAL", "RADIAL_LABEL_SPELLBOOK", "RADIAL_LABEL_TALENTS",
  "RADIAL_LABEL_TARGET_EMOTES", "RADIAL_LABEL_TOGGLE_SIT", "RADIAL_LABEL_TRACKING", "RADIAL_LABEL_TRAIN",
  "RADIAL_LABEL_WAVE",
  -- the skip button
  "SKIP",
}
-- Each writer asks for its own set: two radial emotes own their Japanese under an English a footer also shows
-- ("Train" is the trainer's 訓練 on a footer, the emote 汽車 on the radial; "Point"), and an owned key wins any
-- match that names it (UIStrings Index:matchOnly), so it must not be in a set it does not belong to.
local function without(list, drop)
  local out = {}
  for _, key in ipairs(list) do if not drop[key] then out[#out + 1] = key end end
  return out
end
local PROMPT = { only = without(Gamepad.KEYS, { RADIAL_LABEL_POINT = true, RADIAL_LABEL_TRAIN = true }) }
local RADIAL = { only = without(Gamepad.KEYS, { TRAIN = true }) }
local SKIP = { only = { "SKIP" } }
Gamepad.PROMPT_KEYS, Gamepad.RADIAL_KEYS = PROMPT.only, RADIAL.only

-- What a HUD label may match. Every writer here is handed a whole global string (a footer binding's label, a legend
-- entry, a radial handler's label, SKIP), never a name and never a formatted template. The writer's own set is
-- tried first (an owned key is found only when asked for by key: "Back" is 戻る on a footer, 背中 as a slot); then a
-- label that is exactly one dictionary English takes that key (the UI/Errors Lua-line rule): a footer also shows
-- OKAY, CANCEL, NEXT or the neighbouring window's jump-hint title (CHARACTER, WORLD_MAP, TALENTS), which no list here
-- could keep up with. Anything else stays as written.
local exactOnly = {} -- key → { only = { key } }, built once per key
local function opts(fs, set)
  local index = WFJ.UIIndex
  local text = type(fs) == "table" and type(fs.GetText) == "function" and fs:GetText() or nil
  if not index or type(text) ~= "string" or text == "" then return set end
  if index:matchOnly(text, set.only) then return set end
  local key = index:exactKey(text)
  if not key then return set end
  local only = exactOnly[key]
  if not only then
    only = { only = { key } }
    exactOnly[key] = only
  end
  return only
end

-- The "More Actions" context menu entries (PromptedBindingMixin:CreateMoreActionsMenu, promptedbinding.lua:126–181;
-- camelot/paperdollframe.lua:2950–2956, containerframe.lua:3302–3306, playerspellsframe.lua:841–842,
-- mainmenubarbagbuttons.lua:220, floatingchatframe.lua:329); the menu is tagged MORE_CONTEXT_ACTIONS
-- (promptedbinding.lua:140), so UI/MenusTags appends these to that tag's list.
Gamepad.MENU_KEYS = {
  "ACTION_LABEL_BIND_SET", "ACTION_LABEL_CHANGE_NAME_AND_ICON_FOR_SET", "ACTION_LABEL_CHAT_CHANNELS",
  "ACTION_LABEL_DELETE_SET", "ACTION_LABEL_EQUIP_SET", "ACTION_LABEL_SAVE_SET", "CONTEXT_ACTION_LABEL_AUTO_CAST",
  "CONTEXT_ACTION_LABEL_BIND_TO_GAMEPAD_ACTION_BAR", "CONTEXT_ACTION_LABEL_CAST", "CONTEXT_ACTION_LABEL_DESTROY_ITEM",
  "CONTEXT_ACTION_LABEL_FEED_TO_PET", "CONTEXT_ACTION_LABEL_SPLIT_ITEM_STACK", "CONTEXT_ACTION_LABEL_UNEQUIP_BAG",
  "CONTEXT_ACTION_LABEL_USE", "FRAME_ACTION_TOGGLE_ITEM_COMPARE",
}

local CANDIDATES = {
  promptMixin = { "InputPromptMixin" },
  radial = { "GamepadRadial" },
  gamepadMode = { "GamepadMode" },
  skipMovie = { "GamepadMovieSkipButton" },
  skipCinematic = { "GamepadCinematicSkipButton" },
  enumerate = { "EnumerateFrames" },
}
local function get(key) return Compat.get(SURFACE, key) end

local keyOf = WFJ.Labels.keyer("prompt")
local refits = setmetatable({}, { __mode = "k" }) -- prompt frame → its refit closure (one per frame)

-- Re-sizes one prompt after its label changed, exactly as SetPromptText does (inputprompts.lua:37–41), and re-lays
-- out the footer legend that holds it (a persistent-legend entry has fixed anchors and no such method).
local function refit(prompt)
  local ctl = prompt.ControlDescText
  local fs = type(ctl) == "table" and ctl.FontString or nil
  if type(fs) == "table" and type(fs.GetWidth) == "function" and type(ctl.SetWidth) == "function" then
    ctl:SetWidth(fs:GetWidth())
  end
  if type(prompt.RefreshInputPromptSize) == "function" then prompt:RefreshInputPromptSize() end
  local container = type(prompt.GetParent) == "function" and prompt:GetParent() or nil
  local legend = type(container) == "table" and type(container.GetParent) == "function" and container:GetParent() or nil
  if type(legend) == "table" and type(legend.ApplyDefaultPromptPositioning) == "function" then
    legend:ApplyDefaultPromptPositioning()
  end
end

local function refitFor(prompt)
  local fn = refits[prompt]
  if not fn then
    fn = function() refit(prompt) end
    refits[prompt] = fn
  end
  return fn
end

-- The SetPromptText post-hook (the mixin's and each older frame's). → 1 when the label is a dictionary word, else 0
function Gamepad.onPrompt(prompt)
  local ctl = type(prompt) == "table" and prompt.ControlDescText or nil
  local fs = type(ctl) == "table" and ctl.FontString or nil
  if type(fs) ~= "table" then return 0 end
  local n = WFJ.Labels.show(SURFACE, keyOf(fs), fs, refitFor(prompt), opts(fs, PROMPT))
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- The SetPromptFont post-hook: the persistent legend's header rows set their font object right after their label
-- (gamepadpersistentinputlegend.lua:146, 153–156; inputprompts.lua:44–49), which puts the client's face back under
-- our Japanese. The record is dropped (the client's English and font back) and the label shown again, so the current
-- font is captured and the Japanese one applied over it.
function Gamepad.onPromptFont(prompt)
  local ctl = type(prompt) == "table" and prompt.ControlDescText or nil
  local fs = type(ctl) == "table" and ctl.FontString or nil
  if type(fs) ~= "table" then return 0 end
  WFJ.SurfaceState.drop(SURFACE, keyOf(fs))
  return Gamepad.onPrompt(prompt)
end

-- Hooks the mixin for later frames and every frame that already exists on its own. → the number of hooks placed
local function hookPrompts()
  local mixin = get("promptMixin")
  local original = type(mixin) == "table" and mixin.SetPromptText or nil
  if type(original) ~= "function" then return 0 end
  local originalFont = mixin.SetPromptFont
  hooksecurefunc(mixin, "SetPromptText", Gamepad.onPrompt)
  local n = 1
  if type(originalFont) == "function" then
    hooksecurefunc(mixin, "SetPromptFont", Gamepad.onPromptFont)
    n = n + 1
  end
  local enumerate = get("enumerate")
  if type(enumerate) ~= "function" then return n end
  local frame = enumerate()
  while frame do
    -- a forbidden frame (the secure environment's) is never read or written (UI/Scan's rule)
    local forbidden = type(frame) == "table" and type(frame.IsForbidden) == "function" and frame:IsForbidden()
    if type(frame) == "table" and not forbidden and frame.SetPromptText == original then
      hooksecurefunc(frame, "SetPromptText", Gamepad.onPrompt)
      WFJ.Diag.watch(frame, "SetPromptText", "prompt")
      if originalFont and frame.SetPromptFont == originalFont then
        hooksecurefunc(frame, "SetPromptFont", Gamepad.onPromptFont)
      end
      Gamepad.onPrompt(frame) -- its label was written before the addon loaded
      n = n + 1
    end
    frame = enumerate(frame)
  end
  return n
end

local segmentKey = WFJ.Labels.keyer("radial")

-- The ActivateRadial / SetMenuOptions post-hooks: the header, every segment label and every D-pad indicator.
-- → the number of dictionary words shown
function Gamepad.onRadial()
  local radial = get("radial")
  if type(radial) ~= "table" then return 0 end
  local n = WFJ.Labels.show(SURFACE, "radial.header", radial.HeaderText, nil, opts(radial.HeaderText, RADIAL))
  for _, segment in ipairs(type(radial.SegmentList) == "table" and radial.SegmentList or {}) do
    if type(segment) == "table" and segment.IconLabel then
      local label = segment.IconLabel
      n = n + WFJ.Labels.show(SURFACE, segmentKey(label), label, nil, opts(label, RADIAL))
    end
  end
  local selector = radial.ContextActionSelector
  for _, indicator in pairs(type(selector) == "table" and type(selector.indicators) == "table"
      and selector.indicators or {}) do
    if type(indicator) == "table" and indicator.Label then
      n = n + WFJ.Labels.show(SURFACE, segmentKey(indicator.Label), indicator.Label, nil, opts(indicator.Label, RADIAL))
    end
  end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

local function hookRadial()
  local radial = get("radial")
  if type(radial) ~= "table" or type(radial.ActivateRadial) ~= "function" then return 0 end
  hooksecurefunc(radial, "ActivateRadial", Gamepad.onRadial)
  local n = 1
  local selector = radial.ContextActionSelector
  if type(selector) == "table" and type(selector.SetMenuOptions) == "function" then
    hooksecurefunc(selector, "SetMenuOptions", Gamepad.onRadial)
    n = n + 1
  end
  Gamepad.onRadial()
  return n
end

local skipped = setmetatable({}, { __mode = "k" }) -- skip button → true once its OnUpdate is hooked

local lastSkip = setmetatable({}, { __mode = "k" }) -- button → the last frame's { en, alt, on, out }

-- The client writes the English every frame; a frame whose English, modifier and switches are those of the last one
-- gets the last result written back directly (one SetText) instead of a full match and render; only a change goes
-- through Labels.show, which keeps the record, the font and Alt exactly as for any label.
local function onSkipUpdate(button)
  local fs = type(button) == "table" and button.text or nil
  if type(fs) ~= "table" or type(fs.GetText) ~= "function" then return end
  local en = fs:GetText()
  local alt = WFJ.Modifier.isDown() and true or false
  local on = (WFJ.State.enabled and WFJ.State.areaEnabled("ui")) and true or false
  local last = lastSkip[button]
  if last and last.en == en and last.alt == alt and last.on == on then
    if last.out ~= en then fs:SetText(last.out) end
    return
  end
  WFJ.Labels.show(SURFACE, "skip", fs, nil, SKIP)
  lastSkip[button] = { en = en, alt = alt, on = on, out = fs:GetText() }
end

-- → true when `button` was newly hooked
function Gamepad.hookSkip(button)
  if type(button) ~= "table" or skipped[button] or type(button.HookScript) ~= "function" then return false end
  skipped[button] = true
  button:HookScript("OnUpdate", onSkipUpdate)
  onSkipUpdate(button)
  return true
end

local function hookSkips()
  local n = 0
  for _, key in ipairs({ "skipMovie", "skipCinematic" }) do
    if Gamepad.hookSkip(get(key)) then n = n + 1 end
  end
  local mode = get("gamepadMode")
  if type(mode) == "table" and type(mode.CreateHoldButtonWithTextFromTemplate) == "function" then
    -- the button is created after the addon when gamepad mode starts later; it is the global named `name`
    hooksecurefunc(mode, "CreateHoldButtonWithTextFromTemplate", function(name)
      Gamepad.hookSkip(type(name) == "string" and _G[name] or nil)
    end)
    n = n + 1
  end
  return n
end

local hooked = false

-- Called by Main with the other Forever surfaces. → false when the client has no gamepad HUD, else the hook count
function Gamepad.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  if hooked then return false end
  hooked = true
  local n = hookPrompts() + hookRadial() + hookSkips()
  if n == 0 then return false end
  return n
end
