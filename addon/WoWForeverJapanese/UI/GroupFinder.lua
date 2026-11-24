-- UI/GroupFinder.lua: the Looking For Group window on Forever (surface "groupfinder", area "ui", ADR-016).
-- Blizzard_GroupFinder_VanillaStyle is load-on-demand (its toc: LoadOnDemand 1, AllowLoadGameType classic, camelot);
-- SetLookingForGroupUIAvailable loads it (blizzard_lfgutil/camelot/lfgutil.lua:1–7), and ToggleGroupFinderFrame
-- (blizzard_game/shared/game.lua:73–88), its TOGGLEGROUPFINDER binding (bindings.xml:2–4), the who binding
-- (blizzard_framexml/bindings_camelot.xml:1252–1254) and the queue-status eye (blizzard_queuestatusframe/camelot/
-- queuestatusframeoverrides.lua:5–10) open it. LFGParentFrame holds three panels: LFGListingFrame (Create Listing),
-- LFGBrowseFrame (Group Browser) and LFGWhoListFrame (Who List: UI/Friends.lua's, not touched here).
-- LFGVANILLA_SETTING_MODERN_STYLE is true (mainline/lfgvanilla_constants.lua:6): the bottom tabs are hidden and the
-- side tabs carry the tab names as tooltips (blizzard_lfgvanilla_parentframe.lua:63–71).
-- Static labels (XML text= or an OnLoad write; each restricted to its own keys):
--   the three panels' TitleContainer.TitleText, written directly with SetText(LFG_TITLE), never SetTitle
--     (blizzard_lfgvanilla_listing.lua:80, blizzard_lfgvanilla_browse.lua:135, mainline/wholist.lua:201–203);
--   LFGListingFrame: GroupRoleButtons.RolePollButton ROLE_POLL (mainline/blizzard_lfgvanilla_listing.xml:389),
--     LockedView.ActivityText LFG_LIST_MY_ACTIVITY_LIST_HEADER (xml:601), ActivityView.VoiceChatLabel VOICE_CHAT
--     (xml:554), ActivityView.LevelRangesCheckbox.Text LFG_LIST_IGNORE_SUGGESTED_LEVEL (xml:564–590);
--   LFGBrowseFrame: SearchingSpinner.Label SEARCHING (mainline/blizzard_lfgvanilla_browse.xml:509),
--     SendMessageButton SEND_MESSAGE (xml:525);
--   LFGBrowseSearchEntryTooltip: Delisted, NewPlayerFriendlyText, CompletedEncounterHeader (xml:326–360).
-- Dynamic, each post-hooked (a frame's own method, or a global looked up by name at call time):
--   LFGParentFrame:UpdateTabs → Tab1 LFG_LIST_TAB_1 / LFG_LIST_EDIT (parentframe.lua:73–78);
--   LFGListingPostButton_UpdateText → PostButton List Self / List Group / Update (listing.lua:610–618);
--   LFGListingBackButton_UpdateText → BackButton LFG_LIST_UNLIST or BACK (listing.lua:643–649);
--   LFGListingLockedView_RefreshContent → LockedView.ErrorText (listing.lua:1089–1097);
--   LFGListingFrame.ActivityView OnShow (HookScript: the XML binds the global by reference) → the comment box's
--     Instructions FontString, DESCRIPTION_OF_YOUR_GROUP / LFG_AUTHENTICATOR_DESCRIPTION_BOX (listing.lua:822, 838).
--     The EditBox's own text is never touched;
--   LFGBrowseFrame:UpdateResults → NoResultsFound (browse.lua:189); :UpdateButtonState → GroupInviteButton (:305);
--   LFGBrowseSearchEntry_Update (global, browse.lua:351–357, and on the row's events) and the ScrollBox's
--     initialized-frame callback → a result row's ActivityName: LFG_SELF_LISTING, "%d activities" or a single
--     activity's name (browse.lua:417–426, 474), its DataDisplay.Solo.RolesText LFG_TOOLTIP_ROLES (xml:23), and a
--     divider row's CategoryLabel (browse.lua:73–79);
--   LFGBrowseSearchEntryTooltip_UpdateAndShow → MemberCount (browse.lua:695–699), VoiceChat, VOICE_CHAT_MODE_FORMAT
--     around the listing's voice mode, an entry (browse.lua:702–708, blizzard_lfgvanilla_voicechat.lua), the
--     activity lines of its activityPool (an activity's name, a group's name, "  <activity>" under a group,
--     browse.lua:711–806) and the defeated bosses of its completedEncounterPool (:813–833). The tooltip's width
--     is taken from the English lines before the hook runs (:707, 748, 769, 794, 840) and it is not measured again,
--     so a wider Japanese line widens the tooltip here;
--   the dropdown buttons' own text, after DropdownTextMixin:UpdateText (blizzard_menu/menutemplates.lua:740–741):
--     the category (CATEGORY default, LFG_TYPE_NONE, LFG_SELF_LISTING, or the chosen category's name, browse.lua:
--     1049–1052, 1082), the activity filter (LFGBROWSE_ACTIVITY_HEADER_DEFAULT / LFGBROWSE_ACTIVITY_HEADER, or the
--     one chosen activity's name, browse.lua:1247–1259), the group role (TANK / HEALER / DAMAGER, listing.lua:
--     591–593), the voice chat mode (its default text and the chosen radio, VOICE_CHAT_MODE_NONE / _LEGACY /
--     _DISCORD / _CUSTOM, listing.lua:48–69). The popup entries themselves are UI/Menus': the category menu's
--     categories and the activity filter menu's groups and activities come here through the tags' `show`
--     (GroupFinder.showCategoryEntry, GroupFinder.showActivityEntry), after the client has shown the menu;
--   LFGListingLockedView_RefreshContent → the lines of the group's own listing, one pooled frame's Text each
--     (listing.lua:1205–1326): an activity's name, "  <activity>" under a group, and a group's name followed by
--     its count in the highlight colour. The client sizes each frame to its English text before the hook runs
--     (:1322–1326); the frame is sized again to the text shown.
--   the hover of a locked line that stands for a group and its count: the pooled frame's OnEnter writes one
--     GameTooltip:SetText holding the group and, under it, each activity after the indent, joined by line breaks
--     (frame.tooltip, listing.lua:1295–1300, 1325; mainline/blizzard_lfgvanilla_listing.xml:240–245). Each pooled
--     frame is a help-tooltip owner whose line this module splits: every line of it by the rule of a locked line,
--     the line breaks and indents kept. The names of one hover are Japanese together or English together.
-- Help tooltips (GameTooltip:SetText / AddLine on the frame): the side tabs' tooltipText (SidePanelTabButtonMixin:
--   OnEnter, blizzard_sharedxml/mainline/shareduipaneltemplates.lua:408–416), the role buttons'
--   ROLE_DESCRIPTION_<role> + CLASS_ROLE_NOT_RECOMMENDED (listing.xml:22–31), the role-poll button, the role
--   dropdown SELECT_YOUR_ROLE, the new-player-friendly button, the post button's error text, the refresh button
--   LFG_LIST_SEARCH_AGAIN
--   (browse.xml:474–475). Each owner is restricted to the keys it shows.
-- The client-table words of the finder (ADR-042), shown whatever the names choice is: a category's name
-- (LfgCategory: the listing's category buttons, LFGListingCategorySelection_AddButton → button:SetText(
-- categoryInfo.name), listing.lua:776–794; the browse dropdown's text and menu), an activity group's name
-- (LfgActivityGroup: "Dungeons", "Raids") and the activity "Custom" (LfgActivity), wherever a group or an activity
-- is written: the listing's rows (NameButton.Name, LFGListingActivityView_InitActivityGroupButton /
-- _InitActivityButton, listing.lua:1063–1130, the name button re-sized to the text shown), a browse row, the
-- filter dropdown and its menu, the result tooltip and the locked view.
-- Game names (ADR-106): every other activity is a dungeon, a raid, a battleground or a zone
-- (LFGUtil_GetActivityInfoName, blizzard_lfgvanilla_parentframe.lua:270–273), and a group with no table word is a
-- continent. While Japanese names are on, each of those widgets shows the name's Japanese (UI/NameLabels); a name
-- with no line in the name list, and every name while names are English, stays as the client wrote it.
-- None of these widgets is a secure button or is measured on the way to a protected call: the rows are plain
-- Buttons and Frames (mainline/blizzard_lfgvanilla_listing.xml:126–250, blizzard_lfgvanilla_browse.xml:139–275),
-- and the client measures only the leader's name on a result row (browse.lua:489), its own English on a listing
-- row, a locked line and a tooltip line before these hooks run, and writes that English again on every refresh.
-- Never touched: leader / member names, the listing comment, level numbers.
-- Not here: blizzard_lfgvanilla_minimap.lua's listing tooltip (LFGMinimapMixin:OnEnter, :72–118). The toc lists no
-- such file and no XML makes a frame with that mixin (blizzard_groupfinder_vanillastyle.toc:9–31), so the client
-- never runs it. The button by the minimap is the queue status eye, UI/QueueStatus's.
-- It is set up only where LFGWhoListFrame exists (WhoList.lua|xml, toc:28–29), so a client without it is left
-- untouched.
local _, WFJ = ...
local GroupFinder = {}
WFJ.GroupFinder = GroupFinder

local SURFACE = "groupfinder"
GroupFinder.SURFACE = SURFACE
local Compat = WFJ.Compat
local ADDON = "Blizzard_GroupFinder_VanillaStyle"

local LISTING, BROWSE, TIP = "LFGListingFrame", "LFGBrowseFrame", "LFGBrowseSearchEntryTooltip"

GroupFinder.NEVER_TOUCH = { "LFGListingComment.EditBox", TIP .. ".Leader.Name", TIP .. ".Comment" }

-- The table families a widget may show before its text is read as a game name.
local CATEGORY_FAMILY = { "LfgCategory" }
local ACTIVITY_FAMILIES = { "LfgActivityGroup", "LfgActivity" }

-- Static and single-writer labels: record key → { candidate, the keys it may show }.
local LABELS = {
  tab1 = { "LFGParentFrame.Tab1", { "LFG_LIST_TAB_1", "LFG_LIST_EDIT" } },
  tab2 = { "LFGParentFrame.Tab2", { "LFG_LIST_TAB_2" } }, tab3 = { "LFGParentFrame.Tab3", { "LFG_LIST_TAB_3" } },
  listingTitle = { LISTING .. ".TitleContainer.TitleText", { "LFG_TITLE" } },
  browseTitle = { BROWSE .. ".TitleContainer.TitleText", { "LFG_TITLE" } },
  -- the who list panel's own title, written once at its load (mainline/wholist.lua:201–203)
  whoTitle = { "LFGWhoListFrame.TitleContainer.TitleText", { "LFG_TITLE" } },
  -- BACK is asked for by key: its English is also a cloak's slot name, which an open match would pick
  back = { LISTING .. ".BackButton", { "LFG_LIST_UNLIST", "BACK" } },
  post = { LISTING .. ".PostButton", { "LFG_POST_GROUP_UPDATE", "LFG_POST_GROUP_PARTY", "LFG_POST_GROUP_SOLO" } },
  rolePoll = { LISTING .. ".GroupRoleButtons.RolePollButton", { "ROLE_POLL" } },
  lockedError = { LISTING .. ".LockedView.ErrorText",
    { "LFG_LIST_ONLY_LEADER_CREATE", "LFG_LIST_ONLY_LEADER_UPDATE" } },
  lockedActivity = { LISTING .. ".LockedView.ActivityText", { "LFG_LIST_MY_ACTIVITY_LIST_HEADER" } },
  instructions = { "LFGListingComment.EditBox.Instructions",
    { "DESCRIPTION_OF_YOUR_GROUP", "LFG_AUTHENTICATOR_DESCRIPTION_BOX" } },
  noResults = { BROWSE .. ".NoResultsFound", { "LFG_LIST_NO_RESULTS_FOUND", "LFG_LIST_SEARCH_FAILED" } },
  searching = { BROWSE .. ".SearchingSpinner.Label", { "SEARCHING" } },
  sendMessage = { BROWSE .. ".SendMessageButton", { "SEND_MESSAGE" } },
  groupInvite = { BROWSE .. ".GroupInviteButton", { "GROUP_INVITE" } },
  tipDelisted = { TIP .. ".Delisted", { "LFG_LIST_ENTRY_DELISTED" } },
  tipNewPlayer = { TIP .. ".NewPlayerFriendlyText", { "LFG_LIST_NEW_PLAYER_FRIENDLY_HEADER" } },
  tipBosses = { TIP .. ".CompletedEncounterHeader", { "LFG_LIST_BOSSES_DEFEATED" } },
  tipMembers = { TIP .. ".MemberCount", { "LFG_LIST_TOOLTIP_MEMBERS", "LFG_LIST_TOOLTIP_MEMBERS_SIMPLE" } },
  voiceLabel = { LISTING .. ".ActivityView.VoiceChatLabel", { "VOICE_CHAT" } },
  levelRanges = { LISTING .. ".ActivityView.LevelRangesCheckbox.Text", { "LFG_LIST_IGNORE_SUGGESTED_LEVEL" } },
  tipVoice = { TIP .. ".VoiceChat", { "VOICE_CHAT_MODE_FORMAT" } },
}
local ORDER = {}
for key in pairs(LABELS) do ORDER[#ORDER + 1] = key end
table.sort(ORDER)

-- Dropdown buttons: record key → { candidate, the keys its own text may show[, the table families it may show[,
-- true when a text that is neither is a game name] ] }.
local DROPDOWNS = {
  category = { BROWSE .. ".CategoryDropdown", { "CATEGORY", "LFG_TYPE_NONE", "LFG_SELF_LISTING" }, CATEGORY_FAMILY },
  activity = { BROWSE .. ".ActivityDropdown", { "LFGBROWSE_ACTIVITY_HEADER_DEFAULT", "LFGBROWSE_ACTIVITY_HEADER" },
    { "LfgActivity" }, true },
  role = { LISTING .. ".GroupRoleButtons.RoleDropdown", { "TANK", "HEALER", "DAMAGER" } },
  -- the listing's playstyle: the chosen one, or the required prompt in a colour code while none is chosen
  -- [verified: forever-ui-1.60.1.70425 blizzard_lfgvanilla_listing.lua:921–949]
  playstyle = { LISTING .. ".ActivityView.PlayStyleDropdown", { "GROUP_FINDER_GENERAL_PLAYSTYLE1",
    "GROUP_FINDER_GENERAL_PLAYSTYLE2", "GROUP_FINDER_GENERAL_PLAYSTYLE3", "GROUP_FINDER_GENERAL_PLAYSTYLE4",
    "GROUP_FINDER_PLAYSTYLE_REQUIRED" } },
  voice = { LISTING .. ".ActivityView.VoiceChatDropdown", { "VOICE_CHAT_MODE_NONE", "VOICE_CHAT_MODE_LEGACY",
    "VOICE_CHAT_MODE_DISCORD", "VOICE_CHAT_MODE_CUSTOM" } },
}

local ROLE_TIP = { only = { "ROLE_DESCRIPTION_TANK", "ROLE_DESCRIPTION_HEALER", "ROLE_DESCRIPTION_DAMAGER",
  "CLASS_ROLE_NOT_RECOMMENDED" } }
-- Help-tooltip owners: candidate → the keys its tooltip may show.
local TOOLTIPS = {
  { "LFGParentFrame.ListingTab", { only = { "LFG_LIST_TAB_1" } } },
  { "LFGParentFrame.BrowsingTab", { only = { "LFG_LIST_TAB_2" } } },
  { "LFGParentFrame.WhoListingTab", { only = { "LFG_LIST_TAB_3" } } },
  { LISTING .. ".SoloRoleButtons.Tank", ROLE_TIP }, { LISTING .. ".SoloRoleButtons.Healer", ROLE_TIP },
  { LISTING .. ".SoloRoleButtons.DPS", ROLE_TIP }, { LISTING .. ".GroupRoleButtons.RoleIcon", ROLE_TIP },
  { LISTING .. ".GroupRoleButtons.RolePollButton", { only = { "ERR_LFG_ROLE_CHECK_ONLY_LEADER" } } },
  { LISTING .. ".GroupRoleButtons.RoleDropdown", { only = { "SELECT_YOUR_ROLE" } } },
  { LISTING .. ".NewPlayerFriendlyButton", { only = { "LFG_LIST_NEW_PLAYER_FRIENDLY_TOOLTIP" } } },
  -- the button's errorText, every value LFGListingMixin:UpdatePostButtonEnableState gives it
  -- [verified: blizzard_lfgvanilla_listing.lua:477-530; .xml:329-331]
  { LISTING .. ".PostButton",
    { only = { "LFG_LIST_TOO_MANY_FOR_ACTIVITY", "LFG_LIST_TOO_MANY_ACTIVITIES_SELECTED", "LFG_LIST_ONLY_LEADER_UPDATE",
      "LFG_LIST_ONLY_LEADER_CREATE", "GROUP_FINDER_PLAYSTYLE_REQUIRED" } } },
  { BROWSE .. ".RefreshButton", { only = { "LFG_LIST_SEARCH_AGAIN" } } },
}

local CANDIDATES = {
  parent = { "LFGParentFrame" }, whoList = { "LFGWhoListFrame" }, listing = { LISTING }, browse = { BROWSE },
  activityView = { LISTING .. ".ActivityView" }, lockedView = { LISTING .. ".LockedView" }, tip = { TIP },
  results = { BROWSE .. ".ScrollBox" }, scrollUtil = { "ScrollUtil" },
  postText = { "LFGListingPostButton_UpdateText" }, backText = { "LFGListingBackButton_UpdateText" },
  lockedRefresh = { "LFGListingLockedView_RefreshContent" }, entryUpdate = { "LFGBrowseSearchEntry_Update" },
  tipUpdate = { "LFGBrowseSearchEntryTooltip_UpdateAndShow" },
  activityButton = { "LFGListingActivityView_InitActivityButton" }, -- listing.lua:989–1029
  activityGroupButton = { "LFGListingActivityView_InitActivityGroupButton" }, -- listing.lua:946–988
  categoryButton = { "LFGListingCategorySelection_AddButton" }, -- listing.lua:702–726
}

local ROW_ACTIVITY_KEYS = { "LFG_SELF_LISTING", "LFGBROWSE_ACTIVITY_COUNT", "LFGBROWSE_ACTIVITY_MATCHING_COUNT" }
local ROW_ROLES = { only = { "LFG_TOOLTIP_ROLES" } }
local ROW_CATEGORY = { only = { "LFG_LIST_CATEGORY_SOLO_PLAYERS", "LFG_LIST_CATEGORY_GROUPS" } }
-- a result's playstyle line, GetGeneralPlaystyleString (blizzard_lfgutil/mainline/lfgutil.lua:315–326;
-- blizzard_lfgvanilla_browse.lua:466–467)
local ROW_PLAYSTYLE = { only = { "GROUP_FINDER_GENERAL_PLAYSTYLE1", "GROUP_FINDER_GENERAL_PLAYSTYLE2",
  "GROUP_FINDER_GENERAL_PLAYSTYLE3", "GROUP_FINDER_GENERAL_PLAYSTYLE4" } }
local ROW_DELIST = { only = { "LFG_LIST_UNLIST" } }

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  for key, l in pairs(LABELS) do Compat.declare(SURFACE, "label." .. key, { l[1] }) end
  for key, d in pairs(DROPDOWNS) do Compat.declare(SURFACE, "dropdown." .. key, { d[1] }) end
  for i, t in ipairs(TOOLTIPS) do Compat.declare(SURFACE, "tip." .. i, { t[1] }) end
end

-- Shows the named labels (all of them when none is named). → the number of dictionary words found.
function GroupFinder.show(...)
  local keys = select("#", ...) > 0 and { ... } or ORDER
  local items = {}
  for _, key in ipairs(keys) do
    items[#items + 1] = { key, get("label." .. key), { only = LABELS[key][2] } }
  end
  return WFJ.Labels.showAll(SURFACE, items)
end

-- A widget that holds a word of the client's tables or a game name, maybe after the indent the client puts before
-- an activity under its group (LFG_LIST_INDENT, "  %s"): the word in its Japanese whatever the names choice is,
-- else the name in its Japanese while names are on, the indent kept byte for byte. One record key serves both, so
-- a pooled widget that held a word and now holds a name never keeps the word's record. → 1 | 0
local function wordOrName(surface, recKey, widget, opts, refit)
  local n = WFJ.Labels.show(surface, recKey, widget, refit, opts)
  if n > 0 then return n end
  local fs = WFJ.Labels.widget(widget)
  local text = fs and fs:GetText() or nil
  if WFJ.SurfaceState.secret(text) or type(text) ~= "string" then return 0 end
  local indent = text:match("^ +")
  if indent then return WFJ.NameLabels.after(surface, recKey, widget, indent, nil, refit) end
  return WFJ.NameLabels.show(surface, recKey, widget, nil, refit)
end

-- A dropdown button's own text: one of its keys, a word of its table families, or the one activity chosen. → 1 | 0
local function showDropdown(key)
  local dropdown = get("dropdown." .. key)
  if type(dropdown) ~= "table" then return 0 end
  local d = DROPDOWNS[key]
  local opts = d[3] and WFJ.Labels.familiesWith(d[2], unpack(d[3])) or { only = d[2] }
  if d[4] then return wordOrName(SURFACE, "dropdown." .. key, dropdown.Text, opts) end
  return WFJ.Labels.show(SURFACE, "dropdown." .. key, dropdown.Text, nil, opts)
end
GroupFinder.showDropdown = showDropdown

-- The category menu's entries (MENU_LFG_BROWSE_CATEGORY's `show`, after the tag's own keys found nothing): a
-- category's name. → 1 | 0
function GroupFinder.showCategoryEntry(surface, recKey, fs)
  return WFJ.Labels.show(surface, recKey, fs, nil, WFJ.Labels.families(unpack(CATEGORY_FAMILY)))
end

-- The activity filter menu's entries (MENU_LFG_BROWSE_ACTIVITY's `show`): a group's name, and an activity's name,
-- indented under its group in a menu with one group and plain in a group's submenu (browse.lua:1148–1178). → 1 | 0
function GroupFinder.showActivityEntry(surface, recKey, fs)
  return wordOrName(surface, recKey, fs, WFJ.Labels.families(unpack(ACTIVITY_FAMILIES)))
end

local rowKey = WFJ.Labels.keyer("row.") -- a pooled result row's record key (follows the widget, never an index)

-- One pooled browse row: a result entry or a category divider. Called from the ScrollBox's initialized-frame
-- callback ((owner, frame, elementData) for a new row, (frame, elementData) for the iterateExisting pass) and
-- after LFGBrowseSearchEntry_Update(row). Returns nothing: ForEachFrame stops at the first truthy return.
function GroupFinder.onRow(a, b)
  local row = a
  if a == GroupFinder then row = b end
  if type(row) ~= "table" then return end
  local show = WFJ.Labels.show
  if type(row.ActivityName) == "table" then
    wordOrName(SURFACE, rowKey(row.ActivityName), row.ActivityName,
      WFJ.Labels.familiesWith(ROW_ACTIVITY_KEYS, "LfgActivity"))
  end
  if type(row.CategoryLabel) == "table" then
    show(SURFACE, rowKey(row.CategoryLabel), row.CategoryLabel, nil, ROW_CATEGORY)
  end
  if type(row.PlaystyleLabel) == "table" then
    show(SURFACE, rowKey(row.PlaystyleLabel), row.PlaystyleLabel, nil, ROW_PLAYSTYLE)
  end
  local display = row.DataDisplay
  if type(display) == "table" then
    local roles = type(display.Solo) == "table" and display.Solo.RolesText or nil
    if type(roles) == "table" then show(SURFACE, rowKey(roles), roles, nil, ROW_ROLES) end
    if type(display.DelistButton) == "table" then WFJ.HelpTooltip.register(display.DelistButton, ROW_DELIST) end
  end
end

-- An activity row's lockout warning icon: its OnEnter adds BOSSES_KILLED ("%d/%d Bosses Defeated", the
-- counts kept) for a saved instance (mainline/blizzard_lfgvanilla_listing.xml:222–229; the icon is shown by
-- LFGListingActivityView_InitActivityButton, listing.lua:1013–1029). Each row's icon is registered as its owner.
local LOCK_TIP = { only = { "BOSSES_KILLED" } }
local nameKey = WFJ.Labels.keyer("name.") -- a pooled row's name record

