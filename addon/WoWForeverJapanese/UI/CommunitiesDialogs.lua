-- UI/CommunitiesDialogs.lua: the Communities window's dialogs on Forever (surface "communities.dialogs", area "ui",
-- ADR-016): community settings (CommunitiesSettingsDialog), the channel create / edit dialog and the
-- notification settings (CommunitiesFrame.EditStreamDialog / .NotificationSettingsDialog), the invite-link manager
-- (CommunitiesTicketManagerDialog) and the icon picker (CommunitiesAvatarPickerDialog). Plumbing:
-- UI/CommunitiesKit. Every file:line is the camelot extract 1.60.1.69913, blizzard_communities/.
-- Static labels: communitiessettings.xml:11-289 (labels, check-box labels, the item-level placeholder, buttons) and
--   its finder dropdowns' labels (ClubFinderDropdownMixin:OnLoad, clubfinder.lua:18-21; LANGUAGE,
--   communitieslanguage.xml:17); communitiesstreams.xml:85-165, 181-269 (QuickJoinButton.Text is written by its
--   OnLoad, xml:252-254); communitiesticketmanagerdialog.xml:198-422; the picker's unnamed instructions
--   (communitiesavatarpickerdialog.xml:36, found by its text); the edit boxes' placeholders (InputScrollFrame_OnLoad
--   writes EditBox.Instructions, blizzard_sharedxml/shared/inputbox/inputboxtemplates.lua:82-95).
-- Writers: the settings dialog's OnShow (XML-bound, HookScript) → DialogLabel (communitiessettings.lua:50-55);
--   SetClubId → the description placeholder (lua:104); HideOrShowCommunityFinderOptions → ClubFinderPostingBannedError
--   (lua:326); EditStreamDialog:ShowCreateDialog / ShowEditDialog → TitleLabel (communitiesstreams.lua:166-194);
--   the ticket manager's OnShow → DialogLabel "Invite to <community>" (communitiesticketmanagerdialog.lua:260),
--   RefreshLink → UsesText / ExpiresText (lua:462-481); a ticket row's SetTicket (the ScrollBox initializer and
--   direct calls, lua:200-202, 351) → Uses / Expires; the dropdowns' selection text (Labels.dropdown).
-- Help tooltips: the settings Accept button's name-check errors (lua:350-367: the error text is the client's, kept
--   as written), the cross-faction toggle (owner its Label, lua:417-425).
-- Never touched: every edit box, a ticket's creator and link, the stream names in the notification list.
local _, WFJ = ...
local Kit = WFJ.CommunitiesKit
local Dialogs = {}
WFJ.CommunitiesDialogs = Dialogs

local SURFACE = "communities.dialogs"
Dialogs.SURFACE = SURFACE

local SD = "CommunitiesSettingsDialog"
local ES = "CommunitiesFrame.EditStreamDialog"
local NS = "CommunitiesFrame.NotificationSettingsDialog"
local TM = "CommunitiesTicketManagerDialog"

Dialogs.NEVER_TOUCH = { SD .. ".NameEdit", SD .. ".ShortNameEdit", SD .. ".Description.EditBox",
  SD .. ".MessageOfTheDay.EditBox", SD .. ".MinIlvlOnly.EditBox", ES .. ".NameEdit", ES .. ".Description.EditBox",
  TM .. ".LinkIDText" }

local k = Kit.new(SURFACE, {
  settings = { SD }, stream = { ES }, notifications = { NS }, tickets = { TM },
  ticketRows = { TM .. ".InviteManager.ScrollBox" }, ticketColumns = { TM .. ".InviteManager.ColumnDisplay" },
  picker = { "CommunitiesAvatarPickerDialog" },
})

local FOCUS = { "CLUB_FINDER_FOCUS_SOCIAL_LEVELING", "GUILD_INTEREST_DUNGEON", "GUILD_INTEREST_RAID", "PVP_ENABLED",
  "GUILD_INTEREST_RP", "CLUB_FINDER_ANY_FLAG", "CLUB_FINDER_MULTIPLE_CHECKED" }
