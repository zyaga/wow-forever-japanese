-- UI/ZoneText.lua: the zone banner's PvP line and the follow status on Forever (surface "zonetext", area "ui",
-- ADR-016). Blizzard_FrameXML loads mainline/zonetext.lua|xml on camelot. The zone and subzone names
-- (ZoneTextString, SubZoneTextString: GetZoneText / GetSubZoneText, zonetext.lua:88, 105, 115, 130) are place names
-- and are never touched. The lines under them are dictionary words, written by the global SetZoneText
-- (zonetext.lua:7–69), which ZoneText_OnEvent calls by name (:90, 106, 116), so a post-hook on the global sees every
-- write:
--   PVPInfoTextString / PVPArenaTextString  SANCTUARY_TERRITORY (:17), FREE_FOR_ALL_TERRITORY (:22),
--                                           FACTION_CONTROLLED_TERRITORY "(%s Territory)" (:28, 35; %s is the
--                                           faction name, kept English), CONTESTED_TERRITORY (:41), COMBAT_ZONE (:47)
-- SetZoneText reads PVPInfoTextString:GetText() back only to compare it with "" (:64): a shown Japanese line is
-- non-empty exactly when the English was, so the anchor it picks is unchanged.
-- AutoFollowStatus (zonetext.xml:57–73) binds its OnEvent by reference (`function="AutoFollowStatus_OnEvent"`), so
-- the global is never looked up again: the frame's script is hooked instead. AutoFollowStatusText holds
-- AUTOFOLLOWSTART / AUTOFOLLOWSTOP ("Following %s."; %s is the followed unit, kept as written; zonetext.lua:147, 152).
local _, WFJ = ...
local ZoneText = {}
WFJ.ZoneText = ZoneText

local SURFACE = "zonetext"
ZoneText.SURFACE = SURFACE
local Compat = WFJ.Compat

ZoneText.NEVER_TOUCH = { "ZoneTextString", "SubZoneTextString" } -- place names

local CANDIDATES = {
  pvpInfo = { "PVPInfoTextString" }, pvpArena = { "PVPArenaTextString" },
  followFrame = { "AutoFollowStatus" }, followText = { "AutoFollowStatusText" },
  setZoneText = { "SetZoneText" },
}

local PVP = { only = { "SANCTUARY_TERRITORY", "FREE_FOR_ALL_TERRITORY", "FACTION_CONTROLLED_TERRITORY",
  "CONTESTED_TERRITORY", "COMBAT_ZONE" } }
local FOLLOW = { only = { "AUTOFOLLOWSTART", "AUTOFOLLOWSTOP" } }

local function get(key) return Compat.get(SURFACE, key) end

-- hooksecurefunc target (SetZoneText). → the number of dictionary lines found.
function ZoneText.onZoneText()
  local n = WFJ.Labels.show(SURFACE, "pvpInfo", get("pvpInfo"), nil, PVP)
    + WFJ.Labels.show(SURFACE, "pvpArena", get("pvpArena"), nil, PVP)
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- HookScript target (AutoFollowStatus OnEvent). → 1 | 0
function ZoneText.onFollow()
  return WFJ.Labels.show(SURFACE, "follow", get("followText"), nil, FOLLOW)
end

local hooked = false

-- Called by Main after Compat.init.
function ZoneText.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  if hooked then return false end
  if type(get("pvpInfo")) ~= "table" or type(get("setZoneText")) ~= "function" then return false end
  hooked = true
  hooksecurefunc("SetZoneText", ZoneText.onZoneText)
  local follow = get("followFrame")
  if type(follow) == "table" and type(follow.HookScript) == "function" then
    follow:HookScript("OnEvent", ZoneText.onFollow)
  end
  ZoneText.onZoneText()
  return true
end
