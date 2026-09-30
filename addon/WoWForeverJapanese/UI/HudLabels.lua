-- UI/HudLabels.lua: the fixed words the HUD's small bars and messages write on Forever (surface "hudlabels", area
-- "ui", ADR-016): four tiny always-on widgets, each one FontString with one writer, sharing one reason to
-- change (which HUD bar writes a fixed word, and when).
-- Writers [verified: Forever 1.60.1.69913], each the frame's own method, post-hooked on the instance:
--   mirror timers (breath, fatigue): MirrorTimerContainer.mirrorTimers (parentArray, blizzard_mirrortimer/mainline/
--     mirrortimer.xml:3, 57); MirrorTimerContainerMixin:SetupTimer calls availableTimerFrame:Setup(timer, value,
--     maxvalue, paused, label), which writes self.Text:SetText(label) (mirrortimer.lua:50–57, 146–158). The label
--     comes from the client (MIRROR_TIMER_START / GetMirrorTimerInfo, lua:28–35): the source does not say which
--     strings it sends, so the timer text is matched against BREATH_LABEL and EXHAUSTION_LABEL only (in-game check);
--     a third timer's label can be a spell name ("Feign Death") and never matches;
--   swing timers: SwingTimerMainHandFrame / SwingTimerOffHandFrame / SwingTimerRangedFrame (blizzard_swingtimer/
--     blizzard_swingtimer.xml:11–37): InitializeBarPresentation writes GetTypeLabel():SetText(self.typeText),
--     typeText = SWING_TIMER_MAIN_HAND / _OFF_HAND / _RANGED (lua:161–163, xml:56, 69, 82), once from OnLoad
--     (lua:50). Shown at init, after each InitializeBarPresentation and on the frame's OnShow;
--   the honor bar's text: HonorBarMixin:UpdateOverlayFrameText: SetBarText(HONOR_BAR:format(current, max)) into
--     bar.OverlayFrame.Text (blizzard_statustrackingbar/mainline/honorbar.lua:14–23, shared/statustrackingbar.lua:
--     20–22), on each container's Honor bar (container.bars[StatusTrackingBarInfo.BarsEnum.Honor], mainline/
--     statustrackingmanageroverrides.lua:56–69), shown while in a battlefield or world PvP (CanShowBar, :26–27).
--     UI/MicroMenu owns the Experience bar of the same containers; this is the same pattern for the Honor bar;
--   the screen message: ActionStatus:DisplayMessage(text) writes self.Text:SetText(text)
--     (blizzard_actionstatus/mainline/actionstatus.lua:50–55). Every caller in the load set passes a global string:
--     SCREENSHOT_SUCCESS / SCREENSHOT_FAILURE (lua:31, 34), PING_TARGET_TOGGLED_ALL / _ENVIRONMENT
--     (blizzard_pingui/blizzard_pingutil.lua:17, 20), the sound toggles (blizzard_sharedxml/mainline/sound.lua:7–46),
--     so the text is matched against the whole dictionary (another addon's message matches nothing and stays as
--     written).
--   the FPS counter (Ctrl+R): FramerateFrameMixin:OnUpdate writes self.FramerateText:SetFormattedText(
--     FPS_COUNTER_CPU_BOUND or _GPU_BOUND ("%.1f CPU Bound"), framerate) four times a second, or the bare "%.1f"
--     when the client has no bound state (blizzard_framerateframe/mainline/framerateframe.lua:9–24): a post-hook on
--     the FontString's SetFormattedText, restricted to those two keys (the bare number matches neither);
--   the buff / debuff durations ("5 m", "30 s"): AuraButtonMixin:UpdateDuration writes
--     self.Duration:SetFormattedText(SecondsToTimeAbbrev(timeLeft)), one of *_ONELETTER_ABBR and the number
--     (blizzard_buffframe/buffframe.lua:1355–1368; blizzard_sharedxml/timeutil.lua:463–480). It runs from each
--     button's OnUpdate, every frame (securecall, :1203); on enUS nothing re-fonts the text after it (the smaller
--     duration font is zhTW-only, blizzard_framexmlutil/localization.lua:17–21). The buttons exist from
--     AuraFrame_OnLoad (:191–204), so each button of BuffFrame and DebuffFrame is post-hooked on its own. The client
--     rewrites the same English every frame: while it is the English the record was made for, the Japanese already
--     worked out is put back (text only, the font stays); a new value goes through Labels.show.
-- Never touched: the timers' and bars' values (numbers), the swing timer's time label ("0.0", lua:210).
local _, WFJ = ...
local HudLabels = {}
WFJ.HudLabels = HudLabels

