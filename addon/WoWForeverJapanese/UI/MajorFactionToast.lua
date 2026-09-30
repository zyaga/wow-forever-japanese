-- UI/MajorFactionToast.lua: the renown level-up and faction-unlocked banners on Forever (surface
-- "majorfactiontoast", area "ui", ADR-016). Blizzard_MajorFactions loads at login on camelot, and the system
-- behind it is live there: camelot's own PvP rank panel and reputation window read C_MajorFactions
-- (blizzard_uipanels_game/camelot/pvprankframe.lua:91, 134; camelot/reputationframe.lua:556, 844). Whether the server
-- lets a given faction toast is its data (`hideRenownLevelUpToast`, blizzard_majorfactionrenowntoast.lua:18): an
-- in-game check. Both banners are shown by TopBannerManager through the frame's own PlayBanner method
-- (blizzard_framexml/topbannermanager.lua:33, 55 `frame:PlayBanner(data)`), post-hooked on each frame:
--   MajorFactionsRenownToast.RenownLabel   MAJOR_FACTION_RENOWN_LEVEL_TOAST "Renown %d" (renowntoast.lua:91)
--   MajorFactionUnlockToast.HeaderText     JOURNEY_UNLOCKED_TOAST or
--                                          WAR_WITHIN_LANDING_PAGE_ALERT_MAJOR_FACTION_UNLOCKED (unlocktoast.lua:46,
--                                          48; the XML default, unlocktoast.xml:18)
--   the reward icon's tooltip (owner MajorFactionsRenownToast.RewardIconMouseOver, renowntoast.lua:117–158):
--     RENOWN_REWARD_CAPSTONE_TOOLTIP_TITLE / _DESC / _DESC2, RENOWN_REWARD_MILESTONE_TOOLTIP_TITLE "Renown %d
--     Rewards". A single reward's title and description are its name and server text; "- %s" lines carry reward
--     names: the owner is registered with exactly the four keys, so none of those is ever matched.
-- Never touched: MajorFactionUnlockToast.FactionName (a faction), RewardDescription (server text).
-- Without either frame nothing is hooked.
local _, WFJ = ...
local MajorFactionToast = {}
WFJ.MajorFactionToast = MajorFactionToast

local SURFACE = "majorfactiontoast"
MajorFactionToast.SURFACE = SURFACE
local Compat = WFJ.Compat

MajorFactionToast.NEVER_TOUCH = { "MajorFactionUnlockToast.FactionName", "MajorFactionsRenownToast.RewardDescription" }

local CANDIDATES = {
  renown = { "MajorFactionsRenownToast" }, renownLabel = { "MajorFactionsRenownToast.RenownLabel" },
  rewardOwner = { "MajorFactionsRenownToast.RewardIconMouseOver" },
  unlock = { "MajorFactionUnlockToast" }, unlockHeader = { "MajorFactionUnlockToast.HeaderText" },
}
local RENOWN = { only = { "MAJOR_FACTION_RENOWN_LEVEL_TOAST" } }
local UNLOCK = { only = { "JOURNEY_UNLOCKED_TOAST", "WAR_WITHIN_LANDING_PAGE_ALERT_MAJOR_FACTION_UNLOCKED" } }
local TOOLTIP = { only = { "RENOWN_REWARD_CAPSTONE_TOOLTIP_TITLE", "RENOWN_REWARD_CAPSTONE_TOOLTIP_DESC",
  "RENOWN_REWARD_CAPSTONE_TOOLTIP_DESC2", "RENOWN_REWARD_MILESTONE_TOOLTIP_TITLE" } }

local function get(key) return Compat.get(SURFACE, key) end

-- hooksecurefunc target (MajorFactionsRenownToast:PlayBanner). → 1 | 0
function MajorFactionToast.onRenown()
  return WFJ.Labels.show(SURFACE, "renown", get("renownLabel"), nil, RENOWN)
end

-- hooksecurefunc target (MajorFactionUnlockToast:PlayBanner). → 1 | 0
function MajorFactionToast.onUnlock()
  return WFJ.Labels.show(SURFACE, "unlock", get("unlockHeader"), nil, UNLOCK)
end

local hooked = false

-- Called by Main after Compat.init and HelpTooltip.init.
function MajorFactionToast.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  local renown, unlock = get("renown"), get("unlock")
  if hooked or (type(renown) ~= "table" and type(unlock) ~= "table") then return false end -- neither frame
  hooked = true
  if type(renown) == "table" and type(renown.PlayBanner) == "function" then
    hooksecurefunc(renown, "PlayBanner", MajorFactionToast.onRenown)
  end
  if type(unlock) == "table" and type(unlock.PlayBanner) == "function" then
    hooksecurefunc(unlock, "PlayBanner", MajorFactionToast.onUnlock)
  end
  local owner = get("rewardOwner")
  if type(owner) == "table" then WFJ.HelpTooltip.register(owner, TOOLTIP) end
  return true
end
