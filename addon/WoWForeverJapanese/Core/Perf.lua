-- Core/Perf.lua: how long the addon's write paths take, added up per label per frame, so a lag report comes with the
-- surface that caused it (docs/systems/diagnostics.md). A label is a surface name or a tooltip pass, never game text.
-- Pure: the clock (milliseconds), collectgarbage (called with "count", KB), the frame stamp (constant within one frame)
-- and the trail are injected by Main; without a clock every call is a no-op. Nothing allocates per call, and nothing
-- runs on its own: a frame's totals are looked at when the first timed call of a later frame stops, or when the taint
-- watch asks for the trail (Perf.flush).
local _, WFJ = ...
local Perf = {}
WFJ.Perf = Perf

Perf.SLOW_MS = 8 -- half of a 60 fps frame: one label taking this long in one frame is felt as a hitch

local deps = {}
local session = {} -- label → { calls, ms, max }
local frame = {} -- label → { ms, kb, calls } for the frame being counted (rows are reused, zeroed on flush)
local ran = {} -- the labels with a row in use this frame, in the order they first ran
local last = {} -- the previous flushed frame's labels, to tell a repeat of the same frame from a new one
local lastLine
local depth = {} -- label → open calls; only the outermost one counts, so a pass that calls itself counts once
local opened = {} -- label → the frame its outermost call opened in
local current

function Perf.setDeps(d)
  deps = d or {}
end

local function mem()
  return deps.mem and deps.mem("count") or 0
end

-- The frame's line for the trail: its labels in order, the same string again for a frame that ran the same labels
-- (a hovered item refreshing), so the taint watch counts it in place instead of filling its ring.
local function trailLine()
  local same = #ran == #last
  for i = 1, #ran do
    if ran[i] ~= last[i] then same = false end
    last[i] = ran[i]
  end
  for i = #last, #ran + 1, -1 do last[i] = nil end
  if not same or not lastLine then lastLine = table.concat(ran, " ") end
  return lastLine
end

-- Looks at the frame counted so far: a label that took SLOW_MS or more in it is logged, the frame's labels go to the
-- trail, and the rows are zeroed for the next frame.
function Perf.flush()
  if #ran == 0 then return end
  for _, label in ipairs(ran) do
    local row = frame[label]
    if row.ms >= Perf.SLOW_MS and WFJ.Diag then
      local ms, kb = math.floor(row.ms * 10 + 0.5) / 10, math.floor(row.kb + 0.5)
      local e = WFJ.Diag.log("slow", label, { ms = ms, kb = kb, calls = row.calls })
      if e and (e.n or 1) > 1 and ms > (e.ms or 0) then e.ms, e.kb, e.calls = ms, kb, row.calls end
    end
  end
  if deps.trail then deps.trail(trailLine()) end
  for i = #ran, 1, -1 do
    local row = frame[ran[i]]
    row.ms, row.kb, row.calls = 0, 0, 0
    ran[i] = nil
  end
end

-- Opens a timed call of `label`. → the clock and memory at the start (nil when there is no clock)
function Perf.start(label)
  if not deps.clock then return nil end
  local stamp = deps.frame and deps.frame()
  local d = depth[label] or 0
  if d > 0 and opened[label] ~= stamp then d = 0 end -- a call that raised in an earlier frame never closed
  if d == 0 then opened[label] = stamp end
  depth[label] = d + 1
  return deps.clock(), mem()
end

-- Closes the call `start` opened; the outermost one adds its time and allocation to the label.
function Perf.stop(label, t0, k0)
  if t0 == nil or not deps.clock then return end
  local d = (depth[label] or 1) - 1
  depth[label] = d > 0 and d or 0
  if d > 0 then return end
  local ms = deps.clock() - t0
  local kb = mem() - (k0 or 0)
  if kb < 0 then kb = 0 end -- the collector ran during the call
  local stamp = opened[label] -- the outermost call opened in this frame
  if stamp ~= current then
    Perf.flush()
    current = stamp
  end
  local row = frame[label]
  if not row then
    row = { ms = 0, kb = 0, calls = 0 }
    frame[label] = row
  end
  if row.calls == 0 then ran[#ran + 1] = label end
  row.ms, row.kb, row.calls = row.ms + ms, row.kb + kb, row.calls + 1
  local s = session[label]
  if not s then
    s = { calls = 0, ms = 0, max = 0 }
    session[label] = s
  end
  s.calls, s.ms = s.calls + 1, s.ms + ms
  if ms > s.max then s.max = ms end
end

-- `fn(...)` timed under `label`. → fn's first result (every timed path returns at most one value)
function Perf.call(label, fn, ...)
  local t0, k0 = Perf.start(label)
  local r = fn(...)
  Perf.stop(label, t0, k0)
  return r
end

-- `fn` timed under `label`, for a callback whose result nobody reads (a tooltip post-call). → the timed function
function Perf.wrap(label, fn)
  return function(...) Perf.call(label, fn, ...) end
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
