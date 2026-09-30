-- UI/ClubFinderApplicants.lua: the club finder's applicant list on Forever (surface "communities.applicants",
-- area "ui", ADR-016): CommunitiesFrame.ApplicantList (ClubFinderApplicantListFrameTemplate), shown to a
-- guild or community leader instead of the roster. Plumbing: UI/CommunitiesKit.
-- Every file:line is the camelot extract 1.60.1.69913, interface/addons/blizzard_communities/.
-- Column headers: ApplicantList.ColumnDisplay:LayoutColumns(APPLICANT_COLUMN_INFO) runs in the list's OnLoad
--   (clubfinderapplicantlist.lua:1-37, 254-256), before this addon: the pooled headers are walked now and after any
--   later layout (the roster titles, CLUB_FINDER_SPEC and ITEM_LEVEL_ABBR).
-- Rows: the ScrollBox element initializer calls UpdateMemberInfo (lua:258-262), which writes RequestStatus (the
--   applicant's state, lua:173-189) and AllSpec (NONE when no spec, lua:121-127); the Invite button's own label is
--   xml:35. Name, Level, ItemLevel and Note are the applicant's own and never touched.
-- Help tooltips: the row (lua:211-240: the applicant's name, spec lines and note are not matched), the Invite button
--   (lua:509-517) and the decline button (lua:571-575).
local _, WFJ = ...
local Kit = WFJ.CommunitiesKit
local Applicants = {}
WFJ.ClubFinderApplicants = Applicants

local SURFACE = "communities.applicants"
Applicants.SURFACE = SURFACE

local AL = "CommunitiesFrame.ApplicantList"
Applicants.NEVER_TOUCH = {}

local k = Kit.new(SURFACE, { list = { AL }, columns = { AL .. ".ColumnDisplay" }, rows = { AL .. ".ScrollBox" } })

local COLUMNS = { "COMMUNITIES_ROSTER_COLUMN_TITLE_LEVEL", "COMMUNITIES_ROSTER_COLUMN_TITLE_CLASS",
  "COMMUNITIES_ROSTER_COLUMN_TITLE_NAME", "CLUB_FINDER_SPEC", "ITEM_LEVEL_ABBR",
  "COMMUNITIES_ROSTER_COLUMN_TITLE_NOTE" }
local STATUS = { "CLUB_FINDER_PENDING", "CLUB_FINDER_APPROVED", "CLUB_FINDER_JOINED", "CLUB_FINDER_JOINED_ANOTHER",
  "CLUB_FINDER_CANCELED", "CLUB_FINDER_DECLINED" }
local ROW_TIP = { "UNIT_TYPE_LEVEL_FACTION_TEMPLATE", "UNIT_TYPE_LEVEL_TEMPLATE", "LFG_LIST_ITEM_LEVEL_CURRENT",
  "CLUB_FINDER_SPECIALIZATIONS", "CLUB_FINDER_APPLICANT_LIST_NO_MATCHING_SPECS" }

local rowKey = WFJ.Labels.keyer("row.") -- a pooled row's record key (never a position)

-- One applicant row after UpdateMemberInfo.
function Applicants.onRow(row)
  for _, field in ipairs({ "Name", "Level", "ItemLevel", "Note" }) do
    if type(row[field]) == "table" then WFJ.Labels.forbid(row[field]) end
  end
  local id = rowKey(row)
  k.show(id .. ".status", row.RequestStatus, STATUS)
  k.show(id .. ".allSpec", row.AllSpec, { "NONE" })
  k.show(id .. ".invite", Kit.child(row, "InviteButton.Text"), { "INVITE" })
  k.tooltip(row, ROW_TIP)
  k.tooltip(row.InviteButton, { "INVITE", "CLUB_FINDER_MAX_MEMBER_COUNT_HIT" })
  k.tooltip(row.CancelInvitationButton, { "DECLINE" })
  WFJ.Render.updateBanner(SURFACE)
end

local hooked = false

function Applicants.setup()
  if not Kit.ready(k, Applicants.NEVER_TOUCH) then return false end
  if hooked then return false end
  hooked = true
  k.headers(k.get("columns"), COLUMNS, "column.")
  k.rows(k.get("rows"), Applicants.onRow)
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init.
function Applicants.init() return Kit.init(k, Applicants.setup) end
