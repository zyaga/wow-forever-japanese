-- UI/CustomerOrders.lua: the crafting-orders customer window on Forever (surface "customerorders", area "ui",
-- ADR-016, ADR-029): ProfessionsCustomerOrdersFrame (Blizzard_ProfessionsCustomerOrders, load-on-demand).
-- Entry point on camelot: the server event CRAFTINGORDERS_SHOW_CUSTOMER → GameEvent.HandleCraftingOrdersShowCustomer
-- → ShowProfessionsCustomerOrdersFrame() (blizzard_game/mainline/eventrouting.lua:30, eventimplementation.lua:
-- 483–489; blizzard_professionscustomerorders_bootstrap.lua:7–11). The handler is in the camelot load set; whether a
-- Forever server ever sends the event cannot be told from source (in-game check).
-- Titles, both through Labels.title (SetTitle → TitleContainer.TitleText):
--   the window: ProfessionsCustomerOrdersMixin:SelectMode → SetTitle(PLACE_CRAFTING_ORDERS | MY_ORDERS)
--     (blizzard_professionscustomerorders.lua:3–7, 123–125);
--   the form's listings panel: InitCurrentListings → CurrentListings:SetTitle(PROFESSIONS_CURRENT_LISTINGS)
--     (blizzard_professionscustomerordersform.lua:330–331).
-- Static labels (XML text, written at load): the two tabs (blizzard_professionscustomerorders.xml:67, 75), the
--   browse page's Search button (browseorders.xml:36), the orders page's empty text (myorders.xml:90), and the
--   form's Back / List Order / Cancel Order / Close buttons and its field labels (form.xml:98–604). The Back button's
--   PROFESSIONS_CRAFTING_FORM_BACK shares "Back" with the equipment slot (BACKSLOT, 背中): it owns its Japanese
--   (UIStrings.OWN), asked for by key.
-- Writer: Form:Init(order), a method call from the window (blizzard_professionscustomerorders.lua:46), rewrites the
--   reagent container labels (PROFESSIONS_CUSTOMER_… / PROFESSIONS_PROVIDED_…, form.lua:1314–1315, 1374–1375) and
--   the order's state word (OrderStateText, one of six GlobalStrings, form.lua:1356–1370) and the order's type
--   (OrderRecipientDisplay.PostedTo: PROFESSIONS_CRAFTING_FORM_ORDER_RECIPIENT_PUBLIC / _GUILD / _PRIVATE, :1346–1354;
--   never a name); the duration label is written by SetupDurationDropdown (:587). Post-hooked on the form, which
--   re-shows every label.
-- Composites (ADR-038):
--   ProfessionText = CRAFTING_ORDER_RECIPE_PROFESSION_FMT with the profession's name kept (`text`,
--     InitSchematic, form.lua:1026, 1165–1166; run from Init :1279); PaymentContainer.TimeRemainingDisplay.Text =
--     CRAFTING_ORDER_TIME_PENDING_FMT around the formatted duration (`time`, Init :1321–1331), both after Init;
--   the reagent slots UpdateReagentSlots acquires from reagentSlotPool (form.lua:661–745; called as
--     self:UpdateReagentSlots(), :223, 446, 631, 1175), post-hooked: each slot's Checkbox owns
--     ERROR_COLOR(PROFESSIONS_ORDERS_NOT_ENOUGH_REAGENTS) (:793; SetElementTooltipText, blizzard_professionstemplates/
--     blizzard_professionsrecipereagentslot.lua:406–416, 438–440; `wrapped`); each slot's Button tooltip (a quality
--     picker or the reagent's item tooltip (ProcessInfo)) gets PROFESSIONS_ORDER_CRAFTER / _CUSTOMER_REQUIRED_REAGENT
--     appended (:826–866), shown after GameTooltip:Show by HelpTooltip.appended (itemAppended; the reagent's own lines
--     stay with UI/Tooltip). Whether ProcessInfo ends in Show on Forever is an in-game check (crafting orders).
-- Never touched: the recipe / item name (RecipeName, RecraftRecipeName), the crafter value (the crafter's name, or
--   CRAFTING_ORDER_NOT_YET_CLAIMED /
--   _NOT_CLAIMED in the same FontString, :1334–1344) and the recipient box (a player name), the
--   time-remaining value (a formatted duration), the note and recipient EditBoxes, the list rows (item and player
--   names).
local _, WFJ = ...
local CustomerOrders = {}
WFJ.CustomerOrders = CustomerOrders

local SURFACE = "customerorders"
CustomerOrders.SURFACE = SURFACE
local Compat = WFJ.Compat

