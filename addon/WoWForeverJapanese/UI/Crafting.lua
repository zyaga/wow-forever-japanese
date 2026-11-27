-- UI/Crafting.lua: the professions window's crafting page on Forever (surface "crafting", area "ui",
-- ADR-016, ADR-029): the recipe list and the recipe form of ProfessionsFrame.CraftingPage.
-- Entry points on camelot: TRADE_SKILL_SHOW → GameEvent.HandleTradeSkillShow → ShowProfessionsFrame()
-- (blizzard_game/mainline/eventrouting.lua:107, eventimplementation.lua:475–477), a profession side tab
-- (ProfessionsFrameRightTabMixin:OnClick, blizzard_professionstemplates/blizzard_professionstemplates.lua:982–989)
-- and an item's OpenProfessionUIToSkillLine (blizzard_professions_bootstrap.lua:13–22). camelot's ProfessionsFrame
-- has two pages only, CraftingPage and BookPage (camelot/blizzard_professionsframe.xml:66–79): the specializations
-- and crafter-orders pages are never built. Blizzard_Professions is load-on-demand (WFJ.LoadOnDemand.when).
-- Every widget is parentKey-only (dotted Compat names). Writers, each a method looked up on the instance:
--   CraftingPage:ValidateControls (blizzard_professionscrafting.lua:719–840; called :122, 128, 309, 345, 470, 995)
--     → CreateButton  SetTextToFit(CREATE_PROFESSION | CREATE_PROFESSION_ENCHANT | PROFESSIONS_CRAFTING_RECRAFT, or
--                     the recipe's abilityVerb / alternateVerb: client data, left English by `only`) (:764–785);
--     → CreateAllButton  PROFESSIONS_CREATE_ALL_FORMAT "%s [%d]" around PROFESSIONS_CREATE_ALL /
--                     PROFESSIONS_ENCHANT_ALL (or abilityAllVerb, client data) (:767, 787–794);
--   SchematicForm:Init (blizzard_professionsrecipeschematicform.lua:353; called from the page :466, 990) →
--     RecipeSourceButton.Text  TRADESKILL_NEXT_RANK_HEADER | TRADESKILL_UNLEARNED_RECIPE_HEADER (:641–645),
--     OptionalReagents.Label   PROFESSIONS_REAGENT_CONTAINER_ENCHANT_LABEL | PROFESSIONS_OPTIONAL_REAGENT_
--                              CONTAINER_LABEL (:1261–1264),
--     Cooldown                 COOLDOWN_EXPIRES_AT_MIDNIGHT | TRADESKILL_CHARGES_REMAINING (:566, 585); the other
--                              forms join a formatted duration and stay English.
-- Static (XML text / KeyValue, written at load): ViewGuildCraftersButton (blizzard_professionscrafting.xml:220),
--   the guild crafters list's title (GuildFrame.Title ← GUILD_CRAFTERS, blizzard_professionsguildmemberlist.lua:21),
--   RecipeList.NoResultsText and the search box's placeholder (blizzard_professionsrecipelist.xml:13, 53),
--   Reagents / FinishingReagents labels (labelText, ProfessionsReagentContainerMixin:OnLoad,
--   blizzard_professionstemplates.lua:186–192; schematicform.xml:66–88), FirstCraftBonus.Text (xml:177), and the
--   crafting results panel's title: ScrollingFlatPanelMixin:OnLoad → SetTitle(panelTitle =
--   PROFESSIONS_CRAFT_OUTPUT_TITLE) (blizzard_uipanels_game/mainline/scrollingflatpanel.lua:6;
--   blizzard_professionscraftingoutputlog.xml:136), through Labels.title.
-- The recipe list's rows (a ScrollBox tree of pooled frames, blizzard_professionsrecipelist.lua:21–86), followed with
--   ScrollUtil.AddInitializedFrameCallback and keyed by the row widget: a category row's header (ButtonText, written
--   by ProfessionsRecipeListCategoryMixin:Init → SetHeaderText(categoryInfo.name), :207; listtemplates.lua:21, 57)
--   is C_TradeSkillUI.GetCategoryInfo's name, a TradeSkillCategory row (TradeSkillCategory.Name_lang, ADR-042), or
--   the favourites category, PROFESSIONS_CATEGORY_FAVORITE (blizzard_professions.lua:844): those are the keys it may
--   show. A profession's own name has no row there and stays English. The unlearned divider's Label is XML text
--   PROFESSIONS_CATEGORY_UNLEARNED (recipelist.xml:98); a recipe row's Label is the recipe's name (a name: its
--   Japanese while names are on, never a dictionary word), and
--   its SkillUps icon owns a tooltip of one line, PROFESSIONS_SKILL_UP_EASY / _MEDIUM / _OPTIMAL
--   (recipelist.lua:282–316), registered per row.
-- The enchant target slot (form.enchantSlot, built for an Enchant-type recipe by the form's Init,
--   schematicform.lua:1177–1188): its Name is SetNameText(PROFESSIONS_ADD_ENCHANT) at Init and ClearReagent
--   (enchantslot.lua:8, 65), shown after the form's Init and after each SetNameText (hooked on the instance); an
--   allocated item's name replaces it (SetItem, :72) and the stale record is dropped. Its button's tooltip is
--   ENCHANT_TARGET_TOOLTIP_CLICK_TO_ADD (:1240) when empty, the item's own tooltip once filled.
-- The item picker flyout (one unnamed frame, blizzard_professionsrecipeflyoutinstance.lua:1): OpenProfessionsItemFlyout
--   (anchorTo, owner, behavior) re-parents it to the form (:12–22); it opens from the enchant slot (schematicform.lua:
--   1201) and the optional-reagent slots. Its OnLoad wrote Text = PROFESSIONS_PICKER_NO_AVAILABLE_REAGENTS (shown
--   when nothing qualifies) and HideUnownedCheckbox.text = PROFESSIONS_HIDE_UNOWNED_REAGENTS (recipeflyout.lua:
--   165–167). The global is post-hooked; the flyout is found among the owner's children by those two fields.
-- Help tooltips: LinkButton → GameTooltip:SetText(LINK_TRADESKILL_TOOLTIP) (blizzard_professionscrafting.lua:18–21);
--   FirstCraftBonus → PROFESSIONS_FIRST_CRAFT_DESCRIPTION (schematicform.lua:171–175); the form itself owns the
--   required-tool / crafting-station hyperlink tooltip, PROFESSIONS_REQUIREMENT_TOOL | _TABLE (:1536–1544). Each
--   owner is restricted to its keys.
-- Composites (ADR-038):
--   the create buttons' disabled reason: SetCreateButtonTooltipText writes RED(PROFESSIONS_RECIPE_COOLDOWN |
--     PROFESSIONS_INSUFFICIENT_REAGENTS | PROFESSIONS_MISSING_REQUIREMENT) into CreateButton / CreateAllButton
--     .tooltipText (blizzard_professionscrafting.lua:638–653, 811–813), shown by the button's OnEnter (the template is
--     not in the extract: an in-game check); both buttons are owners restricted to those keys (`wrapped`);
--   the required tools line: form.UpdateRequiredTools, set per recipe by Init and run by form:Update
--     (schematicform.lua:258–266, 735–752): RequiredTools / RecraftingRequiredTools = PROFESSIONS_REQUIRED_TOOLS with
--     the tool list kept as written (`text`), shown after Update and Init;
--   TrackRecipeCheckbox.Text = LIGHTGRAY(PROFESSIONS_TRACK_RECIPE) (schematicform.lua:125, `wrapped`);
--   the enchant slot's filled tooltip: SetItemByGUID, then ENCHANT_TARGET_TOOLTIP_CLICK_TO_REPLACE appended
--     (schematicform.lua:1225–1243); an item tooltip, so after GameTooltip:Show with the slot's button as owner the
--     appended line is shown by HelpTooltip.appended (itemAppended), the item's lines left to UI/Tooltip;
--   the output log: an enchant result's ItemContainer.Text = ENCHANTED_TOOLTIP_LINE with the item's name kept, written
--     when the item loads (craftingoutputlog.lua:29–40); each pooled element's Text is followed (SetText post-hook).
-- The recipe's description (Description, written by UpdateRecipeDescription from the recipe spell's description,
--   schematicform.lua:1466–1490) shows that spell's description Japanese, as its tooltip does (kind
--   spell.description, numbers from the live English); an embedded icon in the English is not carried over.
-- The recipe list's Filter button (RecipeList.FilterDropdown, WowStyle1FilterDropdownTemplate, recipelist.xml:32)
--   shows FILTER, re-shown after each UpdateText.
-- The output item's name (OutputText, on this page's form and the inspect window's): UpdateOutputItem writes the
--   item's name in its quality colour (or the recipe's name) with SetTextToFit, which writes the text, measures it and
--   sizes the FontString to it, then sets the output icon (blizzard_professionsrecipeschematicform.lua:349–359,
--   1358–1388). It is called as self:UpdateOutputItem() (:683, 1368, 1435), so a post-hook on each form runs after
--   that pass: the client measures only its own English. While names are on the name shows its Japanese with its
--   colour code kept (UI/NameLabels.wrapped), and the FontString is sized again for the text shown, the way
--   SetTextToFit sized it, from the form's own width rules (:1349–1356). Nothing protected follows: the create
--   buttons are plain buttons made with CreateFrame (blizzard_professionscrafting.lua:249–258) and crafting is
--   C_TradeSkillUI.CraftRecipe, documented with no HasRestrictions flag (tradeskilluidocumentation.lua:76–78).
-- Never touched: the EditBoxes (both search boxes, the create-count box), the recipe's sub text (OutputSubText),
--   RecraftingOutputText (PROFESSIONS_CRAFTING_FORM_RECRAFTING_HEADER around the coloured name, or
--   PROFESSIONS_CRAFTING_RECRAFTING: recrafting lines Forever never shows, pipeline/ui_exclusions.txt), the list's
--   recipe names (client data: blizzard_professionsrecipelist.lua:247) and any category name with no
--   TradeSkillCategory row, the rank bar (joins the profession name). The window title is UI/Professions' (the same
--   frame; a profession's name here).
local _, WFJ = ...
local Crafting = {}
WFJ.Crafting = Crafting

