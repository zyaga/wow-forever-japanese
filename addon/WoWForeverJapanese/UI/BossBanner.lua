-- UI/BossBanner.lua: the "boss defeated" banner on Forever (surface "bossbanner", area "ui", ADR-016).
-- Blizzard_FrameXML loads bossbannertoast.xml|lua at login on `camelot`. Entry point: BossBanner registers BOSS_KILL
-- and ENCOUNTER_LOOT_RECEIVED itself (bossbannertoast.lua:177–184) and queues itself on the top banner manager
-- (:186–205); BossBanner_Play (stored as self.PlayBanner at OnLoad, :179, so the global is never re-read) writes the
-- title and then calls self:Show() (:229–243); an OnShow pass (HookScript) sees the finished text:
--   Title     BOSS_YOU_DEFEATED when the PraiseTheSun CVar is on, else the boss's name (a name: `only` restriction)
--   SubTitle  BOSS_KILL_SUBTITLE "has been defeated" (XML text=, bossbannertoast.xml:225), shown under the name.
-- Loot rows: BossBanner_ConfigureLootFrame(lootFrame, data), called by its global name (:57, :73–112), writes
--   SetName BOSS_BANNER_LOOT_SET "Set: %s" around the item set's name (stays English inside the Japanese: a `text`
--   argument, Core/UIStrings). The row is pooled (parentArray LootFrames): records are keyed by widget (Labels.keyer).
-- Never touched: the loot row's ItemName, Count and PlayerName (an item, a number, a player).
local _, WFJ = ...
local BossBanner = {}
WFJ.BossBanner = BossBanner

local SURFACE = "bossbanner"
BossBanner.SURFACE = SURFACE
local Compat = WFJ.Compat

BossBanner.NEVER_TOUCH = {}

local CANDIDATES = { frame = { "BossBanner" }, title = { "BossBanner.Title" }, subtitle = { "BossBanner.SubTitle" },
  configure = { "BossBanner_ConfigureLootFrame" } }
local TITLE = { only = { "BOSS_YOU_DEFEATED" } }
local SUBTITLE = { only = { "BOSS_KILL_SUBTITLE" } }
local SET = { only = { "BOSS_BANNER_LOOT_SET" } }

local setKey = WFJ.Labels.keyer("set.")

local function get(key) return Compat.get(SURFACE, key) end

-- The banner's two labels (its OnShow). → the number of dictionary words found.
function BossBanner.show()
  return WFJ.Labels.showAll(SURFACE, { { "title", get("title"), TITLE }, { "subtitle", get("subtitle"), SUBTITLE } })
end

-- hooksecurefunc target (BossBanner_ConfigureLootFrame): one loot row just written. → 1 | 0
function BossBanner.onLoot(lootFrame)
  if type(lootFrame) ~= "table" or type(lootFrame.SetName) ~= "table" then return 0 end
  return WFJ.Labels.show(SURFACE, setKey(lootFrame.SetName), lootFrame.SetName, nil, SET)
end

local hooked = false

-- Called by Main after Compat.init. → true when the banner was hooked now; false on a second call.
function BossBanner.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  if hooked then return false end
  local frame = get("frame")
  if type(frame) ~= "table" or type(frame.HookScript) ~= "function" then return false end
  hooked = true
  frame:HookScript("OnShow", BossBanner.show)
  if type(get("configure")) == "function" then hooksecurefunc("BossBanner_ConfigureLootFrame", BossBanner.onLoot) end
  BossBanner.show()
  return true
end
