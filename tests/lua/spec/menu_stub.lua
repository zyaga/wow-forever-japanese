-- A stub of the Menu system for the menu specs (menus_spec, menus_tags_spec, menus_unit_spec, menus_untagged_spec,
-- and the window specs that open a menu). A generated menu is a tree of element descriptions; the client builds a
-- menu frame per level holding one element frame per entry, each with .fontString holding the client's English, sets
-- its scripts, then fires "MenuProxy.OnShow" and, for a tagged root, "Menu.OpenMenuTag"
-- [verified: blizzard_menu/menu.lua:1117–1131, 1845–1849, 2453–2459, 2506–2566; menuvariants.lua:9–22].
-- Geometry: entries stack downwards (GetTop); an entry's text widget sits 16 px into its element frame and is sized
-- to its English (SetTextToFit, menutemplates.lua:298); every element frame has the menu's common width, the widest
-- English plus a 10 px margin.
local Stub = require("tests.lua.spec.wow_stub")

local M = {}

M.CHAR = 7 -- the stub's width of one character, Latin or Japanese
M.INSET = 16 -- the text widget's left offset in its element frame
M.MARGIN = 10 -- the space the client leaves after the widest label
M.PAD = 12 -- the menu frame's padding on each side

-- The width a line takes: its characters (colour codes, textures and links' markup left out) × M.CHAR.
function M.width(text)
  local t = tostring(text or "")
  t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
  local _, n = t:gsub("[^\128-\191]", "")
  return n * M.CHAR
end

-- An element description: `text`, children (a submenu), and `init` (optional): a client initializer run on the
-- element frame as the client builds it (the utility buttons it attaches, compositor.lua:34–46).
function M.element(text, init)
  local e = { text = text, children = {}, init = init }
  function e:CreateButton(t, clientInit)
    local c = M.element(t, clientInit)
    self.children[#self.children + 1] = c
    return c
  end
  function e:EnumerateElementDescriptions() return ipairs(self.children) end
  function e:GetTag() return self.tag end
  return e
end

-- EventRegistry: RegisterCallback(event, fn, owner) → fn(owner, ...) on TriggerEvent. → the registry
function M.registry()
  local registry = { calls = {} }
  function registry:RegisterCallback(event, fn, owner)
    self.calls[event] = self.calls[event] or {}
    table.insert(self.calls[event], { fn, owner })
  end
  function registry:TriggerEvent(event, ...)
    for _, c in ipairs(self.calls[event] or {}) do c[1](c[2], ...) end
  end
  _G.EventRegistry = registry
  return registry
end

local function disallowed() error("Use of function 'SetFont' is disallowed. (Index)") end

-- One menu frame for `desc`'s entries, as the client builds it (no code of the addon has run). `owner` (optional):
-- the region it reports from GetOwnerRegion. → menu frame
function M.menuFrame(desc, frames, owner)
  local kids, widest = {}, 0
  for _, e in desc:EnumerateElementDescriptions() do widest = math.max(widest, M.width(e.text)) end
  local entryWidth = M.INSET + widest + M.MARGIN
  for i, e in desc:EnumerateElementDescriptions() do
    local frame = CreateFrame("Button")
    frame.shown = true
    frame.size = { entryWidth, 20 }
    frame.top = -20 * i -- the entries stack downwards, the first at the top
    function frame:GetTop() return self.top end
    function frame:GetWidth() return self.size[1] end
    frame.GetLeft = function() return 0 end
    function frame:GetRight() return self.size[1] end
    local fs = Stub.fontString(e.text)
    fs.SetFont = disallowed -- the compositor forbids SetFont on its FontStrings (compositor.lua:166–169)
    fs.width = M.width(e.text) -- SetTextToFit
    function fs:GetWidth() return self.width end
    fs.GetLeft = function() return M.INSET end
    function fs:GetUnboundedStringWidth() return M.width(self.text) end
    frame.fontString = fs
    frame.attached = {}
    function frame:AttachButton()
      local b = CreateFrame("Button")
      self.attached[#self.attached + 1] = b
      return b
    end
    function frame:GetChildren() return unpack(self.attached) end
    function frame:GetNumChildren() return #self.attached end
    if e.init then e.init(frame, e) end
    kids[#kids + 1] = frame
    frames[e] = frame
  end
  local menu = { shown = true, width = entryWidth + 2 * M.PAD, owner = owner }
  function menu:IsShown() return self.shown end
  function menu:GetWidth() return self.width end
  function menu:SetWidth(w) self.width = w end
  function menu:GetOwnerRegion() return self.owner end
  menu.GetNumChildren = function() return #kids end
  menu.GetChildren = function() return unpack(kids) end
  return menu
end

-- Opens `root` as the client does: its menu frame shown, then "Menu.OpenMenuTag" when `tag` is given, then each
-- submenu's frame shown (its entry hovered). → { [element] = frame }, { menu frames, root first }
function M.open(registry, tag, root, contextData, owner)
  local frames, menus = {}, {}
  local rootMenu = M.menuFrame(root, frames, owner)
  menus[1] = rootMenu
  registry:TriggerEvent("MenuProxy.OnShow", rootMenu)
  if tag then registry:TriggerEvent("Menu.OpenMenuTag", tag, contextData) end
  local function subs(desc)
    for _, e in desc:EnumerateElementDescriptions() do
      if #e.children > 0 then
        local m = M.menuFrame(e, frames)
        menus[#menus + 1] = m
        registry:TriggerEvent("MenuProxy.OnShow", m)
        subs(e)
      end
    end
  end
  subs(root)
  return frames, menus
end

-- Closes the menus, submenus first, as the client hides them.
function M.close(registry, menus)
  for i = #menus, 1, -1 do
    menus[i].shown = false
    registry:TriggerEvent("MenuProxy.OnHide", menus[i])
  end
end

-- Hovers `owner` the way MenuUtil.HookTooltipScripts does (menuutil.lua:114–130): SetOwner, the title, Show.
-- → GameTooltip's first line
function M.hover(owner, title, line)
  local tt = _G.GameTooltip
  tt:SetOwner(owner, "ANCHOR_RIGHT")
  tt:SetText(title)
  if line then tt:AddLine(line) end
  tt:Show()
  return _G.GameTooltipTextLeft1:GetText()
end

return M
