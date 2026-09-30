"""UI/Popups.lua (ADR-037) writes only through widget methods. It never assigns into StaticPopupDialogs,
a dialog, its dialogInfo or any other Blizzard table, and never calls Resize / Layout / MarkDirty or a StaticPopup_*
function (it only hooks them); nothing an OnAccept handler reads may come from addon code."""

import re
from pathlib import Path

POPUPS = Path(__file__).resolve().parents[2] / "addon" / "WoWForeverJapanese" / "UI" / "Popups.lua"


def _code() -> list[str]:
    lines = []
    for ln in POPUPS.read_text(encoding="utf-8").splitlines():
        code = re.sub(r'"(?:[^"\\]|\\.)*"', '""', ln)  # strings first: a "--" inside one is not a comment
        lines.append(code.split("--", 1)[0])
    return lines


def test_no_write_into_a_blizzard_table():
    bad = []
    for n, ln in enumerate(_code(), 1):
        # a field assignment `x.y = …` / `x[y] = …` that is not the module's own table or a local table we built
        m = re.match(r"\s*([A-Za-z_][\w]*)\s*(?:\.[\w.]+|\[[^\]]*\])\s*=(?!=)", ln)
        if m and m.group(1) not in {"Popups", "WFJ", "args", "writerHooked", "seen"}:  # ours: module, namespace, tables
            bad.append(f"{n}: {ln.strip()}")
    assert bad == []


def test_no_layout_call_and_no_staticpopup_call():
    text = "\n".join(_code())
    assert not re.search(r"StaticPopupDialogs\s*[\[.][^=\n]*=(?!=)", text)
    assert not re.search(r":(?:Resize|Layout|MarkDirty|SetWidth|SetHeight|SetSize)\(", text)
    assert not re.search(r"\bStaticPopup(?:Special)?_\w+\s*\(", text)  # hooksecurefunc names them as strings only


def test_the_hooks_are_post_hooks():
    text = POPUPS.read_text(encoding="utf-8")
    assert 'hooksecurefunc("StaticPopup_Show", Popups.onShowCall)' in text
    assert 'hooksecurefunc("StaticPopup_OnUpdate", Popups.onUpdate)' in text
    assert not re.search(r"^\s*_G\.\w+\s*=|SetScript\(", text, re.M)
