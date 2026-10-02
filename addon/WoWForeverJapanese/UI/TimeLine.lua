-- UI/TimeLine.lua: the cooldown countdown of a spell or item tooltip ("Cooldown remaining: 2 sec",
-- ITEM_COOLDOWN_TIME around INT_SPELL_DURATION_*), in Japanese while the client hides the number. In combat the
-- seconds left are a secret value: the addon may hand them on but not read them. So the line is written by the
-- client itself, applying a rule the addon gives it to its own hidden duration: C_Spell.GetSpellCooldownDuration
-- answers a tainted caller [verified: spelldocumentation.lua:327–341], LuaDurationObject:FormatRemainingDuration takes
-- a numeric rule formatter [verified: luadurationobjectapidocumentation.lua:145–159], and FontString:SetText takes
-- the secret result [verified: simplefontstringapidocumentation.lua:664–667].
-- The rule is Blizzard's own one-term SecondsToTime with rounding up: seconds rounded up, a larger unit from 1.5 of
-- it, rounded up [verified: blizzard_sharedxml/timeutil.lua:364–426]. The client's compiled tooltip code may round
-- a boundary second differently; a readable countdown is translated by the UI dictionary, not by this rule, so the
-- rule only ever writes a line the addon could not read anyway.
local _, WFJ = ...
local TimeLine = {}
WFJ.TimeLine = TimeLine
local Compat = WFJ.Compat

local UNITS = { { name = "sec", size = 1 }, { name = "min", size = 60 }, { name = "hour", size = 3600 },
  { name = "day", size = 86400 } }
TimeLine.UNITS = UNITS
local KEYS = { sec = "INT_SPELL_DURATION_SEC", min = "INT_SPELL_DURATION_MIN", hour = "INT_SPELL_DURATION_HOURS",
  day = "INT_SPELL_DURATION_DAYS" }
local WRAP = "ITEM_COOLDOWN_TIME"
local SWITCH = 1.5 -- a larger unit takes over at 1.5 of it
local SAMPLE = 37

-- → unit name, number: what the rule writes for `seconds` left
function TimeLine.predict(seconds)
  for i = #UNITS, 2, -1 do
    local u = UNITS[i]
    if seconds >= u.size * SWITCH then return u.name, math.ceil(seconds / u.size - 1e-9) end
  end
  return "sec", math.ceil(seconds - 1e-9)
end

-- The English the client writes for a unit and number: its own template, with the |4singular:plural; code resolved.
local function english(unit, n)
  local template, wrap = Compat.resolve(KEYS[unit]), Compat.resolve(WRAP)
  if type(template) ~= "string" or type(wrap) ~= "string" then return nil end
  local text = template:gsub("|4([^:;]*):([^;]*);", n == 1 and "%1" or "%2"):format(n)
  return wrap:format(text)
end

-- The Japanese line for a unit, with %d where the number goes: a sample put through the dictionary.
local japanese = {}
local function japaneseFormat(unit)
  if japanese[unit] then return japanese[unit] end
  local en = english(unit, SAMPLE)
  local index = WFJ.UIIndex
  if not en or not index then return nil end
  local key, args = index:match(en)
  if not key then return nil end
  local ja = WFJ.Render.preview("tooltip.timeline", en, nil, "ui", "ui", key, { args = args })
  if type(ja) ~= "string" or ja == en then return nil end
  local fmt, found = ja:gsub("%%", "%%%%"):gsub(tostring(SAMPLE), "%%d", 1)
  if found ~= 1 then return nil end
  japanese[unit] = fmt
  return fmt
end

-- The Japanese for a readable number of seconds left, in Lua. → text | nil
function TimeLine.render(seconds)
  local unit, n = TimeLine.predict(seconds)
  local fmt = japaneseFormat(unit)
  return fmt and fmt:format(n) or nil
end

local formatter, formatterWhy
-- The client's rule formatter carrying the rule and the Japanese formats. → formatter | nil, why
function TimeLine.formatter()
  if formatter then return formatter end
  local create = Compat.resolve("C_StringUtil.CreateNumericRuleFormatter")
  local modes = Compat.resolve("Enum.NumericRuleFormatRounding")
  if type(create) ~= "function" or type(modes) ~= "table" then
    formatterWhy = "no rule formatter"
    return nil, formatterWhy
  end
  local breakpoints = {}
  for _, u in ipairs(UNITS) do
    local fmt = japaneseFormat(u.name)
    if not fmt then formatterWhy = "no Japanese for " .. u.name; return nil, formatterWhy end
    if u.size == 1 then
      breakpoints[#breakpoints + 1] = { threshold = 0, step = 1, rounding = modes.Up, format = fmt }
    else
      breakpoints[#breakpoints + 1] = { threshold = u.size * SWITCH, format = fmt,
        components = { { div = u.size, step = 1, rounding = modes.Up } } }
    end
  end
  local ok, f = pcall(function()
    local created = create()
    created:SetBreakpoints(breakpoints)
    return created
  end)
  if not ok or not f then formatterWhy = "formatter refused: " .. tostring(f); return nil, formatterWhy end
  formatter, formatterWhy = f, nil
  return formatter
end

-- A readable number of seconds left, written in Japanese. → true | nil, why
function TimeLine.writeSeconds(fs, seconds)
  if type(seconds) ~= "number" or seconds <= 0 then return nil, "no cooldown running" end
  local text = TimeLine.render(seconds)
  if not text then return nil, "no Japanese for the countdown" end
  fs:SetText(text)
  return true, ("%.1f s, written"):format(seconds)
end

-- A hidden duration, written in Japanese by the client's formatter. → true | nil, why
function TimeLine.writeDuration(fs, duration)
  local f, why = TimeLine.formatter()
  if not f then return nil, why end
  -- the client's duration is userdata; a test's model is a table
  local t = type(duration)
  if (t ~= "userdata" and t ~= "table") or type(duration.FormatRemainingDuration) ~= "function" then
    return nil, "no duration object"
  end
  local ok, text = pcall(duration.FormatRemainingDuration, duration, f)
  if not ok then return nil, "format refused: " .. tostring(text) end
  fs:SetText(text)
  return true, "hidden, written by the client"
end

-- One line for /wfj debug.
function TimeLine.status()
  if formatter then return "countdown formatter ready (seconds up, a larger unit from 1.5 of it, up)" end
  return "countdown formatter not built yet" .. (formatterWhy and (": " .. formatterWhy) or "")
end
