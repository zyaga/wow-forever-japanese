-- UI/Render.lua: binds SurfaceState to real FontStrings and owns the "desired text" rule:
--   apply → ja in the bundled font · none → the client's English, untouched.
--   leave / none → restore if something is applied. Zero writes when nothing changes.
--   Markers: a surface that registered a BANNER FontString (Render.setBanner) shows its marker messages there, one
--   line outside the text (quest window: the stone band under the NPC name); a surface without a banner gets the
--   message inline (on its own line above prose, before a single-line title), and that widget takes the bundled
--   font so the kanji render (one font per widget).
-- Surfaces call show() on their event and release() on close; refresh() runs on State events.
-- Readings: after an apply the record is offered to UI/Readings (the word-reading box; it takes only the
-- quest / gossip prose surfaces it lists); every restore, release, forget and stale drop detaches it first.
local _, WFJ = ...
local Render = {}
WFJ.Render = Render

local SS = WFJ.SurfaceState
local translator
Render.fontFailures = 0 -- SetFont returned false (bad path / unsupported face / font file not loaded yet); /wfj debug
-- Where they happen, for /wfj debug: surface → { n, key, size, flags } (the first failing record's arguments).
Render.fontFailureSurfaces = {}
-- Records whose font was refused and not applied since (weak keys: a dropped record is forgotten).
local pendingFonts = setmetatable({}, { __mode = "k" })
Render.BLANK = " " -- what a companion line shows while its primary is applied

-- The client's secret test, for the record machine (which reads no global itself).
SS.secret = function(v)
  local f = WFJ.Compat and WFJ.Compat.resolve("issecretvalue")
  return type(f) == "function" and f(v) == true
end

function Render.init(T)
  translator = T
end

local function sameFont(a, b)
  if a == nil or b == nil then return a == b end
  return a.path == b.path and a.size == b.size and a.flags == b.flags
end

local banners = {} -- surface → the FontString its marker messages are shown on (may be shared by surfaces)

-- The marker banner widget (markers are legible messages at the top): one FontString of ours on a
-- small frame parented to `frame` and raised `LIFT` levels above it (the client's child panels paint background art
-- over a string drawn on the frame itself), anchored TOP at (x, y), `width` wide, in the bundled font at 14 px, gold
-- WFJ.MARKER_COLOR, hidden until a marker needs it. Used by the quest window and the gossip window.
Render.BANNER_SIZE = 14
Render.BANNER_LIFT = 10
function Render.createBanner(frame, x, y, width)
  local holder = CreateFrame("Frame", nil, frame)
  holder:SetSize(width, Render.BANNER_SIZE + 6)
  holder:SetPoint("TOP", frame, "TOP", x, y)
  holder:SetFrameLevel(frame:GetFrameLevel() + Render.BANNER_LIFT)
  local fs = holder:CreateFontString(nil, "OVERLAY")
  fs:SetPoint("TOP", holder, "TOP", 0, 0)
  fs:SetWidth(width)
  fs:SetJustifyH("CENTER")
  WFJ.Font.set(fs, WFJ.Font.PATH, Render.BANNER_SIZE, "")
  local c = WFJ.MARKER_COLOR
  fs:SetTextColor(c.r, c.g, c.b)
  fs:Hide()
  return fs, holder
end

-- Registers the FontString a surface shows its markers on. Several surfaces may share one (the three quest
-- panels share the quest window's band); the banner then reflects every record on all of them.
function Render.setBanner(surface, fs)
  banners[surface] = fs
end

-- Inline form for surfaces without a banner: the message on its own line above prose, before a title.
local function inlineMarker(rec, name)
  local kind = rec.meta and rec.meta.kind or ""
  local sep = kind:sub(-6) == ".title" and " " or "\n"
  return WFJ.MARKER_INLINE_COLOR .. WFJ.MARKER[name] .. "|r" .. sep
end
Render.inlineMarker = inlineMarker

-- → text, font (font nil = original) or nil when the element should show what the client wrote; then the
-- Translator action and the marker this element contributes ("stale" / "missing" / nil), for the banner.
-- A companion record (ctx.follow = <key of the primary on the same surface>) shows BLANK (one space, never "":
-- a line the client has cleared reads "", so SurfaceState.drop can never mistake it for ours) in its original font
-- only while the primary *applies* a translation: a tooltip's description run collapses into its first line,
-- and its own English otherwise (including when the primary shows English + the missing marker:
-- a missing translation never touches the other lines). It never resolves the policy itself.
local desired
-- A run of lines shown as one (a tooltip's description and its flavour text): `colors[i]` is the colour of the
-- i-th non-empty English part (a line, or a piece of one between line breaks) when it differs from the first
-- line's ("ffRRGGBB"), and the Japanese has one non-empty part per English part, split at its line breaks;
-- blank lines and empty parts count on neither side. Each such part is wrapped in its colour; a Japanese whose
-- parts do not line up is left as it is. → text
local function colourParts(ja, colors)
  local parts, filled = {}, {}
  for part in (ja .. "\n"):gmatch("(.-)\n") do
    parts[#parts + 1] = part
    if part ~= "" then filled[#filled + 1] = #parts end
  end
  if #filled ~= colors.n then return ja end
  for i, at in ipairs(filled) do
    if colors[i] then parts[at] = "|c" .. colors[i] .. parts[at] .. "|r" end
  end
  return table.concat(parts, "\n")
end
Render.colourParts = colourParts

-- Coloured runs of the English no argument carried ({ run, code }, from Tooltip.matchColoured): each run the
-- Japanese holds exactly once, as plain text, is wrapped in its colour; any other run is left as it is. → text
local function colourRuns(ja, runs)
  for _, r in ipairs(runs) do
    local at, stop = ja:find(r.run, 1, true)
    if at and not ja:find(r.run, stop + 1, true) then
      ja = ja:sub(1, at - 1) .. r.code .. r.run .. "|r" .. ja:sub(stop + 1)
    end
  end
  return ja
end
Render.colourRuns = colourRuns

local function desiredOf(rec)
  local m = rec.meta or {}
  local action, payload = translator.resolve(m.area, m.kind, m.id, m.ctx)
  local inline = banners[rec.surface] == nil
  if action == "apply" then
    local prefix = (inline and payload.marker) and inlineMarker(rec, payload.marker) or ""
    local ja = payload.ja
    if m.ctx and m.ctx.partColors then ja = colourParts(ja, m.ctx.partColors) end
    if m.ctx and m.ctx.runColours then ja = colourRuns(ja, m.ctx.runColours) end
    return prefix .. ja, WFJ.Font.bundled(rec.font), action, payload.marker
  elseif action == "none" and payload and payload.marker then
    -- A compact row (a quest list title, a tracker header or objective) never carries the missing marker:
    -- markers are messages at the top of a window, not a tag on every row; its window says it
    if payload.marker == "missing" and m.ctx and m.ctx.compact then return nil, nil, action, nil end
    if not inline then return nil, nil, action, payload.marker end
    return inlineMarker(rec, payload.marker) .. (rec.en or ""), WFJ.Font.bundled(rec.font), action, payload.marker
  end
  return nil, nil, action, nil
end

-- → text, font, and the record's own action: "apply" only for a primary record that shows its Japanese
-- (a companion's BLANK is not a line of its own).
desired = function(rec)
  local ctx = rec.meta and rec.meta.ctx
  local follow = ctx and ctx.follow
  if follow then
    local primary = SS.get(rec.surface, follow)
    if primary then
      local _, _, action = desiredOf(primary)
      if action == "apply" then return Render.BLANK, nil, "follow" end
    end
    return nil
  end
  local text, font, action = desiredOf(rec)
  return text, font, action
end

-- The text and font the policy would show for an element that has no record: a widget the client only measures
-- with (the gossip ScrollBox's measure widgets) → text, font | nil (show the English as is). Writes nothing.
-- `ctx` (optional): as Render.show's (a UI template's `args`).
function Render.preview(surface, en, font, area, kind, id, ctx)
  if not translator then return nil end
  local text, f, action = desired({ surface = surface, en = en, font = font,
    meta = { area = area, kind = kind, id = id, ctx = ctx } })
  return text, f, action
end

-- Refreshes the banner `surface` shares: the messages of every marker any primary record on those surfaces
-- resolves to ("missing" before "stale"), or hidden when there is none.
local function updateBanner(surface)
  local fs = banners[surface]
  if not fs then return end
  local seen, names = {}, {}
  for s, b in pairs(banners) do
    if b == fs then
      for _, rec in pairs(SS.records(s)) do
        local ctx = rec.meta and rec.meta.ctx
        if not (ctx and ctx.follow) then
          local _, _, _, marker = desiredOf(rec)
          if marker and not seen[marker] then seen[marker] = true; names[#names + 1] = marker end
        end
      end
    end
  end
  if #names == 0 then
    fs:SetText("")
    fs:Hide()
    return
  end
  table.sort(names)
  for i, name in ipairs(names) do names[i] = WFJ.MARKER[name] end
  fs:SetText(table.concat(names, "  "))
  fs:Show()
end
Render.updateBanner = updateBanner

-- The word-reading box is an optional display on the hot path of seven surfaces: an error in it is counted
-- (/wfj debug) and never stops a surface from rendering.
Render.readingErrors = 0
local function readings(fn, rec)
  local V = WFJ.ReadingView
  if not V then return end
  local ok = pcall(V[fn], rec)
  if not ok then Render.readingErrors = Render.readingErrors + 1 end
end

-- Every Japanese line written is offered to Core/RecentLines (the fix window's list). Like the readings
-- above, a failure there is counted and never stops a surface from rendering.
Render.recentErrors = 0
-- Only a write the client asked for (Render.show) records the line; a refresh (the reveal key released, a setting
-- switched) re-writes every applied record in no particular order and would reorder the list and bring back lines
-- of windows closed long ago. A refresh records a record only the first time it applies it.
local function noteRecent(rec, text, fromShow)
  local R = WFJ.RecentLines
  if not R then return end
  if not fromShow and rec.recentNoted then return end
  rec.recentNoted = true
  local m = rec.meta or {}
  local ok = pcall(R.note, m.kind, m.id, rec.surface, text, type(GetTime) == "function" and GetTime() or nil)
  if not ok then Render.recentErrors = Render.recentErrors + 1 end
end

-- Brings one record in line with the policy. Returns whether a write happened.
local function sync(rec, fromShow)
  local text, font, action = desired(rec)
  if text == nil then
    pendingFonts[rec] = nil
    readings("detach", rec)
    return SS.restore(rec.surface, rec.key)
  end
  if rec.applied == text and sameFont(rec.appliedFont, font) then
    pendingFonts[rec] = nil
    return false
  end
  local _, fontOk = SS.apply(rec.surface, rec.key, text, font)
  if action == "apply" then noteRecent(rec, text, fromShow) end
  -- a refused font lays the text out in another face: word rectangles wait for the font (retryFonts attaches)
  if fontOk ~= false then readings("attach", rec) end
  if fontOk == false then
    pendingFonts[rec] = font
  else
    pendingFonts[rec] = nil
  end
  if fontOk == false then
    Render.fontFailures = Render.fontFailures + 1
    local by = Render.fontFailureSurfaces[rec.surface]
    if not by then
      by = { n = 0, key = rec.key, size = font and font.size, flags = font and font.flags }
      Render.fontFailureSurfaces[rec.surface] = by
    end
    by.n = by.n + 1
  end
  return true
end

-- A record whose widget no longer shows what we last left there (our text when applied, the captured English when
-- not) was rewritten by the client without the surface hook firing, e.g. ItemRefTooltip reused for another link.
-- Refreshing it would write stale text back; it is dropped instead.
local function stale(rec)
  if not rec.fs or not rec.fs.GetText then return false end
  local current = rec.fs:GetText()
  if SS.secret(current) then return true end -- the client rewrote the widget with text the addon may not read
  if rec.applied ~= nil then return current ~= rec.applied end
  return current ~= rec.en
end

local function refit(rec)
  local ctx = rec.meta and rec.meta.ctx
  if ctx and ctx.refit then ctx.refit() end
end

-- Called by a surface with the API-returned English for one logical element.
-- ctx: { lines = {...} (tooltip align gate), nameScope = <the name line>, refit = function() tooltip:Show() end,
--        follow = <primary key>, live = <the API English> (quest surfaces: the live check),
--        args, compact = true for a row or fixed-size widget that never carries the missing marker } (all optional)
function Render.show(surface, key, fs, en, area, kind, id, ctx)
  -- Main guards each init step, so surfaces install their hooks even when Render.init failed. Asserting here would
  -- turn one load failure into an error on every hover and window open; nothing to render against renders nothing.
  if not translator then return false end
  local rec = SS.capture(surface, key, fs, en, { area = area, kind = kind, id = id, ctx = ctx })
  if not rec then return false end
  local changed = sync(rec, true)
  if changed then refit(rec) end
  updateBanner(surface)
  return changed
end

-- Re-resolves every live record (one surface, or all). Returns the number of writes.
-- Records are snapshotted before syncing and each distinct `ctx.refit` runs ONCE after the surface's loop
-- (a surface may span several frames, e.g. the six tooltip frames): a refit (tooltip:Show()) may re-enter the
-- surface hook and add records, which must not happen mid-walk. The re-entrancy guard only stops our own echo;
-- if Show() makes the client rewrite lines in English, the surface's refit must carry an in-refit flag.
-- → the number of records whose font is refused and not yet applied (read-only, for /wfj debug)
function Render.pendingFonts()
  local n = 0
  for _ in pairs(pendingFonts) do n = n + 1 end
  return n
end

-- One pending record, for /wfj debug fonts (read-only) → rec | nil
function Render.pendingFontSample()
  return (next(pendingFonts))
end

-- Tries the refused fonts again (the bundled font file can load after the load-time labels are shown on a
-- fresh launch). A record the client has since rewritten is dropped, as refresh does. → the number still pending
function Render.retryFonts()
  -- Only the font is tried again: no policy resolve and no text write per try. A record whose text changed since (a
  -- State refresh re-synced it, or the client rewrote the widget) is no longer this retry's business.
  local n = 0
  for rec, font in pairs(pendingFonts) do
    local result = SS.get(rec.surface, rec.key) == rec and SS.applyFont(rec.surface, rec.key, font)
    if result == false then
      n = n + 1
    else
      pendingFonts[rec] = nil -- applied, or nothing left to retry (clearing a key during pairs is allowed)
      if result == true then readings("attach", rec) end -- the text is laid out in its font now
    end
  end
  return n
end

function Render.refresh(surface)
  if not translator then return 0 end
  local n = 0
  local function walk(s)
    local list = {}
    for _, rec in pairs(SS.records(s)) do list[#list + 1] = rec end
    local refits, seen = {}, {}
    for _, rec in ipairs(list) do
      if stale(rec) then
        readings("detach", rec)
        if SS.drop(rec.surface, rec.key) then n = n + 1 end
      elseif sync(rec) then
        n = n + 1
        local ctx = rec.meta and rec.meta.ctx
        local fn = ctx and ctx.refit
        if fn and not seen[fn] then seen[fn] = true; refits[#refits + 1] = fn end
      end
    end
    for _, fn in ipairs(refits) do fn() end
    updateBanner(s)
  end
  if surface then
    walk(surface)
  else
    local names = {}
    for s in pairs(SS.surfaces()) do names[#names + 1] = s end
    for _, s in ipairs(names) do walk(s) end
  end
  return n
end

local function detachAll(surface)
  for _, rec in pairs(SS.records(surface)) do readings("detach", rec) end
end

function Render.release(surface)
  detachAll(surface)
  local n = SS.release(surface)
  updateBanner(surface)
  return n
end

-- Forgets a surface whose widgets the client may have rewritten since we captured them (see SurfaceState.drop).
function Render.forget(surface)
  detachAll(surface)
  local n = SS.dropAll(surface)
  updateBanner(surface)
  return n
end

-- Forgets a surface whose widgets now hold text the addon may not read (see SurfaceState.discard). Nothing is written.
function Render.discard(surface)
  detachAll(surface)
  local n = SS.discard(surface)
  updateBanner(surface)
  return n
end

WFJ.State.on("enabled", function() Render.refresh() end)
WFJ.State.on("area", function() Render.refresh() end)
WFJ.State.on("modifier", function() Render.refresh() end)
WFJ.State.on("markers", function() Render.refresh() end)
