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
from collections.abc import Iterable, Mapping, Sequence
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
    code = hashlib.sha256()  # the addon's own code, without its data: what a window's module is built from
    for path in sorted(addon.rglob("*.lua")):
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        code.update(path.relative_to(addon).as_posix().encode("utf-8") + b"\0" + path.read_bytes())
        for entry in scan_file(path, addon, defined):
            key = (entry["kind"], entry["name"], entry["surface"], entry.get("dynamic", ""))
            if key in seen:
                continue
            seen.add(key)
            entries.append(entry)
    return {"addon": addon.name, "entries": entries, "code": code.hexdigest()[:12]}


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
    -- The raid window's own code raises an error outside a raid on every pet and name update once it is loaded
    -- (RaidClassButton_Update; listed in pipeline/ui_test_game_errors.txt). The walk is what loaded it, so the
    -- walk takes those two events off the raid window until the next reload.
    if addon == "Blizzard_RaidUI" and type(RaidFrame) == "table" and not IsInRaid() then
      RaidFrame:UnregisterEvent("UNIT_PET")
      RaidFrame:UnregisterEvent("UNIT_NAME_UPDATE")
      local back = CreateFrame("Frame")
      back:RegisterEvent("GROUP_ROSTER_UPDATE")
      back:SetScript("OnEvent", function(self)
        if not IsInRaid() then return end
        self:UnregisterAllEvents()
        RaidFrame:RegisterEvent("UNIT_PET")
        RaidFrame:RegisterEvent("UNIT_NAME_UPDATE")
      end)
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
-- The dictionary's interface strings by name. The addon reads each one's English from the client to match a line
-- on screen, so a string the client does not hand to addon code can be matched by nothing; the test lists them.
local KEYS = {
%s
}
-- Each spell whose Japanese is filled from the live tooltip, with how many numbers the English it is numbered to
-- prints: the tooltip read checks the client's own line against it.
local VALUES = {
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
-- Forever's group finder is the vanilla-style one: blizzard_groupfinder_vanillastyle.toc:5 allows camelot, and
-- blizzard_groupfinder.toc:10 (the PVEFrame one) excludes it. Its key bindings open a page by number with
-- LFGVanilla_ToggleFrame (blizzard_groupfinder_vanillastyle/bindings.xml:3 the listing, blizzard_framexml/
-- bindings_camelot.xml:1254 the who list), which shows that page (blizzard_lfgvanilla_parentframe.lua:107-150).
-- The side tabs that switch pages are frames with a mouse-up handler (LFGParentFrameRightTabMixin, :92-105 of the
-- same file), not buttons, so the sweep cannot click them: each page is opened by its number instead. The client
-- loads the addon at login (blizzard_game/camelot/eventimplementation.lua:12, blizzard_lfgutil/camelot/
-- lfgutil.lua:1-5); should it not be loaded yet, its own loader is called. [unverified: that an addon may call that
-- loader without the load being refused; the run records the error if it is]
-- An opener's error that starts with this says the window is not there for this player to open: the run names it
-- with the windows this client does not have and does not fail on it. The window is tested whenever it is there.
local NOT_AVAILABLE = "not available: "
local function groupFinder(page)
  return function()
    -- the client's own toggle shows nothing when the client is on another finder or this account or character
    -- may not use this one (blizzard_lfgvanilla_parentframe.lua:135-141): then there is no window to test
    local style = C_LFGList and C_LFGList.GetPremadeGroupFinderStyle and C_LFGList.GetPremadeGroupFinderStyle()
    local may = C_LFGInfo and C_LFGInfo.CanPlayerUsePremadeGroup and C_LFGInfo.CanPlayerUsePremadeGroup()
    local vanilla = Enum and Enum.PremadeGroupFinderStyle and Enum.PremadeGroupFinderStyle.Vanilla
    if may == false or (vanilla ~= nil and style ~= nil and style ~= vanilla) then
      error(NOT_AVAILABLE .. "the group finder (finder style " .. tostring(style) .. ", this character may use it: "
        .. tostring(may) .. ")", 0)
    end
    if not LFGParentFrame then GroupFinderVanillaStyle_LoadUI() end
    LFGVanilla_ToggleFrame(page)
    if LFGParentFrame and LFGParentFrame:IsShown() then return end
    error("the client kept it shut: finder style " .. tostring(style) .. ", this character may use it: "
      .. tostring(may), 0)
  end
end
local LIVE = {
  { "spellbook", spells("ToggleSpellBookFrame") },
  { "achievements", function() ToggleAchievementFrame() end },
  { "map", function() ToggleWorldMap() end },
  { "quest log", function() ToggleQuestLog() end },
  { "collections", function() ToggleCollectionsJournal(1) end },
  { "group finder", groupFinder(1), "GroupFinderVanillaStyle_LoadUI" },
  { "group finder > browse", groupFinder(2), "GroupFinderVanillaStyle_LoadUI" },
  { "group finder > who", groupFinder(3), "GroupFinderVanillaStyle_LoadUI" },
  -- Forever does not load the dungeon journal (blizzard_encounterjournal.toc:7 allows standard and classic only),
  -- so there the opener is missing and the window is named as absent
  { "dungeon journal", function() ToggleEncounterJournal() end, "ToggleEncounterJournal" },
  { "friends", function() ToggleFriendsFrame(1) end },
  { "professions", function() ToggleProfessionsBook() end },
  { "bags", function() ToggleAllBags() end },
  { "calendar", function() ToggleCalendar() end },
  { "help", function() ToggleHelpFrame() end },
}
-- The character window is never opened or closed by the test. Its show script turns on the player frame's health
-- and mana numbers and compares them (CharacterFrameMixin:OnShow, blizzard_uipanels_game/camelot/
-- characterframe.lua:710-729; TextStatusBarMixin:UpdateTextStringWithValues, blizzard_textstatusbar/
-- textstatusbar.lua:110), and those numbers are secret to addon code wherever the client's secret restrictions
-- are on, which on this client is everywhere: opened by an addon it raises an error every time. Its hide script
-- writes the same bars' fields (lua:758-782), so closed by an addon it leaves them tainted for the session. The
-- player opens it instead: the test asks at its end, reads it for as long as it stays open (every page the
-- player shows), and never clicks in it.
local CHARACTER_WAIT, CHARACTER_READ = 30, 0.5 -- seconds to wait for it to open; between two reads of it
local CHARACTER_ASK = 6 -- seconds between two askings
local function characterShown()
  return type(CharacterFrame) == "table" and CharacterFrame:IsShown()
end
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

-- Whether this player has Japanese names on. The setting is read, never written: a run shows what the player sees.
local function namesOn()
  local settings = type(WFJ_DB) == "table" and WFJ_DB.settings
  return type(settings) == "table" and settings["names.japanese"] == true
end

-- With Japanese names on, a game name left in English is a fault, and a name is in no dictionary the sweep
-- holds: the name list is far too long to carry here. So every text on screen that still holds Latin letters is
-- kept under `latin`, by widget, and the result holds each one to the name list when it is read.
local LATIN_MAX, LATIN_CHARS = 400, 200 -- texts kept per read; characters kept of each

-- A unit frame or nameplate of a unit a player controls (a hunter's pet, a guardian): its name is the player's
-- to give, so the addon leaves it as written and the run does not hold it to the name list. A pet that kept the
-- name of the creature it was tamed from reads like a game name and is not one.
local function playersUnit(frame)
  local unit = type(frame) == "table" and (frame.displayedUnit or frame.unit) or nil
  if type(unit) ~= "string" then return false end
  local ok, controlled = pcall(UnitPlayerControlled, unit)
  return ok and controlled == true
end

-- Text on screen that is what a player wrote, never the game's: an action button's name line, which shows only
-- a macro's name (ActionButton's UpdateName: C_ActionBar.GetActionText when UsesActionText, blizzard_actionbar/
-- shared/actionbutton.lua:621-629), and a chat tab whose window the player named: the client names only its first
-- three windows, GENERAL, COMBAT_LOG and VOICE (FCF_ResetChatWindows, blizzard_chatframebase/mainline/
-- floatingchatframe.lua:1865-1873), and asks the player for every other name.
local function playersText(name, plain)
  if name:find("^ActionButton%%d+%%.?Name$") or name:find("^MultiBar.-Button%%d+%%.?Name$") then return true end
  if name:find("^ChatFrame%%d+Tab") then
    return plain ~= GENERAL and plain ~= COMBAT_LOG and plain ~= VOICE
  end
  return false
end

-- Text drawn fully transparent is not on screen: the spellbook's and the professions page's own texts stay as the
-- client wrote them under the addon's Japanese labels. A text region has its own alpha and no effective one (only
-- a frame has GetEffectiveAlpha: blizzard_apidocumentationgenerated/simpleregionapidocumentation.lua:10,
-- simpleframeapidocumentation.lua:366), so its own and its frame's are read.
local function unseen(region)
  if region.GetAlpha and region:GetAlpha() == 0 then return true end
  local parent = region.GetParent and region:GetParent()
  return parent ~= nil and parent.GetEffectiveAlpha ~= nil and parent:GetEffectiveAlpha() == 0
end

local function readScreen()
  -- whether the tooltip on screen is a unit's (the creature or player under the mouse)
  local shows, unit = pcall(function() return GameTooltip:IsShown() and GameTooltip:GetUnit() end)
  local unitTip = shows and unit ~= nil and unit ~= false
  -- a unit's tooltip that is fading out no longer names its unit, and its rows are still on screen: a player's
  -- guild on its second row is no interface line. The tooltip's own data still says what kind it is.
  if not unitTip and type(GameTooltip) == "table" and type(GameTooltip.GetPrimaryTooltipInfo) == "function" then
    local fine, info = pcall(function() return GameTooltip:IsShown() and GameTooltip:GetPrimaryTooltipInfo() end)
    local data = fine and type(info) == "table" and info.tooltipData or nil
    local kinds = type(Enum) == "table" and Enum.TooltipDataType or nil
    unitTip = type(data) == "table" and kinds ~= nil and data.type == kinds.Unit
  end
  local record = { english = {}, japanese = 0, boxes = {} }
  local latin, kept = namesOn() and {} or nil, 0
  record.latin = latin
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
        if region:GetObjectType() == "FontString" and region:IsVisible() and not unseen(region) then
          local plain = plainOf(region)
          local name = tostring(region:GetDebugName())
          if plain and playersText(name, plain) then plain = nil end
          if plain and ENGLISH[plain] then
            -- a name plate shows a creature's name and a unit's tooltip under the mouse shows an NPC's title:
            -- names, which stay English, and never part of the window being read (a mob called "Gold" walking
            -- by is not the word Gold left untranslated). Any other tooltip is the window's own and is read.
            if not name:find("^NamePlate%%d") and not (unitTip and name:find("^GameTooltipText")) then
              record.english[name] = plain
            end
          elseif plain and hasJapanese(plain) then
            record.japanese = record.japanese + 1
            pcall(box, region, plain)
          end
          if latin and plain and kept < LATIN_MAX and not ENGLISH[plain] and plain:find("%%a%%a")
            and not playersUnit(frame) then
            kept = kept + 1
            latin[tostring(region:GetDebugName())] = plain:sub(1, LATIN_CHARS)
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
  "friendslist", "communitieslist", "baganator", "calendarview", "calendarevent", "calendarinvite", "calendarmass",
  "calendartexture", "whoframe", "guildcontrol", "guildinfo", "communitiessettings",
  "titlemanager" }

local ACT = {}
for _, word in ipairs(ACTS) do ACT[word] = true end
-- the group finder's Delist button takes the player's listing down (blizzard_lfgvanilla_browse.lua:1295-1298)
ACT.delist, ACT.unlist = true, true

-- While the player has a group listing up, the listing page's Back button takes it down instead of going back
-- (LFGListingBackButton_OnClick, blizzard_lfgvanilla_listing.lua:703-706), so no button of that page is clicked
-- then. With no listing, Back only clears the page back to its categories.
local function listingUp()
  local ok, up = pcall(function() return C_LFGList.HasActiveEntryInfo() end)
  return ok and up == true
end

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
  if name:find("^LFGListing") and listingUp() then return nil, "a group listing is up: this page changes it" end
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

-- The lists scrollOn moved, back at their first row: the window is left as the player had it.
local function scrollBack(roots)
  local frame = EnumerateFrames()
  while frame do
    pcall(function()
      if frame:IsForbidden() or type(frame.SetScrollPercentage) ~= "function" then return end
      if not tostring(frame:GetDebugName()):find("Categories.ScrollBox$") or not under(frame, roots) then return end
      frame:SetScrollPercentage(0)
    end)
    frame = EnumerateFrames(frame)
  end
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

-- How a tooltip's rows are judged, by the tooltip read below and by the hover read: the same rules for both.
local function readable(text)
  return type(text) == "string" and text ~= "" and not (issecretvalue and issecretvalue(text))
end
-- Latin abbreviations Japanese text keeps as they are, as Japanese players write them
local ABBREVIATIONS = { NPC = true, GM = true, PvP = true, PvE = true, DND = true, CC = true, ID = true,
  WoW = true, HP = true, MP = true, UI = true }
-- markup is no text: colour codes in either case, named colours, textures, atlases, plural groups, and the
-- addon's own markers, whose English half is there on purpose
local function rowPlain(text)
  return (text:gsub("|[cC]%%x%%x%%x%%x%%x%%x%%x%%x", ""):gsub("|[cC][nN][^:]*:", ""):gsub("|[rR]", "")
    :gsub("|T[^|]*|t", ""):gsub("|A[^|]*|a", ""):gsub("|4[^;]*;", ""):gsub("|n", " ")
    :gsub("%%[[^%%]]-/ English Changed%%]", ""):gsub("%%[[^%%]]-/ No Voice Yet%%]", ""))
end
-- A row is judged when it holds a word: not a line the addon marks as not translated (listed elsewhere), and not
-- a developer's own row ("Test Profession [DNT]: …"), which no player is meant to read.
local function judged(plain)
  return plain:find("%%a%%a") ~= nil and not plain:find("Not Translated]", 1, true) and not plain:find("[DNT]", 1, true)
end
-- What a judged row leaves in English, to `found(into, key)`: the whole row under "english" when it holds no
-- Japanese, its digits folded so "Rank 3" and "Rank 4" are one row; else each Latin word in it that is no
-- abbreviation under "runs" (a name the name list has no line for).
local function englishIn(plain, found)
  if not hasJapanese(plain) then
    found("english", (plain:gsub("%%d[%%d%%.,]*", "#"):sub(1, 160)))
    return
  end
  for run in plain:gmatch("%%a[%%a' %%-]*%%a") do
    if not ABBREVIATIONS[run] then found("runs", run) end
  end
end
-- The tooltip's own data, or nil when it has none (a tooltip built line by line from code)
local function tooltipData()
  if type(GameTooltip.GetPrimaryTooltipInfo) ~= "function" then return nil end
  local fine, info = pcall(GameTooltip.GetPrimaryTooltipInfo, GameTooltip)
  local data = fine and type(info) == "table" and info.tooltipData or nil
  return type(data) == "table" and data or nil
