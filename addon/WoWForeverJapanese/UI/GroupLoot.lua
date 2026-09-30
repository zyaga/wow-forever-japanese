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
-- Never touched: GroupLootFrameN.Name (the item's name, grouplootframe.lua:319), MasterLooterFrame.Item.ItemName and
-- the player rows' Name (:893, :966). A GroupLootFrameN without its LootButtonContainer is not this shape: init
-- returns false for it.
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

local function frameKey(i) return "frame" .. i end
local function get(key) return Compat.get(SURFACE, key) end

function GroupLoot.onMasterShow()
  local n = WFJ.Labels.title(SURFACE, get("master"), TITLE, "master.title")
  WFJ.Render.updateBanner(SURFACE)
  return n
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
  if hooked then return false end
  local n = 0
  for i = 1, NUM_FRAMES do
    local frame = get(frameKey(i))
    local container = type(frame) == "table" and frame.LootButtonContainer or nil
    if type(container) == "table" then
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
  local master = get("master")
  if type(master) == "table" and type(master.HookScript) == "function" then
    master:HookScript("OnShow", GroupLoot.onMasterShow)
    master:HookScript("OnHide", GroupLoot.release)
    GroupLoot.onMasterShow()
  end
  return true
end

function GroupLoot.registered() return registered end