local SURFACE = "crafting"
Crafting.SURFACE = SURFACE
local Compat = WFJ.Compat

local ADDON = "Blizzard_Professions"
local PAGE = "ProfessionsFrame.CraftingPage"
local FORM = PAGE .. ".SchematicForm"
-- the recipe a link in chat opens (InspectRecipeFrame:Open, blizzard_professionstemplates/
-- blizzard_professions.lua:664): the same schematic form on its own window
-- (blizzard_professionsinspectrecipe.xml:5-9)
local INSPECT = "InspectRecipeFrame.SchematicForm"

Crafting.NEVER_TOUCH = { PAGE .. ".RecipeList.SearchBox", PAGE .. ".MinimizedSearchBox",
  PAGE .. ".CreateMultipleInputBox", FORM .. ".OutputText", FORM .. ".OutputSubText", FORM .. ".RecraftingOutputText" }

local CANDIDATES = {
  page = { PAGE }, form = { FORM }, outputLog = { PAGE .. ".CraftingOutputLog" },
  linkButton = { PAGE .. ".LinkButton" },
  createButton = { PAGE .. ".CreateButton" }, createAllButton = { PAGE .. ".CreateAllButton" },
  guildCrafters = { PAGE .. ".ViewGuildCraftersButton" }, guildTitle = { PAGE .. ".GuildFrame.Title" },
  noResults = { PAGE .. ".RecipeList.NoResultsText" }, filter = { PAGE .. ".RecipeList.FilterDropdown" },
  searchHint = { PAGE .. ".RecipeList.SearchBox.Instructions" },
  reagents = { FORM .. ".Reagents.Label" }, optionalReagents = { FORM .. ".OptionalReagents.Label" },
  finishingReagents = { FORM .. ".FinishingReagents.Label" }, firstCraft = { FORM .. ".FirstCraftBonus.Text" },
  recipeSource = { FORM .. ".RecipeSourceButton.Text" }, cooldown = { FORM .. ".Cooldown" },
  firstCraftBonus = { FORM .. ".FirstCraftBonus" },
  listBox = { PAGE .. ".RecipeList.ScrollBox" }, scrollUtil = { "ScrollUtil" },
  openFlyout = { "OpenProfessionsItemFlyout" },
  requiredTools = { FORM .. ".RequiredTools" }, recraftTools = { FORM .. ".RecraftingRequiredTools" },
  trackRecipe = { FORM .. ".TrackRecipeCheckbox.Text" }, outputBox = { PAGE .. ".CraftingOutputLog.ScrollBox" },
  tooltip = { "GameTooltip" },
  inspectForm = { INSPECT }, inspectReagents = { INSPECT .. ".Reagents.Label" },
  inspectOptional = { INSPECT .. ".OptionalReagents.Label" },
  inspectFinishing = { INSPECT .. ".FinishingReagents.Label" },
  inspectFirstCraft = { INSPECT .. ".FirstCraftBonus.Text" },
  inspectSource = { INSPECT .. ".RecipeSourceButton.Text" }, inspectTrack = { INSPECT .. ".TrackRecipeCheckbox.Text" },
}

