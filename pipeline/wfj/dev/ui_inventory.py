"""UI string inventory: every Blizzard global string a translated surface can put on screen, from the
client's own UI source and string table, so coverage is found mechanically, never from in-game screenshots.

    python -m wfj.dev.ui_inventory <Interface/AddOns> <GlobalStrings.csv> > <inventory>

`make ui-inventory` reads a Forever client UI extract (`wfj.dev.client_ui`, lowercased paths) and the Forever
GlobalStrings, and writes pipeline/ui_inventory.txt (Forever is the only target). Forever is game type
camelot, a member of the mainline family: its file map (FOREVER_WINDOWS) is the camelot load set resolved from
the client's own TOCs (see the camelot surface research in docs/research/). Paths resolve through a casefold
index, so the map keeps Blizzard's casing and still reads a lowercased extract.

Three kinds of source:
- windows: the global names each hooked window's XML / Lua uses (`text="NAME"`,
  `value="NAME" type="global"`, and bare upper-case identifiers in Lua), filtered to names
  GlobalStrings defines;
- dynamic families: names built at run time (`_G["SPELL_STAT"..i.."_NAME"]`), listed per surface in
  DYNAMIC and expanded against GlobalStrings;
- tooltips: the C client writes item / spell tooltip lines itself, so there is no Lua to scan;
  the inventory is every GlobalStrings key in the tooltip families (FAMILIES).
The output is `<surface> <KEY>` per line, sorted. `tests/python/test_ui_coverage.py` asserts
every inventoried key is in pipeline/ui_keys.txt or in pipeline/ui_exclusions.txt with a
reason. Re-run when the client build changes or a surface is added; commit the result.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

from wfj.dev.ui_windows import DYNAMIC, FOREVER_WINDOWS
from wfj.io import wago

SOURCE = "the Forever (camelot) UI extract"  # named in the output's header line

FAMILIES = re.compile(
    r"^(ITEM_|CHANCE_TO_|INVTYPE_"
    r"|SPELL_(CAST|RECAST|RANGE|REAGENTS|TOTEMS|ON_NEXT|REQUIRED_FORM|EQUIPPED|SCHOOL\d_CAP)"
    r"|[A-Z]+_COST(_|$)|[A-Z_]*DAMAGE_TEMPLATE|SINGLE_DAMAGE|PLUS_DAMAGE|DPS_TEMPLATE|ARMOR_TEMPLATE|SHIELD_BLOCK"
    r"|DURABILITY_TEMPLATE|MELEE_RANGE$|TOOLTIP_TALENT|RANK$|SPEED$|SELL_PRICE$|CURRENTLY_EQUIPPED$"
    r"|FACTION_STANDING_LABEL\d$|CONTAINER_SLOTS$"
    # the socket lines (the GemSocket line kind) and the loot-trade window line (TradeTimeRemaining)
    r"|EMPTY_SOCKET|SOCKET_ITEM_|BIND_TRADE_TIME_REMAINING$)"
)
_NAMES = re.compile(
    r'text="([A-Z][A-Z0-9_]+)"|value="([A-Z][A-Z0-9_]+)" type="global"'
    # a bare name, or one in a `..NAME..` concatenation, never a field (`t.NAME`)
    r"|(?<![\w:\"'])(?:(?<=\.\.)|(?<!\.))([A-Z][A-Z0-9_]{2,})(?![\w(])"
)


def file_index(addons: Path) -> dict[str, Path]:
    """Every file under `addons` by its casefolded relative path: built once per run, so a map in
    Blizzard's casing reads a lowercased extract and a case-sensitive file system alike. Two files
    whose paths differ only in case are refused, never resolved to whichever `rglob` returned last."""
    index: dict[str, Path] = {}
    for p in sorted(addons.rglob("*")):
        if not p.is_file():
            continue
        key = p.relative_to(addons).as_posix().casefold()
        if key in index:
            raise ValueError(f"ui_inventory: {index[key]} and {p} differ only in case")
        index[key] = p
    return index


def resolve(index: dict[str, Path], rel: str) -> Path:
    path = index.get(rel.replace("\\", "/").casefold())
    if path is None:
        raise FileNotFoundError(f"ui_inventory: {rel} is not in the UI source")
    return path


def window_keys(
    addons: Path, files: list[str], strings: dict[str, str], index: dict[str, Path] | None = None
) -> set[str]:
    index = file_index(addons) if index is None else index
    found: set[str] = set()
    for rel in files:
        text = resolve(index, rel).read_text(encoding="utf-8", errors="ignore")
        for m in _NAMES.finditer(text):
            key = next(g for g in m.groups() if g)
            if strings.get(key, "").strip():
                found.add(key)
    return found


def dynamic_keys(surface: str, strings: dict[str, str]) -> set[str]:
    patterns = [re.compile(p) for p in DYNAMIC.get(surface, [])]
    return {k for k, v in strings.items() if v.strip() and any(p.fullmatch(k) for p in patterns)}


# Every errors-frame call in the camelot load set; the keys named on the call line are the
# errors surface's too (uierrorsframe.lua:158–163 for the external ones; most pass no id). A variable
# argument's sources are the `errors` DYNAMIC families.
_ERRORS_CALL = re.compile(
    r"UIErrorsFrame:(?:AddMessage|AddExternalErrorMessage|AddExternalWarningMessage|CheckAddMessage)\((.*)"
)
# The lines Blizzard's Lua prints into chat (a line like the code-of-conduct notice is in no other list):
# ChatFrameUtil.AddSystemMessage / DisplaySystemMessage* (chatframeutil.lua:297–315), a frame's AddMessage
_CHAT_CALL = re.compile(
    r"(?:AddSystemMessage|DisplaySystemMessage[A-Za-z]*|SendSystemMessage"
    r"|(?:DEFAULT_CHAT_FRAME|SELECTED_CHAT_FRAME|ChatFrame1):AddMessage)\((.*)"
)
_KEY = re.compile(r"\b([A-Z][A-Z0-9_]{2,})\b")


def call_keys(
    addons: Path, strings: dict[str, str], index: dict[str, Path], call: re.Pattern[str]
) -> set[str]:
    """The GlobalStrings keys named on a `call` line, in every file of the camelot load set. One line per
    call: a key assigned to a variable on an earlier line, or a call split over lines, is not seen (the
    helper families in DYNAMIC name those)."""
    from wfj.dev import client_addons  # client_addons imports this module

    found: set[str] = set()
    for _addon, _state, files in client_addons.sweep(addons, index):
        for rel in files:
            if not rel.endswith((".lua", ".xml")):
                continue
            text = resolve(index, rel).read_text(encoding="utf-8", errors="ignore")
            for m in call.finditer(text):
                found |= {k for k in _KEY.findall(m.group(1)) if strings.get(k, "").strip()}
    return found


def errors_call_keys(addons: Path, strings: dict[str, str], index: dict[str, Path]) -> set[str]:
    """The keys named on an errors-frame call."""
    return call_keys(addons, strings, index, _ERRORS_CALL)


def chat_call_keys(addons: Path, strings: dict[str, str], index: dict[str, Path]) -> set[str]:
    """The keys named on a call that prints into chat."""
    return call_keys(addons, strings, index, _CHAT_CALL)


# A dialog definition (`StaticPopupDialogs["X"] = {`), and the fields of it that are on-screen text
# (gamedialog.lua:120–128 the text, :302–320 the buttons; the SubText and the extra button). A later
# `StaticPopupDialogs["X"].text = NAME` line counts too.
_POPUP_DEF = re.compile(r'StaticPopupDialogs\[\s*"[A-Z0-9_]+"\s*\]\s*=\s*\{')
# a key of any length: a dialog's button2 is often NO
_POPUP_FIELD = re.compile(
    r"\b(?:text|subText|button[1-4]|extraButton)\s*=\s*([A-Z][A-Z0-9_]+)\b(?!\s*[.(\[])"
)
_POPUP_SET = re.compile(
    r'StaticPopupDialogs\[\s*"[A-Z0-9_]+"\s*\]\.(?:text|subText|button[1-4]|extraButton)\s*=\s*([A-Z][A-Z0-9_]+)\b'
)


def _table_body(text: str, start: int) -> str:
    """The text of the Lua table whose `{` is at `start`, up to its matching `}` (strings and comments are not
    parsed: a brace inside one is rare in a dialog definition and only widens the scan)."""
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[start : i + 1]
    return text[start:]


def _strip_comments(text: str) -> str:
    """Lua with its `--` line comments removed (a `--` inside a string on that line is kept): a
    commented-out `--button3 = NAME` is no field the dialog shows. Block comments are rare in dialog
    definitions and kept."""
    out = []
    for line in text.split("\n"):
        quote, i = None, 0
        while i < len(line):
            ch = line[i]
            if quote:
                if ch == "\\":
                    i += 1
                elif ch == quote:
                    quote = None
            elif ch in "\"'":
                quote = ch
            elif line.startswith("--", i):
                line = line[:i]  # noqa: PLW2901  (the code before the comment is what the loop reads next)
                break
            i += 1
        out.append(line)
    return "\n".join(out)


def popup_keys(addons: Path, strings: dict[str, str], index: dict[str, Path]) -> set[str]:
    """The GlobalStrings keys a StaticPopupDialogs definition shows as its text, subText or a button
    in every Lua file of the camelot load set. Only the definition's top level is read: a nested
    table's `text` (an inserted frame's) is not the dialog's."""
    from wfj.dev import client_addons  # client_addons imports this module

    found: set[str] = set()
    for _addon, _state, files in client_addons.sweep(addons, index):
        for rel in files:
            if not rel.endswith(".lua"):
                continue
            text = _strip_comments(resolve(index, rel).read_text(encoding="utf-8", errors="ignore"))
            for m in _POPUP_DEF.finditer(text):
                body = _table_body(text, m.end() - 1)
                top, depth = [], 0
                for ch in body[1:-1]:
                    depth += ch == "{"
                    if depth == 0:
                        top.append(ch)
                    depth -= ch == "}"
                found |= {k for k in _POPUP_FIELD.findall("".join(top)) if strings.get(k, "").strip()}
            found |= {k for k in _POPUP_SET.findall(text) if strings.get(k, "").strip()}
    return found


