-- UI/Options.lua: the settings pages: main (translation, what to translate, markers), collector and
-- about, registered through Compat as one AddOns category with two subcategories. The layout is declared in PAGES: a
-- row is a setting id (a checkbox for `boolean`, the key row for `key`) or a named ACTIONS builder; every non-hidden
-- setting appears exactly once (options_spec). Labels read in one language (UI/OptionsWidgets). Main.lua
-- pcalls the build: a template that differs on a client leaves /wfj working, and /wfj debug names the error.
local _, WFJ = ...
local Options = {}
WFJ.Options = Options

local S, M, W, Text, KC = WFJ.Settings, WFJ.Modifier, WFJ.OptionsWidgets, WFJ.OptionsText, WFJ.KeyCapture
local LEFT, WIDTH, COL2 = 16, 620, 330
local COL3 = math.floor(WIDTH / 3) -- a three-column section's column width

Options.TITLE = "WoW Forever Japanese"
Options.frame = nil -- the main page
Options.pages = {} -- id → page frame
Options.buildError = nil -- set by Main.lua when the pcall'd build fails; printed by /wfj debug
Options.controls = {} -- setting rows: { id, kind = "boolean", widget } | { id, kind = "key", dropdown, capture, … }
Options.captures = {} -- every KeyCapture on the pages (combat stops them)
Options.refreshers = {} -- per-action refresh functions
Options.inCombat = false -- set by Main's PLAYER_REGEN_* (the lockdown query may still read false inside the event)

Options.PAGES = {
  { id = "main", title = "page.main", header = true, tagline = true, sections = {
    -- Two columns: readings beside "Enable translation", then meanings and the minimap button on a second row. With
    -- the areas in three columns below, the page fits 640 × 560.
    { title = "section.translation", columns = 2,
      rows = { "enabled", "readings.enabled", "readings.glosses", "minimapButton" }, gap = 0 },
    { rows = { "modifier", "toggleKey" } },
    { title = "section.areas", columns = 3,
      rows = { "area.quests", "area.gossip", "area.books", "area.itemTooltips", "area.spellTooltips",
        "area.interface" } },
    { title = "section.markers", rows = { "marker.stale", "marker.missing" } },
  } },
  { id = "collector", title = "page.collector", sections = {
    { title = "section.collector",
      rows = { "collectorExplain", "collector.enabled", "collectorStatus", "collectorClear" } },
    { title = "section.files", rows = { "collectorPath", "collectorIssue" } },
  } },
  { id = "about", title = "page.about", header = true, sections = {
    { title = "section.help", rows = { "aboutHold", "aboutReadings", "aboutMarkers", "aboutOpen" } },
    { title = "section.slash", rows = { "slashHelp" } },
    { rows = { "aboutFix", "reportLink" } }, -- the fix window, then the issue tracker
  } },
}

-- A marker row shows the marker itself beside its checkbox.
Options.SAMPLES = { ["marker.stale"] = WFJ.MARKER.stale, ["marker.missing"] = WFJ.MARKER.missing }

local function thousands(n)
  local s = tostring(n)
  while true do
    local t, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
    s = t
    if k == 0 then return s end
  end
end

-- → the English and the Japanese header line
local function headerText()
  local mem = WFJ.Compat.memoryKB()
  local memEn, memJa = Text.get("header.noMemory")
  if mem then memEn = ("%.1f MB"):format(mem / 1024); memJa = memEn end
  local meta = WFJ.Data and WFJ.Data.meta
  local dataEn, dataJa = Text.get("header.noData")
  if meta then
    local c = meta.counts
    dataEn, dataJa = Text.get("header.data", thousands(c.quest), thousands(c.item), thousands(c.spell),
      thousands(c.ui or 0))
  end
  return ("%s · %s · %s"):format(WFJ.VERSION, memEn, dataEn), ("%s · %s · %s"):format(WFJ.VERSION, memJa, dataJa)
end

local function definition(id)
  for _, d in ipairs(S.list()) do if d.id == id then return d end end
  return nil
end

local function stackedText(pair, en, ja)
  W.setPair(pair, en, ja)
end

-- ── Rows ────────────────────────────────────────────────────────────────────