-- A listing row's name: a word of `family`, else a game name; the name button is re-sized to the text shown, as
-- the client sized it to the English (listing.lua:1096–1099, 1118–1129).
local function showName(button, family)
  local nb = type(button) == "table" and button.NameButton or nil
  local name = type(nb) == "table" and nb.Name or nil
  if type(name) ~= "table" then return 0 end
  local function refit()
    if type(nb.SetWidth) == "function" and type(name.GetWidth) == "function" then
      if type(name.SetWidth) == "function" then name:SetWidth(0) end
      nb:SetWidth(name:GetWidth())
    end
  end
  local n = wordOrName(SURFACE, nameKey(name), name, WFJ.Labels.families(family), refit)
  if n > 0 then refit() end
  return n
end

function GroupFinder.onActivityButton(button)
  local icon = type(button) == "table" and button.InstanceLockWarningIcon or nil
  if type(icon) == "table" then WFJ.HelpTooltip.register(icon, LOCK_TIP) end
  showName(button, "LfgActivity")
  WFJ.Render.updateBanner(SURFACE)
end

-- An activity group row (hooksecurefunc target, LFGListingActivityView_InitActivityGroupButton).
function GroupFinder.onActivityGroupButton(button)
  showName(button, "LfgActivityGroup")
  WFJ.Render.updateBanner(SURFACE)
