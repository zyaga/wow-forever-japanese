"""What the addon depends on in the client, and what a client answers for it.

    python -m wfj.dev.client_surface build --addon <addon dir> --out surface-manifest.json
    python -m wfj.dev.client_surface probe --manifest surface-manifest.json --addon-out <dir>
    python -m wfj.dev.client_surface report --manifest surface-manifest.json --probe <pasted output> \
        [--source <dir of extracted client UI>] --out verdicts.json

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

`probe --addon-out` writes a small probe addon (`WFJProbe.toc` + `WFJProbe.lua`) to install in the client. It
answers every name at login, and sweeps again whenever a load-on-demand addon loads and on `/wfjprobe
<surface>` (the player marking a surface as asked with its window open, which is the only evidence
separating "the client removed it" from "nobody ever opened it"), so a surface whose window was opened is
answered too, and the addons that loaded are recorded. It saves to SavedVariables (`WFJProbeDB`), stamped
with the manifest it was built from so answers from another manifest are dropped rather than merged.
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
from pathlib import Path
from typing import Any

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


def probe_names(manifest: dict[str, Any]) -> list[tuple[str, str]]:
    """(kind, name) to ask the client about, deduped. A dynamic entry has no name to ask for, and a `method`
    entry is a method on an object (`hooksecurefunc(frame, "Update")`); asking `_G` for it means nothing, so
    it is reported from its surface's own verdict instead."""
    out: list[tuple[str, str]] = []
    seen: set[tuple[str, str]] = set()
    for e in manifest["entries"]:
        if not e.get("name") or e["kind"] == "method":
            continue
        key = (e["kind"], e["name"])
        if key not in seen:
            seen.add(key)
            out.append(key)
    return out


PROBE_ADDON = """-- Asks this client for every name the addon depends on, saves the answers to
-- SavedVariables (`WFJProbeDB`), which `wfj.dev.client_surface report` reads. Generated; do not hand-edit.
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
  if type(WFJProbeDB) ~= "table" or WFJProbeDB.manifest ~= MANIFEST or WFJProbeDB.client ~= build then
    WFJProbeDB = { manifest = MANIFEST, client = build, answers = {}, loaded = {}, asked = {} }
  end
  WFJProbeDB.manifest = MANIFEST
  WFJProbeDB.client = build
  WFJProbeDB.build = { GetBuildInfo() }
  WFJProbeDB.answers = WFJProbeDB.answers or {}
  WFJProbeDB.loaded = WFJProbeDB.loaded or {}
  WFJProbeDB.asked = WFJProbeDB.asked or {}   -- surface → sweeps run while the player had its window open
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
    if answer ~= "no" or WFJProbeDB.answers[key] == nil then
      WFJProbeDB.answers[key] = answer
    end
  end
end

f:SetScript("OnEvent", function(_, event, addon)
  sweep()
  if event == "ADDON_LOADED" and addon then
    WFJProbeDB.loaded[addon] = true
  end
  if event == "PLAYER_LOGIN" then
    print("WFJ probe: " .. #NAMES .. " names checked · build " .. tostring(WFJProbeDB.build[1]) ..
      " · interface " .. tostring(WFJProbeDB.build[4]) ..
      ". Open a window, then /wfjprobe <surface>; /wfjprobe lists what is left")
  end
end)

-- The `lod` tag only covers a surface whose Blizzard addon our own addon names in
-- LoadOnDemand.when. A window the client builds on first show without a load-on-demand addon (the
-- guild frame is the open case) has no such tag, so its absences read as proven when nobody ever
-- opened it. `/wfjprobe <surface>` is the player saying "it is open now, ask again": the only evidence that
-- separates "the client removed it" from "it was never built".
local function remaining()
  local out = {}
  for surface in pairs(SURFACES) do
    if not WINDOWLESS[surface] and (WFJProbeDB.asked[surface] or 0) == 0 then out[#out + 1] = surface end
  end
  table.sort(out)
  return out
end

SLASH_WFJPROBE1 = "/wfjprobe"
SlashCmdList["WFJPROBE"] = function(arg)
  arg = (arg or ""):lower():gsub("^%%s+", ""):gsub("%%s+$", "")
  if type(WFJProbeDB) ~= "table" or WFJProbeDB.answers == nil then
    print("WFJ probe: not loaded yet")
    return
  end
  WFJProbeDB.asked = WFJProbeDB.asked or {}
  if arg == "" then
    local left = remaining()
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
  sweep()
  WFJProbeDB.asked[arg] = (WFJProbeDB.asked[arg] or 0) + 1
  print("WFJ probe: " .. arg .. " asked · " .. #remaining() ..
    " surfaces still unasked; /reload to save")
end
"""

PROBE_TOC = """## Interface: {interface}
## Title: WFJ Probe
## Notes: client surface probe; reports what this client has, translates nothing
## SavedVariables: WFJProbeDB
WFJProbe.lua
"""


def target_interface(repo: Path) -> int:
    """The interface number `pipeline/clients.toml` targets, so the probe is never out of date by default."""
    text = (repo / "pipeline" / "clients.toml").read_text(encoding="utf-8")
    section = re.search(r"^\[forever\](.*?)(?=^\[|\Z)", text, re.M | re.S)
    m = re.search(r"^interface\s*=\s*(\d+)", section.group(1), re.M) if section else None
    if not m:
        raise SystemExit("client_surface: no [forever].interface in pipeline/clients.toml")
    return int(m.group(1))


