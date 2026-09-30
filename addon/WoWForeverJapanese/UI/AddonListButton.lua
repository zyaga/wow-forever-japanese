-- UI/AddonListButton.lua: a "Settings · 設定" button on this addon's row in the in-game AddOn List.
-- The list builds rows in a ScrollBox from pooled AddonListEntryTemplate buttons; its element factory looks up the
-- global AddonList_InitAddon on every call, so a post-hook sees every row [verified: AddonList.lua:258–261]. The
-- button sits where the row's hidden "Load AddOn" button would [verified: AddonList.xml:82–85] and is hidden on rows
-- for other addons. The click only opens the settings; the addon never calls HideUIPanel (a taint
-- path); the Settings panel manages the panels itself. Should opening it close the list, unsaved enable /
-- disable changes would be reset [verified: AddonList.lua:660–669], so with changes pending the button is disabled and
-- says why. Installed only when the settings pages registered. Not available at character select (no addons loaded).
local _, WFJ = ...
local AddonListButton = {}
WFJ.AddonListButton = AddonListButton

local W, Text, C = WFJ.OptionsWidgets, WFJ.OptionsText, WFJ.Compat

AddonListButton.installed = false

local function hasChanges()
  local fn = C.resolve("AddonList_HasAnyChanged")
  return type(fn) == "function" and fn() == true
end

local tip
local function showReason(owner)
  -- parented to UIParent: the list's ScrollBox clips its children, and rows are pooled [verified: ScrollBox.xml:20]
  tip = tip or CreateFrame("GameTooltip", "WFJSettingsTooltip", C.resolve("UIParent"), "GameTooltipTemplate")
  -- one language, like the rest of the addon's copy
  local text = W.pick(Text.get("warn.addonChanges"))
  tip:SetOwner(owner, "ANCHOR_RIGHT")
  tip:SetText(text, 1, 1, 1)
  local line = C.resolve("WFJSettingsTooltipTextLeft1")
  if line then W.setText(line, text, 12) end
  tip:Show()
end

-- Opens the settings from the list. → true when the settings were opened
function AddonListButton.open()
  if hasChanges() then return false end
  return C.openOptions()
end

local function decorate(entry, treeNode)
  local data = treeNode and treeNode.GetData and treeNode:GetData()
  local index = data and data.addonIndex
  local ours = index ~= nil and C_AddOns.GetAddOnName(index) == WFJ.ADDON
  local b = entry.wfjSettings
  if not ours then
    if b then b:Hide() end
    return
  end
  if not b then
    local en, ja = Text.get("button.settings")
    b = W.button(entry, en, ja, 110, function() AddonListButton.open() end)
    b:SetPoint("LEFT", entry.Title, "RIGHT", 70, 0)
    b:SetMotionScriptsWhileDisabled(true)
    b:SetScript("OnEnter", function(self) if not self:IsEnabled() then showReason(self) end end)
    b:SetScript("OnLeave", function() if tip then tip:Hide() end end)
    entry.wfjSettings = b
  end
  b:setEnabled(not hasChanges())
  b:Show()
end

-- Runs inside the list's own row initializer: a failure here must not break the AddOn List.
function AddonListButton.decorate(entry, treeNode)
  local ok, err = pcall(decorate, entry, treeNode)
  if not ok then AddonListButton.error = tostring(err) end
end

-- Hooks the list's row initializer once, when the settings pages registered. → true when installed (now or before)
function AddonListButton.install()
  if AddonListButton.installed then return true end
  if C.optionsCategories == nil then return false end
  if type(C.resolve("AddonList_InitAddon")) ~= "function" then return false end
  hooksecurefunc("AddonList_InitAddon", function(entry, treeNode) AddonListButton.decorate(entry, treeNode) end)
  AddonListButton.installed = true
  return true
end
