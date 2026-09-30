-- UI/CommunitiesKit.lua: the shared plumbing of the Forever Communities window surfaces (area "ui",
-- ADR-016): UI/Communities (the guild view), UI/CommunitiesFrame, UI/CommunitiesGuild, UI/ClubFinder and
-- UI/CommunitiesDialogs each describe their widgets as data and this module does what every one of them would
-- otherwise repeat: the Compat candidates (dotted paths), key-restricted labels (Labels.show `only`: every widget in
-- this window may also hold a club, community, channel or player name), post-hooks on the client's writers AFTER
-- they write (hooksecurefunc on the instance; a frame's XML-bound script through HookScript), help-tooltip owners with
-- the keys their writer shows, dropdown selection texts, and pooled ScrollBox rows through ScrollUtil's
-- initialized-frame callback (after the element initializer ran). Nothing here writes a Blizzard field or calls a
-- Blizzard writer; a name bound to the wrong type (a number where a frame was expected) is skipped, never an error.
-- It is not a surface: it declares no SURFACE of its own.
local _, WFJ = ...
local Kit = {}
WFJ.CommunitiesKit = Kit

local Compat = WFJ.Compat

Kit.ADDON = "Blizzard_Communities"

-- `path` ("A.B.C") under `frame`, each step a table. → the value | nil
function Kit.child(frame, path)
  local v = frame
  for field in tostring(path):gmatch("[^.]+") do
    if type(v) ~= "table" then return nil end
    v = v[field]
  end
  return v
end

local function asTable(v) return type(v) == "table" and v or nil end

local hooked = setmetatable({}, { __mode = "k" }) -- owner → { [method] = true }

-- One post-hook per owner, method and `tag` (the hooking surface: a re-run setup never stacks a second one, and two
-- surfaces may each hook the same writer). → true when installed now.
function Kit.after(owner, method, fn, tag)
  if type(owner) ~= "table" or type(owner[method]) ~= "function" then return false end
  local set = hooked[owner] or {}
  local id = method .. "|" .. tostring(tag)
  if set[id] then return false end
  set[id] = true
  hooked[owner] = set
  hooksecurefunc(owner, method, fn)
  return true
end

-- A frame script bound in XML (`<OnShow method="OnShow"/>`, an inline <OnLoad>) runs the function captured at load,
-- so the method table is not the writer the client calls; HookScript runs after the bound handler. → true when set.
function Kit.script(frame, script, fn, tag)
  if type(frame) ~= "table" or type(frame.HookScript) ~= "function" then return false end
  local set = hooked[frame] or {}
  local id = "script:" .. script .. "|" .. tostring(tag)
  if set[id] then return false end
  set[id] = true
  hooked[frame] = set
  frame:HookScript(script, fn)
  return true
end

-- A new window description. `surface` is the module's own surface ("communities.<window>"); `candidates` maps a
-- local key to a Compat candidate list of dotted names.
function Kit.new(surface, candidates)
  local k = { surface = surface, candidates = candidates or {} }

  function k.declare()
    for key, names in pairs(k.candidates) do Compat.declare(surface, key, names) end
  end

  function k.get(key) return Compat.get(surface, key) end
  function k.after(owner, method, fn) return Kit.after(owner, method, fn, surface) end
  function k.script(frame, script, fn) return Kit.script(frame, script, fn, surface) end

  -- One key-restricted label (a FontString or a Button). → 1 | 0
  function k.show(recKey, widget, keys)
    if type(widget) ~= "table" then
      WFJ.SurfaceState.drop(surface, recKey)
      return 0
    end
    return WFJ.Labels.show(surface, recKey, widget, nil, { only = keys })
  end

  -- { { recKey, widget, keys }, … } → the number of dictionary words shown; the banner follows.
  function k.showList(list)
    local n = 0
    for _, item in ipairs(list) do n = n + k.show(item[1], item[2], item[3]) end
    WFJ.Render.updateBanner(surface)
    return n
  end

  -- `labels` = { { recKey, candidateKey, childPath or false, keys }, … } resolved under their candidate. → n shown
  function k.showUnder(labels)
    local list = {}
    for _, l in ipairs(labels) do
      local base = k.get(l[2])
      list[#list + 1] = { l[1], l[3] and Kit.child(base, l[3]) or base, l[4] }
    end
    return k.showList(list)
  end

  -- A help-tooltip owner whose writer shows only `keys` (the other lines are names, counts, notes).
  function k.tooltip(owner, keys)
    if type(owner) == "table" then WFJ.HelpTooltip.register(owner, { only = keys }) end
  end

  function k.dropdown(recKey, dropdown, keys)
    if type(dropdown) ~= "table" then return 0 end
    return WFJ.Labels.dropdown(surface, recKey, dropdown, { only = keys })
  end

  -- Pooled rows of a ScrollBox: fn(row, elementData) after the element initializer, for every new row and
  -- (iterateExisting) the ones already shown; ScrollUtil calls (owner, frame, elementData) for a new one and
  -- (frame, elementData) for the existing pass. The callback returns nothing: ForEachFrame stops at the first truthy
  -- return.
  function k.rows(box, fn)
    local util = asTable(Compat.get(surface, "scrollUtil"))
    if type(box) ~= "table" or not util or type(util.AddInitializedFrameCallback) ~= "function" then return false end
    util.AddInitializedFrameCallback(box, function(a, b, c)
      local row, data = a, b
      if a == k then row, data = b, c end
      if type(row) == "table" then fn(row, data) end
    end, k, true)
    return true
  end

  -- A ColumnDisplay's pooled header buttons (ColumnDisplayMixin:LayoutColumns, shareduipaneltemplates.lua): every
  -- active header after each layout, keyed by widget, restricted to `keys`. → n shown now
  function k.headers(display, keys, prefix)
    if type(display) ~= "table" then return 0 end
    local keyOf = WFJ.Labels.keyer(prefix)
    local function walk()
      local pool = asTable(display.columnHeaders)
      if not pool or type(pool.EnumerateActive) ~= "function" then return 0 end
      local n = 0
      for header in pool:EnumerateActive() do
        if type(header) == "table" then n = n + k.show(keyOf(header), header, keys) end
      end
      WFJ.Render.updateBanner(surface)
      return n
    end
    Kit.after(display, "LayoutColumns", walk, surface .. "." .. prefix)
    return walk()
  end

  return k
end

-- Registers a module whose setup needs Blizzard_Communities (its frames exist only once it has loaded): `init` →
-- false when the addon has not loaded yet; the setup then runs on its ADDON_LOADED.
function Kit.init(k, setup)
  k.declare()
  Compat.declare(k.surface, "frame", { "CommunitiesFrame" })
  Compat.declare(k.surface, "scrollUtil", { "ScrollUtil" })
  return WFJ.LoadOnDemand.when(Kit.ADDON, setup)
end

-- The common head of every setup: re-declare (the frames exist only now: forget what Compat memoized), refuse
-- without the window, register the never-touch widgets. → true when the module may hook.
function Kit.ready(k, neverTouch)
  k.declare()
  Compat.declare(k.surface, "frame", { "CommunitiesFrame" })
  Compat.declare(k.surface, "scrollUtil", { "ScrollUtil" })
  if type(k.get("frame")) ~= "table" then return false end
  WFJ.Labels.forbidNames(neverTouch)
  return true
end
