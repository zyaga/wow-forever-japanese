-- UI/TimeLine.lua: the time a tooltip counts down, in Japanese even while the client hides it. Two lines move while a
-- tooltip is up: an aura's time left ("9 minutes remaining", SPELL_TIME_REMAINING_*) and a cooldown ("Cooldown
-- remaining: 2 sec", ITEM_COOLDOWN_TIME around INT_SPELL_DURATION_*). In combat the line and the number behind it can
-- be secret values, which an addon may write but not read.
-- The client builds both lines in compiled code, so where it switches from seconds to minutes and how it rounds is in
-- no file. Its own Lua helper switches at 1.5 units and rounds up [verified: blizzard_sharedxml/timeutil.lua:463–483];
-- the tooltip may differ. So every rule the client could be using is a candidate, and each time line read while it is
-- readable rules out the candidates that would have written anything else. Until one is left, the rule in use is
-- Blizzard's own (SecondsToTime with one term and rounding up: switch at 1.5 units, every unit rounded up
-- [verified: blizzard_sharedxml/timeutil.lua:364–426]; a readable "Cooldown remaining: 2 sec" with 1.4 s left agrees),
-- as long as no line has ruled it out. The client's formatter built from the rule is checked at login against the
-- rule on durations the addon makes itself (C_DurationUtil.CreateDuration), so the first fight is covered too. A
-- hidden line is then written by the client applying the rule to the hidden duration itself
-- (C_StringUtil.CreateNumericRuleFormatter [verified: stringutildocumentation.lua:21–28],
-- LuaDurationObject:FormatRemainingDuration [verified: luadurationobjectapidocumentation.lua:145–159]) and
-- FontString:SetText takes the result (SecretArguments AllowedWhenTainted [verified:
-- simplefontstringapidocumentation.lua:664–667]). Otherwise the client's line stays: a time is never shown wrong.
-- What was learnt is kept in WFJ_DB.timeRule and starts over when the client build changes.
local _, WFJ = ...
local TimeLine = {}
WFJ.TimeLine = TimeLine
local Compat = WFJ.Compat

local UNITS = { { name = "sec", size = 1 }, { name = "min", size = 60 }, { name = "hour", size = 3600 },
  { name = "day", size = 86400 } }
TimeLine.FAMILIES = {
  aura = { keys = { sec = "SPELL_TIME_REMAINING_SEC", min = "SPELL_TIME_REMAINING_MIN",
    hour = "SPELL_TIME_REMAINING_HOURS", day = "SPELL_TIME_REMAINING_DAYS" } },
  cooldown = { wrap = "ITEM_COOLDOWN_TIME", keys = { sec = "INT_SPELL_DURATION_SEC", min = "INT_SPELL_DURATION_MIN",
    hour = "INT_SPELL_DURATION_HOURS", day = "INT_SPELL_DURATION_DAYS" } },
}
local SWITCH = { 1, 1.5 }
local ROUNDING = { "up", "nearest", "down" }
local ENUM_ROUNDING = { up = "Up", nearest = "Nearest", down = "Down" }
local SAMPLE = 37

local candidates = {}
for _, switch in ipairs(SWITCH) do
  for _, sec in ipairs(ROUNDING) do
    for _, big in ipairs(ROUNDING) do
      candidates[#candidates + 1] = { id = ("%s/%s/%s"):format(switch, sec, big), switch = switch, sec = sec,
        big = big }
    end
  end
end
TimeLine.CANDIDATES = candidates

local db -- WFJ_DB.timeRule: { build, [family] = { out = { [candidate id] = true }, seen, formatter, mismatch } }

local function secret(...)
  local isSecret = Compat.resolve("issecretvalue")
  if type(isSecret) ~= "function" then return false end
  for i = 1, select("#", ...) do
    if isSecret((select(i, ...))) then return true end
  end
  return false
end

local function buildId()
  local info = Compat.resolve("GetBuildInfo")
  if type(info) ~= "function" then return nil end
  local version, build = info()
  return tostring(version) .. "." .. tostring(build)
end

