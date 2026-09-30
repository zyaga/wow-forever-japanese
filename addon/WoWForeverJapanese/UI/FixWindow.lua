-- UI/FixWindow.lua: the fix window (docs/systems/fix-reports.md): a player picks a line the addon just
-- showed, says what is wrong (and may write their own Japanese), and later copies every pending fix out as one
-- report for the issue form. Mouse only: every step is a click; typing is only in the optional note and Japanese.
-- Pages: Translations (Core/RecentLines) · Pending (Core/Reports) · Send report (Core/ReportText), and the
-- edit panel a row opens. Every label is the addon's own copy (UI/OptionsText) in ONE language: Japanese, or the
-- copy's English while the reveal key is held or translation is off, the game text's toggle (both at once was too
-- hard to read in game). The window shows Japanese lines and never any English game text (the addon never ships
-- stored English; English on screen is always what the client shows now): it reads lines only through
-- Core/RecentLines, Core/Reports and Core/Lookup, never a frame, a global string or the Collector.
-- Confirming a replace or a clear is the settings pages' in-place "click again" (UI/Options collectorClear): our
-- Japanese in Blizzard's StaticPopup font is unverified.
-- Forever (camelot) FrameXML, each cited where it is used: ButtonFrameTemplate (the window), TabSystemTemplate (the
-- tabs), UIRadialButtonTemplate (the filters and reasons), UIPanelButtonTemplate (buttons); the list and the text
-- fields are OptionsWidgets' scrollList / scrollText.
-- Entry points call FixWindow.open(): /wfj fix, the About page's button and the minimap button.
local _, WFJ = ...
local FixWindow = {}
WFJ.FixWindow = FixWindow

