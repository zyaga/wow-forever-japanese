-- UI/RaidManager.lua: the group manager panel at the left screen edge on Forever (surface "raidmanager", area "ui",
-- ADR-016). `camelot` loads blizzard_compactraidframes/mainline/blizzard_compactraidframemanager.lua|xml
-- (a login addon); CompactRaidFrameManager is shown whenever the player is in a group
-- (CompactRaidFrameManager_UpdateShown, lua:295–306). A manager without the widgets named here is not this panel:
-- every candidate misses and nothing is touched.
-- Static labels (XML text=, never rewritten) [verified: mainline/blizzard_compactraidframemanager.xml]:
--   displayFrame.raidMarkers.raidMarkerUnitTab / raidMarkerGroundTab   GROUPMANAGER_UNIT_MARKER / _GROUND_MARKER
--     (xml:337, 342);
--   displayFrame.RestrictPingsLabel   RAID_MANAGER_RESTRICT_PINGS_TO (xml:365);
--   CompactRaidFrameManagerLeavePartyButton   PARTY_LEAVE (xml:377).
-- Writers:
--   CompactRaidFrameManager_UpdateLabel (lua:308–314, called by global name from OnLoad :263 and OnEvent :272) →
--     displayFrame.label RAID / PARTY: post-hooked (hooksecurefunc on the global);
--   CompactRaidFrameManagerLeaveInstanceGroupButton: LeaveInstanceGroupButtonMixin:OnUpdate writes
--     INSTANCE_WALK_IN_LEAVE / INSTANCE_PARTY_LEAVE on every frame the button is visible (lua:1324–1333, xml:386–394):
--     followed with HookScript("OnUpdate"), restricted to those two keys. While the text is still ours Labels.show
--     returns at its first comparison, so the per-frame cost is one GetText;
--   the two dropdown buttons' own selection text (displayFrame.ModeControlDropdown (RAID / PARTY, lua:200–209) and
--     displayFrame.RestrictPingsDropdown (NONE / RAID_MANAGER_RESTRICT_PINGS_TO_LEAD / _ASSIST / _TANKS_HEALERS,
--     lua:174–184; built only when C_Ping.IsPingSystemEnabled())), through Labels.dropdown. The popup entries are
--     handled with the menus.
-- Help tooltips: the toolbar buttons inherit CRFManagerTooltipTemplate: OnEnter → SetOwner(self),
--   GameTooltip_SetTitle(self.tooltip or the red disabledTooltipText), Show (lua:36–49; GameTooltip_SetTitle is
--   ClearLines + AddLine, blizzard_sharedxml/sharedtooltiptemplates.lua:128–131). Owners registered with
--   UI/HelpTooltip, restricted to TOOLTIP_KEYS: editMode CRF_EDIT_MODE, settings CRF_SETTINGS, hiddenModeToggle
--   CRF_HIDE_GROUPS, everyoneIsAssistButton CRF_ALL_ASSIST, difficulty CRF_DIFFICULTY, readyCheckButton
--   CRF_READY_CHECK, rolePollButton CRF_ROLE_POLL, countdownButton CRF_COUNTDOWN (xml:234–332).
--   The disabled reason (ALL_ASSIST_NOT_LEADER_ERROR) arrives wrapped in RED_FONT_COLOR (lua:38–39): it renders once
--   that key is granted the `wrapped` label form in Core/UIStrings; until then it stays English.
-- Never touched: displayFrame.memberCountLabel ("%d/%d", lua:561), the role filter buttons ("<icon> %d/%d",
-- lua:601) and the group filter buttons (a group number, lua:104): numbers only.
local _, WFJ = ...
local RaidManager = {}
WFJ.RaidManager = RaidManager

local SURFACE = "raidmanager"
RaidManager.SURFACE = SURFACE
local Compat = WFJ.Compat

local DISPLAY = "CompactRaidFrameManager.displayFrame."
RaidManager.NEVER_TOUCH = { DISPLAY .. "memberCountLabel", DISPLAY .. "filterOptions.filterRoleTank",
  DISPLAY .. "filterOptions.filterRoleHealer", DISPLAY .. "filterOptions.filterRoleDamager" }

