-- UI/InstanceDifficulty.lua: the minimap's instance difficulty banner tooltip on Forever (surface "instancedifficulty"
-- via UI/HelpTooltip, area "ui", ADR-016). Blizzard_FrameXML loads instancedifficulty.xml|lua and
-- camelot/instancedifficultyoverrides.lua at login on `camelot`; the minimap creates the banner as
-- MinimapCluster.InstanceDifficulty (blizzard_minimap/mainline/minimap.xml:442, InstanceDifficultyTemplate).
-- Two Lua tooltips, each owner registered with UI/HelpTooltip and restricted to its keys:
--   the banner (InstanceDifficultyMixin:OnEnter, instancedifficulty.lua:177–191) calls GetDifficultyTooltip, which
--     camelot replaces (camelot/instancedifficultyoverrides.lua:9–22): title LFG_TYPE_DUNGEON / LFG_TYPE_RAID, line
--     DUNGEON_DIFFICULTY_5PLAYER / RAID_DIFFICULTY_10PLAYER / _20PLAYER / _40PLAYER;
--   the guild-group banner (GuildInstanceDifficultyMixin:OnEnter on .Guild, instancedifficulty.lua:218–247):
--     DUNGEON_DIFFICULTY_BANNER_TOOLTIP_PLAYER_COUNT "%d/%d Players", GUILD_GROUP and GUILD_ACHIEVEMENTS_ELIGIBLE /
--     _MINXP / _MAXXP, whose guild name stays English inside the Japanese (a `text` argument, Core/UIStrings);
--     its title DUNGEON_DIFFICULTY_BANNER_TOOLTIP "%s Difficulty" (instancedifficulty.lua:232, the difficulty's name
--     a `words` argument: in Japanese when it is a dictionary word, as written otherwise).
-- The banner's own text is a player count (instancedifficultyoverrides.lua:25–31): nothing to show.
local _, WFJ = ...
local InstanceDifficulty = {}
WFJ.InstanceDifficulty = InstanceDifficulty

local SURFACE = "instancedifficulty"
InstanceDifficulty.SURFACE = SURFACE
local Compat = WFJ.Compat

InstanceDifficulty.NEVER_TOUCH = {}

local OWNERS = {
  banner = { { "MinimapCluster.InstanceDifficulty" }, { only = { "LFG_TYPE_DUNGEON", "LFG_TYPE_RAID",
    "DUNGEON_DIFFICULTY_5PLAYER", "RAID_DIFFICULTY_10PLAYER", "RAID_DIFFICULTY_20PLAYER",
    "RAID_DIFFICULTY_40PLAYER" } } },
  guild = { { "MinimapCluster.InstanceDifficulty.Guild" }, { only = { "DUNGEON_DIFFICULTY_BANNER_TOOLTIP_PLAYER_COUNT",
    "GUILD_GROUP", "DUNGEON_DIFFICULTY_BANNER_TOOLTIP", "GUILD_ACHIEVEMENTS_ELIGIBLE",
    "GUILD_ACHIEVEMENTS_ELIGIBLE_MINXP",
    "GUILD_ACHIEVEMENTS_ELIGIBLE_MAXXP" } } },
}

local done = false

-- Called by Main after Compat.init and HelpTooltip.init. → true when the banner was registered now;
-- false on a second call and when the minimap has no banner.
function InstanceDifficulty.init()
  for key, o in pairs(OWNERS) do Compat.declare(SURFACE, key, o[1]) end
  if done then return false end
  local banner = Compat.get(SURFACE, "banner")
  if type(banner) ~= "table" then return false end
  done = true
  WFJ.HelpTooltip.register(banner, OWNERS.banner[2])
  local guild = Compat.get(SURFACE, "guild")
  if type(guild) == "table" then WFJ.HelpTooltip.register(guild, OWNERS.guild[2]) end
  return true
end