local NEVER = { "COMMUNITIES_INVITE_MANAGER_EXPIRES_NEVER" }
local UNLIMITED = { "COMMUNITIES_INVITE_MANAGER_USES_UNLIMITED" }

-- Static labels: { recKey, candidate, child path, keys }.
local STATIC = {
  { "sd.name", "settings", "NameLabel", { "COMMUNITIES_SETTINGS_NAME_LABEL" } },
  { "sd.shortName", "settings", "ShortNameLabel", { "COMMUNITIES_SETTINGS_SHORT_NAME_LABEL" } },
  { "sd.description", "settings", "DescriptionLabel", { "COMMUNITIES_SETTINGS_DESCRIPTION_LABEL" } },
  { "sd.motd", "settings", "MessageOfTheDayLabel", { "COMMUNITIES_SETTINGS_MOTD_LABEL" } },
  { "sd.motdHint", "settings", "MessageOfTheDay.EditBox.Instructions",
    { "COMMUNITIES_SETTINGS_DIALOG_MOTD_INSTRUCTIONS" } },
  { "sd.avatar", "settings", "ChangeAvatarButton", { "COMMUNITIES_CREATE_DIALOG_ICON_SELECTION_BUTTON" } },
  { "sd.crossFaction", "settings", "CrossFactionToggle.Label", { "COMMUNITIES_EDIT_DIALOG_CROSS_FACTION" } },
  { "sd.list", "settings", "ShouldListClub.Label", { "CLUB_FINDER_LIST_COMMUNITY" } },
  { "sd.autoAccept", "settings", "AutoAcceptApplications.Label", { "CLUB_FINDER_COMMUNITY_AUTO_ACCEPT" } },
  { "sd.maxLevel", "settings", "MaxLevelOnly.Label", { "CLUB_FINDER_MAX_LEVEL_ONLY" } },
  { "sd.minIlvl", "settings", "MinIlvlOnly.Label", { "LFG_LIST_ITEM_LEVEL_REQ" } },
  { "sd.minIlvlHint", "settings", "MinIlvlOnly.EditBox.Text", { "STAT_AVERAGE_ITEM_LEVEL" } },
  { "sd.focus", "settings", "ClubFocusDropdown.Label", { "CLUB_FINDER_FOCUS" } },
  { "sd.lookingFor", "settings", "LookingForDropdown.Label", { "CLUB_FINDER_LOOKING_FOR" } },
  { "sd.language", "settings", "LanguageDropdown.Label", { "LANGUAGE" } },
  { "sd.delete", "settings", "Delete", { "DELETE" } }, { "sd.accept", "settings", "Accept", { "ACCEPT" } },
  { "sd.cancel", "settings", "Cancel", { "CANCEL" } },
  { "es.name", "stream", "NameLabel", { "COMMUNITIES_CHANNEL_NAME_LABEL" } },
  { "es.description", "stream", "DescriptionLabel", { "COMMUNITIES_CHANNEL_SUBJECT_LABEL" } },
  { "es.type", "stream", "TypeLabel", { "COMMUNITIES_CHANNEL_TYPE_LABEL" } },
  { "es.hint", "stream", "Description.EditBox.Instructions", { "COMMUNITIES_CHANNEL_DESCRIPTION_INSTRUCTIONS" } },
  { "es.accept", "stream", "Accept", { "ACCEPT" } }, { "es.delete", "stream", "Delete", { "DELETE" } },
  { "es.cancel", "stream", "Cancel", { "CANCEL" } },
  { "ns.title", "notifications", "TitleLabel", { "COMMUNITIES_NOTIFICATION_SETTINGS_DIALOG_LABEL" } },
  { "ns.settings", "notifications", "ScrollFrame.Child.SettingsLabel",
    { "COMMUNITIES_NOTIFICATION_SETTINGS_DIALOG_SETTINGS_LABEL" } },
  { "ns.quickJoin", "notifications", "ScrollFrame.Child.QuickJoinButton.Text",
    { "COMMUNITIES_NOTIFICATION_SETTINGS_DIALOG_QUICK_JOIN_LABEL" } },
  { "ns.none", "notifications", "ScrollFrame.Child.NoneButton", { "COMMUNITIES_NOTIFICATION_SETTINGS_NONE" } },
  { "ns.all", "notifications", "ScrollFrame.Child.AllButton", { "COMMUNITIES_NOTIFICATION_SETTINGS_ALL" } },
  { "tm.instructions", "tickets", "LinkInstructions", { "COMMUNITIES_INVITE_MANAGER_LINK_INSTRUCTIONS" } },
  { "tm.linkId", "tickets", "LinkIDLabel", { "COMMUNITIES_INVITE_MANAGER_LINK_ID_LABEL" } },
  { "tm.expires", "tickets", "ExpiresLabel", { "COMMUNITIES_INVITE_MANAGER_EXPIRES_LABEL" } },
  { "tm.uses", "tickets", "UsesLabel", { "COMMUNITIES_INVITE_MANAGER_USES_LABEL" } },
  { "tm.expand", "tickets", "ExpandLabel", { "COMMUNITIES_INVITE_MANAGER_EXPAND_LABEL" } },
  { "tm.newLink", "tickets", "NewLinkLabel", { "COMMUNITIES_INVITE_MANAGER_CREATE_NEW_LINK" } },
  { "tm.expiresAfter", "tickets", "ExpiresDropdownLabel", { "COMMUNITIES_INVITE_MANAGER_EXPIRES_AFTER_LABEL" } },
  { "tm.numUses", "tickets", "UsesDropdownLabel", { "COMMUNITIES_INVITE_MANAGER_NUMBERUSES_LABEL" } },
  { "tm.linkToChat", "tickets", "LinkToChat", { "COMMUNITIES_INVITE_MANAGER_LINK_TO_CHAT" } },
  { "tm.copy", "tickets", "Copy", { "COMMUNITIES_INVITE_MANAGER_COPY" } },
  { "tm.generate", "tickets", "GenerateLinkButton", { "COMMUNITIES_INVITE_MANAGER_GENERATE" } },
  { "tm.close", "tickets", "Close", { "CLOSE" } },
}

