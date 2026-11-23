-- UI/GroupLoot.lua: the group loot roll frames and the master looter's window on Forever (surface "grouploot", area
-- "ui", ADR-016 / ADR-029). camelot loads blizzard_uipanels_game/mainline/grouplootframe.lua|xml.
-- - Roll buttons: GroupLootFrame1–4 (grouplootframe.xml:641–644, MKBGroupLootFrameTemplate :482–548) each hold
--   LootButtonContainer.NeedButton / PassButton / GreedButton / TransmogButton. Their text is a tooltip: the inline
--   OnEnter of LootRollButtonTemplate builds GameTooltip_SetTitle(self.tooltipText) (NEED / PASS / GREED /
--   TRANSMOGRIFICATION (:497, 511, 525, 539)) and, for a disabled button, AddLine(self.reason) (:9–16), where reason
--   is _G["LOOT_ROLL_INELIGIBLE_REASON" .. n] (grouplootframe.lua:335–353). Each button is a help-tooltip owner
--   restricted to those keys. `newbieText` (:498, 512, 526) is set and never read on this client.
-- - MasterLooterFrame (grouplootframe.xml:707, a DefaultPanelTemplate): MasterLooterFrame_OnLoad writes
--   TitleContainer.TitleText = ASSIGN_LOOT (grouplootframe.lua:851–852) → Labels.title, shown on OnShow.
-- - Item names: GroupLootFrameN.Name, written by GroupLootFrame_SetupItemDisplay (grouplootframe.lua:312–324), which
--   GroupLootFrame_OnShow calls by name (:371–372); MasterLooterFrame.Item.ItemName, written by MasterLooterFrame_Show
--   (:882–884), called by name (:202). Both globals are post-hooked. Never dictionary words; while names are on each
--   shows the item's Japanese (UI/NameLabels). A roll frame's name is its own record on "grouploot.items", put back
--   when that frame hides, so another open roll keeps its Japanese. Plain labels: fixed-size or anchored FontStrings
--   on plain frames (grouplootframe.xml:310–315, 745–750); the client colours them (SetVertexColor, :327, :890) and
--   never reads or measures them (a roll and the master loot use the roll id and the slot).
-- Never touched: the master looter's player rows' Name (player names, :960), which the client measures
-- (IsTruncated, :968). A GroupLootFrameN without its LootButtonContainer is not this shape: init returns false for it.
-- Not this surface: the master looter's context menu (MASTER_LOOTER, ASSIGN_LOOT, REQUEST_ROLL; :216–253) is a menu
-- popup (UI/Menus); BonusRollFrame and GamepadGroupLootRollFrame are listed in pipeline/ui_exclusions.txt.
local _, WFJ = ...
local GroupLoot = {}
WFJ.GroupLoot = GroupLoot

local SURFACE = "grouploot"
GroupLoot.SURFACE = SURFACE
local Compat = WFJ.Compat

local NUM_FRAMES = 4 -- NUM_GROUP_LOOT_FRAMES (grouplootframe.lua:1)
local BUTTONS = { "NeedButton", "PassButton", "GreedButton", "TransmogButton" }

GroupLoot.NEVER_TOUCH = { "MasterLooterFrame.Item.ItemName" }
for i = 1, NUM_FRAMES do GroupLoot.NEVER_TOUCH[#GroupLoot.NEVER_TOUCH + 1] = "GroupLootFrame" .. i .. ".Name" end

local TOOLTIP = { only = { "NEED", "PASS", "GREED", "TRANSMOGRIFICATION" } }
for i = 1, 7 do TOOLTIP.only[#TOOLTIP.only + 1] = "LOOT_ROLL_INELIGIBLE_REASON" .. i end
GroupLoot.TOOLTIP_KEYS = TOOLTIP.only
local TITLE = { only = { "ASSIGN_LOOT" } }

local ITEMS = SURFACE .. ".items"
GroupLoot.ITEMS = ITEMS

local function frameKey(i) return "frame" .. i end
local function get(key) return Compat.get(SURFACE, key) end
local rollKey = WFJ.Labels.keyer("roll.")

local function masterItemName()
  local master = get("master")
  local item = type(master) == "table" and master.Item or nil
  return type(item) == "table" and item.ItemName or nil
end

function GroupLoot.onMasterShow()
  local n = WFJ.Labels.title(SURFACE, get("master"), TITLE, "master.title")
  WFJ.NameLabels.show(SURFACE, "master.item", masterItemName(), "items")
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- hooksecurefunc target (MasterLooterFrame_Show): the item may change while the window stays open. → 1 | 0
function GroupLoot.onMasterItem()
  return WFJ.NameLabels.show(SURFACE, "master.item", masterItemName(), "items")
end

-- hooksecurefunc target (GroupLootFrame_SetupItemDisplay(frame)). → 1 | 0
function GroupLoot.onRollItem(frame)
  local fs = type(frame) == "table" and frame.Name or nil
  if type(fs) ~= "table" then return 0 end
  local n = WFJ.NameLabels.show(ITEMS, rollKey(fs), fs, "items")
  WFJ.Render.updateBanner(ITEMS)
  return n
end

-- A roll frame hid: only its own name goes back to the English.
local function onRollHide(frame)
  local fs = type(frame) == "table" and frame.Name or nil
  if type(fs) == "table" then WFJ.SurfaceState.drop(ITEMS, rollKey(fs)) end
end

function GroupLoot.release()
  return WFJ.Render.release(SURFACE)
end

local hooked = false
local registered = 0

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init. → false when no roll frame is the mainline
-- shape, else true.
function GroupLoot.init()
  for i = 1, NUM_FRAMES do Compat.declare(SURFACE, frameKey(i), { "GroupLootFrame" .. i }) end
  Compat.declare(SURFACE, "master", { "MasterLooterFrame" })
  Compat.declare(SURFACE, "setupItem", { "GroupLootFrame_SetupItemDisplay" })
  Compat.declare(SURFACE, "masterShow", { "MasterLooterFrame_Show" })
  if hooked then return false end
  local n = 0
  local frames = {}
  for i = 1, NUM_FRAMES do
    local frame = get(frameKey(i))
    local container = type(frame) == "table" and frame.LootButtonContainer or nil
    if type(container) == "table" then
      frames[#frames + 1] = frame
      for _, name in ipairs(BUTTONS) do
        local button = container[name]
        if type(button) == "table" then
          WFJ.HelpTooltip.register(button, TOOLTIP)
          n = n + 1
        end
      end
    end
  end
  if n == 0 then return false end
  hooked = true
  registered = n
  for _, frame in ipairs(frames) do
    if type(frame.HookScript) == "function" then frame:HookScript("OnHide", onRollHide) end
  end
  if type(get("setupItem")) == "function" then
    hooksecurefunc("GroupLootFrame_SetupItemDisplay", GroupLoot.onRollItem)
  end
  if type(get("masterShow")) == "function" then hooksecurefunc("MasterLooterFrame_Show", GroupLoot.onMasterItem) end
  local master = get("master")
  if type(master) == "table" and type(master.HookScript) == "function" then
    master:HookScript("OnShow", GroupLoot.onMasterShow)
    master:HookScript("OnHide", GroupLoot.release)
    GroupLoot.onMasterShow()
  end
  return true
end

function GroupLoot.registered() return registered end
