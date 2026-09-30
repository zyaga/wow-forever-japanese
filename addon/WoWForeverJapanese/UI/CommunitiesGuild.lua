-- UI/CommunitiesGuild.lua: the Communities window's guild benefits and preferred-play pages on Forever (surface
-- "communities.benefits", area "ui", ADR-016): guild perks and rewards, the guild reputation bar, the
-- achievement-point display and the preferred play settings. Plumbing: UI/CommunitiesKit.
-- Every file:line below is the camelot extract 1.60.1.69913, interface/addons/blizzard_communities/.
-- Static labels: GuildBenefitsFrame.Perks.TitleText (guildperks.xml:123), .Rewards.TitleText (guildrewards.xml:222),
--   .FactionFrame.Label (communitiesframe.xml:37); GuildPreferredPlaySettingsFrame's Title / LocaleLabel /
--   DatacenterLabel (its OnLoad writes, guildpreferredplaysettings.lua:50-52) and the two Apply buttons
--   (guildpreferredplaysettings.xml:35, 51).
-- Writers: GuildPreferredPlaySettingsFrame:RefreshState → NotGuildMasterNotice (lua:104-106); a reward row's Init
--   (CommunitiesGuildRewardsButtonMixin:Init, guildrewards.lua:7-56, the ScrollBox element initializer, lua:62-64) →
--   SubText: REQUIRES_GUILD_FACTION with the standing word, or REQUIRES_LABEL + icon + the achievement's name (the
--   name kept as written by the label's `list` form). The row's Name is the item's name: never touched.
-- Help tooltips: FactionFrame.Bar (CommunitiesGuildFactionBarMixin:OnEnter, guildrewards.lua:180-199: the faction
--   description line is the client's text, not matched); GuildAchievementPointDisplay (lua:266-270);
--   GuildRewardsTutorialButton (guildrewards.xml:57-62); the two Apply buttons' lockout tooltip
--   (guildpreferredplaysettings.lua:12-14, 205-227).
-- A reward row's tooltip is an item tooltip (SetHyperlink, guildrewards.lua:102-129): the help-tooltip walker leaves
--   item tooltips to the item surface, and the requirement lines are added after the item surface ran, so the row's
--   OnEnter (bound in XML with function=, guildrewards.xml:202; HookScript, and the global the Update refresh and
--   UpdateTooltip call, lua:95-97, 128) shows those three lines itself, restricted to their keys, released when the
--   tooltip hides.
-- The guild info page's texts (ADR-038) the client builds:
--   the guild event log (guildEventLog): CommunitiesGuildLogFrame.Container.ScrollFrame.Child.HTMLFrame, a SimpleHTML
--     (guildinfo.xml:384–422) whose one text CommunitiesGuildLogFrame_Update rebuilds (guildinfo.lua:163–194): per
--     GetGuildEventInfo row, a GUILDEVENT_TYPE_* line .. GUILD_BANK_LOG_TIME .. "|n". A SetText post-hook on the
--     SimpleHTML (it has no GetText) reads each text the client writes; every line is matched as its template (player
--     names and the rank `text`, kept as written) followed by the time suffix; a line that matches nothing stays as
--     written. An adapter gives Render the FontString interface: GetText is the text of record (the client's, or ours
--     once shown), SetText writes the SimpleHTML, the font is the P text type's [unverified: that a plain-text
--     SimpleHTML draws with the P font; in-game check]. Alt / the switch put the client's text back (Render).
--   guild news (guildnews.lua:120–136 → GuildNewsButton_SetText, blizzard_framexml/guildutil.lua:41–44): an event
--     row is GUILD_EVENT_FORMAT with the day (GUILD_EVENT_TODAY colour-wrapped, or a weekday) and the event's title
--     kept as written; only that key on button.text, so the other news rows (names, achievements) stay English.
--   the text-edit dialog's Title (CommunitiesGuildTextEditFrame_SetType, guildinfo.lua:127–146): GUILD_MOTD_EDITLABEL /
--     GUILD_INFO_EDITLABEL; its EditBox is never touched.
--   the guild reputation bar's Label (CommunitiesGuildFactionBarMixin:UpdateFaction / :OnLeave, guildrewards.lua:
--     201–226): the standing word (FACTION_STANDING_LABEL<n>[_FEMALE]); OnEnter's numbers are left alone.
local _, WFJ = ...
local Kit = WFJ.CommunitiesKit
local CommunitiesGuild = {}
WFJ.CommunitiesGuild = CommunitiesGuild

local SURFACE = "communities.benefits"
CommunitiesGuild.SURFACE = SURFACE
local REWARD_TT = SURFACE .. ".rewardtip"

local BENEFITS = "CommunitiesFrame.GuildBenefitsFrame"
local PLAY = "CommunitiesFrame.GuildPreferredPlaySettingsFrame"

CommunitiesGuild.NEVER_TOUCH = {}

