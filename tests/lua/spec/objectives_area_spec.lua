local H = require("tests.lua.spec.helpers")

-- Core/Objectives builds one index from several sources: the objective texts (QuestObjective id) and the
-- quests' area texts (quest id). An entry is its type and id; one fingerprint with different Japanese across the
-- sources is ambiguous and never matched. Pure: loaded under an empty environment.
describe("Core/Objectives: objective and area sources", function()
  local O

  -- a stand-in fingerprint: the index only compares the number `hash` returns with each row's h1
  local H1 = { ["Archive Burned"] = 1, ["Scout through the Fargodeep Mine"] = 2, ["Tower Marked"] = 3,
    ["Rescue Drull"] = 4, ["Kernobee Rescue"] = 5 }
  local function h1(text) return H1[text] end
  local function r(ja, en) return { ja, H1[en], "." } end

  before_each(function()
    local ns = {}
    H.loadPure("Core/Objectives.lua", "WoWForeverJapanese", ns)
    O = ns.Objectives
  end)

  it("matches an area row by its fingerprint, keeps the count and names the type", function()
    local index = O.build({ hash = h1, sources = {
      { type = "objective", rows = { [380142] = r("Archiveを焼き払う", "Archive Burned") } },
      { type = "area", rows = { [62] = r("Fargodeep Mineを偵察する", "Scout through the Fargodeep Mine") } },
    } })
    local id, args, kind = index:match("0/1 Scout through the Fargodeep Mine")
    assert.are.equal(62, id); assert.are.equal("area", kind)
    assert.are.same({ form = "affix", before = "0/1 ", after = "" }, args)
    id, args, kind = index:match("Archive Burned: 0/1")
    assert.are.equal(380142, id); assert.are.equal("objective", kind)
    assert.are.same({ form = "affix", before = "", after = ": 0/1" }, args)
    assert.is_nil(index:match("Find the lost relic"))
  end)

  it("the same id in both types is two entries, never a clash", function()
    local index = O.build({ hash = h1, sources = {
      { type = "objective", rows = { [7] = r("Drullを救出する", "Rescue Drull") } },
      { type = "area", rows = { [7] = r("Kernobeeの救出", "Kernobee Rescue") } },
    } })
    local id, _, kind = index:match("Rescue Drull")
    assert.are.same({ 7, "objective" }, { id, kind })
    id, _, kind = index:match("Kernobee Rescue")
    assert.are.same({ 7, "area" }, { id, kind })
    assert.are.same({ shipped = 2, indexed = 2, ambiguous = 0, byType = { objective = 1, area = 1 } }, index.counts)
  end)

  it("one fingerprint with different Japanese across the two types is ambiguous and never shown", function()
    local index = O.build({ hash = h1, sources = {
      { type = "objective", rows = { [380900] = r("Towerに印をつける", "Tower Marked") } },
      { type = "area", rows = { [2240] = r("Towerを示す", "Tower Marked"),
        [3000] = r("Drullを救出する", "Rescue Drull") } },
    } })
    assert.is_nil(index:match("0/1 Tower Marked"))
    assert.are.equal(3000, (index:match("Rescue Drull")))
    assert.are.same({ shipped = 3, indexed = 1, ambiguous = 2, byType = { objective = 1, area = 2 } }, index.counts)
  end)

  it("the same Japanese across the two types is one text: indexed, not ambiguous", function()
    local index = O.build({ hash = h1, sources = {
      { type = "objective", rows = { [1] = r("Drullを救出する", "Rescue Drull") } },
      { type = "area", rows = { [2] = r("Drullを救出する", "Rescue Drull") } },
    } })
    local id, _, kind = index:match("Rescue Drull")
    assert.are.equal(1, id); assert.are.equal("objective", kind) -- the first source's row, deterministically
    assert.are.same({ shipped = 2, indexed = 2, ambiguous = 0, byType = { objective = 1, area = 1 } }, index.counts)
  end)

  it("the plain form (`rows`) is one objective source; an empty source counts zero", function()
    local index = O.build({ hash = h1, rows = { [380142] = r("Archiveを焼き払う", "Archive Burned") } })
    local id, _, kind = index:match("Archive Burned")
    assert.are.equal(380142, id); assert.are.equal("objective", kind)
    assert.are.same({ shipped = 1, indexed = 1, ambiguous = 0, byType = { objective = 1 } }, index.counts)
    index = O.build({ hash = h1, sources = { { type = "objective", rows = {} }, { type = "area", rows = {} } } })
    assert.are.same({ shipped = 0, indexed = 0, ambiguous = 0, byType = { objective = 0, area = 0 } }, index.counts)
  end)
end)
