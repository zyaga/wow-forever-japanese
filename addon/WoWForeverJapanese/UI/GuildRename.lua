-- UI/GuildRename.lua: the guild rename NPC window on Forever (surface "guildrename", area "ui", ADR-016).
-- Blizzard_GuildRename loads at login on `camelot` (blizzard_guildrename.toc `## AllowLoadGameType: standard,
-- camelot`, `## LoadOnDemand: 0`). Entry point: RegisterPlayerInteraction(Enum.PlayerInteractionType.GuildRename,
-- { frame = "GuildRenameFrame", showFunc }) (blizzard_guildrename.lua:40–54) → GuildRenameFrame:BeginInteraction →
-- ShowUIPanel (:293–321). Without GuildRenameFrame init returns false.
-- Every child is a parentKey (dotted Compat names). Writers, each the frame's own mixin method called as `self:…()`
-- or `<child>:…()` (method lookup at call time), post-hooked on the instance:
--   GuildRenameFrame:UpdateInteractionMode (:323–333; GUILD_RENAME_STATUS_UPDATE :132–142, BeginInteractionMode
--     :314–321) → TitleFlow:UpdateFromStatus writes TitleFlow.Description: GUILD_RENAME_OPTIONS_DESCRIPTION,
--     GUILD_RENAME_ERROR_NO_PERMISSION or GUILD_RENAME_OPTIONS_DESCRIPTION_DISABLED (:531–559);
--   GuildRenameFrame:UpdateFromMode (:356–358; also after a name check, :265) → ContextButton:SetText(
--     GUILD_RENAME_COMMAND_DO_RENAME | GOODBYE) (:567–577);
--   TitleFlow:UpdateOptions (:496–529) → RenameOption / RefundOption:SetTextAndResize(
--     GUILD_RENAME_OPTIONS_RENAME_AVAILABLE | _RENAME_COOLDOWN | GUILD_RENAME_OPTIONS_REFUND). It runs from the
--     flow's OnUpdate (:492–494), so the client rewrites both buttons every frame while the title flow is shown and
--     the hook shows them again each time: two restricted matches per frame, only while this NPC window is open
--     (in-game check: cost and the button height SetTextAndResize measured from the English);
--   RenameFlow:UpdateFlowNameStatus (:439–447) and :ClearRenameStatus (:449–453) → RenameFlow.StatusText: a
--     GUILD_RENAME_ERROR_* word (guildErrorLookup, :22–32), a name-check error token's string (_G[token], :261, not
--     matched here), or " ".
-- Static labels (XML text=): RenameFlow.Description GUILD_RENAME_DESCRIPTION (xml:54), RenameFlow.CostLabel
--   GUILD_RENAME_COSTS_LABEL (xml:100), and the name box's placeholder RenameFlow.NameBox.Instructions
--   GUILD_RENAME_EDITBOX_INSTRUCTIONS (xml:71: a FontString shown / hidden by OnTextChanged, lua:376–379, never the
--   EditBox's own text).
-- Tooltips (SimpleTooltipRegionMixin:OnEnter → GameTooltip_SetTitle, lua:3–12; owners registered with
--   UI/HelpTooltip, each restricted): MoneyFrame GUILD_RENAME_GUILD_BANK_MONEY_TOOLTIP (xml:135), GuildIcon
--   GUILD_RENAME_COSTS_TOOLTIP (xml:147), ContextButton a GUILD_RENAME_ERROR_* word while disabled (lua:578–583).
-- Never touched: the window title (SetTitle(UnitName("npc")), :99, the NPC's name), the name EditBox, the money.
-- The two confirmation dialogs are StaticPopups (ADR-015 §5). Release on the frame's OnHide.
local _, WFJ = ...
local GuildRename = {}
WFJ.GuildRename = GuildRename

local SURFACE = "guildrename"
GuildRename.SURFACE = SURFACE
local Compat = WFJ.Compat

GuildRename.NEVER_TOUCH = { "GuildRenameFrame.TitleContainer.TitleText", "GuildRenameFrame.RenameFlow.NameBox" }

local F = "GuildRenameFrame"
local CANDIDATES = {
  frame = { F }, titleFlow = { F .. ".TitleFlow" }, renameFlow = { F .. ".RenameFlow" },
  optionsDescription = { F .. ".TitleFlow.Description" }, renameOption = { F .. ".TitleFlow.RenameOption" },
  refundOption = { F .. ".TitleFlow.RefundOption" }, description = { F .. ".RenameFlow.Description" },
  instructions = { F .. ".RenameFlow.NameBox.Instructions" }, status = { F .. ".RenameFlow.StatusText" },
  costLabel = { F .. ".RenameFlow.CostLabel" }, context = { F .. ".ContextButton" },
  money = { F .. ".MoneyFrame" }, guildIcon = { F .. ".GuildIcon" },
}

local ERROR_KEYS = { "GUILD_RENAME_ERROR_UNKNOWN", "GUILD_RENAME_ERROR_NAME_INVALID",
  "GUILD_RENAME_ERROR_NAME_ALREADY_EXISTS", "GUILD_RENAME_ERROR_NO_PERMISSION",
  "GUILD_RENAME_ERROR_NOT_ENOUGH_MONEY", "GUILD_RENAME_ERROR_TOO_MUCH_MONEY", "GUILD_RENAME_ERROR_IN_COOLDOWN",
  "GUILD_RENAME_ERROR_RESERVATION_EXPIRED" }
local STATUS = { only = ERROR_KEYS }
local OPTIONS = {
  { "renameOption", { only = { "GUILD_RENAME_OPTIONS_RENAME_AVAILABLE", "GUILD_RENAME_OPTIONS_RENAME_COOLDOWN" } } },
  { "refundOption", { only = { "GUILD_RENAME_OPTIONS_REFUND" } } },
}
local LABELS = {
  { "optionsDescription", { only = { "GUILD_RENAME_OPTIONS_DESCRIPTION", "GUILD_RENAME_ERROR_NO_PERMISSION",
    "GUILD_RENAME_OPTIONS_DESCRIPTION_DISABLED" } } },
  { "description", { only = { "GUILD_RENAME_DESCRIPTION" } } },
  { "instructions", { only = { "GUILD_RENAME_EDITBOX_INSTRUCTIONS" } } },
  { "costLabel", { only = { "GUILD_RENAME_COSTS_LABEL" } } },
  { "context", { only = { "GUILD_RENAME_COMMAND_DO_RENAME", "GOODBYE" } } },
}

local function get(key) return Compat.get(SURFACE, key) end

-- hooksecurefunc target (TitleFlow:UpdateOptions, every frame while the title flow is shown). → 0 | 1 | 2
function GuildRename.onOptions()
  local n = 0
  for _, o in ipairs(OPTIONS) do n = n + WFJ.Labels.show(SURFACE, o[1], get(o[1]), nil, o[2]) end
  return n
end

-- hooksecurefunc target (RenameFlow:UpdateFlowNameStatus / :ClearRenameStatus). → 1 | 0
function GuildRename.onStatus()
  local n = WFJ.Labels.show(SURFACE, "status", get("status"), nil, STATUS)
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- OnShow and hooksecurefunc target (frame:UpdateInteractionMode / :UpdateFromMode). → the number of words found.
function GuildRename.onUpdate()
  local n = 0
  for _, l in ipairs(LABELS) do n = n + WFJ.Labels.show(SURFACE, l[1], get(l[1]), nil, l[2]) end
  n = n + GuildRename.onOptions() + GuildRename.onStatus()
  return n
end

function GuildRename.release()
  return WFJ.Render.release(SURFACE)
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function GuildRename.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  local frame = get("frame")
  if hooked or type(frame) ~= "table" then return false end -- no GuildRenameFrame
  hooked = true
  for _, method in ipairs({ "UpdateInteractionMode", "UpdateFromMode" }) do
    if type(frame[method]) == "function" then hooksecurefunc(frame, method, GuildRename.onUpdate) end
  end
  if type(frame.HookScript) == "function" then
    frame:HookScript("OnShow", GuildRename.onUpdate)
    frame:HookScript("OnHide", GuildRename.release)
  end
  local titleFlow, renameFlow = get("titleFlow"), get("renameFlow")
  if type(titleFlow) == "table" and type(titleFlow.UpdateOptions) == "function" then
    hooksecurefunc(titleFlow, "UpdateOptions", GuildRename.onOptions)
  end
  if type(renameFlow) == "table" then
    for _, method in ipairs({ "UpdateFlowNameStatus", "ClearRenameStatus" }) do
      if type(renameFlow[method]) == "function" then hooksecurefunc(renameFlow, method, GuildRename.onStatus) end
    end
  end
  WFJ.HelpTooltip.register(get("money"), { only = { "GUILD_RENAME_GUILD_BANK_MONEY_TOOLTIP" } })
  WFJ.HelpTooltip.register(get("guildIcon"), { only = { "GUILD_RENAME_COSTS_TOOLTIP" } })
  WFJ.HelpTooltip.register(get("context"), STATUS)
  return true
end