-- Takes the loaded WFJ_DB table. → the time rule state
function TimeLine.load(saved)
  if type(saved) ~= "table" then db = {}; return db end
  local build = buildId()
  if type(saved.timeRule) ~= "table" or saved.timeRule.build ~= build then saved.timeRule = { build = build } end
  db = saved.timeRule
  return db
end

local function state(family)
  db = db or {}
  db[family] = db[family] or { out = {}, seen = 0 }
  return db[family]
end

local function round(mode, x)
  if mode == "up" then return math.ceil(x - 1e-9) end
  if mode == "down" then return math.floor(x + 1e-9) end
  return math.floor(x + 0.5)
end

-- → unit name, number: what a candidate rule writes for `seconds` left
function TimeLine.predict(c, seconds)
  for i = #UNITS, 2, -1 do
    local u = UNITS[i]
    if seconds >= u.size * c.switch then return u.name, round(c.big, seconds / u.size) end
  end
  return "sec", round(c.sec, seconds)
end

-- The English the client writes for a unit and number: its own template, with the |4singular:plural; code resolved.
local function english(family, unit, n)
  local f = TimeLine.FAMILIES[family]
  local template = Compat.resolve(f.keys[unit])
  if type(template) ~= "string" then return nil end
  local text = template:gsub("|4([^:;]*):([^;]*);", n == 1 and "%1" or "%2"):format(n)
  if f.wrap then
    local wrap = Compat.resolve(f.wrap)
    if type(wrap) ~= "string" then return nil end
    text = wrap:format(text)
  end
  return text
end

local function escape(s) return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end

