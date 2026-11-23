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
-- Names, while Japanese names are on (UI/NameLabels): the spell's name StartCast writes into Text (:404–406), under
-- the same record key as the fixed words, so one record owns the widget; and CastTargetNameText, the spell's target
-- (UnitSpellTargetName, written by UpdateTargetNameText at the end of StartCast, :434, 932–961), only when it is the
-- name of the player's target and that target is a creature (UnitIsPlayer and UnitPlayerControlled answer a plain
-- false): the name alone cannot tell a player from an NPC. Neither widget is read or measured by the client's bar
-- code (castingbarframe.lua: SetText only) or by Edit Mode's cast bar system (editmodesystemtemplates.lua:1839–1961),
-- and no protected call follows on the bar. [unverified in combat: the window test's run in and out of combat
-- decides whether these stay]
-- Never touched: CastTimeText ("%.1f s", a number), nameplate and unit-frame bars.
local _, WFJ = ...
local CastingBar = {}
WFJ.CastingBar = CastingBar

local SURFACE = "castingbar"
CastingBar.SURFACE = SURFACE
local Compat = WFJ.Compat

CastingBar.NEVER_TOUCH = { "PlayerCastingBarFrame.CastTimeText", "PlayerCastingBarFrame.CastTargetNameText" }

local KEYS = { only = { "FAILED", "INTERRUPTED", "SPELL_INTERRUPTED_BY" } }

local function get(key) return Compat.get(SURFACE, key) end

-- The spell's target, when it is the player's target and a creature. → 1 | 0
local function showTarget(bar)
  local fs = bar.CastTargetNameText
  if type(fs) ~= "table" or type(fs.GetText) ~= "function" then return 0 end
  local secret, unitName = get("issecretvalue"), Compat.resolve("UnitName")
  local shown = fs:GetText()
  local name = type(unitName) == "function" and unitName("target") or nil
  if type(secret) == "function" and (secret(shown) or secret(name)) then return 0 end
  local rec = WFJ.SurfaceState.get(SURFACE, "target")
  local ours = rec ~= nil and rec.fs == fs and rec.applied ~= nil and rec.applied == shown -- still our Japanese
  if type(name) ~= "string" or name == "" or (shown ~= name and not ours) then
    WFJ.SurfaceState.drop(SURFACE, "target")
    return 0
  end
  return WFJ.NameLabels.unit(SURFACE, "target", fs, "target")
end

-- HookScript("OnEvent") target: the bar's text as the client left it after this event. → the lines shown
function CastingBar.onEvent(bar)
  local text = type(bar) == "table" and bar.Text or nil
  if type(text) ~= "table" or type(text.GetText) ~= "function" then return 0 end
  local secret = get("issecretvalue")
  if type(secret) == "function" and secret(text:GetText()) then return 0 end
  local n = WFJ.Labels.show(SURFACE, "text", text, nil, KEYS)
  if n == 0 then n = WFJ.NameLabels.show(SURFACE, "text", text) end
  return n + showTarget(bar)
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
