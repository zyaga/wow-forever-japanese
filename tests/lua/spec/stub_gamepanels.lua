-- Shared pieces for the Blizzard_UIPanels_Game window specs (trade, loot, grouploot, taxi, tabard, petition,
-- guildregistrar, dressup, castingbar, maplegend): the load sequence, a titled panel, a Lua-built tooltip. Each
-- spec replays its own window from the Forever client source. Client writes go to `fs.text`.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local G = {}

-- H.UI_FILES + the module(s) under test.
function G.files(...)
  local files = {}
  for i, f in ipairs(H.UI_FILES) do files[i] = f end
  for _, f in ipairs({ ... }) do files[#files + 1] = f end
  return files
end

-- A fresh stub client with the addon loaded over `ui`. `patch(WFJ)` runs before the index is built: a spec uses it
-- for the Core/UIStrings ARGS / LABELS entries its surface needs.
function G.load(files, ui, patch)
  Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
  Stub.installTooltipAPI()
  local WFJ = H.loadChunks(files)
  if patch then patch(WFJ) end
  H.uiSetup(WFJ, ui)
  return WFJ
end

-- A mainline titled panel: TitleContainer.TitleText + SetTitle (blizzard_sharedxml/portraitframe.lua:3–13).
function G.titled(name, title)
  local frame = CreateFrame("Frame", name)
  frame.TitleContainer = { TitleText = Stub.fontString(title or "") }
  function frame.SetTitle(self, text) self.TitleContainer.TitleText.text = text end
  return frame
end

-- A tooltip the way an OnEnter builds it: SetOwner, SetText / AddLine …, Show.
function G.tooltip(owner, lines)
  local tt = _G.GameTooltip
  tt:SetOwner(owner, "ANCHOR_RIGHT")
  tt:SetText(lines[1])
  for i = 2, #lines do tt:AddLine(lines[i]) end
  tt:Show()
  return tt
end

function G.line(i) return _G["GameTooltipTextLeft" .. i]:GetText() end

function G.alt(WFJ, down)
  Stub.keys.alt = down
  WFJ.Modifier.refresh()
end

-- true when no surface holds a record for `widget` (a Button is recorded through its ButtonText adapter).
function G.unrecorded(WFJ, widget)
  local adapter = WFJ.ButtonText.known(widget) and WFJ.ButtonText.of(widget) or nil
  for _, bucket in pairs(WFJ.SurfaceState.surfaces()) do
    for _, rec in pairs(bucket) do
      if rec.fs == widget or (adapter and rec.fs == adapter) then return false end
    end
  end
  return true
end

function G.clear(names)
  H.uiTeardown()
  Stub.keys.alt = false
  for _, name in ipairs(names or {}) do _G[name] = nil end
end

return G
