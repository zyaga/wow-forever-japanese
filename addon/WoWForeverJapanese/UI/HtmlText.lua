-- UI/HtmlText.lua: a SimpleHTML seen as a FontString, so Render and SurfaceState can show a translation on it.
-- A SimpleHTML has no GetText [verified: blizzard_apidocumentationgenerated/simplehtmlapidocumentation.lua:
-- SetText(text, ignoreMarkup), per-text-type GetFont / SetFont]. GetText is the text of record: the client's last
-- write, or ours once shown. SetText writes the SimpleHTML (with ignoreMarkup when the client writes it that way) and
-- flags the write, so the module's SetText post-hook can skip its own text. The font is the P text type's
-- [unverified: that plain SimpleHTML text draws with the P font; in-game check].
local _, WFJ = ...
local HtmlText = {}
WFJ.HtmlText = HtmlText

local Adapter = {}
Adapter.__index = Adapter

function Adapter:GetText() return self.logical end

function Adapter:SetText(text)
  self.writing = true
  local ok, err
  if self.ignoreMarkup then
    ok, err = pcall(self.html.SetText, self.html, text, true)
  else
    ok, err = pcall(self.html.SetText, self.html, text)
  end
  self.writing = false
  if not ok then error(err, 0) end
  self.logical = text
end

function Adapter:GetFont()
  if type(self.html.GetFont) ~= "function" then return nil end
  return self.html:GetFont("P")
end

-- SimpleHTML's SetFont returns nothing: a refusal is read back. → bool
function Adapter:SetFont(path, size, flags)
  if type(self.html.SetFont) ~= "function" then return false end
  self.html:SetFont("P", path, size, flags)
  return (self:GetFont()) == path
end

-- A new adapter; `html` (the SimpleHTML) and `logical` are set by the module's SetText post-hook. `ignoreMarkup`:
-- write as the client does when it passes SetText's second argument. → adapter
function HtmlText.new(ignoreMarkup)
  return setmetatable({ html = nil, logical = nil, writing = false, ignoreMarkup = ignoreMarkup == true }, Adapter)
end
