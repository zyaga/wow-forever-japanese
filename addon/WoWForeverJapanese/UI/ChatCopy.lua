-- UI/ChatCopy.lua: copying a chat line (docs/systems/chat-tools.md). An addon cannot write the clipboard, so a small
-- icon at the top right of the chat line under the mouse opens a tool window holding that line in a read-only
-- field with its text selected, for the player's own Ctrl+C. A line a player typed gives only what they typed; any
-- other line (system, loot, an emote) is given whole. Escape codes are taken out; a link keeps its label.
-- UI/ChatLines says which line the mouse is on, and never names one whose text the client keeps secret.
--   ChatCopy.textOf(line, text) → what the box will hold for that line
--   ChatCopy.show(text)          opens the box
local _, WFJ = ...
local Copy = {}
WFJ.ChatCopy = Copy

local Compat = WFJ.Compat
local W, Text = WFJ.OptionsWidgets, WFJ.OptionsText

local WIDTH, HEIGHT = 600, 220
local ICON = "Interface\\Buttons\\UI-GuildButton-PublicNote-Up" -- the note icon of the guild roster
local window, button

function Copy.textOf(line, text)
  return WFJ.ChatWords.plain(WFJ.ChatLines.typedPart(line, text) or text)
end

local function pick(key) return W.pick(Text.get(key)) end

function Copy.show(text)
  if not window then
    window = W.toolWindow("WFJChatCopyWindow", WIDTH, HEIGHT)
    window.field = W.scrollText(window, 16, -70, WIDTH - 32, HEIGHT - 110) -- read-only: it selects itself on focus
    window.foot = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    window.foot:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 16, 8)
    window.foot:SetTextColor(0.75, 0.75, 0.75)
  end
  window.title:SetText(pick("chat.copy.title"))
  WFJ.Font.set(window.title, WFJ.Font.PATH, 13, "")
  window.foot:SetText(pick("chat.copy.how"))
  WFJ.Font.set(window.foot, WFJ.Font.PATH, 11, "")
  window:Show()
  window.field:setText(type(text) == "string" and text or "")
  window.field.focusAll()
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
  -- the line's text is read out only when it is asked for
  button:SetScript("OnClick", function(self)
    if self.line and self.text then Copy.show(Copy.textOf(self.line, self.text)) end
  end)
  W.hoverLabel(button, function() return pick("chat.copy.tip") end)
  button:Hide()
  return button
end

-- UI/ChatLines' listener: the icon sits on the line under the mouse, and goes when there is none.
function Copy.follow(_, line, text)
  if not (line and WFJ.State.enabled and WFJ.Settings.get("chat.copy") == true) then
    if button and button:IsShown() then button:Hide() end
    return
  end
  local b = ensureButton()
  -- the icon sits inside its line's rectangle, so the mouse on the icon is still on the line: placed once per line
  if b.line == line and b.text == text and b:IsShown() then return end
  b.line, b.text = line, text
  b:ClearAllPoints()
  b:SetPoint("TOPRIGHT", line, "TOPRIGHT", 0, 0)
  b:Show()
end

function Copy.button() return button end

function Copy.init()
  WFJ.ChatLines.onLine(Copy.follow)
  return true
end