local ADDON = "Blizzard_ProfessionsCustomerOrders"
local FRAME = "ProfessionsCustomerOrdersFrame"
local FORM = FRAME .. ".Form"
local PAY = FORM .. ".PaymentContainer"

CustomerOrders.NEVER_TOUCH = { FORM .. ".RecipeName", FORM .. ".RecraftRecipeName",
  FORM .. ".OrderRecipientTarget", FORM .. ".OrderRecipientDisplay.CrafterValue",
  PAY .. ".NoteEditBox.ScrollingEditBox",
  FRAME .. ".BrowseOrders.SearchBar.SearchBox" }

local function only(...) return { only = { ... } } end

-- { record key, dotted path, opts }
local LABELS = {
  { "browseTab", FRAME .. ".BrowseTab", only("BROWSE_ORDERS") },
  { "ordersTab", FRAME .. ".OrdersTab", only("MY_ORDERS") },
  { "search", FRAME .. ".BrowseOrders.SearchBar.SearchButton", only("AUCTION_HOUSE_SEARCH_BUTTON") },
  { "noOrders", FRAME .. ".MyOrdersPage.OrderList.ResultsText", only("PROFESSIONS_CUSTOMER_NO_ORDERS") },
  { "back", FORM .. ".BackButton", only("PROFESSIONS_CRAFTING_FORM_BACK") },
  { "minQuality", FORM .. ".MinimumQuality.Text", only("PROFESSIONS_CRAFTING_FORM_MIN_QUALITY") },
  { "crafter", FORM .. ".OrderRecipientDisplay.Crafter", only("PROFESSIONS_ORDER_CRAFTER") },
  { "reagents", FORM .. ".ReagentContainer.Reagents.Label",
    only("PROFESSIONS_CUSTOMER_REAGENT_CONTAINER_LABEL", "PROFESSIONS_PROVIDED_REAGENT_CONTAINER_LABEL") },
  { "optionalReagents", FORM .. ".ReagentContainer.OptionalReagents.Label",
    only("PROFESSIONS_CUSTOMER_OPTIONAL_REAGENT_CONTAINER_LABEL",
      "PROFESSIONS_PROVIDED_OPTIONAL_REAGENT_CONTAINER_LABEL") },
  { "recraftInfo", FORM .. ".ReagentContainer.RecraftInfoText", only("PROFESSIONS_RECRAFT_ORDER_INSTRUCTION") },
  { "orderState", FORM .. ".OrderStateText", only("PROFESSIONS_ORDER_COMPLETE", "PROFESSIONS_ORDER_EXPIRED",
    "PROFESSIONS_ORDER_CANCELLED", "PROFESSIONS_ORDER_REJECTED", "PROFESSIONS_CRAFTING_ORDER_IN_PROGRESS",
    "CRAFTING_ORDER_NOT_CLAIMED") },
  { "postedTo", FORM .. ".OrderRecipientDisplay.PostedTo", only("PROFESSIONS_CRAFTING_FORM_ORDER_RECIPIENT_PUBLIC",
    "PROFESSIONS_CRAFTING_FORM_ORDER_RECIPIENT_GUILD", "PROFESSIONS_CRAFTING_FORM_ORDER_RECIPIENT_PRIVATE") },
  { "duration", PAY .. ".Duration", only("PROFESSIONS_CRAFTING_FORM_CUSTOMER_DURATION") },
  { "tip", PAY .. ".Tip", only("PROFESSIONS_CRAFTING_FORM_TIP") },
  { "timeRemaining", PAY .. ".TimeRemaining", only("PROFESSIONS_ORDER_TIME_REMAINING") },
  { "postingFee", PAY .. ".PostingFee", only("PROFESSIONS_CRAFTING_FORM_POSTING_FEE") },
  { "totalPrice", PAY .. ".TotalPrice", only("PROFESSIONS_CRAFTING_FORM_TOTAL_PRICE") },
  { "noteTitle", PAY .. ".NoteEditBox.TitleBox.Title", only("PROFESSIONS_NOTE_TO_CRAFTER") },
  { "listOrder", PAY .. ".ListOrderButton", only("PROFESSIONS_CRAFTING_FORM_LIST_ORDER") },
  { "cancelOrder", PAY .. ".CancelOrderButton", only("PROFESSIONS_CRAFTING_FORM_CANCEL_ORDER") },
  { "listingsClose", FORM .. ".CurrentListings.CloseButton", only("CLOSE") },
  { "listingsNone", FORM .. ".CurrentListings.OrderList.ResultsText", only("PROFESSIONS_CUSTOMER_NO_ORDERS") },
  { "profession", FORM .. ".ProfessionText", only("CRAFTING_ORDER_RECIPE_PROFESSION_FMT") },
  { "timePending", PAY .. ".TimeRemainingDisplay.Text", only("CRAFTING_ORDER_TIME_PENDING_FMT") },
}
local NOT_ENOUGH = only("PROFESSIONS_ORDERS_NOT_ENOUGH_REAGENTS")
local SOURCE = only("PROFESSIONS_ORDER_CRAFTER_REQUIRED_REAGENT", "PROFESSIONS_ORDER_CUSTOMER_REQUIRED_REAGENT")
local WINDOW_TITLE = only("PLACE_CRAFTING_ORDERS", "MY_ORDERS")
local LISTINGS_TITLE = only("PROFESSIONS_CURRENT_LISTINGS")

