-- Core/Perf.lua: how long the addon's write paths take, added up per label per frame, so a lag report comes with the
-- surface that caused it (docs/systems/diagnostics.md). A label is a surface name or a tooltip pass, never game text.
-- Pure: the clock (milliseconds), the Lua memory count (KB), the frame stamp (constant within one frame) and the trail
-- are injected by Main; without them every call is a no-op. Nothing allocates per call, and nothing runs on its own:
-- a frame's totals are looked at when the first timed call of a later frame stops.
local _, WFJ = ...
local Perf = {}
WFJ.Perf = Perf

Perf.SLOW_MS = 8 -- half of a 60 fps frame: one label taking this long in one frame is felt as a hitch

local deps = {}
local session = {} -- label → { calls, ms, max }
local frame = {} -- label → { ms, kb, calls } for the frame being counted (rows are reused, zeroed on flush)
local depth = {} -- label → open calls; only the outermost one counts, so a pass that calls itself counts once
local opened = {} -- label → the frame its outermost call opened in
local current

function Perf.setDeps(d)
  deps = d or {}
end

local function flush()
  for label, row in pairs(frame) do
    if row.calls > 0 and row.ms >= Perf.SLOW_MS and WFJ.Diag then
      local ms = math.floor(row.ms * 10 + 0.5) / 10
      local e = WFJ.Diag.log("slow", label, { ms = ms, kb = math.floor(row.kb + 0.5), calls = row.calls })
      if e and (e.n or 1) > 1 and ms > (e.ms or 0) then
        e.ms, e.kb, e.calls = ms, math.floor(row.kb + 0.5), row.calls
      end
    end
    row.ms, row.kb, row.calls = 0, 0, 0
  end
end

-- Opens a timed call of `label`. → the clock and memory at the start (nil when there is no clock)
function Perf.start(label)
  if not deps.clock then return nil end
  local stamp = deps.frame and deps.frame()
  if (depth[label] or 0) > 0 and opened[label] ~= stamp then depth[label] = 0 end -- a call that raised never closed
  if (depth[label] or 0) == 0 then opened[label] = stamp end
  depth[label] = (depth[label] or 0) + 1
  return deps.clock(), deps.mem and deps.mem() or 0
end

-- Closes the call `start` opened; the outermost one adds its time and allocation to the label.
function Perf.stop(label, t0, k0)
  if t0 == nil or not deps.clock then return end
  local d = (depth[label] or 1) - 1
  depth[label] = d > 0 and d or 0
  if d > 0 then return end
  local ms = deps.clock() - t0
  local kb = (deps.mem and deps.mem() or 0) - (k0 or 0)
  if kb < 0 then kb = 0 end -- the collector ran during the call
  local stamp = deps.frame and deps.frame()
  if stamp ~= current then
    flush()
    current = stamp
  end
  local row = frame[label]
  if not row then
    row = { ms = 0, kb = 0, calls = 0 }
    frame[label] = row
  end
  row.ms, row.kb, row.calls = row.ms + ms, row.kb + kb, row.calls + 1
  local s = session[label]
  if not s then
    s = { calls = 0, ms = 0, max = 0 }
    session[label] = s
  end
  s.calls, s.ms = s.calls + 1, s.ms + ms
  if ms > s.max then s.max = ms end
  if deps.trail then deps.trail(label) end
end

-- `fn` timed under `label`, for a callback whose result nobody reads (a tooltip post-call). → the timed function
function Perf.wrap(label, fn)
  return function(...)
    local t0, k0 = Perf.start(label)
    fn(...)
    Perf.stop(label, t0, k0)
  end
end

-- The session's labels by total time, at most `n`. → { { label, calls, ms, max }, … }
function Perf.report(n)
  local out = {}
  for label, s in pairs(session) do out[#out + 1] = { label = label, calls = s.calls, ms = s.ms, max = s.max } end
  table.sort(out, function(a, b) return a.ms > b.ms end)
  for i = #out, (n or 10) + 1, -1 do out[i] = nil end
  return out
end

function Perf.reset()
  session = {}
end