local function only(...) return { only = { ... } } end
-- a category header: Favorites, or the category's TradeSkillCategory row (Labels caches the set per index)
local function category() return WFJ.Labels.familiesWith({ "PROFESSIONS_CATEGORY_FAVORITE" }, "TradeSkillCategory") end
local CREATE = only("CREATE_PROFESSION", "CREATE_PROFESSION_ENCHANT", "PROFESSIONS_CRAFTING_RECRAFT")
local CREATE_ALL = only("PROFESSIONS_CREATE_ALL_FORMAT")
local OUTPUT_TITLE = only("PROFESSIONS_CRAFT_OUTPUT_TITLE")
local LINK = only("LINK_TRADESKILL_TOOLTIP")
local UNLEARNED = only("PROFESSIONS_CATEGORY_UNLEARNED")
local SKILL_UP = only("PROFESSIONS_SKILL_UP_EASY", "PROFESSIONS_SKILL_UP_MEDIUM", "PROFESSIONS_SKILL_UP_OPTIMAL")
local ENCHANT_SLOT = only("PROFESSIONS_ADD_ENCHANT")
local ENCHANT_TIP = only("ENCHANT_TARGET_TOOLTIP_CLICK_TO_ADD")
local FIRST_CRAFT_TIP = only("PROFESSIONS_FIRST_CRAFT_DESCRIPTION")
local REQUIREMENT_TIP = only("PROFESSIONS_REQUIREMENT_TOOL", "PROFESSIONS_REQUIREMENT_TABLE")
local FLYOUT_EMPTY = only("PROFESSIONS_PICKER_NO_AVAILABLE_REAGENTS")
local FLYOUT_HIDE = only("PROFESSIONS_HIDE_UNOWNED_REAGENTS")
local CREATE_TIP = only("PROFESSIONS_RECIPE_COOLDOWN", "PROFESSIONS_INSUFFICIENT_REAGENTS",
  "PROFESSIONS_MISSING_REQUIREMENT")