local W, Text = WFJ.OptionsWidgets, WFJ.OptionsText
local WIDTH, HEIGHT, LEFT = 600, 580, 16
local INNER = WIDTH - 2 * LEFT
local ROWS, ROW_H, LEFT_COL = 12, 32, 130
local PREVIEW = 108 -- bytes of Japanese a row shows (about 36 characters: the row's width at 11 px)
local CONFIRM_SECONDS = 5

FixWindow.frame = nil
FixWindow.pages = {}
FixWindow.current = nil -- "recent" | "pending" | "copy" | "edit"
FixWindow.filter = "all" -- the recent-lines group shown: story · tooltips · windows · all
FixWindow.edit = nil -- the line the edit panel holds: { type, id, field, ja_hash, ja, pending = index? }

local KEYED = { gossip = true, book = true }

local function now()
  return type(GetTime) == "function" and GetTime() or 0
end

-- The player's own name, which Core/Reports keeps out of a saved fix. Not when the stored line itself holds
-- that word: then it is a game name (a creature or place called like the player), and it must stay as written.
local function playerName(storedJa)
  local name = type(UnitName) == "function" and UnitName("player") or nil
  if name == _G.UNKNOWNOBJECT then return nil end
  if name and WFJ.Reports.mentions(storedJa or "", name) then return nil end
  return name
end

-- The Lookup kind of a store address (the reverse of RecentLines.address).
local function kindOf(type_, field)
  if KEYED[type_] then return type_ end
  return type_ .. "." .. field
end
FixWindow.kindOf = kindOf

-- The Japanese the addon ships for an address now, or nil.
local function storedJa(type_, id, field)
  local entry = WFJ.Lookup.get(kindOf(type_, field), id)
  return entry and type(entry.ja) == "string" and entry.ja or nil
end

-- Cut at `n` bytes without splitting a UTF-8 character; "…" when cut. Newlines read as spaces in a row.
local function preview(s)
  s = (s or ""):gsub("\r", ""):gsub("\n", " ")
  if #s <= PREVIEW then return s end
  local cut = PREVIEW
  while cut > 0 and s:byte(cut + 1) and s:byte(cut + 1) >= 128 and s:byte(cut + 1) < 192 do cut = cut - 1 end
  return s:sub(1, cut) .. "…"
end

-- The window's language: Japanese, or English while the reveal key is held.
-- English when translation is off (the master switch) or the reveal key is held, the game text's own rule.
local function revealHeld()
  if WFJ.State ~= nil and WFJ.State.enabled == false then return true end
  return WFJ.Modifier ~= nil and WFJ.Modifier.isDown() == true
end
FixWindow.revealHeld = revealHeld

local function tx(key, ...)
  local en, ja = Text.get(key, ...)
  if revealHeld() then return en end
  return ja
end
FixWindow.tx = tx

-- Labels and buttons whose copy never changes, re-set when the language flips (FixWindow.relabel).
local statics = {}
local function label(parent, key, x, y, width)
  local l = W.label(parent, "", "", x, y, width)
  statics[#statics + 1] = { label = l, key = key }
  return l
end
-- The window writes all of its own copy in the bundled font at fixed sizes, English or Japanese: letting each string
-- keep the font it had before the language flipped left buttons and rows at mixed sizes.
local function put(fs, text, size)
  fs:SetText(text or "")
  WFJ.Font.set(fs, WFJ.Font.PATH, size, "")
end
local function setLabel(l, text)
  W.setPair(l, text) -- one text: shown as is, and kept through W.relabel
end
-- A button's caption: set, re-fonted, and the button re-sized to fit it (as W.button's setLabel does).
local function caption(b, text)
  b:setLabel(text or "")
  WFJ.Font.set(b.caption, WFJ.Font.PATH, 11, "")
  local w = b.caption.GetStringWidth and b.caption:GetStringWidth()
  if w and b.SetWidth then b:SetWidth(math.max(b.minWidth or 0, math.ceil(w) + 2 * W.BUTTON_PAD)) end
end
local function button(parent, key, width, onClick)
  local b = W.button(parent, "", nil, width, onClick)
  statics[#statics + 1] = { button = b, key = key }
  return b
end

-- A radio button with its label (pick-one choices: the filter row, the reasons), the label clickable too; the
-- click always checks it (a radio is never unticked by a second click) and calls onPick. [verified:
-- UIRadialButtonTemplate (the newer radio art the modern menus use) Blizzard_SharedXML/Shared/Button/
-- CheckButtonTemplates.xml:26 (18 px, atlas common-dropdown-tickradial, `.text`), loaded unconditionally:
-- Blizzard_SharedXML.toc:70]
local function radio(parent, key, x, y, onPick)
  local b = CreateFrame("CheckButton", nil, parent, "UIRadialButtonTemplate")
  b:SetPoint("TOPLEFT", x, y)
  b.text = b.text or b:CreateFontString(nil, "BACKGROUND")
  b:SetScript("OnClick", function(self) self:SetChecked(true); onPick() end)
  statics[#statics + 1] = { radio = b, key = key }
  return b
end

-- The line's type in the window's language (a row's left column).
local function typeLabel(type_)
  if not Text.T["type." .. type_] then return type_ end
  return tx("type." .. type_)
end

local function build()
  local UIParent = WFJ.Compat.resolve("UIParent")
  -- the client's current window frame: title bar, a 60 px strip for the tabs, an inset panel
  -- [verified: ButtonFrameTemplate Blizzard_SharedXML/Mainline/
  -- SharedUIPanelTemplates.xml:711 (Inset TOPLEFT 4,-60 / BOTTOMRIGHT -6,26), ButtonFrameTemplate_HidePortrait
  -- SharedUIPanelTemplates.lua:111, SetTitle / GetTitleText PortraitFrame.lua:4–28; camelot's FriendsFrame and
  -- AddonList use it]
  local f = CreateFrame("Frame", "WFJFixWindow", UIParent, "ButtonFrameTemplate")
  ButtonFrameTemplate_HidePortrait(f)
  f:SetSize(WIDTH, HEIGHT)
  f:SetPoint("CENTER")
  -- above the client's own overlays (the beta's Issue Reporter button sits over DIALOG)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetToplevel(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  -- Esc closes it like the client's own panels [verified: UISpecialFrames + CloseSpecialWindows,
  -- Blizzard_UIParentPanelManager/Shared/UIParentPanelManager.lua:1106]
  local special = WFJ.Compat.resolve("UISpecialFrames")
  if type(special) == "table" then special[#special + 1] = "WFJFixWindow" end
  f:SetTitle("")
  f.title = f:GetTitleText()
  f:Hide()

  -- tabs: the client's own tab widget, hanging off the window's top edge
  -- [verified: TabSystemTemplate / TabSystemTopButtonTemplate, Blizzard_SharedXML/Shared/TabSystem/
  -- TabSystemTemplates.{xml,lua} are loaded for camelot: Blizzard_SharedXML.toc:131–134 exclude only vanilla, tbc;
  -- camelot's FriendsFrame uses it]. Its pool is rebuilt for the top-hanging button (tabTemplate is read at OnLoad).
  local ts = CreateFrame("Frame", nil, f, "TabSystemTemplate")
  ts.tabTemplate = "TabSystemTopButtonTemplate"
  ts.tabPool = CreateFramePool("BUTTON", ts, "TabSystemTopButtonTemplate")
  ts.minTabWidth = 100
  ts:SetPoint("BOTTOMLEFT", f.Inset, "TOPLEFT", 10, -2) -- in the strip above the inset
  f.tabSystem = ts
  f.tabs, f.tabIDs = {}, {}
  local byID = {}
  for _, id in ipairs({ "recent", "pending", "copy" }) do
    local tabID = ts:AddTab("")
    local t = ts:GetTabButton(tabID)
    t.caption = t.Text
    f.tabs[id], f.tabIDs[id], byID[tabID] = t, tabID, id
  end
  -- a click shows the page; show() sets the visual selection itself (true = suppress the widget's own)
  ts:SetTabSelectedCallback(function(tabID) FixWindow.show(byID[tabID]); return true end)
  -- selecting swaps each tab's font object back to the client's (Latin-only) font: put ours back after
  hooksecurefunc(ts, "SetTabVisuallySelected", function() FixWindow.fontTabs() end)
  f.message = W.fontString(f, "GameFontHighlightSmall", "", LEFT, -HEIGHT + 28, INNER, 11)
  f.message:SetTextColor(W.GOLD[1], W.GOLD[2], W.GOLD[3])

  local function page()
    local p = CreateFrame("Frame", nil, f)
    p:SetPoint("TOPLEFT", 0, -72) -- a margin under the inset's top edge
    p:SetSize(WIDTH, HEIGHT - 90)
    p:Hide()
    return p
  end
  local P = FixWindow.pages

  -- Translations (the recent lines)
  P.recent = page()
  label(P.recent, "fix.recent.explain", LEFT, -4, INNER)
  -- All first; each option follows the previous one's label, so they sit evenly whatever
  -- the language
  P.recent.filters = {}
  local prev
  for _, id in ipairs({ "all", "story", "tooltips", "windows" }) do
    local b = radio(P.recent, "fix.filter." .. id, LEFT + 4, -32, function() FixWindow.setFilter(id) end)
    if prev then
      b:ClearAllPoints()
      b:SetPoint("LEFT", prev.text, "RIGHT", 18, 0)
    end
    P.recent.filters[id], prev = b, b
  end
  P.recent.empty = W.label(P.recent, "", "", LEFT, -64, INNER)
  P.recent.list = W.scrollList(P.recent, LEFT, -60, INNER, ROWS * ROW_H, ROW_H, LEFT_COL, function(item)
    FixWindow.openEdit(item.line)
  end)

  -- Pending fixes
  P.pending = page()
  label(P.pending, "fix.pending.explain", LEFT, -4, INNER)
  P.pending.empty = W.label(P.pending, "", "", LEFT, -32, INNER)
  P.pending.list = W.scrollList(P.pending, LEFT, -28, INNER, ROWS * ROW_H, ROW_H, LEFT_COL, function(_, index)
    FixWindow.openPending(index)
  end)

  -- Send report
  P.copy = page()
  -- in the order the player does it: 1 open the form, 2 copy the report, 3 paste and
  -- submit, 4 clear what was sent. With nothing saved the steps give way to how to save one.
  P.copy.empty = W.label(P.copy, "", "", LEFT, -4, INNER)
  P.copy.steps = CreateFrame("Frame", nil, P.copy)
  P.copy.steps:SetAllPoints()
  local S = P.copy.steps
  label(S, "fix.copy.step1", LEFT, -4, INNER)
  P.copy.url = W.copyBox(S, LEFT, -26, INNER - 12, Text.FIX_URL)
  label(S, "fix.copy.step2", LEFT, -60, INNER)
  P.copy.report = W.scrollText(S, LEFT, -84, INNER, 250)
  label(S, "fix.copy.step3", LEFT, -346, INNER)
  label(S, "fix.copy.step4", LEFT, -380, 280) -- the button sits on the same line, after the text
  P.copy.clear = W.button(S, "", nil, 200, function() FixWindow.clearSent() end)
  P.copy.clear:SetPoint("TOPLEFT", LEFT + 290, -375)
  P.copy:HookScript("OnHide", function() FixWindow.clearArmed = nil end)

  -- Edit panel
  P.edit = page()
  local E = P.edit
  -- one box: the line as the addon ships it, which the player may rewrite (a read-only copy above
  -- an editable copy would be two walls of the same text). The report carries the hash of the shipped line, so the
  -- pipeline has the before; only a changed line travels as the after.
  label(E, "fix.edit.ja", LEFT, -4, INNER)
  E.ja = W.scrollText(E, LEFT, -28, INNER, 248, { editable = true, maxBytes = WFJ.Reports.JA_MAX })
  label(E, "fix.edit.reason", LEFT, -286, INNER)
  E.reasons = {}
  for i, r in ipairs(WFJ.Reports.REASONS) do
    local col, rowN = (i - 1) % 3, math.floor((i - 1) / 3)
    E.reasons[r] = radio(E, "reason." .. r, LEFT + 4 + col * 190, -312 - rowN * 26, function()
      FixWindow.pickReason(r)
    end)
  end
  label(E, "fix.edit.note", LEFT, -370, INNER)
  -- a few rows to write in; Enter leaves the box (a note is one line in the report; ReportText refuses a newline)
  E.noteBox = W.scrollText(E, LEFT, -390, INNER, 40, { editable = true, maxBytes = WFJ.Reports.NOTE_MAX })
  E.note = E.noteBox.box
  E.note:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  E.save = button(E, "button.saveFix", 150, function() FixWindow.save() end)
  E.save:SetPoint("TOPLEFT", LEFT, -440)
  E.delete = button(E, "button.delete", 90, function() FixWindow.deletePending() end)
  E.delete:SetPoint("LEFT", E.save, "RIGHT", 8, 0)
  E.back = button(E, "button.back", 90, function() FixWindow.show(FixWindow.edit and FixWindow.edit.pending
    and "pending" or "recent") end)
  E.back:SetPoint("TOPRIGHT", -LEFT, -440)

  FixWindow.frame = f
  return f
end

local function say(key, ...)
  if not FixWindow.frame then return end
  FixWindow.message = key and { key = key, n = select("#", ...), ... } or nil
  if key == nil then return put(FixWindow.frame.message, "", 11) end
  put(FixWindow.frame.message, tx(key, ...), 11)
end
FixWindow.say = say

-- Each tab's text in the bundled font, sized to fit, and the row re-laid out.
function FixWindow.fontTabs()
  local f = FixWindow.frame
  if not (f and f.tabs) then return end
  for _, t in pairs(f.tabs) do
    put(t.Text, t.tabText or "", 12)
    if t.UpdateTabWidth then t:UpdateTabWidth() end
  end
  if f.tabSystem.MarkDirty then f.tabSystem:MarkDirty() end
end

local function refreshTabs()
  local tabs = FixWindow.frame.tabs
  tabs.recent.tabText = tx("fix.tab.recent")
  tabs.pending.tabText = tx("fix.tab.pending", WFJ.Reports.count())
  tabs.copy.tabText = tx("fix.tab.copy")
  FixWindow.fontTabs()
end

local function refreshRecent()
  local P = FixWindow.pages.recent
  local items = {}
  for id, b in pairs(P.filters) do b:SetChecked(id == FixWindow.filter) end
  for _, line in ipairs(WFJ.RecentLines.list(FixWindow.filter)) do
    -- an empty `shown` (a line written blank) falls back to the stored Japanese rather than a blank row
    local shown = (line.shown ~= nil and line.shown ~= "") and line.shown or line.ja
    items[#items + 1] = { left = typeLabel(line.type), text = preview(shown), line = line }
  end
  P.list:setItems(items)
  setLabel(P.empty, #items == 0 and tx("fix.recent.empty") or "")
end

local function refreshPending()
  local P = FixWindow.pages.pending
  local items = {}
  for _, fix in ipairs(WFJ.Reports.list()) do
    local shown = fix.ja or storedJa(fix.type, fix.id, fix.field) or fix.note or ""
    -- the reason under the type (left), the Japanese beside them: two lines each fit a row
    items[#items + 1] = { left = typeLabel(fix.type) .. "\n" .. tx("reason." .. fix.reason), text = preview(shown) }
  end
  P.list:setItems(items)
  setLabel(P.empty, #items == 0 and tx("fix.pending.empty") or "")
end

-- The report text for the pending fixes, as ReportText writes it.
function FixWindow.reportText()
  local client = "?"
  if type(GetBuildInfo) == "function" then
    local v, b = GetBuildInfo()
    if type(v) == "string" and b ~= nil then client = v .. "." .. tostring(b) end
  end
  return WFJ.ReportText.serialize(WFJ.VERSION or "?", client, WFJ.Reports.list())
end

local function refreshCopy()
  local P = FixWindow.pages.copy
  local n = WFJ.Reports.count()
  setLabel(P.empty, n == 0 and tx("fix.copy.empty") or "")
  if n == 0 then P.steps:Hide() else P.steps:Show() end
  P.report:setText(n == 0 and "" or FixWindow.reportText())
  -- the addresses this report holds: Clear removes these and nothing saved after
  FixWindow.sent = {}
  for _, f in ipairs(WFJ.Reports.list()) do
    FixWindow.sent[#FixWindow.sent + 1] = { type = f.type, id = f.id, field = f.field }
  end
  if not FixWindow.clearArmed then caption(P.clear, tx("button.clearSent")) end
  P.clear:setEnabled(n > 0)
  if n > 0 then P.report.focusAll() end
end

-- Re-sets every label in the current language (Japanese, or English while the reveal key is held). The lists and the
-- copy page's text are re-drawn; the copy box keeps its text and selection.
function FixWindow.relabel()
  local f = FixWindow.frame
  if not f then return end
  put(f.title, tx("fix.title"), 13)
  for _, st in ipairs(statics) do
    if st.label then setLabel(st.label, tx(st.key))
    elseif st.radio then
      put(st.radio.text, tx(st.key), 12)
      -- the clickable area is the circle plus its own label, exactly: a fixed width overlapped the next option
      -- when they sit close (clicks landed on the neighbour)
      local w = st.radio.text.GetStringWidth and st.radio.text:GetStringWidth() or 0
      if st.radio.SetHitRectInsets then st.radio:SetHitRectInsets(0, -(w + 8), -3, -3) end
    else caption(st.button, tx(st.key)) end
  end
  refreshTabs()
  if FixWindow.current == "recent" then refreshRecent()
  elseif FixWindow.current == "pending" then refreshPending()
  elseif FixWindow.current == "copy" then
    local P = FixWindow.pages.copy
    setLabel(P.empty, WFJ.Reports.count() == 0 and tx("fix.copy.empty") or "")
    if not FixWindow.clearArmed then caption(P.clear, tx("button.clearSent")) end
  end
  local m = FixWindow.message
  if m then put(f.message, tx(m.key, unpack(m, 1, m.n)), 11) end
end

-- A line recorded while the list is open shows up without reopening: the window marks itself dirty and redraws
-- once, on its next frame (a burst of lines is one redraw). Its OnUpdate is set only while dirty; no polling.
local function redrawSoon()
  local f = FixWindow.frame
  if not (f and f:IsShown() and FixWindow.current == "recent") then return end
  f:SetScript("OnUpdate", function(self)
    self:SetScript("OnUpdate", nil)
    if self:IsShown() and FixWindow.current == "recent" then refreshRecent() end
  end)
end
FixWindow.redrawSoon = redrawSoon
WFJ.RecentLines.onChange = redrawSoon

local function relabelIfShown()
  if FixWindow.frame and FixWindow.frame:IsShown() then FixWindow.relabel() end
end
WFJ.State.on("modifier", relabelIfShown)
WFJ.State.on("enabled", relabelIfShown)

-- Shows one page (and the window). id: "recent" | "pending" | "copy" | "edit".
function FixWindow.show(id)
  local f = FixWindow.frame or build()
  -- the edit panel keeps the tab it was opened from selected
  if f.tabIDs[id] then f.tabSystem:SetTabVisuallySelected(f.tabIDs[id]) end
  for pid, p in pairs(FixWindow.pages) do
    if pid ~= id then p:Hide() end
  end
  FixWindow.current = id
  if id ~= "edit" then FixWindow.armed = nil end
  FixWindow.relabel()
  say(nil)
  if id == "recent" then refreshRecent()
  elseif id == "pending" then refreshPending()
  elseif id == "copy" then refreshCopy() end
  FixWindow.pages[id]:Show()
  f:Show()
  return f
end

-- Which group of recent lines the list shows ("story" · "tooltips" · "windows" · "all").
function FixWindow.setFilter(id)
  FixWindow.filter = id
  if FixWindow.current == "recent" then refreshRecent() end
end

-- The one entry point: /wfj fix, the About page's button, the minimap button.
function FixWindow.open(id)
  return FixWindow.show(id or "recent")
end

function FixWindow.pickReason(r)
  local e = FixWindow.edit
  if not e then return end
  e.reason = r
  for id, cb in pairs(FixWindow.pages.edit.reasons) do cb:SetChecked(id == r) end
end

local function loadEdit(line, fix)
  FixWindow.show("edit")
  local E = FixWindow.pages.edit
  FixWindow.edit = { type = line.type, id = line.id, field = line.field, ja_hash = line.ja_hash, ja = line.ja,
    pending = fix and fix.index or nil }
  FixWindow.armed = nil
  E.ja:setText((fix and fix.ja) or line.ja or "")
  E.note:SetText((fix and fix.note) or "")
  FixWindow.pickReason(fix and fix.reason or nil)
  if fix and fix.index then E.delete:Show() else E.delete:Hide() end
end

-- A recent line → the edit panel for exactly that address. A line that already has a pending fix shows it, and
-- saving over it asks first (the second click); editing it without asking is the pending page's.
function FixWindow.openEdit(line)
  local i = WFJ.Reports.find(line.type, line.id, line.field)
  local fix = i and WFJ.Reports.list()[i] or nil
  if fix then
    fix = { reason = fix.reason, note = fix.note, ja = fix.ja }
  end
  loadEdit(line, fix)
end

-- A pending fix → the edit panel (the Japanese shown is what the addon ships now; the hash stays the one saved).
function FixWindow.openPending(index)
  local fix = WFJ.Reports.list()[index]
  if not fix then return end
  local line = { type = fix.type, id = fix.id, field = fix.field, ja_hash = fix.ja_hash,
    ja = storedJa(fix.type, fix.id, fix.field) }
  loadEdit(line, { index = index, reason = fix.reason, note = fix.note, ja = fix.ja })
end

-- Save (one button): the player's Japanese is kept only when it differs from the line
-- shown; an untouched box saves the reason (and note) alone. A line with an earlier fix is replaced on the second
-- click (or at once when the panel was opened from that fix).
function FixWindow.save()
  local e = FixWindow.edit
  if not e then return false end
  if not e.reason then say("fix.noReason"); return false end
  local E = FixWindow.pages.edit
  local ja = E.ja.getText()
  -- unchanged: the same text once carriage returns are set aside (an edit box may drop them), or a
  -- cut-down copy of it (an edit box that shortened a long line)
  local boxed, stored = ja:gsub("\r", ""), (e.ja or ""):gsub("\r", "")
  if ja == "" or boxed == stored or (#boxed < #stored and stored:sub(1, #boxed) == boxed) then ja = nil end
  -- one line, no edge spaces; only spaces is no note
  local note = (E.note:GetText() or ""):gsub("[\r\n]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if note == "" then note = nil end
  local fix = { type = e.type, id = e.id, field = e.field, ja_hash = e.ja_hash, reason = e.reason, note = note,
    ja = ja }
  local armedNow = FixWindow.armed and now() - FixWindow.armed.at
    <= CONFIRM_SECONDS
  local ok, why = WFJ.Reports.save(fix, e.pending ~= nil or armedNow, playerName(e.ja))
  if ok then
    FixWindow.armed = nil
    FixWindow.show("pending")
    say("fix.saved")
    return true
  end
  if why == "exists" then
    FixWindow.armed = { at = now() }
    say("fix.exists")
  elseif why == "full" then
    say("fix.full", WFJ.Reports.CAP)
  elseif why == "note" or why == "ja" then
    say("fix.tooLong")
  elseif why == "unavailable" then
    say("fix.unavailable") -- the saved settings did not load
  else
    say("fix.noReason")
  end
  return false
end

function FixWindow.deletePending()
  local e = FixWindow.edit
  if not (e and e.pending) then return false end
  WFJ.Reports.delete(e.pending)
  FixWindow.edit = nil
  FixWindow.show("pending")
  say("fix.deleted")
  return true
end

-- Clear sent fixes: the first click arms, a second within CONFIRM_SECONDS clears.
function FixWindow.clearSent()
  local P = FixWindow.pages.copy
  local sent = FixWindow.sent or {}
  if FixWindow.clearArmed and now() - FixWindow.clearArmed <= CONFIRM_SECONDS then
    FixWindow.clearArmed = nil
    if P.clear.SetScript then P.clear:SetScript("OnUpdate", nil) end
    local n = WFJ.Reports.clearOnly(sent)
    FixWindow.show("copy")
    caption(P.clear, tx("fix.cleared", n))
    return n
  end
  FixWindow.clearArmed = now()
  caption(P.clear, tx("fix.clear.confirm", #sent))
  -- the confirm runs out: the caption goes back when it does; the button's OnUpdate is set only
  -- while armed
  if P.clear.SetScript then
    P.clear:SetScript("OnUpdate", function(self)
      if FixWindow.clearArmed and now() - FixWindow.clearArmed <= CONFIRM_SECONDS then return end
      self:SetScript("OnUpdate", nil)
      FixWindow.clearArmed = nil
      caption(self, tx("button.clearSent"))
    end)
  end
  return nil
end
