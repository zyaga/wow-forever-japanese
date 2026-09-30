-- A stub of the Menu system for the menu specs (menus_tags_spec, menus_unit_spec, menus_untagged_spec): a
-- generated menu is a tree of element descriptions whose initializers run on pooled frames holding .fontString
-- [verified: blizzard_menu/menu.lua:418–455, 2708–2745; menuvariants.lua:9–22]. The same shape as menus_spec.lua's
-- local helpers, shared by the three specs.
local Stub = require("tests.lua.spec.wow_stub")

local M = {}

-- An element description: `text`, children, initializers (the client's first, then ours), resetters. `init`
-- (optional): a client initializer added when the element is created (as a generator's AddInitializer does).
function M.element(text, init)
  local e = { text = text, children = {}, inits = {}, resets = {} }
  function e:CreateButton(t, clientInit)
    local c = M.element(t, clientInit)
    self.children[#self.children + 1] = c
    return c
  end
  function e:EnumerateElementDescriptions() return ipairs(self.children) end
  function e:AddInitializer(fn) self.inits[#self.inits + 1] = fn end
  function e:AddResetter(fn) self.resets[#self.resets + 1] = fn end
  function e:GetTag() return self.tag end
  if init then e:AddInitializer(init) end
  return e
end

-- The compositor: a frame per element, the client's text first, then every initializer in order. Attached frames
-- (the utility buttons) are the frame's children (blizzard_menu/compositor.lua:34–46). → { [element] = frame }
function M.open(root)
  local frames = {}
  local function each(desc)
    for _, e in desc:EnumerateElementDescriptions() do
      local frame = CreateFrame("Button")
      frame.fontString = Stub.fontString(e.text)
      -- the compositor forbids SetFont on its FontStrings (blizzard_menu/compositor.lua:166–169, 254–256)
      frame.fontString.SetFont = function() error("Use of function 'SetFont' is disallowed. (Index)") end
      frame.attached = {}
      function frame:AttachButton()
        local b = CreateFrame("Button")
        self.attached[#self.attached + 1] = b
        return b
      end
      function frame:GetChildren() return unpack(self.attached) end
      for _, fn in ipairs(e.inits) do fn(frame, e) end
      frames[e] = frame
      each(e)
    end
  end
  each(root)
  return frames
end

function M.release(frames)
  for e, frame in pairs(frames) do
    for _, fn in ipairs(e.resets) do fn(frame, e) end
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