local TOOLS = only("PROFESSIONS_REQUIRED_TOOLS")
local REPLACE_TIP = only("ENCHANT_TARGET_TOOLTIP_CLICK_TO_REPLACE")
local ENCHANTED = only("ENCHANTED_TOOLTIP_LINE")
local STATIC = {
  { "guildCrafters", only("GUILD_TRADE_SKILL_VIEW_CRAFTERS") }, { "guildTitle", only("GUILD_CRAFTERS") },
  { "noResults", only("PROFESSIONS_NO_JOURNAL_ENTRIES") }, { "searchHint", only("SEARCH") },
  { "reagents", only("PROFESSIONS_REAGENT_CONTAINER_LABEL") },
  { "finishingReagents", only("PROFESSIONS_CRAFTING_FINISHING_HEADER") },
  { "firstCraft", only("PROFESSIONS_FIRST_CRAFT") },
}
local FORM_WRITTEN = {
  { "recipeSource", only("TRADESKILL_NEXT_RANK_HEADER", "TRADESKILL_UNLEARNED_RECIPE_HEADER",
    "PROFESSIONS_RECIPE_UNLEARNED") },
  { "optionalReagents", only("PROFESSIONS_OPTIONAL_REAGENT_CONTAINER_LABEL",
    "PROFESSIONS_REAGENT_CONTAINER_ENCHANT_LABEL") },
  { "cooldown", only("COOLDOWN_EXPIRES_AT_MIDNIGHT", "TRADESKILL_CHARGES_REMAINING") },
  { "requiredTools", TOOLS }, { "recraftTools", TOOLS }, { "trackRecipe", only("PROFESSIONS_TRACK_RECIPE") },
}

