-- Core/Compat.lua: every client-specific name resolves here, once. Pure: the world is reached only through the
-- `env(name)` function Main injects (a lookup into the client's global table); tests inject a table lookup.
-- Surfaces declare their own candidate lists at load (Compat.declare: one surface, one file, its own names)
-- and read them with Compat.get. /wfj debug prints Compat.unresolved().
local ADDON, WFJ = ...
local Compat = {}
WFJ.Compat = Compat

local env = function() return nil end
local declared = {} -- [surface][key] = { candidate names, in preference order }
local resolved = {} -- [surface][key] = value | false (memoized; frames do not appear later)

function Compat.init(fn)
  env = fn
  resolved = {}
end

-- One candidate name → its value. A bare name is the injected env lookup. A dotted name
-- ("C_Spell.GetSpellDescription", "TooltipDataProcessor.AddTooltipPostCall") walks the segments from the first
-- one's global: modern clients moved APIs into namespace tables, and a surface has to be able to name the moved
-- form as a candidate.
local function lookup(name)
  if type(name) ~= "string" then return nil end
  local dot = name:find(".", 1, true)
  if not dot then return env(name) end
  local value = env(name:sub(1, dot - 1))
  local rest = name:sub(dot + 1)
  while value ~= nil do
    if type(value) ~= "table" then return nil end
    dot = rest:find(".", 1, true)
    if not dot then return value[rest] end
    value = value[rest:sub(1, dot - 1)]
    rest = rest:sub(dot + 1)
  end
  return nil
end

function Compat.declare(surface, key, candidates)
  declared[surface] = declared[surface] or {}
  declared[surface][key] = candidates
  if resolved[surface] then resolved[surface][key] = nil end
end

-- One dynamic name through the injected env (tooltip line widgets `<Frame>TextLeft<i>`): not declared,
-- not memoized, nil when absent. Every static name still goes through declare/get.
function Compat.resolve(name)
  if not env then return nil end
  local value = lookup(name)
  return value or nil
end

-- First candidate `env` resolves to something truthy, else nil (a `false` global counts as unresolved).
function Compat.get(surface, key)
  local bucket = resolved[surface]
  if bucket and bucket[key] ~= nil then return bucket[key] or nil end
  local value
  local cands = declared[surface] and declared[surface][key]
  if cands then
    for _, name in ipairs(cands) do
      value = lookup(name)
      if value then break end
    end
  end
  resolved[surface] = resolved[surface] or {}
  resolved[surface][key] = value or false
  return value or nil
end

-- Sorted "surface.key" list of every declared name that resolves to nothing.
function Compat.unresolved()
  local out = {}
  for surface, keys in pairs(declared) do
    for key in pairs(keys) do
      if Compat.get(surface, key) == nil then out[#out + 1] = surface .. "." .. key end
    end
  end
  table.sort(out)
  return out
end

-- Settings pages via the Settings API [verified: classic_era FrameXML]. `pages` = ordered { { id, frame, name } }: the
-- first is the AddOns category, the rest its canvas subcategories, registered before `RegisterAddOnCategory`, "the
-- last step" [verified: Blizzard_ImplementationReadme.lua:42–43]; the list shows them collapsed under the category
-- until its toggle is clicked (RegisterCanvasLayoutSubcategory returns the
-- subcategory [verified: Blizzard_SettingsInbound.lua:99–102]). Categories are opened by numeric id only: a name or
-- the category object fails silently [verified: Blizzard_SettingsPanel.lua:282–291]. → the first page's id (or its
-- category) | nil when the API is absent. A client without subcategories registers the first page only.
function Compat.registerOptions(pages)
  local S = env("Settings")
  if type(S) ~= "table" or type(S.RegisterCanvasLayoutCategory) ~= "function"
      or type(S.RegisterAddOnCategory) ~= "function" or type(pages) ~= "table" or pages[1] == nil then
    return nil
  end
  local function idOf(category)
    return (type(category) == "table" and type(category.GetID) == "function") and category:GetID() or nil
  end
  local parent = S.RegisterCanvasLayoutCategory(pages[1].frame, pages[1].name)
  if parent == nil then return nil end
  local categories, ids = { [pages[1].id] = parent }, { [pages[1].id] = idOf(parent) }
  if type(S.RegisterCanvasLayoutSubcategory) == "function" then
    for i = 2, #pages do
      local sub = S.RegisterCanvasLayoutSubcategory(parent, pages[i].frame, pages[i].name)
      categories[pages[i].id] = sub
      ids[pages[i].id] = idOf(sub)
    end
  end
  -- The category starts expanded, so its sub-pages are seen in the list without
  -- clicking its toggle (our own category object's method) [verified: SettingsCategoryMixin:SetExpanded,
  -- Blizzard_Settings_Shared/Blizzard_Category.lua:114; the list reads IsExpanded, Blizzard_CategoryList.lua:102]
  if type(parent.SetExpanded) == "function" then parent:SetExpanded(true) end
  S.RegisterAddOnCategory(parent)
  Compat.optionsCategories, Compat.optionsIds, Compat.optionsMain = categories, ids, pages[1].id
  return Compat.optionsIds[pages[1].id] or parent
end

-- Opens a registered page (default: the first). An unregistered page falls back to the first. → true | false
function Compat.openOptions(page)
  local S = env("Settings")
  if Compat.optionsCategories == nil or type(S) ~= "table" or type(S.OpenToCategory) ~= "function" then
    return false
  end
  local id = page and Compat.optionsCategories[page] and page or Compat.optionsMain
  S.OpenToCategory(Compat.optionsIds[id] or Compat.optionsCategories[id])
  return true
end

-- Addon memory in KB, or nil when the API is absent.
function Compat.memoryKB(addon)
  local update, get = env("UpdateAddOnMemoryUsage"), env("GetAddOnMemoryUsage")
  if type(get) ~= "function" then return nil end
  if type(update) == "function" then update() end
  local ok, kb = pcall(get, addon or ADDON)
  if ok and type(kb) == "number" then return kb end
  return nil
end
