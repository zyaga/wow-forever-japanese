-- UI/ButtonText.lua: a Button seen as the FontString-like object SurfaceState works on (ADR-015):
-- GetText / SetText go to the button, GetFont / SetFont to its text region. One adapter per button (weak-keyed), so a
-- record keeps its widget identity across hooks.
-- A button's text region takes its Normal / Highlight / Disabled font object when its state changes [likely: the
-- client applies the XML <NormalFont>/<HighlightFont>/<DisabledFont> styles itself; in-game check in
-- docs/testing/strategy.md]; a font object carries the enUS face, which has no kana or kanji. While the bundled font
-- is applied the adapter puts it back after each state script (HookScript, installed once per button; `rehook`
-- re-installs the two scripts a pooled button's owner replaces with SetScript). No CreateFont / font-object edits:
-- if the in-game check still shows missing glyphs on a state, the fallback is addon-owned font objects (ADR-015).
local _, WFJ = ...
local ButtonText = {}
WFJ.ButtonText = ButtonText

local adapters = setmetatable({}, { __mode = "k" })
local STATE_SCRIPTS = { "OnEnter", "OnLeave", "OnMouseDown", "OnMouseUp", "OnEnable", "OnDisable", "OnShow" }
local REPLACED_SCRIPTS = { "OnEnter", "OnLeave" } -- the scripts MainMenuFrameMixin:AddButton sets on every reuse

local function reapply(a)
  local f = a.font
  if not f or f.path ~= WFJ.Font.PATH then return end
  local fs = a.button.GetFontString and a.button:GetFontString()
  if fs then fs:SetFont(f.path, f.size, f.flags) end
end

local function hook(a, scripts)
  local button = a.button
  if not button.HookScript then return end
  for _, script in ipairs(scripts) do
    button:HookScript(script, function() reapply(a) end)
  end
end

-- → the adapter for `button`, or nil when it is not a button with a text region.
function ButtonText.of(button)
  if type(button) ~= "table" or type(button.GetFontString) ~= "function" then return nil end
  local a = adapters[button]
  if a then return a end
  a = { button = button, font = nil }
  function a.GetText() return button:GetText() end
  function a.SetText(_, text) button:SetText(text) end
  function a.GetFont()
    local fs = button:GetFontString()
    if not fs then return nil end
    return fs:GetFont()
  end
  function a.SetFont(_, path, size, flags)
    local fs = button:GetFontString()
    if not fs then return false end
    a.font = { path = path, size = size, flags = flags }
    return fs:SetFont(path, size, flags)
  end
  adapters[button] = a
  hook(a, STATE_SCRIPTS)
  return a
end

function ButtonText.known(button)
  return adapters[button] ~= nil
end

-- A pooled button whose owner re-set OnEnter / OnLeave with SetScript (dropping our hooks): hook those two again.
function ButtonText.rehook(button)
  local a = adapters[button]
  if a then hook(a, REPLACED_SCRIPTS) end
  return a
end

-- The re-apply step, exposed for specs that drive a state change by hand.
ButtonText.reapply = reapply

-- Tabs (ADR-016): PanelTemplates_SelectTab disables the selected tab and then sets its disabled font object,
-- after the OnDisable re-apply has already run; DeselectTab / SetDisabledTabState / UpdateTabs (which EnableTab and
-- DisableTab call) swap font objects the same way [verified: classic_era Blizzard_SharedXML/Classic/
-- SharedUIPanelTemplates.lua:458–546]. After each, every adapter with the bundled font applied whose region no longer
-- carries it gets it back. A button no record has touched costs nothing.
local function reapplyAll()
  for _, a in pairs(adapters) do
    local f = a.font
    if f and f.path == WFJ.Font.PATH then
      local fs = a.button.GetFontString and a.button:GetFontString()
      if fs and (fs:GetFont()) ~= f.path then fs:SetFont(f.path, f.size, f.flags) end
    end
  end
end
ButtonText.reapplyAll = reapplyAll

local TAB_WRITERS = { "PanelTemplates_SelectTab", "PanelTemplates_DeselectTab", "PanelTemplates_SetDisabledTabState",
  "PanelTemplates_UpdateTabs" }
local tabsHooked = false

-- Called by Main after Compat.init.
function ButtonText.init()
  for _, name in ipairs(TAB_WRITERS) do WFJ.Compat.declare("buttontext", name, { name }) end
  if tabsHooked then return 0 end
  tabsHooked = true
  local n = 0
  for _, name in ipairs(TAB_WRITERS) do
    if type(WFJ.Compat.get("buttontext", name)) == "function" then
      hooksecurefunc(name, reapplyAll)
      n = n + 1
    end
  end
  return n
end
