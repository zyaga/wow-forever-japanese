-- UI/Gossip.lua: the NPC talk window (surface "gossip", area "gossip", ADR-017): the greeting and the option
-- rows, each translated by the gossip key of its API English (ADR-005). Quest rows, dividers, the NPC name and the
-- window chrome are not this surface's (the Goodbye button is interface text). A quest row shows its quest's title as
-- the quest log does, through UI/QuestMap's title helper, by the row's quest id.
-- Forever builds the window as a WowScrollBoxList with pooled rows [verified: forever-ui blizzard_uipanels_game/
-- mainline/gossipframe.xml:62, shared/gossipframeshared.lua]:
--   * GOSSIP_SHOW → GossipFrame:Update() → ScrollBox:SetDataProvider: every row is released, the extents are measured
--     on four module-local measure widgets (the greeting's GreetingText:SetText, the option button's Setup), rows are
--     laid out by those extents, then each row's initializer writes it and OnInitializedFrame fires.
--   * Rows are reached through Blizzard's subscriber API for addons, ScrollUtil.AddInitializedFrameCallback /
--     AddReleasedFrameCallback [verified: Blizzard_SharedXML/Shared/Scroll/ScrollUtil.lua:14–53]: a post-write
--     callback, so no writer hook is needed for the rows (ADR-009).
--   * Heights: a newly acquired row is sized to its measured extent, laid out by the rows' heights, then initialized;
--     the extents also set the scroll range and offsets, and a row resized later is not laid out again until the next
--     layout pass [verified: Blizzard_SharedXML/Shared/Scroll/ScrollBoxLinearView.lua:12–33, 93–96;
--     ScrollBoxViewUtil.lua:33–49; ScrollBoxListView.lua:360–397]. So every row's height must equal its extent: the
--     measure widgets are post-hooked once they are first seen (from the data provider after Update) to measure the
--     text the policy will show (Render.preview), and the session's first window is laid out again once.
--   * [unverified; in-game check in docs/testing/strategy.md] both row initializers call
--     self:RegisterFontString(<row text>) before Setup and Update ends with self:UpdateTheme()
--     (GossipFrameShared.lua:143, 148, 293) on a UIThemeContainerFrame, a native type with no FrameXML source: if the
--     theme re-applies a font object after our write, Japanese rows would lose their glyphs.
--     The fallback is to re-apply the bundled font from the Update post-hook, which runs after UpdateTheme.
--   * English from the API (C_GossipInfo.GetText, the GetOptions entry the row was written from); a row that does not
--     show exactly that English is left untouched and any record on its key dropped, except a
--     prepend-decorated option, GOSSIP_OPTION_PREPEND:format(QUEST_PREPEND, <option>) ("(Quest) <option>",
--     shared/gossipframeshared.lua:66–82): its prepend is shown in Japanese through the UI dictionary and the option's
--     server text is kept as the client wrote it. Its row is measured with the English (one line either way).
--   * A released row's record is dropped before the pool hands the frame out again. Release on GossipFrame's OnHide.
--   * Markers go on a banner in the stone band between the title bar and the parchment, like the quest window's: the
--     rock background starts at y −21 and the greeting panel's parchment at y −63 [verified: Blizzard_SharedXML/
--     Classic/SharedUIPanelTemplates.xml PortraitFrameTemplateNoCloseButton (338 wide; Bg at y −21, portrait 61×61
--     top-left); Classic/GossipFrame.xml:37–42, 59–64]. The only client widget there is FriendshipStatusBar
--     (TOPLEFT 73, −41, 230×14, hidden unless the NPC has a friendship reputation, GossipFrame.xml:73–77,
--     Classic/FriendshipStatusBar.lua:10–25); while it is shown the markers fall back to inline.
-- Every greeting and option English goes to the Collector first, with the NPC's GUID (UnitGUID("npc") [likely: the
-- window reads UnitName("npc"), GossipFrameShared.lua:286]).
local _, WFJ = ...
local Gossip = {}
WFJ.Gossip = Gossip

local SURFACE, AREA, KIND = "gossip", "gossip", "gossip"
Gossip.SURFACE = SURFACE
local GREETING_WIDTH = 270 -- GossipGreetingTextMixin:Setup sizes the row to (270, text height) [verified: :104–108]
-- The banner: centred right of the portrait (which reaches x ≈ 55) over the band y −21 … −63.
local BANNER_X, BANNER_Y, BANNER_WIDTH = 20, -38, 230