local SURFACE = "hudlabels"
HudLabels.SURFACE = SURFACE
local Compat = WFJ.Compat

HudLabels.NEVER_TOUCH = {} -- every widget here is restricted to its own keys; none can hold a name we would match

local SWING = {
  { "SwingTimerMainHandFrame", { only = { SWING_TIMER_MAIN_HAND = true } } },
  { "SwingTimerOffHandFrame", { only = { SWING_TIMER_OFF_HAND = true } } },
  { "SwingTimerRangedFrame", { only = { SWING_TIMER_RANGED = true } } },
}
local BAR_CONTAINERS = { "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }
local MIRROR = { only = { BREATH_LABEL = true, EXHAUSTION_LABEL = true } }
local HONOR = { only = { HONOR_BAR = true } }
local DURATION = { only = { DAY_ONELETTER_ABBR = true, HOUR_ONELETTER_ABBR = true, MINUTE_ONELETTER_ABBR = true,
  SECOND_ONELETTER_ABBR = true } }
local AURA_FRAMES = { "BuffFrame", "DebuffFrame", "ExternalDefensivesFrame" }

local function declareAll()
  Compat.declare(SURFACE, "mirrorContainer", { "MirrorTimerContainer" })
  Compat.declare(SURFACE, "actionStatus", { "ActionStatus" })
  Compat.declare(SURFACE, "barInfo", { "StatusTrackingBarInfo" })
  for _, swing in ipairs(SWING) do Compat.declare(SURFACE, swing[1], { swing[1] }) end
  for _, name in ipairs(BAR_CONTAINERS) do Compat.declare(SURFACE, name, { name }) end
  for _, name in ipairs(AURA_FRAMES) do Compat.declare(SURFACE, name, { name }) end
  Compat.declare(SURFACE, "auraMixin", { "AuraButtonMixin" })
  Compat.declare(SURFACE, "framerate", { "FramerateFrame.FramerateText" })
end

local function get(key) return Compat.get(SURFACE, key) end

local mirrorKey = WFJ.Labels.keyer("mirror.") -- a timer frame is reused for whichever timer starts next

-- hooksecurefunc target (a mirror timer's Setup). → 1 | 0
function HudLabels.onMirrorSetup(timer)
  local text = type(timer) == "table" and timer.Text or nil
  if type(text) ~= "table" then return 0 end
  return WFJ.Labels.show(SURFACE, mirrorKey(text), text, nil, MIRROR)
end

-- A swing timer's type label (SwingTimerMixin:GetTypeLabel → StatusBar.TypeLabel, lua:15–27). → 1 | 0
function HudLabels.showSwing(name, opts)
  local frame = get(name)
  local bar = type(frame) == "table" and frame.StatusBar or nil
  return WFJ.Labels.show(SURFACE, "swing." .. name, type(bar) == "table" and bar.TypeLabel or nil, nil, opts)
end

-- hooksecurefunc target (an Honor bar's UpdateOverlayFrameText). → 1 | 0
function HudLabels.showHonor(bar, recKey)
  local overlay = type(bar) == "table" and bar.OverlayFrame or nil
  return WFJ.Labels.show(SURFACE, recKey, type(overlay) == "table" and overlay.Text or nil, nil, HONOR)
end

-- hooksecurefunc target (ActionStatus:DisplayMessage). → 1 | 0
function HudLabels.onActionStatus()
  local status = get("actionStatus")
  -- no `only` on purpose: the line shows many Blizzard messages (screenshots, ping targets …) keyed across families;
  -- it never holds a name, and another addon's text is left alone unless it is exactly a dictionary entry
  return WFJ.Labels.show(SURFACE, "actionstatus", type(status) == "table" and status.Text or nil)
end

local durationKey = WFJ.Labels.keyer("duration.")

-- hooksecurefunc target (an aura button's UpdateDuration). → 1 | 0
function HudLabels.onDuration(button)
  local fs = type(button) == "table" and button.Duration or nil
  if type(fs) ~= "table" or type(fs.GetText) ~= "function" then return 0 end
  local key = durationKey(fs)
  local rec = WFJ.SurfaceState.get(SURFACE, key)
  local en = fs:GetText()
  -- The client rewrites the same value every frame (its OnUpdate). While the record still stands for that English,
  -- nothing is resolved again: our Japanese goes back, or (with the modifier held or the addon off, where no text of
  -- ours is applied) the client's own line is left alone (`capture` walks every record).
  if rec and rec.fs == fs and rec.en == en then
    if type(rec.applied) == "string" and rec.applied ~= en then
      fs:SetText(rec.applied)
      return 1
    end
    if rec.applied == nil then return 0 end
  end
  return WFJ.Labels.show(SURFACE, key, fs, nil, DURATION)
end

-- The mixin is hooked for every aura button made later (Mixin copies the method when the frame is created), and each
-- button that already exists is hooked on its own. Never both: a button made before the mixin hook still holds the
-- method the mixin had then, which is what `original` compares against.
local function hookAuraButtons()
  local mixin = get("auraMixin")
  local original = type(mixin) == "table" and mixin.UpdateDuration or nil
  local n = 0
  if type(original) == "function" then
    hooksecurefunc(mixin, "UpdateDuration", HudLabels.onDuration)
    n = n + 1
  end
  for _, name in ipairs(AURA_FRAMES) do
    local frame = get(name)
    for _, button in ipairs(type(frame) == "table" and type(frame.auraFrames) == "table" and frame.auraFrames or {}) do
      if type(button) == "table" and not button.isAuraAnchor and type(button.UpdateDuration) == "function"
          and (original == nil or button.UpdateDuration == original) then
        hooksecurefunc(button, "UpdateDuration", HudLabels.onDuration)
        n = n + 1
      end
    end
  end
  return n
end

local function hookMirrorTimers()
  local container = get("mirrorContainer")
  local timers = type(container) == "table" and container.mirrorTimers or nil
  if type(timers) ~= "table" then return 0 end
  local n = 0
  for _, timer in pairs(timers) do
    if type(timer) == "table" and type(timer.Setup) == "function" then
      hooksecurefunc(timer, "Setup", HudLabels.onMirrorSetup)
      HudLabels.onMirrorSetup(timer)
      n = n + 1
    end
  end
  return n
end

local function hookSwingTimers()
  local n = 0
  for _, swing in ipairs(SWING) do
    local name, opts = swing[1], swing[2]
    local frame = get(name)
    if type(frame) == "table" then
      local pass = function() HudLabels.showSwing(name, opts) end
      if type(frame.InitializeBarPresentation) == "function" then
        hooksecurefunc(frame, "InitializeBarPresentation", pass)
      end
      if type(frame.HookScript) == "function" then frame:HookScript("OnShow", pass) end
      pass()
      n = n + 1
    end
  end
  return n
end

local function hookHonorBars()
  local info = get("barInfo")
  local index = type(info) == "table" and type(info.BarsEnum) == "table" and info.BarsEnum.Honor
  if type(index) ~= "number" then return 0 end
  local n = 0
  for _, name in ipairs(BAR_CONTAINERS) do
    local container = get(name)
    local bars = type(container) == "table" and container.bars
    local bar = type(bars) == "table" and bars[index]
    if type(bar) == "table" and type(bar.UpdateOverlayFrameText) == "function" then
      local recKey = "honor." .. name
      hooksecurefunc(bar, "UpdateOverlayFrameText", function(self) HudLabels.showHonor(self, recKey) end)
      HudLabels.showHonor(bar, recKey)
      n = n + 1
    end
  end
  return n
end

local function hookActionStatus()
  local status = get("actionStatus")
  if type(status) ~= "table" or type(status.DisplayMessage) ~= "function" or type(status.Text) ~= "table" then
    return 0
  end
  hooksecurefunc(status, "DisplayMessage", HudLabels.onActionStatus)
  return 1
end

local FPS = { only = { "FPS_COUNTER_CPU_BOUND", "FPS_COUNTER_GPU_BOUND" } }

-- hooksecurefunc target (FramerateText:SetFormattedText). → 1 | 0
function HudLabels.onFramerate(fs)
  -- the bare number ("60.0", four times a second) is no word: never looked up, so it never fills the match memo
  local text = type(fs) == "table" and type(fs.GetText) == "function" and fs:GetText() or nil
  if type(text) ~= "string" or not text:find("%a") then
    WFJ.SurfaceState.drop(SURFACE, "framerate")
    return 0
  end
  return WFJ.Labels.show(SURFACE, "framerate", fs, nil, FPS)
end

local function hookFramerate()
  local fs = get("framerate")
  if type(fs) ~= "table" or type(fs.SetFormattedText) ~= "function" then return 0 end
  hooksecurefunc(fs, "SetFormattedText", HudLabels.onFramerate)
  return 1
end

local hooked = false

-- Called by Main after Compat.init and ButtonText.init. → false when the client has none of the five widgets in the
-- shape named above; a widget it lacks is skipped.
function HudLabels.init()
  declareAll()
  if hooked then return false end
  local n = hookMirrorTimers() + hookSwingTimers() + hookHonorBars() + hookActionStatus() + hookAuraButtons()
    + hookFramerate()
  if n == 0 then return false end
  hooked = true
  WFJ.Render.updateBanner(SURFACE)
  return true
end
