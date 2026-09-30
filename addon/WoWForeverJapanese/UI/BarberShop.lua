-- UI/BarberShop.lua: the barber shop's three buttons on Forever (surface "barbershop", area "ui", ADR-016).
-- Blizzard_BarberShopUI is load-on-demand on `camelot` (blizzard_barbershopui.toc; Mainline\Blizzard_BarberShopUI
-- .lua|xml). Entry point: the BARBER_SHOP_OPEN event (blizzard_game/shared/eventrouting.lua:48) →
-- GameEvent.HandleBarberShopOpen → ShowBarberShopFrame() (blizzard_game/shared/eventimplementation.lua:111–112) →
-- LoadAddOnWithErrorHandling + ShowUIPanel(BarberShopFrame) (blizzard_barbershopui_bootstrap.lua:3–11). Whether a
-- barber exists on Forever is an in-game question; the module waits through WFJ.LoadOnDemand.when and does nothing
-- until the client loads the addon.
-- Static labels (XML text=), shown on the frame's OnShow:
--   BarberShopFrame.CancelButton CANCEL (mainline/blizzard_barbershopui.xml:46), .ResetButton RESET (:55),
--   .AcceptButton ACCEPT (:86).
-- The customization text (ADR-042) from the client tables, each widget restricted to its family:
--   an option's label (CustomizationOption: the check button's Label, blizzard_customizationoptiontemplates.lua:209;
--     the dropdown's and the slider's label, :336, :111–118), a choice's SelectionName (CustomizationChoice, :652;
--     the unselected "-Select-" CHARACTER_CUSTOMIZE_POPOUT_UNSELECTED_OPTION, :684), each written by a mixin method
--     the pooled option frames copy when they are created, so the methods are post-hooked on the mixin tables once
--     Blizzard_CustomizationUI has loaded (before the barber shop builds its first option);
--   the option tooltip's choice line CHARACTER_CUSTOMIZATION_CHOICE_TOOLTIP "%d: %s" (:134–137) and a locked
--     choice's BARBERSHOP_CUSTOMIZATION_SOURCE_FORMAT "Source: %s" (:533–539), on CustomizationNoHeaderTooltip, with
--     their customization argument kinds; a category name in that tooltip (the Customization* families).
-- Never touched: druid form, demon and mount names (Blizzard_CharacterCustomize's altered-form dropdown),
-- the body-type buttons, and SDToggleButton.Text (xml:71): its global string is named "HIGH-DEFINITION_MODELS", and a
-- hyphen is outside the key grammar of pipeline/ui_keys.txt, so it has no dictionary entry (the toggle is hidden
-- unless C_GameRules.IsSDHDToggleEnabled(), blizzard_barbershopui.lua:257–263).
-- The camera buttons' tooltip (RESET_CAMERA, ZOOM_IN / ZOOM_OUT, ROTATE_LEFT / ROTATE_RIGHT,
-- RANDOMIZE_APPEARANCE: simpleTooltipLine, blizzard_customizationui.xml:22–66) is CustomizationNoHeaderTooltip, a
-- tooltip frame of its own (blizzard_customizationtemplates.lua:27–29): followed through TooltipLines.follow,
-- restricted to those six words (an option's tooltip names a client-table choice and matches none of them). Release on
-- the frame's OnHide.
local _, WFJ = ...
local BarberShop = {}
WFJ.BarberShop = BarberShop

local SURFACE = "barbershop"
BarberShop.SURFACE = SURFACE
local Compat = WFJ.Compat
local ADDON = "Blizzard_BarberShopUI"

BarberShop.NEVER_TOUCH = { "BarberShopFrame.SDToggleButton.Text" }

local CANDIDATES = {
  frame = { "BarberShopFrame" }, cancel = { "BarberShopFrame.CancelButton" },
  tooltip = { "CustomizationNoHeaderTooltip" },
  reset = { "BarberShopFrame.ResetButton" }, accept = { "BarberShopFrame.AcceptButton" },
}
local STATIC = { { "cancel", { only = { "CANCEL" } } }, { "reset", { only = { "RESET" } } },
  { "accept", { only = { "ACCEPT" } } } }

local CAMERA_KEYS = { "RESET_CAMERA", "ZOOM_IN", "ZOOM_OUT", "ROTATE_LEFT", "ROTATE_RIGHT", "RANDOMIZE_APPEARANCE",
  -- the option tooltip's lines
  "CHARACTER_CUSTOMIZATION_CHOICE_TOOLTIP", "BARBERSHOP_CUSTOMIZATION_SOURCE_FORMAT" }
local CHOICE_KEYS = { "CHARACTER_CUSTOMIZE_POPOUT_UNSELECTED_OPTION" }
BarberShop.CUSTOMIZATION_ADDON = "Blizzard_CustomizationUI"
BarberShop.TOOLTIP_SURFACE = "barbershop.tooltip"

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
end

-- HookScript("OnShow") target. → the number of dictionary words found.
function BarberShop.onShow()
  local list = {}
  for _, s in ipairs(STATIC) do list[#list + 1] = { s[1], get(s[1]), s[2] } end
  return WFJ.Labels.showAll(SURFACE, list)
end

function BarberShop.release()
  return WFJ.Render.release(SURFACE)
end

local optionKey = WFJ.Labels.keyer("option.") -- a pooled option frame's label record
local choiceKey = WFJ.Labels.keyer("choice.")

-- An option frame's label after its SetupOption. Returns nothing (a post-hook).
function BarberShop.onOption(frame)
  if type(frame) ~= "table" or frame.Label == nil then return end
  WFJ.Labels.show(SURFACE, optionKey(frame), frame.Label, nil, WFJ.Labels.families("CustomizationOption"))
end

-- A choice's name after CustomizationElementDetailsMixin:UpdateText. Returns nothing.
function BarberShop.onChoice(details)
  if type(details) ~= "table" or details.SelectionName == nil then return end
  WFJ.Labels.show(SURFACE, choiceKey(details), details.SelectionName, nil,
    WFJ.Labels.familiesWith(CHOICE_KEYS, "CustomizationChoice"))
end

-- The mixins of Blizzard_CustomizationUI's pooled frames, hooked on their tables before any frame is made. → count
BarberShop.MIXINS = { { "CustomizationOptionCheckButtonMixin", "SetupOption", BarberShop.onOption },
  { "CustomizationDropdownWithSteppersAndLabelMixin", "SetupOption", BarberShop.onOption },
  { "CustomizationOptionSliderMixin", "SetupOption", BarberShop.onOption },
  { "CustomizationElementDetailsMixin", "UpdateText", BarberShop.onChoice } }
local mixinsHooked = false
function BarberShop.hookMixins()
  if mixinsHooked then return 0 end
  local n = 0
  for _, m in ipairs(BarberShop.MIXINS) do
    local mixin = Compat.resolve(m[1])
    if type(mixin) == "table" and type(mixin[m[2]]) == "function" then
      hooksecurefunc(mixin, m[2], m[3])
      n = n + 1
    end
  end
  mixinsHooked = n > 0
  return n
end

local hooked, waiting = false, false

-- Runs once Blizzard_BarberShopUI is loaded (now, or on its ADDON_LOADED). Declared again: a declare clears Compat's
-- memo, which holds `false` for a name looked up before the addon loaded.
function BarberShop.setup()
  declare()
  local frame = get("frame")
  if hooked or type(frame) ~= "table" or type(frame.HookScript) ~= "function" then return false end
  hooked = true
  WFJ.Labels.forbidNames(BarberShop.NEVER_TOUCH) -- its widgets exist only now (Main's pass ran before the load)
  frame:HookScript("OnShow", BarberShop.onShow)
  frame:HookScript("OnHide", BarberShop.release)
  WFJ.TooltipLines.follow(BarberShop.TOOLTIP_SURFACE, get("tooltip"), WFJ.Labels.familiesWith(CAMERA_KEYS,
    "CustomizationCategory", "CustomizationOption", "CustomizationChoice"))
  if type(frame.IsShown) == "function" and frame:IsShown() then BarberShop.onShow() end
  return true
end

-- Called by Main after Compat.init, ButtonText.init and LoadOnDemand.init. → true when the window is set up now.
function BarberShop.init()
  declare()
  if hooked then return false end
  if not waiting then
    waiting = true
    WFJ.LoadOnDemand.when(BarberShop.CUSTOMIZATION_ADDON, BarberShop.hookMixins)
    return WFJ.LoadOnDemand.when(ADDON, BarberShop.setup) and hooked
  end
  return false
end
