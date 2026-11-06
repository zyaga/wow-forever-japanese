-- Core/Study.lua: studying the saved word list in game (ADR-071, docs/systems/study.md). Pure: no globals, no
-- frames. The card states live in their own SavedVariables table, keyed like the word list (Core/Words):
--   WFJ_Study = { schema = 1, cards = { [key] = { s, d, due, last, reps, lapses } }, days = { [YYYY-MM-DD] = n } }
-- `days` holds how many new cards were first graded today, for the daily cap (only today's count is ever read, so
-- a new day replaces it). Time is epoch seconds (the client's time()); `today` is the client's date("%Y-%m-%d");
-- both are passed in, never read here.
--   Study.load(saved, entries) → the table to keep in WFJ_Study    Study.prune(entries) → cards dropped
--   Study.scan(entries, now, today, newPerDay) → { entry, kind, due, newLeft, fresh, nextDue }: one walk
--   Study.next(...) → entry, "due" | "new"        Study.counts(...) → the same table (no entry needed)
--   Study.answer(key, rating, now, today) → the card's state, or nil when refused
-- Due order is Anki's: a graded card is due once its date has passed (the earliest first), then new cards in the
-- order they were saved while today's new count is under the cap. A card graded Again comes back after one
-- relearn step; Good waits the FSRS interval in whole days, at least one. Only a key the word list holds is
-- graded: the list's keys come with load and prune, and the list's own change event keeps them current.
-- UI/StudyWindow shows the cards.
local _, WFJ = ...
local Study = {}
WFJ.Study = Study

Study.SCHEMA = 1
Study.RELEARN = 600 -- seconds: Anki's default relearning step
Study.DAY = 86400
Study.AGAIN, Study.GOOD = WFJ.Fsrs.AGAIN, WFJ.Fsrs.GOOD

local list -- the saved table
local frozen = false -- saved by a newer version: kept as it is, never written
local known = {} -- the word list's keys as last given

-- a finite number: the formulas assume one, and a NaN written back would spoil the whole saved file
local function finite(n)
  return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function isCard(c)
  return type(c) == "table" and finite(c.s) and c.s > 0 and finite(c.d) and finite(c.due) and finite(c.last)
end

local function count(n)
  return finite(n) and n >= 0 and math.floor(n) == n and n or nil
end

local function keysOf(entries)
  local set = {}
  for _, e in ipairs(entries or {}) do
    if type(e) == "table" and e.key ~= nil then set[e.key] = true end
  end
  return set
end

-- `entries`: the word list's entries; a card whose word is gone from the list is dropped. `listFrozen`: the word
-- list itself was saved by a newer version, so its entries cannot be trusted to name the cards: the study table is
-- kept as it is, read-only, like the list.
function Study.load(saved, entries, listFrozen)
  frozen = false
  known = keysOf(entries)
  if listFrozen or (type(saved) == "table" and type(saved.schema) == "number" and saved.schema > Study.SCHEMA) then
    list, frozen = type(saved) == "table" and saved or nil, true
    return saved
  end
  local t = { schema = Study.SCHEMA, cards = {}, days = {} }
  if type(saved) == "table" then
    if type(saved.cards) == "table" then
      for k, c in pairs(saved.cards) do
        if type(k) == "string" and known[k] and isCard(c) then
          t.cards[k] = { s = c.s, d = math.min(math.max(c.d, 1), 10), due = c.due, last = c.last,
            reps = count(c.reps) or 0, lapses = count(c.lapses) or 0 }
        end
      end
    end
    if type(saved.days) == "table" then
      for day, n in pairs(saved.days) do
        if type(day) == "string" and day:find("^%d%d%d%d%-%d%d%-%d%d$") and count(n) then t.days[day] = n end
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
function Study.prune(entries)
  if frozen or not list then return 0 end
  known = keysOf(entries)
  local n = 0
  for k in pairs(list.cards) do
    if not known[k] then list.cards[k] = nil; n = n + 1 end
  end
  return n
end

-- the word list says when it changed (State "words"): a saved word becomes gradable, a removed one loses its card
if WFJ.State then
  WFJ.State.on("words", function() if WFJ.Words then Study.prune(WFJ.Words.entries()) end end)
end

local function newToday(today)
  return list.days[today] or 0
end

function Study.scan(entries, now, today, newPerDay)
  local out = { due = 0, newLeft = 0, fresh = 0, waiting = 0 }
  if frozen or not list then return out end
  local first, best, firstNew
  for _, e in ipairs(entries) do
    local c = list.cards[e.key]
    if not c then
      out.fresh = out.fresh + 1
      firstNew = firstNew or e
    elseif c.due <= now then
      out.due = out.due + 1
      if not best or c.due < best then first, best = e, c.due end
    elseif not out.nextDue or c.due < out.nextDue then
      out.nextDue = c.due
    end
  end
  out.newLeft = math.max(0, math.min(out.fresh, newPerDay - newToday(today)))
  out.waiting = out.due + out.newLeft -- what the player can study now: every count shown outside the card uses it
  if first then
    out.entry, out.kind = first, "due"
  elseif firstNew and out.newLeft > 0 then
    out.entry, out.kind = firstNew, "new"
  end
  return out
end

function Study.next(entries, now, today, newPerDay)
  local r = Study.scan(entries, now, today, newPerDay)
  return r.entry, r.kind
end

function Study.counts(entries, now, today, newPerDay)
  return Study.scan(entries, now, today, newPerDay)
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
    list.days = { [today] = newToday(today) + 1 }
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
