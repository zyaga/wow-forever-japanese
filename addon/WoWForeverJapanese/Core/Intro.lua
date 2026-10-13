-- Core/Intro.lua: whether the intro window (UI/IntroWindow) is owed (docs/systems/settings.md).
-- A first install shows it once, at its first login or reload; a player who already had saved settings never sees it.
-- The flag is WFJ_DB.intro: false while owed, true once shown or when the table existed before this key did.
-- Pure: no frame access (lint-core-gate); Main.lua passes the settings table and the window's open function.
--   Intro.prepare(db, fresh)   at load; fresh = there was no WFJ_DB before the settings loaded
--   Intro.run(db, show) → true when it called show
local _, WFJ = ...
local Intro = {}
WFJ.Intro = Intro

function Intro.prepare(db, fresh)
  if type(db) ~= "table" then return end
  if db.intro == nil then db.intro = not fresh end
end

-- Marks it seen before showing: a window that fails to build must not come back at every login.
function Intro.run(db, show)
  if type(db) ~= "table" or db.intro ~= false then return false end
  db.intro = true
  show()
  return true
end
