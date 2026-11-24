-- UI/ChatCopy.lua: copying a chat line (docs/systems/chat-tools.md). An addon cannot write the clipboard, so a small
-- icon at the top right of the chat line under the mouse opens a tool window holding that line with its text
-- selected, for the player's own Ctrl+C. A line a player typed gives only what they typed; any other line (system,
-- loot, an emote) is given whole. Escape codes are taken out; a link keeps its label. UI/ChatCards says which line
-- the mouse is on, and never names a line whose text the client keeps secret.
--   ChatCopy.textOf(line, text) → what the box will hold for that line
--   ChatCopy.show(text)          opens the box
local _, WFJ = ...
local Copy = {}
WFJ.ChatCopy = Copy

local Compat = WFJ.Compat
local W, Text = WFJ.OptionsWidgets, WFJ.OptionsText

local WIDTH, HEIGHT = 600, 220
local ICON = "Interface\\Buttons\\UI-GuildButton-PublicNote-Up" -- the note icon of the guild roster
local window, box, button, tip

function Copy.textOf(line, text)
  local typed = WFJ.ChatCards.typedPart(line, text)
  return WFJ.ChatWords.plain(typed or text)
end

local function pick(key) return W.pick(Text.get(key)) end

function Copy.show(text)
  if not window then
    window = W.toolWindow("WFJChatCopyWindow", WIDTH, HEIGHT)
    box = CreateFrame("EditBox", nil, window)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFont(WFJ.Font.PATH, 14, "")
    box:SetPoint("TOPLEFT", window.Inset, "TOPLEFT", 12, -12)
    box:SetPoint("BOTTOMRIGHT", window.Inset, "BOTTOMRIGHT", -12, 12)
    box:SetScript("OnEscapePressed", function() window:Hide() end)
    window.foot = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    window.foot:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 16, 8)
    window.foot:SetTextColor(0.75, 0.75, 0.75)
  end
  window.title:SetText(pick("chat.copy.title"))
  WFJ.Font.set(window.title, WFJ.Font.PATH, 13, "")
  window.foot:SetText(pick("chat.copy.how"))
  WFJ.Font.set(window.foot, WFJ.Font.PATH, 11, "")
  window:Show()
  box:SetText(type(text) == "string" and text or "")
  box:SetFocus()
  box:HighlightText()
  return window
end

local function ensureButton()
  if button then return button end
  button = CreateFrame("Button", nil, Compat.resolve("UIParent"))
  button:SetFrameStrata("HIGH")
  button:SetSize(14, 14)
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints(button)
  icon:SetTexture(ICON)
  button:SetHighlightTexture(ICON, "ADD")
  button:SetScript("OnClick", function(self)
    if self.text then Copy.show(self.text) end
  end)
  -- a label of the addon's own: the client's tooltip font has no Japanese
  tip = CreateFrame("Frame", nil, button, "TooltipBackdropTemplate")
  tip:SetFrameStrata("TOOLTIP")
  WFJ.ReadingView.solid(tip)
  tip.text = tip:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  tip.text:SetPoint("CENTER", tip, "CENTER", 0, 0)
  tip:SetPoint("BOTTOMLEFT", button, "TOPRIGHT", 2, 2)
  tip:Hide()
  button:SetScript("OnEnter", function()
    tip.text:SetText(pick("chat.copy.tip"))
    WFJ.Font.set(tip.text, WFJ.Font.PATH, 12, "")
    tip:SetSize(tip.text:GetStringWidth() + 18, tip.text:GetStringHeight() + 12)
    tip:Show()
  end)
  button:SetScript("OnLeave", function() tip:Hide() end)
  button:SetScript("OnHide", function() tip:Hide() end)
  button:Hide()
  return button
end

-- UI/ChatCards' listener: the icon sits on the readable line under the mouse, and goes when there is none.
function Copy.follow(line, text)
  local on = line ~= nil and WFJ.State.enabled and WFJ.Settings.get("chat.copy") == true
  if not on then
    -- the icon sits inside its line's rectangle, so the mouse on the icon is still on the line
    if button then button:Hide() end
    return
  end
  local b = ensureButton()
  b.text = Copy.textOf(line, text)
  b:ClearAllPoints()
  b:SetPoint("TOPRIGHT", line, "TOPRIGHT", 0, 0)
  b:Show()
end

function Copy.button() return button end

function Copy.init()
  WFJ.ChatCards.onLine(Copy.follow)
  return true
end

WFJ.State.on("chat", function() if button then button:Hide() end end)
