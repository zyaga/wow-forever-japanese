-- UI/Merchant.lua: the merchant window's fixed words (surface "merchant", area "ui", ADR-016).
-- Camelot loads the mainline [Family]\MerchantFrame.lua|xml at login [verified: blizzard_uipanels_game.toc:110–115].
-- Static (shown at init, before the first show, so each tab's own OnShow → PanelTemplates_TabResize measures the
-- Japanese): MerchantFrameTab1 / Tab2 (XML text="MERCHANT" / "BUYBACK"); the unnamed Prev / Next FontStrings, regions
--   of MerchantPrevPageButton / MerchantNextPageButton found by the client's English (Labels.region). Tab font resets
--   (PanelTemplates_SetTab → UpdateTabs and the tab OnClick) are ButtonText's tab hooks.
-- Dynamic: MerchantFrame_Update calls MerchantFrame_UpdateMerchantInfo / _UpdateBuybackInfo by global name
-- (mainline/merchantframe.lua:192–217), so post-hooks on those two globals follow every refresh:
--   title: UpdateMerchantInfo writes MerchantFrame:SetTitle(UnitName("npc")) (a name: its record is dropped, never
--     matched), and UpdateBuybackInfo SetTitle(MERCHANT_BUYBACK) (lua:274–275, 532–533) → TitleContainer.TitleText
--     (blizzard_sharedxml/portraitframe.lua:11–13), shown with `only`. A global MerchantFrameTitleText is tried first
--     (whether the `$parent` name resolves through the unnamed TitleContainer is an in-game check).
--   page: MerchantPageText, SetFormattedText(MERCHANT_PAGE_NUMBER, page, pages) (lua:280), a template like
--     PAGE_NUMBER.
--   filter dropdown: MerchantFrame.FilterDropdown (a Menu dropdown; lua:21–65) shows its selection in .Text via
--     UpdateText (Labels.dropdown's writer): a spec name, the class name (ALL_SPECS is translated to UnitClass),
--     ITEM_BIND_ON_EQUIP or ALL. Names stay English: only ITEM_BIND_ON_EQUIP / ALL. Hidden when the game rule
--     MerchantFilterDisabled is active (lua:193–197) [unknown on Forever].
-- Help tooltips: MerchantRepairAllButton / MerchantRepairItemButton build theirs inline (SetText(REPAIR_ALL_ITEMS) +
-- a money line; SetText(REPAIR_AN_ITEM)); MerchantSellAllJunkButton (SetText(SELL_ALL_JUNK_ITEMS), xml:220–224) and
-- MerchantGuildBankRepairButton, shown when CanGuildBankRepair() (lua:987–1003): REPAIR_ALL_ITEMS, a money line,
-- GUILDBANK_REPAIR, a money line, GUILDBANK_REPAIR_PERSONAL / _INSUFFICIENT_FUNDS (xml:345–378); every line `only`.
-- Release of the dynamic surface on MerchantFrame's OnHide.
local _, WFJ = ...
local Merchant = {}
WFJ.Merchant = Merchant

local SURFACE = "merchant"
Merchant.SURFACE = SURFACE
local STATIC = SURFACE .. ".static"
Merchant.STATIC = STATIC
local Compat = WFJ.Compat

-- Widgets this module must never record: item names on the merchant and buyback rows.
Merchant.NEVER_TOUCH = { "MerchantBuyBackItemName" }
for i = 1, 12 do Merchant.NEVER_TOUCH[#Merchant.NEVER_TOUCH + 1] = "MerchantItem" .. i .. "Name" end

local CANDIDATES = {
  frame          = { "MerchantFrame" },
  tab1           = { "MerchantFrameTab1" },
  tab2           = { "MerchantFrameTab2" },
  prevButton     = { "MerchantPrevPageButton" },
  nextButton     = { "MerchantNextPageButton" },
  pageText       = { "MerchantPageText" },
  nameText       = { "MerchantFrameTitleText", "MerchantFrame.TitleContainer.TitleText" },
  repairAll      = { "MerchantRepairAllButton" },
  repairItem     = { "MerchantRepairItemButton" },
  updateMerchant = { "MerchantFrame_UpdateMerchantInfo" },
  updateBuyback  = { "MerchantFrame_UpdateBuybackInfo" },
  sellJunk       = { "MerchantSellAllJunkButton" },
  guildRepair    = { "MerchantGuildBankRepairButton" },
  filter         = { "MerchantFrame.FilterDropdown" },
}
local GUILD_REPAIR_KEYS = { "REPAIR_ALL_ITEMS", "GUILDBANK_REPAIR", "GUILDBANK_REPAIR_PERSONAL",
  "GUILDBANK_REPAIR_INSUFFICIENT_FUNDS" }
local FILTER_ONLY = { only = { "ALL", "ITEM_BIND_ON_EQUIP" } }

local function get(key) return Compat.get(SURFACE, key) end

-- The load-time words. → the number of dictionary words found.
function Merchant.showStatic()
  return WFJ.Labels.showAll(STATIC, {
    { "ui.tab1", get("tab1") },
    { "ui.tab2", get("tab2") },
    { "ui.prev", WFJ.Labels.region(get("prevButton"), "PREV") },
    { "ui.next", WFJ.Labels.region(get("nextButton"), "NEXT") },
  })
end

local BUYBACK_TITLE = { only = { "MERCHANT_BUYBACK" } }

-- hooksecurefunc target: the merchant tab was written. → the number of dictionary words found.
function Merchant.onMerchantInfo()
  WFJ.SurfaceState.drop(SURFACE, "ui.title") -- the NPC name now: the buyback title's record goes
  return WFJ.Labels.showAll(SURFACE, { { "ui.page", get("pageText") } })
end

-- hooksecurefunc target: the buyback tab was written. → the number of dictionary words found.
-- The title goes through the shared SetTitle helper: the same widget, record and `only`, re-shown after
-- every SetTitle (the NPC's name never matches, so its SetTitle drops the record as onMerchantInfo does). A frame
-- without a TitleContainer: the helper finds nothing and the title candidates are shown directly.
function Merchant.onBuybackInfo()
  local n = WFJ.Labels.title(SURFACE, get("frame"), BUYBACK_TITLE, "ui.title")
  if n > 0 then
    WFJ.Render.updateBanner(SURFACE)
    return n
  end
  return WFJ.Labels.showAll(SURFACE, { { "ui.title", get("nameText"), BUYBACK_TITLE } })
end

-- After the filter dropdown's UpdateText. → 1 | 0
function Merchant.onFilterText()
  local dropdown = get("filter")
  local n = WFJ.Labels.show(SURFACE, "ui.filter", type(dropdown) == "table" and dropdown.Text or nil, nil, FILTER_ONLY)
  WFJ.Render.updateBanner(SURFACE)
  return n
end

function Merchant.release()
  return WFJ.Render.release(SURFACE)
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function Merchant.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  if hooked then return false end
  local frame = get("frame")
  if type(frame) ~= "table" then return false end
  hooked = true
  Merchant.showStatic()
  if type(get("updateMerchant")) == "function" then
    hooksecurefunc("MerchantFrame_UpdateMerchantInfo", Merchant.onMerchantInfo)
  end
  if type(get("updateBuyback")) == "function" then
    hooksecurefunc("MerchantFrame_UpdateBuybackInfo", Merchant.onBuybackInfo)
  end
  WFJ.HelpTooltip.register(get("repairAll"), { only = { "REPAIR_ALL_ITEMS" } })
  WFJ.HelpTooltip.register(get("repairItem"), { only = { "REPAIR_AN_ITEM" } })
  WFJ.HelpTooltip.register(get("sellJunk"), { only = { "SELL_ALL_JUNK_ITEMS" } })
  WFJ.HelpTooltip.register(get("guildRepair"), { only = GUILD_REPAIR_KEYS })
  local filter = get("filter")
  if type(filter) == "table" and type(filter.UpdateText) == "function" then
    hooksecurefunc(filter, "UpdateText", Merchant.onFilterText)
    Merchant.onFilterText()
  end
  if type(frame.HookScript) == "function" then frame:HookScript("OnHide", Merchant.release) end
  return true
end
