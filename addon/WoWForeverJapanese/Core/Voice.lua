-- Core/Voice.lua: the voice pack's registry and the decision whether a shown line is voiced (ADR-061). Pure: no
-- frames, no sound API; UI/VoicePlayer plays what `decide` returns.
-- The audio lives in a separate addon, WoWForeverJapanese_Voice, which hands its table to the global
-- WoWForeverJapanese_RegisterVoice (Main.lua) when its Register.lua loads. Each entry is keyed like the Japanese it
-- speaks ("<questID>-<field>", or "g-<gossip key>") and carries the hash of the Japanese it was made from: a line
-- whose shipped Japanese changed since stays silent, never voices other words.
local _, WFJ = ...
local Voice = {}
WFJ.Voice = Voice

Voice.FOLDER = "WoWForeverJapanese_Voice" -- the pack's addon folder; every file is read from its Sound folder
Voice.FORMAT = 1 -- the Register.lua table shape this file reads

-- The lines a pack may voice: surface → record key → the setting that turns that kind off. Objectives, titles and
-- option rows are never voiced.
Voice.KINDS = {
  ["questframe.detail"] = { description = "voice.offer" },
  ["questframe.progress"] = { progress = "voice.progress" },
  ["questframe.reward"] = { completion = "voice.turnin" },
  ["questframe.greeting"] = { greeting = "voice.greeting" },
  gossip = { greeting = "voice.greeting" },
}

local lines -- pack key → { file, jaHash, seconds }; nil until a pack registers
local deps = {}

local function zero()
  return { registered = 0, invalid = 0, matched = 0, missing = 0, stale = 0 }
end
Voice.counts = zero()

-- deps: lookup(kind, id) → { ja } | nil (the shipped Japanese, tokens unfilled), hash(text) → 16 hex,
-- setting(id) → value, revealed() → bool (English showing: the reveal key held), enabled() → bool (translation on)
function Voice.init(d)
  deps = d or {}
end

local function validEntry(e)
  return type(e) == "table" and type(e[1]) == "string" and e[1]:match("^[%w%-]+%.mp3$") ~= nil
    and type(e[2]) == "string" and e[2]:match("^%x+$") ~= nil and #e[2] == 16
    and (e[3] == nil or type(e[3]) == "number")
end

-- The pack's table → registered, invalid. A second pack replaces the first. Entries that do not match the shape are
-- dropped and counted, never guessed at: a file name outside the pack's Sound folder would play another addon's file.
function Voice.register(tbl)
  Voice.counts = zero()
  if type(tbl) ~= "table" or tbl.format ~= Voice.FORMAT or tbl.folder ~= Voice.FOLDER or type(tbl.lines) ~= "table"
  then
    Voice.counts.invalid = 1
    return 0, 1
  end
  local kept, n, bad = {}, 0, 0
  for key, e in pairs(tbl.lines) do
    if type(key) == "string" and validEntry(e) then
      kept[key] = { file = e[1], jaHash = e[2]:lower(), seconds = e[3] }
      n = n + 1
    else
      bad = bad + 1
    end
  end
  lines = kept
  Voice.counts.registered, Voice.counts.invalid = n, bad
  return n, bad
end

function Voice.hasPack()
  return lines ~= nil
end

-- The pack key of a rendered line (its Translator kind and id): a quest field by quest id, gossip by its key.
function Voice.packKey(kind, id)
  if kind == "gossip" and type(id) == "string" then return "g-" .. id end
  local field = type(kind) == "string" and kind:match("^quest%.(%a+)$")
  if field and type(id) == "number" then return ("%d-%s"):format(id, field) end
  return nil
end

local function setting(id)
  return type(deps.setting) == "function" and deps.setting(id)
end

-- A line just shown in Japanese on `surface` under record key `recKey`, rendered as (kind, id).
-- → the file's path and its length in seconds, or nil and why ("kind" · "off" · "english" · "nopack" · "missing" ·
-- "stale" · "notext")
function Voice.decide(surface, recKey, kind, id)
  local byKey = Voice.KINDS[surface]
  local kindSetting = byKey and byKey[recKey]
  if not kindSetting then return nil, "kind" end
  if not setting("voice.enabled") or not setting(kindSetting) then return nil, "off" end
  if (type(deps.enabled) == "function" and not deps.enabled())
    or (type(deps.revealed) == "function" and deps.revealed()) then
    return nil, "english"
  end
  if not lines then return nil, "nopack" end
  local key = Voice.packKey(kind, id)
  local entry = key and lines[key]
  if not entry then
    Voice.counts.missing = Voice.counts.missing + 1
    return nil, "missing"
  end
  local shipped = type(deps.lookup) == "function" and deps.lookup(kind, id) or nil
  if type(shipped) ~= "table" or type(shipped.ja) ~= "string" then return nil, "notext" end
  if type(deps.hash) ~= "function" or deps.hash(shipped.ja) ~= entry.jaHash then
    Voice.counts.stale = Voice.counts.stale + 1
    return nil, "stale"
  end
  Voice.counts.matched = Voice.counts.matched + 1
  return "Interface\\AddOns\\" .. Voice.FOLDER .. "\\Sound\\" .. entry.file, entry.seconds
end
