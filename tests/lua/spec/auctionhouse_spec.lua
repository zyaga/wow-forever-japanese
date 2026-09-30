-- UI/AuctionHouse.lua over an AuctionHouseFrame replayed from camelot
-- blizzard_auctionhouseui (shared/blizzard_auctionhouseframe.xml:4–197, frame.lua:541–651, itemlist.lua:254–270,
-- tablebuilder.lua:884–885, sharedtemplates.lua:632–637, categorieslist.lua:91–92), load-on-demand in both load
-- orders. Item, seller and category names from the client tables stay English. Client writes go to `fs.text`.
local Stub = require("tests.lua.spec.wow_stub")
local C = require("tests.lua.spec.stub_commerce")

local ADDON = "Blizzard_AuctionHouseUI"
local GLOBALS = { "AuctionHouseFrame", "AuctionHouseMultisellProgressFrame", "AuctionHouseFilterButton_SetUp",
  "BrowseWowTokenResults_Update" }

-- Forever GlobalStrings (build 1.60.1.69913) → a test Japanese
local UI = {
  AUCTION_HOUSE_FRAME_TITLE_BUY = { "Browse Auctions", "オークションを見る" },
  AUCTION_HOUSE_FRAME_TITLE_SELL = { "Post Auctions", "出品する" },
  AUCTION_HOUSE_AUCTIONS_SUB_TAB = { "Auctions", "オークション" },
  AUCTION_HOUSE_BUY_TAB = { "Buy", "購入" }, AUCTION_HOUSE_SELL_TAB = { "Sell", "売却" },
  AUCTION_HOUSE_SEARCH_BUTTON = { "Search", "検索" },
  AUCTION_HOUSE_UNIT_PRICE_LABEL = { "Unit Price", "単価" }, AUCTION_HOUSE_BUYOUT_LABEL = { "Buyout Price", "即決価格" },
  AUCTION_HOUSE_BUYOUT_OPTIONAL_LABEL = { "|cff777777(Optional)|r", "|cff777777(任意)|r" },
  AUCTION_HOUSE_POST_BUTTON = { "Create Auction", "出品" }, AUCTION_HOUSE_BID_BUTTON = { "Bid", "入札" },
  AUCTION_HOUSE_DIALOG_PRICE_UPDATED = { "Price updated to the cheapest available.", "最安値に更新されました。" },
  SEARCHING = { "Searching...", "検索中..." }, BROWSE_NO_RESULTS = { "No items found", "アイテムが見つかりません" },
  AUCTION_HOUSE_QUANTITY_AVAILABLE_FORMAT = { "%s Available", "%s個出品中" },
  AUCTION_HOUSE_BROWSE_HEADER_NAME = { "Name", "名前" }, AUCTION_HOUSE_BROWSE_HEADER_PRICE = { "Price", "価格" },
  AUCTION_HOUSE_NUM_SELLERS = { "%d Sellers", "出品者%d人" },
  AUCTION_HOUSE_NONE_AVAILABLE = { "None available", "出品なし" },
  AUCTION_HOUSE_ALL_AUCTIONS = { "All Auctions", "すべてのオークション" },
  AUCTION_CATEGORY_WEAPONS = { "Weapons", "武器" }, AUCTION_CREATING = { "Creating %d/%d", "出品中 %d/%d" },
  AUCTION_HOUSE_TOOLTIP_TITLE_NOT_ENOUGH_MONEY = { "You don't have enough money", "所持金が足りません" },
  AUCTION_HOUSE_REFRESH_BUTTON_TOOLTIP = { "Refresh", "更新" },
  TOKEN_CURRENT_BUYOUT_PRICE = { "Buyout Price", "即決価格" }, AUCTION_DURATION_THREE = { "24 Hours", "24時間" },
  AUCTION_HOUSE_FAVORITES_MAXED_TOOLTIP = { "Your favorites list is full.", "お気に入りリストがいっぱいです。" },
  AUCTION_HOUSE_OWNED_COMMODITIES_LINE_TOOLTIP_TITLE = { "Your Auction", "自分のオークション" },
  TOKEN_BUYOUT_PRICE_UPDATES = { "This is the current market price of WoW Tokens.", "WoW Tokenの現在の相場です。" },
  TUTORIAL_TOKEN_ABOUT_TOKENS = { "About WoW Tokens", "WoW Tokenについて" }, -- the token tutorial's title
  ERR_NOT_ENOUGH_GOLD = { "Not enough gold", "ゴールドが足りない" },
  -- dictionary words that are also things the window shows as names
  SWORDS = { "Swords", "剣" },
  -- "Back" owns its Japanese on the buy frame; the cloak slot keeps its own
  AUCTION_HOUSE_BACK_BUTTON = { "Back", "戻る" }, INVTYPE_CLOAK = { "Back", "背中" },
  -- a sub category is an item sub-class name (the ItemSubClassName family) or an armour slot
  ["ItemSubClassName:2:10"] = { "Staves", "杖" }, INVTYPE_HEAD = { "Head", "頭" },
}

