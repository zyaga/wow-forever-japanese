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
--   MajorFactionsRenownToast.RewardDescription  the level's rewards' toastDescription, joined with "|n"
--                                          (SetupRewardVisuals, renowntoast.lua:50-88, called from PlayBanner :102):
--                                          each piece the RenownRewardToast family, all or nothing, "|n" kept; a
--                                          piece with no shipped row leaves the whole text as the client wrote it
--   the reward icon's tooltip (owner MajorFactionsRenownToast.RewardIconMouseOver, renowntoast.lua:117–158):
--     RENOWN_REWARD_CAPSTONE_TOOLTIP_TITLE / _DESC / _DESC2, RENOWN_REWARD_MILESTONE_TOOLTIP_TITLE "Renown %d
--     Rewards", and a single reward's title and description (RenownRewardUtil.GetRenownRewardInfo: the reward's
--     name and description), the RenownRewardName and RenownRewardDescription families. "- %s" lines carry reward
--     names inside a template that is not in the set, so they are never matched; an item's, a mount's or a spell's
--     own name has no row and stays English.
-- Never touched: MajorFactionUnlockToast.FactionName (a faction).
-- Without either frame nothing is hooked.
local _, WFJ = ...
local MajorFactionToast = {}
WFJ.MajorFactionToast = MajorFactionToast

local SURFACE = "majorfactiontoast"
MajorFactionToast.SURFACE = SURFACE
local Compat = WFJ.Compat

MajorFactionToast.NEVER_TOUCH = { "MajorFactionUnlockToast.FactionName" }

local CANDIDATES = {
  renown = { "MajorFactionsRenownToast" }, renownLabel = { "MajorFactionsRenownToast.RenownLabel" },
  rewardOwner = { "MajorFactionsRenownToast.RewardIconMouseOver" },
  rewardDescription = { "MajorFactionsRenownToast.RewardDescription" },
  unlock = { "MajorFactionUnlockToast" }, unlockHeader = { "MajorFactionUnlockToast.HeaderText" },
}
local RENOWN = { only = { "MAJOR_FACTION_RENOWN_LEVEL_TOAST" } }
local UNLOCK = { only = { "JOURNEY_UNLOCKED_TOAST", "WAR_WITHIN_LANDING_PAGE_ALERT_MAJOR_FACTION_UNLOCKED" } }
local TOOLTIP_KEYS = { "RENOWN_REWARD_CAPSTONE_TOOLTIP_TITLE", "RENOWN_REWARD_CAPSTONE_TOOLTIP_DESC",
  "RENOWN_REWARD_CAPSTONE_TOOLTIP_DESC2", "RENOWN_REWARD_MILESTONE_TOOLTIP_TITLE" }

local function get(key) return Compat.get(SURFACE, key) end

-- The reward description: every "|n"-joined piece a RenownRewardToast row, or the client's text untouched. → 1 | 0
function MajorFactionToast.showRewardDescription()
  local fs = WFJ.Labels.widget(get("rewardDescription"))
  if not fs then return 0 end
  local rec = WFJ.SurfaceState.get(SURFACE, "rewardDescription")
  if rec and rec.fs == fs and rec.applied ~= nil and fs:GetText() == rec.applied then return 1 end -- still ours
  local text, parts = fs:GetText(), {}
  if type(text) ~= "string" or text == "" then return WFJ.Labels.showArgs(SURFACE, "rewardDescription", fs, nil) end
  local only = WFJ.Labels.families("RenownRewardToast").only
  for piece in (text .. "|n"):gmatch("(.-)|n") do
    local part = WFJ.Labels.part(piece, only)
    if not part then return WFJ.Labels.showArgs(SURFACE, "rewardDescription", fs, nil) end
    if #parts > 0 then parts[#parts + 1] = "|n" end
    parts[#parts + 1] = part
  end
  return WFJ.Labels.showArgs(SURFACE, "rewardDescription", fs, parts[1].key, { form = "seq", parts = parts })
end

-- hooksecurefunc target (MajorFactionsRenownToast:PlayBanner). → the number of dictionary words found
function MajorFactionToast.onRenown()
  local n = WFJ.Labels.show(SURFACE, "renown", get("renownLabel"), nil, RENOWN)
    + MajorFactionToast.showRewardDescription()
  WFJ.Render.updateBanner(SURFACE)
  return n
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
  if type(owner) == "table" then
    WFJ.HelpTooltip.register(owner,
      WFJ.Labels.familiesWith(TOOLTIP_KEYS, "RenownRewardName", "RenownRewardDescription"))
  end
  return true
end