-- the inspect window's form: the same labels as the crafting page's, under its own names
local INSPECT_LABELS = {
  { "inspectReagents", only("PROFESSIONS_REAGENT_CONTAINER_LABEL") },
  { "inspectFinishing", only("PROFESSIONS_CRAFTING_FINISHING_HEADER") },
  { "inspectFirstCraft", only("PROFESSIONS_FIRST_CRAFT") },
  { "inspectSource", only("TRADESKILL_NEXT_RANK_HEADER", "TRADESKILL_UNLEARNED_RECIPE_HEADER",
    "PROFESSIONS_RECIPE_UNLEARNED") },
  { "inspectOptional", only("PROFESSIONS_OPTIONAL_REAGENT_CONTAINER_LABEL",
    "PROFESSIONS_REAGENT_CONTAINER_ENCHANT_LABEL") },
  { "inspectTrack", only("PROFESSIONS_TRACK_RECIPE") },
}

local function get(key) return Compat.get(SURFACE, key) end
local function declare()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
end

local function showList(list)
  local items = {}
  for i, entry in ipairs(list) do items[i] = { entry[1], get(entry[1]), entry[2] } end
  return WFJ.Labels.showAll(SURFACE, items)
end

-- hooksecurefunc target (CraftingPage:ValidateControls). → the number of dictionary words found.
function Crafting.onControls()
  return WFJ.Labels.showAll(SURFACE, { { "createButton", get("createButton"), CREATE },
    { "createAllButton", get("createAllButton"), CREATE_ALL } })
end

-- The enchant target slot's placeholder (after the form's Init and each SetNameText). → 1 | 0
local slotHooked = setmetatable({}, { __mode = "k" })
function Crafting.showEnchantSlot()
  local form = get("form")
  local slot = type(form) == "table" and form.enchantSlot or nil
  if type(slot) ~= "table" then return 0 end
  if not slotHooked[slot] then
    slotHooked[slot] = true
    if type(slot.SetNameText) == "function" then hooksecurefunc(slot, "SetNameText", Crafting.showEnchantSlot) end
    if type(slot.Button) == "table" then WFJ.HelpTooltip.register(slot.Button, ENCHANT_TIP) end
  end
  local n = WFJ.Labels.show(SURFACE, "enchantSlot", slot.Name, nil, ENCHANT_SLOT)
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- The client sized the description to its English; this sizes it again to the text shown.
local function fitDescription()
  local form = get("form")
  local fs = type(form) == "table" and form.Description or nil
  if type(fs) ~= "table" or type(fs.GetStringHeight) ~= "function" or type(fs.SetHeight) ~= "function" then return end
  fs:SetHeight(600)
  fs:SetHeight(fs:GetStringHeight() + 1)
