-- UI/PartyPose.lua: the end-of-match "party pose" screens on Forever (surface "partypose", area "ui",
-- ADR-016). Three load-on-demand windows share Blizzard_PartyPoseUI's PartyPoseFrameTemplate and its one writer, so
-- they share this file; each is waited for through WFJ.LoadOnDemand.when:
--   Blizzard_MatchCelebrationPartyPoseUI: MatchCelebrationPartyPoseFrame, shown by the SHOW_PARTY_POSE_UI handler
--     (blizzard_game/mainline/eventimplementation.lua:163–165 → ShowMatchCelebrationPartyPoseFrame, bootstrap:7–10);
--   Blizzard_IslandsPartyPoseUI / Blizzard_WarfrontsPartyPoseUI: IslandsPartyPoseFrame / WarfrontsPartyPoseFrame,
--     shown by ISLAND_COMPLETED / WARFRONT_COMPLETED (blizzard_game/mainline/eventrouting.lua:56, 116 →
--     blizzard_partyposeui_bootstrap.lua:7–19). The TOCs load them on `camelot`; whether the Forever servers ever
--     send those events is an in-game question (checklist), so they are served rather than assumed dead.
-- Writer: <frame>:LoadPartyPose (PartyPoseMixin, blizzard_partyposeui.lua:345–370; the frame's own method, called as
--   self:LoadPartyPose from LoadScreen / LoadScreenByPartyPoseID, :400–414) →
--   TitleText PARTY_POSE_VICTORY / PARTY_POSE_DEFEAT, or the party pose's own title from the client table,
--     never matched (:352–358);
--   the leave button, via self:SetLeaveButtonText() (:369): ISLAND_LEAVE / WARFRONTS_LEAVE / INSTANCE_LEAVE
--     (each addon's lua), and the match celebration's ExtraButton CLOSE, or a table-driven label, never matched
--     (blizzard_matchcelebrationpartyposeui.lua:25, 35).
-- Static: RewardAnimations.RewardFrame.Label YOU_EARNED_LABEL (blizzard_partyposeui.xml:68, 138).
-- Never touched: the reward's Name (an item or currency name) and Count.
local _, WFJ = ...
local PartyPose = {}
WFJ.PartyPose = PartyPose

local SURFACE = "partypose"
PartyPose.SURFACE = SURFACE
local Compat = WFJ.Compat

PartyPose.NEVER_TOUCH = {}

-- addon → { frame, leave button path under the frame, extra button path | nil }
local WINDOWS = {
  Blizzard_MatchCelebrationPartyPoseUI = { "MatchCelebrationPartyPoseFrame", "ButtonContainer.LeaveButton",
    "ButtonContainer.ExtraButton" },
  Blizzard_IslandsPartyPoseUI = { "IslandsPartyPoseFrame", "LeaveButton" },
  Blizzard_WarfrontsPartyPoseUI = { "WarfrontsPartyPoseFrame", "LeaveButton" },
}
local ADDON_ORDER = { "Blizzard_MatchCelebrationPartyPoseUI", "Blizzard_IslandsPartyPoseUI",
  "Blizzard_WarfrontsPartyPoseUI" }

local TITLE = { only = { "PARTY_POSE_VICTORY", "PARTY_POSE_DEFEAT" } }
local LEAVE = { only = { "INSTANCE_LEAVE", "ISLAND_LEAVE", "WARFRONTS_LEAVE" } }
local EXTRA = { only = { "CLOSE" } }
local EARNED = { only = { "YOU_EARNED_LABEL" } }

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  for addon, w in pairs(WINDOWS) do
    Compat.declare(SURFACE, addon .. ".frame", { w[1] })
    Compat.declare(SURFACE, addon .. ".title", { w[1] .. ".TitleText" })
    Compat.declare(SURFACE, addon .. ".leave", { w[1] .. "." .. w[2] })
    Compat.declare(SURFACE, addon .. ".earned", { w[1] .. ".RewardAnimations.RewardFrame.Label" })
    Compat.declare(SURFACE, addon .. ".rewardName", { w[1] .. ".RewardAnimations.RewardFrame.Name" })
    if w[3] then Compat.declare(SURFACE, addon .. ".extra", { w[1] .. "." .. w[3] }) end
  end
end

-- Shows one window's labels (the hooksecurefunc target of its LoadPartyPose). → the number of dictionary words found.
function PartyPose.show(addon)
  if not WINDOWS[addon] then return 0 end
  return WFJ.Labels.showAll(SURFACE, {
    { addon .. ".title", get(addon .. ".title"), TITLE }, { addon .. ".leave", get(addon .. ".leave"), LEAVE },
    { addon .. ".extra", get(addon .. ".extra"), EXTRA }, { addon .. ".earned", get(addon .. ".earned"), EARNED },
  })
end

local hooked = {}

-- One addon's part: runs once it is loaded (now, or on its ADDON_LOADED). → true when its window was found.
function PartyPose.setup(addon)
  declare() -- its frame exists only now: forget what Compat memoized before
  local frame = get(addon .. ".frame")
  if type(frame) ~= "table" then return false end
  WFJ.Labels.forbid(get(addon .. ".rewardName")) -- an item or currency name
  if not hooked[addon] then
    hooked[addon] = true
    if type(frame.LoadPartyPose) == "function" then
      hooksecurefunc(frame, "LoadPartyPose", function() PartyPose.show(addon) end)
    end
  end
  PartyPose.show(addon)
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init.
-- → true when at least one of the addons was already loaded.
function PartyPose.init()
  declare()
  local any = false
  for _, addon in ipairs(ADDON_ORDER) do
    if WFJ.LoadOnDemand.when(addon, function() PartyPose.setup(addon) end) then any = true end
  end
  return any
end