# Every HelpTip callout's text (a callout like the dressing room's "Share this custom set…" is in no other
# list), in every load-set file of an addon the game can show (not `no-content` / `unreachable`). A
# callout is a table holding `HelpTip.` (its buttonStyle / targetPoint) and a `text = NAME` field, or a
# `<helpTip…>.text = NAME` assignment (blizzard_sharedxml/helptip.lua; e.g.
# blizzard_sharedxmlgame/dressupmodelframemixin.lua:23–30).
_HELPTIP_TEXT = re.compile(r"\btext\s*=\s*([A-Z][A-Z0-9_]{2,})\b(?!\s*[.(\[])")
_HELPTIP_FIELD = re.compile(r"\b(\w*[Hh]elp[Tt]ip\w*)\.text\s*=\s*([A-Z][A-Z0-9_]{2,})\b(?!\s*[.(\[])")
DISPOSITIONS = Path(__file__).resolve().parents[2] / "forever_addon_dispositions.txt"


def _hidden_addons() -> set[str]:
    """Addons the game never shows on Forever (dispositioned `no-content` or `unreachable`)."""
    hidden = set()
    for ln in DISPOSITIONS.read_text(encoding="utf-8").splitlines():
        parts = ln.split()
        if len(parts) >= 2 and not ln.startswith("#") and parts[1] in ("no-content", "unreachable"):
            hidden.add(parts[0])
    return hidden


