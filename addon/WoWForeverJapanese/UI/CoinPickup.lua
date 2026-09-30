-- UI/CoinPickup.lua: the money pickup box (click a coin amount) on Forever (surface "coinpickup", area "ui",
-- ADR-016). Blizzard_FrameXML loads mainline/coinpickupframe.lua|xml on camelot. Its two buttons carry static XML
-- text: CoinPickupOkayButton OKAY, CoinPickupCancelButton COINPICKUP_CANCEL (coinpickupframe.xml:69, 78); nothing
-- rewrites them, so they are shown on OnShow. CoinPickupText is the amount with a coin letter concatenated
-- (`money .. symbol`, coinpickupframe.lua:72, 101, 137, 167, 204, 217): a composite, never touched.
local _, WFJ = ...
local CoinPickup = {}
WFJ.CoinPickup = CoinPickup

local SURFACE = "coinpickup"
CoinPickup.SURFACE = SURFACE
local Compat = WFJ.Compat

CoinPickup.NEVER_TOUCH = { "CoinPickupText" } -- the amount: a number with a coin letter

local CANDIDATES = {
  frame = { "CoinPickupFrame" }, okay = { "CoinPickupOkayButton" }, cancel = { "CoinPickupCancelButton" },
}
local OKAY, CANCEL = { only = { "OKAY" } }, { only = { "COINPICKUP_CANCEL", "CANCEL" } }

-- HookScript target (CoinPickupFrame OnShow). → the number of words found.
function CoinPickup.onShow()
  return WFJ.Labels.showAll(SURFACE, { { "okay", Compat.get(SURFACE, "okay"), OKAY },
    { "cancel", Compat.get(SURFACE, "cancel"), CANCEL } })
end

local hooked = false

-- Called by Main after Compat.init and ButtonText.init.
function CoinPickup.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  if hooked then return false end
  local frame = Compat.get(SURFACE, "frame")
  if type(frame) ~= "table" then return false end
  hooked = true
  if type(frame.HookScript) == "function" then frame:HookScript("OnShow", CoinPickup.onShow) end
  CoinPickup.onShow()
  return true
end
