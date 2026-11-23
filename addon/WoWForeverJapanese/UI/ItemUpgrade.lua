-- UI/ItemUpgrade.lua: the item upgrade window on Forever (surface "itemupgrade", area "ui", ADR-016,
-- ADR-029). Load-on-demand Blizzard_ItemUpgradeUI (Mainline\Blizzard_ItemUpgradeUI.lua|xml on `camelot`); its
-- [Bootstrap] file registers Enum.PlayerInteractionType.ItemUpgrade at login → ShowItemUpgradeFrame
-- (blizzard_itemupgradeui_bootstrap.lua:7–33), so the window opens when an NPC sends that interaction. Whether
-- Forever has one is an in-game question. Set up through WFJ.LoadOnDemand.when.
-- Title: ItemUpgradeFrame:SetTitle(ITEM_UPGRADE) (mainline/blizzard_itemupgradeui.lua:22), through Labels.title.
-- Static labels (XML text=, mainline/blizzard_itemupgradeui.xml), each restricted to its own key:
--   MissingDescription ITEM_UPGRADE_DESCRIPTION (:210), ItemInfo.MissingItemText UPGRADE_MISSING_ITEM (:274),
--   ItemInfo.UpgradeTo ITEM_UPGRADE_FRAME_UPGRADE_TO (:293), UpgradeButton UPGRADE (:358).
-- Writer: ItemUpgradeFrame:PopulatePreviewFrames (:238; the frame's own method, called as `self:…`, :169) → the
--   Left / RightPreviewBigText, PVP_ITEM_LEVEL_TOOLTIP when the item has a PvP item level (:831–855). The same
--   FontStrings hold an item effect's text otherwise (:860), hence the restriction.
-- PopulatePreviewFrames also writes FrameErrorText with ITEM_UPGRADE_NO_MORE_UPGRADES for a maxed item (or the
--   server's failure message, never matched) and gives UpgradeButton the same as its disabled tooltip (:238–262):
--   the label restricted to that key, the button a help-tooltip owner restricted to it.
-- The item's name: ItemInfo.ItemName, written in the item's quality colour by ItemInfo:Setup (:992, called as
--   self.ItemInfo:Setup from UpdateUpgradeItemInfo and PopulatePreviewFrames, :111, 262) and by
--   PlayUpgradedCelebration (:646, called as self:… from OnConfirm, :101–103). Setup ends with the info panel's
--   Layout (a ResizeLayoutFrame, xml:268; lua:1009), which measures the English; the name is shown after it, from
--   post-hooks on both writers, so the client never measures this addon's text. The window's one server call,
--   C_ItemUpgrade.UpgradeItem(self.numUpgradeLevels) (:103), reads nothing the layout wrote. While names are on it
--   shows the item's Japanese with its colour code kept (UI/NameLabels.wrapped).
-- Never touched: the upgrade progress line (a track name inside ITEM_UPGRADE_PROGRESS_LEVEL_FORMAT_STRING, :997),
-- the upgrade-level dropdown, the stat previews (item tooltip lines in pooled frames), costs and currency names.
-- Release on the frame's OnHide.
local _, WFJ = ...
local ItemUpgrade = {}
WFJ.ItemUpgrade = ItemUpgrade

local SURFACE = "itemupgrade"
ItemUpgrade.SURFACE = SURFACE
local Compat = WFJ.Compat
local ADDON = "Blizzard_ItemUpgradeUI"
local F = "ItemUpgradeFrame"

ItemUpgrade.NEVER_TOUCH = { F .. ".ItemInfo.ItemName", F .. ".ItemInfo.UpgradeProgress" }

local TITLE = { only = { "ITEM_UPGRADE" } }
local PVP = { "PVP_ITEM_LEVEL_TOOLTIP" }
-- record key → { candidate, the key(s) the widget may show }
local LABELS = {
  description = { F .. ".MissingDescription", { "ITEM_UPGRADE_DESCRIPTION" } },
  missingItem = { F .. ".ItemInfo.MissingItemText", { "UPGRADE_MISSING_ITEM" } },
  upgradeTo = { F .. ".ItemInfo.UpgradeTo", { "ITEM_UPGRADE_FRAME_UPGRADE_TO" } },
  upgrade = { F .. ".UpgradeButton", { "UPGRADE" } },
  leftBig = { F .. ".LeftPreviewBigText", PVP }, rightBig = { F .. ".RightPreviewBigText", PVP },
  frameError = { F .. ".FrameErrorText", { "ITEM_UPGRADE_NO_MORE_UPGRADES" } },
}
local ORDER = { "description", "frameError", "leftBig", "missingItem", "rightBig", "upgrade", "upgradeTo" }
local OPTS = {}
for key, l in pairs(LABELS) do OPTS[key] = { only = l[2] } end

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  Compat.declare(SURFACE, "frame", { F })
  Compat.declare(SURFACE, "itemInfo", { F .. ".ItemInfo" })
  Compat.declare(SURFACE, "itemName", { F .. ".ItemInfo.ItemName" })
  for key, l in pairs(LABELS) do Compat.declare(SURFACE, key, { l[1] }) end
end

-- After ItemInfo:Setup and PlayUpgradedCelebration. → 1 | 0
function ItemUpgrade.showName()
  local n = WFJ.NameLabels.wrapped(SURFACE, "itemName", get("itemName"), "items")
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- OnShow and hooksecurefunc target (ItemUpgradeFrame:PopulatePreviewFrames). → the number of dictionary words found
function ItemUpgrade.show()
  local list = {}
  for _, key in ipairs(ORDER) do list[#list + 1] = { key, get(key), OPTS[key] } end
  return WFJ.Labels.showAll(SURFACE, list) + WFJ.Labels.title(SURFACE, get("frame"), TITLE) + ItemUpgrade.showName()
end

function ItemUpgrade.release()
  return WFJ.Render.release(SURFACE)
end

local hooked, waiting = false, false

-- Runs once Blizzard_ItemUpgradeUI is loaded (now, or on its ADDON_LOADED).
function ItemUpgrade.setup()
  declare() -- its frames exist only now: forget what Compat memoized before
  local frame = get("frame")
  if hooked or type(frame) ~= "table" then return false end
  hooked = true
  WFJ.Labels.forbidNames(ItemUpgrade.NEVER_TOUCH)
  WFJ.Labels.title(SURFACE, frame, TITLE) -- hooks SetTitle once
  local button = get("upgrade")
  if type(button) == "table" then WFJ.HelpTooltip.register(button, OPTS.frameError) end -- its disabled tooltip
  if type(frame.PopulatePreviewFrames) == "function" then
    hooksecurefunc(frame, "PopulatePreviewFrames", ItemUpgrade.show)
  end
  if type(frame.PlayUpgradedCelebration) == "function" then
    hooksecurefunc(frame, "PlayUpgradedCelebration", ItemUpgrade.showName)
  end
  local info = get("itemInfo")
  if type(info) == "table" and type(info.Setup) == "function" then
    hooksecurefunc(info, "Setup", ItemUpgrade.showName)
  end
  if type(frame.HookScript) == "function" then
    frame:HookScript("OnShow", ItemUpgrade.show)
    frame:HookScript("OnHide", ItemUpgrade.release)
  end
  if type(frame.IsShown) == "function" and frame:IsShown() then ItemUpgrade.show() end
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init. → true when the window
-- exists now, false while it waits for the addon.
function ItemUpgrade.init()
  declare()
  if hooked then return false end
  if not waiting then
    waiting = true
    return WFJ.LoadOnDemand.when(ADDON, ItemUpgrade.setup) and hooked
  end
  return false
end
