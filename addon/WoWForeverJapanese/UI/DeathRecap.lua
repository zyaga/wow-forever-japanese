-- UI/DeathRecap.lua: the death recap window on Forever (surface "deathrecap", area "ui", ADR-016).
-- Blizzard_DeathRecap is load-on-demand; its bootstrap file loads at login ([Bootstrap], blizzard_deathrecap.toc) and
-- defines OpenDeathRecapUI (mainline/blizzard_deathrecap_bootstrap.lua:7–11), which loads the addon and calls
-- DeathRecapFrame:OpenRecap(id). Entry points in the camelot load set: the death dialog's fourth button
-- (blizzard_staticpopup_game/mainline/gamedialogdefs.lua:189, 247), a `death:` chat link
-- (blizzard_uipanels_game/shared/itemrefhandlersshared.lua:131) and a damage meter death row
-- (blizzard_damagemeter/damagemetersessionwindow.lua:969). Without the frame init returns false and nothing is
-- touched.
-- Static labels, written once from XML (mainline/blizzard_deathrecap.xml): Title text="DEATH_RECAP_TITLE" (:174),
-- Unavailable text="DEATH_RECAP_UNAVAILABLE" (:187), CloseButton text="CLOSE" (:217).
-- Rows: DeathRecapFrame.ScrollBox of pooled DeathRecapEntryTemplate frames (blizzard_deathrecap.lua:285–295), each
-- initialized by DeathRecapEntryMixin:Init (:156–223), followed with ScrollUtil's initialized-frame callback:
--   SpellInfo.Caster  the source's name, or COMBATLOG_UNKNOWN_UNIT ("Something") when the event has none (:201–213):
--                     restricted to that one key, so a unit name is never matched;
--   DamageInfo        owns a Lua-built tooltip (OnEnter, :44–81: ClearLines, AddLine…, Show), registered with
--                     UI/HelpTooltip and restricted to DEATH_RECAP_CAST_BY_TT ("%s by %s", the spell and the caster
--                     kept as written), DEATH_RECAP_CURR_HP_TT and DEATH_RECAP_DEATH_TT (numbers only).
-- Never touched: SpellInfo.Name (a spell name, or "Melee" / an environmental damage word wrapped in an |Haction link,
-- :139–147), DamageInfo.Amount / AmountLarge (numbers). They are pooled, so they are forbidden per row, not by name.
-- ADR-038: the tooltip's first line is DEATH_RECAP_DAMAGE_TT, "%s %s" (:49–51): the amount, or
-- TEXT_MODE_A_STRING_VALUE_SCHOOL "<amount> <school>", then the overkill / absorb / resist / block fragments
-- TEXT_MODE_A_STRING_RESULT_* joined with spaces (:167–187). The `trailer` form (this file) peels each trailing
-- "(…)" group and matches it by key, matches the head as the school template (the amount kept, a school word in
-- Japanese) or keeps it as written, and shows the rejoined line, after the client's OnEnter (HookScript per row,
-- surface "deathrecap.tip", released on GameTooltip's OnHide). The Avoidable / Deadly lines (an atlas joined in front,
-- :63, 67) take the `icon` form through the tooltip's key list.
-- A FontString can hold a secret value on this client (issecretvalue, blizzard_sharedxmlbase/securetypes.lua:6); a
-- recap is read after death, but the caster text is still checked before it is matched.
local _, WFJ = ...
local DeathRecap = {}
WFJ.DeathRecap = DeathRecap

local SURFACE = "deathrecap"
DeathRecap.SURFACE = SURFACE
local ADDON = "Blizzard_DeathRecap"
local Compat = WFJ.Compat

-- Pooled name / number widgets are forbidden per row in onRow; nothing here has a global name.
DeathRecap.NEVER_TOUCH = {}

local CANDIDATES = {
  opener = { "OpenDeathRecapUI" }, frame = { "DeathRecapFrame" }, title = { "DeathRecapFrame.Title" },
  unavailable = { "DeathRecapFrame.Unavailable" }, close = { "DeathRecapFrame.CloseButton" },
  box = { "DeathRecapFrame.ScrollBox" }, scrollUtil = { "ScrollUtil" }, secret = { "issecretvalue" },
  tooltip = { "GameTooltip" },
}

local STATIC = {
  { "title", { only = { "DEATH_RECAP_TITLE" } } },
  { "unavailable", { only = { "DEATH_RECAP_UNAVAILABLE" } } },
  { "close", { only = { "CLOSE" } } },
}
local CASTER = { only = { "COMBATLOG_UNKNOWN_UNIT" } }
local TOOLTIP = { only = { "DEATH_RECAP_CAST_BY_TT", "DEATH_RECAP_CURR_HP_TT", "DEATH_RECAP_DEATH_TT",
  "DEATH_RECAP_AVOIDABLE_SPELL", "DEATH_RECAP_DEADLY_SPELL" } }
local TIP = SURFACE .. ".tip"
local DAMAGE_KEY = "DEATH_RECAP_DAMAGE_TT"
local HEAD = { "TEXT_MODE_A_STRING_VALUE_SCHOOL" }
local TRAILERS = { "TEXT_MODE_A_STRING_RESULT_OVERKILLING", "TEXT_MODE_A_STRING_RESULT_ABSORB",
  "TEXT_MODE_A_STRING_RESULT_RESIST", "TEXT_MODE_A_STRING_RESULT_BLOCK" }

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
end

