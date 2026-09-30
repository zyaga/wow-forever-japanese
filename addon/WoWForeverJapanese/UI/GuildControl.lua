-- UI/GuildControl.lua: the guild control window on Forever (surface "guildcontrol", area "ui", ADR-016).
-- Load-on-demand Blizzard_GuildControlUI. Entry points in the camelot load set: the Communities window's
-- GuildControlButton (blizzard_communities/communitiesframe.xml:258–264, shown to the guild leader and officers,
-- communitiesframe.lua:1772–1775) and the guild unit-popup's "Guild Control" entry (blizzard_unitpopup/mainline/
-- unitpopupbuttons.lua:237–239), both → GuildControlUI_Show → LoadAddOn + ShowUIPanel(GuildControlUI)
-- (blizzard_guildcontrolui_bootstrap.lua:3–11). Set up through WFJ.LoadOnDemand.when.
-- Static labels (blizzard_guildcontrolui.xml), each restricted to its own key:
--   GuildControlUITitle GUILDCONTROL (:414); orderFrame.newButton GUILD_NEW_RANK (:460), .dupButton GUILD_DUP_RANK
--   (:469); the rank-permission checkboxes GuildControlUIRankSettingsFrameCheckbox<id>Text, written once by
--   GuildControlUI_OnLoad from _G["GUILDCONTROL_OPTION" .. id] (lua:97–103; ids 2, 5–8, 15, 16, 18, 19, 21:
--   xml:679–774), and OfficerCheckbox.text GUILD_CONTROL_RANK_PERMISSION_HAS_OFFICER_PRIVLEGES (lua:514);
--   GuildControlUIRankSettingsFrameBankLabel GUILD_BANK (:649); the unnamed GUILDCONTROL_SELECTRANK labels in the two
--   rank dropdowns' layers (:499, :663) and DISCORD_SELECT_SERVER / DISCORD_SELECT_CHANNEL (:556, :591), found with
--   Labels.region; the Discord pane's noChannelsError (:574), channelButton (:600), and the two frames it creates on
--   demand (lua:325, :403): DiscordLinkFrame.linkedTitle (lua:330), .SeparateStream.Label (:345), .button (:354),
--   DiscordUnlinkFrame.unlinkedTitle (:378, lua:406), .button (:387).
--   Each bank tab row GuildControlBankTab<i> (created on demand, lua:175–178; BankTabPermissionTemplate xml:140–300):
--   owned.viewCB.text GUILDCONTROL_VIEW_TAB (:182), owned.depositCB.text GUILDCONTROL_DEPOSIT_ITEMS (:195), the
--   buy.button BANKSLOTPURCHASE (:287). A row's owned.tabName is the tab's name and is never touched.
-- The navigation dropdown's own text (GUILDCONTROL_GUILDRANKS / _RANK_PERMISSIONS / _BANK_PERMISSIONS, lua:61–73)
--   goes through Labels.dropdown; its popup entries are UI/Menus'. The rank dropdowns show rank names: never touched.
-- Writers: the pane updates are globals (GuildControlUI_RankOrder_Update, _RankPermissions_Update,
--   _BankTabPermissions_Update, _Discord_Update) that the window stores in GuildControlUI.rankUpdate when a pane is
--   selected (lua:38–53) and calls from there (:131). A hook on the global is seen by every selection made after it
--   was installed; the pane selected before that is covered by the OnShow pass (in-game check: the first pane after
--   a rank change without re-opening).
-- Tooltips (XML OnEnter → GameTooltip:SetText, owner = the button): each rank row's delete / down / up buttons
--   GUILDREMOVERANK_BUTTON_TOOLTIP, GUILD_LOWERRANK_BUTTON_TOOLTIP, GUILD_RAISERANK_BUTTON_TOOLTIP plus the reason
--   line ERR_GUILD_RANK_IN_USE / AUTHENTICATOR_GUILD_RANK_CHANGE (xml:43–106, lua:563–591); the authenticator
--   checkbox's tooltip frame GUILD_RANK_AUTHENTICATOR_TOOLTIP, AUTHENTICATOR_GUILD_RANK_LAST / _IN_USE (xml:790–810,
--   lua:457–461).
-- rankPermFrame.OfficerPermissions (xml:643) holds table.concat(GUILD_OFFICER_PERMISSION_STRINGS, "|n")
--   (lua:471–483, written by GuildControlRankSettings_OnLoad, :511–512); lineList: every "|n"-separated line must be
--   a GUILD_OFFICER_PERMISSION_* entry, else the whole text stays English; rejoined with "|n". The Discord pane's
--   DiscordLinkFrame.linkedServer / .linkedChannel (DISCORD_GUILD_LINKED_SERVER / _CHANNEL, lua:328–332) and
--   discordFrame.channelListTitle (DISCORD_VALID_SERVER_CHANNEL_LIST, lua:377–378): only their own key; the server
--   and channel names are `text` arguments, kept as written.
-- Never touched: rank names (the rows' EditBoxes, the rank dropdowns), bank tab names, the gold / stack EditBoxes,
-- "Rank n:" (RANK .. " " .. i .. ":", lua:546, a run-time composite), Discord server and channel names.
-- Release on GuildControlUI's OnHide.
local _, WFJ = ...
local GuildControl = {}
WFJ.GuildControl = GuildControl

local SURFACE = "guildcontrol"
GuildControl.SURFACE = SURFACE
local Compat = WFJ.Compat
local ADDON = "Blizzard_GuildControlUI"
local F = "GuildControlUI"
local PERM = "GuildControlUIRankSettingsFrame"
local MAX_RANKS, MAX_TABS = 10, 8 -- MAX_GUILDRANKS / MAX_GUILDBANK_TABS (blizzard_framexmlbase/constants.lua)
local OPTION_IDS = { 2, 5, 6, 7, 8, 15, 16, 18, 19, 21 }

GuildControl.NEVER_TOUCH = { PERM .. "GoldBox", F .. ".bankTabFrame.dropdown.Text",
  F .. ".rankPermFrame.dropdown.Text" }

-- record key → { candidate, the key the widget may show }
local LABELS = {
  title = { "GuildControlUITitle", "GUILDCONTROL" }, newRank = { F .. ".orderFrame.newButton", "GUILD_NEW_RANK" },
  dupRank = { F .. ".orderFrame.dupButton", "GUILD_DUP_RANK" }, bankLabel = { PERM .. "BankLabel", "GUILD_BANK" },
  officer = { F .. ".rankPermFrame.OfficerCheckbox.text", "GUILD_CONTROL_RANK_PERMISSION_HAS_OFFICER_PRIVLEGES" },
  noChannels = { F .. ".discordFrame.noChannelsError", "DISCORD_GUILD_SETTING_CHANNEL_LIST_EMPTY" },
  linkChannel = { F .. ".discordFrame.channelButton", "DISCORD_CHANNEL_LINK_PROMPT" },
  linkedTitle = { "DiscordLinkFrame.linkedTitle", "DISCORD_GUILD_SERVER_CHANNEL_LINKED" },
  separateStream = { "DiscordLinkFrame.SeparateStream.Label", "DISCORD_GUILD_SETTING_SEPARATE_STREAM" },
  unlink = { "DiscordLinkFrame.button", "DISCORD_SERVER_UNLINK_PROMPT" },
  unlinkedTitle = { "DiscordUnlinkFrame.unlinkedTitle", "DISCORD_GUILD_NEED_TO_OAUTH" },
  oauth = { "DiscordUnlinkFrame.button", "DISCORD_SETUP_OAUTH" },
  linkedServer = { "DiscordLinkFrame.linkedServer", "DISCORD_GUILD_LINKED_SERVER" },
  linkedChannel = { "DiscordLinkFrame.linkedChannel", "DISCORD_GUILD_LINKED_CHANNEL" },
  channelList = { F .. ".discordFrame.channelListTitle", "DISCORD_VALID_SERVER_CHANNEL_LIST" },
}
local PERMISSIONS = { "GUILD_OFFICER_PERMISSION_ACCESS_CHANNELS", "GUILD_OFFICER_PERMISSION_REMOVE_FROM_VOICE",
  "GUILD_OFFICER_PERMISSION_DELETE_MESSAGES", "GUILD_OFFICER_PERMISSION_DELETE_EVENTS",
  "GUILD_OFFICER_PERMISSION_OFFICER_NOTES", "GUILD_OFFICER_PERMISSION_PUBLIC_NOTES",
  "GUILD_OFFICER_PERMISSION_GUILD_INFO", "GUILD_OFFICER_PERMISSION_MOTD", "GUILD_OFFICER_PERMISSION_FINDER_LIST",
  "GUILD_OFFICER_PERMISSION_INVITE_APPLICANTS", "GUILD_OFFICER_PERMISSION_SET_DISCORD" }
for _, id in ipairs(OPTION_IDS) do
  LABELS["option" .. id] = { PERM .. "Checkbox" .. id .. "Text", "GUILDCONTROL_OPTION" .. id }
end
local ORDER = {}
for key in pairs(LABELS) do ORDER[#ORDER + 1] = key end
table.sort(ORDER)
local OPTS = {}
for key, l in pairs(LABELS) do OPTS[key] = { only = { l[2] } } end

-- Unnamed labels: record key → { the frame whose region it is, key }.
local REGIONS = {
  selectBankRank = { F .. ".bankTabFrame.dropdown", "GUILDCONTROL_SELECTRANK" },
  selectPermRank = { F .. ".rankPermFrame.dropdown", "GUILDCONTROL_SELECTRANK" },
  selectServer = { F .. ".discordFrame.serverDropdown", "DISCORD_SELECT_SERVER" },
  selectChannel = { F .. ".discordFrame.channelDropdown", "DISCORD_SELECT_CHANNEL" },
}
local REGION_ORDER = { "selectBankRank", "selectChannel", "selectPermRank", "selectServer" }

local VIEW, DEPOSIT, PURCHASE = { only = { "GUILDCONTROL_VIEW_TAB" } }, { only = { "GUILDCONTROL_DEPOSIT_ITEMS" } },
  { only = { "BANKSLOTPURCHASE" } }
local REASONS = { "ERR_GUILD_RANK_IN_USE", "AUTHENTICATOR_GUILD_RANK_CHANGE" }
local RANK_TOOLTIPS = {
  deleteButton = { only = { "GUILDREMOVERANK_BUTTON_TOOLTIP", REASONS[1], REASONS[2] } },
  downButton = { only = { "GUILD_LOWERRANK_BUTTON_TOOLTIP", REASONS[1], REASONS[2] } },
  upButton = { only = { "GUILD_RAISERANK_BUTTON_TOOLTIP", REASONS[1], REASONS[2] } },
}
local AUTH_TOOLTIP = { only = { "GUILD_RANK_AUTHENTICATOR_TOOLTIP", "AUTHENTICATOR_GUILD_RANK_LAST",
  "AUTHENTICATOR_GUILD_RANK_IN_USE" } }
local WRITERS = { "GuildControlUI_RankOrder_Update", "GuildControlUI_RankPermissions_Update",
  "GuildControlUI_BankTabPermissions_Update", "GuildControlUI_Discord_Update" }

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  Compat.declare(SURFACE, "frame", { F })
  Compat.declare(SURFACE, "nav", { F .. ".dropdown" })
  Compat.declare(SURFACE, "authTooltip", { PERM .. "Checkbox18Tooltip" })
  Compat.declare(SURFACE, "permissions", { F .. ".rankPermFrame.OfficerPermissions" })
  for key, l in pairs(LABELS) do Compat.declare(SURFACE, key, { l[1] }) end
  for key, r in pairs(REGIONS) do Compat.declare(SURFACE, "region." .. key, { r[1] }) end
  for i = 1, MAX_RANKS do Compat.declare(SURFACE, "rank" .. i, { "GuildControlUIRankOrderFrameRank" .. i }) end
  for i = 1, MAX_TABS do Compat.declare(SURFACE, "bankTab" .. i, { "GuildControlBankTab" .. i }) end
  for _, name in ipairs(WRITERS) do Compat.declare(SURFACE, name, { name }) end
end

-- The rank rows' three buttons own a tooltip each; rows are created as ranks are added. → the number registered
local function registerRanks()
  local n = 0
  for i = 1, MAX_RANKS do
    local row = get("rank" .. i)
    if type(row) == "table" then
      for field, opts in pairs(RANK_TOOLTIPS) do WFJ.HelpTooltip.register(row[field], opts) end
      n = n + 1
    end
  end
  return n
end

-- The officer permission lines (lineList): all-or-nothing, "|n" kept. → 1 | 0
function GuildControl.showPermissions()
  local fs = WFJ.Labels.widget(get("permissions"))
  if not fs then return 0 end
  local rec = WFJ.SurfaceState.get(SURFACE, "permissions")
  if rec and rec.fs == fs and rec.applied ~= nil and fs:GetText() == rec.applied then return 1 end -- still ours
  local text, parts = fs:GetText(), {}
  if type(text) ~= "string" or text == "" then return WFJ.Labels.showArgs(SURFACE, "permissions", fs, nil) end
  for line in (text .. "|n"):gmatch("(.-)|n") do
    local part = WFJ.Labels.part(line, PERMISSIONS)
    if not part then return WFJ.Labels.showArgs(SURFACE, "permissions", fs, nil) end
    if #parts > 0 then parts[#parts + 1] = "|n" end
    parts[#parts + 1] = part
  end
  return WFJ.Labels.showArgs(SURFACE, "permissions", fs, parts[1].key, { form = "seq", parts = parts })
end

-- OnShow and hooksecurefunc target (the four pane updates). → the number of dictionary words found
function GuildControl.show()
  declare() -- rank rows, bank tab rows and the Discord frames are created on demand: forget Compat's misses
  local list = {}
  for _, key in ipairs(ORDER) do list[#list + 1] = { key, get(key), OPTS[key] } end
  for _, key in ipairs(REGION_ORDER) do
    local k = REGIONS[key][2]
    list[#list + 1] = { key, WFJ.Labels.region(get("region." .. key), k), { only = { k } } }
  end
  for i = 1, MAX_TABS do
    local row = get("bankTab" .. i)
    local owned, buy = type(row) == "table" and row.owned or nil, type(row) == "table" and row.buy or nil
    if type(owned) == "table" then
      local view, deposit = owned.viewCB, owned.depositCB
      list[#list + 1] = { "bankTab" .. i .. ".view", type(view) == "table" and view.text or nil, VIEW }
      list[#list + 1] = { "bankTab" .. i .. ".deposit", type(deposit) == "table" and deposit.text or nil, DEPOSIT }
    end
    if type(buy) == "table" then list[#list + 1] = { "bankTab" .. i .. ".buy", buy.button, PURCHASE } end
  end
  registerRanks()
  local n = GuildControl.showPermissions()
  return n + WFJ.Labels.showAll(SURFACE, list) + WFJ.Labels.dropdown(SURFACE, "nav", get("nav"))
end

function GuildControl.release()
  return WFJ.Render.release(SURFACE)
end

local hooked, waiting = false, false

-- Runs once Blizzard_GuildControlUI is loaded (now, or on its ADDON_LOADED).
function GuildControl.setup()
  declare()
  local frame = get("frame")
  if hooked or type(frame) ~= "table" then return false end
  hooked = true
  WFJ.Labels.forbidNames(GuildControl.NEVER_TOUCH) -- its widgets exist only now
  for _, name in ipairs(WRITERS) do
    if type(get(name)) == "function" then hooksecurefunc(name, GuildControl.show) end
  end
  if type(frame.HookScript) == "function" then
    frame:HookScript("OnShow", GuildControl.show)
    frame:HookScript("OnHide", GuildControl.release)
  end
  WFJ.HelpTooltip.register(get("authTooltip"), AUTH_TOOLTIP)
  if type(frame.IsShown) == "function" and frame:IsShown() then GuildControl.show() end
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init. → true when the window
-- exists now, false while it waits for Blizzard_GuildControlUI.
function GuildControl.init()
  declare()
  if hooked then return false end
  if not waiting then
    waiting = true
    return WFJ.LoadOnDemand.when(ADDON, GuildControl.setup) and hooked
  end
  return false
end
