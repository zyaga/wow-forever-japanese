"""`.luacheckrc` grants neither `CreateFont` nor any `GameFont*` / `SystemFont*` object, so the addon
cannot create or modify a global font object; fonts are set per FontString."""

import re
import subprocess
from pathlib import Path

from test_luacheck_bit import _luacheck


def _globals_blocks(root: Path) -> list[str]:
    text = (root / ".luacheckrc").read_text(encoding="utf-8")
    blocks = re.findall(r"(?:read_)?globals\s*=\s*\{(.*?)\}", text, re.S)
    assert blocks
    return blocks


def test_luacheckrc_grants_no_font_objects(root):
    for block in _globals_blocks(root):
        assert '"CreateFont"' not in block
        assert not re.search(r'"GameFont\w*"', block)
        assert not re.search(r'"SystemFont\w*"', block)


def test_luacheck_fails_on_font_object_use(root, tmp_path: Path):
    lc = _luacheck()
    if lc is None:
        import pytest

        pytest.skip("luacheck not installed")
    bad = tmp_path / "Bad.lua"
    src = 'local f = CreateFont("WFJFont")\nGameFontNormal:SetFont("x", 12)\nreturn f\n'
    bad.write_text(src, encoding="utf-8")
    r = subprocess.run([lc, "--config", str(root / ".luacheckrc"), str(bad)], capture_output=True, text=True, check=False)
    assert r.returncode != 0
    assert "CreateFont" in r.stdout
    assert "GameFontNormal" in r.stdout
