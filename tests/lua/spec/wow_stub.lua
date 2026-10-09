-- Minimal Blizzard API stub. Builds ONLY what the addon touches; anything missing fails loudly.
local Stub = {}

local function readToc(path)
  local meta = {}
  local f = assert(io.open(path, "r"))
  for line in f:lines() do
    line = line:gsub("^\239\187\191", "") -- UTF-8 BOM, which Windows editors add and WoW accepts
    local k, v = line:match("^##%s*([%w%-]+):%s*(.-)%s*$")
    if k then meta[k] = v end
  end
  f:close()
  return meta
end

-- Whether the widget write in progress comes from the addon: the first caller outside this file is under addon/.
-- Client replays live here, in gossip_client.lua or in a spec, so they never count. PUC Lua 5.1 (CI) reports a
-- tail call as its own "=(tail call)" level (`return fs:SetFont(…)` in UI/ButtonText); it is skipped, as LuaJIT does.
local function byAddon()
  for level = 3, 40 do
    local info = debug.getinfo(level, "S")
    if not info then return false end
    local src = info.source or ""
    if src:find("/addon/WoWForeverJapanese/", 1, true) then return true end
    if src ~= "=(tail call)" and not src:find("wow_stub.lua", 1, true) then return false end
  end
  return false
end

