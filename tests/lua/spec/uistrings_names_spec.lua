-- The ui index built from the real data (data/ui + data/english/ui), then every English item name, spell name, quest
-- title and objective line (data/english/{item,spell,quest,objective}) run through the UNRESTRICTED `index:match`,
-- which is what a surface without an `only` list does. Names stay in English, so no key from the name-template batch
-- (provenance source "draft-ui-…" below) may answer: "%s Recipe" must not take "Desert Recipe", "%s Begins" not
-- "The Hunt Begins", "Illusion: %s" not a spell's name. Every such template whose argument holds text is key-only
-- (UIStrings.ONLY). An exact word an older key already shipped with the same Japanese ("Reset") is not a hit.
-- The whole corpus runs (≈60,000 lines, about two seconds under LuaJIT): no sampling, so it is deterministic.
local H = require("tests.lua.spec.helpers")
local json = require("dkjson")
local lfs = require("lfs")

local function jsonlFiles(dir)
  local out = {}
  for f in lfs.dir(H.ROOT .. "/" .. dir) do
    if f:find("%.jsonl$") then out[#out + 1] = H.ROOT .. "/" .. dir .. "/" .. f end
  end
  table.sort(out)
  return out
end

-- Calls fn(record) for every line of the dir's .jsonl files holding `needle` (a plain prefilter; nil = every line).
local function eachRecord(dir, needle, fn)
  for _, path in ipairs(jsonlFiles(dir)) do
    for line in io.lines(path) do
      if not needle or line:find(needle, 1, true) then fn(json.decode(line)) end
    end
  end
end

describe("name-carrying templates never answer an unrestricted match on a name (real data)", function()
  local index, rows, batch, names

  setup(function()
    local ns = H.loadChunks({ "Core/UIStringKeys.lua", "Core/UIStrings.lua" })
    local english, ja = {}, {}
    batch = {}
    eachRecord("data/english/ui", nil, function(r) english[r.id] = r.en end)
    eachRecord("data/ui", nil, function(r)
      if type(r.ja) == "string" and r.ja ~= "" then
        ja[r.id] = r.ja
        local source = r.provenance and r.provenance.source or ""
        if source:find("^draft%-ui%-menus") then batch[r.id] = true end
      end
    end)
    local function h1(text)
      local n = 0
      for i = 1, #text do n = (n * 31 + text:byte(i)) % 4294967296 end
      return n
    end
    rows = {}
    for key, text in pairs(ja) do
      if english[key] then rows[key] = { text, h1(english[key]), "." } end
    end
    index = ns.UIStrings.build({ rows = rows, hash = h1, english = function(key) return english[key] end })
    names = {}
    local function add(r) names[#names + 1] = r.en end
    eachRecord("data/english/item", '"field": "name"', add)
    eachRecord("data/english/spell", '"field": "name"', add)
    eachRecord("data/english/quest", '"field": "title"', add)
    eachRecord("data/english/objective", nil, add)
  end)

  -- A hit is the batch's when the key answering is a batch row, unless it is an exact word whose English an older key
  -- already shipped with the same Japanese (the line read the same before the batch).
  local function isBatchHit(key, args)
    if not batch[key] then return false end
    if args == nil then
      for _, k in ipairs(index.synonyms[key] or { key }) do
        if not batch[k] and rows[k][1] == rows[key][1] then return false end
      end
    end
    return true
  end

  it("the corpus and the batch rows are loaded", function()
    assert.is_true(#names > 50000, "names: " .. #names)
    assert.is_true(batch.CRAFTING_ORDER_RECIPE_PROFESSION_FMT == true)
    assert.is_true(batch.CALENDAR_EVENTNAME_FORMAT_START == true)
  end)

  it("no item / spell name, quest title or objective line is taken by a batch key", function()
    local hits = {}
    for _, name in ipairs(names) do
      local key, args = index:match(name)
      if key and isBatchHit(key, args) then hits[#hits + 1] = name .. " → " .. key end
    end
    assert.are.same({}, hits)
  end)

  it("the known name collisions stay English; the keys still answer where a surface asks for them", function()
    for _, name in ipairs({ "Desert Recipe", "The Hunt Begins", "Manifestation Ends", "Illusion: Black Dragonkin" }) do
      assert.is_nil(index:match(name), name)
    end
    assert.are.equal("CRAFTING_ORDER_RECIPE_PROFESSION_FMT",
      (index:matchOnly("Alchemy Recipe", { "CRAFTING_ORDER_RECIPE_PROFESSION_FMT" })))
    assert.are.equal("CALENDAR_EVENTNAME_FORMAT_START",
      (index:matchOnly("Darkmoon Faire Begins", { "CALENDAR_EVENTNAME_FORMAT_START" })))
  end)
end)
