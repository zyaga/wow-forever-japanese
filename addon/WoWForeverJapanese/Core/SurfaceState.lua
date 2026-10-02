-- Core/SurfaceState.lua: the pure capture → apply → restore machine over a FontString-like interface
-- (GetText/SetText/GetFont/SetFont). Records are keyed by LOGICAL element (surface, key: quest field, gossip
-- option index, tooltip line n), never by widget identity: pooled widgets are reused. No global is read.
-- A record holds the client's live English only for the life of the surface (glossary: Render record).
local _, WFJ = ...
local SurfaceState = {}
WFJ.SurfaceState = SurfaceState

local records = {} -- [surface] = { [key] = rec }

local function bucket(surface, create)
  local b = records[surface]
  if not b and create then b = {}; records[surface] = b end
  return b
end

local function readFont(fs)
  local path, size, flags = fs:GetFont()
  return { path = path, size = size, flags = flags }
end

local function sameFont(a, b)
  if a == nil or b == nil then return a == b end
  return a.path == b.path and a.size == b.size and a.flags == b.flags
end

-- Returns the record, or nil when the capture is our own write echoing back (re-entrancy guard).
-- A widget belongs to at most one record, on any surface. The client rewrites TEXT but never fonts, so:
--   same key, same widget   → keep the original font on record and carry the font we currently have applied;
--   same key, other widget  → the old widget keeps our font: put its original back (its text is the client's);
--   any other record on this widget (pool reuse, even across surfaces) → drop it silently, carry its fonts.
function SurfaceState.capture(surface, key, fs, en, meta)
  local b = bucket(surface, true)
  local rec = b[key]
  if rec and rec.fs == fs and rec.applied ~= nil and en == rec.applied then return nil end

  local origFont, carriedFont
  if rec then
    if rec.fs == fs then
      origFont, carriedFont = rec.font, rec.appliedFont
    elseif rec.appliedFont then
      rec.fs:SetFont(rec.font.path, rec.font.size, rec.font.flags)
    end
  end
  for _, sb in pairs(records) do
    for k, r in pairs(sb) do
      if r ~= rec and r.fs == fs then
        origFont = origFont or r.font
        carriedFont = carriedFont or r.appliedFont
        sb[k] = nil
      end
    end
  end

  rec = {
    surface = surface, key = key, fs = fs, en = en,
    font = origFont or readFont(fs),
    applied = nil, appliedFont = carriedFont, last = nil,
    meta = meta,
  }
  b[key] = rec
  return rec
end

function SurfaceState.get(surface, key)
  local b = bucket(surface)
  return b and b[key] or nil
end

-- Writes `text` (and `font` = {path,size,flags}, or nil to keep/restore the original font).
-- Returns true, fontSetResult on success; false when there is no record.
function SurfaceState.apply(surface, key, text, font)
  local rec = SurfaceState.get(surface, key)
  if not rec then return false end
  local fontOk
  if font then
    if not sameFont(rec.appliedFont, font) then
      fontOk = rec.fs:SetFont(font.path, font.size, font.flags)
      -- A refused SetFont changed nothing: record no font, so the next apply tries again and a restore has no font
      -- to put back. (On a fresh client launch the bundled font file is not loaded yet when the load-time labels
      -- are shown, and hundreds are refused; Render.retryFonts retries them.)
      if fontOk ~= false then rec.appliedFont = font end
    end
  elseif rec.appliedFont then
    rec.fs:SetFont(rec.font.path, rec.font.size, rec.font.flags)
    rec.appliedFont = nil
  end
  rec.fs:SetText(text)
  rec.applied = text
  rec.last = { text = text, font = font }
  return true, fontOk
end

-- Tries only the font of an applied record again (a font the client refused while the bundled font file was
-- still loading). Nothing happens unless the widget still shows the text we applied. → true (applied) · false
-- (refused again) · nil (nothing to retry)
function SurfaceState.applyFont(surface, key, font)
  local rec = SurfaceState.get(surface, key)
  if not rec or not font or rec.applied == nil or sameFont(rec.appliedFont, font) then return nil end
  if rec.fs:GetText() ~= rec.applied then return nil end
  if rec.fs:SetFont(font.path, font.size, font.flags) == false then return false end
  rec.appliedFont = font
  if rec.last then rec.last.font = font end
  return true
end

-- Puts back exactly what the client wrote: the text if we replaced it, the font if we changed it (a carried font
-- from a replaced record counts). Returns whether anything was written.
function SurfaceState.restore(surface, key)
  local rec = SurfaceState.get(surface, key)
  if not rec then return false end
  local wrote = false
  if rec.applied ~= nil then
    rec.fs:SetText(rec.en)
    rec.applied = nil
    wrote = true
  end
  if rec.appliedFont then
    rec.fs:SetFont(rec.font.path, rec.font.size, rec.font.flags)
    rec.appliedFont = nil
    wrote = true
  end
  return wrote
end

-- Re-applies the last applied text/font after a restore. Returns whether anything was written.
-- No caller yet: Render re-resolves instead. Kept for a surface that restores around a client re-layout.
function SurfaceState.reapply(surface, key)
  local rec = SurfaceState.get(surface, key)
  if not rec or rec.applied ~= nil or rec.last == nil then return false end
  return (SurfaceState.apply(surface, key, rec.last.text, rec.last.font))
end

-- Restores every record of the surface that has text or a carried font applied, then drops them all.
-- Returns the number of records that needed a write.
function SurfaceState.release(surface)
  local b = bucket(surface)
  if not b then return 0 end
  local n = 0
  for key in pairs(b) do
    if SurfaceState.restore(surface, key) then n = n + 1 end
  end
  records[surface] = nil
  return n
end

-- Forgets one record WITHOUT restoring text the client has since rewritten (that would overwrite fresh English).
-- If the widget still shows the text we applied, the client has not touched it: put the client's English back.
-- A carried / applied font is always reset. Returns whether anything was written.
function SurfaceState.drop(surface, key)
  local rec = SurfaceState.get(surface, key)
  if not rec then return false end
  local wrote = false
  local current = rec.fs:GetText()
  if rec.applied ~= nil and not SurfaceState.secret(current) and current == rec.applied then
    rec.fs:SetText(rec.en)
    wrote = true
  end
  if rec.appliedFont then
    rec.fs:SetFont(rec.font.path, rec.font.size, rec.font.flags)
    wrote = true
  end
  records[surface][key] = nil
  return wrote
end

-- drop() for every record of the surface, then forget the surface. Returns the number of records that wrote.
function SurfaceState.dropAll(surface)
  local b = bucket(surface)
  if not b then return 0 end
  local n = 0
  for key in pairs(b) do
    if SurfaceState.drop(surface, key) then n = n + 1 end
  end
  records[surface] = nil
  return n
end

-- Forgets a surface's records without reading or writing any widget: for a pass whose lines the client has rewritten
-- with text the addon may not compare (a tooltip in combat), where drop would have to read them. → records forgotten
function SurfaceState.discard(surface)
  local b = bucket(surface)
  if not b then return 0 end
  local n = 0
  for _, rec in pairs(b) do
    n = n + 1
    if rec.appliedFont then rec.fs:SetFont(rec.font.path, rec.font.size, rec.font.flags) end -- no text is read
  end
  records[surface] = nil
  return n
end

-- Whether a value may not be read (the client's secret values): Render sets it from the client. Default: never.
SurfaceState.secret = function() return false end

function SurfaceState.records(surface)
  return bucket(surface) or {}
end

function SurfaceState.surfaces()
  return records
end

function SurfaceState.count(surface)
  local n = 0
  for _ in pairs(SurfaceState.records(surface)) do n = n + 1 end
  return n
end
