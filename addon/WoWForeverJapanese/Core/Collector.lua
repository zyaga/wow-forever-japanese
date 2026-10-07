-- Core/Collector.lua: records the English the client shows that the addon cannot recognise, into WFJ_Collector
-- (its own SavedVariables), for hand-off and `wfj import english collector` (docs/systems/collector.md, ADR-013).
-- Pure: every world access is an injected dep (Main wires them); no frame access (lint-core-gate).
--   Collector.load(saved, deps) → the table to keep in WFJ_Collector
--     deps = { enabled(), lookup(kind, id) → {h1}|nil, player() → {name, class, race}, build() → string|nil,
--              print(msg), beta() → true on a beta client (optional) }
--   Collector.record(kind, id, field, raw) → result[, reason]   never raises
--     "off" · "known" · "seen" · "recorded" · "replaced" · "capped" · "refused", reason · "error", message
--   Collector.recordGossip(raw, guid) → result[, reason]   never raises (keyed by the gossip key, `n` = NPC ids)
--   Collector.key(raw, player) → the gossip key of `raw` as stored (16 hex) | nil
--   Collector.keys(raw, player) → the candidate keys a translation may be shipped under (full, name only, none; then,
--     for a 1–2 code-point name, full and name only with that name replaced too, ADR-024)
--   Collector.fingerprints(raw, player, masked) → each candidate's h1, inconclusive: the quest live check
--     (ADR-019); `masked`: digit runs `#` first, for a quest line filled from live values
--   Collector.recordNpc(guid, name) · Collector.disclose() · Collector.status() · Collector.clear()
--   Collector.unsentCount() → #Collector.pending() without building or sorting the list
--   Collector.pending(all) → the entries a send carries, sorted by key: { { key, entry }, … } (unsent ones, or every
--     one with `all`), leaving out lines that ship in Japanese now; and how many were left out for that
--   Collector.markSent(list) · list = { { key = …, h = … }, … }: the player sent these (the `sent` map)
--   Collector.buildName(b) → the build string an entry's `b` points at
--   Collector.onDisk(key, h) → whether the saved file holds that entry (it was loaded with it) · isReadOnly()
--   Collector.path() → where the file is saved: PATH, with the beta's folder named on a beta client
-- Privacy by construction: the stored text is normalize_v1 per paragraph, written in Blizzard's own tokens: the
-- player's name as $N (and, for quests, class/race as $C/$R), paragraph breaks as $B$B, the pfQuest convention; no
-- GUID, time, realm, zone, character or account field exists in the shape.
local _, WFJ = ...
local Collector = {}
WFJ.Collector = Collector

local Normalize, Hash = WFJ.Normalize, WFJ.Hash

Collector.VERSION = 1
Collector.CAP_BYTES = 4 * 1024 * 1024 -- estimate of the SavedVariables text (Collector.size); a constant, no setting
Collector.ISSUE_URL = "https://github.com/zyaga/wow-forever-japanese/issues/new?template=collector-send.yml"
Collector.PATH = "World of Warcraft\\<client folder>\\WTF\\Account\\<ACCOUNT>\\SavedVariables\\WoWForeverJapanese.lua"
-- the beta client's folder under World of Warcraft (the Forever beta install)
Collector.BETA_FOLDER = "_classic_beta_"

-- kind → field set.
Collector.KINDS = {
  quest = { title = true, objectives = true, description = true, progress = true, completion = true },
  item = { description = true },
  spell = { description = true, aura = true }, -- aura: the buff / debuff tooltip line
  npc = { name = true },
  gossip = { text = true }, -- id = the gossip key (16 hex), not a game id
}
-- Server text that carries Blizzard's player tokens ($N / $C / $R): the player's name, class and race become tokens.
local TOKEN_KINDS = { quest = true, gossip = true }
Collector.NPC_CAP = 32 -- creature ids kept per gossip entry (a generic "Goodbye" would otherwise grow without bound)
-- Never recorded: text that names the player's bind location: the Hearthstone item's Use: line and the
-- Hearthstone / Astral Recall spell descriptions [likely, not yet confirmed in game].
Collector.SKIP = { item = { [6948] = true }, spell = { [8690] = true, [556] = true } }

local ENTRY_KEYS = { t = true, i = true, f = true, h = true, e = true, b = true, n = true, p = true }

