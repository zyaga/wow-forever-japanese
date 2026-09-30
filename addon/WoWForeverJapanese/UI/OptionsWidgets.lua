-- UI/OptionsWidgets.lua: the addon's own interface building blocks (settings pages, fix window): labels, section
-- headers, checkboxes, buttons, copy boxes, a dropdown, a scrolling list and a multi-line text field. Every widget is
-- placed TOPLEFT on its parent at (x, y) so a page's extent is the sum of its rows. They are the widgets Forever's own
-- windows use, and the copy reads in one language (W.pick): Japanese, or English while the reveal key is held or
-- translation is off. Text is the bundled font (W.put), since the client's fonts have no Japanese.
-- Templates [verified: forever-ui-1.60.1.70009: MinimalCheckboxTemplate Blizzard_SharedXML/Shared/
-- Button/CheckButtonTemplates.xml:74, SettingsListSectionHeaderTemplate Blizzard_Settings_Shared/
-- Blizzard_SettingControls.xml:12, UIPanelButtonTemplate Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml:315,
-- InputBoxTemplate Blizzard_SharedXML/Shared/InputBox/InputBoxTemplates.xml:70, WowStyle1DropdownTemplate
-- Blizzard_Menu/Mainline/MenuTemplates.xml:3; the list and field below cite theirs]. Button text is our own
-- FontString over an empty template label: the template swaps its label's font object on hover / disable, which would
-- drop the font (the same problem UI/ButtonText handles).
local _, WFJ = ...
local W = {}
WFJ.OptionsWidgets = W

W.JA_COLOR = { 0.72, 0.72, 0.72 }
W.GOLD = { 1, 0.82, 0 }
W.ROW = 30 -- a label row (one language)

-- The addon's own copy reads in ONE language: Japanese, or English while the reveal key is held or translation is
-- off (the same rule as the game text). A widget given both texts shows the current one and
-- re-shows it on the State "modifier" / "enabled" events (W.relabel); given one text (the other nil or ""), it shows
-- that. Consumers: UI/Options (every page), UI/FixWindow (passes one text), UI/KeyCapture, UI/AddonListButton,
-- UI/MinimapButton (W.setText / W.pick for its tooltip and menu).
function W.english()
  if WFJ.State ~= nil and WFJ.State.enabled == false then return true end
  return WFJ.Modifier ~= nil and WFJ.Modifier.isDown() == true
end

function W.pick(en, ja)
  if ja == nil or ja == "" then return en or "" end
  if en == nil or en == "" then return ja end
  return W.english() and en or ja
end