-- The pattern a unit's English line matches, singular and plural, with the number captured.
local patterns = {}
local function patternsOf(family, unit)
  local k = family .. ":" .. unit
  if patterns[k] then return patterns[k] end
  local out = {}
  for _, n in ipairs({ 1, 2 }) do
    local text = english(family, unit, n)
    if text then
      local p = "^" .. escape(text):gsub(escape(tostring(n)), "(%%d+)", 1) .. "$"
      out[#out + 1] = p
    end
  end
  patterns[k] = out
  return out
end

-- → family, unit, number for a readable time line | nil
function TimeLine.parse(text)
  if type(text) ~= "string" or text == "" or secret(text) then return nil end
  for family in pairs(TimeLine.FAMILIES) do
    for _, u in ipairs(UNITS) do
      for _, p in ipairs(patternsOf(family, u.name)) do
        local n = text:match(p)
        if n then return family, u.name, tonumber(n) end
      end
    end
  end
  return nil
end

-- A row whose number moves while the tooltip is up. → its family | nil
function TimeLine.family(text)
  local family = TimeLine.parse(text)
  return family
end

-- The Japanese line for a unit, with %d where the number goes: a sample put through the dictionary.
local japanese = {}
local function japaneseFormat(family, unit)
  local k = family .. ":" .. unit
  if japanese[k] ~= nil then return japanese[k] or nil end
  japanese[k] = false
  local en = english(family, unit, SAMPLE)
  local index = WFJ.UIIndex
  if not en or not index then return nil end
  local key, args = index:match(en)
  if not key then return nil end
  local ja = WFJ.Render.preview("tooltip.timeline", en, nil, "ui", "ui", key, { args = args })
  if type(ja) ~= "string" or ja == en then return nil end
  local fmt, found = ja:gsub("%%", "%%%%"):gsub(tostring(SAMPLE), "%%d", 1)
  if found ~= 1 then return nil end
  japanese[k] = fmt
  return fmt
end

-- Blizzard's two documented rules, the starting rule while lines have not narrowed it to one: SecondsToTime with one
-- term rounding up (every unit up) [verified: blizzard_sharedxml/timeutil.lua:364–426], then SecondsToTimeAbbrev, which
-- the buff icons use (seconds as they are, larger units up) [verified: timeutil.lua:463–483]; both switch at 1.5 units.
TimeLine.DEFAULTS = { "1.5/up/up", "1.5/down/up" }

-- The rule for a family: the one left, else the first of Blizzard's no line has ruled out. → candidate | nil, why
function TimeLine.rule(family)
  local s = state(family)
  local left, last, alive = 0, nil, {}
  for _, c in ipairs(candidates) do
    if not s.out[c.id] then
      left = left + 1
      last = c
      alive[c.id] = c
    end
  end
  if left == 0 then return nil, "no rule fits what the game showed" end
  if left == 1 then return last end
  for _, id in ipairs(TimeLine.DEFAULTS) do
    if alive[id] then return alive[id] end
  end
  return nil, ("%d rules still possible, Blizzard's ruled out"):format(left)
end

-- What the client wrote for `seconds` left rules out every candidate that would have written something else.
-- → candidates left
-- The last few lines each family learnt from and could not read (/wfj debug), kept for this session only.
TimeLine.recent = { aura = {}, cooldown = {} }
local function keepRecent(family, line)
  local list = TimeLine.recent[family]
  if not list then return end
  if list[#list] == line then return end
  list[#list + 1] = line
  if #list > 4 then table.remove(list, 1) end
end

function TimeLine.observe(family, seconds, text)
  if type(seconds) ~= "number" or secret(seconds, text) or seconds <= 0 then return nil end
  local fam, unit, n = TimeLine.parse(text)
  if fam ~= family then
    keepRecent(family, ("unread %.1f s: %q"):format(seconds, tostring(text)))
    return nil
  end
  keepRecent(family, ("%.1f s -> %s %d"):format(seconds, unit, n))
  local s = state(family)
  s.seen = (s.seen or 0) + 1
  local left = 0
  for _, c in ipairs(candidates) do
    if not s.out[c.id] then
      local u, m = TimeLine.predict(c, seconds)
      if u ~= unit or m ~= n then s.out[c.id] = true else left = left + 1 end
    end
  end
  return left
end

local formatters = {}
-- The client's rule formatter for a family's rule, in Japanese. → formatter | nil, why
local function formatterFor(family, c)
  local k = family .. ":" .. c.id
  if formatters[k] then return formatters[k] end
  local create = Compat.resolve("C_StringUtil.CreateNumericRuleFormatter")
  local modes = Compat.resolve("Enum.NumericRuleFormatRounding")
  if type(create) ~= "function" or type(modes) ~= "table" then return nil, "no rule formatter" end
  local breakpoints = {}
  for _, u in ipairs(UNITS) do
    local fmt = japaneseFormat(family, u.name)
    if not fmt then return nil, "no Japanese for " .. u.name end
    local mode = modes[ENUM_ROUNDING[u.size == 1 and c.sec or c.big]]
    if u.size == 1 then
      breakpoints[#breakpoints + 1] = { threshold = 0, step = 1, rounding = mode, format = fmt }
    else
      breakpoints[#breakpoints + 1] = { threshold = u.size * c.switch, format = fmt,
        components = { { div = u.size, step = 1, rounding = mode } } }
    end
  end
  local ok, formatter = pcall(function()
    local f = create()
    f:SetBreakpoints(breakpoints)
    return f
  end)
  if not ok or not formatter then return nil, "formatter refused: " .. tostring(formatter) end
  formatters[k] = formatter
  return formatter
end

-- The Japanese for `seconds` left by a rule, in Lua. → text | nil
local function render(family, c, seconds)
  local unit, n = TimeLine.predict(c, seconds)
  local fmt = japaneseFormat(family, unit)
  return fmt and fmt:format(n) or nil
end
TimeLine.render = render

-- On a readable line with its duration object: the client's formatter must give what the rule gives, or no hidden
-- line of this family is written. → true | false | nil (nothing to check yet)
function TimeLine.checkFormatter(family, duration, seconds)
  local c = TimeLine.rule(family)
  if not c or type(duration) ~= "table" or secret(seconds) then return nil end
  local formatter = formatterFor(family, c)
  if not formatter then return nil end
  local ok, text = pcall(duration.FormatRemainingDuration, duration, formatter)
  if not ok or secret(text) then return nil end
  local want = render(family, c, seconds)
  local s = state(family)
  s.formatterRule = c.id
  if text == want then
    s.formatter = true
  else
    s.formatter = false
    s.mismatch = ("formatter %q, rule %q at %.1f s"):format(tostring(text), tostring(want), seconds)
  end
  return s.formatter
end

-- At login: the client's formatter for each family's rule, checked against the rule on durations the addon makes
-- itself, around every switch point. → true when both families' formatters agree
local SELF_TEST = { 0.4, 1.4, 1.6, 12.3, 59.4, 59.6, 60.4, 75.2, 89.6, 90.4, 1799.7, 3599.4, 5399.6, 5400.4, 86399.6,
  129599.6, 129600.4 }
function TimeLine.selfTest()
  local create = Compat.resolve("C_DurationUtil.CreateDuration")
  local clock = Compat.resolve("GetTime")
  if type(create) ~= "function" or type(clock) ~= "function" then return false end
  local all = true
  for family in pairs(TimeLine.FAMILIES) do
    local c = TimeLine.rule(family)
    local formatter = c and formatterFor(family, c)
    local s = state(family)
    if not formatter then
      all = false
    else
      local ok = true
      for _, seconds in ipairs(SELF_TEST) do
        local okD, duration = pcall(create)
        if not okD or not duration then ok = false; break end
        local now = clock()
        pcall(duration.SetTimeFromStart, duration, now, seconds)
        local okF, text = pcall(duration.FormatRemainingDuration, duration, formatter)
        local want = render(family, c, seconds)
        if not okF or text ~= want then
          ok = false
          s.mismatch = ("self-test: formatter %q, rule %q at %.1f s"):format(tostring(text), tostring(want), seconds)
          break
        end
      end
      s.formatter = ok
      s.formatterRule = c.id
      all = all and ok
    end
  end
  return all
end

local function ready(family)
  local c, why = TimeLine.rule(family)
  if not c then return nil, why end
  local s = state(family)
  if s.formatter == false then return nil, "formatter disagreed: " .. tostring(s.mismatch) end
  return c
end

-- A readable number of seconds written in Japanese. → true | nil, why
function TimeLine.writeSeconds(fs, family, seconds)
  local c, why = TimeLine.rule(family)
  if not c then return nil, why end
  local text = render(family, c, seconds)
  if not text then return nil, "no Japanese" end
  fs:SetText(text)
  return true, ("%.1f s, written"):format(seconds)
end

-- A hidden duration written in Japanese by the client's formatter. → true | nil, why
function TimeLine.writeDuration(fs, family, duration)
  local c, why = ready(family)
  if not c then return nil, why end
  local s = state(family)
  if s.formatter ~= true or s.formatterRule ~= c.id then
    TimeLine.selfTest()
    if s.formatter ~= true or s.formatterRule ~= c.id then return nil, "formatter not checked for rule " .. c.id end
  end
  local formatter, bad = formatterFor(family, c)
  if not formatter then return nil, bad end
  local ok, text = pcall(duration.FormatRemainingDuration, duration, formatter)
  if not ok then return nil, "format refused: " .. tostring(text) end
  fs:SetText(text)
  return true, "hidden, written by the client"
end

-- Whether there is still something to learn: a family with more than one rule left, or a formatter not checked.
function TimeLine.learning()
  for family in pairs(TimeLine.FAMILIES) do
    if not TimeLine.rule(family) or state(family).formatter ~= true then return true end
  end
  return false
end

-- One line for /wfj debug per family.
function TimeLine.status()
  local out = {}
  for _, family in ipairs({ "aura", "cooldown" }) do
    local s = state(family)
    local c, why = TimeLine.rule(family)
    local formatter = s.formatter == true and "checked" or s.formatter == false and ("disagreed: " .. tostring(
      s.mismatch)) or "not checked yet"
    out[#out + 1] = ("%s: %s, %d lines seen, formatter %s"):format(family, c and ("rule " .. c.id) or why,
      s.seen or 0, formatter)
    if not c then
      local left = {}
      for _, cand in ipairs(candidates) do
        if not s.out[cand.id] then left[#left + 1] = cand.id end
      end
      out[#out + 1] = ("  %s rules left (switch/seconds/larger units): %s"):format(family, table.concat(left, " "))
    end
    for _, line in ipairs(TimeLine.recent[family] or {}) do out[#out + 1] = "  " .. family .. " " .. line end
  end
  return out
end
