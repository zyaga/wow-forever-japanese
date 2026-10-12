-- Core/Translator.lua: the policy "what should this element show now". Pure: every dependency is injected,
-- no global is read (tests load it under an empty environment). Returns action, payload:
--   "leave"  frame untouched, no marker (master/area off, or modifier held)
--   "none"   no usable translation: payload { reason?, marker="missing"? }
--   "apply"  payload { ja, marker="stale"? }
-- deps = { enabled(), areaEnabled(area), modifierHeld(), lookup(kind, id) → {ja, status}|nil,
--          marker(name) → bool, align(ja, lines) → ok[, text] [optional; absent = unaligned entries fail closed],
--          alignVariants(variants, shapes, lines, nameScope) → ok[, text] [optional; an entry with
--            `variants` (a branch line, ADR-043) goes through it on the gated path; absent → fails closed],
--          alignSections(sections, lines, nameScope) → ok[, text] [optional; an entry with `sections` (a
--            sectioned line) goes through it the same way; absent → fails closed],
--          expand(ja) → ja [optional; player tokens, applied to every `apply` text after the align gate],
--          fill(ja, args) → text|nil [optional; UI templates, run when ctx.args is present, before expand;
--          nil = the Japanese needs a value the live line did not have → fails closed],
--          fingerprints(live, masked) → { h1, … }, inconclusive [optional; quest live check, see below;
--            `masked`: digit runs as `#`, for a line filled from live values] }
-- Live check (ADR-019): a quest surface passes the API English as ctx.live. For a "quest.<field>" entry with an
-- h1 and a non-empty fingerprint list, the stale marker follows the live client: no fingerprint equal to h1 → the
-- Japanese shows marked stale; one equal → unmarked, whatever the build-time status. No ctx.live, no dep or no
-- fingerprints (player not known yet) → the status decides. ADR-024: the entry's h1f (the female
-- variant of a `$G` English) counts as a match like h1; with `inconclusive` (a 1–2 code-point player name occurs in the
-- text) no match is not proof of a change, so the status decides instead of the marker.
-- `lines` is ctx.lines and may be nil when a surface passes no ctx; align must accept that; ctx.nameScope
-- (the tooltip's name line) is extra text names may come from.
-- Gated kinds (ADR-007): an "item" / "spell" entry carries $N values only the live tooltip fills, so it always
-- goes through align when unaligned, or stale (its tooltip English changed since it was translated): on a pass a stale
-- entry applies with the stale marker, on a fail it leaves the English like any gated entry.
-- An entry with an empty `ja` is not a translation: fails closed and the live English stays.
-- status is the generated one-char code: "." trusted · "s" stale · "u" unaligned (docs/architecture/data-model.md).
local _, WFJ = ...
local Translator = {}
WFJ.Translator = Translator

local STATUS = { ["."] = "trusted", s = "stale", u = "unaligned" }
local GATED = { item = true, spell = true }

function Translator.new(deps)
  local T = {}

  -- The align gate sees the stored text; only what is written gets the player's values.
  local function shown(ja)
    if deps.expand == nil then return ja end
    return (deps.expand(ja))
  end

  -- A UI template gets the live line's values. → text | nil
  -- A UI template's captured arguments, then the values the server fills into a quest line: a
  -- `$N<k>` count in `Collect $1oa Lady's Tear Moss.` is not in the text the server sent, only in the line
  -- the player is shown. nil from either is fail-closed and the caller leaves the line English.
  local function filled(ja, ctx)
    if ctx ~= nil and ctx.args ~= nil and deps.fill ~= nil then
      ja = deps.fill(ja, ctx.args)
      if type(ja) ~= "string" then return nil end
    end
    if deps.fillValues == nil then return ja end
    local live = ctx and (ctx.live or (ctx.lines and table.concat(ctx.lines, "\n")))
    return deps.fillValues(ja, live)
  end

  -- → true (live English differs from the checked English) · false (matches) · nil (no live check possible)
  local function liveDiffers(kind, entry, ctx)
    if ctx == nil or ctx.live == nil or deps.fingerprints == nil or entry.h1 == nil then return nil end
    if type(kind) ~= "string" or kind:sub(1, 6) ~= "quest." then return nil end
    -- a line filled from the live values (`Collect $1oa …` → `$N1`) ships a masked h1: every number of both
    -- sides is `#`, so the server's count cannot fail the check and a rewording still does
    local masked = type(entry.ja) == "string" and entry.ja:find("%$[ND]%d") ~= nil
    local fps, inconclusive = deps.fingerprints(ctx.live, masked)
    if type(fps) ~= "table" or #fps == 0 then return nil end
    for _, h in ipairs(fps) do
      if h == entry.h1 or (entry.h1f ~= nil and h == entry.h1f) then return false end
    end
    if inconclusive then return nil end
    return true
  end

  local function none(reason)
    local payload = {}
    if reason then payload.reason = reason end
    if deps.marker("missing") then payload.marker = "missing" end
    return "none", payload
  end

  function T.resolve(area, kind, id, ctx)
    if not deps.enabled() then return "leave" end
    if not deps.areaEnabled(area) then return "leave" end
    if deps.modifierHeld() then return "leave" end

    local entry = deps.lookup(kind, id)
    if entry ~= nil and entry.sections ~= nil then return T.sections(entry, ctx) end
    if entry ~= nil and entry.variants ~= nil then return T.variants(entry, ctx) end
    if entry == nil or entry.ja == nil or entry.ja == "" then return none() end

    local status = STATUS[entry.status]
    local ja = entry.ja
    -- gated by the kind's type: a tooltip asks for `item.description` / `spell.description`
    local type_ = type(kind) == "string" and kind:match("^%a+") or kind
    local gated = status == "unaligned" or (status == "stale" and GATED[type_] == true)
    if (status == "trusted" or status == "stale") and not gated then
      ja = filled(ja, ctx)
      if ja == nil or ja == "" then return none("fill_failed") end
    end
    if (status == "trusted" or status == "stale") and not gated then
      local stale = liveDiffers(kind, entry, ctx)
      if stale == nil then stale = status == "stale" end
      local payload = { ja = shown(ja) }
      if stale and deps.marker("stale") then payload.marker = "stale" end
      return "apply", payload
    elseif gated then
      if deps.align == nil then return none("unaligned_ungated") end
      -- align → ok[, text]: `text` is the Japanese with live values filled in; a bare `true` keeps entry.ja.
      local ok, text = deps.align(entry.ja, ctx and ctx.lines, ctx and ctx.nameScope)
      if not ok then return none("align_failed") end
      local payload = { ja = shown((type(text) == "string" and text ~= "") and text or entry.ja) }
      if status == "stale" and deps.marker("stale") then payload.marker = "stale" end
      return "apply", payload
    end
    return none("not_shipped")
  end

  -- A branch line (ADR-043). Only an item / spell line is one, and those are always gated: the one
  -- variant that fits the live line applies (stale marker as for any gated entry), otherwise English.
  function T.variants(entry, ctx)
    local status = STATUS[entry.status]
    if status ~= "unaligned" and status ~= "stale" then return none("not_shipped") end
    if deps.alignVariants == nil then return none("unaligned_ungated") end
    local ok, text = deps.alignVariants(entry.variants, entry.shapes, ctx and ctx.lines, ctx and ctx.nameScope)
    if not ok or type(text) ~= "string" or text == "" then return none("align_failed") end
    local payload = { ja = shown(text) }
    if status == "stale" and deps.marker("stale") then payload.marker = "stale" end
    return "apply", payload
  end

  -- A sectioned line: a heading and optional paragraphs, each found by the words it begins with. Gated like a
  -- branch line: every live paragraph must be found and fit, otherwise English.
  function T.sections(entry, ctx)
    local status = STATUS[entry.status]
    if status ~= "unaligned" and status ~= "stale" then return none("not_shipped") end
    if deps.alignSections == nil then return none("unaligned_ungated") end
    local ok, text = deps.alignSections(entry.sections, ctx and ctx.lines, ctx and ctx.nameScope)
    if not ok or type(text) ~= "string" or text == "" then return none("align_failed") end
    local payload = { ja = shown(text) }
    if status == "stale" and deps.marker("stale") then payload.marker = "stale" end
    return "apply", payload
  end

  return T
end