-- Widgets that hold both texts, each with the frame it shows on: re-shown when the language flips. The flip is the
-- reveal key's every press and release, so nothing is re-drawn while none of them is on screen: the
-- set is marked stale instead, and a page re-draws it when it shows (W.relabelIfStale).
local live = {}
W.stale = false
local function register(owner, fn)
  live[#live + 1] = { owner = owner, fn = fn }
end
local function onScreen(owner)
  return type(owner) == "table" and type(owner.IsVisible) == "function" and owner:IsVisible() == true
end
-- force: re-draw even when nothing is on screen
function W.relabel(force)
  if not force then
    local any = false
    for i = 1, #live do
      if onScreen(live[i].owner) then any = true; break end
    end
    if not any then W.stale = true; return end
  end
  W.stale = false
  for i = 1, #live do live[i].fn() end
end
function W.relabelIfStale()
  if W.stale then W.relabel(true) end
end
if WFJ.State then
  -- wrapped: the events pass their new value, which must not reach W.relabel as `force`
  WFJ.State.on("modifier", function() W.relabel() end)
  WFJ.State.on("enabled", function() W.relabel() end)
end

-- Text in the bundled font at a fixed size, English or Japanese: one face everywhere, no size drift when the
-- language flips.
function W.put(fs, text, size)
  fs:SetText(text or "")
  WFJ.Font.set(fs, WFJ.Font.PATH, size, "")
end

local function hasJapanese(text)
  return type(text) == "string" and text:find("[\227-\233\239]") ~= nil
end
W.hasJapanese = hasJapanese

-- Sets text; switches the FontString to the bundled font when the text needs it, and back to its own font when a
-- later text does not (a key text that goes from "Not set · 未設定" to "CTRL-J").
function W.setText(fs, text, size)
  fs:SetText(text or "")
  if hasJapanese(text) then
    local path, current, flags = fs:GetFont()
    if not fs.wfjOwnFont and path ~= WFJ.Font.PATH then fs.wfjOwnFont = { path, current, flags } end
    WFJ.Font.set(fs, WFJ.Font.PATH, size or current or WFJ.Font.DEFAULT_SIZE, flags or "")
  elseif fs.wfjOwnFont then
    WFJ.Font.set(fs, fs.wfjOwnFont[1], fs.wfjOwnFont[2], fs.wfjOwnFont[3])
  end
end

function W.fontString(parent, template, text, x, y, width, size)
  local fs = parent:CreateFontString(nil, "ARTWORK", template)
  fs:SetPoint("TOPLEFT", x, y)
  if width then fs:SetWidth(width) end
  fs:SetJustifyH("LEFT")
  W.setText(fs, text, size)
  return fs
end

-- A label in the current language (W.pick), bundled font, wrapping at `width`. `l.en` is the line shown; `l.ja` stays
-- (empty) for callers that measure both. W.setPair changes the texts later. → { en = fs, ja = fs }
function W.label(parent, en, ja, x, y, width)
  local l = {}
  l.en = W.fontString(parent, "GameFontHighlight", "", x, y, width)
  l.ja = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  l.ja:SetPoint("TOPLEFT", l.en, "BOTTOMLEFT", 0, -1)
  if width then l.ja:SetWidth(width) end
  l.ja:SetJustifyH("LEFT")
  l.ja:SetText("")
  function l.show() W.put(l.en, W.pick(l.pair[1], l.pair[2]), 12) end
  W.setPair(l, en, ja)
  register(parent, l.show)
  return l
end

function W.setPair(l, en, ja)
  l.pair = { en, ja }
  l.show()
end

-- The height a stacked label actually takes once laid out (English + Japanese, wrapped at their width), never less
-- than `minimum`. GetStringHeight measures the wrapped text [likely: FontString API with a set width]; without it
-- (the specs' stub) the minimum stands.
function W.labelHeight(l, minimum)
  if not l.en.GetStringHeight then return minimum end
  return math.max(minimum, math.ceil(l.en:GetStringHeight()) + 12)
end

-- A section header in the style of the client's own settings pages [verified: SettingsListSectionHeaderTemplate,
-- Blizzard_Settings_Shared/Blizzard_SettingControls.xml:12 (Title GameFontHighlightLarge at 7, -16), AllowLoad: Both],
-- with a faint rule under it. → { frame, title, rule, height }
function W.section(parent, en, ja, x, y, width)
  local f = CreateFrame("Frame", nil, parent, "SettingsListSectionHeaderTemplate")
  f:SetPoint("TOPLEFT", x - 7, y + 12)
  f:SetSize(width, 34)
  local title = f.Title or W.fontString(f, "GameFontHighlightLarge", "", 7, -16)
  -- gold on a faint band with a gold rule, so a section reads as a new block (a white title blends into the rows)
  title:SetTextColor(W.GOLD[1], W.GOLD[2], W.GOLD[3])
  local function show() W.put(title, W.pick(en, ja), 15) end
  show()
  register(f, show)
  local band = parent:CreateTexture(nil, "BACKGROUND")
  band:SetColorTexture(1, 1, 1, 0.06)
  band:SetPoint("TOPLEFT", x - 6, y + 4)
  band:SetSize(width + 6, 24)
  local rule = parent:CreateTexture(nil, "ARTWORK")
  rule:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.45)
  rule:SetPoint("TOPLEFT", x - 6, y - 20)
  rule:SetSize(width + 6, 1)
  return { frame = f, title = title, band = band, rule = rule, height = 32 }
end

-- A checkbox in the client's own settings style with its label to the right [verified: MinimalCheckboxTemplate,
-- Blizzard_SharedXML/Shared/Button/CheckButtonTemplates.xml:74 (atlas checkbox-minimal), Blizzard_SharedXML.toc:70].
-- onClick(checked).
function W.checkbox(parent, en, ja, x, y, width, onClick)
  local cb = CreateFrame("CheckButton", nil, parent, "MinimalCheckboxTemplate")
  cb:SetSize(24, 24)
  cb:SetPoint("TOPLEFT", x, y + 5)
  cb.label = W.label(parent, en, ja, x + 30, y, width - 30)
  cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
  return cb
