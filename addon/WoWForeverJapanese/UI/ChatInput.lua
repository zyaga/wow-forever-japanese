-- UI/ChatInput.lua: the chat input box in the bundled Japanese face while it holds Japanese. The client's chat font
-- has no kana or kanji, so Japanese the player types (or pastes) shows as nothing. Each chat frame's edit box
-- (frame.editBox, floatingchatframe.xml:555) gets an OnTextChanged hook: text with a CJK character wears the bundled
-- face at the box's own size, any other text gets back the font the box had before. Nothing is translated here.
local _, WFJ = ...
local ChatInput = {}
WFJ.ChatInput = ChatInput

local SURFACE = "chat.input"
local Compat = WFJ.Compat

ChatInput.NEVER_TOUCH = {}

local CANDIDATES = { frames = { "CHAT_FRAMES" }, openTemporary = { "FCF_OpenTemporaryWindow" } }
local hooked = setmetatable({}, { __mode = "k" })

-- Lead bytes of U+3000..U+9FFF (ideographic punctuation, kana, kanji) and of the full-width forms (U+FF00..).
local function hasJapanese(text)
  return type(text) == "string" and (text:find("[\227-\233]") or text:find("\239[\188-\191]")) ~= nil
end
ChatInput.hasJapanese = hasJapanese

-- OnTextChanged: the face follows what the box holds. → true when the box wears the bundled face
function ChatInput.follow(box)
  local fontObject = type(box.GetFontObject) == "function" and box:GetFontObject() or nil
  if hasJapanese(box:GetText()) then
    if not WFJ.Font.dressed(box) then WFJ.Font.bundle(box, fontObject) end
  elseif WFJ.Font.dressed(box) then
    -- the font the box had before, as remembered: in game the box kept the bundled face through its font object
    WFJ.Font.restore(box)
  end
  return WFJ.Font.dressed(box)
end

local function hookBox(box)
  if type(box) ~= "table" or hooked[box] or type(box.HookScript) ~= "function" then return 0 end
  hooked[box] = true
  box:HookScript("OnTextChanged", ChatInput.follow)
  return 1
end

-- → the number of edit boxes newly hooked
function ChatInput.hookAll()
  local n = 0
  local names = Compat.get(SURFACE, "frames")
  for _, name in ipairs(type(names) == "table" and names or {}) do
    local frame = Compat.resolve(name)
    if type(frame) == "table" then n = n + hookBox(frame.editBox or Compat.resolve(name .. "EditBox")) end
  end
  return n
end

function ChatInput.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  if type(Compat.get(SURFACE, "frames")) ~= "table" then return false end
  ChatInput.hookAll()
  if type(Compat.get(SURFACE, "openTemporary")) == "function" then
    hooksecurefunc("FCF_OpenTemporaryWindow", ChatInput.hookAll) -- a whisper window made later
  end
  return true
end