Options.ACTIONS = {}
local A = Options.ACTIONS

local function inCombat()
  return Options.inCombat or (InCombatLockdown() and true or false)
end

-- A change from the page (dropdown or capture). Refused in combat: the page offers keys only out of combat.
function Options.setModifier(v)
  if inCombat() then
    Options.refresh()
    return false
  end
  local ok = S.set("modifier", v)
  for _, c in ipairs(Options.controls) do
    if c.kind == "key" then c.refused = (not ok) and v or nil end
  end
  Options.refresh()
  return ok
end

local function keyRow(page, d, x, y, width)
  W.label(page, d.label, d.ja, x, y, 220)
  local ctl = { id = d.id, kind = "key" }
  ctl.dropdown = W.dropdown(page, x + 230, y, 150, function(_, root)
    for _, k in ipairs(M.PRESETS) do
      root:CreateRadio(M.display(k), function() return S.get(d.id) == k end, function() Options.setModifier(k) end, k)
    end
    local cur = S.get(d.id)
    if M.class(cur) == "bound" then
      root:CreateRadio(KC.keyText(cur), function() return S.get(d.id) == cur end, function() end, cur)
    end
  end)
  ctl.capture = KC.new(page, { mode = "reveal", width = 105, onKey = Options.setModifier,
    onRefused = function() Options.refresh() end })
  ctl.capture.button:SetPoint("TOPLEFT", x + 395, y + 2)
  ctl.warning = W.label(page, "", "", x, y - 26, width)
  ctl.warning.en:SetTextColor(W.GOLD[1], W.GOLD[2], W.GOLD[3])
  Options.controls[#Options.controls + 1] = ctl
  Options.captures[#Options.captures + 1] = ctl.capture
  return 48
end

local function settingRow(page, id, x, y, width)
  local d = assert(definition(id), "Options: no setting " .. id)
  if d.kind == "key" then return keyRow(page, d, x, y, width) end
  assert(d.kind == "boolean", "Options: no row for kind " .. d.kind)
  -- a marker row's label stops before the sample shown at x + 400
  local labelWidth = Options.SAMPLES[id] and math.min(width, 390) or width
  local cb = W.checkbox(page, d.label, d.ja, x, y, labelWidth, function(checked)
    S.set(d.id, checked)
    Options.refresh()
  end)
  Options.controls[#Options.controls + 1] = { id = d.id, kind = "boolean", widget = cb }
  if Options.SAMPLES[id] then
    local sample = W.fontString(page, "GameFontNormalSmall", Options.SAMPLES[id], x + 400, y - 2, width - 400, 11)
    sample:SetTextColor(WFJ.MARKER_COLOR.r, WFJ.MARKER_COLOR.g, WFJ.MARKER_COLOR.b)
  end
  -- a label that wraps (a narrow column) makes its row taller instead of running into the next one
  return W.labelHeight(cb.label, W.ROW)
end

-- The note that stops `v` becoming the toggle key, or nil. Re-checked on Replace: the modifier may have moved onto
-- the pending key since it was proposed.
local function toggleRefusal(v)
  if S.get("modifier"):upper() == v:upper() then return { "warn.revealConflict", KC.keyText(v) } end
  return nil
end

function Options.proposeToggle(v)
  local t = Options.toggle
  t.pending, t.note = nil, toggleRefusal(v)
  if not t.note then
    local action = KC.conflict(v, KC.TOGGLE)
    if action then
      t.pending, t.note = v, { "warn.bindReplace", KC.keyText(v), action }
    else
      KC.setToggle(v)
    end
  end
  Options.refresh()
end

function Options.unbindOrReplace()
  local t = Options.toggle
  local pending = t.pending
  t.pending, t.note = nil, nil
  if pending then
    t.note = toggleRefusal(pending)
    if not t.note then KC.setToggle(pending) end
  else
    KC.clearToggle()
  end
  Options.refresh()
end

-- Leaving the page forgets a pending Replace and any refusal note.
function Options.forgetPending()
  if Options.toggle then Options.toggle.pending, Options.toggle.note = nil, nil end
  for _, c in ipairs(Options.controls) do c.refused = nil end
end

-- The toggle key: its current key, Set key with Unbind / Replace beside it, and a note to the left of the buttons.
function A.toggleKey(page, x, y)
  W.label(page, Text.T.toggleKey.en, Text.T.toggleKey.ja, x, y, 220)
  local t = {}
  t.keyText = W.fontString(page, "GameFontHighlight", "", x + 230, y, 155, 12)
  t.capture = KC.new(page, { mode = "toggle", width = 105, onKey = Options.proposeToggle,
    onRefused = function() Options.refresh() end })
  t.capture.button:SetPoint("TOPLEFT", x + 395, y + 2)
  local en, ja = Text.get("button.unbind")
  -- beside Set key, on the same line
  t.unbind = W.button(page, en, ja, 95, function() Options.unbindOrReplace() end)
  t.unbind:SetPoint("LEFT", t.capture.button, "RIGHT", 6, 0)
  t.warning = W.label(page, "", "", x, y - 26, 380)
  t.warning.en:SetTextColor(W.GOLD[1], W.GOLD[2], W.GOLD[3])
  Options.toggle = t
  Options.captures[#Options.captures + 1] = t.capture
  return 36 -- the section's last row: its (rare) note line sits in the section gap
end

function A.collectorExplain(page, x, y, width)
  local en, ja = Text.get("collector.explain")
  return W.labelHeight(W.label(page, en, ja, x, y, width), 64) -- wraps: the Japanese follows the English's bottom
end

function A.collectorStatus(page, x, y, width)
  local fs = W.fontString(page, "GameFontHighlight", "", x, y, width)
  Options.collectorStatus = fs
  Options.refreshers[#Options.refreshers + 1] = function()
    local s = WFJ.Collector.status()
    local function t(key, ...) return W.pick(Text.get(key, ...)) end
    local line = t("collector.statusLine", t(s.enabled and "collector.on" or "collector.off"), s.entries,
      WFJ.Collector.formatBytes(s.bytes), WFJ.Collector.formatBytes(s.cap))
    if s.capped then line = line .. " · " .. t("collector.full") end
    if s.readOnly then line = line .. " · " .. t("collector.paused") end
    if s.errors > 0 then line = line .. " · " .. t("collector.errors", s.errors) end
    W.put(fs, ("%s: %s"):format(t("collector.status"), line), 12) -- the labels' size
  end
  return 24
end

function A.collectorClear(page, x, y)
  local armedAt
  local en, ja = Text.get("collector.clear")
  local b = W.button(page, en, ja, 320, function(self)
    local now = GetTime()
    if armedAt and now - armedAt <= 5 then
      armedAt = nil
      local n = WFJ.Collector.clear()
      Options.refresh()
      -- nil: a dump from a newer version is never cleared (the status line says "paused")
      if n then self:setLabel(Text.get("collector.cleared", n)) else self:setLabel(Text.get("collector.clear")) end
    else
      armedAt = now
      self:setLabel(Text.get("collector.confirm", WFJ.Collector.status().entries))
    end
  end)
  b:SetPoint("TOPLEFT", x, y)
  page:HookScript("OnHide", function() armedAt = nil; b:setLabel(Text.get("collector.clear")) end)
  Options.refreshers[#Options.refreshers + 1] = function() -- an armed label that timed out goes back
    if armedAt and GetTime() - armedAt > 5 then armedAt = nil; b:setLabel(Text.get("collector.clear")) end
  end
  Options.collectorClear = b
  return 30
end

local function copyRow(key, value)
  return function(page, x, y, width)
    local en, ja = Text.get(key)
    local labelHeight = W.labelHeight(W.label(page, en, ja, x, y, width), 22)
    Options.copyBoxes = Options.copyBoxes or {}
    Options.copyBoxes[key] = W.copyBox(page, x, y - labelHeight, width - 12, value)
    return labelHeight + 28
  end
end
A.collectorPath = copyRow("collector.path", WFJ.Collector.PATH)
A.collectorIssue = copyRow("collector.issue", WFJ.Collector.ISSUE_URL)
A.reportLink = copyRow("about.report", Text.REPORT_URL)

-- The About page's way into the fix window (report a line the player just saw).
function A.aboutFix(page, x, y, width)
  local en, ja = Text.get("about.fix")
  local h = W.labelHeight(W.label(page, en, ja, x, y, width), 24) - 6
  en, ja = Text.get("button.reportLine")
  local b = W.button(page, en, ja, 150, function() WFJ.FixWindow.open() end)
  b:SetPoint("TOPLEFT", x, y - h) -- under its sentence
  Options.reportLine = b
  return h + 36
end

local function helpRow(key)
  return function(page, x, y, width)
    return W.labelHeight(W.label(page, Text.T[key].en, Text.T[key].ja, x, y, width), 24)
  end
end
A.aboutOpen, A.aboutReadings = helpRow("about.open"), helpRow("about.readings")

function A.aboutMarkers(page, x, y, width)
  local l = W.label(page, "", "", x, y, width)
  W.setPair(l, Text.get("about.markers", WFJ.MARKER.stale, WFJ.MARKER.missing))
  return W.labelHeight(l, 24)
end

-- The reveal key by name: a preset's ("Alt"), or a bound key's as the client names it ("Mouse Button 4").
function Options.keyName()
  local k = S.get("modifier")
  if M.class(k) == "bound" then return KC.keyText(k) end
  return M.display(k)
end

-- Names the reveal key, so it follows a key change.
function A.aboutHold(page, x, y, width)
  local l = W.label(page, "", "", x, y, width)
  local function fill() W.setPair(l, Text.get("about.hold", Options.keyName())) end
  fill()
  Options.refreshers[#Options.refreshers + 1] = fill
  return W.labelHeight(l, 24)
end

function A.slashHelp(page, x, y, width)
  for i, line in ipairs(Text.SLASH) do
    W.fontString(page, "GameFontHighlightSmall", line, x, y - (i - 1) * 14, width)
  end
  return #Text.SLASH * 14 + 6
end

-- ── Pages ───────────────────────────────────────────────────────────────────

local function row(page, id, x, y, width)
  if A[id] then return A[id](page, x, y, width) end
  return settingRow(page, id, x, y, width)
end

local function buildPage(spec)
  local page = CreateFrame("Frame")
  -- the page title in the current language, gold like the client's own page titles
  page.title = W.label(page, "", "", LEFT, -16, WIDTH) -- the whole page width: the full name at 18 must not wrap
  page.title.en:SetTextColor(W.GOLD[1], W.GOLD[2], W.GOLD[3])
  W.setPair(page.title, Text.get(spec.title))
  local function titleSize() W.put(page.title.en, page.title.en:GetText(), 18) end
  titleSize()
  Options.refreshers[#Options.refreshers + 1] = titleSize
  -- No links to the other pages: the Settings panel's own category list on the left already switches between them.
  -- The addon never writes Blizzard's category tables itself.
  local y = -40
  if spec.header then
    page.subtitle = W.label(page, "", "", LEFT, y, WIDTH) -- filled on show
    y = y - 18
  end
  if spec.tagline then
    stackedText(W.label(page, "", "", LEFT, y, WIDTH), Text.get("tagline"))
    y = y - 34
  end
  y = y - 8
  for _, section in ipairs(spec.sections) do
    local title = section.title and Text.T[section.title]
    if title then y = y - W.section(page, title.en, title.ja, LEFT, y, WIDTH).height end
    local rows, i = section.rows, 1
    while i <= #rows do
      if section.columns == 2 and i < #rows then
        local left = row(page, rows[i], LEFT, y, COL2 - LEFT - 10)
        local h = math.max(left, row(page, rows[i + 1], COL2, y, WIDTH + LEFT - COL2))
        y, i = y - h, i + 2
      elseif section.columns == 3 then -- three columns of COL3 (the areas: short labels)
        local h = 0
        for c = 0, 2 do
          if rows[i + c] then h = math.max(h, row(page, rows[i + c], LEFT + c * COL3, y, COL3 - 10)) end
        end
        y, i = y - h, i + 3
      else
        y, i = y - row(page, rows[i], LEFT, y, WIDTH), i + 1
      end
    end
    y = y - (section.gap or 10) -- gap 0: a section that continues the one above
  end
  page.bottom = -y
  page:SetScript("OnShow", function()
    if page.subtitle then W.setPair(page.subtitle, headerText()) end -- memory is read on show only (an expensive call)
    W.relabelIfStale() -- the language flipped while no page was on screen (OptionsWidgets)
    Options.refresh()
  end)
  page:SetScript("OnHide", function() Options.forgetPending() end)
  -- Built hidden: a parentless frame is visible, and the Settings panel shows a canvas itself when its category is
  -- selected (and hides it on leaving) [verified: Blizzard_SettingsPanel.lua:866–909].
  page:Hide()
  return page
end

-- Builds every page. → the ordered page list for Compat.registerOptions
function Options.build()
  Options.controls, Options.captures, Options.refreshers, Options.pages = {}, {}, {}, {}
  local list = {}
  for _, spec in ipairs(Options.PAGES) do
    local page = buildPage(spec)
    Options.pages[spec.id] = page
    local name = spec.id == "main" and Options.TITLE or Text.T[spec.title].en -- the category list has no Japanese font
    list[#list + 1] = { id = spec.id, frame = page, name = name }
  end
  Options.frame = Options.pages.main
  Options.refresh()
  return list
end

-- ── Refresh ─────────────────────────────────────────────────────────────────

local function refreshKeyRow(ctl, combat)
  local cur = S.get(ctl.id)
  local menuOpen = ctl.dropdown.IsMenuOpen and ctl.dropdown:IsMenuOpen()
  if ctl.dropdown.GenerateMenu and not menuOpen then ctl.dropdown:GenerateMenu() end
  ctl.dropdown:SetEnabled(not combat)
  ctl.capture.button:setEnabled(not combat)
  local en, ja = "", ""
  if combat then
    en, ja = Text.get("warn.combat")
  elseif ctl.refused then
    en, ja = Text.get("warn.toggleConflict", KC.keyText(ctl.refused))
  elseif WFJ.RevealBinding and WFJ.RevealBinding.state == "queued" then
    en, ja = Text.get("warn.afterCombat", KC.keyText(cur))
  elseif M.class(cur) == "bound" then
    local action = KC.conflict(cur, KC.REVEAL)
    if action then en, ja = Text.get("warn.takeover", KC.keyText(cur), action, KC.keyText(cur)) end
  end
  stackedText(ctl.warning, en, ja)
end

local function refreshToggle(t, combat)
  local key = KC.toggleKey()
  local none = Text.T["key.notSet"]
  W.put(t.keyText, key and KC.keyText(key) or W.pick(none.en, none.ja), 12)
  t.capture.button:setEnabled(not combat)
  t.unbind:setLabel(Text.get(t.pending and "button.replace" or "button.unbind"))
  t.unbind:setEnabled(not combat and (t.pending ~= nil or key ~= nil))
  local en, ja = "", ""
  if combat then en, ja = Text.get("warn.combat")
  elseif t.note then en, ja = Text.get(unpack(t.note))
  elseif key and key:upper() == S.get("modifier"):upper() then -- bound to the modifier's key in Key Bindings later
    en, ja = Text.get("warn.revealConflict", KC.keyText(key))
  end
  stackedText(t.warning, en, ja)
end

function Options.refresh()
  local combat = inCombat()
  for _, c in ipairs(Options.controls) do
    if c.kind == "boolean" then c.widget:SetChecked(S.get(c.id) == true) else refreshKeyRow(c, combat) end
  end
  if Options.toggle then refreshToggle(Options.toggle, combat) end
  for _, fn in ipairs(Options.refreshers) do fn() end
end

-- A page is on screen only while the Settings panel shows it (IsVisible: shown and every parent shown).
local function refreshIfVisible()
  for _, page in pairs(Options.pages) do
    if page:IsVisible() then return Options.refresh() end
  end
end

-- PLAYER_REGEN_DISABLED / ENABLED (Main): combat stops any capture; the key controls follow when a page is on screen.
function Options.setCombat(flag)
  Options.inCombat = flag and true or false
  if Options.inCombat then
    for _, c in ipairs(Options.captures) do c:stop() end
  end
  refreshIfVisible()
end

-- "modifier": the pages read in one language, and holding the reveal key re-labels them in English
for _, event in ipairs({ "enabled", "area", "markers", "readings", "revealKey", "modifier" }) do
  WFJ.State.on(event, refreshIfVisible)
end
