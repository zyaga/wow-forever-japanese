-- Adds up luacov stats files, one per test process, into one, the way luacov adds a run to a file it finds.
--   lua tests/lua/merge-coverage.lua <out> <stats file>...
local stats = require("luacov.stats")

local out = assert(arg[1], "usage: merge-coverage.lua <out> <stats file>...")
local total = {}
for i = 2, #arg do
  for name, file in pairs(stats.load(arg[i]) or {}) do
    local into = total[name]
    if not into then
      total[name] = file
    else
      into.max = math.max(into.max, file.max)
      for line, hits in pairs(file) do
        if type(line) == "number" then
          into[line] = (into[line] or 0) + hits
          into.max_hits = math.max(into.max_hits, into[line])
        end
      end
    end
  end
end
stats.save(out, total)
