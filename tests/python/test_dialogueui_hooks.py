"""ADR-073: the addon never puts a function of its own in place of a method or field of Dialogue UI's objects.

A replaced method runs Dialogue UI's own code inside the addon's function, so every value it writes there (the click
handler an option button keeps) carries the addon's taint, and Dialogue UI's own click then runs on it: an option
that opens a vendor shows the game's interface again on that taint, and the bag click that follows is blocked in the
addon's name. The Dialogue UI modules only follow its methods with hooksecurefunc and write the Japanese afterwards.

For the same reason nothing in the addon hooks a script of UIParent: Dialogue UI shows the hidden interface again with
its window's close, and the bags and a vendor window run their OnShow inside that same call.
"""

import re
from pathlib import Path

import pytest

ADDON = Path("addon/WoWForeverJapanese")
DUI_FILES = ("UI/DialogueUI.lua", "UI/DialogueUIFrames.lua", "UI/DialogueUIBook.lua")
# the modules' own tables: functions on these are the addon's API, never Dialogue UI's
OWN = {"DialogueUI", "Frames", "Book", "Holder", "WFJ"}

# obj.Key = function / obj.a.Key = function
FIELD_FUNCTION = re.compile(r"\b([A-Za-z_]\w*)((?:\.\w+)*)\.(\w+)\s*=\s*function\b")
# function obj:Method( / function obj.Method(
FUNCTION_DEF = re.compile(r"\bfunction\s+([A-Za-z_]\w*)((?:\.\w+)*)[.:](\w+)\s*\(")
# obj[k] = function
INDEX_FUNCTION = re.compile(r"\b([A-Za-z_]\w*)\s*\[[^\]\n]+\]\s*=\s*function\b")
# obj[k] = wrap(obj[k]) / obj.Key = wrap(obj.Key)
INDEX_WRAP = re.compile(r"\b([A-Za-z_]\w*)\s*\[\s*([^\]\n]+?)\s*\]\s*=\s*[\w.:]+\s*\(\s*\1\s*\[\s*\2\s*\]")
FIELD_WRAP = re.compile(r"\b([A-Za-z_]\w*)\.(\w+)\s*=\s*[\w.:]+\s*\(\s*\1\.\2\b")
# obj.Method = someFunction (a method name, PascalCase, given a plain name)
FIELD_NAME = re.compile(r"\b([A-Za-z_]\w*)\.([A-Z]\w*)\s*=\s*([a-z_]\w*)\s*(?:$|\n|;|--)", re.M)


def _no_comments(text: str) -> str:
    text = re.sub(r"--\[(=*)\[.*?\]\1\]", "", text, flags=re.S)
    return re.sub(r"--[^\n]*", "", text)


def _code(text: str) -> str:
    """Lua with comments and string literals blanked."""
    return re.sub(r'"(?:\\.|[^"\\\n])*"|\'(?:\\.|[^\'\\\n])*\'', '""', _no_comments(text))


def replacements(rel: str, text: str) -> list[str]:
    """Every place in `text` that puts a function in a key of a table that is not one of the module's own."""
    code = _code(text)
    out = []
    for pat in (FIELD_FUNCTION, FUNCTION_DEF):
        for m in pat.finditer(code):
            if m.group(1) not in OWN:
                out.append(f"{rel}: {m.group(0).strip()}")
    for pat in (INDEX_FUNCTION, INDEX_WRAP, FIELD_WRAP, FIELD_NAME):
        for m in pat.finditer(code):
            if m.group(1) not in OWN:
                out.append(f"{rel}: {m.group(0).strip()}")
    return out


# UIParent itself, or a local that holds it (`local ui = Compat.resolve("UIParent")`)
UIPARENT_LOCAL = re.compile(
    r"\blocal\s+(\w+)(?:\s*,\s*\w+)*\s*=\s*(?:[\w.]*resolve\s*\(\s*[\"']UIParent[\"']\s*\)|(?:_G\.)?UIParent\b)")
UIPARENT_DIRECT = re.compile(
    r"(?:\bUIParent|resolve\s*\(\s*[\"']UIParent[\"']\s*\))\s*[:.]\s*HookScript\s*\(")


def uiparent_hooks(rel: str, text: str) -> list[str]:
    """Every HookScript on UIParent in `text`, directly or through a local that holds it."""
    code = _no_comments(text)
    out = [f"{rel}: {m.group(0)}" for m in UIPARENT_DIRECT.finditer(code)]
    for name in {m.group(1) for m in UIPARENT_LOCAL.finditer(code)}:
        for m in re.finditer(rf"\b{re.escape(name)}\s*[:.]\s*HookScript\s*\(", code):
            out.append(f"{rel}: {m.group(0)} ({name} is UIParent)")
    return out


@pytest.mark.parametrize("sample", [
    "button.SetGossip = function(b, data) end",
    "tip.ProcessTooltipData = function(self, data) end",
    "pool.Acquire = function(...) end",
    "button.onClickFunc = function() end",
    "function fly:SetQuestText(title) end",
    "function popup.SetTitle(self, title) end",
    "f[name] = wrap(f[name])",
    "f['FormatParagraph'] = wrap(f['FormatParagraph'])",
    "frame[m] = function() end",
    "panel.AddMessage = wrap(panel.AddMessage)",
    "sf.SetObjectData = hooked\n",
])
def test_each_replacement_is_found(sample):
    assert replacements("UI/DialogueUI.lua", sample), sample


@pytest.mark.parametrize("sample", [
    "hooksecurefunc(button, 'SetGossip', function(b, data) end)",
    "hook(f, 'AcquireFontString', function(self) guarded(acquired, self) end)",
    "function DialogueUI.install() end",
    "DialogueUI.face = function(...) return face(...) end",
    "function Holder:GetText() return self.text end",
    "raw[n] = call('getText')",
    "entry[1] = shown",
    "grid[k] = nil",
    "content[i].text = want",
    "-- button.SetGossip = function() end",
])
def test_hooks_and_data_writes_are_allowed(sample):
    assert replacements("UI/DialogueUI.lua", sample) == [], sample


def test_the_dialogue_ui_modules_replace_nothing(root):
    found = []
    for rel in DUI_FILES:
        found += replacements(rel, (root / ADDON / rel).read_text(encoding="utf-8"))
    assert found == []


@pytest.mark.parametrize("sample", [
    "UIParent:HookScript('OnShow', fn)",
    "Compat.resolve(\"UIParent\"):HookScript(\"OnShow\", fn)",
    "local ui = Compat.resolve(\"UIParent\")\nif ui then ui:HookScript(\"OnShow\", fn) end",
    "local ui, cursor = C.resolve(\"UIParent\"), C.resolve(\"GetCursorPosition\")\nui:HookScript('OnHide', fn)",
])
def test_each_uiparent_hook_is_found(sample):
    assert uiparent_hooks("UI/Example.lua", sample), sample


def test_a_frame_of_our_own_may_be_hooked():
    sample = "local ui = Compat.resolve(\"UIParent\")\nframe:SetParent(ui)\nframe:HookScript(\"OnShow\", fn)"
    assert uiparent_hooks("UI/Example.lua", sample) == []


def test_nothing_in_the_addon_hooks_uiparent(root):
    found = []
    for path in sorted((root / ADDON).rglob("*.lua")):
        rel = path.relative_to(root / ADDON).as_posix()
        if rel.startswith("Data/"):
            continue
        found += uiparent_hooks(rel, path.read_text(encoding="utf-8"))
    assert found == []