def probe_addon(manifest: dict[str, Any], out: Path, interface: int) -> Path:
    """A probe addon in `out`: every manifest name with its surface, checked at login, saved for `report`."""
    surfaces = {(e["kind"], e["name"]): e["surface"] for e in manifest["entries"] if e.get("name")}
    rows = [f'  {{"{kind}","{name}","{surfaces[(kind, name)]}"}},' for kind, name in probe_names(manifest)]
    probed = set(surfaces.values())
    bare = sorted({e["surface"] for e in manifest["entries"]
                   if e.get("windowless") and e["surface"] in probed})
    out.mkdir(parents=True, exist_ok=True)
    stamp = hashlib.sha256("\n".join(rows).encode("utf-8")).hexdigest()[:12]
    windowless_lua = " ".join(f'["{s}"] = true,' for s in bare)
    lua = PROBE_ADDON % (stamp, "\n".join(rows), windowless_lua)
    (out / "WFJProbe.lua").write_text(lua, encoding="utf-8")
    (out / "WFJProbe.toc").write_text(PROBE_TOC.format(interface=interface), encoding="utf-8")
    return out


# a dotted name of any depth (Enum.TooltipDataType.Item), as `_RESOLVE` and Core/Compat.lua accept
_SV_ENTRY = re.compile(
    r'\["(global|function|script|api)\|([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)\|([a-z_0-9]+)"\]'
    r'\s*=\s*"([^"]*)"'
)
_SV_BUILD = re.compile(r'\["build"\]\s*=\s*\{(.*?)\}', re.S)
_SV_LOADED = re.compile(r'\["loaded"\]\s*=\s*\{(.*?)\n\t?\}', re.S)
_SV_ASKED = re.compile(r'\["asked"\]\s*=\s*\{(.*?)\n\t?\}', re.S)
_SV_ASKED_ENTRY = re.compile(r'\["([a-z_0-9.]+)"\]\s*=\s*(\d+)')


def asked_surfaces(text: str) -> dict[str, int] | None:
    """The probe's `asked` table: surface → how many sweeps the player ran with its window open
    (`/wfjprobe <surface>`). `None` when the file carries no such table, i.e. a probe from an older
    generator: the caller then keeps the `lod`-only rule rather than calling every absence unknown."""
    m = _SV_ASKED.search(text)
    if not m:
        return None
    return {s: int(n) for s, n in _SV_ASKED_ENTRY.findall(m.group(1))}


def read_saved_variables(text: str) -> dict[str, str]:
    """`WFJProbeDB` as the client saves it → the same shape `read_probe` returns. The probe records what each
    name *is* (`frame`, `function`, `no`), so anything but `no` counts as present. `build` is the interface
    number from `GetBuildInfo()` (its fourth value), which the TOC needs."""
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



def source_hits(source: Path | None, names: list[str]) -> dict[str, str]:
    """name → the extracted client file it appears in, or "" when absent. No source dir: {}."""
    if source is None:
        return {}
    files = [p for p in source.rglob("*") if p.is_file()]
    texts = {p: p.read_text(encoding="utf-8", errors="replace") for p in files}
    hits: dict[str, str] = {}
    for name in names:
        hits[name] = ""
        for p, text in texts.items():
            if re.search(rf"(?<![A-Za-z0-9_]){re.escape(name)}(?![A-Za-z0-9_])", text):
                hits[name] = p.name
                break
    return hits


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
           asked: dict[str, int] | None = None) -> dict[str, Any]:
    names = [e["name"] for e in manifest["entries"] if e.get("name")]
    hits = source_hits(source, sorted(set(names)))
    rows = []
    for e in manifest["entries"]:
        v, why = verdict(e, probe, hits, asked)
        rows.append({**e, "verdict": v, "evidence": why})
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


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="client_surface", description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build")
    b.add_argument("--addon", required=True, type=Path)
    b.add_argument("--out", required=True, type=Path)
    p = sub.add_parser("probe")
    p.add_argument("--manifest", required=True, type=Path)
    p.add_argument("--addon-out", required=True, type=Path, help="where to write the probe addon")
    p.add_argument("--interface", type=int, help="TOC interface number (default: clients.toml's)")
    r = sub.add_parser("report")
    r.add_argument("--manifest", required=True, type=Path)
    r.add_argument("--probe", required=True, type=Path,
                   help="the pasted /run output, or the client's WFJProbeDB SavedVariables file")
    r.add_argument("--source", type=Path)
    r.add_argument("--out", required=True, type=Path)
    args = ap.parse_args(argv)
    if args.cmd == "build":
        manifest = build(args.addon)
        args.out.write_text(json.dumps(manifest, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
        print("\n".join(summary(manifest)))
        return 0
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    if args.cmd == "probe":
        repo = Path(__file__).resolve().parents[3]
        out = probe_addon(manifest, args.addon_out, args.interface or target_interface(repo))
        print(f"probe addon: {len(probe_names(manifest))} names → {out}")
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
    result = report(manifest, answers, args.source, asked_surfaces(raw))
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
    if result["asked"] is None:
        print("probe predates /wfjprobe: an absence outside a load-on-demand surface is occasion-blind",
              file=sys.stderr)
    elif result["unopened"]:
        print(f"{len(result['unopened'])} surfaces never asked with their window open: "
              + " ".join(result["unopened"]), file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
