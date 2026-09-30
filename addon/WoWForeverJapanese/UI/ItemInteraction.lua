-- UI/ItemInteraction.lua: the item interaction window on Forever (surface "iteminteraction", area "ui",
-- ADR-016, ADR-029). Load-on-demand Blizzard_ItemInteractionUI; its [Bootstrap] file registers
-- Enum.PlayerInteractionType.ItemInteraction at login (blizzard_iteminteractionui_bootstrap.lua:7–17), so the window
-- opens when an NPC or object sends that interaction. Whether Forever has one is an in-game question. Set up through
-- WFJ.LoadOnDemand.when.
-- Almost everything this window says comes from the interaction's own data (frameData: the title, the action
-- button's text and tooltip, the description, blizzard_iteminteractionui.lua:265–301) and is never touched. The
-- fixed words:
--   ItemInteractionFrame.CurrencyCost.Costs RUNEFORGE_LEGENDARY_COST_LABEL (XML text=, xml:45), shown on OnShow;
--   ItemInteractionFrame:UpdateDescription (:384–395; the frame's own method, called as `self:…`, :301, :471–473) →
--     Description, when the text is the recharge sentence SL_SET_CONVERSION_RECHARGE_TIME (GetRechargeMessage,
--     :477–483; its `%s` is a SecondsToTime duration, Core/UIStrings ARGS `time`). The same FontString holds the
--     interaction's own description, hence the restriction. (The charge sentences of :511–523 are a StaticPopup's
--     subText, :552, ADR-015 §5, not this surface.);
--   tooltips, owner = the widget: the conversion input slot's GENERIC_ITEM_CONVERSION_SLOT_TOOLTIP and
--     ERR_ITEM_CONVERSION_NO_VALID_ITEMS (:728–739; the owner is the item slot), the action button's NOT_ENOUGH_GOLD
--     (:812–819).
-- Never touched: the title (SetTitle(frameData.titleText), :265, interaction data), the action button's text, item
-- and currency names, costs. Release on the frame's OnHide.
local _, WFJ = ...
local ItemInteraction = {}
WFJ.ItemInteraction = ItemInteraction

local SURFACE = "iteminteraction"
ItemInteraction.SURFACE = SURFACE
local Compat = WFJ.Compat
local ADDON = "Blizzard_ItemInteractionUI"
local F = "ItemInteractionFrame"

ItemInteraction.NEVER_TOUCH = { F .. ".TitleContainer.TitleText", F .. ".ButtonFrame.ActionButton" }

local CANDIDATES = {
  frame = { F }, costs = { F .. ".CurrencyCost.Costs" }, description = { F .. ".Description" },
  inputSlot = { F .. ".ItemConversionFrame.ItemConversionInputSlot" }, itemSlot = { F .. ".ItemSlot" },
  action = { F .. ".ButtonFrame.ActionButton" },
}
local COSTS = { only = { "RUNEFORGE_LEGENDARY_COST_LABEL" } }
local DESCRIPTION = { only = { "SL_SET_CONVERSION_RECHARGE_TIME" } }
local SLOT_TOOLTIP = { only = { "GENERIC_ITEM_CONVERSION_SLOT_TOOLTIP", "ERR_ITEM_CONVERSION_NO_VALID_ITEMS" } }
-- NOT_ENOUGH_CURRENCY with the currency's name kept (:824–831); its English is shared with the error
-- ERR_OUT_OF_POWER_DISPLAY, a key-only group, asked for here by key
local ACTION_TOOLTIP = { only = { "NOT_ENOUGH_GOLD", "NOT_ENOUGH_CURRENCY" } }

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
end

-- OnShow and hooksecurefunc target (ItemInteractionFrame:UpdateDescription). → the number of dictionary words found
function ItemInteraction.show()
  return WFJ.Labels.showAll(SURFACE, { { "costs", get("costs"), COSTS },
    { "description", get("description"), DESCRIPTION } })
end

function ItemInteraction.release()
  return WFJ.Render.release(SURFACE)
end

local hooked, waiting = false, false

-- Runs once Blizzard_ItemInteractionUI is loaded (now, or on its ADDON_LOADED).
function ItemInteraction.setup()
  declare() -- its frames exist only now: forget what Compat memoized before
  local frame = get("frame")
  if hooked or type(frame) ~= "table" then return false end
  hooked = true
  WFJ.Labels.forbidNames(ItemInteraction.NEVER_TOUCH)
  if type(frame.UpdateDescription) == "function" then
    hooksecurefunc(frame, "UpdateDescription", ItemInteraction.show)
  end
  if type(frame.HookScript) == "function" then
    frame:HookScript("OnShow", ItemInteraction.show)
    frame:HookScript("OnHide", ItemInteraction.release)
  end
  WFJ.HelpTooltip.register(get("inputSlot"), SLOT_TOOLTIP)
  WFJ.HelpTooltip.register(get("itemSlot"), SLOT_TOOLTIP)
  WFJ.HelpTooltip.register(get("action"), ACTION_TOOLTIP)
  if type(frame.IsShown) == "function" and frame:IsShown() then ItemInteraction.show() end
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init. → true when the window
-- exists now, false while it waits for the addon.
function ItemInteraction.init()
  declare()
  if hooked then return false end
  if not waiting then
    waiting = true
    return WFJ.LoadOnDemand.when(ADDON, ItemInteraction.setup) and hooked
  end
  return false
end