end

W.BUTTON_PAD = 16 -- each side, between the caption and the button edge

-- A template button labelled in the current language (W.pick), bundled font, at least `width` wide and never narrower
-- than its caption plus padding. `template` (optional) picks another button art (UI/KeyCapture: the key-binding
-- button). → button with :setLabel(en, ja), :setEnabled(v)
function W.button(parent, en, ja, width, onClick, template)
  local b = CreateFrame("Button", nil, parent, template or "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  b.minWidth = width
  b:SetText("")
  b.caption = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.caption:SetPoint("CENTER", 0, 0)
  function b.setLabel(self, e, j)
    self.pair = { e, j }
    W.put(self.caption, W.pick(e, j), 11)
    local textWidth = self.caption.GetStringWidth and self.caption:GetStringWidth()
    if textWidth then self:SetWidth(math.max(self.minWidth, math.ceil(textWidth) + 2 * W.BUTTON_PAD)) end
  end
  function b.setEnabled(self, v)
    self:SetEnabled(v)
    local c = v and W.GOLD or W.JA_COLOR
    self.caption:SetTextColor(c[1], c[2], c[3])
  end
  b:setLabel(en, ja)
  register(b, function() if b.pair then b:setLabel(b.pair[1], b.pair[2]) end end)
  b:setEnabled(true)
  if onClick then b:SetScript("OnClick", function(self, button) onClick(self, button) end) end
  return b
end

-- A read-only, selectable text box (a path or a URL to copy). The text snaps back after any edit.
function W.copyBox(parent, x, y, width, text)
  local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  box:SetSize(width, 20)
  box:SetPoint("TOPLEFT", x + 6, y) -- InputBoxTemplate's left cap sits outside the frame
  box:SetAutoFocus(false)
  box.value = text
  box:SetText(text)
  box:SetCursorPosition(0)
  box:SetScript("OnTextChanged", function(self, userInput)
    if userInput then self:SetText(self.value); self:HighlightText() end
  end)
  box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  return box
end

-- A Blizzard_Menu dropdown; generator(dropdown, rootDescription) builds its radio items.
function W.dropdown(parent, x, y, width, generator)
  local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
  dd:SetPoint("TOPLEFT", x, y + 2)
  dd:SetWidth(width)
  dd:SetupMenu(generator)
  return dd
end

-- ── The fix window's widgets (UI/FixWindow) ─────────────────────────────────

-- A multi-line text box on the client's newest scrolling edit box, in a dark bordered field with the slim scroll bar,
-- like the calendar's event description [verified: forever-ui
-- Blizzard_SharedXML/Shared/Scroll/ScrollTemplates.xml:21 ScrollingEditBoxTemplate, ScrollTemplates.lua:15–253
-- (SetFontObject :135, SetText :165, SetCursorPosition :94, OnTextChanged callback :216), MinimalScrollBar,
-- ScrollUtil.RegisterScrollBoxWithScrollBar ScrollUtil.lua:149, TooltipBackdropTemplate SharedTooltipTemplates.xml
-- (Blizzard_SharedXML.toc:160–161); Blizzard_Calendar.xml:844–875]. The edit box re-applies its template font object in
-- ApplyText (every SetText) and on focus while a placeholder shows [verified: EventEditBoxMixin:ApplyText /
-- OnEditFocusGained_Intrinsic, Blizzard_SharedXML/Shared/Frame/EventEditBox.lua:66–138], so our own box is hooked to
-- put the bundled face back right after, with no addon font object. Read-only unless opts.editable: a
-- read-only box selects all of itself on focus and any edit snaps back. opts.maxBytes caps an editable box.
-- → { frame, editor, box, setText(t), getText(), focusAll() }
function W.scrollText(parent, x, y, width, height, opts)
  opts = opts or {}
  local st = {}
  local frame = CreateFrame("Frame", nil, parent, "TooltipBackdropTemplate")
  frame:SetPoint("TOPLEFT", x, y)
  frame:SetSize(width, height)
  if frame.SetBackdropColor then frame:SetBackdropColor(0, 0, 0, 0.9) end
  if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(0.55, 0.55, 0.55, 1) end
  local editor = CreateFrame("Frame", nil, frame, "ScrollingEditBoxTemplate")
  editor:SetPoint("TOPLEFT", 6, -6)
  editor:SetPoint("BOTTOMRIGHT", -20, 6)
  local bar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
  bar:SetPoint("TOPRIGHT", -6, -6)
  bar:SetPoint("BOTTOMRIGHT", -6, 6)
  ScrollUtil.RegisterScrollBoxWithScrollBar(editor:GetScrollBox(), bar)
  local box = editor:GetEditBox()
  local function refont() WFJ.Font.set(box, WFJ.Font.PATH, 12, "") end
  refont()
  hooksecurefunc(box, "ApplyText", refont)
  box:HookScript("OnEditFocusGained", refont)
  if opts.maxBytes then box:SetMaxBytes(opts.maxBytes + 1) end
  -- a click anywhere in the field puts the cursor in it
  frame:EnableMouse(true)
  frame:SetScript("OnMouseDown", function() box:SetFocus() end)
  if not opts.editable then
    -- no letter limit: a 25-fix report can be long, and a cut copy would never read
    if box.SetMaxLetters then box:SetMaxLetters(0) end
    box:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
    editor:RegisterCallback("OnTextChanged", function(_, _, userChanged)
      if userChanged then editor:SetText(st.value or ""); box:HighlightText() end
    end, st)
  end
  st.frame, st.editor, st.box, st.bar, st.value = frame, editor, box, bar, ""
  function st.setText(_, text)
    st.value = text or ""
    editor:SetText(st.value)
    editor:SetCursorPosition(0)
  end
  function st.getText()
    return box:GetText() or ""
  end
  function st.focusAll()
    box:SetFocus()
    box:HighlightText()
  end
  return st
