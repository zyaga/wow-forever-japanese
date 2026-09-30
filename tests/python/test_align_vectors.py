"""The align vectors are a regeneration of align.py, and the Lua allowlist equals allowlist.txt."""

import json
import re

from wfj.core.align import load_allowlist
from wfj.dev import gen_align_vectors


def test_committed_align_vectors_match_regeneration(root, tmp_path):
    gen_align_vectors.write(tmp_path)
    for name in ("align_vectors.jsonl", "align_vectors.lua"):
        assert (tmp_path / name).read_text(encoding="utf-8") == (root / "vectors" / name).read_text(
            encoding="utf-8"
        ), name


def test_align_vectors_cover_every_op(root):
    rows = [
        json.loads(line)
        for line in (root / "vectors/align_vectors.jsonl").read_text(encoding="utf-8").splitlines()
        if line
    ]
    assert len(rows) >= 25
    assert {r["op"] for r in rows} == {"names", "checkNames", "numbers", "numberWords"}
    assert any(r["expected"] for r in rows if r["op"] == "checkNames")  # at least one miss
    assert any(not r["expected"] for r in rows if r["op"] == "checkNames")  # at least one pass


def test_lua_allowlist_equals_allowlist_txt(root):
    lua = (root / "addon/WoWForeverJapanese/Core/Align.lua").read_text(encoding="utf-8")
    block = lua[lua.index("Align.ALLOWLIST = {") : lua.index("}", lua.index("Align.ALLOWLIST = {"))]
    lua_terms = set(re.findall(r"(\w+) = true", block))
    assert lua_terms == load_allowlist((root / "pipeline/allowlist.txt").read_text(encoding="utf-8"))
