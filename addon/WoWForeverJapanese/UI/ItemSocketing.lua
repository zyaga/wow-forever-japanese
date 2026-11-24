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
-- The socketed item's name (surface "itemsocketing", area "items"): line 1 of ItemSocketingDescription, a GameTooltip
--   in the window's scroll child (xml:391–417) that ItemSocketingFrame_Update fills with SetSocketedItem (lua:56–67).
--   The scroll frame's range callback fills it again (:35–37, 69–71), so a refit of the tooltip after a write could
--   change the range and start that callback. The name is written only from a post-hook on the global
--   ItemSocketingFrame_Update (called by name from the window's OnEvent and from the bootstrap, :44–46;
--   blizzard_itemsocketingui_bootstrap.lua:9), never from SetSocketedItem or the range callback, and with no refit:
--   no write of this addon lays the tooltip out, so none can start the callback, and a fill from the callback is the
--   client's English alone. While names are on the name shows its Japanese (UI/NameLabels). [unverified] whether a
--   GameTooltip lays itself out again when a line's text changes with no Show; if it does, the range callback puts
--   the English back once and stops there (an in-game look at a socketed item settles it).
-- Never touched: the rest of ItemSocketingDescription (UI/Tooltip's), gem names. The confirmation dialogs are
-- StaticPopups (ADR-015 §5).
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
  itemName = { "ItemSocketingDescriptionTextLeft1" }, update = { "ItemSocketingFrame_Update" },
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

-- hooksecurefunc target (ItemSocketingFrame_Update): the socketed item's name, with no refit. → 1 | 0
function ItemSocketing.showName()
  local n = WFJ.NameLabels.show(SURFACE, "itemName", get("itemName"), "items")
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
  if type(get("update")) == "function" then hooksecurefunc("ItemSocketingFrame_Update", ItemSocketing.showName) end
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