def _enclosing_table(text: str, pos: int) -> str:
    """The text of the innermost `{…}` around `pos` ("" when there is none)."""
    depth = 0
    for i in range(pos, -1, -1):
        if text[i] == "}":
            depth += 1
        elif text[i] == "{":
            if depth == 0:
                return _table_body(text, i)
            depth -= 1
    return ""


def helptip_keys(addons: Path, strings: dict[str, str], index: dict[str, Path]) -> set[str]:
    """The GlobalStrings keys a HelpTip callout shows, in the shown addons' Lua files."""
    from wfj.dev import client_addons  # client_addons imports this module

    hidden = _hidden_addons()
    found: set[str] = set()
    for addon, _state, files in client_addons.sweep(addons, index):
        if addon in hidden:
            continue
        for rel in files:
            if not rel.endswith(".lua"):
                continue
            text = resolve(index, rel).read_text(encoding="utf-8", errors="ignore")
            if "HelpTip" not in text:
                continue
            for m in _HELPTIP_TEXT.finditer(text):
                if "HelpTip." in _enclosing_table(text, m.start()) and strings.get(m.group(1), "").strip():
                    found.add(m.group(1))
            found |= {k for _v, k in _HELPTIP_FIELD.findall(text) if strings.get(k, "").strip()}
    return found


