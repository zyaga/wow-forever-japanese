-- UI/FriendsTooltip.lua: the friends list's own tooltip on Forever (ADR-031): a Battle.net friend's
-- "Zone: <zone> / Realm: <realm>" line (BNET_FRIEND_TOOLTIP_ZONE_AND_REALM, _ZONE_AND_REGION), and the "(3 more
-- characters)" line under the game accounts (FRIENDS_TOOLTIP_TOO_MANY_CHARACTERS, written into
-- FriendsTooltipGameAccountMany by the same FriendsFrameTooltip_SetLine: camelot friendsframe.lua:2095–2096).
-- FriendsTooltip is not a GameTooltip. FriendsListButtonMixin:OnEnter writes each line through
-- FriendsFrameTooltip_SetLine (SetText, then tooltip.height += line:GetHeight() and tooltip.maxWidth = max(…,
-- GetStringWidth + left)) and ends with SetHeight(height + margin), SetWidth(min(MAX, maxWidth + margin)), Show()
-- [verified: camelot friendsframe.lua:1879–1902, 1955–1967, 2098–2102; FriendsTooltip friendsframe.xml:829]. So the
-- lines are rewritten from a post-hook on the tooltip's Show, and the refit moves the tooltip's height and width by the
-- line's change the same way the client sized it. The zone and the realm are names, kept as written (`text`).
local _, WFJ = ...
local FriendsTooltip = {}
WFJ.FriendsTooltip = FriendsTooltip

local SURFACE = "friends.tooltip"
FriendsTooltip.SURFACE = SURFACE
FriendsTooltip.KEYS = { "BNET_FRIEND_TOOLTIP_ZONE_AND_REALM", "BNET_FRIEND_TOOLTIP_ZONE_AND_REGION" }
FriendsTooltip.MANY_KEYS = { "FRIENDS_TOOLTIP_TOO_MANY_CHARACTERS" }
local MAX_GAME_ACCOUNTS = 5 -- FRIENDS_TOOLTIP_MAX_GAME_ACCOUNTS (camelot friendsframe.lua), read from the client

local Compat = WFJ.Compat

local function get(key) return Compat.get(SURFACE, key) end

local heights = setmetatable({}, { __mode = "k" }) -- line → the height the tooltip was sized with

local function refitFor(line)
  return function()
    local tip = get("tooltip")
    if type(tip) ~= "table" or type(line.GetHeight) ~= "function" then return end
    local h, old = line:GetHeight(), heights[line]
    heights[line] = h
    local margin = get("margin")
    margin = type(margin) == "number" and margin or 0
    if type(old) == "number" and type(h) == "number" and h ~= old and type(tip.height) == "number" then
      tip.height = tip.height + (h - old)
      if type(tip.SetHeight) == "function" then tip:SetHeight(tip.height + margin) end
    end
    local maxWidth = get("maxWidth")
    if type(line.GetStringWidth) == "function" and type(tip.GetWidth) == "function" and type(tip.SetWidth) == "function"
        and type(maxWidth) == "number" then
      local want = math.min(maxWidth, line:GetStringWidth() + margin * 2)
      if want > tip:GetWidth() then tip:SetWidth(want) end
    end
  end
end

-- One line: the height the client just sized the tooltip with (unless the line still shows our Japanese), then the
-- line through Labels.show with its refit. → 1 | 0
local function showLine(line, recKey, keys)
  if type(line) ~= "table" or type(line.GetText) ~= "function" then return 0 end
  -- a line the client hid for this friend keeps its old text: never ours to write
  if type(line.IsShown) == "function" and not line:IsShown() then
    WFJ.SurfaceState.drop(SURFACE, recKey)
    return 0
  end
  local rec = WFJ.SurfaceState.get(SURFACE, recKey)
  if not (rec and rec.applied ~= nil and rec.applied == line:GetText()) then
    heights[line] = type(line.GetHeight) == "function" and line:GetHeight() or nil
  end
  return WFJ.Labels.show(SURFACE, recKey, line, refitFor(line), { only = keys })
end

-- The Show post-hook: every game-account info line that holds one of KEYS, and the "more characters" line.
-- → the number shown
function FriendsTooltip.onShow()
  local n = 0
  local count = get("maxAccounts")
  for i = 1, type(count) == "number" and count or MAX_GAME_ACCOUNTS do
    n = n + showLine(Compat.resolve("FriendsTooltipGameAccount" .. i .. "Info"), "info" .. i, FriendsTooltip.KEYS)
  end
  n = n + showLine(Compat.resolve("FriendsTooltipGameAccountMany"), "many", FriendsTooltip.MANY_KEYS)
  WFJ.Render.updateBanner(SURFACE)
  return n
end

local hooked = false

-- Called by Main after Compat.init. → true when FriendsTooltip exists (the camelot / mainline friends frame)
function FriendsTooltip.init()
  Compat.declare(SURFACE, "tooltip", { "FriendsTooltip" })
  Compat.declare(SURFACE, "margin", { "FRIENDS_TOOLTIP_MARGIN_WIDTH" })
  Compat.declare(SURFACE, "maxWidth", { "FRIENDS_TOOLTIP_MAX_WIDTH" })
  Compat.declare(SURFACE, "maxAccounts", { "FRIENDS_TOOLTIP_MAX_GAME_ACCOUNTS" })
  local tip = get("tooltip")
  if type(tip) ~= "table" or type(tip.Show) ~= "function" or hooked then return hooked end
  hooked = true
  hooksecurefunc(tip, "Show", FriendsTooltip.onShow)
  if type(tip.HookScript) == "function" then
    tip:HookScript("OnHide", function() WFJ.Render.release(SURFACE) end)
  end
  return true
end
