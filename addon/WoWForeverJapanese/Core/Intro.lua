-- Core/Intro.lua: whether the welcome window (UI/IntroWindow) is owed (docs/systems/settings.md).
-- A first install shows it once, at its first login or reload. A player who already had saved settings is shown it
-- once too, the first time a version that asks what they are here for loads: nobody has answered that yet.
-- The flags: WFJ_DB.intro is false while a first install's window is owed, true once shown or when the table existed
-- before this key did; WFJ_DB.asked is false until the question has been put, to anyone.
-- Pure: no frame access (lint-core-gate); Main.lua passes the settings table and the window's open function.
--   Intro.prepare(db, fresh)   at load; fresh = there was no WFJ_DB before the settings loaded
--   Intro.run(db, show) → true when it called show
local _, WFJ = ...
local Intro = {}
WFJ.Intro = Intro

function Intro.prepare(db, fresh)
  if type(db) ~= "table" then return end
  if db.intro == nil then db.intro = not fresh end
  if db.asked == nil then db.asked = false end
end

-- Marks it seen before showing: a window that fails to build must not come back at every login.
function Intro.run(db, show)
  if type(db) ~= "table" or (db.intro ~= false and db.asked ~= false) then return false end
  db.intro, db.asked = true, true
  show()
  return true
end