local Compat = WFJ.Compat
local SS = WFJ.SurfaceState
local PREPEND = { only = { "GOSSIP_OPTION_PREPEND" } } -- an option's quest prepend

local deps = {}
local inCallback, inRefit, measuring = false, false, false
-- the hooked measure widgets: { greeting = FontString, greetingFont, greetingApplied, option = Button, optionFont,
-- optionApplied }
local measure = {}

local function frame() return Compat.get(SURFACE, "frame") end

local function scrollBox()
  local f = frame()
  return f and f.GreetingPanel and f.GreetingPanel.ScrollBox or nil
end

local function gossipInfo() return Compat.get(SURFACE, "gossipInfo") end

local function apiText()
  local api = gossipInfo()
  return api and type(api.GetText) == "function" and api.GetText() or nil
end

-- GOSSIP_BUTTON_TYPE_TITLE = 1, _OPTION = 3 [verified: Shared/GossipFrameShared.lua:1–5]
local function buttonType(name, fallback)
  local v = Compat.resolve(name)
  return type(v) == "number" and v or fallback
end

-- Markers on the banner, or inline while the friendship bar holds the band. Called before anything is measured or shown
-- (FriendshipStatusBar:Update runs before Update in GOSSIP_SHOW, Classic/GossipFrame.lua:14–17).
local function syncBanner()
  local banner = Gossip.banner
  if not banner then return end
  local f = frame()
  local bar = f and f.FriendshipStatusBar
  if bar and bar.IsShown and bar:IsShown() then
    WFJ.Render.setBanner(SURFACE, nil)
    banner:SetText("")
    banner:Hide()
  else
    WFJ.Render.setBanner(SURFACE, banner)
  end
end

local function keyOf(en)
  if type(en) ~= "string" or en == "" or not deps.key then return nil end
  return deps.key(en)
end

local function readFont(fs)
  local path, size, flags = fs:GetFont()
  return { path = path, size = size, flags = flags }
end

-- Calls fn with `flag` set, resetting it even when fn raises.
local function flagged(set, fn, ...)
  set(true)
  local ok, err = pcall(fn, ...)
  set(false)
  if not ok then error(err, 0) end
end

local function setInCallback(v) inCallback = v end
local function setInRefit(v) inRefit = v end
local function setMeasuring(v) measuring = v end

local function fullUpdate()
  local sb = scrollBox()
  if not sb or type(sb.FullUpdate) ~= "function" then return end
  flagged(setInRefit, sb.FullUpdate, sb, true)
end

-- The row's height follows its text, the way the client's own Setup does it.
local function resize(row)
  if type(row) ~= "table" then return end
  if row.GreetingText then
    if row.SetSize then row:SetSize(GREETING_WIDTH, row.GreetingText:GetHeight()) end
  elseif type(row.Resize) == "function" then
    row:Resize()
  end
end

-- One refit for every record (Render.refresh dedupes it): resize the recorded rows, then, unless the client is in
-- the middle of its own update or we already are, re-measure and lay the list out again.
local function refit()
  for _, rec in pairs(SS.records(SURFACE)) do
    local ctx = rec.meta and rec.meta.ctx
    if ctx and ctx.row then resize(ctx.row) end
  end
  if inCallback or inRefit then return end
  fullUpdate()
end

-- → widget, English, record key for a greeting or option row; nil for any other row.
local function rowOf(row, elementData)
  if type(row) ~= "table" or type(elementData) ~= "table" then return nil end
  local t = elementData.buttonType
  if t == buttonType("GOSSIP_BUTTON_TYPE_TITLE", 1) then
    return row.GreetingText, apiText(), "greeting"
  elseif t == buttonType("GOSSIP_BUTTON_TYPE_OPTION", 3) then
    local opt = elementData.info
    if type(opt) ~= "table" then return nil end
    return WFJ.ButtonText.of(row), opt.name, "option." .. tostring(opt.orderIndex or elementData.index)
  end
  return nil
end

