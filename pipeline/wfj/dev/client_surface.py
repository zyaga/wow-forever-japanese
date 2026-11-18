"""What the addon depends on in the client, and what a client answers for it.

    python -m wfj.dev.client_surface build --addon <addon dir> --out surface-manifest.json
    python -m wfj.dev.client_surface probe --manifest surface-manifest.json --out <dir>/WFJScanProbe.lua
    python -m wfj.dev.client_surface report --manifest surface-manifest.json --probe <saved WFJScan.lua> \
        [--source <dir of extracted client UI> [--game standard]] \
        [--reference <the other client's extract> --reference-game camelot] --out verdicts.json

`build` reads the addon's Lua and lists every client name it needs, so the list cannot go stale by hand:

- `Compat.declare(SURFACE, key, { "A", "B" })`: the candidate globals of a surface; a candidate that is a
  file-local table of string literals (`for _, name in ipairs(TAB_WRITERS)`) is expanded from that table
- `Compat.resolve("Name")`: a global read outside declare
- `hooksecurefunc("Name", fn)`: a client function post-hooked by name
- `:HookScript("OnX", fn)`: the widget script types the addon hooks
- `GetTrainerGreetingText(…)`, `C_AddOns.IsAddOnLoaded(…)`: a client API the addon calls directly, which no
  `Compat.declare` covers (`api` kind). Generated data shards are skipped: their Japanese contains words that
  look like calls.

A name the parser cannot resolve statically (built by concatenation, or read from a table it cannot see) is
kept as `dynamic` with the expression text, never dropped, because a missing entry is a missed difference.

`probe --out` writes the probe as one Lua file that the scan dev addon (WFJScan) loads in the client. It
answers every name at login, and sweeps again whenever a load-on-demand addon loads and on `/wfjprobe
<surface>` (the player marking a surface as asked with its window open, which is the only evidence
separating "the client removed it" from "nobody ever opened it"), so a surface whose window was opened is
answered too, and the addons that loaded are recorded. It saves to the scan addon's SavedVariables, under
`WFJScanDB.probe` only, stamped with the manifest it was built from so answers from another manifest are
dropped rather than merged.
`report` reads that file (refusing one that does not cover the manifest) and merges it with the extracted
client source (`--source`) into one verdict per entry: `works`, `names only` (gone from the client, still in
its source), `rework` (gone from both) or `unknown` (a dynamic name, a `method` hook, or a load-on-demand
surface whose addon never loaded).

A surface is the file stem, and not every file owns a window. `Core/` modules, `Main.lua` and the UI
modules in WINDOWLESS_UI act on key bindings, slash commands or other surfaces' widgets, so there is no
window to open and `/wfjprobe <surface>` can never be run for them fairly. Their entries carry
`windowless: true` and skip the asked-window rule: the login sweep is their evidence, so an absent name
there reads `rework` / `names only`.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from collections.abc import Iterable
from pathlib import Path
from typing import Any

from wfj.dev import client_addons

SKIP_DIRS = ("Data",)  # generated shards: translated text, not code
# UI modules with no window of their own (key capture, the reveal binding, slash commands, the
# load-on-demand wait, and the render / label / font helpers every window surface shares). With Core/ and the
# addon root they are the window-less surfaces: the asked-window rule does not apply to them.
WINDOWLESS_UI = frozenset({
    "keycapture", "revealbinding", "slash", "loadondemand", "render", "labels", "font",
})


def windowless(rel: str) -> bool:
    """True for a file (addon-relative, posix) whose surface has no window: outside UI/, or a
    WINDOWLESS_UI module."""
    parts = rel.split("/")
    return parts[0] != "UI" or Path(rel).stem.lower() in WINDOWLESS_UI
# An `api` candidate is only a client API when it looks like one. Everything else a bare `Name(` match picks
# up (widget methods the addon calls on its own objects, event names, the addon's own constants) is
# recorded with `suspect: true` and left out of the headline counts, never dropped.
API_PREFIXES = ("Get", "Is", "Set", "Select", "Unit", "Has", "C_", "Create", "Toggle", "Can", "Add", "Send")
WIDGET_METHODS = frozenset({
    "Show", "Hide", "SetScript", "HookScript", "SetText", "SetHeight", "SetWidth", "SetPoint", "AddLine",
    "AppendText", "SetFormattedText", "GetTextWidth", "UpdateText", "UpdateTabs", "UpdatePages", "SetFont",
    "SetShown", "SetSize", "SetAlpha", "SetParent", "ClearAllPoints", "SetOwner", "SetValue",
})


def suspect_api(name: str) -> bool:
    """True when an `api` match is probably not a client API: an UPPER_SNAKE event or constant, a widget
    method the addon calls on its own frames, or a word that simply reads like a call."""
    if name.isupper() or (name.upper() == name and "_" in name):
        return True
    if name.split(".")[-1] in WIDGET_METHODS:
        return True
    return not name.startswith(API_PREFIXES)

# a dotted literal is still a literal: Compat.resolve("Enum.TooltipDataType") names one thing
_RESOLVE = re.compile(r"""Compat\.resolve\(\s*"([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)"\s*\)""")
_HOOKSECURE = re.compile(r"""hooksecurefunc\(\s*"([A-Za-z_][A-Za-z0-9_]*)"\s*,""")
# `hooksecurefunc(frame, "Method", fn)`: the mixin-method form Forever's newer surfaces need
_HOOK_OBJECT = re.compile(
    r"""hooksecurefunc\(\s*[A-Za-z_][\w.\[\]"']*\s*,\s*"([A-Za-z_][A-Za-z0-9_]*)"\s*,"""
)
# `:HookScript(script, …)` with a variable script type
_HOOKSCRIPT_VAR = re.compile(r"""HookScript\(\s*([a-z][A-Za-z0-9_]*)\s*,""")
# a declare anywhere, including across lines, with either a literal list or an identifier as candidates
_DECLARE_ANY = re.compile(r"Compat\.declare\(\s*([^,]+),\s*([^,]+),\s*(\{[^}]*\}|[A-Za-z_][\w.\[\]]*)\s*\)",
                          re.S)
_HOOKSCRIPT = re.compile(r"""HookScript\(\s*"([A-Za-z_][A-Za-z0-9_]*)"\s*""")
_STRING = re.compile(r'"([^"\\]*)"')
_IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
# a call to a name the addon does not define itself: `GetBuildInfo()`, `C_AddOns.IsAddOnLoaded()`
_CALL = re.compile(r"(?<![\w.:\"'])((?:C_[A-Za-z]+\.)?[A-Z][A-Za-z0-9_]{2,})\s*\(")
_DEFINED = re.compile(r"(?:function\s+([A-Za-z_][\w.:]*)|local\s+([A-Za-z_]\w*)\s*=)")
_LOCAL_TABLE = re.compile(r"^local\s+([A-Z][A-Z0-9_]*)\s*=\s*\{(.*?)\n?\}", re.M | re.S)
# `for _, name in ipairs(TAB_WRITERS) do … { name }`: the loop names the table the candidate comes from
# `Blizzard_TrainerUI` and friends load on demand: their frames do not exist until the window is opened, so a
# probe at login would report them missing.
_LOD_ADDON = re.compile(r'"(Blizzard_[A-Za-z]+)"')
LOD_SKIP = frozenset({"Blizzard_FrameXML", "Blizzard_UIParent", "Blizzard_UIPanels", "Blizzard_Menu"})
_LOOP = re.compile(r"for\s+([\w,\s]+?)\s+in\s+i?pairs\(([A-Za-z_][A-Za-z0-9_]*)\)")


_BLOCK_COMMENT = re.compile(r"--\[\[.*?\]\]", re.S)
_LINE_COMMENT = re.compile(r"--[^\n]*")


def code_only(text: str) -> str:
    """The file with comments blanked out, line count and column offsets preserved, so a commented-out call
    is never read as live code. String contents are kept: a declare's candidates live in
    them."""
    def blank(m: re.Match[str]) -> str:
        return re.sub(r"[^\n]", " ", m.group(0))
    return _LINE_COMMENT.sub(blank, _BLOCK_COMMENT.sub(blank, text))


def local_tables(text: str) -> dict[str, list[str]]:
    """File-local upper-case tables → their string literals (`local TAB_WRITERS = { "A", "B" }`, and
    `{ key = "Name" }`), so a declare that loops over one can be expanded."""
    out = {m.group(1): _STRING.findall(m.group(2)) for m in _LOCAL_TABLE.finditer(text)}
    # a table of tables (`local CANDIDATES = { frame = { "BankFrame" }, … }`) declares its inner names too
    for m in re.finditer(r"^local\s+([A-Z][A-Z0-9_]*)\s*=\s*\{(.*?)\n\}", text, re.M | re.S):
        out.setdefault(m.group(1), [])
        out[m.group(1)] = list(dict.fromkeys(out[m.group(1)] + _STRING.findall(m.group(2))))
    return out


def _candidates(raw: str, tables: dict[str, list[str]], line: str = "") -> tuple[list[str], str | None]:
    """The names in a declare's `{ … }`: string literals as they are; a bare identifier expanded from the
    file-local table it names, or from the table the same line loops over (`for _, name in ipairs(TABS) do
    Compat.declare(S, name, { name })`); else nothing and the expression kept as the dynamic reason. A
    concatenation is always dynamic; its literal half is only part of the real name."""
    raw = raw.strip()
    if raw.startswith("{") and raw.endswith("}"):
        raw = raw[1:-1]
    if ".." in raw:
        return [], raw.strip()
    literals = _STRING.findall(raw)
    if literals:
        return literals, None
    ident = raw.strip()
    if _IDENT.match(ident):
        if ident in tables:
            return tables[ident], None
        loop = _LOOP.search(line)
        if loop and ident in [v.strip() for v in loop.group(1).split(",")] and loop.group(2) in tables:
            return tables[loop.group(2)], None
    return [], ident or "<empty>"


def addon_defined(addon: Path) -> set[str]:
    """Every name the addon defines itself (functions, locals), so a call to one is not a client API."""
    out: set[str] = set()
    for path in addon.rglob("*.lua"):
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        for fn, local in _DEFINED.findall(path.read_text(encoding="utf-8", errors="replace")):
            name = fn or local
            out.add(name.split(".")[-1].split(":")[-1])
    return out


def lod_addons(text: str) -> list[str]:
    """The load-on-demand Blizzard addons a surface names, so its entries can be read as `unknown` until that
    addon is loaded rather than as removed."""
    return sorted({a for a in _LOD_ADDON.findall(text) if a not in LOD_SKIP})


def scan_file(path: Path, addon: Path, defined: set[str] | None = None) -> list[dict[str, Any]]:
    raw = path.read_text(encoding="utf-8", errors="replace")
    text = code_only(raw)
    tables = local_tables(text)
    rel = path.relative_to(addon).as_posix()
    surface = path.stem.lower()
    lod = lod_addons(text)
    out = _declare_rows(text, tables, surface, rel)
    for line_no, line in enumerate(text.splitlines(), 1):
        out += _hook_rows(line, line_no, tables, surface, rel)
        out += _call_rows(line, line_no, defined, surface, rel)
    if lod:
        for entry in out:
            entry["lod"] = lod
    if windowless(rel):
        for entry in out:
            entry["windowless"] = True
    return out


def _declare_rows(text: str, tables: dict[str, list[str]], surface: str, rel: str) -> list[dict[str, Any]]:
    """The `Compat.declare` rows of one file."""
    out: list[dict[str, Any]] = []
    # declares first, over the whole file: a call may span lines, and its candidates may be an identifier
    for m in _DECLARE_ANY.finditer(text):
        line_no = text[: m.start()].count("\n") + 1
        line_start = text.rfind("\n", 0, m.start()) + 1
        line_end = text.find("\n", m.end())
        line = text[line_start: line_end if line_end > 0 else len(text)]
        key = (_STRING.findall(m.group(2)) or [m.group(2).strip()])[0]
        names, dynamic = _candidates(m.group(3), tables, line)
        for name in names:
            out.append({"kind": "global", "name": name, "surface": surface, "key": key,
                        "file": rel, "line": line_no})
        if dynamic:
            out.append({"kind": "global", "name": None, "dynamic": dynamic, "surface": surface,
                        "key": key, "file": rel, "line": line_no})
    # every `Compat.declare(` must leave a row: one the pattern cannot read becomes a dynamic entry, so a
    # shape the parser has never seen is reported instead of vanishing
    unread = len(re.findall(r"Compat\.declare\(", text)) - len(_DECLARE_ANY.findall(text))
    for _ in range(max(0, unread)):
        out.append({"kind": "global", "name": None, "dynamic": "a Compat.declare the parser cannot read",
                    "surface": surface, "key": "declare", "file": rel, "line": 0})
    return out


def _hook_rows(
    line: str, line_no: int, tables: dict[str, list[str]], surface: str, rel: str
) -> list[dict[str, Any]]:
    """The hook and `Compat.resolve` rows of one line, in the order the scan has always listed them."""
    out: list[dict[str, Any]] = []
    for m in _HOOK_OBJECT.finditer(line):
        out.append({"kind": "method", "name": m.group(1), "surface": surface,
                    "key": "hooksecurefunc", "file": rel, "line": line_no})
    for m in _HOOKSCRIPT_VAR.finditer(line):
        var = m.group(1)
        loop = _LOOP.search(line)
        expanded = tables.get(loop.group(2), []) if loop and var in [
            v.strip() for v in loop.group(1).split(",")] else []
        for name in expanded:
            out.append({"kind": "script", "name": name, "surface": surface, "key": "HookScript",
                        "file": rel, "line": line_no})
        if not expanded:
            out.append({"kind": "script", "name": None, "dynamic": f"HookScript({var})",
                        "surface": surface, "key": "HookScript", "file": rel, "line": line_no})

    for m in _RESOLVE.finditer(line):
        out.append({"kind": "global", "name": m.group(1), "surface": surface, "key": "resolve",
                    "file": rel, "line": line_no})
    if "Compat.resolve(" in line and not _RESOLVE.search(line):
        out.append({"kind": "global", "name": None, "dynamic": line.strip()[:120], "surface": surface,
                    "key": "resolve", "file": rel, "line": line_no})
    for m in _HOOKSECURE.finditer(line):
        out.append({"kind": "function", "name": m.group(1), "surface": surface, "key": "hooksecurefunc",
                    "file": rel, "line": line_no})
    for m in _HOOKSCRIPT.finditer(line):
        out.append({"kind": "script", "name": m.group(1), "surface": surface, "key": "HookScript",
                    "file": rel, "line": line_no})
    return out


def _call_rows(
    line: str, line_no: int, defined: set[str] | None, surface: str, rel: str
) -> list[dict[str, Any]]:
    """The client API calls of one line that the addon does not define itself."""
    out: list[dict[str, Any]] = []
    for m in _CALL.finditer(line):
        name = m.group(1)
        if defined is None or name.split(".")[-1] in defined or name in ("CreateFrame", "WFJ"):
            continue
        entry = {"kind": "api", "name": name, "surface": surface, "key": "call",
                 "file": rel, "line": line_no}
        if suspect_api(name):
            entry["suspect"] = True
        out.append(entry)
    return out


def build(addon: Path) -> dict[str, Any]:
    """Every client name the addon needs, in file order, deduped on (kind, name, surface)."""
    if not addon.is_dir():
        raise SystemExit(f"client_surface: no addon directory at {addon}")
    entries: list[dict[str, Any]] = []
    seen: set[tuple[str, str | None, str, str]] = set()
    defined = addon_defined(addon)
    for path in sorted(addon.rglob("*.lua")):
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        for entry in scan_file(path, addon, defined):
            key = (entry["kind"], entry["name"], entry["surface"], entry.get("dynamic", ""))
            if key in seen:
                continue
            seen.add(key)
            entries.append(entry)
    return {"addon": addon.name, "entries": entries}


def summary(manifest: dict[str, Any]) -> list[str]:
    """Per surface: the names the client is asked about, the suspect `api` matches held back, and the dynamic
    names no static scan can resolve. The three add up to the entry count."""
    counts: dict[str, list[int]] = {}
    for e in manifest["entries"]:
        row = counts.setdefault(e["surface"], [0, 0, 0])
        row[2 if not e.get("name") else 1 if e.get("suspect") else 0] += 1
    lines = [
        f"{s}: {n} names" + (f" · {sus} suspect" if sus else "") + (f" · {d} dynamic" if d else "")
        for s, (n, sus, d) in sorted(counts.items())
    ]
    n = sum(c[0] for c in counts.values())
    sus = sum(c[1] for c in counts.values())
    dyn = sum(c[2] for c in counts.values())
    lines.append(f"total: {n} names · {sus} suspect · {dyn} dynamic · {n + sus + dyn} entries · "
                 f"{len(counts)} surfaces")
    return lines


def partial(name: str) -> bool:
    """A name that starts or ends with a dot (`.BackButton`, `InspectPVPFrame.MainInfoFrame.`): one piece of a
    longer name the surface joins at run time (`LISTING .. ".BackButton"`). There is no global of that name to
    ask a client for."""
    return name.startswith(".") or name.endswith(".")


def probe_names(manifest: dict[str, Any]) -> list[tuple[str, str]]:
    """(kind, name) to ask the client about, deduped. A dynamic entry has no name to ask for, and a `method`
    entry is a method on an object (`hooksecurefunc(frame, "Update")`); asking `_G` for it means nothing, so
    it is reported from its surface's own verdict instead. A piece of a longer name is left out for the same
    reason."""
    out: list[tuple[str, str]] = []
    seen: set[tuple[str, str]] = set()
    for e in manifest["entries"]:
        if not e.get("name") or e["kind"] == "method" or partial(e["name"]):
            continue
        key = (e["kind"], e["name"])
        if key not in seen:
            seen.add(key)
            out.append(key)
    return out


PROBE_LUA = """-- Asks this client for every name the addon depends on and saves the answers in the scan dev
-- addon's SavedVariables, under `WFJScanDB.probe`, which `wfj.dev.client_surface report` reads. Generated; do
-- not hand-edit. It only ever replaces `WFJScanDB.probe`: the rest of `WFJScanDB` is the quest scan's state.
local MANIFEST = "%s"   -- answers saved under another manifest are dropped, never merged
local NAMES = {
%s
}
local SURFACES = {}
for _, row in ipairs(NAMES) do SURFACES[row[3]] = true end
-- surfaces with no window (Core/, Main, key capture, slash …): the login sweep is their
-- evidence, so they are never listed as left to ask and cannot be marked asked
local WINDOWLESS = { %s }

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("ADDON_LOADED")

-- A name the client may hold under a namespace table: C_AddOns.IsAddOnLoaded, C_Spell.GetSpellDescription,
-- Enum.TooltipDataType. Shared by every kind, so a *global* candidate written in dotted form is found too.
-- Every segment is walked, as Core/Compat.lua's lookup does, so Enum.TooltipDataType.Item is
-- the value itself and not the table two segments up.
local function valueOf(name)
  local value = _G[name]
  if value ~= nil or not name:find(".", 1, true) then return value end
  local segments = { strsplit(".", name) }
  local field = table.remove(segments)
  local root = _G
  for _, segment in ipairs(segments) do
    if type(root) ~= "table" then return nil end
    root = root[segment]
  end
  return type(root) == "table" and root[field] or nil
end

local function sweep()
  local probe = CreateFrame("Frame")
  local build = select(2, GetBuildInfo())
  -- answers are kept across a session's sweeps, but never across another manifest or another client build:
  -- a patch that removes a frame must be able to turn a "found" back into "no"
  WFJScanDB = type(WFJScanDB) == "table" and WFJScanDB or {}
  local db = WFJScanDB.probe
  if type(db) ~= "table" or db.manifest ~= MANIFEST or db.client ~= build then
    db = { manifest = MANIFEST, client = build, answers = {}, loaded = {}, asked = {} }
    WFJScanDB.probe = db
  end
  db.build = { GetBuildInfo() }
  db.answers = db.answers or {}
  db.loaded = db.loaded or {}
  db.asked = db.asked or {}   -- surface → sweeps run while the player had its window open
  for _, row in ipairs(NAMES) do
    local kind, name, surface = row[1], row[2], row[3]
    local answer
    if kind == "script" then
      local widget = name:find("^OnTooltip") and GameTooltip or probe
      answer = (widget and widget.HasScript and widget:HasScript(name)) and "script" or "no"
    else
      local value = valueOf(name)
      if kind == "function" or kind == "api" then
        answer = type(value) == "function" and "function" or "no"
      else
        answer = value ~= nil and (type(value) == "table" and "frame" or type(value)) or "no"
      end
    end
    local key = kind .. "|" .. name .. "|" .. surface
    -- a later sweep only ever upgrades an answer: a frame that appears when its window opens stays found
    if answer ~= "no" or db.answers[key] == nil then
      db.answers[key] = answer
    end
  end
  return db
end

f:SetScript("OnEvent", function(_, event, addon)
  local db = sweep()
  if event == "ADDON_LOADED" and addon then
    db.loaded[addon] = true
  end
  if event == "PLAYER_LOGIN" then
    print("WFJ probe: " .. #NAMES .. " names checked · build " .. tostring(db.build[1]) ..
      " · interface " .. tostring(db.build[4]) ..
      ". Open a window, then /wfjprobe <surface>; /wfjprobe lists what is left")
  end
end)

-- The `lod` tag only covers a surface whose Blizzard addon our own addon names in
-- LoadOnDemand.when. A window the client builds on first show without a load-on-demand addon (the
-- guild frame is the open case) has no such tag, so its absences read as proven when nobody ever
-- opened it. `/wfjprobe <surface>` is the player saying "it is open now, ask again": the only evidence that
-- separates "the client removed it" from "it was never built".
local function remaining(db)
  local out = {}
  for surface in pairs(SURFACES) do
    if not WINDOWLESS[surface] and (db.asked[surface] or 0) == 0 then out[#out + 1] = surface end
  end
  table.sort(out)
  return out
end

SLASH_WFJPROBE1 = "/wfjprobe"
SlashCmdList["WFJPROBE"] = function(arg)
  arg = (arg or ""):lower():gsub("^%%s+", ""):gsub("%%s+$", "")
  local db = type(WFJScanDB) == "table" and WFJScanDB.probe
  if type(db) ~= "table" or db.answers == nil then
    print("WFJ probe: not loaded yet")
    return
  end
  db.asked = db.asked or {}
  if arg == "" then
    local left = remaining(db)
    print("WFJ probe: " .. #left .. " surfaces not yet asked with their window open")
    print("WFJ probe: " .. (#left == 0 and "none left; /reload to save" or table.concat(left, " ")))
    return
  end
  if not SURFACES[arg] then
    print("WFJ probe: no surface '" .. arg .. "'; /wfjprobe lists what is left")
    return
  end
  if WINDOWLESS[arg] then
    print("WFJ probe: " .. arg .. " has no window; the login sweep already answers it")
    return
  end
  -- One surface per invocation, deliberately. An `all` verb would mark every surface as "asked with
  -- its window open" from one keystroke with nothing open: the false evidence this mechanism exists
  -- to prevent.
  db = sweep()
  db.asked[arg] = (db.asked[arg] or 0) + 1
  print("WFJ probe: " .. arg .. " asked · " .. #remaining(db) ..
    " surfaces still unasked; /reload to save")
end
"""

WALK_LUA = """
-- The load walk. After login, outside combat, it asks the client to load each load-on-demand Blizzard addon a
-- surface waits for, a few per frame, so every surface sets up in one session without its window being opened
-- by hand. It opens nothing. The client's answer per addon is saved under `probe.walk`. On a client people play
-- on it does not run at login: the window test runs it first (`WFJScanWalk`).
local WALK = { %s }
local AT_LOGIN = %s
local PER_FRAME = 3
local walker = CreateFrame("Frame")
local nextAt = 1
local walked, afterWalk = false, nil

local function probeDb()
  local db = type(WFJScanDB) == "table" and WFJScanDB.probe
  if type(db) ~= "table" then db = sweep() end
  db.walk = db.walk or {}
  db.readings = db.readings or {}
  return db
end

local function walk()
  if InCombatLockdown() then return end
  local db = probeDb()
  for _ = 1, PER_FRAME do
    local addon = WALK[nextAt]
    if not addon then
      walker:SetScript("OnUpdate", nil)
      walked = true
      print("WFJ probe: load walk done, " .. #WALK .. " addons; /reload to save")
      if afterWalk then
        local go = afterWalk
        afterWalk = nil
        go()
      elseif WFJScanTextSweep then
        WFJScanTextSweep()
      end
      return
    end
    nextAt = nextAt + 1
    if C_AddOns.IsAddOnLoaded(addon) then
      db.walk[addon] = "already loaded"
    else
      local ok, loaded, reason = pcall(C_AddOns.LoadAddOn, addon)
      db.walk[addon] = (ok and loaded) and "loaded" or ("refused: " .. (ok and tostring(reason) or "error"))
    end
  end
end

-- Runs the walk when it has not run, then `done`.
function WFJScanWalk(done)
  if walked then return done() end
  afterWalk = done
  walker:SetScript("OnUpdate", walk)
end

-- What the client restricts for addon code, written down where the player happens to be: the instance type
-- and the map id are part of each record's name, so the open world and a dungeon keep separate answers.
local function reading(what, fn)
  local ok, value = pcall(fn)
  local _, instance = IsInInstance()
  local place = tostring(instance) .. " map " .. tostring(C_Map.GetBestMapForUnit("player"))
  probeDb().readings[what .. " @ " .. place] = ok and tostring(value) or "no such API"
end

walker:RegisterEvent("PLAYER_ENTERING_WORLD")
walker:RegisterEvent("ZONE_CHANGED_NEW_AREA")
walker:RegisterEvent("PLAYER_TARGET_CHANGED")
walker:RegisterEvent("QUEST_DETAIL")
local started = false
walker:SetScript("OnEvent", function(self, event)
  if event == "PLAYER_TARGET_CHANGED" then
    if UnitExists("target") and not UnitIsPlayer("target") then
      reading("npc identity secret", function() return C_Secrets.ShouldUnitIdentityBeSecret("target") end)
    end
  elseif event == "QUEST_DETAIL" then
    reading("quest text secret", function() return issecretvalue(GetQuestText()) end)
  else
    reading("secret restrictions", function() return C_Secrets.HasSecretRestrictions() end)
    reading("map restriction", function()
      return C_RestrictedActions.GetAddOnRestrictionState(Enum.AddOnRestrictionType.Map)
    end)
    if not started and AT_LOGIN then
      started = true
      self:SetScript("OnUpdate", walk)
    end
  end
end)
"""


# Addons the walk never loads: the event log opens its window and starts recording as soon as it loads.
WALK_SKIP = frozenset({"Blizzard_EventTrace"})


TEXT_LUA = """
-- The text sweep. After the load walk it reads every frame's text regions and writes down each one that still
-- holds an English line the dictionary has Japanese for, with the region's name, under `probe.english`. A window
-- the addon reaches shows Japanese there, so what is listed is text no surface touched. `/wfjtext` runs it again
-- (with a window open, to read what that window writes when it shows).
local ENGLISH = {
%s
}
local PER_TICK = 400
local sweeper = CreateFrame("Frame")

function WFJScanTextSweep()
  local db = probeDb()
  db.english = {}
  local found, seen = 0, 0
  local frame = EnumerateFrames()
  sweeper:SetScript("OnUpdate", function()
    for _ = 1, PER_TICK do
      if not frame then
        sweeper:SetScript("OnUpdate", nil)
        print("WFJ probe: text sweep done, " .. found .. " English lines in " .. seen .. " frames; /reload to save")
        return
      end
      seen = seen + 1
      pcall(function()
        if frame:IsForbidden() then return end
        for _, region in ipairs({ frame:GetRegions() }) do
          if region:GetObjectType() == "FontString" then
            local text = region:GetText()
            if type(text) == "string" and not (issecretvalue and issecretvalue(text)) then
              local plain = (text:gsub("|c%%x%%x%%x%%x%%x%%x%%x%%x", ""):gsub("|r", ""))
              if ENGLISH[plain] then
                local rec = db.english[plain] or { n = 0, at = {} }
                rec.n = rec.n + 1
                if #rec.at < 3 then
                  rec.at[#rec.at + 1] = tostring(region:GetDebugName()) .. (region:IsVisible() and " (visible)" or "")
                end
                db.english[plain] = rec
                found = found + 1
              end
            end
          end
        end
      end)
      frame = EnumerateFrames(frame)
    end
  end)
end

SLASH_WFJTEXT1 = "/wfjtext"
SlashCmdList.WFJTEXT = WFJScanTextSweep

-- The live sweep (`/wfjlive`, out of combat). A surface puts its Japanese on from the functions the client runs
-- when a window opens, so text in a closed window, or in one shown by a bare Show, proves nothing. This opens the
-- player's main windows one at a time through the client's own toggle functions, reads every text region on screen
-- (the English ones that have Japanese by name, the Japanese ones as a count), clicks through every tab the window
-- shows and every tab a page shows in turn, reading each page, and closes the window. A window is saved under its
-- name and a page under `<window> > <the tab's name>`, in `probe.live`.
local function plainOf(region)
  local text = region:GetText()
  if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return nil end
  return (text:gsub("|c%%x%%x%%x%%x%%x%%x%%x%%x", ""):gsub("|r", ""))
end

local function spells(name) return function() PlayerSpellsUtil[name]() end end
local LIVE = {
  { "character", function() ToggleCharacter("PaperDollFrame") end },
  { "spellbook", spells("ToggleSpellBookFrame") },
  { "achievements", function() ToggleAchievementFrame() end },
  { "map", function() ToggleWorldMap() end },
  { "quest log", function() ToggleQuestLog() end },
  { "collections", function() ToggleCollectionsJournal(1) end },
  { "group finder", function() PVEFrame_ToggleFrame() end },
  { "dungeon journal", function() ToggleEncounterJournal() end },
  { "friends", function() ToggleFriendsFrame(1) end },
  { "guild", function() ToggleGuildFrame() end },
  { "professions", function() ToggleProfessionsBook() end },
  { "bags", function() ToggleAllBags() end },
  { "calendar", function() ToggleCalendar() end },
  { "help", function() ToggleHelpFrame() end },
}
local OPEN_TICKS, CLOSED_TICKS = 45, 12

-- The sweeps read what a player with Japanese on sees: with translation off, or English first, every window is
-- English and the answer means nothing.
local function japaneseOn()
  local settings = type(WFJ_DB) == "table" and WFJ_DB.settings
  if type(settings) == "table" and (settings.enabled == false or settings.direction == "en") then
    print("WFJ probe: translation is off (or English first). Turn Japanese on, then run it again")
    return false
  end
  return true
end
local opener = CreateFrame("Frame")

-- Japanese on screen in a face that has no Japanese letters is drawn as empty boxes: a guild's message of the day
-- a player wrote in Japanese, in the client's own font. The addon's bundled face is the one face known to hold
-- them, so any other face under Japanese text is written down, with the widget's name, under `boxes`.
local JAPANESE_FACE = "ipagui" -- the bundled face's file name (the addon's Font.PATH)
local function hasJapanese(text)
  if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return false end
  return text:find("[\\227-\\233\\239]") ~= nil -- the lead byte of kana, kanji and full-width forms
end
local function boxed(font)
  return type(font) == "string" and not font:lower():find(JAPANESE_FACE, 1, true)
end

local function readScreen()
  local record = { english = {}, japanese = 0, boxes = {} }
  local function box(widget, text, ...)
    if not hasJapanese(text) then return end
    local font = widget:GetFont(...)
    if boxed(font) then record.boxes[tostring(widget:GetDebugName())] = font end
  end
  local frame = EnumerateFrames()
  while frame do
    pcall(function()
      if frame:IsForbidden() or not frame:IsVisible() then return end
      for _, region in ipairs({ frame:GetRegions() }) do
        if region:GetObjectType() == "FontString" and region:IsVisible() then
          local plain = plainOf(region)
          if plain and ENGLISH[plain] then
            record.english[tostring(region:GetDebugName())] = plain
          elseif plain and hasJapanese(plain) then
            record.japanese = record.japanese + 1
            pcall(box, region, plain)
          end
        end
      end
      -- text a frame holds itself: what a typing box shows, and a SimpleHTML's paragraphs (it has no GetText;
      -- GetTextData gives each paragraph with its text type, and the font is asked per text type)
      local kind = frame:GetObjectType()
      if kind == "EditBox" then
        pcall(box, frame, frame:GetText())
      elseif kind == "SimpleHTML" then
        for _, node in ipairs(frame:GetTextData()) do
          if not pcall(box, frame, node.text, node.type) then pcall(box, frame, node.text, "P") end
        end
      end
    end)
    frame = EnumerateFrames(frame)
  end
  return record
end

-- What the test clicks in an open window. It finds the buttons itself: every button of the window that is on
-- screen, enabled, has a click script and is not protected. Two kinds are clicked:
--   a page switcher by name: a tab (CharacterFrameTab2, CollectionsJournal.MountsTab, PaperDollSidebarTab1,
--     CommunitiesFrame.RosterTab, or one a tab system made, which carries a tabID) and the group finder's and PvP
--     window's side buttons (…GroupButton<n>, …CategoryButton<n>);
--   any other plain button, unless its name or its window says it does something: buys, sells, deletes, sends,
--     accepts, joins, queues, casts, uses an item, spends a talent, changes a setting. Those words are below; a
--     button is left alone when the last two parts of its name hold one of ACTS, or any part holds one of AREAS.
-- A checkbox is never clicked (it changes a setting), nor a button outside the window (the action bars, the chat,
-- the minimap), nor a menu's entries (a menu is a window of its own).
local ACTS = { "item", "slot", "bag", "container", "action", "spell", "macro", "loot", "buy", "purchase", "sell",
  "bid", "post", "auction", "delete", "destroy", "abandon", "leave", "quit", "logout", "exit", "close", "cancel",
  "accept", "confirm", "okay", "yes", "apply", "save", "send", "invite", "kick", "remove", "disband", "reset",
  "learn", "train", "upgrade", "craft", "create", "join", "queue", "enter", "start", "summon", "mount", "equip",
  "use", "refund", "unlock", "activate", "pay", "claim", "collect", "report", "ignore", "block", "friend",
  "whisper", "share", "sign", "donate", "deposit", "withdraw", "repair", "socket", "enchant", "trade", "mail",
  "swap", "rename", "promote", "demote", "shop", "store", "checkout", "redeem", "favorite", "wrap", "dismiss",
  "release", "revive", "heal", "cage", "edit", "unlearn", "respec", "reforge", "scrap", "obliterate", "convert",
  "transfer", "lock", "ticket", "url", "link", "copy", "import", "export", "move", "pickup", "ready", "role",
  "vote", "roll", "need", "greed", "pass", "decline", "reject", "resign", "surrender", "forfeit", "concede",
  "battle", "find", "search", "request", "submit", "publish", "upload", "connect", "login", "sync", "track",
  "toggle", "summon", "cast", "glyph", "pet", "toy", "heirloom", "transmog", "outfit", "dye", "place", "sort",
  "party", "raid", "chat", "message", "call", "travel", "customise", "customize", "tentative", "rsvp", "attend",
  "signup", "respond", "available", "mass", "auto", "enable", "disable", "clear", "wipe", "purge",
  "ok", "select", "continue", "commit", "spend", "complete", "choose", "who", "column", "header", "guild",
  "officer", "note", "rank", "motd", "info", "permission", "option", "config", "setting", "settings",
  "clean", "refresh", "new", "add", "set", "pin", "waypoint", "social", "tweet", "screenshot", "photo", "drag" }
local AREAS = { "talent", "spellbook", "pagedspells", "loadout", "containerframe", "merchant", "auction", "trade",
  "mailframe", "bankframe", "guildbank", "catalogshop", "storeframe", "macro", "keybind", "binding", "editmode",
  "settingspanel", "helpframe", "worldmap", "questmap", "toybox", "heirloom", "wardrobe", "transmog", "barber",
  "petbattle", "stable", "housing", "houseeditor", "voidstorage", "itemupgrade", "scrapping", "reforge",
  "azerite", "runeforge", "soulbind", "covenant", "garrison", "orderhall", "calendarcreate", "communitiesticket",
  "clubfinder", "recruitafriend", "channel", "voice", "report", "tooltip", "dropdown", "menu", "chatframe",
  "chatconfig", "actionbar", "microbutton", "minimap", "objectivetracker", "staticpopup",
  "achievementframeachievements", "achievementframesummary", "achievementframecomparison", "shield",
  "friendslist", "baganator", "calendarview", "calendarevent", "calendarinvite", "calendarmass",
  "calendartexture", "whoframe", "guildcontrol", "guildinfo", "communitiessettings",
  "titlemanager" }

local ACT = {}
for _, word in ipairs(ACTS) do ACT[word] = true end

-- A frame with no name of its own is named by its address (`ScrollTarget.9914c3950`), which changes every
-- session and from row to row: a run of eight or more hex characters holding a digit. → the name with `*` there.
local function unaddressed(name)
  return (name:gsub("%%f[%%w]%%x+%%f[%%W]", function(part)
    if #part >= 8 and part:find("%%d") then return "*" end
  end))
end

-- The action word a name holds, as one of its own words (CloseButton → close; ScrollTarget holds none), or nil.
local function act(name)
  -- an address is not a word: its letters would spell one by chance (`…add…`, `…bid…`)
  local words = unaddressed(name):gsub("(%%l)(%%u)", "%%1 %%2"):gsub("(%%u)(%%u%%l)", "%%1 %%2"):lower()
  for word in words:gmatch("%%a+") do
    if ACT[word] or (word:sub(-1) == "s" and ACT[word:sub(1, -2)]) then return word end
  end
  return nil
end

local function holds(text, words)
  for _, word in ipairs(words) do
    if text:find(word, 1, true) then return word end
  end
  return nil
end

-- What a button shows: its own text, or its first text region's (a list row's label).
local function caption(button)
  local text = button:GetText()
  if type(text) == "string" and text ~= "" then return text end
  for _, region in ipairs({ button:GetRegions() }) do
    if region:GetObjectType() == "FontString" then
      local label = region:GetText()
      if type(label) == "string" and label ~= "" then return label end
    end
  end
  return ""
end

-- What the test does with a button, and why: "page" for a page switcher, "button" for another button that is safe
-- to click, or nil with the reason it is left alone.
local function verdict(button)
  local kind = button:GetObjectType()
  if kind ~= "Button" and kind ~= "CheckButton" then return nil, "not a button" end
  local name = tostring(button:GetDebugName())
  if name:find("^ChatFrame%%d") or name:find("ChatConfig", 1, true) or name:find("Tooltip", 1, true) then
    return nil, "chat or tooltip"
  end
  local page = button.tabID ~= nil or name:find("Tab%%d*$") or name:find("GroupButton%%d+$")
    or name:find("CategoryButton%%d+$")
  if not button:IsEnabled() then return nil, page and "page, disabled (the page in front, or locked)" or "disabled" end
  if page then
    -- the dungeon journal's tabs run a call the client refuses to addon code (it answers with its blocked notice)
    if name:find("^EncounterJournal") then return nil, "the client refuses this tab to an addon" end
    return "page"
  end
  if kind ~= "Button" then return nil, "a checkbox" end
  if not button:GetScript("OnClick") then return nil, "no click script" end
  local lower = name:lower()
  local area = holds(lower, AREAS)
  if area then return nil, "area: " .. area end
  local does = act(name:match("([^.]*%%.?[^.]*)$") or name) -- the last two parts of the name
  if does then return nil, "act: " .. does end
  -- a button with no name of its own and no words on it is an icon: an item, a spell, a pet. What a click on
  -- one does cannot be told from outside, so it is never clicked.
  if name:find("%%.%%x+$") and unaddressed(name) ~= name then
    local ok, text = pcall(caption, button)
    if not ok or text == "" then return nil, "an icon with no words" end
  end
  return "button"
end

local function clickable(button)
  if not button:IsVisible() then return nil end
  return (verdict(button))
end

-- The top-level frames on screen: a window's buttons are the ones under a frame that was not there before it opened.
local function rootsOnScreen()
  local roots = {}
  local frame = EnumerateFrames()
  while frame do
    pcall(function()
      if not frame:IsForbidden() and frame:IsVisible() and frame:GetParent() == UIParent then roots[frame] = true end
    end)
    frame = EnumerateFrames(frame)
  end
  return roots
end

local function under(frame, roots)
  for _ = 1, 40 do
    if not frame then return false end
    if roots[frame] then return true end
    frame = frame:GetParent()
  end
  return false
end

-- A button as its place in the window and what it shows now. A list's rows are a few frames the client reuses
-- for one entry after another, and gives back in any order: the entry is the same wherever it is drawn, so the
-- row's own address is left out of its name. Rows that show no text count as one.
local function taken(button)
  local ok, text = pcall(caption, button)
  return unaddressed(tostring(button:GetDebugName())) .. "|" .. (ok and text or "")
end

-- A category list longer than its window (the achievement window's): moved down a step so its further rows are
-- drawn. → true when a list moved.
local SCROLL_STEP, MAX_SCROLLS = 0.12, 14
local function scrollOn(roots)
  local moved = false
  local frame = EnumerateFrames()
  while frame do
    pcall(function()
      if frame:IsForbidden() or not frame:IsVisible() or type(frame.SetScrollPercentage) ~= "function" then return end
      if not tostring(frame:GetDebugName()):find("Categories.ScrollBox$") or not under(frame, roots) then return end
      local at = frame:GetScrollPercentage() or 0
      if frame:HasScrollableExtent() and at < 0.999 then
        frame:SetScrollPercentage(math.min(1, at + SCROLL_STEP))
        moved = true
      end
    end)
    frame = EnumerateFrames(frame)
  end
  return moved
end

-- `/wfjtest tabs` clicks page switchers only: the first run on a client, before the list of other buttons the
-- test would click (`probe.test.buttons`) has been read.
local pagesOnly = false

-- The buttons of the open window to click, page switchers first. `skip` holds the ones already taken.
local function tabsOnScreen(skip, roots)
  local pages, buttons = {}, {}
  -- the cheap questions first: the client holds tens of thousands of frames and nearly all are not buttons on screen
  local function visit(frame)
    if frame:IsForbidden() then return end
    local type = frame:GetObjectType()
    if (type ~= "Button" and type ~= "CheckButton") or not frame:IsVisible() or frame:IsProtected() then return end
    if roots ~= nil and not under(frame, roots) then return end
    if skip[taken(frame)] then return end
    local kind = clickable(frame)
    if kind then
      local list = kind == "page" and pages or buttons
      list[#list + 1] = frame
    end
  end
  local frame = EnumerateFrames()
  while frame do
    pcall(visit, frame)
    frame = EnumerateFrames(frame)
  end
  local function byPlace(a, b) -- top to bottom, then left to right
    local top, other = a:GetTop() or 0, b:GetTop() or 0
    if math.abs(top - other) > 4 then return top > other end
    return (a:GetLeft() or 0) < (b:GetLeft() or 0)
  end
  pcall(table.sort, pages, byPlace)
  pcall(table.sort, buttons, byPlace)
  if not pagesOnly then
    for _, button in ipairs(buttons) do pages[#pages + 1] = button end
  end
  return pages
end

-- Every button of the open window with what the test decides about it, for reading afterwards: one line each,
-- `<name> | <what it shows> | <page, button, or why it is left alone>`. Pooled rows of one kind are listed once.
local MAX_LISTED = 500
local function listButtons(roots)
  local out, listed = {}, {}
  local frame = EnumerateFrames()
  while frame do
    pcall(function()
      if frame:IsForbidden() or not frame:IsVisible() then return end
      local kind = frame:GetObjectType()
      if (kind ~= "Button" and kind ~= "CheckButton") or not under(frame, roots) then return end
      local what, why
      if frame:IsProtected() then
        what, why = nil, "protected"
      else
        what, why = verdict(frame)
      end
      local name = unaddressed(tostring(frame:GetDebugName()))
      local ok, text = pcall(caption, frame)
      local line = name .. " | " .. (ok and text or "") .. " | " .. (what or why or "?")
      local once = name .. "|" .. (what or why or "?")
      if #out < MAX_LISTED and (not name:find("*", 1, true) or not listed[once]) then
        listed[once] = true
        out[#out + 1] = line
      end
    end)
    frame = EnumerateFrames(frame)
  end
  return out
end

-- A click can raise a confirmation or leave a menu open: both are put away before the next click, unanswered.
local function putAway()
  local raised = false
  for i = 1, 4 do
    local popup = _G["StaticPopup" .. i]
    if popup and popup:IsShown() then
      raised = true
      pcall(popup.Hide, popup)
    end
  end
  pcall(function() Menu.GetManager():CloseMenus() end)
  return raised
end

local TAB_TICKS, MAX_PAGES = 15, 150

local function WFJScanLiveSweep(done)
  if not japaneseOn() then return end
  if InCombatLockdown() then
    print("WFJ probe: the live sweep does not run in combat")
    return
  end
  local db = probeDb()
  db.live = { ["(nothing open)"] = readScreen() }
  local idle, idleRoots = {}, rootsOnScreen()
  for _, tab in ipairs(tabsOnScreen({})) do idle[taken(tab)] = true end
  db.test = db.test or {}
  db.test.finished = nil -- a sweep started again: what is saved is no longer the finished run
  db.test.popups = {}
  local at, ticks, english, pages = 0, 0, 0, 0
  local state, queue, seen, window, roots, scrolls = "closed", nil, nil, nil, nil, 0
  local queued, clicks = {}, 0
  local function record(name)
    local screen = readScreen()
    for _ in pairs(screen.english) do english = english + 1 end
    db.live[name] = screen
    pages = pages + 1
  end
  -- What is on screen and not clicked yet joins the front of the queue, in screen order: what a click brought up
  -- (a category's own entries) is clicked next, while it is still shown. `seen` holds what was clicked, so a row
  -- that scrolled away before its turn is found again when the list brings it back.
  -- The queue holds entries (a button's place and what it shows), not frames: a list draws one entry in one row
  -- now and another later, so the row to click is looked up when the entry's turn comes.
  local function moreTabs()
    local fresh = {}
    for _, tab in ipairs(tabsOnScreen(seen, roots)) do
      local key = taken(tab)
      if not queued[key] then
        queued[key] = true
        fresh[#fresh + 1] = key
      end
    end
    for i = #fresh, 1, -1 do table.insert(queue, 1, fresh[i]) end
  end
  -- Every entry drawn now with its button. An entry missing from it is not drawn (it comes back when the list
  -- scrolls). Read once for a run of entries: reading the client's frames is the slow part.
  local function drawn()
    local map = {}
    for _, tab in ipairs(tabsOnScreen(seen, roots)) do
      local key = taken(tab)
      if not map[key] then map[key] = tab end
    end
    return map
  end
  -- Clicks `tab` when it is still there and still new. A list's rows that are not categories (a mount, a friend)
  -- are sampled: two of a kind show what a row's page looks like.
  local function click(key, map)
    queued[key] = nil
    local tab = not seen[key] and clicks < MAX_PAGES and map[key] or nil
    if not tab then error("skip") end
    -- a run of like buttons: a list's rows (one name but for the row's address) or numbered ones (a calendar's days)
    local kind = unaddressed(tostring(tab:GetDebugName())):gsub("%%d+", "#")
    if verdict(tab) == "button" and (kind:find("*", 1, true) or kind:find("#", 1, true))
      and not kind:find("Categor", 1, true) then
      local sampled = seen["#" .. kind] or 0
      if sampled >= 2 then error("skip") end
      seen["#" .. kind] = sampled + 1
    end
    seen[key] = true
    clicks = clicks + 1
    tab:Click()
    return tab
  end
  opener:SetScript("OnUpdate", function()
    if InCombatLockdown() then return end
    ticks = ticks + 1
    if state == "open" then
      if ticks < OPEN_TICKS then return end
      record(window)
      roots = {}
      for frame in pairs(rootsOnScreen()) do
        if not idleRoots[frame] then roots[frame] = true end
      end
      db.test.buttons = db.test.buttons or {}
      db.test.buttons[window] = listButtons(roots)
      if next(roots) == nil then
        db.test.unopened = db.test.unopened or {}
        db.test.unopened[window] = "the toggle opened nothing"
      end
      -- a character in no guild shows none of the guild's pages (the roster, the info tab with the message of the
      -- day): the run did not look at them, and says so instead of passing them
      if window == "guild" and type(IsInGuild) == "function" and not IsInGuild() then
        db.test.unopened = db.test.unopened or {}
        db.test.unopened["guild pages"] = "this character is in no guild"
      end
      queue, seen, scrolls, queued, clicks = {}, {}, 0, {}, 0
      for tab in pairs(idle) do seen[tab] = true end
      moreTabs()
      state, ticks = "tabs", TAB_TICKS
      return
    end
    if state == "tabs" then
      if ticks < TAB_TICKS then return end
      if queue.scrolled then
        queue.scrolled = nil
        moreTabs()
      end
      if queue.shown then
        local name = tostring(queue.shown:GetDebugName())
        record(window .. " > " .. name) -- read before a menu the click opened is put away
        if putAway() then db.test.popups[name] = true end
        moreTabs() -- a page can carry buttons of its own
        queue.shown = nil
      end
      local map
      while queue[1] do -- the entries passed over cost nothing more: the next one is tried at once
        map = map or drawn()
        local ok, clicked = pcall(click, table.remove(queue, 1), map)
        if ok then
          queue.shown = clicked
          ticks = 0
          return
        end
        if not tostring(clicked):find("skip", 1, true) and type(db.test.errors) == "table" then
          local key = "[live] click: " .. tostring(clicked):sub(1, 300)
          db.test.errors[key] = (db.test.errors[key] or 0) + 1
        end
      end
      if scrolls < MAX_SCROLLS and scrollOn(roots) then -- nothing left on screen to click: the list's next rows
        scrolls = scrolls + 1
        queue.scrolled = true
        ticks = 0
        return
      end
      pcall(CloseAllWindows)
      state, ticks = "closed", 0
      return
    end
    if ticks < CLOSED_TICKS then return end
    at, ticks = at + 1, 0
    if not LIVE[at] then
      opener:SetScript("OnUpdate", nil)
      print("WFJ probe: live sweep done, " .. #LIVE .. " windows, " .. pages .. " pages, " .. english
        .. " English lines on screen; /reload to save")
      if type(done) == "function" then done() end
      return
    end
    window = LIVE[at][1]
    local ok, err = pcall(LIVE[at][2])
    if ok then
      state = "open"
    else
      db.live[window] = { refused = tostring(err) }
      db.test.unopened = db.test.unopened or {}
      db.test.unopened[window] = tostring(err):sub(1, 200)
    end
  end)
end

SLASH_WFJLIVE1 = "/wfjlive"
SlashCmdList.WFJLIVE = WFJScanLiveSweep

-- The open sweep (`/wfjopen`, out of combat): every closed window that holds an English line the dictionary has
-- Japanese for is shown, read and hidden again, one at a time. It reaches the windows no key opens (a merchant,
-- the mail, a garrison table). A window shown this way did not run the client's own opening code, so a surface
-- that works from that code has not run either: the live sweep is the proof for the windows it covers, and this
-- one lists the rest to read. Windows that would alarm (a trial's logout timer, the death and movie frames) are
-- left closed. Saved under `probe.opened`.
local ALARMING = { "Tooltip", "DropDown", "Cinematic", "Movie", "Trial", "Ghost", "Death", "Logout", "Splash",
  "StaticPopup", "GMChat", "Survey", "RatingMenu", "Kiosk", "Subscription", "Destiny", "BossBanner", "LevelUp",
  "Toast", "ReadyCheck", "ReadyPopup", "ReadyDialog", "RoleCheck", "RolePoll", "Invite", "Report", "Behavioral",
  "EditMode", "BarberShop", "PetBattle", "Commentator" }

local function windowOf(region)
  local frame, top = region:GetParent(), nil
  while frame and frame ~= UIParent and frame ~= WorldFrame do
    top = frame
    frame = frame:GetParent()
  end
  return top
end

local function alarming(name)
  for _, word in ipairs(ALARMING) do
    if name:find(word, 1, true) then return true end
  end
  return false
end

local shower = CreateFrame("Frame")

local function WFJScanOpenSweep(done)
  if not japaneseOn() then return end
  if InCombatLockdown() then
    print("WFJ probe: the open sweep does not run in combat")
    return
  end
  local db = probeDb()
  db.opened = {}
  if type(db.test) == "table" then db.test.finished = nil end
  local groups, order = {}, {}
  local frame = EnumerateFrames()
  while frame do
    pcall(function()
      if frame:IsForbidden() then return end
      for _, region in ipairs({ frame:GetRegions() }) do
        if region:GetObjectType() == "FontString" and not region:IsVisible() then
          local plain = plainOf(region)
          local top = plain and ENGLISH[plain] and windowOf(region)
          local name = top and tostring(top:GetDebugName()) or ""
          if top and not top:IsForbidden() and not top:IsProtected() and not top:IsShown() and not alarming(name) then
            if not groups[top] then
              groups[top] = {}
              order[#order + 1] = top
            end
            table.insert(groups[top], region)
          end
        end
      end
    end)
    frame = EnumerateFrames(frame)
  end
  local at, wait, still, fixed, hidden = 0, 0, 0, 0, 0
  local current
  shower:SetScript("OnUpdate", function()
    if InCombatLockdown() then return end
    if current then
      wait = wait + 1
      if wait < 4 then return end
      local record = { still = {}, fixed = 0, hidden = 0 }
      for _, region in ipairs(groups[current]) do
        pcall(function()
          local plain = plainOf(region)
          if not region:IsVisible() then
            record.hidden = record.hidden + 1
            hidden = hidden + 1
          elseif plain and ENGLISH[plain] then
            record.still[tostring(region:GetDebugName())] = plain
            still = still + 1
          else
            record.fixed = record.fixed + 1
            fixed = fixed + 1
          end
        end)
      end
      db.opened[tostring(current:GetDebugName())] = record
      pcall(current.Hide, current)
      current = nil
      return
    end
    at = at + 1
    current = order[at]
    wait = 0
    if not current then
      shower:SetScript("OnUpdate", nil)
      print("WFJ probe: open sweep done, " .. #order .. " windows: " .. still .. " still English, " .. fixed
        .. " Japanese once shown, " .. hidden .. " on pages not showing; /reload to save")
      if type(done) == "function" then done() end
      return
    end
    if not pcall(current.Show, current) then
      db.opened[tostring(current:GetDebugName())] = { refused = true }
      current = nil
    end
  end)
end

SLASH_WFJOPEN1 = "/wfjopen"
SlashCmdList.WFJOPEN = WFJScanOpenSweep

-- The whole window test (`/wfjtest`): the load walk, the live sweep, then one done line. `probe.test` holds when
-- it ran and on which build, so a result read later is known to be a whole run of that build. The open sweep is
-- not part of it: a window shown bare runs its scripts with none of the data the client gives it, and each raises
-- an error (and can taint the frames it touches) on the character the test runs on. `/wfjopen` still runs it alone.
SLASH_WFJTEST1 = "/wfjtest"
local testRunning = false
SlashCmdList.WFJTEST = function(how)
  if not japaneseOn() or InCombatLockdown() then return end
  if testRunning then
    print("WFJ test: already running")
    return
  end
  testRunning = true
  pagesOnly = how == "tabs"
  local db = probeDb()
  db.test = { started = date("%%Y-%%m-%%d %%H:%%M:%%S"), build = tostring((select(2, GetBuildInfo()))),
    errors = {}, blocked = {}, warnings = {}, clicks = pagesOnly and "tabs" or "all" }
  -- every Lua error, every warning and every action the client refused an addon while the test runs, each with
  -- its count
  local shown = geterrorhandler()
  local function grab(message)
    local key = "[" .. tostring(db.test.part) .. "] " .. tostring(message):sub(1, 400)
    db.test.errors[key] = (db.test.errors[key] or 0) + 1
    return shown(message)
  end
  seterrorhandler(grab)
  -- an error-catching addon can keep the handler to itself: the run then sees no error at all, and says so
  if geterrorhandler() ~= grab then db.test.handler = "another addon keeps the error handler" end
  -- BugGrabber is that addon for most players: it sets its own handler, makes seterrorhandler do nothing
  -- (BugGrabber.lua:573-574) and keeps every error, warning and refused action in a list other addons may read
  -- (GetDB, each entry with its message, stack and a counter, :455-466). The counters before the run are kept, so
  -- what the run added is known when it ends.
  local grabber = type(BugGrabber) == "table" and BugGrabber or nil
  local function grabbed()
    local ok, list = pcall(function() return grabber:GetDB() end)
    return ok and type(list) == "table" and list or nil
  end
  local before = {}
  for _, e in ipairs(grabber and grabbed() or {}) do
    if type(e) == "table" then before[tostring(e.message)] = tonumber(e.counter) or 1 end
  end
  local function readGrabbed()
    local list = grabber and grabbed()
    if not list then return end
    for _, e in ipairs(list) do
      local added = type(e) == "table" and (tonumber(e.counter) or 1) - (before[tostring(e.message)] or 0) or 0
      if added > 0 then
        local where = tostring(e.stack or ""):match("[^\\n]+") or ""
        local key = "[grabbed] " .. tostring(e.message):sub(1, 300) .. " @ " .. where:sub(1, 140)
        db.test.errors[key] = (db.test.errors[key] or 0) + added
      end
    end
    db.test.handler = nil -- the errors were watched after all
  end
  local watcher = CreateFrame("Frame")
  watcher:RegisterEvent("ADDON_ACTION_BLOCKED")
  watcher:RegisterEvent("ADDON_ACTION_FORBIDDEN")
  watcher:RegisterEvent("LUA_WARNING") -- its one argument is the warning's text
  watcher:SetScript("OnEvent", function(_, event, addon, action)
    if event == "LUA_WARNING" then
      local key = "[" .. tostring(db.test.part) .. "] " .. tostring(addon):sub(1, 400)
      db.test.warnings[key] = (db.test.warnings[key] or 0) + 1
      return
    end
    local key = "[" .. tostring(db.test.part) .. "] " .. event .. " " .. tostring(addon) .. " " .. tostring(action)
    db.test.blocked[key] = (db.test.blocked[key] or 0) + 1
  end)
  db.test.part = "load"
  WFJScanWalk(function()
    db.test.part = "live"
    WFJScanLiveSweep(function()
      db.opened = nil -- an earlier run's bare-window list is not this run's
      db.test.part = "done"
      seterrorhandler(shown)
      watcher:UnregisterAllEvents()
      readGrabbed()
      testRunning = false
      db.test.finished = date("%%Y-%%m-%%d %%H:%%M:%%S")
      print("WFJ test done: /reload to save, then the result can be read")
    end)
  end)
end
"""


def _lua_string(text: str) -> str:
    out = text.replace("\\", "\\\\").replace('"', '\\"').replace("\r", "\\r").replace("\n", "\\n")
    return f'"{out}"'


def walk_addons(manifest: dict[str, Any]) -> list[str]:
    """The load-on-demand Blizzard addons the manifest's surfaces wait for, sorted, less `WALK_SKIP`."""
    return sorted({addon for e in manifest["entries"] for addon in e.get("lod", ())} - WALK_SKIP)


def translated_english(data: Path) -> list[str]:
    """The English of every interface line that ships Japanese under `data` (none when the folder has no such
    lines): what the window test looks for on screen."""
    japanese = {}
    for path in sorted((data / "ui").glob("*.jsonl")):
        for line in path.read_text(encoding="utf-8").splitlines():
            row = json.loads(line) if line.strip() else {}
            if row.get("ja"):
                japanese[row["id"]] = row["ja"]
    out = []
    for path in sorted((data / "english" / "ui").glob("*.jsonl")):
        for line in path.read_text(encoding="utf-8").splitlines():
            row = json.loads(line) if line.strip() else {}
            # a line whose Japanese is its English (a name) is not English left on screen
            if row.get("en") and japanese.get(row.get("id"), row["en"]) != row["en"]:
                out.append(row["en"])
    return out


def probe_lua(manifest: dict[str, Any], walk: bool = False, english: Iterable[str] = (),
              at_login: bool = True) -> str:
    """The probe as one Lua file for the scan dev addon: every manifest name with its surface, checked at
    login, saved under `WFJScanDB.probe` for `report`. With `walk` it also loads every load-on-demand addon a
    surface waits for and records what the client restricts (`read_walk` reads both back); with `at_login`
    false that loading waits for the window test."""
    surfaces = {(e["kind"], e["name"]): e["surface"] for e in manifest["entries"] if e.get("name")}
    rows = [f'  {{"{kind}","{name}","{surfaces[(kind, name)]}"}},' for kind, name in probe_names(manifest)]
    probed = set(surfaces.values())
    bare = sorted({e["surface"] for e in manifest["entries"]
                   if e.get("windowless") and e["surface"] in probed})
    stamp = hashlib.sha256("\n".join(rows).encode("utf-8")).hexdigest()[:12]
    windowless_lua = " ".join(f'["{s}"] = true,' for s in bare)
    lua = PROBE_LUA % (stamp, "\n".join(rows), windowless_lua)
    if walk:
        lua += WALK_LUA % (", ".join(f'"{addon}"' for addon in walk_addons(manifest)), "true" if at_login else "false")
        # the English lines that have Japanese: a text region still holding one was reached by no surface
        lines = sorted({t for t in english if "%" not in t and re.search(r"[A-Za-z]{2}", t)})
        if lines:
            lua += TEXT_LUA % "\n".join(f"  [{_lua_string(t)}] = true," for t in lines)
    return lua


# a dotted name of any depth (Enum.TooltipDataType.Item), as `_RESOLVE` and Core/Compat.lua accept
_SV_ENTRY = re.compile(
    r'\["(global|function|script|api)\|([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)\|([a-z_0-9]+)"\]'
    r'\s*=\s*"([^"]*)"'
)
_SV_BUILD = re.compile(r'\["build"\]\s*=\s*\{(.*?)\}', re.S)
_SV_LOADED = re.compile(r'\["loaded"\]\s*=\s*\{(.*?)\n\t?\}', re.S)
_SV_ASKED = re.compile(r'\["asked"\]\s*=\s*\{(.*?)\n\t?\}', re.S)
_SV_ASKED_ENTRY = re.compile(r'\["([a-z_0-9.]+)"\]\s*=\s*(\d+)')
_SV_WALK = re.compile(r'\["walk"\]\s*=\s*\{(.*?)\n\t*\}', re.S)
_SV_READINGS = re.compile(r'\["readings"\]\s*=\s*\{(.*?)\n\t*\}', re.S)
_SV_PAIR = re.compile(r'\["([^"]+)"\]\s*=\s*"([^"]*)"')


_SV_PROBE = re.compile(r'^\t\["probe"\]\s*=\s*\{\n(.*?)^\t\}', re.M | re.S)


def probe_section(text: str) -> str:
    """The probe's answers out of a saved-variables file. The scan dev addon's file (`WFJScan.lua`) holds them
    under `WFJScanDB.probe`, next to the quest scan's own state, which must not be read as answers: that table
    is returned one level dedented, so it reads like a file of its own. A file without it (the older
    standalone `WFJProbeDB`) is returned as is."""
    m = _SV_PROBE.search(text)
    if not m:
        return text
    return re.sub(r"^\t", "", m.group(1), flags=re.M)


def asked_surfaces(text: str) -> dict[str, int] | None:
    """The probe's `asked` table: surface → how many sweeps the player ran with its window open
    (`/wfjprobe <surface>`). `None` when the file carries no such table, i.e. a probe from an older
    generator: the caller then keeps the `lod`-only rule rather than calling every absence unknown."""
    m = _SV_ASKED.search(probe_section(text))
    if not m:
        return None
    return {s: int(n) for s, n in _SV_ASKED_ENTRY.findall(m.group(1))}


def read_walk(text: str) -> tuple[dict[str, str], dict[str, str]]:
    """The probe's load walk (Blizzard addon → the client's answer) and its restriction readings
    (`<what> @ <instance type> map <id>` → value) out of a saved-variables file. Both empty for a probe made
    without the walk."""
    section = probe_section(text)
    walk, readings = _SV_WALK.search(section), _SV_READINGS.search(section)
    return (dict(_SV_PAIR.findall(walk.group(1))) if walk else {},
            dict(_SV_PAIR.findall(readings.group(1))) if readings else {})


def read_saved_variables(text: str) -> dict[str, str]:
    """The probe's saved answers (`WFJScanDB.probe`, or an older `WFJProbeDB`) → name → yes / no. The probe
    records what each name *is* (`frame`, `function`, `no`), so anything but `no` counts as present. `build`
    is the interface number from `GetBuildInfo()` (its fourth value)."""
    text = probe_section(text)
    out: dict[str, str] = {}
    for kind, name, _surface, value in _SV_ENTRY.findall(text):
        out[f"{kind}|{name}"] = "no" if value == "no" else "yes"
        out[f"value|{kind}|{name}"] = value
    if m := _SV_LOADED.search(text):
        for addon in re.findall(r'\["([A-Za-z_][A-Za-z0-9_]*)"\]\s*=\s*true', m.group(1)):
            out[f"loaded|{addon}"] = "yes"
    if m := _SV_BUILD.search(text):
        values = _STRING.findall(m.group(1))
        numbers = re.findall(r"(?<![\w.])(\d{4,6})(?![\w.])", m.group(1))
        if values:
            out["version"] = values[0]
        if numbers:
            out["build"] = numbers[-1]
    return out



_WORD = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


def _read(files: list[Path]) -> tuple[list[str], dict[str, set[int]]]:
    """The files' texts, and for each word the indexes of the files that hold it."""
    texts = [p.read_text(encoding="utf-8", errors="replace") for p in files]
    holders: dict[str, set[int]] = {}
    for i, text in enumerate(texts):
        for word in set(_WORD.findall(text)):
            holders.setdefault(word, set()).add(i)
    return texts, holders


def _hits(
    files: list[Path], texts: list[str], holders: dict[str, set[int]], names: list[str]
) -> dict[str, str]:
    hits: dict[str, str] = {}
    for name in names:
        hits[name] = ""
        words = _WORD.findall(name)
        if not words:
            continue
        # A name can only be in a file that holds every word of it, so the pattern runs on those files alone:
        # a name no file has costs a set lookup, not a pass over the extract.
        candidates = set.intersection(*(holders.get(w, set()) for w in words))
        # a piece that starts with a dot follows its frame (`self.BackButton`), so nothing is asked of what
        # comes before it
        before = "" if name.startswith(".") else r"(?<![A-Za-z0-9_])"
        after = "" if name.endswith(".") else r"(?![A-Za-z0-9_])"
        pattern = re.compile(before + re.escape(name) + after)
        for i in sorted(candidates):
            if pattern.search(texts[i]):
                hits[name] = files[i].name
                break
    return hits


def _missing(holders: dict[str, set[int]], names: list[str]) -> dict[str, list[str]]:
    return {name: [w for w in _WORD.findall(name) if w not in holders] for name in names}


_PARENT_SUFFIX = re.compile(r"\$parent([A-Za-z0-9_]+)")
_INHERITS = re.compile(
    r'CreateFrame\(\s*"[^"]*"\s*,[^,()]*,[^,()]*,\s*"([^"]+)"|CreateFontString\([^,()]*,[^,()]*,\s*"([^"]+)"'
)


def unbuildable(files: list[Path], names: list[str]) -> dict[str, list[str]]:
    """name → the words of it nothing in `files` can build; a name with none is left out. A word is buildable
    when a file holds it, or when it is a buildable word followed by a suffix XML writes after `$parent`
    (`<Button name="$parentCloseButton">` under `JournalFrame` is `JournalFrameCloseButton`). Unlike
    `missing_words` this needs no second client to compare with, so it can judge a name only this client has:
    a word it reports is a typo or a guess."""
    words: set[str] = set()
    suffixes: set[str] = set()
    for path in files:
        text = path.read_text(encoding="utf-8", errors="replace")
        words.update(_WORD.findall(text))
        suffixes.update(_PARENT_SUFFIX.findall(text))
    known: dict[str, bool] = {}

    def buildable(word: str) -> bool:
        if word not in known:
            known[word] = word in words or any(
                len(s) < len(word) and word.endswith(s) and buildable(word[: -len(s)]) for s in suffixes
            )
        return known[word]

    out = {name: [w for w in _WORD.findall(name) if not buildable(w)] for name in names}
    return {name: gone for name, gone in out.items() if gone}


def inherited(code: str) -> list[str]:
    """The frame templates and font objects a file's code (comments stripped) creates its widgets with."""
    groups = (group for m in _INHERITS.finditer(code) for group in m.groups() if group)
    return sorted({t.strip() for group in groups for t in group.split(",")})


def _under(source: Path) -> list[Path]:
    return [p for p in source.rglob("*") if p.is_file()]


def source_hits(source: Path | None, names: list[str], files: list[Path] | None = None) -> dict[str, str]:
    """name → the extracted client file it appears in, or "" when absent. No source dir: {}. `files` narrows
    the search to those files (a game type's load set); without it every file under `source` is read."""
    if source is None:
        return {}
    files = _under(source) if files is None else files
    return _hits(files, *_read(files), names)


def missing_words(files: list[Path], names: list[str]) -> dict[str, list[str]]:
    """name → the words of it that none of `files` holds. A frame's children are named one by one in the
    client's XML (`parentKey="DetailFrame"`), so a dotted name is rarely written out whole and `source_hits`
    cannot say it is gone. A word no loaded file has is the proof: nothing the client loads can build that
    name."""
    return _missing(_read(files)[1], names)


def verdict(entry: dict[str, Any], probe: dict[str, str], hits: dict[str, str],
            asked: dict[str, int] | None = None) -> tuple[str, str]:
    """One of works / names only / rework / unknown, with the evidence that decided it.

    `asked` is the probe's per-surface manual-sweep count. The `lod` tag below only covers a
    surface whose Blizzard addon our own addon names in `LoadOnDemand.when`; a window the client builds
    on first show without one (guild is the open case) carries no tag, so without this its absences
    read as proven even though nobody opened it. Passing `None` (the default, and what an older
    probe file gives) keeps the `lod`-only rule."""
    name = entry.get("name")
    if not name:
        return "unknown", f"dynamic: {entry.get('dynamic', '')}"
    if entry["kind"] == "method":
        # `hooksecurefunc(frame, "Update")`: it exists if the frame does, which the frame's own row answers
        return "unknown", "method hook on a client object; judged by its surface's frames"
    if partial(name):
        where = hits.get(name, "")
        found = f" · source: {where}" if where else " · source: absent" if hits else " · no source"
        return "unknown", "part of a name the surface joins at run time" + found
    answer = probe.get(f"{entry['kind']}|{name}")
    in_source = hits.get(name, "")
    if answer == "yes":
        return "works", "probe: present" + (f" · source: {in_source}" if in_source else "")
    if answer == "no":
        return _absent_verdict(entry, probe, hits, in_source, asked)
    if in_source:
        return "unknown", f"no probe answer · source: {in_source}"
    return "unknown", "no probe answer" + (" · source: absent" if hits else " · no source")


def _absent_verdict(entry: dict[str, Any], probe: dict[str, str], hits: dict[str, str], in_source: str,
                    asked: dict[str, int] | None) -> tuple[str, str]:
    """`verdict` for an entry the probe found absent: whether that absence proves anything."""
    missing_lod = [a for a in entry.get("lod", []) if probe.get(f"loaded|{a}") != "yes"]
    if missing_lod:
        # its Blizzard addon never loaded in the probed session: absence proves nothing
        return "unknown", f"probe: absent, but {', '.join(missing_lod)} was not loaded"
    if asked is not None and not entry.get("windowless") and asked.get(entry["surface"], 0) == 0:
        # nobody ever had this window open while the probe swept: absence proves nothing either.
        # A window-less surface has no window to open; the login sweep is its evidence.
        return "unknown", ("probe: absent, but the " + entry["surface"]
                           + " window was never opened"
                           + (f" · source: still in {in_source}" if in_source else ""))
    if in_source:
        return "names only", f"probe: absent · source: still in {in_source}"
    return "rework", "probe: absent" + (" · source: absent" if hits else "")


def report(manifest: dict[str, Any], probe: dict[str, str], source: Path | None,
           asked: dict[str, int] | None = None, files: list[Path] | None = None,
           reference: list[Path] | None = None) -> dict[str, Any]:
    """`reference` is the files another client loads, the client the addon is known to work on. With it every
    named row gets `lacks`: the words of the name that client's files have and this one's do not, unless this
    client's probe found the name. Words neither client's files have prove nothing (a string table entry, a
    function the client builds in, a frame named by its template), so only the difference counts."""
    names = sorted({e["name"] for e in manifest["entries"] if e.get("name")})
    hits: dict[str, str] = {}
    here: dict[str, list[str]] = {}
    there: dict[str, list[str]] = {}
    if source is not None:
        files = _under(source) if files is None else files
        texts, holders = _read(files)
        hits = _hits(files, texts, holders, names)
        if reference is not None:
            here, there = _missing(holders, names), missing_words(reference, names)
    rows = []
    for e in manifest["entries"]:
        v, why = verdict(e, probe, hits, asked)
        row = {**e, "verdict": v, "evidence": why}
        if hits:
            # the file that has the name, "" when no file read has it, None for an entry with no name
            row["source"] = hits.get(e["name"]) if e.get("name") else None
        if reference is not None:
            name = e.get("name")
            found = probe.get(f"{e['kind']}|{name}") == "yes"
            row["lacks"] = None if not name else (
                [] if found else [w for w in here.get(name, []) if w not in there.get(name, [])])
        rows.append(row)
    unclassified = [r for r in rows if r["verdict"] not in ("works", "names only", "rework", "unknown")]
    if unclassified:
        raise SystemExit(f"client_surface: {len(unclassified)} entries unclassified")
    surfaces = sorted({e["surface"] for e in manifest["entries"] if not e.get("windowless")})
    unopened = [s for s in surfaces if asked is not None and asked.get(s, 0) == 0]
    return {"build": probe.get("build", "unknown"), "rows": rows, "asked": asked, "unopened": unopened}


def by_surface(rows: list[dict[str, Any]], include_suspect: bool = False) -> dict[str, dict[str, int]]:
    """Verdict counts per surface. Suspect `api` matches are left out unless asked for, so the table and the
    headline totals are the same population."""
    out: dict[str, dict[str, int]] = {}
    for r in rows:
        if r.get("suspect") and not include_suspect:
            continue
        out.setdefault(r["surface"], {}).setdefault(r["verdict"], 0)
        out[r["surface"]][r["verdict"]] += 1
    return out


# A pooled frame's debug name carries its address (`b0462b3b0`), which changes every session.
_POOLED = re.compile(r"\b(?=[0-9a-f]*\d)[0-9a-f]{8,}\b")
ALWAYS = "always on screen"
# a window the test asked for and did not get: a line of the result like any other, so the baseline can allow it
# with its reason (a window the test character is too low for)
NOT_OPENED = "(did not open)"
# Japanese on screen in a face with no Japanese letters (drawn as empty boxes): a line of the result too, named by
# its widget, so the baseline can allow one with its reason
BOXES = "(Japanese in a font without it)"
# the face the sweep takes as able to draw Japanese: the addon's bundled one, by file name (its Font.PATH)
JAPANESE_FACE = "ipagui"


def read_window_test(text: str) -> tuple[dict[str, str], set[tuple[str, str]]]:
    """The window test out of a saved-variables file: (when it ran and on which build, the English lines left on
    screen as (window, English)). A live-sweep window is named as the test lists it; a window the open sweep
    showed is `opened <its frame>`. A line on screen with no window open is filed once, under `always on screen`.
    Japanese drawn in a face without it is a line as well: (window, `BOXES <widget>`)."""
    from wfj.io import lua_reader

    db = lua_reader.parse_assignments(text).get("WFJScanDB")
    probe = db.get("probe") if db is not None else None
    if probe is None:
        return {}, set()
    test = probe.get("test").named() if probe.get("test") is not None else {}
    info = {str(k): str(v) for k, v in test.items() if isinstance(v, (str, int, float))}
    found: set[tuple[str, str]] = set()
    live = probe.get("live").named() if probe.get("live") is not None else {}
    idle = live.get("(nothing open)")
    always = idle.get("english").named() if idle is not None and idle.get("english") is not None else {}
    found |= {(ALWAYS, str(en)) for en in always.values()}
    idle_boxes = idle.get("boxes").named() if idle is not None and idle.get("boxes") is not None else {}
    found |= {(ALWAYS, f"{BOXES} {_POOLED.sub('*', str(name))}") for name in idle_boxes}
    for window, record in live.items():
        if window == "(nothing open)":
            continue
        where = _POOLED.sub("*", str(window))
        english, boxes = record.get("english"), record.get("boxes")
        if english is not None:
            found |= {(where, str(en)) for name, en in english.named().items() if name not in always}
        if boxes is not None:
            found |= {(where, f"{BOXES} {_POOLED.sub('*', str(name))}") for name in boxes.named()
                      if name not in idle_boxes}
    unopened = probe.get("test").get("unopened") if probe.get("test") is not None else None
    if unopened is not None:
        found |= {(str(window), NOT_OPENED) for window in unopened.named()}
    opened = probe.get("opened").named() if probe.get("opened") is not None else {}
    for window, record in opened.items():
        still = record.get("still")
        if still is not None:
            found |= {(f"opened {_POOLED.sub('*', str(window))}", str(en)) for en in still.named().values()}
    return info, found


def read_test_problems(text: str, log: str = "") -> list[str]:
    """What went wrong while the window test ran, one line each: the Lua errors and the actions the client refused
    an addon, as the scan addon counted them, and, from the shipped addon's own saved file (`log`), its recorded
    errors and failed load steps since the test started."""
    from wfj.io import lua_reader

    db = lua_reader.parse_assignments(text).get("WFJScanDB")
    probe = db.get("probe") if db is not None else None
    test = probe.get("test") if probe is not None else None
    if test is None:
        return []
    out: list[str] = []
    words = {"errors": "error", "blocked": "refused", "warnings": "warning"}
    for kind, word in words.items():
        table = test.get(kind)
        for message, count in (table.named() if table is not None else {}).items():
            out.append(f"{word} x{count}: {' '.join(str(message).split())}")
    if test.get("handler"):
        # the run could not watch for Lua errors: none recorded proves nothing
        out.append(f"errors not watched: {test.get('handler')}")
    started = str(test.get("started") or "")
    saved = lua_reader.parse_assignments(log).get("WFJ_Log") if log.strip() else None
    if saved is not None and started:
        errors = saved.get("errors")
        for row in (errors.positional() if errors is not None else []):
            if str(row.get("last") or "") >= started:
                out.append(f"addon error x{row.get('n') or 1}: {' '.join(str(row.get('msg')).split())}")
        entries = saved.get("entries")
        for row in (entries.positional() if entries is not None else []):
            if row.get("kind") == "init" and str(row.get("at") or "") >= started:
                out.append(f"addon load step failed: {row.get('msg')}: {' '.join(str(row.get('err')).split())}")
    return sorted(set(out))


def _line(text: str) -> str:
    return text.replace("\\", "\\\\").replace("\t", "\\t").replace("\r", "\\r").replace("\n", "\\n")


def read_window_baseline(text: str) -> dict[tuple[str, str], str]:
    """The English lines a window may keep, with why: `<window>\\t<English>\\t<reason>` per line."""
    out: dict[tuple[str, str], str] = {}
    for n, raw in enumerate(text.splitlines(), 1):
        if not raw.strip() or raw.startswith("#"):
            continue
        parts = raw.split("\t")
        if len(parts) != 3 or not parts[2].strip():
            raise ValueError(f"window baseline line {n}: expected <window> <English> <reason>, tab-separated")
        out[(parts[0], parts[1])] = parts[2].strip()
    return out


def window_test_report(found: set[tuple[str, str]], baseline: dict[tuple[str, str], str]) -> tuple[list[str], list[str]]:
    """(the lines on screen in English that the baseline does not allow, the baseline lines no longer seen), each
    as `<window>\\t<English>`, sorted."""
    seen = {(w, _line(en)) for w, en in found}
    # a line the baseline allows for a window is allowed on every page of it (`<window> > <tab>`)
    allowed = {(w, en) for w, en in seen if (w, en) in baseline or (w.split(" > ")[0], en) in baseline}
    used = {(w.split(" > ")[0], en) for w, en in allowed} | allowed
    return (sorted(f"{w}\t{en}" for w, en in seen - allowed),
            sorted(f"{w}\t{en}" for w, en in set(baseline) - used))


def _loaded(extract: Path, game: str) -> list[Path]:
    """A game type's loaded files, or an exit: an extract with no file loaded is a mistyped path, and as a
    reference it would call every name buildable."""
    files = client_addons.loaded_files(extract, game)
    if not files:
        raise SystemExit(f"client_surface: {game} loads no file under {extract}; is it a client UI extract?")
    return files


def _texts(args: argparse.Namespace) -> int:
    """The `texts` command: the window test's saved result against the baseline. → the exit code."""
    info, found = read_window_test(args.saved.read_text(encoding="utf-8", errors="replace"))
    if not info.get("finished"):
        print("window test: no finished run in the saved file (run /wfjtest, wait for its done line, /reload)")
        return 2
    baseline = read_window_baseline(args.baseline.read_text(encoding="utf-8")) if args.baseline.exists() else {}
    new, gone = window_test_report(found, baseline)
    # a window the open sweep showed did not run the client's opening code, so a surface that works from that
    # code never ran: its English is a list to read against the code, never a failure, like its errors
    bare = [row for row in new if row.startswith("opened ")]
    new = [row for row in new if row not in bare]
    print(f"window test of build {info.get('build')}, run {info.get('started')}: {len(found)} English lines on "
          f"screen, {len(found) - len(new) - len(bare)} allowed by the baseline, {len(new)} new in the windows "
          f"opened the client's way, {len(bare)} to read in windows shown bare")
    for row in new:
        print(f"NEW   {row}")
    for row in bare:
        print(f"read  {row}")
    for row in gone:
        print(f"gone  {row}")
    log = args.log or args.saved.with_name("WoWForeverJapanese.lua")
    problems = read_test_problems(args.saved.read_text(encoding="utf-8", errors="replace"),
                                  log.read_text(encoding="utf-8", errors="replace") if log.exists() else "")
    # the open sweep shows a window without the client's own opening code, so a window that needs data it was
    # never given errors by itself: listed, never a failure. The live sweep opens windows the client's way.
    noted = [row for row in problems if ": [open] " in row]
    failing = [row for row in problems if row not in noted]
    print(f"errors during the run: {len(failing)} (and {len(noted)} from windows shown bare)")
    for row in failing:
        print(f"ERROR {row}")
    for row in noted:
        print(f"noted {row}")
    return 1 if new or failing else 0


def _parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(prog="client_surface", description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build")
    b.add_argument("--addon", required=True, type=Path)
    b.add_argument("--out", required=True, type=Path)
    p = sub.add_parser("probe")
    p.add_argument("--manifest", required=True, type=Path)
    p.add_argument("--out", required=True, type=Path, help="the probe's Lua file, inside the scan dev addon")
    p.add_argument("--walk", action="store_true",
                   help="also load every load-on-demand addon a surface waits for, and record restrictions")
    p.add_argument("--window-test", type=Path, metavar="DATA",
                   help="also carry the window test (/wfjtest) for the interface lines that ship Japanese under this "
                   "data folder; the load-on-demand addons are loaded when the test starts, not at login")
    t = sub.add_parser("texts", help="the window test's result against the baseline: exit 1 on a new English line")
    t.add_argument("--saved", required=True, type=Path, help="the client's WFJScan.lua SavedVariables file")
    t.add_argument("--baseline", required=True, type=Path)
    t.add_argument("--log", type=Path, help="the shipped addon's SavedVariables file, for its recorded errors "
                   "(default: WoWForeverJapanese.lua beside --saved)")
    r = sub.add_parser("report")
    r.add_argument("--manifest", required=True, type=Path)
    r.add_argument("--probe", required=True, type=Path,
                   help="the client's WFJScan.lua SavedVariables file (or an older WFJProbe.lua)")
    r.add_argument("--source", type=Path)
    games = sorted(client_addons.GAMES)
    r.add_argument("--game", choices=games, help="read only the files of --source this game type loads")
    r.add_argument("--reference", type=Path, help="the extract of the client the addon works on")
    r.add_argument("--reference-game", choices=games, help="that client's game type")
    r.add_argument("--out", required=True, type=Path)
    return ap


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    if args.cmd == "texts":
        return _texts(args)
    if args.cmd == "build":
        manifest = build(args.addon)
        args.out.write_text(json.dumps(manifest, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
        print("\n".join(summary(manifest)))
        return 0
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    if args.cmd == "probe":
        args.out.parent.mkdir(parents=True, exist_ok=True)
        english = translated_english(args.window_test) if args.window_test else ()
        text = probe_lua(manifest, walk=args.walk or bool(args.window_test), english=english,
                         at_login=args.walk)
        args.out.write_text(text, encoding="utf-8")
        print(f"probe: {len(probe_names(manifest))} names → {args.out}")
        return 0
    raw = args.probe.read_text(encoding="utf-8", errors="replace")
    answers = read_saved_variables(raw)
    if not answers:
        raise SystemExit(f"client_surface: no probe answers in {args.probe}")
    wanted = {f"{k}|{n}" for k, n in probe_names(manifest)}
    unanswered = sorted(a for a in wanted if a not in answers)
    if unanswered:
        raise SystemExit(
            f"client_surface: {len(unanswered)} of {len(wanted)} names have no answer "
            f"(e.g. {', '.join(x.split('|')[1] for x in unanswered[:3])}); the probe file is from another "
            "manifest or an interrupted run; re-run the probe and try again"
        )
    files = None
    if args.game:
        if args.source is None:
            raise SystemExit("client_surface: --game narrows --source to a game type's files; give --source")
        files = _loaded(args.source, args.game)
    reference = None
    if args.reference:
        if not (args.game and args.reference_game):
            raise SystemExit("client_surface: --reference needs --game and --reference-game")
        reference = _loaded(args.reference, args.reference_game)
    result = report(manifest, answers, args.source, asked_surfaces(raw), files, reference)
    args.out.write_text(json.dumps(result, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    counted = [r for r in result["rows"] if not r.get("suspect")]
    for surface, counts in sorted(by_surface(result["rows"]).items()):
        print(f"{surface}: " + " · ".join(f"{v} {n}" for v, n in sorted(counts.items())))
    totals: dict[str, int] = {}
    for r in counted:
        totals[r["verdict"]] = totals.get(r["verdict"], 0) + 1
    print(f"build {result['build']} · {len(counted)} counted entries "
          f"({len(result['rows']) - len(counted)} suspect held back) · "
          + " · ".join(f"{v} {n}" for v, n in sorted(totals.items())))
    if reference is not None:
        lacking = sorted({r["surface"] for r in result["rows"] if r.get("lacks")})
        print(f"{len(lacking)} surfaces name something this client cannot build: " + " ".join(lacking))
    if result["asked"] is None:
        print("probe predates /wfjprobe: an absence outside a load-on-demand surface is occasion-blind",
              file=sys.stderr)
    elif result["unopened"]:
        print(f"{len(result['unopened'])} surfaces never asked with their window open: "
              + " ".join(result["unopened"]), file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