local function en(key) return _G[key] end

local function makeList()
  local list = CreateFrame("Frame")
  C.tree(list, { ["LoadingSpinner.SearchingText"] = en("SEARCHING"), ResultsText = "",
    ["RefreshFrame.TotalQuantity"] = "" })
  list.RefreshFrame.RefreshButton = Stub.button(nil, "")
  function list.RefreshFrame.SetQuantity(self, n)
    self.TotalQuantity.text = n ~= 0 and string.format(en("AUCTION_HOUSE_QUANTITY_AVAILABLE_FORMAT"), n) or ""
  end
  list.ScrollBox = Stub.scrollBox()
  local headers = C.pool(function() return Stub.button(nil, "") end)
  list.tableBuilder = { EnumerateHeaders = function() return headers:EnumerateActive() end }
  function list.UpdateTableBuilderLayout(_, titles) -- the layout function re-acquires every header (tablebuilder.lua)
    headers:ReleaseAll()
    for _, title in ipairs(titles) do headers:Acquire():SetText(title) end
  end
  function list.SetState(self, state)
    self.ResultsText.text = state == "none" and en("BROWSE_NO_RESULTS") or ""
    self.RefreshFrame:SetQuantity(state == "results" and 1234 or 0)
  end
  function list.SetCustomError(self, text) self.ResultsText.text = text end
  function list.RefreshScrollFrame() end
  -- a row the table builder filled: cells[i].Text (tablebuilder.lua:323–341)
  function list.addRow(self, texts)
    local row = { cells = {} }
    for i, text in ipairs(texts) do row.cells[i] = { Text = Stub.fontString(text), FavoriteButton = Stub.button() } end
    self.ScrollBox:initFrame(row, {})
    return row
  end
  return list
end

