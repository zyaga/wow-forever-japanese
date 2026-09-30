-- UI/BlackMarket.lua: the black market auction window on Forever (surfaces "blackmarket" and "blackmarket.static",
-- area "ui", ADR-016 / ADR-029). Load-on-demand Blizzard_BlackMarketUI (blizzard_blackmarketui.toc); its
-- [Bootstrap] file registers Enum.PlayerInteractionType.BlackMarketAuctioneer at login
-- (blizzard_blackmarketui_bootstrap.lua:20–31), so the window opens when an NPC sends that interaction. Set up through
-- WFJ.LoadOnDemand.when.
-- Static labels (XML text= or an inline OnLoad; each restricted to its own key), on "blackmarket.static":
--   HotDeal.Title HOT_ITEM (:363), HotDeal.SellerTAG HOT_ITEM_SELLER (:408),
--   HotDeal.BlackMarketHotItemBidPrice.CurrentBid BLACK_MARKET_HOT_ITEM_CURRENT_BID (:512) and .YourBid
--   BLACK_MARKET_YOUR_BID (:518);
--   the six column headers' .Name: NAME, REQ_LEVEL_ABBR, TYPE, CLOSES_IN, AUCTION_CREATOR, CURRENT_BID (:535–600);
--   Inset.NoItems BLACK_MARKET_NO_ITEMS (:615), BidButton BID (:653), and the unnamed BID label of
--   BlackMarketBidPrice (:669).
-- Dynamic, on "blackmarket" (released on the frame's OnHide):
--   BlackMarketFrame_UpdateHotItem (a global, called by name from OnEvent, blizzard_blackmarketui.lua:143, 170–218)
--     → HotDeal.TimeLeft.Text format(BLACK_MARKET_HOT_ITEM_TIME_LEFT, AUCTION_TIME_LEFT<n>) (:211); HotDeal.TimeLeft
--     owns a tooltip of AUCTION_TIME_LEFT<n>_DETAIL (:212, xml:493–498);
--   the pooled rows (BlackMarketItemTemplate in BlackMarketFrame.ScrollBox; BlackMarketItemMixin:Init, lua:70–120),
--     walked from the ScrollBox's initialized-frame callback after the element initializer (lua:36–39): YourBid
--     (BLACK_MARKET_YOUR_BID, xml:89), TimeLeft.Text AUCTION_TIME_LEFT<n> (lua:113), and the TimeLeft button's tooltip
--     AUCTION_TIME_LEFT<n>_DETAIL (lua:114, xml:192–199). Rows are keyed by widget, never by position.
-- Never touched: the window's title, an unnamed FontString BLACK_MARKET_TITLE "Black Market / Auction House"
-- (blizzard_blackmarketui.xml:348): a place's name, and a bare Auction House label ships as the English
-- (translation_glossary.tsv); the item names (HotDeal.Name, a row's Name), sellers
-- (HotDeal.Seller, a row's Seller; the row's widgets are never read), item types and levels (client data), money,
-- and the bid EditBoxes.
-- The bid confirmation is a StaticPopup (BID_BLACKMARKET, lua:5–16): ADR-015 §5, not this surface.
local _, WFJ = ...
local BlackMarket = {}
WFJ.BlackMarket = BlackMarket

local SURFACE = "blackmarket"
BlackMarket.SURFACE = SURFACE
local STATIC = SURFACE .. ".static"
local Compat = WFJ.Compat
local ADDON = "Blizzard_BlackMarketUI"
local FRAME = "BlackMarketFrame"
local HOT = FRAME .. ".HotDeal"

BlackMarket.NEVER_TOUCH = { HOT .. ".Name", HOT .. ".Seller", HOT .. ".Type", HOT .. ".Level",
  "BlackMarketBidPriceGold", "BlackMarketBidPriceSilver", "BlackMarketBidPriceCopper" }

-- Static labels: record key → { candidate, the one key it shows }.
local STATIC_LABELS = {
  hotTitle = { HOT .. ".Title", "HOT_ITEM" }, sellerTag = { HOT .. ".SellerTAG", "HOT_ITEM_SELLER" },
  hotCurrentBid = { HOT .. ".BlackMarketHotItemBidPrice.CurrentBid", "BLACK_MARKET_HOT_ITEM_CURRENT_BID" },
  hotYourBid = { HOT .. ".BlackMarketHotItemBidPrice.YourBid", "BLACK_MARKET_YOUR_BID" },
  columnName = { FRAME .. ".ColumnName.Name", "NAME" },
  columnLevel = { FRAME .. ".ColumnLevel.Name", "REQ_LEVEL_ABBR" },
  columnType = { FRAME .. ".ColumnType.Name", "TYPE" },
  columnDuration = { FRAME .. ".ColumnDuration.Name", "CLOSES_IN" },
  columnHighBidder = { FRAME .. ".ColumnHighBidder.Name", "AUCTION_CREATOR" },
  columnCurrentBid = { FRAME .. ".ColumnCurrentBid.Name", "CURRENT_BID" },
  noItems = { FRAME .. ".Inset.NoItems", "BLACK_MARKET_NO_ITEMS" }, bidButton = { FRAME .. ".BidButton", "BID" },
}
local STATIC_ORDER = {}
for key in pairs(STATIC_LABELS) do STATIC_ORDER[#STATIC_ORDER + 1] = key end
table.sort(STATIC_ORDER)

-- Unnamed labels, found by the client's English among a frame's regions: record key → { frame candidate, key }.
local REGIONS = { bidLabel = { "BlackMarketBidPrice", "BID" } }
local REGION_ORDER = { "bidLabel" }

local HOT_TIME = { only = { "BLACK_MARKET_HOT_ITEM_TIME_LEFT" } }
local TIME_LEFT = { only = { "AUCTION_TIME_LEFT0", "AUCTION_TIME_LEFT1", "AUCTION_TIME_LEFT2", "AUCTION_TIME_LEFT3",
  "AUCTION_TIME_LEFT4" } }
local TIME_DETAIL = { only = { "AUCTION_TIME_LEFT0_DETAIL", "AUCTION_TIME_LEFT1_DETAIL",
  "AUCTION_TIME_LEFT2_DETAIL", "AUCTION_TIME_LEFT3_DETAIL", "AUCTION_TIME_LEFT4_DETAIL" } }
local YOUR_BID = { only = { "BLACK_MARKET_YOUR_BID" } }

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  Compat.declare(SURFACE, "frame", { FRAME })
  Compat.declare(SURFACE, "hotTime", { HOT .. ".TimeLeft.Text" })
  Compat.declare(SURFACE, "hotTimeOwner", { HOT .. ".TimeLeft" })
  Compat.declare(SURFACE, "scrollBox", { FRAME .. ".ScrollBox" })
  Compat.declare(SURFACE, "scrollUtil", { "ScrollUtil" })
  Compat.declare(SURFACE, "updateHotItem", { "BlackMarketFrame_UpdateHotItem" })
  for key, label in pairs(STATIC_LABELS) do Compat.declare(SURFACE, "static." .. key, { label[1] }) end
  for key, region in pairs(REGIONS) do Compat.declare(SURFACE, "region." .. key, { region[1] }) end
end

-- The labels the client writes once at load. → the number of dictionary words found.
function BlackMarket.showStatic()
  local items = {}
  for _, key in ipairs(STATIC_ORDER) do
    items[#items + 1] = { key, get("static." .. key), { only = { STATIC_LABELS[key][2] } } }
  end
  for _, key in ipairs(REGION_ORDER) do
    local k = REGIONS[key][2]
    items[#items + 1] = { key, WFJ.Labels.region(get("region." .. key), k), { only = { k } } }
  end
  return WFJ.Labels.showAll(STATIC, items)
end

-- hooksecurefunc target (BlackMarketFrame_UpdateHotItem). → 1 | 0
function BlackMarket.onHotItem()
  local n = WFJ.Labels.show(SURFACE, "hotTime", get("hotTime"), nil, HOT_TIME)
  WFJ.Render.updateBanner(SURFACE)
  return n
end

local rowKey = WFJ.Labels.keyer("row.") -- a pooled row's record key prefix (records follow the widget)

-- One pooled row after its initializer ran (ScrollUtil's initialized-frame callback: (owner, frame, elementData) for a
-- new row, (frame, elementData) for the iterateExisting pass). Returns nothing: ForEachFrame stops at the first truthy
-- return.
function BlackMarket.onRow(a, b)
  local row = a
  if a == BlackMarket then row = b end
  if type(row) ~= "table" then return end
  local key = rowKey(row)
  if type(row.YourBid) == "table" then WFJ.Labels.show(SURFACE, key .. ".yourBid", row.YourBid, nil, YOUR_BID) end
  local timeLeft = row.TimeLeft
  if type(timeLeft) == "table" then
    if type(timeLeft.Text) == "table" then
      WFJ.Labels.show(SURFACE, key .. ".time", timeLeft.Text, nil, TIME_LEFT)
    end
    WFJ.HelpTooltip.register(timeLeft, TIME_DETAIL)
  end
  WFJ.Render.updateBanner(SURFACE)
end

function BlackMarket.release()
  return WFJ.Render.release(SURFACE)
end

local hooked = false

-- The Blizzard_BlackMarketUI part: runs once that addon is loaded (now, or on its ADDON_LOADED). → true when hooked
function BlackMarket.setup()
  declare() -- its frames exist only now: forget what Compat memoized before
  local frame = get("frame")
  if type(frame) ~= "table" then return false end
  WFJ.Labels.forbidNames(BlackMarket.NEVER_TOUCH) -- its widgets exist only now
  BlackMarket.showStatic()
  if hooked then return false end
  hooked = true
  if type(get("updateHotItem")) == "function" then
    hooksecurefunc("BlackMarketFrame_UpdateHotItem", BlackMarket.onHotItem)
  end
  local owner = get("hotTimeOwner")
  if type(owner) == "table" then WFJ.HelpTooltip.register(owner, TIME_DETAIL) end
  local box, util = get("scrollBox"), get("scrollUtil")
  if type(box) == "table" and type(box.ForEachFrame) == "function" and type(util) == "table"
      and type(util.AddInitializedFrameCallback) == "function" then
    util.AddInitializedFrameCallback(box, BlackMarket.onRow, BlackMarket, true)
  end
  if type(frame.HookScript) == "function" then
    frame:HookScript("OnShow", BlackMarket.showStatic)
    frame:HookScript("OnHide", BlackMarket.release)
  end
  BlackMarket.onHotItem()
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init. → true when the window
-- was set up now; false while it waits for the addon.
function BlackMarket.init()
  declare()
  local result = false
  WFJ.LoadOnDemand.when(ADDON, function() result = BlackMarket.setup() end)
  return result
end
