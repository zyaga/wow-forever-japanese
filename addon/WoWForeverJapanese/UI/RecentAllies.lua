-- UI/RecentAllies.lua: the social window's Recent Allies panel on Forever (surface "recentallies", area "ui",
-- ADR-016). Blizzard_RecentAllies loads at login; RecentAlliesFrame.List (RecentAlliesListTemplate) is a
-- child of FriendsFrame (blizzard_friendsframe/camelot/friendsframe.xml:775–777), shown by the contacts header's
-- Recent Allies tab when C_RecentAllies.IsSystemEnabled() (camelot/friendsframe.lua:456, 622; the tab and the title
-- are UI/Friends.lua's).
-- The panel has no fixed labels: a row is a name, a level, a class, a location and the last activity's description
-- (server text). Everything the dictionary can show is a help tooltip on a pooled row, so each row and its buttons
-- are registered from the ScrollBox's initialized-frame callback (keyed by widget), each restricted to its keys:
--   the row (RecentAlliesEntryMixin:BuildRecentAllyTooltip, blizzard_recentalliestemplates.lua:153–225): the
--     "Recent Activities" / "<time> ago" double line (:203–206). Its name, race, class, faction, location, note and
--     activity lines are names or server text and are never matched; the level / race line
--     RECENT_ALLY_TOOLTIP_LEVEL_RACE_FORMAT "Level %d  %s  %s" (:163–167), its atlas divider and the race name kept
--     as written (`text`);
--   PartyButton: "Invite to Group", and "Player Offline" when disabled (:367–380);
--   StateIconContainer.PinDisplay: "Pinned Ally" / "Pinned Ally (Expires in <time>)" (:406–418).
-- The time arguments are SecondsFormatter output (blizzard_recentalliesutil.lua:50–59), kept as written unless the
-- dictionary's duration entries cover them.
-- Never touched: CharacterData.Name / Level / Class / Location / MostRecentInteraction.
-- The SocialUI card view in the same file (RecentAlliesSocialView*, :425 on) is not handled here.
-- Set up only where FriendsFrame carries SetTitle (the mainline social window, UI/Labels.title).
local _, WFJ = ...
local RecentAllies = {}
WFJ.RecentAllies = RecentAllies

local SURFACE = "recentallies"
RecentAllies.SURFACE = SURFACE
local Compat = WFJ.Compat

RecentAllies.NEVER_TOUCH = {}

local CANDIDATES = {
  friends = { "FriendsFrame" }, list = { "RecentAlliesFrame.List" }, rows = { "RecentAlliesFrame.List.ScrollBox" },
  scrollUtil = { "ScrollUtil" },
}

local ROW_TIP = { only = { "RECENT_ALLY_RECENT_ACTIVITIES_LABEL", "RECENT_ALLY_INTERACTION_TIME_FORMAT",
  "RECENT_ALLY_TOOLTIP_LEVEL_RACE_FORMAT" } }
local PARTY_TIP = { only = { "RECENT_ALLIES_PARTY_BUTTON_TOOLTIP", "RECENT_ALLIES_PARTY_BUTTON_OFFLINE_TOOLTIP" } }
local PIN_TIP = { only = { "RECENT_ALLY_PIN_TOOLTIP", "RECENT_ALLY_PIN_EXPIRING_TOOLTIP" } }

local function get(key) return Compat.get(SURFACE, key) end

-- One pooled row after its initializer ran: (owner, frame, elementData) for a new row, (frame, elementData) for the
-- iterateExisting pass. A divider row has none of the children. Returns nothing (ForEachFrame stops on a truthy one).
function RecentAllies.onRow(a, b)
  local row = a
  if a == RecentAllies then row = b end
  if type(row) ~= "table" then return end
  local register = WFJ.HelpTooltip.register
  if type(row.CharacterData) == "table" then
    register(row, ROW_TIP)
    local data = row.CharacterData
    for _, key in ipairs({ "Name", "Level", "Class", "Location", "MostRecentInteraction" }) do
      WFJ.Labels.forbid(data[key]) -- names and server text, whatever a later pass is asked to show
    end
  end
  if type(row.PartyButton) == "table" then register(row.PartyButton, PARTY_TIP) end
  local pin = type(row.StateIconContainer) == "table" and row.StateIconContainer.PinDisplay or nil
  if type(pin) == "table" then register(pin, PIN_TIP) end
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function RecentAllies.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  local friends, rows, util = get("friends"), get("rows"), get("scrollUtil")
  if hooked or type(rows) ~= "table" or type(friends) ~= "table" or type(friends.SetTitle) ~= "function" then
    return false -- a social window without SetTitle, or a client without the panel
  end
  if type(util) ~= "table" or type(util.AddInitializedFrameCallback) ~= "function" then return false end
  hooked = true
  util.AddInitializedFrameCallback(rows, RecentAllies.onRow, RecentAllies, true)
  return true
end
