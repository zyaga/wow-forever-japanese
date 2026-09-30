-- UI/TooltipLines.lua: the lines of a Blizzard tooltip that is not GameTooltip (area "ui", ADR-016).
-- UI/HelpTooltip.lua serves GameTooltip and decides by the tooltip's owner. The Options window and quick keybind
-- mode have tooltips of their own, each with one writer family and no items or spells:
--   SettingsTooltip (blizzard_settings_shared/blizzard_settingspanel.xml:115): every option row, checkbox, slider,
--     dropdown and key-binding button builds it in DefaultTooltipMixin:OnEnter and then calls SettingsTooltip:Show()
--     (blizzard_settingcontrols.lua:26–38);
--   QuickKeybindTooltip (blizzard_quickkeybind/quickkeybind.xml:18): QuickKeybindButtonSetTooltip adds its lines and
--     calls QuickKeybindTooltip:Show() (quickkeybind.lua:51–72).
-- TooltipLines.follow post-hooks that tooltip's Show (hooksecurefunc on the instance, once) and shows every left
-- line through Labels.show with the surface's `only` set, then lays the tooltip out again once if a line changed
-- (our own Show is ignored while refitting). Records are released on the tooltip's OnHide, as HelpTooltip does.
-- A line built by concatenation ("<option>: <tooltip>", "<binding> (<key>)") matches nothing and stays English.
local _, WFJ = ...
local TooltipLines = {}
WFJ.TooltipLines = TooltipLines

local Compat = WFJ.Compat
local followed = setmetatable({}, { __mode = "k" }) -- tooltip → { surface, opts, busy, recorded, refit }

-- → the number of dictionary lines on `tt` (0 when it is not followed or a walk is running).
function TooltipLines.walk(tt)
  local f = followed[tt]
  if not f or f.busy or type(tt.GetName) ~= "function" or type(tt.NumLines) ~= "function" then return 0 end
  if f.allow and not f.allow() then
    if f.recorded > 0 then
      f.recorded = 0
      WFJ.Render.forget(f.surface) -- the client rewrote the lines: never put our old English back
    end
    return 0
  end
  local name, lines = tt:GetName(), tt:NumLines() or 0
  if type(name) ~= "string" then return 0 end
  local n, changed = 0, false
  f.busy = true -- per-record refits wait for the single refit at the end of this pass
  local ok, err = pcall(function()
    for i = 1, lines do
      local fs = Compat.resolve(name .. "TextLeft" .. i)
      local recKey = "L" .. i
      if type(fs) == "table" and type(fs.GetText) == "function" and (fs:GetText() or "") ~= "" then
        local before = fs:GetText()
        n = n + WFJ.Labels.show(f.surface, recKey, fs, f.refit, f.opts)
        if fs:GetText() ~= before then changed = true end
      else
        WFJ.SurfaceState.drop(f.surface, recKey)
      end
    end
    for i = lines + 1, f.recorded do WFJ.SurfaceState.drop(f.surface, "L" .. i) end
  end)
  f.busy = false -- cleared even when a write errors, so the tooltip never stays switched off
  if not ok then error(err, 0) end
  f.recorded = lines
  if changed then f.refit() end
  return n
end

-- Follows `tt` on `surface`. `opts`: Labels.show's ({ only = set }, required). `allow` (optional): a function → false
-- when the tooltip's current content is not ours to touch (an addon's options page). → true when the hooks went in.
function TooltipLines.follow(surface, tt, opts, allow)
  if type(tt) ~= "table" or followed[tt] or type(opts) ~= "table" or type(opts.only) ~= "table" then return false end
  if type(tt.Show) ~= "function" or type(tt.HookScript) ~= "function" then return false end
  local f = { surface = surface, opts = opts, allow = allow, busy = false, recorded = 0 }
  -- A tooltip's lines never take word cards (UI/Readings, loaded before this file)
  if WFJ.ReadingView then WFJ.ReadingView.tooltipSurface(surface) end
  function f.refit()
    if f.busy then return end
    f.busy = true
    local ok, err = pcall(tt.Show, tt)
    f.busy = false
    if not ok then error(err, 0) end
  end
  followed[tt] = f
  hooksecurefunc(tt, "Show", function(self) TooltipLines.walk(self) end)
  tt:HookScript("OnHide", function()
    f.recorded = 0
    WFJ.Render.release(surface)
  end)
  return true
end