-- Text geometry for height assertions: an ASCII glyph is 6 px wide, any other character 13 px; lines wrap at
-- the widget's width; a line is the font size + 1 px tall, + 4 px in the bundled Japanese face.
function Stub.textHeight(text, font, width)
  if type(text) ~= "string" or text == "" then return 0 end
  local lines = 0
  for seg in (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. "\n"):gmatch("(.-)\n") do
    local w = 0
    for ch in seg:gmatch("[%z\1-\127\194-\244][\128-\191]*") do w = w + (#ch == 1 and 6 or 13) end
    lines = lines + math.max(1, math.ceil(w / width))
  end
  local bundled = font.path:find("ipagui", 1, true) ~= nil
  return lines * (font.size + (bundled and 4 or 1))
end

-- A FontString-like object: Get/SetText, Get/SetFont, SetPoint, Show/Hide, plus call counters for the specs
-- (`calls.addonSetText` / `addonSetFont`: the writes the addon made).
-- Every FontString created is appended to Stub.fontStrings so a spec can assert which widgets were written.
function Stub.fontString(text, path, size, flags)
  local fs = {
    text = text or "", font = { path = path or "Fonts\\FRIZQT__.TTF", size = size or 13, flags = flags or "" },
    calls = { SetText = 0, SetFont = 0, addonSetText = 0, addonSetFont = 0 }, shown = true,
  }
  function fs:GetText() return self.text end
  function fs:SetText(t)
    self.calls.SetText = self.calls.SetText + 1
    if byAddon() then self.calls.addonSetText = self.calls.addonSetText + 1 end
    self.text = t
  end
  function fs:GetHeight() return Stub.textHeight(self.text, self.font, self.width or 300) end
  function fs:GetFont() return self.font.path, self.font.size, self.font.flags end
  function fs:SetFont(p, s, f)
    self.calls.SetFont = self.calls.SetFont + 1
    if byAddon() then self.calls.addonSetFont = self.calls.addonSetFont + 1 end
    if Stub.fontSetFails then return false end
    self.font = { path = p, size = s, flags = f }
    return true
  end
  -- font objects (the Menu compositor sets its FontStrings with SetFontObject)
  -- re-applying the object a FontString already has does not undo a SetFont made since (in game: chat lines kept the
  -- bundled face through RefreshDisplay's InitializeFontString, scrollingmessageframe.lua:642, 716)
  function fs:SetFontObject(obj)
    if obj ~= nil and obj == self.fontObject then return end
    self.fontObject = obj
    if type(obj) == "table" and obj.font then
      self.font = { path = obj.font.path, size = obj.font.size, flags = obj.font.flags }
    end
  end
  function fs:GetFontObject() return self.fontObject end
  function fs:SetPoint(...) self.point = { ... } end
  function fs:Show() self.shown = true end
  function fs:Hide() self.shown = false end
  function fs:IsShown() return self.shown end
  function fs:SetWidth(w) self.width = w end
  function fs:SetSize(w, h) self.width, self.height = w, h end
  function fs:SetJustifyH(j) self.justifyH = j end
  function fs:SetJustifyV(j) self.justifyV = j end
  function fs:SetWordWrap(w) self.wordWrap = w end
  function fs:ClearAllPoints() self.point = nil end
  function fs:SetTextColor(r, g, b, a) self.color = { r, g, b, a } end
  function fs:GetTextColor() -- white unless set, as a client FontString's default
    local c = self.color or { 1, 1, 1, 1 }
    return c[1], c[2], c[3], c[4]
  end
  function fs.GetObjectType() return "FontString" end -- region walks (Labels.region)
  function fs:IsVisible() return self.shown end
  if Stub.fontStrings then Stub.fontStrings[#Stub.fontStrings + 1] = fs end
  return fs
end

-- A Font object (a frame's GetFontObject): its font as a table, and GetFont like the client's.
function Stub.fontObject(path, size, flags)
  local obj = { font = { path = path, size = size, flags = flags or "" } }
  function obj:GetFont() return self.font.path, self.font.size, self.font.flags end
  return obj
end

-- A FontString registered as a global, the way Blizzard's XML-named widgets are.
function Stub.namedFontString(name, text, path, size, flags)
  local fs = Stub.fontString(text, path, size, flags)
  fs.name = name
  _G[name] = fs
  return fs
end

-- The Settings (options panel) API mock: records calls in Stub.settingsCalls. The category is id 42; subcategories
-- are 43, 44, … in registration order.
function Stub.installSettingsAPI()
  Stub.settingsCalls = {}
  local nextSub = 43
  _G.Settings = {
    RegisterCanvasLayoutCategory = function(frame, name)
      Stub.settingsCalls[#Stub.settingsCalls + 1] = { "RegisterCanvasLayoutCategory", frame, name }
      return { frame = frame, name = name, GetID = function() return 42 end }
    end,
    RegisterCanvasLayoutSubcategory = function(parent, frame, name)
      Stub.settingsCalls[#Stub.settingsCalls + 1] = { "RegisterCanvasLayoutSubcategory", parent, frame, name }
      local id = nextSub
      nextSub = nextSub + 1
      return { frame = frame, name = name, GetID = function() return id end }
    end,
    RegisterAddOnCategory = function(category)
      Stub.settingsCalls[#Stub.settingsCalls + 1] = { "RegisterAddOnCategory", category }
    end,
    OpenToCategory = function(id)
      Stub.settingsCalls[#Stub.settingsCalls + 1] = { "OpenToCategory", id }
    end,
  }
end

function Stub.removeSettingsAPI()
  _G.Settings = nil
end

-- Keys and bindings: side polls, IsKeyDown / IsMouseButtonDown, combat, the player's binding set
-- (Stub.bindings[key] = action), override bindings and every binding write (Stub.bindingCalls), and the client's
-- BindingUtil helpers as classic_era defines them [verified: Blizzard_SharedXML/BindingUtil.lua:5–40, 66, 86, 116].
Stub.META = { LALT = true, RALT = true, LCTRL = true, RCTRL = true, LSHIFT = true, RSHIFT = true, LMETA = true,
  RMETA = true, ALT = true, CTRL = true, SHIFT = true, META = true }
Stub.MOUSE = { LeftButton = "BUTTON1", RightButton = "BUTTON2", MiddleButton = "BUTTON3", Button1 = "BUTTON1",
  Button2 = "BUTTON2", Button3 = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }
Stub.BINDING_NAMES = { ACTIONBUTTON5 = "Action Button 5", MOVEFORWARD = "Move Forward",
  WFJ_TOGGLE = "Toggle translation" }
Stub.KEY_NAMES = { BUTTON4 = "Mouse Button 4", BUTTON5 = "Mouse Button 5", BUTTON3 = "Middle Mouse" }

function Stub.installKeyAPI()
  Stub.pressed, Stub.mouse, Stub.combat = {}, {}, false
  Stub.bindings, Stub.bindingCalls, Stub.keyboardCalls = {}, {}, {}
  local sides = { Left = "l", Right = "r" }
  for side, prefix in pairs(sides) do
    _G["Is" .. side .. "AltKeyDown"] = function() return Stub.keys[prefix .. "alt"] end
    _G["Is" .. side .. "ControlKeyDown"] = function() return Stub.keys[prefix .. "ctrl"] end
    _G["Is" .. side .. "ShiftKeyDown"] = function() return Stub.keys[prefix .. "shift"] end
  end
  _G.IsKeyDown = function(k) return Stub.pressed[k] == true end
  _G.IsMouseButtonDown = function(b) return Stub.mouse[b] == true end
  _G.InCombatLockdown = function() return Stub.combat end
  local function record(...) Stub.bindingCalls[#Stub.bindingCalls + 1] = { ... } end
  _G.GetBindingKey = function(action)
    local keys = {}
    for k, a in pairs(Stub.bindings) do if a == action then keys[#keys + 1] = k end end
    table.sort(keys)
    return unpack(keys)
  end
  _G.GetBindingAction = function(k) return Stub.bindings[k] or "" end
  _G.GetBindingText = function(k, prefix)
    if prefix then return Stub.BINDING_NAMES[k] or k end
    return Stub.KEY_NAMES[k] or k
  end
  _G.SetBinding = function(k, action)
    record("SetBinding", k, action)
    Stub.bindings[k] = action
    return true
  end
  _G.SaveBindings = function(set) record("SaveBindings", set) end
  _G.GetCurrentBindingSet = function() return 2 end
  _G.SetOverrideBinding = function(owner, priority, k, command)
    record("SetOverrideBinding", owner, priority, k, command)
  end
  _G.ClearOverrideBindings = function(owner) record("ClearOverrideBindings", owner) end
  _G.GetConvertedKeyOrButton = function(k) return Stub.MOUSE[k] or k end
  _G.IsMetaKey = function(k) return Stub.META[k] == true end
  _G.CreateKeyChordStringUsingMetaKeyState = function(k)
    local chord = {}
    if Stub.keys.alt then chord[#chord + 1] = "ALT" end
    if Stub.keys.ctrl then chord[#chord + 1] = "CTRL" end
    if Stub.keys.shift then chord[#chord + 1] = "SHIFT" end
    if not Stub.META[k] then chord[#chord + 1] = k end
    return table.concat(chord, "-")
  end
end

-- The in-game AddOn List: AddonList, the global row initializer the ScrollBox factory calls, the pending-
-- changes query, HideUIPanel. Stub.addonEntry() is one pooled AddonListEntryTemplate row; Stub.addonNode(i) its data.
function Stub.installAddonList()
  Stub.addonListChanged, Stub.panelCalls = false, {}
  CreateFrame("Frame", "UIParent")
  CreateFrame("Frame", "AddonList")
  _G.AddonList_InitAddon = function(entry, treeNode)
    entry.Title:SetText(Stub.addonNames[treeNode:GetData().addonIndex] or "?")
  end
  _G.AddonList_HasAnyChanged = function() return Stub.addonListChanged end
  _G.HideUIPanel = function(f) Stub.panelCalls[#Stub.panelCalls + 1] = { "HideUIPanel", f } end
end

function Stub.addonEntry()
  local entry = CreateFrame("Button", nil, nil, "AddonListEntryTemplate")
  entry.Title = Stub.fontString("")
  return entry
end

function Stub.addonNode(index)
  return { GetData = function() return { addonIndex = index } end }
end

function Stub.install(tocPath)
  local meta = readToc(tocPath)
  Stub.prints = {}
  Stub.frames = {}
  Stub.fontStrings = {}
  Stub.hooks = {}
  Stub.keys = { alt = false, ctrl = false, shift = false, -- the side polls
    lalt = false, ralt = false, lctrl = false, rctrl = false, lshift = false, rshift = false }
  Stub.fontSetFails = false
  _G.WFJ_DB = nil -- fresh SavedVariables per install (a real global; it would otherwise leak between specs)
  _G.WFJ_Collector = nil
  -- the AddOn List is opt-in per spec (Stub.installAddonList), never left over from an earlier one
  _G.AddonList, _G.AddonList_InitAddon, _G.AddonList_HasAnyChanged, _G.HideUIPanel = nil, nil, nil, nil
  _G.UIParent, _G.WFJSettingsTooltip = nil, nil

  -- GetAddOnName(index) reads Stub.addonNames (the AddOn List button).
  Stub.addonNames = {}
  _G.C_AddOns = {
    GetAddOnMetadata = function(_, key) return meta[key] end,
    GetAddOnName = function(index) return Stub.addonNames[index] end,
  }
  _G.SlashCmdList = {}
  _G.GetTime = function() return 0 end
  _G.time = function() return 1790000000 end -- the client's wall clock (the collector reminder's day)
  -- Units: the player is always "Reyn"; any other token reads Stub.units[token] = { name, guid } or nil.
  Stub.units = {}
  _G.UnitName = function(unit)
    if unit == nil or unit == "player" then return "Reyn" end
    return Stub.units[unit] and Stub.units[unit].name or nil
  end
  _G.UnitGUID = function(unit)
    if unit == "player" then return "Player-4372-0ABCDEF1" end
    return Stub.units[unit] and Stub.units[unit].guid or nil
  end
  _G.GetBuildInfo = function() return "1.15.9", "69722", "Aug 1 2026", 11509 end
  _G.GetRealmName = function() return "Stubrealm" end -- never read by the addon; a source scan proves it
  _G.UnitClass = function() return "Hunter", "HUNTER", 3 end
  _G.UnitRace = function() return "Night Elf", "NightElf", 4 end
  _G.UnitSex = function() return 2 end -- male (for gender pairs)
  _G.IsAltKeyDown = function() return Stub.keys.alt end
  _G.IsControlKeyDown = function() return Stub.keys.ctrl end
  _G.IsShiftKeyDown = function() return Stub.keys.shift end
  Stub.installKeyAPI()
  Stub.memoryUpdates = 0 -- the expensive call is counted
  _G.UpdateAddOnMemoryUsage = function() Stub.memoryUpdates = Stub.memoryUpdates + 1 end
  _G.GetAddOnMemoryUsage = function() return 1234.5 end
  _G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    Stub.prints[#Stub.prints + 1] = table.concat(parts, " ")
  end
  Stub.installSettingsAPI()

  -- hooksecurefunc(name, fn) / hooksecurefunc(table, name, fn): the original runs first, then fn with the same
  -- arguments (the table form wraps a method on that table; self is the first argument).
  _G.hooksecurefunc = function(a, b, c)
    local tbl, name, fn = _G, a, b
    if type(a) == "table" then tbl, name, fn = a, b, c end
    local orig = tbl[name]
    assert(type(orig) == "function", "hooksecurefunc: no function " .. tostring(name))
    local label = tbl == _G and name or ((tbl.name or "?") .. ":" .. name)
    Stub.hooks[label] = Stub.hooks[label] or {}
    table.insert(Stub.hooks[label], fn)
    tbl[name] = function(...)
      local results = { orig(...) }
      fn(...)
      return unpack(results)
    end
  end

  _G.CreateFrame = function(kind, name, parent, template)
    local frame = {
      kind = kind, name = name, parent = parent, template = template, events = {}, scripts = {}, shown = false,
      checked = false, children = {}, textures = {}, calls = { UpdateScrollChildRect = 0 },
    }
    function frame:RegisterEvent(e) self.events[e] = true end
    function frame:UnregisterEvent(e) self.events[e] = nil end
    -- the unit filter is recorded but not applied: a spec fires the event with the unit it means
    function frame:RegisterUnitEvent(e, ...) self.events[e] = { ... } end
    function frame:SetScript(k, fn) self.scripts[k] = fn end
    function frame:GetScript(k) return self.scripts[k] end
    function frame:HookScript(k, fn)
      local prev = self.scripts[k]
      self.scripts[k] = function(...) if prev then prev(...) end fn(...) end
    end
    function frame:Show() self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
    function frame:Hide() self.shown = false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
    function frame:IsShown() return self.shown end
    -- IsVisible: shown, and every parent shown (a parentless frame counts on its own)
    function frame:IsVisible()
      local f = self
      while f do
        if f.IsShown and not f:IsShown() then return false end
        f = f.parent
      end
      return true
    end
    function frame:GetName() return self.name end
    function frame:SetPoint(...) self.point = { ... } end
    function frame:SetSize(w, h) self.size = { w, h } end
    function frame:SetWidth(w) self.size = { w, self.size and self.size[2] or 0 } end
    -- the settings pages' widgets (template buttons, EditBoxes, the dropdown, a tooltip, key capture)
    function frame:SetText(t) self.text = t end
    function frame:GetText() return self.text end
    function frame:SetEnabled(v) self.enabled = v and true or false end
    function frame:IsEnabled() return self.enabled ~= false end
    function frame:SetMotionScriptsWhileDisabled(v) self.motionWhileDisabled = v end
    function frame:EnableKeyboard(v)
      self.keyboard = v and true or false
      Stub.keyboardCalls[#Stub.keyboardCalls + 1] = self.keyboard
    end
    function frame:SetAutoFocus(v) self.autoFocus = v end
    function frame:SetCursorPosition(n) self.cursor = n end
    function frame:HighlightText() self.highlighted = true end
    function frame:ClearFocus() self.focused = false end
    function frame:SetupMenu(generator) self.menuGenerator = generator end
    function frame:GenerateMenu() self.menuGenerated = (self.menuGenerated or 0) + 1 end
    function frame:SetOwner(owner, anchor) self.owner, self.anchor = owner, anchor; self.lines = {} end
    function frame:AddLine(t) self.lines[#self.lines + 1] = t end
    function frame:CreateTexture(texName, layer)
      local tex = { name = texName, layer = layer }
      tex.SetColorTexture = function(t, ...) t.color = { ... } end
      tex.SetPoint = function(t, ...) t.point = { ... } end
      tex.SetSize = function(t, w, h) t.size = { w, h } end
      tex.SetHeight = function(t, h) t.height = h end
      tex.SetTexture = function(t, path) t.texture = path end
      tex.SetAtlas = function(t, atlas) t.atlas = atlas end
      tex.SetAllPoints = function(t, rel) t.allPoints = rel or true end
      tex.ClearAllPoints = function(t) t.point = nil end
      tex.Show = function(t) t.shown = true end
      tex.Hide = function(t) t.shown = false end
      tex.IsShown = function(t) return t.shown ~= false end
      self.children[#self.children + 1] = tex
      return tex
    end
    -- test-only: the recorded dropdown's radio items → { { text, isSelected, setSelected, data } }
    function frame:menuItems()
      local items, root = {}, {}
      function root.CreateRadio(_, text, isSelected, setSelected, data)
        items[#items + 1] = { text = text, isSelected = isSelected, setSelected = setSelected, data = data }
      end
      self.menuGenerator(self, root)
      return items
    end
    -- test-only: a key / mouse button pressed while this frame has keyboard input
    function frame:keyDown(key) if self.scripts.OnKeyDown then self.scripts.OnKeyDown(self, key) end end
    function frame:mouseDown(button) if self.scripts.OnMouseDown then self.scripts.OnMouseDown(self, button) end end
    function frame:GetFrameLevel() return self.level or 1 end
    function frame:SetAlpha(a) self.alpha = a end
    function frame:SetFrameLevel(l) self.level = l end
    function frame:SetChecked(v) self.checked = v and true or false end
    function frame:GetChecked() return self.checked end
    function frame:SetNormalTexture(t) self.textures.normal = t end
    function frame:SetPushedTexture(t) self.textures.pushed = t end
    function frame:SetHighlightTexture(t) self.textures.highlight = t end
    function frame:SetCheckedTexture(t) self.textures.checked = t end
    function frame:UpdateScrollChildRect() self.calls.UpdateScrollChildRect = self.calls.UpdateScrollChildRect + 1 end
    function frame:CreateFontString(fsName, layer, fontTemplate)
      local fs = Stub.fontString("")
      fs.name, fs.layer, fs.template = fsName, layer, fontTemplate
      self.children[#self.children + 1] = fs
      return fs
    end
    -- a frame's FontString regions in creation order (unnamed labels are found this way)
    function frame:GetRegions() return unpack(self.children) end
    function frame:GetObjectType() return self.kind end
    function frame:IsVisible() return self.shown end
    -- test-only: attach an existing FontString as a region (an XML label the client created)
    function frame:addRegion(fs) self.children[#self.children + 1] = fs; return fs end
    -- test-only: a click toggles a CheckButton's state (as the client does) and runs OnClick
    function frame:click(button)
      if self.kind == "CheckButton" then self.checked = not self.checked end
      if self.scripts.OnClick then self.scripts.OnClick(self, button or "LeftButton") end
    end
    -- test-only: deliver an event to this frame if it is registered
    function frame:fire(event, ...)
      if self.events[event] and self.scripts.OnEvent then self.scripts.OnEvent(self, event, ...) end
    end
    Stub.frames[#Stub.frames + 1] = frame
    if name then _G[name] = frame end
    return frame
  end
  Stub.installGameMenu()
  -- EnumerateFrames(prev) → the next frame the stub created (for /wfj debug ui scan)
  _G.EnumerateFrames = function(prev)
    local i = 0
    if prev then for j, f in ipairs(Stub.frames) do if f == prev then i = j end end end
    return Stub.frames[i + 1]
  end
  -- C_Item.GetItemSubClassInfo: Stub.subclasses["c:s"] = name
  Stub.subclasses = {}
  _G.C_Item = { GetItemSubClassInfo = function(c, sub) return Stub.subclasses[c .. ":" .. sub] end }
  -- load-on-demand addons (Stub.loadedAddons[name] = true) and the tab / scroll-box helpers
  Stub.loadedAddons = {}
  _G.C_AddOns.IsAddOnLoaded = function(name) return Stub.loadedAddons[name] == true end
  Stub.installPanelTemplates()
  Stub.installScrollUtil()
  return meta
end

-- The client's font object faces a button region takes on a tab state change.
Stub.TAB_FONT = "Fonts\\FRIZQT__.TTF"

-- PanelTemplates as Blizzard_SharedXML/Classic/SharedUIPanelTemplates.lua writes tabs: SelectTab disables
-- the tab and sets its disabled font object (the region's font resets to the enUS face); DeselectTab enables it;
-- TabResize measures the tab's current text (recorded in tab.measured). Tabs are Stub.button()s.
function Stub.installPanelTemplates()
  local function resetFont(tab)
    local fs = tab.GetFontString and tab:GetFontString()
    if fs then fs.font = { path = Stub.TAB_FONT, size = 10, flags = "" } end
  end
  _G.PanelTemplates_TabResize = function(tab)
    tab.measured = tab:GetText()
  end
  _G.PanelTemplates_SelectTab = function(tab)
    tab.enabled = false
    resetFont(tab)
  end
  _G.PanelTemplates_DeselectTab = function(tab)
    tab.enabled = true
    resetFont(tab)
  end
  _G.PanelTemplates_SetDisabledTabState = function(tab)
    tab.enabled = false
    resetFont(tab)
  end
  _G.PanelTemplates_UpdateTabs = function(frame)
    for i, tab in ipairs(frame.tabs or {}) do
      if i == frame.selectedTab then _G.PanelTemplates_SelectTab(tab) else _G.PanelTemplates_DeselectTab(tab) end
    end
  end
end

-- A tab: a named button whose OnShow resizes it from its current text (CharacterFrameTemplates.xml:84–87).
function Stub.tab(name, text)
  local tab = Stub.button(name, text)
  tab:SetScript("OnShow", function(self) _G.PanelTemplates_TabResize(self, 0, nil, 36, 88) end)
  return tab
end

-- ScrollUtil.AddInitializedFrameCallback: Stub.scrollBox() records callbacks; box:initFrame(frame, data)
-- runs the element initializer then every callback, the way ScrollBoxListView does on acquire.
function Stub.installScrollUtil()
  _G.ScrollUtil = {
    -- as ScrollUtil.lua:21–30: iterateExisting runs ForEachFrame(callback) → callback(frame, elementData); the
    -- OnInitializedFrame event passes (owner, frame, elementData)
    AddInitializedFrameCallback = function(box, cb, owner, iterateExisting)
      if iterateExisting then box:ForEachFrame(cb) end
      box.initCallbacks[#box.initCallbacks + 1] = { cb = cb, owner = owner }
    end,
  }
end

function Stub.scrollBox()
  local box = { frames = {}, initCallbacks = {} }
  function box:initFrame(frame, elementData, initializer)
    frame.elementData = elementData
    if initializer then initializer(frame, elementData) end
    if not _G.tContains(self.frames, frame) then self.frames[#self.frames + 1] = frame end
    for _, c in ipairs(self.initCallbacks) do c.cb(c.owner, frame, elementData) end
  end
  function box:ForEachFrame(fn) for _, f in ipairs(self.frames) do fn(f, f.elementData) end end
  return box
end

-- A ScrollingFontTemplate frame (scrolltemplates.lua:330–358): GetFontString / GetFontStringContainer /
-- GetScrollBox, and a SetText that writes the FontString, re-heights the container and fully updates the box.
-- `sf.container.height` and `sf.box.fullUpdates` record the refits.
function Stub.scrollingFont(text)
  local sf = CreateFrame("Frame")
  sf.fs = Stub.fontString(text or "")
  function sf.fs.GetStringHeight(f) return f:GetHeight() end
  sf.container = { height = 0 }
  function sf.container.SetHeight(c, h) c.height = h end
  sf.box = { fullUpdates = 0 }
  function sf.box.FullUpdate(b) b.fullUpdates = b.fullUpdates + 1 end
  function sf.GetFontString(self) return self.fs end
  function sf.GetFontStringContainer(self) return self.container end
  function sf.GetScrollBox(self) return self.box end
  function sf.SetText(self, t)
    self.fs.text = t
    self.container:SetHeight(self.fs:GetStringHeight())
    self.box:FullUpdate(true)
  end
  function sf.GetText(self) return self.fs:GetText() end
  return sf
end

_G.tContains = function(t, v) -- the client's global helper
  for _, x in ipairs(t) do if x == v then return true end end
  return false
end

-- A Button as FrameXML builds one: its text region is a FontString in the template's Normal font; the
-- client switches that region to the Highlight / Disabled font object on a state change (modelled by :state(),
-- which resets the region's font, then runs the state script). Named buttons are globals.
function Stub.button(name, text)
  local b = CreateFrame("Button", name)
  b.fontString = Stub.fontString(text or "", "Fonts\\FRIZQT__.TTF", 12, "")
  b.fontString.name = name and (name .. "Text") or nil
  b.enabled = true
  function b:GetFontString() return self.fontString end
  function b:GetText() return self.fontString:GetText() end
  function b:SetText(t) self.fontString:SetText(t) end
  function b:SetEnabled(v) self.enabled = v and true or false end
  -- test-only: a state change the client drives (OnEnter / OnLeave / OnDisable / OnEnable / OnMouseDown …)
  function b:state(script)
    self.fontString.font = { path = "Fonts\\FRIZQT__.TTF", size = 12, flags = "" } -- the font object's face
    if self.scripts[script] then self.scripts[script](self) end
  end
  return b
end

-- The Esc game menu: GameMenuFrame with a button pool and InitButtons, replaying
-- MainMenuFrameMixin:Reset / AddButton / AddCloseButton (SetText + SetScript("OnEnter"/"OnLeave") on every reuse).
-- Stub.gameMenuLabels: the labels InitButtons adds, in order.
function Stub.installGameMenu()
  local frame = CreateFrame("Frame", "GameMenuFrame")
  frame.Header = { Text = Stub.fontString("Main Menu", "Fonts\\FRIZQT__.TTF", 14, "") } -- MAINMENU_BUTTON at load
  Stub.gameMenuLabels = { "Options", "AddOns", "Support", "Macros", "Logout", "Exit Game", "Return to Game" }
  local pool = { active = {}, inactive = {} }
  function pool:Acquire()
    local b = table.remove(self.inactive) or Stub.button(nil, "")
    self.active[#self.active + 1] = b
    return b
  end
  function pool:ReleaseAll()
    for _, b in ipairs(self.active) do b.layoutIndex = nil; self.inactive[#self.inactive + 1] = b end
    self.active = {}
  end
  function pool:EnumerateActive()
    local i = 0
    return function()
      i = i + 1
      if self.active[i] then return self.active[i], true end
    end
  end
  frame.buttonPool = pool
  function frame.InitButtons(self)
    self.buttonPool:ReleaseAll()
    for i = #Stub.gameMenuLabels, 1, -1 do -- acquire in reverse so pool order differs from layout order
      local b = self.buttonPool:Acquire()
      b.layoutIndex = i
      b:SetText(Stub.gameMenuLabels[i])
      b:SetScript("OnEnter", nil)
      b:SetScript("OnLeave", nil)
    end
  end
  frame:SetScript("OnShow", function(self) self:InitButtons() end)
  return frame
end

-- The NPC talk window: GossipFrame with its ScrollBox, measure widgets and C_GossipInfo, replayed from the
-- client source in gossip_client.lua. Stub.showGossip{ … } / Stub.closeGossip().
-- the book / letter / plaque window (tests/lua/spec/itemtext_client.lua). → frame, SimpleHTML page
function Stub.installItemTextAPI()
  return require("tests.lua.spec.itemtext_client").install(Stub)
end

function Stub.installGossipAPI(viewRows)
  return require("tests.lua.spec.gossip_client").install(Stub, viewRows)
end

function Stub.fireAll(event, ...)
  for _, f in ipairs(Stub.frames) do f:fire(event, ...) end
end

-- The quest window, and the Blizzard writer functions the surface post-hooks, replaying the exact writes of
-- Blizzard_UIPanels_Game/{Vanilla,Classic}/Quest*.lua. Quest data: Stub.quest (the NPC-offered quest).
function Stub.installQuestAPI()
  Stub.quest = { id = 0, title = "", description = "", objectives = "", progress = "", completion = "" }

  -- frames [verified: QuestFrame.xml]
  CreateFrame("Frame", "QuestFrame")
  CreateFrame("Frame", "QuestFrameProgressPanel")
  for _, n in ipairs({ "QuestDetailScrollFrame", "QuestRewardScrollFrame", "QuestProgressScrollFrame",
    "QuestDetailScrollChildFrame", "QuestRewardScrollChildFrame" }) do
    CreateFrame("ScrollFrame", n)
  end
  -- the six prose widgets [verified: QuestInfo.xml, QuestFrame.xml]
  Stub.namedFontString("QuestInfoTitleHeader", "", "Fonts\\MORPHEUS.TTF", 18, "")
  Stub.namedFontString("QuestInfoDescriptionText", "", "Fonts\\FRIZQT__.TTF", 13, "")
  Stub.namedFontString("QuestInfoObjectivesText", "", "Fonts\\FRIZQT__.TTF", 13, "")
  Stub.namedFontString("QuestInfoRewardText", "", "Fonts\\FRIZQT__.TTF", 13, "")
  Stub.namedFontString("QuestProgressTitleText", "", "Fonts\\MORPHEUS.TTF", 18, "")
  Stub.namedFontString("QuestProgressText", "", "Fonts\\FRIZQT__.TTF", 13, "")
  -- decoys the addon must never write: per-objective lines, headers
  for i = 1, 2 do Stub.namedFontString("QuestInfoObjective" .. i, "Kobold Vermin slain: 0/10") end
  Stub.namedFontString("QuestInfoObjectivesHeader", "Quest Objectives")
  -- labels and buttons, with the enUS text the XML sets [verified: Vanilla/QuestInfo.xml, QuestFrame.xml];
  -- a spec with a UI index translates them, every other spec leaves them untouched.
  Stub.namedFontString("QuestInfoDescriptionHeader", "Description")
  Stub.namedFontString("QuestInfoSpellObjectiveLearnLabel", "Learn Spell:")
  Stub.namedFontString("QuestInfoRequiredMoneyText", "Required Money:")
  Stub.namedFontString("QuestProgressRequiredItemsText", "Required items:")
  Stub.namedFontString("QuestProgressRequiredMoneyText", "Required Money:")
  local rewards = CreateFrame("Frame", "QuestInfoRewardsFrame")
  rewards.Header = Stub.fontString("Rewards")
  rewards.ItemChooseText = Stub.fontString("You will be able to choose one of these rewards:")
  rewards.ItemReceiveText = Stub.fontString("You will also receive:")
  rewards.XPFrame = { ReceiveText = Stub.fontString("Experience:") }
  Stub.namedFontString("QuestInfoGroupSize", "Suggested Players [3]")
  -- the mainline QuestInfo's timer (questinfo.xml:374–391; QuestInfo_ShowTimer, questinfo.lua:327–340) and the
  -- map's rewards frame (questinfo.xml:612), which the quest window module reads too
  CreateFrame("Frame", "QuestInfoTimerFrame")
  Stub.namedFontString("QuestInfoTimerText", "")
  _G.QuestInfo_ShowTimer = function() end
  -- the rewards redraw the client runs on QUEST_ITEM_UPDATE (questframe.lua:75–84); the spec writes its English
  _G.QuestInfo_ShowRewards = function() end
  CreateFrame("Frame", "MapQuestInfoRewardsFrame")
  CreateFrame("Frame", "QuestFrameGreetingPanel")
  Stub.namedFontString("CurrentQuestsText", "Current Quests")
  Stub.namedFontString("AvailableQuestsText", "Available Quests")
  Stub.namedFontString("GreetingText", "Well met, traveller.", "Fonts\\FRIZQT__.TTF", 13, "")
  CreateFrame("ScrollFrame", "QuestGreetingScrollFrame")
  for name, text in pairs({ QuestFrameAcceptButton = "Accept", QuestFrameDeclineButton = "Decline",
    QuestFrameCompleteButton = "Continue", QuestFrameGoodbyeButton = "Cancel", QuestFrameCompleteQuestButton =
    "Complete Quest", QuestFrameCancelButton = "Cancel", QuestFrameGreetingGoodbyeButton = "Goodbye" }) do
    Stub.button(name, text)
  end

  -- quest API for the NPC window
  Stub.greeting = "Well met, traveller." -- GetGreetingText
  _G.GetGreetingText = function() return Stub.greeting end
  _G.GetQuestID = function() return Stub.quest.id end
  _G.GetTitleText = function() return Stub.quest.title end
  _G.GetQuestText = function() return Stub.quest.description end
  _G.GetObjectiveText = function() return Stub.quest.objectives end
  _G.GetProgressText = function() return Stub.quest.progress end
  _G.GetRewardText = function() return Stub.quest.completion end

  -- Blizzard writers (globals, so hooksecurefunc can wrap them), replaying the client's writes.
  _G.QUEST_TEMPLATE_DETAIL = { questLog = nil, contentWidth = 275 }
  _G.QUEST_TEMPLATE_REWARD = { questLog = nil, contentWidth = 285 }
  _G.QUEST_TEMPLATE_LOG = { questLog = true, contentWidth = 285 }
  _G.QuestInfo_Display = function(template, parentFrame)
    -- QuestInfo.lua: ShowTitle / ShowDescriptionText / ShowObjectivesText / ShowRewardText
    if template.questLog then return end
    QuestInfoTitleHeader:SetText(GetTitleText())
    if parentFrame == QuestDetailScrollChildFrame then
      QuestInfoDescriptionText:SetText(GetQuestText())
      QuestInfoObjectivesText:SetText(GetObjectiveText())
    elseif parentFrame == QuestRewardScrollChildFrame then
      QuestInfoRewardText:SetText(GetRewardText())
    end
  end
  _G.QuestFrameProgressPanel_OnShow = function()
    QuestProgressTitleText:SetText(GetTitleText())
    QuestProgressText:SetText(GetProgressText())
  end
  -- Bound the way the XML does (<OnShow function="QuestFrameProgressPanel_OnShow"/>). [likely] the frame holds the
  -- function VALUE, so a hooksecurefunc on the global would not run; HookScript on the frame is correct either way.
  QuestFrameProgressPanel:SetScript("OnShow", _G.QuestFrameProgressPanel_OnShow)
  -- QuestFrameGreetingPanel_OnShow writes the greeting prose (Classic/QuestFrame.lua:316), XML-bound the same way
  -- (Vanilla/QuestFrame.xml:497) and also called by name on QUEST_LOG_UPDATE (Classic/QuestFrame.lua:99–104).
  _G.QuestFrameGreetingPanel_OnShow = function()
    GreetingText:SetText(GetGreetingText())
  end
  QuestFrameGreetingPanel:SetScript("OnShow", _G.QuestFrameGreetingPanel_OnShow)
  -- QUEST_GREETING: panel:Hide(); panel:Show() (Classic/QuestFrame.lua:59–60)
  function Stub.showGreeting()
    QuestFrame:Show()
    QuestFrameGreetingPanel:Hide()
    QuestFrameGreetingPanel:Show()
  end
  -- QUEST_LOG_UPDATE while the greeting panel is shown: the writer by name
  function Stub.questLogUpdate()
    if QuestFrameGreetingPanel:IsShown() then _G.QuestFrameGreetingPanel_OnShow(QuestFrameGreetingPanel) end
  end

  -- Drivers: what the client does on QUEST_DETAIL / QUEST_PROGRESS / QUEST_COMPLETE.
  -- (Panel OnShow → QuestInfo_Display / QuestFrameProgressPanel_OnShow; Classic/QuestFrame.lua:753, 127, 200.)
  function Stub.showDetail()
    QuestFrame:Show()
    QuestRewardScrollChildFrame:Hide(); QuestDetailScrollChildFrame:Show()
    QuestInfo_Display(QUEST_TEMPLATE_DETAIL, QuestDetailScrollChildFrame)
  end
  function Stub.showReward()
    QuestFrame:Show()
    QuestDetailScrollChildFrame:Hide(); QuestRewardScrollChildFrame:Show()
    QuestInfo_Display(QUEST_TEMPLATE_REWARD, QuestRewardScrollChildFrame)
  end
  function Stub.showProgress()
    QuestFrame:Show()
    QuestFrameProgressPanel:Show() -- QuestFrame_OnEvent: panel:Hide(); panel:Show() (Classic/QuestFrame.lua:81–82)
  end
end

-- The six tooltip frames: GameTooltip-like frames whose left lines are the globals <Name>TextLeft<i>,
-- NumLines, GetItem, GetSpell. Stub.setItemTooltip / setSpellTooltip write the lines the way the client does, then fire
-- the tooltip-data post-call.
Stub.TOOLTIP_FRAMES = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
  "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2" }

function Stub.tooltipFrame(name)
  local frame = CreateFrame("GameTooltip", name)
  frame.lines, frame.item, frame.spell = {}, nil, nil
  frame.calls.Show = 0
  frame.owner = nil
  frame.refireOnShow = false -- when true, Show() re-fires the Item/Spell post-call (models the worst case)
  function frame:NumLines() return #self.lines end
  function frame:GetItem() if self.item then return self.item.name, self.item.link end return nil end
  function frame:GetSpell() if self.spell then return self.spell.name, self.spell.id end return nil end
  -- the modern client's type filter (blizzard_sharedxmlgame/tooltip/tooltiputil.lua). Defined on every
  -- stub frame; only the data-processor path ever calls it.
  function frame:IsTooltipType(t)
    if t == 0 then return self.item ~= nil end
    if t == 1 then return self.spell ~= nil end
    if t == 7 then return self.item == nil and self.spell == nil and self.primaryInfo ~= nil end
    return false
  end
  function frame:Show()
    self.calls.Show = self.calls.Show + 1
    self.shown = true
    if self.refireOnShow then
      if self.item then Stub.fireTooltipSet(self, "Item") end
      if self.spell then Stub.fireTooltipSet(self, "Spell") end
    end
  end
  -- a Lua-built tooltip: SetOwner, then SetText (line 1, clears the rest), AddLine / AddDoubleLine, Show,
  -- written the way the client does (fs.text, not counted as ours); the item and spell are cleared.
  -- the six aura methods write the aura's lines natively (Stub.auraData, keyed as C_UnitAuras reads it),
  -- item and spell cleared. Nothing fires a post-call for them, as on the client.
  -- On the modern stub the method records {getterName, getterArgs} as the tooltip's info and fires the UnitAura
  -- post-calls, as Forever's TooltipDataHandlerMixin accessor does (tooltipdatahandler.lua:488–503).
  local function auraLines(self, key, getter, ...)
    local aura = Stub.auraData[key]
    self.item, self.spell = nil, nil
    -- tooltipData.lines: what the client wrote; `aura.extra` lines are another addon's, appended after
    local written = aura and aura.lines or {}
    self.primaryInfo = { getterName = getter, getterArgs = { n = select("#", ...), ... }, aura = true,
      tooltipData = { lines = written } }
    local shown = {}
    for _, l in ipairs(written) do shown[#shown + 1] = l end
    for _, l in ipairs(aura and aura.extra or {}) do shown[#shown + 1] = l end
    self:writeLines(shown)
    self.shown = true
    if Stub.modernTooltips then
      for _, fn in ipairs(Stub.tooltipPostCalls[7] or {}) do fn(self) end
    end
  end
  function frame:GetPrimaryTooltipInfo() return self.primaryInfo end
  function frame:SetUnitAura(unit, index, filter)
    auraLines(self, Stub.auraKey(unit, index, filter or "HELPFUL"), "GetUnitAura", unit, index, filter)
  end
  function frame:SetUnitBuff(unit, index, filter)
    auraLines(self, Stub.auraKey(unit, index, "HELPFUL"), "GetUnitBuff", unit, index, filter)
  end
  function frame:SetUnitDebuff(unit, index, filter)
    auraLines(self, Stub.auraKey(unit, index, "HARMFUL"), "GetUnitDebuff", unit, index, filter)
  end
  function frame:SetUnitAuraByAuraInstanceID(unit, id, filter)
    auraLines(self, Stub.auraKey(unit, id), "GetUnitAuraByAuraInstanceID", unit, id, filter)
  end
  function frame:SetUnitBuffByAuraInstanceID(unit, id, filter)
    auraLines(self, Stub.auraKey(unit, id), "GetUnitBuffByAuraInstanceID", unit, id, filter)
  end
  function frame:SetUnitDebuffByAuraInstanceID(unit, id, filter)
    auraLines(self, Stub.auraKey(unit, id), "GetUnitDebuffByAuraInstanceID", unit, id, filter)
  end
  -- Forever's RebuildFromTooltipInfo: the lines rewritten from the recorded info, no method called, the post-calls
  -- fired again (gametooltip.lua:963–979). Classic Era has no such path.
  function frame:rebuild(lines)
    self:writeLines(lines)
    if Stub.modernTooltips and self.primaryInfo and self.primaryInfo.aura then
      for _, fn in ipairs(Stub.tooltipPostCalls[7] or {}) do fn(self) end
    end
  end
  function frame:SetOwner(owner) self.owner = owner; self.item, self.spell = nil, nil end
  function frame:GetOwner() return self.owner end
  function frame:ClearLines() self:writeLines({}) end
  function frame:SetText(text) self.item, self.spell = nil, nil; self:writeLines({ text }); self.shown = true end
  -- AddLine / AddDoubleLine add one line below the others and leave those as they are (a translated line stays)
  local function addLine(self, l, r)
    local i = #self.lines + 1
    for side, text in pairs({ Left = l or "", Right = r or "" }) do
      local fsName = name .. "Text" .. side .. i
      local fs = _G[fsName] or Stub.namedFontString(fsName, "", "Fonts\\FRIZQT__.TTF", 12, "")
      fs.text = text
    end
    self.lines[i] = l or ""
  end
  function frame:AddLine(text) addLine(self, text) end
  function frame:AddDoubleLine(l, r) addLine(self, l, r) end
  -- AppendText adds to line 1's current text [unknown: or to the client's copy of the SetText string; in-game
  -- check in docs/testing/strategy.md]
  function frame:AppendText(text)
    local fs = _G[name .. "TextLeft1"]
    if not fs then return end
    fs.text = (fs.text or "") .. text
    self.lines[1] = fs.text
  end
  -- A line is "left text" or { "left", "right" } (the right column: armor type, "Speed 2.60").
  function frame:writeLines(lines)
    local lefts = {}
    for i, line in ipairs(lines) do
      local left, right = line, ""
      if type(line) == "table" then left, right = line[1], line[2] or "" end
      lefts[i] = left
      for side, text in pairs({ Left = left, Right = right }) do
        local fs = _G[name .. "Text" .. side .. i]
        if not fs then fs = Stub.namedFontString(name .. "Text" .. side .. i, "", "Fonts\\FRIZQT__.TTF", 12, "") end
        fs.text = text -- the client's own write: not counted as ours
        -- a line given as { left, right, color = { r, g, b } } is written in that colour; any other in the default
        if side == "Left" then fs.color = type(line) == "table" and line.color or nil end
      end
    end
    for i = #lines + 1, #self.lines do
      for _, side in ipairs({ "Left", "Right" }) do
        local fs = _G[name .. "Text" .. side .. i]
        if fs then fs.text = "" end
      end
    end
    self.lines = lefts
  end
  return frame
end

-- auras as C_UnitAuras returns them. Stub.auraData[key] = { spellId, lines }; `key` is
-- "<unit>:<index>:<HELPFUL|HARMFUL>" for the index getters, "<unit>#<auraInstanceID>" for the instance one.
function Stub.auraKey(unit, a, filter)
  if filter then return unit .. ":" .. tostring(a) .. ":" .. filter:match("^(%u+)") end
  return unit .. "#" .. tostring(a)
end

function Stub.installAuraAPI()
  Stub.auraData = {}
  local function get(key) local a = Stub.auraData[key]; return a and a.data or nil end
  _G.C_UnitAuras = {
    GetAuraDataByIndex = function(unit, index, filter) return get(Stub.auraKey(unit, index, filter or "HELPFUL")) end,
    GetBuffDataByIndex = function(unit, index) return get(Stub.auraKey(unit, index, "HELPFUL")) end,
    GetDebuffDataByIndex = function(unit, index) return get(Stub.auraKey(unit, index, "HARMFUL")) end,
    GetAuraDataByAuraInstanceID = function(unit, id) return get(Stub.auraKey(unit, id)) end,
  }
end

function Stub.installTooltipAPI()
  for _, n in ipairs(Stub.TOOLTIP_FRAMES) do
    for i = 1, 40 do _G[n .. "TextLeft" .. i] = nil; _G[n .. "TextRight" .. i] = nil end -- fresh per install
    Stub.tooltipFrame(n)
  end
  Stub.installAuraAPI()
  _G.ITEM_SPELL_TRIGGER_ONUSE = "Use:"
  _G.ITEM_SPELL_TRIGGER_ONEQUIP = "Equip:"
  _G.ITEM_SPELL_TRIGGER_ONPROC = "Chance on hit:"
  -- the Forever tooltip client: no OnTooltipSet* scripts and no bare GetSpellDescription; it has
  -- TooltipDataProcessor + Enum.TooltipDataType and carries the description reader as C_Spell.GetSpellDescription
  -- (a live probe found the bare name absent): Stub.spellDescriptions[id]; set
  -- Stub.noSpellDescriptionAPI before installing to model a client without it. Every install starts clean.
  Stub.spellDescriptions = {}
  Stub.modernTooltips = true -- read by the aura setters above (they fire the UnitAura post-calls)
  Stub.tooltipPostCalls = { [0] = {}, [1] = {}, [7] = {} }
  _G.Enum, _G.TooltipDataProcessor, _G.GetSpellDescription, _G.C_Spell = nil, nil, nil, nil
  -- Set Stub.noTooltipDataProcessor before installing to model a client that has no TooltipDataProcessor: the
  -- surfaces' defensive path (Tooltip.path "none", TooltipUnit.init false). Forever always has one.
  if not Stub.noTooltipDataProcessor then
    _G.Enum = { TooltipDataType = { Item = 0, Spell = 1, Unit = 2, UnitAura = 7 } }
    _G.TooltipDataProcessor = {
      AddTooltipPostCall = function(dataType, fn)
        local list = Stub.tooltipPostCalls[dataType] or {}
        list[#list + 1] = fn
        Stub.tooltipPostCalls[dataType] = list
      end,
    }
    if not Stub.noSpellDescriptionAPI then
      _G.C_Spell = { GetSpellDescription = function(id) return Stub.spellDescriptions[id] or "" end }
    end
  end
end

-- hands the tooltip to the data processor's post-calls. `kind` is "Item" or "Spell".
function Stub.fireTooltipSet(frame, kind)
  local dataType = kind == "Item" and 0 or 1
  for _, fn in ipairs(Stub.tooltipPostCalls[dataType] or {}) do fn(frame) end
end

function Stub.setItemTooltip(frame, link, lines)
  -- the item's name is the link's [label] (a comparison tooltip's line 1 is its header, not the name)
  local first = type(lines[1]) == "table" and lines[1][1] or lines[1]
  frame.item = link and { name = link:match("%[(.-)%]") or first, link = link } or nil
  frame.primaryInfo = nil
  frame.spell = nil
  frame:writeLines(lines)
  frame.shown = true
  Stub.fireTooltipSet(frame, "Item")
end

function Stub.setSpellTooltip(frame, id, lines)
  frame.spell = id and { name = lines[1], id = id } or nil
  frame.primaryInfo = nil
  frame.item = nil
  frame:writeLines(lines)
  frame.shown = true
  Stub.fireTooltipSet(frame, "Spell")
end

-- SavedVariables text for the round-trip fixture: one `NAME = <value>` per variable; an array part as
-- positional values with a `-- [i]` comment, other keys as `["k"] = v` sorted, tab-indented; strings with
-- \\ \" \n \r escaped. Deterministic on purpose: the real client file (1.15.9.69722) has no
-- indentation, no `-- [i]` comments and unordered keys; the pipeline reader accepts either layout.
local function svString(s)
  return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r") .. '"'
end

local function svValue(v, depth, out)
  local t = type(v)
  if t == "string" then out[#out + 1] = svString(v)
  elseif t == "number" then out[#out + 1] = (v == math.floor(v)) and ("%d"):format(v) or tostring(v)
  elseif t == "boolean" then out[#out + 1] = tostring(v)
  elseif t == "table" then
    local keys = {}
    for k in pairs(v) do
      if not (type(k) == "number" and k >= 1 and k <= #v and k == math.floor(k)) then keys[#keys + 1] = k end
    end
    table.sort(keys, function(a, b)
      if type(a) ~= type(b) then return type(a) == "number" end
      return a < b
    end)
    out[#out + 1] = "{\n"
    for i = 1, #v do
      out[#out + 1] = ("\t"):rep(depth + 1)
      svValue(v[i], depth + 1, out)
      out[#out + 1] = (", -- [%d]\n"):format(i)
    end
    for _, k in ipairs(keys) do
      out[#out + 1] = ("\t"):rep(depth + 1)
      out[#out + 1] = type(k) == "number" and ("[%d] = "):format(k) or ("[" .. svString(k) .. "] = ")
      svValue(v[k], depth + 1, out)
      out[#out + 1] = ",\n"
    end
    out[#out + 1] = ("\t"):rep(depth) .. "}"
  else
    error("svValue: cannot serialize " .. t)
  end
end

function Stub.serializeSavedVariables(names)
  local out = {}
  for _, name in ipairs(names) do
    out[#out + 1] = name .. " = "
    if _G[name] == nil then out[#out + 1] = "nil" else svValue(_G[name], 0, out) end
    out[#out + 1] = "\n"
  end
  return table.concat(out)
end

return Stub
