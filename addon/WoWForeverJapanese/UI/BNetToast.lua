-- UI/BNetToast.lua: the Battle.net toast and the play-time alert on Forever (surface "bnettoast", area "ui",
-- ADR-016). Blizzard_BNet loads at login ([Family]\BNet.lua is the mainline file, which camelot takes, ADR-029).
-- Both frames are SocialToastTemplate alerts (blizzard_socialtoast/socialtoast.xml:44) above the chat frame.
-- BNToastFrame (bnet.xml:3): BNToastMixin:ShowToast (mainline/bnet.lua:193–298, the frame's own method, called as
--   self:ShowToast) writes, per toast type:
--   DoubleLine: BN_TOAST_NEW_INVITE (:210), BN_TOAST_PENDING_INVITES with the request count (:215),
--     BN_TOAST_NEW_CLUB_INVITATION with the community's colour-wrapped name, kept as written (:279, :287);
--   BottomLine: BN_TOAST_OFFLINE (:250), and BN_TOAST_ONLINE wrapped a second time in FRIENDS_GRAY_COLOR (:237; the
--     `wrapped` form: the grey kept around the Japanese, the inner green "online" colour kept by the
--     Japanese); a broadcast's BottomLine is the friend's own message (:266), which the key restriction never
--     matches.
--   TopLine / MiddleLine are the friend's account and character names (:227, :235, :248, :263): never touched.
-- TimeAlertFrame (bnet.xml:83): BNetTimeAlertMixin:OnUpdate rewrites Text every frame while shown with
--   TIME_PLAYED_ALERT and SecondsToTime's session length (mainline/bnet.lua:361–363). The frame's OnUpdate script is
--   post-hooked (HookScript), so the addon's line is the one on screen at the end of each frame; the duration inside it
--   is kept as the client wrote it unless the dictionary's duration entries cover it.
-- The toast's click-through tooltip (TooltipFrame, :84–85) repeats the broadcast message: player text, not touched.
local _, WFJ = ...
local BNetToast = {}
WFJ.BNetToast = BNetToast

local SURFACE = "bnettoast"
BNetToast.SURFACE = SURFACE
local Compat = WFJ.Compat

BNetToast.NEVER_TOUCH = { "BNToastFrame.TopLine", "BNToastFrame.MiddleLine", "BNToastFrame.TooltipFrame.Text" }

local CANDIDATES = {
  toast = { "BNToastFrame" }, double = { "BNToastFrame.DoubleLine" }, bottom = { "BNToastFrame.BottomLine" },
  alert = { "TimeAlertFrame" }, alertText = { "TimeAlertFrame.Text" },
}

local DOUBLE = { only = { "BN_TOAST_NEW_INVITE", "BN_TOAST_PENDING_INVITES", "BN_TOAST_NEW_CLUB_INVITATION" } }
local BOTTOM = { only = { "BN_TOAST_OFFLINE", "BN_TOAST_ONLINE" } }
local ALERT = { only = { "TIME_PLAYED_ALERT" } }

local function get(key) return Compat.get(SURFACE, key) end

-- hooksecurefunc target (BNToastFrame:ShowToast). → the number of dictionary words found.
function BNetToast.onToast()
  local n = WFJ.Labels.show(SURFACE, "double", get("double"), nil, DOUBLE)
    + WFJ.Labels.show(SURFACE, "bottom", get("bottom"), nil, BOTTOM)
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- HookScript target (TimeAlertFrame's OnUpdate). → 1 | 0
function BNetToast.onAlert()
  return WFJ.Labels.show(SURFACE, "alert", get("alertText"), nil, ALERT)
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function BNetToast.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  if hooked then return false end
  local toast, alert = get("toast"), get("alert")
  local any = false
  if type(toast) == "table" and type(toast.ShowToast) == "function" then
    hooksecurefunc(toast, "ShowToast", BNetToast.onToast)
    any = true
  end
  if type(alert) == "table" and type(alert.HookScript) == "function" and type(alert.Start) == "function" then
    alert:HookScript("OnUpdate", BNetToast.onAlert)
    any = true
  end
  hooked = any
  return any
end
