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
