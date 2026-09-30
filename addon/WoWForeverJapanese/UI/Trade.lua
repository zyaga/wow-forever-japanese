-- UI/Trade.lua: the player trade window on Forever (surface "trade", area "ui", ADR-016 / ADR-029).
-- camelot loads blizzard_uipanels_game/mainline/tradeframe.lua|xml (Blizzard_UIPanels_Game.toc, mainline family);
-- TradeFrame opens on the server's TRADE_SHOW (tradeframe.lua:7, 32–38).
-- - Static (written once by the XML / an OnLoad, shown on the frame's OnShow):
--     TradeFramePlayerEnchantText / TradeFrameRecipientEnchantText  TRADEFRAME_ENCHANT_SLOT_LABEL
--                             (tradeframe.xml:205, 210)
--     TradeFrameTradeButton   TRADE, written to self.Text by TradeFrameTradeButtonMixin:OnLoad (tradeframe.lua:306–308)
--     TradeFrameCancelButton  CANCEL (tradeframe.xml:430)
-- - Writers: TradeFrame_UpdatePlayerItem(id) / TradeFrame_UpdateTargetItem(id) (tradeframe.lua:96–118, 145–166) write
--   the enchant slot's name text (id 7): the enchantment's name (left English), or
--   HIGHLIGHT_FONT_COLOR_CODE .. TRADEFRAME_NOT_MODIFIED_TEXT .. "|r" (:106, :154): the `wrapped` label form. Both are
--   globals called by name from TradeFrame_OnEvent / TradeFrame_Update (:33–52, :73–76): post-hooked by name. Slots
--   1–6 carry item names and are never read.
-- - Tooltip: TradeFrameTradeButtonMixin:OnEnter adds TRADE_WARNING_CHANGED_OFFER (with the other player's name) as an
--   error line (tradeframe.lua:85–93, 311–317): the button is a help-tooltip owner restricted to that key.
-- Never touched: TradeFramePlayerNameText / TradeFrameRecipientNameText (player names, :71–72), the item name
-- FontStrings of slots 1–6, the money EditBoxes.
-- Release on TradeFrame's OnHide.
local _, WFJ = ...
local Trade = {}
WFJ.Trade = Trade

local SURFACE = "trade"
Trade.SURFACE = SURFACE
local Compat = WFJ.Compat

local ENCHANT_SLOT = 7 -- TRADE_ENCHANT_SLOT = MAX_TRADE_ITEMS (tradeframe.lua:1–3)

Trade.NEVER_TOUCH = { "TradeFramePlayerNameText", "TradeFrameRecipientNameText" }
for i = 1, ENCHANT_SLOT - 1 do
  Trade.NEVER_TOUCH[#Trade.NEVER_TOUCH + 1] = "TradePlayerItem" .. i .. "Name"
  Trade.NEVER_TOUCH[#Trade.NEVER_TOUCH + 1] = "TradeRecipientItem" .. i .. "Name"
end

local CANDIDATES = {
  frame = { "TradeFrame" }, tradeButton = { "TradeFrameTradeButton" }, cancelButton = { "TradeFrameCancelButton" },
  playerEnchantLabel = { "TradeFramePlayerEnchantText" }, recipientEnchantLabel = { "TradeFrameRecipientEnchantText" },
  playerEnchant = { "TradePlayerItem" .. ENCHANT_SLOT .. "Name" },
  recipientEnchant = { "TradeRecipientItem" .. ENCHANT_SLOT .. "Name" },
}

local LABEL = { only = { "TRADEFRAME_ENCHANT_SLOT_LABEL" } }
local NOT_MODIFIED = { only = { "TRADEFRAME_NOT_MODIFIED_TEXT" } } -- an enchantment's name never matches
local WARNING = { only = { "TRADE_WARNING_CHANGED_OFFER" } }

local function get(key) return Compat.get(SURFACE, key) end

-- The static labels (TradeFrame's OnShow). → the number of dictionary words found.
function Trade.onShow()
  return WFJ.Labels.showAll(SURFACE, {
    { "trade", get("tradeButton"), { only = { "TRADE" } } },
    { "cancel", get("cancelButton"), { only = { "CANCEL" } } },
    { "playerEnchantLabel", get("playerEnchantLabel"), LABEL },
    { "recipientEnchantLabel", get("recipientEnchantLabel"), LABEL },
    { "playerEnchant", get("playerEnchant"), NOT_MODIFIED },
    { "recipientEnchant", get("recipientEnchant"), NOT_MODIFIED },
  })
end

-- hooksecurefunc targets (TradeFrame_UpdatePlayerItem / _UpdateTargetItem): only the enchant slot holds a fixed word.
function Trade.onPlayerItem(id)
  if id ~= ENCHANT_SLOT then return 0 end
  return WFJ.Labels.show(SURFACE, "playerEnchant", get("playerEnchant"), nil, NOT_MODIFIED)
end

function Trade.onTargetItem(id)
  if id ~= ENCHANT_SLOT then return 0 end
  return WFJ.Labels.show(SURFACE, "recipientEnchant", get("recipientEnchant"), nil, NOT_MODIFIED)
end

function Trade.release()
  return WFJ.Render.release(SURFACE)
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function Trade.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  Compat.declare(SURFACE, "updatePlayerItem", { "TradeFrame_UpdatePlayerItem" })
  Compat.declare(SURFACE, "updateTargetItem", { "TradeFrame_UpdateTargetItem" })
  local frame = get("frame")
  if hooked or type(frame) ~= "table" or type(frame.HookScript) ~= "function" then return false end
  hooked = true
  frame:HookScript("OnShow", Trade.onShow)
  frame:HookScript("OnHide", Trade.release)
  if type(get("updatePlayerItem")) == "function" then
    hooksecurefunc("TradeFrame_UpdatePlayerItem", Trade.onPlayerItem)
  end
  if type(get("updateTargetItem")) == "function" then
    hooksecurefunc("TradeFrame_UpdateTargetItem", Trade.onTargetItem)
  end
  local button = get("tradeButton")
  if type(button) == "table" then WFJ.HelpTooltip.register(button, WARNING) end
  return true
end
