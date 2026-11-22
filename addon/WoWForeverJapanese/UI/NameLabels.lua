-- UI/NameLabels.lua: a widget that holds only a game name (an NPC's, a place's, an item's, a spell's) shows the
-- name's Japanese while names are on. It goes through UI/Render as kind "name", keyed by the English the client
-- wrote, so the reveal key, the direction, the master switch and a surface's release give the English back exactly
-- as they do for a translated line. A name with no Japanese keeps the client's text and gets no record.
--   NameLabels.show(surface, recKey, widget[, area]) → 1 when the name shows in Japanese (or is still ours), else 0
--   NameLabels.unit(surface, recKey, widget, unit[, area]) → the same for a unit's name; a player's is never touched
-- Both guards live here so no surface repeats them: a value the client hides from addons (a unit's name in
-- combat inside an instance) is never read, compared, hashed or written, and a player's name is not a game name
-- even when an NPC shares it.
local _, WFJ = ...
local NameLabels = {}
WFJ.NameLabels = NameLabels

local function secret(v)
  local isSecret = WFJ.Compat.resolve("issecretvalue")
  return type(isSecret) == "function" and isSecret(v) == true
end

local function show(surface, recKey, widget, area)
  local fs = WFJ.Labels.widget(widget)
  if not WFJ.State.names or not fs then
    WFJ.SurfaceState.drop(surface, recKey)
    return 0
  end
  local en = fs:GetText()
  if secret(en) then
    WFJ.SurfaceState.drop(surface, recKey)
    return 0
  end
  local rec = WFJ.SurfaceState.get(surface, recKey)
  if rec and rec.fs == fs and rec.applied ~= nil and en == rec.applied then -- still our Japanese
    WFJ.Render.keepFont(surface, recKey)
    return 1
  end
  if type(en) ~= "string" or en == "" or not WFJ.Names.item(en) then
    WFJ.SurfaceState.drop(surface, recKey)
    return 0
  end
  WFJ.Render.show(surface, recKey, fs, en, area or "ui", "name", en)
  return 1
end

function NameLabels.show(surface, recKey, widget, area)
  return WFJ.Perf.call(surface, show, surface, recKey, widget, area)
end

function NameLabels.unit(surface, recKey, widget, unit, area)
  if not WFJ.State.names then
    WFJ.SurfaceState.drop(surface, recKey)
    return 0
  end
  local isPlayer = WFJ.Compat.resolve("UnitIsPlayer")
  local player = type(isPlayer) == "function" and isPlayer(unit)
  -- anything but a plain false is a player, or an answer the client hides: the name stays as written
  if player ~= false then
    WFJ.SurfaceState.drop(surface, recKey)
    return 0
  end
  return NameLabels.show(surface, recKey, widget, area)
end
