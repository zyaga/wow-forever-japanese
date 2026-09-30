-- The bank, bag and merchant windows as the Forever (camelot) client builds them: the mainline
-- Blizzard_UIPanels_Game [Family]\{BankFrameTemplates,ContainerFrame,MerchantFrame}.* with camelot's [Game]\BankFrame.*
-- and ContainerFrame.lua, and Blizzard_MainMenuBarBagButtons' Shared / [Game] files, replaying their exact writes:
-- mixin methods copied onto each frame instance (called as self:Method(), so an instance hook sees them), frame pools,
-- SetTitle → TitleContainer.TitleText, and the Lua-built help tooltips. A client write is stored as `fs.text = …` so
-- only the addon's writes are counted. Requires Stub.install and Stub.installTooltipAPI first; CI.teardown() clears
-- every global it set. Line references are to the lowercased Forever extract.
local Stub = require("tests.lua.spec.wow_stub")

local CI = {}
local set = {}

local function global(name, value)
  _G[name] = value
  set[#set + 1] = name
  return value
end

local function frame(kind, name)
  local f = _G.CreateFrame(kind, name)
  if name then set[#set + 1] = name end
  return f
end

local function button(name, text)
  local b = Stub.button(name, text)
  if name then set[#set + 1] = name end
  return b
end

local function G(key) return _G[key] end

-- PortraitFrameTemplate / ButtonFrameTemplate: SetTitle writes TitleContainer.TitleText
-- (blizzard_sharedxml/portraitframe.lua:11–13); the `$parentTitleText` global is not modelled.
local function titled(f)
  f.TitleContainer = _G.CreateFrame("Frame")
  f.TitleContainer.TitleText = Stub.fontString("")
  function f.SetTitle(self, t) self.TitleContainer.TitleText.text = t end
end

-- CreateFramePool: EnumerateActive yields each active object (pools.lua); Acquire reuses a released one.
local function pool(make)
  local p = { active = {}, free = {} }
  function p.Acquire(self)
    local obj = table.remove(self.free) or make()
    self.active[#self.active + 1] = obj
    return obj
  end
  function p.ReleaseAll(self)
    for _, obj in ipairs(self.active) do self.free[#self.free + 1] = obj; obj.shown = false end
    self.active = {}
  end
  function p.EnumerateActive(self)
    local i = 0
    return function() i = i + 1; return self.active[i] end
  end
  return p
end

-- ---------------------------------------------------------------------------------------------------------------
-- Bank [camelot/bankframe.{xml,lua}; mainline/bankframetemplates.{xml,lua}]
local function installBank()
  local bank = frame("Frame", "BankFrame")
  titled(bank)
  global("BankFrameTitleText", Stub.fontString("")) -- BankFrameTemplate's own BORDER FontString (xml:680)
  bank.BagCost = Stub.fontString(G("COSTS_LABEL")) -- camelot/bankframe.xml:62
  bank.BagText = Stub.fontString(G("BAGSLOTTEXT_COLON")) -- :68
  bank:addRegion(bank.BagCost)
  bank:addRegion(bank.BagText)
  global("BankItemSearchBox", Stub.fontString("Bank")) -- an EditBox holding a dictionary word
  CI.purchasedBags = 1
  CI.pages = 2
  CI.lockReason = nil
  CI.tabs = nil -- nil: ShouldUsePlayerBagsInBank; else { names } of the purchased bank tabs

  local panel = frame("Frame", nil)
  panel.name = "BankPanel"
  bank.BankPanel = panel
  panel.PurchaseButton = button(nil, G("BANKSLOTPURCHASE")) -- nested virtual BankFramePurchaseButton (:108)
  panel.MoneyFrame = frame("Frame", nil)
  panel.MoneyFrame.WithdrawButton = button(nil, G("BANK_WITHDRAW_MONEY_BUTTON_LABEL")) -- xml:205
  panel.MoneyFrame.DepositButton = button(nil, G("BANK_DEPOSIT_MONEY_BUTTON_LABEL")) -- xml:214
  local cost = frame("Frame", nil)
  cost.TabCost = Stub.fontString(G("COSTS_LABEL"))
  cost.PurchaseButton = button(nil, G("BANKSLOTPURCHASE"))
  panel.PurchasePrompt = frame("Frame", nil)
  panel.PurchasePrompt.TabCostFrame = cost
  panel.PurchasePrompt.Title = Stub.fontString("Expand your bank") -- server data (tabData.purchasePromptTitle)

  -- LockPrompt: OnShow → self:Refresh() → PromptText (lua:1170–1209)
  local lock = frame("Frame", nil)
  lock.name = "LockPrompt"
  lock.PromptText = Stub.fontString("")
  local LOCKED = { disabled = "BANK_LOCKED_REASON_BANK_DISABLED", failed = "BANK_LOCKED_REASON_BANK_CONVERSION_FAILED" }
  function lock.Refresh(self) self.PromptText.text = CI.lockReason and G(LOCKED[CI.lockReason]) or "" end
  lock:SetScript("OnShow", function(self) self:Refresh() end)
  panel.LockPrompt = lock

  -- AutoSortButton: SetText(BAG_CLEANUP_BANK) (lua:1831–1837)
  local sort = frame("Button", nil)
  sort:SetScript("OnEnter", function(self)
    _G.GameTooltip:SetOwner(self)
    _G.GameTooltip:SetText(G("BAG_CLEANUP_BANK"))
    _G.GameTooltip:Show()
  end)
  panel.AutoSortButton = sort

  -- TabSettingsMenu.DepositSettingsMenu: three XML headers, six checkboxes whose Init writes Text on every show
  local menu = frame("Frame", nil)
  menu.AssignExpansionHeader = Stub.fontString(G("BANK_TAB_ASSIGN_EXPANSION_HEADER"))
  menu.AssignSettingsHeader = Stub.fontString(G("BANK_TAB_DEPOSIT_SETTINGS_HEADER"))
  menu.CleanUpSettingsHeader = Stub.fontString(G("BANK_TAB_CLEANUP_SETTINGS_HEADER"))
  menu.DepositSettingsCheckboxes = {}
  for _, key in ipairs({ "BANK_TAB_ASSIGN_EQUIPMENT_CHECKBOX", "BANK_TAB_ASSIGN_CONSUMABLES_CHECKBOX",
    "BANK_TAB_ASSIGN_PROFESSION_GOODS_CHECKBOX", "BANK_TAB_ASSIGN_REAGENTS_CHECKBOX", "BANK_TAB_ASSIGN_JUNK_CHECKBOX",
    "BANK_TAB_IGNORE_IN_CLEANUP_CHECKBOX" }) do
    local box = frame("CheckButton", nil)
    box.name = "Checkbox"
    box.Text = Stub.fontString("")
    box.text = G(key)
    function box.Init(self) if self.text then self.Text.text = self.text end end
    box:SetScript("OnShow", function(self) self:Init() end)
    menu.DepositSettingsCheckboxes[#menu.DepositSettingsCheckboxes + 1] = box
  end
  panel.TabSettingsMenu = frame("Frame", nil)
  panel.TabSettingsMenu.DepositSettingsMenu = menu

  -- Bank panel tabs (only without player bags in the bank): tooltip = the tab's name + the click instruction
  panel.bankTabPool = pool(function()
    local tab = frame("Button", nil)
    tab:SetScript("OnEnter", function(self)
      _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      _G.GameTooltip:SetText(self.tabName) -- GameTooltip_SetTitle(tabData.name)
      _G.GameTooltip:AddLine(G("BANK_TAB_TOOLTIP_CLICK_INSTRUCTION"))
      _G.GameTooltip:Show()
    end)
    return tab
  end)
  function panel.RefreshBankTabs(self)
    if not CI.tabs then return end
    self.bankTabPool:ReleaseAll()
    for _, name in ipairs(CI.tabs) do
      local tab = self.bankTabPool:Acquire()
      tab.tabName = name
      tab.shown = true
    end
  end
  function panel.RequestTitleRefresh() _G.BankFrame:SetTitle(G("BANK")) end -- TitleUpdateRequested → SetTitle
  function panel.Reset(self)
    self:RefreshBankTabs()
    self:RequestTitleRefresh()
  end

  -- Bag buttons (camelot/bankframe.lua:136–190, 330–343) and page tabs (:104–134, 285–299)
  bank.itemButtonBagPool = pool(function()
    local b = frame("Button", nil)
    b:SetScript("OnEnter", function(self)
      local tt = _G.GameTooltip
      tt:SetOwner(self, "ANCHOR_RIGHT")
      if self.bag then
        Stub.setItemTooltip(tt, "|Hitem:4499:0:0:0|h[" .. self.bag .. "]|h", { self.bag, "16 Slot Bag" })
      else
        tt:SetText(self.tooltipText)
      end
      tt:Show()
    end)
    return b
  end)
  bank.bankPageTabPool = pool(function()
    local tab = frame("Frame", nil)
    tab:SetScript("OnEnter", function(self)
      _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      _G.GameTooltip:SetText(self.tooltipText)
      _G.GameTooltip:Show()
    end)
    return tab
  end)
  CI.bagContents = {} -- bag slot → bag name held there
  function bank.RefreshBagButtons(self)
    self.itemButtonBagPool:ReleaseAll()
    for bagNum = 2, 7 do
      local b = self.itemButtonBagPool:Acquire()
      b.bag = CI.bagContents[bagNum]
      b.tooltipText = (bagNum - 1) <= CI.purchasedBags and G("BANK_BAG") or G("BANK_BAG_PURCHASE")
    end
  end
  function bank.RefreshPageTabs(self, currentPage)
    self.bankPageTabPool:ReleaseAll()
    for page = 1, CI.pages do
      local tab = self.bankPageTabPool:Acquire()
      tab.tooltipText = G("PAGE_NUMBER"):format(page)
      tab.checked = page == currentPage
    end
  end
  function bank.RefreshAll(self)
    self:RefreshBagButtons()
    self.BankPanel:Reset()
  end
  bank:SetScript("OnShow", function(self)
    self:RefreshPageTabs(1)
    self:RefreshAll()
    if CI.lockReason then self.BankPanel.LockPrompt:Show() end
  end)
end

function CI.openBank() _G.BankFrame:Show() end
function CI.closeBank() _G.BankFrame:Hide() end
function CI.bankBagButtons() return _G.BankFrame.itemButtonBagPool.active end
function CI.bankPageTabs() return _G.BankFrame.bankPageTabPool.active end
function CI.bankTabs() return _G.BankFrame.BankPanel.bankTabPool.active end

-- ---------------------------------------------------------------------------------------------------------------
-- Bags [mainline/containerframe.{xml,lua}; camelot/containerframe.lua; blizzard_mainmenubarbagbuttons]
local function installBags()
  global("KEYRING_CONTAINER", -2)
  CI.bagNames = { [0] = "Backpack", [1] = "Small Red Pouch", [2] = "Keyring", [-2] = "Keyring" }
  CI.bindings = { TOGGLEBACKPACK = "B" }
  global("C_Container", { GetBagName = function(id) return CI.bagNames[id] end })
  -- BagSearchBoxTemplate → SearchBoxTemplate: the placeholder is .Instructions, written once at OnLoad (SEARCH)
  local search = frame("EditBox", "BagItemSearchBox")
  search.Instructions = Stub.fontString(G("SEARCH") or "Search")
  -- ContainerFrameExtendedItemButton_OnEnter (lua:1622–1627): an extended (padlocked) slot's tooltip
  global("ContainerFrameExtendedItemButton_OnEnter", function(self)
    _G.GameTooltip:SetOwner(self, "ANCHOR_NONE")
    _G.GameTooltip:ClearLines() -- GameTooltip_SetTitle
    _G.GameTooltip:AddLine(G("BACKPACK_AUTHENTICATOR_INCREASE_SIZE"))
    _G.GameTooltip:Show()
  end)
  -- ContainerFrameItemButtonMixin:UpdateExtended (lua:1956–1979): the frame is made lazily from the template, whose
  -- OnEnter is bound to the global when the frame is created
  function CI.makeExtended()
    local ext = frame("Frame", nil)
    ext:SetScript("OnEnter", _G.ContainerFrameExtendedItemButton_OnEnter)
    return ext
  end

  local function portraitButton(f, name)
    local p = frame("DropdownButton", name)
    p:SetScript("OnEnter", function(self) -- ContainerFramePortraitButtonMixin:OnEnter (lua:2000–2040)
      local tt, id = _G.GameTooltip, self:GetParent().bagID
      tt:SetOwner(self, "ANCHOR_LEFT")
      if id == 0 then
        tt:SetText(G("BACKPACK_TOOLTIP"), 1, 1, 1)
        if CI.bindings.TOGGLEBACKPACK then
          tt:AppendText(" |cffffd200(" .. CI.bindings.TOGGLEBACKPACK .. ")|r")
        end
      elseif id == _G.KEYRING_CONTAINER then
        tt:SetText(G("KEYRING"), 1, 1, 1)
      else
        tt:SetText(CI.bagNames[id]) -- the bag's item name, not an item tooltip
      end
      if id ~= _G.KEYRING_CONTAINER then tt:AddLine(G("CLICK_BAG_SETTINGS")) end
      tt:Show()
    end)
    p.GetParent = function() return f end
    f.PortraitButton = p
  end
  local function container(name)
    local f = frame("Frame", name)
    titled(f)
    portraitButton(f, name .. "PortraitButton")
    function f.UpdateName(self) self:SetTitle(_G.C_Container.GetBagName(self.bagID)) end
    return f
  end
  for i = 1, 7 do container("ContainerFrame" .. i) end -- xml:300–306
  local combined = container("ContainerFrameCombinedBags") -- xml:308
  function combined.UpdateName(self) self:SetTitle(G("COMBINED_BAG_TITLE")) end
  -- ContainerFrameExtendedSlotPack:UpdateAddSlots (lua:2614–2620): an unnamed button made on first use
  local function updateAddSlots(f)
    if f.AddSlotsButton then return end
    local add = frame("Button", nil)
    add:SetScript("OnEnter", function(self)
      _G.GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      _G.GameTooltip:SetText(G("BACKPACK_AUTHENTICATOR_INCREASE_SIZE"), 1, 1, 1)
      _G.GameTooltip:Show()
    end)
    f.AddSlotsButton = add
  end
  global("ContainerFrame_GenerateFrame", function(f, size, id) -- lua:1287–1306
    f.bagID, f.size = id, size
    f:Show()
    f:UpdateName()
    if id == 0 then updateAddSlots(f) end
  end)

  local sort = frame("Button", "BagItemAutoSortButton") -- xml:345–367
  sort:SetScript("OnEnter", function(self)
    _G.GameTooltip:SetOwner(self)
    _G.GameTooltip:ClearLines() -- GameTooltip_SetTitle
    _G.GameTooltip:AddLine(G("BAG_CLEANUP_BAGS"))
    _G.GameTooltip:AddLine(G("BAG_CLEANUP_BAGS_DESCRIPTION"))
    _G.GameTooltip:Show()
  end)

  local backpack = frame("ItemButton", "MainMenuBarBackpackButton") -- shared/mainmenubarbagbuttons.lua:284–297
  backpack:SetScript("OnEnter", function(self)
    local tt = _G.GameTooltip
    tt:SetOwner(self, "ANCHOR_LEFT")
    tt:ClearLines()
    tt:AddLine(G("BACKPACK_TOOLTIP"))
    tt:AppendText("|cffffd200 (B)|r") -- NORMAL_FONT_COLOR:WrapTextInColorCode(" (B)")
    tt:AddLine(string.format(G("NUM_FREE_SLOTS") or "%d free slots", CI.freeSlots or 12)) -- NUM_FREE_SLOTS
    tt:Show()
  end)
  local keyring = frame("ItemButton", "KeyRingButton") -- camelot/mainmenubarbagbuttons.lua:179–183
  keyring:SetScript("OnEnter", function(self)
    _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    _G.GameTooltip:SetText(G("KEYRING"), 1, 1, 1)
    _G.GameTooltip:AddLine()
  end)
  CI.equipped = {} -- slot name → bag name
  local function bagSlot(name, reagent) -- BaseBagSlotButtonMixin:OnEnterInternal (shared lua:102–127)
    local slot = frame("ItemButton", name)
    slot:SetScript("OnEnter", function(self)
      local tt = _G.GameTooltip
      tt:SetOwner(self, "ANCHOR_LEFT")
      local bag = CI.equipped[name]
      if bag then
        Stub.setItemTooltip(tt, "|Hitem:4496:0:0:0|h[" .. bag .. "]|h", { bag, "6 Slot Bag" })
      else
        tt:ClearLines()
        tt:AddLine(G(reagent and "EQUIP_CONTAINER_REAGENT" or "EQUIP_CONTAINER"))
      end
      tt:Show()
    end)
  end
  for i = 0, 3 do bagSlot("CharacterBag" .. i .. "Slot") end
  bagSlot("CharacterReagentBag0Slot", true)
end

-- ToggleBackpack / ToggleBag → ContainerFrame_GenerateFrame(frame, size, id); combined bags → the combined frame.
CI.openFrames = 0
function CI.openBag(id, size)
  CI.openFrames = CI.openFrames + 1
  local f = _G["ContainerFrame" .. CI.openFrames]
  _G.ContainerFrame_GenerateFrame(f, size or 16, id)
  return f
end
function CI.openCombined()
  _G.ContainerFrame_GenerateFrame(_G.ContainerFrameCombinedBags, 0, 0)
  return _G.ContainerFrameCombinedBags
end

-- ---------------------------------------------------------------------------------------------------------------
-- Merchant [mainline/merchantframe.{xml,lua}]
local function installMerchant()
  local merchant = frame("Frame", "MerchantFrame")
  titled(merchant)
  merchant.page, merchant.selectedTab = 1, 1
  local tab1, tab2 = Stub.tab("MerchantFrameTab1", G("MERCHANT")), Stub.tab("MerchantFrameTab2", G("BUYBACK"))
  set[#set + 1] = "MerchantFrameTab1"; set[#set + 1] = "MerchantFrameTab2"
  merchant.tabs = { tab1, tab2 }
  Stub.namedFontString("MerchantPageText", "Page"); set[#set + 1] = "MerchantPageText"
  for i = 1, 12 do Stub.namedFontString("MerchantItem" .. i .. "Name", "Item Name"); set[#set + 1] = "MerchantItem"
    .. i .. "Name" end
  Stub.namedFontString("MerchantBuyBackItemName", "Item Name"); set[#set + 1] = "MerchantBuyBackItemName"
  for name, key in pairs({ MerchantPrevPageButton = "PREV", MerchantNextPageButton = "NEXT" }) do
    local b = frame("Button", name)
    b:addRegion({ GetObjectType = function() return "Texture" end })
    b:addRegion(Stub.fontString(G(key)))
  end
  CI.merchantItems = {}
  CI.guildRepair = { amount = 100, personal = true } -- CanGuildBankRepair()

  local function tooltip(name, build)
    local b = frame("Button", name)
    b:SetScript("OnEnter", function(self)
      _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      build(_G.GameTooltip)
      _G.GameTooltip:Show()
    end)
    return b
  end
  tooltip("MerchantRepairAllButton", function(tt)
    tt:SetText(G("REPAIR_ALL_ITEMS"))
    tt:AddLine("12|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t")
  end)
  tooltip("MerchantRepairItemButton", function(tt) tt:SetText(G("REPAIR_AN_ITEM")) end)
  tooltip("MerchantSellAllJunkButton", function(tt) tt:SetText(G("SELL_ALL_JUNK_ITEMS")) end) -- xml:220–224
  tooltip("MerchantGuildBankRepairButton", function(tt) -- xml:345–378
    tt:SetText(G("REPAIR_ALL_ITEMS"))
    tt:AddLine("40|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t")
    tt:AddLine(G("GUILDBANK_REPAIR"))
    tt:AddLine("1|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t")
    tt:AddLine(G(CI.guildRepair.personal and "GUILDBANK_REPAIR_PERSONAL" or "GUILDBANK_REPAIR_INSUFFICIENT_FUNDS"))
  end)

  -- FilterDropdown: a Menu dropdown whose UpdateText writes .Text (the selection translator: class for ALL_SPECS)
  local dropdown = frame("DropdownButton", nil)
  dropdown.name = "FilterDropdown"
  dropdown.Text = Stub.fontString("")
  CI.filter = "ALL"
  function dropdown.UpdateText(self)
    local texts = { ALL = G("ALL"), BOE = G("ITEM_BIND_ON_EQUIP"), CLASS = "Warrior", SPEC = "Arms" }
    self.Text.text = texts[CI.filter]
  end
  function dropdown.Update(self) self:UpdateText() end
  merchant.FilterDropdown = dropdown

  global("MerchantFrame_UpdateMerchantInfo", function() -- lua:274–300
    _G.MerchantFrame:SetTitle(_G.UnitName("npc"))
    _G.MerchantPageText.text = G("MERCHANT_PAGE_NUMBER"):format(_G.MerchantFrame.page, 3)
    for i = 1, 10 do _G["MerchantItem" .. i .. "Name"].text = CI.merchantItems[i] or "" end
  end)
  global("MerchantFrame_UpdateBuybackInfo", function() -- lua:532–594
    _G.MerchantFrame:SetTitle(G("MERCHANT_BUYBACK"))
    for i = 1, 12 do _G["MerchantItem" .. i .. "Name"].text = CI.merchantItems[i] or "" end
    _G.MerchantPageText:Hide()
  end)
  global("MerchantFrame_Update", function() -- lua:192–217
    _G.MerchantFrame.FilterDropdown:Update()
    if _G.MerchantFrame.selectedTab == 1 then _G.MerchantFrame_UpdateMerchantInfo()
    else _G.MerchantFrame_UpdateBuybackInfo() end
  end)
  merchant:SetScript("OnShow", function(self) -- MerchantFrame_OnShow (lua:147–161)
    self.selectedTab = 1
    _G.PanelTemplates_UpdateTabs(self)
    _G.MerchantFrame_Update()
  end)
end

function CI.openMerchant()
  _G.MerchantFrameTab1:Show(); _G.MerchantFrameTab2:Show()
  _G.MerchantFrame:Show()
end
function CI.merchantTab(i)
  _G.MerchantFrame.selectedTab = i
  _G.PanelTemplates_UpdateTabs(_G.MerchantFrame)
  _G.MerchantFrame_Update()
end
function CI.setFilter(f)
  CI.filter = f
  _G.MerchantFrame.FilterDropdown:UpdateText()
end

function CI.hover(owner) owner.scripts.OnEnter(owner) end
function CI.leave() _G.GameTooltip:Hide() end

-- The client's English for every key a spec's UI table names must be set as globals (H.uiSetup) before install.
function CI.install()
  set = {}
  CI.openFrames = 0
  Stub.units.npc = { name = "Merchant Buyback" } -- an NPC name that is also a dictionary word
  installBank()
  installBags()
  installMerchant()
end

function CI.teardown()
  for _, name in ipairs(set) do _G[name] = nil end
  set = {}
end

return CI
