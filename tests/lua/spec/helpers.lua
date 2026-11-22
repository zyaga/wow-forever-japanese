-- Test helpers: load one addon chunk the way the client does (vararg = ADDON, WFJ).
local H = {}
local ROOT = (debug.getinfo(1, "S").source:match("^@(.*)/tests/lua/spec/helpers%.lua$")) or "."
H.ROOT = ROOT
H.ADDON_DIR = ROOT .. "/addon/WoWForeverJapanese"

-- Under `make coverage-lua` the generated data is loaded with the coverage hook off: it is not code under
-- test, and luacov's hook runs on every line of its tables even while luacov is paused (pausing only stops
-- saving), which makes a whole-addon load many times slower. The hook is put back as luacov sets it. The
-- `Data.add` calls the shards make go uncounted with it; specs that call `Data.add` themselves count it.
local function run(relpath, chunk, addonName, ns)
  local runner = package.loaded["luacov.runner"]
  if not (runner and runner.debug_hook and relpath:find("^Data/")) then
    return chunk(addonName or "WoWForeverJapanese", ns)
  end
  debug.sethook()
  local ok, result = pcall(chunk, addonName or "WoWForeverJapanese", ns)
  debug.sethook(runner.debug_hook, "l")
  if not ok then error(result, 0) end
  return result
end

-- One parse per file per process. A parsed chunk runs again for each fresh namespace, and parsing the generated
-- data again for every test is most of what a whole-addon load costs.
local chunks = {}

function H.loadChunk(relpath, addonName, ns)
  local path = H.ADDON_DIR .. "/" .. relpath
  local chunk = chunks[path]
  if not chunk then
    local err
    chunk, err = loadfile(path)
    assert(chunk, err)
    chunks[path] = chunk
  end
  return run(relpath, chunk, addonName, ns)
end

-- Loads several chunks in order into one namespace. Core/Perf comes first when the list does not name it: the write
-- paths call it unguarded, as they can in game, where it loads before every surface (without its clock it does
-- nothing).
function H.loadChunks(relpaths, ns, addonName)
  ns = ns or {}
  local hasPerf = false
  for _, rel in ipairs(relpaths) do if rel == "Core/Perf.lua" then hasPerf = true end end
  if not hasPerf and not ns.Perf then H.loadChunk("Core/Perf.lua", addonName, ns) end
  for _, rel in ipairs(relpaths) do H.loadChunk(rel, addonName, ns) end
  -- a spec that loads its own files covers the Japanese quest titles: the switch on, as its own Translator (built
  -- with no `kindOff`) has it. The shipped default is covered by `uiSetup`'s `titlesOff` and by addon_load_spec,
  -- which loads the whole addon through its own loader.
  if ns.State then ns.State.names = true end
  return ns
end

-- Loads a chunk under an environment holding only the Lua 5.1 standard library: any WoW global access errors.
-- Proves a Core module is pure.
function H.loadPure(relpath, addonName, ns)
  local chunk, err = loadfile(H.ADDON_DIR .. "/" .. relpath)
  assert(chunk, err)
  local env = {
    string = string, table = table, math = math, pairs = pairs, ipairs = ipairs, type = type,
    tostring = tostring, tonumber = tonumber, select = select, error = error, assert = assert,
    setmetatable = setmetatable, getmetatable = getmetatable, next = next, rawget = rawget, rawset = rawset,
    unpack = unpack, pcall = pcall,
  }
  setmetatable(env, { __index = function(_, k) error("global access in pure module: " .. tostring(k), 2) end })
  setfenv(chunk, env)
  return run(relpath, chunk, addonName, ns)
end

function H.vectors()
  return dofile(ROOT .. "/vectors/hash_vectors.lua")
end

function H.readFile(relpath)
  local f = assert(io.open(ROOT .. "/" .. relpath, "r"))
  local s = f:read("*a")
  f:close()
  return s
end