local CANDIDATES = {
  frame = { "CompactRaidFrameManager" },
  label = { DISPLAY .. "label" },
  unitTab = { DISPLAY .. "raidMarkers.raidMarkerUnitTab" },
  groundTab = { DISPLAY .. "raidMarkers.raidMarkerGroundTab" },
  pingsLabel = { DISPLAY .. "RestrictPingsLabel" },
  leaveParty = { "CompactRaidFrameManagerLeavePartyButton" },
  leaveInstance = { "CompactRaidFrameManagerLeaveInstanceGroupButton" },
  modeDropdown = { DISPLAY .. "ModeControlDropdown" },
  pingsDropdown = { DISPLAY .. "RestrictPingsDropdown" },
  updateLabel = { "CompactRaidFrameManager_UpdateLabel" },
}
-- The toolbar buttons that own a help tooltip (parentKeys of displayFrame).
local TOOLTIP_OWNERS = { "editMode", "settings", "hiddenModeToggle", "everyoneIsAssistButton", "difficulty",
  "readyCheckButton", "rolePollButton", "countdownButton" }
for _, key in ipairs(TOOLTIP_OWNERS) do CANDIDATES[key] = { DISPLAY .. key } end

local TOOLTIP_KEYS = { "CRF_EDIT_MODE", "CRF_SETTINGS", "CRF_HIDE_GROUPS", "CRF_ALL_ASSIST", "CRF_DIFFICULTY",
  "CRF_READY_CHECK", "CRF_ROLE_POLL", "CRF_COUNTDOWN", "ALL_ASSIST_NOT_LEADER_ERROR" }
local LABEL = { only = { "RAID", "PARTY" } }
local LEAVE_INSTANCE = { only = { "INSTANCE_PARTY_LEAVE", "INSTANCE_WALK_IN_LEAVE" } }
local STATIC = {
  { "unitTab", { only = { "GROUPMANAGER_UNIT_MARKER" } } },
  { "groundTab", { only = { "GROUPMANAGER_GROUND_MARKER" } } },
  { "pingsLabel", { only = { "RAID_MANAGER_RESTRICT_PINGS_TO" } } },
  { "leaveParty", { only = { "PARTY_LEAVE" } } },
}

local function get(key) return Compat.get(SURFACE, key) end

-- hooksecurefunc target (CompactRaidFrameManager_UpdateLabel). → 1 | 0
function RaidManager.onLabel()
  return WFJ.Labels.show(SURFACE, "label", get("label"), nil, LABEL)
end

-- HookScript("OnUpdate") target on the leave-instance button (its own OnUpdate just wrote the English). → 1 | 0
function RaidManager.onLeaveInstance()
  return WFJ.Labels.show(SURFACE, "leaveInstance", get("leaveInstance"), nil, LEAVE_INSTANCE)
end

-- The static labels, the header and both dropdown selections. → the number of dictionary words found.
function RaidManager.showAll()
  local n = RaidManager.onLabel() + RaidManager.onLeaveInstance()
  for _, item in ipairs(STATIC) do n = n + WFJ.Labels.show(SURFACE, item[1], get(item[1]), nil, item[2]) end
  n = n + WFJ.Labels.dropdown(SURFACE, "modeDropdown", get("modeDropdown"))
  n = n + WFJ.Labels.dropdown(SURFACE, "pingsDropdown", get("pingsDropdown"))
  WFJ.Render.updateBanner(SURFACE)
  return n
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function RaidManager.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  local frame = get("frame")
  -- a manager without displayFrame.raidMarkers tabs and BottomButtons is not this panel
  if hooked or type(frame) ~= "table" or type(get("unitTab")) ~= "table" then return false end
  hooked = true
  if type(get("updateLabel")) == "function" then
    hooksecurefunc("CompactRaidFrameManager_UpdateLabel", RaidManager.onLabel)
  end
  local leave = get("leaveInstance")
  if type(leave) == "table" and type(leave.HookScript) == "function" then
    leave:HookScript("OnUpdate", RaidManager.onLeaveInstance)
  end
  if type(frame.HookScript) == "function" then frame:HookScript("OnShow", RaidManager.showAll) end
  for _, key in ipairs(TOOLTIP_OWNERS) do
    local owner = get(key)
    if type(owner) == "table" then WFJ.HelpTooltip.register(owner, { only = TOOLTIP_KEYS }) end
  end
  RaidManager.showAll()
  return true
end
