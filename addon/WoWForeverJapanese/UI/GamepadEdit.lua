-- UI/GamepadEdit.lua: the gamepad action-bar edit window on Forever (surface "gamepadedit", area "ui",
-- ADR-016). Blizzard_GamepadActionBars is a camelot-only login addon (`## AllowLoadGameType: camelot`,
-- blizzard_gamepadactionbars.toc:5). GamepadActionBarEditFrame (actionbareditframe.xml:110) opens from the gamepad
-- prompts "Edit Action Bar" / "Bind" of the spellbook, bags, paperdoll, macro window and quest tracker
-- (GamepadActionBarEditFrame:BindItem / BindSpell / BindMacro …: blizzard_uipanels_game/mainline/
-- containerframe.lua:3213, camelot/paperdollframe.lua:1752, blizzard_macroui/blizzard_macroui.lua:48), so only with
-- a gamepad in use. Without the frame init returns false.
-- Static labels, written once at load and never again [verified: actionbareditframe.xml / .lua]:
--   BindingInfoFrame.TitleBox.TitleText          GAMEPAD_EDIT_FRAME_BIND_INFO_FRAME_TITLE (xml:39; the title box's
--     OnLoad writes self.Title and sizes the box from the English width + 60, lua:985–990; in-game check: the
--     Japanese fits the box);
--   BindingInfoFrame.BindInstructionText         GAMEPAD_EDIT_FRAME_BIND_INFO_FRAME_BIND_INSTRUCTION (xml:51);
--   EditActionBarsInfoFrame.TitleBox.TitleText   GAMEPAD_EDIT_FRAME_EDIT_ACTION_BARS_INFO_FRAME_TITLE (xml:83);
--   EditActionBarsInfoFrame.PickupInstructionText  …_EDIT_ACTION_BARS_INFO_FRAME_PICKUP_INSTRUCTION (xml:95).
-- Shown at init and again on the window's OnShow (a record dropped meanwhile is taken again).
-- Never touched: BindingInfoFrame.ActionName: the spell, item, macro or equipment-set name being bound
-- (lua:216). The button prompts along the bottom are drawn by GamepadSharedUtility, not by this window. The bind /
-- move failures are UIErrorsFrame lines (actionbindingutil.lua:145–285, actionbareditframe.lua:66–846), not window
-- text. The bars themselves show icons, counts and slot glyphs only.
local _, WFJ = ...
local GamepadEdit = {}
WFJ.GamepadEdit = GamepadEdit

local SURFACE = "gamepadedit"
GamepadEdit.SURFACE = SURFACE
local Compat = WFJ.Compat

local FRAME = "GamepadActionBarEditFrame"
GamepadEdit.NEVER_TOUCH = { FRAME .. ".BindingInfoFrame.ActionName" }

local CANDIDATES = {
  frame = { FRAME },
  bindTitle = { FRAME .. ".BindingInfoFrame.TitleBox.TitleText" },
  bindInstruction = { FRAME .. ".BindingInfoFrame.BindInstructionText" },
  editTitle = { FRAME .. ".EditActionBarsInfoFrame.TitleBox.TitleText" },
  editInstruction = { FRAME .. ".EditActionBarsInfoFrame.PickupInstructionText" },
}
local LABELS = {
  { "bindTitle", { only = { "GAMEPAD_EDIT_FRAME_BIND_INFO_FRAME_TITLE" } } },
  { "bindInstruction", { only = { "GAMEPAD_EDIT_FRAME_BIND_INFO_FRAME_BIND_INSTRUCTION" } } },
  { "editTitle", { only = { "GAMEPAD_EDIT_FRAME_EDIT_ACTION_BARS_INFO_FRAME_TITLE" } } },
  { "editInstruction", { only = { "GAMEPAD_EDIT_FRAME_EDIT_ACTION_BARS_INFO_FRAME_PICKUP_INSTRUCTION" } } },
}

-- HookScript("OnShow") target. → the number of dictionary words found.
function GamepadEdit.showAll()
  local n = 0
  for _, item in ipairs(LABELS) do
    n = n + WFJ.Labels.show(SURFACE, item[1], Compat.get(SURFACE, item[1]), nil, item[2])
  end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function GamepadEdit.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  local frame = Compat.get(SURFACE, "frame")
  if hooked or type(frame) ~= "table" then return false end -- no gamepad edit window
  hooked = true
  if type(frame.HookScript) == "function" then frame:HookScript("OnShow", GamepadEdit.showAll) end
  GamepadEdit.showAll()
  return true
end
