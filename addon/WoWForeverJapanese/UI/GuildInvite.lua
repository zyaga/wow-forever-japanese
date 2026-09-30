-- UI/GuildInvite.lua: the guild invitation window on Forever (surface "guildinvite", area "ui", ADR-016).
-- Blizzard_FrameXML loads guildinviteframe.xml|lua at login on `camelot`. Entry point: the frame registers
-- GUILD_INVITE_REQUEST itself (guildinviteframe.xml:140); GuildInviteFrame_OnEvent writes the inviter and guild names
-- and the reputation warning, then StaticPopupSpecial_Show(GuildInviteFrame) (guildinviteframe.lua:1–38), so every
-- text is written before OnShow; one OnShow pass (HookScript) shows the window.
-- Static labels (XML text=): GuildInviteFrameInviteText GUILD_INVITATION (xml:40), Points.Title ACHIEVEMENTS (xml:87),
--   GuildInviteFrameJoinButton GUILD_INVITE_JOIN (xml:112), GuildInviteFrameDeclineButton GUILD_INVITE_DECLINE
--   (xml:125).
-- Written on each invite: GuildInviteFrameWarningText GUILD_REPUTATION_WARNING "… with %s" (the old guild's name stays
--   English inside the Japanese) / GUILD_REPUTATION_WARNING_GENERIC / "" (lua:22–30).
-- Never touched: the inviter's name, the guild's name (GuildInviteFrameInviterName / GuildNameName, lua:8–9), the
--   points number, and the inviter tooltip (a player name, lua:41–46).
local _, WFJ = ...
local GuildInvite = {}
WFJ.GuildInvite = GuildInvite

local SURFACE = "guildinvite"
GuildInvite.SURFACE = SURFACE
local Compat = WFJ.Compat

GuildInvite.NEVER_TOUCH = { "GuildInviteFrameInviterName", "GuildInviteFrameGuildName", "GuildInviteFrame.Points.Text" }

local CANDIDATES = {
  frame = { "GuildInviteFrame" }, invite = { "GuildInviteFrameInviteText" },
  points = { "GuildInviteFrame.Points.Title" },
  join = { "GuildInviteFrameJoinButton" }, decline = { "GuildInviteFrameDeclineButton" },
  warning = { "GuildInviteFrameWarningText" },
}

local LABELS = {
  { "invite", { only = { "GUILD_INVITATION" } } }, { "points", { only = { "ACHIEVEMENTS" } } },
  { "join", { only = { "GUILD_INVITE_JOIN" } } }, { "decline", { only = { "GUILD_INVITE_DECLINE" } } },
  { "warning", { only = { "GUILD_REPUTATION_WARNING", "GUILD_REPUTATION_WARNING_GENERIC" } } },
}

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
end

-- The window's labels (its OnShow). → the number of dictionary words found.
function GuildInvite.show()
  local list = {}
  for i, l in ipairs(LABELS) do list[i] = { l[1], get(l[1]), l[2] } end
  return WFJ.Labels.showAll(SURFACE, list)
end

local hooked = false

-- Called by Main after Compat.init. → true when the window was found and hooked now; false on a second
-- call.
function GuildInvite.init()
  declare()
  if hooked then return false end
  local frame = get("frame")
  if type(frame) ~= "table" or type(frame.HookScript) ~= "function" then return false end
  hooked = true
  frame:HookScript("OnShow", GuildInvite.show)
  GuildInvite.show()
  return true
end
