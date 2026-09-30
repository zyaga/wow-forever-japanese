-- UI/Bank.lua: the bank window's fixed words (surfaces "bank" and "bank.static", area "ui",
-- ADR-016). Camelot loads [Game]\BankFrame.lua|xml over the mainline [Family]\BankFrameTemplates.lua|xml at login
-- [verified: blizzard_uipanels_game.toc:137–141, 190–194] (the mainline [Family]\BankFrame.xml, with the TabSystem
-- and the AutoDepositFrame, is excluded for camelot, :140). The global BankFrame:
--   static: "Item Slots" / "Bag Slots", unnamed FontString regions of BankFrame (Labels.region by the client's
--     English); BankFrame.BagCost (COSTS_LABEL) and BankFrame.BagText (BAGSLOTTEXT_COLON) (camelot/bankframe.xml:
--     62–75); BankFrame.BankPanel.PurchaseButton (BANKSLOTPURCHASE, :108); the money frame's Withdraw / Deposit
--     buttons (mainline/bankframetemplates.xml:205, 214; their Refresh never writes text, bankframetemplates.lua:
--     1401–1435); the purchase prompt's TabCost / PurchaseButton (xml:541–556); the tab settings menu's three headers
--     (xml:61–80). The prompt's title and body are server data, never shown.
--   title: BankFrame:SetTitle(BANK) (bankframetemplates.lua:22–24, 946–949) is NOT translated: a bare "Bank" label
--     ships as the English (pipeline/translation_glossary.tsv).
--   lock prompt: BankPanel.LockPrompt:Refresh (self:Refresh() from its OnShow, lua:1170–1174, 1203–1205) writes
--     PromptText = BANK_LOCKED_REASON_* (:1188–1192, 1207–1209).
--   deposit checkboxes: BankPanelCheckboxMixin:Init (self:Init() from OnShow) writes Text = self.text on every show
--     (lua:1743–1768); each of TabSettingsMenu.DepositSettingsMenu.DepositSettingsCheckboxes is hooked.
--   help tooltips: BankPanel.AutoSortButton (SetText(BAG_CLEANUP_BANK), lua:1831–1837); pooled buttons walked after
--     their writer (never by index): BankFrame:RefreshBagButtons → itemButtonBagPool (tooltipText = BANK_BAG /
--     BANK_BAG_PURCHASE, OnEnter SetText(self.tooltipText) unless SetBagItem shows the bag, camelot/bankframe.lua:
--     136–190, 330–343); BankFrame:RefreshPageTabs → bankPageTabPool (tooltipText = PAGE_NUMBER, SidePanelTabButton
--     OnEnter SetText, :104–134, 285–299; blizzard_sharedxml/mainline/shareduipaneltemplates.lua:406–420);
--     BankPanel:RefreshBankTabs → bankTabPool (only when not C_Bank.ShouldUsePlayerBagsInBank(), lua:673–675, 964;
--     line 1 is the player's tab name, so only BANK_TAB_TOOLTIP_CLICK_INSTRUCTION, :329–338). The tab's
--     deposit settings lines between them (AddBankTabSettingsToTooltip, mainline/bankframetemplates.lua:311–326):
--     BANK_TAB_EXPANSION_ASSIGNMENT (an `entry`: BANK_TAB_EXPANSION_FILTER_CURRENT / _LEGACY) and
--     BANK_TAB_DEPOSIT_ASSIGNMENTS (an `entryList` of BAG_FILTER_LABELS joined with LIST_DELIMITER).
-- Release of the dynamic surface on BankFrame's OnHide.
local _, WFJ = ...
local Bank = {}
WFJ.Bank = Bank

local SURFACE = "bank"
Bank.SURFACE = SURFACE
local STATIC = SURFACE .. ".static"
Bank.STATIC = STATIC
local Compat = WFJ.Compat

-- Widgets this module must never record: an explicit title FontString. BankItemSearchBox (an EditBox) is not listed:
-- no widget here resolves to it.
Bank.NEVER_TOUCH = { "BankFrameTitleText" }

local function set(list)
  local s = {}
  for _, k in ipairs(list) do s[k] = true end
  return s
end

local CANDIDATES = {
  frame          = { "BankFrame" },
  slotCost       = { "BankFrame.BagCost" },
  purchaseButton = { "BankFrame.BankPanel.PurchaseButton" },
  bagText        = { "BankFrame.BagText" },
  panel          = { "BankFrame.BankPanel" },
  withdraw       = { "BankFrame.BankPanel.MoneyFrame.WithdrawButton" },
  deposit        = { "BankFrame.BankPanel.MoneyFrame.DepositButton" },
  promptCost     = { "BankFrame.BankPanel.PurchasePrompt.TabCostFrame.TabCost" },
  promptPurchase = { "BankFrame.BankPanel.PurchasePrompt.TabCostFrame.PurchaseButton" },
  lockPrompt     = { "BankFrame.BankPanel.LockPrompt" },
  autoSort       = { "BankFrame.BankPanel.AutoSortButton" },
  depositMenu    = { "BankFrame.BankPanel.TabSettingsMenu.DepositSettingsMenu" },
}
local BAG_SLOT_KEYS = { "BANK_BAG", "BANK_BAG_PURCHASE" }
local LOCK_ONLY = { only = set({ "BANK_LOCKED_REASON_BANK_CONVERSION_FAILED", "BANK_LOCKED_REASON_BANK_DISABLED" }) }
local CHECKBOX_ONLY = { only = set({ "BANK_TAB_ASSIGN_EQUIPMENT_CHECKBOX", "BANK_TAB_ASSIGN_CONSUMABLES_CHECKBOX",
  "BANK_TAB_ASSIGN_PROFESSION_GOODS_CHECKBOX", "BANK_TAB_ASSIGN_REAGENTS_CHECKBOX", "BANK_TAB_ASSIGN_JUNK_CHECKBOX",
  "BANK_TAB_IGNORE_IN_CLEANUP_CHECKBOX" }) }
local HEADERS = { "AssignExpansionHeader", "AssignSettingsHeader", "CleanUpSettingsHeader" }
Bank.CAMELOT_KEYS = { lock = LOCK_ONLY.only, checkbox = CHECKBOX_ONLY.only }

local function get(key) return Compat.get(SURFACE, key) end

-- The load-time words. → the number of dictionary words found.
function Bank.showStatic()
  local frame, menu = get("frame"), get("depositMenu")
  local items = {
    { "ui.itemSlots", WFJ.Labels.region(frame, "ITEMSLOTTEXT") },
    { "ui.bagSlots", WFJ.Labels.region(frame, "BAGSLOTTEXT") },
    { "ui.cost", get("slotCost") },
    { "ui.purchase", get("purchaseButton") },
    { "ui.bagText", get("bagText") },
    { "ui.withdraw", get("withdraw") },
    { "ui.deposit", get("deposit") },
    { "ui.promptCost", get("promptCost") },
    { "ui.promptPurchase", get("promptPurchase") },
  }
  for _, key in ipairs(HEADERS) do
    items[#items + 1] = { "ui.header." .. key, type(menu) == "table" and menu[key] or nil }
  end
  return WFJ.Labels.showAll(STATIC, items)
end

-- Registers every active object of a frame pool as a help-tooltip owner. → the number registered.
local function registerPool(pool, only)
  if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then return 0 end
  local n = 0
  for obj in pool:EnumerateActive() do
    if type(obj) == "table" then
      WFJ.HelpTooltip.register(obj, { only = only })
      n = n + 1
    end
  end
  return n
end

-- hooksecurefunc targets, `self` the frame whose method ran. → the number registered.
function Bank.onBagButtons(self)
  return registerPool(type(self) == "table" and self.itemButtonBagPool or nil, BAG_SLOT_KEYS)
end
function Bank.onPageTabs(self)
  return registerPool(type(self) == "table" and self.bankPageTabPool or nil, { "PAGE_NUMBER" })
end
local BANK_TAB_KEYS = { "BANK_TAB_TOOLTIP_CLICK_INSTRUCTION", "BANK_TAB_EXPANSION_ASSIGNMENT",
  "BANK_TAB_DEPOSIT_ASSIGNMENTS" }
function Bank.onBankTabs(self)
  return registerPool(type(self) == "table" and self.bankTabPool or nil, BANK_TAB_KEYS)
end

-- After LockPrompt:Refresh. → 1 | 0
function Bank.onLockPrompt()
  local prompt = get("lockPrompt")
  local n = WFJ.Labels.show(SURFACE, "ui.lock", type(prompt) == "table" and prompt.PromptText or nil, nil, LOCK_ONLY)
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- After a deposit checkbox's Init (its Text is rewritten on every show). → 1 | 0
local checkboxKeys = setmetatable({}, { __mode = "k" }) -- checkbox → its record key
function Bank.onCheckboxInit(checkbox)
  local key = checkboxKeys[checkbox]
  if not key or type(checkbox) ~= "table" then return 0 end
  return WFJ.Labels.showAll(STATIC, { { key, checkbox.Text, CHECKBOX_ONLY } })
end

function Bank.release()
  return WFJ.Render.release(SURFACE)
end

-- A method hook on a frame instance, only when it is a function there. → true | false
local function hookMethod(frame, method, fn)
  if type(frame) ~= "table" or type(frame[method]) ~= "function" then return false end
  hooksecurefunc(frame, method, fn)
  return true
end

-- The writer hooks (each only where it resolves).
local function hookWriters(frame)
  local panel = get("panel")
  if type(panel) ~= "table" then return false end
  if hookMethod(frame, "RefreshBagButtons", Bank.onBagButtons) then Bank.onBagButtons(frame) end
  if hookMethod(frame, "RefreshPageTabs", Bank.onPageTabs) then Bank.onPageTabs(frame) end
  if hookMethod(panel, "RefreshBankTabs", Bank.onBankTabs) then Bank.onBankTabs(panel) end
  if hookMethod(get("lockPrompt"), "Refresh", Bank.onLockPrompt) then Bank.onLockPrompt() end
  local autoSort = get("autoSort")
  if type(autoSort) == "table" then WFJ.HelpTooltip.register(autoSort, { only = { "BAG_CLEANUP_BANK" } }) end
  local menu = get("depositMenu")
  local boxes = type(menu) == "table" and menu.DepositSettingsCheckboxes or nil
  if type(boxes) == "table" then
    for i, box in ipairs(boxes) do
      if type(box) == "table" then
        checkboxKeys[box] = "ui.checkbox." .. i -- a fixed XML child, never pooled
        if hookMethod(box, "Init", Bank.onCheckboxInit) then Bank.onCheckboxInit(box) end
      end
    end
  end
  if type(frame.HookScript) == "function" then frame:HookScript("OnHide", Bank.release) end
  return true
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function Bank.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  if hooked then return false end
  local frame = get("frame")
  if type(frame) ~= "table" then return false end
  hooked = true
  Bank.showStatic()
  hookWriters(frame)
  return true
end