end
-- Only the rows the game itself drew: each line of the tooltip's own data carries the row it was drawn on, and a
-- row with no such line was added by another addon (an inventory count, a character's name). → the set of those
-- rows, or nil when the data names none: then every row is the tooltip's own.
local function ownRows(data)
  if type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
  local own = {}
  for _, line in ipairs(data.lines) do
    if type(line.lineIndex) == "number" then own[line.lineIndex] = true end
  end
  return next(own) ~= nil and own or nil
end
-- A tooltip still waiting for the item it names is half drawn (the client's own "Retrieving item information" row
-- stands in for the item's rows): what it shows a moment later is what counts, so its rows are not judged.
local function stillLoading()
  if type(RETRIEVING_ITEM_INFO) ~= "string" then return false end
  for i = 1, GameTooltip:NumLines() do
    local fs = _G["GameTooltipTextLeft" .. i]
    if fs and fs:GetText() == RETRIEVING_ITEM_INFO then return true end
  end
  return false
end

-- The hover read. A window's list rows and labels raise tooltips of their own when the mouse is on them (a guild
-- member's zone, a calendar day's events, a friend's details, a listing's collapsed line), and no click and no
-- screen read shows one. While a window is open, every frame of it on screen that takes the mouse and has an
-- enter script is pointed at the way the client does it: its enter script runs, the tooltip is read on the next
-- frame (an addon may finish it on the frame it shows) by the tooltip read's rules, then its leave script runs and
-- the tooltip is hidden. Never in a fight: one that starts stops the window's hovering, and the run says so.
-- Never a protected frame, a secure template, an action button, or a widget whose text the client protects (the
-- same widgets the result counts and never fails: the spellbook, the map's top bar). Each window's English rows
-- and English words inside Japanese rows are kept under `probe.hover[<window>]`, each with the frame it came from
-- and the row as written, with how many frames were pointed at (`made`), found and not pointed at (`skipped`:
-- past the cap, or gone before their turn) and left alone (`denied`).
local hoverBegin, hoverStep
do
  local HOVER_MAX = 60 -- frames pointed at per window, over all its pages
  local HOVER_MS = 6 -- milliseconds of hovering per frame: one frame's enter script and read stay well inside it
  local HOVER_ROWS_MAX = 3000 -- rows and words kept over the whole run
  local HOVER_TEXTS = 24 -- texts of a frame and its children held against its tooltip's rows
  local HOVER_DENY = { "^PlayerSpellsFrame%%.SpellBookFrame", "^SpellBookFrame", "NavBar", "^WorldMapFrameText$",
    "ActionButton", "MultiBar", "^ChatFrame", "Tooltip" }
  -- the window being hovered: its name, its record, what is queued, the frame whose tooltip is up, and the
  -- entries already found in it (a list draws one entry in one row now and another later)
  local at = { queue = {}, kept = 0 }

  local function mouseOn(frame)
    if type(frame.IsMouseMotionEnabled) == "function" then return frame:IsMouseMotionEnabled() end
    return type(frame.IsMouseEnabled) == "function" and frame:IsMouseEnabled()
  end

  -- The loaded addons that are not the client's own (a bag addon that replaces the bags, an action bar addon):
  -- their windows are theirs, not the client's, and their words are no text this addon translates. A frame is
  -- theirs when its name starts with the addon's name ("Baganator_SingleViewBackpackViewFrame…").
  local others
  local function otherAddons()
    if others then return others end
    others = {}
    local C = type(C_AddOns) == "table" and C_AddOns or nil
    local count = C and C.GetNumAddOns and C.GetNumAddOns() or 0
    for i = 1, count do
      local name = C.GetAddOnInfo(i)
      local loaded = C.IsAddOnLoaded and C.IsAddOnLoaded(i)
      if type(name) == "string" and loaded and not name:find("^Blizzard_") and name ~= "WoWForeverJapanese"
          and not name:find("^WoWForeverJapanese_") and name ~= "WFJScan" and #name >= 4 then
        others[#others + 1] = name
      end
    end
    return others
  end

  -- → why a frame is never pointed at, or nil
  local function denied(frame, name)
    if frame:IsProtected() then return "protected" end
    for _, addon in ipairs(otherAddons()) do
      if name:sub(1, #addon) == addon then return "another addon's window" end
    end
    for _, pattern in ipairs(HOVER_DENY) do
      if name:find(pattern) then return pattern end
    end
    if frame.action ~= nil then return "an action button" end
    -- a secure template is set up by its attributes: what it does on a click or for a unit
    for _, key in ipairs({ "type", "type1", "unit", "_onenter", "_onleave" }) do
      local ok, value = pcall(frame.GetAttribute, frame, key)
      if ok and value ~= nil then return "a secure template" end
    end
    return nil
  end

  -- What a frame shows itself, and its children: a row's player name, note or guild rank. A tooltip row that
  -- repeats it is the row's own data, which a player typed or a name the screen read holds to its rules already;
  -- what stands around it in the row (a label like "Note:") is still read. Longest first.
  local function ownTexts(frame)
    local texts = {}
    local function from(f)
      for _, region in ipairs({ f:GetRegions() }) do
        if #texts < HOVER_TEXTS and region:GetObjectType() == "FontString" and readable(region:GetText()) then
          texts[#texts + 1] = rowPlain(region:GetText())
        end
      end
      local ok, text = pcall(function() return f:GetText() end)
      if ok and readable(text) and #texts < HOVER_TEXTS then texts[#texts + 1] = rowPlain(text) end
    end
    pcall(from, frame)
    for _, child in ipairs({ frame:GetChildren() }) do pcall(from, child) end
    table.sort(texts, function(a, b) return #a > #b end)
    return texts
  end
  -- The names of the player's friends, as the friends list's tooltips write them: a friend's character name,
  -- account name and BattleTag are what players chose, never text this addon translates.
  local function friendNames()
    local names = {}
    local F = type(C_FriendList) == "table" and C_FriendList or nil
    for i = 1, F and F.GetNumFriends and F.GetNumFriends() or 0 do
      local info = F.GetFriendInfoByIndex(i)
      if type(info) == "table" and readable(info.name) then names[#names + 1] = (info.name:gsub("%%-.*$", "")) end
    end
    local B = type(C_BattleNet) == "table" and C_BattleNet or nil
    local count = type(BNGetNumFriends) == "function" and BNGetNumFriends() or 0
    for i = 1, B and B.GetFriendAccountInfo and count or 0 do
      local info = B.GetFriendAccountInfo(i)
      if type(info) == "table" then
        for _, v in ipairs({ info.accountName, info.battleTag and (info.battleTag:gsub("#%%d+$", "")) or nil,
            info.gameAccountInfo and info.gameAccountInfo.characterName or nil }) do
          if readable(v) then names[#names + 1] = v end
        end
      end
    end
    return names
  end

  -- What the player's guild wrote and is: its members' names, its rank names and the members' notes, as the
  -- roster's tooltips write them. A guild sets its rank names itself ("Initiate", "Veteran"), so none of it is
  -- text this addon translates. [verified: blizzard_communities/communitiesmemberlist.lua:1184-1211, the roster
  -- entry's tooltip: name, rank, level line, zone, note]
  local function guildTexts()
    local texts = {}
    local count = type(GetNumGuildMembers) == "function" and GetNumGuildMembers() or 0
    for i = 1, math.min(count or 0, 1000) do
      local name, rank, _, _, _, _, note, officerNote = GetGuildRosterInfo(i)
      for _, v in ipairs({ type(name) == "string" and (name:gsub("%%-.*$", "")) or nil, rank, note, officerNote }) do
        if readable(v) then texts[#texts + 1] = v end
      end
    end
    for i = 1, type(GuildControlGetNumRanks) == "function" and GuildControlGetNumRanks() or 0 do
      local rank = GuildControlGetRankName(i)
      if readable(rank) then texts[#texts + 1] = rank end
    end
    return texts
  end

  local function without(plain, texts)
    for _, text in ipairs(texts) do
      if #text >= 2 then
        local s, e = plain:find(text, 1, true)
        while s do
          plain = plain:sub(1, s - 1) .. plain:sub(e + 1)
          s, e = plain:find(text, 1, true)
        end
      end
    end
    return (plain:gsub("^%%s+", ""):gsub("%%s+$", ""))
  end

  -- the client's own way to run a frame's script (its errors reach the error handler, so the run records them),
  -- or the script itself where the client has no such function
  local function run(frame, script)
    local test = type(probeDb().test) == "table" and probeDb().test or nil
    local was = test and test.part
    if test then test.part = "hover" end
    if type(ExecuteFrameScript) == "function" then
      pcall(ExecuteFrameScript, frame, script, true)
    else
      local handler = frame:GetScript(script)
      if handler then pcall(handler, frame, true) end
    end
    if test then test.part = was end
  end

  local function read(rec, frame)
    if not GameTooltip:IsShown() or GameTooltip:NumLines() == 0 then return end
    local data = tooltipData()
    local kinds = type(Enum) == "table" and Enum.TooltipDataType or nil
    local okUnit, _, unit = pcall(GameTooltip.GetUnit, GameTooltip)
    -- a unit's tooltip names a player and their guild: what players chose, never interface text
    if (okUnit and unit) or (data and kinds and data.type == kinds.Unit) then
      rec.units = rec.units + 1
      return
    end
    if stillLoading() then
      rec.loading = rec.loading + 1
      return
    end
    rec.tips = rec.tips + 1
    local own, texts = ownRows(data), ownTexts(frame)
    for _, name in ipairs(friendNames()) do texts[#texts + 1] = name end
    for _, text in ipairs(guildTexts()) do texts[#texts + 1] = text end
    table.sort(texts, function(a, b) return #a > #b end)
    local name = unaddressed(tostring(frame:GetDebugName()))
    for i = 1, GameTooltip:NumLines() do
      for _, side in ipairs({ "Left", "Right" }) do
        local fs = _G["GameTooltipText" .. side .. i]
        local text = (not own or own[i]) and fs and fs:IsShown() and fs:GetText()
        if readable(text) then
          local plain = without(rowPlain(text), texts)
          if judged(plain) then
            englishIn(plain, function(into, key)
              local seen = rec[into][key]
              if seen then
                seen.n = seen.n + 1
              elseif at.kept < HOVER_ROWS_MAX then
                at.kept = at.kept + 1
                rec[into][key] = { n = 1, frame = name, row = i .. " " .. side,
                  raw = text:gsub("|", "||"):gsub("%%c", " "):sub(1, 200) }
              end
            end)
          end
        end
      end
    end
  end

  local function leave(frame)
    run(frame, "OnLeave")
    pcall(GameTooltip.Hide, GameTooltip)
  end

  -- A fight started: nothing more is pointed at in this window, the tooltip up is put away, and the run says so
  -- (in chat now, and in the result, which fails on it). → false, nothing more to do.
  local function stop()
    if at.pending then leave(at.pending) end
    at.pending, at.queue = nil, {}
    if not at.rec.stopped then
      at.rec.stopped = "a fight started"
      print("WFJ test: a fight started, so hovering stopped in the " .. tostring(at.window) .. " window")
    end
    return false
  end

  -- The frames of the open window (under `roots`) not found before, queued one kind at a time in turn, so a long
  -- list of like rows does not take every hover the window has. → true when there is hovering to do.
  function hoverBegin(window, roots)
    local db = probeDb()
    db.hover = db.hover or {}
    if at.db ~= db.hover then -- a new run: nothing of the last one carries over
      if at.pending then leave(at.pending) end
      at.db, at.kept, at.rec, at.pending, at.queue = db.hover, 0, nil, nil, {}
    end
    local rec = db.hover[window]
    if not rec then
      rec = { made = 0, found = 0, skipped = 0, denied = 0, tips = 0, units = 0, loading = 0, english = {}, runs = {} }
      db.hover[window] = rec
    end
    if at.rec ~= rec then
      if at.pending then leave(at.pending) end
      at.rec, at.window, at.queue, at.seen, at.pending = rec, window, {}, {}, nil
    end
    if rec.stopped then return false end
    if InCombatLockdown() then return stop() end
    -- past the cap the window's further pages are not searched (a search reads every frame of the client): the
    -- result says the cap was reached, and `skipped` counts only what was found before it
    if rec.made >= HOVER_MAX then
      rec.capped = true
      return false
    end
    local kinds, order = {}, {}
    local frame = EnumerateFrames()
    while frame do
      pcall(function()
        -- the cheap questions first: nearly every frame of the client is not on screen, or takes no mouse
        if frame:IsForbidden() or not frame:IsVisible() or not frame:GetScript("OnEnter") or not mouseOn(frame) then
          return
        end
        if not under(frame, roots) then return end
        local name = tostring(frame:GetDebugName())
        local key = unaddressed(name) .. "|" .. table.concat(ownTexts(frame), "|")
        if at.seen[key] then return end
        at.seen[key] = true
        if denied(frame, name) then
          rec.denied = rec.denied + 1
          return
        end
        rec.found = rec.found + 1
        local kind = unaddressed(name):gsub("%%d+", "#")
        if not kinds[kind] then
          kinds[kind] = {}
          order[#order + 1] = kind
        end
        table.insert(kinds[kind], frame)
      end)
      frame = EnumerateFrames(frame)
    end
    for round = 1, math.huge do
      local any = false
      for _, kind in ipairs(order) do
        if kinds[kind][round] then
          at.queue[#at.queue + 1] = kinds[kind][round]
          any = true
        end
      end
      if not any then break end
    end
    rec.skipped = rec.found - rec.made
    return at.queue[1] ~= nil and rec.made < HOVER_MAX
  end

  -- One step, once a frame: the tooltip raised on the last frame is read and put away, then (unless `settleOnly`)
  -- the next frame is pointed at. → true while the window's hovering goes on.
  function hoverStep(settleOnly)
    local rec = at.rec
    if not rec or (not at.pending and not at.queue[1]) then return false end
    if InCombatLockdown() then return stop() end
    local t0 = debugprofilestop()
    if at.pending then
      local frame = at.pending
      at.pending = nil
      pcall(read, rec, frame)
      leave(frame)
    end
    while not settleOnly and at.queue[1] and rec.made < HOVER_MAX and debugprofilestop() - t0 < HOVER_MS do
      local frame = table.remove(at.queue, 1)
      local ok, still = pcall(function() return frame:IsVisible() and not frame:IsProtected() end)
      if ok and still then
        pcall(GameTooltip.Hide, GameTooltip) -- what is up then is this frame's tooltip
        rec.made = rec.made + 1
        run(frame, "OnEnter")
        at.pending = frame
        break
      end
    end
    rec.skipped = rec.found - rec.made
    if rec.made >= HOVER_MAX and at.queue[1] then
      rec.capped = true
      at.queue = {}
    end
    return at.pending ~= nil or (not settleOnly and at.queue[1] ~= nil)
  end
end

local TAB_TICKS, MAX_PAGES = 15, 150

local tested = {} -- the top-level frames of the windows the live sweep opened

-- The friends window must still hold the player's friends. An addon that runs code while the client builds the
-- list can leave it empty with no error at all (the client withholds Battle.net data from addon code), so errors
-- alone prove nothing here: the friends the client counts are held against the friend cards it drew. A count
-- that may not be read is written down as such, never taken as zero.
local function friendsDrawn(roots)
  local function count(fn)
    local ok, n = pcall(fn)
    if not ok then return "no such call" end
    if issecretvalue and issecretvalue(n) then return "secret" end
    return tonumber(n) or "none"
  end
  local out = {
    battlenet = count(function() return (BNGetNumFriends()) end),
    game = count(function() return C_FriendList.GetNumFriends() end),
    listed = count(function() return SocialUIFrame.FriendsList.ScrollBox:GetDataProviderSize() end),
    drawn = 0,
  }
  local frame = EnumerateFrames()
  while frame do
    pcall(function()
      -- a friend card is a row with a FriendName line (FriendsListSocialCardTemplate)
      if not frame:IsForbidden() and frame:IsVisible() and type(frame.FriendName) == "table" and under(frame, roots) then
        out.drawn = out.drawn + 1
      end
    end)
    frame = EnumerateFrames(frame)
  end
  return out
end

local function WFJScanLiveSweep(done)
  if not japaneseOn() then return end
  if InCombatLockdown() then
    print("WFJ probe: the live sweep does not run in combat")
    return
  end
  local db = probeDb()
  db.live = { ["(nothing open)"] = readScreen() }
  db.hover = {}
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
    -- a page read, its frames are pointed at before the next click; hoverStep itself stops for a fight
    if state == "hover" then
      if hoverStep() then return end
      state, ticks = "tabs", TAB_TICKS
    end
    if InCombatLockdown() then return end
    ticks = ticks + 1
    if state == "open" then
      if ticks < OPEN_TICKS then return end
      record(window)
      roots = {}
      for frame in pairs(rootsOnScreen()) do
        if not idleRoots[frame] then
          roots[frame] = true
          tested[frame] = true
        end
      end
      db.test.buttons = db.test.buttons or {}
      db.test.buttons[window] = listButtons(roots)
      if window == "friends" and type(SocialUIFrame) == "table" and roots[SocialUIFrame] then
        db.test.friends = friendsDrawn(roots)
      end
      if next(roots) == nil then
        db.test.unopened = db.test.unopened or {}
        db.test.unopened[window] = "the toggle opened nothing"
      end
      queue, seen, scrolls, queued, clicks = {}, {}, 0, {}, 0
      for tab in pairs(idle) do seen[tab] = true end
      moreTabs()
      state, ticks = "tabs", TAB_TICKS
      if hoverBegin(window, roots) then state = "hover" end
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
        if hoverBegin(window, roots) then
          state = "hover"
          return
        end
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
      if scrolls > 0 then scrollBack(roots) end
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
    if LIVE[at][3] and _G[LIVE[at][3]] == nil then -- a window this client does not have: said, not failed
      db.test.absent = (db.test.absent and db.test.absent .. ", " or "") .. window
      return
    end
    local ok, err = pcall(LIVE[at][2])
    if ok then
      state = "open"
    elseif tostring(err):sub(1, #NOT_AVAILABLE) == NOT_AVAILABLE then
      -- not there for this player: named, not failed, and tested again on a player who has it
      db.test.absent = (db.test.absent and db.test.absent .. ", " or "") .. window
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

-- The closed-window read: every text region that is not on screen, in a window the live sweep did not open, that
-- holds an English line the dictionary has Japanese for, filed under its window (`probe.closed`). Nothing is
-- shown: a window shown bare runs its scripts with none of the data the client gives it, and each raises an error
-- (and can taint the frames it touches) on the character the test runs on. So this reads what a window was built
-- with and misses what it writes only when it opens; like the open sweep's list it is read against the code,
-- never a failure (a surface that works from the window's opening code has not run).
local closedReader = CreateFrame("Frame")
local function WFJScanClosedRead(done)
  local db = probeDb()
  db.closed = {}
  local frame = EnumerateFrames()
  closedReader:SetScript("OnUpdate", function()
    for _ = 1, PER_TICK do
      if not frame then
        closedReader:SetScript("OnUpdate", nil)
        return done()
      end
      pcall(function()
        if frame:IsForbidden() then return end
        for _, region in ipairs({ frame:GetRegions() }) do
          if region:GetObjectType() == "FontString" and not region:IsVisible() then
            local plain = plainOf(region)
            local top = plain and ENGLISH[plain] and windowOf(region)
            if top and not tested[top] then
              local name = tostring(top:GetDebugName())
              db.closed[name] = db.closed[name] or {}
              db.closed[name][tostring(region:GetDebugName())] = plain
            end
          end
        end
      end)
      frame = EnumerateFrames(frame)
    end
  end)
end

-- The English Collector records each tooltip line the addon leaves English, as English waiting for a translation.
-- The tooltip read and the names read show thousands of tooltips no player asked for, so the Collector is paused
-- while they run and the player's own value is put back after, also when a read ends early. The addon reads the
-- setting from its saved table each time it records (Settings.get, Core/Settings.lua), and this setting has no
-- step that runs when it changes, so writing it there pauses it at once. The value it had is kept in this addon's
-- saved table as well: a logout or reload puts it back before the game saves, and after a crash mid-read the next
-- login puts it back.
local COLLECTOR = "collector.enabled"
local function addonSettings()
  local settings = type(WFJ_DB) == "table" and WFJ_DB.settings
  return type(settings) == "table" and settings or nil
end
local function probeRecord()
  local db = type(WFJScanDB) == "table" and WFJScanDB.probe
  return type(db) == "table" and db or nil
end
local function resumeCollector()
  local db, settings = probeRecord(), addonSettings()
  if not db or type(db.collectorPaused) ~= "table" then return end
  if settings then settings[COLLECTOR] = db.collectorPaused.was end
  db.collectorPaused = nil
end
-- → `done`, to be called when the read ends: the Collector stays paused until then
local function collectorPaused(done)
  local db, settings = probeRecord(), addonSettings()
  if db and settings and type(db.collectorPaused) ~= "table" then
    db.collectorPaused = { was = settings[COLLECTOR] }
    settings[COLLECTOR] = false
  end
  return function(...)
    resumeCollector()
    return done(...)
  end
end
local collectorGuard = CreateFrame("Frame")
collectorGuard:RegisterEvent("PLAYER_LOGIN")
collectorGuard:RegisterEvent("PLAYER_LOGOUT")
collectorGuard:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" or event == "PLAYER_LOGOUT" then resumeCollector() end
end)

-- The tooltip read. No sweep above opens a tooltip, so a tooltip whose numbers sat in the wrong places, or whose
-- flavour line was written over its use line, was seen by no run. This shows the tooltip of every spell in
-- `VALUES` and of every item the character wears or carries, the way the client shows them, and reads each
-- against the client's own tooltip data (which the addon never changes), into `probe.tooltips`:
--   wrong      a spell shown in Japanese although its line holds another count of numbers than the Japanese is
--              numbered to: every later number is in the wrong place. A failure.
--   changed    a spell left English because of that: the game changed its tooltip and the Japanese is to follow
--   folded     an item whose one Japanese paragraph stands for several of its lines, the others blanked
--   left       every spell left English, with the reason the addon's gate gives (see leftWhy) and its line
--   leftItems  every item with one of its own lines left as the client wrote it, with that line
--   icons      every spell whose Japanese holds an icon slot: whether the client's line and the row shown carry
--              an icon escape, and whether the addon showed Japanese
-- A spell whose text the client has not loaded yet is not read, and counted. The Collector is paused meanwhile.
local TOOLTIP_MS = 8 -- per frame
local STACK_KEPT = 1800 -- characters of an error's call stack the result keeps
local TOOLTIP_SAY = 3000 -- spells between two progress lines
local TOOLTIP_FLIGHT = 40 -- spells waited for at once
local TOOLTIP_PATIENCE = 4 -- seconds one spell's text is waited for
local TOOLTIP_PROOF = 400 -- spells given up on, with none read, after which the read stops
local tooltipReader = CreateFrame("Frame")

-- how many values the addon reads off a line (Core/Align.values): icons out, digit runs with their points and
-- commas, none glued to a Latin letter, "A to B" one value
local function valueCount(text)
  text = text:gsub("||", "\\1"):gsub("|T[^|]*|t", " ")
  local n, last = 0, nil
  for s, tok, e in text:gmatch("()([%%d%%.,]+)()") do
    if tok:find("%%d") and not text:sub(s - 1, s - 1):find("%%a") and not text:sub(e, e):find("%%a") then
      if not (last and text:sub(last, s - 1) == " to ") then n = n + 1 end
      last = e
    end
  end
  return n
end

local function shownRow(i)
  local region = _G["GameTooltipTextLeft" .. i]
  local text = region and region:GetText()
  if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return nil end
  return text
end

-- Why the addon left a spell's line English although its Japanese ships, decided by the addon's own gate (the copy
-- of Core/Align.lua at the top of this file, `ShippedAlign`), step by step in the order Align.check runs, on the
-- Japanese the addon ships (`SHIPPED`). → reason, what was seen. The reasons:
--   hole    the client printed a gap of its own, for a spell the character does not know: an included text as
--           "<digits>". Not a fault.
--   words   the client wrote words where a duration goes ("until canceled") and the Japanese around that slot
--           cannot take them
--   values  the live line holds another count of numbers than the Japanese is numbered to
--   icon    the Japanese holds an icon slot ($I<k>) and the live line has no icon escape to fill it
--   name    the Japanese holds a Latin word the live line lacks
--   number  a number in the filled Japanese is not in the live line
--   none    no Japanese ships for it
--   other   none of these: a placeholder with no value, or the gate's checks pass on this line
-- The addon renders a duration through its interface strings, which this addon does not carry. A stand-in takes a
-- number followed by time units as a duration, so a duration decides no reason here.
local UNITS = { sec = true, secs = true, second = true, seconds = true, min = true, mins = true, minute = true,
  minutes = true, hr = true, hrs = true, hour = true, hours = true, day = true, days = true }
local function anyDuration(phrase)
  if phrase:find("|4", 1, true) then return phrase end -- the client's plural code: "1 |4hour:hrs;"
  local words = 0
  for word in phrase:gmatch("%%a+") do
    if not UNITS[word:lower()] then return nil end
    words = words + 1
  end
  return words > 0 and phrase or nil
end

-- The duration reader the gate copy is given: a number with time units, and the words the client prints where
-- it has no duration ("until canceled") with the Japanese the addon puts there.
local function spellDuration()
  local worded = type(SPELL_DURATION_UNTIL_CANCELLED) == "string" and SPELL_DURATION_UNTIL_CANCELLED or nil
  return { render = anyDuration, words = worded and { { en = worded, ja = "解除されるまで" } } or {} }
end

-- Whether the live line holds the count of values the Japanese is numbered to, read the way the addon's gate
-- reads it: a worded duration takes a value's place, a number glued to a word is read when the plain reading
-- misses the count, and a granted ability's heading is held to the heading's own count. → true | false
local function gateCount(id, english)
  local A = ShippedAlign
  local shipped = type(SHIPPED) == "table" and SHIPPED[id]
  if type(A) ~= "table" or type(A.values) ~= "function" or not shipped then
    return valueCount(english) == VALUES[id]
  end
  local ja, duration = shipped[1], spellDuration()
  local plain = A.textures(english)
  if type(A.grantedHead) == "function" then
    local head, count = A.grantedHead(ja, english)
    if head then return count == nil or #A.values(plain, duration) == count end
  end
  local words = ja:find("%%$D%%d") and duration or nil
  return #A.values(plain, words) == VALUES[id] or #A.values(plain, words, true) == VALUES[id]
end

local function leftWhy(id, english)
  local shipped = type(SHIPPED) == "table" and SHIPPED[id]
  if not shipped then return "none", "no Japanese ships for it" end
  local ja = shipped[1]
  if english:find("<%%d+>") then
    return "hole", "the client printed a gap for a spell this character does not know"
  end
  local A = ShippedAlign
  if type(A) ~= "table" then return "other", "this test addon carries no copy of the gate" end
  local scope = english
  local head, tail = A.splitTail(ja, scope)
  if head == nil then return "other", "the line's list of names is laid out another way" end
  if tail then ja, scope = head, tail.scope end
  local plain, icons = A.textures(scope)
  -- the words the client prints where it has no duration count as that duration, as in the addon
  local duration = spellDuration()
  local worded = duration.words[1] and duration.words[1].en or nil
  local values = A.values(plain, duration)
  if VALUES[id] and #values ~= VALUES[id] then
    return "values", VALUES[id] .. " numbers in the Japanese, " .. #values .. " on this client"
  end
  for k in ja:gmatch("%%$I(%%d+)") do
    if not icons[tonumber(k)] then
      return "icon", "icon slot " .. k .. ", and the live line has " .. #icons .. " icons"
    end
  end
  local text = A.fill(ja, values, A.durations(plain, duration), icons)
  if not text then
    if worded and plain:find(worded, 1, true) then
      return "words", "the client wrote words where a duration goes, and the Japanese there cannot take them"
    end
    return "other", "a placeholder has no value in the live line"
  end
  if shipped[2] == "." then return "other", "a trusted line, and its values fill" end
  local checked = A.textures(text)
  local names = A.checkNames(checked, plain)
  if #names > 0 then return "name", table.concat(names, ", ") end
  local numbers = A.checkNumbers(checked, plain, values)
  if #numbers > 0 then return "number", table.concat(numbers, ", ") end
  return "other", "the gate's checks pass on this line"
end

local function iconIn(text)
  return type(text) == "string" and text:gsub("||", ""):find("|T[^|]*|t") ~= nil
end

-- A spell's line after its tooltip was shown: the icon facts for a Japanese with an icon slot, and, when the addon
-- left it English, why. The rune spells' Japanese asks for an icon, and whether the client's line carries one is
-- not known: `icons` answers it.
local TRACES_KEPT, TRACE_CHARS, TRACE_PASSES = 60, 3000, 5
-- The last few passes of the addon's own tooltip trace, oldest first: the pass that read this tooltip and what
-- it rendered sit just before the calls it made afterwards.
local function lastPasses()
  local trace = type(WFJ_DB) == "table" and WFJ_DB.tooltipTrace
  if type(trace) ~= "table" or #trace == 0 then return "the addon's trace holds no pass at all" end
  local out = {}
  for i = math.max(1, #trace - TRACE_PASSES + 1), #trace do out[#out + 1] = tostring(trace[i]) end
  return table.concat(out, "\\n"):sub(-TRACE_CHARS)
end
-- The tooltip's own data, line by line: each line's type, the row it was drawn on, and for a nested block the
-- id and kind of what it holds. Where a row's text comes from is in here and nowhere else.
local function dataLines()
  if type(GameTooltip.GetPrimaryTooltipInfo) ~= "function" then return "no tooltip data on this client" end
  local fine, info = pcall(GameTooltip.GetPrimaryTooltipInfo, GameTooltip)
  local data = fine and type(info) == "table" and info.tooltipData or nil
  if type(data) ~= "table" or type(data.lines) ~= "table" then return "no tooltip data for this tooltip" end
  local out = {}
  for i, line in ipairs(data.lines) do
    out[#out + 1] = i .. ":type " .. tostring(line.type) .. " row " .. tostring(line.lineIndex)
      .. (line.tooltipID and (" id " .. tostring(line.tooltipID) .. " kind " .. tostring(line.tooltipType)) or "")
  end
  return table.concat(out, ", ")
end
-- A spell left English because its line holds another count of numbers than the Japanese, whose English splices in
-- other spells' text (`WFJScanIncludes`): its whole line, and how the client held each spell it splices in when
-- the line was read (that spell's data loaded, the character knows it, the text the client gives for it). Those
-- spells are then asked for, and the line is read again at the end of the tooltip read (`recheckIncluded`), so
-- one run says whether a spliced-in spell the client had not loaded is what took the numbers out.
local function includedState(sid)
  local cached = type(C_Spell) == "table" and type(C_Spell.IsSpellDataCached) == "function"
    and C_Spell.IsSpellDataCached(sid)
  local known = type(IsPlayerSpell) == "function" and IsPlayerSpell(sid)
  local describe = type(C_Spell) == "table" and C_Spell.GetSpellDescription or GetSpellDescription
  local fine, text = pcall(describe, sid)
  local said = fine and readable(text) and text:gsub("%%s+", " "):sub(1, 200) or "(no text)"
  return "loaded " .. tostring(cached) .. ", known " .. tostring(known) .. ", text: " .. said
end

local function noteIncluded(record, id, english)
  local entry = record.left[tostring(id)]
  entry.text = english:sub(1, TRACE_CHARS)
  local ids = type(WFJScanIncludes) == "table" and WFJScanIncludes[id]
  if type(ids) ~= "table" then return end
  record.spliced = record.spliced or {}
  record.spliced[tostring(id)] = entry
  entry.included = {}
  for _, sid in ipairs(ids) do
    entry.included[tostring(sid)] = includedState(sid)
    if type(C_Spell) == "table" and type(C_Spell.RequestLoadSpellData) == "function" then
      pcall(C_Spell.RequestLoadSpellData, sid)
    end
  end
  record.recheck = record.recheck or {}
  record.recheck[#record.recheck + 1] = id
end

-- The description row of the spell the tooltip shows, from the tooltip's own data, and what it says now: whether
-- the addon showed Japanese there, and how many numbers the client's line for the spell holds.
local function shownState(id)
  local row
  local kinds = type(Enum) == "table" and Enum.TooltipDataLineType or nil
  if kinds and type(GameTooltip.GetPrimaryTooltipInfo) == "function" then
    local fine, info = pcall(GameTooltip.GetPrimaryTooltipInfo, GameTooltip)
    local data = fine and type(info) == "table" and info.tooltipData or nil
    for _, line in ipairs(type(data) == "table" and type(data.lines) == "table" and data.lines or {}) do
      if line.type == kinds.SpellDescription and type(line.lineIndex) == "number" then row = line.lineIndex end
    end
  end
  local shown = row and shownRow(row)
  local japanese = hasJapanese(shown) and not tostring(shown):find("Not Translated]", 1, true)
  local describe = type(C_Spell) == "table" and C_Spell.GetSpellDescription or GetSpellDescription
  local fine, text = pcall(describe, id)
  local live = fine and readable(text) and valueCount(text) or "no"
  return (japanese and "Japanese" or "English") .. ", the client's line holds " .. tostring(live) .. " numbers"
end

-- The spells `noteIncluded` kept, at the end of the tooltip read, one at a time: shown cold (the addon asks for the
-- spliced-in spells the client has not loaded), the same tooltip again once they loaded without showing it again
-- (whether the client redrew it by itself), then shown again; with how the client holds each spliced-in spell by
-- then. The tooltip is put off the screen meanwhile: it stays open while the spells load, and `ANCHOR_NONE` keeps
-- the place the game last gave it.
local RECHECK_POLL, RECHECK_REDRAW = 0.1, 0.5 -- seconds between looks while the spells load; then for the redraw
local function allCached(id)
  local cached = type(C_Spell) == "table" and C_Spell.IsSpellDataCached
  if type(cached) ~= "function" then return true end
  for _, sid in ipairs(WFJScanIncludes[id]) do
    if not cached(sid) then return false end
  end
  return true
end

local function recheckIncluded(record, done)
  local ids = record.recheck
  if type(ids) ~= "table" or #ids == 0 or type(C_Timer) ~= "table" then return done() end
  local function show(id)
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", -200, -200)
    GameTooltip:SetSpellByID(id)
  end
  local at = 0
  local function nextSpell()
    at = at + 1
    local id = ids[at]
    if not id then
      GameTooltip:Hide()
      return done()
    end
    local entry = record.left[tostring(id)]
    show(id)
    entry.cold = shownState(id)
    local waited = 0
    local function look()
      if not allCached(id) and waited < TOOLTIP_PATIENCE then
        waited = waited + RECHECK_POLL
        return C_Timer.After(RECHECK_POLL, look)
      end
      C_Timer.After(RECHECK_REDRAW, function()
        entry.waited = shownState(id)
        entry.includedAfter = {}
        for _, sid in ipairs(WFJScanIncludes[id]) do entry.includedAfter[tostring(sid)] = includedState(sid) end
        show(id)
        entry.after = shownState(id)
        -- shown in Japanese once what it splices in loaded: what a player sees, so not left English
        if entry.after:find("^Japanese") then
          record.left[tostring(id)], record.changed[tostring(id)] = nil, nil
        end
        nextSpell()
      end)
    end
    look()
  end
  nextSpell()
end

-- the client's gap for a spell named in angle brackets (`<1243318>`): this client never fills that form in, so a line
-- holding one is a gap (as `leftWhy` says), never a tooltip the game changed
local GAP = "<%%d+>"

local function noteSpell(record, id, english, shown, row)
  record.left = record.left or {}
  record.icons = record.icons or {}
  local shipped = type(SHIPPED) == "table" and SHIPPED[id]
  local japanese = hasJapanese(shown)
    and not (type(shown) == "string" and shown:find("Not Translated]", 1, true) ~= nil)
  if shipped and shipped[1]:find("%%$I%%d") then
    record.icons[tostring(id)] = { line = iconIn(english), shown = iconIn(shown), japanese = japanese }
  end
  if japanese then
    record.shownTraced = record.shownTraced or 0
    if shipped and shipped[1]:find("%%$N%%d") and record.shownTraced < 6 then
      record.shownTraced = record.shownTraced + 1
      record.shownTraces = record.shownTraces or {}
      record.shownTraces[tostring(id)] = { text = english:sub(1, 200), trace = lastPasses() }
    end
    return
  end
  -- a description with no word in it ("..", "???", a placeholder the developers left) has nothing to translate
  if not english:find("%%a%%a") then
    record.noWords = (record.noWords or 0) + 1
    -- an empty line that splices in a spell the client had not loaded yet: read again once that spell loaded
    if type(WFJScanIncludes) == "table" and WFJScanIncludes[id] and not english:find(GAP) then
      record.left[tostring(id)] = { reason = "values", why = "no words until the spells it splices in loaded",
        text = english:sub(1, 300) }
      noteIncluded(record, id, english)
    end
    return
  end
  local ok, reason, why = pcall(leftWhy, id, english)
  if not ok then reason, why = "other", "the reason could not be read: " .. tostring(reason) end
  record.left[tostring(id)] = { reason = reason, why = why, text = english:sub(1, 300) }
  if reason == "values" then noteIncluded(record, id, english) end
  -- what the addon itself did on this tooltip: the last pass of its own tooltip trace, kept for the first few
  -- spells left English, so one run says why and nobody has to guess from outside
  record.traced = record.traced or 0
  if record.traced < TRACES_KEPT then
    record.traced = record.traced + 1
    local entry = record.left[tostring(id)]
    entry.trace = lastPasses()
    -- what the run itself saw: the row it read, how many rows the tooltip has, and every row's text now. A row
    -- that is not the description's, or a text the addon wrote a moment later, shows here.
    entry.row, entry.rows = row, GameTooltip:NumLines()
    entry.saw = tostring(shown):sub(1, 120)
    local now = {}
    for i = 1, math.min(GameTooltip:NumLines(), 8) do now[i] = tostring(shownRow(i)):sub(1, 60) end
    entry.now = table.concat(now, " || ")
  end
end

-- An item's own line (its use, equip or hit line, or its flavour text in quotes) shown as the client wrote it: the
-- first one of each item, under `leftItems`. Whether Japanese ships for the item is looked up when the result is
-- read. [unverified: that the client's tooltip data starts these lines with the English trigger word; the run's
-- list shows it]
local function ownLine(text)
  local plain = text:gsub("^|c%%x%%x%%x%%x%%x%%x%%x%%x", "")
  return plain:find("^Use: ") or plain:find("^Equip: ") or plain:find("^Chance on hit: ") or plain:find('^"')
end
local function noteItem(record, id, lines)
  record.leftItems = record.leftItems or {}
  for i = 2, #lines do
    local english = lines[i].leftText
    if readable(english) and shownRow(i) == english and ownLine(english) then
      record.leftItems[tostring(id)] = english:sub(1, 300)
      return
    end
  end
end

-- Every row of the tooltip on screen, left and right: the description is one row of several, and a name, a cost,
-- a range or a requirement left in English was seen by no check. A row with no Japanese at all is kept whole
-- under `english`; a Latin word inside a Japanese row (a name the name list has no line for) under `runs`. Each
-- is kept once, with how often it was met and one tooltip that shows it; digits are folded so "Rank 3" and
-- "Rank 4" are one row.
local ROWS_MAX = 6000 -- distinct rows and words kept
local function noteRows(record, what, id)
  local rows = record.rows
  if not rows then
    rows = { english = {}, runs = {}, kept = 0, tooltips = 0 }
    record.rows = rows
  end
  -- a tooltip still waiting for the item its spell makes is counted apart and its rows are not judged
  if stillLoading() then
    rows.loading = (rows.loading or 0) + 1
    return
  end
  rows.tooltips = rows.tooltips + 1
  local own = ownRows(tooltipData())
  -- the first row of each kind is kept as the client wrote it, markup and all (a bar doubled so it reads as
  -- text): what stands around a word says why it was left
  local function keep(into, key, row, side, raw)
    local seen = into[key]
    if seen then
      seen.n = seen.n + 1
    elseif rows.kept < ROWS_MAX then
      rows.kept = rows.kept + 1
      into[key] = { n = 1, at = what .. " " .. tostring(id) .. " row " .. row .. " " .. side .. ": "
        .. raw:gsub("|", "||"):gsub("%%c", " "):sub(1, 200) }
      -- for the first few kinds, how the tooltip was built and what the addon did with it, so a row left
      -- English is explained by one run
      rows.traced = rows.traced or 0
      if rows.traced < TRACES_KEPT then
        rows.traced = rows.traced + 1
        into[key].data = dataLines()
        into[key].trace = lastPasses()
      end
    end
  end
  for i = 1, GameTooltip:NumLines() do
    for _, side in ipairs({ "Left", "Right" }) do
      local fs = _G["GameTooltipText" .. side .. i]
      local text = (not own or own[i]) and fs and fs:IsShown() and fs:GetText()
      if readable(text) then
        local plain = rowPlain(text)
        if judged(plain) then
          -- a whole row with no Japanese under rows.english, a Latin word in a Japanese row under rows.runs
          englishIn(plain, function(into, key) keep(rows[into], key, i, side, text) end)
        end
      end
    end
  end
end

-- why a spell was not read, with the first few ids of each kind, so a run that reads few says what stopped it
local function unread(record, why, id, seen)
  record.unread = record.unread + 1
  local kind = record.why[why] or { n = 0, ids = {} }
  record.why[why] = kind
  kind.n = kind.n + 1
  if #kind.ids < 5 then kind.ids[#kind.ids + 1] = id .. (seen and (": " .. tostring(seen):sub(1, 80)) or "") end
end

local function readSpell(record, id, describe, why)
  local english = describe(id)
  if not readable(english) then
    -- what the tooltip itself shows for a spell whose text the client did not give
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    GameTooltip:SetSpellByID(id)
    return unread(record, why or "no text from the client", id, GameTooltip:NumLines() .. " lines, last: "
      .. tostring(shownRow(GameTooltip:NumLines())))
  end
  local data = C_TooltipInfo.GetSpellByID(id)
  local row
  for i, line in ipairs(type(data) == "table" and type(data.lines) == "table" and data.lines or {}) do
    if line.leftText == english then row = i end
  end
  if not row then
    local lines = type(data) == "table" and type(data.lines) == "table" and data.lines or {}
    return unread(record, "its text is no line of the tooltip", id,
      #lines .. " lines, last: " .. tostring(lines[#lines] and lines[#lines].leftText))
  end
  GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
  GameTooltip:SetSpellByID(id)
  -- A line's place in the data is not its row on screen: the tooltip does not draw every line, and writes the row
  -- it drew a line on into that line as `lineIndex` (blizzard_sharedxmlgame/tooltip/tooltipdatahandler.lua:
  -- 319-335). A run that took the place in the list read row 4 of a three-row tooltip, saw nothing, and called
  -- 8,000 Japanese tooltips English. So the row is the `lineIndex` of the line in the tooltip's own data, and
  -- a row past the tooltip's last one is never judged.
  local shownData
  if type(GameTooltip.GetPrimaryTooltipInfo) == "function" then
    local fine, info = pcall(GameTooltip.GetPrimaryTooltipInfo, GameTooltip)
    shownData = fine and type(info) == "table" and info.tooltipData or nil
  end
  local own, typed
  local kinds = type(Enum) == "table" and Enum.TooltipDataLineType or nil
  for _, line in ipairs(type(shownData) == "table" and type(shownData.lines) == "table" and shownData.lines or {}) do
    if type(line.lineIndex) == "number" then
      if line.leftText == english then own = line.lineIndex end
      if kinds and line.type == kinds.SpellDescription then typed = line.lineIndex end
    end
  end
  row = own or typed or row
  if row > GameTooltip:NumLines() then
    return unread(record, "the row of its text is past the tooltip's last row", id,
      "row " .. row .. " of " .. GameTooltip:NumLines())
  end
  record.read = record.read + 1
  local live, shown = valueCount(english), shownRow(row)
  local said = VALUES[id] .. " numbers in the Japanese, " .. live .. " on this client"
  -- A line the addon leaves English wears its not-translated marker, whose own words are Japanese: such a row
  -- is English, however its text reads.
  local marked = type(shown) == "string" and shown:find("Not Translated]", 1, true) ~= nil
  if hasJapanese(shown) and not marked then
    record.japanese = record.japanese + 1
    local fine, agrees = pcall(gateCount, id, english)
    if not (fine and agrees) then
      -- with both texts, so the report shows which numbers went where
      record.wrong[tostring(id)] = said .. " | live: " .. english:gsub("%%s+", " "):sub(1, 220)
        .. " | shown: " .. shown:gsub("%%s+", " "):sub(1, 220)
    end
  else
    if marked then record.marked = (record.marked or 0) + 1 end
    local fine, agrees = pcall(gateCount, id, english)
    -- a line that is only the client's gap for a spliced-in spell is counted as a gap by noteSpell, not as a tooltip
    -- the game changed
    local gap = english:find(GAP) ~= nil
    if VALUES[id] and not (fine and agrees) and not gap then record.changed[tostring(id)] = said end
  end
  noteSpell(record, id, english, shown, row)
  noteRows(record, "spell", id)
end

-- one item's tooltip, already shown, against its data
local function readItem(record, id, data)
  if type(id) ~= "number" or type(data) ~= "table" or type(data.lines) ~= "table" then return end
  record.items = record.items + 1
  noteRows(record, "item", id)
  local lines = data.lines
  for i = 2, #lines do
    local shown, english = shownRow(i), lines[i].leftText
    if hasJapanese(shown) and readable(english) and shown ~= english and not shown:find("\\n") then
      local folded, j = 0, i + 1
      while lines[j] and (shownRow(j) == " " or lines[j].leftText == "") do
        -- the client's own blank row (a set's bonuses end with one, its text a single space) is no row written over
        if readable(lines[j].leftText) and lines[j].leftText:find("%%S") then folded = folded + 1 end
        j = j + 1
      end
      if folded > 0 then
        record.folded[tostring(id)] = "one Japanese paragraph over " .. (folded + 1) .. " lines"
      end
    end
  end
  noteItem(record, id, lines)
end

local function readItems(record)
  for slot = 1, 19 do
    local id = GetInventoryItemID("player", slot)
    if id then
      GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
      GameTooltip:SetInventoryItem("player", slot)
      readItem(record, id, C_TooltipInfo.GetInventoryItem("player", slot))
    end
  end
  for bag = 0, 4 do
    for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
      local id = C_Container.GetContainerItemID(bag, slot)
      if id then
        GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        GameTooltip:SetBagItem(bag, slot)
        readItem(record, id, C_TooltipInfo.GetBagItem(bag, slot))
      end
    end
  end
end

-- The items listed for the run (`pipeline/ui_test_items.txt`: an item a player reported) are shown by id, loaded
-- first, and every line of each is kept beside what the tooltip shows for it, so a run says what such an item's
-- tooltip reads on this client whether or not the character owns it. A list to read, never a failure.
local function readReported(record, done)
  local ids = type(WFJScanReportedItems) == "table" and WFJScanReportedItems or {}
  record.reported = {}
  if #ids == 0 or type(C_Item) ~= "table" or type(C_Item.RequestLoadItemDataByID) ~= "function"
      or type(C_TooltipInfo.GetItemByID) ~= "function" then
    return done()
  end
  for _, id in ipairs(ids) do pcall(C_Item.RequestLoadItemDataByID, id) end
  local waited = 0
  tooltipReader:SetScript("OnUpdate", function(_, elapsed)
    waited = waited + (elapsed or 0)
    local ready = true
    for _, id in ipairs(ids) do
      local ok, cached = pcall(C_Item.IsItemDataCachedByID, id)
      if not (ok and cached) then ready = false end
    end
    if not ready and waited < TOOLTIP_PATIENCE then return end
    tooltipReader:SetScript("OnUpdate", nil)
    for _, id in ipairs(ids) do
      local lines = {}
      local got, data = pcall(C_TooltipInfo.GetItemByID, id)
      GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
      local shownOk = pcall(GameTooltip.SetItemByID, GameTooltip, id)
      for i, line in ipairs(got and type(data) == "table" and type(data.lines) == "table" and data.lines or {}) do
        local english, shown = line.leftText, shownRow(i)
        if readable(english) then
          local said = shown == nil and "(not shown)" or shown == english and "(English)"
            or shown:gsub("%%s+", " "):sub(1, 160)
          lines[#lines + 1] = english:gsub("%%s+", " "):sub(1, 160) .. " => " .. said
        end
      end
      if #lines == 0 then
        lines[1] = shownOk and "no lines: the client has no data for this item" or "the client refused this item"
      end
      record.reported[tostring(id)] = lines
    end
    GameTooltip:Hide()
    done()
  end)
end

local function WFJScanTooltipRead(done)
  done = collectorPaused(done)
  local db = probeDb()
  local record = { read = 0, unread = 0, japanese = 0, items = 0, wrong = {}, changed = {}, folded = {},
    why = {}, load = { asked = 0, loaded = 0, failed = 0, texts = 0 } }
  db.tooltips = record
  -- the addon's own tooltip trace is switched on for the read (its slash command is the one way in from another
  -- addon), and off again when the spells are done: noteSpell keeps what it recorded
  local slash = type(SlashCmdList) == "table" and SlashCmdList["WFJ"]
  if type(slash) == "function" then pcall(slash, "debug tooltip on") end
  local describe = type(C_Spell) == "table" and C_Spell.GetSpellDescription or GetSpellDescription
  local ids = {}
  for id in pairs(VALUES) do ids[#ids + 1] = id end
  table.sort(ids)
  if type(describe) ~= "function" or type(C_TooltipInfo) ~= "table" then
    record.refused = "this client has no spell description or tooltip data to read"
    return done()
  end
  local ok, err = pcall(readItems, record)
  if not ok then record.refused = "items: " .. tostring(err) end
  -- The client holds a spell's text only for a spell it has loaded, and only once that text was asked for: the
  -- first ask answers with nothing, and the client says SPELL_TEXT_UPDATE for that spell when the text is there.
  -- It does not keep the text of thousands of spells asked at once. So a few spells are in hand at a time, and
  -- each is read at the moment the client says it has it.
  local load = type(C_Spell) == "table" and C_Spell.RequestLoadSpellData
  local waiting, order, head, flight = {}, {}, 1, 0
  local at, said = 0, 0
  -- read the spell if the client gives its text now; `how` counts when it did
  local function settle(id, how)
    local fine, text = pcall(describe, id)
    if not (fine and readable(text)) then return false end
    if waiting[id] then
      waiting[id] = nil
      flight = flight - 1
    end
    record.load[how] = (record.load[how] or 0) + 1
    local read, why = pcall(readSpell, record, id, describe)
    if not read then record.refused = "spell " .. id .. ": " .. tostring(why) end
    return true
  end
  local function giveUp(id, why)
    waiting[id] = nil
    flight = flight - 1
    local read, said = pcall(readSpell, record, id, describe, why)
    if not read then record.refused = "spell " .. id .. ": " .. tostring(said) end
  end
  tooltipReader:RegisterEvent("SPELL_DATA_LOAD_RESULT")
  tooltipReader:RegisterEvent("SPELL_TEXT_UPDATE")
  tooltipReader:SetScript("OnEvent", function(_, event, id, success)
    if type(id) ~= "number" then return end
    local held = waiting[id]
    if event == "SPELL_TEXT_UPDATE" then
      record.load.texts = record.load.texts + 1
      if held then
        held.text = true
        settle(id, "onText")
      end
    elseif success then
      record.load.loaded = record.load.loaded + 1
      if held then
        held.loaded = true
        settle(id, "onLoad")
      end
    else
      record.load.failed = record.load.failed + 1
      if held then giveUp(id, "the client could not load the spell") end
    end
  end)
  print("WFJ test: reading " .. #ids .. " spell tooltips")
  tooltipReader:SetScript("OnUpdate", function()
    local t0, now = debugprofilestop(), GetTime()
    while head <= #order do
      local id = order[head]
      local held = waiting[id]
      if held and now - held.at < TOOLTIP_PATIENCE then break end
      head = head + 1
      if held and not settle(id, "late") then
        giveUp(id, "no text " .. TOOLTIP_PATIENCE .. "s after it was asked for (loaded: "
          .. tostring(held.loaded or false) .. ", text said ready: " .. tostring(held.text or false) .. ")")
      end
    end
    local stopped = record.read == 0 and record.unread >= TOOLTIP_PROOF
    while not stopped and at < #ids and flight < TOOLTIP_FLIGHT and debugprofilestop() - t0 < TOOLTIP_MS do
      at = at + 1
      local id = ids[at]
      if not settle(id, "atOnce") then
        waiting[id] = { at = now }
        order[#order + 1] = id
        flight = flight + 1
        record.load.asked = record.load.asked + 1
        if type(load) == "function" then pcall(load, id) end
      end
    end
    if at - said >= TOOLTIP_SAY then
      said = at
      print("WFJ test: spell tooltips " .. at .. "/" .. #ids .. " (" .. record.read .. " read)")
    end
    if not stopped and (at < #ids or flight > 0) then return end
    if stopped then
      record.refused = "stopped: none of the first " .. record.unread .. " spells gave its text"
    end
    tooltipReader:SetScript("OnUpdate", nil)
    tooltipReader:UnregisterAllEvents()
    GameTooltip:Hide()
    print("WFJ test: spell tooltips done, " .. record.read .. " read")
    if type(slash) == "function" then pcall(slash, "debug tooltip off") end
    recheckIncluded(record, function() readReported(record, done) end)
  end)
end

-- The no-voice read. With a voice pack, a translated line the pack lists as having no voice yet says so on its
-- window: `[音声なし / No Voice Yet]`. The quest and NPC talk windows need an NPC, so the run reads the one window
-- it can open by itself: the quest log, one quest of the character's at a time, shown the client's way. What the
-- pane says is held to the list the voice entry gave the addon, kept here as it was handed over, into
-- `probe.novoice`:
--   wrong   a quest whose pane says the wrong thing: the message for a line not listed (or with no pack), no
--           message for a listed line that shows its Japanese, or both messages at once. A failure.
-- A character with no quest in its log reads nothing, and the result says so.
local NO_VOICE, NOT_TRANSLATED = "音声なし", "未翻訳"
local NOVOICE_TICKS = 20 -- frames between showing a quest and reading its pane
local listedNoVoice -- the pack keys the voice entry listed, as a set; nil when it listed none
local packWatcher = CreateFrame("Frame")
packWatcher:RegisterEvent("ADDON_LOADED")
packWatcher:SetScript("OnEvent", function(self, _, name)
  if name ~= "WoWForeverJapanese" then return end
  self:UnregisterAllEvents()
  if type(WoWForeverJapanese_VoiceNotMade) ~= "function" then return end
  hooksecurefunc("WoWForeverJapanese_VoiceNotMade", function(list)
    listedNoVoice = nil
    if type(list) ~= "table" then return end
    listedNoVoice = {}
    for _, key in ipairs(list) do listedNoVoice[key] = true end
  end)
end)

local function voicePackLoaded()
  for i = 1, C_AddOns.GetNumAddOns() do
    local name = C_AddOns.GetAddOnInfo(i)
    if type(name) == "string" and name:find("^WoWForeverJapanese_Voice") and C_AddOns.IsAddOnLoaded(i) then
      return true
    end
  end
  return false
end

-- whether the addon's settings leave the message on for a quest's offer (a setting never changed is on)
local function messageOn()
  local settings = type(WFJ_DB) == "table" and WFJ_DB.settings
  if type(settings) ~= "table" then return true end
  return settings["voice.enabled"] ~= false and settings["voice.offer"] ~= false and settings["voice.mark"] ~= false
end

-- the two messages as the quest log's pane shows them now → says no voice, says not translated
local function paneSays()
  local noVoice, notTranslated = false, false
  local frame = EnumerateFrames()
  while frame do
    pcall(function()
      if frame:IsForbidden() or not frame:IsVisible() then return end
      for _, region in ipairs({ frame:GetRegions() }) do
        if region:GetObjectType() == "FontString" and region:IsVisible() then
          local text = plainOf(region)
          if text and text:find(NO_VOICE, 1, true) then noVoice = true end
          if text and text:find(NOT_TRANSLATED, 1, true) then notTranslated = true end
        end
      end
    end)
    frame = EnumerateFrames(frame)
  end
  return noVoice, notTranslated
end

local noVoiceReader = CreateFrame("Frame")
local function WFJScanNoVoiceRead(done)
  local db = probeDb()
  local record = { quests = 0, said = 0, pack = voicePackLoaded(), listed = 0, wrong = {} }
  db.novoice = record
  for _ in pairs(listedNoVoice or {}) do record.listed = record.listed + 1 end
  local quests = {}
  local ok, err = pcall(function()
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
      local info = C_QuestLog.GetInfo(i)
      if type(info) == "table" and not info.isHeader and not info.isHidden and type(info.questID) == "number" then
        quests[#quests + 1] = info.questID
      end
    end
    if #quests > 0 and not (QuestMapFrame and QuestMapFrame:IsVisible()) then
      ToggleQuestLog()
      record.opened = true
    end
  end)
  if not ok then
    record.refused = tostring(err)
    return done()
  end
  if #quests == 0 then return done() end
  local at, ticks, showing = 0, 0, nil
  noVoiceReader:SetScript("OnUpdate", function()
    ticks = ticks + 1
    if ticks < NOVOICE_TICKS then return end
    ticks = 0
    if showing then
      local said, missing = paneSays()
      local listed = listedNoVoice ~= nil and listedNoVoice[showing .. "-description"] == true
      record.quests = record.quests + 1
      if said then record.said = record.said + 1 end
      local what
      if said and missing then
        what = "says both that it has no voice and that it is not translated"
      elseif said and not record.pack then
        what = "says it has no voice, with no voice pack loaded"
      elseif said and not listed then
        what = "says it has no voice, and the voice pack does not list it"
      elseif listed and record.pack and messageOn() and not said and not missing then
        what = "the voice pack lists it with no voice, and the pane does not say so"
      end
      if what then record.wrong[tostring(showing)] = what end
      showing = nil
    end
    at = at + 1
    if at > #quests then
      noVoiceReader:SetScript("OnUpdate", nil)
      if record.opened then pcall(ToggleQuestLog) end -- closed again, the way it was opened
      record.opened = nil
      return done()
    end
    local fine, why = pcall(QuestMapFrame_ShowQuestDetails, quests[at])
    if fine then showing = quests[at] else record.refused = tostring(why) end
  end)
end

-- The names read. With Japanese names on, a widget that holds a game name shows the name's Japanese. The run reads
-- the names it can reach by itself and keeps each one's English and what was shown, into `probe.names`; the name
-- list is held to them when the result is read:
--   item    the name line of every item the character wears or carries
--   spell   the name line of every spell the tooltip read asks for
--   zone    the zone banner, written the client's way
--   unit    the target's name line, when the character has a creature targeted
--   player  the player's own name line: a player's name is never a game name and must stay as written
-- The names setting is read, never written: the run shows what this player sees. With names off it reads nothing
-- and the result says so.
local NAMES_MAX = 600 -- rows kept: every bag full is under 200 items

local function WFJScanNamesRead(done)
  local db = probeDb()
  local record = { on = namesOn(), rows = {} }
  db.names = record
  if not record.on then return done() end
  done = collectorPaused(done) -- it shows tooltips by id, as the tooltip read does
  local seen = {}
  local function keep(kind, english, shown)
    if not readable(english) or not readable(shown) or #record.rows >= NAMES_MAX then return end
    local key = kind .. " " .. english
    if seen[key] then return end
    seen[key] = true
    record.rows[#record.rows + 1] = { kind = kind, english = english, shown = shown }
  end
  -- the tooltip on screen: its first line against the name the client's own data gives it
  local function nameLine(kind, data)
    local lines = type(data) == "table" and type(data.lines) == "table" and data.lines or nil
    if lines and lines[1] then keep(kind, lines[1].leftText, shownRow(1)) end
  end
  local ok, err = pcall(function()
    for slot = 1, 19 do
      if GetInventoryItemID("player", slot) then
        GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        GameTooltip:SetInventoryItem("player", slot)
        nameLine("item", C_TooltipInfo.GetInventoryItem("player", slot))
      end
    end
    for bag = 0, 4 do
      for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
        if C_Container.GetContainerItemID(bag, slot) then
          GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
          GameTooltip:SetBagItem(bag, slot)
          nameLine("item", C_TooltipInfo.GetBagItem(bag, slot))
        end
      end
    end
    -- once the rows are full every further tooltip shown is thrown away: with the client's spells loaded that
    -- was thousands of them in one go, and the client stopped the script for running too long
    for id in pairs(VALUES) do
      if #record.rows >= NAMES_MAX then break end
      local data = C_TooltipInfo.GetSpellByID(id)
      if type(data) == "table" then
        GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        GameTooltip:SetSpellByID(id)
        nameLine("spell", data)
      end
    end
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    GameTooltip:SetUnit("player")
    keep("player", UnitName("player"), shownRow(1))
    if UnitExists("target") and UnitIsPlayer("target") == false then
      GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
      GameTooltip:SetUnit("target")
      keep("unit", UnitName("target"), shownRow(1))
      -- the rows under the name: a quest's objective row on a creature it counts for ("12/12 Saltwater Murloc
      -- Eye") holds a name too, held to the name list with the windows' Latin text
      record.target = {}
      for i = 2, math.min(GameTooltip:NumLines(), 30) do
        local text = shownRow(i)
        if readable(text) then record.target["target tooltip row " .. i] = text end
      end
    end
    GameTooltip:Hide()
    -- the zone banner, written by the client's own handler, as on a zone change
    if type(ZoneText_OnEvent) == "function" and ZoneTextFrame and ZoneTextString then
      ZoneText_OnEvent(ZoneTextFrame, "ZONE_CHANGED_NEW_AREA")
      keep("zone", GetZoneText(), ZoneTextString:GetText())
    end
  end)
  if not ok then record.refused = tostring(err) end
  done()
end

-- The nameplate read. With Japanese names a creature's name shows on its nameplate, and a nameplate shows only within
-- the client's nameplate range, so Japanese names widen it and turn off the client's English names over NPC heads
-- (UI/NamePlateSetting). Into `probe.plates`: each of those settings' value and default, and `limit`, the largest
-- range the client holds (a larger value set and read back, then the value before it put back).
local PLATE_CVARS = { "nameplateMaxDistance", "UnitNameNPC", "UnitNameHostleNPC", "UnitNameInteractiveNPC",
  "UnitNameFriendlySpecialNPCName" }
local NAMES_SETTING = "names.japanese"

local function WFJScanPlatesRead()
  local db = probeDb()
  local settings = addonSettings() or {}
  local record = { names = settings[NAMES_SETTING] == true, values = {}, defaults = {} }
  db.plates = record
  if not (C_CVar and C_CVar.GetCVar and C_CVar.SetCVar) then
    record.refused = "the client has no C_CVar"
    return
  end
  for _, name in ipairs(PLATE_CVARS) do
    record.values[name] = C_CVar.GetCVar(name) or "none"
    record.defaults[name] = C_CVar.GetCVarDefault and C_CVar.GetCVarDefault(name) or "unknown"
  end
  local before = C_CVar.GetCVar("nameplateMaxDistance")
  if before then
    pcall(C_CVar.SetCVar, "nameplateMaxDistance", "200")
    record.limit = C_CVar.GetCVar("nameplateMaxDistance")
    pcall(C_CVar.SetCVar, "nameplateMaxDistance", before)
  end
end

-- The load read: what the addon costs. Into `probe.load`: its own Lua memory in KB (the client's per-addon count) and,
-- from its problem log, how long its files took to load and its setup after them, in milliseconds.
local function WFJScanLoadRead()
  local db = probeDb()
  local record = {}
  db.load = record
  local update = (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage) or UpdateAddOnMemoryUsage
  local get = (C_AddOns and C_AddOns.GetAddOnMemoryUsage) or GetAddOnMemoryUsage
  if update and get then
    update()
    record.kb = get("WoWForeverJapanese")
  end
  local timed = type(WFJ_Log) == "table" and WFJ_Log.load
  if type(timed) == "table" then record.files, record.setup = timed.files, timed.setup end
end

-- The bag click read. A bag item's right-click reads these before it uses the item (ContainerFrameItemButton_OnClick,
-- mainline/containerframe.lua:1503-1611, and the button's own fields, :1845); one carrying the addon's taint makes
-- the use a forbidden call out of combat, the addon named. Each global that is a table is read one level down too
-- (MerchantFrame's fields, BankFrame's, ItemButtonUtil's). Read three times: as the run left them; with the backpack
-- open after the mouse was pointed at its items the client's way (a player points at the Hearthstone before using it,
-- and the item tooltip runs the addon's code); and after the whole interface was hidden and shown again (what Dialogue
-- UI does around a talk, and Alt+Z), so a hook of the addon's that runs inside either is caught. Into
-- `probe.bagclick`:
--   checked  values read; ours  { "<when>\\t<name>" } carrying the addon's taint: a failure
--   others   name → the addon whose taint it carries (listed, not failed); refused  why the second pass did not run
local BAG_CLICK_GLOBALS = { "ContainerFrameItemButton_OnClick", "MerchantFrame_ResetRefundItem", "MerchantFrame",
  "StackSplitFrame", "BankFrame", "GuildBankFrame", "MailFrame", "AuctionFrame", "AuctionHouseFrame", "TradeFrame",
  "ItemUpgradeFrame", "ObliterumForgeFrame", "ChallengesKeystoneFrame", "AzeriteRespecFrame", "RuneforgeFrame",
  "ItemLocation", "ItemButtonUtil", "BankUtil_IsAccountBankDepositRefundable", "ContainerFrame_GetExtendedPriceString",
  "ContainerFrame_IsAccountBankTab", "C_Container", "C_Cursor", "C_Item", "C_AuctionHouse", "C_ItemSocketInfo",
  "C_ArtifactUI", "C_MountJournal", "GetCursorInfo", "SpellCanTargetItem", "SpellCanTargetItemID", "CursorHasItem",
  "MerchantFrame_ConfirmExtendedItemCost", "MerchantFrame_ConfirmHighCostItem", "MerchantFrame_SetRefundItem",
  "StaticPopup_Show" }
local BAG_CLICK_MERCHANT = { "selectedTab", "extendedCost", "highPrice" }

local BAG_POINT_MAX = 8 -- bag items pointed at: the item tooltip's code is the same for each
local function WFJScanBagClickRead(done)
  local db = probeDb()
  local record = { checked = 0, ours = {}, others = {} }
  db.bagclick = record
  local listed = {}
  local function note(when, name, secure, owner)
    record.checked = record.checked + 1
    if secure or owner == nil then return end
    if owner == "WoWForeverJapanese" then
      if not listed[name] then
        listed[name] = true
        record.ours[#record.ours + 1] = when .. "\\t" .. name
      end
    elseif owner == "WFJScan" then
      -- the read's own steps run as the test addon, so what they write carries its taint, not this addon's: counted,
      -- so a pass is read knowing it cannot show taint the addon would leave on that route
      record.own = (record.own or 0) + 1
    else
      record.others[name] = tostring(owner)
    end
  end
  local function fields(when, label, t)
    for key in pairs(t) do
      if type(key) == "string" then note(when, label .. "." .. key, issecurevariable(t, key)) end
    end
  end
  local pointedAt = {} -- the bag item buttons pointed at, read with the rest
  local function read(when)
    for i, button in ipairs(pointedAt) do fields(when, button:GetName() or ("bag item button " .. i), button) end
    for _, name in ipairs(BAG_CLICK_GLOBALS) do
      note(when, name, issecurevariable(name))
      local value = _G[name]
      if type(value) == "table" then fields(when, name, value) end
    end
    if type(MerchantFrame) == "table" then
      for _, key in ipairs(BAG_CLICK_MERCHANT) do
        note(when, "MerchantFrame." .. key, issecurevariable(MerchantFrame, key))
      end
    end
    if type(BankFrame) == "table" and type(rawget(BankFrame, "BankPanel")) == "table" then
      fields(when, "BankFrame.BankPanel", BankFrame.BankPanel)
    end
    local frames = { "ContainerFrameCombinedBags" }
    for i = 1, 13 do frames[#frames + 1] = "ContainerFrame" .. i end
    for _, name in ipairs(frames) do
      local f = _G[name]
      if type(f) == "table" then
        fields(when, name, f)
        local items = rawget(f, "Items")
        if type(items) == "table" then
          for i, button in ipairs(items) do
            if type(button) == "table" then fields(when, name .. ".Items[" .. i .. "]", button) end
          end
        end
      end
    end
  end
  -- a read that raises is recorded and the run goes on: the rest of the test must still run
  local function readSafely(when)
    local ok, err = pcall(read, when)
    if not ok then record.failed = when .. ": " .. tostring(err) end
  end
  readSafely("after the run")
  if type(SetUIVisibility) ~= "function" or type(OpenAllBags) ~= "function" then
    record.refused = "the client has no SetUIVisibility or OpenAllBags"
    return done()
  end
  -- the bags the player uses: the client's own, or a bag addon's that takes the same call (Baganator)
  local wasOpen = type(IsBagOpen) == "function" and IsBagOpen(0)
  if not wasOpen then OpenAllBags() end
  -- why no button was pointed at, when none was: how many frames got how far, and the first error
  local skipped = { bagButtons = 0, shown = 0, badSlot = 0, empty = 0, errors = 0 }
  record.skipped = skipped
  -- the client's own way to point at a frame, as the hover read does: its enter script, then its leave script. Any
  -- bag item button on screen, found by what it is (a button that knows its bag) rather than by a frame name, so a
  -- bag addon's buttons count too.
  local function consider(f)
    if type(f.GetBagID) ~= "function" or type(f.GetID) ~= "function" then return end
    skipped.bagButtons = skipped.bagButtons + 1
    if not f:IsVisible() then return end
    skipped.shown = skipped.shown + 1
    -- a bag addon's frames answer GetBagID too (a bag slot, a header) with a slot the client refuses: only a slot
    -- from 1 up is asked about
    local bag = f:GetBagID()
    local slot = type(bag) == "number" and bag >= 0 and f:GetID() or nil
    if type(slot) ~= "number" or slot < 1 then
      skipped.badSlot = skipped.badSlot + 1
      skipped.sample = skipped.sample or ((f:GetName() or "unnamed") .. " bag " .. tostring(bag) .. " slot "
        .. tostring(f:GetID()))
      return
    end
    if not C_Container.GetContainerItemID(bag, slot) then
      skipped.empty = skipped.empty + 1
      return
    end
    pointedAt[#pointedAt + 1] = f
    if type(ExecuteFrameScript) == "function" then
      pcall(ExecuteFrameScript, f, "OnEnter")
      pcall(ExecuteFrameScript, f, "OnLeave")
    end
  end
  local function finish()
    if not wasOpen and type(CloseAllBags) == "function" then CloseAllBags() end
    done()
  end
  local function pointAndHide()
    local f = EnumerateFrames()
    while f and #pointedAt < BAG_POINT_MAX do
      -- a frame the client will not answer for (a forbidden one) is passed over
      local ok, err = pcall(consider, f)
      if not ok then
        skipped.errors = skipped.errors + 1
        skipped.firstError = skipped.firstError or tostring(err)
      end
      f = EnumerateFrames(f)
    end
    record.pointed = #pointedAt
    -- what a bag item button's enter script calls, run for the items in the bags whatever addon draws their buttons
    -- (a bag addon's may not be on screen or found): the item tooltip's code on a bag item, the path under test
    local shown = 0
    if type(GameTooltip) == "table" and type(GameTooltip.SetBagItem) == "function" then
      for bag = 0, 4 do
        local ok, slots = pcall(C_Container.GetContainerNumSlots, bag)
        slots = ok and tonumber(slots) or 0
        for slot = 1, slots do
          if shown < BAG_POINT_MAX and C_Container.GetContainerItemID(bag, slot) then
            local ok, err = pcall(function()
              GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
              GameTooltip:SetBagItem(bag, slot)
              GameTooltip:Hide()
            end)
            if ok then
              shown = shown + 1
            else
              skipped.errors = skipped.errors + 1
              skipped.firstError = skipped.firstError or tostring(err)
            end
          end
        end
      end
    end
    record.tooltips = shown
    readSafely("after pointing at bag items")
    -- the client shows a hidden interface again only out of combat: a fight that started during the wait above
    -- would leave it hidden, so the toggle is not done then and the run says so
    if InCombatLockdown() then
      record.refused = "a fight started before the interface could be hidden and shown"
      return finish()
    end
    SetUIVisibility(false)
    SetUIVisibility(true)
    -- what the interface's return sets off runs on the frames after it (a help tip's OnUpdate): waited for, so an
    -- error it raises lands inside the run
    C_Timer.After(0.5, function()
      readSafely("after the interface came back")
      finish()
    end)
  end
  -- a bag addon lays its buttons out on the frames after its window opens: waited for. A raise inside the timer
  -- would end the run with no done line, so it is recorded and the run goes on.
  C_Timer.After(0.5, function()
    local ok, err = pcall(pointAndHide)
    if not ok then
      record.failed = "pointing at bag items: " .. tostring(err)
      finish()
    end
  end)
end

-- The reads below look for a value the addon wrote where the client's own code reads it. They sit in one function
-- of their own, reached through this table: the file's chunk may hold 200 local names at once, and it is near that.
local WFJScanTaint = {}
-- The addon's popup dictionary covers, as it holds them: each one's state (its frame under `frame`, its text, its
-- spans, the marks drawn on it). A cover's frame carries no field, so the state is asked for, never read off it.
WFJScanTaint.coverStates = function()
  local out = {}
  if type(WFJ_ReadingCovers) == "function" then
    pcall(WFJ_ReadingCovers, function(_, frame, _, state)
      if type(state) == "table" and type(frame) == "table" then out[#out + 1] = state end
    end)
  end
  return out
end
;(function()
-- The touch read. Everything of the addon's that the client's own code could read: a client frame's field that
-- carries the addon's taint (the addon wrote it, or replaced a function there), and a frame the addon made that sits
-- inside a client frame, with the fields it carries. The client reads fields off the children of its frames (a
-- layout frame asks each child for ignoreInLayout), and a value the addon wrote taints the client's run from that
-- read on. A frame is the addon's when its fields carry the addon's taint and none is secure. Read in slices, so
-- the game does not stall. Into `probe.touch`:
--   frames   frames walked; made  frames the addon made; insideN  of them, inside a client frame
--   onClient { "<frame>.<key>" } client fields carrying the addon's taint (the first TOUCH_MAX); onClientN  all
--   inside   { "<keys, space separated>\\t<count>\\t<a parent it was found under>" } one line per set of keys
local TOUCH_SLICE = 400 -- frames read per frame drawn, at most
local TOUCH_MAX = 300
WFJScanTaint.touch = function(done)
  local TOUCH_MS = 2 -- milliseconds of reading per frame drawn: nothing here may be long enough to see
  local db = probeDb()
  local record = { frames = 0, made = 0, insideN = 0, onClient = {}, onClientN = 0, inside = {} }
  db.touch = record
  local ADDON = "WoWForeverJapanese"
  local madeBy = {} -- frame → true | false
  local groups, order = {}, {}
  local function nameOf(f)
    local ok, name = pcall(function() return f.GetDebugName and f:GetDebugName() or f:GetName() end)
    return ok and type(name) == "string" and name or "unnamed"
  end
  -- → whether the addon made `f`, and its string keys (sorted) and the client keys carrying the addon's taint
  local function look(f)
    local ours, secure, keys, tainted = 0, 0, {}, {}
    for key in pairs(f) do
      if type(key) == "string" then
        local ok, isSecure, by = pcall(issecurevariable, f, key)
        if ok and isSecure then
          secure = secure + 1
        elseif ok and by == ADDON then
          ours = ours + 1
          tainted[#tainted + 1] = key
        end
        keys[#keys + 1] = key
      end
    end
    return ours > 0 and secure == 0, keys, tainted
  end
  -- Whether the addon made `f`: its own keys say so, or its global name carries the addon's taint, or a frame above it
  -- is the addon's (a button the addon built from a client template holds the template's keys beside the addon's).
  local function made(f)
    local known = madeBy[f]
    if known ~= nil then return known end
    madeBy[f] = false -- a parent loop ends here
    local mine = (look(f))
    if not mine then
      local okN, name = pcall(f.GetName, f)
      if okN and type(name) == "string" and _G[name] == f then
        local okS, isSecure, by = pcall(issecurevariable, _G, name)
        mine = okS and not isSecure and by == ADDON
      end
    end
    if not mine then
      local okP, parent = pcall(f.GetParent, f)
      mine = okP and parent ~= nil and parent ~= UIParent and parent ~= WorldFrame and made(parent) or false
    end
    madeBy[f] = mine
    return mine
  end
  local function read(f)
    record.frames = record.frames + 1
    local okF, forbidden = pcall(function() return f.IsForbidden and f:IsForbidden() end)
    if not okF or forbidden then return end
    local _, keys, tainted = look(f)
    if not made(f) then
      for _, key in ipairs(tainted) do
        record.onClientN = record.onClientN + 1
        if #record.onClient < TOUCH_MAX then record.onClient[#record.onClient + 1] = nameOf(f) .. "." .. key end
      end
      return
    end
    record.made = record.made + 1
    -- the nearest ancestor the addon did not make: its fields are read by the client when that is a client frame
    -- only a frame directly under a client frame is one of that frame's children; UIParent holds every window
    local direct = f:GetParent()
    if not direct or direct == UIParent or direct == WorldFrame or made(direct) then return end
    record.insideN = record.insideN + 1
    table.sort(keys)
    local sig = table.concat(keys, " ")
    local g = groups[sig]
    if not g then
      g = { n = 0, where = nameOf(direct) }
      groups[sig] = g
      order[#order + 1] = sig
    end
    g.n = g.n + 1
  end
  local f = EnumerateFrames()
  local walker = CreateFrame("Frame")
  walker:SetScript("OnUpdate", function(self)
    local n, started = 0, debugprofilestop()
    while f and n < TOUCH_SLICE and debugprofilestop() - started < TOUCH_MS do
      pcall(read, f)
      f = EnumerateFrames(f)
      n = n + 1
    end
    if f then return end
    self:SetScript("OnUpdate", nil)
    for i, sig in ipairs(order) do
      if i > TOUCH_MAX then break end
      record.inside[i] = sig .. "\\t" .. groups[sig].n .. "\\t" .. groups[sig].where
    end
    done()
  end)
end

-- The popup dictionary cover read. A cover is the addon's own frame laid over a text, and what the mouse meets
-- there: a cover that is missing, lies beside its text, or stays when its text hides is a popup dictionary that does
-- not answer or answers in the wrong place. A cover also sits among the client's frames, so it may carry no field
-- (the client's layout code reads fields off every child it lays out) and may not be a layout frame's own child.
-- Read as they are now, over whatever is on screen. Into `probe.covers`:
--   total  covers the addon holds; shown  those showing; noread  the addon has no such read (an older build)
--   on       whether the popup dictionary is switched on; idle  covers showing over a text that is not (the cover
--            answers nothing there and lets the mouse through: counted, never a failure)
--   stray    { "<text>" } a cover showing over a text that is not the addon's any more: a failure
--   missing  { "<text>" } with the popup dictionary on, a text of the addon's showing with its cover hidden: a failure
--   beside   { "<text>" } a showing cover whose box is not its text's box: a failure
--   fields   { "<text>\\t<keys>" } a cover's frame carrying a field: a failure
--   inLayout { "<text>" } a cover that is a layout frame's own child: a failure
WFJScanTaint.covers = function(done)
  local COVERS_MAX = 40 -- names listed per kind of fault
  local db = probeDb()
  local record = { total = 0, shown = 0, idle = 0, stray = {}, missing = {}, beside = {}, fields = {}, inLayout = {} }
  db.covers = record
  if type(WFJ_ReadingCovers) ~= "function" then
    record.noread = true
    return done()
  end
  local function note(list, text)
    if #list < COVERS_MAX then list[#list + 1] = text end
  end
  local function label(fs)
    local ok, name = pcall(function() return fs:GetDebugName() end)
    return ok and type(name) == "string" and name or "unnamed"
  end
  local function near(a, b) return a ~= nil and b ~= nil and math.abs(a - b) <= 1.5 end
  local visits = {}
  local okOn, on = pcall(WFJ_ReadingCovers, function(fs, frame, inUse) visits[#visits + 1] = { fs, frame, inUse } end)
  record.on = okOn and on and true or false
  for _, visit in ipairs(visits) do
    local fs, frame, inUse = visit[1], visit[2], visit[3]
    record.total = record.total + 1
    local name = label(fs)
    local frameShown, textShown = frame:IsVisible() and true or false, fs:IsVisible() and true or false
    if frameShown then record.shown = record.shown + 1 end
    if frameShown and not inUse then note(record.stray, name) end
    if frameShown and inUse and not textShown then record.idle = record.idle + 1 end
    if record.on and inUse and textShown and not frameShown then note(record.missing, name) end
    if frameShown and textShown then
      local l, b, w, h = frame:GetRect()
      local fl, fb, fw, fh = fs:GetRect()
      if l and fl and not (near(l, fl) and near(b, fb) and near(w, fw) and near(h, fh)) then note(record.beside, name) end
    end
    local keys = {}
    for key in pairs(frame) do
      if type(key) == "string" then keys[#keys + 1] = key end
    end
    if #keys > 0 then
      table.sort(keys)
      note(record.fields, name .. "\\t" .. table.concat(keys, " "))
    end
    local parent = frame:GetParent()
    if type(parent) == "table" and type(parent.Layout) == "function" and type(parent.GetLayoutChildren) == "function" then
      note(record.inLayout, name)
    end
  end
  done()
end

-- The chat send read. A slash command the player types runs from the chat box's Enter handler through the client's
-- own send code (chatframeeditbox.lua:451-455, 426, 296, 271) to the command's function; a value on that path that
-- carries an addon's taint makes the client refuse a command that needs a clean run (a guild invite). Read here:
-- every field of each chat edit box, the globals that path names, and each entry of the slash command tables.
-- Into `probe.send`:
--   checked  values read; tainted  { "<name>\\t<addon>" } carrying any addon's taint when the read began
--   afterInsert / afterOpen  the same, for what an addon's own insert into the chat box and its own open added
local SEND_GLOBALS = { "ACTIVE_CHAT_EDIT_BOX", "LAST_ACTIVE_CHAT_EDIT_BOX", "CHAT_FOCUS_OVERRIDE", "DEFAULT_CHAT_FRAME",
  "SELECTED_CHAT_FRAME", "SELECTED_DOCK_FRAME", "ChatFrameUtil", "ChatFrameEditBoxMixin", "ChatFrameEditBoxBaseMixin",
  "ChatFrameMixin", "SlashCmdList", "hash_SlashCmdList", "hash_EmoteTokenList", "hash_ChatTypeInfoList", "ChatTypeInfo",
  "C_GuildInfo", "C_PartyInfo", "C_ChatInfo", "Constants", "GetUnitName", "UnitName", "strtrim", "strupper", "strlower",
  "strmatch", "strfind", "strsub", "strlen", "strsplit", "format", "gsub", "tinsert", "tremove", "securecallfunction",
  "secureexecuterange", "issecure", "IsSecureCmd", "GENERAL_CHAT_DOCK", "FCFDock_GetSelectedWindow", "GetCVar",
  "GetCVarBool", "UIParent", "AutoCompleteEditBox_OnEnterPressed", "AutoComplete_Update", "IsVoiceTranscription",
  "MacroEditBox", "RunMacroText", "SecureCmdOptionParse", "ChatEdit_ParseText", "ChatEdit_SendText",
  "ChatFrame_OpenChat", "ChatEdit_ActivateChat", "ChatEdit_OnEnterPressed" }
local SEND_TABLES = { "ChatFrameUtil", "ChatFrameEditBoxMixin", "ChatFrameEditBoxBaseMixin", "hash_SlashCmdList",
  "hash_ChatTypeInfoList", "C_GuildInfo", "C_PartyInfo" }
WFJScanTaint.send = function(done)
  local db = probeDb()
  local record = { checked = 0, tainted = {}, afterInsert = {}, afterOpen = {} }
  db.send = record
  -- every tainted value of the send path, as name → the addon whose taint it carries
  local function snapshot()
    local found = {}
    local function look(t, key, name)
      record.checked = record.checked + 1
      local ok, isSecure, by = pcall(issecurevariable, t, key)
      if ok and not isSecure then found[name] = tostring(by) end
    end
    for _, name in ipairs(SEND_GLOBALS) do look(_G, name, name) end
    for _, name in ipairs(SEND_TABLES) do
      local t = _G[name]
      if type(t) == "table" then
        for key in pairs(t) do
          if type(key) == "string" then look(t, key, name .. "." .. key) end
        end
      end
    end
    for i = 1, NUM_CHAT_WINDOWS or 10 do
      for _, name in ipairs({ "ChatFrame" .. i .. "EditBox", "ChatFrame" .. i }) do
        local f = _G[name]
        look(_G, name, name)
        if type(f) == "table" then
          for key in pairs(f) do
            if type(key) == "string" then look(f, key, name .. "." .. key) end
          end
        end
      end
    end
    return found
  end
  -- what `now` holds that `before` did not, into `list`
  local function added(list, before, now)
    for name, by in pairs(now) do
      if before[name] ~= by and #list < 200 then list[#list + 1] = name .. "\\t" .. by end
    end
    table.sort(list)
  end
  local base = snapshot()
  added(record.tainted, {}, base)
  -- What an addon leaves on the path when it writes into the chat box itself, as the phrase book does: first text
  -- put into the box, then the box opened with the client's own call. Both are the test's own writes, so they
  -- carry the test addon's name; the chat box is put away again and a reload clears them.
  local box = _G.ChatFrame1EditBox
  if type(box) == "table" and type(box.Insert) == "function" then
    pcall(box.Insert, box, "x")
    local now = snapshot()
    added(record.afterInsert, base, now)
    base = now
    pcall(box.SetText, box, "")
  end
  local open = type(ChatFrameUtil) == "table" and ChatFrameUtil.OpenChat or _G.ChatFrame_OpenChat
  if type(open) == "function" then
    pcall(open, "")
    added(record.afterOpen, base, snapshot())
    local active = type(ChatFrameUtil) == "table" and type(ChatFrameUtil.GetActiveWindow) == "function"
      and ChatFrameUtil.GetActiveWindow() or nil
    if active and type(ChatFrameUtil.DeactivateChat) == "function" then pcall(ChatFrameUtil.DeactivateChat, active) end
  end
  done()
end

-- The crafting window read. The window is opened the way the client opens it for a player: the test asks the
-- client for the trade skill (C_TradeSkillUI.OpenTradeSkill), the client answers with its own event, and the window's
-- own code opens it in a fresh run that carries no addon's taint. A field of the window that then carries the
-- addon's taint was written while one of the addon's hooks had poisoned what that code reads; the recipe form marks
-- reagents in the bags, so the taint reaches the bag buttons and from there a vendor and the action bars. Read once
-- with the window open and once after the client opened another recipe. Into `probe.craft`:
--   checked  values read; ours  { "<when>\\t<name>" } carrying the addon's taint: a failure
--   others   name → the addon whose taint it carries; own  values the test's own steps tainted
--   refused  why the window was not read; line  the skill line opened; recipe  the recipe opened
local CRAFT_WAIT = 5 -- seconds the client is given to answer
local CRAFT_FRAMES = { "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot",
  "CharacterReagentBag0Slot", "MainMenuBarBackpackButton", "ContainerFrameCombinedBags", "MerchantFrame" }
WFJScanTaint.craft = function(done)
  local db = probeDb()
  local record = { checked = 0, ours = {}, others = {}, own = 0 }
  db.craft = record
  local listed = {}
  local function note(when, name, secure, owner)
    record.checked = record.checked + 1
    if secure or owner == nil then return end
    if owner == "WoWForeverJapanese" then
      if not listed[name] then
        listed[name] = true
        record.ours[#record.ours + 1] = when .. "\\t" .. name
      end
    elseif owner == "WFJScan" then
      record.own = record.own + 1
    else
      record.others[name] = tostring(owner)
    end
  end
  local function fields(when, label, t)
    if type(t) ~= "table" then return end
    for key in pairs(t) do
      if type(key) == "string" then note(when, label .. "." .. key, issecurevariable(t, key)) end
    end
  end
  local function read(when)
    local frame = _G.ProfessionsFrame
    fields(when, "ProfessionsFrame", frame)
    local page = type(frame) == "table" and rawget(frame, "CraftingPage") or nil
    if type(page) == "table" then
      fields(when, "CraftingPage", page)
      fields(when, "CraftingPage.RankBar", rawget(page, "RankBar"))
      fields(when, "CraftingPage.SchematicForm", rawget(page, "SchematicForm"))
      local list = rawget(page, "RecipeList")
      fields(when, "CraftingPage.RecipeList", list)
      if type(list) == "table" then fields(when, "CraftingPage.RecipeList.ScrollBox", rawget(list, "ScrollBox")) end
    end
    for _, name in ipairs(CRAFT_FRAMES) do fields(when, name, _G[name]) end
  end
  local function readSafely(when)
    local ok, err = pcall(read, when)
    if not ok then record.failed = when .. ": " .. tostring(err) end
  end
  local api = C_TradeSkillUI
  if type(api) ~= "table" or type(api.OpenTradeSkill) ~= "function" or type(GetProfessions) ~= "function"
      or type(GetProfessionInfo) ~= "function" then
    record.refused = "the client has no OpenTradeSkill or GetProfessions"
    return done()
  end
  -- the first profession the character has: its two main ones, then cooking
  local owned = { GetProfessions() }
  local line
  for _, i in ipairs({ 1, 2, 5 }) do
    local index = owned[i]
    if index and not line then line = select(7, GetProfessionInfo(index)) end
  end
  if type(line) ~= "number" then
    record.refused = "the character has no profession with a crafting window"
    return done()
  end
  record.line = line
  local function shown()
    local frame = _G.ProfessionsFrame
    return type(frame) == "table" and frame:IsShown()
  end
  if shown() then
    record.refused = "the crafting window was already open"
    return done()
  end
  local function close()
    if type(api.CloseTradeSkill) == "function" then pcall(api.CloseTradeSkill) end
    C_Timer.After(0.5, done)
  end
  local function second()
    readSafely("window open")
    local ids = type(api.GetAllRecipeIDs) == "function" and api.GetAllRecipeIDs() or nil
    local pick
    for _, id in ipairs(type(ids) == "table" and ids or {}) do
      local info = type(api.GetRecipeInfo) == "function" and api.GetRecipeInfo(id) or nil
      if type(info) == "table" and info.learned then pick = id end
    end
    if not pick or type(api.OpenRecipe) ~= "function" then
      record.norecipe = true
      return close()
    end
    record.recipe = pick
    pcall(api.OpenRecipe, pick)
    C_Timer.After(1.5, function()
      readSafely("recipe opened")
      close()
    end)
  end
  -- one opening of the window, then `after()` once it shows (or the read ends, when it does not)
  local function open(after)
    local ok, err = pcall(api.OpenTradeSkill, line)
    if not ok then
      record.refused = "OpenTradeSkill raised: " .. tostring(err)
      return done()
    end
    local waited = 0
    local ticker
    ticker = C_Timer.NewTicker(0.25, function()
      waited = waited + 0.25
      if shown() then
        ticker:Cancel()
        record.shown = true
        return C_Timer.After(1.5, after)
      end
      if waited >= CRAFT_WAIT then
        ticker:Cancel()
        record.refused = "the crafting window did not open for skill line " .. tostring(line)
        done()
      end
    end)
  end
  open(second)
end
end)()

-- The frozen tooltip read. The freeze key draws a copy of the tooltip showing, so the mouse can rest on its words
-- (UI/TooltipFreeze); no sweep above presses it. This shows the tooltip of each item the character wears or
-- carries and runs what the key runs (`WFJ_FreezeTooltip`), twice, into `probe.freeze`:
--   bound    the key the binding has ("" for none)
--   items    tooltips frozen; lines  Japanese lines on the copies; cards  word-card covers laid on them
--   missing  an item whose copy did not show, or lacks a line the tooltip showed: a failure
--   stuck    an item whose copy the key did not close again over the same tooltip: a failure
--   cards    expected when Japanese shows with the reading box on (`expect`): none at all is a failure
local FREEZE_MAX = 40 -- items frozen: a few bags' worth tells as much as every one

local function shownTexts(frame, out)
  for _, r in ipairs({ frame:GetRegions() }) do
    if r.GetText and r:IsShown() then
      local text = r:GetText()
      if readable(text) then out[#out + 1] = { text = text, region = r } end
    end
  end
  return out
end

-- The Japanese on a copied line that no word card covers, as runs of characters: each covered byte comes from the
-- cover laid on the line's twin (its `text` and `spans`, UI/Readings), whose text is the line's own or the start of
-- it. Kana and kanji count; the ideographic punctuation block (E3 80) and the full-width forms (EF: ！？～：) do not.
local UNCARDED_MAX = 400
local function uncardedRuns(plain, cover)
  local covered = {}
  if cover then
    for _, sp in ipairs(cover.spans) do
      if type(sp.first) == "number" and type(sp.last) == "number" then
        for b = sp.first, sp.last do covered[b] = true end
      end
    end
  end
  local runs, run, i = {}, "", 1
  while i <= #plain do
    local c = plain:byte(i)
    local n = c >= 240 and 4 or c >= 224 and 3 or c >= 192 and 2 or 1
    local japanese = n == 3 and c >= 227 and c <= 233 and not (c == 227 and plain:byte(i + 1) == 128)
    if japanese and not covered[i] then
      run = run .. plain:sub(i, i + n - 1)
    elseif run ~= "" then
      runs[#runs + 1], run = run, ""
    end
    i = i + n
  end
  if run ~= "" then runs[#runs + 1] = run end
  return runs
end

-- The word status read. The known words window is the addon's own window, which no sweep opens: this opens it the
-- addon's own way (its slash command), reads it and hides it again. Then it puts a marked text on screen itself:
-- it opens the quest log on the character's first quest, the way the no-voice read does, waits for the pane, and
-- looks at every frame that carries word status marks (a word-card cover, a chat line's overlay). The quest log is
-- closed again when the read opened it. Into `probe.marks`:
--   quest    the quest whose text it showed; noquest  the character has no quest to show
--   on       the marks are switched on for quest text (a run with them off has nothing to read)
--   window   the text regions the known words window shows
--   english  with Japanese showing (`expect`), a text of that window holding no Japanese: a failure
--   frames   the frames that carry marks; shown  the marks showing on them
--   stale    a frame showing marks whose text is gone or is no longer what they were drawn for: a failure
--   bare     with no status saved yet and the underline on, visible marked texts with words and not one mark
--            between them: a failure (every word is unknown then, so a build that draws nothing shows here)
--   tags     a score tag showing something other than a percent: a failure
-- It changes no status: it clicks nothing and imports nothing.
local marksReader = CreateFrame("Frame")
local function WFJScanMarksRead(done)
  local db = probeDb()
  local saved = addonSettings() or {}
  local record = { window = 0, frames = 0, shown = 0, texts = 0, english = {}, stale = {}, tags = {},
    expect = saved.enabled ~= false and saved.direction ~= "en",
    on = saved.enabled ~= false and saved["marks.enabled"] ~= false and saved["marks.quest"] ~= false }
  db.marks = record
  local slash = type(SlashCmdList) == "table" and SlashCmdList.WFJ or nil
  if type(slash) ~= "function" then
    record.refused = "the addon has no slash command to run"
    return done()
  end
  local wasOpen = _G.WFJKnownWordsWindow and _G.WFJKnownWordsWindow:IsShown() or false
  local ok, err = pcall(function()
    if not wasOpen then slash("known") end
    local window = _G.WFJKnownWordsWindow
    if not (window and window:IsShown()) then
      record.refused = "the known words window did not open"
      return
    end
    for _, shown in ipairs(shownTexts(window, {})) do
      record.window = record.window + 1
      if record.expect and not hasJapanese(shown.text) then
        record.english[#record.english + 1] = shown.text
      end
    end
  end)
  if not ok then record.refused = tostring(err) end
  if not wasOpen and _G.WFJKnownWordsWindow then _G.WFJKnownWordsWindow:Hide() end
  local function look()
  -- One carrier of marks: `held` holds what the addon keeps about it, `frame` is what is on screen. A chat line's
  -- overlay is its own frame and holds its own fields; a cover's frame carries none, and its state is asked for.
  local function judge(held, frame)
    if frame:IsForbidden() then return end
    if type(held.markTex) ~= "table" and not (held.marksPlace and held.spans) then return end
    record.frames = record.frames + 1
    local showing = 0
    for _, mark in ipairs(held.markTex or {}) do
      if mark:IsShown() then showing = showing + 1 end
    end
    record.shown = record.shown + showing
    local owner = held.fs
    local now = owner and owner.GetText and owner:GetText() or held.text
    if showing > 0 and frame:IsVisible() and (held.text == nil or now ~= held.text) then
      record.stale[#record.stale + 1] = tostring(held.surface or "chat")
    end
    if held.marksPlace and held.spans and frame:IsVisible() then record.texts = record.texts + 1 end
    local tag = held.scoreFs
    if tag and tag:IsShown() and frame:IsVisible() then
      local said = tag:GetText()
      if type(said) ~= "string" or not said:find("%%d+%%%%") then record.tags[#record.tags + 1] = tostring(said) end
    end
  end
  local frame = EnumerateFrames()
  while frame do
    pcall(function()
      if type(frame.markTex) == "table" then judge(frame, frame) end
    end)
    frame = EnumerateFrames(frame)
  end
  for _, state in ipairs(WFJScanTaint.coverStates()) do pcall(judge, state, state.frame) end
  local known = type(WFJ_Known) == "table" and type(WFJ_Known.ja) == "table" and WFJ_Known.ja or {}
  record.bare = record.texts > 0 and record.shown == 0 and next(known) == nil
    and saved["marks.enabled"] ~= false and saved["marks.underline"] ~= false
    and saved["marks.quest"] ~= false or false
  end
  local opened = false
  local fine, why = pcall(function()
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
      local info = C_QuestLog.GetInfo(i)
      if type(info) == "table" and not info.isHeader and not info.isHidden and type(info.questID) == "number" then
        record.quest = info.questID
        break
      end
    end
    if not record.quest then return end
    if not (QuestMapFrame and QuestMapFrame:IsVisible()) then
      ToggleQuestLog()
      opened = true
    end
    QuestMapFrame_ShowQuestDetails(record.quest)
  end)
  if not fine then record.refused = tostring(why) end
  if not record.quest then
    record.noquest = true
    look()
    return done()
  end
  local ticks = 0
  marksReader:SetScript("OnUpdate", function()
    ticks = ticks + 1
    if ticks < NOVOICE_TICKS then return end
    marksReader:SetScript("OnUpdate", nil)
    pcall(look)
    if opened then pcall(ToggleQuestLog) end -- closed again, the way it was opened
    done()
  end)
end

-- The chat tools read. The phrase book's card and the player's own chat words window are the addon's own windows:
-- no sweep above opens them. This opens each the addon's own way (its slash command), reads it and closes it
-- again, into `probe.chat`:
--   topics   the card's topic tabs; phrases  the phrase rows read over every topic
--   blank    a tab with no words on it or with its words cut off, or a phrase row missing a line: a failure
--   sizes    the card's size on each topic: more than one is a failure (the card must not move under the mouse)
--   english  with Japanese showing (`expect`), a heading, tab or label holding no Japanese: a failure
--   words    the text regions the chat words window shows
--   list     the text regions the word list window shows (`/wfj words`), read here because it is opened the same way
--   stuck    the card still showing after the command that closes it: a failure
--   secretLines    the chat lines on screen whose text the client keeps secret
--   secretAnswers  what such a line answers with a secret (IsVisible, GetAlpha, ...)
-- It types nothing into chat and sends nothing: it never clicks a phrase.
local function WFJScanChatRead()
  local db = probeDb()
  local settings = addonSettings() or {}
  local record = { topics = 0, phrases = 0, words = 0, list = 0, blank = {}, sizes = {}, english = {},
    expect = settings.enabled ~= false and settings.direction ~= "en" }
  db.chat = record
  local slash = type(SlashCmdList) == "table" and SlashCmdList.WFJ or nil
  if type(slash) ~= "function" then
    record.refused = "the addon has no slash command to run"
    return
  end
  local function judge(what, text)
    if record.expect and readable(text) and not hasJapanese(text) then
      record.english[#record.english + 1] = what .. "\t" .. text
    end
  end
  -- the chat lines on screen whose text the client keeps secret: how many, and which questions about itself such
  -- a line answers with a secret (asked, never tested). The game cannot be made to show one, so a run with none
  -- proved nothing about them and says so.
  record.secretLines, record.secretAnswers = 0, {}
  local kept = {}
  for _, name in ipairs(type(CHAT_FRAMES) == "table" and issecretvalue and CHAT_FRAMES or {}) do
    local chat = _G[name]
    for _, line in ipairs(type(chat) == "table" and type(chat.visibleLines) == "table" and chat.visibleLines or {}) do
      if issecretvalue(line:GetText()) then
        record.secretLines = record.secretLines + 1
        for _, method in ipairs({ "IsVisible", "IsShown", "GetAlpha", "IsMouseOver", "GetWidth" }) do
          if issecretvalue(line[method](line)) then kept[method] = true end
        end
      end
    end
  end
  for method in pairs(kept) do record.secretAnswers[#record.secretAnswers + 1] = method end
  table.sort(record.secretAnswers)
  -- as the player left them: a card already open stays open, a button hidden for the session stays hidden
  local wasOpen = _G.WFJPhraseCard and _G.WFJPhraseCard:IsShown() or false
  local hadButton = _G.WFJPhraseButton and _G.WFJPhraseButton:IsShown() or false
  local ok, err = pcall(function()
    if not wasOpen then slash("phrases") end
    local card = _G.WFJPhraseCard
    if not (card and card:IsShown()) then
      record.refused = "the phrase card did not open"
      return
    end
    judge("phrase card heading", card.title and card.title:GetText())
    judge("phrase card foot", card.foot and card.foot:GetText())
    local sizes = {}
    for _, tab in ipairs(type(card.tabs) == "table" and card.tabs or {}) do
      record.topics = record.topics + 1
      local name = tostring(tab.topic)
      local said = tab.Text and tab.Text:GetText()
      if not readable(said) then
        record.blank[#record.blank + 1] = "tab " .. name .. "\tno words"
      elseif tab.Text.IsTruncated and tab.Text:IsTruncated() then
        record.blank[#record.blank + 1] = "tab " .. name .. "\tcut off: " .. said
      else
        judge("tab " .. name, said)
      end
      if card.tabSystem and card.tabSystem.SetTab then card.tabSystem:SetTab(tab.tabID) end
      sizes[math.floor(card:GetWidth() + 0.5) .. "x" .. math.floor(card:GetHeight() + 0.5)] = true
      local shown = 0
      for n, row in ipairs(type(card.rows) == "table" and card.rows or {}) do
        if row:IsShown() then
          shown = shown + 1
          local ja, en = row.ja and row.ja:GetText(), row.en and row.en:GetText()
          if not readable(ja) or not readable(en) then
            record.blank[#record.blank + 1] = "topic " .. name .. " row " .. n .. "\ta line is missing"
          elseif not hasJapanese(ja) then
            record.blank[#record.blank + 1] = "topic " .. name .. " row " .. n .. "\tno Japanese: " .. ja
          end
        end
      end
      if shown == 0 then record.blank[#record.blank + 1] = "topic " .. name .. "\tno phrases" end
      record.phrases = record.phrases + shown
    end
    for size in pairs(sizes) do record.sizes[#record.sizes + 1] = size end
    table.sort(record.sizes)
    if not wasOpen then
      slash("phrases") -- the same command closes the card
      if card:IsShown() then
        record.stuck = true
        card:Hide()
      end
    end
    -- the copy box, opened by the copy icon's own click handler on a line of this read's own (no chat line is read)
    local icon = _G.WFJChatCopyButton
    local click = icon and icon:GetScript("OnClick")
    if not click then
      record.refusedCopy = "the copy icon was not made"
    else
      local line, text = icon.line, icon.text
      icon.line, icon.text = {}, "|cffffffffWFJ テスト|r"
      local clicked, why = pcall(click, icon)
      icon.line, icon.text = line, text
      local box = _G.WFJChatCopyWindow
      if not clicked then
        record.refusedCopy = tostring(why)
      elseif not (box and box:IsShown()) then
        record.refusedCopy = "the copy box did not open"
      else
        record.copy = box.field and box.field.getText and box.field.getText() or ""
        judge("copy box heading", box.title and box.title:GetText())
        judge("copy box foot", box.foot and box.foot:GetText())
        box:Hide()
      end
    end
    slash("chatwords")
    local window = _G.WFJChatWordsWindow
    if not (window and window:IsShown()) then
      record.refusedWords = "the chat words window did not open"
      return
    end
    for _, shown in ipairs(shownTexts(window, {})) do
      record.words = record.words + 1
      judge("chat words window", shown.text)
    end
    window:Hide()
    slash("words")
    local list = _G.WFJWordsWindow
    if not (list and list:IsShown()) then
      record.refusedList = "the word list window did not open"
      return
    end
    -- its labels sit on its page, a child frame, not on the window itself
    for _, holder in ipairs({ list, list.page }) do
      for _, shown in ipairs(shownTexts(holder, {})) do
        record.list = record.list + 1
        judge("word list window", shown.text)
      end
    end
    -- its last row, the Anki add-on's address, is placed under whatever rows show: it must end inside the window
    local last = list.addonBox
    local bottom, floor = last and last:GetBottom(), list:GetBottom()
    if not (bottom and floor) then
      record.refusedList = "the word list window has no add-on line to measure"
    elseif bottom < floor then
      record.refusedList = "the word list window's add-on line ends below the window"
    end
    list:Hide()
  end)
  if not ok then record.refused = tostring(err) end
  local card, button = _G.WFJPhraseCard, _G.WFJPhraseButton
  if card and not wasOpen and card:IsShown() then card:Hide() end
  if button and not hadButton and button:IsShown() then button:Hide() end
end

-- The secret chat line try. The client keeps some chat text secret, and a line holding it answers questions about
-- itself (is it visible, how faint, is the mouse on it) with secret values, which tainted code may not test. No
-- such line can be ordered up, so the test makes its own with `secretwrap` and puts them where the chat tools
-- look: a chat frame of the test's own, listed in CHAT_FRAMES until they have looked (three seconds at most),
-- that says the mouse is on it. It holds two lines: a real text region given secret text (what it answers is what a secret chat line
-- answers, kept in `answers`), and a line that answers every question with a secret. An error the chat tools
-- throw on either is caught like any other error of the run. `looks` counts the looks the chat tools took.
local function WFJScanSecretLine(done)
  local db = probeDb()
  db.chat = db.chat or {}
  local try = { looks = 0, answers = {} }
  db.chat.secretTry = try
  if type(secretwrap) ~= "function" or type(issecretvalue) ~= "function" or type(CHAT_FRAMES) ~= "table" then
    try.refused = "this client has no secretwrap, issecretvalue or CHAT_FRAMES"
    return done()
  end
  local ASKED = { "IsVisible", "IsShown", "GetAlpha", "IsMouseOver", "GetWidth", "GetText" }
  local holder, real
  local every = {}
  -- a client that refuses any of this proves nothing here and says why; nothing is listed until it all worked
  local made, why = pcall(function()
    holder = CreateFrame("Frame", nil, UIParent)
    holder:SetSize(200, 20)
    holder:SetPoint("BOTTOMLEFT", UIParent, "TOPLEFT", 0, 40) -- shown, and off the screen
    real = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    real:SetPoint("LEFT")
    real:SetText(secretwrap("WFJ secret line"))
    for _, method in ipairs(ASKED) do
      local ok, answer = pcall(real[method], real)
      if ok and issecretvalue(answer) then try.answers[#try.answers + 1] = method end
    end
    for _, method in ipairs(ASKED) do
      local plain = method == "GetText" and "WFJ secret line" or (method == "GetAlpha" or method == "GetWidth") and 1
      if plain == false then plain = true end
      every[method] = function() return secretwrap(plain) end
    end
  end)
  if not made then
    try.refused = tostring(why)
    if holder then holder:Hide() end
    return done()
  end
  -- anything else asked of the frame, by the client's own walks of CHAT_FRAMES too, is a call that does nothing
  local NAME = "WFJScanSecretChat"
  local frame = setmetatable({ visibleLines = { real, every } },
    { __index = function() return function() end end })
  frame.IsVisible = function() return true end
  -- the client's own walk of CHAT_FRAMES on every frame (FCF_OnUpdate) reads a shown chat frame's parts: this one
  -- says it is not shown there, and the chat tools ask IsVisible
  frame.IsShown = function() return false end
  frame.IsMouseOver = function()
    try.looks = try.looks + 1
    return true
  end
  _G[NAME] = frame
  CHAT_FRAMES[#CHAT_FRAMES + 1] = NAME
  -- until the chat tools have looked a few times, or three seconds: in a whole run a single slow frame can be
  -- longer than any fixed wait, and the wait would end before their timer had a turn
  local started, turns = GetTime(), 0
  local function wait()
    turns = turns + 1
    if try.looks < 3 and GetTime() - started < 3 then return C_Timer.After(0.1, wait) end
    try.turns, try.seconds = turns, GetTime() - started
    for i = #CHAT_FRAMES, 1, -1 do
      if CHAT_FRAMES[i] == NAME then table.remove(CHAT_FRAMES, i) end
    end
    _G[NAME] = nil
    holder:Hide()
    done()
  end
  C_Timer.After(0.1, wait)
end

local function WFJScanFreezeRead(done)
  local db = probeDb()
  local settings = addonSettings() or {}
  -- uncarded: { "<what was frozen>\t<covered: none | part>\t<line>\t<runs joined by a space>" }
  local record = { items = 0, spells = 0, lines = 0, cards = 0, missing = {}, stuck = {}, uncarded = {},
    bound = GetBindingKey("WFJ_FREEZE_TOOLTIP") or "",
    expect = settings.enabled ~= false and settings.direction ~= "en" and settings["readings.enabled"] ~= false }
  db.freeze = record
  if type(WFJ_FreezeTooltip) ~= "function" then
    record.refused = "the addon has no freeze binding to run"
    return done()
  end
  done = collectorPaused(done) -- it shows tooltips, as the tooltip read does
  local function freeze(id, show, counter)
    counter = counter or "items"
    if record[counter] >= FREEZE_MAX then return end
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("CENTER", UIParent, "CENTER")
    show()
    if not GameTooltip:IsShown() or (GameTooltip:NumLines() or 0) == 0 then return end
    record[counter] = record[counter] + 1
    local want = {}
    for i = 1, GameTooltip:NumLines() do
      for _, side in ipairs({ "Left", "Right" }) do
        local region = _G["GameTooltipText" .. side .. i]
        local text = region and region:IsShown() and region:GetText()
        if readable(text) then want[#want + 1] = text end
      end
    end
    WFJ_FreezeTooltip()
    local copy = _G.WFJFrozenTooltip1
    if not (copy and copy:IsShown()) then
      record.missing[tostring(id)] = "no copy showed"
      return
    end
    local got = {}
    for _, t in ipairs(shownTexts(copy, {})) do
      got[t.text] = true
      -- the twin a coloured line is measured on is drawn at no opacity: it is not a line of its own
      if hasJapanese(t.text) and not (t.region.GetAlpha and t.region:GetAlpha() == 0) then
        record.lines = record.lines + 1
      end
    end
    local lost = 0
    for _, text in ipairs(want) do if not got[text] then lost = lost + 1 end end
    if lost > 0 then record.missing[tostring(id)] = lost .. " of " .. #want .. " lines not on the copy" end
    local covers = {}
    for _, child in ipairs({ copy:GetChildren() }) do
      if child ~= copy.NineSlice and child:IsShown() and child.IsMouseMotionEnabled and child:IsMouseMotionEnabled() then
        record.cards = record.cards + 1
      end
    end
    -- the covers laid on this copy, as the addon holds them: a cover's frame carries no field to read
    for _, state in ipairs(WFJScanTaint.coverStates()) do
      if type(state.text) == "string" and type(state.spans) == "table" and state.frame:IsShown()
          and state.frame:GetParent() == copy then
        covers[#covers + 1] = state
      end
    end
    -- every Japanese character of every copied line: under a word card or not
    for _, t in ipairs(shownTexts(copy, {})) do
      if hasJapanese(t.text) and not (t.region.GetAlpha and t.region:GetAlpha() == 0)
        and #record.uncarded < UNCARDED_MAX then
        -- as the copy's twin holds it: no colour codes, a line break escape as a line break
        local plain = t.text:gsub("|c%%x%%x%%x%%x%%x%%x%%x%%x", ""):gsub("|r", ""):gsub("|n", "\\n")
        local cover
        for _, c in ipairs(covers) do
          if c.text ~= "" and plain:sub(1, #c.text) == c.text then cover = c end
        end
        local runs = uncardedRuns(plain, cover)
        if runs[1] then
          -- the words the line's cards do cover, so a missing one can be told from a misplaced one
          local had = {}
          for _, sp in ipairs(cover and cover.spans or {}) do
            if type(sp.first) == "number" and type(sp.last) == "number" then had[#had + 1] = plain:sub(sp.first, sp.last) end
          end
          record.uncarded[#record.uncarded + 1] = table.concat({ counter .. " " .. tostring(id),
            cover and ("part:" .. table.concat(had, ",")) or "none", (plain:gsub("[\\t\\n]", " ")),
            table.concat(runs, " ") }, "\\t")
        end
      end
    end
    WFJ_FreezeTooltip() -- the same tooltip still shows: the key closes the copy
    if copy:IsShown() then
      record.stuck[tostring(id)] = "the key over the same tooltip left the copy showing"
      copy:Hide()
    end
  end
  local ok, err = pcall(function()
    for slot = 1, 19 do
      local id = GetInventoryItemID("player", slot)
      if id then freeze(id, function() GameTooltip:SetInventoryItem("player", slot) end) end
    end
    for bag = 0, 4 do
      for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
        local id = C_Container.GetContainerItemID(bag, slot)
        if id then freeze(id, function() GameTooltip:SetBagItem(bag, slot) end) end
      end
    end
    -- the spells the character knows among those that ship Japanese: a spell tooltip's lines (cost, range, cast
    -- time, cooldown, reagents, requirements) are kinds an item's lack
    if type(IsPlayerSpell) == "function" then
      local ids = {}
      for sid in pairs(VALUES) do ids[#ids + 1] = sid end
      table.sort(ids)
      for _, sid in ipairs(ids) do
        if IsPlayerSpell(sid) then freeze(sid, function() GameTooltip:SetSpellByID(sid) end, "spells") end
      end
    end
  end)
  if not ok then record.refused = tostring(err) end
  if _G.WFJFrozenTooltip1 and _G.WFJFrozenTooltip1:IsShown() then _G.WFJFrozenTooltip1:Hide() end
  GameTooltip:Hide()
  done()
end

-- The character window, opened by the player (see above): read every half second while it is open, so each page
-- the player shows is read; it ends when the player closes it. Not opened in time, the run says so. What was read
-- is kept from the first read on, and a reload while the window is open ends the run as closing it does: the
-- player has done the step either way, and the read must not be lost with it.
local characterReader = CreateFrame("Frame")
-- the top frame of each window the player opens: the hover read points only at frames under it
local HAND_FRAMES = { guild = "CommunitiesFrame", character = "CharacterFrame" }
-- One window the player opens: `name` as the result files it, `shown` whether it is open, `ASK` what to do.
local function playerRead(name, shown, ASK, done)
  local db = probeDb()
  local record = { english = {}, japanese = 0, boxes = {}, latin = namesOn() and {} or nil }
  local waited, sinceRead, opened = 0, CHARACTER_READ, false
  local roots = {} -- found when the window opens: the guild window's addon may load only then
  -- said in chat and in the middle of the screen, and again every few seconds until the window opens: one chat
  -- line is easy to miss, and a reload before this step ends leaves the run unfinished
  local sinceAsk = CHARACTER_ASK
  characterReader:SetScript("OnUpdate", function(_, elapsed)
    -- the tooltip the hover read raised on the last frame is read and put away first: the screen read must not
    -- take it for the window's own text, and a window closed meanwhile leaves none up
    hoverStep(true)
    if not opened then
      sinceAsk = sinceAsk + elapsed
      if sinceAsk >= CHARACTER_ASK then
        sinceAsk = 0
        print(ASK)
        pcall(function() UIErrorsFrame:AddMessage(ASK, 1, 0.82, 0) end)
      end
    end
    if shown() then
      if not opened then
        opened = true
        db.live[name] = record
        local top = _G[HAND_FRAMES[name]]
        if type(top) == "table" then roots[top] = true end
        print("WFJ test: reading the " .. name .. " window. Click its tabs, then close it")
      end
      sinceRead = sinceRead + elapsed
      if sinceRead >= CHARACTER_READ then
        sinceRead = 0
        local screen = readScreen()
        for name, text in pairs(screen.english) do record.english[name] = text end
        for name, font in pairs(screen.boxes) do record.boxes[name] = font end
        if record.latin then
          for name, text in pairs(screen.latin or {}) do record.latin[name] = text end
        end
        record.japanese = math.max(record.japanese, screen.japanese)
        -- each page the player shows brings frames of its own to point at
        hoverBegin(name, roots)
      end
      hoverStep()
      return
    end
    waited = waited + elapsed
    if not opened and waited < CHARACTER_WAIT then return end
    characterReader:SetScript("OnUpdate", nil)
    characterReader:UnregisterEvent("PLAYER_LOGOUT")
    if not opened then
      db.test.unopened = db.test.unopened or {}
      db.test.unopened[name] = "not opened when the test asked (an addon cannot open it without an error)"
    end
    done()
  end)
  characterReader:RegisterEvent("PLAYER_LOGOUT")
  characterReader:SetScript("OnEvent", function()
    if not opened then return end
    characterReader:SetScript("OnUpdate", nil)
    done()
  end)
end

-- Two chat lines before the done line: what fails the run, and what was left English without a fault, by kind.
-- The window lines are counted before the baseline is applied; `make window-test` applies it and lists each line.
local function keysIn(t)
  local n = 0
  for _ in pairs(type(t) == "table" and t or {}) do n = n + 1 end
  return n
end
local function sayCounts(db)
  local test = type(db.test) == "table" and db.test or {}
  local tips = type(db.tooltips) == "table" and db.tooltips or {}
  local novoice = type(db.novoice) == "table" and db.novoice or {}
  local hovered, hoverRows = 0, 0
  for _, rec in pairs(type(db.hover) == "table" and db.hover or {}) do
    hovered = hovered + (tonumber(rec.made) or 0)
    hoverRows = hoverRows + keysIn(rec.english) + keysIn(rec.runs)
  end
  print("WFJ test: faults: " .. (keysIn(test.errors) + keysIn(test.blocked) + keysIn(test.warnings))
    .. " errors or refused actions, " .. keysIn(tips.wrong) .. " tooltips with numbers in the wrong places, "
    .. keysIn(tips.folded) .. " items written over, " .. keysIn(novoice.wrong) .. " wrong no-voice messages, "
    .. hoverRows .. " English rows or words on " .. hovered .. " hovered frames' tooltips, before names and the baseline")
  local by, holes = {}, 0
  for _, row in pairs(type(tips.left) == "table" and tips.left or {}) do
    if row.reason == "hole" then holes = holes + 1 else by[row.reason] = (by[row.reason] or 0) + 1 end
  end
  local parts = {}
  for _, reason in ipairs({ "icon", "values", "words", "name", "number", "none", "other" }) do
    if by[reason] then parts[#parts + 1] = reason .. " " .. by[reason] end
  end
  local windows = 0
  for window, screen in pairs(type(db.live) == "table" and db.live or {}) do
    if window ~= "(nothing open)" and type(screen) == "table" then windows = windows + keysIn(screen.english) end
  end
  print("WFJ test: left English, not a fault: spells " .. (#parts > 0 and table.concat(parts, ", ") or "0")
    .. " (and " .. holes .. " gaps the client printed), items " .. keysIn(tips.leftItems) .. ", window lines "
    .. windows .. "; make window-test lists them")
end

local function WFJScanCharacterRead(done)
  playerRead("character", characterShown,
    "WFJ test: NOT DONE YET. Open the character window (press C), click its tabs, then close it", done)
end

-- The guild window is the player's to open as well. Opened and paged by the test, every click on one of its
-- tabs redraws the list of communities from addon code (CommunitiesTabs.lua:3-6 → SetDisplayMode →
-- CommunitiesList.lua:523), and the client refuses that list's icon call to an addon each time
-- (C_Club.SetAvatarTexture: an ADDON_ACTION_BLOCKED per row). Read while the player pages it, nothing is
-- refused. A character in no guild shows none of the guild's pages (the roster, the info tab with the message
-- of the day): the run did not look at them, and says so instead of passing them.
local function guildShown()
  return type(CommunitiesFrame) == "table" and CommunitiesFrame:IsShown()
end
local function WFJScanGuildRead(done)
  if type(IsInGuild) == "function" and not IsInGuild() then
    local db = probeDb()
    db.test.unopened = db.test.unopened or {}
    db.test.unopened["guild pages"] = "this character is in no guild"
    return done()
  end
  playerRead("guild", guildShown,
    "WFJ test: NOT DONE YET. Open the guild window (press J), click its tabs, then close it", done)
end

-- ── Windows read as the player opens them ───────────────────────────────────────────────────────────────────────
-- A window the client opens for the player (a key, a click on an NPC, a micro button) is opened by the client's own
-- code in a run that carries no addon's taint. If that code reads a value the addon wrote, everything it writes from
-- there carries the addon's name: the window's fields, then the bags and the action bars. The test cannot see that
-- when it opens the window itself (its own taint comes first), so every window is read here as play opens it: the
-- client's ShowUIPanel is followed with a post-hook, and the events of the NPC windows are listened for. A second
-- after a window shows, its fields, the fields of the tables and frames under it, the bag buttons and the action
-- buttons are read for the addon's taint. Nothing is opened, clicked or written. Into `WFJScanDB.watch`, started
-- again for another client build or addon code:
--   windows[<frame>] = { opens, reads, checked, at, ours = { "<name>" } }   ours: a failure
;(function()
  local WATCH_DEPTH = 4 -- tables under a window that are read
  local WATCH_KEYS = 40000 -- values read per window (the first run stopped at 6,000 on every window)
  local WATCH_READS = 3 -- reads of one window per build and addon code
  local WATCH_OURS = 60
  local WATCH_ALWAYS = { "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot",
    "CharacterReagentBag0Slot", "MainMenuBarBackpackButton", "ContainerFrameCombinedBags", "ContainerFrame1",
    "ContainerFrame2", "ContainerFrame3", "ContainerFrame4", "ContainerFrame5", "ContainerFrame6", "MerchantFrame",
    "MainMenuBar", "MainActionBar", "ActionButton1", "ActionButton2", "ActionButton12", "MultiBarBottomLeftButton1",
    "MultiBarBottomRightButton1", "MultiBarRightButton1", "MultiBarLeftButton1", "StanceButton1", "PetActionButton1" }
  local WATCH_EVENTS = { MERCHANT_SHOW = "MerchantFrame", GOSSIP_SHOW = "GossipFrame", QUEST_DETAIL = "QuestFrame",
    QUEST_GREETING = "QuestFrame", QUEST_PROGRESS = "QuestFrame", QUEST_COMPLETE = "QuestFrame", MAIL_SHOW = "MailFrame",
    BANKFRAME_OPENED = "BankFrame", AUCTION_HOUSE_SHOW = "AuctionHouseFrame", TRAINER_SHOW = "ClassTrainerFrame",
    TAXIMAP_OPENED = "TaxiFrame", LOOT_OPENED = "LootFrame", TRADE_SHOW = "TradeFrame",
    ITEM_TEXT_BEGIN = "ItemTextFrame", TRADE_SKILL_SHOW = "ProfessionsFrame", GUILDBANKFRAME_OPENED = "GuildBankFrame" }

  local function watchDb()
    if type(WFJScanDB) ~= "table" then return nil end
    local build = tostring((select(2, GetBuildInfo())))
    local w = WFJScanDB.watch
    if type(w) ~= "table" or w.code ~= WFJScanAddonCode or w.build ~= build or type(w.windows) ~= "table" then
      -- what the last code or build left in the addon's name is still worth tracing on this one
      local suspects = {}
      for _, rec in pairs(type(w) == "table" and type(w.windows) == "table" and w.windows or {}) do
        for _, path in ipairs(type(rec.ours) == "table" and rec.ours or {}) do suspects[#suspects + 1] = path end
      end
      for _, path in ipairs(type(w) == "table" and type(w.suspects) == "table" and w.suspects or {}) do
        suspects[#suspects + 1] = path
      end
      w = { code = WFJScanAddonCode, build = build, windows = {}, suspects = suspects }
      WFJScanDB.watch = w
    end
    return w
  end

  -- Whether the frame `f` sits under `root` (a table that is no frame counts as under it: a window's own data).
  local function watchUnder(root, f)
    if type(f.GetParent) ~= "function" then return true end
    local at = f
    for _ = 1, 12 do
      if at == root then return true end
      local ok, parent = pcall(at.GetParent, at)
      if not ok or type(parent) ~= "table" then return false end
      at = parent
    end
    return false
  end

  -- The reads waiting, done a little per frame: nothing here may be long enough to see, and a window with a few
  -- thousand values is. A job is a stack of tables still to read, each with the key it was left at.
  local WATCH_MS = 2 -- milliseconds of reading per frame drawn
  local jobs = {}
  local pump -- the frame whose OnUpdate does the reading, made at the first read
  local function push(job, t, name, depth)
    if type(t) ~= "table" or job.seen[t] then return end
    local okF, forbidden = pcall(function() return type(t.IsForbidden) == "function" and t:IsForbidden() end)
    if not okF or forbidden then return end
    job.seen[t] = true
    job.stack[#job.stack + 1] = { t = t, name = name, depth = depth }
    if depth < WATCH_DEPTH and type(t.GetChildren) == "function" then
      local ok, children = pcall(function() return { t:GetChildren() } end)
      for i, child in ipairs(ok and children or {}) do push(job, child, name .. ".#" .. i, depth + 1) end
    end
  end
  -- One key of the job's top table. → false when the job has nothing left
  local function step(job)
    local top = job.stack[#job.stack]
    if not top or job.left <= 0 then return false end
    local ok, key, value = pcall(next, top.t, top.at)
    if not ok or key == nil then
      job.stack[#job.stack] = nil
      return true
    end
    top.at = key
    if type(key) == "string" then
      job.left = job.left - 1
      local okS, isSecure, owner = pcall(issecurevariable, top.t, key)
      if okS then job.visit(top.name .. "." .. key, isSecure, owner) end
      if top.depth < WATCH_DEPTH and type(value) == "table" and watchUnder(job.root, value) then
        push(job, value, top.name .. "." .. key, top.depth + 1)
      end
    end
    return true
  end
  local function pumpStart()
    if not pump then
      pump = CreateFrame("Frame")
      pump:SetScript("OnUpdate", function(self)
        local started = debugprofilestop()
        while jobs[1] do
          if not step(jobs[1]) then table.remove(jobs, 1) end
          if debugprofilestop() - started >= WATCH_MS then return end
        end
        self:Hide()
      end)
    end
    pump:Show()
  end

  local watchPending = {}
  local watchStep -- the names of the windows shown while the open step runs, when it runs

  -- One read of the window `name`, queued. `always` reads it whatever the count (the open step's own windows).
  local function watchRead(name, frame, always)
    local w = watchDb()
    if not w or type(frame) ~= "table" then return end
    local rec = w.windows[name]
    if type(rec) ~= "table" then
      rec = { opens = 0, reads = 0, checked = 0, ours = {} }
      w.windows[name] = rec
    end
    rec.opens = rec.opens + 1
    -- a window whose last read found something is read again at every open, until a read finds it clean: a
    -- finding from before a fix must not stand for good because the window had used up its reads
    if not always and rec.reads >= WATCH_READS and #rec.ours == 0 then return end
    rec.reads = rec.reads + 1
    rec.at = date("%%Y-%%m-%%d %%H:%%M:%%S")
    -- each read starts its list again: a value an earlier read (or an earlier session, before a fix) found in the
    -- addon's name is a finding of that read, not of this one
    local listed = {}
    rec.ours = {}
    local job = { root = frame, stack = {}, seen = {}, left = WATCH_KEYS }
    function job.visit(n, isSecure, owner)
      rec.checked = rec.checked + 1
      if not isSecure and owner == "WoWForeverJapanese" and not listed[n] and #rec.ours < WATCH_OURS then
        listed[n] = true
        rec.ours[#rec.ours + 1] = n
      end
    end
    -- the bag and bar buttons first on the stack, so they are read last and only their own fields
    for _, global in ipairs(WATCH_ALWAYS) do
      local t = _G[global]
      if type(t) == "table" and t ~= frame and not job.seen[t] then
        job.seen[t] = true
        job.stack[#job.stack + 1] = { t = t, name = global, depth = WATCH_DEPTH }
      end
    end
    push(job, frame, name, 0)
    jobs[#jobs + 1] = job
    pumpStart()
  end

  local function watchShown(frame, always)
    if type(frame) ~= "table" or type(frame.GetName) ~= "function" then return end
    local ok, name = pcall(frame.GetName, frame)
    if not ok or type(name) ~= "string" or name == "" or watchPending[name] then return end
    if watchStep then watchStep[#watchStep + 1] = name end
    watchPending[name] = true
    C_Timer.After(1, function()
      watchPending[name] = nil
      pcall(watchRead, name, frame, always or watchStep ~= nil)
    end)
  end

  -- Every action the client refuses an addon, in play: the result the reads above look for the cause of. Kept per
  -- addon and action with how often, whether in a fight, and when first and last; and the fights the session saw,
  -- so "none refused" can be told from "never fought". Into `WFJScanDB.watch`:
  --   refused[<addon>\t<action>] = { n, fights, first, last }; fights  fights begun; fightSeconds  time in them
  local fightBegan
  local function watchRefused(addon, action)
    local w = watchDb()
    if not w then return end
    w.refused = type(w.refused) == "table" and w.refused or {}
    local key = tostring(addon) .. "\t" .. tostring(action)
    local rec = w.refused[key]
    local at = date("%%Y-%%m-%%d %%H:%%M:%%S")
    if type(rec) ~= "table" then
      rec = { n = 0, fights = 0, first = at }
      w.refused[key] = rec
    end
    rec.n = rec.n + 1
    if InCombatLockdown() then rec.fights = rec.fights + 1 end
    rec.last = at
  end
  local function watchFight(began)
    local w = watchDb()
    if not w then return end
    if began then
      fightBegan = GetTime()
      w.fights = (tonumber(w.fights) or 0) + 1
    elseif fightBegan then
      w.fightSeconds = math.floor((tonumber(w.fightSeconds) or 0) + GetTime() - fightBegan)
      fightBegan = nil
    end
  end

  -- Who wrote it. A value the watcher found in the addon's name says nothing about the call that wrote it. So at the
  -- next login, before the window is shown again, every function of the tables on the way to that value gets a
  -- post-hook, and the first one after which the value reads in the addon's name is kept with its call stack: the
  -- stack runs from that function back to what called it. Into `WFJScanDB.watch.traces`:
  --   { path, after = "<table>:<function>", stack }
  local TRACE_SKIP = { scrollPercentage = true, visibleExtentPercentage = true, panExtentPercentage = true,
    updateLock = true }
  local TRACE_MAX = 12
  -- the table a watched name leads to and its last key: "CharacterFrame.#19.#4.#9.factionID"
  local function traceResolve(path, upTo)
    local parts = {}
    for part in path:gmatch("[^.]+") do parts[#parts + 1] = part end
    local t = _G[parts[1]]
    for i = 2, (upTo or #parts - 1) do
      if type(t) ~= "table" then return nil end
      local index = parts[i]:match("^#(%%d+)$")
      if index then
        local ok, children = pcall(function() return { t:GetChildren() } end)
        t = ok and children[tonumber(index)] or nil
      else
        t = rawget(t, parts[i])
      end
    end
    return type(t) == "table" and t or nil, parts[#parts], #parts
  end
  local function traceArm()
    local w = watchDb()
    if not w then return end
    local pending, hooked, labels = {}, {}, {}
    local function want(path)
      if type(path) == "string" and not TRACE_SKIP[path:match("([^.]+)$") or ""] then
        pending[path] = function() return traceResolve(path) end
      end
    end
    for _, rec in pairs(w.windows) do
      for _, path in ipairs(type(rec.ours) == "table" and rec.ours or {}) do want(path) end
    end
    for _, path in ipairs(type(w.suspects) == "table" and w.suspects or {}) do want(path) end
    -- nothing to trace: no hook is placed, so a session the watcher found nothing in stays free of the test's own
    -- code inside the player's clicks
    if next(pending) == nil then return end
    w.traces = {}
    -- what else on the tables being watched reads in the addon's name at that moment: what the writer may have read
    local function near()
      local out = {}
      for t, label in pairs(labels) do
        for key in pairs(t) do
          if type(key) == "string" and #out < 30 then
            local ok, isSecure, owner = pcall(issecurevariable, t, key)
            if ok and not isSecure and owner == "WoWForeverJapanese" then out[#out + 1] = label .. "." .. key end
          end
        end
      end
      table.sort(out)
      return table.concat(out, " | ")
    end
    -- the keys of the watched tables that read in the addon's name, each noted the first time with the function it
    -- showed up after: the first of them is where the addon's name came into the client's run
    local known = {}
    w.entered = {}
    local function entered(label)
      for t, name in pairs(labels) do
        for key in pairs(t) do
          if type(key) == "string" and not known[name .. "." .. key] then
            local ok, isSecure, owner = pcall(issecurevariable, t, key)
            if ok and not isSecure and owner == "WoWForeverJapanese" then
              known[name .. "." .. key] = true
              if #w.entered < 30 then
                w.entered[#w.entered + 1] = { key = name .. "." .. key, after = label, at = date("%%H:%%M:%%S"),
                  stack = #w.entered < 6 and debugstack(4, 30, 30) or nil }
              end
            end
          end
        end
      end
    end
    local checking = false
    local function check(label)
      -- its own reads may run a hooked function (a frame that keeps GetChildren as a field): never from inside
      if checking then return end
      checking = true
      entered(label)
      if next(pending) == nil then
        checking = false
        return
      end
      for name, find in pairs(pending) do
        local t, key = find()
        if t then
          local ok, isSecure, owner = pcall(issecurevariable, t, key)
          if ok and not isSecure and owner == "WoWForeverJapanese" then
            pending[name] = nil
            if #w.traces < TRACE_MAX then
              w.traces[#w.traces + 1] = { path = name, after = label, stack = debugstack(3, 40, 40), near = near(),
                at = date("%%H:%%M:%%S") }
            end
          end
        end
      end
      checking = false
    end
    local function hookAll(t, label)
      if type(t) ~= "table" or hooked[t] then return end
      hooked[t] = true
      labels[t] = label
      for key, value in pairs(t) do
        if type(key) == "string" and type(value) == "function" then
          pcall(hooksecurefunc, t, key, function() check(label .. ":" .. key) end)
        end
      end
      if type(t.HookScript) == "function" then
        for _, script in ipairs({ "OnShow", "OnEvent", "OnHide" }) do
          pcall(t.HookScript, t, script, function() check(label .. " script " .. script) end)
        end
      end
    end
    local function hookPath(path)
      local _, _, count = traceResolve(path)
      for upTo = 1, (count or 1) - 1 do
        hookAll(traceResolve(path, upTo), (path:match(("[^.]+%%."):rep(upTo - 1) .. "[^.]+") or path))
      end
    end
    for name in pairs(pending) do hookPath(name) end
    for _, name in ipairs(TRACE_ALSO) do hookAll((traceResolve(name .. ".x")), name) end
    -- the help tips there are now, and the ones waiting in the pool
    local pool = type(HelpTip) == "table" and HelpTip.framePool or nil
    if type(pool) == "table" then
      local n = 0
      pcall(function()
        for tip in pool:EnumerateActive() do
          n = n + 1
          hookAll(tip, "HelpTip active " .. n)
        end
      end)
      for i, tip in ipairs(type(pool.inactiveObjects) == "table" and pool.inactiveObjects or {}) do
        hookAll(tip, "HelpTip waiting " .. i)
      end
    end
    -- what already reads in the addon's name before anything is shown
    entered("at login")
  end

  -- Everything that takes the addon's name, as it happens. Once at login and then over and over while the test
  -- runs (and for a while after), every frame's keys, every global name and one level under each global table are
  -- read; a key in the addon's name not seen before is kept with the time, the part of the test running then and
  -- the number of the sweep. The first sweep is what was there at login; anything after it came during the run,
  -- and the part beside it is what was running. Into `WFJScanDB.watch.marks`:
  --   { "<name>\t<time>\t<part>\t<sweep>" }
  local SWEEP_MS = 4 -- milliseconds a frame: the test's own run, so it may cost more than play would bear
  local SWEEP_MARKS = 6000
  local SWEEP_AFTER = 25 -- seconds it goes on after the test ends
  local sweep = { seen = {}, n = 0 }
  local function sweepPart()
    local probe = type(WFJScanDB) == "table" and WFJScanDB.probe or nil
    local test = type(probe) == "table" and probe.test or nil
    return type(test) == "table" and test.finished == nil and tostring(test.part or "starting") or "no test"
  end
  -- the two names kept: the addon's and the test addon's own. Another addon's frames hold thousands of keys in its
  -- own name, which say nothing here.
  local SWEEP_OWNERS = { WoWForeverJapanese = true, WFJScan = true }
  local function sweepNote(name, owner)
    local id = name .. "\t" .. owner
    if sweep.seen[id] then return end
    sweep.seen[id] = true
    local w = watchDb()
    if not w then return end
    w.marks = type(w.marks) == "table" and w.marks or {}
    if #w.marks < SWEEP_MARKS then
      w.marks[#w.marks + 1] = name .. "\t" .. date("%%H:%%M:%%S") .. "\t" .. (sweep.after or sweepPart()) .. "\t"
        .. sweep.n .. "\t" .. owner
    end
  end
  local function sweepKeys(t, label)
    for key in pairs(t) do
      if type(key) == "string" then
        local ok, isSecure, owner = pcall(issecurevariable, t, key)
        if ok and not isSecure and SWEEP_OWNERS[owner] then sweepNote(label .. "." .. key, owner) end
      end
    end
  end
  local function sweepOwn(name)
    return name:find("^WFJ") or name:find("^WoWForeverJapanese") or name:find("^SLASH_WFJ") or name:find("WFJ_")
  end
  local function sweepSome()
    local started = debugprofilestop()
    while debugprofilestop() - started < SWEEP_MS do
      if sweep.phase == "frames" then
        sweep.frame = EnumerateFrames(sweep.frame)
        local f = sweep.frame
        if not f then
          sweep.phase, sweep.key = "globals", nil
        else
          pcall(function()
            if f:IsForbidden() then return end
            local name = f.GetDebugName and f:GetDebugName() or "unnamed"
            sweepKeys(f, tostring(name))
          end)
        end
      else
        local key, value = next(_G, sweep.key)
        sweep.key = key
        if key == nil then
          sweep.n = sweep.n + 1
          sweep.phase, sweep.frame = "frames", nil
          local w = watchDb()
          if w then w.sweeps = sweep.n end
          -- a pass asked for after a part: it has read everything once since that part ended
          if sweep.waiting and sweep.n >= sweep.waiting.from + 2 then
            local go = sweep.waiting.go
            sweep.waiting, sweep.after = nil, nil
            go()
          end
          if sweep.stopAt and GetTime() >= sweep.stopAt then
            sweep.runner:Hide()
            return
          end
        elseif type(key) == "string" and not sweepOwn(key) then
          local ok, isSecure, owner = pcall(issecurevariable, _G, key)
          if ok and not isSecure and SWEEP_OWNERS[owner] then sweepNote("_G." .. key, owner) end
          -- one level under a global table that is no frame: a frame was read with the frames
          if type(value) == "table" and type(rawget(value, 0)) ~= "userdata" then pcall(sweepKeys, value, key) end
        end
      end
    end
  end
  local function sweepStep()
    -- a global removed while the sweep stood on it ends that pass: the next one starts over
    if not pcall(sweepSome) then sweep.phase, sweep.frame, sweep.key = "frames", nil, nil end
  end
  -- One whole pass over everything after the part `label` ended, then `go`: what the pass finds for the first time
  -- is kept as found "after <label>", so the part that brought a name in is the one named. (Two pass ends are
  -- waited for: the pass under way when the part ended had read some things before it did.)
  WFJScanTaint.sweepAfter = function(label, go)
    if not sweep.runner or not sweep.runner:IsShown() then return go() end
    sweep.after = "after " .. label
    sweep.waiting = { from = sweep.n, go = go }
  end
  -- `seconds`: how long to go on from now, or nil to go on until told
  WFJScanTaint.sweepFor = function(seconds)
    if not sweep.runner then
      sweep.runner = CreateFrame("Frame")
      sweep.runner:SetScript("OnUpdate", sweepStep)
    end
    sweep.phase = sweep.phase or "frames"
    sweep.stopAt = seconds and GetTime() + seconds or nil
    sweep.runner:Show()
  end

  -- under pcall: a client without one of these keeps the rest of the test
  pcall(function()
    if type(ShowUIPanel) == "function" then hooksecurefunc("ShowUIPanel", function(frame) watchShown(frame) end) end
    local watcher = CreateFrame("Frame")
    for event in pairs(WATCH_EVENTS) do pcall(watcher.RegisterEvent, watcher, event) end
    for _, event in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "PLAYER_REGEN_DISABLED",
      "PLAYER_REGEN_ENABLED", "PLAYER_LOGIN" }) do
      pcall(watcher.RegisterEvent, watcher, event)
    end
    watcher:SetScript("OnEvent", function(_, event, a1, a2)
      if event == "PLAYER_LOGIN" then
        pcall(traceArm)
        -- what is in the addon's name before anything runs: one sweep, a few seconds after login
        C_Timer.After(3, function() pcall(WFJScanTaint.sweepFor, 1) end)
        return
      end
      if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then return watchRefused(a1, a2) end
      if event == "PLAYER_REGEN_DISABLED" then return watchFight(true) end
      if event == "PLAYER_REGEN_ENABLED" then return watchFight(false) end
      watchShown(_G[WATCH_EVENTS[event]])
    end)
  end)

  -- The open step (`/wfjtest open`): the windows of the micro buttons and the bags, opened the client's own way. A
  -- window the test opens carries the test's taint first, so here the player's own click does the opening: a secure
  -- button of the test's runs "/click <micro button>" lines, which the client runs in a clean run exactly as it runs a
  -- player's macro [verified: blizzard_framexml/securetemplates.lua:450-463]. Each press opens the next few windows
  -- one after another; the watcher above reads each. Into `probe.open`:
  --   asked    the buttons the step clicked; presses  the presses it took; windows  the frames that showed
  --   refused  why it did not run (no button to click, or the player never pressed)
  local OPEN_BUTTONS = { "CharacterMicroButton", "ProfessionMicroButton", "PlayerSpellsMicroButton",
    "SpellbookMicroButton", "TalentMicroButton", "AchievementMicroButton", "QuestLogMicroButton", "GuildMicroButton",
    "LFDMicroButton", "CollectionsMicroButton", "LegacyMicroButton", "MainMenuBarBackpackButton" }
  -- Left out: EJMicroButton and HousingMicroButton. Forever has the buttons and reports them shown and enabled, but
  -- not what they open: their own click handlers raise (CanShowEncounterJournal and HousingFramesUtil are nil,
  -- blizzard_micromenu/mainline/mainmenubarmicrobuttons.lua:1832, 1189) [seen in game].
  local OPEN_TEXT_MAX = 240 -- characters of macro text per press
  local OPEN_WAIT = 120 -- seconds the player is given to press
  local openButton
  -- The isolated test of one finding (`/wfjtest isolate`): two values of the reputation pane read in the addon's
  -- name after a test run and never in play. It does one thing at a time and keeps, after each, whose name every
  -- value of the character window's reputation side carries (any addon's, not only this one's):
  --   1  as it is, before anything
  --   2  the player opens the window and clicks the Reputation tab, 3 closes it: the base, with nothing of the
  --      test's before it in the session. Run it first thing after a reload.
  -- The test never opens the window itself: a run it starts carries the test addon's name from its first line, and
  -- says nothing about the addon. A copy of the addon with a switch (WFJ_ISOLATE_BUILD) gets one round per switch
  -- value instead, each opened by the player.
  -- Values the client writes before the addon's hooks run (CharacterFrame.activeSubframe,
  -- ReputationFrame.needsInitialSelection) and after them (the detail pane's ViewRenownButton.factionID, the filter
  -- dropdown's menuGenerator) are all in the list, so the step and the place a name comes in can be read off it.
  -- Into `probe.isolate`: steps = { { label, at, raised, owners = { "<value>\\t<addon>" } } }
  WFJScanTaint.isolate = function(done)
    local db = probeDb()
    local record = { steps = {} }
    db.isolate = record
    local guildTarget = _G.WFJ_ISOLATE_TARGET == "guild"
    local function owners()
      local out = {}
      local function keys(t, label)
        if type(t) ~= "table" then return end
        for key in pairs(t) do
          if type(key) == "string" then
            local ok, isSecure, owner = pcall(issecurevariable, t, key)
            if ok and not isSecure and #out < 400 then out[#out + 1] = label .. "." .. key .. "\\t" .. tostring(owner) end
          end
        end
      end
      -- a copy of the addon may point the test at the guild window instead (WFJ_ISOLATE_TARGET)
      local guild = guildTarget and _G.CommunitiesFrame or nil
      if type(guild) == "table" then
        keys(guild, "CommunitiesFrame")
        local chat = guild.Chat
        keys(chat, "CommunitiesFrame.Chat")
        if type(chat) == "table" then
          keys(chat.MessageFrame, "CommunitiesFrame.Chat.MessageFrame")
          keys(chat.ScrollBar, "CommunitiesFrame.Chat.ScrollBar")
        end
      end
      keys(_G.CharacterFrame, "CharacterFrame")
      local pane = _G.ReputationFrame
      keys(pane, "ReputationFrame")
      if type(pane) == "table" then
        keys(pane.filterDropdown, "ReputationFrame.filterDropdown")
        local detail = pane.ReputationDetailFrame
        keys(detail, "ReputationDetailFrame")
        if type(detail) == "table" then
          keys(detail.ViewRenownButton, "ReputationDetailFrame.ViewRenownButton")
          keys(detail.Description, "ReputationDetailFrame.Description")
          keys(type(detail.Description) == "table" and detail.Description.ScrollBox or nil,
            "ReputationDetailFrame.Description.ScrollBox")
          keys(detail.DescriptionScrollBar, "ReputationDetailFrame.DescriptionScrollBar")
          keys(detail.StandingBar, "ReputationDetailFrame.StandingBar")
          keys(detail.Content, "ReputationDetailFrame.Content")
        end
        local box = pane.ScrollBox
        keys(box, "ReputationFrame.ScrollBox")
        if type(box) == "table" and type(box.GetFrames) == "function" then
          local ok, rows = pcall(box.GetFrames, box)
          for i, row in ipairs(ok and type(rows) == "table" and rows or {}) do
            if i <= 8 then keys(row, "ReputationFrame.ScrollBox row " .. i) end
          end
        end
      end
      for _, name in ipairs({ "CHARACTERFRAME_SUBFRAMES", "PaperDollFrame", "SkillsFrame", "TokenFrame" }) do
        local ok, isSecure, owner = pcall(issecurevariable, _G, name)
        if ok and not isSecure then out[#out + 1] = "_G." .. name .. "\\t" .. tostring(owner) end
      end
      table.sort(out)
      return out
    end
    -- How the description sits in its scroll box: the text's own height, the height of the container the scroll box
    -- scrolls, and the height of the box. A container shorter than the text cuts the text off.
    local function fit()
      if guildTarget then
        -- what the copy of the addon logged since the last step (which of its pieces ran), and the chat's line count
        local log = type(_G.WFJ_ISOLATE_LOG) == "table" and _G.WFJ_ISOLATE_LOG or {}
        local text = table.concat(log, ", ")
        for i = #log, 1, -1 do log[i] = nil end
        local guild = _G.CommunitiesFrame
        local frame = type(guild) == "table" and type(guild.Chat) == "table" and guild.Chat.MessageFrame or nil
        local ok, n = pcall(function() return frame:GetNumMessages() end)
        return ("%%s lines in the chat; the addon: %%s"):format(ok and tostring(n) or "?", text ~= "" and text or "nothing ran")
      end
      local pane = _G.ReputationFrame
      local detail = type(pane) == "table" and pane.ReputationDetailFrame or nil
      local sf = type(detail) == "table" and detail.Description or nil
      if type(sf) ~= "table" or type(sf.GetFontString) ~= "function" then return nil end
      local ok, out = pcall(function()
        local fs, container, box = sf:GetFontString(), sf:GetFontStringContainer(), sf:GetScrollBox()
        return ("text %%.0f, container %%.0f, box %%.0f, %%d letters"):format(fs:GetStringHeight() or 0,
          container:GetHeight() or 0, box:GetHeight() or 0, #(fs:GetText() or ""))
      end)
      return ok and out or nil
    end
    local function step(label, raised)
      record.steps[#record.steps + 1] = { label = label, at = date("%%H:%%M:%%S"), raised = raised, owners = owners(),
        fit = fit() }
    end
    local function shown()
      local frame = guildTarget and _G.CommunitiesFrame or _G.CharacterFrame
      if guildTarget and type(frame) ~= "table" then return false end
      return type(frame) == "table" and frame:IsShown()
    end
    if shown() then
      record.refused = "the window was open"
      return done()
    end
    local function paneShown()
      if guildTarget then
        local guild = _G.CommunitiesFrame
        return type(guild) == "table" and type(guild.Chat) == "table" and guild.Chat:IsVisible()
      end
      local pane = _G.ReputationFrame
      return type(pane) == "table" and pane:IsVisible()
    end
    -- The player's own way in: the tab is no button a script can click, so the test waits for the click, keeps the
    -- names once the pane shows and once the window is closed, then goes on.
    local function byPlayer(first, second, ask, nxt)
      print(ask)
      local waited, seen, ticker = 0, false, nil
      ticker = C_Timer.NewTicker(0.25, function()
        waited = waited + 0.25
        if not seen and paneShown() then
          seen, waited = true, 0
          C_Timer.After(guildTarget and 3 or 1.5, function() step(first) end)
        elseif seen and waited > (guildTarget and 3.5 or 2) and not shown() then
          ticker:Cancel()
          return C_Timer.After(1, function()
            step(second)
            nxt()
          end)
        end
        if waited >= 180 then
          ticker:Cancel()
          record.refused = seen and "the window was not closed" or "the reputation pane was not opened"
          done()
        end
      end)
    end
    step("1 before anything")
    -- With a copy of the addon that takes a switch (WFJ_ISOLATE: the one write of the reputation pane it makes), the
    -- test turns on one write at a time and the player opens the pane once for each: the write after which a value
    -- reads in the addon's name is the one. The description comes last: what it leaves on its scroll box stays for
    -- the opens after it.
    if _G.WFJ_ISOLATE_BUILD then
      -- this half needs the addon writing: with translation off no write is made and every step reads clean
      local settings = type(WFJ_DB) == "table" and WFJ_DB.settings or nil
      if type(settings) == "table" and settings.enabled == false then
        print("WFJ test: translation is off. Type /wfj on, then run it again.")
        record.refused = "translation was off"
        return done()
      end
      -- the copy may name its own rounds (WFJ_ISOLATE_ORDER), each a value of the switch it understands
      local own = type(_G.WFJ_ISOLATE_ORDER) == "table" and _G.WFJ_ISOLATE_ORDER or nil
      local order = own or { "none", "title", "rows", "list", "empty", "description", "everything" }
      local function variant(i)
        local what = order[i]
        if not what then
          _G.WFJ_ISOLATE = nil
          return done()
        end
        if own then _G.WFJ_ISOLATE = what else _G.WFJ_ISOLATE = what ~= "everything" and what or nil end
        byPlayer("only " .. what .. ": the player's own click showed the " .. (guildTarget and "guild chat" or "reputation pane"),
          "only " .. what .. ": the player closed the window",
          "WFJ test (" .. i .. " of " .. #order .. "): " .. (guildTarget and "open the guild window, wait for its chat, close it."
            or "open the character window, click the Reputation tab, close it."),
          function() variant(i + 1) end)
      end
      return variant(1)
    end
    byPlayer("2 the player's own click showed the reputation pane, nothing of the test's before it",
      "3 the player closed the window",
      "WFJ test: open the character window, click the Reputation tab, then close the window.", done)
  end

  WFJScanTaint.watch = function(done) done() end

  WFJScanTaint.open = function(done)
    local db = probeDb()
    local record = { asked = {}, presses = 0, windows = {} }
    db.open = record
    local texts, text = {}, ""
    for _, name in ipairs(OPEN_BUTTONS) do
      local b = _G[name]
      if type(b) == "table" and type(b.IsShown) == "function" and b:IsShown()
          and (type(b.IsEnabled) ~= "function" or b:IsEnabled()) then
        record.asked[#record.asked + 1] = name
        -- twice: the first click opens the window, the second puts it away again
        local lines = "/click " .. name .. "\\n/click " .. name .. "\\n"
        if #text + #lines > OPEN_TEXT_MAX and text ~= "" then
          texts[#texts + 1] = text
          text = ""
        end
        text = text .. lines
      end
    end
    if text ~= "" then texts[#texts + 1] = text end
    if #texts == 0 then
      record.refused = "no micro button to click"
      return done()
    end
    if not openButton then
      openButton = CreateFrame("Button", "WFJScanOpenButton", UIParent, "SecureActionButtonTemplate,UIPanelButtonTemplate")
      openButton:SetSize(360, 44)
      openButton:SetPoint("TOP", UIParent, "TOP", 0, -140)
      openButton:SetFrameStrata("DIALOG")
      openButton:RegisterForClicks("AnyUp", "AnyDown")
      openButton:SetAttribute("type", "macro")
    end
    local press = 0
    local function arm()
      openButton:SetAttribute("macrotext", texts[press + 1])
      openButton:SetText("WFJ test: click here (" .. (press + 1) .. " of " .. #texts .. ")")
    end
    watchStep = record.windows
    local waited, ticker = 0, nil
    local function finish(why)
      if ticker then ticker:Cancel() end
      openButton:SetScript("PostClick", nil)
      record.refused = why
      record.presses = press
      -- the last windows are read a second after they show
      C_Timer.After(2.5, function()
        watchStep = nil
        if not InCombatLockdown() then openButton:Hide() end
        done()
      end)
    end
    openButton:SetScript("PostClick", function(_, _, down)
      -- the client runs the macro on one of the two halves of a click; the other half does nothing
      if down ~= GetCVarBool("ActionButtonUseKeyDown") then return end
      press = press + 1
      waited = 0
      if press >= #texts then return finish(nil) end
      if InCombatLockdown() then return finish("a fight started before every window was opened") end
      arm()
    end)
    arm()
    openButton:Show()
    print("WFJ test: click the button at the top of the screen " .. #texts .. " times. Windows open and close by themselves.")
    ticker = C_Timer.NewTicker(1, function()
      waited = waited + 1
      if waited >= OPEN_WAIT then finish("the button was not clicked") end
    end)
  end
end)()

-- The whole window test (`/wfjtest`): the load walk, the live sweep (with the hover read of each window), the
-- closed-window read, the tooltip read, the no-voice read, the names read, the bag click read, the frozen tooltip read,
-- then one done line. `/wfjtest hand` also reads the guild and character
-- windows, which the player opens when it asks. `probe.test` holds when it ran and on which build, so a result read
-- later is known to be a whole run of that build. The open sweep is not part of it (see the closed-window read);
-- `/wfjopen` still runs it alone.
SLASH_WFJTEST1 = "/wfjtest"
-- the names `/wfjtest <part>` takes, in run order (the parts are built in the handler)
-- (a test holds this list to the parts table)
local TEST_PART_NAMES = "craft, walk, live, closed, tooltips, novoice, names, plates, load, chat, marks, bagclick, touch, send, covers, open, watch, isolate, freeze"
local TEST_PARTS = {}
for name in TEST_PART_NAMES:gmatch("[^, ]+") do TEST_PARTS[name] = true end
local testRunning = false
SlashCmdList.WFJTEST = function(how)
  -- the isolated test runs with translation off as well: one run with the addon writing nothing is half of it
  if strtrim(how or "") == "isolate" then
    if InCombatLockdown() then return end
  else
    if not japaneseOn() or InCombatLockdown() then return end
  end
  if characterShown() then -- the test closes windows as it goes, and must not close this one (see above)
    print("WFJ test: close the character window first, then run it again")
    return
  end
  if type(CommunitiesFrame) == "table" and CommunitiesFrame:IsShown() then -- nor the guild window
    print("WFJ test: close the guild window first, then run it again")
    return
  end
  if testRunning then
    print("WFJ test: already running")
    return
  end
  how = strtrim(how or "")
  -- one part's name runs that part alone; "hand" and "tabs" are ways to run the whole test
  local section = how ~= "" and how ~= "hand" and how ~= "tabs" and how or nil
  if section and not TEST_PARTS[section] then
    print("WFJ test: no part named " .. section .. ". Parts: " .. TEST_PART_NAMES)
    return
  end
  testRunning = true
  pcall(WFJScanTaint.sweepFor, nil) -- every key that takes the addon's name while the test runs
  pagesOnly = how == "tabs"
  local db = probeDb()
  db.test = { started = date("%%Y-%%m-%%d %%H:%%M:%%S"), build = tostring((select(2, GetBuildInfo()))),
    errors = {}, blocked = {}, warnings = {}, clicks = pagesOnly and "tabs" or "all",
    code = WFJScanAddonCode, section = section }
  -- every Lua error, every warning and every action the client refused an addon while the test runs, each with
  -- its count
  local shown = geterrorhandler()
  -- An error is kept with its whole call stack, the error catcher's own frames left out: the first frame is
  -- where it was raised, and the cause (a click of the test's, a hook of the addon's) is further down.
  local function stackOf(stack)
    local frames = {}
    for line in tostring(stack or ""):gmatch("[^\\n]+") do
      if not line:find("BugGrabber", 1, true) and line:find("%%S") then frames[#frames + 1] = line end
    end
    return table.concat(frames, " < "):sub(1, STACK_KEPT)
  end
  -- One stack is kept per message, and cut short. So whether ANY raise of a message ran through this addon or
  -- the test addon is noted from the whole stack, before it is cut: such an error is never the game's own.
  db.test.ours = {}
  local function oursIn(stack)
    stack = type(stack) == "string" and stack or ""
    return stack:find("AddOns/WoWForeverJapanese", 1, true) ~= nil or stack:find("AddOns/WFJScan", 1, true) ~= nil
  end
  local function grab(message)
    local key = "[" .. tostring(db.test.part) .. "] " .. tostring(message):sub(1, 400)
    db.test.errors[key] = (db.test.errors[key] or 0) + 1
    db.test.stacks = db.test.stacks or {}
    local ok, stack = pcall(debugstack, 2)
    if ok and oursIn(stack) then db.test.ours[key] = true end
    if not db.test.stacks[key] then db.test.stacks[key] = stackOf(ok and stack or "") end
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
        local key = "[grabbed] " .. tostring(e.message):sub(1, 300)
        db.test.stacks = db.test.stacks or {}
        if oursIn(e.stack) then db.test.ours[key] = true end
        db.test.stacks[key] = stackOf(e.stack)
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
  -- asked before anything is loaded or shown: the strings exist from login or not at all
  local missing = {}
  for _, key in ipairs(KEYS) do
    if type(_G[key]) ~= "string" then missing[#missing + 1] = key end
  end
  db.test.strings = { asked = #KEYS, missing = missing }
  -- a fight that starts during the load walk would end the live sweep before it began, and the run with it: the
  -- sweep waits for the fight to end
  local function outOfCombat(fn)
    if not InCombatLockdown() then return fn() end
    print("WFJ test: waiting for combat to end")
    local waiter = CreateFrame("Frame")
    waiter:SetScript("OnUpdate", function(self)
      if InCombatLockdown() then return end
      self:SetScript("OnUpdate", nil)
      fn()
    end)
  end
  local function finish(said)
    db.test.part = "done"
    seterrorhandler(shown)
    watcher:UnregisterAllEvents()
    readGrabbed()
    testRunning = false
    pcall(WFJScanTaint.sweepFor, 25) -- and for a while after: the windows the player opens last are read too
    db.test.finished = date("%%Y-%%m-%%d %%H:%%M:%%S")
    pcall(sayCounts, db)
    print("WFJ test done: /reload to save, then the result can be read" .. said)
  end
  -- The run's parts in order, each named: `/wfjtest <name>` runs that part alone (with the parts it needs), so a
  -- change to one area is checked without the whole run. The whole run is the bar before a merge.
  local parts = {
    -- First, and straight from the player's own key press: the client opens the crafting window only for a call
    -- that comes from one, and refuses it from a timer (seen in game: a refused call, and the part read nothing).
    -- The client refuses to open a window in a fight too.
    { "craft", function(nxt) outOfCombat(function() WFJScanTaint.craft(nxt) end) end },
    { "walk", function(nxt) WFJScanWalk(nxt) end },
    -- a fight that starts during the load walk would end the live sweep before it began: it waits for the end
    { "live", function(nxt) outOfCombat(function() WFJScanLiveSweep(nxt) end) end, needs = "walk" },
    { "closed", function(nxt)
      db.opened = nil -- an earlier run's bare-window list is not this run's
      WFJScanClosedRead(nxt)
    end, needs = "walk" },
    -- in a fight the client hides a tooltip's rows from addons: nothing could be read
    { "tooltips", function(nxt) outOfCombat(function() WFJScanTooltipRead(nxt) end) end },
    { "novoice", function(nxt) outOfCombat(function() WFJScanNoVoiceRead(nxt) end) end },
    -- in a fight the client hides a tooltip's rows and a unit's name from addons
    { "names", function(nxt) outOfCombat(function() WFJScanNamesRead(nxt) end) end },
    -- the client refuses a setting written in a fight
    { "plates", function(nxt) outOfCombat(function() WFJScanPlatesRead() nxt() end) end },
    { "load", function(nxt) WFJScanLoadRead() nxt() end },
    -- the addon's own chat windows: opened, read and closed at once
    { "chat", function(nxt) WFJScanChatRead() WFJScanSecretLine(nxt) end },
    -- the addon's own known words window, and the word status marks wherever they are
    { "marks", function(nxt) outOfCombat(function() WFJScanMarksRead(nxt) end) end },
    -- the interface is hidden and shown again, which waits for the end of a fight too
    { "bagclick", function(nxt) outOfCombat(function() WFJScanBagClickRead(nxt) end) end },
    -- after the windows were walked and opened, so the frames the addon makes on them exist
    { "touch", function(nxt) WFJScanTaint.touch(nxt) end },
    { "send", function(nxt) WFJScanTaint.send(nxt) end },
    { "covers", function(nxt) WFJScanTaint.covers(nxt) end },
    -- the player presses a button for this one, so a plain run leaves it out (like the hand read)
    { "open", function(nxt) outOfCombat(function() WFJScanTaint.open(nxt) end) end, only = true },
    -- nothing to run: the windows read during play are in the saved file already
    { "watch", function(nxt) WFJScanTaint.watch(nxt) end },
    -- one finding, taken apart: not part of a plain run
    { "isolate", function(nxt) outOfCombat(function() WFJScanTaint.isolate(nxt) end) end, only = true },
    -- in a fight the copy takes no cards and the client hides a tooltip's rows from addons
    { "freeze", function(nxt) outOfCombat(function() WFJScanFreezeRead(nxt) end) end },
  }
  local byName = {}
  for _, part in ipairs(parts) do byName[part[1]] = part end
  local chosen = {}
  for _, part in ipairs(parts) do
    if not part.only then chosen[#chosen + 1] = part end
  end
  if section then
    chosen = { byName[section].needs and byName[byName[section].needs] or nil, byName[section] }
    if chosen[1] == nil then chosen = { byName[section] } end
  end
  local function run(i)
    local part = chosen[i]
    if part then
      db.test.part = part[1]
      -- after each part, everything is read once more before the next part starts
      return part[2](function() WFJScanTaint.sweepAfter(part[1], function() run(i + 1) end) end)
    end
    if section then return finish(" (only the " .. section .. " part; plain /wfjtest runs them all)") end
    -- The guild and character windows are the player's to open, so a plain run does not wait for them:
    -- what the last `/wfjtest hand` read of them stands for this run while the build is the same.
    if how ~= "hand" then
      db.test.hand = false
      return finish(". Guild and character windows not read in this run (/wfjtest hand reads them)")
    end
    db.test.hand = true
    db.test.part = "guild"
    WFJScanGuildRead(function()
      db.test.part = "character"
      WFJScanCharacterRead(function()
        local unopened = {}
        for window, why in pairs(db.test.unopened or {}) do
          if window == "guild" or window == "character" or window == "guild pages" then
            unopened[window] = why
          end
        end
        local hover = type(db.hover) == "table" and db.hover or {}
        db.hand = { build = db.test.build, code = db.test.code, at = date("%%Y-%%m-%%d %%H:%%M:%%S"),
          guild = db.live.guild, character = db.live.character, unopened = unopened,
          hover = { guild = hover.guild, character = hover.character } }
        finish("")
      end)
    end)
  end
  run(1)
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


_STRING_NAME = re.compile(r"[A-Z][A-Z0-9_]*")


def translated_keys(data: Path) -> list[str]:
    """The names of the interface strings that ship Japanese under `data`: the client's own string names only
    (a client-table row, keyed `<Family>:<id>`, has no such name)."""
    out = []
    for path in sorted((data / "ui").glob("*.jsonl")):
        for line in path.read_text(encoding="utf-8").splitlines():
            row = json.loads(line) if line.strip() else {}
            if row.get("ja") and _STRING_NAME.fullmatch(str(row.get("id", ""))):
                out.append(row["id"])
    return out


def spell_value_counts(data: Path) -> dict[int, int]:
    """Each shipped spell description that is filled from the live tooltip, with how many numbers its English
    prints (`generate.value_counts`): what the window test's tooltip read holds the client's line to. A line
    that waits for a redraft (it ships a count no line has) is left out: it is English by design."""
    from wfj.cmd import generate
    from wfj.io.jsonl_store import Store

    counts = generate.value_counts("spell", Store(data).load("spell"), Store(data, english=True))
    return {int(i): n for (i, field), n in counts.items() if field == "description" and n >= 0}


def spell_includes(data: Path, ids: Iterable[int]) -> dict[int, list[int]]:
    """Each listed spell whose English description splices in another spell's description or aura text
    (`align.included_spells`), with those spells' ids: when the client's line of such a spell holds another count
    of numbers than the Japanese, the tooltip read records how the client held each of them."""
    from wfj.core import align
    from wfj.io.jsonl_store import Store

    english = {(ln["id"], ln["field"]): ln["en"] for ln in Store(data, english=True).load("spell")}
    out: dict[int, list[int]] = {}
    for i in sorted(set(ids)):
        en = english.get((i, "description"), "")
        if "$@" not in en:
            continue
        spliced = sorted({sid for sid, field in align.included_spells(en, english) if field in ("description", "aura")})
        if spliced:
            out[i] = spliced
    return out


# the addon's gate, copied into the test addon whole (`gate_lua`), relative to the repository
ALIGN_LUA = Path("addon/WoWForeverJapanese/Core/Align.lua")


def spell_japanese(data: Path, ids: Iterable[int]) -> dict[int, tuple[str, str]]:
    """Each listed spell's shipped Japanese description as the addon ships it (`tooltip_text.shipped_ja`), with
    its status letter (`schema.STATUS_CHAR`): what the tooltip read runs the addon's own gate on, to say why a
    spell's line stayed English. A spell with no shipped description is left out."""
    from wfj.core import tooltip_text
    from wfj.emit import lua_writer, schema
    from wfj.io.jsonl_store import Store

    wanted = set(ids)
    english = {ln["id"]: ln["en"] for ln in Store(data, english=True).load("spell")
               if ln["field"] == "description" and ln["id"] in wanted}
    out: dict[int, tuple[str, str]] = {}
    for ln in Store(data).load("spell"):
        if ln["field"] == "description" and ln["id"] in wanted and lua_writer.shipped(ln):
            out[int(ln["id"])] = (tooltip_text.shipped_ja(ln, english.get(ln["id"])), schema.STATUS_CHAR[ln["status"]])
    return out


# Lua 5.1 keeps one pool of constants per function: the Japanese is split over functions of this many entries
_SHIPPED_PART = 2000

GATE_LUA_HEAD = """
-- The addon's own gate, Core/Align.lua copied in whole when this file is built, run in a table of its own the way
-- the addon runs it in its namespace. The tooltip read asks it why a spell's line stayed English (leftWhy).
local ShippedAlign
do
  local shipped = {}
  local function run(...)
"""
GATE_LUA_TAIL = """
  end
  run("WoWForeverJapanese", shipped)
  ShippedAlign = shipped.Align
end
-- Each spell's Japanese as the addon ships it, with its status letter ("." trusted, "u" unaligned, "s" stale)
local SHIPPED = {}
for _, part in ipairs({
%s
}) do
  for id, entry in pairs(part()) do SHIPPED[id] = entry end
end
"""


def gate_lua(align: str, japanese: Mapping[int, tuple[str, str]]) -> str:
    """The addon's gate (`align`, the text of Core/Align.lua) as `ShippedAlign`, and each spell's shipped Japanese
    with its status letter (`spell_japanese`) as `SHIPPED`, for the test addon's tooltip read."""
    items = sorted(japanese.items())
    parts = []
    for at in range(0, len(items), _SHIPPED_PART):
        rows = "\n".join(f"  [{i}] = {{ {_lua_string(ja)}, {_lua_string(status)} }},"
                         for i, (ja, status) in items[at:at + _SHIPPED_PART])
        parts.append(f"function() return {{\n{rows}\n}} end,")
    return GATE_LUA_HEAD + align + GATE_LUA_TAIL % "\n".join(parts)


def probe_lua(  # noqa: PLR0913 - the manifest, how it runs, and one parameter per list the window test carries
              manifest: dict[str, Any], walk: bool = False, english: Iterable[str] = (),
              at_login: bool = True, keys: Iterable[str] = (), values: Mapping[int, int] | None = None,
              japanese: Mapping[int, tuple[str, str]] | None = None, gate: str | None = None,
              items: Iterable[int] = (), includes: Mapping[int, Sequence[int]] | None = None) -> str:
    """The probe as one Lua file for the scan dev addon: every manifest name with its surface, checked at
    login, saved under `WFJScanDB.probe` for `report`. With `walk` it also loads every load-on-demand addon a
    surface waits for and records what the client restricts (`read_walk` reads both back); with `at_login`
    false that loading waits for the window test. With `gate` (the text of Core/Align.lua) the window test also
    carries the addon's gate and the spells' shipped Japanese (`japanese`), to say why a spell stayed English."""
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
            lua += f'WFJScanAddonCode = "{manifest.get("code", "")}"\n'
            lua += "WFJScanReportedItems = { " + ", ".join(str(i) for i in sorted(set(items))) + " }\n"
            lua += "WFJScanIncludes = {\n" + "".join(
                f"  [{i}] = {{ {', '.join(str(s) for s in ids)} }},\n" for i, ids in sorted((includes or {}).items())
            ) + "}\n"
            if gate is not None:
                lua += gate_lua(gate, japanese or {})
            lua += TEXT_LUA % ("\n".join(f"  [{_lua_string(t)}] = true," for t in lines),
                               "\n".join(f'  "{k}",' for k in sorted(set(keys))),
                               "\n".join(f"  [{i}] = {n}," for i, n in sorted((values or {}).items())))
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
HAND_WINDOWS = ("guild", "character")
HAND_OWED = "(not read on this build and addon code: /wfjtest hand, then J and C when it asks)"
# Japanese on screen in a face with no Japanese letters (drawn as empty boxes): a line of the result too, named by
# its widget, so the baseline can allow one with its reason
BOXES = "(Japanese in a font without it)"
# the face the sweep takes as able to draw Japanese: the addon's bundled one, by file name (its Font.PATH)
JAPANESE_FACE = "ipagui"


def _standing_hand(probe: Any) -> tuple[bool, Any]:
    """For a plain run, which does not wait for the two windows the player opens: (whether it is one, the last
    `/wfjtest hand` read when that read stands for it, else None). The read stands while it is of this client
    build and this addon code: a change of either may have changed the two windows."""
    test = probe.get("test")
    if test is None or test.get("hand") is not False:
        return False, None
    hand = probe.get("hand")
    current = (hand is not None and test.get("build") is not None
               and str(hand.get("build")) == str(test.get("build"))
               and str(hand.get("code") or "") == str(test.get("code") or ""))
    return True, hand if current else None


def _hand_read(probe: Any, info: dict[str, str], always: set[Any], idle_boxes: set[Any]) -> set[tuple[str, str]]:
    """The lines of the two windows the player opens, for a plain run, which does not wait for them. What the
    last `/wfjtest hand` read of them stands for it while the build is the same (`info["hand"]` says which);
    with no such read on this build, each window is a line of the result."""
    plain, hand = _standing_hand(probe)
    if not plain:
        return set()
    info["hand"] = f"read by hand on {hand.get('at')}" if hand is not None else "not read on this build and addon code"
    if hand is None:
        return {(window, HAND_OWED) for window in HAND_WINDOWS}
    found: set[tuple[str, str]] = set()
    for window in HAND_WINDOWS:
        record = hand.get(window)
        english = record.get("english") if record is not None else None
        boxes = record.get("boxes") if record is not None else None
        if english is not None:
            found |= {(window, str(en)) for name, en in english.named().items() if name not in always}
        if boxes is not None:
            found |= {(window, f"{BOXES} {_POOLED.sub('*', str(name))}") for name in boxes.named()
                      if name not in idle_boxes}
    kept = hand.get("unopened")
    if kept is not None:
        found |= {(str(window), NOT_OPENED) for window in kept.named()}
    return found


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
    info = {str(k): str(v) for k, v in test.items() if isinstance(v, (str, int, float)) and not isinstance(v, bool)}
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
    found |= _hand_read(probe, info, set(always), set(idle_boxes))
    # a run that stopped while waiting for the character window read every other window: its result is read, and
    # the window nobody read is a line of it
    # so does a run that stopped while waiting for the guild window, which comes just before it
    if not info.get("finished") and info.get("part") in ("guild", "character") and "character" not in live:
        found.add(("character", NOT_OPENED))
    if not info.get("finished") and info.get("part") == "guild":
        found.add(("guild", NOT_OPENED))
    closed = probe.get("closed").named() if probe.get("closed") is not None else {}
    for window, lines in closed.items():
        found |= {(f"closed {_POOLED.sub('*', str(window))}", str(en)) for en in lines.named().values()}
    opened = probe.get("opened").named() if probe.get("opened") is not None else {}
    for window, record in opened.items():
        still = record.get("still")
        if still is not None:
            found |= {(f"opened {_POOLED.sub('*', str(window))}", str(en)) for en in still.named().values()}
    return info, found


def read_missing_strings(text: str) -> tuple[int, list[str]]:
    """The dictionary's interface strings the client did not hand to addon code when the window test asked:
    (how many it asked for, the names it did not get). A line the game writes from such a string can be matched
    by nothing the addon reads, so it stays English however good its Japanese is."""
    from wfj.io import lua_reader

    db = lua_reader.parse_assignments(text).get("WFJScanDB")
    probe = db.get("probe") if db is not None else None
    test = probe.get("test") if probe is not None else None
    strings = test.get("strings") if test is not None else None
    if strings is None:
        return 0, []
    missing = strings.get("missing")
    names = sorted(str(v) for _, v in missing.items) if missing is not None else []
    return int(strings.get("asked") or 0), names


def read_tooltips(text: str) -> dict[str, Any] | None:
    """The window test's tooltip read out of a saved-variables file, or None when the run had none: how many
    spell tooltips it read (`read`), how many showed Japanese (`japanese`), how many the client had not loaded
    (`unread`), how many items (`items`), why it could not read (`refused`), and three lists of (id, what was
    seen): `wrong` (a spell in Japanese whose line holds another count of numbers than the Japanese is numbered
    to), `changed` (a spell left English for that reason: the game changed its tooltip) and `folded` (an item
    whose one Japanese paragraph stands for several lines)."""
    from wfj.io import lua_reader

    db = lua_reader.parse_assignments(text).get("WFJScanDB")
    probe = db.get("probe") if db is not None else None
    record = probe.get("tooltips") if probe is not None else None
    if record is None:
        return None
    out: dict[str, Any] = {k: int(record.get(k) or 0) for k in ("read", "japanese", "unread", "items", "marked")}
    out["refused"] = str(record.get("refused") or "")
    load, why = record.get("load"), record.get("why")
    out["load"] = {str(k): v for k, v in (load.named() if load is not None else {}).items()}
    out["why"] = {
        str(k): (int(v.get("n") or 0), [str(x) for _, x in v.get("ids").items] if v.get("ids") is not None else [])
        for k, v in (why.named() if why is not None else {}).items()
    }
    for kind in ("wrong", "changed", "folded"):
        table = record.get(kind)
        out[kind] = sorted((str(k), str(v)) for k, v in (table.named() if table is not None else {}).items())
    reported = record.get("reported")
    out["reported"] = {
        str(k): [str(x) for _, x in v.items] for k, v in (reported.named() if reported is not None else {}).items()
    }
    return out


def tooltip_problems(tooltips: dict[str, Any] | None) -> list[str]:
    """What the tooltip read found wrong, one line each. A run whose test addon had no tooltip read says so: its
    result proves nothing about tooltips."""
    if tooltips is None:
        return ["tooltips not read: this run's test addon has no tooltip read (make scan-install, then run it again)"]
    out = [f"tooltip numbers in the wrong places: spell {i} ({said})" for i, said in tooltips["wrong"]]
    out += [f"tooltip lines written over: item {i} ({said})" for i, said in tooltips["folded"]]
    if tooltips["refused"]:
        out.append(f"tooltips not read: {tooltips['refused']}")
    elif not tooltips["read"]:
        out.append("tooltips not read: no spell tooltip could be read")
    elif tooltips["read"] < tooltips["unread"]:
        # the client gave no text for most of the spells: the run looked at too few to pass
        why = sorted(tooltips.get("why", {}).items(), key=lambda kv: (-kv[1][0], kv[0]))[:4]
        reasons = "; ".join(f"{n} {reason}, e.g. {ids[:4]}" for reason, (n, ids) in why)
        out.append(f"tooltips not read: only {tooltips['read']} of {tooltips['read'] + tooltips['unread']} spells "
                   "could be read" + (f" ({reasons})" if reasons else ""))
    return out


def read_no_voice(text: str) -> dict[str, Any] | None:
    """The window test's no-voice read out of a saved-variables file, or None when the run had none: how many
    quests of the quest log it read (`quests`), how many said they have no voice (`said`), whether a voice
    pack was loaded (`pack`), how many lines the voice entry listed (`listed`), why it could not read
    (`refused`), and `wrong`: (quest id, what its pane said that it should not)."""
    from wfj.io import lua_reader

    db = lua_reader.parse_assignments(text).get("WFJScanDB")
    probe = db.get("probe") if db is not None else None
    record = probe.get("novoice") if probe is not None else None
    if record is None:
        return None
    wrong = record.get("wrong")
    return {
        "quests": int(record.get("quests") or 0), "said": int(record.get("said") or 0),
        "listed": int(record.get("listed") or 0), "pack": bool(record.get("pack")),
        "refused": str(record.get("refused") or ""),
        "wrong": sorted((str(k), str(v)) for k, v in (wrong.named() if wrong is not None else {}).items()),
    }


def no_voice_problems(record: dict[str, Any] | None) -> list[str]:
    """What the no-voice read found wrong, one line each. A run that read no quest proves nothing about the
    message and says so: the character needs a quest in its log."""
    if record is None:
        return ["no-voice message not read: this run's test addon has no such read (make scan-install, then "
                "run it again)"]
    out = [f"no-voice message: quest {i} {said}" for i, said in record["wrong"]]
    if record["refused"]:
        out.append(f"no-voice message not read: {record['refused']}")
    elif not record["quests"]:
        out.append("no-voice message not read: the quest log holds no quest (take one, then run it again)")
    return out


def read_names(text: str) -> dict[str, Any] | None:
    """The window test's names read out of a saved-variables file, or None when the run had none: whether
    Japanese names were on (`on`), why it could not read (`refused`), and `rows`: (kind, the client's English,
    what the widget showed) for every name it read."""
    from wfj.io import lua_reader

    db = lua_reader.parse_assignments(text).get("WFJScanDB")
    probe = db.get("probe") if db is not None else None
    record = probe.get("names") if probe is not None else None
    if record is None:
        return None
    rows = record.get("rows")
    return {
        "on": bool(record.get("on")), "refused": str(record.get("refused") or ""),
        "rows": [(str(r.get("kind")), str(r.get("english")), str(r.get("shown")))
                 for r in (rows.positional() if rows is not None else [])],
    }


def read_freeze(text: str) -> dict[str, Any] | None:
    """The window test's frozen tooltip read out of a saved-variables file, or None when the run had none: the
    key the binding has (`bound`, "" for none), how many item tooltips it froze (`items`), the Japanese lines on
    the copies (`lines`), the word-card covers laid on them (`cards`), whether cards were to be expected
    (`expect`: Japanese showing with the reading box on), why it could not read (`refused`), and two lists of
    (item id, what was seen): `missing` (a copy that did not show or lacks a line) and `stuck` (a copy the key
    did not close)."""
    from wfj.io import lua_reader

    db = lua_reader.parse_assignments(text).get("WFJScanDB")
    probe = db.get("probe") if db is not None else None
    record = probe.get("freeze") if probe is not None else None
    if record is None:
        return None
    out: dict[str, Any] = {k: int(record.get(k) or 0) for k in ("items", "spells", "lines", "cards")}
    out["bound"] = str(record.get("bound") or "")
    out["expect"] = bool(record.get("expect"))
    out["refused"] = str(record.get("refused") or "")
    for kind in ("missing", "stuck"):
        table = record.get(kind)
        out[kind] = sorted((str(k), str(v)) for k, v in (table.named() if table is not None else {}).items())
    rows = record.get("uncarded")
    out["uncarded"] = [tuple(str(r).split("\t", 3)) for r in (rows.positional() if rows is not None else [])]
    return out


# Kana a word card never takes: the particles and the copula a reading list leaves out (core/readings `_BARE`), and
# two of them together (には, への).
_FREEZE_PARTICLES = ["は", "が", "を", "に", "で", "と", "の", "へ", "も", "や", "か", "よ", "ね", "な", "から", "まで"]
FREEZE_BARE = frozenset(_FREEZE_PARTICLES + ["だ", "です", "ー", "しか"]
                        + [a + b for a in _FREEZE_PARTICLES for b in _FREEZE_PARTICLES])


def uncarded_words(record: dict[str, Any]) -> list[tuple[str, str, str, str]]:
    """The frozen copies' Japanese that no word card covers, as (what was frozen, "none" | "part", the line, the
    runs left), a run that is only a particle or the copula left out: the reading lists never give those a card."""
    out = []
    for row in record.get("uncarded", []):
        if len(row) != 4:
            continue
        what, covered, line, runs = row
        left = [r for r in runs.split(" ") if r and r not in FREEZE_BARE]
        if left:
            out.append((what, covered, line, " ".join(left)))
    return out


PLATE_WANT = {"UnitNameNPC": "0", "UnitNameHostleNPC": "0", "UnitNameInteractiveNPC": "0",
              "UnitNameFriendlySpecialNPCName": "0"}
PLATE_RANGE = 60  # the range Japanese names set (UI/NamePlateSetting WANT), or the client's limit when lower


def read_plates(text: str) -> dict[str, Any] | None:
    """The window test's nameplate read out of a saved-variables file, or None when the run had none: whether
    Japanese names were on (`names`), each setting's value and default (`values`, `defaults`), the largest
    nameplate range the client holds (`limit`, "" when unread) and why it could not read (`refused`)."""
    from wfj.io import lua_reader

    db = lua_reader.parse_assignments(text).get("WFJScanDB")
    probe = db.get("probe") if db is not None else None
    record = probe.get("plates") if probe is not None else None
    if record is None:
        return None
    out: dict[str, Any] = {"names": bool(record.get("names")), "refused": str(record.get("refused") or ""),
                           "limit": str(record.get("limit") or "")}
    for kind in ("values", "defaults"):
        table = record.get(kind)
        out[kind] = {str(k): str(v) for k, v in (table.named() if table is not None else {}).items()}
    return out


def read_load(text: str) -> dict[str, float] | None:
    """The window test's load read out of a saved-variables file, or None when the run had none: the addon's own
    memory in KB (`kb`) and how long its files took to load and its setup after them, in ms (`files`, `setup`),
    each left out when the client or the addon gave none."""
    from wfj.io import lua_reader

    db = lua_reader.parse_assignments(text).get("WFJScanDB")
    probe = db.get("probe") if db is not None else None
    record = probe.get("load") if probe is not None else None
    if record is None:
        return None
    return {k: float(v) for k, v in record.named().items() if isinstance(v, (int, float))}


def read_bagclick(text: str) -> dict[str, Any] | None:
    """The window test's bag click read out of a saved-variables file, or None when the run had none: how many
    values it read (`checked`), the ones carrying the addon's taint as (when, name) (`ours`), the ones carrying
    another addon's as name → addon (`others`), why the second pass did not run (`refused`), a read that raised
    (`failed`), the bag item buttons pointed at (`pointed`), the bag item tooltips shown (`tooltips`), the values the
    test's own steps tainted (`own`) and how far the frames it passed over got (`skipped`)."""
    from wfj.io import lua_reader

    db = lua_reader.parse_assignments(text).get("WFJScanDB")
    probe = db.get("probe") if db is not None else None
    record = probe.get("bagclick") if probe is not None else None
    if record is None:
        return None
    rows = record.get("ours")
    others = record.get("others")
    skipped = record.get("skipped")
    return {
        "checked": int(record.get("checked") or 0),
        "ours": [tuple(str(r).split("\t", 1)) for r in (rows.positional() if rows is not None else [])],
        "others": {str(k): str(v) for k, v in (others.named() if others is not None else {}).items()},
        "refused": str(record.get("refused") or ""),
        "failed": str(record.get("failed") or ""),
        "pointed": int(record.get("pointed") or 0),
        "tooltips": int(record.get("tooltips") or 0),
        "own": int(record.get("own") or 0),
        "skipped": {str(k): str(v) for k, v in (skipped.named() if skipped is not None else {}).items()},
    }


def bagclick_problems(record: dict[str, Any] | None) -> list[str]:
    """What the bag click read found wrong, one line each: every value a bag item's click reads that carries the
    addon's taint (the game would refuse the item's use in the addon's name). A run whose test addon had no such
    read says so."""
    if record is None:
        return ["bag click not read: this run's test addon has no such read (make scan-install, then run it again)"]
    out = [f"bag click value tainted by the addon ({when}): {name}" for when, name in record["ours"]]
    if record["refused"]:
        out.append(f"bag click read only as the run left it: {record['refused']}")
    if record["failed"]:
        out.append(f"bag click read stopped: {record['failed']}")
    # a run that pointed at no bag item never ran the item tooltip's code on a bag button, the path under test
    if record["skipped"] and not record["pointed"] and not record["tooltips"] and not record["refused"]:
        out.append("bag click pointed at no bag item: "
                   + ", ".join(f"{k} {v}" for k, v in sorted(record["skipped"].items())))
    return out


def read_craft(text: str) -> dict[str, Any] | None:
    """The window test's crafting window read out of a saved-variables file, or None when the run had none: how many
    values it read (`checked`), the ones carrying the addon's taint as (when, name) (`ours`), the ones carrying
    another addon's as name → addon (`others`), the values the test's own steps tainted (`own`), why the window was
    not read (`refused`), a read that raised (`failed`), whether the window opened (`shown`), the skill line and the
    recipe opened (`line`, `recipe`)."""
    from wfj.io import lua_reader

    db = lua_reader.parse_assignments(text).get("WFJScanDB")
    probe = db.get("probe") if db is not None else None
    record = probe.get("craft") if probe is not None else None
    if record is None:
        return None
    rows = record.get("ours")
    others = record.get("others")
    return {
        "checked": int(record.get("checked") or 0),
        "ours": [tuple(str(r).split("\t", 1)) for r in (rows.positional() if rows is not None else [])],
        "others": {str(k): str(v) for k, v in (others.named() if others is not None else {}).items()},
        "own": int(record.get("own") or 0),
        "refused": str(record.get("refused") or ""),
        "failed": str(record.get("failed") or ""),
        "shown": bool(record.get("shown")),
        "line": int(record.get("line") or 0),
        "recipe": int(record.get("recipe") or 0),
    }


def craft_problems(record: dict[str, Any] | None) -> list[str]:
    """What the crafting window read found wrong, one line each: every value of the window, the bag buttons or the
    vendor window that carries the addon's taint after the client opened the window itself (from there the taint
    reaches a vendor and the action bars). A window that was not read is a problem too: the read proves nothing."""
    if record is None:
        return ["crafting window not read: this run's test addon has no such read (make scan-install, then run it "
                "again)"]
    out = [f"crafting window value tainted by the addon ({when}): {name}" for when, name in record["ours"]]
    if record["refused"]:
        out.append(f"crafting window not read: {record['refused']}")
    if record["failed"]:
        out.append(f"crafting window read stopped: {record['failed']}")
    return out


def client_field_names(ui: Path) -> set[str]:
    """Every name the client's UI source uses as a member (`x.name`, `x:name`, a parentKey, a KeyValue key) under
    `ui` (an extract's Interface/AddOns folder): the names a field of the addon's must not have on a frame that sits
    inside a client frame."""
    names: set[str] = set()
    member = re.compile(r"[.:]\s*([A-Za-z_][A-Za-z0-9_]*)")
    keyed = re.compile(r'(?:parentKey|key)="([A-Za-z_][A-Za-z0-9_]*)"')
    for path in ui.rglob("*"):
        suffix = path.suffix.lower()
        if suffix == ".lua":
            names.update(member.findall(path.read_text(encoding="utf-8", errors="replace")))
        elif suffix == ".xml":
            names.update(keyed.findall(path.read_text(encoding="utf-8", errors="replace")))
    return names


# A client field the addon may taint, by the field's name, with the reason: none. A scroll box's and a scroll bar's
# state were listed here once, on the reasoning that only the scroll code reads them. An isolated test in game
# showed that reasoning wrong: the scroll code runs inside whatever the client is doing when the box updates, and a
# value it reads there in the addon's name puts the addon's name on what the client writes next. An entry here needs
# an isolated test that shows the value is never read on the way to anything else, not an argument that it is not.
TOUCH_ALLOWED: dict[str, str] = {}


def read_touch(text: str) -> dict[str, Any] | None:
    """The window test's touch read out of a saved-variables file, or None when the run had none: the frames walked
    (`frames`), the ones the addon made (`made`) and how many of those sit inside a client frame (`inside_n`), the
    client fields carrying the addon's taint (`on_client`, and their whole count `on_client_n`), and the addon's
    frames inside client frames as (keys, count, a parent) (`inside`)."""
    from wfj.io import lua_reader

    db = lua_reader.parse_assignments(text).get("WFJScanDB")
    probe = db.get("probe") if db is not None else None
    record = probe.get("touch") if probe is not None else None
    if record is None:
        return None
    on_client = record.get("onClient")
    inside = record.get("inside")
    rows = []
    for row in (inside.positional() if inside is not None else []):
        keys, count, where = (str(row).split("\t") + ["", ""])[:3]
        rows.append((keys.split(), int(count or 0), where))
    return {
        "frames": int(record.get("frames") or 0),
        "made": int(record.get("made") or 0),
        "inside_n": int(record.get("insideN") or 0),
        "on_client": [str(r) for r in (on_client.positional() if on_client is not None else [])],
        "on_client_n": int(record.get("onClientN") or 0),
        "inside": rows,
    }


def touch_problems(record: dict[str, Any] | None, client_names: set[str] | None) -> list[str]:
    """What the touch read found wrong, one line each: a client field carrying the addon's taint that is not allowed
    (TOUCH_ALLOWED), and a field on a frame of the addon's inside a client frame whose name the client's own source
    uses (`client_names`, or None when no UI extract was given: then every such field is named, as it cannot be
    cleared)."""
    if record is None:
        return ["touch not read: this run's test addon has no such read (make scan-install, then run it again)"]
    out = [f"client field tainted by the addon: {name}" for name in record["on_client"]
           if name not in TOUCH_ALLOWED and name.rsplit(".", 1)[-1] not in TOUCH_ALLOWED]
    if record["on_client_n"] > len(record["on_client"]):
        out.append(f"client fields tainted by the addon: {record['on_client_n'] - len(record['on_client'])} more")
    for keys, count, where in record["inside"]:
        read = [k for k in keys if client_names is None or k in client_names]
        if read:
            out.append(f"the addon's frame inside a client frame carries fields the client's code names "
                       f"({count} frames, e.g. under {where}): {' '.join(read)}")
    return out


# An addon's own slash command entry is its own to write; nothing on the send path reads another command's entry.
_SEND_OWN = re.compile(r"^(hash_SlashCmdList|hash_ChatTypeInfoList)\./")


def read_send(text: str) -> dict[str, Any] | None:
    """The window test's chat send read out of a saved-variables file, or None when the run had none: how many
    values of the chat send path it read (`checked`), the ones carrying an addon's taint as (name, addon)
    (`tainted`), and what an addon's own insert into the chat box and its own open of it added (`after_insert`,
    `after_open`)."""
    from wfj.io import lua_reader

    db = lua_reader.parse_assignments(text).get("WFJScanDB")
    probe = db.get("probe") if db is not None else None
    record = probe.get("send") if probe is not None else None
    if record is None:
        return None

    def pairs_of(key: str) -> list[tuple[str, ...]]:
        rows = record.get(key)
        return [tuple((str(r).split("\t", 1) + [""])[:2]) for r in (rows.positional() if rows is not None else [])]

    return {"checked": int(record.get("checked") or 0), "tainted": pairs_of("tainted"),
            "after_insert": pairs_of("afterInsert"), "after_open": pairs_of("afterOpen")}


SEND_ADDONS = ("WoWForeverJapanese", "WFJScan")
# A value of the send path an addon's taint may sit on, with the reason.
SEND_ALLOWED = {
    "autoCompleteParams": "set while the player types a slash command: the client looks the command up in the table "
                          "every addon registers in, so the box's completion settings are written in the name of "
                          "the addon whose command is being typed (here the test's own), and again on the next "
                          "change of chat type",
}


def send_problems(record: dict[str, Any] | None) -> list[str]:
    """What the chat send read found wrong, one line each: a value on the chat send path carrying the taint of the
    addon or of the test addon, other than a slash command entry (every addon writes its own)."""
    if record is None:
        return ["chat send path not read: this run's test addon has no such read (make scan-install, then run it "
                "again)"]
    return [f"chat send path value tainted by {by}: {name}" for name, by in record["tainted"]
            if by in SEND_ADDONS and not _SEND_OWN.match(name) and name.rsplit(".", 1)[-1] not in SEND_ALLOWED]


def read_covers(text: str) -> dict[str, Any] | None:
    """The window test's popup dictionary cover read out of a saved-variables file, or None when the run had none:
    how many covers the addon holds (`total`) and shows (`shown`), whether the addon had no such read (`noread`),
    how many show over a text that does not (`idle`), and the texts whose cover shows though the text is not the
    addon's any more (`stray`), is hidden though the text shows (`missing`), lies beside them (`beside`), carries a
    field (`fields`, as (text, keys)) or is a layout frame's own child (`in_layout`)."""
    from wfj.io import lua_reader

    db = lua_reader.parse_assignments(text).get("WFJScanDB")
    probe = db.get("probe") if db is not None else None
    record = probe.get("covers") if probe is not None else None
    if record is None:
        return None

    def rows(key: str) -> list[str]:
        found = record.get(key)
        return [str(r) for r in (found.positional() if found is not None else [])]

    return {"total": int(record.get("total") or 0), "shown": int(record.get("shown") or 0),
            "noread": bool(record.get("noread")), "idle": int(record.get("idle") or 0),
            "stray": rows("stray"), "missing": rows("missing"), "beside": rows("beside"),
            "fields": [tuple((r.split("\t", 1) + [""])[:2]) for r in rows("fields")], "in_layout": rows("inLayout")}


def covers_problems(record: dict[str, Any] | None) -> list[str]:
    """What the popup dictionary cover read found wrong, one line each."""
    if record is None:
        return ["popup dictionary covers not read: this run's test addon has no such read (make scan-install, then "
                "run it again)"]
    if record["noread"]:
        return ["popup dictionary covers not read: the addon in the game has no read for them (an older build)"]
    out = [f"popup dictionary cover showing over a text that is not the addon's any more: {name}"
           for name in record["stray"]]
    out += [f"popup dictionary cover hidden while its text shows: {name}" for name in record["missing"]]
    out += [f"popup dictionary cover not over its text: {name}" for name in record["beside"]]
    out += [f"popup dictionary cover carries a field ({keys}): {name}" for name, keys in record["fields"]]
    out += [f"popup dictionary cover is a layout frame's own child: {name}" for name in record["in_layout"]]
    return out


# The windows a player opens from an NPC or the micro buttons: the ones a release should have seen read in play.
WATCH_EXPECTED = ("CharacterFrame", "MerchantFrame", "GossipFrame", "QuestFrame", "MailFrame", "BankFrame",
                  "AuctionHouseFrame", "ClassTrainerFrame", "ProfessionsFrame", "WorldMapFrame", "FriendsFrame")


def read_watch(text: str) -> dict[str, Any] | None:
    """The windows the test addon read as play opened them, out of a saved-variables file, or None when it holds
    none: the client build and addon code they were read on (`build`, `code`) and, per window frame, how often it
    opened and was read, the values read, when, and the values carrying the addon's taint (`windows`)."""
    from wfj.io import lua_reader

    db = lua_reader.parse_assignments(text).get("WFJScanDB")
    watch = db.get("watch") if db is not None else None
    windows = watch.get("windows") if watch is not None else None
    if windows is None:
        return None
    out: dict[str, dict[str, Any]] = {}
    for name, rec in windows.named().items():
        ours = rec.get("ours")
        out[str(name)] = {"opens": int(rec.get("opens") or 0), "reads": int(rec.get("reads") or 0),
                          "checked": int(rec.get("checked") or 0), "at": str(rec.get("at") or ""),
                          "ours": [str(r) for r in (ours.positional() if ours is not None else [])]}
    refused: dict[tuple[str, str], dict[str, Any]] = {}
    found = watch.get("refused")
    for key, rec in (found.named().items() if found is not None else []):
        addon, action = (str(key).split("\t", 1) + [""])[:2]
        refused[addon, action] = {"n": int(rec.get("n") or 0), "fights": int(rec.get("fights") or 0),
                                  "first": str(rec.get("first") or ""), "last": str(rec.get("last") or "")}
    entered = []
    came = watch.get("entered")
    for row in (came.positional() if came is not None else []):
        entered.append({"key": str(row.get("key") or ""), "after": str(row.get("after") or ""),
                        "at": str(row.get("at") or ""), "stack": str(row.get("stack") or "")})
    marks = []
    noted = watch.get("marks")
    for row in (noted.positional() if noted is not None else []):
        name, at, part, sweep, owner = (str(row).split("\t") + ["", "", "", ""])[:5]
        marks.append({"name": name, "at": at, "part": part, "sweep": int(sweep or 0),
                      "owner": owner or "WoWForeverJapanese"})
    traces = []
    kept = watch.get("traces")
    for row in (kept.positional() if kept is not None else []):
        traces.append({"path": str(row.get("path") or ""), "after": str(row.get("after") or ""),
                       "stack": str(row.get("stack") or ""), "near": str(row.get("near") or ""),
                       "at": str(row.get("at") or "")})
    return {"build": str(watch.get("build") or ""), "code": str(watch.get("code") or ""), "windows": out,
            "traces": traces, "entered": entered, "marks": marks, "sweeps": int(watch.get("sweeps") or 0),
            "refused": refused, "fights": int(watch.get("fights") or 0),
            "fight_seconds": int(watch.get("fightSeconds") or 0)}


def watch_problems(record: dict[str, Any] | None) -> list[str]:
    """What the windows read in play carry wrong, one line each: a value in the addon's name on a window the client
    opened itself, on a bag button or on an action button, and an action the client refused in the addon's name
    while the player played. A window never opened in play is not a problem (it is printed as not read yet)."""
    if record is None:
        return []
    out = [f"a window opened in play carries the addon's taint ({name}): {value}"
           for name, rec in sorted(record["windows"].items()) for value in rec["ours"]
           if value.rsplit(".", 1)[-1] not in TOUCH_ALLOWED]
    out += [f"the game refused {action} in the addon's name in play: {rec['n']} times, {rec['fights']} in a fight "
            f"(first {rec['first']}, last {rec['last']})"
            for (addon, action), rec in sorted(record["refused"].items()) if addon == "WoWForeverJapanese"]
    return out


def read_open(text: str) -> dict[str, Any] | None:
    """The window test's open step out of a saved-variables file, or None when the run had none: the micro buttons
    it clicked through the player's own click (`asked`), the presses it took (`presses`), the frames that showed
    (`windows`) and why it did not finish (`refused`)."""
    from wfj.io import lua_reader

    db = lua_reader.parse_assignments(text).get("WFJScanDB")
    probe = db.get("probe") if db is not None else None
    record = probe.get("open") if probe is not None else None
    if record is None:
        return None

    def rows(key: str) -> list[str]:
        found = record.get(key)
        return [str(r) for r in (found.positional() if found is not None else [])]

    return {"asked": rows("asked"), "presses": int(record.get("presses") or 0), "windows": rows("windows"),
            "refused": str(record.get("refused") or "")}


def open_problems(record: dict[str, Any] | None, watch: dict[str, Any] | None) -> list[str]:
    """What the open step found wrong: it did not run to its end, it opened no window, a window it opened was not
    read, or a window it opened carries the addon's taint."""
    if record is None:
        return ["open step not run: this run's test addon has no such step (make scan-install, then run it again)"]
    if record["refused"]:
        return [f"open step not finished: {record['refused']}"]
    if not record["windows"]:
        return ["open step opened no window: the micro buttons' clicks showed nothing"]
    seen = watch["windows"] if watch is not None else {}
    out = [f"open step: {name} showed and was not read" for name in sorted(set(record["windows"]))
           if not seen.get(name, {}).get("checked")]
    out += [f"a window the open step opened carries the addon's taint ({name}): {value}"
            for name in sorted(set(record["windows"])) for value in seen.get(name, {}).get("ours", [])
            if value.rsplit(".", 1)[-1] not in TOUCH_ALLOWED]
    return out


def read_isolate(text: str) -> list[dict[str, Any]] | None:
    """The window test's isolated test out of a saved-variables file, or None when the run had none: its steps in
    order, each with its label, its time, an error it raised, and whose name each value carried (`owners`, as
    (value, addon))."""
    from wfj.io import lua_reader

    db = lua_reader.parse_assignments(text).get("WFJScanDB")
    probe = db.get("probe") if db is not None else None
    record = probe.get("isolate") if probe is not None else None
    steps = record.get("steps") if record is not None else None
    if steps is None:
        return None
    out = []
    for step in steps.positional():
        rows = step.get("owners")
        out.append({"label": str(step.get("label") or ""), "at": str(step.get("at") or ""),
                    "raised": str(step.get("raised") or ""), "fit": str(step.get("fit") or ""),
                    "owners": [tuple((str(r).split("\t", 1) + [""])[:2])
                               for r in (rows.positional() if rows is not None else [])]})
    return out


def print_isolate(steps: list[dict[str, Any]]) -> None:
    """Prints the isolated test: per step, the values that carry a name the step before did not show, with the name."""
    before: dict[str, str] = {}
    for step in steps:
        now = dict(step["owners"])
        new = {k: v for k, v in now.items() if before.get(k) != v}
        gone = [k for k in before if k not in now]
        print(f"isolate  {step['at']} {step['label']}: {len(now)} values carry a name, {len(new)} new or changed"
              + (f", raised: {step['raised']}" if step["raised"] else "")
              + (f" [description: {step['fit']}]" if step.get("fit") else ""))
        for key in sorted(new):
            print(f"isolate      {key}: {new[key]}" + (f" (was {before[key]})" if key in before else ""))
        for key in sorted(gone):
            print(f"isolate      {key}: clean again (was {before[key]})")
        before = now


def plates_problems(record: dict[str, Any] | None) -> list[str]:
    """What the nameplate read found wrong: with Japanese names on, an English name over an NPC head still on, or a
    nameplate range short of the one Japanese names set (PLATE_RANGE, or the client's limit when that is lower). A
    player who changed one by hand sees it here too, as the read cannot tell; a run with names off proves nothing
    and says nothing."""
    if record is None or record["refused"] or not record["names"]:
        return []
    values = record["values"]
    out = [f"nameplates: {name} is {values.get(name)} with Japanese names on (English names over NPC heads)"
           for name, want in PLATE_WANT.items() if values.get(name) not in (want, "none")]
    try:
        distance = float(values.get("nameplateMaxDistance", ""))
        limit = float(record["limit"]) if record["limit"] else float(PLATE_RANGE)
    except ValueError:
        return out
    if distance < min(PLATE_RANGE, limit):
        out.append(f"nameplates: range {distance:g} with Japanese names on, short of {min(PLATE_RANGE, limit):g}")
    return out


# what the copy box must hold for the line the chat tools read hands the copy icon
COPY_PROBE = "WFJ テスト"


def read_chat(text: str) -> dict[str, Any] | None:
    """The window test's chat tools read out of a saved-variables file, or None when the run had none: the
    phrase card's topic tabs (`topics`) and the phrase rows read over them (`phrases`), the text regions the
    chat words window showed (`words`) and the word list window (`list`), whether Japanese was to be expected
    (`expect`), why it could not read (`refused`, `refused_words`, `refused_copy`, `refused_list`), what the copy box held (`copy`), whether the card stayed open
    (`stuck`), the card's sizes over its topics
    (`sizes`), the chat lines on screen the client kept secret (`secret_lines`) and what they answered with a
    secret (`secret_answers`), and two lists of (what, what was seen): `blank` (a tab or a row with no words, or
    cut off) and `english` (a heading, tab or label with no Japanese in it)."""
    from wfj.io import lua_reader

    db = lua_reader.parse_assignments(text).get("WFJScanDB")
    probe = db.get("probe") if db is not None else None
    record = probe.get("chat") if probe is not None else None
    if record is None:
        return None
    out: dict[str, Any] = {k: int(record.get(k) or 0) for k in ("topics", "phrases", "words", "list")}
    out["expect"] = bool(record.get("expect"))
    out["stuck"] = bool(record.get("stuck"))
    out["refused"] = str(record.get("refused") or "")
    out["refused_words"] = str(record.get("refusedWords") or "")
    out["refused_copy"] = str(record.get("refusedCopy") or "")
    out["refused_list"] = str(record.get("refusedList") or "")
    out["copy"] = str(record.get("copy") or "")
    sizes = record.get("sizes")
    out["sizes"] = [str(v) for v in (sizes.positional() if sizes is not None else [])]
    out["secret_lines"] = int(record.get("secretLines") or 0)
    answers = record.get("secretAnswers")
    out["secret_answers"] = [str(v) for v in (answers.positional() if answers is not None else [])]
    tried = record.get("secretTry")
    out["secret_try"] = None
    if tried is not None:
        kept = tried.get("answers")
        out["secret_try"] = {"looks": int(tried.get("looks") or 0), "refused": str(tried.get("refused") or ""),
                             "answers": [str(v) for v in (kept.positional() if kept is not None else [])]}
    for kind in ("blank", "english"):
        rows = record.get(kind)
        out[kind] = [tuple(str(r).split("\t", 1)) for r in (rows.positional() if rows is not None else [])]
    return out


def chat_problems(record: dict[str, Any] | None) -> list[str]:
    """What the chat tools read found wrong, one line each. A run whose test addon had no such read, or one
    that could not open the phrase card, proves nothing about the chat tools and says so."""
    if record is None:
        return ["chat tools not read: this run's test addon has no such read (make scan-install, then run it "
                "again)"]
    if record["refused"]:
        return [f"chat tools not read: {record['refused']}"]
    if not record["topics"]:
        return ["phrase card has no topics"]
    out = [f"phrase card: {what} ({seen})" for what, seen in record["blank"]]
    if len(record["sizes"]) > 1:
        out.append(f"phrase card changes size between topics: {', '.join(record['sizes'])}")
    if record["stuck"]:
        out.append("phrase card did not close on its own command")
    if record["refused_copy"]:
        out.append(f"copy box not read: {record['refused_copy']}")
    elif record["copy"] != COPY_PROBE:
        out.append(f"copy box holds {record['copy']!r}, not the line without its codes ({COPY_PROBE!r})")
    if record["refused_words"]:
        out.append(f"chat words window not read: {record['refused_words']}")
    elif not record["words"]:
        out.append("chat words window shows no text")
    if record["refused_list"]:
        out.append(f"word list window not read: {record['refused_list']}")
    elif not record["list"] and not record["refused_words"]:
        out.append("word list window shows no text")
    if record["expect"]:
        out += [f"chat tools left English: {seen!r} ({what})" for what, seen in record["english"]]
    return out + secret_try_problems(record)


def secret_try_problems(record: dict[str, Any]) -> list[str]:
    """Why the secret chat line try proved nothing, when it did not: an error the chat tools throw on the test's
    secret lines fails the run with the run's other errors, so the try only has to show that they looked."""
    tried = record.get("secret_try")
    if tried is None:
        return ["secret chat line not tried: this run's test addon has no such try (make scan-install, then run "
                "it again)"]
    if tried["refused"]:
        return [f"secret chat line not tried: {tried['refused']}"]
    if not tried["looks"]:
        return ["secret chat line not tried: the chat tools never looked at the test's chat frame (chat word "
                "cards and the copy icon are both off, or translation is off)"]
    return []


def secret_lines_note(record: dict[str, Any]) -> str:
    """What a run saw of chat lines the client keeps secret. The game cannot be made to show one, so a run with
    none on screen proved nothing about how the chat tools take them."""
    tried = record.get("secret_try")
    made = ""
    if tried is not None and tried["looks"]:
        made = (f"the chat tools looked {tried['looks']} times at the test's own secret chat lines (a text region "
                f"holding secret text answers {', '.join(tried['answers']) or 'nothing'} with a secret); ")
    if not record["secret_lines"]:
        return made + "no secret chat line of the game's own was on screen"
    answers = ", ".join(record["secret_answers"]) or "nothing"
    return made + f"{record['secret_lines']} of the game's own on screen, answering {answers} with a secret"


def read_marks(text: str) -> dict[str, Any] | None:
    """The window test's word status read out of a saved-variables file, or None when the run had none: the text
    regions the known words window showed (`window`), the frames that carry word status marks (`frames`) and the
    marks showing on them (`shown`), the visible marked texts with words (`texts`), whether none of them showed
    a mark although no word has a status (`bare`), the quest whose text the read showed (`quest`, 0 when the
    character has none), whether the marks are on for quest text (`on`), whether Japanese was to be expected
    (`expect`), why it could
    not read (`refused`), and three lists: `english` (a text of the window with no Japanese in it), `stale` (a frame
    showing marks with no text attached any more) and `tags` (a score tag that is not a percent)."""
    from wfj.io import lua_reader

    db = lua_reader.parse_assignments(text).get("WFJScanDB")
    probe = db.get("probe") if db is not None else None
    record = probe.get("marks") if probe is not None else None
    if record is None:
        return None
    out: dict[str, Any] = {k: int(record.get(k) or 0) for k in ("window", "frames", "shown", "texts", "quest")}
    out["expect"] = bool(record.get("expect"))
    out["on"] = bool(record.get("on"))
    out["bare"] = bool(record.get("bare"))
    out["refused"] = str(record.get("refused") or "")
    for kind in ("english", "stale", "tags"):
        rows = record.get(kind)
        out[kind] = [str(r) for r in (rows.positional() if rows is not None else [])]
    return out


def marks_problems(record: dict[str, Any] | None) -> list[str]:
    """What the word status read found wrong, one line each. A run whose test addon had no such read, or one
    that could not open the known words window, proves nothing about it and says so."""
    if record is None:
        return ["word status not read: this run's test addon has no such read (make scan-install, then run it "
                "again)"]
    if record["refused"]:
        return [f"word status not read: {record['refused']}"]
    out = []
    if not record["window"]:
        out.append("known words window shows no text")
    if record["expect"]:
        out += [f"known words window left English: {seen!r}" for seen in record["english"]]
    out += [f"word status marks left on a text that is gone ({where})" for where in record["stale"]]
    if record["bare"]:
        out.append(f"no word status mark on {record['texts']} marked texts although no word has a status yet")
    out += [f"score tag does not show a percent: {seen!r}" for seen in record["tags"]]
    if record["on"] and not record["quest"]:
        out.append("word status marks not read on any text: the character has no quest in its log to show")
    elif record["on"] and not record["texts"]:
        out.append(f"word status marks not read on any text: quest {record['quest']} showed no marked text")
    return out


def _marks_read(saved: str) -> dict[str, Any] | None:
    """The word status read, with its line of the result printed when it read anything."""
    marks = read_marks(saved)
    if marks is not None and not marks["refused"]:
        print(f"word status: {marks['window']} text regions in the known words window, "
              f"{marks['shown']} marks showing on {marks['texts']} marked texts of quest {marks['quest']}")
    return marks


def freeze_problems(record: dict[str, Any] | None) -> list[str]:
    """What the frozen tooltip read found wrong, one line each. A run whose test addon had no such read, or
    one that froze nothing, proves nothing about the frozen tooltip and says so."""
    if record is None:
        return ["frozen tooltip not read: this run's test addon has no such read (make scan-install, then run it "
                "again)"]
    if record["refused"]:
        return [f"frozen tooltip not read: {record['refused']}"]
    if not record["items"]:
        return ["frozen tooltip not read: the character carries no item to freeze"]
    out = [f"frozen tooltip copy wrong: item {i} ({said})" for i, said in record["missing"]]
    out += [f"frozen tooltip did not close: item {i} ({said})" for i, said in record["stuck"]]
    if record["expect"] and record["lines"] and not record["cards"]:
        out.append(f"frozen tooltip has no word cards: {record['lines']} Japanese lines copied, none took a card")
    if record["expect"]:
        # each distinct line once: the same line on twenty tooltips is one fault
        seen: dict[str, tuple[str, str, str]] = {}
        for what, covered, line, runs in uncarded_words(record):
            seen.setdefault(line, (what, covered, runs))
        out += [f"frozen tooltip word without a card ("
                f"{'no card on the line' if covered == 'none' else 'cards on ' + covered.removeprefix('part:')}): "
                f"{runs} in {line!r} ({what})" for line, (what, covered, runs) in sorted(seen.items())]
    return out


def _joined_name(english: str, japanese: Mapping[str, str]) -> str | None:
    """A profession's spell heads its tooltip with the skill and a name ("Enchanting: Enchant Cloak - Dodge"): two
    names around one separator, each spelled by its own line."""
    head, sep, rest = english.partition(": ")
    if not sep or head not in japanese or rest not in japanese:
        return None
    return f"{japanese[head]}: {japanese[rest]}"


def _suffixed_name(english: str, japanese: Mapping[str, str]) -> str | None:
    """An item with a random suffix ("Charged Gear of Strength"): the item's name and the suffix's, each spelled
    by its own line and joined by a middle dot, the split nearest the end first, as the addon reads it
    (Core/Names.lua, `suffixed`)."""
    at = len(english)
    while (first := english.rfind(" of ", 0, at)) > 0:
        item, suffix = english[:first], english[first + 1:]
        if item in japanese and suffix in japanese:
            return f"{japanese[item]}・{japanese[suffix]}"
        at = first
    return None


def names_problems(record: dict[str, Any] | None, japanese: Mapping[str, str]) -> list[str]:
    """What the names read found wrong, one line each, held to the name list (`japanese`: English name → its
    Japanese). A name the list has a line for must show that Japanese; a name it has none for stays the client's
    English; a player's name is never changed. A run with names off, or one that read nothing, proves nothing
    and says so."""
    if record is None:
        return ["names not read: this run's test addon has no such read (make scan-install, then run it again)"]
    if record["refused"]:
        return [f"names not read: {record['refused']}"]
    if not record["on"]:
        return ["names not read: Japanese names are off (/wfj intro, pick Japanese names, Confirm, then run it "
                "again)"]
    if not record["rows"]:
        return ["names not read: nothing with a name could be read"]
    out = []
    for kind, english, shown in record["rows"]:
        want = japanese.get(english) or _joined_name(english, japanese) or _suffixed_name(english, japanese)
        if kind == "player":
            if shown != english:
                out.append(f"player's name changed: {english} shows {shown}")
        elif want is None:
            if shown != english:
                out.append(f"name changed with no line in the name list: {kind} {english} shows {shown}")
        elif shown == english:
            out.append(f"name left English: {kind} {english} (its Japanese is {want})")
        elif shown != want:
            out.append(f"name not as the name list spells it: {kind} {english} shows {shown}, the list has {want}")
    return sorted(out)


# A game name the name list has Japanese for, still in English in a window, is a line of the result too:
# (window, `NAME_LEFT <the name>`), so the baseline can allow one with its reason
NAME_LEFT = "(name left English)"
TOOLTIP_SHOWN = "tooltip under the mouse"
TARGET_TOOLTIP = "the target's tooltip"
OTHER_SHOWN = 200  # texts of the other English on screen the report prints
_LATIN_RUN = re.compile(r"[A-Za-z][A-Za-z'’\-]*(?: [A-Za-z][A-Za-z'’\-]*)*")
_JAPANESE = re.compile(r"[\u3040-\u30ff\u4e00-\u9fff]")
# a count, a range or a mark around a name in a line with no words of its own ("0/8", "2", "x", "-", "(3)")
_COUNT_TOKEN = re.compile(r"[\d/,.:%()×x\-]+")


def _bare_name(text: str) -> str:
    """`text` without the counts and marks around a name: "0/8 Solid Sharpening Stone" and "Solid Sharpening
    Stone: 0/8" both give "Solid Sharpening Stone"."""
    kept = [t for t in text.split() if not _COUNT_TOKEN.fullmatch(t)]
    return " ".join(kept).rstrip(":")
# Widgets whose name the addon must leave as the client writes it (docs/architecture/client-limits.md): text
# written there taints a protected action. Their names are counted, never failed. Chat holds what players typed.
PROTECTED_NAME_WIDGETS = (
    (re.compile(r"^PlayerSpellsFrame\.SpellBookFrame|^SpellBookFrame"), "the spellbook"),
    (re.compile(r"NavBar|^WorldMapFrameText$"), "the map's top bar"),
)
_PLAYER_TEXT_WIDGETS = re.compile(r"^ChatFrame\d|EditBox|MessageFrame|MOTD|GuildDetailsFrameNews")


def read_latin(text: str) -> dict[str, dict[str, str]]:
    """The Latin-letter text each live window read kept while Japanese names were on: window → {widget: text}.
    Empty when names were off or the run's test addon keeps none. A plain run does not read the two windows the
    player opens: what the last `/wfjtest hand` kept of them stands for it, as their lines do (`_hand_read`)."""
    from wfj.io import lua_reader

    db = lua_reader.parse_assignments(text).get("WFJScanDB")
    probe = db.get("probe") if db is not None else None
    live = probe.get("live").named() if probe is not None and probe.get("live") is not None else {}
    out: dict[str, dict[str, str]] = {}
    for window, record in live.items():
        latin = record.get("latin") if hasattr(record, "get") else None
        if latin is not None:
            where = ALWAYS if window == "(nothing open)" else _POOLED.sub("*", str(window))
            out[where] = {str(k): str(v) for k, v in latin.named().items()}
    # the targeted creature's tooltip rows under its name, which the names read keeps while names are on
    names = probe.get("names") if probe is not None else None
    target = names.get("target") if names is not None and hasattr(names, "get") else None
    if target is not None:
        out[TARGET_TOOLTIP] = {str(k): str(v) for k, v in target.named().items()}
    hand = _standing_hand(probe)[1] if probe is not None else None
    # only for a run that kept Latin text itself: with names off, an English name is no fault
    for window in HAND_WINDOWS if out and hand is not None else ():
        record = hand.get(window)
        latin = record.get("latin") if record is not None else None
        if latin is not None and window not in out:
            out[window] = {str(k): str(v) for k, v in latin.named().items()}
    return out


def latin_names(latin: Mapping[str, Mapping[str, str]], japanese: Mapping[str, str],
                keep: frozenset[str] | set[str]) -> tuple[set[tuple[str, str]], dict[str, int], list[tuple[str, str]]]:
    """The Latin text of a run held to the name list. → (the faults as result lines: a text that is a name the
    list has Japanese for, or Japanese text with such a name inside it; how many names stand in widgets the
    client protects, by what the widget is; the other English text on screen as (window, text), for the
    report). A text on screen with no window open is filed once, under that."""
    from wfj.core.names import kept_as_written

    def known(run: str) -> bool:
        return run in japanese and not kept_as_written(run, keep)

    idle = set(latin.get(ALWAYS, {}).values())
    faults: set[tuple[str, str]] = set()
    protected: dict[str, int] = {}
    other: set[tuple[str, str]] = set()
    for window, texts in latin.items():
        for widget, text in texts.items():
            # a text on screen with no window open is filed once; a page of a window repeats what the window
            # itself showed (a pooled row keeps its text under another address), so that is filed with the window
            if window != ALWAYS and text in idle:
                continue
            # the tooltip under the mouse is whatever the player pointed at while the run went on: filed once
            where = TOOLTIP_SHOWN if widget.startswith("GameTooltip") else window
            parent = where.split(" > ")[0]
            if parent != where and text in latin.get(parent, {}).values():
                continue
            if _PLAYER_TEXT_WIDGETS.search(widget):
                continue
            whole = text.strip()
            bare = _bare_name(whole)
            # a whole text that is a name, a name with only counts around it (an objective line, "0/8 Solid
            # Sharpening Stone"), or a name inside Japanese text
            runs = [whole] if known(whole) else [bare] if bare != whole and known(bare) else (
                [m.group(0) for m in _LATIN_RUN.finditer(text) if known(m.group(0))]
                if _JAPANESE.search(text) else [])
            if not runs:
                if not _JAPANESE.search(text):
                    other.add((where, whole))
                continue
            what = next((label for pattern, label in PROTECTED_NAME_WIDGETS if pattern.search(widget)), None)
            if what:
                protected[what] = protected.get(what, 0) + len(runs)
            else:
                faults |= {(where, f"{NAME_LEFT} {run}") for run in runs}
    return faults, protected, sorted(other)


def _by_id(table: Any) -> list[tuple[Any, Any]]:
    rows = table.named() if table is not None else {}
    return sorted(rows.items(), key=lambda kv: (int(kv[0]) if str(kv[0]).isdigit() else -1, str(kv[0])))


def read_left_english(text: str) -> dict[str, Any] | None:
    """The tooltip read's lines left English out of a saved-variables file, or None when the run's test addon
    kept no such list: `spells` (id, reason, what was seen, the client's line) for every spell read whose
    Japanese the addon did not show, `items` (id, the first of the item's own lines left as the client wrote it),
    and `icons` (id, the client's line carries an icon escape, the row shown carries one, the addon showed
    Japanese) for every spell whose Japanese holds an icon slot. Sorted by id."""
    from wfj.io import lua_reader

    db = lua_reader.parse_assignments(text).get("WFJScanDB")
    probe = db.get("probe") if db is not None else None
    record = probe.get("tooltips") if probe is not None else None
    if record is None or record.get("left") is None:
        return None
    return {
        "spells": [(str(k), str(v.get("reason")), str(v.get("why") or ""), str(v.get("text") or ""))
                   for k, v in _by_id(record.get("left"))],
        "items": [(str(k), str(v)) for k, v in _by_id(record.get("leftItems"))],
        "icons": [(str(k), bool(v.get("line")), bool(v.get("shown")), bool(v.get("japanese")))
                  for k, v in _by_id(record.get("icons"))],
    }


# the reasons a line was left English, in the order they are listed
LEFT_REASONS = ("icon", "values", "words", "name", "number", "none", "other")


def untranslated(left: dict[str, Any] | None, new: Iterable[str], item_ships: set[int]) -> tuple[list[str], int]:
    """The lines left English that are not a fault of the addon, one per line, `<what>\\t<reason>\\t<what was
    seen>\\t<the line>`: the spells and items of `left` (`read_left_english`), then the window lines of `new`
    (`window_test_report`'s lines the baseline does not allow; a window that did not open and Japanese in a font
    without it are faults, not text). An item is `other` when its Japanese ships (`item_ships`), else `none`.
    → (the lines, how many spells were the client's own gaps: `hole`, counted and never listed)."""
    order = {reason: n for n, reason in enumerate(LEFT_REASONS)}
    spells, items, holes = [], [], 0
    for id_, reason, why, text in (left or {}).get("spells", []):
        if reason == "hole":
            holes += 1
            continue
        spells.append((order.get(reason, len(order)), f"spell {id_}\t{reason}\t{_line(why)}\t{_line(text)}"))
    for id_, text in (left or {}).get("items", []):
        ships = id_.isdigit() and int(id_) in item_ships
        reason, why = (("other", "Japanese ships for this item and the line stayed English") if ships
                       else ("none", "no Japanese ships for this item"))
        items.append((order[reason], f"item {id_}\t{reason}\t{why}\t{_line(text)}"))
    windows = []
    for row in new:
        window, _, english = row.partition("\t")
        if not english.startswith((NOT_OPENED, BOXES)):
            windows.append(f"window {window}\twindow\tnot allowed by the baseline, so it also fails the run\t{english}")
    ranked = [row for _, row in sorted(spells, key=lambda r: r[0])] + [row for _, row in sorted(items, key=lambda r: r[0])]
    return ranked + windows, holes


def _items_with_japanese() -> set[int]:
    """The items whose Japanese description ships, from this checkout's data."""
    from wfj.emit import lua_writer
    from wfj.io.jsonl_store import Store
    from wfj.paths import data_root

    return {int(ln["id"]) for ln in Store(data_root()).load("item") if lua_writer.shipped(ln)}


def _say_left(saved: str, new: list[str]) -> None:
    """Prints the lines left English that are not a fault, whether the run passed or failed, so every run says
    what is still to translate."""
    left = read_left_english(saved)
    if left is None:
        print("left English: this run's test addon does not list the spells and items it left English "
              "(make scan-install, then run it again)")
    elif left["icons"]:
        icons = left["icons"]
        print(f"icon slots: {len(icons)} spells whose Japanese holds one; the client's line carried an icon on "
              f"{sum(1 for i in icons if i[1])}, the row shown on {sum(1 for i in icons if i[2])}; shown in Japanese "
              f"on {sum(1 for i in icons if i[3])}")
    ships = _items_with_japanese() if left is not None and left["items"] else set()
    rows, holes = untranslated(left, new, ships)
    gaps = ("1 gap the client printed for a spell this character does not know" if holes == 1
            else f"{holes} gaps the client printed for spells this character does not know")
    print(f"left English, not a fault: {len(rows)} lines (and {gaps}, counted and not listed)")
    for row in rows:
        print(f"LEFT  {row}")
    print("Report this list to the maintainer and ask what to do with it: translate these lines with this change, "
          "or name where they go.")


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
    kept = test.get("stacks")
    stacks = {str(k): str(v) for k, v in (kept.named() if kept is not None else {}).items()}
    marked = test.get("ours")
    ours = {str(k) for k in (marked.named() if marked is not None else {})}
    for kind, word in words.items():
        table = test.get(kind)
        for message, count in (table.named() if table is not None else {}).items():
            stack = stacks.get(str(message))
            through = " [ran through this addon's code]" if str(message) in ours else ""
            out.append(f"{word} x{count}: {' '.join(str(message).split())}{through}"
                       + (f" @ {' '.join(stack.split())}" if stack else ""))
    friends = test.get("friends")
    if friends is not None:
        counts = {k: friends.get(k) for k in ("battlenet", "game", "listed", "drawn")}
        known = [n for n in (counts["battlenet"], counts["game"]) if isinstance(n, (int, float))]
        if not known:
            # neither count could be read: the list was not checked, and the run says so
            out.append(f"friends list not checked: the client's friend counts could not be read ({counts})")
        elif sum(known) > 0 and not counts["drawn"]:
            out.append(f"friends list is empty: the client counts {int(sum(known))} friends and the window drew "
                       f"none ({counts})")
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


TEST_ITEMS = Path(__file__).resolve().parents[2] / "ui_test_items.txt"


def listed_items(text: str) -> dict[int, str]:
    """The items the window test shows by id, with why each is listed: `<item id>\\t<reason>` per line."""
    out: dict[int, str] = {}
    for n, raw in enumerate(text.splitlines(), 1):
        if not raw.strip() or raw.startswith("#"):
            continue
        parts = raw.split("\t")
        if len(parts) != 2 or not parts[0].strip().isdigit() or not parts[1].strip():
            raise ValueError(f"test items line {n}: expected <item id> <reason>, tab-separated")
        out[int(parts[0])] = parts[1].strip()
    return out


def read_game_errors(text: str) -> dict[str, str]:
    """The game's own errors the window test may meet, with why: `<text of the message>\\t<reason>` per line."""
    out: dict[str, str] = {}
    for n, raw in enumerate(text.splitlines(), 1):
        if not raw.strip() or raw.startswith("#"):
            continue
        parts = raw.split("\t")
        if len(parts) != 2 or not parts[0].strip() or not parts[1].strip():
            raise ValueError(f"game errors line {n}: expected <text of the message> <reason>, tab-separated")
        out[parts[0].strip()] = parts[1].strip()
    return out


OUR_FRAMES = ("AddOns/WFJScan", "AddOns/WoWForeverJapanese", "tainted by", "ran through this addon's code")


def game_own_errors(problems: list[str], listed: dict[str, str]) -> dict[str, str]:
    """The Lua errors of `problems` that are the game's own: the message holds a listed text, the error carries
    its call stack, and neither names an addon of ours. → {the problem line: the listed reason}. An error with
    no stack, one that ran through our code and one the client blames on an addon are never the game's own."""
    out: dict[str, str] = {}
    for row in problems:
        if not row.startswith("error x") or " @ " not in row or any(word in row for word in OUR_FRAMES):
            continue
        message = row.split(" @ ", 1)[0]
        for text, why in listed.items():
            if text in message:
                out[row] = why
                break
    return out


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


_FOLDER_PRODUCT = {"_forever_": "wowf", "_classic_era_": "wow_classic_era", "_retail_": "wow"}


def client_build_beside(saved: Path) -> str | None:
    """The build number the client that wrote `saved` is on now, read from the install's `.build.info` when
    `saved` lies inside a client folder (`_forever_/WTF/…`); None anywhere else. A result saved before the
    client updated is a run of the build before, and says nothing about this one."""
    from wfj.io import casc

    for folder in saved.resolve().parents:
        product = _FOLDER_PRODUCT.get(folder.name)
        if product:
            try:
                version = casc.read_build_info(folder.parent, product).version
            except casc.CascError as exc:
                print(f"window test: the client's build could not be read ({exc}); the saved run's build is not checked")
                return None
            return version.rsplit(".", 1)[-1] or None
    return None


def _print_watch(watch: dict[str, Any]) -> None:
    """Prints what the test addon read while the player played: each window, the fights and refused actions, who
    wrote a value found in the addon's name, and the expected windows not opened yet."""
    for name, rec in sorted(watch["windows"].items()):
        print(f"read in play  {name}: opened {rec['opens']} times, {rec['checked']} values read, "
              f"{len(rec['ours'])} in the addon's name (last {rec['at']})")
    minutes = watch["fight_seconds"] // 60
    ours = sum(rec["n"] for (addon, _), rec in watch["refused"].items() if addon == "WoWForeverJapanese")
    print(f"in play  {watch['fights']} fights ({minutes} minutes in them); actions the game refused in the "
          f"addon's name: {ours}")
    for (addon, action), rec in sorted(watch["refused"].items()):
        if addon != "WoWForeverJapanese":
            print(f"in play  refused in another addon's name ({addon}): {action}, {rec['n']} times")
    late = [m for m in watch["marks"] if m["sweep"] > 0]
    if watch["marks"]:
        print(f"in play  {watch['sweeps']} sweeps of every frame and global: {len(watch['marks']) - len(late)} keys "
              f"in the addon's name at login, {len(late)} more after it")
    for mark in late:
        print(f"in play  {mark['at']} sweep {mark['sweep']} {mark['part']}: {mark['name']} ({mark['owner']})")
    for row in watch["entered"]:
        print(f"in play  {row['at']} {row['key']} first read in the addon's name after {row['after']}")
        for line in row["stack"].splitlines():
            print("in play      " + line)
    for trace in watch["traces"]:
        print(f"in play  {trace['path']} was written in the addon's name by {trace['after']} at {trace['at']}"
              f" (also in its name there: {trace['near'] or 'nothing'}):")
        for line in trace["stack"].splitlines():
            print("in play      " + line)
    unread = [name for name in WATCH_EXPECTED if not watch["windows"].get(name, {}).get("checked")]
    if unread:
        print("read in play  not opened yet on this build and addon code: " + ", ".join(unread))


def _taint_reads(saved: str, part: Any, ui: Path | None, section: str | None = None) -> list[str]:
    """Prints what the crafting, touch, chat send, cover, play and open-step reads saw and gives back their problems; `part(name)` says
    whether this run holds that part."""
    out: list[str] = []
    craft = read_craft(saved) if part("craft") else None
    if craft is not None:
        print(f"crafting window: {craft['checked']} values read, {len(craft['ours'])} tainted by the addon, "
              f"{craft['own']} by the test's own steps, skill line {craft['line'] or 'none'}, "
              f"recipe {craft['recipe'] or 'none'}"
              + (", others: " + ", ".join(f"{k} ({v})" for k, v in sorted(craft["others"].items()))
                 if craft["others"] else ""))
    out += craft_problems(craft) if part("craft") else []
    touch = read_touch(saved) if part("touch") else None
    if touch is not None:
        print(f"touch: {touch['frames']} frames walked, {touch['made']} made by the addon, {touch['inside_n']} of "
              f"them inside a client frame in {len(touch['inside'])} shapes; {touch['on_client_n']} client fields "
              f"tainted by the addon" + ("" if ui else "; no UI extract given, so every field is named"))
    if part("touch"):
        out += touch_problems(touch, client_field_names(ui) if ui and touch is not None else None)
    send = read_send(saved) if part("send") else None
    if send is not None:
        print(f"chat send path: {send['checked']} values read, {len(send['tainted'])} tainted"
              + (": " + ", ".join(f"{name} ({by})" for name, by in send["tainted"][:40]) if send["tainted"] else ""))
        for label, key in (("an addon's own insert into the chat box", "after_insert"),
                           ("an addon's own open of the chat box", "after_open")):
            names = [name for name, _ in send[key]]
            print(f"chat send path: {label} taints {len(names)} values" + (": " + ", ".join(names[:40]) if names else ""))
    out += send_problems(send) if part("send") else []
    covers = read_covers(saved) if part("covers") else None
    if covers is not None and not covers["noread"]:
        print(f"popup dictionary covers: {covers['total']} held, {covers['shown']} showing, "
              f"{covers['idle']} over a text that is hidden")
    out += covers_problems(covers) if part("covers") else []
    watch = read_watch(saved)
    if watch is not None and (part("watch") or part("open")):
        _print_watch(watch)
    out += watch_problems(watch) if part("watch") else []
    if section == "isolate":
        steps = read_isolate(saved)
        if steps is not None:
            print_isolate(steps)
    if section == "open":
        opened = read_open(saved)
        if opened is not None:
            print(f"open step: {len(opened['asked'])} buttons in {opened['presses']} presses, "
                  f"{len(set(opened['windows']))} windows showed: {', '.join(sorted(set(opened['windows'])))}")
        out += open_problems(opened, watch)
    return out


def _own_reads(saved: str, section: str | None = None, ui: Path | None = None) -> list[str]:
    """Prints what the tooltip read, the no-voice read and the names read saw and gives back their problems; for a
    run of one part (`section`), only that part's: the others' records are an earlier run's."""
    def part(name: str) -> bool:
        return section is None or section == name

    tooltips = read_tooltips(saved) if part("tooltips") else None
    if tooltips is not None:
        print(f"tooltips: {tooltips['read']} spells read ({tooltips['japanese']} in Japanese, "
              f"{tooltips['unread']} the client had not loaded), {tooltips['items']} items; "
              f"{len(tooltips['changed'])} spells left English because the game changed them, "
              f"{tooltips['marked']} marked not translated")
        for id_, said in tooltips["changed"]:
            print(f"read  changed spell\t{id_}\t{said}")
        for id_, lines in sorted(tooltips["reported"].items()):
            for line in lines:
                print(f"read  listed item\t{id_}\t{line}")
        if tooltips.get("load"):
            print(f"tooltips: loading {tooltips['load']}")
        for why, (n, ids) in sorted(tooltips.get("why", {}).items()):
            print(f"tooltips: {n} not read, {why}, e.g. {ids}")
    no_voice = read_no_voice(saved) if part("novoice") else None
    if no_voice is not None:
        print(f"no-voice message: {no_voice['quests']} quests read in the quest log, {no_voice['said']} said they "
              f"have no voice; voice pack {'loaded' if no_voice['pack'] else 'not loaded'}, "
              f"{no_voice['listed']} lines listed with no voice")
    names = read_names(saved) if part("names") else None
    japanese: dict[str, str] = {}
    if names is not None and names["rows"]:
        from wfj.io.names_store import load_lines
        from wfj.paths import data_root

        japanese = {ln["en"]: ln["ja"] for ln in load_lines(data_root()) if ln.get("status") == "trusted"}
        shown = sum(1 for _, english, text in names["rows"] if text != english)
        print(f"names: {len(names['rows'])} read, {shown} shown in Japanese")
    freeze = read_freeze(saved) if part("freeze") else None
    if freeze is not None:
        print(f"frozen tooltip: {freeze['items']} item and {freeze['spells']} spell tooltips frozen, "
              f"{freeze['lines']} Japanese lines copied, {freeze['cards']} word cards, "
              f"{len(uncarded_words(freeze))} lines with a word that takes none; key {freeze['bound'] or 'none'}")
    chat = read_chat(saved) if part("chat") else None
    if chat is not None and not chat["refused"]:
        print(f"chat tools: {chat['topics']} topics and {chat['phrases']} phrases on the phrase card, "
              f"{chat['words']} text regions in the chat words window; {secret_lines_note(chat)}")
    marks = _marks_read(saved) if part("marks") else None
    bagclick = read_bagclick(saved) if part("bagclick") else None
    if bagclick is not None:
        print(f"bag click: {bagclick['checked']} values read, {bagclick['pointed']} bag item buttons pointed at, "
              f"{bagclick['tooltips']} bag item tooltips shown, "
              f"{len(bagclick['ours'])} tainted by the addon, {bagclick['own']} by the test's own steps "
              "(which the read cannot tell from the addon's)"
              + (", others: " + ", ".join(f"{k} ({v})" for k, v in sorted(bagclick["others"].items()))
                 if bagclick["others"] else ""))
    plates = read_plates(saved) if part("plates") else None
    if plates is not None and not plates["refused"]:
        v, d = plates["values"], plates["defaults"]
        print(f"nameplates: range {v.get('nameplateMaxDistance')} (default {d.get('nameplateMaxDistance')}, the "
              f"client holds up to {plates['limit'] or 'unknown'}); English names over NPC heads "
              + ", ".join(f"{k} {v.get(k)}" for k in PLATE_WANT))
    load = read_load(saved) if part("load") else None
    if load:
        said = [f"{load['kb'] / 1024:.0f} MB of Lua memory"] if "kb" in load else []
        said += [f"files loaded in {load['files']:.0f} ms"] if "files" in load else []
        said += [f"setup {load['setup']:.0f} ms"] if "setup" in load else []
        print("addon load: " + ", ".join(said))
    out = included_problems(saved) + tooltip_problems(tooltips) if part("tooltips") else []
    out += no_voice_problems(no_voice) if part("novoice") else []
    out += names_problems(names, japanese) if part("names") else []
    out += chat_problems(chat) if part("chat") else []
    out += marks_problems(marks) if part("marks") else []
    out += freeze_problems(freeze) if part("freeze") else []
    out += plates_problems(plates) if part("plates") else []
    out += bagclick_problems(bagclick) if part("bagclick") else []
    return out + _taint_reads(saved, part, ui, section)


# A refusal only a click of the test's own causes, which no player's click does: listed, never a failure. A
# Communities tab redraws the list of communities, and a row with a picture sets it through a call the client
# refuses to addon code (CommunitiesList.lua:523, reached from CommunitiesTabs.lua:6). The test leaves that window
# to the player, so this is met only when a click of the test's reaches such a tab from another window.
OWN_REFUSALS = ("WFJScan SetAvatarTexture()", "AddOn 'WFJScan' tried to call the protected function 'SetAvatarTexture()'")


def _names_in_windows(latin: Mapping[str, Mapping[str, str]]) -> tuple[
        set[tuple[str, str]], dict[str, int], list[tuple[str, str]]]:
    """`latin_names` over a run's Latin text, with the name list and the kept-as-written words of this checkout."""
    if not latin:
        return set(), {}, []
    from wfj.cmd.generate import load_kept_as_written
    from wfj.io.names_store import load_lines
    from wfj.paths import data_root

    japanese = {ln["en"]: ln["ja"] for ln in load_lines(data_root()) if ln.get("status") == "trusted"}
    return latin_names(latin, japanese, load_kept_as_written(data_root()))


TRACES_SHOWN = 6  # passes of the addon's own tooltip trace the report prints


ROWS_SHOWN = 400  # kinds of English row, and of English word inside a Japanese row, the report prints


def read_tooltip_rows(saved: str) -> tuple[int, list[tuple[int, str, str]], list[tuple[int, str, str]]]:
    """Every row of every tooltip the run showed, as the test addon kept them: (how many tooltips, the rows with
    no Japanese at all, the Latin words inside Japanese rows), each as (how often, the text, one tooltip that
    shows it), most frequent first. Digits in a whole row are folded to `#`."""
    from wfj.io import lua_reader

    db = lua_reader.parse_assignments(saved).get("WFJScanDB")
    probe = db.get("probe") if db is not None else None
    record = probe.get("tooltips") if probe is not None else None
    rows = record.get("rows") if record is not None else None
    if rows is None:
        return 0, [], []

    def listed(name: str) -> list[tuple[int, str, str]]:
        table = rows.get(name)
        out = [(int(v.get("n") or 0), str(k), str(v.get("at"))) for k, v in (table.named().items() if table else [])]
        return sorted(out, key=lambda r: (-r[0], r[1]))

    return int(rows.get("tooltips") or 0), listed("english"), listed("runs")


def tooltip_row_problems(saved: str) -> list[str]:
    """One failure line when any tooltip row still shows English: a row with no Japanese, or a Latin word inside
    a Japanese row that the name list has Japanese for or that is no name at all. The rows themselves are
    printed by `_say_rows`."""
    tooltips, english, runs = read_tooltip_rows(saved)
    if not tooltips:
        return ["tooltip rows not read: this run's test addon reads the description row only (make scan-install, "
                "then run it again)"]
    if english or runs:
        return [f"English on tooltips: {len(english)} kinds of row with no Japanese and {len(runs)} English words "
                f"inside Japanese rows, over {tooltips} tooltips (listed below as ROW and WORD)"]
    return []


def _say_rows(saved: str) -> None:
    tooltips, english, runs = read_tooltip_rows(saved)
    if not tooltips:
        return
    print(f"tooltip rows: {tooltips} tooltips read row by row; {len(english)} kinds of row with no Japanese, "
          f"{len(runs)} English words inside Japanese rows")
    for n, text, at in english[:ROWS_SHOWN]:
        print(f"ROW   x{n}\t{text}\t({at})")
    if len(english) > ROWS_SHOWN:
        print(f"ROW   (and {len(english) - ROWS_SHOWN} more kinds)")
    for n, text, at in runs[:ROWS_SHOWN]:
        print(f"WORD  x{n}\t{text}\t({at})")
    if len(runs) > ROWS_SHOWN:
        print(f"WORD  (and {len(runs) - ROWS_SHOWN} more)")


# A hovered tooltip's English as a line of the baseline: (window, `HOVER <text>`), so the baseline can allow one
# with its reason. A word inside a Japanese row is its own text.
HOVER = "(hover)"
_HOVER_COUNTS = ("made", "found", "skipped", "denied", "tips", "units", "loading")


def _hover_windows(table: Any) -> dict[str, dict[str, Any]]:
    out: dict[str, dict[str, Any]] = {}
    for window, rec in (table.named().items() if table is not None else []):
        if not hasattr(rec, "get"):
            continue
        entry: dict[str, Any] = {k: int(rec.get(k) or 0) for k in _HOVER_COUNTS}
        entry["stopped"] = str(rec.get("stopped") or "")
        entry["capped"] = bool(rec.get("capped"))
        for kind in ("english", "runs"):
            kept = rec.get(kind)
            rows = [(int(v.get("n") or 0), str(k), str(v.get("frame") or ""), str(v.get("raw") or ""))
                    for k, v in (kept.named().items() if kept is not None else [])]
            entry[kind] = sorted(rows, key=lambda r: (-r[0], r[1]))
        out[_POOLED.sub("*", str(window))] = entry
    return out


def read_hover(saved: str) -> dict[str, dict[str, Any]] | None:
    """The hover read out of a saved-variables file, or None when the run's test addon has none: window →
    {how many frames were pointed at (`made`), found (`found`), found and not pointed at (`skipped`), left alone
    (`denied`), how many showed a tooltip read row by row (`tips`), a unit's tooltip (`units`, never read) or one
    still loading (`loading`); `stopped` (why the window's hovering stopped early), `capped` (the cap was reached),
    and the rows left English: `english` (rows with no Japanese) and `runs` (Latin words inside Japanese rows), each
    as (how often, the text, the frame, the row as written), most frequent first}. A plain run does not read the
    two windows the player opens: what the last `/wfjtest hand` kept of them stands for it, as their lines do."""
    from wfj.io import lua_reader

    db = lua_reader.parse_assignments(saved).get("WFJScanDB")
    probe = db.get("probe") if db is not None else None
    record = probe.get("hover") if probe is not None else None
    if record is None:
        return None
    windows = _hover_windows(record)
    hand = _standing_hand(probe)[1]
    if hand is not None and hand.get("hover") is not None:
        for window, entry in _hover_windows(hand.get("hover")).items():
            windows.setdefault(window, entry)
    return windows


def hover_faults(hover: Mapping[str, Mapping[str, Any]], baseline: Mapping[tuple[str, str], str],
                 japanese: Mapping[str, str], keep: frozenset[str] | set[str],
                 names_on: bool) -> tuple[list[tuple[str, int, str, str, str]], int]:
    """The English rows and words of the hover read that fail the run, as (window, how often, the text, the frame,
    the row as written), and how many were allowed. Allowed: a line the baseline allows for the window
    (`HOVER <text>`), a word the screen keeps as written, and a game name of the name list while Japanese names are
    off (names stay English then). With Japanese names on, a name the list has Japanese for is a fault."""
    from wfj.core.names import kept_as_written

    faults: list[tuple[str, int, str, str, str]] = []
    allowed = 0
    for window, entry in sorted(hover.items()):
        for n, text, frame, raw in [*entry.get("english", []), *entry.get("runs", [])]:
            line = f"{HOVER} {_line(text)}"
            named = text in japanese
            if ((window, line) in baseline or (window.split(" > ")[0], line) in baseline
                    or kept_as_written(text, keep) or (named and not names_on)):
                allowed += 1
            else:
                faults.append((window, n, text, frame, raw))
    return faults, allowed


def hover_problems(hover: Mapping[str, Mapping[str, Any]] | None,
                   faults: list[tuple[str, int, str, str, str]]) -> list[str]:
    """What the hover read found wrong, one line each: a window whose hovering a fight stopped, a run that pointed
    at nothing, and one line for every English row and word left on hovered tooltips (printed by `_say_hover`).
    A run whose test addon has no hover read says so: its result proves nothing about those tooltips."""
    if hover is None:
        return ["hover not read: this run's test addon does not point at a window's frames (make scan-install, "
                "then run it again)"]
    out = [f"hover stopped in {window}: {entry['stopped']} (run it again out of combat)"
           for window, entry in sorted(hover.items()) if entry["stopped"]]
    if not sum(entry["made"] for entry in hover.values()):
        out.append("hover not read: no frame of any window was pointed at")
    if faults:
        windows = len({window for window, *_ in faults})
        out.append(f"English on hovered tooltips: {len(faults)} rows or words in {windows} windows (listed below "
                   "as HOVER)")
    return out


def _say_hover(hover: Mapping[str, Mapping[str, Any]] | None, faults: list[tuple[str, int, str, str, str]],
               allowed: int) -> None:
    if hover is None:
        return
    for window, entry in sorted(hover.items()):
        notes = [f"{entry['tips']} tooltips read", f"{entry['denied']} left alone"]
        notes += ["cap reached"] if entry["capped"] else []
        notes += [f"stopped: {entry['stopped']}"] if entry["stopped"] else []
        print(f"hover: {window}: {entry['made']} hovered, {entry['skipped']} skipped ({', '.join(notes)})")
    print(f"hovered tooltips: {len(faults)} English rows or words fail the run, {allowed} allowed (a name while "
          "Japanese names are off, a word kept as written, or the baseline)")
    for window, n, text, frame, raw in faults[:ROWS_SHOWN]:
        print(f"HOVER x{n} {text} ({window} {frame}: {raw})")
    if len(faults) > ROWS_SHOWN:
        print(f"HOVER (and {len(faults) - ROWS_SHOWN} more)")


def _name_list() -> tuple[dict[str, str], frozenset[str]]:
    """This checkout's name list (English → Japanese, trusted lines) and the words the screen keeps as written."""
    from wfj.cmd.generate import load_kept_as_written
    from wfj.io.names_store import load_lines
    from wfj.paths import data_root

    japanese = {ln["en"]: ln["ja"] for ln in load_lines(data_root()) if ln.get("status") == "trusted"}
    return japanese, load_kept_as_written(data_root())


def _included_rows(saved: str) -> list[tuple[str, Any]]:
    from wfj.io import lua_reader

    db = lua_reader.parse_assignments(saved).get("WFJScanDB")
    probe = db.get("probe") if db is not None else None
    record = probe.get("tooltips") if probe is not None else None
    spliced = record.get("spliced") if record is not None else None
    return [(spell, row) for spell, row in _by_id(spliced) if hasattr(row, "get")]


def included_lines(saved: str) -> list[str]:
    """The spells read cold before the spells their English splices in had loaded (`noteIncluded`): how many
    showed Japanese once those had loaded (`recheckIncluded`), then, for each one that did not, its whole line, how
    the client held each spliced-in spell when the line was read and at the end of the read, and the tooltip shown
    cold, after a wait and shown again. The report's lines; none for a run from a test addon without this read."""
    rows = _included_rows(saved)
    if not rows:
        return []
    fixed = sum(1 for _, row in rows if str(row.get("after") or "").startswith("Japanese"))
    out = [f"spliced-in spells: {len(rows)} spells read before the spells they splice in had loaded, {fixed} "
           "shown in Japanese once they had"]
    for spell, row in rows:
        if str(row.get("after") or "").startswith("Japanese"):
            continue
        out.append(f"INCL  spell {spell} ({row.get('why')}), its whole line: {_line(str(row.get('text') or ''))}")
        after = row.get("includedAfter")
        for sid, state in _by_id(row.get("included")):
            out.append(f"INCL    splices in {sid}: when read, {_line(str(state))}")
            if after is not None and after.get(sid) is not None:
                out.append(f"INCL    splices in {sid}: at the end, {_line(str(after.get(sid)))}")
        for key, label in (("cold", "shown cold"), ("waited", "the same tooltip after a wait"),
                           ("after", "shown again")):
            out.append(f"INCL    {label}: {row.get(key) or 'not read'}")
    return out


def included_problems(saved: str) -> list[str]:
    """A spell still English when shown again although every spell it splices in was loaded: its Japanese does not
    fit the client's whole line, so loading them is not what keeps it English. One line each."""
    out = []
    for spell, row in _included_rows(saved):
        after, loaded = row.get("after"), row.get("includedAfter")
        states = [str(v) for _, v in _by_id(loaded)] if loaded is not None else []
        if after and str(after).startswith("English") and states and all(v.startswith("loaded true") for v in states):
            out.append(f"tooltip still English with every spell it splices in loaded: spell {spell} ({after})")
    return out


def _say_included(saved: str) -> None:
    """Prints `included_lines`."""
    for line in included_lines(saved):
        print(line)


def _say_traces(saved: str) -> None:
    """Prints what the addon's own tooltip trace recorded for the first spells it left English: the pass over
    that tooltip, row by row, with what the addon rendered. It answers why from the addon's side."""
    from wfj.io import lua_reader

    db = lua_reader.parse_assignments(saved).get("WFJScanDB")
    probe = db.get("probe") if db is not None else None
    record = probe.get("tooltips") if probe is not None else None
    left = record.get("left") if record is not None else None
    shown = 0
    for spell, row in (left.named().items() if left is not None else []):
        trace = row.get("trace") if hasattr(row, "get") else None
        if trace is None or shown >= TRACES_SHOWN:
            continue
        shown += 1
        print(f"TRACE spell {spell} left English ({row.get('reason')}): {row.get('text')}")
        print(f"TRACE   the run read row {row.get('row')} of {row.get('rows')} and saw: {row.get('saw')}")
        print(f"TRACE   every row right after: {row.get('now')}")
        for line in str(trace).replace("\\n", "\n").splitlines():
            print(f"TRACE   {line}")
    rows = record.get("rows") if record is not None else None
    for name in ("english", "runs"):
        table = rows.get(name) if rows is not None else None
        for text, row in (table.named().items() if table is not None else []):
            if not hasattr(row, "get") or row.get("data") is None:
                continue
            print(f"TRACE row left English: {text} ({row.get('at')})")
            print(f"TRACE   tooltip data: {row.get('data')}")
            for line in str(row.get("trace")).replace("\\n", "\n").splitlines():
                print(f"TRACE   {line}")
    kept = record.get("shownTraces") if record is not None else None
    for spell, row in list(kept.named().items() if kept is not None else [])[:3]:
        print(f"TRACE spell {spell} shown in Japanese: {row.get('text')}")
        for line in str(row.get("trace")).replace("\\n", "\n").splitlines():
            print(f"TRACE   {line}")


def _say_other(read: bool, protected: Mapping[str, int], other: list[tuple[str, str]]) -> None:
    """Prints the names the client protects and the other English text on screen, so every run says what a
    player still reads in English."""
    if not read:
        print("names in windows: not read (Japanese names are off, or this run's test addon keeps no Latin text: "
              "make scan-install, then run it again)")
        return
    for what, n in sorted(protected.items()):
        print(f"names in windows: {n} left English in {what}, which the client protects")
    print(f"other English on screen, not a name and not in the dictionary: {len(other)} texts")
    for window, text in other[:OTHER_SHOWN]:
        print(f"OTHER {window}\t{text}")
    if len(other) > OTHER_SHOWN:
        print(f"OTHER (and {len(other) - OTHER_SHOWN} more)")


def _say_head(info: dict[str, str], text: str) -> str | None:
    """Prints what the run was before its result: one part or the whole test, the windows this client lacks, the
    hand read and the interface strings the client does not hand to addons. → the part a run of one part ran.
    A run of one part (`/wfjtest <part>`) is judged on that part and the errors of its run; the rest of the saved
    file is an earlier run's."""
    section = info.get("section") or None
    windows = section in (None, "live", "closed")
    if section:
        print(f"window test: a run of the {section} part only; plain /wfjtest runs them all and is the bar before "
              "a merge")
    if info.get("absent") and windows:
        print(f"windows this client does not have: {info['absent']}")
    if info.get("hand") and windows:
        print(f"guild and character windows: {info['hand']}, not in this run")
    asked, missing = read_missing_strings(text)
    if asked and not section:
        # grouped by the first two words of the name: a whole family missing reads as one line
        groups: dict[str, int] = {}
        for name in missing:
            head = "_".join(name.split("_")[:2])
            groups[head] = groups.get(head, 0) + 1
        print(f"dictionary strings the client does not hand to addons: {len(missing)} of {asked}")
        for head, n in sorted(groups.items(), key=lambda kv: (-kv[1], kv[0]))[:40]:
            print(f"read  not handed to addons\t{head}\t{n}")
    return section


def _say_errors(problems: list[str], listed: Path) -> list[str]:
    """Prints the run's problems as failures, as errors of windows shown bare and as the game's own errors that
    `listed` sets aside. → the failures."""
    # the open sweep shows a window without the client's own opening code, so a window that needs data it was
    # never given errors by itself: listed, never a failure. The live sweep opens windows the client's way.
    noted = [row for row in problems if ": [open] " in row or any(own in row for own in OWN_REFUSALS)]
    own = game_own_errors([row for row in problems if row not in noted],
                          read_game_errors(listed.read_text(encoding="utf-8")) if listed.exists() else {})
    failing = [row for row in problems if row not in noted and row not in own]
    print(f"errors during the run: {len(failing)} (and {len(noted)} from windows shown bare, {len(own)} the "
          "game's own)")
    for row in failing:
        print(f"ERROR {row}")
    for row in noted:
        print(f"noted {row}")
    for row, why in sorted(own.items()):
        print(f"game  {row}\n      listed: {why}")
    return failing


def _say_tail(text: str, section: str | None, hover: tuple[Any, Any, Any], latin: tuple[Any, Any, Any],
              new: list[str]) -> None:
    """Prints the lists that end a result, those of the parts the run ran: tooltip rows, hovered tooltips, traces,
    included text, Latin words in windows and the lines left English."""
    windows = section in (None, "live", "closed")
    if section in (None, "tooltips"):
        _say_rows(text)
    if section in (None, "live"):
        _say_hover(*hover)
    if section in (None, "tooltips"):
        _say_traces(text)
        _say_included(text)
    if windows:
        _say_other(*latin)
    if section in (None, "tooltips", "live"):
        _say_left(text, new)


def _texts(args: argparse.Namespace) -> int:
    """The `texts` command: the window test's saved result against the baseline. → the exit code."""
    text = args.saved.read_text(encoding="utf-8", errors="replace")
    info, found = read_window_test(text)
    now = client_build_beside(args.saved)
    if now and info.get("build") and now != info["build"]:
        print(f"window test: the saved run is of build {info['build']} and the client is on {now} now: "
              "run /wfjtest again on this build")
        return 2
    if not info.get("finished") and info.get("part") in ("guild", "character"):
        print(f"window test: the run stopped while waiting for the {info['part']} window; the rest is read below")
    elif not info.get("finished"):
        print("window test: no finished run in the saved file (run /wfjtest, wait for its done line, /reload)")
        return 2
    section = _say_head(info, text)
    windows = section in (None, "live", "closed")
    latin = read_latin(text)
    faults, protected, other = _names_in_windows(latin)
    found |= faults
    baseline = read_window_baseline(args.baseline.read_text(encoding="utf-8")) if args.baseline.exists() else {}
    # a hovered tooltip's lines are held to the baseline by the hover read, never taken for a line on screen
    hover_baseline = {key: why for key, why in baseline.items() if key[1].startswith(f"{HOVER} ")}
    baseline = {key: why for key, why in baseline.items() if key not in hover_baseline}
    new, gone = window_test_report(found, baseline)
    hover = read_hover(text)
    hover_seen = {(w, f"{HOVER} {_line(text)}") for w, entry in (hover or {}).items()
                  for _, text, _, _ in [*entry["english"], *entry["runs"]]}
    gone += sorted(f"{w}\t{en}" for w, en in hover_baseline
                   if not any((seen_w == w or seen_w.split(" > ")[0] == w) and seen_en == en
                              for seen_w, seen_en in hover_seen))
    names = read_names(text)
    listed_names = _name_list() if hover_seen else ({}, frozenset())
    hovered, hover_allowed = hover_faults(hover or {}, hover_baseline, *listed_names,
                                          names_on=bool(names and names["on"]))
    # a window the open sweep showed did not run the client's opening code, so a surface that works from that
    # code never ran: its English is a list to read against the code, never a failure, like its errors
    # a closed window read without being shown is the same kind of list
    bare = [row for row in new if row.startswith(("opened ", "closed "))]
    new = [row for row in new if row not in bare]
    if not windows:
        found, new, bare, gone, hovered = set(), [], [], [], []
    elif section == "closed":
        # the live and hover records are an earlier run's: only the windows read closed are this run's
        found = {row for row in found if row[0].startswith(("closed ", "opened "))}
        new, gone, hovered = [], [], []
    print(f"window test of build {info.get('build')}, run {info.get('started')}"
          + (f": {len(found)} English lines on screen, {len(found) - len(new) - len(bare)} allowed by the baseline, "
             f"{len(new)} new in the windows opened the client's way, {len(bare)} to read in closed windows"
             if windows else ""))
    for row in new:
        print(f"NEW   {row}")
    for row in bare:
        print(f"read  {row}")
    for row in gone:
        print(f"gone  {row}")
    log = args.log or args.saved.with_name("WoWForeverJapanese.lua")
    problems = read_test_problems(text,
                                  log.read_text(encoding="utf-8", errors="replace") if log.exists() else "")
    problems += _own_reads(text, section, getattr(args, "ui", None))
    if section in (None, "tooltips"):
        problems += tooltip_row_problems(text)
    if section in (None, "live"):
        problems += hover_problems(hover, hovered)
    failing = _say_errors(problems, args.baseline.with_name("ui_test_game_errors.txt"))
    _say_tail(text, section, (hover, hovered, hover_allowed), (bool(latin), protected, other), new)
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
    t.add_argument("--ui", type=Path, help="the client's UI extract (Interface/AddOns), for the names its code uses")
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
        keys = translated_keys(args.window_test) if args.window_test else ()
        values = spell_value_counts(args.window_test) if args.window_test else None
        japanese = spell_japanese(args.window_test, values or {}) if args.window_test else None
        gate = ((args.window_test.resolve().parent / ALIGN_LUA).read_text(encoding="utf-8")
                if args.window_test else None)
        items = listed_items(TEST_ITEMS.read_text(encoding="utf-8")) if TEST_ITEMS.exists() else {}
        includes = spell_includes(args.window_test, values or {}) if args.window_test else None
        text = probe_lua(manifest, walk=args.walk or bool(args.window_test), english=english,
                         at_login=args.walk, keys=keys, values=values, japanese=japanese, gate=gate,
                         items=items, includes=includes)
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
