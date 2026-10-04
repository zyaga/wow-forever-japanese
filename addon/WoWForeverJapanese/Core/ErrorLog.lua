-- Core/ErrorLog.lua: the addon's own Lua errors, kept in the problem log (WFJ_Log.errors) for a bug report
-- (docs/systems/diagnostics.md, ADR-057). Forever hides Lua errors by default, so a player never sees ours.
-- At file load it wraps the client's current error handler: the wrapper records the error, inside pcall, and always
-- hands it to the previous handler unchanged, so the game's error window, BugSack and other addons behave as before.
-- An error is kept only when it was raised in a file under WoWForeverJapanese/: the file its message names, or, for a
-- message without one, the top Lua frame of its stack. No locals, and the player's name is written as <name>.
--   ErrorLog.install(get, set) · ErrorLog.setDeps(d) · ErrorLog.load(WFJ_Log) · ErrorLog.stack(api)
--   ErrorLog.record(msg) · ErrorLog.recordCaught(msg) · ErrorLog.isOurs(msg, stack) · ErrorLog.scrub(text, name)
--   ErrorLog.rescrub() · ErrorLog.checkOurs(get) · ErrorLog.ours() · ErrorLog.unsent() · ErrorLog.markSent(items)
--   ErrorLog.status()
-- deps = { clock() → string, name() → the player's name | nil, stack() → string | nil, print(text),
--          accessible(value) → false when the message may not be read (a secret value) }
local _, WFJ = ...
local ErrorLog = {}
WFJ.ErrorLog = ErrorLog

ErrorLog.MAX_ERRORS = 30 -- 30 errors at their longest still fit one issue body when pasted
ErrorLog.MAX_MESSAGE = 500
ErrorLog.MAX_STACK = 1000
ErrorLog.MAX_STACK_LINES = 12
ErrorLog.NAME = "<name>"
ErrorLog.SAY = "WFJ: the addon hit a Lua error. /wfj bug reports it."

local deps = {
  clock = function() return "" end, name = function() return nil end, stack = function() return nil end,
  print = function() end, accessible = function() return true end,
}
local db -- WFJ_Log, once loaded
local pending = {} -- errors caught before WFJ_Log loaded
local wrapper -- the handler this addon installed
local active -- false when another handler replaced ours (checkOurs)
local seen = false -- one of our errors reached the wrapper this session
local said = false
local busy = false

function ErrorLog.setDeps(d)
  for k, v in pairs(d or {}) do deps[k] = v end
end

-- The stack at the error, read the way the client's own handler reads it: the current height less the error's
-- [verified: forever-ui Blizzard_ScriptErrors/Blizzard_ScriptErrors.lua:49–64]. A handler called directly, outside an
-- error, has no error height: offset 0, as the client does. A client without the height functions gives no stack, and
-- the message alone decides. api = { debugstack, height, errorHeight } → string | nil
function ErrorLog.stack(api)
  api = api or {}
  if type(api.debugstack) ~= "function" or type(api.height) ~= "function" or type(api.errorHeight) ~= "function" then
    return nil
  end
  local errorHeight = api.errorHeight()
  return api.debugstack(api.height() - ((errorHeight or 1) - 1))
end

