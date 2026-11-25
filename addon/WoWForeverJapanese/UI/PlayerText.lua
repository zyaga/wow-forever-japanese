-- UI/PlayerText.lua: text a player wrote (a guild's message of the day, a member's note, a rank's name) in the
-- bundled Japanese face when it needs it. The client's fonts have no kana or kanji, so Japanese there is drawn as
-- empty boxes. A typing box always wears the bundled face, as the chat input box does: what will be typed is not
-- known. Shown text wears it only while it holds Japanese, and has its own font back otherwise, so a window with no
-- Japanese in it looks as the client draws it. Nothing is translated here, and none of it depends on the addon's
-- switches: the text is the player's, whatever language the game's own text is shown in.
local _, WFJ = ...
local PlayerText = {}
WFJ.PlayerText = PlayerText

local Font, Compat = WFJ.Font, WFJ.Compat

local function secret(text) return Compat.secret(text) end

-- Whether `text` holds kana, kanji or full-width forms (their first byte in UTF-8).
function PlayerText.hasJapanese(text)
  return type(text) == "string" and not secret(text) and text:find("[\227-\233\239]") ~= nil
end

local function dress(box)
  local path, size, flags = box:GetFont()
  -- a font the client keeps secret can be neither compared nor set again: the box keeps what it has
  if secret(path) or secret(size) or secret(flags) then return false end
  if path == Font.PATH then return true end
  return box:SetFont(Font.PATH, Font.size(size) or Font.DEFAULT_SIZE, flags or "") ~= false
end

local boxes = setmetatable({}, { __mode = "k" })

-- A typing box in the bundled face at its own size and flags, now, whenever it shows and whenever the client gives
-- it a font object again (a box with a placeholder swaps between two font objects as it empties and fills,
-- eventeditbox.lua:127–138). → true when the box wears it
function PlayerText.box(box)
  if type(box) ~= "table" or type(box.GetFont) ~= "function" or type(box.SetFont) ~= "function" then return false end
  if not boxes[box] and type(box.HookScript) == "function" then
    boxes[box] = true
    box:HookScript("OnShow", dress)
    if type(box.SetFontObject) == "function" then hooksecurefunc(box, "SetFontObject", dress) end
  end
  return dress(box)
end

-- Shown text: the bundled face while `text` (the widget's own text when not given) holds Japanese, the widget's own
-- font back when it does not. A secret value can be neither read nor matched: the widget is left as it is.
-- → true when the widget wears the bundled face
function PlayerText.shown(widget, text)
  if type(widget) ~= "table" or type(widget.SetFont) ~= "function" then return false end
  if text == nil and type(widget.GetText) == "function" then text = widget:GetText() end
  if secret(text) then return false end
  if PlayerText.hasJapanese(text) then return Font.bundle(widget) ~= nil end
  Font.restore(widget)
  return false
end

-- A SimpleHTML's text: it has no GetText, and gives its paragraphs with GetTextData
-- [verified: blizzard_apidocumentationgenerated/simplehtmlapidocumentation.lua, GetTextData → HTMLContentNode.text].
local function htmlText(html)
  if type(html.GetTextData) ~= "function" then return nil end
  local ok, nodes = pcall(html.GetTextData, html)
  if not ok or type(nodes) ~= "table" then return nil end
  local parts = {}
  for _, node in ipairs(nodes) do
    if type(node) == "table" and type(node.text) == "string" and not secret(node.text) then
      parts[#parts + 1] = node.text
    end
  end
  return table.concat(parts, "\n")
end

local followed = setmetatable({}, { __mode = "k" }) -- widget → what its font is set through

-- Shown text the client rewrites: PlayerText.shown for what the widget holds now and after every SetText. A
-- SimpleHTML's font is read and set through its paragraph text type (UI/HtmlText's adapter)
-- [verified in game: plain SimpleHTML text draws with the P font, on the guild message of the day in Japanese].
-- → true when the widget was hooked now
function PlayerText.follow(widget)
  if type(widget) ~= "table" or type(widget.SetText) ~= "function" or followed[widget] then return false end
  local target, now = widget, nil
  if type(widget.GetText) ~= "function" then
    target = WFJ.HtmlText.new()
    target.html = widget
    now = htmlText(widget)
  end
  followed[widget] = target
  hooksecurefunc(widget, "SetText", function(_, text) PlayerText.shown(target, text) end)
  if target == widget or now ~= nil then PlayerText.shown(target, now) end
  return true
end

-- PlayerText.box / .follow / .shown for widgets named by path ("CommunitiesSettingsDialog.NameEdit"): the first
-- name is a global, the rest are fields. A widget this client does not have is passed over. → the number found
local function at(path)
  local head, rest = path:match("^([^.]+)%.?(.*)$")
  local w = head and Compat.resolve(head)
  for field in rest:gmatch("[^.]+") do w = type(w) == "table" and w[field] or nil end
  return type(w) == "table" and w or nil
end

function PlayerText.each(fn, paths)
  local n = 0
  for _, path in ipairs(paths) do
    local w = at(path)
    if w then
      fn(w)
      n = n + 1
    end
  end
  return n
end
