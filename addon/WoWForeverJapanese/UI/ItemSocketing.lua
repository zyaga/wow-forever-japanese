-- UI/ItemSocketing.lua: the item socketing window on Forever (surfaces "itemsocketing" and "itemsocketing.static",
-- area "ui", ADR-016 / ADR-029). Load-on-demand Blizzard_ItemSocketingUI; GameEvent.HandleSocketInfoUpdate
-- (blizzard_game/mainline/eventimplementation.lua:507–509) calls ShowItemSocketingFrame, which loads the addon
-- (blizzard_itemsocketingui_bootstrap.lua:3–12). Set up through WFJ.LoadOnDemand.when.
-- Static labels (XML text=; each restricted to its own key), on "itemsocketing.static":
--   an unnamed FontString of ItemSocketingFrame ITEM_SOCKETING, the window title; the frame inherits
--   ButtonFrameTemplate but never calls SetTitle (blizzard_itemsocketingui.xml:143–151);
--   ItemSocketingFrame.SocketingContainer.ApplySocketsButton APPLY (xml:128, 419).
-- Dynamic, on "itemsocketing" (released on the frame's OnHide):
--   SocketingContainer:Update (GenericItemSocketingFrameMixin:Update, blizzard_itemsocketingui.lua:222–338; the mixin
--   is copied onto the frame and ItemSocketingFrame_Update calls it by method lookup, :56–58) writes each socket's
--   BracketFrame.ColorText with _G[strupper(gemColor) .. "_GEM"] in colour-blind mode (:238–297): restricted to the
--   colour words RED_GEM / YELLOW_GEM / BLUE_GEM / META_GEM / PRISMATIC_GEM. Sockets are keyed by widget.
-- Never touched: ItemSocketingDescription (a GameTooltip showing the item, xml:406; UI/Tooltip's), gem and item
-- names. The confirmation dialogs are StaticPopups (ADR-015 §5).
local _, WFJ = ...
local ItemSocketing = {}
WFJ.ItemSocketing = ItemSocketing

local SURFACE = "itemsocketing"
ItemSocketing.SURFACE = SURFACE
local STATIC = SURFACE .. ".static"
local Compat = WFJ.Compat
local ADDON = "Blizzard_ItemSocketingUI"

ItemSocketing.NEVER_TOUCH = { "ItemSocketingDescriptionTextLeft1" }

local CANDIDATES = {
  frame = { "ItemSocketingFrame" }, container = { "ItemSocketingFrame.SocketingContainer" },
  apply = { "ItemSocketingFrame.SocketingContainer.ApplySocketsButton" },
}
local TITLE = { only = { "ITEM_SOCKETING" } }
local APPLY = { only = { "APPLY" } }
local COLOR = { only = { "RED_GEM", "YELLOW_GEM", "BLUE_GEM", "META_GEM", "PRISMATIC_GEM" } }

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
end

-- The labels the client writes once at load. → the number of dictionary words found.
function ItemSocketing.showStatic()
  return WFJ.Labels.showAll(STATIC, {
    { "title", WFJ.Labels.region(get("frame"), "ITEM_SOCKETING"), TITLE },
    { "apply", get("apply"), APPLY },
  })
end

local socketKey = WFJ.Labels.keyer("socket.") -- a socket button's record key (records follow the widget)

-- hooksecurefunc target (SocketingContainer:Update). → the number of dictionary words found.
function ItemSocketing.onUpdate()
  local container = get("container")
  local sockets = type(container) == "table" and container.SocketFrames or nil
  local n = 0
  if type(sockets) == "table" then
    for _, socket in ipairs(sockets) do
      local bracket = type(socket) == "table" and socket.BracketFrame or nil
      local text = type(bracket) == "table" and bracket.ColorText or nil
      if type(text) == "table" then n = n + WFJ.Labels.show(SURFACE, socketKey(text), text, nil, COLOR) end
    end
  end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

function ItemSocketing.release()
  return WFJ.Render.release(SURFACE)
end

local hooked = false

-- The Blizzard_ItemSocketingUI part: runs once that addon is loaded (now, or on its ADDON_LOADED). → true when hooked
function ItemSocketing.setup()
  declare() -- its frames exist only now: forget what Compat memoized before
  local frame = get("frame")
  if type(frame) ~= "table" then return false end
  WFJ.Labels.forbidNames(ItemSocketing.NEVER_TOUCH)
  ItemSocketing.showStatic()
  if hooked then return false end
  hooked = true
  local container = get("container")
  if type(container) == "table" and type(container.Update) == "function" then
    hooksecurefunc(container, "Update", ItemSocketing.onUpdate)
  end
  if type(frame.HookScript) == "function" then
    frame:HookScript("OnShow", ItemSocketing.showStatic)
    frame:HookScript("OnHide", ItemSocketing.release)
  end
  ItemSocketing.onUpdate()
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init. → true when the window
-- was set up now; false while it waits for the addon.
function ItemSocketing.init()
  declare()
  local result = false
  WFJ.LoadOnDemand.when(ADDON, function() result = ItemSocketing.setup() end)
  return result
end
