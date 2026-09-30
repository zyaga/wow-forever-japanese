"""Drift guard: the committed vectors equal a regeneration (both files)."""

from wfj.dev import gen_vectors

REQUIRED_PREFIXES = {
    "ascii", "ja", "color", "tex", "link", "newline", "brk", "ph", "gender", "fwdigit", "ws", "empty", "big", "nfc",
    "player",
}


def test_case_count_and_categories(vectors):
    assert len(vectors) >= 40
    prefixes = {v["id"].rsplit("-", 1)[0] for v in vectors}
    assert prefixes >= REQUIRED_PREFIXES
    assert sum(1 for v in vectors if v["player"]) >= 6
    assert any(len(v["raw"]) >= 4096 for v in vectors)


def test_placeholder_case_variants(vectors):
    raws = "\n".join(v["raw"] for v in vectors)
    for tok in ("$N", "$n", "$C", "$c", "$R", "$r", "$G", "$B", "$b", "|n", "|T", "|H", "|c"):
        assert tok in raws, tok


def test_substring_name_not_substituted(vectors):
    v = next(v for v in vectors if v["id"] == "player-03")
    assert "Marketplace" in v["norm"] and v["norm"].endswith("{name}.")


def test_committed_files_match_regeneration(root, tmp_path):
    gen_vectors.write(tmp_path)
    for name in ("hash_vectors.jsonl", "hash_vectors.lua"):
        assert (tmp_path / name).read_text(encoding="utf-8") == (root / "vectors" / name).read_text(encoding="utf-8"), name
