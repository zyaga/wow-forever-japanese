-- The client-table words that sit inside a sentence the dictionary already translates (ADR-051): a pet's diet
-- (PetFood, a comma-separated list), the rest state (RestState) and "Requires <weapon kind>" (ItemSubClassMask).
-- Each is shown in Japanese only when it is that family's row; anything else in the slot is kept as written.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local UI = {
  ["PetFood:1"] = { "Meat", "肉" },
  ["PetFood:2"] = { "Fish", "魚" },
  ["RestState:1"] = { "Rested", "休息" },
  ["ItemSubClassMask:1"] = { "Melee Weapon", "近接武器" },
  PET_DIET_TEMPLATE = { "|cffffd200Diet:|r %s", "|cffffd200食性:|r %s" },
  EXHAUST_TOOLTIP1 = { "%s\n%d%% of normal experience\ngained from monsters.", "%s\nモンスターから得る経験値が通常の%d%%" },
  SPELL_EQUIPPED_ITEM = { "Requires %s", "%sが必要" },
  SPELL_REQUIRED_FORM = { "Requires %s", "%sが必要" },
}

describe("served-text family words inside a translated sentence", function()
  local WFJ, index
  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    WFJ = H.loadChunks(H.UI_FILES)
    H.uiSetup(WFJ, UI)
    index = WFJ.UIIndex
  end)
  after_each(function() H.uiTeardown() end)

  local function japanese(line, only)
    local key, args
    if only then key, args = index:matchOnly(line, only) else key, args = index:match(line) end
    assert.is_not_nil(key, line)
    return index:fill(index.rows[key][1], args)
  end

  it("a pet's diet: each food word that is a PetFood row is Japanese, the rest kept, the commas kept", function()
    assert.are.equal("|cffffd200食性:|r 肉, 魚", japanese("|cffffd200Diet:|r Meat, Fish"))
    assert.are.equal("|cffffd200食性:|r 肉, Mystery Bread", japanese("|cffffd200Diet:|r Meat, Mystery Bread"))
    assert.are.equal("|cffffd200食性:|r 魚", japanese("|cffffd200Diet:|r Fish"))
  end)

  it("the rest state is a RestState row's Japanese, else as written", function()
    local only = { "EXHAUST_TOOLTIP1" }
    assert.are.equal("休息\nモンスターから得る経験値が通常の200%",
      japanese("Rested\n200% of normal experience\ngained from monsters.", only))
    assert.are.equal("Normal\nモンスターから得る経験値が通常の100%",
      japanese("Normal\n100% of normal experience\ngained from monsters.", only))
  end)

  it("Requires: a weapon kind is Japanese; a form or an item name stays English", function()
    assert.are.equal("近接武器が必要", japanese("Requires Melee Weapon"))
    assert.are.equal("Cat Formが必要", japanese("Requires Cat Form"))
    assert.are.equal("Bows, Crossbowsが必要", japanese("Requires Bows, Crossbows"))
  end)

  it("the family words are never matched on their own by the open match", function()
    assert.is_nil(index:match("Fish"))
    assert.is_nil(index:match("Melee Weapon"))
    assert.is_true(WFJ.UIStrings.isRestrictedKey("PetFood:2"))
    assert.is_true(WFJ.UIStrings.isRestrictedKey("CriteriaText:1"))
    assert.is_true(WFJ.UIStrings.isFingerprintKey("MailBody:1"))
  end)
end)
