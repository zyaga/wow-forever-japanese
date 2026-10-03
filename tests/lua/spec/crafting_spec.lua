-- the professions window's crafting page on the Forever (camelot) client: UI/Crafting.lua over a
-- ProfessionsFrame.CraftingPage replayed from the extracted 1.60.1 source: blizzard_professions/
-- blizzard_professionscrafting.lua|xml (ValidateControls' Create / Create All buttons, the link button's tooltip,
-- the static buttons), blizzard_professionstemplates (the recipe list, the schematic form's labels and Init) and
-- the crafting results panel's SetTitle. Recipe, item and profession names and the recipe's verbs stay English.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/Crafting.lua"

local ADDON = "Blizzard_Professions"

local UI = {
  CREATE_PROFESSION = { "Create", "作成" }, CREATE_PROFESSION_ENCHANT = { "Enchant", "エンチャント" },
  PROFESSIONS_CREATE_ALL = { "Create All", "すべて作成" },
  PROFESSIONS_CREATE_ALL_FORMAT = { "%s [%d]", "%s [%d]" },
  GUILD_TRADE_SKILL_VIEW_CRAFTERS = { "View Crafters", "製作者を表示" },
  GUILD_CRAFTERS = { "Guild Crafters", "ギルドの製作者" },
  PROFESSIONS_NO_JOURNAL_ENTRIES = { "There are no results with your current filters.",
    "現在のフィルターに一致する結果はありません。" },
  SEARCH = { "Search", "検索" }, PROFESSIONS_REAGENT_CONTAINER_LABEL = { "Reagents:", "材料:" },
  -- the same English in a spell tooltip means spell components: the crafting label owns its Japanese
  SPELL_REAGENTS = { "Reagents:", "触媒:" },
  PROFESSIONS_OPTIONAL_REAGENT_CONTAINER_LABEL = { "Optional Reagents:", "任意の材料:" },
  PROFESSIONS_REAGENT_CONTAINER_ENCHANT_LABEL = { "Optional Target:", "任意の対象:" },
  PROFESSIONS_CRAFTING_FINISHING_HEADER = { "Finishing Reagents:", "仕上げ材料:" },
  PROFESSIONS_FIRST_CRAFT = { "First Craft", "初回製作" },
  TRADESKILL_NEXT_RANK_HEADER = { "Next Rank", "次のランク" },
  TRADESKILL_UNLEARNED_RECIPE_HEADER = { "Recipe Unlearned", "未習得のレシピ" },
  COOLDOWN_EXPIRES_AT_MIDNIGHT = { "Cooldown resets daily", "クールダウンは毎日リセットされます" },
  TRADESKILL_CHARGES_REMAINING = { "Available Crafts: %i / %i.", "製作可能回数: %i / %i。" },
  PROFESSIONS_CRAFT_OUTPUT_TITLE = { "Crafting Results", "製作結果" },
  LINK_TRADESKILL_TOOLTIP = { "Click here to create a link to your profession.",
    "クリックすると専門技術へのリンクを作成します。" },
  SMELT = { "Smelt", "製錬" }, -- a recipe's verb (client data) that is also a dictionary word here
  PROFESSIONS_CATEGORY_FAVORITE = { "Favorites", "お気に入り" },
  PROFESSIONS_CATEGORY_UNLEARNED = { "Unlearned", "未習得" },
  PROFESSIONS_SKILL_UP_EASY = { "Low chance of gaining skill", "スキル上昇の確率は低い" },
  PROFESSIONS_SKILL_UP_OPTIMAL = { "Guaranteed chance of gaining %d skill ups", "確実にスキルが%d上昇する" },
  PROFESSIONS_ADD_ENCHANT = { "Select Item to Enchant", "エンチャントするアイテムを選択" },
  ENCHANT_TARGET_TOOLTIP_CLICK_TO_ADD = { "Left Click to select an item to Enchant",
    "左クリックでエンチャントするアイテムを選択" },
  PROFESSIONS_FIRST_CRAFT_DESCRIPTION = { "Crafting this recipe for the first time will teach you something new.",
    "このレシピを初めて製作すると、新しいことを覚えます。" },
  PROFESSIONS_REQUIREMENT_TOOL = { "This recipe requires you to have a special tool in your inventory. Higher tier"
    .. " tools typically satisfy lower tier requirements.", "このレシピには特別な道具が必要です。" },
  PROFESSIONS_PICKER_NO_AVAILABLE_REAGENTS = { "You do not own any suitable reagents.", "適した材料を持っていません。" },
  PROFESSIONS_HIDE_UNOWNED_REAGENTS = { "Hide Unavailable", "使用不可を隠す" },
  COOKING = { "Cooking", "料理" }, -- a category name (client data) that is also a dictionary word here
  PROFESSIONS_INSUFFICIENT_REAGENTS = { "You have insufficient reagents.", "材料が足りません。" },
  PROFESSIONS_REQUIRED_TOOLS = { "|cnNORMAL_FONT_COLOR:Requires:|r %s", "|cnNORMAL_FONT_COLOR:必要:|r %s" },
  PROFESSIONS_TRACK_RECIPE = { "Track Recipe", "レシピを追跡" },
  ENCHANT_TARGET_TOOLTIP_CLICK_TO_REPLACE = { "|cnDISABLED_FONT_COLOR:Left Click to replace this item|r",
    "|cnDISABLED_FONT_COLOR:左クリックでこのアイテムを置き換え|r" },
  ENCHANTED_TOOLTIP_LINE = { "Enchanted: %s", "エンチャント済み: %s" },
  -- client-table rows (fingerprints: no global; ADR-042)
  ["TradeSkillCategory:1"] = { "Leather Armor", "革鎧" },
  ["TradeSkillCategory:2"] = { "Bags", "鞄" },
  ["CurrencyCategory:9"] = { "Miscellaneous", "その他" }, -- another family: never a recipe-list header
}

local function en(key) return _G[key] end
local function fs(text) return Stub.fontString(text or "") end

-- C.recipe = { name, verb, enchant, count, unlearned, nextRank, cooldown }
local C = {}

local function loadProfessions()
  Stub.loadedAddons[ADDON] = true
  local frame = CreateFrame("Frame", "ProfessionsFrame")
  local page = CreateFrame("Frame", nil, frame)
  page.name = "CraftingPage"
  frame.CraftingPage = page
  page.CreateButton, page.CreateAllButton = Stub.button(nil, ""), Stub.button(nil, "")
  page.ViewGuildCraftersButton = Stub.button(nil, en("GUILD_TRADE_SKILL_VIEW_CRAFTERS"))
  page.GuildFrame = { Title = fs(en("GUILD_CRAFTERS")) } -- ProfessionsGuildListingMixin:OnLoad
  page.CreateMultipleInputBox = CreateFrame("EditBox", nil, page)
  page.MinimizedSearchBox = CreateFrame("EditBox", nil, page)
  page.RecipeList = CreateFrame("Frame", nil, page)
  page.RecipeList.NoResultsText = fs(en("PROFESSIONS_NO_JOURNAL_ENTRIES"))
  page.RecipeList.SearchBox = CreateFrame("EditBox", nil, page.RecipeList)
  page.RecipeList.SearchBox.Instructions = fs(en("SEARCH"))
  page.RecipeList.ScrollBox = Stub.scrollBox()
  page.LinkButton = CreateFrame("Button", nil, page)
  page.LinkButton:SetScript("OnEnter", function(self) -- ProfessionsLinkButtonMixin:OnEnter (:18–21)
    local tt = _G.GameTooltip
    tt:SetOwner(self, "ANCHOR_RIGHT")
    tt:ClearLines()
    tt:SetText(en("LINK_TRADESKILL_TOOLTIP"))
    tt:Show()
  end)
  local log = CreateFrame("Frame", nil, page) -- ScrollingFlatPanelTemplate: OnLoad → SetTitle(panelTitle)
  log.TitleContainer = { TitleText = fs("") }
  function log.SetTitle(self, t) self.TitleContainer.TitleText.text = t end
  log:SetTitle(en("PROFESSIONS_CRAFT_OUTPUT_TITLE"))
  page.CraftingOutputLog = log

  local form = CreateFrame("Frame", nil, page)
  form.name = "SchematicForm"
  page.SchematicForm = form
  form.Reagents = { Label = fs(en("PROFESSIONS_REAGENT_CONTAINER_LABEL")) }
  form.OptionalReagents = { Label = fs(en("PROFESSIONS_OPTIONAL_REAGENT_CONTAINER_LABEL")) }
  form.FinishingReagents = { Label = fs(en("PROFESSIONS_CRAFTING_FINISHING_HEADER")) }
  form.FirstCraftBonus = { Text = fs(en("PROFESSIONS_FIRST_CRAFT")) }
  form.RecipeSourceButton = { Text = fs("Recipe Unlearned") }
  form.OutputText, form.OutputSubText, form.Description = fs(""), fs(""), fs("")
  form.RecraftingOutputText, form.Cooldown = fs(""), fs("")
  function form.Init(self) -- blizzard_professionsrecipeschematicform.lua:353 (the writes this surface follows)
    local r = C.recipe or {}
    self.OutputText.text = r.name or ""
    self.RecipeSourceButton.Text.text = r.nextRank and en("TRADESKILL_NEXT_RANK_HEADER")
      or en("TRADESKILL_UNLEARNED_RECIPE_HEADER")
    self.OptionalReagents.Label.text = r.enchant and en("PROFESSIONS_REAGENT_CONTAINER_ENCHANT_LABEL")
      or en("PROFESSIONS_OPTIONAL_REAGENT_CONTAINER_LABEL")
    self.Cooldown.text = r.cooldown or ""
    if r.enchant then -- :1177–1188: the enchant target slot, built once, Init → ClearReagent → SetNameText
      if not self.enchantSlot then
        local slot = CreateFrame("Frame", nil, self)
        slot.name = "enchantSlot"
        slot.Name, slot.Button = fs(""), CreateFrame("Button", nil, slot)
        function slot.SetNameText(s2, t) s2.Name:SetText(t) end
        function slot.SetItem(s2, itemName) s2.Name:SetText(itemName) end -- enchantslot.lua:69–75: no SetNameText
        self.enchantSlot = slot
      end
      self.enchantSlot:SetNameText(en("PROFESSIONS_ADD_ENCHANT"))
    end
  end
  function page.ValidateControls(self) -- blizzard_professionscrafting.lua:764–794
    local r = C.recipe or {}
    local fmt = en("PROFESSIONS_CREATE_ALL_FORMAT")
    if type(self.CreateButton) ~= "table" then return end -- a spec moved it: nothing to replay
    if r.enchant then
      self.CreateButton:SetText(en("CREATE_PROFESSION_ENCHANT"))
    else
      self.CreateButton:SetText(r.verb or en("CREATE_PROFESSION"))
    end
    self.CreateAllButton:SetText(fmt:format(r.allVerb or en("PROFESSIONS_CREATE_ALL"), r.count or 0))
  end
  function page.SelectRecipe(self, recipe) -- :466–470
    C.recipe = recipe
    self.SchematicForm:Init(recipe)
    self:ValidateControls()
  end
  return frame
end

describe("the crafting page on the Forever client", function()
  local WFJ, SS

  local function alt(down) Stub.keys.alt = down; WFJ.Modifier.refresh() end
  local function page() return _G.ProfessionsFrame.CraftingPage end
  local function form() return page().SchematicForm end

  local function setup(loadedFirst, shape)
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    SS = WFJ.SurfaceState
    -- The `words` argument kind PROFESSIONS_CREATE_ALL_FORMAT needs in Core/UIStrings.ARGS (harmless when it is
    -- already there). Without it the button keeps "Create All [5]" verbatim.
    WFJ.UIStrings.ARGS.PROFESSIONS_CREATE_ALL_FORMAT = { [1] = "words" }
    H.uiSetup(WFJ, UI)
    C.recipe = nil
    if loadedFirst then
      local frame = loadProfessions()
      if shape then shape(frame) end
      assert.is_true(WFJ.Crafting.init())
    else
      assert.is_false(WFJ.Crafting.init()) -- waits for the addon
      local frame = loadProfessions()
      if shape then shape(frame) end
      assert.are.equal(1, WFJ.LoadOnDemand.loaded(ADDON))
    end
  end

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    _G.ProfessionsFrame = nil
  end)

  for _, order in ipairs({ { true, "loaded before the addon" }, { false, "loaded on demand" } }) do
    describe("Blizzard_Professions " .. order[2], function()
      before_each(function() setup(order[1]) end)

      it("the static labels and the results panel's title render, and come back after a hide", function()
        page():Show()
        assert.are.equal("製作者を表示", page().ViewGuildCraftersButton:GetText())
        assert.are.equal("ギルドの製作者", page().GuildFrame.Title:GetText())
        assert.are.equal("現在のフィルターに一致する結果はありません。", page().RecipeList.NoResultsText:GetText())
        assert.are.equal("検索", page().RecipeList.SearchBox.Instructions:GetText())
        assert.are.equal("材料:", form().Reagents.Label:GetText())
        assert.are.equal("SPELL_REAGENTS", (WFJ.UIIndex:match("Reagents:")))
        assert.are.equal("仕上げ材料:", form().FinishingReagents.Label:GetText())
        assert.are.equal("初回製作", form().FirstCraftBonus.Text:GetText())
        local log = page().CraftingOutputLog
        assert.are.equal("製作結果", log.TitleContainer.TitleText:GetText())
        log:SetTitle(_G.PROFESSIONS_CRAFT_OUTPUT_TITLE) -- a second SetTitle keeps the Japanese
        assert.are.equal("製作結果", log.TitleContainer.TitleText:GetText())
        alt(true)
        assert.are.equal("Reagents:", form().Reagents.Label:GetText())
        alt(false)
        page():Hide()
        assert.are.equal("Reagents:", form().Reagents.Label:GetText())
        assert.are.equal(0, SS.count("crafting"))
        page():Show()
        assert.are.equal("材料:", form().Reagents.Label:GetText())
      end)

      it("the writer-hooked words follow ValidateControls and the form's Init; the recipe's name and its verb stay"
        .. " English", function()
        page():Show()
        page():SelectRecipe({ name = "Search", nextRank = true, count = 5, cooldown = "Cooldown resets daily" })
        assert.are.equal("作成", page().CreateButton:GetText())
        -- "%s [%d]" around PROFESSIONS_CREATE_ALL: the first argument is a `words` capture (see setup)
        assert.are.equal("すべて作成 [5]", page().CreateAllButton:GetText())
        assert.are.equal("次のランク", form().RecipeSourceButton.Text:GetText())
        assert.are.equal("任意の材料:", form().OptionalReagents.Label:GetText())
        assert.are.equal("クールダウンは毎日リセットされます", form().Cooldown:GetText())
        assert.are.equal("Search", form().OutputText:GetText()) -- a recipe whose name is a dictionary word
        assert.is_true(WFJ.Labels.forbidden(form().OutputText))
        page():SelectRecipe({ name = "Enchant Bracer", enchant = true, count = 1,
          cooldown = "Available Crafts: 2 / 3." })
        assert.are.equal("エンチャント", page().CreateButton:GetText())
        assert.are.equal("任意の対象:", form().OptionalReagents.Label:GetText())
        assert.are.equal("未習得のレシピ", form().RecipeSourceButton.Text:GetText())
        assert.are.equal("製作可能回数: 2 / 3。", form().Cooldown:GetText())
        page():SelectRecipe({ name = "Copper Bar", verb = "Smelt", allVerb = "Smelt All", count = 4,
          cooldown = "Cooldown remaining: 3 Hr" })
        assert.are.equal("Smelt", page().CreateButton:GetText()) -- client data, a dictionary word here
        assert.are.equal("Smelt All [4]", page().CreateAllButton:GetText()) -- client data: kept as captured
        assert.are.equal("Cooldown remaining: 3 Hr", form().Cooldown:GetText()) -- joins a duration: English
      end)

      it("the link button's tooltip translates; the EditBoxes are never ours", function()
        local link = page().LinkButton
        link.scripts.OnEnter(link)
        assert.are.equal("クリックすると専門技術へのリンクを作成します。", _G.GameTooltipTextLeft1:GetText())
        assert.is_true(WFJ.Labels.forbidden(page().RecipeList.SearchBox))
        assert.is_true(WFJ.Labels.forbidden(page().CreateMultipleInputBox))
        assert.is_true(WFJ.Labels.forbidden(page().MinimizedSearchBox))
      end)

      it("hooks install once", function()
        assert.is_false(WFJ.Crafting.setup())
        assert.are.equal(1, #Stub.hooks["CraftingPage:ValidateControls"])
        assert.are.equal(1, #Stub.hooks["SchematicForm:Init"])
      end)
    end)
  end

  it("client names bound to the wrong type degrade to untouched English with no error", function()
    assert.has_no.errors(function()
      setup(true, function(frame)
        local p = frame.CraftingPage
        p.CreateButton, p.RecipeList, p.CraftingOutputLog, p.LinkButton = "moved", "moved", "moved", "moved"
        p.SchematicForm.Reagents = "moved"
        p.SchematicForm.Init = "moved"
      end)
      page():Show()
      page():ValidateControls()
      page():Hide()
    end)
    assert.is_nil(Stub.hooks["SchematicForm:Init"])
    page():Show()
    assert.are.equal("仕上げ材料:", form().FinishingReagents.Label:GetText()) -- the rest still renders
    _G.ProfessionsFrame = nil
    assert.has_no.errors(function() setup(true, function(frame) frame.CraftingPage = "moved" end) end)
    assert.is_false(WFJ.Crafting.setup())
  end)

  it("without the frame init returns false and touches nothing", function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    assert.is_false(WFJ.Crafting.init())
    assert.is_false(WFJ.Crafting.setup())
    assert.are.equal(0, WFJ.SurfaceState.count("crafting"))
  end)
end)

-- the recipe list's rows (pooled, keyed by widget), the enchant target slot and the form's help tooltips
-- [blizzard_professionsrecipelist.lua:21–86, 207, 282–316; recipelist.xml:98; blizzard_professions.lua:844;
-- blizzard_professionsrecipeenchantslot.lua:8, 65, 72; schematicform.lua:171–175, 1177–1244, 1536–1544].
describe("the crafting page on the Forever client: list rows, enchant slot, help tooltips", function()
  local WFJ

  local function alt(down) Stub.keys.alt = down; WFJ.Modifier.refresh() end
  local function page() return _G.ProfessionsFrame.CraftingPage end
  local function form() return page().SchematicForm end
  local function box() return page().RecipeList.ScrollBox end
  local function node(data) return { GetData = function() return data end } end
  local function category(name)
    local row = CreateFrame("Button")
    row.ButtonText = fs("")
    box():initFrame(row, node({ categoryInfo = { name = name } }), function(r) r.ButtonText:SetText(name) end)
    return row
  end
  local function hover(owner, text)
    local tt = _G.GameTooltip
    tt:SetOwner(owner, "ANCHOR_RIGHT")
    tt:ClearLines()
    tt:AddLine(text)
    tt:Show()
    return _G.GameTooltipTextLeft1:GetText()
  end

  local function setup(loadedFirst, shape)
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    C.recipe = nil
    if loadedFirst then
      local frame = loadProfessions()
      if shape then shape(frame) end
      WFJ.Crafting.init()
    else
      WFJ.Crafting.init()
      local frame = loadProfessions()
      if shape then shape(frame) end
      WFJ.LoadOnDemand.loaded(ADDON)
    end
  end

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    _G.ProfessionsFrame = nil
  end)

  for _, order in ipairs({ { true, "loaded before the addon" }, { false, "loaded on demand" } }) do
    it("Favorites and Unlearned render on their rows; every other category and every recipe name stay English ("
      .. order[2] .. ")", function()
      setup(order[1])
      page():Show()
      assert.are.equal(1, #box().initCallbacks)
      local fav, cooking = category("Favorites"), category("Cooking")
      assert.are.equal("お気に入り", fav.ButtonText:GetText())
      assert.are.equal("Cooking", cooking.ButtonText:GetText()) -- client data, a dictionary word here
      local divider = CreateFrame("Frame")
      divider.Label = fs(_G.PROFESSIONS_CATEGORY_UNLEARNED)
      box():initFrame(divider, node({ isDivider = true, dividerHeight = 30 }))
      assert.are.equal("未習得", divider.Label:GetText())
      local recipe = CreateFrame("Button")
      recipe.Label, recipe.SkillUps = fs(""), CreateFrame("Button", nil, recipe)
      box():initFrame(recipe, node({ recipeInfo = { name = "Favorites" } }),
        function(r) r.Label:SetText("Favorites") end)
      assert.are.equal("Favorites", recipe.Label:GetText())
      assert.is_true(WFJ.Labels.forbidden(recipe.Label))
      assert.are.equal("確実にスキルが3上昇する", hover(recipe.SkillUps, "Guaranteed chance of gaining 3 skill ups"))
      assert.are.equal("スキル上昇の確率は低い", hover(recipe.SkillUps, "Low chance of gaining skill"))
      alt(true)
      assert.are.equal("Favorites", fav.ButtonText:GetText())
      alt(false)
      assert.are.equal("お気に入り", fav.ButtonText:GetText())
      -- a pooled row reused for another category: the record follows the widget and drops
      box():initFrame(fav, node({ categoryInfo = { name = "Axes" } }), function(r) r.ButtonText:SetText("Axes") end)
      assert.are.equal("Axes", fav.ButtonText:GetText())
      page():Hide()
      assert.are.equal("Unlearned", divider.Label:GetText())
    end)
  end

  it("a category header with a TradeSkillCategory row shows its Japanese; Alt shows the English; a profession's name,"
    .. " another family's word and a reused row stay English", function()
    setup(true)
    page():Show()
    local leather, bags = category("Leather Armor"), category("Bags")
    local profession, misc = category("Leatherworking"), category("Miscellaneous")
    assert.are.equal("革鎧", leather.ButtonText:GetText())
    assert.are.equal("鞄", bags.ButtonText:GetText())
    assert.are.equal("Leatherworking", profession.ButtonText:GetText()) -- a profession's name has no row
    assert.are.equal("Miscellaneous", misc.ButtonText:GetText())
    assert.is_nil(WFJ.UIIndex:match("Leather Armor")) -- the family only where the header names it
    alt(true)
    assert.are.equal("Leather Armor", leather.ButtonText:GetText())
    alt(false)
    assert.are.equal("革鎧", leather.ButtonText:GetText())
    box():initFrame(leather, node({ categoryInfo = { name = "Shields" } }),
      function(r) r.ButtonText:SetText("Shields") end)
    assert.are.equal("Shields", leather.ButtonText:GetText())
    alt(true)
    alt(false)
    assert.are.equal("Shields", leather.ButtonText:GetText())
  end)

  it("the enchant slot's placeholder renders after Init and after ClearReagent; an allocated item's name stays"
    .. " English", function()
    setup(true)
    page():Show()
    page():SelectRecipe({ name = "Enchant Bracer - Minor Health", enchant = true, count = 1 })
    local slot = form().enchantSlot
    assert.are.equal("エンチャントするアイテムを選択", slot.Name:GetText())
    assert.are.equal("左クリックでエンチャントするアイテムを選択",
      hover(slot.Button, "Left Click to select an item to Enchant"))
    slot:SetItem("Select Item to Enchant") -- an item whose name reads as the placeholder: SetItem is not followed
    alt(true)
    alt(false)
    assert.are.equal("Select Item to Enchant", slot.Name:GetText())
    slot:SetNameText(_G.PROFESSIONS_ADD_ENCHANT) -- ClearReagent
    assert.are.equal("エンチャントするアイテムを選択", slot.Name:GetText())
    page():SelectRecipe({ name = "Enchant Boots", enchant = true, count = 1 }) -- the slot is reused: hooked once
    assert.are.equal(1, #Stub.hooks["enchantSlot:SetNameText"])
  end)

  it("the item picker flyout's two fixed words render when it opens from the form", function()
    local flyout
    setup(true, function()
      -- blizzard_professionsrecipeflyoutinstance.lua:1, 12–22: one unnamed flyout, re-parented to the owner on open
      flyout = CreateFrame("Frame")
      flyout.Text = fs(_G.PROFESSIONS_PICKER_NO_AVAILABLE_REAGENTS)
      flyout.HideUnownedCheckbox = { text = fs(_G.PROFESSIONS_HIDE_UNOWNED_REAGENTS) }
      _G.OpenProfessionsItemFlyout = function(_, owner)
        owner.children = { flyout }
        return flyout
      end
    end)
    form().GetChildren = function(self) return unpack(self.children or {}) end
    _G.OpenProfessionsItemFlyout(form(), form(), {})
    assert.are.equal("適した材料を持っていません。", flyout.Text:GetText())
    assert.are.equal("使用不可を隠す", flyout.HideUnownedCheckbox.text:GetText())
    assert.has_no.errors(function()
      WFJ.Crafting.onFlyout(nil, "moved")
      WFJ.Crafting.onFlyout(nil, { GetChildren = function() return "moved", { HideUnownedCheckbox = "moved" } end })
    end)
    _G.OpenProfessionsItemFlyout = nil
  end)

  it("the first-craft and the required-tool tooltips render; another owner's line of the same text does not",
    function()
    setup(true)
    local text = _G.PROFESSIONS_FIRST_CRAFT_DESCRIPTION
    assert.are.equal("このレシピを初めて製作すると、新しいことを覚えます。", hover(form().FirstCraftBonus, text))
    assert.are.equal("このレシピには特別な道具が必要です。", hover(form(), _G.PROFESSIONS_REQUIREMENT_TOOL))
    assert.are.equal(text, hover(form(), text)) -- the form's `only` is the two requirement lines
  end)

  it("a moved list, a missing ScrollUtil or rows of the wrong shape degrade to English with no error", function()
    assert.has_no.errors(function()
      setup(true, function(frame) frame.CraftingPage.RecipeList.ScrollBox = "moved" end)
    end)
    _G.ProfessionsFrame = nil
    assert.has_no.errors(function() setup(true, function() _G.ScrollUtil = "moved" end) end)
    _G.ProfessionsFrame = nil
    setup(true)
    assert.has_no.errors(function()
      WFJ.Crafting.onListRow(WFJ.Crafting, "moved")
      WFJ.Crafting.onListRow(WFJ.Crafting, { ButtonText = "moved" }, node({ categoryInfo = {} }))
      WFJ.Crafting.onListRow({ Label = "moved" }, { isDivider = true })
      WFJ.Crafting.onListRow({ Label = "moved", SkillUps = "moved" }, { recipeInfo = {} })
      WFJ.Crafting.onListRow({}, "moved")
      form().enchantSlot = "moved"
      WFJ.Crafting.onFormInit()
      form().enchantSlot = { Name = "moved", SetNameText = "moved", Button = "moved" }
      WFJ.Crafting.onFormInit()
    end)
  end)
  it("the create buttons' disabled reason, the required tools, Track Recipe, the enchant slot's replace hint"
    .. " and an enchant's output line; names kept, Alt shows English", function()
    local tools = fs("")
    setup(true, function(frame) -- the form's Update runs UpdateRequiredTools (schematicform.lua:258–266)
      local f = frame.CraftingPage.SchematicForm
      f.RequiredTools = tools
      f.TrackRecipeCheckbox = { Text = fs("|cffaaaaaa" .. _G.PROFESSIONS_TRACK_RECIPE .. "|r") }
      function f.Update(self) self.RequiredTools:SetText(_G.PROFESSIONS_REQUIRED_TOOLS:format("Blacksmith Hammer")) end
    end)
    page():Show()
    local red = "|cffff2020" .. _G.PROFESSIONS_INSUFFICIENT_REAGENTS .. "|r" -- SetCreateButtonTooltipText (:638–643)
    local tt = _G.GameTooltip
    tt:SetOwner(page().CreateButton)
    tt:SetText(red)
    tt:Show()
    assert.are.equal("|cffff2020材料が足りません。|r", _G.GameTooltipTextLeft1:GetText())
    form():Update()
    assert.are.equal("|cnNORMAL_FONT_COLOR:必要:|r Blacksmith Hammer", tools:GetText())
    assert.are.equal("|cffaaaaaaレシピを追跡|r", form().TrackRecipeCheckbox.Text:GetText())
    alt(true)
    assert.are.equal("|cnNORMAL_FONT_COLOR:Requires:|r Blacksmith Hammer", tools:GetText())
    alt(false)
    C.recipe = { name = "Enchant Bracer", enchant = true }
    form():Init(C.recipe)
    local button = form().enchantSlot.Button
    tt:SetOwner(button)
    Stub.setItemTooltip(tt, "|Hitem:2:0:0:0|h[Cooking]|h", { "Cooking", "Wrist" })
    tt:AddLine(" ")
    tt:AddLine(_G.ENCHANT_TARGET_TOOLTIP_CLICK_TO_REPLACE)
    tt:Show()
    assert.are.equal("Cooking", _G.GameTooltipTextLeft1:GetText()) -- the item's name: untouched
    assert.are.equal("|cnDISABLED_FONT_COLOR:左クリックでこのアイテムを置き換え|r", _G.GameTooltipTextLeft4:GetText())
    local element = { ItemContainer = { Text = fs("") } }
    WFJ.Crafting.onLogElement(WFJ.Crafting, element)
    element.ItemContainer.Text:SetText(_G.ENCHANTED_TOOLTIP_LINE:format("Cooking")) -- the item loads later
    assert.are.equal("エンチャント済み: Cooking", element.ItemContainer.Text:GetText())
    element.ItemContainer.Text:SetText("Cooking") -- a crafted item's plain name
    assert.are.equal("Cooking", element.ItemContainer.Text:GetText())
  end)
end)