end

-- A scrolling list on the client's ScrollBox, the list Forever's own windows use (camelot FriendsFrame)
-- [verified: forever-ui-1.60.1.70009 Blizzard_SharedXML: WowScrollBoxList ScrollTemplates.xml:4, MinimalScrollBar
-- MinimalScrollBar.xml:15, CreateScrollBoxListLinearView ScrollBoxLinearView.lua:246, SetElementInitializer
-- ScrollBoxListView.lua:496, ScrollUtil.InitScrollBoxListWithScrollBar ScrollUtil.lua:137, CreateDataProvider
-- DataProvider.lua:277; all unconditional in Blizzard_SharedXML.toc]. Rows are pooled: a row's font strings are
-- made once, and every init re-sets their text in the bundled font.
-- Each item is { left = text, text = text }: `left` in a column lw wide, `text` beside it; onClick(item, index).
-- → { box, bar, setItems(items) }
function W.scrollList(parent, x, y, width, height, rowHeight, lw, onClick)
  local list = {}
  local box = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
  box:SetPoint("TOPLEFT", x, y)
  box:SetSize(width - 20, height)
  local bar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
  bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 6, 0)
  bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 6, 0)
  local view = CreateScrollBoxListLinearView()
  view:SetElementExtent(rowHeight)
  view:SetElementInitializer("Button", function(b, item)
    if not b.left then
      b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
      local function fs(px, w)
        local s = b:CreateFontString(nil, "ARTWORK")
        WFJ.Font.set(s, WFJ.Font.PATH, 11, "")
        s:SetPoint("TOPLEFT", px, -4)
        s:SetWidth(w)
        s:SetHeight(rowHeight - 6) -- clipped to its row: a long line never runs into the next one
        s:SetJustifyH("LEFT")
        s:SetJustifyV("TOP")
        return s
      end
      b.left = fs(4, lw - 8)
      b.text = fs(lw, width - 20 - lw - 4)
      b:SetScript("OnClick", function(self) if self.item then onClick(self.item, self.item.index) end end)
    end
    b.item = item
    WFJ.Font.set(b.left, WFJ.Font.PATH, 11, ""); b.left:SetText(item.left or "")
    WFJ.Font.set(b.text, WFJ.Font.PATH, 11, ""); b.text:SetText(item.text or "")
  end)
  ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
  list.box, list.bar = box, bar
  function list.setItems(_, items)
    list.items = items
    for i, it in ipairs(items) do it.index = i end
    box:SetDataProvider(CreateDataProvider(items), ScrollBoxConstants.RetainScrollPosition)
  end
  return list
end