local function at(key, path) return Kit.child(k.get(key), path) end

function Dialogs.showStatic()
  local n = k.showUnder(STATIC)
  local picker = k.get("picker")
  local key = "COMMUNITIES_CREATE_DIALOG_AVATAR_PICKER_INSTRUCTIONS"
  return n + k.show("picker", WFJ.Labels.region(picker, key), { key })
end

-- hooksecurefunc / HookScript targets of the settings dialog (OnShow, SetClubId, HideOrShowCommunityFinderOptions).
function Dialogs.onSettings()
  return k.showList({
    { "sd.title", at("settings", "DialogLabel"),
      { "COMMUNITIES_SETTINGS_LABEL", "COMMUNITIES_SETTINGS_CHARACTER_LABEL" } },
    { "sd.descriptionHint", at("settings", "Description.EditBox.Instructions"),
      { "COMMUNITIES_CREATE_DIALOG_DESCRIPTION_INSTRUCTIONS",
        "COMMUNITIES_CREATE_DIALOG_DESCRIPTION_INSTRUCTIONS_BATTLE_NET" } },
    { "sd.banned", at("settings", "ClubFinderPostingBannedError"), { "CLUB_FINDER_BANNED_POSTING_WARNING" } },
  })
end

-- hooksecurefunc target (EditStreamDialog:ShowCreateDialog / ShowEditDialog).
function Dialogs.onStream()
  return k.showList({
    { "es.title", at("stream", "TitleLabel"), { "COMMUNITIES_CREATE_CHANNEL", "COMMUNITIES_EDIT_CHANNEL" } },
  })
end

