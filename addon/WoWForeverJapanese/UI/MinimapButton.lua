-- UI/MinimapButton.lua: the fix-report minimap button, a small button on the minimap's edge. Left-click opens the
-- fix window; right-click opens a menu with translation on / off (the master switch, the same state as the settings
-- checkbox), report a line, settings, hide this button. Drag moves it around the rim; the angle is kept in
-- WFJ_DB.minimap (absent → DEFAULT_ANGLE). The `minimapButton` setting (default on) shows or hides it; "Hide this
-- button" turns that setting off, and the settings page or `/wfj minimapButton on` brings it back. Blizzard's addon
-- dropdown on the minimap gets the same two actions through the TOC's AddonCompartmentFunc (Main.lua's globals), so
-- a hidden button never locks anyone out.
-- Forever (camelot) sources [verified: forever-ui-1.60.1.70009:
--   MiniMapButtonTemplate Blizzard_Minimap/Shared/MinimapButtonTemplate.xml (press offset on the `<name>Icon`
--     texture, MinimapButtonTemplate.lua), listed for camelot in Blizzard_Minimap.toc;
--   the Minimap frame Blizzard_Minimap/Mainline/Minimap.xml:195 ([Family] loads for camelot);
--   MenuUtil.CreateContextMenu Blizzard_Menu/MenuUtil.lua:151, the description's CreateTitle / CreateCheckbox /
--     CreateButton / CreateDivider inserters MenuUtil.lua:270–287;
--   AddonCompartmentFunc / …FuncOnEnter / …FuncOnLeave, called (addonName, buttonName | frame)
--     Blizzard_Minimap/Mainline/AddonCompartment.lua:77–117].
-- The rim is placed for a round minimap [unverified: camelot's minimap shape; no GetMinimapShape in its FrameXML].
-- Menu entries take the bundled font through Labels.menuText, as UI/Menus does (the compositor forbids SetFont).
local _, WFJ = ...
local MinimapButton = {}
WFJ.MinimapButton = MinimapButton

local S, W, Text, C = WFJ.Settings, WFJ.OptionsWidgets, WFJ.OptionsText, WFJ.Compat

MinimapButton.DEFAULT_ANGLE = 225 -- lower left of the rim, clear of the zoom buttons and the clock
MinimapButton.SIZE = 31
MinimapButton.DRAG_GRACE = 0.25 -- seconds after a drag in which a click is the drag's own mouse-up
MinimapButton.RIM = 10 -- beyond the minimap's radius
-- the TOC's IconTexture: the addon's own 字 medallion (Media/icon.tga)
MinimapButton.ICON = "Interface\\AddOns\\WoWForeverJapanese\\Media\\icon"
MinimapButton.button = nil
MinimapButton.db = nil

local function angle()
  local m = MinimapButton.db and MinimapButton.db.minimap
  local a = m and tonumber(m.angle)
  return a or MinimapButton.DEFAULT_ANGLE
end
MinimapButton.angle = angle

-- Places the button on the rim at `deg` degrees (0 = right, counter-clockwise).
function MinimapButton.place(deg)
  local b, map = MinimapButton.button, C.resolve("Minimap")
  if not (b and map) then return end
  local r = (map:GetWidth() or 140) / 2 + MinimapButton.RIM
  local rad = math.rad(deg)
  b:ClearAllPoints()
  b:SetPoint("CENTER", map, "CENTER", math.cos(rad) * r, math.sin(rad) * r)
end

-- Saves the angle (created only once the player moves the button: an untouched WFJ_DB keeps its shape).
function MinimapButton.setAngle(deg)
  deg = deg % 360
  if MinimapButton.db then
    MinimapButton.db.minimap = MinimapButton.db.minimap or {}
    MinimapButton.db.minimap.angle = deg
  end
  MinimapButton.place(deg)
  return deg
end

-- The cursor's angle around the minimap's centre, in degrees.
function MinimapButton.cursorAngle()
  local map = C.resolve("Minimap")
  local getCursor = C.resolve("GetCursorPosition")
  if not (map and getCursor) then return angle() end
  local mx, my = map:GetCenter()
  local px, py = getCursor()
  local scale = map:GetEffectiveScale()
  px, py = px / scale, py / scale
  return math.deg(math.atan2(py - my, px - mx)) % 360
end

-- The button's copy in one language, like the fix window: Japanese, or English while the reveal key is held.
local function tx(key)
  local en, ja = Text.get(key)
  if WFJ.State ~= nil and WFJ.State.enabled == false then return en end -- translation off: English, like the game
  if WFJ.Modifier ~= nil and WFJ.Modifier.isDown() == true then return en end
  return ja
end

-- ── Tooltip ─────────────────────────────────────────────────────────────────

local tip
function MinimapButton.showTooltip(owner)
  tip = tip or CreateFrame("GameTooltip", "WFJMinimapTooltip", C.resolve("UIParent"), "GameTooltipTemplate")
  local text = tx("minimap.tip")
  tip:SetOwner(owner, "ANCHOR_LEFT")
  tip:SetText("WoW Forever Japanese", 1, 0.82, 0)
  tip:AddLine(text, 1, 1, 1)
  local line = C.resolve("WFJMinimapTooltipTextLeft2")
  if line then W.setText(line, text, 12) end
  tip:Show()
  return tip
end

function MinimapButton.hideTooltip()
  if tip then tip:Hide() end
end

-- ── Menu ────────────────────────────────────────────────────────────────────

local function bundled(frame)
  local fs = type(frame) == "table" and frame.fontString or nil
  if type(fs) ~= "table" or not WFJ.Labels then return end
  local a = WFJ.Labels.menuText(fs)
  if not a then return end
  local _, size, flags = a:GetFont()
  WFJ.Font.set(a, WFJ.Font.PATH, size or WFJ.Font.DEFAULT_SIZE, flags or "")
end


-- The menu, as data (the specs read it): { kind, text, isSelected?, action }.
function MinimapButton.items()
  return {
    { kind = "checkbox", text = tx("minimap.enabled"),
      isSelected = function() return S.get("enabled") == true end,
      action = function() S.set("enabled", not S.get("enabled")) end },
    { kind = "button", text = tx("button.reportLine"), action = function() WFJ.FixWindow.open() end },
    { kind = "button", text = tx("button.settings"), action = function() C.openOptions() end },
    { kind = "button", text = tx("minimap.hide"), action = function() S.set("minimapButton", false) end },
  }
end

function MinimapButton.generator(_, root)
  root:CreateTitle("WoW Forever Japanese")
  for _, item in ipairs(MinimapButton.items()) do
    local el
    if item.kind == "checkbox" then
      el = root:CreateCheckbox(item.text, item.isSelected, item.action)
    else
      el = root:CreateButton(item.text, item.action)
    end
    if el and el.AddInitializer then el:AddInitializer(bundled) end
    -- a divider between the on / off toggle and the actions, as the client's own menus separate them [verified:
    -- MenuUtil.CreateDivider Blizzard_Menu/MenuUtil.lua:270, rootDescription:CreateDivider()
    -- 11_0_0_MenuImplementationGuide.lua:411]
    if item.kind == "checkbox" and root.CreateDivider then root:CreateDivider() end
  end
