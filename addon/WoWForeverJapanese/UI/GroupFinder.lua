-- UI/GroupFinder.lua: the Looking For Group window on Forever (surface "groupfinder", area "ui", ADR-016).
-- Blizzard_GroupFinder_VanillaStyle is load-on-demand (its toc: LoadOnDemand 1, AllowLoadGameType classic, camelot);
-- SetLookingForGroupUIAvailable loads it (blizzard_lfgutil/camelot/lfgutil.lua:1–7), and ToggleGroupFinderFrame
-- (blizzard_game/shared/game.lua:73–88), its TOGGLEGROUPFINDER binding (bindings.xml:2–4), the who binding
-- (blizzard_framexml/bindings_camelot.xml:1256–1258) and the queue-status eye (blizzard_queuestatusframe/camelot/
-- queuestatusframeoverrides.lua:5–10) open it. LFGParentFrame holds three panels: LFGListingFrame (Create Listing),
-- LFGBrowseFrame (Group Browser) and LFGWhoListFrame (Who List: UI/Friends.lua's, not touched here).
-- LFGVANILLA_SETTING_MODERN_STYLE is true (mainline/lfgvanilla_constants.lua:6): the bottom tabs are hidden and the
-- side tabs carry the tab names as tooltips (blizzard_lfgvanilla_parentframe.lua:77–85).
-- Static labels (XML text= or an OnLoad write; each restricted to its own keys):
--   the two panels' TitleContainer.TitleText, written directly with SetText(LFG_TITLE), never SetTitle
--     (blizzard_lfgvanilla_listing.lua:46, blizzard_lfgvanilla_browse.lua:131);
--   LFGListingFrame: GroupRoleButtons.RolePollButton ROLE_POLL (mainline/blizzard_lfgvanilla_listing.xml:389),
--     LockedView.ActivityText LFG_LIST_MY_ACTIVITY_LIST_HEADER (xml:598), ActivityView.VoiceChatLabel VOICE_CHAT
--     (xml:554);
--   LFGBrowseFrame: SearchingSpinner.Label SEARCHING (mainline/blizzard_lfgvanilla_browse.xml:509),
--     SendMessageButton SEND_MESSAGE (xml:525);
--   LFGBrowseSearchEntryTooltip: Delisted, NewPlayerFriendlyText, CompletedEncounterHeader (xml:326–360).
-- Dynamic, each post-hooked (a frame's own method, or a global looked up by name at call time):
--   LFGParentFrame:UpdateTabs → Tab1 LFG_LIST_TAB_1 / LFG_LIST_EDIT (parentframe.lua:87–92);
--   LFGListingPostButton_UpdateText → PostButton List Self / List Group / Update (listing.lua:610–618);
--   LFGListingBackButton_UpdateText → BackButton LFG_LIST_UNLIST; its other text is BACK, whose English "Back" the
--     dictionary gives to INVTYPE_CLOAK, so it stays English (listing.lua:643–649);
--   LFGListingLockedView_RefreshContent → LockedView.ErrorText (listing.lua:1089–1097);
--   LFGListingFrame.ActivityView OnShow (HookScript: the XML binds the global by reference) → the comment box's
--     Instructions FontString, DESCRIPTION_OF_YOUR_GROUP / LFG_AUTHENTICATOR_DESCRIPTION_BOX (listing.lua:822, 838).
--     The EditBox's own text is never touched;
--   LFGBrowseFrame:UpdateResults → NoResultsFound (browse.lua:189); :UpdateButtonState → GroupInviteButton (:305);
--   LFGBrowseSearchEntry_Update (global, browse.lua:351–357, and on the row's events) and the ScrollBox's
--     initialized-frame callback → a result row's ActivityName: LFG_SELF_LISTING or "%d activities"
--     (browse.lua:410–419; a single activity's name is client-table text, never matched), its
--     DataDisplay.Solo.RolesText LFG_TOOLTIP_ROLES (xml:23), and a divider row's CategoryLabel (browse.lua:73–79);
--   LFGBrowseSearchEntryTooltip_UpdateAndShow → MemberCount (browse.lua:667–672) and VoiceChat, VOICE_CHAT_MODE_FORMAT
--     around the listing's voice mode, an entry (browse.lua:674–682, blizzard_lfgvanilla_voicechat.lua). The
--     tooltip's width is taken from the English line before the hook runs (:680, 813); it is not measured again;
--   the three dropdown buttons' own text, after DropdownTextMixin:UpdateText (blizzard_menu/menutemplates.lua:
--     712–713): the category (CATEGORY default, LFG_TYPE_NONE, LFG_SELF_LISTING; a category's name is client-table
--     text), the activity filter (LFGBROWSE_ACTIVITY_HEADER_DEFAULT / LFGBROWSE_ACTIVITY_HEADER), the group role
--     (TANK / HEALER / DAMAGER, listing.lua:522–524), the voice chat mode (its default text and the chosen radio,
--     VOICE_CHAT_MODE_NONE / _LEGACY / _DISCORD / _CUSTOM, listing.lua:48–69). The popup entries themselves are
--     UI/Menus'.
-- Help tooltips (GameTooltip:SetText / AddLine on the frame): the side tabs' tooltipText (SidePanelTabButtonMixin:
--   OnEnter, blizzard_sharedxml/mainline/shareduipaneltemplates.lua:406–414), the role buttons'
--   ROLE_DESCRIPTION_<role> + CLASS_ROLE_NOT_RECOMMENDED (listing.xml:22–31), the role-poll button, the role
--   dropdown SELECT_YOUR_ROLE, the new-player-friendly button, the post button's error text, the refresh button
--   LFG_LIST_SEARCH_AGAIN
--   (browse.xml:474–475). Each owner is restricted to the keys it shows.
-- The client-table words of the listing (ADR-042): a category button's name (LfgCategory:
-- LFGListingCategorySelection_AddButton → button:SetText(categoryInfo.name), listing.lua:702–718), an activity
-- group row's and an activity row's NameButton.Name (LfgActivityGroup / LfgActivity: LFGListingActivityView_
-- InitActivityGroupButton / _InitActivityButton, :946–1003, the name button re-sized to the Japanese) and a browse
-- row's single activity name (LfgActivity: "Custom"). A dungeon, raid or zone name is no row of those families and
-- stays English.
-- Never touched: leader / member names, dungeon / raid / zone names, the listing comment, level numbers.
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

-- Static and single-writer labels: record key → { candidate, the keys it may show }.
local LABELS = {
  tab1 = { "LFGParentFrame.Tab1", { "LFG_LIST_TAB_1", "LFG_LIST_EDIT" } },
  tab2 = { "LFGParentFrame.Tab2", { "LFG_LIST_TAB_2" } }, tab3 = { "LFGParentFrame.Tab3", { "LFG_LIST_TAB_3" } },
  listingTitle = { LISTING .. ".TitleContainer.TitleText", { "LFG_TITLE" } },
  browseTitle = { BROWSE .. ".TitleContainer.TitleText", { "LFG_TITLE" } },
  back = { LISTING .. ".BackButton", { "LFG_LIST_UNLIST" } },
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
  tipVoice = { TIP .. ".VoiceChat", { "VOICE_CHAT_MODE_FORMAT" } },
}
local ORDER = {}
for key in pairs(LABELS) do ORDER[#ORDER + 1] = key end
table.sort(ORDER)

-- Dropdown buttons: record key → { candidate, the keys its own text may show }.
local DROPDOWNS = {
  category = { BROWSE .. ".CategoryDropdown", { "CATEGORY", "LFG_TYPE_NONE", "LFG_SELF_LISTING" } },
  activity = { BROWSE .. ".ActivityDropdown", { "LFGBROWSE_ACTIVITY_HEADER_DEFAULT", "LFGBROWSE_ACTIVITY_HEADER" } },
  role = { LISTING .. ".GroupRoleButtons.RoleDropdown", { "TANK", "HEALER", "DAMAGER" } },
  -- the listing's playstyle: the chosen one, or the required prompt in a colour code while none is chosen
  -- [verified: forever-ui-1.60.1.70170 blizzard_lfgvanilla_listing.lua:849–876]
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
  { LISTING .. ".PostButton",
    { only = { "LFG_LIST_TOO_MANY_FOR_ACTIVITY", "LFG_LIST_TOO_MANY_ACTIVITIES_SELECTED" } } },
  { BROWSE .. ".RefreshButton", { only = { "LFG_LIST_SEARCH_AGAIN" } } },
}

local CANDIDATES = {
  parent = { "LFGParentFrame" }, whoList = { "LFGWhoListFrame" }, listing = { LISTING }, browse = { BROWSE },
  activityView = { LISTING .. ".ActivityView" },
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
-- blizzard_lfgvanilla_browse.lua:465–466)
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

-- A dropdown button's own text, restricted to its keys (a category or activity name is never matched). → 1 | 0
local function showDropdown(key)
  local dropdown = get("dropdown." .. key)
  if type(dropdown) ~= "table" then return 0 end
  return WFJ.Labels.show(SURFACE, "dropdown." .. key, dropdown.Text, nil, { only = DROPDOWNS[key][2] })
end
GroupFinder.showDropdown = showDropdown

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
    show(SURFACE, rowKey(row.ActivityName), row.ActivityName, nil,
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

-- A listing row's name, restricted to `family`; the name button is re-sized to the text shown, as the client
-- sized it to the English (listing.lua:977–979, 1000–1001).
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
  local n = WFJ.Labels.show(SURFACE, nameKey(name), name, refit, WFJ.Labels.families(family))
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
function GroupFinder.onLocked() return GroupFinder.show("lockedError", "lockedActivity") end
function GroupFinder.onActivityView() return GroupFinder.show("instructions") end
function GroupFinder.onResults() return GroupFinder.show("noResults") end
function GroupFinder.onButtons() return GroupFinder.show("groupInvite", "sendMessage") end
-- The client sizes the tooltip from the English voice line before this hook runs, and that line does not wrap
-- (blizzard_lfgvanilla_browse.lua:680, 813; browse.xml:406), so a wider Japanese line would be cut short.
local function fitVoiceLine()
  local fs = get("label.tipVoice")
  if type(fs) ~= "table" or type(fs.GetParent) ~= "function" or type(fs.GetStringWidth) ~= "function" then return end
  if type(fs.IsShown) == "function" and not fs:IsShown() then return end
  local tip = fs:GetParent()
  if type(tip) ~= "table" or type(tip.GetWidth) ~= "function" or type(tip.SetWidth) ~= "function" then return end
  local need = (fs:GetStringWidth() or 0) + 22
  if need > (tip:GetWidth() or 0) then tip:SetWidth(need) end
end

function GroupFinder.onTooltip()
  local n = GroupFinder.show("tipDelisted", "tipNewPlayer", "tipBosses", "tipMembers", "tipVoice")
  fitVoiceLine()
  return n
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
