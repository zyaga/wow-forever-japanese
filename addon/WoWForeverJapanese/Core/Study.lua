-- Core/Study.lua: studying the saved word list in game (ADR-071, docs/systems/study.md). Pure: no globals, no
-- frames. The card states live in their own SavedVariables table, keyed like the word list (Core/Words):
--   WFJ_Study = { schema = 1, cards = { [key] = { s, d, due, last, reps, lapses } }, days = { [YYYY-MM-DD] = n } }
-- `days` counts the new cards first graded on each day, for the daily cap. Time is epoch seconds (the client's
-- time()); `today` is the client's date("%Y-%m-%d"); both are passed in, never read here.
--   Study.load(saved, keys) → the table to keep in WFJ_Study    Study.prune(keys) → how many cards were dropped
--   Study.next(entries, now, today, newPerDay) → entry, "due" | "new"; nil when nothing is to ask
--   Study.counts(entries, now, today, newPerDay) → { due, newLeft, fresh, nextDue }  (fresh: never graded)
--   Study.answer(key, rating, now, today) → the card's state, or nil when refused
-- Due order is Anki's: a graded card is due once its date has passed (the earliest first), then new cards in the
-- order they were saved while today's new count is under the cap. A card graded Again comes back after one
-- relearn step; Good waits the FSRS interval in whole days, at least one. UI/StudyWindow shows the cards.
local _, WFJ = ...
local Study = {}
WFJ.Study = Study

Study.SCHEMA = 1
Study.RELEARN = 600 -- seconds: Anki's default relearning step
Study.DAY = 86400
Study.AGAIN, Study.GOOD = 1, 3

local list -- the saved table
local frozen = false -- saved by a newer version: kept as it is, never written
local known = {} -- the word list's keys as last seen (load, prune, next): a key not in the list is never graded

local function isCard(c)
  return type(c) == "table" and type(c.s) == "number" and type(c.d) == "number" and type(c.due) == "number"
    and type(c.last) == "number"
end

local function keySet(keys)
  local set = {}
  for _, k in ipairs(keys or {}) do set[k] = true end
  return set
end

-- `keys`: the word list's keys; a card whose word is gone from the list is dropped, and only a listed key is graded.
function Study.load(saved, keys)
  frozen = false
  if type(saved) == "table" and type(saved.schema) == "number" and saved.schema > Study.SCHEMA then
    list, frozen = saved, true
    return saved
  end
  local t = { schema = Study.SCHEMA, cards = {}, days = {} }
  known = keySet(keys)
  if type(saved) == "table" then
    local keep = known
    if type(saved.cards) == "table" then
      for k, c in pairs(saved.cards) do
        if type(k) == "string" and keep[k] and isCard(c) then
          t.cards[k] = { s = c.s, d = c.d, due = c.due, last = c.last,
            reps = type(c.reps) == "number" and c.reps or 0, lapses = type(c.lapses) == "number" and c.lapses or 0 }
        end
      end
    end
    if type(saved.days) == "table" then
      for day, n in pairs(saved.days) do
        if type(day) == "string" and day:find("^%d%d%d%d%-%d%d%-%d%d$") and type(n) == "number" then t.days[day] = n end
      end
    end
  end
  list = t
  return t
end

function Study.readonly() return frozen end
function Study.table() return list end
function Study.card(key) return list and not frozen and list.cards[key] or nil end

-- → the number of cards dropped because their word left the list
function Study.prune(keys)
  if frozen or not list then return 0 end
  known = keySet(keys)
  local n = 0
  for k in pairs(list.cards) do
    if not known[k] then list.cards[k] = nil; n = n + 1 end
  end
  return n
end

local function newToday(today)
  return list.days[today] or 0
end

function Study.next(entries, now, today, newPerDay)
  if frozen or not list then return nil end
  local due, first
  known = {}
  for _, e in ipairs(entries) do
    known[e.key] = true
    local c = list.cards[e.key]
    if c then
      if c.due <= now and (not due or c.due < due.due) then due = c end
      if due == c then first = e end
    end
  end
  if first then return first, "due" end
  if newToday(today) < newPerDay then
    for _, e in ipairs(entries) do
      if not list.cards[e.key] then return e, "new" end
    end
  end
  return nil
end

function Study.counts(entries, now, today, newPerDay)
  local out = { due = 0, newLeft = 0, fresh = 0, nextDue = nil }
  if frozen or not list then return out end
  for _, e in ipairs(entries) do
    local c = list.cards[e.key]
    if not c then
      out.fresh = out.fresh + 1
    elseif c.due <= now then
      out.due = out.due + 1
    elseif not out.nextDue or c.due < out.nextDue then
      out.nextDue = c.due
    end
  end
  out.newLeft = math.max(0, math.min(out.fresh, newPerDay - newToday(today)))
  return out
end

function Study.answer(key, rating, now, today)
  if frozen or not list or not known[key] then return nil end
  if rating ~= Study.AGAIN and rating ~= Study.GOOD then return nil end
  local c = list.cards[key]
  local s, d
  if c then
    s, d = WFJ.Fsrs.review(c.s, c.d, (now - c.last) / Study.DAY, rating)
  else
    s, d = WFJ.Fsrs.review(-1, 0, 0, rating)
    list.days[today] = newToday(today) + 1
    c = { reps = 0, lapses = 0 }
    list.cards[key] = c
  end
  c.s, c.d, c.last, c.reps = s, d, now, c.reps + 1
  if rating == Study.AGAIN then
    c.lapses = c.lapses + 1
    c.due = now + Study.RELEARN
  else
    c.due = now + math.max(1, math.floor(s + 0.5)) * Study.DAY
  end
  return c
end