local db, deps
-- key → hash of every entry the file held when it was loaded: what the saved file on disk holds until the next
-- logout or /reload, so a send of the file itself marks only those
local onDisk = {}
local readOnly, cappedPrinted, errors, lastError = false, false, 0, nil
local memo = {} -- key → { raw, result, reason }: the same text again this session answers without re-hashing
-- NPC speech adds an entry per distinct line heard, so the memo is dropped at MEMO_CAP entries (a dropped entry is
-- only evaluated again, never recorded twice: the stored entry answers "seen")
local MEMO_CAP, memoCount = 4096, 0
local function remember(key, value)
  if memoCount >= MEMO_CAP then memo, memoCount = {}, 0 end
  if memo[key] == nil then memoCount = memoCount + 1 end
  memo[key] = value
end

WFJ.Settings.define{ id = "collector.enabled", kind = "boolean", default = true,
  label = "Record English for future translations", ja = "今後の翻訳のために英語テキストを記録する" }
-- the once-a-day chat line that unsent English is waiting (Core/CollectorRemind)
WFJ.Settings.define{ id = "collector.remind", kind = "boolean", default = true,
  label = "Remind me when collected English is waiting to be sent",
  ja = "集めた英語が送信待ちのときに知らせる" }

-- ── Text ───────────────────────────────────────────────────────────────────

local function codePoints(s)
  local _, n = s:gsub("[^\128-\191]", "")
  return n
end

local function isLetter(b)
  return b ~= nil and ((b >= 65 and b <= 90) or (b >= 97 and b <= 122))
end

-- Whole-word, exact-case occurrence (the boundaries Normalize.replaceWord uses).
function Collector.containsWord(text, token)
  local i, t = 1, #token
  while true do
    local j = text:find(token, i, true)
    if not j then return false end
    if not isLetter(text:byte(j - 1)) and not isLetter(text:byte(j + t)) then return true end
    i = j + 1
  end
end

-- Text we may have written ourselves: any CJK character (U+3000..U+9FFF: ideographic punctuation, kana, kanji:
-- UTF-8 lead bytes E3..E9) or a marker message anywhere in it. English game text has neither.
local function isOwnText(raw)
  if raw:find("[\227-\233]") then return true end
  for _, message in pairs(WFJ.MARKER) do
    if raw:find(message, 1, true) then return true end
  end
  return false
end

-- The paragraphs of `raw` after normalize_v1 (markup stripped over the whole text first, so a break inside a link
-- label never splits the link). Breaks (newline, |n, $B) are marked with \1 (not whitespace to the normalizer), and
-- split on afterwards; empty paragraphs are dropped.
-- Blizzard's lowercase $c / $r print the class / race in lowercase ("Journey forth, young druid"), which
-- normalize_v1's exact-case replacement leaves alone; quest text gets the lowercase forms replaced too, so the
-- stored text matches pfQuest's `$c` and the field is recognised as known.
-- A plural the server built from the token ("$cs like yourself" → "druids like yourself") is the word plus "s"
-- as one word, which no whole-word match finds. Only the lookup candidate marked `plural` (Collector.keys, last)
-- turns it into the token plus "s", as normalize_v1 writes "$cs": recorded text keeps a literal plural as written,
-- since the import could not put the word back into a stand-in line.
local function replaceLower(text, player)
  for _, pair in ipairs({ { player.class, "{class}" }, { player.race, "{race}" } }) do
    local word = pair[1]
    if type(word) == "string" and word ~= "" then
      if player.plural then text = Normalize.replaceWord(text, word .. "s", pair[2] .. "s") end
      if word:lower() ~= word then
        if player.plural then text = Normalize.replaceWord(text, word:lower() .. "s", pair[2] .. "s") end
        text = Normalize.replaceWord(text, word:lower(), pair[2])
      end
    end
  end
  return text
end

