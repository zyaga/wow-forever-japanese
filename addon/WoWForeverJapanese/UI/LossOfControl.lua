-- UI/LossOfControl.lua: the loss-of-control alert ("Stunned 3.2 seconds") on Forever (surface "lossofcontrol", area
-- "ui", ADR-016). Blizzard_FrameXML loads lossofcontrolframe.xml|lua at login on `camelot`; LossOfControlFrame
-- (lossofcontrolframe.xml:4) is an Edit Mode system shown while the lossOfControl CVar is on.
-- Writer: LossOfControlMixin:SetUpDisplay (lossofcontrolframe.lua:142–207), called as self:SetUpDisplay (:66, :73,
--   :220, :232; method lookup on the instance, so a post-hook on the frame sees every call) writes
--   AbilityName: TEXT_OVERRIDE[spellID] (LOSS_OF_CONTROL_DISPLAY_CYCLONE / _STUN, :17–27), or
--   LOSS_OF_CONTROL_DISPLAY_INTERRUPT_SCHOOL "%s Locked" around the school's name (:160–165; a `word` argument,
--   Core/UIStrings), or data.displayText from C_LossOfControl (:149). That last text is the client's; the addon matches
--   it only against the LOSS_OF_CONTROL_DISPLAY_* words (all 32 GlobalStrings of that family; PACIFYSILENCE "Disabled"
--   owns its Japanese in UIStrings.OWN: the shared 無効 reads as a turned-off setting). Whether the client hands
--   those strings over is an in-game check; a text that is none of them stays English.
-- Static: TimeLeft.SecondsText LOSS_OF_CONTROL_SECONDS "seconds" (XML text=, lossofcontrolframe.xml:91); the number
--   beside it (TimeLeft.NumberText) is never touched.
local _, WFJ = ...
local LossOfControl = {}
WFJ.LossOfControl = LossOfControl

local SURFACE = "lossofcontrol"
LossOfControl.SURFACE = SURFACE
local Compat = WFJ.Compat

LossOfControl.NEVER_TOUCH = { "LossOfControlFrame.TimeLeft.NumberText" }

local CANDIDATES = { frame = { "LossOfControlFrame" }, ability = { "LossOfControlFrame.AbilityName" },
  seconds = { "LossOfControlFrame.TimeLeft.SecondsText" } }

local DISPLAY = {}
for _, suffix in ipairs({ "BANISH", "CHARM", "CONFUSE", "CYCLONE", "DAZE", "DISARM", "DISORIENT", "DISTRACT", "FEAR",
  "FEAR_MECHANIC", "FREEZE", "HORROR", "INCAPACITATE", "INTERRUPT", "INTERRUPT_SCHOOL", "INVULNERABILITY",
  "MAGICAL_IMMUNITY", "PACIFY", "PACIFYSILENCE", "POLYMORPH", "POSSESS", "ROOT", "SAP", "SCHOOL_INTERRUPT",
  "SHACKLE_UNDEAD", "SILENCE", "SLEEP", "SNARE", "STUN", "STUN_MECHANIC", "TAUNT", "TURN_UNDEAD" }) do
  DISPLAY[#DISPLAY + 1] = "LOSS_OF_CONTROL_DISPLAY_" .. suffix
end
local ABILITY = { only = DISPLAY }
local SECONDS = { only = { "LOSS_OF_CONTROL_SECONDS" } }

local function get(key) return Compat.get(SURFACE, key) end

-- The alert's two words (after SetUpDisplay). → the number of dictionary words found.
function LossOfControl.show()
  return WFJ.Labels.showAll(SURFACE, { { "ability", get("ability"), ABILITY }, { "seconds", get("seconds"), SECONDS } })
end

local hooked = false

-- Called by Main after Compat.init. → true when the alert was hooked now; false on a second call and
-- when the alert is absent.
function LossOfControl.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  if hooked then return false end
  local frame = get("frame")
  if type(frame) ~= "table" or type(frame.SetUpDisplay) ~= "function" then return false end
  hooked = true
  hooksecurefunc(frame, "SetUpDisplay", LossOfControl.show)
  LossOfControl.show()
  return true
end