-- true when `widget`'s text may be read and matched (not a secret value). A widget without GetText is left to
-- Labels.show, which drops it.
local function readable(widget)
  if type(widget) ~= "table" or type(widget.GetText) ~= "function" then return true end
  local secret = get("secret")
  if type(secret) ~= "function" then return true end
  return not secret(widget:GetText())
end

local casterKey = WFJ.Labels.keyer("caster.") -- a pooled row's record key (follows the widget, never the index)

-- The `trailer` form: "<head>[ ]<(group)>[ <(group)>…]" → `seq` args | nil (no group matched and no school head).
-- Each trailing group must be a TRAILERS key, else the line stays English.
function DeathRecap.trailerArgs(text)
  if type(text) ~= "string" then return nil end
  local tail, head, n = {}, text, 0
  while true do
    local rest, sep, group = head:match("^(.-)(%s*)(%([^%(%)]*%))$")
    if not rest then break end
    local part = WFJ.Labels.part(group, TRAILERS)
    if not part then return nil end
    table.insert(tail, 1, part)
    table.insert(tail, 1, sep)
    head, n = rest, n + 1
  end
  local value, gap = head:match("^(.-)(%s*)$")
  local headPart = WFJ.Labels.part(value, HEAD)
  if n == 0 and not headPart then return nil end
  local parts = { headPart or value, gap }
  for _, p in ipairs(tail) do parts[#parts + 1] = p end
  return { form = "seq", parts = parts }
end

-- After the client's DamageInfo OnEnter built the tooltip: its first line in the trailer form. → 1 | 0
function DeathRecap.onDamageTooltip()
  local tt = get("tooltip")
  local fs = WFJ.Compat.resolve("GameTooltipTextLeft1")
  if type(tt) ~= "table" or type(fs) ~= "table" or type(fs.GetText) ~= "function" or not readable(fs) then return 0 end
  local index = WFJ.UIIndex
  local args = DeathRecap.trailerArgs(fs:GetText())
  local key = args and index and index.rows[DAMAGE_KEY] and DAMAGE_KEY or nil
  return WFJ.Labels.showArgs(TIP, "L1", fs, key, args, function()
    if type(tt.Show) == "function" then tt:Show() end
  end)
end

local hookedDamage = setmetatable({}, { __mode = "k" }) -- DamageInfo frames whose OnEnter is hooked

-- The labels the XML wrote. → the number of dictionary words found.
function DeathRecap.showStatic()
  local items = {}
  for _, s in ipairs(STATIC) do items[#items + 1] = { s[1], get(s[1]), s[2] } end
  return WFJ.Labels.showAll(SURFACE, items)
end

-- One pooled entry after its initializer ran (ScrollUtil's initialized-frame callback: (owner, frame, elementData)
-- for a new row, (frame, elementData) for the existing-frames pass). Returns nothing: ForEachFrame stops at the first
-- truthy return (see UI/Raid.onRow).
function DeathRecap.onRow(a, b)
  local row = a
  if a == DeathRecap then row = b end
  if type(row) ~= "table" then return end
  local spell, damage = row.SpellInfo, row.DamageInfo
  if type(spell) == "table" then
    WFJ.Labels.forbid(spell.Name) -- a spell name
    local caster = spell.Caster
    if type(caster) == "table" and readable(caster) then
      WFJ.Labels.show(SURFACE, casterKey(caster), caster, nil, CASTER)
    end
  end
  if type(damage) == "table" then
    WFJ.Labels.forbid(damage.Amount)
    WFJ.Labels.forbid(damage.AmountLarge)
    WFJ.HelpTooltip.register(damage, TOOLTIP)
    if not hookedDamage[damage] and type(damage.HookScript) == "function" then
      hookedDamage[damage] = true
      damage:HookScript("OnEnter", DeathRecap.onDamageTooltip)
    end
  end
end

local hooked = false

-- Blizzard_DeathRecap's part: runs once the addon is loaded (now, or on its ADDON_LOADED). → true when set up.
function DeathRecap.setup()
  declare() -- its frame exists only now: forget what Compat memoized before
  local frame = get("frame")
  if type(frame) ~= "table" then return false end
  DeathRecap.showStatic()
  if hooked then return false end
  hooked = true
  if type(frame.HookScript) == "function" then frame:HookScript("OnShow", DeathRecap.showStatic) end
  local tt = get("tooltip")
  if type(tt) == "table" and type(tt.HookScript) == "function" then
    tt:HookScript("OnHide", function() WFJ.Render.release(TIP) end)
  end
  local box, util = get("box"), get("scrollUtil")
  if type(box) == "table" and type(util) == "table" and type(util.AddInitializedFrameCallback) == "function" then
    util.AddInitializedFrameCallback(box, DeathRecap.onRow, DeathRecap, true)
  end
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init. → true when the window
-- was set up now; false when it waits for the addon, or on a client without a death recap.
function DeathRecap.init()
  declare()
  if type(get("opener")) ~= "function" and type(get("frame")) ~= "table" then return false end
  return WFJ.LoadOnDemand.when(ADDON, DeathRecap.setup)
end