# The key binding names. The client reads Bindings XML outside every TOC (camelot's
# blizzard_framexml/bindings_camelot.xml and a loaded addon's own Bindings.xml), so no window scan sees them.
# Every `<Binding name="X">` is BINDING_NAME_X; its `category="BINDING_HEADER_Y"` (or a `header="Y"`) is a
# section header. Shown by UI/SettingsKeys (the key bindings page, the quick keybind tooltip).
BINDINGS_FILES = ["Blizzard_FrameXML/Bindings_Camelot.xml"]
_BINDING = re.compile(r'<Binding\s+name="([A-Za-z0-9_]+)"([^>]*)>')
_BINDING_CATEGORY = re.compile(r'category="(BINDING_HEADER_[A-Z0-9_]+)"')
_BINDING_HEADER = re.compile(r'header="([A-Z0-9_]+)"')


def binding_keys(addons: Path, strings: dict[str, str], index: dict[str, Path]) -> set[str]:
    """The BINDING_NAME_* / BINDING_HEADER_* keys of camelot's bindings file and of every shown addon's
    Bindings.xml."""
    from wfj.dev import client_addons  # client_addons imports this module

    # an extract without camelot's bindings file has none to read (a test tree); the committed inventory is
    # compared against the real extract, so a missing file there shows as a changed inventory
    files = [p for p in (index.get(rel.casefold()) for rel in BINDINGS_FILES) if p is not None]
    hidden = _hidden_addons()
    for addon, state, _files in client_addons.sweep(addons, index):
        own = index.get(f"{addon}/bindings.xml")
        if own is not None and state in ("login", "lod") and addon not in hidden:
            files.append(own)
    found: set[str] = set()
    for path in files:
        text = path.read_text(encoding="utf-8", errors="ignore")
        for name, attrs in _BINDING.findall(text):
            found.add(f"BINDING_NAME_{name}")
            found |= set(_BINDING_CATEGORY.findall(attrs))
            found |= {f"BINDING_HEADER_{h}" for h in _BINDING_HEADER.findall(attrs)}
        found |= {f"BINDING_HEADER_{h}" for h in _BINDING_HEADER.findall(text)}
    return {k for k in found if strings.get(k, "").strip()}


def inventory(
    addons: Path,
    strings: dict[str, str],
    windows: dict[str, list[str]] = FOREVER_WINDOWS,
) -> list[tuple[str, str]]:
    index = file_index(addons)
    rows: set[tuple[str, str]] = set()
    for surface, files in windows.items():
        found = window_keys(addons, files, strings, index) | dynamic_keys(surface, strings)
        rows |= {(surface, k) for k in found}
    if "errors" in windows:
        rows |= {("errors", k) for k in errors_call_keys(addons, strings, index)}
    if "chatsystem" in windows:
        rows |= {("chatsystem", k) for k in chat_call_keys(addons, strings, index)}
    if "popups" in windows:
        rows |= {("popups", k) for k in popup_keys(addons, strings, index)}
    if "help" in windows:
        rows |= {("help", k) for k in helptip_keys(addons, strings, index)}
    if "settingspanel" in windows:  # the key bindings page (the quick keybind tooltip uses the same list)
        rows |= {("settingspanel", k) for k in binding_keys(addons, strings, index)}

    rows |= {("tooltip", k) for k, v in strings.items() if FAMILIES.match(k) and v.strip()}
    return sorted(rows)


INVENTORY = Path(__file__).resolve().parents[2] / "ui_inventory.txt"


def read_inventory(path: Path = INVENTORY) -> dict[str, set[str]]:
    """The committed inventory as key → the surfaces that show it. A key the file does not list has no
    known screen (its callers build the name at run time or live outside the extract)."""
    out: dict[str, set[str]] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        parts = line.split()
        if len(parts) == 2 and not line.startswith("#"):
            out.setdefault(parts[1], set()).add(parts[0])
    return out


def main(argv: list[str]) -> int:
    if len(argv) != 2 or argv[0].startswith("-"):
        print(__doc__, file=sys.stderr)
        return 2
    strings = wago.read_global_strings(Path(argv[1]))
    print(f"# GENERATED by `python -m wfj.dev.ui_inventory` from {SOURCE} + GlobalStrings.")
    for surface, key in inventory(Path(argv[0]), strings):
        print(f"{surface} {key}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
