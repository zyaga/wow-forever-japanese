-- The NPC windows (merchant tabs, repair and bag-slot help tooltips, gossip rows, never-touch widgets):
-- gossip chrome, merchant, bank and bags, driven through stub_npc's replay of the client's writers (first
-- modelled on the Classic Era files; the cases here are the ones whose widgets and writers Forever shares: the
-- Forever-only shapes are in merchant_camelot_spec, bank_camelot_spec and bags_camelot_spec).
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local NPC = require("tests.lua.spec.stub_npc")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
for _, f in ipairs({ "UI/GossipChrome.lua", "UI/Merchant.lua", "UI/Bank.lua", "UI/Bags.lua" }) do
  FILES[#FILES + 1] = f
end

-- key → { English the client holds, Japanese }
local UI = {
  GOODBYE = { "Goodbye", "さようなら" },
  TRIVIAL_QUEST_DISPLAY = { "|cff000000%s (low level)|r", "|cff000000%s (低レベル)|r" },
  IGNORED_QUEST_DISPLAY = { "|cff000000%s (ignored)|r", "|cff000000%s (無視)|r" },
  MERCHANT = { "Merchant", "商人" }, BUYBACK = { "Buyback", "買い戻し" },
  MERCHANT_BUYBACK = { "Merchant Buyback", "商人の買い戻し" }, PAGE_NUMBER = { "Page %d", "ページ %d" },
  REPAIR_ITEMS = { "Repair Items", "修理" }, PREV = { "Prev", "前へ" }, NEXT = { "Next", "次へ" },
  REPAIR_ALL_ITEMS = { "Repair All Items", "すべて修理" }, REPAIR_AN_ITEM = { "Repair an Item", "アイテムを修理" },
  ITEMSLOTTEXT = { "Item Slots", "アイテムスロット" }, BAGSLOTTEXT = { "Bag Slots", "バッグスロット" },
  BANKSLOTPURCHASE_LABEL = { "Do you wish to purchase space for an additional bag?",
    "バッグスロットを1つ追加購入しますか?" },
  COSTS_LABEL = { "Cost:", "費用:" }, BANKSLOTPURCHASE = { "Purchase", "購入" },
  BANK_BAG = { "Bag Slot", "バッグスロット" }, BANK_BAG_PURCHASE = { "Purchasable Bag Slot", "購入可能なバッグスロット" },
  BACKPACK_TOOLTIP = { "Backpack", "バックパック" }, KEYRING = { "Keyring", "キーリング" },
  EQUIP_CONTAINER = { "Equip Container", "バッグを装備" },
  BACKPACK_AUTHENTICATOR_INCREASE_SIZE = { "Increase Backpack Size", "バックパックを拡張" },
}

describe("the NPC windows: gossip chrome, merchant, bank, bags", function()
  local WFJ, S, SS, tt

  local function left(i) return _G["GameTooltipTextLeft" .. i] end
  local function font(widget)
    local fs = widget.GetFontString and widget:GetFontString() or widget
    return (fs:GetFont())
  end
  local function alt(down) Stub.keys.alt = down; WFJ.Modifier.refresh() end
  -- every record, on any surface, whose widget is `widget` (a FontString, or a button's adapter)
  local function recordsOn(widget)
    local n = 0
    for _, bucket in pairs(SS.surfaces()) do
      for _, rec in pairs(bucket) do
        if rec.fs == widget or (type(rec.fs) == "table" and rec.fs.button == widget) then n = n + 1 end
      end
    end
    return n
  end
  local function initModules()
    WFJ.GossipChrome.init(); WFJ.Merchant.init(); WFJ.Bank.init(); WFJ.Bags.init()
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    NPC.install()
    WFJ = H.loadChunks(FILES)
    S, SS = WFJ.Settings, WFJ.SurfaceState
    H.uiSetup(WFJ, UI)
    tt = _G.GameTooltip
  end)

  after_each(function()
    H.uiTeardown()
    NPC.teardown()
  end)

  describe("gossip", function()
    local function quest(kind, title, flags)
      local info = { title = title, isTrivial = flags == "trivial", isIgnored = flags == "ignored" }
      return { buttonType = kind, info = info }
    end

    it("Goodbye is Japanese from init, in the bundled font; the NPC title is untouched", function()
      initModules()
      local goodbye = _G.GossipFrame.GreetingPanel.GoodbyeButton
      assert.are.equal("さようなら", goodbye:GetText())
      assert.are.equal(WFJ.Font.PATH, font(goodbye))
      NPC.gossip({ { buttonType = 1, text = "Well met." } }, "Goodbye")
      assert.are.equal("Goodbye", _G.GossipFrameTitleText:GetText())
      assert.are.equal(0, _G.GossipFrameTitleText.calls.SetText)
    end)

    it("trivial / ignored quest rows show the Japanese suffix with the title verbatim; other rows are untouched",
      function()
        initModules()
        NPC.gossip({
          { buttonType = 1, text = "Greetings." }, { buttonType = 2 },
          quest(5, "Merchant", "trivial"), quest(5, "Buyback", nil), quest(4, "The Balance of Nature", "ignored"),
          { buttonType = 3, info = { name = "Merchant" } },
        })
        local rows = NPC.gossipRows
        assert.are.equal("|cff000000Merchant (低レベル)|r", rows[3]:GetText())
        assert.are.equal(WFJ.Font.PATH, font(rows[3]))
        assert.are.equal("|cff000000Buyback|r", rows[4]:GetText())
        assert.are.equal(0, rows[4].fontString.calls.SetText)
        assert.are.equal("|cff000000The Balance of Nature (無視)|r", rows[5]:GetText())
        assert.are.equal("Merchant", rows[6]:GetText()) -- an option whose text is a dictionary word
        assert.are.equal(0, rows[6].fontString.calls.SetText)
        assert.are.equal("Greetings.", rows[1]:GetText())

        local later = NPC.gossipScroll(quest(5, "Wanted: Hogger", "trivial"))
        assert.are.equal("|cff000000Wanted: Hogger (低レベル)|r", later:GetText())

        alt(true)
        assert.are.equal("|cff000000Merchant (low level)|r", rows[3]:GetText())
        assert.are.equal("Fonts\\FRIZQT__.TTF", font(rows[3]))
        alt(false)
        assert.are.equal("|cff000000Merchant (低レベル)|r", rows[3]:GetText())
        S.set("area.interface", false)
        assert.are.equal("|cff000000The Balance of Nature (ignored)|r", rows[5]:GetText())
        S.set("area.interface", true)
        assert.are.equal("|cff000000The Balance of Nature (無視)|r", rows[5]:GetText())
      end)

    it("a pooled row reused for an option drops its record without writing over the client's text", function()
      initModules()
      NPC.gossip({ quest(5, "Merchant", "trivial") })
      local row = NPC.gossipRows[1]
      assert.are.equal("|cff000000Merchant (低レベル)|r", row:GetText())
      NPC.gossip({ { buttonType = 3, info = { name = "I want to browse your goods." } } })
      assert.are.equal("I want to browse your goods.", row:GetText())
      assert.are.equal("Fonts\\FRIZQT__.TTF", font(row))
      assert.are.equal(0, recordsOn(row))
      alt(true); alt(false)
      assert.are.equal("I want to browse your goods.", row:GetText())
    end)

    it("rows initialized before the hook installs are walked (iterateExisting), and OnHide releases", function()
      NPC.gossip({ quest(4, "Merchant", "ignored") })
      initModules()
      local row = NPC.gossipRows[1]
      assert.are.equal("|cff000000Merchant (無視)|r", row:GetText())
      _G.GossipFrame:Hide()
      assert.are.equal("|cff000000Merchant (ignored)|r", row:GetText())
      assert.are.equal(0, SS.count("gossip.chrome"))
      assert.are.equal("さようなら", _G.GossipFrame.GreetingPanel.GoodbyeButton:GetText()) -- static stays
    end)
  end)

  describe("merchant", function()
    it("tabs hold Japanese before the first show, so the tab resize measures it; the font survives UpdateTabs",
      function()
        initModules()
        assert.are.equal("商人", _G.MerchantFrameTab1:GetText())
        assert.are.equal("買い戻し", _G.MerchantFrameTab2:GetText())
        NPC.openMerchant()
        assert.are.equal("商人", _G.MerchantFrameTab1.measured)
        assert.are.equal("買い戻し", _G.MerchantFrameTab2.measured)
        assert.are.equal(WFJ.Font.PATH, font(_G.MerchantFrameTab1)) -- selected by OnShow (font object reset)
        NPC.merchantTab(2)
        assert.are.equal(WFJ.Font.PATH, font(_G.MerchantFrameTab2))
        assert.are.equal(WFJ.Font.PATH, font(_G.MerchantFrameTab1))
        alt(true)
        assert.are.equal("Merchant", _G.MerchantFrameTab1:GetText())
        alt(false)
        assert.are.equal("商人", _G.MerchantFrameTab1:GetText())
        S.set("area.interface", false)
        assert.are.equal("Buyback", _G.MerchantFrameTab2:GetText())
      end)

    it("page text and the Prev / Next regions translate; the merchant-tab NPC name does not", function()
      initModules()
      _G.MerchantFrame.page = 2
      NPC.openMerchant()
      assert.are.equal("ページ 2", _G.MerchantPageText:GetText())
      assert.are.equal(WFJ.Font.PATH, font(_G.MerchantPageText))
      local prev = select(2, _G.MerchantPrevPageButton:GetRegions())
      local nxt = select(2, _G.MerchantNextPageButton:GetRegions())
      assert.are.equal("前へ", prev:GetText())
      assert.are.equal("次へ", nxt:GetText())
      assert.are.equal("Merchant Buyback", _G.MerchantNameText:GetText()) -- UnitName("NPC"), also a dictionary word
      assert.are.equal(0, _G.MerchantNameText.calls.SetText)
    end)

    it("the repair buttons' tooltips translate; a money line is not a word", function()
      initModules()
      NPC.hover(_G.MerchantRepairAllButton)
      assert.are.equal("すべて修理", left(1):GetText())
      assert.are.equal(WFJ.Font.PATH, font(left(1)))
      assert.are.equal("12|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t", left(2):GetText())
      NPC.leave()
      assert.are.equal("Repair All Items", left(1):GetText())
      NPC.hover(_G.MerchantRepairItemButton)
      assert.are.equal("アイテムを修理", left(1):GetText())
      alt(true)
      assert.are.equal("Repair an Item", left(1):GetText())
      alt(false)
      assert.are.equal("アイテムを修理", left(1):GetText())
    end)
  end)

  describe("bank", function()
    it("the Item Slots / Bag Slots region labels translate at init; the NPC title does not", function()
      initModules()
      local _, items, bags = _G.BankFrame:GetRegions()
      assert.are.equal("アイテムスロット", items:GetText())
      assert.are.equal("バッグスロット", bags:GetText())
      assert.are.equal(WFJ.Font.PATH, font(items))
      _G.BankFrame:Show()
      assert.are.equal("Purchase", _G.BankFrameTitleText:GetText()) -- UnitName("npc"), also a dictionary word
      assert.are.equal(0, _G.BankFrameTitleText.calls.SetText)
      S.set("area.interface", false)
      assert.are.equal("Item Slots", items:GetText())
    end)
  end)

  describe("bags", function()
    for _, mode in ipairs({ "current", "copy" }) do
      it("the backpack button's title keeps its key binding in Japanese (AppendText " .. mode .. ")", function()
        NPC.appendMode = mode
        initModules()
        NPC.hover(_G.MainMenuBarBackpackButton)
        assert.are.equal("バックパック |cffffd200(B)|r", left(1):GetText())
        assert.are.equal(WFJ.Font.PATH, font(left(1)))
        alt(true)
        assert.are.equal("Backpack |cffffd200(B)|r", left(1):GetText())
        alt(false)
        assert.are.equal("バックパック |cffffd200(B)|r", left(1):GetText())
        NPC.leave()
        assert.are.equal(0, SS.count("help"))
      end)
    end

    it("the portrait buttons: backpack and keyring (with bindings) translate, a bag's item tooltip does not", function()
      NPC.bindings.TOGGLEKEYRING = "K"
      initModules()
      local backpack, pouch, keyring = NPC.openBag(0), NPC.openBag(1), NPC.openBag(-2, 4)
      NPC.hover(backpack.PortraitButton)
      assert.are.equal("バックパック |cffffd200(B)|r", left(1):GetText())
      NPC.hover(keyring.PortraitButton)
      assert.are.equal("キーリング |cffffd200(K)|r", left(1):GetText())
      assert.are.equal(WFJ.Font.PATH, font(left(1)))
      NPC.hover(pouch.PortraitButton)
      assert.are.equal("Small Red Pouch", left(1):GetText())
      assert.are.equal("Fonts\\FRIZQT__.TTF", font(left(1)))
    end)

    it("keyring and empty bag slot (and its captured refresh) tooltips translate; a bag in a slot does not",
      function()
        initModules()
        NPC.hover(_G.KeyRingButton)
        assert.are.equal("キーリング", left(1):GetText())
        NPC.hover(_G.CharacterBag0Slot)
        assert.are.equal("バッグを装備", left(1):GetText())
        NPC.refresh(_G.CharacterBag0Slot)
        assert.are.equal("バッグを装備", left(1):GetText())
        assert.are.equal(WFJ.Font.PATH, font(left(1)))
        _G.CharacterBag1Slot.item = "Equip Container"
        NPC.hover(_G.CharacterBag1Slot)
        assert.are.equal("Equip Container", left(1):GetText())
      end)

    it("a tooltip owned by an unregistered frame is untouched", function()
      initModules()
      local other = _G.CreateFrame("Button", nil)
      tt:SetOwner(other)
      tt:SetText("Backpack")
      tt:Show()
      assert.are.equal("Backpack", left(1):GetText())
      assert.are.equal(0, SS.count("help"))
    end)
  end)

  describe("master switch", function()
    it("enabled = false restores every static label and a shown help tooltip", function()
      initModules()
      NPC.hover(_G.MerchantRepairItemButton)
      S.set("enabled", false)
      assert.are.equal("Goodbye", _G.GossipFrame.GreetingPanel.GoodbyeButton:GetText())
      assert.are.equal("Merchant", _G.MerchantFrameTab1:GetText())
      assert.are.equal("Item Slots", (select(2, _G.BankFrame:GetRegions())):GetText())
      assert.are.equal("Repair an Item", left(1):GetText())
      S.set("enabled", true)
      assert.are.equal("商人", _G.MerchantFrameTab1:GetText())
    end)
  end)

  describe("never-touch widgets", function()
    it("declared widgets holding a dictionary English are never recorded while every writer runs", function()
      initModules()
      local holds = { GossipFrameTitleText = "Goodbye", MerchantBuyBackItemName = "Buyback",
        BankFrameTitleText = "Bag Slots", BagItemSearchBox = "Backpack" }
      for i = 1, 12 do holds["MerchantItem" .. i .. "Name"] = "Merchant" end
      for i = 1, 12 do NPC.merchantItems[i] = "Merchant" end
      Stub.units.npc = { name = "Bag Slots" }
      -- drive every writer
      NPC.gossip({ { buttonType = 5, info = { title = "Goodbye", isTrivial = true } } }, "Goodbye")
      NPC.openMerchant(); NPC.merchantTab(2); NPC.merchantTab(1)
      _G.MerchantBuyBackItemName.text = "Buyback"
      _G.BankFrame:Show()
      NPC.openBag(0); NPC.openBag(-2, 4)
      NPC.hover(_G.MainMenuBarBackpackButton)
      alt(true); alt(false)
      local modules = { WFJ.GossipChrome, WFJ.Merchant, WFJ.Bank, WFJ.Bags }
      local checked = 0
      for _, module in ipairs(modules) do
        for _, name in ipairs(module.NEVER_TOUCH) do
          local widget = _G[name]
          assert.is_not_nil(widget, name)
          assert.are.equal(holds[name], widget:GetText(), name)
          assert.are.equal(0, recordsOn(widget), name)
          checked = checked + 1
        end
      end
      assert.are.equal(16, checked)
    end)
  end)
end)