local k = Kit.new(SURFACE, {
  benefits = { BENEFITS }, play = { PLAY }, rewards = { BENEFITS .. ".Rewards.ScrollBox" },
  tooltip = { "GameTooltip" }, rewardEnter = { "CommunitiesGuildRewardsButton_OnEnter" },
  logFrame = { "CommunitiesGuildLogFrame" },
  logHtml = { "CommunitiesGuildLogFrame.Container.ScrollFrame.Child.HTMLFrame" },
  newsText = { "GuildNewsButton_SetText" }, editType = { "CommunitiesGuildTextEditFrame_SetType" },
})
local LOG = SURFACE .. ".log"
local LOG_KEYS = { "GUILDEVENT_TYPE_INVITE", "GUILDEVENT_TYPE_JOIN", "GUILDEVENT_TYPE_PROMOTE",
  "GUILDEVENT_TYPE_DEMOTE", "GUILDEVENT_TYPE_REMOVE", "GUILDEVENT_TYPE_QUIT" }
local LOG_TIME = { "GUILD_BANK_LOG_TIME" }
local NEWS = { "GUILD_EVENT_FORMAT" }
local EDIT_TITLES = { "GUILD_MOTD_EDITLABEL", "GUILD_INFO_EDITLABEL" }
local STANDINGS = {}
for i = 1, 8 do
  STANDINGS[#STANDINGS + 1] = "FACTION_STANDING_LABEL" .. i
  STANDINGS[#STANDINGS + 1] = "FACTION_STANDING_LABEL" .. i .. "_FEMALE"
end

local STATIC = {
  { "perksTitle", "benefits", "Perks.TitleText", { "GUILD_PERKS_TITLE" } },
  { "rewardsTitle", "benefits", "Rewards.TitleText", { "GUILD_REWARDS_TITLE" } },
  { "reputation", "benefits", "FactionFrame.Label", { "GUILD_REPUTATION_COLON" } },
  { "play.title", "play", "Title", { "PREFERRED_PLAY_SETTINGS" } },
  { "play.locale", "play", "LocaleLabel", { "PREFERRED_LOCALE_LABEL" } },
  { "play.datacenter", "play", "DatacenterLabel", { "PREFERRED_GUILD_DATACENTER_LOCALITY_LABEL" } },
  { "play.localeApply", "play", "LocaleApplyButton", { "APPLY" } },
  { "play.datacenterApply", "play", "DatacenterApplyButton", { "APPLY" } },
}

local LOCKOUT = { "PREFERRED_PLAY_SETTINGS_LOCKED_REASON_FORMAT" }
local TOOLTIPS = {
  { "benefits", "FactionFrame.Bar", { "GUILD_REPUTATION", "GUILD_EXPERIENCE_CURRENT" } },
  { "benefits", "GuildAchievementPointDisplay", { "GUILD_POINTS_TT" } },
  { "benefits", "GuildRewardsTutorialButton", { "GUILD_REWARDS_VISIT_VENDOR" } },
  { "play", "LocaleApplyButton", LOCKOUT }, { "play", "DatacenterApplyButton", LOCKOUT },
}
local SUBTEXT = { "REQUIRES_GUILD_FACTION", "REQUIRES_LABEL" }
local REWARD_LINES = { "REQUIRES_GUILD_ACHIEVEMENT", "REQUIRES_GUILD_FACTION_TOOLTIP", "INSPECT_REQUIREMENTS" }

function CommunitiesGuild.showStatic() return k.showUnder(STATIC) end

-- hooksecurefunc target (GuildPreferredPlaySettingsFrame:RefreshState). → 1 | 0
function CommunitiesGuild.onPlay()
  local n = k.show("play.notice", Kit.child(k.get("play"), "NotGuildMasterNotice"),
    { "GUILD_PREFERRED_PLAY_SETTINGS_NO_PERMISSION" })
  WFJ.Render.updateBanner(SURFACE)
  return n
end

local rowKey = WFJ.Labels.keyer("reward.") -- a pooled reward row's record key

-- One reward row after its Init.
function CommunitiesGuild.onReward(row)
  if type(row.Name) == "table" then WFJ.Labels.forbid(row.Name) end
  if type(row.SubText) == "table" then k.show(rowKey(row.SubText), row.SubText, SUBTEXT) end
  Kit.script(row, "OnEnter", CommunitiesGuild.onRewardTooltip, SURFACE)
  WFJ.Render.updateBanner(SURFACE)
end

-- After a reward row's tooltip is built: its requirement lines (never the item's own lines). A second run for the same
-- hover (a row created after the global was hooked binds the hooked global too) finds its own Japanese and keeps it.
-- → n shown
function CommunitiesGuild.onRewardTooltip()
  local tt = k.get("tooltip")
  if type(tt) ~= "table" or type(tt.NumLines) ~= "function" or type(tt.GetName) ~= "function" then return 0 end
  local name, n, changed = tt:GetName(), 0, false
  for i = 1, tt:NumLines() or 0 do
    local fs = WFJ.Compat.resolve(name .. "TextLeft" .. i)
    if type(fs) == "table" and type(fs.GetText) == "function" then
      local before = fs:GetText()
      n = n + WFJ.Labels.show(REWARD_TT, "L" .. i, fs, nil, { only = REWARD_LINES })
      if fs:GetText() ~= before then changed = true end
    end
  end
  if changed and type(tt.Show) == "function" then tt:Show() end -- one refit for the new line widths
  return n
end

-- ── the guild event log ─────────────────────────────────────────────
local log = { html = nil, logical = nil, writing = false }
CommunitiesGuild.log = log
function log:GetText() return self.logical end
function log:SetText(text)
  self.writing = true
  local ok, err = pcall(self.html.SetText, self.html, text)
  self.writing = false
  if not ok then error(err, 0) end
  self.logical = text
end
function log:GetFont()
  if type(self.html.GetFont) ~= "function" then return nil end
  return self.html:GetFont("P")
end
function log:SetFont(path, size, flags) -- SimpleHTML's SetFont returns nothing: a refusal is read back
  if type(self.html.SetFont) ~= "function" then return false end
  self.html:SetFont("P", path, size, flags)
  return (self:GetFont()) == path
end

-- The log text the client wrote, line by line. → n lines shown in Japanese (0: the text stays as written)
function CommunitiesGuild.showLog()
  if type(log.html) ~= "table" or type(log.logical) ~= "string" then return 0 end
  local rec = WFJ.SurfaceState.get(LOG, "log")
  if rec and rec.applied ~= nil and log.logical == rec.applied then return 1 end -- still ours
  local parts, key, n, pos = {}, nil, 0, 1
  local text = log.logical
  while pos <= #text do
    local s, e = text:find("|n", pos, true)
    local line = text:sub(pos, (s or 0) - 1)
    local head, suffix = line:match("^(.*)(|c%x%x%x%x%x%x%x%x[^|]*|r)$")
    local event = head and WFJ.Labels.part(head, LOG_KEYS)
    local time = event and WFJ.Labels.part(suffix, LOG_TIME)
    if time then
      parts[#parts + 1] = event
      parts[#parts + 1] = time
      key, n = key or event.key, n + 1
    else
      parts[#parts + 1] = line
    end
    if not s then break end
    parts[#parts + 1] = "|n"
    pos = e + 1
  end
  WFJ.Labels.showArgs(LOG, "log", log, key, key and { form = "seq", parts = parts } or nil)
  return n
end

-- SetText post-hook on the SimpleHTML: every text the client writes (ours is skipped).
local function onLogText(html, text)
  if log.writing then return end
  log.html, log.logical = html, type(text) == "string" and text or nil
  CommunitiesGuild.showLog()
end

local newsKey = WFJ.Labels.keyer("news.")

-- GuildNewsButton_SetText post-hook: an event row's text (GUILD_EVENT_FORMAT only). → 1 | 0
function CommunitiesGuild.onNews(button)
  local fs = type(button) == "table" and button.text or nil
  if type(fs) ~= "table" then return 0 end
  return k.show(newsKey(fs), fs, NEWS)
end

-- CommunitiesGuildTextEditFrame_SetType post-hook. → 1 | 0
function CommunitiesGuild.onEditType(frame)
  return k.show("edit.title", type(frame) == "table" and frame.Title or nil, EDIT_TITLES)
end

-- The reputation bar's standing word (UpdateFaction / OnLeave). → 1 | 0
function CommunitiesGuild.onFaction()
  return k.show("faction.bar", Kit.child(k.get("benefits"), "FactionFrame.Bar.Label"), STANDINGS)
end

local hooked = false

function CommunitiesGuild.setup()
  if not Kit.ready(k, CommunitiesGuild.NEVER_TOUCH) then return false end
  CommunitiesGuild.showStatic()
  for _, t in ipairs(TOOLTIPS) do k.tooltip(Kit.child(k.get(t[1]), t[2]), t[3]) end
  if hooked then return false end
  hooked = true
  k.after(k.get("play"), "RefreshState", CommunitiesGuild.onPlay)
  k.rows(k.get("rewards"), CommunitiesGuild.onReward)
  if type(k.get("rewardEnter")) == "function" then
    hooksecurefunc("CommunitiesGuildRewardsButton_OnEnter", CommunitiesGuild.onRewardTooltip)
  end
  k.script(k.get("tooltip"), "OnHide", function() WFJ.Render.release(REWARD_TT) end)
  local html = k.get("logHtml")
  if k.after(html, "SetText", onLogText) then log.html = html end
  k.script(k.get("logFrame"), "OnHide", function() WFJ.Render.release(LOG) end)
  if type(k.get("newsText")) == "function" then hooksecurefunc("GuildNewsButton_SetText", CommunitiesGuild.onNews) end
  if type(k.get("editType")) == "function" then
    hooksecurefunc("CommunitiesGuildTextEditFrame_SetType", CommunitiesGuild.onEditType)
  end
  local bar = Kit.child(k.get("benefits"), "FactionFrame.Bar")
  k.after(bar, "UpdateFaction", CommunitiesGuild.onFaction)
  k.script(bar, "OnLeave", CommunitiesGuild.onFaction)
  CommunitiesGuild.onFaction()
  CommunitiesGuild.onPlay()
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init.
function CommunitiesGuild.init() return Kit.init(k, CommunitiesGuild.setup) end
