-- UI/GuildRegistrar.lua: the guild master NPC's window on Forever (surface "guildregistrar", area "ui",
-- ADR-016 / ADR-029). camelot loads blizzard_uipanels_game/mainline/guildregistrarframe.lua|xml; the frame is
-- registered for Enum.PlayerInteractionType.Registrar (guildregistrarframe.lua:14–21).
-- Every word is XML text, written once; the two panels swap with Show / Hide (GuildRegistrar_OnShow,
-- GuildRegistrar_ShowPurchaseFrame, guildregistrarframe.lua:1–12), so one pass on the frame's OnShow covers both:
--     AvailableServicesText            AVAILABLE_SERVICES (guildregistrarframe.xml:54)
--     GuildRegistrarFrameGoodbyeButton / GuildRegistrarFrameCancelButton  CANCEL (:63, :132)
--     GuildRegistrarButton1–3          GUILD_CHARTER_PURCHASE, GUILD_CHARTER_REGISTER, GUILD_CREST_DESIGN (:74–91)
--     GuildRegistrarPurchaseText       GUILD_REGISTRAR_PURCHASE_TEXT (:107)
--     GuildRegistrarCostLabel          COSTS_LABEL (:113)
--     GuildRegistrarFramePurchaseButton  PURCHASE (:143)
-- The purchase button's trial-account tooltip is RED .. TRIAL_RESTRICTED .. "|r" (xml:154–166): a help-tooltip owner
-- restricted to that key (the `wrapped` label form).
-- Never touched: GuildRegistrarFrameNpcNameText (the NPC's name, lua:5), GuildRegistrarText (the NPC's own greeting)
-- and GuildRegistrarFrameEditBox (the guild name the player types; Blizzard reads it back, lua:27).
-- Release on the frame's OnHide.
local _, WFJ = ...
local GuildRegistrar = {}
WFJ.GuildRegistrar = GuildRegistrar

local SURFACE = "guildregistrar"
GuildRegistrar.SURFACE = SURFACE
local Compat = WFJ.Compat

GuildRegistrar.NEVER_TOUCH = { "GuildRegistrarFrameNpcNameText", "GuildRegistrarText", "GuildRegistrarFrameEditBox" }

local SERVICES = { only = { "GUILD_CHARTER_PURCHASE", "GUILD_CHARTER_REGISTER", "GUILD_CREST_DESIGN" } }
local CANCEL = { only = { "CANCEL" } }
local LABELS = {
  { "services", "AvailableServicesText", { only = { "AVAILABLE_SERVICES" } } },
  { "goodbye", "GuildRegistrarFrameGoodbyeButton", CANCEL },
  { "cancel", "GuildRegistrarFrameCancelButton", CANCEL },
  { "service1", "GuildRegistrarButton1", SERVICES },
  { "service2", "GuildRegistrarButton2", SERVICES },
  { "service3", "GuildRegistrarButton3", SERVICES },
  { "purchaseText", "GuildRegistrarPurchaseText", { only = { "GUILD_REGISTRAR_PURCHASE_TEXT" } } },
  { "costLabel", "GuildRegistrarCostLabel", { only = { "COSTS_LABEL" } } },
  { "purchase", "GuildRegistrarFramePurchaseButton", { only = { "PURCHASE" } } },
}
local TRIAL = { only = { "TRIAL_RESTRICTED" } }

local function get(key) return Compat.get(SURFACE, key) end

function GuildRegistrar.onShow()
  local list = {}
  for i, item in ipairs(LABELS) do list[i] = { item[1], get(item[1]), item[3] } end
  return WFJ.Labels.showAll(SURFACE, list)
end

function GuildRegistrar.release()
  return WFJ.Render.release(SURFACE)
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function GuildRegistrar.init()
  Compat.declare(SURFACE, "frame", { "GuildRegistrarFrame" })
  for _, item in ipairs(LABELS) do Compat.declare(SURFACE, item[1], { item[2] }) end
  local frame = get("frame")
  if hooked or type(frame) ~= "table" or type(frame.HookScript) ~= "function" then return false end
  hooked = true
  frame:HookScript("OnShow", GuildRegistrar.onShow)
  frame:HookScript("OnHide", GuildRegistrar.release)
  local purchase = get("purchase")
  if type(purchase) == "table" then WFJ.HelpTooltip.register(purchase, TRIAL) end
  return true
end
