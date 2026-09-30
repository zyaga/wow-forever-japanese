-- Shared by the Blizzard_FrameXML surface specs (zonetext, combatfeedback, readycheck, alerts, ghostframe,
-- stacksplit, coinpickup, loothistory): loads the UI files and one surface on a fresh stub.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local M = {}

-- → WFJ. `opts`: { args = { KEY = { [n] = kind } } → UIStrings.ARGS
-- entries this surface needs (Core/UIStrings carries them; a key already
-- there is left as it is), before = function() … end → builds the client frames before uiSetup }.
function M.load(surfaceFile, ui, opts)
  opts = opts or {}
  Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
  Stub.installTooltipAPI()
  Stub.installScrollUtil()
  local files = {}
  for i, f in ipairs(H.UI_FILES) do files[i] = f end
  files[#files + 1] = surfaceFile
  local WFJ = H.loadChunks(files)
  for key, kinds in pairs(opts.args or {}) do
    if WFJ.UIStrings.ARGS[key] == nil then WFJ.UIStrings.ARGS[key] = kinds end
  end
  if opts.before then opts.before() end
  H.uiSetup(WFJ, ui)
  return WFJ
end

function M.teardown(names)
  H.uiTeardown()
  Stub.keys.alt = false
  for _, n in ipairs(names or {}) do _G[n] = nil end
end

function M.alt(WFJ, down)
  Stub.keys.alt = down
  WFJ.Modifier.refresh()
end

-- true when no surface holds a record for `widget`
function M.unrecorded(WFJ, widget)
  for _, bucket in pairs(WFJ.SurfaceState.surfaces()) do
    for _, rec in pairs(bucket) do
      if rec.fs == widget then return false end
    end
  end
  return true
end

return M
