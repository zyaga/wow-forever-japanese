-- UI/ChatUnlisted.lua: finds the client interface string a chat line was written from when the addon has no
-- Japanese for that line, and hands the collector that string's NAME (Core/Collector recordUiKey). The game's own
-- code writes many chat lines from interface strings no file lists ("%s seems to be sobering up."), so they can
-- only be found in play.
-- Only the name is kept. The line is never stored, shipped or sent: it may name a player, and the addon keeps no
-- English game text. A line waits in memory, this session only, until it has been looked up.
-- UI/ChatSystem calls ChatUnlisted.seen(line) for a line of a plain chat type (never one a player typed, never a
-- secret value) that no dictionary English, no chat key's template and no NPC line answered.
-- The index: the client's interface strings are plain globals. Each string value under an all-capitals name that
-- the addon has no row for becomes a candidate: a format string as the anchored pattern Core/UIStrings makes of a
-- chat key's template (UIStrings.chatPattern, so the same specifiers, plural forms and limits: a `%s` takes no
-- full stop), a string with no specifier as its exact text. Globals are only read, never written.
-- Cost: nothing until the first such line. Then the globals are walked and the lines matched in slices of
-- BUDGET_MS per frame, out of combat only (a walk begun before combat stops at its next slice and goes on when
-- Main reports the combat over). A Forever client holds about 27,000 interface strings among some 150,000
-- globals; with the strings the addon ships taken out, about 2,200 format strings and 8,700 sentences are left as
-- candidates.
local _, WFJ = ...
local ChatUnlisted = {}
WFJ.ChatUnlisted = ChatUnlisted

local SURFACE = "chatsystem" -- these are the chat surface's lines: its names are read under the same surface
local Compat = WFJ.Compat

local CANDIDATES = { globals = { "_G" }, clock = { "debugprofilestop" }, after = { "C_Timer.After" },
  inCombat = { "InCombatLockdown" } }
for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end

-- The letters a template must hold outside its specifiers and markup. Under six sit the label shapes that fit
-- almost any line once their `%s` may be any text ("%s: %s", "%s and %s", "%s (%s)", "Rank %d", "Level %d"); the
-- shortest sentences the game writes into chat have seven or more ("%s has died.").
ChatUnlisted.MIN_LETTERS = 6
ChatUnlisted.MAX_TEXT = 400 -- a longer string is a help text or a page, never one chat line
ChatUnlisted.BUDGET_MS = 2 -- of a frame's 16 ms at 60 frames a second
ChatUnlisted.CHECK_EVERY = 64 -- globals or templates between two readings of the clock
ChatUnlisted.QUEUE_MAX = 32 -- lines waiting for a lookup; one that arrives past it is dropped
ChatUnlisted.MEMO_MAX = 512 -- lines already handed over this session, so a repeated line is looked up once
ChatUnlisted.MAX_RESTARTS = 3 -- a walk the client's own writes broke is begun again this many times

local NAME = "^[A-Z][A-Z0-9_]*$"

local templates, exact = {}, {} -- { name, pattern, word } · text → { name, … }
local taken = {} -- names already in the index (a walk begun again meets them twice)
local state, cursor, restarts = "idle", nil, 0 -- idle → building → ready
local queue, current = {}, nil -- lines to look up · the one being matched: { line, at, found, set }
local lineMemo, lineCount = {}, 0
local recorded = {} -- names handed to the collector this session
local scheduled, failed = false, false

local function secret(value) return Compat.secret(value) end

local function hasJapanese(name)
  local index = WFJ.UIIndex
  return index ~= nil and type(index.rows) == "table" and index.rows[name] ~= nil
end

-- The letters of a template's literal text: colour codes, textures, atlases and links hold letters that are no
-- words.
local function letters(parts)
  local n = 0
  for _, p in ipairs(parts) do
    if p.lit then
      local text = WFJ.UIStrings.stripColour(p.lit):gsub("|[TA].-|[ta]", ""):gsub("|H.-|h", ""):gsub("|[nh]", "")
      local _, count = text:gsub("%a", "")
      n = n + count
    end
  end
  return n
end

