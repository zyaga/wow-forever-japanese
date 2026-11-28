-- UI/NameLabels.lua: a widget that holds only a game name (an NPC's, a place's, an item's, a spell's) shows the
-- name's Japanese while names are on. It goes through UI/Render as kind "name", keyed by the English the client
-- wrote, so the reveal key, the direction, the master switch and a surface's release give the English back exactly
-- as they do for a translated line. A name with no Japanese keeps the client's text and gets no record.
--   NameLabels.show(surface, recKey, widget[, area[, refit]]) → 1 when the name shows in Japanese (or is still
--     ours), else 0. `refit` (a tooltip's line) runs after each write, so the frame is laid out for the new text.
--   NameLabels.lead(surface, recKey, widget[, area[, refit]]) → the same for a widget that starts with a name and
--     ends with what the client wrote after it ("Blacksmithing 135/150", a zone and its coloured level range): the
--     name in Japanese, the rest byte for byte. The rest may hold only numbers, signs and colour codes; a line where
--     words follow the name stays English whole.
--   NameLabels.wrapped(surface, recKey, widget[, area[, refit]]) → the same for a name behind one colour code
--     ("|cffa335ee<name>|r", an item in its quality colour), maybe with an item level inside the colour and what the
--     client put after it: a count, a quality icon, a key binding. The colour code and everything but the name are
--     kept byte for byte; a line where words follow the name stays English whole.
--   NameLabels.after(surface, recKey, widget, lead[, area[, refit]]) → the same for a name the client wrote after a
--     fixed lead ("- <name>", a reward in a list): the lead kept byte for byte. A text that does not start with the
--     lead, or whose rest is no name, stays as written.
--   NameLabels.counted(surface, recKey, widget[, area[, refit]]) → the same for a name the client wrote after a
--     count, maybe inside one colour code ("|cffffffff3/5 Copper Bar|r", a reagent in a crafting slot).
--   NameLabels.before(surface, recKey, widget, tail[, area[, refit]]) → the same for a name the client wrote before
--     a fixed tail ("<skill>:"): the tail kept byte for byte.
--   NameLabels.joined(surface, recKey, widget[, area[, refit]]) → the same for a widget that holds one name or two
--     names the client joined with ": " (a holiday's title on the calendar, "Call to Arms: Warsong Gulch"): both
--     names in Japanese, the separator kept. A text with a half that is no name stays as written. Only a widget
--     whose text the game names takes this: a colon in any other text joins nothing.
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

local function secret(v) return WFJ.Compat.secret(v) end

local function show(surface, recKey, widget, area, refit)
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
  WFJ.Render.show(surface, recKey, fs, en, area or "ui", "name", en, refit and { refit = refit } or nil)
  return 1
end

function NameLabels.show(surface, recKey, widget, area, refit)
  return WFJ.Perf.call(surface, show, surface, recKey, widget, area, refit)
end

-- What follows a name: no letter outside its colour codes.
local function plainTail(tail)
  local bare = tail:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[%w_]+:", ""):gsub("|r", "")
  return not bare:find("%a")
end

-- What the client draws after a name in a list, a slot or a tooltip title, read through like a colour code: an atlas
-- or texture icon, the "x" of a count ("x20"), and a key binding in brackets in its own colour at the very end
-- (GameTooltip:AppendText's " |cffffd200(B)|r").
local function decoratedTail(tail)
  local rest = tail:gsub(" |c%x%x%x%x%x%x%x%x%([^|()]*%)|r$", "")
  rest = rest:gsub("|A.-|a", ""):gsub("|T.-|t", ""):gsub("x(%d)", "%1")
  return plainTail(rest)
end

-- → the name and what follows it, split before a space or a colour code (and a colour's close when `decorated`),
-- the longest name first | nil
local function splitTail(text, decorated)
  for i = #text, 2, -1 do
    local at = text:sub(i, i + 1)
    if text:sub(i, i) == " " or at == "|c" or (decorated and at == "|r") then
      local name, tail = text:sub(1, i - 1), text:sub(i)
      -- a name holds no markup and ends in no space: the name tables read through both, and the tail would lose them
      local bare = name:sub(-1) ~= " " and not name:find("|", 1, true)
      if bare and (decorated and decoratedTail or plainTail)(tail) and WFJ.Names.item(name) then return name, tail end
    end
  end
  return nil
end

-- lead: the whole text, or a name and the numbers after it
local function leadParts(en)
  if not en:find("|", 1, true) and WFJ.Names.item(en) then return en, nil, nil end
  local name, tail = splitTail(en, false)
  return name, nil, tail
end

-- wrapped: one leading colour code, then a name and what the client put after it
local function wrappedParts(en)
  local head, body = en:match("^(|c%x%x%x%x%x%x%x%x)(.*)$")
  if not head then head, body = en:match("^(|cn[%w_]+:)(.*)$") end
  body = body or en
  if not body:find("|", 1, true) and WFJ.Names.item(body) then return body, head, nil end
  local name, tail = splitTail(body, true)
  return name, head, tail
end

local function parts(surface, recKey, widget, area, refit, split)
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
  local name, head, tail
  if type(en) == "string" and en ~= "" then name, head, tail = split(en) end
  if not name then
    WFJ.SurfaceState.drop(surface, recKey)
    return 0
  end
  local ctx = (head or tail or refit) and { head = head, tail = tail, refit = refit } or nil
  WFJ.Render.show(surface, recKey, fs, en, area or "ui", "name", name, ctx)
  return 1
end

function NameLabels.lead(surface, recKey, widget, area, refit)
  return WFJ.Perf.call(surface, parts, surface, recKey, widget, area, refit, leadParts)
end

function NameLabels.wrapped(surface, recKey, widget, area, refit)
  return WFJ.Perf.call(surface, parts, surface, recKey, widget, area, refit, wrappedParts)
end

function NameLabels.after(surface, recKey, widget, lead, area, refit)
  local function split(en)
    if type(lead) ~= "string" or lead == "" or en:sub(1, #lead) ~= lead then return nil end
    local name = en:sub(#lead + 1)
    if name == "" or name:find("|", 1, true) or not WFJ.Names.item(name) then return nil end
    return name, lead, nil
  end
  return WFJ.Perf.call(surface, parts, surface, recKey, widget, area, refit, split)
end

-- A reagent in a crafting slot: a name after its count, the whole inside one colour code or none
-- ("|cffffffff3/5 Copper Bar|r", "2 Copper Bar"; blizzard_professionsrecipereagentslot.lua:113–130, 236–252). The
-- colour code and the count are kept byte for byte.
function NameLabels.counted(surface, recKey, widget, area, refit)
  local function split(en)
    local open = en:match("^|c%x%x%x%x%x%x%x%x") or ""
    local rest = en:sub(#open + 1)
    local count = rest:match("^%d+/%d+ ") or rest:match("^%d+ ")
    if not count then return nil end
    local name, close = rest:sub(#count + 1), nil
    if open ~= "" then
      if name:sub(-2) ~= "|r" then return nil end
      name, close = name:sub(1, -3), "|r"
    end
    if name == "" or name:find("|", 1, true) or not WFJ.Names.item(name) then return nil end
    return name, open .. count, close
  end
  return WFJ.Perf.call(surface, parts, surface, recKey, widget, area, refit, split)
end

-- The mirror of `after`: a name the client wrote before a fixed tail ("<skill>:", a weapon skill's line in the
-- character window's damage tooltip), the tail kept byte for byte.
function NameLabels.before(surface, recKey, widget, tail, area, refit)
  local function split(en)
    if type(tail) ~= "string" or tail == "" or #en <= #tail or en:sub(-#tail) ~= tail then return nil end
    local name = en:sub(1, -#tail - 1)
    if name:find("|", 1, true) or not WFJ.Names.item(name) then return nil end
    return name, nil, tail
  end
  return WFJ.Perf.call(surface, parts, surface, recKey, widget, area, refit, split)
end

-- joined: the whole text when it is a name, else two names with ": " between them. The record is the first
-- name's, and the separator with the second name's Japanese follows it, so the reveal key and the names choice
-- give the whole English back as for any name.
local function joinedParts(en)
  if en:find("|", 1, true) then return nil end
  if WFJ.Names.item(en) then return en, nil, nil end
  local ja, _, first, second = WFJ.Names.joined(en)
  if not ja then return nil end
  return first, nil, en:sub(#first + 1, #en - #second) .. WFJ.Names.of(second)
end

function NameLabels.joined(surface, recKey, widget, area, refit)
  return WFJ.Perf.call(surface, parts, surface, recKey, widget, area, refit, joinedParts)
end

function NameLabels.unit(surface, recKey, widget, unit, area)
  if not WFJ.State.names then
    WFJ.SurfaceState.drop(surface, recKey)
    return 0
  end
  local isPlayer = WFJ.Compat.resolve("UnitIsPlayer")
  local player = type(isPlayer) == "function" and isPlayer(unit)
  -- anything but a plain false is a player, or an answer the client hides (a secret, which may not be compared):
  -- the name stays as written
  if secret(player) or player ~= false then
    WFJ.SurfaceState.drop(surface, recKey)
    return 0
  end
  -- a unit a player controls (a pet) carries a name its player gave it; any answer but a plain false leaves it
  local controlled = WFJ.Compat.resolve("UnitPlayerControlled")
  local mine = type(controlled) == "function" and controlled(unit)
  if type(controlled) == "function" and (secret(mine) or mine ~= false) then
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