end

local categoryKey = WFJ.Labels.keyer("category.")
-- A category button (hooksecurefunc target, LFGListingCategorySelection_AddButton(self, index, categoryID)).
function GroupFinder.onCategoryButton(selection, index)
  local buttons = type(selection) == "table" and selection.CategoryButtons or nil
  local button = type(buttons) == "table" and buttons[index] or nil
  if type(button) ~= "table" then return end
  WFJ.Labels.show(SURFACE, categoryKey(button), button, nil, WFJ.Labels.families("LfgCategory"))
  WFJ.Render.updateBanner(SURFACE)
end

-- hooksecurefunc targets.
function GroupFinder.onTabs() return GroupFinder.show("tab1") end
function GroupFinder.onPostText() return GroupFinder.show("post") end
function GroupFinder.onBackText() return GroupFinder.show("back") end

local lockedKey = WFJ.Labels.keyer("locked.")
local COUNT_KEYS = { "LFGBROWSE_ACTIVITY_COUNT" }

-- A locked line that is a group and its count ("Dungeons |cffffffff(3 activities)|r", listing.lua:1262, 1293): the
-- group's table word and the count line, the colour kept. A group that is no table word is a continent: a game
-- name, in its Japanese while names are. → 1 | 0
local function showGroupCount(recKey, fs)
  local text = fs:GetText()
  if WFJ.SurfaceState.secret(text) or type(text) ~= "string" then return 0 end
  local group, open, count, close = text:match("^(.-)( |c%x%x%x%x%x%x%x%x%()(.-)(%)|r)$")
  if not group then return 0 end
  local countPart = WFJ.Labels.part(count, COUNT_KEYS)
  if group == "" or group:find("|", 1, true) or not countPart then return 0 end
  local groupPart = WFJ.Labels.part(group, WFJ.Labels.families("LfgActivityGroup").only) or { name = group }
  return WFJ.Labels.showArgs(SURFACE, recKey, fs, countPart.key,
    { form = "seq", parts = { groupPart, open, countPart, close } })