end
-- The form's recipe description (UpdateRecipeDescription, blizzard_professionsrecipeschematicform.lua:1466–1490):
-- C_TradeSkillUI.GetRecipeDescription of the recipe's spell, so it shows that spell's description Japanese, as its
-- tooltip does, the numbers taken from the live English. A description the form cleared (a recraft, the minimized
-- window) is left alone. → true when shown
function Crafting.onDescription()
  local form = get("form")
  local fs = type(form) == "table" and form.Description or nil
  local info = type(form) == "table" and form.currentRecipeInfo or nil
  local id = type(info) == "table" and info.recipeID or nil
  if type(fs) ~= "table" or type(fs.GetText) ~= "function" or type(id) ~= "number" then return false end
  local en = fs:GetText()
  if type(en) ~= "string" or en == "" then return false end
  local shown = WFJ.Render.show(SURFACE, "description", fs, en, "spells", "spell.description", id,
    { lines = { en }, refit = fitDescription })
  return shown
end

-- The output name's refit, one per form: the width and height SetTextToFit gives the text shown (:349–359).
local fits = setmetatable({}, { __mode = "k" })
local function fitOf(form)
  local fit = fits[form]
  if fit then return fit end
  fit = function()
    local fs = form.OutputText
    local max = type(form.GetOutputItemMaxWidth) == "function" and form:GetOutputItemMaxWidth() or nil
    if type(fs) ~= "table" or type(max) ~= "number" or type(fs.GetStringWidth) ~= "function"
        or type(fs.GetStringHeight) ~= "function" or type(fs.SetHeight) ~= "function" then return end
    fs:SetHeight(200)
    fs:SetWidth(max)
    if not (type(form.ShouldAllowMultiline) == "function" and form:ShouldAllowMultiline()) then
      fs:SetWidth(fs:GetStringWidth())
    end
    fs:SetHeight(fs:GetStringHeight())
  end
  fits[form] = fit
  return fit
end

-- hooksecurefunc target (a form's UpdateOutputItem): its output name. → 1 | 0
function Crafting.showOutput(form)
  if type(form) ~= "table" then return 0 end
  local key = form == get("inspectForm") and "inspect.output" or "output"
  local n = WFJ.NameLabels.wrapped(SURFACE, key, form.OutputText, "items", fitOf(form))
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- hooksecurefunc target (SchematicForm:Init): the words the form rewrites per recipe. → the number found.
function Crafting.onFormInit()
  return showList(FORM_WRITTEN) + Crafting.showEnchantSlot() + Crafting.showReagents(get("form"))
end

-- A reagent slot's name ("3/5 Copper Bar" in the slot's colour, written by the slot's Update,
-- blizzard_professionsrecipereagentslot.lua:113–130): the reagent in Japanese while names are on, the count and the
-- colour as written. Each slot's Update is followed once, since the slot runs it again when an item loads and when
-- the bags change. → names shown
local slotKey = WFJ.Labels.keyer("slot.")
local slotHooked = setmetatable({}, { __mode = "k" })
local function showSlotName(slot)
  local fs = type(slot) == "table" and slot.Name or nil
  if type(fs) ~= "table" or type(fs.GetText) ~= "function" then return 0 end
  local n = WFJ.NameLabels.counted(SURFACE, slotKey(fs), fs, "items")
  WFJ.Render.updateBanner(SURFACE)
  return n
end
function Crafting.showReagents(form)
  local pool = type(form) == "table" and form.reagentSlotPool or nil
  if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then return 0 end
  local n = 0
  for slot in pool:EnumerateActive() do
    if type(slot) == "table" and not slotHooked[slot] and type(slot.Update) == "function" then
      slotHooked[slot] = true
      hooksecurefunc(slot, "Update", showSlotName)
    end
    n = n + showSlotName(slot)
  end
  return n
end

