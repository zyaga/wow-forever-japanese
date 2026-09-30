-- UI/LoadOnDemand.lua: runs a surface's setup once a load-on-demand Blizzard addon is present (ADR-016):
-- the talent frame (Blizzard_PlayerSpells), the trainer (Blizzard_TrainerUI) and the raid roster (Blizzard_RaidUI) are
-- created only when the client first needs them [verified: classic_era Blizzard_UIParent/Vanilla/UIParent.lua:209–250,
-- Shared/UIParent.lua:265, 296]. `when` runs the setup immediately if the addon is already loaded, otherwise on its
-- ADDON_LOADED, which Main forwards (Main owns the one event frame).
local _, WFJ = ...
local LoadOnDemand = {}
WFJ.LoadOnDemand = LoadOnDemand

local pending = {} -- addon name → { fn, … }
local isLoaded = function() return false end

-- Main injects the client's IsAddOnLoaded (C_AddOns.IsAddOnLoaded).
function LoadOnDemand.init(loadedFn)
  if type(loadedFn) == "function" then isLoaded = loadedFn end
end

-- → true when `fn` ran now, false when it waits for the addon's ADDON_LOADED.
function LoadOnDemand.when(addonName, fn)
  if isLoaded(addonName) then
    fn()
    return true
  end
  local list = pending[addonName] or {}
  list[#list + 1] = fn
  pending[addonName] = list
  return false
end

-- Main's ADDON_LOADED handler: runs (once) every setup waiting for `addonName`; a setup that errors does not stop the
-- others, and the first error is raised after they all ran. → the number run.
function LoadOnDemand.loaded(addonName)
  local list = pending[addonName]
  if not list then return 0 end
  pending[addonName] = nil
  local firstErr
  for _, fn in ipairs(list) do
    local ok, err = pcall(fn)
    if not ok and firstErr == nil then firstErr = err end
  end
  if firstErr ~= nil then error(firstErr, 0) end
  return #list
end
