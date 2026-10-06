-- Core/Voice.lua: the voice packs' registry and the decision whether a shown line is voiced (ADR-061, ADR-062).
-- Pure: no frames, no sound API; UI/VoicePlayer plays what `decide` returns.
-- The audio lives in separate addons whose folders start with WoWForeverJapanese_Voice; each hands its table to the
-- global WoWForeverJapanese_RegisterVoice (Main.lua) when its Register.lua loads, and the packs merge. Each entry is
-- keyed like the Japanese it speaks ("<questID>-<field>", "g-<gossip key>", "b-<book page key>") and carries the
-- hash of the Japanese it was made from: a line whose shipped Japanese changed since stays silent, never voices
-- other words. A line several differently cast creatures say has a file per voice; the speaker on screen picks it.
local _, WFJ = ...
local Voice = {}
WFJ.Voice = Voice

Voice.FOLDER = "WoWForeverJapanese_Voice" -- every pack's addon folder starts with this; files are read from its Sound folder
Voice.FORMATS = { [1] = true, [2] = true } -- the Register.lua table shapes this file reads (ADR-061, ADR-062)

-- The lines a pack may voice: surface → record key → the setting that turns that kind off. Objectives, titles and
-- option rows are never voiced.
Voice.KINDS = {
  ["questframe.detail"] = { description = "voice.offer" },
  ["questframe.progress"] = { progress = "voice.progress" },
  ["questframe.reward"] = { completion = "voice.turnin" },
  ["questframe.greeting"] = { greeting = "voice.greeting" },
  gossip = { greeting = "voice.greeting" },
  itemtext = { page = "voice.books" },
}

local lines -- pack key → { file, jaHash, seconds, folder, v = { [voice] = { file, seconds } } }; nil until a pack registers
local creatures = {} -- creature id → voice id, or { male voice, female voice } (the speakers of lines with variants)
local packs = {} -- pack folder → the number of its lines registered
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

local function validFile(f)
  return type(f) == "string" and f:match("^[%w%-_]+%.mp3$") ~= nil
end

local function validEntry(e)
  if not (type(e) == "table" and validFile(e[1]) and type(e[2]) == "string" and e[2]:match("^%x+$") ~= nil
    and #e[2] == 16 and (e[3] == nil or type(e[3]) == "number")) then
    return false
  end
  if e.v == nil then return true end
  if type(e.v) ~= "table" then return false end
  for vid, f in pairs(e.v) do
    if type(vid) ~= "string" or type(f) ~= "table" or not validFile(f[1]) then return false end
  end
  return true
end

local function validVoice(v)
  if type(v) == "string" then return true end
  return type(v) == "table" and type(v[1]) == "string" and type(v[2]) == "string"
end

local function recount()
  local n = 0
  for _ in pairs(lines or {}) do n = n + 1 end
  Voice.counts.registered = n
end

-- A pack's table → registered, invalid. Packs merge: each line remembers the folder it came from, and a pack that
-- registers again replaces only its own lines. Entries that do not match the shape are dropped and counted, never
-- guessed at: a file name outside the pack's Sound folder would play another addon's file.
function Voice.register(tbl)
  if type(tbl) ~= "table" or not Voice.FORMATS[tbl.format] or type(tbl.folder) ~= "string"
    or tbl.folder:sub(1, #Voice.FOLDER) ~= Voice.FOLDER or not tbl.folder:match("^[%w_]+$")
    or type(tbl.lines) ~= "table" then
    Voice.counts.invalid = Voice.counts.invalid + 1
    return 0, 1
  end
  lines = lines or {}
  for key, e in pairs(lines) do
    if e.folder == tbl.folder then lines[key] = nil end
  end
  local n, bad = 0, 0
  for key, e in pairs(tbl.lines) do
    if type(key) == "string" and validEntry(e) then
      local v
      if e.v then
        v = {}
        for vid, f in pairs(e.v) do v[vid] = { file = f[1], seconds = f[2] } end
      end
      lines[key] = { file = e[1], jaHash = e[2]:lower(), seconds = e[3], folder = tbl.folder, v = v }
      n = n + 1
    else
      bad = bad + 1
    end
  end
  for c, v in pairs(type(tbl.creatures) == "table" and tbl.creatures or {}) do
    if type(c) == "number" and validVoice(v) then creatures[c] = v else bad = bad + 1 end
  end
  packs[tbl.folder] = n
  Voice.counts.invalid = Voice.counts.invalid + bad
  recount()
  return n, bad
end

-- → { [folder] = lines } of every registered pack (for the settings page and /wfj debug)
function Voice.packs()
  return packs
end

function Voice.hasPack()
  return lines ~= nil
end

-- The pack key of a rendered line (its Translator kind and id): a quest field by quest id, gossip by its key.
function Voice.packKey(kind, id)
  if kind == "gossip" and type(id) == "string" then return "g-" .. id end
  if kind == "book" and type(id) == "string" then return "b-" .. id end
  local field = type(kind) == "string" and kind:match("^quest%.(%a+)$")
  if field and type(id) == "number" then return ("%d-%s"):format(id, field) end
  return nil
end

local function setting(id)
  return type(deps.setting) == "function" and deps.setting(id)
end

-- The file of a line for the speaker on screen: its voice's own file when the line has one for it, else the line's
-- main file. `who`: { creature = id, sex = UnitSex value (3 female) } or nil.
local function fileFor(entry, who)
  local voice = who and creatures[who.creature]
  if type(voice) == "table" then voice = who.sex == 3 and voice[2] or voice[1] end
  local own = voice and entry.v and entry.v[voice]
  if own then return own.file, own.seconds end
  return entry.file, entry.seconds
end

-- A line just shown in Japanese on `surface` under record key `recKey`, rendered as (kind, id), said by `who`.
-- → the file's path and its length in seconds, or nil and why ("kind" · "off" · "english" · "nopack" · "missing" ·
-- "stale" · "notext")
function Voice.decide(surface, recKey, kind, id, who)
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
  local file, seconds = fileFor(entry, who)
  return "Interface\\AddOns\\" .. entry.folder .. "\\Sound\\" .. file, seconds
end