end

-- The hover of a collapsed locked line (HelpTooltip's `show` for its owner): the group, then each activity after
-- its indent, in one line of the tooltip. A table word shows its Japanese whatever the names choice is. The names
-- show in Japanese only when every one of them has a line, so the list is never half in each language. → 1 | 0
local function showListed(surface, recKey, fs, refit)
  local text = fs:GetText()
  if WFJ.SurfaceState.secret(text) or type(text) ~= "string" or text:find("|", 1, true) then return 0 end
  local only = WFJ.Labels.families(unpack(ACTIVITY_FAMILIES)).only
  local parts, names, key, allNamed = {}, {}, nil, true
  for line in (text .. "\n"):gmatch("(.-)\n") do
    local indent, body = line:match("^( *)(.+)$")
    if not body then return 0 end
    if #parts > 0 then parts[#parts + 1] = "\n" end
    if indent ~= "" then parts[#parts + 1] = indent end
    local part = WFJ.Labels.part(body, only)
    if part then
      key = key or part.key
    else
      part = { name = body }
      names[#names + 1] = #parts + 1
      if not WFJ.Names.value(body) then allNamed = false end
    end
    parts[#parts + 1] = part
  end
  if key then
    if not allNamed then
      for _, i in ipairs(names) do parts[i] = parts[i].name end
    end
    return WFJ.Labels.showArgs(surface, recKey, fs, key, { form = "seq", parts = parts }, refit)
  end
  -- No table word: the group is a continent and every line a name. The record is the first name's, with the
  -- other names in Japanese around it; it shows only while names are Japanese.
  if not allNamed or not WFJ.State.names then return 0 end
  local first = names[1]
  local out = {}
  for i, part in ipairs(parts) do
    out[i] = i == first and "" or (type(part) == "table" and WFJ.Names.value(part.name) or part)
  end
  local head, tail = table.concat(out, "", 1, first - 1), table.concat(out, "", first + 1)
  WFJ.Render.show(surface, recKey, fs, text, "ui", "name", parts[first].name,
    { head = head ~= "" and head or nil, tail = tail ~= "" and tail or nil, refit = refit })
  return 1
end
local LISTED_TIP = { only = {}, show = showListed }

-- The lines of the group's own listing, one pooled frame each.
local function showLockedLines()
  local view = get("lockedView")
  local pool = type(view) == "table" and view.framePool or nil
  if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then return 0 end
  local n = 0
  for frame in pool:EnumerateActive() do
    local fs = type(frame) == "table" and frame.Text or nil
    if type(fs) == "table" and type(fs.GetText) == "function" then
      WFJ.HelpTooltip.register(frame, LISTED_TIP)
      local function refit()
        if type(frame.SetSize) ~= "function" or type(fs.GetWidth) ~= "function" then return end
        if type(fs.SetSize) == "function" then fs:SetSize(0, 0) end
        frame:SetSize(fs:GetWidth(), type(fs.GetHeight) == "function" and fs:GetHeight() or 0)
      end
      local key = lockedKey(fs)
      local shown = wordOrName(SURFACE, key, fs, WFJ.Labels.families(unpack(ACTIVITY_FAMILIES)), refit)
      if shown == 0 then shown = showGroupCount(key, fs) end
      if shown > 0 then refit() end
      n = n + shown
    end
  end
  return n
end

function GroupFinder.onLocked()
  return GroupFinder.show("lockedError", "lockedActivity") + showLockedLines()
end
function GroupFinder.onActivityView() return GroupFinder.show("instructions") end
function GroupFinder.onResults() return GroupFinder.show("noResults") end
function GroupFinder.onButtons() return GroupFinder.show("groupInvite", "sendMessage") end
-- The client sizes the tooltip from its English lines before this hook runs, and the voice line and the activity
-- lines do not wrap (blizzard_lfgvanilla_browse.lua:707, 748, 769, 794, 840; browse.xml:359, 406), so a wider
-- Japanese line would be cut short or run past the edge.
-- `method`: the voice line is as wide as its text (GetStringWidth); an activity line is held between the tooltip's
-- edges, so only its text's own width says what it needs (GetUnboundedStringWidth).
local function fitTipLine(fs, method)
  if type(fs) ~= "table" or type(fs.GetParent) ~= "function" or type(fs[method]) ~= "function" then return end
  if type(fs.IsShown) == "function" and not fs:IsShown() then return end
  local tip = fs:GetParent()
  if type(tip) ~= "table" or type(tip.GetWidth) ~= "function" or type(tip.SetWidth) ~= "function" then return end
  local need = (fs[method](fs) or 0) + 22
  if need > (tip:GetWidth() or 0) then tip:SetWidth(need) end
end

local tipKey = WFJ.Labels.keyer("tip.")

-- The result tooltip's pooled lines: its activities and groups, and the bosses the group has defeated (names).
local function showTipLines()
  local tip = get("tip")
  if type(tip) ~= "table" then return 0 end
  local n = 0
  local function each(pool, showLine)
    if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then return end
    for fs in pool:EnumerateActive() do
      if type(fs) == "table" and type(fs.GetText) == "function" then
        local shown = showLine(tipKey(fs), fs)
        if shown > 0 then fitTipLine(fs, "GetUnboundedStringWidth") end
        n = n + shown
      end
    end
  end
  local activity = WFJ.Labels.families(unpack(ACTIVITY_FAMILIES))
  each(tip.activityPool, function(key, fs) return wordOrName(SURFACE, key, fs, activity) end)
  each(tip.completedEncounterPool, function(key, fs) return WFJ.NameLabels.show(SURFACE, key, fs) end)
  return n
end

function GroupFinder.onTooltip()
  local n = GroupFinder.show("tipDelisted", "tipNewPlayer", "tipBosses", "tipMembers", "tipVoice")
  fitTipLine(get("label.tipVoice"), "GetStringWidth")
  return n + showTipLines()
end

local hooked = false

local function hookMethod(frame, method, fn)
  if type(frame) == "table" and type(frame[method]) == "function" then hooksecurefunc(frame, method, fn) end
end

local function hookGlobal(key, name, fn)
  if type(get(key)) == "function" then hooksecurefunc(name, fn) end
end

-- Blizzard_GroupFinder_VanillaStyle's part: runs once the addon is loaded (now, or on its ADDON_LOADED).
-- → true when set up.
function GroupFinder.setup()
  declare() -- its frames exist only now: forget what Compat memoized before
  local parent, browse = get("parent"), get("browse")
  if type(parent) ~= "table" or type(browse) ~= "table" or type(get("listing")) ~= "table"
      or type(get("whoList")) ~= "table" then
    return false -- not the camelot group finder
  end
  WFJ.Labels.forbidNames(GroupFinder.NEVER_TOUCH) -- its widgets exist only now (Main's registration found none)
  for i, t in ipairs(TOOLTIPS) do
    local owner = get("tip." .. i)
    if type(owner) == "table" then WFJ.HelpTooltip.register(owner, t[2]) end
  end
  GroupFinder.show()
  if hooked then return false end
  hooked = true
  hookMethod(parent, "UpdateTabs", GroupFinder.onTabs)
  hookMethod(browse, "UpdateResults", GroupFinder.onResults)
  hookMethod(browse, "UpdateButtonState", GroupFinder.onButtons)
  hookGlobal("postText", "LFGListingPostButton_UpdateText", GroupFinder.onPostText)
  hookGlobal("backText", "LFGListingBackButton_UpdateText", GroupFinder.onBackText)
  hookGlobal("lockedRefresh", "LFGListingLockedView_RefreshContent", GroupFinder.onLocked)
  hookGlobal("entryUpdate", "LFGBrowseSearchEntry_Update", GroupFinder.onRow)
  hookGlobal("tipUpdate", "LFGBrowseSearchEntryTooltip_UpdateAndShow", GroupFinder.onTooltip)
  hookGlobal("activityButton", "LFGListingActivityView_InitActivityButton", GroupFinder.onActivityButton)
  hookGlobal("activityGroupButton", "LFGListingActivityView_InitActivityGroupButton", GroupFinder.onActivityGroupButton)
  hookGlobal("categoryButton", "LFGListingCategorySelection_AddButton", GroupFinder.onCategoryButton)
  local view = get("activityView")
  if type(view) == "table" and type(view.HookScript) == "function" then
    view:HookScript("OnShow", GroupFinder.onActivityView)
  end
  for key in pairs(DROPDOWNS) do
    local dropdown = get("dropdown." .. key)
    if type(dropdown) == "table" and type(dropdown.Text) == "table" then
      hookMethod(dropdown, "UpdateText", function() showDropdown(key) end)
      showDropdown(key)
    end
  end
  local results, util = get("results"), get("scrollUtil")
  if type(results) == "table" and type(util) == "table" and type(util.AddInitializedFrameCallback) == "function" then
    util.AddInitializedFrameCallback(results, GroupFinder.onRow, GroupFinder, true)
  end
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init.
function GroupFinder.init()
  declare()
  return WFJ.LoadOnDemand.when(ADDON, GroupFinder.setup)
end
