-- UI/ClubFinder.lua: the guild and community finder on Forever (surface "communities.clubfinder", area "ui",
-- ADR-016): the two finder panels (CommunitiesFrame.GuildFinderFrame and .CommunityFinderFrame, both
-- ClubFinderGuildAndCommunityFrameTemplate), their search options, cards, request-to-join dialogs and pending lists,
-- the finder invitation panel (CommunitiesFrame.ClubFinderInvitationFrame) and the guild recruitment dialog
-- (CommunitiesFrame.RecruitmentDialog). ClubFinder loads unconditionally; whether the finder shows is the runtime
-- C_ClubFinder.IsEnabled() (clubfinder.lua:1818-1827). The applicant list is UI/ClubFinderApplicants. Plumbing:
-- UI/CommunitiesKit. Every file:line is the camelot extract 1.60.1.69913, blizzard_communities/.
-- Static labels: the options' dropdown labels (ClubFinderDropdownMixin:OnLoad writes labelText, clubfinder.lua:18-21;
--   clubfinder.xml:803-815, 1059, 1064), the Search button and box placeholder, PendingTextFrame.Text (xml:1052), the
--   disabled panel (xml:1270-1275), the searching spinner (xml:884), the cards' Request to Join buttons and reported
--   notes (xml:753, 781, 937), the request-to-join dialog (xml:560-680), the invitation panel's buttons (xml:78-118)
--   and its join warning's buttons (xml:43-54), the recruitment dialog (xml:251-479).
-- Writers: the panel's UpdateType / GetDisplayModeBasedOnSelectedTab and the card lists' BuildCardList →
--   InsetFrame.GuildDescription (lua:1609, 1781, 1952-1999); InsetFrame's XML OnShow → ErrorDescription, red-wrapped
--   (xml:1244-1252); a card's UpdateCard / SetReportedCardState → RequestStatus and Focus (lua:1220-1290, 1330-1460;
--   community cards are ScrollBox rows whose Init calls UpdateCard, lua:1320-1326, 1520-1524, and lists re-run it on
--   live cards, lua:1542-1546); RequestToJoinFrame:Initialize → RecruitingSpecDescriptions (lua:444-458);
--   ClubFinderInvitationFrame:DisplayInvitation → Type, Leader, MemberCount, InvitationText (lua:2047-2067);
--   the join warning's OnShow → DialogLabel (lua:2167-2175); the dropdowns' selection text (Labels.dropdown).
-- Help tooltips: the role checkboxes (lua:2208-2224), the Search button (lua:1040-1044), the two side tabs
--   (tooltip = SEARCH, xml:1286; CLUB_FINDER_PENDING_REQUESTS, lua:1809-1972), the cards (a guild card anchors to its
--   list, lua:1298; a community card to itself, lua:1466; CommunitiesUtil.AddLookingForLines adds "Looking For:",
--   blizzard_framexmlutil/communitiesutil.lua:337-357), the Apply buttons (lua:287-293, 2096-2126).
-- Never touched: club names, descriptions, leaders, member counts, spec names (the spec checkboxes), edit boxes.
local _, WFJ = ...
local Kit = WFJ.CommunitiesKit
local ClubFinder = {}
WFJ.ClubFinder = ClubFinder

local SURFACE = "communities.clubfinder"
ClubFinder.SURFACE = SURFACE

local CF = "CommunitiesFrame"
local CI = CF .. ".ClubFinderInvitationFrame"
local RD = CF .. ".RecruitmentDialog"

ClubFinder.NEVER_TOUCH = { CI .. ".Name", CI .. ".Description", CI .. ".RequestToJoinFrame.ClubName",
  CI .. ".RequestToJoinFrame.ClubDescription", CI .. ".RequestToJoinFrame.MessageFrame.MessageScroll.EditBox",
  RD .. ".RecruitmentMessageFrame.RecruitmentMessageInput.EditBox", RD .. ".MinIlvlOnly.EditBox" }