-- A quest row ("|cff000000<title>|r", or the low-level / ignored wrapper): the quest's Japanese title by its id
-- [verified: forever-ui blizzard_uipanels_game/shared/gossipframeshared.lua:27–59]. → 1 | 0
local function isQuestRow(elementData)
  local t = elementData.buttonType
  return t == buttonType("GOSSIP_BUTTON_TYPE_ACTIVE_QUEST", 4)
    or t == buttonType("GOSSIP_BUTTON_TYPE_AVAILABLE_QUEST", 5)
end

local function questRow(row, elementData)
  if not isQuestRow(elementData) then return nil end
  local info = elementData.info
  local fs = WFJ.ButtonText.of(row)
  if type(info) ~= "table" or type(fs) ~= "table" then return 0 end
  return WFJ.QuestMap.showTitle(SURFACE, info.questID, fs, refit, info.title, row)
end

-- OnInitializedFrame subscriber: the client has just written `row`. → 1 when the row is ours to show, else 0.
function Gossip.onInitialized(_, row, elementData)
  local f = frame()
  local closed = f and f.IsShown and not f:IsShown() -- rebuilt while closed (an auto-selected option, QUEST_LOG_UPDATE)
  if type(row) == "table" and type(elementData) == "table" and isQuestRow(elementData) then
    if closed then return 0 end
    syncBanner()
    local n = 0
    flagged(setInCallback, function() n = questRow(row, elementData) or 0 end)
    return n
  end
  local widget, en, recKey = rowOf(row, elementData)
  if not widget then return 0 end
  if closed then
    SS.drop(SURFACE, recKey)
    return 0
  end
  syncBanner()
  local rec = SS.get(SURFACE, recKey)
  if rec and rec.fs == widget and rec.applied ~= nil and rec.en == en and widget:GetText() == rec.applied then
    return 1 -- not rewritten since our write
  end
  local key = keyOf(en)
  if key and widget:GetText() == en then
    flagged(setInCallback, WFJ.Render.show, SURFACE, recKey, widget, en, AREA, KIND, key, { refit = refit, row = row })
    return 1
  end
  if widget:GetText() ~= en and recKey ~= "greeting" then -- "(Quest) <option>"
    local n = 0
    flagged(setInCallback, function() n = WFJ.Labels.show(SURFACE, recKey, widget, refit, PREPEND) end)
    return n
  end
  SS.drop(SURFACE, recKey)
  return 0
end