end

function MinimapButton.openMenu(owner)
  local MU = C.resolve("MenuUtil")
  if not (MU and MU.CreateContextMenu) then return false end
  MU.CreateContextMenu(owner, MinimapButton.generator)
  return true
end

-- One click (the button's, or the addon dropdown's): right opens the menu, anything else the fix window.
function MinimapButton.click(owner, mouseButton)
  if mouseButton == "RightButton" then return MinimapButton.openMenu(owner) end
  WFJ.FixWindow.open()
  return true
end

-- ── Button ──────────────────────────────────────────────────────────────────

local function build()
  local map = C.resolve("Minimap")
  if not map then return nil end
  local b = CreateFrame("Button", "WFJMinimapButton", map, "MiniMapButtonTemplate")
  b:SetSize(MinimapButton.SIZE, MinimapButton.SIZE)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(map:GetFrameLevel() + 8)
  -- The classic gold ring around the 字 medallion. Forever's HUD minimap buttons (a ui-hud-minimap-button disc,
  -- Blizzard_Minimap/Mainline/Minimap.xml:60–95) read in game as a dark square behind an art icon; the ring suits a
  -- round art icon.
  local icon = b:CreateTexture("WFJMinimapButtonIcon", "ARTWORK") -- the template's press offset moves `<name>Icon`
  icon:SetTexture(MinimapButton.ICON)
  -- in MiniMap-TrackingBorder's hole, which sits toward the texture's top-left: Blizzard's tracking button draws the
  -- border 64×64 at TOPLEFT and its icon 24×24 at CENTER +2, -2 of a 33×33 frame [verified: wow-ui-source
  -- Blizzard_Minimap/Classic/MinimapTracking_Simple.xml]; scaled to our 52 px border (×0.8125): 20×20 at 5, -5
  icon:SetSize(20, 20)
  icon:SetPoint("TOPLEFT", 5, -5)
  b.icon = icon
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(52, 52)
  border:SetPoint("TOPLEFT", 0, 0)
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetScript("OnClick", function(self, mouseButton)
    -- the mouse-up that ends a drag is not a click: a click within DRAG_GRACE seconds of the drag's end is dropped;
    -- the flag is time-based, so a client that sends no click after a drag never swallows the next one
    local stop = self.dragStoppedAt
    self.dragStoppedAt = nil
    if stop and (GetTime() - stop) <= MinimapButton.DRAG_GRACE then return end
    MinimapButton.click(self, mouseButton)
  end)
  b:SetScript("OnDragStart", function(self)
    MinimapButton.hideTooltip()
    self:SetScript("OnUpdate", function() MinimapButton.place(MinimapButton.cursorAngle()) end)
  end)
  b:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    MinimapButton.setAngle(MinimapButton.cursorAngle())
    self.dragStoppedAt = GetTime()
  end)
  b:SetScript("OnEnter", function(self) MinimapButton.showTooltip(self) end)
  b:SetScript("OnLeave", function() MinimapButton.hideTooltip() end)
  return b
end

-- Shows or hides the button per the setting.
function MinimapButton.refresh()
  local b = MinimapButton.button
  if not b then return end
  if S.get("minimapButton") then
    MinimapButton.place(angle())
    b:Show()
  else
    b:Hide()
  end
end

-- Main.lua, after the settings loaded. `db`: the live WFJ_DB.
function MinimapButton.init(db)
  MinimapButton.db = db
  MinimapButton.button = MinimapButton.button or build()
  MinimapButton.refresh()
  return MinimapButton.button
end

WFJ.State.on("minimapButton", function() MinimapButton.refresh() end)