for _, f in ipairs({ ".GuildFinderFrame", ".CommunityFinderFrame" }) do
  for _, w in ipairs({ ".OptionsList.SearchBox", ".RequestToJoinFrame.ClubName", ".RequestToJoinFrame.ClubDescription",
    ".RequestToJoinFrame.MessageFrame.MessageScroll.EditBox" }) do
    ClubFinder.NEVER_TOUCH[#ClubFinder.NEVER_TOUCH + 1] = CF .. f .. w
  end
end

local k = Kit.new(SURFACE, {
  guild = { CF .. ".GuildFinderFrame", "ClubFinderGuildFinderFrame" },
  community = { CF .. ".CommunityFinderFrame", "ClubFinderCommunityAndGuildFinderFrame" },
  invitation = { CI }, recruitment = { RD },
})

local FOCUS = { "CLUB_FINDER_FOCUS_SOCIAL_LEVELING", "GUILD_INTEREST_DUNGEON", "GUILD_INTEREST_RAID", "PVP_ENABLED",
  "GUILD_INTEREST_RP" }
local function plus(list, ...)
  local out = {}
  for _, v in ipairs(list) do out[#out + 1] = v end
  for i = 1, select("#", ...) do out[#out + 1] = (select(i, ...)) end
  return out
end
ClubFinder.KEYS = {
  description = { "COMMUNITIES_GUILD_FINDER_DESCRIPTION2", "CLUB_FINDER_NO_OPTIONS_SELECTED_GUILD_MESSAGE",
    "BROWSE_SEARCH_TEXT", "CLUB_FINDER_SEARCH_NOTHING_FOUND" },
  error = { "COMMUNITY_FEATURE_UNAVAILABLE_MUTED", "COMMUNITY_FEATURE_UNAVAILABLE_SILENCED" },
  status = { "CLUB_FINDER_REPORTED", "CLUB_FINDER_ALREADY_IN_THAT_CLUB", "CLUB_FINDER_PENDING", "CLUB_FINDER_INVITED",
    "CLUB_FINDER_DECLINED", "CLUB_FINDER_CANCELED", "CLUB_FINDER_JOINED" },
  card = { "CLUB_FINDER_REALM_NAME", "CLUB_FINDER_ACTIVE_MEMBERS", "CLUB_FINDER_LEADER",
    "CROSS_FACTION_CLUB_FINDER_SEARCH_OPTION", "CLUB_FINDER_LOOKING_FOR",
    "CLUB_FINDER_APPLICANT_LIST_NO_MATCHING_SPECS",
    "CLUB_FINDER_RECRUITING_ALL_SPECS" }, -- CommunitiesUtil.AddLookingForLines (communitiesutil.lua:342)
  specs = { "CLUB_FINDER_GUILD_LOOKING_ALL_SPECS", "CLUB_FINDER_COMMUNITY_LOOKING_ALL_SPECS",
    "CLUB_FINDER_RECRUITING_ONE_SPEC", "CLUB_FINDER_RECRUITING_TWO_SPECS", "CLUB_FINDER_RECRUITING_THREE_SPECS",
    "CLUB_FINDER_RECRUITING_FOUR_SPECS" },
  -- the dropdowns' selection texts (a spec + class selection and a language name stay as written)
  focus = plus(FOCUS, "CLUB_FINDER_ANY_FLAG", "CLUB_FINDER_MULTIPLE_CHECKED"),
  lookingFor = { "CLUB_FINDER_MULTIPLE_ROLES", "CLUB_FINDER_ANY_FLAG" },
  filter = plus(FOCUS, "CLUB_FINDER_ANY_FLAG", "CLUB_FINDER_MULTIPLE_CHECKED",
    "CROSS_FACTION_CLUB_FINDER_SEARCH_OPTION"),
  size = { "CLUB_FINDER_ANY_FLAG", "SMALL", "CLUB_FINDER_MEDIUM", "LARGE" },
  sort = { "CLUB_FINDER_SORT_BY_RELEVANCE", "CLUB_FINDER_SORT_BY_MOST_MEMBERS", "CLUB_FINDER_SORT_BY_NEWEST" },
}
local K = ClubFinder.KEYS

-- A request-to-join dialog's labels (the finder panels' and the invitation panel's). → list
local function requestLabels(p, rtj)
  local c = function(path) return Kit.child(rtj, path) end
  return {
    { p .. "rtj.label", c("DialogLabel"), { "CLUB_FINDER_REQUEST_TO_JOIN" } },
    { p .. "rtj.notRecruiting", c("ClubDescription2"), { "CLUB_FINDER_NOT_RECRUITING_YOUR_SPECS" } },
    { p .. "rtj.error", c("ErrorDescription"), { "CLUB_FINDER_NO_MATCHING_SPEC_DIALOG_ERR_STRING" } },
    { p .. "rtj.apply", c("Apply"), { "CLUB_FINDER_APPLY" } }, { p .. "rtj.cancel", c("Cancel"), { "CANCEL" } },
    { p .. "rtj.note", c("MessageFrame.MessageScroll.EditBox.Instructions"), { "CLUB_FINDER_RECRUITING_NOTE" } },
  }
end

-- One finder panel's load-time labels.
local function panelLabels(p, f)
  local c = function(path) return Kit.child(f, path) end
  local list = {
    { p .. "pending", c("OptionsList.PendingTextFrame.Text"), { "CLUB_FINDER_PENDING_CLUBS_LIST" } },
    { p .. "filterLabel", c("OptionsList.ClubFilterDropdown.Label"), { "FILTER" } },
    { p .. "sizeLabel", c("OptionsList.ClubSizeDropdown.Label"), { "CLUB_FINDER_GUILD_SIZE" } },
    { p .. "sortLabel", c("OptionsList.SortByDropdown.Label"), { "CLUB_FINDER_SORT_BY" } },
    { p .. "search", c("OptionsList.Search"), { "SEARCH" } },
    { p .. "searchBox", c("OptionsList.SearchBox.Instructions"), { "SEARCH" } },
    { p .. "disabledTitle", c("DisabledFrame.Title"), { "GUILD" } },
    { p .. "disabledText", c("DisabledFrame.Description"), { "COMMUNITIES_GUILD_FINDER_DESCRIPTION" } },
    { p .. "searching", c("GuildCards.SearchingSpinner.Label"), { "SEARCHING" } },
    { p .. "pendingSearching", c("PendingGuildCards.SearchingSpinner.Label"), { "SEARCHING" } },
  }
  for _, item in ipairs(requestLabels(p, c("RequestToJoinFrame"))) do list[#list + 1] = item end
  return list
end

-- The recruitment dialog's and the invitation panel's load-time labels.
local function dialogLabels()
  local r = function(path) return Kit.child(k.get("recruitment"), path) end
  local i = function(path) return Kit.child(k.get("invitation"), path) end
  local list = {
    { "rd.label", r("DialogLabel"), { "GUILD_RECRUITMENT" } },
    { "rd.list", r("ShouldListClub.Label"), { "CLUB_FINDER_LIST_GUILD" } },
    { "rd.focus", r("ClubFocusDropdown.Label"), { "CLUB_FINDER_FOCUS" } },
    { "rd.lookingFor", r("LookingForDropdown.Label"), { "CLUB_FINDER_LOOKING_FOR" } },
    { "rd.language", r("LanguageDropdown.Label"), { "LANGUAGE" } },
    { "rd.message", r("RecruitmentMessageFrame.Label"), { "CLUB_FINDER_RECRUITMENT_MESSAGE" } },
    { "rd.messageHint", r("RecruitmentMessageFrame.RecruitmentMessageInput.EditBox.Instructions"),
      { "CLUB_FINDER_RECRUITMENT_DESCRIPTION" } },
    { "rd.maxLevel", r("MaxLevelOnly.Label"), { "CLUB_FINDER_MAX_LEVEL_ONLY" } },
    { "rd.minIlvl", r("MinIlvlOnly.Label"), { "LFG_LIST_ITEM_LEVEL_REQ" } },
    { "rd.minIlvlHint", r("MinIlvlOnly.EditBox.Text"), { "STAT_AVERAGE_ITEM_LEVEL" } },
    { "rd.accept", r("Accept"), { "ACCEPT" } }, { "rd.cancel", r("Cancel"), { "CANCEL" } },
    { "ci.accept", i("AcceptButton"), { "ACCEPT" } }, { "ci.apply", i("ApplyButton"), { "CLUB_FINDER_APPLY" } },
    { "ci.decline", i("DeclineButton"), { "DECLINE" } },
    { "ci.warnAccept", i("WarningDialog.Accept"), { "ACCEPT" } },
    { "ci.warnCancel", i("WarningDialog.Cancel"), { "CANCEL" } },
  }
  for _, item in ipairs(requestLabels("ci.", i("RequestToJoinFrame"))) do list[#list + 1] = item end
  return list
end

local cardKey = WFJ.Labels.keyer("card.") -- a card's record key (never a position in its list)

-- A card after UpdateCard / SetReportedCardState (guild cards are fixed, community cards pooled rows).
function ClubFinder.onCard(card)
  if type(card) ~= "table" then return 0 end
  local n = k.show(cardKey(card) .. ".status", card.RequestStatus, K.status)
    + k.show(cardKey(card) .. ".focus", card.Focus, { "CLUB_FINDER_FOCUS_STRING" })
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- A card seen for the first time: its names are never ours; its labels, writers and tooltip.
function ClubFinder.watchCard(card)
  if type(card) ~= "table" then return end
  for _, field in ipairs({ "Name", "Description", "MemberCount" }) do
    if type(card[field]) == "table" then WFJ.Labels.forbid(card[field]) end
  end
  k.show(cardKey(card) .. ".join", card.RequestJoin, { "CLUB_FINDER_REQUEST_TO_JOIN" })
  k.show(cardKey(card) .. ".reported", card.ReportedDescription, { "CLUB_FINDER_THANK_YOU_REPORTED" })
  k.after(card, "UpdateCard", ClubFinder.onCard)
  k.after(card, "SetReportedCardState", ClubFinder.onCard)
  k.tooltip(card, K.card)
  ClubFinder.onCard(card)
end

-- hooksecurefunc target (a panel's UpdateType / GetDisplayModeBasedOnSelectedTab, a list's BuildCardList): `self` is
-- the panel or one of its card lists.
function ClubFinder.onDescription(self)
  local panel = self
  if type(self) == "table" and type(self.InsetFrame) ~= "table" and type(self.GetParent) == "function" then
    panel = self:GetParent()
  end
  if type(panel) ~= "table" then return 0 end
  local p = panel == k.get("guild") and "guild." or "community."
  return k.showList({
    { p .. "description", Kit.child(panel, "InsetFrame.GuildDescription"), K.description },
    { p .. "error", Kit.child(panel, "InsetFrame.ErrorDescription"), K.error },
  })
end

-- hooksecurefunc target (a RequestToJoinFrame's Initialize); the record key follows the dialog.
local rtjKey = WFJ.Labels.keyer("rtj.")
function ClubFinder.onRequest(rtj)
  if type(rtj) ~= "table" then return 0 end
  local n = k.show(rtjKey(rtj), rtj.RecruitingSpecDescriptions, K.specs)
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- hooksecurefunc target (ClubFinderInvitationFrame:DisplayInvitation), and the join warning's OnShow.
function ClubFinder.onInvitation()
  local i = function(path) return Kit.child(k.get("invitation"), path) end
  return k.showList({
    { "ci.type", i("Type"), { "CLUB_FINDER_TYPE_GUILD", "CLUB_FINDER_COMMUNITY_TYPE" } },
    { "ci.leader", i("Leader"), { "COMMUNITIES_INVIVATION_FRAME_LEADER_FORMAT" } },
    { "ci.members", i("MemberCount"), { "COMMUNITIES_INVITATION_FRAME_MEMBER_COUNT" } },
    { "ci.text", i("InvitationText"), { "COMMUNITY_INVITATION_FRAME_INVITATION_TEXT" } },
    { "ci.warning", i("WarningDialog.DialogLabel"), { "CLUB_FINDER_ACCEPT_GUILD_ALREADY_IN_GUILD_WARNING",
      "CLUB_FINDER_ACCEPT_GUILD_STANDARD_WARNING" } },
  })
end

local function setupPanel(p, f)
  if type(f) ~= "table" then return end
  local c = function(path) return Kit.child(f, path) end
  k.showList(panelLabels(p, f))
  for _, role in ipairs({ "TankRoleFrame", "HealerRoleFrame", "DpsRoleFrame" }) do
    k.tooltip(c("OptionsList." .. role .. ".Checkbox"),
      { "CLUB_FINDER_ROLE_TOOLTIP", "YOUR_CLASS_MAY_NOT_PERFORM_ROLE" })
  end
  k.tooltip(c("OptionsList.Search"), { "CLUB_FINDER_SEARCH_ERROR" })
  k.tooltip(c("ClubFinderSearchTab"), { "SEARCH" })
  k.tooltip(c("ClubFinderPendingTab"), { "CLUB_FINDER_PENDING_REQUESTS" })
  k.tooltip(c("RequestToJoinFrame.Apply"), { "CLUB_FINDER_ONE_SPEC_REQUIRED" })
  k.dropdown(p .. "filter", c("OptionsList.ClubFilterDropdown"), K.filter)
  k.dropdown(p .. "size", c("OptionsList.ClubSizeDropdown"), K.size)
  k.dropdown(p .. "sort", c("OptionsList.SortByDropdown"), K.sort)
  k.after(f, "UpdateType", ClubFinder.onDescription)
  k.after(f, "GetDisplayModeBasedOnSelectedTab", ClubFinder.onDescription)
  k.script(c("InsetFrame"), "OnShow", function() ClubFinder.onDescription(f) end)
  k.after(c("RequestToJoinFrame"), "Initialize", ClubFinder.onRequest)
  for _, list in ipairs({ "GuildCards", "PendingGuildCards" }) do
    k.tooltip(c(list), K.card) -- a guild card's tooltip is owned by its list (clubfinder.lua:1298)
    k.after(c(list), "BuildCardList", ClubFinder.onDescription)
    for _, card in ipairs(c(list .. ".Cards") or {}) do ClubFinder.watchCard(card) end
  end
  for _, list in ipairs({ "CommunityCards", "PendingCommunityCards" }) do
    k.after(c(list), "BuildCardList", ClubFinder.onDescription)
    k.rows(c(list .. ".ScrollBox"), ClubFinder.watchCard)
  end
  ClubFinder.onDescription(f)
end

local hooked = false

function ClubFinder.setup()
  if not Kit.ready(k, ClubFinder.NEVER_TOUCH) then return false end
  k.showList(dialogLabels())
  if hooked then return false end
  hooked = true
  setupPanel("guild.", k.get("guild"))
  setupPanel("community.", k.get("community"))
  local ci, rd = k.get("invitation"), k.get("recruitment")
  local i = function(path) return Kit.child(ci, path) end
  k.after(ci, "DisplayInvitation", ClubFinder.onInvitation)
  k.script(i("WarningDialog"), "OnShow", ClubFinder.onInvitation)
  k.after(i("RequestToJoinFrame"), "Initialize", ClubFinder.onRequest)
  k.tooltip(i("AcceptButton"),
    { "CLUB_FINDER_IS_GUILD_LEADER_JOIN_ERROR", "CLUB_FINDER_ALREADY_IN_GUILD_PLEASE_LEAVE" })
  k.tooltip(i("ApplyButton"), { "CLUB_FINDER_ALREADY_IN_THAT_CLUB", "CLUB_FINDER_ALREADY_APPLIED_ERROR" })
  k.tooltip(i("RequestToJoinFrame.Apply"), { "CLUB_FINDER_ONE_SPEC_REQUIRED" })
  k.dropdown("rd.focusDropdown", Kit.child(rd, "ClubFocusDropdown"), K.focus)
  k.dropdown("rd.lookingForDropdown", Kit.child(rd, "LookingForDropdown"), K.lookingFor)
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init.
function ClubFinder.init() return Kit.init(k, ClubFinder.setup) end