-- OnReleasedFrame subscriber: forget whatever we recorded on the row before the pool reuses it. → records dropped
function Gossip.onReleased(_, row)
  if type(row) ~= "table" then return 0 end
  local widget = row.GreetingText or (WFJ.ButtonText.known(row) and WFJ.ButtonText.of(row)) or nil
  if not widget then return 0 end
  WFJ.QuestMap.dropWidget(SURFACE, nil, widget) -- a quest row's title record sits on the title helper's adapter
  local keys = {}
  for key, rec in pairs(SS.records(SURFACE)) do
    if rec.fs == widget then keys[#keys + 1] = key end
  end
  for _, key in ipairs(keys) do SS.drop(SURFACE, key) end
  return #keys
end

-- ── Measure widgets ────────────────────────────────────────────────────────

-- GreetingText:SetText(text) on the greeting measure widget, inside the client's extent calculator.
local function measureGreetingBody(fs, text)
  if measure.greetingApplied then
    local f = measure.greetingFont
    fs:SetFont(f.path, f.size, f.flags)
    measure.greetingApplied = false
  end
  local en = apiText()
  if type(text) == "string" and text ~= "" and text == en and fs:GetText() == en then
    local shown, font = WFJ.Render.preview(SURFACE, en, measure.greetingFont, AREA, KIND, keyOf(en))
    if shown then
      if font then
        fs:SetFont(font.path, font.size, font.flags)
        measure.greetingApplied = true
      end
      fs:SetText(shown)
    end
  end
end

local function measureGreeting(fs, text)
  if measuring then return end
  syncBanner()
  flagged(setMeasuring, measureGreetingBody, fs, text)
end

-- button:Setup(optionInfo) on the option measure widget, inside the client's extent calculator.
local function measureOptionBody(button, opt)
  local fs = button:GetFontString()
  if not fs then return end
  local changed = false
  if measure.optionApplied then
    local f = measure.optionFont
    fs:SetFont(f.path, f.size, f.flags)
    measure.optionApplied, changed = false, true
  end
  local en = type(opt) == "table" and opt.name or nil
  if type(en) == "string" and en ~= "" and button:GetText() == en then
    local shown, font = WFJ.Render.preview(SURFACE, en, measure.optionFont, AREA, KIND, keyOf(en))
    if shown then
      if font then
        fs:SetFont(font.path, font.size, font.flags)
        measure.optionApplied = true
      end
      button:SetText(shown)
      changed = true
    end
  end
  if changed and type(button.Resize) == "function" then button:Resize() end
end

local function measureOption(button, opt)
  if measuring then return end
  syncBanner()
  flagged(setMeasuring, measureOptionBody, button, opt)
end

-- Hooks the measure widgets the data provider names, each once per session. → whether a hook was installed now
local function hookMeasureWidgets(sb)
  if type(sb.ForEachElementData) ~= "function" then return false end
  local greeting, option
  sb:ForEachElementData(function(elementData)
    if type(elementData) ~= "table" then return end
    local g = elementData.greetingTextFrame
    if type(g) == "table" and g.GreetingText then greeting = g.GreetingText end
    if type(elementData.titleOptionButton) == "table" then option = elementData.titleOptionButton end
  end)
  local installed = false
  if greeting and not measure.greeting then
    measure.greeting, measure.greetingFont = greeting, readFont(greeting)
    hooksecurefunc(greeting, "SetText", measureGreeting)
    installed = true
  end
  if option and not measure.option and type(option.Setup) == "function" and type(option.GetFontString) == "function"
    and option:GetFontString() then
    measure.option, measure.optionFont = option, readFont(option:GetFontString())
    hooksecurefunc(option, "Setup", measureOption)
    installed = true
  end
  return installed
end

local function anyApplied()
  for _, rec in pairs(SS.records(SURFACE)) do
    if rec.applied ~= nil or rec.appliedFont then return true end
  end
  return false
end

-- Post-hook on GossipFrame:Update, the client has built and initialized the list. → greeting + options recorded
function Gossip.onUpdate()
  local f = frame()
  if not f or (f.IsShown and not f:IsShown()) then return 0 end -- auto-selected single option: never shown
  local guid, n = UnitGUID("npc"), 0
  local text = apiText()
  if text then WFJ.Collector.recordGossip(text, guid); n = n + 1 end
  local api = gossipInfo()
  local options = api and type(api.GetOptions) == "function" and api.GetOptions() or nil
  if type(options) == "table" then
    for _, opt in ipairs(options) do
      if type(opt) == "table" and opt.name then WFJ.Collector.recordGossip(opt.name, guid); n = n + 1 end
    end
  end
  local sb = scrollBox()
  -- The first window of the session was measured before the hooks existed: lay it out again if it shows ours.
  if sb and hookMeasureWidgets(sb) and anyApplied() then fullUpdate() end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

function Gossip.release()
  return WFJ.Render.release(SURFACE)
end

-- For specs.
function Gossip.measureWidgets()
  return measure.greeting, measure.option
end

local hooked = false

-- Called by Main after Compat.init. deps = { key(text) → gossip key | nil }.
function Gossip.init(d)
  deps = d or deps
  Compat.declare(SURFACE, "frame", { "GossipFrame" })
  Compat.declare(SURFACE, "scrollUtil", { "ScrollUtil" })
  Compat.declare(SURFACE, "gossipInfo", { "C_GossipInfo" })
  if hooked then return false end
  local f, util, sb = frame(), Compat.get(SURFACE, "scrollUtil"), scrollBox()
  if not (f and sb and util and type(f.Update) == "function"
    and type(util.AddInitializedFrameCallback) == "function" and type(util.AddReleasedFrameCallback) == "function") then
    return false
  end
  hooked = true
  util.AddInitializedFrameCallback(sb, Gossip.onInitialized, Gossip)
  util.AddReleasedFrameCallback(sb, Gossip.onReleased, Gossip)
  hooksecurefunc(f, "Update", Gossip.onUpdate)
  if f.HookScript then f:HookScript("OnHide", Gossip.release) end
  if f.CreateFontString and not Gossip.banner then
    Gossip.banner, Gossip.bannerFrame = WFJ.Render.createBanner(f, BANNER_X, BANNER_Y, BANNER_WIDTH)
    syncBanner()
  end
  return true
end