-- The client's stack paths: "Interface/AddOns/WoWForeverJapanese/UI/X.lua:12:", the same with "@" or inside
-- [string "..."], and front-truncated to the last ~55 characters: "...rface/AddOns/WoWForeverJapanese/UI/X.lua:12:"
-- [verified: the client's own crash reports, Errors/*.txt, stack lines #7 and #9]. A long Data path can lose the
-- "WoW" too ("...oWForeverJapanese/Data/..."), so a truncated prefix only has to end like "WoW".
local function prefixIsOurs(prefix)
  local rest = prefix
  if prefix:sub(1, 3) == "..." then
    rest = prefix:sub(4)
    if rest == "" then return true end
    if #rest < 3 then return ("WoW"):sub(-#rest) == rest end
  end
  return rest == "WoW" or rest:sub(-4):match("^[/\\@]WoW$") ~= nil
end

local function namesOurs(text)
  if type(text) ~= "string" then return false end
  for prefix in text:gmatch("([^%s\"'<>%[%]%(%)]*)ForeverJapanese[/\\]") do
    if prefixIsOurs(prefix) then return true end
  end
  return false
end

-- The file a message or a stack line starts with ("…/UI/X.lua:12: …" or [string "…"]:12:), or nil.
local function location(text)
  return text:match("^(%[string \".-\"%]):%d+:") or text:match("^([^%s:]+):%d+:")
end

-- The wrapper's own frames: on the stack of a handler called outside an error they sit above the caller.
local function isWrapper(line)
  return line:find("ForeverJapanese[/\\]Core[/\\]ErrorLog%.lua") ~= nil
end

-- → true when the error was raised in a file of this addon: the file the message names; without one, the top Lua
-- frame of the stack (a [C] frame is the client's, and our wrapper's frames never count).
function ErrorLog.isOurs(msg, stack)
  if type(msg) ~= "string" then return false end
  local file = location(msg)
  if file then return namesOurs(file) end
  if type(stack) ~= "string" then return false end
  for line in stack:gmatch("[^\n]+") do
    local frame = line:gsub("^%s+", "")
    if not frame:find("^%[C%]") and not frame:find("^%(tail call%)") and not isWrapper(frame) then
      local where = location(frame)
      return where ~= nil and namesOurs(where)
    end
  end
  return false
end

local function wordByte(b)
  return b ~= nil and (b >= 128 or (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122))
end

-- Every whole-word copy of name in text as <name>. A name inside a longer word, or that is a file name in a path
-- ("/Main.lua"), is left alone: the report needs the file.
function ErrorLog.scrub(text, name)
  if type(text) ~= "string" or type(name) ~= "string" or name == "" then return text end
  local out, i = {}, 1
  while true do
    local s, e = text:find(name, i, true)
    if not s then break end
    local before = text:sub(s - 1, s - 1)
    local whole = not wordByte(text:byte(s - 1)) and not wordByte(text:byte(e + 1))
      and before ~= "/" and before ~= "\\" and text:sub(e + 1, e + 4) ~= ".lua"
    out[#out + 1] = text:sub(i, s - 1) .. (whole and ErrorLog.NAME or name)
    i = e + 1
  end
  out[#out + 1] = text:sub(i)
  return table.concat(out)
end

-- The first n bytes of s, cut back so no UTF-8 character is split.
local function cut(s, n)
  if #s <= n then return s end
  local i = n
  while i > 0 and s:byte(i + 1) and s:byte(i + 1) >= 128 and s:byte(i + 1) < 192 do i = i - 1 end
  return s:sub(1, i)
end

local function trimStack(stack)
  if type(stack) ~= "string" then return "" end
  local lines = {}
  for line in stack:gmatch("[^\n]+") do
    if not isWrapper(line) then lines[#lines + 1] = line end
    if #lines == ErrorLog.MAX_STACK_LINES then break end
  end
  return cut(table.concat(lines, "\n"), ErrorLog.MAX_STACK)
end

-- The message with table and function addresses blanked: the same error raised on another table is one entry.
local function key(msg)
  return (msg:gsub("(%a+): (0?x?%x%x%x%x%x%x+)", function(kind, address)
    if kind == "table" or kind == "function" or kind == "userdata" or kind == "thread" then return kind .. ": ?" end
    return kind .. ": " .. address
  end))
end

-- Over the cap the oldest sent error goes first; with none sent the newest is dropped, so the first errors (most
-- often the cause of the rest) are kept.
local function cap(list)
  while #list > ErrorLog.MAX_ERRORS do
    local drop = #list
    for i, e in ipairs(list) do
      if e.sent then drop = i break end
    end
    table.remove(list, drop)
  end
end

local function say()
  if said then return end
  said = true
  deps.print(ErrorLog.SAY)
end

local function later(a, b)
  if a == nil or a == "" then return b end
  if b == nil or b == "" then return a end
  return b > a and b or a -- the clock's "%Y-%m-%d %H:%M:%S" sorts as text
end

-- Adds e to list: the same error again adds its count. → the stored entry, or nil when the cap dropped it
local function store(list, e)
  local k = key(e.msg)
  for _, old in ipairs(list) do
    if key(old.msg) == k then
      if old.sent then
        -- sent before: a new occurrence for the next report
        old.sent, old.n, old.first, old.stack, old.last = nil, e.n or 1, e.first, e.stack, e.last
      else
        old.n, old.last = (tonumber(old.n) or 1) + (e.n or 1), later(old.last, e.last)
      end
      return old
    end
  end
  list[#list + 1] = e
  cap(list)
  return list[#list] == e and e or nil
end

local function keep(msg, stack)
  seen = true
  local name = deps.name()
  local at = deps.clock()
  local e = { msg = cut(ErrorLog.scrub(msg, name), ErrorLog.MAX_MESSAGE),
    stack = ErrorLog.scrub(trimStack(stack), name), n = 1, first = at, last = at }
  if not db then
    return store(pending, e)
  end
  local kept = store(db.errors, e)
  say()
  return kept
end

-- Records one error from the handler when it is this addon's. → the stored entry, or nil
function ErrorLog.record(msg)
  if not deps.accessible(msg) then return nil end
  msg = tostring(msg)
  local stack = deps.stack()
  if not ErrorLog.isOurs(msg, stack) then return nil end
  return keep(msg, stack)
end

-- Records an error this addon caught itself (a setup step's pcall): it never reaches the handler, and there is no
-- stack left to read, so the message decides. → the stored entry, or nil
function ErrorLog.recordCaught(msg)
  msg = tostring(msg)
  if not ErrorLog.isOurs(msg, nil) then return nil end
  return keep(msg, "")
end

-- Wraps the current handler once. get / set: the client's geterrorhandler and seterrorhandler. → true when installed
function ErrorLog.install(get, set)
  if wrapper or type(get) ~= "function" or type(set) ~= "function" then return false end
  local prev = get()
  wrapper = function(msg, ...)
    if not busy then -- an error raised while recording is never recorded again
      busy = true
      pcall(ErrorLog.record, msg)
      busy = false
    end
    if type(prev) == "function" then return prev(msg, ...) end
  end
  set(wrapper)
  return true
end

-- A saved entry this version can read: a table with a message. The rest is dropped.
local function valid(e)
  if type(e) ~= "table" or type(e.msg) ~= "string" then return false end
  e.n = tonumber(e.n) or 1
  e.stack = type(e.stack) == "string" and e.stack or ""
  return true
end

-- Takes WFJ_Log (after Diag.load) and stores what was caught before it loaded. → the errors list
function ErrorLog.load(saved)
  if type(saved) ~= "table" then return nil end
  local list = {}
  for _, e in ipairs(type(saved.errors) == "table" and saved.errors or {}) do
    if valid(e) then list[#list + 1] = e end
  end
  saved.errors = list
  db = saved
  local name, at = deps.name(), deps.clock()
  for _, e in ipairs(pending) do
    e.msg, e.stack = ErrorLog.scrub(e.msg, name), ErrorLog.scrub(e.stack, name)
    if e.first == "" then e.first, e.last = at, at end -- caught before the clock was wired
    store(db.errors, e)
  end
  if #pending > 0 then say() end
  pending = {}
  return db.errors
end

-- Writes the player's name as <name> in every stored error (an error recorded before the name was known).
function ErrorLog.rescrub()
  local name = deps.name()
  if not db or type(name) ~= "string" then return 0 end
  for _, e in ipairs(db.errors) do
    e.msg, e.stack = ErrorLog.scrub(e.msg, name), ErrorLog.scrub(e.stack, name)
  end
  return #db.errors
end

-- Whether our wrapper is still the active handler. BugGrabber replaces it and never calls it (ADR-057).
function ErrorLog.checkOurs(get)
  if type(get) ~= "function" then return ErrorLog.ours() end
  active = wrapper ~= nil and get() == wrapper
  return ErrorLog.ours()
end

-- → true when this addon's errors reach the log: our wrapper is the handler, or one of our errors reached it this
-- session (another addon on top that still calls it)
function ErrorLog.ours()
  return wrapper ~= nil and (active ~= false or seen)
end

-- The errors not sent yet, oldest first. → { entry, … }
function ErrorLog.unsent()
  local out = {}
  for _, e in ipairs(db and db.errors or {}) do
    if not e.sent then out[#out + 1] = e end
  end
  return out
end

-- items: { { msg, last, n }, … } as a report showed them. An error that happened again after the report was built is
-- left unsent: the report did not hold that occurrence. → the number marked
function ErrorLog.markSent(items)
  local n = 0
  for _, item in ipairs(items or {}) do
    for _, e in ipairs(db and db.errors or {}) do
      if e.msg == item.msg and e.last == item.last and e.n == item.n and not e.sent then
        e.sent, n = true, n + 1
      end
    end
  end
  return n
end

-- → { count, unsent }
function ErrorLog.status()
  local list = db and db.errors or {}
  return { count = #list, unsent = #ErrorLog.unsent() }
end

-- the client's own functions; a client or a spec without them leaves capture off
if type(geterrorhandler) == "function" and type(seterrorhandler) == "function" then
  ErrorLog.install(geterrorhandler, seterrorhandler)
end
