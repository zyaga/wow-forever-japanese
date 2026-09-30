-- UI/HudTips.lua: the action-bar area's help tooltips on Forever that UI/MicroMenu does not own (records on surface
-- "help", area "ui", ADR-016). Each is a GameTooltip the client writes in Lua, so this module only registers
-- the owners with UI/HelpTooltip, restricted (`only`) to the keys the writer shows. One reason to change: which HUD
-- buttons own a Lua-built help tooltip.
-- Owners and writers [verified: Forever 1.60.1.69913]:
--   MainMenuBarVehicleLeaveButton (blizzard_actionbar/shared/vehicleleavebutton.xml:4):
--     MainMenuBarVehicleLeaveButtonMixin:OnEnter: on a taxi GameTooltip_SetTitle(TAXI_CANCEL) + AddLine(
--     TAXI_CANCEL_DESCRIPTION) + Show, otherwise GameTooltip_SetTitle(LEAVE_VEHICLE) + Show
--     (shared/vehicleleavebutton.lua:12–23). GameTooltip_SetTitle is ClearLines + AddLine
--     (blizzard_sharedxml/sharedtooltiptemplates.lua:128–131), so the Show post-hook does the walk;
--   OverrideActionBar.pitchFrame.PitchUpButton / .PitchDownButton and OverrideActionBar.leaveFrame.LeaveButton:
--     inline OnEnter: GameTooltip_SetTitle(AIM_UP | AIM_DOWN | LEAVE_VEHICLE) + Show
--     (blizzard_overrideactionbar/overrideactionbar.xml:171–206, 262–275);
--   DurabilityFrame: DurabilityFrameMixin:OnEnter: GameTooltip_SetTitle(REPAIR_ARMOR_TOOLTIP_TITLE) +
--     GameTooltip_AddNormalLine(REPAIR_ARMOR_TOOLTIP_BROKEN | REPAIR_ARMOR_TOOLTIP_BREAKING) + Show
--     (blizzard_durabilityframe/durabilityframe.lua:31–43);
--   a totem flyout's empty slot: MultiCastFlyoutButton_SetTooltip (a global function): SetText(
--     MULTI_CAST_TOOLTIP_NO_TOTEM) with the flyout button as owner (blizzard_actionbar/shared/
--     multicastactionbarframe.lua:527–537); the buttons are created on demand, so the writer is post-hooked and the
--     tooltip walked once (HelpTooltip.walkAs) when the button owns it. With a totem in the slot the tooltip is a
--     spell's and is never walked (UI/HelpTooltip's item / spell rule).
-- Not here: action, pet, stance, possess and extra-ability buttons show spell / item tooltips (names and C-written
--   lines: UI/Tooltip, UI/MicroMenu's pet / possess owners); the override bar's XP-bar label composite is never
--   displayed (a local built and dropped, overrideactionbar.xml:383–389).
local _, WFJ = ...
local HudTips = {}
WFJ.HudTips = HudTips

local SURFACE = "help" -- records live on UI/HelpTooltip's surface
HudTips.SURFACE = SURFACE
local DECLARE = "help.hudtips"
local Compat = WFJ.Compat

HudTips.NEVER_TOUCH = {} -- only tooltip lines are written, each through an `only` list

-- Compat key → { candidates, the keys its writer shows }
HudTips.OWNERS = {
  vehicleLeave = { { "MainMenuBarVehicleLeaveButton", "MainActionBar.VehicleLeaveButton" },
    { "TAXI_CANCEL", "TAXI_CANCEL_DESCRIPTION", "LEAVE_VEHICLE" } },
  pitchUp = { { "OverrideActionBar.pitchFrame.PitchUpButton", "OverrideActionBarPitchFramePitchUpButton" },
    { "AIM_UP" } },
  pitchDown = { { "OverrideActionBar.pitchFrame.PitchDownButton", "OverrideActionBarPitchFramePitchDownButton" },
    { "AIM_DOWN" } },
  overrideLeave = { { "OverrideActionBar.leaveFrame.LeaveButton", "OverrideActionBarLeaveFrameLeaveButton" },
    { "LEAVE_VEHICLE" } },
  durability = { { "DurabilityFrame" },
    { "REPAIR_ARMOR_TOOLTIP_TITLE", "REPAIR_ARMOR_TOOLTIP_BROKEN", "REPAIR_ARMOR_TOOLTIP_BREAKING" } },
}
local ORDER = { "vehicleLeave", "pitchUp", "pitchDown", "overrideLeave", "durability" }
local NO_TOTEM = { only = { "MULTI_CAST_TOOLTIP_NO_TOTEM" } }
local FLYOUT_WRITER = "MultiCastFlyoutButton_SetTooltip"

local function get(key) return Compat.get(DECLARE, key) end

-- hooksecurefunc target (MultiCastFlyoutButton_SetTooltip): the empty-slot tooltip, when the button owns it.
function HudTips.onFlyoutTooltip(button)
  local tt = get("tooltip")
  if type(tt) ~= "table" or type(tt.GetOwner) ~= "function" or button == nil or tt:GetOwner() ~= button then
    return 0
  end
  return WFJ.HelpTooltip.walkAs(tt, NO_TOTEM)
end

local hooked = false
local registered = 0

-- Called by Main after Compat.init and HelpTooltip.init. → the number of owners registered, or false when the
-- client has none of them. A missing owner is skipped, like UI/MicroMenu's.
function HudTips.init()
  for key, entry in pairs(HudTips.OWNERS) do Compat.declare(DECLARE, key, entry[1]) end
  Compat.declare(DECLARE, "tooltip", { "GameTooltip" })
  Compat.declare(DECLARE, "flyoutWriter", { FLYOUT_WRITER })
  if hooked then return registered end
  local n = 0
  for _, key in ipairs(ORDER) do
    local owner = get(key)
    if type(owner) == "table" then
      WFJ.HelpTooltip.register(owner, { only = HudTips.OWNERS[key][2] })
      n = n + 1
    end
  end
  local writer = type(get("flyoutWriter")) == "function"
  if n == 0 and not writer then return false end
  hooked = true
  if writer then hooksecurefunc(FLYOUT_WRITER, function(button) return HudTips.onFlyoutTooltip(button) end) end
  registered = n
  return n
end
