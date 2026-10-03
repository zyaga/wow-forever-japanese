-- UI/ChatInput.lua: the chat input box, its channel header and the header's ": " suffix always in the bundled
-- Japanese face. The client's chat font has no kana or kanji, so Japanese the player types or pastes would show as
-- nothing. One face throughout, whatever the box holds and whether the addon is on or off, means the client's own
-- header layout (chatframeeditbox.lua:640, 696–710) always measures the face that is shown. Each chat frame's edit
-- box (frame.editBox, floatingchatframe.xml:555) is dressed once and again whenever it shows. Nothing is translated
-- here.
local _, WFJ = ...
local ChatInput = {}
WFJ.ChatInput = ChatInput

local SURFACE = "chatsystem.input"
local Compat = WFJ.Compat

ChatInput.NEVER_TOUCH = {}

local CANDIDATES = { frames = { "CHAT_FRAMES" }, openTemporary = { "FCF_OpenTemporaryWindow" } }
local hooked = setmetatable({}, { __mode = "k" })

-- The bundled face at the widget's own size and flags. → true when the widget wears it
local function dressOne(widget)
  if type(widget) ~= "table" or type(widget.GetFont) ~= "function" then return false end
  local path, size, flags = widget:GetFont()
  if path == WFJ.Font.PATH then return true end
  return widget:SetFont(WFJ.Font.PATH, size or WFJ.Font.DEFAULT_SIZE, flags or "") ~= false
end

-- The box, its header and the header's suffix. → true when the box wears the bundled face
function ChatInput.dress(box)
  local name = type(box.GetName) == "function" and box:GetName() or nil
  if name then
    dressOne(Compat.resolve(name .. "Header"))
    dressOne(Compat.resolve(name .. "HeaderSuffix"))
  end
  return dressOne(box)
end

local function hookBox(box)
  if type(box) ~= "table" or hooked[box] or type(box.HookScript) ~= "function" then return 0 end
  hooked[box] = true
  ChatInput.dress(box)
  box:HookScript("OnShow", ChatInput.dress)
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
