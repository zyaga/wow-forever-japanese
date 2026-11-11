"""The Core/ frame-access gate fails on offending code and passes on the delivered tree."""

import subprocess
from pathlib import Path


def run_gate(root: Path, addon_dir: Path) -> int:
    return subprocess.run(
        ["make", "-s", "lint-core-gate", f"ADDON={addon_dir}"], cwd=root, capture_output=True, text=True,check=False,
    ).returncode


def test_gate_fails_on_frame_access(root, tmp_path: Path):
    core = tmp_path / "Core"
    core.mkdir()
    (core / "Bad.lua").write_text('local f = CreateFrame("Frame")\n', encoding="utf-8")
    assert run_gate(root, tmp_path) != 0


def test_gate_fails_on_global_table_lookup(root, tmp_path: Path):
    core = tmp_path / "Core"
    core.mkdir()
    (core / "Bad.lua").write_text('local t = _G["GameTooltipTextLeft1"]\n', encoding="utf-8")
    assert run_gate(root, tmp_path) != 0


def test_gate_passes_on_clean_core(root, tmp_path: Path):
    core = tmp_path / "Core"
    core.mkdir()
    (core / "Ok.lua").write_text("local x = 1\nreturn x\n", encoding="utf-8")
    assert run_gate(root, tmp_path) == 0


def test_gate_passes_on_delivered_tree(root):
    assert run_gate(root, root / "addon" / "WoWForeverJapanese") == 0


def test_no_english_gate(root, tmp_path: Path):
    """Nothing under addon/ may reference data/english."""
    bad = tmp_path / "Core"
    bad.mkdir()
    (bad / "X.lua").write_text('local p = "data/english/quest"\n', encoding="utf-8")
    r = subprocess.run(["make", "-s", "lint-no-english-in-addon", f"ADDON={tmp_path}"], cwd=root, capture_output=True, check=False)
    assert r.returncode != 0
    ok = subprocess.run(["make", "-s", "lint-no-english-in-addon"], cwd=root, capture_output=True, check=False)
    assert ok.returncode == 0


def test_only_the_key_itself_is_read_as_a_key(root):
    """Which language shows is the direction crossed with the reveal key, asked through `Modifier.english()`
    or `State.showsEnglish()`. A file that reads the held key to pick a language shows the wrong one in English
    first, so only the files that are about the key itself may read it."""
    import re

    addon = root / "addon" / "WoWForeverJapanese"
    allowed = {
        "Core/Modifier.lua",  # the key
        "Core/State.lua",  # its mirror
        "UI/RevealBinding.lua",  # the binding that follows the key while it is held
        "UI/KeyCapture.lua",  # capturing a key on the settings page
        "UI/Slash.lua",  # /wfj prints the key's state
        "Main.lua",  # the binding's handler
    }
    # the function by name (called or handed on), the mirror behind any alias, and the key's own event
    pattern = re.compile(r'Modifier\.isDown\b|\.modifierHeld\b|\.on\("modifier"')
    listed = re.compile(r'ipairs\(\{[^}\n]*"modifier"')
    offenders = []
    for path in sorted([*addon.glob("Core/*.lua"), *addon.glob("UI/*.lua"), addon / "Main.lua"]):
        rel = path.relative_to(addon).as_posix()
        if rel in allowed:
            continue
        code = re.sub(r"--[^\n]*", "", path.read_text(encoding="utf-8"))
        if pattern.search(code) or listed.search(code):
            offenders.append(rel)
    assert offenders == []
