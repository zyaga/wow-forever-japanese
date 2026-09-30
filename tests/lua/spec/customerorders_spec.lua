-- the crafting-orders customer window on the Forever (camelot) client: UI/CustomerOrders.lua over a
-- ProfessionsCustomerOrdersFrame replayed from the extracted 1.60.1 source (blizzard_professionscustomerorders/
-- blizzard_professionscustomerorders.lua|xml: SelectMode → SetTitle, the two tabs; …form.lua|xml: the form's labels,
-- Init's reagent labels and order state, InitCurrentListings → SetTitle). Item, recipe and player names stay English.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/CustomerOrders.lua"

local ADDON = "Blizzard_ProfessionsCustomerOrders"

local UI = {
  PLACE_CRAFTING_ORDERS = { "Place Crafting Orders", "製作依頼を出す" }, MY_ORDERS = { "My Orders", "自分の依頼" },
  BROWSE_ORDERS = { "Browse Orders", "依頼を探す" }, AUCTION_HOUSE_SEARCH_BUTTON = { "Search", "検索" },
  PROFESSIONS_CUSTOMER_NO_ORDERS = { "No orders found", "依頼が見つかりません" },
  PROFESSIONS_CUSTOMER_REAGENT_CONTAINER_LABEL = { "Provide Reagents:", "提供する材料:" },
  PROFESSIONS_PROVIDED_REAGENT_CONTAINER_LABEL = { "Provided Reagents:", "提供済みの材料:" },
  PROFESSIONS_CRAFTING_FORM_TIP = { "Commission:", "手数料:" },
  PROFESSIONS_CRAFTING_FORM_LIST_ORDER = { "Place Order", "依頼を出す" },
  PROFESSIONS_ORDER_COMPLETE = { "Order Complete!", "依頼完了!" },
  PROFESSIONS_ORDER_EXPIRED = { "Order Expired", "依頼の期限切れ" },
  PROFESSIONS_CURRENT_LISTINGS = { "Current Listings", "現在の依頼一覧" },
  CLOSE = { "Close", "閉じる" },
  CRAFTING_ORDER_NOT_CLAIMED = { "Not Claimed", "未受注" },
  PROFESSIONS_CRAFTING_FORM_ORDER_RECIPIENT_GUILD = { "Guild Order", "ギルド依頼" },
  CRAFTING_ORDER_RECIPE_PROFESSION_FMT = { "%s Recipe", "%sのレシピ" },
  CRAFTING_ORDER_TIME_PENDING_FMT = { "%s (Pending)", "%s(保留中)" },
  PROFESSIONS_ORDERS_NOT_ENOUGH_REAGENTS = { "You do not have enough of this reagent to provide.",
    "提供するにはこの材料が足りません。" },
  PROFESSIONS_ORDER_CRAFTER_REQUIRED_REAGENT = {
    "|cnDISABLED_REAGENT_COLOR:This reagent will be provided by the crafter.|r",
    "|cnDISABLED_REAGENT_COLOR:この材料は製作者が用意します。|r" },
  SPELL_DURATION_HOURS = { "%d hours", "%d時間" },
}

local function en(key) return _G[key] end
local function fs(text) return Stub.fontString(text or "") end
local function titled(f)
  f.TitleContainer = { TitleText = fs("") }
  function f.SetTitle(self, t) self.TitleContainer.TitleText.text = t end
end

local function loadOrders()
  Stub.loadedAddons[ADDON] = true
  local frame = CreateFrame("Frame", "ProfessionsCustomerOrdersFrame")
  titled(frame)
  frame.BrowseTab, frame.OrdersTab = Stub.button(nil, en("BROWSE_ORDERS")), Stub.button(nil, en("MY_ORDERS"))
  frame.BrowseOrders = { SearchBar = { SearchButton = Stub.button(nil, en("AUCTION_HOUSE_SEARCH_BUTTON")),
    SearchBox = CreateFrame("EditBox") } }
  frame.MyOrdersPage = { OrderList = { ResultsText = fs(en("PROFESSIONS_CUSTOMER_NO_ORDERS")) } }
  local form = CreateFrame("Frame", nil, frame)
  form.name = "Form"
  frame.Form = form
  form.BackButton = Stub.button(nil, "Back") -- PROFESSIONS_CRAFTING_FORM_BACK: excluded (see the module)
  form.RecipeName, form.OrderStateText = fs(""), fs(en("PROFESSIONS_ORDER_COMPLETE"))
  form.ReagentContainer = { Reagents = { Label = fs("") }, OptionalReagents = { Label = fs("") } }
  form.PaymentContainer = { Tip = fs(en("PROFESSIONS_CRAFTING_FORM_TIP")),
    ListOrderButton = Stub.button(nil, en("PROFESSIONS_CRAFTING_FORM_LIST_ORDER")) }
  form.CurrentListings = CreateFrame("Frame", nil, form)
  titled(form.CurrentListings)
  form.CurrentListings:SetTitle(en("PROFESSIONS_CURRENT_LISTINGS")) -- InitCurrentListings, from OnLoad
  form.CurrentListings.CloseButton = Stub.button(nil, en("CLOSE"))
  function form.Init(self, order) -- form.lua:1197, 1314–1315, 1358–1375
    self.RecipeName.text = order.item
    self.ReagentContainer.Reagents.Label.text = order.committed and en("PROFESSIONS_PROVIDED_REAGENT_CONTAINER_LABEL")
      or en("PROFESSIONS_CUSTOMER_REAGENT_CONTAINER_LABEL")
    self.OrderStateText.text = order.expired and en("PROFESSIONS_ORDER_EXPIRED") or en("PROFESSIONS_ORDER_COMPLETE")
  end
  function frame.SelectMode(self, mode) -- blizzard_professionscustomerorders.lua:123–125
    self:SetTitle(mode == "orders" and en("MY_ORDERS") or en("PLACE_CRAFTING_ORDERS"))
  end
  return frame
end

describe("the crafting-orders customer window on the Forever client", function()
  local WFJ, SS

  local function alt(down) Stub.keys.alt = down; WFJ.Modifier.refresh() end
  local function frame() return _G.ProfessionsCustomerOrdersFrame end
  local function title(f) return f.TitleContainer.TitleText:GetText() end

  local function setup(loadedFirst, shape)
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    SS = WFJ.SurfaceState
    H.uiSetup(WFJ, UI)
    if loadedFirst then
      local f = loadOrders()
      if shape then shape(f) end
      assert.is_true(WFJ.CustomerOrders.init())
    else
      assert.is_false(WFJ.CustomerOrders.init()) -- waits for the addon
      local f = loadOrders()
      if shape then shape(f) end
      assert.are.equal(1, WFJ.LoadOnDemand.loaded(ADDON))
    end
  end

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    _G.ProfessionsCustomerOrdersFrame = nil
  end)

  for _, order in ipairs({ { true, "loaded before the addon" }, { false, "loaded on demand" } }) do
    describe("the addon " .. order[2], function()
      before_each(function() setup(order[1]) end)

      it("both titles render after SetTitle and keep the Japanese after a second SetTitle", function()
        frame():Show()
        frame():SelectMode("browse")
        assert.are.equal("製作依頼を出す", title(frame()))
        frame():SelectMode("orders")
        assert.are.equal("自分の依頼", title(frame()))
        frame():SelectMode("orders")
        assert.are.equal("自分の依頼", title(frame()))
        local listings = frame().Form.CurrentListings
        assert.are.equal("現在の依頼一覧", title(listings))
        listings:SetTitle(_G.PROFESSIONS_CURRENT_LISTINGS)
        assert.are.equal("現在の依頼一覧", title(listings))
        alt(true)
        assert.are.equal("My Orders", title(frame()))
        alt(false)
        frame():SetTitle("Close") -- not one of the window's titles, though a dictionary word
        assert.are.equal("Close", title(frame()))
      end)

      it("the static labels render; the form's Init rewrites are followed; the item's name stays English", function()
        frame():Show()
        assert.are.equal("依頼を探す", frame().BrowseTab:GetText())
        assert.are.equal("自分の依頼", frame().OrdersTab:GetText())
        assert.are.equal("検索", frame().BrowseOrders.SearchBar.SearchButton:GetText())
        assert.are.equal("依頼が見つかりません", frame().MyOrdersPage.OrderList.ResultsText:GetText())
        local form = frame().Form
        form:Init({ item = "Search" })
        assert.are.equal("提供する材料:", form.ReagentContainer.Reagents.Label:GetText())
        assert.are.equal("手数料:", form.PaymentContainer.Tip:GetText())
        assert.are.equal("依頼を出す", form.PaymentContainer.ListOrderButton:GetText())
        assert.are.equal("依頼完了!", form.OrderStateText:GetText())
        assert.are.equal("Search", form.RecipeName:GetText()) -- an item whose name is a dictionary word
        assert.is_true(WFJ.Labels.forbidden(form.RecipeName))
        assert.is_true(WFJ.Labels.forbidden(frame().BrowseOrders.SearchBar.SearchBox))
        form:Init({ item = "Copper Bar", committed = true, expired = true })
        assert.are.equal("提供済みの材料:", form.ReagentContainer.Reagents.Label:GetText())
        assert.are.equal("依頼の期限切れ", form.OrderStateText:GetText())
        frame():Hide()
        assert.are.equal("Commission:", form.PaymentContainer.Tip:GetText())
        assert.are.equal(0, SS.count("customerorders"))
      end)

      it("hooks install once", function()
        assert.is_false(WFJ.CustomerOrders.setup())
        assert.are.equal(1, #Stub.hooks["Form:Init"])
      end)
    end)
  end

  it("client names bound to the wrong type degrade to untouched English with no error", function()
    assert.has_no.errors(function()
      setup(true, function(f)
        f.BrowseTab, f.MyOrdersPage, f.TitleContainer = "moved", "moved", "moved"
        f.SetTitle = function() end
        f.Form.PaymentContainer, f.Form.CurrentListings, f.Form.Init = "moved", "moved", "moved"
      end)
      frame():Show()
      frame():Hide()
    end)
    assert.is_nil(Stub.hooks["Form:Init"])
    frame():Show()
    assert.are.equal("自分の依頼", frame().OrdersTab:GetText()) -- the rest still renders
    _G.ProfessionsCustomerOrdersFrame = "moved"
    assert.has_no.errors(function() WFJ.CustomerOrders.show() end)
  end)

  it("without the frame init returns false and touches nothing", function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    assert.is_false(WFJ.CustomerOrders.init())
    assert.is_false(WFJ.CustomerOrders.setup())
    assert.are.equal(0, WFJ.SurfaceState.count("customerorders"))
  end)
end)

-- the order's state "Not Claimed" and the order's type (OrderRecipientDisplay.PostedTo) follow Form:Init; the
-- crafter value (a name, or "Not Claimed Yet") is never ours [blizzard_professionscustomerordersform.lua:1334–1370].
describe("the crafting-orders customer window: order state and type", function()
  local WFJ

  local function setup()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    local f = loadOrders()
    local form = f.Form
    form.OrderRecipientDisplay = { PostedTo = fs(""), CrafterValue = fs("") }
    local base = form.Init
    function form.Init(self, order) -- :1334–1370
      base(self, order)
      self.OrderRecipientDisplay.CrafterValue.text = order.crafter or "Not Claimed"
      self.OrderRecipientDisplay.PostedTo.text = order.guild and en("PROFESSIONS_CRAFTING_FORM_ORDER_RECIPIENT_GUILD")
        or ""
      if order.unclaimed then self.OrderStateText.text = en("CRAFTING_ORDER_NOT_CLAIMED") end
    end
    WFJ.CustomerOrders.init()
    return f
  end

  after_each(function()
    H.uiTeardown()
    _G.ProfessionsCustomerOrdersFrame = nil
  end)

  it("renders the state and the type; the crafter value stays English even when it reads as a dictionary word",
    function()
    local f = setup()
    f:Show()
    f.Form:Init({ item = "Copper Bar", guild = true, unclaimed = true })
    assert.are.equal("未受注", f.Form.OrderStateText:GetText())
    assert.are.equal("ギルド依頼", f.Form.OrderRecipientDisplay.PostedTo:GetText())
    assert.are.equal("Not Claimed", f.Form.OrderRecipientDisplay.CrafterValue:GetText())
    assert.is_true(WFJ.Labels.forbidden(f.Form.OrderRecipientDisplay.CrafterValue))
  end)
end)

-- The profession line (ADR-038) and the pending time after Init (form.lua:1165–1166, 1321–1331; the profession
-- name and a duration kept), the reagent slot's not-enough checkbox tooltip (:793) and the provider line appended to
-- a reagent's item tooltip (:826–866, itemAppended); the reagent's own lines untouched.
describe("the crafting-orders customer window: profession, pending time and reagent lines", function()
  local WFJ

  local function setup()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    local f = loadOrders()
    local form = f.Form
    form.ProfessionText = fs("")
    form.PaymentContainer.TimeRemainingDisplay = { Text = fs("") }
    local slot = { Checkbox = CreateFrame("Button"), Button = CreateFrame("Button") }
    form.reagentSlotPool = { EnumerateActive = function() return next, { [slot] = true } end }
    function form.UpdateReagentSlots() end
    local base = form.Init
    function form.Init(self, order)
      base(self, order)
      self.ProfessionText.text = en("CRAFTING_ORDER_RECIPE_PROFESSION_FMT"):format(order.profession)
      self.PaymentContainer.TimeRemainingDisplay.Text.text = en("CRAFTING_ORDER_TIME_PENDING_FMT"):format("12 hours")
      self:UpdateReagentSlots()
    end
    WFJ.CustomerOrders.init()
    return f, slot
  end

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    _G.ProfessionsCustomerOrdersFrame = nil
  end)

  it("the profession line and the pending time: Japanese, the profession name kept, a duration entry in Japanese;"
    .. " Alt English",
    function()
      local f = setup()
      f:Show()
      f.Form:Init({ item = "Copper Bar", profession = "Blacksmithing" })
      assert.are.equal("Blacksmithingのレシピ", f.Form.ProfessionText:GetText())
      assert.are.equal("12時間(保留中)", f.Form.PaymentContainer.TimeRemainingDisplay.Text:GetText())
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      assert.are.equal("Blacksmithing Recipe", f.Form.ProfessionText:GetText())
    end)

  it("a reagent slot: the checkbox's red reason and the provider line appended to the reagent's item tooltip",
    function()
      local f, slot = setup()
      f:Show()
      f.Form:Init({ item = "Copper Bar", profession = "Mining" })
      local tt = _G.GameTooltip
      tt:SetOwner(slot.Checkbox)
      tt:AddLine("|cffff2020" .. en("PROFESSIONS_ORDERS_NOT_ENOUGH_REAGENTS") .. "|r")
      tt:Show()
      assert.are.equal("|cffff2020提供するにはこの材料が足りません。|r", _G.GameTooltipTextLeft1:GetText())
      tt:SetOwner(slot.Button)
      Stub.setItemTooltip(tt, "|Hitem:2770:0:0:0|h[Copper Ore]|h", { "Copper Ore", "Crafting Reagent" })
      tt:AddLine(" ")
      tt:AddLine(en("PROFESSIONS_ORDER_CRAFTER_REQUIRED_REAGENT"))
      tt:Show()
      assert.are.equal("Copper Ore", _G.GameTooltipTextLeft1:GetText())
      assert.are.equal("|cnDISABLED_REAGENT_COLOR:この材料は製作者が用意します。|r", _G.GameTooltipTextLeft4:GetText())
    end)
end)
