-- Core/CollectorRemind.lua: the chat reminder that collected English is waiting to be sent (docs/systems/collector.md).
-- At login or reload, one line with the count of unsent lines and the send command, never their text; only at
-- REMIND_MIN or more, at most once a day, and never on the login that prints the collector's first-time notice.
-- The day of the last reminder is kept in WFJ_DB, never in the collector's own file: that file may be attached to a
-- public issue and holds no time on purpose.
-- Pure: no frame access (lint-core-gate); the caller passes the settings table, the time and the printer. Its
-- setting, collector.remind, is defined with the collector's own in Core/Collector.lua (the English Collector page).
--   CollectorRemind.due(state) → count | nil
--     state = { enabled, remind, readOnly, unsent, today, last, disclosedNow }
--   CollectorRemind.line(count) → the chat line
--   CollectorRemind.run(db, now, print, disclosedNow) → count | nil   reads the collector, prints, stores the day
local _, WFJ = ...
local CollectorRemind = {}
WFJ.CollectorRemind = CollectorRemind

CollectorRemind.REMIND_MIN = 10
local DAY = 86400

function CollectorRemind.due(s)
  if not (s.enabled and s.remind) or s.readOnly or s.disclosedNow then return nil end
  if type(s.unsent) ~= "number" or s.unsent < CollectorRemind.REMIND_MIN then return nil end
  if s.last == s.today then return nil end
  return s.unsent
end

function CollectorRemind.line(count)
  return ("WFJ: %d lines of English the addon has no Japanese for are waiting. /wfj collector send to send them"
    .. " · /wfj collector remind off to stop this reminder"):format(count)
end

function CollectorRemind.run(db, now, print, disclosedNow)
  if type(db) ~= "table" or type(now) ~= "number" then return nil end
  local status = WFJ.Collector.status()
  local today = math.floor(now / DAY)
  local count = CollectorRemind.due({
    enabled = status.enabled, remind = WFJ.Settings.get("collector.remind") == true, readOnly = status.readOnly,
    unsent = status.unsent, today = today, last = db.collectorReminded, disclosedNow = disclosedNow == true,
  })
  if disclosedNow == true then db.collectorReminded = today end -- the notice already named the command today
  if not count then return nil end
  print(CollectorRemind.line(count))
  db.collectorReminded = today
  return count
end