-- The ticket manager's OnShow and RefreshLink.
function Dialogs.onTickets()
  return k.showList({
    { "tm.label", at("tickets", "DialogLabel"), { "COMMUNITIES_INVITE_MANAGER_LABEL" } },
    { "tm.usesText", at("tickets", "UsesText"), UNLIMITED },
    { "tm.expiresText", at("tickets", "ExpiresText"), NEVER },
  })
end

local rowKey = WFJ.Labels.keyer("ticket.") -- a pooled ticket row's record key

-- A ticket row after SetTicket (its creator and link are never ours).
function Dialogs.onTicketRow(row)
  if type(row) ~= "table" then return 0 end
  for _, field in ipairs({ "Creator", "Link" }) do
    if type(row[field]) == "table" then WFJ.Labels.forbid(row[field]) end
  end
  local id = rowKey(row)
  return k.showList({
    { id .. ".uses", row.Uses, UNLIMITED }, { id .. ".expires", row.Expires, NEVER },
    { id .. ".copy", row.CopyLinkButton, { "COMMUNITIES_INVITE_MANAGER_COPY_LINK_BUTTON" } },
  })
end

function Dialogs.watchTicketRow(row)
  k.after(row, "SetTicket", Dialogs.onTicketRow)
  Dialogs.onTicketRow(row)
end

local hooked = false

function Dialogs.setup()
  if not Kit.ready(k, Dialogs.NEVER_TOUCH) then return false end
  Dialogs.showStatic()
  if hooked then return false end
  hooked = true
  local sd, es, tm = k.get("settings"), k.get("stream"), k.get("tickets")
  k.script(sd, "OnShow", Dialogs.onSettings)
  k.after(sd, "SetClubId", Dialogs.onSettings)
  k.after(sd, "HideOrShowCommunityFinderOptions", Dialogs.onSettings)
  k.tooltip(Kit.child(sd, "Accept"), { "COMMUNITIES_CREATE_DIALOG_NAME_AND_SHORT_NAME_ERROR",
    "COMMUNITIES_CREATE_DIALOG_NAME_ERROR", "COMMUNITIES_CREATE_DIALOG_SHORT_NAME_ERROR" })
  k.tooltip(Kit.child(sd, "CrossFactionToggle.Label"), { "COMMUNITIES_SETTING_CROSS_FACTION_TOOLTIP",
    "COMMUNITIES_SETTING_CROSS_FACTION_TOOLTIP_ERROR" })
  k.dropdown("sd.focusDropdown", Kit.child(sd, "ClubFocusDropdown"), FOCUS)
  k.dropdown("sd.lookingForDropdown", Kit.child(sd, "LookingForDropdown"),
    { "CLUB_FINDER_MULTIPLE_ROLES", "CLUB_FINDER_ANY_FLAG" })
  k.after(es, "ShowCreateDialog", Dialogs.onStream)
  k.after(es, "ShowEditDialog", Dialogs.onStream)
  k.script(tm, "OnShow", Dialogs.onTickets)
  k.after(tm, "RefreshLink", Dialogs.onTickets)
  k.dropdown("tm.expiresDropdown", Kit.child(tm, "ExpiresDropdown"), NEVER)
  k.dropdown("tm.usesDropdown", Kit.child(tm, "UsesDropdown"),
    { "COMMUNITIES_INVITE_MANAGER_USES_UNLIMITED", "COMMUNITIES_INVITE_MANAGER_USES" })
  k.headers(k.get("ticketColumns"), { "COMMUNITIES_INVITE_MANAGER_COLUMN_TITLE_CREATOR",
    "COMMUNITIES_INVITE_MANAGER_COLUMN_TITLE_LINK", "COMMUNITIES_INVITE_MANAGER_COLUMN_TITLE_EXPIRES",
    "COMMUNITIES_INVITE_MANAGER_COLUMN_TITLE_USES" }, "column.")
  k.rows(k.get("ticketRows"), Dialogs.watchTicketRow)
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init.
function Dialogs.init() return Kit.init(k, Dialogs.setup) end
