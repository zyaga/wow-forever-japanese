-- The hunter pet happiness tooltip on Forever: UI/PetHappiness.lua over the three camelot frames that
-- inherit PetFrameHappinessTemplate, with the tooltip PetHappinessIndicatorMixin:OnEnter builds
-- (blizzard_framexml/pethappiness.lua:76–91). The pet's food types stay English inside the diet line.
local R = require("tests.lua.spec.stub_retail")

local UI = {
  PET_HAPPINESS1 = { "Unhappy", "不満" }, PET_HAPPINESS3 = { "Happy", "満足" },
  PET_DAMAGE_PERCENTAGE = { "Causes %d%% of normal damage", "通常の%d%%のダメージを与える" },
  GAINING_LOYALTY = { "Gaining Loyalty", "忠誠度上昇中" }, NONE = { "None", "なし" },
  PET_DIET_TEMPLATE = { "|cffffd200Diet:|r %s", "|cffffd200食性:|r %s" },
  -- a dictionary word that is also a food type
  FISH = { "Fish", "魚" },
}
local GLOBALS = { "PetFrameHappiness", "PetPaperDollPetHappinessInfo", "PetStableFrame" }

local function build()
  local pet = CreateFrame("Frame", "PetFrameHappiness")
  CreateFrame("Frame", "PetPaperDollPetHappinessInfo")
  local stable = CreateFrame("Frame", "PetStableFrame")
  R.tree(stable, { ["modelScene.diet"] = { frame = true } })
  return pet
end

local function onEnter(owner, lines) return R.tooltip(owner, lines) end

R.suite(getfenv(1), {
  title = "the pet happiness tooltip on Forever", module = "PetHappiness", file = "UI/PetHappiness.lua",
  root = "PetFrameHappiness", globals = GLOBALS, ui = UI, build = build,
  args = { PET_DIET_TEMPLATE = { [1] = "text" } },
  cases = {
    { "the pet frame's tooltip is Japanese; Alt shows English", function(frame, WFJ)
      onEnter(frame, { "Happy", "Causes 125% of normal damage", "Gaining Loyalty", "|cffffd200Diet:|r None" })
      assert.are.equal("満足", _G.GameTooltipTextLeft1:GetText())
      assert.are.equal("通常の125%のダメージを与える", _G.GameTooltipTextLeft2:GetText())
      assert.are.equal("忠誠度上昇中", _G.GameTooltipTextLeft3:GetText())
      R.alt(WFJ, true)
      assert.are.equal("Happy", _G.GameTooltipTextLeft1:GetText())
      R.alt(WFJ, false)
    end },
    { "the character window's and the stable's indicators are owners too", function()
      onEnter(_G.PetPaperDollPetHappinessInfo, { "Unhappy" })
      assert.are.equal("不満", _G.GameTooltipTextLeft1:GetText())
      onEnter(_G.PetStableFrame.modelScene.diet, { "Happy", "|cffffd200Diet:|r Meat, Fish" })
      assert.are.equal("満足", _G.GameTooltipTextLeft1:GetText())
    end },
  },
  name = function(frame)
    onEnter(frame, { "Happy", "|cffffd200Diet:|r Meat, Fish" })
    assert.are.equal("|cffffd200食性:|r Meat, Fish", _G.GameTooltipTextLeft2:GetText())
    onEnter(frame, { "Fish" }) -- a food type is never a line of its own here
    assert.are.equal("Fish", _G.GameTooltipTextLeft1:GetText())
  end,
  wrong = function()
    _G.PetPaperDollPetHappinessInfo = "x"
    _G.PetStableFrame.modelScene = 3
    return function(f)
      onEnter(f, { "Unhappy" })
      assert.are.equal("不満", _G.GameTooltipTextLeft1:GetText())
    end
  end,
})
