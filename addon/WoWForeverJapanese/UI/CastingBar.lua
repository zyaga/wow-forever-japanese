-- UI/CastingBar.lua: the player's casting bar on Forever (surface "castingbar", area "ui", ADR-016 / ADR-029).
-- camelot loads blizzard_uipanels_game/shared/castingbarframe.lua and mainline/castingbarframe.xml
-- (PlayerCastingBarFrame, castingbarframe.xml:482). The bar's Text is a spell's name while casting; two writers put a
-- fixed word there instead: CastingBarMixin:HandleInterruptOrSpellFailed → FAILED, or GetInterruptText's INTERRUPTED /
-- SPELL_INTERRUPTED_BY "Interrupted: %s" (%s = the interrupter's name, class-coloured, kept as written)
-- (castingbarframe.lua:541–560, 615–635).
-- Both run inside the bar's OnEvent script (XML `method="OnEvent"`, castingbarframe.xml:391; the script holds the
-- function itself, so a table hook on the mixin method would not be called for it): followed with
-- HookScript("OnEvent").
-- Every event re-shows Text restricted to those three keys, so the next cast's spell name drops the record (and the
-- bundled font with it) at once. A spell name is never matched: the restriction names no spell.
-- Only the player's own bar is followed. The client wraps other units' cast values as secrets
-- (WrapValueInSpellCastSecrecy, castingbarframe.lua:4–10), which addon code must not inspect; as a second guard, a
-- text the client's `issecretvalue` flags is never read further.
-- Never touched: CastTimeText ("%.1f s", a number), CastTargetNameText (a unit name), nameplate and unit-frame bars.
local _, WFJ = ...
local CastingBar = {}
WFJ.CastingBar = CastingBar

local SURFACE = "castingbar"
CastingBar.SURFACE = SURFACE
local Compat = WFJ.Compat

CastingBar.NEVER_TOUCH = { "PlayerCastingBarFrame.CastTimeText", "PlayerCastingBarFrame.CastTargetNameText" }

local KEYS = { only = { "FAILED", "INTERRUPTED", "SPELL_INTERRUPTED_BY" } }

local function get(key) return Compat.get(SURFACE, key) end

-- HookScript("OnEvent") target: the bar's text as the client left it after this event. → 1 | 0
function CastingBar.onEvent(bar)
  local text = type(bar) == "table" and bar.Text or nil
  if type(text) ~= "table" or type(text.GetText) ~= "function" then return 0 end
  local secret = get("issecretvalue")
  if type(secret) == "function" and secret(text:GetText()) then return 0 end
  return WFJ.Labels.show(SURFACE, "text", text, nil, KEYS)
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function CastingBar.init()
  Compat.declare(SURFACE, "bar", { "PlayerCastingBarFrame" })
  Compat.declare(SURFACE, "issecretvalue", { "issecretvalue" })
  local bar = get("bar")
  if hooked or type(bar) ~= "table" or type(bar.HookScript) ~= "function" then return false end
  hooked = true
  bar:HookScript("OnEvent", CastingBar.onEvent)
  return true
end
