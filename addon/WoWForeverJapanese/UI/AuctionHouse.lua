-- UI/AuctionHouse.lua: the auction house on Forever (surface "auctionhouse", area "ui", ADR-016, ADR-029).
-- `camelot` loads the mainline auction house, load-on-demand Blizzard_AuctionHouseUI (blizzard_auctionhouseui.toc:2,
-- :9 `AllowLoadGameType: mainline, cata, mists`). Entry point: its [Bootstrap] file runs at login and registers
-- Enum.PlayerInteractionType.Auctioneer → ShowAuctionHouseFrame → LoadAddOn + ShowUIPanel(AuctionHouseFrame)
-- (shared/blizzard_auctionhouseui_bootstrap.lua:7–27, 44). The setup waits on WFJ.LoadOnDemand.when.
-- Every child is a parentKey (shared/blizzard_auctionhouseframe.xml:4–197), so every name is a dotted Compat candidate.
-- Static labels (XML text= / KeyValue labelText written once by an OnLoad), each restricted to its own key(s):
--   the three display-mode tabs (frame.xml:44–60), SearchBar.SearchButton (searchbar.xml:39, 59), the sell frames'
--   CreateAuctionLabel / QuantityInput / PriceInput / Duration / Deposit / TotalPrice labels, MaxButton, PerItemPostfix
--   and PostButton (sellframe.xml:4–62, 108, 185, 229–259; AlignedControlMixin:OnLoad → SetLabel, sellframe.lua:3–11),
--   the item sell frame's SecondaryPriceInput label and BuyoutModeCheckButton.Text (itemsellframe.xml:6–24,
--   itemsellframe.lua:10), the buy frames' BackButton / BuyButton / BidButton / BuyoutButton and their aligned labels
--   (commoditiesbuyframe.xml:42–82, itembuyframe.xml:7–39, sharedtemplates.xml:135, 153), the auctions tab's sub tabs,
--   CancelAuctionButton, bid and buyout buttons (mainline/…auctionsframe.xml:56–80), the buy dialog's three buttons
--   (buydialog.xml:82–92), every list's LoadingSpinner.SearchingText (mainline/…itemlist.xml:81), and the WoW Token
--   panes' labels (wowtokenframe.xml:19, 71–139, 153, 212, 259–285, 342).
-- Writers, each the frame's own method (mixins are copied onto the frame; every call is `self:…()` or
-- `self.<child>:…()`), post-hooked on the instance; every hook re-runs the one idempotent pass (Labels.show returns
-- early on a widget that still holds our Japanese):
--   AuctionHouseFrame:SetDisplayMode (frame.lua:541–587) → UpdateTitle → SetTitle(AUCTION_HOUSE_FRAME_TITLE_BUY |
--     _SELL | AUCTION_HOUSE_AUCTIONS_SUB_TAB) (frame.lua:640–651): the title goes through Labels.title;
--   ItemSellFrame.PriceInput:SetLabel / :SetSubtext: the buyout-mode switch rewrites the price label to
--     AUCTION_HOUSE_BUYOUT_LABEL, the subtext to AUCTION_HOUSE_BUYOUT_OPTIONAL_LABEL (itemsellframe.lua:56, 335–336);
--   BuyDialog:SetState → Notification.Text (AUCTION_HOUSE_DIALOG_PRICE_UPDATED / _UNAVAILABLE, buydialog.lua:166–224);
--   each of the nine lists (AuctionHouseItemListTemplate and the commodities lists that inherit it,
--     commoditieslist.xml:4–33): SetState → ResultsText (BROWSE_NO_RESULTS, or the list's own text:
--     AUCTION_HOUSE_BROWSE_FAVORITES_TIP, browseresultsframe.lua:40; itemlist.lua:254–270), SetCustomError
--     (itemlist.lua:130–134), UpdateTableBuilderLayout → the pooled column headers, walked with
--     tableBuilder:EnumerateHeaders() (blizzard_sharedxml/tablebuilder.lua:278–280; header text:
--     tablebuilder.lua:884–885, 1022–1132, util.lua:448–462, camelot/blizzard_auctiondata.lua:15–191) and keyed by
--     widget, RefreshFrame:SetQuantity → TotalQuantity (AUCTION_HOUSE_QUANTITY_AVAILABLE_FORMAT,
--     sharedtemplates.lua:632–637), and the pooled rows' cells (row.cells[i].Text, tablebuilder.lua:323–341):
--     AUCTION_HOUSE_NONE_AVAILABLE (:785) or its item-level form AUCTION_HOUSE_NONE_AVAILABLE_FORMAT (the sell list's
--     virtual row, itemsellframe.lua:220), AUCTION_HOUSE_INCOMING_AMOUNT (:491), AUCTION_HOUSE_NUM_SELLERS
--     (util.lua:383). The same cells hold seller names, item levels and quantities, so they are restricted to
--     ROW_KEYS. Rows are walked after RefreshScrollFrame and from ScrollUtil's initialized-frame callback; the table
--     builder fills a row from a callback on the same event (scrollutil.lua:1661–1665) and source does not fix the
--     order of the two, so a row scrolled into view may stay English until the next refresh (in-game check);
--   AuctionsFrame.SummaryList.ScrollBox entries: the first line is AUCTION_HOUSE_ALL_AUCTIONS / _ALL_BIDS, every other
--     line is an item name (auctionsframe.lua:58–75), restricted to those two keys;
--   AuctionHouseFilterButton_SetUp (global, called by name from the categories list's element initializer,
--     categorieslist.lua:91–92; mainline/…categorieslist.lua:1–62) → the category button's text. Named categories are
--     GlobalStrings (camelot/blizzard_auctiondata.lua:14–215); generated sub categories are item sub-class names
--     (C_Item.GetItemSubClassInfo: the ItemSubClassName family, ADR-042: "Staves", "Potions") or an armour
--     slot (GetItemInventorySlotInfo: INVTYPE_*) (shared/blizzard_auctiondata.lua:81–95); the restricted set is
--     CATEGORY's keys, the INVTYPE_* slot words and that family;
--   BrowseWowTokenResults_Update (global, wowtokenframe.lua:129–157) and WoWTokenSellFrame:Refresh (:263–281) → the
--     price fields' TOKEN_AUCTIONS_UNAVAILABLE / TOKEN_MARKET_PRICE_NOT_AVAILABLE (otherwise a price, untouched);
--   the Duration dropdowns' own text (sellframe.lua:160–172) through Labels.dropdown; the popup entries are UI/Menus';
--   AuctionHouseMultisellProgressFrame:Start / :Refresh → ProgressBar.Text AUCTION_CREATING (multisell.lua:14–30).
-- Help tooltips (Lua-built, owner = the widget itself): the disabled bid / buyout / buy / buy-now buttons
--   (ButtonWithDisableMixin:OnEnter, blizzard_uipaneltemplates/shared/uipaneltemplatesshared.lua:330–343), the post
--   buttons (sellframe.lua:211–218), the price inputs' PriceError (sellframe.lua:129–135), the buyout-mode checkbox
--   (itemsellframe.lua:18–24), the favorites search button and every list's refresh button (UIButtonMixin tooltip
--   info, searchbar.lua:61, sharedtemplates.lua:654), the item displays' and the list cells' favorite buttons when
--   the favorites list is full (sharedtemplates.lua:744–754), a commodities row holding the player's own auction
--   (commoditieslist.lua:140–146), and the WoW Token panes: the buyout button's ERR_NOT_ENOUGH_GOLD
--   (wowtokenframe.lua:162, 175–180), the two price frames (wowtokenframe.xml:223–235, 327–339) and the shop
--   button's ERR_FEATURE_RESTRICTED_TRIAL (wowtokenframe.lua:377, 443–448).
-- Never touched: item names, seller / bidder names, prices, quantities, item levels, the search box, the money inputs.
-- Owned words (UIStrings.OWN): three words whose English another dictionary key already has with a
-- different sense ("Back" the equipment slot, "Available" the friends status, "Deposit" the bank button) take their
-- own Japanese here, each asked for by key: the buy frames' BackButton (commoditiesbuyframe.xml:82,
-- itembuyframe.xml:7), the "Available" column header (util.lua:455) and the sell frames' Deposit label
-- (sellframe.xml:247–251).
-- The lines the auction house appends (ADR-038) to an item tooltip: sellers and time left
--   (AuctionHouseUtil.AddAuctionHouseTooltipInfo, shared/blizzard_auctionhouseutil.lua:301–306; called from
--   mainline/blizzard_auctionhouseutil.lua:99–101 after SetHyperlink / SetItemKey), post-hooked on AuctionHouseUtil
--   and shown by HelpTooltip.appended, restricted to APPENDED_KEYS (the item's own lines stay with UI/Tooltip); the
--   cell tooltips: the owners cell and the time-left cell anchor to the row (tablebuilder.lua:380–386, 437–448), the
--   bid / buyout cells to themselves (:555–603, BUYER / HIGH_BIDDER with the bidder's name kept); a WoW Token row's
--   time-left tooltip is WHITE(ESTIMATED_TIME_TO_SELL_LABEL) .. <band> (util.lua:4, 263–279: tokenSell, after each
--   cell's ShowTooltip); the item cell's Prefix AUCTION_HOUSE_AUCTION_SOLD_PREFIX (tablebuilder.lua:741); the buy
--   dialog's notification button (PER_UNIT / TOTAL_INCREASE, the left half of two double lines, buydialog.lua:32–44);
--   the token buyout's TOKEN_TRY_AGAIN_LATER (SetText while the owner is the button, wowtokenframe.lua:70–73); and
--   LeftDisplay.Tutorial3's TUTORIAL_TOKEN_GAME_TIME_STEP_2_BALANCE (the balance string kept,
--   wowtokenframe.lua:359–365).
-- Release on AuctionHouseFrame's OnHide.
local _, WFJ = ...
local AuctionHouse = {}
WFJ.AuctionHouse = AuctionHouse

local SURFACE = "auctionhouse"
AuctionHouse.SURFACE = SURFACE
local Compat = WFJ.Compat
local ADDON = "Blizzard_AuctionHouseUI"
local F = "AuctionHouseFrame"

AuctionHouse.NEVER_TOUCH = { F .. ".SearchBar.SearchBox", F .. ".BuyDialog.ItemDisplay.ItemText",
  F .. ".ItemBuyFrame.ItemDisplay.Name", F .. ".ItemSellFrame.ItemDisplay.Name",
  F .. ".CommoditiesSellFrame.ItemDisplay.Name", F .. ".CommoditiesBuyFrame.BuyDisplay.ItemDisplay.Name",
  F .. ".AuctionsFrame.ItemDisplay.Name", F .. ".ItemSellFrame.QuantityInput.InputBox",
  F .. ".CommoditiesSellFrame.QuantityInput.InputBox", F .. ".CommoditiesBuyFrame.BuyDisplay.QuantityInput.InputBox" }

local TITLE = { only = { "AUCTION_HOUSE_FRAME_TITLE_BUY", "AUCTION_HOUSE_FRAME_TITLE_SELL",
  "AUCTION_HOUSE_AUCTIONS_SUB_TAB" } }
local TOKEN_TITLE = { only = { "TUTORIAL_TOKEN_ABOUT_TOKENS" } }
local PRICE_LABEL = { "AUCTION_HOUSE_UNIT_PRICE_LABEL", "AUCTION_HOUSE_BUYOUT_LABEL", "AUCTION_HOUSE_BID_LABEL" }
local TOKEN_PRICE = { "TOKEN_AUCTIONS_UNAVAILABLE", "TOKEN_MARKET_PRICE_NOT_AVAILABLE" }

-- Static and writer-followed labels: { record key, path under AuctionHouseFrame, the key(s) the widget may show }.
local LABELS = {
  { "buyTab", "BuyTab", { "AUCTION_HOUSE_BUY_TAB" } }, { "sellTab", "SellTab", { "AUCTION_HOUSE_SELL_TAB" } },
  { "auctionsTab", "AuctionsTab", { "AUCTION_HOUSE_AUCTIONS_SUB_TAB" } },
  { "search", "SearchBar.SearchButton", { "AUCTION_HOUSE_SEARCH_BUTTON" } },
  { "searchInstructions", "SearchBar.SearchBox.Instructions", { "SEARCH" } },
  { "cbuy.buy", "CommoditiesBuyFrame.BuyDisplay.BuyButton", { "AUCTION_HOUSE_BUY_BUTTON" } },
  { "cbuy.quantity", "CommoditiesBuyFrame.BuyDisplay.QuantityInput.Label", { "AUCTION_HOUSE_QUANTITY_LABEL" } },
  { "cbuy.max", "CommoditiesBuyFrame.BuyDisplay.QuantityInput.MaxButton", { "AUCTION_HOUSE_MAX_QUANTITY_BUTTON" } },
  { "cbuy.unit", "CommoditiesBuyFrame.BuyDisplay.UnitPrice.Label", { "AUCTION_HOUSE_UNIT_PRICE_LABEL" } },
  { "cbuy.total", "CommoditiesBuyFrame.BuyDisplay.TotalPrice.Label", { "AUCTION_HOUSE_TOTAL_PRICE_LABEL" } },
  { "ibuy.buyout", "ItemBuyFrame.BuyoutFrame.BuyoutButton", { "AUCTION_HOUSE_BUYOUT_BUTTON" } },
  { "ibuy.bid", "ItemBuyFrame.BidFrame.BidButton", { "AUCTION_HOUSE_BID_BUTTON" } },
  { "ibuy.back", "ItemBuyFrame.BackButton", { "AUCTION_HOUSE_BACK_BUTTON" } },
  { "cbuy.back", "CommoditiesBuyFrame.BackButton", { "AUCTION_HOUSE_BACK_BUTTON" } },
  { "isell.bidLabel", "ItemSellFrame.SecondaryPriceInput.Label", PRICE_LABEL },
  { "isell.bidLabelTitle", "ItemSellFrame.SecondaryPriceInput.LabelTitle", PRICE_LABEL },
  { "isell.buyoutMode", "ItemSellFrame.BuyoutModeCheckButton.Text", { "AUCTION_HOUSE_BUYOUT_MODE_CHECK_BOX" } },
  { "auctions.tab", "AuctionsFrame.AuctionsTab", { "AUCTION_HOUSE_AUCTIONS_SUB_TAB" } },
  { "auctions.bidsTab", "AuctionsFrame.BidsTab", { "AUCTION_HOUSE_BIDS_SUB_TAB" } },
  { "auctions.cancel", "AuctionsFrame.CancelAuctionButton", { "AUCTION_HOUSE_CANCEL_AUCTION_BUTTON" } },
  { "auctions.buyout", "AuctionsFrame.BuyoutFrame.BuyoutButton", { "AUCTION_HOUSE_BUYOUT_BUTTON" } },
  { "auctions.bid", "AuctionsFrame.BidFrame.BidButton", { "AUCTION_HOUSE_BID_BUTTON" } },
  { "dialog.buyNow", "BuyDialog.BuyNowButton", { "AUCTION_HOUSE_DIALOG_BUY_NOW" } },
  { "dialog.cancel", "BuyDialog.CancelButton", { "CANCEL" } }, { "dialog.okay", "BuyDialog.OkayButton", { "OKAY" } },
  { "dialog.notification", "BuyDialog.Notification.Text",
    { "AUCTION_HOUSE_DIALOG_PRICE_UPDATED", "AUCTION_HOUSE_DIALOG_PRICE_UNAVAILABLE" } },
  { "token.buyoutLabel", "WoWTokenResults.BuyoutLabel", { "TOKEN_CURRENT_BUYOUT_PRICE" } },
  { "token.buyoutPrice", "WoWTokenResults.BuyoutPrice", TOKEN_PRICE },
  { "token.buyout", "WoWTokenResults.Buyout", { "BUYOUT" } },
  { "token.needTime", "WoWTokenResults.GameTimeTutorial.LeftDisplay.Label", { "TUTORIAL_TOKEN_I_NEED_GAME_TIME" } },
  { "token.time1", "WoWTokenResults.GameTimeTutorial.LeftDisplay.Tutorial1",
    { "TUTORIAL_TOKEN_PAY_FOR_TIME_WITH_GOLD" } },
  { "token.time2", "WoWTokenResults.GameTimeTutorial.LeftDisplay.Tutorial2", { "TUTORIAL_TOKEN_GAME_TIME_STEP_1" } },
  { "token.time3", "WoWTokenResults.GameTimeTutorial.LeftDisplay.Tutorial3",
    { "TUTORIAL_TOKEN_GAME_TIME_STEP_2", "TUTORIAL_TOKEN_GAME_TIME_STEP_2_BALANCE" } },
  { "token.needGold", "WoWTokenResults.GameTimeTutorial.RightDisplay.Label", { "TUTORIAL_TOKEN_I_NEED_GOLD" } },
  { "token.gold1", "WoWTokenResults.GameTimeTutorial.RightDisplay.Tutorial1", { "TUTORIAL_TOKEN_SELL_FOR_GOLD" } },
  { "token.gold2", "WoWTokenResults.GameTimeTutorial.RightDisplay.Tutorial2", { "TUTORIAL_TOKEN_GOLD_STEP_1" } },
  { "token.gold3", "WoWTokenResults.GameTimeTutorial.RightDisplay.Tutorial3", { "TUTORIAL_TOKEN_GOLD_STEP_2" } },
  { "token.shop", "WoWTokenResults.GameTimeTutorial.RightDisplay.StoreButton", { "BLIZZARD_STORE" } },
  { "tokenSell.priceLabel", "WoWTokenSellFrame.BuyoutPriceLabel", { "TOKEN_CURRENT_MARKET_PRICE" } },
  { "tokenSell.price", "WoWTokenSellFrame.MarketPrice", TOKEN_PRICE },
  { "tokenSell.estimated", "WoWTokenSellFrame.EstimatedTime", { "ESTIMATED_TIME_TO_SELL" } },
  { "tokenSell.create", "WoWTokenSellFrame.CreateAuctionLabel", { "CREATE_AUCTION" } },
  { "tokenSell.post", "WoWTokenSellFrame.PostButton", { "AUCTION_HOUSE_POST_BUTTON" } },
}
-- the two sell frames share AuctionHouseSellFrameTemplate (sellframe.xml:163–259)
for _, sell in ipairs({ { "isell", "ItemSellFrame" }, { "csell", "CommoditiesSellFrame" } }) do
  local k, p = sell[1] .. ".", sell[2] .. "."
  local function add(rec, path, keys) LABELS[#LABELS + 1] = { k .. rec, p .. path, keys } end
  add("create", "CreateAuctionLabel", { "CREATE_AUCTION" })
  add("quantity", "QuantityInput.Label", { "AUCTION_HOUSE_QUANTITY_LABEL" })
  add("max", "QuantityInput.MaxButton", { "AUCTION_HOUSE_MAX_QUANTITY_BUTTON" })
  add("price", "PriceInput.Label", PRICE_LABEL)
  add("priceTitle", "PriceInput.LabelTitle", PRICE_LABEL)
  add("priceSubtext", "PriceInput.Subtext", { "AUCTION_HOUSE_BUYOUT_OPTIONAL_LABEL" })
  add("perItem", "PriceInput.PerItemPostfix", { "AUCTION_HOUSE_PER_ITEM_LABEL" })
  add("duration", "Duration.Label", { "AUCTION_HOUSE_DURATION_LABEL" })
  add("deposit", "Deposit.Label", { "AUCTION_HOUSE_DEPOSIT_LABEL" })
  add("total", "TotalPrice.Label", { "AUCTION_HOUSE_TOTAL_PRICE_LABEL" })
  add("post", "PostButton", { "AUCTION_HOUSE_POST_BUTTON" })
end

-- The nine lists: record prefix → path under AuctionHouseFrame.
local LISTS = {
  { "browse", "BrowseResultsFrame.ItemList" }, { "ibuy.list", "ItemBuyFrame.ItemList" },
  { "cbuy.list", "CommoditiesBuyFrame.ItemList" }, { "isell.list", "ItemSellList" },
  { "csell.list", "CommoditiesSellList" }, { "auctions.all", "AuctionsFrame.AllAuctionsList" },
  { "auctions.bids", "AuctionsFrame.BidsList" }, { "auctions.items", "AuctionsFrame.ItemList" },
  { "auctions.commodities", "AuctionsFrame.CommoditiesList" },
}
local DURATIONS = { { "isell.durationValue", "ItemSellFrame.Duration.Dropdown" },
  { "csell.durationValue", "CommoditiesSellFrame.Duration.Dropdown" } }

local SEARCHING = { only = { "SEARCHING" } }
local RESULTS = { only = { "BROWSE_NO_RESULTS", "AUCTION_HOUSE_BROWSE_FAVORITES_TIP", "ERR_AUCTION_DATABASE_ERROR" } }
local QUANTITY = { only = { "AUCTION_HOUSE_QUANTITY_AVAILABLE_FORMAT" } }
local HEADER = { only = { "AUCTION_HOUSE_BROWSE_HEADER_NAME", "AUCTION_HOUSE_BROWSE_HEADER_PRICE",
  "AUCTION_HOUSE_BROWSE_HEADER_CONTAINER_SLOTS", "AUCTION_HOUSE_BROWSE_HEADER_QUANTITY",
  "AUCTION_HOUSE_BROWSE_HEADER_RECIPE_SKILL", "AUCTION_HOUSE_BROWSE_HEADER_REQUIRED_LEVEL",
  "AUCTION_HOUSE_HEADER_ITEM", "AUCTION_HOUSE_HEADER_BID_PRICE", "AUCTION_HOUSE_HEADER_BUYOUT_PRICE",
  "AUCTION_HOUSE_HEADER_CURRENT_BID", "AUCTION_HOUSE_HEADER_SELLER", "AUCTION_HOUSE_HEADER_UNIT_PRICE",
  "REQ_LEVEL_ABBR" } }
local ROW = { only = { "AUCTION_HOUSE_NONE_AVAILABLE", "AUCTION_HOUSE_NONE_AVAILABLE_FORMAT",
  "AUCTION_HOUSE_INCOMING_AMOUNT", "AUCTION_HOUSE_NUM_SELLERS",
  "AUCTION_HOUSE_HIGHEST_BIDDER", "AUCTION_HOUSE_OUTBID", "AUCTION_HOUSE_SELLER_YOU", "TIME_LEFT_SHORT",
  "TIME_LEFT_MEDIUM", "TIME_LEFT_LONG", "TIME_LEFT_VERY_LONG" } }
-- appended / cell tooltip lines
local BANDS = { "AUCTION_HOUSE_TOOLTIP_TIME_LEFT_SHORT", "AUCTION_HOUSE_TOOLTIP_TIME_LEFT_MEDIUM",
  "AUCTION_HOUSE_TOOLTIP_TIME_LEFT_LONG", "AUCTION_HOUSE_TOOLTIP_TIME_LEFT_VERY_LONG" }
local SELLERS = { "AUCTION_HOUSE_TOOLTIP_SELLER_FORMAT", "AUCTION_HOUSE_TOOLTIP_MULTIPLE_SELLERS_FORMAT",
  "AUCTION_HOUSE_TOOLTIP_OVERFLOW_SELLERS_FORMAT" }
local function union(...)
  local out = {}
  for _, list in ipairs({ ... }) do for _, k in ipairs(list) do out[#out + 1] = k end end
  return out
end
local APPENDED_KEYS = { only = union(SELLERS, { "AUCTION_HOUSE_TOOLTIP_DURATION_FORMAT" }) }
AuctionHouse.APPENDED_KEYS = APPENDED_KEYS.only
local BID_TIP = { only = { "AUCTION_HOUSE_BUYER_FORMAT", "AUCTION_HOUSE_HIGH_BIDDER_FORMAT" } }
local PREFIX = { only = { "AUCTION_HOUSE_AUCTION_SOLD_PREFIX" } }
local TOKEN_SELL = "ESTIMATED_TIME_TO_SELL_LABEL"
local SUMMARY = { only = { "AUCTION_HOUSE_ALL_AUCTIONS", "AUCTION_HOUSE_ALL_BIDS" } }
local CATEGORY = { only = { "AUCTION_CATEGORY_WEAPONS", "AUCTION_CATEGORY_ARMOR", "AUCTION_CATEGORY_CONTAINERS",
  "AUCTION_CATEGORY_CONSUMABLES", "AUCTION_CATEGORY_TRADE_GOODS", "AUCTION_CATEGORY_PROJECTILE",
  "AUCTION_CATEGORY_RECIPES", "AUCTION_CATEGORY_QUEST_ITEMS", "AUCTION_CATEGORY_MISCELLANEOUS",
  "AUCTION_SUBCATEGORY_ONE_HANDED", "AUCTION_SUBCATEGORY_TWO_HANDED", "AUCTION_SUBCATEGORY_RANGED",
  "AUCTION_SUBCATEGORY_MISCELLANEOUS", "AUCTION_SUBCATEGORY_OTHER", "AUCTION_SUBCATEGORY_RELIC",
  "AUCTION_SUBCATEGORY_CLOAK", "AUCTION_SUBCATEGORY_STANDARD_CONTAINER", "AUCTION_SUBCATEGORY_AMMO_CONTAINER",
  "AUCTION_SUBCATEGORY_REAGENT_CONTAINER", "AUCTION_SUBCATEGORY_ITEM_ENHANCEMENT",
  -- the armour slots GetItemInventorySlotInfo names (camelot/blizzard_auctiondata.lua:68–106)
  "INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_BODY", "INVTYPE_CHEST", "INVTYPE_ROBE",
  "INVTYPE_WAIST", "INVTYPE_LEGS", "INVTYPE_FEET", "INVTYPE_WRIST", "INVTYPE_HAND", "INVTYPE_FINGER",
  "INVTYPE_TRINKET", "INVTYPE_WEAPON", "INVTYPE_SHIELD", "INVTYPE_RANGED", "INVTYPE_CLOAK", "INVTYPE_2HWEAPON",
  "INVTYPE_BAG", "INVTYPE_TABARD", "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPONOFFHAND", "INVTYPE_HOLDABLE",
  "INVTYPE_AMMO", "INVTYPE_THROWN", "INVTYPE_RANGEDRIGHT", "INVTYPE_QUIVER", "INVTYPE_RELIC" } }
local MULTISELL = { only = { "AUCTION_CREATING" } }
local DISABLE_TIP = { only = { "AUCTION_HOUSE_TOOLTIP_TITLE_NOT_ENOUGH_MONEY",
  "AUCTION_HOUSE_TOOLTIP_TITLE_OWN_AUCTION", "AUCTION_HOUSE_TOOLTIP_TITLE_NONE_AVAILABLE" } }
local POST_TIP = { only = { "AUCTION_HOUSE_SELL_FRAME_ERROR_ITEM", "AUCTION_HOUSE_SELL_FRAME_ERROR_DEPOSIT",
  "AUCTION_HOUSE_SELL_FRAME_ERROR_QUANTITY", "AUCTION_HOUSE_SELL_FRAME_ERROR_PRICE",
  "AUCTION_HOUSE_SELL_FRAME_ERROR_BUYOUT", "ERR_GENERIC_THROTTLE" } }
local FAVORITE_TIP = { only = { "AUCTION_HOUSE_FAVORITES_MAXED_TOOLTIP" } }
local OWNED_TIP = { only = union({ "AUCTION_HOUSE_OWNED_COMMODITIES_LINE_TOOLTIP_TITLE",
  "AUCTION_HOUSE_OWNED_COMMODITIES_LINE_TOOLTIP_TEXT", "AUCTION_HOUSE_TIME_LEFT_FORMAT_ACTIVE" }, SELLERS, BANDS) }
-- Help-tooltip owners: path under AuctionHouseFrame → the keys its tooltip may show.
local TOOLTIPS = {
  { "ItemBuyFrame.BidFrame.BidButton", DISABLE_TIP }, { "ItemBuyFrame.BuyoutFrame.BuyoutButton", DISABLE_TIP },
  { "AuctionsFrame.BidFrame.BidButton", DISABLE_TIP }, { "AuctionsFrame.BuyoutFrame.BuyoutButton", DISABLE_TIP },
  { "CommoditiesBuyFrame.BuyDisplay.BuyButton", DISABLE_TIP }, { "BuyDialog.BuyNowButton", DISABLE_TIP },
  { "ItemSellFrame.PostButton", POST_TIP }, { "CommoditiesSellFrame.PostButton", POST_TIP },
  { "ItemSellFrame.PriceInput.PriceError", { only = { "AUCTION_BUYOUT_ERROR" } } },
  { "ItemSellFrame.BuyoutModeCheckButton", { only = { "AUCTION_HOUSE_BUYOUT_MODE_TOOLTIP" } } },
  { "SearchBar.FavoritesSearchButton", { only = { "AUCTION_HOUSE_FAVORITES_SEARCH_TOOLTIP_TITLE",
    "AUCTION_HOUSE_FAVORITES_SEARCH_TOOLTIP_NO_FAVORITES" } } },
  { "ItemBuyFrame.ItemDisplay.FavoriteButton", FAVORITE_TIP },
  { "CommoditiesBuyFrame.BuyDisplay.ItemDisplay.FavoriteButton", FAVORITE_TIP },
  { "AuctionsFrame.ItemDisplay.FavoriteButton", FAVORITE_TIP },
  { "WoWTokenResults.Buyout", { only = { "ERR_NOT_ENOUGH_GOLD", "TOKEN_TRY_AGAIN_LATER" } } },
  { "BuyDialog.Notification.Button", { only = { "AUCTION_HOUSE_DIALOG_PER_UNIT_INCREASE",
    "AUCTION_HOUSE_DIALOG_TOTAL_INCREASE" } } },
  { "WoWTokenResults.InvisiblePriceFrame", { only = { "TOKEN_BUYOUT_PRICE_UPDATES" } } },
  { "WoWTokenResults.GameTimeTutorial.RightDisplay.StoreButton", { only = { "ERR_FEATURE_RESTRICTED_TRIAL" } } },
  { "WoWTokenSellFrame.InvisiblePriceFrame", { only = { "TOKEN_CREATE_AUCTION_LOCKED_PRICE" } } },
}
local REFRESH_TIP = { only = { "AUCTION_HOUSE_REFRESH_BUTTON_TOOLTIP" } }

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  Compat.declare(SURFACE, "frame", { F })
  Compat.declare(SURFACE, "multisell", { "AuctionHouseMultisellProgressFrame" })
  Compat.declare(SURFACE, "scrollUtil", { "ScrollUtil" })
  Compat.declare(SURFACE, "categorySetUp", { "AuctionHouseFilterButton_SetUp" })
  Compat.declare(SURFACE, "tokenUpdate", { "BrowseWowTokenResults_Update" })
  Compat.declare(SURFACE, "util", { "AuctionHouseUtil" })
  Compat.declare(SURFACE, "summary", { F .. ".AuctionsFrame.SummaryList.ScrollBox" })
  Compat.declare(SURFACE, "tokenTutorial", { F .. ".WoWTokenResults.GameTimeTutorial" })
  Compat.declare(SURFACE, "tokenSell", { F .. ".WoWTokenSellFrame" })
  Compat.declare(SURFACE, "priceInput", { F .. ".ItemSellFrame.PriceInput" })
  Compat.declare(SURFACE, "dialog", { F .. ".BuyDialog" })
  for _, l in ipairs(LABELS) do Compat.declare(SURFACE, l[1], { F .. "." .. l[2] }) end
  for _, l in ipairs(LISTS) do Compat.declare(SURFACE, l[1], { F .. "." .. l[2] }) end
  for _, d in ipairs(DURATIONS) do Compat.declare(SURFACE, d[1], { F .. "." .. d[2] }) end
  for i, t in ipairs(TOOLTIPS) do Compat.declare(SURFACE, "tip" .. i, { F .. "." .. t[1] }) end
end

local LABEL_OPTS = {}
for _, l in ipairs(LABELS) do LABEL_OPTS[l[1]] = { only = l[3] } end

local headerKey = WFJ.Labels.keyer("header.") -- pooled column headers
local cellKey = WFJ.Labels.keyer("cell.") -- pooled row cells
local summaryKey = WFJ.Labels.keyer("summary.") -- pooled summary lines
local categoryKey = WFJ.Labels.keyer("category.") -- pooled category buttons
local prefixKey = WFJ.Labels.keyer("prefix.") -- the item cells' "Sold:" prefix

-- tokenSell: a WoW Token row's time-left tooltip line "|cffffffffEstimated Time To Sell:|n|r<band>" (the band
-- in Japanese when it is one, as written otherwise). → the number of lines shown
function AuctionHouse.onCellTooltip()
  local tt = WFJ.HelpTooltip and Compat.get(WFJ.HelpTooltip.SURFACE, "tooltip")
  local index = WFJ.UIIndex
  if type(tt) ~= "table" or not index or type(tt.NumLines) ~= "function" then return 0 end
  local en = Compat.resolve(TOKEN_SELL)
  if type(en) ~= "string" then return 0 end
  local n = 0
  for i = 1, tt:NumLines() or 0 do
    local fs = Compat.resolve(tt:GetName() .. "TextLeft" .. i)
    local text = type(fs) == "table" and fs:GetText() or nil
    local open, label, close, rest = (text or ""):match("^(|c%x%x%x%x%x%x%x%x)(.-)(|r)(.*)$")
    if label == en and index:exactKey(label) then
      local band = WFJ.Labels.part(rest, BANDS) or rest
      n = n + WFJ.Labels.showArgs(SURFACE .. ".token", "L" .. i, fs, TOKEN_SELL,
        { form = "seq", parts = { { key = TOKEN_SELL, open = open, close = close }, band } })
    end
  end
  if n > 0 and type(tt.Show) == "function" then tt:Show() end
  return n
end

local cellHooked = setmetatable({}, { __mode = "k" })

-- One row's cells (row.cells is the table builder's, tablebuilder.lua:335–339). The row owns the commodities list's
-- "your auction" tooltip (commoditieslist.lua:140–146) and a favorite cell's button the favorites-full tooltip
-- (sharedtemplates.lua:744–754, tablebuilder.xml:72). → the number of dictionary words
local function showRow(row)
  local cells = type(row) == "table" and row.cells or nil
  if type(cells) ~= "table" then return 0 end
  WFJ.HelpTooltip.register(row, OWNED_TIP)
  local n = 0
  for _, cell in ipairs(cells) do
    local text = type(cell) == "table" and cell.Text or nil
    if type(text) == "table" then n = n + WFJ.Labels.show(SURFACE, cellKey(text), text, nil, ROW) end
    local favorite = type(cell) == "table" and cell.FavoriteButton or nil
    if type(favorite) == "table" then WFJ.HelpTooltip.register(favorite, FAVORITE_TIP) end
    if type(cell) == "table" then
      WFJ.HelpTooltip.register(cell, BID_TIP)
      if type(cell.Prefix) == "table" then
        n = n + WFJ.Labels.show(SURFACE, prefixKey(cell.Prefix), cell.Prefix, nil, PREFIX)
      end
      if not cellHooked[cell] and type(cell.ShowTooltip) == "function" then
        cellHooked[cell] = true
        hooksecurefunc(cell, "ShowTooltip", AuctionHouse.onCellTooltip)
      end
    end
  end
  return n
end

-- ScrollUtil callback: (owner, frame, elementData) on initialization, (frame, elementData) on the existing-frames
-- pass. Returns nothing (ForEachFrame stops at the first truthy return).
function AuctionHouse.onRow(a, b)
  showRow(a == AuctionHouse and b or a)
end

-- One list's texts as they are now. → the number of dictionary words found
function AuctionHouse.showList(prefix, list)
  if type(list) ~= "table" then return 0 end
  local show = WFJ.Labels.show
  local spinner, refresh = list.LoadingSpinner, list.RefreshFrame
  local n = show(SURFACE, prefix .. ".searching", type(spinner) == "table" and spinner.SearchingText or nil, nil,
    SEARCHING)
  n = n + show(SURFACE, prefix .. ".results", list.ResultsText, nil, RESULTS)
  n = n + show(SURFACE, prefix .. ".quantity", type(refresh) == "table" and refresh.TotalQuantity or nil, nil,
    QUANTITY)
  local builder = list.tableBuilder
  if type(builder) == "table" and type(builder.EnumerateHeaders) == "function" then
    for header in builder:EnumerateHeaders() do
      if type(header) == "table" then n = n + show(SURFACE, headerKey(header), header, nil, HEADER) end
    end
  end
  local box = list.ScrollBox
  if type(box) == "table" and type(box.ForEachFrame) == "function" then
    box:ForEachFrame(function(row) n = n + showRow(row) end)
  end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- ScrollUtil callback for a summary line (same argument shapes as onRow; returns nothing).
function AuctionHouse.onSummaryLine(a, b)
  local line = a == AuctionHouse and b or a
  local text = type(line) == "table" and line.Text or nil
  if type(text) == "table" then WFJ.Labels.show(SURFACE, summaryKey(text), text, nil, SUMMARY) end
end

-- hooksecurefunc target (AuctionHouseFilterButton_SetUp(button, info)). → 1 | 0
function AuctionHouse.onCategory(button)
  if type(button) ~= "table" then return 0 end
  return WFJ.Labels.show(SURFACE, categoryKey(button), button, nil,
    WFJ.Labels.familiesWith(CATEGORY.only, "ItemSubClassName"))
end

-- hooksecurefunc target (AuctionHouseMultisellProgressFrame:Start / :Refresh). → 1 | 0
function AuctionHouse.onMultisell()
  local frame = get("multisell")
  local bar = type(frame) == "table" and frame.ProgressBar or nil
  return WFJ.Labels.show(SURFACE, "multisell", type(bar) == "table" and bar.Text or nil, nil, MULTISELL)
end

-- The whole window as it is now (OnShow, SetDisplayMode and every writer hook). → the number of dictionary words
function AuctionHouse.showAll()
  local n = WFJ.Labels.title(SURFACE, get("frame"), TITLE)
    + WFJ.Labels.title(SURFACE, get("tokenTutorial"), TOKEN_TITLE, "token.title")
  for _, l in ipairs(LABELS) do n = n + WFJ.Labels.show(SURFACE, l[1], get(l[1]), nil, LABEL_OPTS[l[1]]) end
  for _, d in ipairs(DURATIONS) do n = n + WFJ.Labels.dropdown(SURFACE, d[1], get(d[1])) end
  for _, l in ipairs(LISTS) do n = n + AuctionHouse.showList(l[1], get(l[1])) end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

function AuctionHouse.release()
  WFJ.Render.release(SURFACE .. ".token")
  return WFJ.Render.release(SURFACE)
end

-- itemAppended: hooksecurefunc target (AuctionHouseUtil.AddAuctionHouseTooltipInfo(tooltip, rowData, …)).
function AuctionHouse.onAppended(tooltip)
  return WFJ.HelpTooltip.appended(tooltip, APPENDED_KEYS)
end

local function hook(target, method, fn)
  if type(target) == "table" and type(target[method]) == "function" then hooksecurefunc(target, method, fn) end
end

local function hookList(prefix, list, util)
  if type(list) ~= "table" then return end
  local function shown() AuctionHouse.showList(prefix, list) end
  for _, method in ipairs({ "SetState", "SetCustomError", "UpdateTableBuilderLayout", "RefreshScrollFrame" }) do
    hook(list, method, shown)
  end
  local refresh = list.RefreshFrame
  if type(refresh) == "table" then
    hook(refresh, "SetQuantity", shown)
    WFJ.HelpTooltip.register(refresh.RefreshButton, REFRESH_TIP)
  end
  if type(util) == "table" and type(util.AddInitializedFrameCallback) == "function"
      and type(list.ScrollBox) == "table" then
    util.AddInitializedFrameCallback(list.ScrollBox, AuctionHouse.onRow, AuctionHouse, true)
  end
end

local hooked, waiting = false, false

-- Runs once Blizzard_AuctionHouseUI is loaded (now, or on its ADDON_LOADED). Declared again here: a declare clears
-- Compat's memo, which holds `false` for a name looked up before the addon loaded.
function AuctionHouse.setup()
  declare()
  local frame = get("frame")
  if hooked or type(frame) ~= "table" then return false end
  hooked = true
  WFJ.Labels.forbidNames(AuctionHouse.NEVER_TOUCH) -- its widgets exist only now (Main's pass ran before the load)
  hook(frame, "SetDisplayMode", AuctionHouse.showAll)
  if type(frame.HookScript) == "function" then
    frame:HookScript("OnShow", AuctionHouse.showAll)
    frame:HookScript("OnHide", AuctionHouse.release)
  end
  local priceInput = get("priceInput")
  hook(priceInput, "SetLabel", AuctionHouse.showAll)
  hook(priceInput, "SetSubtext", AuctionHouse.showAll)
  hook(get("dialog"), "SetState", AuctionHouse.showAll)
  hook(get("tokenSell"), "Refresh", AuctionHouse.showAll)
  if type(get("tokenUpdate")) == "function" then
    hooksecurefunc("BrowseWowTokenResults_Update", AuctionHouse.showAll)
  end
  if type(get("categorySetUp")) == "function" then
    hooksecurefunc("AuctionHouseFilterButton_SetUp", AuctionHouse.onCategory)
  end
  local ahUtil = get("util")
  if type(ahUtil) == "table" and type(ahUtil.AddAuctionHouseTooltipInfo) == "function" then
    hooksecurefunc(ahUtil, "AddAuctionHouseTooltipInfo", AuctionHouse.onAppended)
  end
  local tutorial = get("tokenTutorial")
  if type(tutorial) == "table" and type(tutorial.HookScript) == "function" then
    tutorial:HookScript("OnShow", AuctionHouse.showAll)
  end
  local multisell = get("multisell")
  hook(multisell, "Start", AuctionHouse.onMultisell)
  hook(multisell, "Refresh", AuctionHouse.onMultisell)
  local util = get("scrollUtil")
  for _, l in ipairs(LISTS) do hookList(l[1], get(l[1]), util) end
  local summary = get("summary")
  if type(summary) == "table" and type(util) == "table" and type(util.AddInitializedFrameCallback) == "function" then
    util.AddInitializedFrameCallback(summary, AuctionHouse.onSummaryLine, AuctionHouse, true)
  end
  for i, t in ipairs(TOOLTIPS) do WFJ.HelpTooltip.register(get("tip" .. i), t[2]) end
  AuctionHouse.showAll() -- what the client already wrote (the addon may load after the frame was shown)
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init. → true when the window
-- exists now, false while it waits for Blizzard_AuctionHouseUI.
function AuctionHouse.init()
  declare()
  if hooked then return false end
  if not waiting then
    waiting = true
    return WFJ.LoadOnDemand.when(ADDON, AuctionHouse.setup) and hooked
  end
  return false
end
