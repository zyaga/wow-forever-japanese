-- UI/UnitFrames.lua: the unit frames' fixed words on Forever (surface "unitframes", area "ui", ADR-016):
-- player / target / focus / boss / party frames and the compact (raid-style) unit frames of blizzard_unitframe, whose
-- camelot load set is the mainline one (blizzard_unitframe.toc). Almost everything on a unit frame is a NAME (unit,
-- aura) or a NUMBER (health, power, level) and is never touched; the fixed words are:
--   the target-style frames' "Dead" / "Unconscious": static XML FontStrings, text="DEAD" / text="UNCONSCIOUS"
--     (mainline/targetframe.xml:182, 187 in TargetFrameContent.TargetFrameContentMain.HealthBarsContainer; :455, :460
--     in the target-of-target HealthBar), shown and hidden by TargetFrameMixin:CheckDead (targetframe.lua:464–478).
--     Shown once at init for TargetFrame, FocusFrame, Boss1..5TargetFrame and their totFrame;
--   a compact unit frame's status text: CompactUnitFrame_UpdateStatusText (a global function, shared/
--     compactunitframe.lua:1085–1115) writes PLAYER_OFFLINE, DEAD, a health number, LOST_HEALTH or a percentage into
--     frame.statusText. Post-hooked; only the two words are ever shown. The health forms can be SECRET values on this
--     client (`issecretvalue`, blizzard_sharedxmlbase/securetypes.lua:6): the hook reads the text once, skips a
--     secret, and calls Labels.show only for one of the two words or to drop a record the client overwrote;
--   a compact raid group's title: CompactRaidGroup_InitializeForGroup: frame.title:SetFormattedText(GROUP_NUMBER,
--     groupIndex) (shared/compactraidgroup.lua:42–51), post-hooked; the compact party frame's title:
--     CompactPartyFrame_Generate → self.title:SetText(self.titleText), titleText = PARTY (shared/
--     compactpartyframe.lua:1–32, compactpartyframe.xml:11), post-hooked and shown at init when the frame exists;
--   the unit tooltip's instruction line: UnitFrame_UpdateTooltip (a global function, mainline/unitframe.lua:396–408):
--     GameTooltip_SetDefaultAnchor(GameTooltip, self) (owner = the unit frame, blizzard_sharedxml/
--     sharedtooltiptemplates.lua:87–88), GameTooltip:SetUnit, a blank line, UNIT_POPUP_RIGHT_CLICK, Show. Post-hooked:
--     when GameTooltip's owner is that frame, walked once with HelpTooltip.walkAs restricted to that one key; the
--     unit's name, level, class and guild lines never match it;
--   the "not present" icon tooltips: PartyMemberFrame's NotPresentIcon: SetText(self.tooltip) + Show
--     (mainline/partyframetemplates.xml:356–360), tooltip = PARTY_IN_PUBLIC_GROUP_MESSAGE | INCOMING_SUMMON_TOOLTIP_*
--     (mainline/partymemberframe.lua:476–495); the compact frame's centerStatusIcon: the same keys
--     (shared/compactunitframe.lua:1477–1500, 2161–2167). Owners registered with UI/HelpTooltip restricted to those
--     keys (a phased reason is client-built text and never matches): the party frames from PartyFrame's pool at init,
--     a compact frame's icon from the post-hook of CompactUnitFrame_UpdateCenterStatusIcon (registering is a table
--     write, repeated harmlessly).
-- Not here (stay English): a TextStatusBar's zero text (SetBarTextZeroText(DEAD), targetframe.lua:733,
--   partymemberframe.lua:240, 690), written inside the health text update on every health event, beside values that
--   can be secret; unit popup menu titles (RAID_TARGET_ICON, SET_FOCUS: the menu system's); HelpTips; edit-mode
--   system names.
local _, WFJ = ...
local UnitFrames = {}
WFJ.UnitFrames = UnitFrames

local SURFACE = "unitframes"
UnitFrames.SURFACE = SURFACE
local Compat = WFJ.Compat

-- Names: every unit name widget of the named frames (the compact frames' `name` is pooled and never addressed here).
UnitFrames.NEVER_TOUCH = {
  "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.PlayerName", "PlayerName",
  "TargetFrame.TargetFrameContent.TargetFrameContentMain.Name",
  "FocusFrame.TargetFrameContent.TargetFrameContentMain.Name",
  "TargetFrameToT.Name", "FocusFrameToT.Name", "PetName",
}

local TARGET_STYLE = { "TargetFrame", "FocusFrame", "Boss1TargetFrame", "Boss2TargetFrame", "Boss3TargetFrame",
  "Boss4TargetFrame", "Boss5TargetFrame" }
local DEAD = { only = { DEAD = true, UNCONSCIOUS = true } }
local STATUS = { only = { PLAYER_OFFLINE = true, DEAD = true } }
local GROUP = { only = { GROUP_NUMBER = true } }
local PARTY = { only = { PARTY = true } }
local RIGHT_CLICK = { only = { "UNIT_POPUP_RIGHT_CLICK" } }
local NOT_PRESENT = { only = { "PARTY_IN_PUBLIC_GROUP_MESSAGE", "INCOMING_SUMMON_TOOLTIP_SUMMON_PENDING",
  "INCOMING_SUMMON_TOOLTIP_SUMMON_ACCEPTED", "INCOMING_SUMMON_TOOLTIP_SUMMON_DECLINED" } }

-- The client's global writers, post-hooked by name: { global function, this module's handler }.
local GLOBAL_HOOKS = {
  { "CompactUnitFrame_UpdateStatusText", "onStatusText" },
  { "CompactUnitFrame_UpdateCenterStatusIcon", "onCenterIcon" },
  { "CompactRaidGroup_InitializeForGroup", "onGroupInit" },
  { "CompactPartyFrame_Generate", "onPartyGenerate" },
  { "UnitFrame_UpdateTooltip", "onUnitTooltip" },
}

local function declareAll()
  for _, name in ipairs(TARGET_STYLE) do Compat.declare(SURFACE, name, { name }) end
  Compat.declare(SURFACE, "partyFrame", { "PartyFrame" })
  Compat.declare(SURFACE, "compactParty", { "CompactPartyFrame" })
  Compat.declare(SURFACE, "tooltip", { "GameTooltip" })
  Compat.declare(SURFACE, "isSecret", { "issecretvalue" })
  for _, hook in ipairs(GLOBAL_HOOKS) do Compat.declare(SURFACE, hook[1], { hook[1] }) end
  Compat.declare(SURFACE, "enDead", { "DEAD" })
  Compat.declare(SURFACE, "enOffline", { "PLAYER_OFFLINE" })
end

local function get(key) return Compat.get(SURFACE, key) end

local statusKey = WFJ.Labels.keyer("status.") -- a compact frame's status text (pooled frames: keyed by widget)
local titleKey = WFJ.Labels.keyer("group.") -- a compact group's title

-- The two FontStrings of one health container (a target-style frame's, or its target-of-target's). → words found
local function showDead(prefix, container)
  if type(container) ~= "table" then return 0 end
  return WFJ.Labels.show(SURFACE, prefix .. ".dead", container.DeadText, nil, DEAD)
    + WFJ.Labels.show(SURFACE, prefix .. ".unconscious", container.UnconsciousText, nil, DEAD)
end

-- The static "Dead" / "Unconscious" labels of every target-style frame that exists. → words found
function UnitFrames.showStatic()
  local n = 0
  for _, name in ipairs(TARGET_STYLE) do
    local frame = get(name)
    if type(frame) == "table" then
      local content = frame.TargetFrameContent
      local main = type(content) == "table" and content.TargetFrameContentMain or nil
      n = n + showDead(name, type(main) == "table" and main.HealthBarsContainer or nil)
      local tot = frame.totFrame
      n = n + showDead(name .. ".tot", type(tot) == "table" and tot.HealthBar or nil)
    end
  end
  local party = get("compactParty")
  if type(party) == "table" then n = n + WFJ.Labels.show(SURFACE, "party.title", party.title, nil, PARTY) end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- → true when `text` must not be read further (a secret value: comparing it from addon code can raise).
local function secret(text)
  local isSecret = get("isSecret")
  return type(isSecret) == "function" and isSecret(text) == true
end

-- hooksecurefunc target (CompactUnitFrame_UpdateStatusText). Runs on every health event of every compact frame, so it
-- does the least it can: one GetText, and Labels.show only for one of the two words or over an existing record.
function UnitFrames.onStatusText(frame)
  local fs = type(frame) == "table" and frame.statusText or nil
  if type(fs) ~= "table" or type(fs.GetText) ~= "function" then return 0 end
  local recKey = statusKey(fs)
  local text = fs:GetText()
  if secret(text) then
    WFJ.SurfaceState.drop(SURFACE, recKey)
    return 0
  end
  if text ~= get("enDead") and text ~= get("enOffline") and not WFJ.SurfaceState.get(SURFACE, recKey) then return 0 end
  return WFJ.Labels.show(SURFACE, recKey, fs, nil, STATUS)
end

-- hooksecurefunc target (CompactRaidGroup_InitializeForGroup): "Group %d" on the group's title button.
function UnitFrames.onGroupInit(frame)
  local title = type(frame) == "table" and frame.title or nil
  if type(title) ~= "table" then return 0 end
  return WFJ.Labels.show(SURFACE, titleKey(title), title, nil, GROUP)
end

-- hooksecurefunc target (CompactPartyFrame_Generate): the frame exists from here on.
function UnitFrames.onPartyGenerate()
  Compat.declare(SURFACE, "compactParty", { "CompactPartyFrame" }) -- re-resolve: it did not exist at init
  local party = get("compactParty")
  if type(party) ~= "table" then return 0 end
  return WFJ.Labels.show(SURFACE, "party.title", party.title, nil, PARTY)
end

-- hooksecurefunc target (CompactUnitFrame_UpdateCenterStatusIcon): the icon owns a help tooltip.
function UnitFrames.onCenterIcon(frame)
  local icon = type(frame) == "table" and frame.centerStatusIcon or nil
  if type(icon) == "table" and not WFJ.HelpTooltip.registered(icon) then WFJ.HelpTooltip.register(icon, NOT_PRESENT) end
end

-- hooksecurefunc target (UnitFrame_UpdateTooltip): the unit tooltip's "<Right click for Frame Settings>" line.
function UnitFrames.onUnitTooltip(frame)
  local tt = get("tooltip")
  if type(tt) ~= "table" or type(tt.GetOwner) ~= "function" or frame == nil or tt:GetOwner() ~= frame then return 0 end
  return WFJ.HelpTooltip.walkAs(tt, RIGHT_CLICK)
end

-- The party member frames PartyFrame's pool holds now. → the number of icons registered
local function registerPartyIcons()
  local party = get("partyFrame")
  local pool = type(party) == "table" and party.PartyMemberFramePool or nil
  if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then return 0 end
  local n = 0
  for member in pool:EnumerateActive() do
    local icon = type(member) == "table" and member.NotPresentIcon or nil
    if type(icon) == "table" then
      WFJ.HelpTooltip.register(icon, NOT_PRESENT)
      n = n + 1
    end
  end
  return n
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init. → false when the mainline unit frames are
-- absent (a TargetFrame without TargetFrameContent).
function UnitFrames.init()
  declareAll()
  local target = get("TargetFrame")
  if hooked or type(target) ~= "table" or type(target.TargetFrameContent) ~= "table" then return false end
  hooked = true
  for _, hook in ipairs(GLOBAL_HOOKS) do
    local name, handler = hook[1], hook[2]
    if type(get(name)) == "function" then
      hooksecurefunc(name, function(...) return UnitFrames[handler](...) end)
    end
  end
  registerPartyIcons()
  UnitFrames.showStatic()
  return true
end
