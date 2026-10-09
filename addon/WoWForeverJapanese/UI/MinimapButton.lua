-- UI/MinimapButton.lua: the fix-report minimap button, a small button on the minimap's edge. Left-click opens the
-- fix window; right-click opens a menu with translation on / off (the master switch, the same state as the settings
-- checkbox), report a line, report a bug or idea, send collected English (only while some waits), settings, hide
-- this button. Drag moves it around the rim; the angle is kept in
-- WFJ_DB.minimap (absent → DEFAULT_ANGLE). The `minimapButton` setting (default on) shows or hides it; "Hide this
-- button" turns that setting off, and the settings page or `/wfj minimapButton on` brings it back. Blizzard's addon
-- dropdown on the minimap gets the same two actions through the TOC's AddonCompartmentFunc (Main.lua's globals), so
-- a hidden button never locks anyone out.
-- Forever (camelot) sources [verified: forever-ui-1.60.1.70009:
--   MiniMapButtonTemplate Blizzard_Minimap/Shared/MinimapButtonTemplate.xml (press offset on the `<name>Icon`
--     texture, MinimapButtonTemplate.lua), listed for camelot in Blizzard_Minimap.toc;
--   the Minimap frame Blizzard_Minimap/Mainline/Minimap.xml:195 ([Family] loads for camelot);
--   TooltipBackdropTemplate Blizzard_SharedXML/SharedTooltipTemplates.xml, for the menu's frame;
--   AddonCompartmentFunc / …FuncOnEnter / …FuncOnLeave, called (addonName, buttonName | frame)
--     Blizzard_Minimap/Mainline/AddonCompartment.lua:77–117].
-- The rim is placed for a round minimap [unverified: camelot's minimap shape; no GetMinimapShape in its FrameXML].
-- Menu rows take the bundled font through OptionsWidgets.setText, like the settings page.
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
-- Name, version, the collector's count of lines that ship no Japanese yet (only when there are some, never their
-- text, the same count as the menu's send entry), then how to use the button.
function MinimapButton.showTooltip(owner)
  tip = tip or CreateFrame("GameTooltip", "WFJMinimapTooltip", C.resolve("UIParent"), "GameTooltipTemplate")
  tip:SetOwner(owner, "ANCHOR_LEFT")
  tip:SetText("WoW Forever Japanese", 1, 0.82, 0)
  local lines = { { tx("minimap.version"):format(tostring(WFJ.VERSION)), 0.6, 0.6, 0.6 } }
  local ok, status = pcall(function() return WFJ.Collector.status() end)
  if ok and type(status) == "table" and not status.readOnly and (status.unsent or 0) > 0 then
    lines[#lines + 1] = { tx("minimap.collected"):format(status.unsent), 0.25, 1, 0.25 }
  end
  lines[#lines + 1] = { tx("minimap.tip"), 1, 1, 1 }
  for i, l in ipairs(lines) do
    tip:AddLine(l[1], l[2], l[3], l[4], true)
    local fs = C.resolve("WFJMinimapTooltipTextLeft" .. (i + 1))
    if fs then W.setText(fs, l[1], 12) end
  end
  tip:Show()
  return tip
end

function MinimapButton.hideTooltip()
  if tip then tip:Hide() end
end

-- ── Menu ────────────────────────────────────────────────────────────────────

-- The menu, as data (the specs read it): { kind, text, isSelected?, action }.
-- The send entry shows the collector's unsent count and only while there is one to send.
function MinimapButton.items()
  local items = {
    { kind = "checkbox", text = tx("minimap.enabled"),
      isSelected = function() return S.get("enabled") == true end,
      action = function() S.set("enabled", not S.get("enabled")) end },
    { kind = "button", text = tx("button.reportLine"), action = function() WFJ.FixWindow.open() end },
    { kind = "button", text = tx("button.reportBug"), action = function() WFJ.ReportWindow.open() end },
  }
  -- guarded: the menu is the main way to report a line and must open even if the collector cannot answer
  local ok, status = pcall(function() return WFJ.Collector.status() end)
  if ok and type(status) == "table" and not status.readOnly and (status.unsent or 0) > 0
      and WFJ.CollectorSendWindow then
    items[#items + 1] = { kind = "button", text = tx("minimap.sendEnglish"):format(status.unsent),
      action = function() WFJ.CollectorSendWindow.open(false) end }
  end
  items[#items + 1] = { kind = "button", text = tx("button.settings"), action = function() C.openOptions() end }
  items[#items + 1] = { kind = "button", text = tx("minimap.hide"),
    action = function() S.set("minimapButton", false) end }
  return items
end

-- The menu is a small frame of the addon's own, not Blizzard's Menu: opening a Blizzard context menu from this
-- button can fail a Lua engine check in Menu.lua's AcquireMenu (writing the owner onto the pooled menu frame) and
-- close the game. Rows: the title, the switch with its check mark, a divider, the actions. A click
-- on a row runs it and closes the menu; a click anywhere else, or another right-click on the button, closes it.
MinimapButton.ROW_HEIGHT = 20
MinimapButton.MENU_WIDTH = 210 -- the least width; showMenu widens it for a longer label
local menuFrame

local function closeMenu()
  if menuFrame then menuFrame:Hide() end
end
MinimapButton.closeMenu = closeMenu

local function menuRow(parent, y, onClick)
  local row = CreateFrame("Button", nil, parent)
  row:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)
  row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, y)
  row:SetHeight(MinimapButton.ROW_HEIGHT)
  row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.text:SetPoint("LEFT", row, "LEFT", 22, 0)
  row:SetScript("OnClick", onClick)
  return row
end

local function buildMenu()
  local f = CreateFrame("Frame", "WFJMinimapMenu", C.resolve("UIParent"), "TooltipBackdropTemplate")
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:Hide()
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
  f.title:SetText("WoW Forever Japanese")
  f.rows = {}
  f:RegisterEvent("GLOBAL_MOUSE_DOWN")
  f:SetScript("OnEvent", function(self)
    if self:IsShown() and not self:IsMouseOver() and not (MinimapButton.button and MinimapButton.button:IsMouseOver())
    then
      self:Hide()
    end
  end)
  return f
end

-- Fills the menu from MinimapButton.items() and shows it under `owner`. → the menu frame
function MinimapButton.showMenu(owner)
  menuFrame = menuFrame or buildMenu()
  local f = menuFrame
  local items = MinimapButton.items()
  local y = -10 - MinimapButton.ROW_HEIGHT
  for i, item in ipairs(items) do
    local row = f.rows[i]
    if not row then
      row = menuRow(f, y, function(self)
        closeMenu()
        if self.item and self.item.action then self.item.action() end
      end)
      f.rows[i] = row
    end
    row.item = item
    W.setText(row.text, item.text, 12)
    if item.kind == "checkbox" then
      row.check = row.check or row:CreateTexture(nil, "ARTWORK")
      row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
      row.check:SetSize(18, 18)
      row.check:SetPoint("LEFT", row, "LEFT", 0, 0)
      if item.isSelected() == true then row.check:Show() else row.check:Hide() end
      y = y - MinimapButton.ROW_HEIGHT
      f.divider = f.divider or f:CreateTexture(nil, "ARTWORK")
      f.divider:SetColorTexture(1, 1, 1, 0.2)
      f.divider:SetHeight(1)
      f.divider:ClearAllPoints()
      f.divider:SetPoint("TOPLEFT", f, "TOPLEFT", 12, y - 4)
      f.divider:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, y - 4)
      y = y - 8
    else
      y = y - MinimapButton.ROW_HEIGHT
    end
    local nextRow = f.rows[i + 1]
    if nextRow then
      nextRow:ClearAllPoints()
      nextRow:SetPoint("TOPLEFT", f, "TOPLEFT", 8, y)
      nextRow:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, y)
    end
    row:Show()
  end
  for i = #items + 1, #f.rows do f.rows[i]:Hide() end
  -- at least MENU_WIDTH, wider when a label (a long unsent count, the English labels) needs it: the rows' text has
  -- no right anchor and would run past the border; 8 + 22 on the left of the text, 8 + 10 on its right
  local width = MinimapButton.MENU_WIDTH
  for i = 1, #items do
    local text = f.rows[i].text
    local w = type(text.GetStringWidth) == "function" and text:GetStringWidth() or nil
    if type(w) == "number" and w + 48 > width then width = math.ceil(w + 48) end
  end
  f:SetSize(width, -y + 10)
  f:ClearAllPoints()
  if owner then
    f:SetPoint("TOPRIGHT", owner, "BOTTOMLEFT", 0, 0)
  else -- from the addon dropdown on the minimap: at the cursor, as a context menu opens
    local ui, cursor = C.resolve("UIParent"), C.resolve("GetCursorPosition")
    local cx, cy = 0, 0
    if type(cursor) == "function" and ui then
      local scale = ui:GetEffectiveScale()
      cx, cy = cursor()
      cx, cy = cx / scale, cy / scale
    end
    f:SetPoint("TOPLEFT", ui, "BOTTOMLEFT", cx, cy)
  end
  f:Show()
  return f
end

function MinimapButton.openMenu(owner)
  if menuFrame and menuFrame:IsShown() then
    closeMenu()
    return true
  end
  MinimapButton.hideTooltip()
  MinimapButton.showMenu(owner)
  return true
end

-- One click (the button's, or the addon dropdown's): right opens the menu, anything else the fix window.
function MinimapButton.click(owner, mouseButton)
  if mouseButton == "RightButton" then return MinimapButton.openMenu(owner) end
  closeMenu()
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