local function get(key) return Compat.get(SURFACE, key) end
local function declare()
  Compat.declare(SURFACE, "frame", { FRAME })
  Compat.declare(SURFACE, "form", { FORM })
  Compat.declare(SURFACE, "listings", { FORM .. ".CurrentListings" })
  Compat.declare(SURFACE, "tooltip", { "GameTooltip" })
  for _, l in ipairs(LABELS) do Compat.declare(SURFACE, l[1], { l[2] }) end
end

-- Every label, and the two titles: on setup, the window's and the form's OnShow, and after Form:Init. → the number
-- of dictionary words found.
function CustomerOrders.show()
  local items = {}
  for i, l in ipairs(LABELS) do items[i] = { l[1], get(l[1]), l[3] } end
  local n = WFJ.Labels.showAll(SURFACE, items)
  return n + WFJ.Labels.title(SURFACE, get("frame"), WINDOW_TITLE, "title")
    + WFJ.Labels.title(SURFACE, get("listings"), LISTINGS_TITLE, "listings.title")
end

function CustomerOrders.release() return WFJ.Render.release(SURFACE) end

-- The reagent slots after UpdateReagentSlots. → the number of slots seen
local reagentButtons = setmetatable({}, { __mode = "k" })
function CustomerOrders.onReagentSlots()
  local form = get("form")
  local pool = type(form) == "table" and form.reagentSlotPool or nil
  if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then return 0 end
  local n = 0
  for slot in pool:EnumerateActive() do
    if type(slot) == "table" then
      if type(slot.Checkbox) == "table" then WFJ.HelpTooltip.register(slot.Checkbox, NOT_ENOUGH) end
      if type(slot.Button) == "table" then reagentButtons[slot.Button] = true end
      n = n + 1
    end
  end
  return n
end

-- GameTooltip:Show post-hook: a reagent slot's tooltip with its provider line appended. → n shown
function CustomerOrders.onTooltipShow(tt)
  if type(tt) ~= "table" or type(tt.GetOwner) ~= "function" or not reagentButtons[tt:GetOwner()] then return 0 end
  return WFJ.HelpTooltip.appended(tt, SOURCE)
end

local hooked = false

-- Runs once the addon is loaded (now, or on its ADDON_LOADED). → true when set up.
function CustomerOrders.setup()
  declare() -- its frames exist only now: forget what Compat memoized before
  local frame = get("frame")
  if hooked or type(frame) ~= "table" then return false end
  hooked = true
  WFJ.Labels.forbidNames(CustomerOrders.NEVER_TOUCH) -- its widgets exist only now
  local form = get("form")
  if type(form) == "table" then
    if type(form.Init) == "function" then hooksecurefunc(form, "Init", CustomerOrders.show) end
    if type(form.UpdateReagentSlots) == "function" then
      hooksecurefunc(form, "UpdateReagentSlots", CustomerOrders.onReagentSlots)
    end
    if type(form.HookScript) == "function" then form:HookScript("OnShow", CustomerOrders.show) end
  end
  if type(frame.HookScript) == "function" then
    frame:HookScript("OnShow", CustomerOrders.show)
    frame:HookScript("OnHide", CustomerOrders.release)
  end
  local tt = get("tooltip")
  if type(tt) == "table" and type(tt.Show) == "function" then
    hooksecurefunc(tt, "Show", CustomerOrders.onTooltipShow)
  end
  CustomerOrders.show()
  CustomerOrders.onReagentSlots()
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init. → true when the addon
-- was already loaded and set up; false while it is waited for.
function CustomerOrders.init()
  declare()
  local LOD = WFJ.LoadOnDemand
  if type(LOD) ~= "table" or type(LOD.when) ~= "function" then return false end
  return LOD.when(ADDON, CustomerOrders.setup)
end