-- Minimal stub of the Blizzard API the Core files touch (extended in addon_load_spec for Main.lua).
function H.coreStub()
  _G.C_AddOns = _G.C_AddOns or { GetAddOnMetadata = function() return "test" end }
end

-- Collector deps for surface specs: on, nothing shipped, the stub player, a fixed build; `o` overrides.
function H.collectorDeps(o)
  o = o or {}
  return {
    enabled = o.enabled or function() return true end,
    lookup = o.lookup or function() return nil end,
    player = o.player or function() return { name = "Reyn", class = "Hunter", race = "Night Elf" } end,
    build = function() return "1.15.9.69722" end,
    print = function(...) print(...) end,
  }
end

-- The addon files a UI window spec loads, in TOC order; a spec appends its own module(s).
H.UI_FILES = { "Core/Const.lua", "Core/Compat.lua", "Core/Align.lua", "Core/State.lua", "Core/Settings.lua",
  "Core/Modifier.lua", "Core/Translator.lua", "Core/UIStringKeys.lua",
  "Core/UIStrings.lua", "Core/SurfaceState.lua", "Core/Normalize.lua",
  "Core/Hash.lua", "Core/Collector.lua", "Core/Diag.lua", "Core/Perf.lua",
  "UI/Font.lua", "UI/Frames.lua", "UI/Render.lua", "UI/ButtonText.lua", "UI/Labels.lua", "UI/TextWatch.lua",
  "UI/HtmlText.lua",
  "UI/LoadOnDemand.lua", "UI/HelpTooltip.lua" }

-- Builds the ui index and the translator the way Main does, over `ui` = { KEY = { English, Japanese } }.
-- The English of a global-string key is set as that global (cleared by H.uiTeardown); `ItemSubClass:` /
-- `SpellItemEnchantment:` keys are fingerprint rows. Settings are loaded fresh. → rows
-- `opts` (optional): { lookup(kind, id) → entry | nil for kinds other than "ui", expand(ja) → ja }.
function H.uiSetup(WFJ, ui, opts)
  opts = opts or {}
  WFJ.Compat.init(function(name) return _G[name] end)
  WFJ.Settings.load(nil, 1, {})
  -- the specs cover the Japanese titles (the switch on) unless one asks for the shipped default, `titlesOff`
  WFJ.State.names = not opts.titlesOff
  local function h1(text) return (WFJ.Hash.h32x2(WFJ.Normalize.v1(text))) end
  local rows = {}
  H._uiGlobals = {}
  for key, pair in pairs(ui) do
    rows[key] = { pair[2], h1(pair[1]), "." }
    if not key:find(":") then _G[key] = pair[1]; H._uiGlobals[#H._uiGlobals + 1] = key end
  end
  WFJ.UIIndex = WFJ.UIStrings.build({ rows = rows, hash = h1, english = function(key)
    if WFJ.UIStrings.isFingerprintKey(key) then return nil end
    return _G[key]
  end })
  WFJ.Render.init(WFJ.Translator.new({
    enabled = function() return WFJ.State.enabled end,
    areaEnabled = WFJ.State.areaEnabled,
    showsEnglish = WFJ.Modifier.english,
    kindOff = opts.titlesOff and function(kind) return kind == "quest.title" end or nil,
    lookup = function(kind, id)
      if kind == "ui" then local r = rows[id]; return r and { ja = r[1], status = r[3] } end
      return opts.lookup and opts.lookup(kind, id) or nil
    end,
    expand = opts.expand,
    marker = function(n) return WFJ.Settings.get("marker." .. n) end,
    align = WFJ.Align.check,
    fill = function(ja, args) return WFJ.UIIndex:fill(ja, args) end,
  }))
  WFJ.LoadOnDemand.init(function(name) return C_AddOns.IsAddOnLoaded(name) end)
  WFJ.ButtonText.init()
  WFJ.HelpTooltip.init()
  return rows
end

function H.uiTeardown()
  for _, key in ipairs(H._uiGlobals or {}) do _G[key] = nil end
  H._uiGlobals = {}
end

return H
