"""`.luacheckrc` grants no `bit` global, so any `bit.*` use in the addon fails lint."""

import os
import re
import shutil
import subprocess
from pathlib import Path


def _luacheck() -> str | None:
    return shutil.which("luacheck") or (
        str(Path.home() / ".luarocks" / "bin" / "luacheck")
        if (Path.home() / ".luarocks" / "bin" / "luacheck").exists()
        else None
    )


def test_luacheckrc_has_no_bit_global(root):
    text = (root / ".luacheckrc").read_text(encoding="utf-8")
    globals_blocks = re.findall(r"(?:read_)?globals\s*=\s*\{(.*?)\}", text, re.S)
    assert globals_blocks
    for block in globals_blocks:
        assert '"bit"' not in block


def test_luacheck_fails_on_bit_usage(root, tmp_path: Path):
    lc = _luacheck()
    if lc is None:
        import pytest

        pytest.skip("luacheck not installed")
    bad = tmp_path / "Bad.lua"
    bad.write_text("local x = bit.bxor(1, 2)\nreturn x\n", encoding="utf-8")
    env = dict(os.environ)
    r = subprocess.run([lc, "--config", str(root / ".luacheckrc"), str(bad)], capture_output=True, text=True, env=env, check=False)
    assert r.returncode != 0
    assert "bit" in r.stdout