-- Whole-word, exact-case replacement of a name of any length: the boundaries of Normalize.replaceWord, without its
-- 3-code-point floor. Only the short-name candidates use it; normalize_v1 itself is unchanged.
local function replaceShortName(text, name)
  local out, i, n, t = {}, 1, #text, #name
  while i <= n do
    local j = text:find(name, i, true)
    if not j then out[#out + 1] = text:sub(i); break end
    local whole = not isLetter(text:byte(j - 1)) and not isLetter(text:byte(j + t))
    out[#out + 1] = text:sub(i, j - 1)
    out[#out + 1] = whole and "{name}" or name
    i = j + t
  end
  return table.concat(out)
end

local function paragraphs(raw, player)
  local s = raw:gsub("|n", "\1")
  s = s:gsub("%$[Bb]", "\1"):gsub("\n", "\1")
  local normalized = Normalize.v1(s, player)
  if player then normalized = replaceLower(normalized, player) end
  -- a short-name candidate: on the markup-free text, so a colour code can never be hit
  if player and player.short and type(player.name) == "string" and player.name ~= "" then
    normalized = replaceShortName(normalized, player.name)
  end
  local out = {}
  for seg in (normalized .. "\1"):gmatch("([^\1]*)\1") do
    seg = seg:gsub("^ +", ""):gsub(" +$", "")
    if seg ~= "" then out[#out + 1] = seg end
  end
  return out
end

local TOKENS = { ["{name}"] = "$N", ["{class}"] = "$C", ["{race}"] = "$R" }

-- The stored text: the paragraphs in Blizzard's tokens ($N / $C / $R, paragraphs joined by $B$B), the form pfQuest
-- English has, so `wfj check` counts its paragraphs the same way. Normalize.v1 of the result equals
-- Normalize.v1(raw, player) (every hash vector proves it in collector_spec).
function Collector.text(raw, player)
  local out = paragraphs(raw, player)
  for i, p in ipairs(out) do out[i] = p:gsub("{%a+}", TOKENS) end
  return table.concat(out, "$B$B")
end

-- Estimated SavedVariables text for one entry: the key (twice: the entry key and `t:i:f`), the text with its
-- escapes, and the field names, indentation and punctuation around them (measured on the fixture file); a gossip
-- entry's NPC id list adds its brackets and ~10 bytes per id.
function Collector.size(key, e, n, who)
  local _, escapes = e:gsub('["\\]', "")
  local ids = type(n) == "table" and (16 + 20 * #n) or 0 -- "\t\t\t\t6740, -- [1]\n" per id
  local p = type(who) == "string" and (#who + 12) or 0 -- "\t\t\t["p"] = "Class|Race",\n"
  return 2 * #key + #e + escapes + 117 + ids + p
end

-- GUID → creature id for Creature / Vehicle units, the pattern Blizzard uses [verified: classic_era
-- Blizzard_PTRFeedback/Blizzard_PTRFeedback_Tooltips.lua:89–91]; players, pets and objects → nil.
function Collector.creatureId(guid)
  if type(guid) ~= "string" then return nil end
  local unitType = guid:match("^(%a+)%-")
  if unitType ~= "Creature" and unitType ~= "Vehicle" then return nil end
  return tonumber(guid:match("%-(%d+)%-%x+$"))
end

-- ── Dump ───────────────────────────────────────────────────────────────────

local function fresh()
  return { version = Collector.VERSION, disclosed = false, builds = {}, bytes = 0, capped = false, entries = {},
    sent = {} }
end

-- Estimated SavedVariables text of one `sent` row (`\t\t["<key>"] = "<16 hex>",`).
function Collector.sentSize(key)
  return #key + 30
end

local function isHash(h)
  return type(h) == "string" and #h == 16 and h:match("^[0-9a-f]+$") ~= nil
end

local function positiveInt(v)
  return type(v) == "number" and v >= 1 and v == math.floor(v)
end

local MAX_ID = 2 ^ 31 - 1 -- a creature id is a 32-bit field of the GUID

-- A gossip entry's `n`: absent, or a list of 1..NPC_CAP positive integers with no hole.
local function validNpcs(n)
  if n == nil then return true end
  if type(n) ~= "table" then return false end
  local count = 0
  for _ in pairs(n) do count = count + 1 end
  if count == 0 or count > Collector.NPC_CAP then return false end
  for i = 1, count do
    if not positiveInt(n[i]) or n[i] > MAX_ID then return false end
  end
  return true
end

local function validEntry(key, e, builds)
  if type(key) ~= "string" or type(e) ~= "table" then return false end
  for k in pairs(e) do
    if not ENTRY_KEYS[k] then return false end
  end
  local fields = Collector.KINDS[e.t]
  if not fields or not fields[e.f] then return false end
  if e.t == "gossip" then
    if type(e.i) ~= "string" or e.i ~= e.h or not validNpcs(e.n) then return false end
  elseif e.n ~= nil or not positiveInt(e.i) then
    return false
  end
  if key ~= e.t .. ":" .. e.i .. ":" .. e.f then return false end
  if not isHash(e.h) then return false end
  if type(e.e) ~= "string" or e.e == "" then return false end
  if e.b ~= nil and (type(e.b) ~= "number" or type(builds[e.b]) ~= "string") then return false end
  if e.p ~= nil and type(e.p) ~= "string" then return false end
  return true
end

function Collector.load(saved, d)
  deps, readOnly, cappedPrinted, errors, lastError = d, false, false, 0, nil
  memo, memoCount, onDisk = {}, 0, {}
  if type(saved) ~= "table" then
    db = fresh()
    return db
  end
  if (tonumber(saved.version) or 0) > Collector.VERSION then
    db, readOnly = saved, true
    d.print(("WFJ: the collector file is from a newer version (%d); recording paused, the file is kept untouched.")
      :format(saved.version))
    return saved
  end
  saved.version = Collector.VERSION
  if type(saved.entries) ~= "table" then saved.entries = {} end
  if type(saved.builds) ~= "table" then saved.builds = {} end
  local bytes = 0
  for key, e in pairs(saved.entries) do
    if validEntry(key, e, saved.builds) then
      bytes = bytes + Collector.size(key, e.e, e.n, e.p)
      onDisk[key] = e.h
    else
      saved.entries[key] = nil
    end
  end
  -- `sent`: entry key → the hash that was sent. A row for an entry that is gone, or not a hash, is dropped. The field
  -- is new in the same file version: an older addon leaves a top-level field it does not know as it is.
  if type(saved.sent) ~= "table" then saved.sent = {} end
  for key, h in pairs(saved.sent) do
    if type(key) ~= "string" or not isHash(h) or saved.entries[key] == nil then
      saved.sent[key] = nil
    else
      bytes = bytes + Collector.sentSize(key)
    end
  end
  saved.bytes = bytes
  saved.capped = saved.capped == true
  saved.disclosed = saved.disclosed == true
  db = saved
  return db
end

-- The client build as a string, or nil when the client does not say (an entry without a build cannot be imported).
local function currentBuild()
  local b = deps.build and deps.build()
  -- the shape a `collector@<build>` source must have in the pipeline's English store (model.validate_line)
  if type(b) ~= "string" or not b:match("^[%w%._%-]+$") or #b < 4 or #b > 64 then return nil end
  return b
end

-- Index of build `b` in db.builds, appended on first use.
local function buildIndex(b)
  for i, v in ipairs(db.builds) do
    if v == b then return i end
  end
  local i = #db.builds + 1 -- a hand-edited list with a hole must not move an existing index
  while db.builds[i] ~= nil do i = i + 1 end
  db.builds[i] = b
  return i
end

-- ── Record ─────────────────────────────────────────────────────────────────

-- Adds creature id `npc` to a gossip entry's `n` → the new sorted id list, or nil when nothing changes (already
-- there, or the list is at NPC_CAP).
local function withNpc(entry, npc)
  local n = entry.n or {}
  for _, v in ipairs(n) do
    if v == npc then return nil end
  end
  if #n >= Collector.NPC_CAP then return nil end
  local out = {}
  for _, v in ipairs(n) do out[#out + 1] = v end
  out[#out + 1] = npc
  table.sort(out)
  return out
end

-- Whether Japanese ships for this English: `e` is the stored text, `h1` its first hash half. Gossip is looked up
-- under each key in `keys`; an NPC name never ships in Japanese (names stay English).
local function shipped(kind, id, field, e, h1, keys)
  if kind == "gossip" then
    for _, k in ipairs(keys) do
      if deps.lookup("gossip", k) then return true end
    end
    return false
  end
  if kind == "npc" then return false end
  local entry = deps.lookup(kind .. "." .. field, id) -- field-qualified: spell has two fields
  if entry and (entry.h1 == h1 or (entry.h1f ~= nil and entry.h1f == h1)) then return true end
  -- a shipped quest line filled from the live values (`$N<k>` for `Collect $1oa …`) ships a masked h1
  -- (`fingerprints(…, masked)`): the count is the server's, a rewording is new English.
  -- Item / spell templates are recorded this way too.
  if kind == "quest" and entry and type(entry.ja) == "string" and entry.ja:find("%$[ND]%d") then
    local m1 = Hash.h32x2(Collector.mask(Normalize.v1(e)))
    if entry.h1 == m1 or (entry.h1f ~= nil and entry.h1f == m1) then return true end
  end
  return false
end

-- kind "gossip": `id` and `key` are derived from the text; `npc` is the speaker's creature id or nil.
local function evaluate(kind, id, field, raw, key, npc)
  if Collector.SKIP[kind] and Collector.SKIP[kind][id] then return "refused", "skip" end
  if isOwnText(raw) then return "refused", "own_text" end
  local p = deps.player() or {}
  local name = p.name
  if type(name) ~= "string" or name == "" then return "refused", "no_player" end
  -- Quest and gossip text is normalized with the class and race too: without them a literal class word would be stored.
  if TOKEN_KINDS[kind] and (type(p.class) ~= "string" or p.class == "" or type(p.race) ~= "string" or p.race == "") then
    return "refused", "no_player"
  end
  local build = currentBuild()
  if not build then return "refused", "no_build" end
  -- Checked on the markup-free paragraphs, so a colour code next to the name cannot hide it.
  local plain = table.concat(paragraphs(raw, nil), "\n")
  if not TOKEN_KINDS[kind] then
    -- Blizzard never writes the player's name into item, spell or NPC text: an occurrence is a coincidence
    -- ("Guard", "Light") and a placeholder there would point at the name. Refuse instead.
    if Collector.containsWord(plain, name) then return "refused", "own_name" end
  elseif codePoints(name) < 3 and Collector.containsWord(plain, name) then
    return "refused", "short_name" -- normalize_v1 never replaces a name this short
  end
  -- Only quest and gossip text carry $N/$C/$R, so only they trade the class and race for tokens. That is right for
  -- the common $C/$R lines; a literal class/race word is the known, audit-visible exception.
  local player = TOKEN_KINDS[kind] and { name = name, class = p.class, race = p.race } or nil

  local e = Collector.text(raw, player)
  if e == "" then return "refused", "empty" end
  -- a line holding $C / $R names the recording character's class and race: the pipeline puts a literal word back
  -- only where it is that character's own (a different word there means the line follows the reader's class)
  local who = player and e:find("%$[CR]") and (player.class .. "|" .. player.race) or nil
  local h1, h2 = Hash.h32x2(Normalize.v1(e))
  local h = Hash.hex8(h1) .. Hash.hex8(h2)

  if kind == "gossip" then
    id, key = h, "gossip:" .. h .. ":text"
  end
  -- gossip: the key is the hash, and a row shipped under any candidate key is this English
  if shipped(kind, id, field, e, h1, kind == "gossip" and Collector.keys(raw, player) or nil) then return "known" end

  local old = db.entries[key]
  local n = kind == "gossip" and npc and { npc } or nil
  if old and old.h == h then
    n = kind == "gossip" and npc and withNpc(old, npc)
    if not n then return "seen" end
  end
  local size = Collector.size(key, e, n, who)
  local oldSize = old and Collector.size(key, old.e, old.n, old.p) or 0
  if db.bytes - oldSize + size > Collector.CAP_BYTES then
    db.capped = true
    if not cappedPrinted then
      cappedPrinted = true
      deps.print(("WFJ: collector full (%s). /wfj collector send to send it, /wfj collector clear to start over.")
        :format(Collector.formatBytes(Collector.CAP_BYTES)))
    end
    return "capped"
  end
  db.bytes = db.bytes - oldSize + size
  db.capped = false -- recording again: the file is not full
  if old and old.h == h then -- a gossip line already stored, from another NPC: only `n` grows
    old.n = n
    return "seen"
  end
  db.entries[key] = { t = kind, i = id, f = field, h = h, e = e, b = buildIndex(build), n = n, p = who }
  return old and "replaced" or "recorded"
end

local function recordImpl(kind, id, field, raw)
  if not db or not deps then return "off" end
  if readOnly then return "refused", "read_only" end
  if not deps.enabled() then return "off" end
  local fields = Collector.KINDS[kind]
  -- gossip is keyed by its text, not an id: recordGossip is its only entry point
  if not fields or not fields[field] or kind == "gossip" then return "refused", "bad_kind" end
  if type(id) ~= "number" or id < 1 or id ~= math.floor(id) then return "refused", "bad_id" end
  if type(raw) ~= "string" or raw == "" then return "refused", "empty" end
  local key = kind .. ":" .. id .. ":" .. field
  local m = memo[key]
  if m and m.raw == raw then return m.result, m.reason end

  local result, reason = evaluate(kind, id, field, raw, key)

  -- Replay the same answer for the same text this session. Not replayed: "capped" (space may free up) and the
  -- refusals that depend on state that can still change (no player name or build yet).
  if result ~= "capped" and reason ~= "no_player" and reason ~= "no_build" then
    local replay = (result == "recorded" or result == "replaced") and "seen" or result
    remember(key, { raw = raw, result = replay, reason = reason })
  end
  return result, reason
end

function Collector.record(kind, id, field, raw)
  local ok, result, reason = pcall(recordImpl, kind, id, field, raw)
  if ok then return result, reason end
  errors, lastError = errors + 1, tostring(result)
  return "error", lastError
end

-- One line of NPC dialogue (a gossip greeting or option, a quest greeting), keyed by its gossip key; `guid` is the
-- speaker, reduced to a creature id (none for a non-creature). The session memo is per speaker and text.
local function recordGossipImpl(raw, guid)
  if not db or not deps then return "off" end
  if readOnly then return "refused", "read_only" end
  if not deps.enabled() then return "off" end
  if type(raw) ~= "string" or raw == "" then return "refused", "empty" end
  local npc = Collector.creatureId(guid)
  local mkey = "gossip:" .. tostring(npc or 0) .. ":" .. raw
  local m = memo[mkey]
  if m then return m.result, m.reason end
  local result, reason = evaluate("gossip", nil, "text", raw, nil, npc)
  if result ~= "capped" and reason ~= "no_player" and reason ~= "no_build" then
    local replay = (result == "recorded" or result == "replaced") and "seen" or result
    remember(mkey, { result = replay, reason = reason })
  end
  return result, reason
end

function Collector.recordGossip(raw, guid)
  local ok, result, reason = pcall(recordGossipImpl, raw, guid)
  if ok then return result, reason end
  errors, lastError = errors + 1, tostring(result)
  return "error", lastError
end

-- The gossip key of `raw` exactly as recordGossip stores it: normalize_v1 over the text in Blizzard's tokens, with
-- the player's name, class and race (capitalized or lowercase) replaced: the one key the surfaces look translations
-- up by (ADR-005, ADR-017). player = { name, class, race } (localized) or nil. → 16 hex | nil for empty text.
function Collector.key(raw, player)
  if type(raw) ~= "string" or raw == "" then return nil end
  local e = Collector.text(raw, player)
  if e == "" then return nil end
  return Hash.key(Normalize.v1(e))
end

-- The players a candidate is normalized for, most specific first: as given, the race only and the class only
-- (a line that says one of them literally and the other as a token: "young $R, a wise druid"), name only, none
-- (`false`). For a name under 3 code points (which normalize_v1 never replaces) two more follow (as given, and
-- name only, with that name replaced as a whole word (`short`). They come last, so a line shipped under its
-- literal English still wins.
local function candidates(player)
  local name = type(player) == "table" and player.name or nil
  local list = { player, false, false, name and { name = name } or false, false }
  if name then
    list[2] = { name = name, race = player.race }
    list[3] = { name = name, class = player.class }
  end
  if type(name) == "string" and name ~= "" and codePoints(name) < 3 then
    list[6] = { name = name, class = player.class, race = player.race, short = true }
    list[7] = { name = name, short = true }
  end
  -- last: the class or race plural as the token ("druids" → "{class}s"); a line stored with the literal plural
  -- is found first by the candidates without them
  if name then
    list[#list + 1] = { name = name, class = player.class, race = player.race, short = list[6] and true or nil,
      plural = true }
  end
  return list
end

-- The keys a translation of `raw` may be shipped under, most specific first, duplicates removed (ADR-017): the full
-- key (name, class and race replaced), the name-only key and the key with nothing replaced. A gossip line that says a
-- class or race word literally ("the mage tower") gets the full key only for players of that class, so its data may
-- be keyed either way; looking both up never shows another line's Japanese: each candidate is this same English.
-- A short-name candidate also replaces the name where the text uses it as an ordinary word ("An"); tried
-- after the literal key, it can only find a line whose `$N` form equals this English (the accepted residual, ADR-024).
function Collector.keys(raw, player)
  local out, seen = {}, {}
  for _, p in ipairs(candidates(player)) do
    local k = Collector.key(raw, p or nil)
    if k and not seen[k] then
      seen[k] = true
      out[#out + 1] = k
    end
  end
  return out
end

-- The live-check fingerprints of `raw` (ADR-019): the h1 (first 32 bits) of each distinct candidate of
-- Collector.keys, in the same order: what a shipped quest field's h1 (or h1f) is compared with. player = { name,
-- class, race } (localized). No fingerprints (→ the status decides) for a player not known yet (any of the three
-- missing). `inconclusive` is true when a name under 3 code points occurs in the text (ADR-024): a candidate
-- that matches proves the English, but none matching may be the name used as a word as well, so the caller lets the
-- status decide rather than show a false stale marker. Results are memoized per player and text (the quest window
-- re-resolves its records on every refresh), and the memo is dropped at MEMO_MAX entries.
-- → { h1, … } (possibly empty; shared, never mutate it), inconclusive (true | nil)
Collector.MEMO_MAX = 64
local fpMemo, fpCount = {}, 0
-- `masked`: every digit run becomes `#` before hashing, the key a quest line filled from live values
-- ships (`normalize.mask_values`), so a count the server fills in cannot fail the comparison and a rewording can.
-- A normalized text with every number `#`: a run of digits with `.` / `,` between them (`1,000`, `2.5`) is one,
-- as `normalize.mask_values` reads it on the pipeline side (the template's count code is `#` there).
function Collector.mask(norm)
  return (norm:gsub("%d[%d.,]*%d", "#"):gsub("%d", "#"))
end

function Collector.fingerprints(raw, player, masked)
  local out, seen = {}, {}
  if type(raw) ~= "string" or raw == "" or type(player) ~= "table" then return out end
  for _, k in ipairs({ "name", "class", "race" }) do
    if type(player[k]) ~= "string" or player[k] == "" then return out end
  end
  local mkey = (masked and "#" or "") .. player.name .. "\0" .. player.class .. "\0" .. player.race .. "\0" .. raw
  local hit = fpMemo[mkey]
  if hit then return hit.out, hit.inconclusive end
  local inconclusive = codePoints(player.name) < 3
    and Collector.containsWord(table.concat(paragraphs(raw, nil), "\n"), player.name) or nil -- true | nil
  for _, p in ipairs(candidates(player)) do
    local e = Collector.text(raw, p or nil)
    if e ~= "" then
      local norm = Normalize.v1(e)
      if masked then norm = Collector.mask(norm) end
      local h1, h2 = Hash.h32x2(norm)
      local k = Hash.hex8(h1) .. Hash.hex8(h2)
      if not seen[k] then
        seen[k] = true
        out[#out + 1] = h1
      end
    end
  end
  if fpCount >= Collector.MEMO_MAX then fpMemo, fpCount = {}, 0 end
  fpMemo[mkey], fpCount = { out = out, inconclusive = inconclusive }, fpCount + 1 -- written only once complete
  return out, inconclusive
end

-- The quest giver's name, keyed by creature id; the GUID itself is never stored.
function Collector.recordNpc(guid, name)
  local id = Collector.creatureId(guid)
  if not id then return "refused", "no_creature" end
  return Collector.record("npc", id, "name", name)
end

-- ── Disclosure, status, clear ──────────────────────────────────────────────

function Collector.disclose()
  if not db or not deps or readOnly or db.disclosed or not deps.enabled() then return false end
  deps.print("WFJ: this addon records English game text it has no data for (quest text, NPC dialogue with the ids "
    .. "of the NPCs who said it, item and spell descriptions, NPC names) in SavedVariables\\WoWForeverJapanese.lua, "
    .. "so it can be translated later. "
    .. "Your character's name is replaced; next to a line that names your class or race, the class and race are "
    .. "noted; no account, realm or location is stored (wording that depends on your "
    .. "character's gender is kept as the game shows it). Nothing leaves your disk unless you send it.")
  deps.print("WFJ: /wfj collector off to stop · /wfj collector send to send what it recorded.")
  db.disclosed = true
  return true
end

function Collector.formatBytes(n)
  if n >= 1024 * 1024 then return ("%.1f MB"):format(n / (1024 * 1024)) end
  return ("%.1f KB"):format(n / 1024)
end

function Collector.status()
  local n, unsent = 0, 0
  if db and type(db.entries) == "table" then
    for _ in pairs(db.entries) do n = n + 1 end
    unsent = Collector.unsentCount()
  end
  return {
    enabled = deps ~= nil and deps.enabled() or false,
    entries = n,
    unsent = unsent,
    bytes = db and tonumber(db.bytes) or 0,
    cap = Collector.CAP_BYTES,
    capped = db ~= nil and db.capped == true,
    readOnly = readOnly,
    errors = errors,
  }
end

-- "on · 12 entries[ (3 unsent)] · 3.4 KB of 4.0 MB[ · full][ · paused (file from a newer version)][ · N errors]"
function Collector.describe()
  local s = Collector.status()
  local unsent = s.entries > 0 and (" (%d unsent)"):format(s.unsent) or ""
  local out = ("%s · %d %s%s · %s of %s"):format(s.enabled and "on" or "off", s.entries,
    s.entries == 1 and "entry" or "entries", unsent, Collector.formatBytes(s.bytes), Collector.formatBytes(s.cap))
  if s.capped then out = out .. " · full" end
  if s.readOnly then out = out .. " · paused (file from a newer version)" end
  if s.errors > 0 then out = out .. (" · %d %s"):format(s.errors, s.errors == 1 and "error" or "errors") end
  return out
end

-- Empties the dump (the disclosure flag stays). A file from a newer version is never cleared. → count | nil
function Collector.clear()
  if not db or readOnly then return nil end
  local n = Collector.status().entries
  db.entries, db.builds, db.bytes, db.capped, db.sent = {}, {}, 0, false, {}
  cappedPrinted, memo, memoCount = false, {}, 0
  return n
end

-- ── Send ───────────────────────────────────────────────────────────────────

-- The entries a send carries, sorted by key: those not sent yet (a line replaced since it was sent counts as not
-- sent), or every entry with `all`. A line that ships in Japanese now is left out and counted: the collector recorded
-- it before a release translated it. → { { key = …, entry = … }, … }, the number left out, their { key, h }
function Collector.pending(all)
  local out, left, leftList = {}, 0, {}
  if not db or not deps or readOnly or type(db.entries) ~= "table" then return out, left, leftList end
  local sent = type(db.sent) == "table" and db.sent or {}
  for key, e in pairs(db.entries) do
    if all or sent[key] ~= e.h then
      local h1 = tonumber(e.h:sub(1, 8), 16)
      local ok, yes = pcall(shipped, e.t, e.i, e.f, e.e, h1, { e.h })
      if ok and yes then
        left = left + 1
        leftList[left] = { key = key, h = e.h }
      else
        out[#out + 1] = { key = key, entry = e }
      end
    end
  end
  table.sort(out, function(x, y) return x.key < y.key end)
  return out, left, leftList
end

-- How many entries a send would carry now: Collector.pending()'s length without building or sorting the list
-- (the minimap menu asks on every open). → number
function Collector.unsentCount()
  if not db or not deps or readOnly or type(db.entries) ~= "table" then return 0 end
  local sent = type(db.sent) == "table" and db.sent or {}
  local n = 0
  for key, e in pairs(db.entries) do
    if sent[key] ~= e.h then
      local ok, yes = pcall(shipped, e.t, e.i, e.f, e.e, tonumber(e.h:sub(1, 8), 16), { e.h })
      if not (ok and yes) then n = n + 1 end
    end
  end
  return n
end

-- Whether the saved file on disk holds this entry with this hash: it was in the file when the addon loaded it.
-- The client writes the file only at logout or /reload, so a line recorded since then is not in it yet.
function Collector.onDisk(key, h)
  return onDisk[key] ~= nil and onDisk[key] == h
end

-- Whether the file is from a newer version of the addon (recording paused, nothing to send).
function Collector.isReadOnly()
  return readOnly
end

function Collector.path()
  local beta = deps and type(deps.beta) == "function" and deps.beta() == true
  if not beta then return Collector.PATH end
  return (Collector.PATH:gsub("<client folder>", Collector.BETA_FOLDER))
end

-- The build string of a build index `b` (an entry's `b`), or nil.
function Collector.buildName(b)
  if not db or type(db.builds) ~= "table" or b == nil then return nil end
  local v = db.builds[b]
  return type(v) == "string" and v or nil
end

-- Notes that the player sent these entries (`list` = { { key, h }, … }, from a pack). Only an entry still stored with
-- that same hash is marked: one replaced since the pack was made stays unsent. A file from a newer version is never
-- written. → the number marked
function Collector.markSent(list)
  if not db or readOnly or type(list) ~= "table" then return 0 end
  if type(db.sent) ~= "table" then db.sent = {} end
  local n = 0
  for _, item in ipairs(list) do
    local e = db.entries[item.key]
    if e and e.h == item.h then
      if db.sent[item.key] == nil then db.bytes = db.bytes + Collector.sentSize(item.key) end
      db.sent[item.key] = item.h
      n = n + 1
    end
  end
  return n
end
