-- UI/NameLabels.lua: a widget that holds only a game name (an NPC's, a place's, an item's, a spell's) shows the
-- name's Japanese while names are on. It goes through UI/Render as kind "name", keyed by the English the client
-- wrote, so the reveal key, the direction, the master switch and a surface's release give the English back exactly
-- as they do for a translated line. A name with no Japanese keeps the client's text and gets no record.
--   NameLabels.show(surface, recKey, widget[, area]) → 1 when the name shows in Japanese (or is still ours), else 0
--   NameLabels.unit(surface, recKey, widget, unit[, area]) → the same for a unit's name; a player's is never touched
--   NameLabels.title(surface, frame[, recKey[, unit]]) → the same for a window whose title bar is its NPC's name
--     (frame:SetTitle(UnitName("npc")) → TitleContainer.TitleText): shown now and after every later SetTitle. `unit`
--     is "npc" unless given; `false` is a window named after an object, with no unit behind it (a machine, a
--     forge): the name shows with no player check. Under the record key the surface's own title uses, so a
--     dictionary title a surface already shows on that widget ("Buyback") is left as it is: one record owns the
--     widget.
-- The guards live here so no surface repeats them: a value the client hides from addons (a unit's name in
-- combat inside an instance) is never read, compared, hashed or written; a player's name is not a game name
-- even when an NPC shares it; and a unit a player controls (a pet) carries the name its player gave it.
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
  -- a unit a player controls (a pet) carries a name its player gave it; any answer but a plain false leaves it
  local controlled = WFJ.Compat.resolve("UnitPlayerControlled")
  if type(controlled) == "function" and controlled(unit) ~= false then
    WFJ.SurfaceState.drop(surface, recKey)
    return 0
  end
  return NameLabels.show(surface, recKey, widget, area)
end

local titleHooked = setmetatable({}, { __mode = "k" })

function NameLabels.title(surface, frame, recKey, unit)
  if type(frame) ~= "table" then return 0 end
  local container = frame.TitleContainer
  local text = type(container) == "table" and container.TitleText or nil
  if type(text) ~= "table" then return 0 end
  recKey = recKey or "title"
  if unit == nil then unit = "npc" end
  local function showTitle()
    if unit == false then return NameLabels.show(surface, recKey, text) end
    return NameLabels.unit(surface, recKey, text, unit)
  end
  if not titleHooked[frame] and type(frame.SetTitle) == "function" then
    titleHooked[frame] = true
    hooksecurefunc(frame, "SetTitle", function() showTitle() end)
  end
  return showTitle()
end
