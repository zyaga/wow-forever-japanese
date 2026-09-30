-- The NPC-interaction windows as the Classic Era 1.15.9.69722 client builds them: the gossip
-- window's Goodbye button and pooled greeting rows, the merchant window, the bank window, the bag frames and the bag
-- bar, plus the Blizzard writers the surfaces post-hook, replaying the exact writes of
-- Blizzard_UIPanels_Game/{Shared,Classic,Vanilla}/{GossipFrame*,MerchantFrame,BankFrame,ContainerFrame*}.* and
-- Blizzard_MainMenuBarBagButtons/Classic/*. A client write is stored as `fs.text = …` so only our writes are counted.
-- Requires Stub.install and Stub.installTooltipAPI first. NPC.teardown() clears every global it set.
local Stub = require("tests.lua.spec.wow_stub")

local NPC = {}
local set = {} -- names of the globals install() set

local function global(name, value)
  _G[name] = value
  set[#set + 1] = name
  return value
end

local function namedFontString(name, text)
  local fs = Stub.namedFontString(name, text)
  set[#set + 1] = name
  return fs
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

local function write(widget, text) -- the client's own write (a FontString, or a button's text region)
  local fs = widget.fontString or widget
  fs.text = text
end

-- A texture region: present among GetRegions(), never a FontString.
local function texture()
  return { GetObjectType = function() return "Texture" end }
end

-- GameTooltip:AppendText [unknown: whether the client appends to the line's current text or to its own copy of the
-- SetText string]: NPC.appendMode "current" (default) or "copy" models each.
local function installAppendText()
  local tt = _G.GameTooltip
  local setText = tt.SetText
  function tt.SetText(self, text, ...)
    self.setTextCopy = text
    return setText(self, text, ...)
  end
  function tt.AppendText(self, text)
    local fs = _G.GameTooltipTextLeft1
    if not fs then return end
    local base = NPC.appendMode == "copy" and (self.setTextCopy or "") or (fs.text or "")
    fs.text = base .. text
    self.lines[1] = fs.text
  end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Gossip [verified: Classic/GossipFrame.xml:34–86; Shared/GossipFrameShared.lua:1–168, 241–294]
local function installGossip()
  global("GOSSIP_BUTTON_TYPE_TITLE", 1)
  global("GOSSIP_BUTTON_TYPE_DIVIDER", 2)
  global("GOSSIP_BUTTON_TYPE_OPTION", 3)
  global("GOSSIP_BUTTON_TYPE_ACTIVE_QUEST", 4)
  global("GOSSIP_BUTTON_TYPE_AVAILABLE_QUEST", 5)
  global("NORMAL_QUEST_DISPLAY", "|cff000000%s|r")
  local gossip = frame("Frame", "GossipFrame")
  namedFontString("GossipFrameTitleText", "")
  local box = Stub.scrollBox()
  gossip.GreetingPanel = { GoodbyeButton = button(nil, "Goodbye"), ScrollBox = box }

  -- The row initializers (ButtonInitializer → button:Setup(info); UpdateTitleForQuest).
  local function initializer(row, data)
    local info = data.info or {}
    if data.buttonType == 3 then
      write(row, info.name)
    elseif data.buttonType == 4 or data.buttonType == 5 then
      local template = _G.NORMAL_QUEST_DISPLAY
      if info.isIgnored then template = _G.IGNORED_QUEST_DISPLAY
      elseif info.isTrivial then template = _G.TRIVIAL_QUEST_DISPLAY end
      write(row, template:format(info.title))
    elseif data.buttonType == 1 then
      write(row, data.text)
    end
  end
  NPC.gossipRows = {}

  -- GossipFrame:Update(): SetDataProvider re-initializes the pooled rows in order; the title is the NPC name.
  function NPC.gossip(entries, npcName)
    for i, data in ipairs(entries) do
      local row = NPC.gossipRows[i] or button(nil, "")
      NPC.gossipRows[i] = row
      box:initFrame(row, data, initializer)
    end
    _G.GossipFrameTitleText.text = npcName or ""
    gossip:Show()
  end
  -- A row acquired later while scrolling.
  function NPC.gossipScroll(data)
    local row = button(nil, "")
    NPC.gossipRows[#NPC.gossipRows + 1] = row
    box:initFrame(row, data, initializer)
    return row
  end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Merchant [verified: Vanilla/MerchantFrame.xml:107–122, 202–281, 432–520; Vanilla/MerchantFrame.lua:84–132, 184–190,
-- 415–480]
local function installMerchant()
  local merchant = frame("Frame", "MerchantFrame")
  merchant.page, merchant.selectedTab = 1, 1
  local tab1, tab2 = Stub.tab("MerchantFrameTab1", "Merchant"), Stub.tab("MerchantFrameTab2", "Buyback")
  set[#set + 1] = "MerchantFrameTab1"; set[#set + 1] = "MerchantFrameTab2"
  merchant.tabs = { tab1, tab2 }
  namedFontString("MerchantNameText", "Merchant Name")
  namedFontString("MerchantPageText", "Page")
  namedFontString("MerchantRepairText", "Repair Items")
  for i = 1, 12 do namedFontString("MerchantItem" .. i .. "Name", "Item Name") end
  namedFontString("MerchantBuyBackItemName", "Item Name")
  for name, text in pairs({ MerchantPrevPageButton = "Prev", MerchantNextPageButton = "Next" }) do
    local b = frame("Button", name)
    b:addRegion(texture())
    b:addRegion(Stub.fontString(text))
  end
  NPC.merchantItems = {} -- buyback / merchant rows: { name }
  NPC.canRepair = true

  local repairAll = frame("Button", "MerchantRepairAllButton")
  repairAll:SetScript("OnEnter", function(self)
    _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if NPC.canRepair then
      _G.GameTooltip:SetText(_G.REPAIR_ALL_ITEMS)
      _G.GameTooltip:AddLine("12|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t") -- GameTooltip_AddMoneyLine
    end
    _G.GameTooltip:Show()
  end)
  local repairItem = frame("Button", "MerchantRepairItemButton")
  repairItem:SetScript("OnEnter", function(self)
    _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    _G.GameTooltip:SetText(_G.REPAIR_AN_ITEM)
  end)

  global("MerchantFrame_UpdateMerchantInfo", function()
    _G.MerchantNameText.text = _G.UnitName("NPC")
    _G.MerchantPageText.text = _G.PAGE_NUMBER:format(_G.MerchantFrame.page)
    for i = 1, 10 do _G["MerchantItem" .. i .. "Name"].text = NPC.merchantItems[i] or "" end
  end)
  global("MerchantFrame_UpdateBuybackInfo", function()
    _G.MerchantNameText.text = _G.MERCHANT_BUYBACK
    for i = 1, 12 do _G["MerchantItem" .. i .. "Name"].text = NPC.merchantItems[i] or "" end
    _G.MerchantPageText:Hide()
  end)
  global("MerchantFrame_Update", function() -- looks the writers up by global name at call time
    if _G.MerchantFrame.selectedTab == 1 then _G.MerchantFrame_UpdateMerchantInfo()
    else _G.MerchantFrame_UpdateBuybackInfo() end
  end)
  global("MerchantFrame_OnShow", function(self)
    self.selectedTab = 1 -- PanelTemplates_SetTab(MerchantFrame, 1)
    _G.PanelTemplates_UpdateTabs(self)
    _G.MerchantFrame_Update()
  end)
  merchant:SetScript("OnShow", _G.MerchantFrame_OnShow) -- XML function= binds the value

  -- Drivers: MERCHANT_SHOW (tabs shown with the frame) and a tab click.
  function NPC.openMerchant()
    tab1:Show(); tab2:Show()
    merchant:Show()
  end
  function NPC.merchantTab(i)
    merchant.selectedTab = i
    _G.PanelTemplates_UpdateTabs(merchant)
    _G.MerchantFrame_Update()
  end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Bank [verified: Vanilla/BankFrame.xml:111–133, 150–233; Vanilla/BankFrame.lua:2, 9–14, 39–68, 206–242]
local function installBank()
  local bank = frame("Frame", "BankFrame")
  bank:addRegion(namedFontString("BankFrameTitleText", ""))
  bank:addRegion(Stub.fontString("Item Slots"))
  bank:addRegion(Stub.fontString("Bag Slots"))
  local info = frame("Frame", "BankFramePurchaseInfo")
  info:addRegion(Stub.fontString("Do you wish to purchase space for an additional bag?"))
  info:addRegion(namedFontString("BankFrameSlotCost", "Cost:"))
  if not NPC.noPurchaseButton then button("BankFramePurchaseButton", "Purchase") end
  local slots = frame("Frame", "BankSlotsFrame")
  NPC.bankSlots = 2 -- purchased bag slots

  global("BankFrameItemButton_OnEnter", function(self)
    local tt = _G.GameTooltip
    tt:SetOwner(self, "ANCHOR_RIGHT")
    if self.item then
      Stub.setItemTooltip(tt, "|Hitem:" .. self.item.id .. ":0:0:0|h[" .. self.item.name .. "]|h", self.item.lines)
    elseif self.isBag then
      tt:SetText(self.tooltipText)
    end
    tt:Show()
  end)
  for i = 1, 6 do
    local b = frame("Button", nil)
    b.isBag = 1
    b.UpdateTooltip = _G.BankFrameItemButton_OnEnter -- captured at OnLoad
    b:SetScript("OnEnter", _G.BankFrameItemButton_OnEnter) -- XML function=
    slots["Bag" .. i] = b
  end
  global("UpdateBagSlotStatus", function()
    for i = 1, 6 do
      slots["Bag" .. i].tooltipText = i <= NPC.bankSlots and _G.BANK_BAG or _G.BANK_BAG_PURCHASE
    end
  end)
  bank:SetScript("OnShow", function()
    _G.BankFrameTitleText.text = _G.UnitName("npc")
    _G.UpdateBagSlotStatus()
  end)
  function NPC.openBank() bank:Show() end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Bags [verified: Classic/ContainerFrame.xml:249, 314–367, 417–429; Classic/ContainerFrame_Shared.lua:713, 941–947,
-- 1479–1510; Blizzard_MainMenuBarBagButtons/Classic/MainMenuBarBagButtons.xml:66–115, .lua:128–148, 240, 286–288;
-- Classic/Keyring.lua:34–38]
local function installBags()
  global("KEYRING_CONTAINER", -2)
  NPC.bagNames = { [0] = "Backpack", [1] = "Small Red Pouch", [2] = "Backpack", [3] = "Keyring" }
  NPC.bindings = { TOGGLEBACKPACK = "B" }
  global("C_Container", { GetBagName = function(id) return NPC.bagNames[id] end })
  global("BagItemSearchBox", Stub.fontString("Backpack"))

  local function suffix(binding) return " |cffffd200(" .. binding .. ")|r" end
  global("ContainerFramePortraitButton_OnEnter", function(self)
    local tt = _G.GameTooltip
    tt:SetOwner(self, "ANCHOR_LEFT")
    if self.id == 0 then
      tt:SetText(_G.BACKPACK_TOOLTIP, 1.0, 1.0, 1.0)
      if NPC.bindings.TOGGLEBACKPACK then tt:AppendText(suffix(NPC.bindings.TOGGLEBACKPACK)) end
    elseif self.id == _G.KEYRING_CONTAINER then
      tt:SetText(_G.KEYRING, 1.0, 1.0, 1.0)
      if NPC.bindings.TOGGLEKEYRING then tt:AppendText(suffix(NPC.bindings.TOGGLEKEYRING)) end
    else
      Stub.setItemTooltip(tt, "|Hitem:828:0:0:0|h[" .. NPC.bagNames[self.id] .. "]|h", { NPC.bagNames[self.id] })
    end
    tt:Show()
  end)
  for i = 1, 13 do
    local name = "ContainerFrame" .. i
    local f = frame("Frame", name)
    namedFontString(name .. "Name", "")
    local portrait = frame("Button", name .. "PortraitButton")
    portrait:SetScript("OnEnter", _G.ContainerFramePortraitButton_OnEnter)
    f.PortraitButton = portrait
    local add = frame("Button", name .. "AddSlotsButton")
    add:SetScript("OnEnter", function(self)
      _G.GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      _G.GameTooltip:SetText(_G.BACKPACK_AUTHENTICATOR_INCREASE_SIZE, 1, 1, 1)
      _G.GameTooltip:Show()
    end)
  end
  global("ContainerFrame_GenerateFrame", function(f, size, id)
    local fs = _G[f:GetName() .. "Name"]
    if size == 1 then
      fs.text = ""
    elseif id == _G.KEYRING_CONTAINER then
      fs.text = _G.KEYRING
    else
      fs.text = _G.C_Container.GetBagName(id)
    end
    f.id = id
    _G[f:GetName() .. "PortraitButton"].id = id
    f:Show()
  end)

  local backpack = frame("CheckButton", "MainMenuBarBackpackButton")
  backpack:SetScript("OnEnter", function(self)
    local tt = _G.GameTooltip
    tt:SetOwner(self, "ANCHOR_LEFT")
    tt:SetText(_G.BACKPACK_TOOLTIP, 1.0, 1.0, 1.0)
    if NPC.bindings.TOGGLEBACKPACK then tt:AppendText(suffix(NPC.bindings.TOGGLEBACKPACK)) end
    tt:Show()
  end)
  local keyring = frame("CheckButton", "KeyRingButton")
  keyring:SetScript("OnEnter", function(self)
    _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    _G.GameTooltip:SetText(_G.KEYRING, 1, 1, 1)
    _G.GameTooltip:AddLine()
  end)
  global("BagSlotButton_OnEnter", function(self)
    local tt = _G.GameTooltip
    tt:SetOwner(self, "ANCHOR_LEFT")
    if self.item then
      Stub.setItemTooltip(tt, "|Hitem:4496:0:0:0|h[" .. self.item .. "]|h", { self.item, "6 Slot Bag" })
      tt:Show()
    else
      tt:SetText(_G.EQUIP_CONTAINER, 1.0, 1.0, 1.0)
    end
  end)
  for i = 0, 3 do
    local slot = frame("CheckButton", "CharacterBag" .. i .. "Slot")
    slot.UpdateTooltip = _G.BagSlotButton_OnEnter -- captured at OnLoad (MainMenuBarBagButtons.lua:240)
    slot:SetScript("OnEnter", function(self) _G.BagSlotButton_OnEnter(self) end) -- method OnEnter → global
  end

  -- Driver: ToggleBag → ContainerFrame_GenerateFrame(ContainerFrame_GetOpenFrame(), size, id).
  NPC.openFrames = 0
  function NPC.openBag(id, size)
    NPC.openFrames = NPC.openFrames + 1
    local f = _G["ContainerFrame" .. NPC.openFrames]
    _G.ContainerFrame_GenerateFrame(f, size or 16, id)
    return f
  end
end

-- Hover / refresh / leave drivers shared by every window.
function NPC.hover(owner) owner.scripts.OnEnter(owner) end
function NPC.refresh(owner) owner:UpdateTooltip() end -- GameTooltip_OnUpdate → owner:UpdateTooltip()
function NPC.leave() _G.GameTooltip:Hide() end

function NPC.install()
  set = {}
  NPC.appendMode = "current"
  Stub.units.NPC = { name = "Merchant Buyback" } -- a name that is also a dictionary word
  Stub.units.npc = { name = "Purchase" }
  installAppendText()
  installGossip()
  installMerchant()
  installBank()
  installBags()
end

function NPC.teardown()
  for _, name in ipairs(set) do _G[name] = nil end
  set = {}
end

return NPC
