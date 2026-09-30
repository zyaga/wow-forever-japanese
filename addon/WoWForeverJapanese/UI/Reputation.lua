-- UI/Reputation.lua: the character window's reputation panel (surfaces "reputation" and "reputation.static", area
-- "ui", ADR-016). The TOC loads [Game]\ReputationFrame.lua|xml on camelot [verified: forever
-- blizzard_uipanels_game.toc:61–70]. What is translated [verified: camelot/reputationframe.lua, reputationframe.xml]:
--   the list: ReputationFrame.ScrollBox of pooled rows (lua:30–87), followed with
--     ScrollUtil.AddInitializedFrameCallback (after the element initializer), each record keyed by the row widget
--     itself. A top-level header's Name is the header's name (lua:274–279): only FACTION_INACTIVE / FACTION_OTHER
--     (every other header is a faction name). An entry's Content.Name is a faction name (forbidden); its
--     Content.ReputationBar.Text holds the standing (GetText("FACTION_STANDING_LABEL"..reaction, gender), or
--     RENOWN_LEVEL_LABEL for a major faction; lua:509–531, 554–575, 654–677). The entry's own OnEnter writes the
--     "value / max" progress into the bar and OnLeave writes the English standing back (lua:388–435; the
--     account-wide icon's OnLeave calls the entry's OnLeave directly, lua:319–322): HookScript on both re-shows that
--     bar. Help tooltips: the account-wide icon (lua:487–499) and the bonus-reputation star (lua:680–686).
--   the detail pane: ReputationFrame.ReputationDetailFrame (CharacterFrameSidePaneTemplate, xml:251–367). Its Refresh
--     is registered BY REFERENCE (lua:735–739), so the methods it calls by method lookup are hooked on the instance,
--     as UI/Skills.lua does for the skills pane: SetEmpty(REPUTATION_DETAIL_SELECT_PROMPT) → EmptyText (lua:812–819);
--     SetPaneTitle(name, standing) → Subtitle = the standing (Title is the faction name, forbidden; lua:756–770);
--     LayoutRows after the REPUTATION_TOOLTIP_ACCOUNT_WIDE_LABEL wrapped row (lua:773–777; a taller Japanese grows
--     the row and lays the pane out again). The checkbox labels (xml text= AT_WAR / MOVE_TO_INACTIVE /
--     SHOW_FACTION_ON_MAINSCREEN, xml:266, 300, 328) and the View Renown button (VIEW_RENOWN_BUTTON_LABEL, xml:346)
--     are static; the three checkboxes own help tooltips (lua:875–930). The description (ADR-042) is the
--     Faction table's text: SetDescription(description) writes the Description ScrollingFont (lua:758, 771;
--     characterframe.lua:873–885), hooked on the instance and matched against FactionDescription:* only.
--   The filter dropdown is hidden on camelot (ShouldShowFilters returns false, lua:81–91).
local _, WFJ = ...
local Reputation = {}
WFJ.Reputation = Reputation

local SURFACE = "reputation"
Reputation.SURFACE = SURFACE
local STATIC = SURFACE .. ".static"
Reputation.STATIC = STATIC
local Compat = WFJ.Compat

-- the detail pane's title (the faction name)
Reputation.NEVER_TOUCH = { "ReputationFrame.ReputationDetailFrame.Title" }

