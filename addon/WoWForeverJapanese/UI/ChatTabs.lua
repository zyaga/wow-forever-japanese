-- UI/ChatTabs.lua: the chat frame's own hover texts on Forever (surface "chattabs", area "ui", ADR-016):
-- the help tooltips of a chat window's tab and of the chat channels button, and the edit box's header. Chat
-- lines are not this module's (not a window's text); the edit box's own text is never touched.
--   A tab's OnEnter (blizzard_chatframebase/mainline/floatingchatframe.xml:357–372) builds
--     GameTooltip_SetTitle(format(CHAT_TAB_NAME, <the tab's text>)) ("%s Tab" around the window's name, which is
--     kept as written) and CHAT_TAB_RIGHT_CLICK. Tabs are ChatFrame<N>Tab; temporary whisper windows add more
--     (FCF_OpenTemporaryWindow, mainline/floatingchatframe.lua:976), so the tabs are registered again after it.
--   ChatFrameChannelButton (blizzard_chatframe/mainline/floatingchatframevoicechat.xml:4) shows
--     MicroButtonTooltipText(CHAT_CHANNELS, "TOGGLECHATTAB") through PropertyBindingMixin:SetTooltip →
--     GameTooltip_SetTitle (mainline/channelframebuttonmixin.lua:27–29; blizzard_sharedxml/
--     propertybindingmixin.lua:126–135): the word with its key binding, the `binding` label form.
--   The docked-tabs overflow list: FCFDockOverflowList_Update(list, dock) (global, mainline/floatingchatframe.lua:
--     2766–2770; floatingchatframe.xml:702) writes list.numTabs with CHAT_WINDOWS_COUNT ("%d Chat Windows"). The
--     list's buttons are chat windows' names: never touched.
--   the edit box header ("Say:", "Tell <name>:"). ChatFrameEditBoxMixin:UpdateHeader writes it:
--     header:SetText(_G["CHAT_"..type.."_SEND"]) or SetFormattedText(CHAT_WHISPER_SEND, target), then sizes it
--     (width 0, capped at half the box with the ": " suffix shown) and insets the typed text by its width
--     (blizzard_chatframebase/shared/chatframeeditbox.lua:613–711; mainline/chatframeeditboxoverrides.lua:5–18 for the
--     language header). A post-hook on each edit box's UpdateHeader shows the header in Japanese and sizes it again
--     the client's way, so the typed text starts after the Japanese; Alt re-sizes it for the English. A whisper
--     target's name is kept (a `text` argument). ChatFrame<N>EditBox; temporary whisper windows add more.
-- The rest is help tooltips: owners are registered with WFJ.HelpTooltip, each restricted to its own keys.
-- Never touched: a tab's own text (a chat window's name is the player's: "General", "Combat Log" or a rename).
local _, WFJ = ...
local ChatTabs = {}
WFJ.ChatTabs = ChatTabs

local SURFACE = "chattabs"
ChatTabs.SURFACE = SURFACE
local Compat = WFJ.Compat

ChatTabs.NEVER_TOUCH = {}
local MAX_TABS = 40 -- ten docked windows plus temporary whisper windows; the walk stops at the first missing frame
for i = 1, 10 do ChatTabs.NEVER_TOUCH[i] = "ChatFrame" .. i .. "Tab" end

local CANDIDATES = {
  firstTab = { "ChatFrame1Tab" }, channelButton = { "ChatFrameChannelButton" },
  openTemporary = { "FCF_OpenTemporaryWindow" }, overflowUpdate = { "FCFDockOverflowList_Update" },
}

local TAB = { only = { "CHAT_TAB_NAME", "CHAT_TAB_RIGHT_CLICK" } }
local CHANNELS = { only = { "CHAT_CHANNELS" } }
local COUNT = { only = { "CHAT_WINDOWS_COUNT" } }
local HEADER = { only = { "CHAT_SAY_SEND", "CHAT_YELL_SEND", "CHAT_PARTY_SEND", "CHAT_RAID_SEND",
  "CHAT_RAID_WARNING_SEND", "CHAT_INSTANCE_CHAT_SEND", "CHAT_GUILD_SEND", "CHAT_OFFICER_SEND", "CHAT_WHISPER_SEND",
  "CHAT_BN_WHISPER_SEND" } }
ChatTabs.HEADER_KEYS = HEADER.only
local HEADER_PAD, HEADER_RIGHT = 15, 13 -- the client's insets (chatframeeditbox.lua:710)

local function get(key) return Compat.get(SURFACE, key) end

-- hooksecurefunc target (FCF_OpenTemporaryWindow), and the first pass. → the number of tabs registered.
function ChatTabs.registerTabs()
  local n = 0
  for i = 1, MAX_TABS do
    local tab = Compat.resolve("ChatFrame" .. i .. "Tab")
    if type(tab) ~= "table" then break end
    WFJ.HelpTooltip.register(tab, TAB)
    WFJ.Labels.forbid(tab) -- the tab's text is a window's name
    n = n + 1
  end
  return n
end

-- The client's header sizing, again (chatframeeditbox.lua:640, 696–710): the typed text starts after the header.
local function fitHeader(box)
  local name = box:GetName()
  local header, suffix = Compat.resolve(name .. "Header"), Compat.resolve(name .. "HeaderSuffix")
  if type(header) ~= "table" or type(box.SetTextInsets) ~= "function" then return end
  header:SetWidth(0)
  local width = (header:GetRight() or 0) - (header:GetLeft() or 0)
  local half = ((box:GetRight() or 0) - (box:GetLeft() or 0)) / 2
  local capped = width > half
  if capped then header:SetWidth(half) end
  if type(suffix) == "table" then suffix:SetShown(capped) end
  local lang = box.languageHeader
  local langWidth = (type(lang) == "table" and lang:IsShown()) and lang:GetWidth() or 0
  local suffixWidth = (capped and type(suffix) == "table") and suffix:GetWidth() or 0
  box:SetTextInsets(HEADER_PAD + header:GetWidth() + suffixWidth + langWidth, HEADER_RIGHT, 0, 0)
end

local refits = setmetatable({}, { __mode = "k" })

-- hooksecurefunc target (<edit box>:UpdateHeader). → 1 | 0
function ChatTabs.onHeader(box)
  if type(box) ~= "table" or type(box.GetName) ~= "function" then return 0 end
  local header = Compat.resolve(box:GetName() .. "Header")
  if type(header) ~= "table" then return 0 end
  local refit = refits[box]
  if not refit then
    refit = function() fitHeader(box) end
    refits[box] = refit
  end
  local n = WFJ.Labels.show(SURFACE, "header." .. box:GetName(), header, refit, HEADER)
  if n > 0 then fitHeader(box) end
  return n
end

local headerHooked = setmetatable({}, { __mode = "k" })

-- Each chat window's edit box, once. → the number hooked now
function ChatTabs.registerEditBoxes()
  local n = 0
  for i = 1, MAX_TABS do
    local box = Compat.resolve("ChatFrame" .. i .. "EditBox")
    if type(box) ~= "table" then break end
    if not headerHooked[box] and type(box.UpdateHeader) == "function" then
      headerHooked[box] = true
      hooksecurefunc(box, "UpdateHeader", ChatTabs.onHeader)
      n = n + 1
    end
  end
  return n
end

-- hooksecurefunc target (FCFDockOverflowList_Update). → 1 | 0
function ChatTabs.onOverflow(list)
  local count = type(list) == "table" and list.numTabs or nil
  if type(count) ~= "table" then return 0 end
  return WFJ.Labels.show(SURFACE, "overflowCount", count, nil, COUNT)
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function ChatTabs.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  if hooked or type(get("firstTab")) ~= "table" then return false end
  hooked = true
  ChatTabs.registerTabs()
  ChatTabs.registerEditBoxes()
  if type(get("openTemporary")) == "function" then
    hooksecurefunc("FCF_OpenTemporaryWindow", function() ChatTabs.registerTabs(); ChatTabs.registerEditBoxes() end)
  end
  if type(get("overflowUpdate")) == "function" then
    hooksecurefunc("FCFDockOverflowList_Update", ChatTabs.onOverflow)
  end
  local button = get("channelButton")
  if type(button) == "table" then WFJ.HelpTooltip.register(button, CHANNELS) end
  return true
end