local function loadAuctionHouse()
  local frame = C.window("AuctionHouseFrame")
  C.tree(frame, {
    BuyTab = { button = en("AUCTION_HOUSE_BUY_TAB") }, SellTab = { button = en("AUCTION_HOUSE_SELL_TAB") },
    AuctionsTab = { button = en("AUCTION_HOUSE_AUCTIONS_SUB_TAB") },
    ["SearchBar.SearchButton"] = { button = en("AUCTION_HOUSE_SEARCH_BUTTON") },
    ["ItemSellFrame.PriceInput.Label"] = en("AUCTION_HOUSE_UNIT_PRICE_LABEL"),
    ["ItemSellFrame.PriceInput.LabelTitle"] = en("AUCTION_HOUSE_UNIT_PRICE_LABEL"),
    ["ItemSellFrame.PriceInput.Subtext"] = "",
    ["ItemSellFrame.PostButton"] = { button = en("AUCTION_HOUSE_POST_BUTTON") },
    ["ItemSellFrame.ItemDisplay.Name"] = "Searching...", -- an item named like a dictionary word
    ["ItemSellFrame.Duration.Dropdown.Text"] = en("AUCTION_DURATION_THREE"),
    ["ItemBuyFrame.BidFrame.BidButton"] = { button = en("AUCTION_HOUSE_BID_BUTTON") },
    ["ItemBuyFrame.BackButton"] = { button = en("AUCTION_HOUSE_BACK_BUTTON") },
    ["BuyDialog.Notification.Text"] = "", ["WoWTokenResults.BuyoutLabel"] = en("TOKEN_CURRENT_BUYOUT_PRICE"),
    ["AuctionsFrame.SummaryList"] = { frame = true },
    ["ItemBuyFrame.ItemDisplay.FavoriteButton"] = { button = "" },
    ["WoWTokenResults.Buyout"] = { button = "Buyout" }, ["WoWTokenResults.InvisiblePriceFrame"] = { frame = true },
  })
  -- the WoW Token game-time tutorial's title: SetTitle(TUTORIAL_TOKEN_ABOUT_TOKENS)
  -- (shared/blizzard_auctionhousewowtokenframe.lua:356), a PortraitFrame title
  local tutorial = CreateFrame("Frame")
  tutorial.TitleContainer = { TitleText = Stub.fontString(en("TUTORIAL_TOKEN_ABOUT_TOKENS")) }
  function tutorial.SetTitle(self, text) self.TitleContainer.TitleText.text = text end
  frame.WoWTokenResults.GameTimeTutorial = tutorial
  local price = frame.ItemSellFrame.PriceInput
  function price.SetLabel(self, text) self.Label.text, self.LabelTitle.text = text, text end
  function price.SetSubtext(self, text) self.Subtext.text = text or "" end
  function frame.BuyDialog.SetState(self, text) self.Notification.Text.text = text end
  function frame.ItemSellFrame.Duration.Dropdown.UpdateText() end
  frame.BrowseResultsFrame = { ItemList = makeList() }
  frame.ItemSellList = makeList()
  frame.AuctionsFrame.SummaryList.ScrollBox = Stub.scrollBox()
  function frame.SetDisplayMode(self, mode)
    self:SetTitle(en(mode == "sell" and "AUCTION_HOUSE_FRAME_TITLE_SELL" or "AUCTION_HOUSE_FRAME_TITLE_BUY"))
  end
  local multisell = CreateFrame("Frame", "AuctionHouseMultisellProgressFrame")
  C.tree(multisell, { ["ProgressBar.Text"] = "" })
  function multisell.Refresh(self, n, total)
    self.ProgressBar.Text.text = string.format(en("AUCTION_CREATING"), n, total)
  end
  _G.AuctionHouseFilterButton_SetUp = function(button, info) button:SetText(info.name) end
  Stub.loadedAddons[ADDON] = true
  return frame
end