-- One global: a candidate when it is an interface string the addon has no Japanese for and its text could be a
-- whole chat line. → true when it was added
local function consider(name, text)
  if type(name) ~= "string" or type(text) ~= "string" or secret(text) then return false end
  if taken[name] or not name:find(NAME) or text == "" or #text > ChatUnlisted.MAX_TEXT then return false end
  if hasJapanese(name) then return false end
  local U = WFJ.UIStrings
  local parts, argc = U.parse(text)
  if letters(parts) < ChatUnlisted.MIN_LETTERS then return false end
  if argc == 0 then
    -- no specifier: only a sentence (several words) can be a chat line; its text is the line, "%%" a percent sign
    local plain = {}
    for _, p in ipairs(parts) do plain[#plain + 1] = p.lit end
    local line = table.concat(plain)
    if not line:find(" ", 1, true) then return false end
    local list = exact[line] or {}
    list[#list + 1] = name
    exact[line] = list
  else
    local forms = U.pluralForms(text)
    if not forms then return false end
    for _, form in ipairs(forms) do
      local pattern, _, _, word = U.chatPattern(form)
      templates[#templates + 1] = { name = name, pattern = pattern, word = word }
    end
  end
  taken[name] = true
  return true
end
ChatUnlisted.consider = consider

-- → a function that says whether this slice's time is up. Without the client's clock a slice is one batch.
local function budget()
  local clock = Compat.get(SURFACE, "clock")
  if type(clock) ~= "function" then
    local asked = false
    return function()
      local was = asked
      asked = true
      return was
    end
  end
  local stop = clock() + ChatUnlisted.BUDGET_MS
  return function() return clock() >= stop end
end

-- Walks the globals from where the last slice stopped. `next` raises when the key it resumes from is gone (the
-- client cleared that global meanwhile): the walk begins again, and `taken` keeps what it already has.
-- → true when the walk is over
local function build(over)
  local globals = Compat.get(SURFACE, "globals")
  if type(globals) ~= "table" then return true end
  local n = 0
  while true do
    local ok, name, value = pcall(next, globals, cursor)
    if not ok then
      restarts, cursor = restarts + 1, nil
      if restarts > ChatUnlisted.MAX_RESTARTS then return true end -- what it has is the index
    elseif name == nil then
      return true
    else
      cursor = name
      consider(name, value)
    end
    n = n + 1
    if n % ChatUnlisted.CHECK_EVERY == 0 and over() then return false end
  end
end

local function found(job, name)
  if not job.set[name] then
    job.set[name] = true
    job.found[#job.found + 1] = name
  end
end

-- Matches the current line against the templates from where the last slice stopped. A line that fits several
-- strings keeps each name (they may share an English); one that fits none keeps nothing. → true when done
local function match(job, over)
  if job.at == 0 then
    for _, name in ipairs(exact[job.line] or {}) do found(job, name) end
    job.at = 1
  end
  local line, n = job.line, 0
  while job.at <= #templates do
    local t = templates[job.at]
    if (t.word == "" or line:find(t.word, 1, true)) and line:find(t.pattern) then found(job, t.name) end
    job.at = job.at + 1
    n = n + 1
    if n % ChatUnlisted.CHECK_EVERY == 0 and over() then return false end
  end
  table.sort(job.found)
  for _, name in ipairs(job.found) do
    if not recorded[name] then
      recorded[name] = true
      WFJ.Collector.recordUiKey(name)
    end
  end
  return true
end

local function pendingWork()
  return not failed and (current ~= nil or #queue > 0)
end

local schedule

-- One slice: the index first, then the waiting lines. → true when work is left for a later frame
local function work()
  local over = budget()
  if state ~= "ready" then
    state = "building"
    if not build(over) then return true end
    state = "ready"
    if over() then return pendingWork() end
  end
  while true do
    if not current then
      local line = table.remove(queue, 1)
      if not line then return false end
      current = { line = line, at = 0, found = {}, set = {} }
    end
    if not match(current, over) then return true end
    current = nil
    if over() then return pendingWork() end
  end
end

-- The timer's callback. In combat nothing runs and no timer is left behind: Main calls flush when it ends.
function ChatUnlisted.step()
  scheduled = false
  if failed then return end
  local inCombat = Compat.get(SURFACE, "inCombat")
  if type(inCombat) == "function" and inCombat() then return end
  local ok, more = pcall(work)
  if not ok then
    -- never a second try at whatever raised: the lines are let go, and the chat goes on untouched
    failed, queue, current = true, {}, nil
    if WFJ.Diag then WFJ.Diag.log(SURFACE, "unlisted chat lookup stopped: " .. tostring(more)) end
    return
  end
  if more then schedule() end
end

schedule = function()
  if scheduled then return end
  local after = Compat.get(SURFACE, "after")
  if type(after) ~= "function" then return end
  scheduled = true
  after(0, ChatUnlisted.step)
end

-- Combat ended: the lines that waited are looked up.
function ChatUnlisted.flush()
  if pendingWork() then schedule() end
end

-- A chat line of a plain type that stayed English. Nothing is looked up here: the line waits for a slice.
-- → true when it was queued
function ChatUnlisted.seen(line)
  -- the secret test before the empty test: comparing a secret value raises
  if failed or type(line) ~= "string" or secret(line) or line == "" then return false end
  if not WFJ.Settings.get("collector.enabled") then return false end -- nothing would be kept: pay nothing
  if lineMemo[line] or #queue >= ChatUnlisted.QUEUE_MAX then return false end
  if lineCount >= ChatUnlisted.MEMO_MAX then lineMemo, lineCount = {}, 0 end
  lineMemo[line], lineCount = true, lineCount + 1
  queue[#queue + 1] = line
  schedule()
  return true
end

-- → state ("idle" | "building" | "ready"), templates, exact strings, lines waiting
function ChatUnlisted.status()
  local sentences = 0
  for _ in pairs(exact) do sentences = sentences + 1 end
  return state, #templates, sentences, #queue + (current and 1 or 0)
end
