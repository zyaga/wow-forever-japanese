-- UI/CombatFeedback.lua: the combat words over the player and pet portraits on Forever (surface "combatfeedback",
-- area "ui", ADR-016). Blizzard_FrameXML loads mainline/combatfeedback.lua on camelot; its one writer is the
-- global CombatFeedback_OnCombatEvent(self, event, flags, amount, type) (combatfeedback.lua:26–95), called by name
-- from the unit frames' UNIT_COMBAT handlers (blizzard_unitframe/mainline/playerframe.lua:122, petframe.lua:109), so
-- a post-hook on the global sees every write. It sets `self.feedbackText` (CombatFeedback_Initialize, :21–24: the
-- player's HitIndicator.HitText, the pet's PetHitIndicator) to a damage or heal number (BreakUpLargeNumbers, never a
-- dictionary word), to COMBAT_TEXT_BLOCK_REDUCED "%s (Block)" around that number (:51), or to a CombatFeedbackText
-- word (:5–17): INTERRUPT MISS RESIST DODGE PARRY BLOCK EVADE IMMUNE DEFLECT ABSORB REFLECT.
-- The widget is whatever the unit frame registered: it is keyed by widget (Labels.keyer), never by position, and
-- restricted to those keys. The text fades out on the frame's OnUpdate, which writes alpha only (:97–120).
local _, WFJ = ...
local CombatFeedback = {}
WFJ.CombatFeedback = CombatFeedback

local SURFACE = "combatfeedback"
CombatFeedback.SURFACE = SURFACE
local Compat = WFJ.Compat

CombatFeedback.NEVER_TOUCH = {}

local CANDIDATES = { writer = { "CombatFeedback_OnCombatEvent" } }

local WORDS = { only = { "INTERRUPT", "MISS", "RESIST", "DODGE", "PARRY", "BLOCK", "EVADE", "IMMUNE", "DEFLECT",
  "ABSORB", "REFLECT", "COMBAT_TEXT_BLOCK_REDUCED" } }

local textKey = WFJ.Labels.keyer("text.") -- one record per unit frame's feedback text

-- hooksecurefunc target (CombatFeedback_OnCombatEvent): `owner` is the unit frame. → 1 | 0
function CombatFeedback.onCombatEvent(owner)
  local text = type(owner) == "table" and owner.feedbackText or nil
  if type(text) ~= "table" then return 0 end
  return WFJ.Labels.show(SURFACE, textKey(text), text, nil, WORDS)
end

local hooked = false

-- Called by Main after Compat.init.
function CombatFeedback.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  if hooked then return false end
  if type(Compat.get(SURFACE, "writer")) ~= "function" then return false end
  hooked = true
  hooksecurefunc("CombatFeedback_OnCombatEvent", CombatFeedback.onCombatEvent)
  return true
end
