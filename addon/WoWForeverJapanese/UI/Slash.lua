-- UI/Slash.lua: /wfj and /wowforeverjapanese. The grammar is generic over the registry:
--   /wfj                      status: every setting and its value
--   /wfj on | off | toggle    the master switch (sugar for `enabled`)
--   /wfj <setting> [<value>]  read or set any setting; dotted ids may be split: /wfj area quests off
--   /wfj config [collector|about]   open the settings (a page)
--   /wfj debug                unresolved Compat candidates, surfaces whose init raised, state, font
--                             failures, memory, data counts, panel error
--   /wfj debug hash           run the shipped hash vectors through Normalize + Hash in-client
--   /wfj debug quest <id>     the shipped row for a quest (each field: status + the start of the Japanese)
--   /wfj debug item <id> | spell <id>
--   /wfj debug gossip         the gossip entry count, then each open gossip line: surface, record, key, status
--   /wfj debug book           the book entry count, then the open page's keys, the shipped one and its record
--   /wfj debug ui             the UI string index: shipped / indexed / hashed / mismatched / ambiguous / unresolved /
--                             unsupported (a template with more plural groups than the matcher takes)
--   /wfj debug objective      the objective index: shipped (objective / area rows) / indexed by
--                             fingerprint / ambiguous
--   /wfj debug ui scan        English still showing on visible frames: "hook?" = the dictionary knows it, "key?" = not
--   /wfj debug fonts          the refused-font retry: timer state, one pending widget, then a retry now
--   /wfj version              the addon, normalization and Lua versions
--   /wfj collector [on|off|status|path|clear]   the English collector; other words fall through to settings;
--                             clear asks for the same command again within 5 s (like the page's two clicks)
--   /wfj glosses [on|off]     readings.glosses · /wfj readings [on|off]  readings.enabled
--   /wfj togglekey [<key>|none]   the toggle binding the settings page's Set key / Unbind row writes
local _, WFJ = ...
local Slash = {}
WFJ.Slash = Slash

local S = WFJ.Settings

local function fmt(v)
  if v == true then return "on" elseif v == false then return "off" end
  return tostring(v)
end

local function say(line, ...)
  print(("WFJ: " .. line):format(...))
end

-- A command that asks to be typed again (replace a bound key, clear the collector) runs on the same line
-- within CONFIRM_SECONDS; any other command in between forgets it.
Slash.CONFIRM_SECONDS = 5
local armed, pending, current -- armed: the line the previous command asked for; current: this command's line

local function confirmed()
  if armed and armed.line == current and GetTime() - armed.at <= Slash.CONFIRM_SECONDS then return true end
  pending = { line = current, at = GetTime() }
  return false
end

-- The toggle binding's key as the client names it, or "not set".
local function toggleText()
  local KC = WFJ.KeyCapture
  if not KC then return "n/a" end
  local key = KC.toggleKey()
  return key and KC.keyText(key) or "not set"
end

function Slash.version()
  print(("WoW Forever Japanese %s (norm %s, %s)"):format(WFJ.VERSION, WFJ.NORM_VERSION, _VERSION))
end

function Slash.status()
  say("translation %s · hold %s for English · modifier %s", fmt(WFJ.State.enabled),
    WFJ.Modifier.display(S.get("modifier")), WFJ.State.modifierHeld and "held" or "up")
  for _, d in ipairs(S.list()) do
    if not d.hidden then print(("  %s = %s"):format(d.id, fmt(S.get(d.id)))) end
  end
  print(("  togglekey = %s"):format(toggleText())) -- a binding, not a setting, but set on the same page
  print("  /wfj on|off|toggle · /wfj <setting> <value> · /wfj readings|glosses [on|off] · /wfj togglekey [<key>|none]"
    .. " · /wfj config [collector|about] · /wfj collector · /wfj debug · /wfj version")
end

-- First 60 bytes of the Japanese, cut back to a UTF-8 boundary (never mid-sequence), one line.
local function short(ja)
  local s = ja:gsub("\n", " ")
  if #s <= 60 then return s end
  local cut = 60
  while cut > 1 and s:byte(cut + 1) and s:byte(cut + 1) >= 0x80 and s:byte(cut + 1) < 0xC0 do cut = cut - 1 end
  return s:sub(1, cut) .. "…"
end

local function debugRow(type_, idText)
  local id = tonumber(idText)
  if not id or id ~= math.floor(id) or id < 1 then return say("usage: /wfj debug %s <id>", type_) end
  local any = false
  for _, field in ipairs(WFJ.SLOTS[type_].fields) do
    local kind = type_ .. "." .. field  -- always field-qualified: spell has two fields
    local e = WFJ.Lookup.get(kind, id)
    if e then
      any = true
      print(("  %s.%s: %s (h1 %s) %s"):format(type_, field, WFJ.STATUS[e.status] or e.status,
        e.h1 and WFJ.Hash.hex8(e.h1) or "-", -- no h1: checked against another field
        e.variants and ("%d branch variants"):format(#e.variants) or short(e.ja))) -- a branch line
    else
      print(("  %s.%s: -"):format(type_, field))
    end
  end
  if not any then say("%s %s: not shipped", type_, idText) end
end

-- One line: the UI string index counts.
local function uiSummary()
  local index = WFJ.UIIndex
  if not index then return "not built" end
  local c = index.counts
  return ("shipped %d · indexed %d · hashed %d · mismatched %d · ambiguous %d · unresolved %d · unsupported %d"
    .. " · owned %d") -- keys that own their Japanese (UIStrings.OWN)
    :format(c.shipped, c.indexed, c.hashed, c.mismatched, c.ambiguous, c.unresolved, c.unsupported or 0, c.owned or 0)
end

local function debugUI()
  say("ui: %s", uiSummary())
  local index = WFJ.UIIndex
  if not index then return end
  for _, kind in ipairs({ "mismatched", "ambiguous", "unresolved", "unsupported" }) do
    local list = index.problems[kind] or {}
    if #list > 0 then
      local shown = {}
      for i = 1, math.min(10, #list) do shown[i] = list[i] end
      print(("  %s: %s%s"):format(kind, table.concat(shown, ", "), #list > 10 and (" … +" .. (#list - 10)) or ""))
    end
  end
end

-- One line: the objective index counts: rows shipped (objective and area rows, each counted), found
-- by fingerprint, and those two rows with one English and different Japanese leave unshown.
local function objectiveSummary()
  local index = WFJ.ObjectiveIndex
  if not index then return "not built" end
  local c = index.counts
  local by = c.byType or {}
  return ("shipped %d (objective %d · area %d) · indexed %d · ambiguous %d"):format(c.shipped, by.objective or 0,
    by.area or 0, c.indexed, c.ambiguous)
end

-- The shipped gossip count, then every live gossip-kind record: surface, record key, gossip key, status.
local function debugGossip()
  say("gossip entries: %d", WFJ.Data.count("gossip"))
  local any = false
  for _, surface in ipairs({ "gossip", "questframe.greeting" }) do
    local keys = {}
    for key, rec in pairs(WFJ.SurfaceState.records(surface)) do
      if rec.meta and rec.meta.kind == "gossip" then keys[#keys + 1] = key end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
      local rec = WFJ.SurfaceState.get(surface, key)
      local e = WFJ.Lookup.gossip(rec.meta.id)
      print(("  %s %s %s %s"):format(surface, key, tostring(rec.meta.id), e and (WFJ.STATUS[e.status] or e.status)
        or "none"))
      any = true
    end
  end
  if not any then print("  no gossip window open") end
end

-- The open book page: the shipped book count, the page's candidate keys, the one a translation is shipped
-- under, and its record.
local function debugBook()
  say("book entries: %d", WFJ.Data.count("book"))
  local info = WFJ.ItemText.inspect()
  if not info.open then return print("  no book open") end
  if info.creator then print("  a player's letter (never translated)") end
  print("  keys: " .. table.concat(info.keys, " "))
  local rec = info.record
  print(("  shipped: %s · record: %s"):format(info.shipped or "none",
    rec and (rec.applied ~= nil and "Japanese" or "English") or "none"))
end

local function debugHash()
  local V = WFJ.Data.vectors
  if not V then return say("no vectors shipped") end
  local ok, total = 0, #V.cases
  for _, c in ipairs(V.cases) do
    if WFJ.Hash.keyOf(c.raw, c.player) == c.key then
      ok = ok + 1
    else
      say("hash vector %s FAILED", c.id)
    end
  end
  say("hash vectors: %d/%d ok (norm %s)", ok, total, V.norm)
end

local function debugFonts()
  local r = WFJ.fontRetry
  if r then
    say("fonts: retry %s · %d tries · %d left at the last try · %.0fs since PLAYER_ENTERING_WORLD · timer %s",
      r.running and "running" or "stopped", r.tries, r.left, GetTime() - r.at, r.timer and "yes" or "missing")
  else
    say("fonts: no retry started (PLAYER_ENTERING_WORLD not seen)")
  end
  local rec = WFJ.Render.pendingFontSample()
  if rec then
    local path, size, flags = rec.fs:GetFont()
    local shown = rec.fs.IsVisible and rec.fs:IsVisible()
    say("fonts: pending %s.%s now %s %s %q · visible %s", tostring(rec.surface), tostring(rec.key), tostring(path),
      tostring(size), tostring(flags), tostring(shown))
  end
  local before = WFJ.Render.pendingFonts()
  local after = WFJ.Render.retryFonts()
  say("fonts: records pending %d → %d after a retry now · own widgets pending %d", before, after,
    WFJ.Font.retryPending())
end

function Slash.debug(sub, arg)
  if sub == "fonts" then return debugFonts() end
  if sub == "hash" then return debugHash() end
  if sub == "quest" or sub == "item" or sub == "spell" then return debugRow(sub, arg) end
  if sub == "gossip" then return debugGossip() end
  if sub == "book" then return debugBook() end
  if sub == "ui" and arg and arg:lower() == "scan" then return WFJ.Scan.run(print) end
  if sub == "ui" then return debugUI() end
  if sub == "objective" then return say("objectives: %s", objectiveSummary()) end
  if sub ~= nil then return print(("WFJ: unknown command 'debug %s' (try /wfj)"):format(sub)) end
  local unresolved = WFJ.Compat.unresolved()
  say("unresolved widgets: %s", #unresolved == 0 and "none" or table.concat(unresolved, ", "))
  -- The surfaces whose init raised. Each one cost only itself; the rest of the addon loaded around it.
  local initErrors = WFJ.initErrors or {}
  local failed = {}
  for i, e in ipairs(initErrors) do failed[i] = ("%s: %s"):format(e.surface, e.err) end
  say("surface errors: %s", #failed == 0 and "none" or table.concat(failed, " · "))
  local areas = {}
  for _, a in ipairs(WFJ.AREAS) do areas[#areas + 1] = a .. "=" .. fmt(WFJ.State.areaEnabled(a)) end
  say("enabled=%s held=%s %s", fmt(WFJ.State.enabled), fmt(WFJ.State.modifierHeld), table.concat(areas, " "))
  local fails = {}
  for surface, f in pairs(WFJ.Render.fontFailureSurfaces) do fails[#fails + 1] = { surface = surface, f = f } end
  table.sort(fails, function(a, b)
    if a.f.n ~= b.f.n then return a.f.n > b.f.n end
    return a.surface < b.surface
  end)
  for i, x in ipairs(fails) do
    fails[i] = ("%s ×%d (%s size=%s flags=%q)"):format(x.surface, x.f.n, tostring(x.f.key), tostring(x.f.size),
      tostring(x.f.flags))
  end
  say("font failures: %d (%d pending)%s", WFJ.Render.fontFailures, WFJ.Render.pendingFonts(),
    #fails > 0 and (" · " .. table.concat(fails, " · ")) or "")
  local RV = WFJ.ReadingView -- the word-reading box
  if RV then
    say("readings: %d quests / greetings loaded · %s · %d attached · %d spans refused%s · %d errors",
      WFJ.Data.count("reading"), RV.enabled and "on" or "off", RV.attached, RV.refused,
      RV.refusedAt and (" (first: " .. RV.refusedAt .. ")") or "", WFJ.Render.readingErrors or 0)
    say("glosses: %d meanings loaded · %s", WFJ.Data.count("gloss"), RV.glossesOn and "on" or "off")
  end
  local nUnknown, unknownList = WFJ.Placeholders.unknownTokens()
  local listed = nUnknown > 0 and (" (" .. table.concat(unknownList, " ") .. ")") or ""
  say("placeholders: %d unknown tokens seen%s", nUnknown, listed)
  local got, want, api, path, auras = WFJ.Tooltip.resolved()
  say("tooltip frames: %d/%d · hook path: %s · spell description API: %s · aura hooks: %d · aura errors: %d",
    got, want, tostring(path), api and "present" or "absent (positional rule)", auras or 0,
    WFJ.Tooltip.auraErrors or 0)
  local sp = WFJ.Tooltip.secretPasses
  say("secret tooltips: %d written back · skipped: %d nothing to write · %d another spell · %d line count · "
    .. "%d another owner · %d English wanted", sp.reapplied, sp.nothing, sp.other, sp.lines, sp.owner, sp.off)
  local kb = WFJ.Compat.memoryKB()
  say("memory: %s", kb and ("%.1f MB"):format(kb / 1024) or "n/a")
  local c = WFJ.Data.counts
  say("data: quests %d · items %d · spells %d · gossip %d · ui %d", c.quest, c.item, c.spell, c.gossip, c.ui)
  say("ui: %s", uiSummary())
  say("objectives: %s", objectiveSummary())
  say("collector: %s", WFJ.Collector.describe())
  local M = WFJ.Modifier
  say("modifier: %s (%s%s)", S.get("modifier"), M.class(S.get("modifier")),
    M.bindingKey() and (" · override " .. WFJ.RevealBinding.state) or "")
  say("addon list button: %s", WFJ.AddonListButton.installed and "installed" or "absent")
  if WFJ.Options.buildError then say("settings panel failed to build: %s", WFJ.Options.buildError) end
end

local COLLECTOR_VERBS = { on = true, off = true, status = true, path = true, clear = true }

-- /wfj collector … → true when handled; any other second word is left to the registry grammar.
function Slash.collector(sub)
  local C = WFJ.Collector
  if sub ~= nil and not COLLECTOR_VERBS[sub] then return false end
  if sub == "on" or sub == "off" then
    S.set("collector.enabled", sub)
  elseif sub == "path" then
    local st = C.status()
    say("collected English is saved when you log out or /reload, in:")
    print("  " .. C.PATH)
    say("%d %s · %s. Attach the file (zipped) to an issue: %s", st.entries, st.entries == 1 and "entry" or "entries",
      C.formatBytes(st.bytes), C.ISSUE_URL)
    return true
  elseif sub == "clear" then
    local st = C.status() -- nothing to lose (empty, or a newer version's file that is never cleared): no ask
    if not st.readOnly and st.entries > 0 and not confirmed() then
      local n = st.entries
      say("type /wfj collector clear again within %d seconds to clear %d %s", Slash.CONFIRM_SECONDS, n,
        n == 1 and "entry" or "entries")
      return true
    end
    local n = C.clear()
    if n == nil then
      say("collector file is from a newer version; not cleared")
    else
      say("collector cleared (%d)", n)
    end
    return true
  end
  say("collector %s", C.describe())
  return true
end

-- /wfj togglekey [<key> | none]: the settings page's toggle-key row by slash, with its refusals, never in
-- combat, never the modifier's key, and a key bound to another action only when the command is repeated (Replace).
function Slash.togglekey(value, extra)
  local KC = WFJ.KeyCapture
  if value == nil then return say("togglekey = %s", toggleText()) end
  if extra ~= nil then return say("togglekey: one key, with - between its parts (ctrl-j)") end
  local combat = KC.inCombat() -- through Compat, as the page reads it; nil: the client cannot say, so never write
  if combat == true then return say("togglekey: key bindings cannot change in combat") end
  if combat == nil then return say("togglekey: key bindings are not available on this client") end
  if value:lower() == "none" then
    if not KC.clearToggle() and KC.toggleKey() then return say("togglekey: %s was not unbound", toggleText()) end
    return say("togglekey = %s", toggleText())
  end
  local chord, why = KC.parseChord(value)
  if not chord then return say("togglekey: %s", why) end
  if S.get("modifier"):upper() == chord then
    return say("togglekey: %s is the key you hold for English (/wfj modifier)", KC.keyText(chord))
  end
  local action = KC.conflict(chord, KC.TOGGLE)
  if action and not confirmed() then
    return say('%s is used for "%s"; type the same command again within %d seconds to replace it',
      KC.keyText(chord), action, Slash.CONFIRM_SECONDS)
  end
  if not KC.setToggle(chord) then return say("togglekey: %s was not bound", KC.keyText(chord)) end
  say("togglekey = %s", toggleText())
end

local BOOLEAN_WORDS = { on = true, off = true, ["true"] = true, ["false"] = true, ["1"] = true, ["0"] = true }

-- Resolves `words` against the registry: "<id> <value>" or "<group> <name> <value>". → id, value | nil
local function settingFromWords(words)
  local id = S.find(words[1])
  if id then return id, words[2] end
  if words[2] then
    id = S.find(words[1] .. "." .. words[2])
    if id then return id, words[3] end
  end
  return nil
end

function Slash.handle(msg)
  local words = {}
  for w in (msg or ""):gmatch("%S+") do words[#words + 1] = w end
  armed, pending, current = pending, nil, table.concat(words, " "):lower()
  local verb = words[1]
  if verb == nil then return Slash.status() end
  local lower = verb:lower()

  if lower == "version" then return Slash.version() end
  if lower == "on" or lower == "off" then
    S.set("enabled", lower)
    return say("translation %s", lower)
  end
  if lower == "toggle" then
    S.set("enabled", not S.get("enabled"))
    return say("translation %s", fmt(S.get("enabled")))
  end
  if lower == "config" then
    if not WFJ.Compat.openOptions(words[2] and words[2]:lower()) then
      say("settings panel not available on this client; use /wfj <setting> <value>")
    end
    return
  end
  if lower == "fix" then -- the fix window (report a line)
    local ok = WFJ.FixWindow and pcall(WFJ.FixWindow.open)
    if not ok then say("the fix window is not available on this client") end
    return
  end
  if lower == "debug" then return Slash.debug(words[2] and words[2]:lower(), words[3]) end
  if lower == "glosses" then -- the word popup's meanings (setting readings.glosses)
    if words[2] then
      local ok, err = S.set("readings.glosses", words[2])
      if not ok then return say("glosses: %s", err) end
    end
    return say("glosses %s · %d meanings loaded", fmt(S.get("readings.glosses")), WFJ.Data.count("gloss"))
  end
  if lower == "readings" and (words[2] == nil or BOOLEAN_WORDS[words[2]:lower()]) then -- readings.enabled
    if words[2] then
      local ok, err = S.set("readings.enabled", words[2])
      if not ok then return say("readings: %s", err) end
    end
    return say("readings %s", fmt(S.get("readings.enabled")))
  end
  if lower == "togglekey" then return Slash.togglekey(words[2], words[3]) end
  if lower == "collector" and Slash.collector(words[2] and words[2]:lower()) then return end

  local id, value = settingFromWords(words)
  if id then
    if value == nil then return say("%s = %s", id, fmt(S.get(id))) end
    local ok, err = S.set(id, value)
    if ok and id == "modifier" then
      local key = WFJ.Modifier.bindingKey()
      local action = key and WFJ.KeyCapture.conflict(key, WFJ.KeyCapture.REVEAL)
      if key and WFJ.RevealBinding.state == "queued" then
        say("modifier = %s: takes effect after combat", fmt(S.get(id)))
      else
        say("%s = %s", id, fmt(S.get(id)))
      end
      if action then say("%s was used for \"%s\"; while the addon is loaded it shows English instead", key, action) end
      return
    end
    if ok then return say("%s = %s", id, fmt(S.get(id))) end
    return say("%s: %s", id, err)
  end

  if lower == "readings" then return say("readings: expected on|off") end -- a known verb, a bad word
  print(("WFJ: unknown command '%s' (try /wfj)"):format(verb))
end

function Slash.register()
  SLASH_WFJ1 = "/wfj"
  SLASH_WFJ2 = "/wowforeverjapanese"
  SlashCmdList["WFJ"] = function(msg) Slash.handle(msg) end
end
