-- The unit mouseover lines the client composes, through the TooltipDataProcessor Unit post-call
-- (UI/TooltipUnit.lua). Line 1 (the unit's name), a guild line and any line outside the unit keys stay as written.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for _, f in ipairs(H.UI_FILES) do FILES[#FILES + 1] = f end
FILES[#FILES + 1] = "UI/TimeLine.lua"
FILES[#FILES + 1] = "UI/Tooltip.lua"
FILES[#FILES + 1] = "UI/TooltipUnit.lua"

local UI = {
  UNIT_TYPE_PLUS_LEVEL_TEMPLATE = { "Level %d Elite %s", "レベル%d エリート %s" },
  UNIT_TYPE_LEVEL_TEMPLATE = { "Level %d %s", "レベル%d %s" },
  UNIT_SKINNABLE_LEATHER = { "Skinnable", "皮はぎ可能" },
  CORPSE_TOOLTIP = { "Corpse of %s", "%sの死体" },
  RAID = { "Raid", "レイド" }, -- a dictionary word that is no unit line
}

describe("UI/TooltipUnit: unit mouseover lines", function()
  local WFJ, tt

  local function left(i) return _G["GameTooltipTextLeft" .. i]:GetText() end
  -- The client's own order: C_TooltipInfo fills the lines, the post-calls run, then it Shows the frame
  -- (blizzard_sharedxmlgame/tooltip/tooltipdatahandler.lua:298–300). The Show can revert
  -- these lines, so the test replays it.
  local function hover(lines)
    tt:SetOwner(_G.UIParent, "ANCHOR_CURSOR")
    tt:SetText(lines[1])
    for i = 2, #lines do tt:AddLine(lines[i]) end
    for _, fn in ipairs(Stub.tooltipPostCalls[2] or {}) do fn(tt) end -- TooltipDataType.Unit
    tt:Show()
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    _G.UIParent = _G.UIParent or CreateFrame("Frame", "UIParent")
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    WFJ.HelpTooltip.init() -- the help surface hooks GameTooltip's Show / OnHide too: the unit lines survive it
    tt = _G.GameTooltip
    assert.is_true(WFJ.TooltipUnit.init())
  end)

  after_each(function() H.uiTeardown(); Stub.noTooltipDataProcessor = false end)

  it("the level and skinning lines are Japanese; the creature type is kept; the name line is never read", function()
    hover({ "Skinnable", "Level 11 Elite Humanoid", "Skinnable", "<Raid>", "Raid" })
    assert.are.equal("Skinnable", left(1)) -- a unit named like a key: line 1 is its name
    assert.are.equal("レベル11 エリート Humanoid", left(2))
    assert.are.equal("皮はぎ可能", left(3))
    assert.are.equal("<Raid>", left(4)) -- a guild line
    assert.are.equal("Raid", left(5)) -- a dictionary word outside the unit keys
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal("Level 11 Elite Humanoid", left(2))
    Stub.keys.alt = false; WFJ.Modifier.refresh()
  end)

  it("a corpse line keeps the name inside it", function()
    hover({ "Kobold Vermin", "Level 1 Humanoid", "Corpse of Kobold Vermin" })
    assert.are.equal("レベル1 Humanoid", left(2))
    assert.are.equal("Kobold Verminの死体", left(3))
  end)

  it("another tooltip frame, or a client without the data processor, is left alone", function()
    assert.are.equal(0, WFJ.TooltipUnit.onUnit(_G.ItemRefTooltip))
    Stub.noTooltipDataProcessor = true
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    local W = H.loadChunks(FILES)
    W.Compat.init(function(name) return _G[name] end)
    assert.is_false(W.TooltipUnit.init())
  end)
  it("the lines survive the client's Show, and hiding the tooltip releases them", function()
    hover({ "Kobold Vermin", "Level 1 Humanoid" })
    assert.are.equal("レベル1 Humanoid", left(2))
    tt:Show() -- a refresh: still ours
    assert.are.equal("レベル1 Humanoid", left(2))
    tt:Hide()
    assert.are.equal(0, WFJ.SurfaceState.count(WFJ.TooltipUnit.SURFACE))
  end)
end)

-- ADR-042: the level line's creature-type slot is a `creatureType` argument: a CreatureType row's Japanese
-- when the word is one, anything else (a race, a class, a pet family) kept as written.
describe("UI/TooltipUnit: the creature type", function()
  local WFJ, tt

  local ROWS = {
    UNIT_TYPE_LEVEL_TEMPLATE = { "Level %d %s", "レベル%d %s" },
    UNIT_TYPE_PLUS_LEVEL_TEMPLATE = { "Level %d Elite %s", "レベル%d エリート %s" },
    ["CreatureType:7"] = { "Humanoid", "人型" },
    ["CreatureType:6"] = { "Undead", "アンデッド" }, -- also the Scourge race's name
    TOOLTIP_UNIT_LEVEL_RACE = { "Level %s %s", "レベル%s %s" },
    TOOLTIP_UNIT_LEVEL_RACE_TYPE = { "Level %s %s (%s)", "レベル%s %s (%s)" },
    ["DispelType:1"] = { "Magic", "魔法" }, -- another family's row: never a creature type
    RAID = { "Raid", "レイド" }, -- a dictionary word: never a creature type
    ["CreatureType:1"] = { "Beast", "野獣" },
    QUEST_MONSTERS_KILLED = { "%2$d/%3$d %1$s slain", "%1$sを倒す: %2$d/%3$d" },
    TOOLTIP_UNIT_LEVEL = { "Level %s", "レベル %s" },
  }
  local function left(i) return _G["GameTooltipTextLeft" .. i]:GetText() end
  local function hover(lines, data)
    tt:SetOwner(_G.UIParent, "ANCHOR_CURSOR")
    tt:SetText(lines[1])
    for i = 2, #lines do tt:AddLine(lines[i]) end
    for _, fn in ipairs(Stub.tooltipPostCalls[2] or {}) do fn(tt, data) end
    tt:Show()
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    _G.UIParent = _G.UIParent or CreateFrame("Frame", "UIParent")
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, ROWS)
    WFJ.HelpTooltip.init()
    tt = _G.GameTooltip
    assert.is_true(WFJ.TooltipUnit.init())
  end)

  after_each(function() H.uiTeardown(); Stub.keys.alt = false end)

  it("a race slot keeps the race English even when it is also a creature type", function()
    hover({ "Someone", "Level ?? Undead" }) -- only TOOLTIP_UNIT_LEVEL_RACE takes "??": slot 2 is the race
    assert.are.equal("レベル?? Undead", left(2))
    hover({ "Someone", "Level 60 Undead (Humanoid)" }) -- a race slot either way: never アンデッド
    assert.is_nil(left(2):find("アンデッド", 1, true))
    -- "Level 60 Undead" is one text for an Undead player and an undead creature: the unit decides
    _G.C_PlayerInfo = { GUIDIsPlayer = function(guid) return guid:find("^Player%-") ~= nil end }
    hover({ "Someone", "Level 60 Undead" }, { guid = "Player-1-00000001" })
    assert.are.equal("レベル60 Undead", left(2))
    hover({ "Skeleton", "Level 60 Undead" }, { guid = "Creature-0-1-2-3-4-5" })
    assert.are.equal("レベル60 アンデッド", left(2))
    hover({ "Skeleton", "Level 60 Undead" }) -- no tooltip data: a creature
    assert.are.equal("レベル60 アンデッド", left(2))
    _G.C_PlayerInfo = nil
  end)

  it("a CreatureType row fills the slot in Japanese; Alt shows the English line", function()
    hover({ "Kobold Vermin", "Level 10 Humanoid" })
    assert.are.equal("レベル10 人型", left(2))
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal("Level 10 Humanoid", left(2))
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    assert.are.equal("レベル10 人型", left(2))
    hover({ "Hogger", "Level 11 Elite Humanoid" })
    assert.are.equal("レベル11 エリート 人型", left(2))
  end)

  it("a creature's type on its own line and its quest kill count translate; the creature's name stays English",
    function()
      hover({ "Young Thistle Boar", "Level 2", "Beast", "The Balance of Nature", "0/4 Young Thistle Boar slain" })
      assert.are.equal("レベル 2", left(2))
      assert.are.equal("野獣", left(3))
      assert.are.equal("The Balance of Nature", left(4)) -- a quest title: keyed by quest id, not by its text
      assert.is_truthy(left(5):find("Young Thistle Boarを倒す: 0/4", 1, true))
      -- a player's tooltip never takes the creature types: "Undead" alone is a race there
      _G.C_PlayerInfo = { GUIDIsPlayer = function() return true end }
      hover({ "Someone", "Level 60", "Undead" }, { guid = "Player-1-00000001" })
      assert.are.equal("Undead", left(3))
      _G.C_PlayerInfo = nil
    end)

  it("a word no CreatureType row has (a pet family, another family's row, a dictionary word) is kept", function()
    hover({ "Timber Wolf", "Level 10 Wolf" })
    assert.are.equal("レベル10 Wolf", left(2))
    hover({ "Arcane Wisp", "Level 10 Magic" })
    assert.are.equal("レベル10 Magic", left(2))
    hover({ "Raid Boss", "Level 10 Raid" })
    assert.are.equal("レベル10 Raid", left(2))
  end)
end)
