-- The frame methods the fix window and the minimap button call that the shared stub's CreateFrame does not
-- define (window dragging, ButtonFrameTemplate, the ScrollBox list, the scrolling edit box, radial buttons, tabs,
-- named fonts, textures, the Menu).
-- Adds them to every frame created after install(); the shared stub is left as it is.
local Stub = require("tests.lua.spec.wow_stub")
local F = {}

local function noop() end

function F.install()
  local create = _G.CreateFrame
  _G.CreateFrame = function(...)
    local f = create(...)
    f.SetMovable, f.SetClampedToScreen, f.EnableMouse, f.SetFrameStrata = noop, noop, noop, noop
    f.SetToplevel, f.LockHighlight, f.UnlockHighlight, f.SetAllPoints = noop, noop, noop, noop
    f.StartMoving, f.StopMovingOrSizing = noop, noop
    function f:RegisterForDrag(...) self.dragButtons = { ... } end
    function f:RegisterForClicks(...) self.clickButtons = { ... } end
    function f.SetMaxBytes(x, n) x.maxBytes = n end
    function f.SetMaxLetters(x, n) x.maxLetters = n end
    function f.SetMultiLine(x, v) x.multiLine = v end
    function f:SetScrollChild(c) self.scrollChild = c end
    function f:SetFocus() self.focused = true end
    function f:SetHeight(h) self.size = { self.size and self.size[1] or 0, h } end
    function f:SetFont(p, s, fl) self.font = { path = p, size = s, flags = fl }; return true end
    function f:GetFont() if self.font then return self.font.path, self.font.size, self.font.flags end end
    function f:ClearAllPoints() self.point = nil end
    function f:GetWidth() return self.size and self.size[1] or 140 end
    function f.GetCenter() return 1000, 500 end
    function f.GetEffectiveScale() return 1 end
    -- text a GameTooltip holds, for the specs (SetText resets its lines)
    function f:SetText(t) self.text = t; self.lines = {} end
    -- FontString:SetHeight (the list rows clip their text to the row) and GetStringWidth (the radio hit rect)
    local cfs = f.CreateFontString
    function f:CreateFontString(...)
      local fs = cfs(self, ...)
      function fs.SetHeight(x, h) x.height = h end
      function fs.GetStringWidth(x) return #(x.text or "") * 6 end
      return fs
    end
    local tex = f.CreateTexture
    function f:CreateTexture(...)
      local t = tex(self, ...)
      function t.SetTexture(x, path) x.texture = path end
      t.SetAllPoints, t.SetWidth, t.SetHeight = noop, noop, noop
      return t
    end
    return f
  end
  _G.UISpecialFrames = {}
  -- TabSystemTemplate (Blizzard_SharedXML/Shared/TabSystem/TabSystemTemplates.lua:283–320): AddTab, the selected
  -- callback, SetTab from a tab's click, SetTabVisuallySelected, GetTabButton; CreateFramePool is only stored
  _G.CreateFramePool = function(kind, parent, template) return { kind = kind, parent = parent, template = template } end
  local plain = _G.CreateFrame
  _G.CreateFrame = function(kind, name, parent, template, ...)
    local f = plain(kind, name, parent, template, ...)
    if template == "TabSystemTemplate" then
      f.tabs = {}
      function f.AddTab(ts, text)
        local id = #ts.tabs + 1
        local t = plain("Button", nil, ts)
        t.Text = t:CreateFontString(nil, "OVERLAY")
        t.tabText, t.tabID = text, id
        t:SetScript("OnClick", function() ts:SetTab(id, true) end)
        ts.tabs[id] = t
        return id
      end
      function f.SetTabSelectedCallback(ts, fn) ts.cb = fn end
      function f.SetTab(ts, id, user) if not ts.cb(id, user) then ts:SetTabVisuallySelected(id) end end
      function f.SetTabVisuallySelected(ts, id) ts.selectedTabID = id end
      function f.GetTabButton(ts, id) return ts.tabs[id] end
      function f.MarkDirty(ts) ts.dirty = true end
    elseif template == "ButtonFrameTemplate" then
      -- SharedUIPanelTemplates.xml:711 + PortraitFrame.lua:4–28: an Inset, a title string, SetTitle / GetTitleText
      f.Inset = plain("Frame", nil, f)
      f.TitleText = f:CreateFontString(nil, "OVERLAY")
      function f.SetTitle(x, t) x.TitleText:SetText(t) end
      function f.GetTitleText(x) return x.TitleText end
    elseif template == "WowScrollBoxList" then
      -- a ScrollBox list: SetDataProvider runs the view's element initializer for every item into pooled stub
      -- buttons (box.frames, shown for items and hidden past them), as ScrollBoxListView does for visible rows
      f.frames = {}
      function f.SetDataProvider(box, dp)
        box.dataProvider = dp
        local items = dp.items
        for i, item in ipairs(items) do
          local b = box.frames[i]
          if not b then b = plain("Button", nil, box); box.frames[i] = b end
          if box.view and box.view.init then box.view.init(b, item) end
          b:Show()
        end
        for i = #items + 1, #box.frames do box.frames[i]:Hide() end
      end
    elseif template == "ScrollingEditBoxTemplate" then
      -- ScrollTemplates.lua:15–253: an EventEditBox inside a ScrollBox; SetFontObject / SetText / SetCursorPosition
      -- act on the edit box; RegisterCallback(event, fn, owner) → fn(owner, …) (CallbackRegistry)
      f.EditBox = plain("EditBox", nil, f)
      f.callbacks = {}
      local sb = plain("Frame", nil, f)
      function f.GetEditBox(x) return x.EditBox end
      function f.GetScrollBox() return sb end
      -- EventEditBox.lua:122–138: ApplyText sets the text, then puts the template's font object back (the client's
      -- GameFontHighlight, no Japanese); our hook must follow it with the bundled face
      function f.EditBox.ApplyText(eb, t)
        eb:SetText(t)
        eb.font = { path = "Fonts\\FRIZQT__.TTF", size = 12, flags = "" }
      end
      function f.SetText(x, t) x.EditBox:ApplyText(t) end
      function f.SetCursorPosition(x, n) x.EditBox:SetCursorPosition(n) end
      function f.RegisterCallback(x, event, fn, owner) x.callbacks[event] = function(...) fn(owner, ...) end end
    elseif template == "UIRadialButtonTemplate" or template == "UIRadioButtonTemplate" then
      f.text = f:CreateFontString(nil, "BACKGROUND")
      function f.SetHitRectInsets(x, l, r, t, b) x.hitRect = { l, r, t, b } end
    end
    return f
  end
  -- ScrollBox helpers (ScrollBoxLinearView.lua:246, ScrollBoxListView.lua:496, ScrollUtil.lua:137 / :149,
  -- DataProvider.lua:277)
  _G.CreateScrollBoxListLinearView = function()
    local v = {}
    function v.SetElementExtent(x, e) x.extent = e end
    function v.SetElementInitializer(x, kind, fn) x.kind, x.init = kind, fn end
    return v
  end
  _G.CreateDataProvider = function(items) return { items = items or {} } end
  _G.ScrollBoxConstants = { RetainScrollPosition = true, UpdateImmediately = true }
  F.scrollUtil()
  _G.ButtonFrameTemplate_HidePortrait = function(f) f.portraitHidden = true end
  _G.time = function() return 1790000000 end
  _G.UIParent = CreateFrame("Frame", "UIParent")
  _G.UIParent.shown = true
  _G.Minimap = CreateFrame("Frame", "Minimap", _G.UIParent)
  _G.Minimap:SetSize(140, 140)
  _G.GetCursorPosition = function() return F.cursor[1], F.cursor[2] end
  F.cursor = { 1000, 600 }
  -- MenuUtil.CreateContextMenu (Blizzard_Menu/MenuUtil.lua:151): records the generated elements
  F.menus = {}
  _G.MenuUtil = { CreateContextMenu = function(owner, generator)
    local menu = { owner = owner, elements = {} }
    local root = {}
    local function add(kind, text, a, b)
      local el = { kind = kind, text = text, a = a, b = b, initializers = {} }
      function el.AddInitializer(e, fn) e.initializers[#e.initializers + 1] = fn end
      menu.elements[#menu.elements + 1] = el
      return el
    end
    function root.CreateTitle(_, text) return add("title", text) end
    function root.CreateCheckbox(_, text, isSelected, setSelected)
      return add("checkbox", text, isSelected, setSelected)
    end
    function root.CreateButton(_, text, fn) return add("button", text, fn) end
    function root.CreateDivider() return add("divider", "") end
    generator(owner, root)
    F.menus[#F.menus + 1] = menu
    return menu
  end }
  return Stub
end

-- The two ScrollUtil helpers the list and the text field call, added to whatever ScrollUtil the shared stubs built
-- (Stub.installGossipAPI replaces the table: call this again after it).
function F.scrollUtil()
  _G.ScrollUtil = _G.ScrollUtil or {}
  _G.ScrollUtil.InitScrollBoxListWithScrollBar = function(box, bar, view) box.view, box.bar = view, bar end
  _G.ScrollUtil.RegisterScrollBoxWithScrollBar = function(box, bar) box.bar = bar end
end

function F.clear()
  for _, name in ipairs({ "CreateScrollBoxListLinearView", "CreateDataProvider", "ScrollBoxConstants",
      "ButtonFrameTemplate_HidePortrait",
      "CreateFramePool", "UISpecialFrames", "time", "UIParent", "Minimap", "GetCursorPosition",
      "MenuUtil", "WFJFixWindow",
      "WFJMinimapButton", "WFJMinimapButtonIcon", "WFJMinimapTooltip" }) do
    _G[name] = nil
  end
end

-- Every text the frames and FontStrings created since install() show (FontStrings, EditBoxes, button captions).
function F.allText()
  local out = {}
  for _, fs in ipairs(Stub.fontStrings) do out[#out + 1] = fs:GetText() or "" end
  for _, f in ipairs(Stub.frames) do
    if type(f.text) == "string" then out[#out + 1] = f.text end
    for _, c in ipairs(f.children) do
      if type(c.GetText) == "function" then out[#out + 1] = c:GetText() or "" end
    end
  end
  return table.concat(out, "\n")
end

return F