-- hooksecurefunc target (the inspect window's SchematicForm:Init / :Update): its labels. → the number found.
function Crafting.onInspect() return showList(INSPECT_LABELS) end

-- hooksecurefunc target (OpenProfessionsItemFlyout(anchorTo, owner, behavior)): the flyout's two fixed words. → the
-- number found.
function Crafting.onFlyout(_, owner)
  for _, child in ipairs(WFJ.Frames.children(owner)) do
    local box = type(child) == "table" and child.HideUnownedCheckbox or nil
    if type(box) == "table" and type(child.Text) == "table" then
      return WFJ.Labels.showAll(SURFACE, { { "flyout.empty", child.Text, FLYOUT_EMPTY },
        { "flyout.hideUnowned", box.text, FLYOUT_HIDE } })
    end
  end
  return 0
end

-- GameTooltip:Show post-hook: the enchant slot's filled tooltip gets its replace hint appended. → n shown
function Crafting.onTooltipShow(tt)
  local form = get("form")
  local slot = type(form) == "table" and form.enchantSlot or nil
  if type(slot) ~= "table" or type(tt) ~= "table" or type(tt.GetOwner) ~= "function" or tt:GetOwner() ~= slot.Button
      or not (tt.GetItem and tt:GetItem()) then return 0 end
  return WFJ.HelpTooltip.appended(tt, REPLACE_TIP)
end

-- An output-log element (ScrollUtil callback, same shapes as onListRow): its item line is followed.
local logKey = WFJ.Labels.keyer("log.")
local logHooked = setmetatable({}, { __mode = "k" })
local function showLogText(fs)
  WFJ.Labels.show(SURFACE, logKey(fs), fs, nil, ENCHANTED)
  WFJ.Render.updateBanner(SURFACE)
end
function Crafting.onLogElement(a, b)
  local element = a == Crafting and b or a
  local container = type(element) == "table" and element.ItemContainer or nil
  local fs = type(container) == "table" and container.Text or nil
  if type(fs) ~= "table" or type(fs.GetText) ~= "function" then return end
  if not logHooked[fs] and type(fs.SetText) == "function" then
    logHooked[fs] = true
    hooksecurefunc(fs, "SetText", showLogText)
  end
  showLogText(fs)
end

local rowKey = WFJ.Labels.keyer("row.") -- a pooled list row's record key

-- A recipe row's name is as wide as its text, up to the room the row's other pieces leave (Init,
-- blizzard_professionsrecipelist.lua:346–353: the row less the lock icon, the craftable count, the skill-up icon and
-- 10 of padding). The client measured the English, so the name is sized again for the text shown, the same way.
local function fitRow(row)
  local label = row.Label
  if type(label) ~= "table" or type(label.SetWidth) ~= "function" or type(label.GetStringWidth) ~= "function"
      or type(row.GetWidth) ~= "function" then
    return
  end
  local function width(piece, measure, onlyShown)
    if type(piece) ~= "table" or type(piece[measure]) ~= "function" then return 0 end
    if onlyShown and not (type(piece.IsShown) == "function" and piece:IsShown()) then return 0 end
    return piece[measure](piece) or 0
  end
  local room = row:GetWidth() - 10 - width(row.SkillUps, "GetWidth") - width(row.LockedIcon, "GetWidth", true)
    - width(row.Count, "GetStringWidth", true)
  label:SetWidth(row:GetWidth())
  label:SetWidth(math.min(room, label:GetStringWidth()))
end

-- ScrollUtil callback for a recipe list row: (owner, frame, node) on initialization, (frame, node) on the
-- existing-frames pass. Returns nothing (ForEachFrame stops at the first truthy return).
function Crafting.onListRow(a, b, c)
  local row, node = a, b
  if a == Crafting then row, node = b, c end
  if type(row) ~= "table" then return end
  local data = node
  if type(node) == "table" and type(node.GetData) == "function" then data = node:GetData() end
  if type(data) ~= "table" then return end
  if data.recipeInfo then
    -- the recipe's name is a name, never a dictionary word; its skill-up icon owns a one-line tooltip
    WFJ.Labels.forbid(row.Label)
    if type(row.SkillUps) == "table" then WFJ.HelpTooltip.register(row.SkillUps, SKILL_UP) end
    if WFJ.NameLabels.show(SURFACE, rowKey(row), row.Label, "ui", function() fitRow(row) end) == 1 then
      WFJ.Render.updateBanner(SURFACE)
    end
    return
  end
  if data.categoryInfo then
    WFJ.Labels.show(SURFACE, rowKey(row), row.ButtonText, nil, category())
  elseif data.isDivider then
    WFJ.Labels.show(SURFACE, rowKey(row), row.Label, nil, UNLEARNED)
  else
    return
  end
  WFJ.Render.updateBanner(SURFACE)
end

-- The page's OnShow (and setup): the static words, then everything a writer may already have written.
function Crafting.onShow()
  local n = showList(STATIC) + Crafting.onFormInit() + Crafting.onControls()
    + WFJ.Labels.dropdown(SURFACE, "filter", get("filter")) + Crafting.showOutput(get("form"))
  if Crafting.onDescription() then n = n + 1 end
  return n + WFJ.Labels.title(SURFACE, get("outputLog"), OUTPUT_TITLE, "outputLog.title")
end

function Crafting.release() return WFJ.Render.release(SURFACE) end

local hooked = false

-- Runs once Blizzard_Professions is loaded (now, or on its ADDON_LOADED). → true when set up.
function Crafting.setup()
  declare() -- its frames exist only now: forget what Compat memoized before
  local page = get("page")
  if hooked or type(page) ~= "table" then return false end
  hooked = true
  WFJ.Labels.forbidNames(Crafting.NEVER_TOUCH) -- its widgets exist only now (Main's registration found none)
  if type(page.ValidateControls) == "function" then
    hooksecurefunc(page, "ValidateControls", Crafting.onControls)
  end
  local form = get("form")
  if type(form) == "table" and type(form.Init) == "function" then
    hooksecurefunc(form, "Init", Crafting.onFormInit)
  end
  if type(form) == "table" and type(form.Update) == "function" then -- the required tools line
    hooksecurefunc(form, "Update", Crafting.onFormInit)
  end
  if type(form) == "table" and type(form.UpdateRecipeDescription) == "function" then
    hooksecurefunc(form, "UpdateRecipeDescription", Crafting.onDescription)
  end
  local inspect = get("inspectForm")
  for _, method in ipairs({ "Init", "Update" }) do
    if type(inspect) == "table" and type(inspect[method]) == "function" then
      hooksecurefunc(inspect, method, Crafting.onInspect)
    end
  end
  for _, f in ipairs({ form, inspect }) do
    if type(f) == "table" and type(f.UpdateOutputItem) == "function" then
      hooksecurefunc(f, "UpdateOutputItem", Crafting.showOutput)
    end
  end
  for _, key in ipairs({ "createButton", "createAllButton" }) do
    local button = get(key)
    if type(button) == "table" then WFJ.HelpTooltip.register(button, CREATE_TIP) end
  end
  local tt = get("tooltip")
  if type(tt) == "table" and type(tt.Show) == "function" then hooksecurefunc(tt, "Show", Crafting.onTooltipShow) end
  if type(page.HookScript) == "function" then
    page:HookScript("OnShow", Crafting.onShow)
    page:HookScript("OnHide", Crafting.release)
  end
  local link = get("linkButton")
  if type(link) == "table" then WFJ.HelpTooltip.register(link, LINK) end
  if type(form) == "table" then WFJ.HelpTooltip.register(form, REQUIREMENT_TIP) end
  local bonus = get("firstCraftBonus")
  if type(bonus) == "table" then WFJ.HelpTooltip.register(bonus, FIRST_CRAFT_TIP) end
  if type(get("openFlyout")) == "function" then hooksecurefunc("OpenProfessionsItemFlyout", Crafting.onFlyout) end
  local util, box = get("scrollUtil"), get("listBox")
  if type(util) == "table" and type(util.AddInitializedFrameCallback) == "function" and type(box) == "table" then
    util.AddInitializedFrameCallback(box, Crafting.onListRow, Crafting, true)
  end
  local logBox = get("outputBox")
  if type(util) == "table" and type(util.AddInitializedFrameCallback) == "function" and type(logBox) == "table" then
    util.AddInitializedFrameCallback(logBox, Crafting.onLogElement, Crafting, true)
  end
  Crafting.onShow()
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init. → true when the addon
-- was already loaded and set up; false while it is waited for.
function Crafting.init()
  declare()
  local LOD = WFJ.LoadOnDemand
  if type(LOD) ~= "table" or type(LOD.when) ~= "function" then return false end
  return LOD.when(ADDON, Crafting.setup)
end