local DETAIL = "ReputationFrame.ReputationDetailFrame"
-- { record key, Compat key, candidates }
local STATIC_LABELS = {
  { "ui.atWar", "atWarLabel", { DETAIL .. ".AtWarCheckbox.Label" } },
  { "ui.inactive", "inactiveLabel", { DETAIL .. ".MakeInactiveCheckbox.Label" } },
  { "ui.mainScreen", "mainScreenLabel", { DETAIL .. ".WatchFactionCheckbox.Label" } },
  { "ui.viewRenown", "viewRenown", { DETAIL .. ".ViewRenownButton" } },
}
local STANDING_ONLY = { only = {} }
for i = 1, 8 do
  STANDING_ONLY.only[#STANDING_ONLY.only + 1] = "FACTION_STANDING_LABEL" .. i
  STANDING_ONLY.only[#STANDING_ONLY.only + 1] = "FACTION_STANDING_LABEL" .. i .. "_FEMALE"
end
local HEADER_ONLY = { only = { "FACTION_INACTIVE", "FACTION_OTHER" } }
-- the detail pane's checkboxes
local OWNERS = {}
for _, cb in ipairs({ "AtWarCheckbox", "MakeInactiveCheckbox", "WatchFactionCheckbox" }) do
  OWNERS[#OWNERS + 1] = DETAIL .. "." .. cb
end

-- a bar's standing (a major faction shows its renown level), the empty prompt, the account-wide row
local BAR_ONLY = { only = { "RENOWN_LEVEL_LABEL" } }
for _, k in ipairs(STANDING_ONLY.only) do BAR_ONLY.only[#BAR_ONLY.only + 1] = k end
local EMPTY_ONLY = { only = { "REPUTATION_DETAIL_SELECT_PROMPT" } }
local DETAIL_ROW_ONLY = { only = { "REPUTATION_TOOLTIP_ACCOUNT_WIDE_LABEL" } }
Reputation.CAMELOT_KEYS = { header = HEADER_ONLY.only, bar = BAR_ONLY.only, empty = EMPTY_ONLY.only,
  detailRow = DETAIL_ROW_ONLY.only }

local function get(name) return Compat.get(SURFACE, name) end

local function declareAll()
  for _, item in ipairs(STATIC_LABELS) do Compat.declare(SURFACE, item[2], item[3]) end
  for _, list in ipairs({ OWNERS, Reputation.NEVER_TOUCH }) do
    for _, name in ipairs(list) do Compat.declare(SURFACE, name, { name }) end
  end
  Compat.declare(SURFACE, "scrollBox", { "ReputationFrame.ScrollBox" })
  Compat.declare(SURFACE, "detail", { "ReputationFrame.ReputationDetailFrame" })
  Compat.declare(SURFACE, "scrollUtil", { "ScrollUtil" })
end

function Reputation.showStatic()
  local items = {}
  for i, item in ipairs(STATIC_LABELS) do items[i] = { item[1], get(item[2]) } end
  return WFJ.Labels.showAll(STATIC, items)
end

-- A stable record key per pooled list row (never its position).
local rowKey = WFJ.Labels.keyer("row.")

local function barText(row)
  local content = type(row) == "table" and row.Content or nil
  local bar = type(content) == "table" and content.ReputationBar or nil
  return type(bar) == "table" and bar.Text or nil
end

-- One entry's bar standing (after its initializer, and after its own OnEnter / OnLeave writes). → 1 | 0
function Reputation.showBar(row)
  local n = WFJ.Labels.show(SURFACE, rowKey(row) .. ".bar", barText(row), nil, BAR_ONLY)
  WFJ.Render.updateBanner(SURFACE)
  return n
end

local rowHooked = setmetatable({}, { __mode = "k" })
local function hookRow(row)
  if rowHooked[row] then return end
  rowHooked[row] = true
  local function reshow() Reputation.showBar(row) end
  if type(row.HookScript) == "function" then
    row:HookScript("OnEnter", reshow)
    row:HookScript("OnLeave", reshow)
  end
  local content = row.Content
  local icon = type(content) == "table" and content.AccountWideIcon or nil
  if type(icon) == "table" then
    WFJ.HelpTooltip.register(icon)
    if type(icon.HookScript) == "function" then icon:HookScript("OnLeave", reshow) end
  end
  local bar = type(content) == "table" and content.ReputationBar or nil
  if type(bar) == "table" and type(bar.BonusIcon) == "table" then WFJ.HelpTooltip.register(bar.BonusIcon) end
end

-- ScrollUtil callback: (owner, frame, elementData) on initialization, (frame, elementData) on the existing-frames
-- pass. Returns nothing (ForEachFrame stops at the first truthy return).
function Reputation.onRow(a, b)
  local row = a
  if a == Reputation then row = b end
  if type(row) ~= "table" then return end
  if type(row.Content) == "table" then -- an entry or a sub-header: a faction name and a standing bar
    WFJ.Labels.forbid(row.Content.Name)
    hookRow(row)
    Reputation.showBar(row)
  elseif type(row.Name) == "table" then -- a top-level header
    WFJ.Labels.show(SURFACE, rowKey(row) .. ".header", row.Name, nil, HEADER_ONLY)
    WFJ.Render.updateBanner(SURFACE)
  end
end

local function detail() return get("detail") end

-- The detail pane's empty prompt, after SetEmpty. → 1 | 0
function Reputation.onSetEmpty()
  local d = detail()
  local n = WFJ.Labels.show(SURFACE, "detail.empty", type(d) == "table" and d.EmptyText or nil, nil, EMPTY_ONLY)
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- The detail pane's standing, after SetPaneTitle. → 1 | 0
function Reputation.onPaneTitle()
  local d = detail()
  local n = WFJ.Labels.show(SURFACE, "detail.standing", type(d) == "table" and d.Subtitle or nil, nil, BAR_ONLY)
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- The detail pane's description, after SetDescription: a faction's own text, never a name. → 1 | 0
function Reputation.onDescription()
  local d = detail()
  local fs, refit = WFJ.Labels.scrolling(type(d) == "table" and d.Description or nil)
  local n = WFJ.Labels.show(SURFACE, "detail.description", fs, refit, WFJ.Labels.families("FactionDescription"))
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- A wrapped row's refit: the client sized it from the English; a taller Japanese grows it and the pane is laid out
-- again (never shrunk: the English comes back at its own height on the next Refresh).
local refits = setmetatable({}, { __mode = "k" })
local function refitOf(row)
  local fn = refits[row]
  if fn then return fn end
  fn = function()
    local label, d = row.Label, detail()
    if type(label) ~= "table" or type(label.GetStringHeight) ~= "function" or type(row.GetHeight) ~= "function"
        or type(row.SetHeight) ~= "function" then
      return
    end
    local h, now = label:GetStringHeight(), row:GetHeight()
    if type(h) ~= "number" or type(now) ~= "number" or h <= now then return end
    row:SetHeight(h)
    local content = type(d) == "table" and d.Content or nil
    if type(content) == "table" and type(content.Layout) == "function" then content:Layout() end
  end
  refits[row] = fn
  return fn
end

-- Every active detail row after LayoutRows. → the number of dictionary words
function Reputation.onLayoutRows()
  local d = detail()
  local pools = type(d) == "table" and d.rowPools or nil
  if type(pools) ~= "table" or type(pools.EnumerateActive) ~= "function" then return 0 end
  local seen, n = {}, 0
  for row in pools:EnumerateActive() do
    if type(row) == "table" and row.Label ~= nil then
      local key = "detail." .. rowKey(row)
      seen[key] = true
      n = n + WFJ.Labels.show(SURFACE, key, row.Label, refitOf(row), DETAIL_ROW_ONLY)
    end
  end
  local gone = {}
  for key in pairs(WFJ.SurfaceState.records(SURFACE)) do
    if key:find("^detail%.row%.") and not seen[key] then gone[#gone + 1] = key end
  end
  for _, key in ipairs(gone) do WFJ.SurfaceState.drop(SURFACE, key) end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

local function initCamelot()
  local d = detail()
  if type(d) == "table" then
    if type(d.SetEmpty) == "function" then hooksecurefunc(d, "SetEmpty", Reputation.onSetEmpty) end
    if type(d.SetPaneTitle) == "function" then hooksecurefunc(d, "SetPaneTitle", Reputation.onPaneTitle) end
    if type(d.LayoutRows) == "function" then hooksecurefunc(d, "LayoutRows", Reputation.onLayoutRows) end
    if type(d.SetDescription) == "function" then hooksecurefunc(d, "SetDescription", Reputation.onDescription) end
    Reputation.onSetEmpty()
    Reputation.onPaneTitle()
    Reputation.onLayoutRows()
    Reputation.onDescription()
  end
  local box, util = get("scrollBox"), get("scrollUtil")
  if type(box) == "table" and type(util) == "table" and type(util.AddInitializedFrameCallback) == "function" then
    util.AddInitializedFrameCallback(box, Reputation.onRow, Reputation, true)
  end
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function Reputation.init()
  declareAll()
  if hooked then return false end
  hooked = true
  Reputation.showStatic()
  for _, name in ipairs(OWNERS) do
    local owner = get(name)
    if owner then WFJ.HelpTooltip.register(owner) end
  end
  initCamelot() -- at login, no load-on-demand wait
  return true
end
