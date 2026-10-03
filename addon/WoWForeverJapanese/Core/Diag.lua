-- Core/Diag.lua: the addon's own diagnostics log, kept in its SavedVariables WFJ_Log so a problem seen in game can be
-- read afterwards, across reloads and up to the last save before a crash (docs/systems/diagnostics.md).
-- Any module writes to it with Diag.log(kind, message, fields). Built in:
--   session  one entry per load: client build, addon version, Lua memory, and every surface whose setup failed;
--   blocked  the client's ADDON_ACTION_BLOCKED / ADDON_ACTION_FORBIDDEN naming this addon (a taint, and the
--            protected function it reached);
--   hook     a method this addon post-hooked on a single frame (Diag.watch) that no longer reads as a function:
--            what is left on the frame's own table and on what it inherits, and the Lua memory then;
--   memory   the Lua memory, sampled on a timer.
-- The log holds no text the game showed, no names and no chat: only addon and frame names, counts and times.
local _, WFJ = ...
local Diag = {}
WFJ.Diag = Diag

Diag.VERSION = 1
Diag.MAX_ENTRIES = 500
Diag.MAX_SESSIONS = 50 -- session entries kept; the oldest go past this
Diag.MAX_LINES = 50 -- the most /wfj log prints
Diag.CHECK_INTERVAL = 5 -- seconds between hook checks
Diag.MEMORY_EVERY = 60 -- hook checks between memory samples (5 minutes)
Diag.BLOCK_EVENTS = { "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }

local db -- WFJ_Log
local deps = {
  now = function() return 0 end, mem = function() return 0 end, clock = function() return "" end,
  print = function() end,
}
local watched = {} -- { obj, method, label, lost }
Diag.watched = watched
local said = {} -- chat lines already printed this session, by text
local repeats = {} -- kind .. "\0" .. message → this session's entry, which counts its repeats

-- Injects the clock, memory and print functions (Main passes the client's; specs pass stubs).
function Diag.setDeps(d)
  for k, v in pairs(d or {}) do deps[k] = v end
end

-- Takes the saved table (a fresh one when it is missing or from another version). → the table to save
function Diag.load(saved)
  if type(saved) ~= "table" or saved.version ~= Diag.VERSION or type(saved.entries) ~= "table" then
    saved = { version = Diag.VERSION, entries = {} }
  end
  db = saved
  return db
end

-- Over the cap, the oldest memory sample goes first, then the oldest problem entry, then the oldest session; and
-- never more than MAX_SESSIONS session entries. A problem entry is never dropped to make room for a session.
local function oldest(list, keep)
  for i, e in ipairs(list) do
    if keep(e) then return i end
  end
  return nil
end
local function trim(list)
  local sessions = 0
  for _, e in ipairs(list) do if e.kind == "session" then sessions = sessions + 1 end end
  while sessions > Diag.MAX_SESSIONS do
    table.remove(list, oldest(list, function(e) return e.kind == "session" end))
    sessions = sessions - 1
  end
  while #list > Diag.MAX_ENTRIES do
    local drop = oldest(list, function(e) return e.kind == "memory" end)
      or oldest(list, function(e) return e.kind ~= "session" end) or 1
    local gone = table.remove(list, drop)
    local key = tostring(gone.kind) .. "\0" .. tostring(gone.msg)
    if repeats[key] == gone then repeats[key] = nil end -- its next repeat starts a new entry
  end
end

-- Appends one entry. fields: a table of string / number / boolean values (anything else is written as its type).
-- The same kind and message again in this session adds to that entry's count (n) and its last time (last) instead
-- of a new entry, so one thing repeating every few seconds never pushes the rest out. Sessions and memory samples
-- are always new entries. → the entry, or nil before load
function Diag.log(kind, message, fields)
  if not db then return nil end
  kind, message = tostring(kind), tostring(message or "")
  local at = deps.clock()
  local key = kind .. "\0" .. message
  local seen = kind ~= "session" and kind ~= "memory" and repeats[key] or nil
  if seen then
    seen.n, seen.last = (seen.n or 1) + 1, at
    return seen
  end
  local e = { kind = kind, msg = message, at = at, up = math.floor(deps.now()), memKB = math.floor(deps.mem()) }
  for k, v in pairs(fields or {}) do
    local t = type(v)
    if e[k] == nil and k ~= "n" and k ~= "last" then -- an entry's own fields are never overwritten
      e[k] = (t == "string" or t == "number" or t == "boolean") and v or t
    end
  end
  local list = db.entries
  list[#list + 1] = e
  if kind ~= "session" and kind ~= "memory" then repeats[key] = e end
  trim(list)
  return e
end

-- Prints a line once per session.
local function say(text)
  if said[text] then return end
  said[text] = true
  deps.print(text)
end

-- The name a frame answers to. → string
function Diag.nameOf(obj)
  if type(obj) == "table" and type(obj.GetName) == "function" then
    local ok, name = pcall(obj.GetName, obj)
    if ok and type(name) == "string" then return name end
  end
  return "?"
end

-- Watches obj[method], a method this addon post-hooked on that one frame. → true when newly watched
function Diag.watch(obj, method, label)
  if type(obj) ~= "table" or type(method) ~= "string" then return false end
  for _, w in ipairs(watched) do
    if w.obj == obj and w.method == method then return false end
  end
  -- the value hooksecurefunc just installed: another function there later means our hook was replaced
  watched[#watched + 1] = { obj = obj, method = method, label = tostring(label or "?"), fn = obj[method] }
  return true
end

-- Where a method went: its type on the frame's own table, and in the table the frame inherits from.
local function whereGone(obj, method)
  local mt = getmetatable(obj)
  local index = type(mt) == "table" and mt.__index or nil
  return type(rawget(obj, method)), type(index) == "table" and type(rawget(index, method)) or "none"
end

local function field(obj, key) return obj[key] end

-- One pass over the watched hooks: a hook is gone when its method is no longer a function, or is another function
-- than the one hooksecurefunc left there. → the number found gone in this pass
function Diag.checkHooks()
  local found = 0
  for _, w in ipairs(watched) do
    if not w.lost then
      local ok, value = pcall(field, w.obj, w.method)
      if not ok or type(value) ~= "function" or (w.fn ~= nil and value ~= w.fn) then
        w.lost, found = true, found + 1
        local own, inherited = whereGone(w.obj, w.method)
        local seen = not ok and "error" or type(value) ~= "function" and type(value) or "replaced"
        Diag.log("hook", w.label .. ":" .. w.method, { frame = w.label, method = w.method, seen = seen, own = own,
          inherited = inherited })
        say(("WFJ: %s:%s is gone (%s). Logged; /wfj log shows it."):format(w.label, w.method, seen))
      end
    end
  end
  return found
end

-- A blocked or forbidden action the client names this addon in. → the entry, or nil when it is another addon's
function Diag.onBlocked(event, addon, fn, addonName)
  if addon ~= addonName then return nil end
  local e = Diag.log("blocked", tostring(fn), { event = event, fn = tostring(fn) })
  say(("WFJ: the game blocked %s (%s). Logged; /wfj log shows it."):format(tostring(fn), event))
  return e
end

-- The session entry. info = { build, version, initErrors = { {surface, err}, … } }
function Diag.session(info)
  info = info or {}
  local failed = {}
  for _, e in ipairs(info.initErrors or {}) do failed[#failed + 1] = tostring(e.surface) end
  Diag.log("session", "load", { build = tostring(info.build or "?"), version = tostring(info.version or "?"),
    failed = table.concat(failed, ",") })
end

-- A surface whose setup failed (Main's step guard, at load and on a later ADDON_LOADED).
function Diag.initFailed(surface, err)
  return Diag.log("init", tostring(surface), { err = tostring(err):sub(1, 300) })
end

-- The last n entries (1..MAX_LINES, 10 by default), newest last, as one line each. → { string, … }
function Diag.lines(n)
  n = math.max(1, math.min(math.floor(tonumber(n) or 10), Diag.MAX_LINES))
  local out, list = {}, db and db.entries or {}
  for i = math.max(1, #list - n + 1), #list do
    local e = list[i]
    local times = (e.n or 1) > 1 and (" ×%d, last %s"):format(e.n, e.last or "?") or ""
    out[#out + 1] = ("%s %s %s%s (%d KB)"):format(e.at or "", e.kind or "", e.msg or "", times, e.memKB or 0)
  end
  return out
end

-- One timer tick (Main runs it every CHECK_INTERVAL seconds): the hook checks, and every MEMORY_EVERY ticks a
-- memory sample. → the number of hooks found gone
local ticks = 0
function Diag.tick()
  ticks = ticks + 1
  if ticks % Diag.MEMORY_EVERY == 0 then Diag.log("memory", "sample") end
  return Diag.checkHooks()
end