describe("the auction house on Forever", function()
  local WFJ

  local function load() WFJ = C.fresh({ "UI/AuctionHouse.lua" }, UI) end

  local function setup(loadedFirst)
    load()
    if loadedFirst then
      loadAuctionHouse()
      WFJ.Labels.forbidNames(WFJ.AuctionHouse.NEVER_TOUCH)
      assert.is_true(WFJ.AuctionHouse.init())
    else
      assert.is_false(WFJ.AuctionHouse.init()) -- waits for the addon
      loadAuctionHouse()
      WFJ.Labels.forbidNames(WFJ.AuctionHouse.NEVER_TOUCH)
      assert.are.equal(1, WFJ.LoadOnDemand.loaded(ADDON))
    end
  end

  after_each(function() C.teardown(GLOBALS) end)

  for _, order in ipairs({ { true, "loaded before the addon" }, { false, "loaded on demand" } }) do
    describe(ADDON .. " " .. order[2], function()
      before_each(function() setup(order[1]) end)

      it("the title follows SetDisplayMode → SetTitle, again after a second SetTitle; Alt shows English",
        function()
          local frame = _G.AuctionHouseFrame
          frame:Show()
          frame:SetDisplayMode("buy")
          local title = frame.TitleContainer.TitleText
          assert.are.equal("オークションを見る", title:GetText())
          frame:SetDisplayMode("sell")
          assert.are.equal("出品する", title:GetText())
          C.alt(WFJ, true)
          assert.are.equal("Post Auctions", title:GetText())
          C.alt(WFJ, false)
          frame:SetTitle("Thrall") -- not a title key: left as written
          assert.are.equal("Thrall", title:GetText())
        end)

      it("static labels, the duration dropdown's own text and the token pane are Japanese; hide releases them",
        function()
          local frame = _G.AuctionHouseFrame
          frame:Show()
          assert.are.equal("購入", frame.BuyTab:GetText())
          assert.are.equal("検索", frame.SearchBar.SearchButton:GetText())
          assert.are.equal("出品", frame.ItemSellFrame.PostButton:GetText())
          assert.are.equal("入札", frame.ItemBuyFrame.BidFrame.BidButton:GetText())
          assert.are.equal("戻る", frame.ItemBuyFrame.BackButton:GetText()) -- an owned word
          assert.are.equal("INVTYPE_CLOAK", (WFJ.UIIndex:match("Back"))) -- the slot word elsewhere
          assert.are.equal("24時間", frame.ItemSellFrame.Duration.Dropdown.Text:GetText())
          assert.are.equal("即決価格", frame.WoWTokenResults.BuyoutLabel:GetText())
          -- forever_titles.txt `key TUTORIAL_TOKEN_ABOUT_TOKENS auctionhouse`
          local tokenTitle = frame.WoWTokenResults.GameTimeTutorial.TitleContainer.TitleText
          assert.are.equal("WoW Tokenについて", tokenTitle:GetText())
          frame.WoWTokenResults.GameTimeTutorial:SetTitle(en("TUTORIAL_TOKEN_ABOUT_TOKENS")) -- a second SetTitle
          assert.are.equal("WoW Tokenについて", tokenTitle:GetText())
          assert.are.equal("検索中...", frame.ItemSellList.LoadingSpinner.SearchingText:GetText())
          frame:Hide()
          assert.are.equal("Buy", frame.BuyTab:GetText())
        end)

      it("the buyout-mode switch rewrites the price label and subtext; the buy dialog's notice follows SetState",
        function()
          local frame = _G.AuctionHouseFrame
          frame:Show()
          local price = frame.ItemSellFrame.PriceInput
          assert.are.equal("単価", price.Label:GetText())
          price:SetLabel(en("AUCTION_HOUSE_BUYOUT_LABEL"))
          price:SetSubtext(en("AUCTION_HOUSE_BUYOUT_OPTIONAL_LABEL"))
          assert.are.equal("即決価格", price.Label:GetText())
          assert.are.equal("即決価格", price.LabelTitle:GetText())
          assert.are.equal("|cff777777(任意)|r", price.Subtext:GetText())
          frame.BuyDialog:SetState(en("AUCTION_HOUSE_DIALOG_PRICE_UPDATED"))
          assert.are.equal("最安値に更新されました。", frame.BuyDialog.Notification.Text:GetText())
        end)

      it("a list: results text, quantity, pooled headers and row cells translate; names in the same cells do not",
        function()
          local frame = _G.AuctionHouseFrame
          frame:Show()
          local list = frame.BrowseResultsFrame.ItemList
          list:SetState("none")
          assert.are.equal("アイテムが見つかりません", list.ResultsText:GetText())
          list:SetState("results")
          assert.are.equal("", list.ResultsText:GetText())
          assert.are.equal("1234個出品中", list.RefreshFrame.TotalQuantity:GetText())
          list:UpdateTableBuilderLayout({ en("AUCTION_HOUSE_BROWSE_HEADER_PRICE"),
            en("AUCTION_HOUSE_BROWSE_HEADER_NAME") })
          local titles = {}
          for h in list.tableBuilder.EnumerateHeaders() do titles[#titles + 1] = h:GetText() end
          assert.are.same({ "価格", "名前" }, titles)
          list:UpdateTableBuilderLayout({ en("AUCTION_HOUSE_BROWSE_HEADER_NAME") }) -- the pool reshuffles
          titles = {}
          for h in list.tableBuilder.EnumerateHeaders() do titles[#titles + 1] = h:GetText() end
          assert.are.same({ "名前" }, titles)
          -- a seller called "Search", an item called "Swords": dictionary words, but not this cell's keys
          local row = list:addRow({ "Swords", "Search", string.format(en("AUCTION_HOUSE_NUM_SELLERS"), 3),
            en("AUCTION_HOUSE_NONE_AVAILABLE") })
          assert.are.equal("Swords", row.cells[1].Text:GetText())
          assert.are.equal("Search", row.cells[2].Text:GetText())
          assert.is_true(C.unrecorded(WFJ, row.cells[1].Text))
          assert.are.equal("出品者3人", row.cells[3].Text:GetText())
          assert.are.equal("出品なし", row.cells[4].Text:GetText())
        end)

      it("summary lines, category buttons and the multisell bar: the fixed words translate, names stay", function()
        local frame = _G.AuctionHouseFrame
        frame:Show()
        local box = frame.AuctionsFrame.SummaryList.ScrollBox
        local all, item = { Text = Stub.fontString("") }, { Text = Stub.fontString("") }
        box:initFrame(all, {}, function(line) line.Text.text = en("AUCTION_HOUSE_ALL_AUCTIONS") end)
        box:initFrame(item, {}, function(line) line.Text.text = "Searching..." end) -- an item's name
        assert.are.equal("すべてのオークション", all.Text:GetText())
        assert.are.equal("Searching...", item.Text:GetText())
        local weapons, swords = Stub.button(nil, ""), Stub.button(nil, "")
        _G.AuctionHouseFilterButton_SetUp(weapons, { name = en("AUCTION_CATEGORY_WEAPONS") })
        _G.AuctionHouseFilterButton_SetUp(swords, { name = "Swords" }) -- a client-table sub class name
        assert.are.equal("武器", weapons:GetText())
        assert.are.equal("Swords", swords:GetText())
        _G.AuctionHouseMultisellProgressFrame:Refresh(2, 5)
        assert.are.equal("出品中 2/5", _G.AuctionHouseMultisellProgressFrame.ProgressBar.Text:GetText())
      end)

      it("a sub category's item sub-class name and armour slot translate; a name with no row stays",
        function()
          _G.AuctionHouseFrame:Show()
          local staves, head, weapons, daggers = Stub.button(nil, ""), Stub.button(nil, ""), Stub.button(nil, ""),
            Stub.button(nil, "")
          _G.AuctionHouseFilterButton_SetUp(staves, { name = "Staves" })
          _G.AuctionHouseFilterButton_SetUp(head, { name = en("INVTYPE_HEAD") })
          _G.AuctionHouseFilterButton_SetUp(weapons, { name = en("AUCTION_CATEGORY_WEAPONS") })
          _G.AuctionHouseFilterButton_SetUp(daggers, { name = "Daggers" }) -- a sub-class with no row
          assert.are.equal("杖", staves:GetText())
          assert.are.equal("頭", head:GetText())
          assert.are.equal("武器", weapons:GetText())
          assert.are.equal("Daggers", daggers:GetText())
          assert.is_true(C.unrecorded(WFJ, daggers))
          C.alt(WFJ, true)
          assert.are.equal("Staves", staves:GetText())
          C.alt(WFJ, false)
          assert.are.equal("杖", staves:GetText())
          -- the pooled button reused for another category shows that one's word
          _G.AuctionHouseFilterButton_SetUp(staves, { name = "Swords" }) -- a global word, not a category key
          assert.are.equal("Swords", staves:GetText())
          assert.is_nil(WFJ.UIIndex:match("Staves")) -- the family is never matched outside the category list
        end)

      it("help tooltips: a disabled bid button and a refresh button translate", function()
        local frame = _G.AuctionHouseFrame
        C.tooltip(frame.ItemBuyFrame.BidFrame.BidButton, { en("AUCTION_HOUSE_TOOLTIP_TITLE_NOT_ENOUGH_MONEY") })
        assert.are.equal("所持金が足りません", _G.GameTooltipTextLeft1:GetText())
        C.tooltip(frame.ItemSellList.RefreshFrame.RefreshButton, { en("AUCTION_HOUSE_REFRESH_BUTTON_TOOLTIP") })
        assert.are.equal("更新", _G.GameTooltipTextLeft1:GetText())
        C.tooltip(frame.ItemBuyFrame.ItemDisplay.FavoriteButton, { en("AUCTION_HOUSE_FAVORITES_MAXED_TOOLTIP") })
        assert.are.equal("お気に入りリストがいっぱいです。", _G.GameTooltipTextLeft1:GetText())
        C.tooltip(frame.WoWTokenResults.Buyout, { en("ERR_NOT_ENOUGH_GOLD") })
        assert.are.equal("ゴールドが足りない", _G.GameTooltipTextLeft1:GetText())
        C.tooltip(frame.WoWTokenResults.InvisiblePriceFrame, { en("TOKEN_BUYOUT_PRICE_UPDATES") })
        assert.are.equal("WoW Tokenの現在の相場です。", _G.GameTooltipTextLeft1:GetText())
        -- a pooled row: the row owns "your auction", a cell's favorite button the favorites-full line
        local row = frame.ItemSellList:addRow({ "Swords" })
        C.tooltip(row, { en("AUCTION_HOUSE_OWNED_COMMODITIES_LINE_TOOLTIP_TITLE") })
        assert.are.equal("自分のオークション", _G.GameTooltipTextLeft1:GetText())
        C.tooltip(row.cells[1].FavoriteButton, { en("AUCTION_HOUSE_FAVORITES_MAXED_TOOLTIP") })
        assert.are.equal("お気に入りリストがいっぱいです。", _G.GameTooltipTextLeft1:GetText())
        C.tooltip(row, { "Swords" }) -- an item tooltip on the same owner: a name, never matched
        assert.are.equal("Swords", _G.GameTooltipTextLeft1:GetText())
      end)

      it("hooks install once", function()
        assert.is_false(WFJ.AuctionHouse.init())
        assert.is_false(WFJ.AuctionHouse.setup())
        assert.are.equal(1, #Stub.hooks["AuctionHouseFilterButton_SetUp"])
      end)
    end)
  end

  it("the item display's name is never recorded, whatever it holds", function()
    setup(true)
    local frame = _G.AuctionHouseFrame
    frame:Show()
    local name = frame.ItemSellFrame.ItemDisplay.Name
    assert.are.equal("Searching...", name:GetText())
    assert.are.equal(0, WFJ.Labels.show("auctionhouse", "x", name))
    assert.is_true(C.unrecorded(WFJ, name))
  end)

  it("client names bound to the wrong type degrade to English with no error", function()
    load()
    local frame = loadAuctionHouse()
    frame.SearchBar = 7
    frame.ItemSellList = "list"
    frame.BrowseResultsFrame.ItemList.tableBuilder = 3
    frame.BrowseResultsFrame.ItemList.ScrollBox = true
    frame.AuctionsFrame.SummaryList.ScrollBox = 9
    frame.TitleContainer.TitleText = "title"
    _G.AuctionHouseFilterButton_SetUp = "not a function"
    _G.AuctionHouseMultisellProgressFrame = 1
    assert.has_no.errors(function()
      assert.is_true(WFJ.AuctionHouse.init())
      frame:Show()
      frame:SetDisplayMode("buy")
      frame.BrowseResultsFrame.ItemList:SetState("none")
    end)
    assert.are.equal("購入", frame.BuyTab:GetText())
    assert.are.equal("アイテムが見つかりません", frame.BrowseResultsFrame.ItemList.ResultsText:GetText())
    load()
    _G.AuctionHouseFrame = 42
    Stub.loadedAddons[ADDON] = true
    assert.has_no.errors(function() assert.is_false(WFJ.AuctionHouse.init()) end)
  end)

  it("the addon never loads → init is false and nothing is set up", function()
    load()
    assert.has_no.errors(function() assert.is_false(WFJ.AuctionHouse.init()) end)
    assert.are.equal(0, WFJ.LoadOnDemand.loaded("Blizzard_AuctionUI"))
  end)
end)
