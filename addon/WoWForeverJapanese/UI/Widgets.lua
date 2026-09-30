-- UI/Widgets.lua: the UI widgets' lines on Forever (surface "widgets", area "ui", ADR-042): the battleground
-- and world-event status lines ("Towers Controlled: 3", "Alliance flag captures", "Blackrock Eruption: 12 min
-- remaining") the top-centre, below-minimap and power-bar containers draw. Blizzard_UIWidgets loads at login
-- (blizzard_uiwidgets.toc, AllowLoad: game). Their text is the client's UiWidgetStringSource table with world-state
-- tokens the client fills with live numbers: the WidgetText family, NUMBERED rows (Core/UIStrings
-- index:matchNumbers): the live line's numbers are put back into the Japanese in the order the line has them.
-- Writer: UIWidgetContainerMixin:ProcessWidget(widgetID, widgetType) runs the widget frame's Setup with the
-- visualization info (blizzard_uiwidgetmanager.lua:472–540), called as self:ProcessWidget from the container's own
-- events (:46–53) and ProcessAllWidgets: post-hooked on each container instance, every container
-- UIWidgetManager:OnWidgetContainerRegistered is told about (:640–642, called from RegisterForWidgetSet, :284), and
-- those already registered (UIWidgetManager.registeredWidgetContainers). After it, the widget frame
-- (container.widgetFrames[widgetID], :483) and its children, three levels down, have every FontString shown,
-- restricted to the WidgetText family: a base, zone or player name on a widget is no row and stays English.
-- Not here: a widget's tooltip (EmbeddedItemTooltip, server text), the widgets inside the PvP scoreboard and the party
-- pose (the same frames, reached the same way when their containers register).
local _, WFJ = ...
local Widgets = {}
WFJ.Widgets = Widgets

local SURFACE = "widgets"
Widgets.SURFACE = SURFACE
local Compat = WFJ.Compat

Widgets.NEVER_TOUCH = {}

local CANDIDATES = { manager = { "UIWidgetManager" } }
local DEPTH = 3

local function get(key) return Compat.get(SURFACE, key) end

local textKey = WFJ.Labels.keyer("text.") -- a pooled widget FontString's record key (follows the widget)

-- Every FontString of `frame` and its children down to `depth`. → list
local function fontStrings(frame, depth, out)
  out = out or {}
  if type(frame) ~= "table" then return out end
  if type(frame.GetRegions) == "function" then
    for _, r in ipairs({ frame:GetRegions() }) do
      if type(r) == "table" and type(r.GetObjectType) == "function" and r:GetObjectType() == "FontString" then
        out[#out + 1] = r
      end
    end
  end
  if depth > 0 and type(frame.GetChildren) == "function" then
    for _, child in ipairs({ frame:GetChildren() }) do fontStrings(child, depth - 1, out) end
  end
  return out
end
Widgets.fontStrings = fontStrings

-- One widget frame's lines. → the number of lines shown in Japanese
function Widgets.showFrame(frame)
  local n, only = 0, WFJ.Labels.families("WidgetText")
  for _, fs in ipairs(fontStrings(frame, DEPTH)) do
    if type(fs.GetText) == "function" and type(fs:GetText()) == "string" and fs:GetText() ~= "" then
      n = n + WFJ.Labels.show(SURFACE, textKey(fs), fs, nil, only)
    end
  end
  return n
end

-- hooksecurefunc target on a container's ProcessWidget(widgetID, widgetType). Returns nothing.
function Widgets.onProcess(container, widgetID)
  local frames = type(container) == "table" and container.widgetFrames or nil
  local frame = type(frames) == "table" and frames[widgetID] or nil
  if frame then
    Widgets.showFrame(frame)
    WFJ.Render.updateBanner(SURFACE)
  end
end

local containers = setmetatable({}, { __mode = "k" })
-- → 1 when `container` was hooked now
function Widgets.hookContainer(container)
  if type(container) ~= "table" or containers[container] or type(container.ProcessWidget) ~= "function" then
    return 0
  end
  containers[container] = true
  hooksecurefunc(container, "ProcessWidget", Widgets.onProcess)
  for widgetID in pairs(type(container.widgetFrames) == "table" and container.widgetFrames or {}) do
    Widgets.onProcess(container, widgetID)
  end
  return 1
end

local hooked = false

-- Called by Main after Compat.init. → false without the widget manager
function Widgets.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  local manager = get("manager")
  if hooked or type(manager) ~= "table" then return false end
  hooked = true
  if type(manager.OnWidgetContainerRegistered) == "function" then
    hooksecurefunc(manager, "OnWidgetContainerRegistered", function(_, container) Widgets.hookContainer(container) end)
  end
  for container in pairs(type(manager.registeredWidgetContainers) == "table" and manager.registeredWidgetContainers
      or {}) do
    Widgets.hookContainer(container)
  end
  return true
end
